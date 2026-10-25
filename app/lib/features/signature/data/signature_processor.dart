import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/signature.dart';
import 'signature_ink.dart';

class SignatureProcessor implements SignatureMaker {
  const SignatureProcessor();

  /// Pad pixels are drawn this many times larger so the PNG stays sharp when placed on a page.
  static const scale = 3.0;

  @override
  Future<Result<SignaturePng>> fromStrokes({
    required List<Stroke> strokes,
    required double padWidth,
    required double padHeight,
    required double penWidth,
    required InkColor ink,
    required String outputPath,
  }) => guard(
    () async {
      final drawn = [
        for (final s in strokes)
          if (s.points.isNotEmpty) s,
      ];
      if (drawn.isEmpty || padWidth <= 0 || padHeight <= 0) throw const ExportFailure('Draw your signature first.');
      final width = (padWidth * scale).ceil(), height = (padHeight * scale).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final paint = ui.Paint()
        ..color = ui.Color(ink.argb)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = penWidth * scale
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..isAntiAlias = true;
      final dot = ui.Paint()
        ..color = ui.Color(ink.argb)
        ..isAntiAlias = true;
      for (final stroke in drawn) {
        final pts = stroke.points;
        if (pts.length == 1) {
          canvas.drawCircle(ui.Offset(pts.first.x * scale, pts.first.y * scale), penWidth * scale / 2, dot);
          continue;
        }
        canvas.drawPath(smoothPath(pts, scale), paint);
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      image.dispose();
      if (data == null) throw const ExportFailure('The signature could not be created.');
      final rgba = data.buffer.asUint8List();
      final margin = math.max(4, (penWidth * scale).round());
      final cut = await Isolate.run(() => _crop(rgba, width, height, margin));
      await File(outputPath).writeAsBytes(cut.png, flush: true);
      return SignaturePng(path: outputPath, width: cut.width, height: cut.height);
    },
    onError: (e) => e is Failure
        ? e
        : (e is FormatException ? const ExportFailure('Draw your signature first.') : ExportFailure('The signature could not be created.', cause: e)),
  );

  @override
  Future<Result<SignaturePng>> fromPhoto({required String sourcePath, required String outputPath, required double sensitivity, InkColor? ink}) => guard(
    () async {
      final size = await Isolate.run(() => extractInkSync(sourcePath, outputPath, sensitivity, ink?.argb));
      return SignaturePng(path: outputPath, width: size.width, height: size.height);
    },
    onError: (e) => e is FormatException && e.message == 'No ink found'
        ? const ExportFailure('No signature found in this photo. Use dark ink on plain white paper with even light.')
        : ExportFailure('This photo could not be read. It may be damaged or in an unsupported format.', cause: e),
  );
}

({Uint8List png, int width, int height}) _crop(Uint8List rgba, int width, int height, int margin) => cropToInk(rgba, width, height, margin: margin);

/// Joins the points with smooth curves so handwriting does not look jagged.
ui.Path smoothPath(List<({double x, double y})> pts, double scale) {
  final path = ui.Path()..moveTo(pts.first.x * scale, pts.first.y * scale);
  if (pts.length == 2) {
    path.lineTo(pts.last.x * scale, pts.last.y * scale);
    return path;
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final mx = (pts[i].x + pts[i + 1].x) / 2 * scale, my = (pts[i].y + pts[i + 1].y) / 2 * scale;
    path.quadraticBezierTo(pts[i].x * scale, pts[i].y * scale, mx, my);
  }
  path.lineTo(pts.last.x * scale, pts.last.y * scale);
  return path;
}
