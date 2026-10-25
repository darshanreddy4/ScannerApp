import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/office/slides/data/pptx_package.dart';
import 'package:scanvault/features/office/slides/data/slide_painter.dart';
import 'package:scanvault/features/office/slides/data/slide_reader.dart';

void main() {
  testWidgets('slides draw to pictures', (tester) async {
    await tester.runAsync(() async {
      final deck = await PptxDeck.open(File('test/fixtures/office/deck.pptx').readAsBytesSync());
      final reader = SlideReader(deck);
      for (var i = 0; i < deck.slides.length; i++) {
        final view = reader.read(deck.slides[i]);
        final images = <String, ui.Image>{};
        await loadSlideImages(mediaOf(view), deck.files, images);
        final img = await renderSlideImage(view, images, deck.width, deck.height, 960);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('/tmp/slide_${i + 1}.png').writeAsBytesSync(data!.buffer.asUint8List());
        expect(img.width, 960);
        expect(img.height, closeTo(540, 2));
      }
    });
  });
}
