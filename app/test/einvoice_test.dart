import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/einvoice/data/einvoice_reader.dart';
import 'package:doculoom/features/einvoice/domain/einvoice.dart';
import 'package:doculoom/features/einvoice/presentation/einvoice_page.dart';

const _cii = '''<?xml version="1.0" encoding="UTF-8"?>
<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100" xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100" xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
  <rsm:ExchangedDocumentContext><ram:GuidelineSpecifiedDocumentContextParameter><ram:ID>urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:basic</ram:ID></ram:GuidelineSpecifiedDocumentContextParameter></rsm:ExchangedDocumentContext>
  <rsm:ExchangedDocument><ram:ID>RE-2024-118</ram:ID><ram:TypeCode>380</ram:TypeCode><ram:IssueDateTime><udt:DateTimeString format="102">20240315</udt:DateTimeString></ram:IssueDateTime><ram:IncludedNote><ram:Content>Thank you for your order</ram:Content></ram:IncludedNote></rsm:ExchangedDocument>
  <rsm:SupplyChainTradeTransaction>
    <ram:IncludedSupplyChainTradeLineItem>
      <ram:SpecifiedTradeProduct><ram:Name>Design work</ram:Name></ram:SpecifiedTradeProduct>
      <ram:SpecifiedLineTradeAgreement><ram:NetPriceProductTradePrice><ram:ChargeAmount>90.00</ram:ChargeAmount></ram:NetPriceProductTradePrice></ram:SpecifiedLineTradeAgreement>
      <ram:SpecifiedLineTradeDelivery><ram:BilledQuantity unitCode="HUR">10</ram:BilledQuantity></ram:SpecifiedLineTradeDelivery>
      <ram:SpecifiedLineTradeSettlement><ram:ApplicableTradeTax><ram:RateApplicablePercent>19.00</ram:RateApplicablePercent></ram:ApplicableTradeTax><ram:SpecifiedTradeSettlementLineMonetarySummation><ram:LineTotalAmount>900.00</ram:LineTotalAmount></ram:SpecifiedTradeSettlementLineMonetarySummation></ram:SpecifiedLineTradeSettlement>
    </ram:IncludedSupplyChainTradeLineItem>
    <ram:ApplicableHeaderTradeAgreement>
      <ram:SellerTradeParty><ram:Name>Muster GmbH</ram:Name><ram:PostalTradeAddress><ram:PostcodeCode>10115</ram:PostcodeCode><ram:LineOne>Hauptstrasse 1</ram:LineOne><ram:CityName>Berlin</ram:CityName><ram:CountryID>DE</ram:CountryID></ram:PostalTradeAddress><ram:SpecifiedTaxRegistration><ram:ID schemeID="VA">DE123456789</ram:ID></ram:SpecifiedTaxRegistration></ram:SellerTradeParty>
      <ram:BuyerTradeParty><ram:Name>Kunde AG</ram:Name></ram:BuyerTradeParty>
    </ram:ApplicableHeaderTradeAgreement>
    <ram:ApplicableHeaderTradeSettlement>
      <ram:PaymentReference>RF18539007547034</ram:PaymentReference>
      <ram:InvoiceCurrencyCode>EUR</ram:InvoiceCurrencyCode>
      <ram:SpecifiedTradeSettlementPaymentMeans><ram:PayeePartyCreditorFinancialAccount><ram:IBANID>DE33100205000001194700</ram:IBANID></ram:PayeePartyCreditorFinancialAccount><ram:PayeeSpecifiedCreditorFinancialInstitution><ram:BICID>BHBLDEHHXXX</ram:BICID></ram:PayeeSpecifiedCreditorFinancialInstitution></ram:SpecifiedTradeSettlementPaymentMeans>
      <ram:SpecifiedTradePaymentTerms><ram:DueDateDateTime><udt:DateTimeString format="102">20240414</udt:DateTimeString></ram:DueDateDateTime></ram:SpecifiedTradePaymentTerms>
      <ram:SpecifiedTradeSettlementHeaderMonetarySummation><ram:LineTotalAmount>900.00</ram:LineTotalAmount><ram:TaxBasisTotalAmount>900.00</ram:TaxBasisTotalAmount><ram:TaxTotalAmount currencyID="EUR">171.00</ram:TaxTotalAmount><ram:GrandTotalAmount>1071.00</ram:GrandTotalAmount><ram:DuePayableAmount>1071.00</ram:DuePayableAmount></ram:SpecifiedTradeSettlementHeaderMonetarySummation>
    </ram:ApplicableHeaderTradeSettlement>
  </rsm:SupplyChainTradeTransaction>
</rsm:CrossIndustryInvoice>''';

