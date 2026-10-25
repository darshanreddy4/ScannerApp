import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../scanner/domain/entities/filter_settings.dart';
import '../../scanner/domain/entities/prepared_image.dart';
import '../../scanner/domain/repositories/scanner_repository.dart';
import '../domain/markup.dart';
import '../domain/markup_renderer.dart';
import '../markup_paint.dart';

class MarkupRendererImpl implements MarkupRenderer {
  MarkupRendererImpl({required ScannerRepository scanner, required Future<Directory> Function() workDir}) : _scanner = scanner, _workDir = workDir;

  final ScannerRepository _scanner;
  final Future<Directory> Function() _workDir;
  int _counter = 0;

  @override
  Future<Result<ImageFileInfo>> render({required String imagePath, required FilterSettings settings, required List<MarkupItem> items}) => guard(() async {
    final untouched = settings.filter == ScanFilter.original && settings.brightness == 0 && settings.contrast == 0;
    var source = imagePath;
    if (!untouched) {
      final filtered = await _scanner.applyFilter(imagePath: imagePath, settings: settings);
      final failure = filtered.failureOrNull;
      if (failure != null) throw failure;
      source = filtered.valueOrNull!.path;
    }

    final codec = await ui.instantiateImageCodec(await File(source).readAsBytes());
    final frame = await codec.getNextFrame();
    codec.dispose();
    final base = frame.image;
    final size = ui.Size(base.width.toDouble(), base.height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(base, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.high);
    paintMarkup(canvas, size, items);
    final picture = recorder.endRecording();
    final done = await picture.toImage(base.width, base.height);
    picture.dispose();
    base.dispose();
    final data = await done.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = done.width, h = done.height;
    done.dispose();
    if (data == null) throw const ImageProcessingFailure('The markup could not be added to this page.');

    final out = p.join((await _workDir()).path, 'markup_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.jpg');
    final bytes = TransferableTypedData.fromList([data.buffer.asUint8List()]);
    await Isolate.run(() => _encode(bytes, w, h, out));
    return ImageFileInfo(path: out, width: w, height: h);
  }, onError: (e) => ImageProcessingFailure('The markup could not be added to this page.', cause: e));
}

void _encode(TransferableTypedData bytes, int w, int h, String out) {
  final rgba = bytes.materialize().asUint8List();
  final image = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4).convert(numChannels: 3);
  File(out).writeAsBytesSync(Uint8List.fromList(img.encodeJpg(image, quality: 92)), flush: true);
}
