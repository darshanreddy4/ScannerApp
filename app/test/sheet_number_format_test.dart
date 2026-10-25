import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/office/sheets/domain/number_format.dart';

String f(double v, String code) => NumberFormatter.format(v, code);

void main() {
  group('General', () {
    test('shows numbers the way a spreadsheet does', () {
      expect(f(1, 'General'), '1');
      expect(f(-42, 'General'), '-42');
      expect(f(1.5, 'General'), '1.5');
      expect(f(0.1 + 0.2, 'General'), '0.3');
      expect(f(1234567.891, 'General'), '1234567.891');
      expect(f(1 / 3, 'General'), '0.3333333333');
      expect(f(123456789012, 'General'), '1.23457E+11');
      expect(f(0.00000000012, 'General'), '1.2E-10');
    });
  });

  group('numbers', () {
    test('decimals, thousands and percent', () {
      expect(f(3.14159, '0.00'), '3.14');
      expect(f(2.5, '0'), '3');
      expect(f(2.4, '0'), '2');
      expect(f(1234567, '#,##0'), '1,234,567');
      expect(f(1234.5, '#,##0.00'), '1,234.50');
      expect(f(999.999, '#,##0.00'), '1,000.00');
      expect(f(0.256, '0%'), '26%');
      expect(f(0.1234, '0.00%'), '12.34%');
      expect(f(0, '0.00'), '0.00');
      expect(f(0.5, '0.00'), '0.50');
      expect(f(0.5, '#.##'), '.5');
    });

    test('optional and required digits', () {
      expect(f(2, '0.0#'), '2.0');
      expect(f(2.25, '0.0#'), '2.25');
      expect(f(2.256, '0.0#'), '2.26');
      expect(f(7, '000'), '007');
      expect(f(1234, '000000'), '001234');
      expect(f(5, '#'), '5');
      expect(f(0, '#'), '');
    });

    test('currency and literal text', () {
      expect(f(1234.5, '"\$"#,##0.00'), '\$1,234.50');
      expect(f(1234.5, r'[$₹-4009]#,##0.00'), '₹1,234.50');
      expect(f(1234.5, r'[$€-407] #,##0.00'), '€ 1,234.50');
      expect(f(12, '0 "kg"'), '12 kg');
      expect(f(5, r'0\%'), '5%');
    });

    test('negatives and zero use their own parts', () {
      expect(f(-5, '#,##0.00;(#,##0.00)'), '(5.00)');
      expect(f(-5, '#,##0;[Red]-#,##0'), '-5');
      expect(f(5, '#,##0.00;(#,##0.00)'), '5.00');
      expect(f(0, '0;-0;"zero"'), 'zero');
      expect(f(-3.5, '0.0'), '-3.5');
    });

    test('thousands scaling and scientific', () {
      expect(f(1500000, '#,##0,'), '1,500');
      expect(f(1500000, '0.0,,"M"'), '1.5M');
      expect(f(12345, '0.00E+00'), '1.23E+04');
      expect(f(0.000123, '0.00E+00'), '1.23E-04');
    });

    test('text format', () {
      expect(f(42, '@'), '42');
    });
  });

  group('dates', () {
    test('serial numbers become dates, with Excel\'s 1900 quirk', () {
      expect(NumberFormatter.serialToDate(45000), DateTime.utc(2023, 3, 15));
      expect(NumberFormatter.serialToDate(1), DateTime.utc(1900, 1, 1));
      expect(NumberFormatter.serialToDate(59), DateTime.utc(1900, 2, 28));
      expect(NumberFormatter.serialToDate(61), DateTime.utc(1900, 3, 1));
      expect(NumberFormatter.serialToDate(45000.75), DateTime.utc(2023, 3, 15, 18));
      expect(NumberFormatter.serialToDate(0, date1904: true), DateTime.utc(1904));
    });

    test('dates and serial numbers convert back', () {
      for (final d in [DateTime.utc(2023, 3, 15), DateTime.utc(2000, 1, 1), DateTime.utc(1900, 3, 1), DateTime.utc(2026, 10, 24, 12)]) {
        expect(NumberFormatter.serialToDate(NumberFormatter.dateToSerial(d)), d);
      }
    });

    test('common date formats', () {
      expect(f(45000, 'yyyy-mm-dd'), '2023-03-15');
      expect(f(45000, 'dd/mm/yyyy'), '15/03/2023');
      expect(f(45000, 'mm-dd-yy'), '03-15-23');
      expect(f(45000, 'd-mmm-yy'), '15-Mar-23');
      expect(f(45000, 'mmmm d, yyyy'), 'March 15, 2023');
      expect(f(45000, 'dddd'), 'Wednesday');
      expect(f(45000, 'ddd, dd mmm'), 'Wed, 15 Mar');
      expect(f(45000, 'mmm-yy'), 'Mar-23');
    });

    test('times and minutes versus months', () {
      expect(f(0.75, 'h:mm AM/PM'), '6:00 PM');
      expect(f(0.25, 'h:mm AM/PM'), '6:00 AM');
      expect(f(0.5, 'hh:mm:ss'), '12:00:00');
      expect(f(45000.5, 'm/d/yy h:mm'), '3/15/23 12:00');
      expect(f(0.0625, 'h:mm'), '1:30');
      expect(f(0.0625, 'mm:ss'), '30:00');
      expect(f(45000.510417, 'yyyy-mm-dd hh:mm'), '2023-03-15 12:15');
    });

    test('elapsed time', () {
      expect(f(1.5, '[h]:mm:ss'), '36:00:00');
      expect(f(0.5, '[m]'), '720');
    });

    test('quoted text inside a date format', () {
      expect(f(45000, '"Week of" d mmm'), 'Week of 15 Mar');
    });

    test('which codes are dates', () {
      for (final c in ['yyyy-mm-dd', 'd-mmm-yy', 'h:mm AM/PM', 'mm-dd-yy', '[h]:mm:ss', 'dd/mm/yyyy hh:mm']) {
        expect(NumberFormatter.isDate(c), isTrue, reason: c);
      }
      for (final c in ['General', '0.00', '#,##0', '0%', '"\$"#,##0.00', '@', '0.00E+00', '#,##0 "days"']) {
        expect(NumberFormatter.isDate(c), isFalse, reason: c);
      }
    });
  });
}
