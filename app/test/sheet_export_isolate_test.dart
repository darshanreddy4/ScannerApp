import 'dart:io';
import 'dart:isolate';

import 'package:doculoom/features/office/sheets/data/sheet_templates.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('xlsx export works while something unsendable is listening to the cubit', () async {
    final c = SheetCubit(workDir: () async => Directory.systemTemp)..startTemplate(sheetTemplates.first);
    final port = ReceivePort();
    final sub = c.stream.listen((_) => port.sendPort);
    final path = await c.export(SheetExportFormat.xlsx);
    await sub.cancel();
    port.close();
    expect(path, isNotNull, reason: '${c.state.failure?.message}');
  });
}
