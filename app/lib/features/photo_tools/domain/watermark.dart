import 'dart:math' as math;

enum WatermarkLayout {
  single('One mark'),
  tiled('Repeated');

  const WatermarkLayout(this.label);
  final String label;
}

enum WatermarkPosition {
  topLeft(0, 0),
  topCenter(0.5, 0),
  topRight(1, 0),
  middleLeft(0, 0.5),
  center(0.5, 0.5),
  middleRight(1, 0.5),
  bottomLeft(0, 1),
  bottomCenter(0.5, 1),
  bottomRight(1, 1);

  const WatermarkPosition(this.fx, this.fy);

  /// Horizontal and vertical place as a share of the free space (0 = start, 1 = end).
  final double fx;
  final double fy;
}

enum WatermarkColor {
  grey('Grey', 0xFF7A7A7A),
  black('Black', 0xFF111111),
  white('White', 0xFFFFFFFF),
  red('Red', 0xFFC62828),
  blue('Blue', 0xFF1D4ED8);

  const WatermarkColor(this.label, this.argb);
  final String label;
  final int argb;
}

/// Ready-made wording for common cases. {name} and {date} are filled in when the mark is made.
abstract final class WatermarkPresets {
  static const confidential = 'CONFIDENTIAL';
  static const copy = 'COPY';
  static const kyc = 'For KYC verification only';
  static const forPurpose = 'Only for {purpose}';

  static const all = <(String, String)>[
    ('Confidential', confidential),
    ('Copy', copy),
    ('Not valid for any other use', 'Not valid for any other use'),
    ('For KYC only', kyc),
    ('Name and date', '{name} - {date}'),
  ];

  /// Fills in the placeholders; unknown ones are left as they are.
  static String fill(String template, {String name = '', required DateTime date}) {
    String two(int n) => n.toString().padLeft(2, '0');
    return template
        .replaceAll('{name}', name)
        .replaceAll('{date}', '${two(date.day)}/${two(date.month)}/${date.year}')
        .replaceAll(RegExp(r'\s+-\s+$'), '')
        .replaceAll(RegExp(r'^\s+-\s+'), '')
        .trim();
  }
}

class WatermarkStyle {
  const WatermarkStyle({
    this.text = WatermarkPresets.confidential,
    this.logoPath,
    this.layout = WatermarkLayout.tiled,
    this.position = WatermarkPosition.bottomRight,
    this.opacity = 0.3,
    this.size = 0.06,
    this.rotation = -30,
    this.color = WatermarkColor.grey,
    this.bold = true,
  });

  /// May hold several lines.
  final String text;

  /// A logo shown above the text.
  final String? logoPath;
  final WatermarkLayout layout;
  final WatermarkPosition position;

  /// 0.05 to 1.
  final double opacity;

  /// Letter height as a share of the picture's shorter side.
  final double size;

  /// Degrees, counter-clockwise negative like a diagonal stamp.
  final double rotation;
  final WatermarkColor color;
  final bool bold;

  static const minOpacity = 0.05;
  static const minSize = 0.02;
  static const maxSize = 0.2;

  bool get isEmpty => text.trim().isEmpty && logoPath == null;

  WatermarkStyle copyWith({
    String? text,
    Object? logoPath = _keep,
    WatermarkLayout? layout,
    WatermarkPosition? position,
    double? opacity,
    double? size,
    double? rotation,
    WatermarkColor? color,
    bool? bold,
  }) => WatermarkStyle(
    text: text ?? this.text,
    logoPath: identical(logoPath, _keep) ? this.logoPath : logoPath as String?,
    layout: layout ?? this.layout,
    position: position ?? this.position,
    opacity: (opacity ?? this.opacity).clamp(minOpacity, 1.0),
    size: (size ?? this.size).clamp(minSize, maxSize),
    rotation: (rotation ?? this.rotation).clamp(-90.0, 90.0),
    color: color ?? this.color,
    bold: bold ?? this.bold,
  );

  static const _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is WatermarkStyle &&
      other.text == text &&
      other.logoPath == logoPath &&
      other.layout == layout &&
      other.position == position &&
      other.opacity == opacity &&
      other.size == size &&
      other.rotation == rotation &&
      other.color == color &&
      other.bold == bold;

  @override
  int get hashCode => Object.hash(text, logoPath, layout, position, opacity, size, rotation, color, bold);
}

/// A business's name, a second line (phone, GST number, website) and its logo, kept for reuse.
class BusinessProfile {
  const BusinessProfile({this.name = '', this.details = '', this.logoPath});
  final String name;
  final String details;
  final String? logoPath;

  bool get isEmpty => name.trim().isEmpty && details.trim().isEmpty && logoPath == null;

  /// The lines used as the watermark text.
  String get text => [name.trim(), details.trim()].where((l) => l.isNotEmpty).join('\n');

  Map<String, Object?> toJson() => {'name': name, 'details': details, 'logoPath': logoPath};

  factory BusinessProfile.fromJson(Map<String, Object?> json) =>
      BusinessProfile(name: json['name'] as String? ?? '', details: json['details'] as String? ?? '', logoPath: json['logoPath'] as String?);
}

/// A single place a watermark is drawn, top-left corner in picture pixels (may be partly outside the picture).
class WatermarkSpot {
  const WatermarkSpot(this.x, this.y);
  final int x;
  final int y;
}

abstract final class WatermarkPlacement {
  /// Where the stamp goes. One mark sits at its position with a margin; repeated marks fill the picture in a
  /// staggered pattern and reach the edges, so cropping cannot remove them.
  static List<WatermarkSpot> spots({
    required int imageWidth,
    required int imageHeight,
    required int stampWidth,
    required int stampHeight,
    required WatermarkLayout layout,
    required WatermarkPosition position,
  }) {
    if (stampWidth <= 0 || stampHeight <= 0) return const [];
    if (layout == WatermarkLayout.single) {
      final margin = (math.min(imageWidth, imageHeight) * 0.03).round();
      final freeW = imageWidth - stampWidth - 2 * margin;
      final freeH = imageHeight - stampHeight - 2 * margin;
      // A stamp bigger than the picture is centred and cut at the edges.
      final x = freeW >= 0 ? margin + (freeW * position.fx).round() : ((imageWidth - stampWidth) / 2).round();
      final y = freeH >= 0 ? margin + (freeH * position.fy).round() : ((imageHeight - stampHeight) / 2).round();
      return [WatermarkSpot(x, y)];
    }

    final stepX = (stampWidth * 1.5).round();
    final stepY = (stampHeight * 2.2).round();
    final spots = <WatermarkSpot>[];
    var row = 0;
    for (var y = -stampHeight ~/ 2; y < imageHeight; y += stepY, row++) {
      // Every other row is shifted by half a step so the pattern does not form columns.
      final shift = row.isOdd ? stepX ~/ 2 : 0;
      for (var x = -stampWidth ~/ 2 + shift - stepX; x < imageWidth; x += stepX) {
        if (x + stampWidth <= 0 || y + stampHeight <= 0) continue;
        spots.add(WatermarkSpot(x, y));
      }
    }
    return spots;
  }
}