const _ubl = '''<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
  <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0</cbc:CustomizationID>
  <cbc:ID>INV-77</cbc:ID><cbc:IssueDate>2024-05-02</cbc:IssueDate><cbc:DueDate>2024-06-01</cbc:DueDate><cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
  <cac:AccountingSupplierParty><cac:Party><cac:PostalAddress><cbc:StreetName>Rue 5</cbc:StreetName><cbc:CityName>Paris</cbc:CityName><cbc:PostalZone>75001</cbc:PostalZone><cac:Country><cbc:IdentificationCode>FR</cbc:IdentificationCode></cac:Country></cac:PostalAddress><cac:PartyTaxScheme><cbc:CompanyID>FR12345678901</cbc:CompanyID></cac:PartyTaxScheme><cac:PartyLegalEntity><cbc:RegistrationName>Fournisseur SARL</cbc:RegistrationName></cac:PartyLegalEntity></cac:Party></cac:AccountingSupplierParty>
  <cac:AccountingCustomerParty><cac:Party><cac:PartyName><cbc:Name>Acheteur BV</cbc:Name></cac:PartyName></cac:Party></cac:AccountingCustomerParty>
  <cac:PaymentMeans><cbc:PaymentID>INV-77</cbc:PaymentID><cac:PayeeFinancialAccount><cbc:ID>FR1420041010050500013M02606</cbc:ID><cac:FinancialInstitutionBranch><cbc:ID>PSSTFRPP</cbc:ID></cac:FinancialInstitutionBranch></cac:PayeeFinancialAccount></cac:PaymentMeans>
  <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">20.00</cbc:TaxAmount></cac:TaxTotal>
  <cac:LegalMonetaryTotal><cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount><cbc:TaxExclusiveAmount currencyID="EUR">100.00</cbc:TaxExclusiveAmount><cbc:TaxInclusiveAmount currencyID="EUR">120.00</cbc:TaxInclusiveAmount><cbc:PayableAmount currencyID="EUR">120.00</cbc:PayableAmount></cac:LegalMonetaryTotal>
  <cac:InvoiceLine><cbc:ID>1</cbc:ID><cbc:InvoicedQuantity unitCode="C62">2</cbc:InvoicedQuantity><cbc:LineExtensionAmount currencyID="EUR">100.00</cbc:LineExtensionAmount><cac:Item><cbc:Name>Widget</cbc:Name><cac:ClassifiedTaxCategory><cbc:Percent>20</cbc:Percent></cac:ClassifiedTaxCategory></cac:Item><cac:Price><cbc:PriceAmount>50.00</cbc:PriceAmount></cac:Price></cac:InvoiceLine>
</Invoice>''';

const _fattura = '''<?xml version="1.0" encoding="UTF-8"?>
<p:FatturaElettronica versione="FPR12" xmlns:p="http://ivaservizi.agenziaentrate.gov.it/docs/xsd/fatture/v1.2">
  <FatturaElettronicaHeader>
    <CedentePrestatore><DatiAnagrafici><IdFiscaleIVA><IdPaese>IT</IdPaese><IdCodice>01234567890</IdCodice></IdFiscaleIVA><Anagrafica><Denominazione>Rossi Srl</Denominazione></Anagrafica></DatiAnagrafici><Sede><Indirizzo>Via Roma 1</Indirizzo><CAP>00100</CAP><Comune>Roma</Comune><Nazione>IT</Nazione></Sede></CedentePrestatore>
    <CessionarioCommittente><DatiAnagrafici><Anagrafica><Nome>Mario</Nome><Cognome>Bianchi</Cognome></Anagrafica></DatiAnagrafici></CessionarioCommittente>
  </FatturaElettronicaHeader>
  <FatturaElettronicaBody>
    <DatiGenerali><DatiGeneraliDocumento><TipoDocumento>TD01</TipoDocumento><Divisa>EUR</Divisa><Data>2024-02-10</Data><Numero>12/A</Numero><ImportoTotaleDocumento>122.00</ImportoTotaleDocumento><Causale>Consulenza</Causale></DatiGeneraliDocumento></DatiGenerali>
    <DatiBeniServizi><DettaglioLinee><NumeroLinea>1</NumeroLinea><Descrizione>Consulenza</Descrizione><Quantita>1.00</Quantita><PrezzoUnitario>100.00</PrezzoUnitario><PrezzoTotale>100.00</PrezzoTotale><AliquotaIVA>22.00</AliquotaIVA></DettaglioLinee><DatiRiepilogo><AliquotaIVA>22.00</AliquotaIVA><ImponibileImporto>100.00</ImponibileImporto><Imposta>22.00</Imposta></DatiRiepilogo></DatiBeniServizi>
    <DatiPagamento><DettaglioPagamento><ModalitaPagamento>MP05</ModalitaPagamento><DataScadenzaPagamento>2024-03-10</DataScadenzaPagamento><ImportoPagamento>122.00</ImportoPagamento><IBAN>IT60X0542811101000000123456</IBAN></DettaglioPagamento></DatiPagamento>
  </FatturaElettronicaBody>
</p:FatturaElettronica>''';

