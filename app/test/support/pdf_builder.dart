import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doculoom/features/pdf_tools/data/security/pdf_model.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_rewriter.dart';

PdfString pdfStr(String s) => PdfString(Uint8List.fromList(latin1.encode(s)));

PdfArray pdfNums(List<num> v) => PdfArray([for (final x in v) PdfReal(x.toString())]);

/// Builds small PDF files by hand, so tests can have forms, turned pages and pictures of any shape.
class TestPdf {
  final objects = <int, PdfObj>{};
  final pageRefs = <PdfRef>[];
  final fieldRefs = <PdfRef>[];
  var _next = 1;
  late final PdfRef _font = add(
    PdfDict({
      'Type': const PdfName('Font'),
      'Subtype': const PdfName('Type1'),
      'BaseFont': const PdfName('Helvetica'),
      'Encoding': const PdfName('WinAnsiEncoding'),
    }),
  );
  final extraRoot = <String, PdfObj>{};
  PdfDict? _acroDefaults;

  PdfRef add(PdfObj o) {
    objects[_next] = o;
    return PdfRef(_next++, 0);
  }

  PdfStream flate(String content, [Map<String, PdfObj> extra = const {}]) =>
      PdfStream(PdfDict({...extra, 'Filter': const PdfName('FlateDecode')}), Uint8List.fromList(zlib.encode(latin1.encode(content))));

  /// A page with [text] written on it. Returns the page object so annotations can be added.
  PdfDict page({double width = 612, double height = 792, int rotate = 0, String text = 'Hello secret', Map<String, PdfObj> xobjects = const {}}) {
    final contents = add(flate('BT /F1 12 Tf 72 700 Td (${text.replaceAll('(', r'\(').replaceAll(')', r'\)')}) Tj ET'));
    final dict = PdfDict({
      'Type': const PdfName('Page'),
      'MediaBox': pdfNums([0, 0, width, height]),
      if (rotate != 0) 'Rotate': PdfInt(rotate),
      'Contents': contents,
      'Resources': PdfDict({
        'Font': PdfDict({'F1': _font}),
        if (xobjects.isNotEmpty) 'XObject': PdfDict(xobjects),
      }),
    });
    pageRefs.add(add(dict));
    return dict;
  }

  void _annot(PdfDict page, PdfRef ref) {
    final list = (page['Annots'] as PdfArray?)?.items ?? <PdfObj>[];
    page['Annots'] = PdfArray([...list, ref]);
  }

  PdfDict _widget(String ft, List<num> rect, PdfDict page, {int flags = 0, Map<String, PdfObj> extra = const {}}) => PdfDict({
    'Type': const PdfName('Annot'),
    'Subtype': const PdfName('Widget'),
    'FT': PdfName(ft),
    if (flags != 0) 'Ff': PdfInt(flags),
    'Rect': pdfNums(rect),
    'F': const PdfInt(4),
    'P': pageRefs.last,
    ...extra,
  });

  PdfRef textField(PdfDict page, String name, List<num> rect, {String value = '', int flags = 0, String da = '/Helv 0 Tf 0 g', int? maxLen, int? q}) {
    final w = _widget(
      'Tx',
      rect,
      page,
      flags: flags,
      extra: {
        'T': pdfStr(name),
        'DA': pdfStr(da),
        if (value.isNotEmpty) 'V': pdfStr(value),
        if (maxLen != null) 'MaxLen': PdfInt(maxLen),
        if (q != null) 'Q': PdfInt(q),
        'MK': PdfDict({
          'BC': pdfNums([0, 0, 0]),
          'BG': pdfNums([0.9]),
        }),
      },
    );
    final ref = add(w);
    _annot(page, ref);
    fieldRefs.add(ref);
    return ref;
  }

  PdfStream _look(List<num> rect, String content) => PdfStream(
    PdfDict({
      'Type': const PdfName('XObject'),
      'Subtype': const PdfName('Form'),
      'BBox': pdfNums([0, 0, rect[2] - rect[0], rect[3] - rect[1]]),
    }),
    Uint8List.fromList(latin1.encode(content)),
  );

