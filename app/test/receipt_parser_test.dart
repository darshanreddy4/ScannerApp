import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/scanner/domain/receipt_parser.dart';

void main() {
  final now = DateTime(2026, 10, 25);

  test('reads shop, total and date from an ordinary till receipt', () {
    const text =
        'FRESH MART\n12 High Street\nTel 0123 456789\nDate: 31/01/2026 09:15\nMilk 2.50\nBread 1.99\nSubtotal 4.49\nTax 0.45\nTOTAL \$4.94\nCash 10.00\nChange 5.06';
    final info = parseReceipt(text, now: now);
    expect(info.vendor, 'FRESH MART');
    expect(info.total, r'$4.94');
    expect(info.date, DateTime(2026, 1, 31));
    expect(info.title, r'Receipt - FRESH MART - $4.94 - 2026-01-31');
  });

  test('the total is not the subtotal, the tax or the change', () {
    final info = parseReceipt('Shop\nSubtotal 10.00\nGST 1.80\nGrand Total 11.80\nChange 8.20', now: now);
    expect(info.total, '11.80');
  });

  test('an amount on the line after "Total" is found, and thousands separators are dropped', () {
    expect(parseReceipt('Shop\nTotal\n1,234.50', now: now).total, '1234.50');
  });

  test('the rupee sign in front of the total is kept', () {
    expect(parseReceipt('Store\nGrand Total ₹ 450.00', now: now).total, '₹450.00');
  });

  test('dates in different writings', () {
    expect(parseReceipt('x\n2026-03-05', now: now).date, DateTime(2026, 3, 5));
    expect(parseReceipt('x\n05 Mar 2026', now: now).date, DateTime(2026, 3, 5));
    expect(parseReceipt('x\n5-3-26', now: now).date, DateTime(2026, 3, 5), reason: 'two-digit year');
    expect(parseReceipt('x\n05.03.2026', now: now).date, DateTime(2026, 3, 5), reason: 'day first');
    expect(parseReceipt('x\n03/25/2026', now: now).date, DateTime(2026, 3, 25), reason: '25 cannot be a month');
  });

  test('impossible or far-future dates are ignored', () {
    expect(parseReceipt('x\n31/02/2026', now: now).date, isNull);
    expect(parseReceipt('x\n01/01/2099', now: now).date, isNull);
  });

  test('the shop is the first real line, not a heading, phone number or address of digits', () {
    expect(parseReceipt('TAX INVOICE\nGSTIN 22AAAAA0000A1Z5\nSuper Bazaar\nTotal 5.00', now: now).vendor, 'Super Bazaar');
    expect(parseReceipt('12345 6789\n0123\nCafe Luna\nTotal 5.00', now: now).vendor, 'Cafe Luna');
  });

  test('European amounts with a comma for cents and a dot for thousands', () {
    expect(parseReceipt('Markt\nGesamtbetrag 1.234,56 €', now: now).total, '€1234.56');
    expect(parseReceipt('Tienda\nTotal a pagar 12,50 EUR', now: now).total, '12.50 EUR');
    expect(parseReceipt('Boulangerie\nMontant 8,90 €', now: now).total, '€8.90');
  });

  test('Indian grouping and rupee wordings, with or without paise', () {
    expect(parseReceipt('Store\nGrand Total ₹ 1,23,456.00', now: now).total, '₹123456.00');
    expect(parseReceipt('Kirana\nAmount Payable Rs. 450', now: now).total, '₹450.00');
    expect(parseReceipt('Kirana\nNet Payable INR 99.50', now: now).total, '99.50 INR');
  });

  test('a whole number without a currency sign is not taken for money', () {
    expect(parseReceipt('Shop\nTotal Items 3\nTotal 3', now: now).total, isNull);
  });

  test('stronger wording wins over a plain "Total", whatever the order', () {
    expect(parseReceipt('Shop\nAmount Due 12.00\nTotal 99.00', now: now).total, '12.00');
  });

  test('the currency sign printed elsewhere is used when the total line has none', () {
    expect(parseReceipt('Cafe\nLatte \$2.50\nTotal 4.94', now: now).total, r'$4.94');
  });

  test('month names before the day, ordinals and Chinese-style dates', () {
    expect(parseReceipt('x\nDec 5, 2026', now: now).date, DateTime(2026, 12, 5));
    expect(parseReceipt('x\n5th December 2026', now: now).date, DateTime(2026, 12, 5));
    expect(parseReceipt('x\n2026年1月5日', now: now).date, DateTime(2026, 1, 5));
    expect(parseReceipt('x\n05/Mar/2026', now: now).date, DateTime(2026, 3, 5));
  });

  test('greetings and invoice headings are not the shop', () {
    expect(parseReceipt('Welcome to\nThank you\nTAX INVOICE\nGreen Grocer\nTotal 5.00', now: now).vendor, 'Green Grocer');
  });

  test('nothing readable gives no title, so the name is left alone', () {
    final info = parseReceipt('', now: now);
    expect(info.isEmpty, isTrue);
    expect(info.title, isNull);
    expect(parseReceipt('\n\n  \n', now: now).title, isNull);
  });

  test('partial results still make a useful title', () {
    expect(parseReceipt('Total 9.99', now: now).title, 'Receipt - 9.99');
  });
}
