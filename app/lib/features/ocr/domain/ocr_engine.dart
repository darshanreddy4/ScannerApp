import '../../../core/error/result.dart';
import 'ocr_models.dart';

/// Reads text from an image file on the device. Nothing is sent over the network.
abstract interface class OcrEngine {
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script);
}
