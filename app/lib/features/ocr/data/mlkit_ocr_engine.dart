import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../scanner/data/datasources/image_processing_service.dart';
import '../domain/ocr_engine.dart';
import '../domain/ocr_models.dart';

/// Google ML Kit text recognition running on the phone. The models ship inside the app, so it works offline.
class MlKitOcrEngine implements OcrEngine {
  MlKitOcrEngine({ImageProcessingService service = const ImageProcessingService()}) : _service = service;

  final ImageProcessingService _service;

  static TextRecognitionScript _script(OcrScript s) => switch (s) {
    OcrScript.latin => TextRecognitionScript.latin,
    OcrScript.devanagari => TextRecognitionScript.devanagiri,
  };

  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) => guard(() async {
    final size = await _service.inspect(imagePath);
    final recognizer = TextRecognizer(script: _script(script));
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      return OcrPageResult(
        width: size.width.toDouble(),
        height: size.height.toDouble(),
        blocks: [
          for (final b in text.blocks)
            OcrBlock(
              lines: [
                for (final l in b.lines)
                  OcrLine(text: l.text, left: l.boundingBox.left, top: l.boundingBox.top, right: l.boundingBox.right, bottom: l.boundingBox.bottom),
              ],
            ),
        ],
      );
    } finally {
      await recognizer.close();
    }
  }, onError: (e) => OcrFailure('The text could not be read from this page.', cause: e));
}