Uint8List _pdfWith(String name, Uint8List data, {bool flate = false}) {
  final stream = flate ? Uint8List.fromList(zlib.encode(data)) : data;
  final head = StringBuffer()
    ..write('%PDF-1.7\n')
    ..write('1 0 obj\n<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [($name) 4 0 R] >> >> >>\nendobj\n')
    ..write('2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n')
    ..write('3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>\nendobj\n')
    ..write('4 0 obj\n<< /Type /Filespec /F ($name) /UF ($name) /EF << /F 5 0 R /UF 5 0 R >> >>\nendobj\n')
    ..write('5 0 obj\n<< /Type /EmbeddedFile /Subtype /text#2Fxml ${flate ? '/Filter /FlateDecode ' : ''}/Length ${stream.length} >>\nstream\n');
  final b = BytesBuilder()
    ..add(latin1.encode(head.toString()))
    ..add(stream)
    ..add(latin1.encode('\nendstream\nendobj\ntrailer\n<< /Root 1 0 R /Size 6 >>\n%%EOF\n'));
  return b.toBytes();
}

void main() {
  group('reading the XML', () {
    test('Factur-X / ZUGFeRD (CII)', () {
      final i = parseEInvoiceXml(_cii)!;
      expect(i.format, 'Factur-X / ZUGFeRD');
      expect((i.number, i.currency, i.isCreditNote), ('RE-2024-118', 'EUR', false));
      expect(i.issueDate, DateTime(2024, 3, 15));
      expect(i.dueDate, DateTime(2024, 4, 14));
      expect(i.seller.name, 'Muster GmbH');
      expect(i.seller.vatId, 'DE123456789');
      expect(i.seller.address, 'Hauptstrasse 1, 10115 Berlin, DE');
      expect(i.buyer.name, 'Kunde AG');
      expect(i.lines.single.name, 'Design work');
      expect(
        (i.lines.single.quantity, i.lines.single.unit, i.lines.single.unitPrice, i.lines.single.total, i.lines.single.vatRate),
        ('10', 'HUR', '90.00', '900.00', '19.00'),
      );
      expect((i.netTotal, i.taxTotal, i.grandTotal, i.amountDue, i.payable), ('900.00', '171.00', '1071.00', '1071.00', '1071.00'));
      expect((i.iban, i.bic, i.paymentReference), ('DE33100205000001194700', 'BHBLDEHHXXX', 'RF18539007547034'));
      expect(i.notes, ['Thank you for your order']);
    });

    test('XRechnung is recognised by its guideline', () {
      expect(parseEInvoiceXml(_cii.replaceAll('urn:factur-x.eu:1p0:basic', 'urn:xeinkauf.de:kosit:xrechnung_3.0'))!.format, 'XRechnung (CII)');
      expect(
        parseEInvoiceXml(_cii.replaceAll('urn:cen.eu:en16931:2017#conformant#urn:factur-x.eu:1p0:basic', 'urn:cen.eu:en16931:2017'))!.format,
        'EN 16931 (CII)',
      );
      expect(parseEInvoiceXml(_cii.replaceAll('<ram:TypeCode>380', '<ram:TypeCode>381'))!.isCreditNote, isTrue);
    });

    test('UBL (XRechnung / Peppol)', () {
      final i = parseEInvoiceXml(_ubl)!;
      expect(i.format, 'XRechnung (UBL)');
      expect((i.number, i.issueDate, i.dueDate, i.currency), ('INV-77', DateTime(2024, 5, 2), DateTime(2024, 6, 1), 'EUR'));
      expect((i.seller.name, i.seller.vatId, i.seller.address), ('Fournisseur SARL', 'FR12345678901', 'Rue 5, 75001 Paris, FR'));
      expect(i.buyer.name, 'Acheteur BV');
      expect(
        (i.lines.single.name, i.lines.single.quantity, i.lines.single.unit, i.lines.single.unitPrice, i.lines.single.total, i.lines.single.vatRate),
        ('Widget', '2', 'C62', '50.00', '100.00', '20'),
      );
      expect((i.netTotal, i.taxTotal, i.grandTotal, i.amountDue), ('100.00', '20.00', '120.00', '120.00'));
      expect((i.iban, i.bic, i.paymentReference), ('FR1420041010050500013M02606', 'PSSTFRPP', 'INV-77'));
      expect(parseEInvoiceXml(_ubl.replaceAll('xrechnung_3.0', 'peppol:bis:billing:3.0'))!.format, 'Peppol BIS (UBL)');
    });

    test('FatturaPA', () {
      final i = parseEInvoiceXml(_fattura)!;
      expect(i.format, 'FatturaPA');
      expect((i.number, i.issueDate, i.currency), ('12/A', DateTime(2024, 2, 10), 'EUR'));
      expect((i.seller.name, i.seller.vatId, i.seller.address), ('Rossi Srl', 'IT01234567890', 'Via Roma 1, 00100 Roma, IT'));
      expect(i.buyer.name, 'Mario Bianchi');
      expect((i.lines.single.name, i.lines.single.total, i.lines.single.vatRate), ('Consulenza', '100.00', '22.00'));
      expect((i.netTotal, i.taxTotal, i.grandTotal, i.amountDue, i.dueDate), ('100.00', '22.00', '122.00', '122.00', DateTime(2024, 3, 10)));
      expect(i.iban, 'IT60X0542811101000000123456');
      expect(i.notes, ['Consulenza']);
      expect(parseEInvoiceXml(_fattura.replaceAll('TD01', 'TD04'))!.isCreditNote, isTrue);
    });

    test('anything else is not an invoice', () {
      expect(parseEInvoiceXml('<html><body>hi</body></html>'), isNull);
      expect(parseEInvoiceXml('not xml at all'), isNull);
      expect(parseEInvoiceXml(''), isNull);
    });

    test('a byte order mark does not matter', () {
      expect(parseEInvoiceXml('\uFEFF$_cii')!.number, 'RE-2024-118');
    });
  });

  group('reading files', () {
    test('an XML file', () {
      final r = readEInvoice(Uint8List.fromList(utf8.encode(_ubl)));
      expect(r.invoice!.number, 'INV-77');
      expect(readEInvoice(Uint8List.fromList(utf8.encode('<a/>'))).problem, contains('not an electronic invoice'));
    });

    test('a PDF with the XML attached, plain or compressed', () {
      for (final flate in [false, true]) {
        final r = readEInvoice(_pdfWith('factur-x.xml', Uint8List.fromList(utf8.encode(_cii)), flate: flate));
        expect(r.problem, isNull, reason: 'flate $flate');
        expect(r.invoice!.number, 'RE-2024-118');
        expect(r.xmlName, 'factur-x.xml');
      }
    });

    test('a PDF with a different kind of attachment, or none', () {
      expect(readEInvoice(_pdfWith('notes.txt', Uint8List.fromList(utf8.encode('hello')))).problem, contains('no invoice data'));
      expect(readEInvoice(_pdfWith('other.xml', Uint8List.fromList(utf8.encode('<a/>')))).problem, contains('not an invoice format'));
      expect(
        readEInvoice(Uint8List.fromList(latin1.encode('%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n'))).problem,
        contains('no invoice data'),
      );
    });

    test('a damaged PDF is explained', () {
      expect(readEInvoice(Uint8List.fromList(latin1.encode('%PDF-1.4 garbage'))).problem, isNotNull);
    });
  });

  group('page', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sv_einv'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> open(WidgetTester tester, String? path, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await sl.reset();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: EInvoicePage(pick: () async => path),
        ),
      );
      await tester.tap(find.text('Choose an invoice'));
      // The page picks, reads and parses in turn, each step waiting on the real event loop.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      }
      await tester.pump();
    }

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('shows a Factur-X invoice at ${width.toInt()} px', (tester) async {
        final file = File(p.join(dir.path, 'invoice.pdf'))..writeAsBytesSync(_pdfWith('factur-x.xml', Uint8List.fromList(utf8.encode(_cii))));
        await open(tester, file.path, width: width);
        expect(find.text('Factur-X / ZUGFeRD'), findsOneWidget);
        expect(find.text('RE-2024-118'), findsOneWidget);
        expect(find.text('Muster GmbH'), findsOneWidget);
        expect(find.text('Design work'), findsOneWidget);
        expect(find.text('1071.00 EUR'), findsOneWidget);
        expect(find.text('DE33 1002 0500 0001 1947 00'), findsOneWidget);
        expect(find.text('Make a payment QR'), findsOneWidget);
        expect(find.text('Open the invoice PDF'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a file that is not an invoice says so', (tester) async {
      final bad = File(p.join(dir.path, 'x.xml'))..writeAsStringSync('<a/>');
      await open(tester, bad.path);
      expect(find.textContaining('not an electronic invoice'), findsOneWidget);
    });

    testWidgets('nothing happens when the picker is cancelled', (tester) async {
      await open(tester, null);
      expect(find.byType(Card), findsNothing);
    });
  });
}
