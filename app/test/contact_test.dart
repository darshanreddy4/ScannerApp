import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/contacts/domain/contact_parser.dart';
import 'package:doculoom/features/contacts/domain/vcard.dart';

void main() {
  group('reading a business card', () {
    test('a typical card', () {
      final c = parseContactText('''
ACME Solutions Pvt Ltd
John Smith
Senior Sales Manager
Mobile: +1 (415) 555-0132
Tel: 415-555-0199
Fax: 415-555-0100
john.smith@acme-solutions.com
www.acme-solutions.com
221B Baker Street, Suite 4
San Francisco, CA 94107
''');
      expect(c.name, 'John Smith');
      expect(c.title, 'Senior Sales Manager');
      expect(c.organization, 'ACME Solutions Pvt Ltd');
      expect(c.phones, ['+1 (415) 555-0132', '415-555-0199'], reason: 'the fax number is not a contact number');
      expect(c.emails, ['john.smith@acme-solutions.com']);
      expect(c.websites, ['https://www.acme-solutions.com']);
      expect(c.address, '221B Baker Street, Suite 4, San Francisco, CA 94107');
    });

    test('a name in capitals is tidied, with initials kept', () {
      expect(parseContactText('PRIYA K. NAIR\nDirector\n+91 98450 12345').name, 'Priya K. Nair');
      expect(parseContactText('M. Ahmed\n+44 20 7946 0958').name, 'M. Ahmed', reason: 'an initial is not a label');
    });

    test('accents and non-English names are kept', () {
      final c = parseContactText('José Álvarez-Núñez\nIngeniero\njose@empresa.es');
      expect(c.name, 'José Álvarez-Núñez');
      expect(c.emails, ['jose@empresa.es']);
    });

    test('labels in front of numbers and addresses are removed', () {
      final c = parseContactText('Anna Berg\nE: ANNA@Berg.DE\nM: +49 170 1234567\nW: berg.de');
      expect(c.emails, ['anna@berg.de']);
      expect(c.phones, ['+49 170 1234567']);
      expect(c.websites, ['https://berg.de']);
    });

    test('the same number written twice is kept once', () {
      final c = parseContactText('Lee Wong\n+65 6123 4567\nTel +65 6123 4567\n6123-4567-0');
      expect(c.phones.where((p) => p.contains('6123 4567')).length, 1);
    });

    test('a website is not taken for an email, and an email not for a website', () {
      final c = parseContactText('Sam Roe\nsam@roe.io\nroe.io');
      expect(c.emails, ['sam@roe.io']);
      expect(c.websites, ['https://roe.io']);
    });

    test('short numbers, years and postcodes are not phone numbers', () {
      final c = parseContactText('Eva Lund\nEst. 1998\n12345\nStockholm 11122\n+46 8 123 456 78');
      expect(c.phones, ['+46 8 123 456 78']);
    });

    test('only an email or only a phone still gives something usable', () {
      expect(parseContactText('hello@shop.com').isUsable, isTrue);
      expect(parseContactText('+1 212 555 0100').isUsable, isTrue);
      expect(parseContactText('').isEmpty, isTrue);
      expect(parseContactText('   \n \n').isUsable, isFalse);
      expect(parseContactText('Welcome to the show').isUsable, isFalse);
    });

    test('noise and symbols are ignored', () {
      final c = parseContactText('•\n|\nRita Shah | Founder\n--\n+91 99999 88888');
      expect(c.phones, ['+91 99999 88888']);
      expect(c.title, isNotEmpty);
    });

    test('lines with the company words become the organisation, not the name', () {
      final c = parseContactText('Blue Ocean Consulting\nTara Dsouza\n+971 4 123 4567');
      expect(c.name, 'Tara Dsouza');
      expect(c.organization, 'Blue Ocean Consulting');
    });

    test('Windows line endings and odd spaces are handled', () {
      final c = parseContactText('Ken\u00A0Ito\r\nManager\r\n+81 3 1234 5678\r\n');
      expect(c.name, 'Ken Ito');
      expect(c.phones, ['+81 3 1234 5678']);
    });
  });

  group('vCard', () {
    test('has the structure Contacts apps expect, with CRLF line ends', () {
      final v = buildVCard(
        const ContactDraft(
          name: 'John Smith',
          organization: 'ACME',
          title: 'Manager',
          phones: ['+1 415 555 0132'],
          emails: ['john@acme.com'],
          websites: ['https://acme.com'],
          address: '1 Main St, Springfield',
        ),
      );
      expect(v.startsWith('BEGIN:VCARD\r\nVERSION:3.0\r\n'), isTrue);
      expect(v.endsWith('END:VCARD\r\n'), isTrue);
      expect(v, contains('N:Smith;John;;;\r\n'));
      expect(v, contains('FN:John Smith\r\n'));
      expect(v, contains('ORG:ACME\r\n'));
      expect(v, contains('TITLE:Manager\r\n'));
      expect(v, contains('TEL;TYPE=VOICE:+1 415 555 0132\r\n'));
      expect(v, contains('EMAIL;TYPE=INTERNET:john@acme.com\r\n'));
      expect(v, contains('URL:https://acme.com\r\n'));
      expect(v, contains(r'ADR;TYPE=WORK:;;1 Main St\, Springfield;;;;'));
      expect('\n'.allMatches(v).length, '\r\n'.allMatches(v).length, reason: 'no bare line feeds');
    });

    test('special characters are escaped', () {
      final v = buildVCard(const ContactDraft(name: 'A', organization: r'Smith; Jones, & Co\Ltd', address: 'Line1\nLine2'));
      expect(v, contains(r'ORG:Smith\; Jones\, & Co\\Ltd'));
      expect(v, contains(r'Line1\nLine2'));
    });

    test('a single name goes in the first-name part, several names keep the last as family name', () {
      expect(buildVCard(const ContactDraft(name: 'Madonna')), contains('N:;Madonna;;;'));
      expect(buildVCard(const ContactDraft(name: 'Ana Maria de Souza')), contains('N:Souza;Ana Maria de;;;'));
    });

    test('empty parts are left out, and a nameless card is named after its email or number', () {
      final v = buildVCard(const ContactDraft(phones: ['+1 212 555 0100']));
      expect(v, isNot(contains('ORG:')));
      expect(v, isNot(contains('EMAIL')));
      expect(v, contains('FN:+1 212 555 0100'));
      expect(buildVCard(const ContactDraft(emails: ['a@b.co'], phones: ['+1'])), contains('FN:a@b.co'));
      expect(buildVCard(const ContactDraft()), contains('FN:Contact'));
    });

    test('long lines are folded at 75 bytes without cutting a character', () {
      final v = buildVCard(ContactDraft(name: 'X', address: '${'é' * 120} Road'));
      for (final line in v.split('\r\n')) {
        expect(line.codeUnits.length, lessThan(200));
        expect(const Utf8Encoder().convert(line).length, lessThanOrEqualTo(75), reason: line);
      }
      final unfolded = v.replaceAll('\r\n ', '');
      expect(unfolded, contains('é' * 120));
    });
  });
}
