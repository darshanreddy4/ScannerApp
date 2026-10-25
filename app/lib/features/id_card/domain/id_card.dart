import 'dart:math' as math;

import '../../../core/error/result.dart';
import '../../photo_tools/domain/passport_maker.dart';

/// The physical size of a card, so the copy on paper matches the real card.
class CardSize {
  const CardSize({required this.id, required this.label, required this.widthMm, required this.heightMm});

  final String id;
  final String label;
  final double widthMm;
  final double heightMm;

  double get aspect => widthMm / heightMm;
  String get sizeLabel => '${_mm(widthMm)} x ${_mm(heightMm)} mm';

  static String _mm(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// Aadhaar, PAN, driving licence, voter ID, debit and credit cards, and most ID cards.
  static const idCard = CardSize(id: 'id1', label: 'ID or bank card', widthMm: 85.6, heightMm: 54);
  static const passportPage = CardSize(id: 'id3', label: 'Passport page', widthMm: 125, heightMm: 88);
  static const a6 = CardSize(id: 'a6', label: 'A6 card or certificate', widthMm: 148, heightMm: 105);

  static const presets = [idCard, passportPage, a6];

  static const minMm = 20.0;
  static const maxMm = 280.0;

  /// A size typed by the user; null when it is not usable.
  static CardSize? custom(double widthMm, double heightMm) {
    if (widthMm < minMm || heightMm < minMm || widthMm > maxMm || heightMm > maxMm) return null;
    return CardSize(id: 'custom', label: 'Custom', widthMm: widthMm, heightMm: heightMm);
  }

  @override
  bool operator ==(Object other) => other is CardSize && other.id == id && other.widthMm == widthMm && other.heightMm == heightMm;

  @override
  int get hashCode => Object.hash(id, widthMm, heightMm);
}

enum CardPaper {
  a4('A4', 210, 297),
  letter('Letter', 215.9, 279.4);

  const CardPaper(this.label, this.widthMm, this.heightMm);
  final String label;
  final double widthMm;
  final double heightMm;
}

/// How big the cards are drawn on the paper.
enum CardScale {
  actual('Real size'),
  fill('Fill the page width');

  const CardScale(this.label);
  final String label;
}

class IdCardOptions {
  const IdCardOptions({this.size = CardSize.idCard, this.paper = CardPaper.a4, this.scale = CardScale.actual, this.blackAndWhite = false, this.border = true});

  final CardSize size;
  final CardPaper paper;
  final CardScale scale;
  final bool blackAndWhite;

  /// A thin line around each card to cut along.
  final bool border;

  IdCardOptions copyWith({CardSize? size, CardPaper? paper, CardScale? scale, bool? blackAndWhite, bool? border}) => IdCardOptions(
    size: size ?? this.size,
    paper: paper ?? this.paper,
    scale: scale ?? this.scale,
    blackAndWhite: blackAndWhite ?? this.blackAndWhite,
    border: border ?? this.border,
  );

  @override
  bool operator ==(Object other) =>
      other is IdCardOptions &&
      other.size == size &&
      other.paper == paper &&
      other.scale == scale &&
      other.blackAndWhite == blackAndWhite &&
      other.border == border;

  @override
  int get hashCode => Object.hash(size, paper, scale, blackAndWhite, border);
}

class CardSlot {
  const CardSlot({required this.xMm, required this.yMm, required this.widthMm, required this.heightMm});
  final double xMm;
  final double yMm;
  final double widthMm;
  final double heightMm;
}

/// Where the cards go on the paper: one above the other, centred.
class CardLayout {
  const CardLayout({required this.paperWidthMm, required this.paperHeightMm, required this.slots, required this.scale, required this.shrunk});

  final double paperWidthMm;
  final double paperHeightMm;
  final List<CardSlot> slots;

  /// Size on paper compared with the real card (1 is real size).
  final double scale;

  /// The card does not fit at real size and was made smaller.
  final bool shrunk;

  static const marginMm = 10.0;
  static const gapMm = 12.0;

  static CardLayout place({required CardPaper paper, required CardSize size, required int count, required CardScale scale}) {
    final n = math.max(1, count);
    final usableW = paper.widthMm - 2 * marginMm;
    final usableH = paper.heightMm - 2 * marginMm - (n - 1) * gapMm;
    final maxScale = math.min(usableW / size.widthMm, usableH / (n * size.heightMm));
    final double s;
    var shrunk = false;
    if (scale == CardScale.fill) {
      s = maxScale;
    } else if (maxScale < 1) {
      s = maxScale;
      shrunk = true;
    } else {
      s = 1;
    }
    final w = size.widthMm * s, h = size.heightMm * s;
    final blockH = n * h + (n - 1) * gapMm;
    final x = (paper.widthMm - w) / 2;
    final y0 = (paper.heightMm - blockH) / 2;
    return CardLayout(
      paperWidthMm: paper.widthMm,
      paperHeightMm: paper.heightMm,
      scale: s,
      shrunk: shrunk,
      slots: [for (var i = 0; i < n; i++) CardSlot(xMm: x, yMm: y0 + i * (h + gapMm), widthMm: w, heightMm: h)],
    );
  }
}

/// Which part of a prepared photo is the card.
class CardCrop {
  const CardCrop({required this.path, required this.left, required this.top, required this.width, required this.height});
  final String path;
  final double left;
  final double top;
  final double width;
  final double height;
}

class CardSheetFiles {
  const CardSheetFiles({required this.jpgPath, required this.pdfPath, required this.cards, required this.scale, required this.shrunk});
  final String jpgPath;
  final String pdfPath;
  final int cards;
  final double scale;
  final bool shrunk;
}

abstract interface class IdCardMaker {
  /// Applies the rotation flag, limits the size and saves a copy to crop from.
  Future<Result<WorkingPhoto>> prepare({required String sourcePath, required String outputPath, bool rotateRight = false});

  /// Crops each side to the card and puts them on one sheet of paper, as a 300 dpi JPG and a PDF of exactly the paper size.
  Future<Result<CardSheetFiles>> sheet({required List<CardCrop> sides, required IdCardOptions options, required String outputBase});
}
