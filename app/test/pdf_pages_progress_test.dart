import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/features/pdf_tools/data/pdf_pages_processor.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_pages.dart';

class _Holder {
  Timer? timer = Timer(const Duration(hours: 1), () {});
  void progress(int d, int t) {}
}

void main() {
  testWidgets('builds pages even when the progress callback reaches an object that cannot be sent to another isolate', (tester) async {
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('scratch');
      addTearDown(() => dir.deleteSync(recursive: true));
      final page = p.join(dir.path, 'a.jpg');
      File(page).writeAsBytesSync(img.encodeJpg(img.Image(width: 80, height: 100)..clear(img.ColorRgb8(10, 20, 30))));
      final holder = _Holder();
      addTearDown(() => holder.timer?.cancel());
      final service = PdfPagesProcessor(pdfToImages: (_) async => [page]);
      final result = await service.build(
        source: OpenedPdf(name: 'x', pages: [page]),
        parts: [
          PartRequest(pages: const [0], fileName: 'out.pdf'),
        ],
        rotations: const {},
        marks: const PageMarks(),
        outputDir: p.join(dir.path, 'out'),
        onProgress: holder.progress,
      );
      expect(result.failureOrNull, isNull, reason: '${result.failureOrNull?.cause}');
    });
  });
}