  PdfRef checkbox(PdfDict page, String name, List<num> rect, {bool on = false, bool withLook = true}) {
    final w = _widget(
      'Btn',
      rect,
      page,
      extra: {
        'T': pdfStr(name),
        'V': PdfName(on ? 'Yes' : 'Off'),
        'AS': PdfName(on ? 'Yes' : 'Off'),
        if (withLook)
          'AP': PdfDict({
            'N': PdfDict({'Yes': add(_look(rect, '0 0 1 rg 0 0 5 5 re f')), 'Off': add(_look(rect, ''))}),
          }),
      },
    );
    final ref = add(w);
    _annot(page, ref);
    fieldRefs.add(ref);
    return ref;
  }

  /// A radio group: one parent with a kid for every option.
  PdfRef radio(PdfDict page, String name, List<(String, List<num>)> options, {String? chosen}) {
    final kids = <PdfRef>[];
    final parent = PdfDict({'FT': const PdfName('Btn'), 'Ff': const PdfInt(32768), 'T': pdfStr(name), 'V': PdfName(chosen ?? 'Off')});
    final parentRef = add(parent);
    for (final (state, rect) in options) {
      final kid = PdfDict({
        'Type': const PdfName('Annot'),
        'Subtype': const PdfName('Widget'),
        'Rect': pdfNums(rect),
        'F': const PdfInt(4),
        'Parent': parentRef,
        'AS': PdfName(chosen == state ? state : 'Off'),
        'AP': PdfDict({
          'N': PdfDict({state: add(_look(rect, '0 g 0 0 4 4 re f')), 'Off': add(_look(rect, ''))}),
        }),
      });
      final ref = add(kid);
      kids.add(ref);
      _annot(page, ref);
    }
    parent['Kids'] = PdfArray(kids);
    fieldRefs.add(parentRef);
    return parentRef;
  }

  PdfRef combo(PdfDict page, String name, List<num> rect, List<(String, String)> options, {String value = ''}) {
    final w = _widget(
      'Ch',
      rect,
      page,
      flags: 131072,
      extra: {
        'T': pdfStr(name),
        'DA': pdfStr('/Helv 10 Tf 0 g'),
        'Opt': PdfArray([
          for (final (v, l) in options) PdfArray([pdfStr(v), pdfStr(l)]),
        ]),
        if (value.isNotEmpty) 'V': pdfStr(value),
      },
    );
    final ref = add(w);
    _annot(page, ref);
    fieldRefs.add(ref);
    return ref;
  }

  /// A note that is not a form box: it has a look of its own (a red square) and a position.
  void stamp(PdfDict page, List<num> rect) {
    final ref = add(
      PdfDict({
        'Type': const PdfName('Annot'),
        'Subtype': const PdfName('Stamp'),
        'Rect': pdfNums(rect),
        'F': const PdfInt(4),
        'AP': PdfDict({'N': add(_look(rect, '1 0 0 rg 0 0 ${rect[2] - rect[0]} ${rect[3] - rect[1]} re f'))}),
      }),
    );
    _annot(page, ref);
  }

  void link(PdfDict page, List<num> rect) {
    final ref = add(
      PdfDict({
        'Type': const PdfName('Annot'),
        'Subtype': const PdfName('Link'),
        'Rect': pdfNums(rect),
        'Border': pdfNums([0, 0, 0]),
      }),
    );
    _annot(page, ref);
  }

  Uint8List finish() {
    final pagesRef = PdfRef(_next, 0);
    final pages = PdfDict({'Type': const PdfName('Pages'), 'Kids': PdfArray(pageRefs), 'Count': PdfInt(pageRefs.length)});
    objects[_next++] = pages;
    for (final p in pageRefs) {
      (objects[p.number]! as PdfDict)['Parent'] = pagesRef;
    }
    final root = PdfDict({
      'Type': const PdfName('Catalog'),
      'Pages': pagesRef,
      if (fieldRefs.isNotEmpty) 'AcroForm': PdfDict({'Fields': PdfArray(fieldRefs), 'DA': pdfStr('/Helv 0 Tf 0 g'), ...?_acroDefaults?.entries}),
      ...extraRoot,
    });
    final rootRef = add(root);
    return writePdfDocument(PdfDoc(objects, PdfDict({'Root': rootRef})));
  }
}
