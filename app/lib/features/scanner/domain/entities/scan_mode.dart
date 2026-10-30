import 'quad.dart';

/// What is being scanned. It changes how the camera guides you and what happens after the photo; it never changes the look of the picture.
enum ScanMode {
  document('Document', 'Scan', 'Document', 'Align the document in the frame'),
  receipt(
    'Receipt',
    'Receipt',
    'Receipt',
    'Flatten the receipt in the frame',
    finishesItself: true,
    about: 'Reads the receipt after the photo: shop, total and date. Then you can share it as a PDF.',
  ),
  card(
    'Card',
    'Card',
    'Card',
    'Fit the card inside the frame',
    cardAspect: 1.75,
    twoSided: true,
    finishesItself: true,
    about: 'Front, then back. Reads the card and opens a new contact.',
  ),
  id(
    'ID',
    'ID',
    'ID',
    'Fit the ID inside the frame',
    cardAspect: 1.586,
    twoSided: true,
    finishesItself: true,
    about: 'Front, then back. Asks for the expiry date and can make a one-page copy.',
  ),
  book('Book', 'Book', 'Book', 'Open the book flat, both pages in the frame', split: true, about: 'Each photo becomes a left and a right page.'),
  whiteboard('Whiteboard', 'Whiteboard', 'Whiteboard', 'Fit the whole board in the frame'),
  table(
    'Table',
    'Table',
    'Table',
    'Fit the whole table in the frame',
    finishesItself: true,
    about: 'Reads the table after the photo and turns it into a spreadsheet you can correct, edit and share.',
  );

  const ScanMode(
    this.label,
    this.titleWord,
    this.noun,
    this.hint, {
    this.split = false,
    this.cardAspect,
    this.twoSided = false,
    this.finishesItself = false,
    this.about,
  });

  final String label;
  final String titleWord;

  /// Used in "Card detected" style messages.
  final String noun;

  /// Shown on the viewfinder while nothing is detected.
  final String hint;

  /// A captured spread becomes a left and a right page.
  final bool split;

  /// Width / height of the card this mode scans; the camera then shows a frame to fit it in.
  final double? cardAspect;

  /// Front and back are scanned one after the other.
  final bool twoSided;

  /// After the last photo the scan is saved and read straight away, without the page editor.
  final bool finishesItself;

  /// One line on what this mode does; null for plain scans.
  final String? about;

  String hintFor(int pagesTaken) => twoSided && pagesTaken == 1 ? 'Now the back of the ${noun.toLowerCase()}' : hint;

  String title(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$titleWord ${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}.${two(d.minute)}';
  }

  /// The frame shown in the viewfinder, in 0..1 coordinates of an image or preview with the given width / height.
  Quad? guideQuad(double imageAspect) {
    final card = cardAspect;
    if (card == null || imageAspect <= 0) return null;
    var w = 0.84;
    var h = w * imageAspect / card;
    if (h > 0.84) {
      h = 0.84;
      w = h * card / imageAspect;
    }
    final l = (1 - w) / 2;
    final t = (1 - h) / 2;
    return Quad(NormPoint(l, t), NormPoint(l + w, t), NormPoint(l + w, t + h), NormPoint(l, t + h));
  }

  /// The first crop for a new photo: a detected outline if it is believable, else the viewfinder frame for cards, else the whole picture.
  Quad pickQuad(Quad? detected, double imageAspect) {
    final guide = guideQuad(imageAspect);
    if (guide == null) return detected ?? Quad.fullFrame;
    if (detected != null && _looksLikeCard(detected, guide, imageAspect)) return detected;
    return guide;
  }

  bool _looksLikeCard(Quad q, Quad guide, double imageAspect) {
    if (!q.isConvex) return false;
    final ratio = guide.area <= 0 ? 0.0 : q.area / guide.area;
    if (ratio < 0.5 || ratio > 1.8) return false;
    final xs = q.points.map((p) => p.x);
    final ys = q.points.map((p) => p.y);
    final w = (xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b)) * imageAspect;
    final h = ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
    if (h <= 0 || w <= 0) return false;
    final shape = w / h;
    final card = cardAspect!;
    bool near(double v) => v >= card * 0.7 && v <= card * 1.3;
    return near(shape) || near(1 / shape);
  }
}
