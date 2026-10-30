import 'package:equatable/equatable.dart';

import '../../../core/error/result.dart';

/// A box on a page as shares of the page as it is shown (0 to 1), measured from the top left.
class FormBox extends Equatable {
  const FormBox(this.left, this.top, this.right, this.bottom);
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  @override
  List<Object?> get props => [left, top, right, bottom];
}

enum FormFieldKind { text, checkbox, radio, choice }

/// One choice of a list, a drop-down or a radio group: [value] is what is stored, [label] what is shown.
class FormOption extends Equatable {
  const FormOption(this.value, this.label);
  final String value;
  final String label;

  @override
  List<Object?> get props => [value, label];
}

/// A fill-in box of a PDF form, where it is on its page and what it holds now.
/// A check box is "on" or "off"; a radio group holds the stored value of the chosen option.
class FormFieldInfo extends Equatable {
  const FormFieldInfo({
    required this.id,
    required this.widget,
    required this.name,
    required this.kind,
    required this.page,
    required this.box,
    required this.value,
    this.options = const [],
    this.option,
    this.multiline = false,
    this.maxLength = 0,
  });

  /// Number of the field; several boxes (the buttons of a radio group) can share it.
  final int id;

  /// Which box of the field this is.
  final int widget;
  final String name;
  final FormFieldKind kind;
  final int page;
  final FormBox box;
  final String value;
  final List<FormOption> options;

  /// For a radio button: the value it stands for.
  final String? option;
  final bool multiline;
  final int maxLength;

  bool get checked => kind == FormFieldKind.checkbox && value == 'on';

  @override
  List<Object?> get props => [id, widget, name, kind, page, box, value, options, option, multiline, maxLength];
}

class PdfFormPageInfo extends Equatable {
  const PdfFormPageInfo({required this.aspect, required this.widthPt, required this.fields});

  /// Width over height of the page as shown.
  final double aspect;

  /// Width of the page as shown, in points.
  final double widthPt;
  final List<FormFieldInfo> fields;

  @override
  List<Object?> get props => [aspect, widthPt, fields];
}

class PdfFormInfo extends Equatable {
  const PdfFormInfo({required this.pages, required this.notes, required this.bytes});
  final List<PdfFormPageInfo> pages;

  /// Comments, stamps, drawings and form boxes that flattening would make part of the page.
  final int notes;
  final int bytes;

  int get fieldCount => {
    for (final p in pages)
      for (final f in p.fields) f.id,
  }.length;
  bool get hasFields => fieldCount > 0;

  @override
  List<Object?> get props => [pages, notes, bytes];
}

enum MarkKind { text, tick, cross }

/// Something put on a page by hand: a line of text (a date is one), a tick or a cross.
class PdfMark extends Equatable {
  const PdfMark({required this.page, required this.u, required this.v, required this.kind, this.text = '', this.sizePt = 12});

  final int page;

  /// Where it goes, as shares of the page as it is shown, from the top left. Text starts at [u] and is centred on [v].
  final double u;
  final double v;
  final MarkKind kind;
  final String text;
  final double sizePt;

  PdfMark copyWith({double? u, double? v, String? text, double? sizePt}) =>
      PdfMark(page: page, u: u ?? this.u, v: v ?? this.v, kind: kind, text: text ?? this.text, sizePt: sizePt ?? this.sizePt);

  @override
  List<Object?> get props => [page, u, v, kind, text, sizePt];
}

/// What to do to the PDF: new values for fields by number, marks to add, and whether to make everything permanent.
class PdfFormPlan {
  const PdfFormPlan({this.values = const {}, this.marks = const [], this.flatten = false});
  final Map<int, String> values;
  final List<PdfMark> marks;
  final bool flatten;

  bool get isEmpty => values.isEmpty && marks.isEmpty && !flatten;
}

class FilledPdf extends Equatable {
  const FilledPdf({required this.path, required this.bytes});
  final String path;
  final int bytes;

  @override
  List<Object?> get props => [path, bytes];
}

abstract interface class PdfFormService {
  /// The fill-in boxes of every page and how much a flatten would make permanent.
  Future<Result<PdfFormInfo>> inspect(String path);

  /// Writes a copy with the [plan] applied.
  Future<Result<FilledPdf>> save({required String sourcePath, required String outputPath, required PdfFormPlan plan});
}

/// How much to cut off each side of a page, as shares of the page as it is shown.
class CropInsets extends Equatable {
  const CropInsets({this.left = 0, this.top = 0, this.right = 0, this.bottom = 0});
  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isNone => left == 0 && top == 0 && right == 0 && bottom == 0;

  /// Each side is at most 90% and something of the page must be left.
  bool get isValid => [left, top, right, bottom].every((v) => v >= 0 && v <= 0.9) && left + right <= 0.95 && top + bottom <= 0.95;

  CropInsets copyWith({double? left, double? top, double? right, double? bottom}) =>
      CropInsets(left: left ?? this.left, top: top ?? this.top, right: right ?? this.right, bottom: bottom ?? this.bottom);

  @override
  List<Object?> get props => [left, top, right, bottom];
}

class ExtractedImage extends Equatable {
  const ExtractedImage({required this.path, required this.page, required this.width, required this.height, required this.bytes});
  final String path;

  /// First page (from 1) that shows it.
  final int page;
  final int width;
  final int height;
  final int bytes;

  @override
  List<Object?> get props => [path, page, width, height, bytes];
}

class ExtractionResult extends Equatable {
  const ExtractionResult({required this.images, required this.skipped});
  final List<ExtractedImage> images;

  /// Pictures that were found but are in a form that cannot be saved as a normal picture file.
  final int skipped;

  @override
  List<Object?> get props => [images, skipped];
}

abstract interface class PdfPageToolsService {
  /// Writes a copy where the pages in [insets] (by index) show less. Nothing is removed from the file.
  Future<Result<FilledPdf>> crop({required String sourcePath, required String outputPath, required Map<int, CropInsets> insets});

  /// Saves the pictures inside the PDF as files in [outputDir].
  Future<Result<ExtractionResult>> extractImages({required String sourcePath, required String outputDir});
}
