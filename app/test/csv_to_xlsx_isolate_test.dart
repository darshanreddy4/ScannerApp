import 'dart:io';
import 'dart:isolate';

import 'package:doculoom/features/office/convert/office_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV to Excel works when the progress callback holds something unsendable', () async {
    final dir = Directory.systemTemp.createTempSync('csvx');
    addTearDown(() => dir.deleteSync(recursive: true));
    final csv = File('${dir.path}/budget.csv')..writeAsStringSync('Item,Amount\r\nRent,1200\r\n');
    final port = ReceivePort();
    addTearDown(port.close);
    final result = await OfficeConverter(workDir: () async => dir).convert(OfficeConversion.csvToXlsx, [csv.path], onProgress: (_) => port.sendPort);
    expect(File(result.single.path).existsSync(), isTrue);
  });
}
