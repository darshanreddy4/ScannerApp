import '../../../core/error/result.dart';
import '../../scanner/domain/entities/filter_settings.dart';
import '../../scanner/domain/entities/prepared_image.dart';
import 'markup.dart';

abstract interface class MarkupRenderer {
  /// Applies [settings] to the image at full size, draws [items] on top and writes the result to a new working file.
  Future<Result<ImageFileInfo>> render({required String imagePath, required FilterSettings settings, required List<MarkupItem> items});
}
