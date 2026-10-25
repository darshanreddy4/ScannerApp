import 'dart:math' as math;

/// Where the photo sits inside the crop frame. [zoom] is 1 when the photo just covers the frame; [centerX] and
/// [centerY] are the spot of the photo (in photo pixels) that sits in the middle of the frame.
class CropView {
  const CropView({required this.zoom, required this.centerX, required this.centerY});

  final double zoom;
  final double centerX;
  final double centerY;

  static const maxZoom = 8.0;

  /// The start: the photo covers the frame and its middle is in the middle.
  factory CropView.initial(int photoW, int photoH) => CropView(zoom: 1, centerX: photoW / 2, centerY: photoH / 2);

  /// Photo pixels per frame pixel at this zoom.
  double pixelsPerUnit(int photoW, int photoH, double frameW, double frameH) => 1 / (CropGeometry.coverScale(photoW, photoH, frameW, frameH) * zoom);

  CropView panned(double dxUnits, double dyUnits, int photoW, int photoH, double frameW, double frameH) {
    final k = pixelsPerUnit(photoW, photoH, frameW, frameH);
    return _clamped(zoom, centerX - dxUnits * k, centerY - dyUnits * k, photoW, photoH, frameW, frameH);
  }

  CropView zoomedBy(double factor, int photoW, int photoH, double frameW, double frameH) =>
      _clamped((zoom * factor).clamp(1.0, maxZoom), centerX, centerY, photoW, photoH, frameW, frameH);

  CropView withZoom(double value, int photoW, int photoH, double frameW, double frameH) =>
      _clamped(value.clamp(1.0, maxZoom), centerX, centerY, photoW, photoH, frameW, frameH);

  /// The part of the photo that is inside the frame, in photo pixels.
  CropRect rect(int photoW, int photoH, double frameW, double frameH) {
    final k = pixelsPerUnit(photoW, photoH, frameW, frameH);
    final w = frameW * k, h = frameH * k;
    return CropRect(centerX - w / 2, centerY - h / 2, w, h);
  }

  static CropView _clamped(double zoom, double cx, double cy, int photoW, int photoH, double frameW, double frameH) {
    final k = 1 / (CropGeometry.coverScale(photoW, photoH, frameW, frameH) * zoom);
    final halfW = frameW * k / 2, halfH = frameH * k / 2;
    return CropView(zoom: zoom, centerX: cx.clamp(halfW, math.max(halfW, photoW - halfW)), centerY: cy.clamp(halfH, math.max(halfH, photoH - halfH)));
  }
}

class CropRect {
  const CropRect(this.left, this.top, this.width, this.height);
  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
}

abstract final class CropGeometry {
  /// Frame pixels per photo pixel when the photo exactly covers the frame.
  static double coverScale(int photoW, int photoH, double frameW, double frameH) => math.max(frameW / photoW, frameH / photoH);
}

/// Where the head should sit in the frame, as fractions of the frame (0 to 1), for the on-screen guide.
class HeadGuide {
  const HeadGuide({required this.top, required this.height, required this.width, required this.eyeLine});

  /// Top of the head, measured from the top of the photo.
  final double top;
  final double height;
  final double width;

  /// Eye level, measured from the top of the photo.
  final double eyeLine;

  double get chin => top + height;

  /// [headMm] is the wanted head height (crown to chin) in a photo [photoHeightMm] tall and [photoWidthMm] wide.
  factory HeadGuide.forPhoto({required double headMm, required double photoWidthMm, required double photoHeightMm}) {
    final height = (headMm / photoHeightMm).clamp(0.3, 0.9);
    // A head is about three quarters as wide as it is tall; the width is a share of the photo width.
    final width = (headMm * 0.74 / photoWidthMm).clamp(0.3, 0.95);
    final top = math.min(0.09, (1 - height) / 3);
    return HeadGuide(top: top, height: height, width: width, eyeLine: top + height * 0.45);
  }
}
