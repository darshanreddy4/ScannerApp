import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

typedef CompressedPage = ({String path, int width, int height});

/// Re-encodes page images smaller. Runs in an isolate; takes and returns only primitives.
List<CompressedPage> compressImages({required List<String> inputs, required String outDir, required int maxSide, required int quality}) {
  Directory(outDir).createSync(recursive: true);
  final out = <CompressedPage>[];
  for (var i = 0; i < inputs.length; i++) {
    var image = img.decodeImage(File(inputs[i]).readAsBytesSync());
    if (image == null) throw const FormatException('A page image could not be read.');
    if (math.max(image.width, image.height) > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    }
    final file = File(p.join(outDir, 'c_$i.jpg'))..writeAsBytesSync(img.encodeJpg(image, quality: quality), flush: true);
    out.add((path: file.path, width: image.width, height: image.height));
  }
  return out;
}
