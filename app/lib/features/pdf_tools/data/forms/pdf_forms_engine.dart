import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../reader/data/pdf_page_reader.dart';
import '../../../reader/data/pdf_text_edit.dart' show unsupportedCharacters, winAnsiBytes;
import '../../domain/pdf_forms.dart';
import '../security/pdf_model.dart';
import '../security/pdf_rewriter.dart';

class PdfFormException implements Exception {
  const PdfFormException(this.message);
  final String message;

  @override
  String toString() => message;
}

String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

String _hex(List<int> bytes) => '<${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>';

Uint8List _utf16(String s) {
  final out = <int>[0xFE, 0xFF];
  for (final u in s.codeUnits) {
    out
      ..add(u >> 8)
      ..add(u & 255);
  }
  return Uint8List.fromList(out);
}

String _decodeString(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    return String.fromCharCodes([for (var i = 2; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1]]);
  }
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
    return String.fromCharCodes([for (var i = 2; i + 1 < b.length; i += 2) (b[i + 1] << 8) | b[i]]);
  }
  return latin1.decode(b, allowInvalid: true);
}

class _Ctx {
  _Ctx(this.doc) : file = PdfReader(doc), next = (doc.objects.keys.isEmpty ? 0 : doc.objects.keys.reduce(math.max)) + 1;

  final PdfDoc doc;
  final PdfReader file;
  int next;
  PdfRef? _helvetica;

  PdfRef addRef(PdfObj o) {
    doc.objects[next] = o;
    return PdfRef(next++, 0);
  }

  PdfStream stream(String content, [Map<String, PdfObj> extra = const {}]) =>
      PdfStream(PdfDict({...extra, 'Filter': const PdfName('FlateDecode')}), Uint8List.fromList(zlib.encode(latin1.encode(content))));

  PdfRef get helvetica => _helvetica ??= addRef(
    PdfDict({
      'Type': const PdfName('Font'),
      'Subtype': const PdfName('Type1'),
      'BaseFont': const PdfName('Helvetica'),
      'Encoding': const PdfName('WinAnsiEncoding'),
    }),
  );

  PdfDict? get root => file.dict(doc.trailer['Root']);
}

String? _nameOf(PdfReader f, PdfObj? o) => switch (f.res(o)) {
  PdfName(:final name) => name,
  _ => null,
};

PdfObj? _inherited(PdfReader f, List<PdfDict> chain, String key) {
  for (final d in chain) {
    final v = d[key];
    if (v != null) return f.res(v);
  }
  return null;
}

int? _intOf(PdfReader f, PdfObj? o) => f.number(o)?.round();

// ------------------------------------------------------------------ finding the fields

class _Widget {
  _Widget(this.annot, this.page, this.rect, this.chain);
  final PdfDict annot;
  final int page;

  /// Left, bottom, right, top in page units.
  final List<double> rect;
  final List<PdfDict> chain;

  double get width => rect[2] - rect[0];
  double get height => rect[3] - rect[1];
}

class _Field {
  _Field(this.id, this.dict, this.name, this.kind, this.flags);
  final int id;
  final PdfDict dict;
  final String name;
  final FormFieldKind kind;
  final int flags;
  final widgets = <_Widget>[];

  bool get multiline => kind == FormFieldKind.text && flags & 4096 != 0;
  bool get password => kind == FormFieldKind.text && flags & 8192 != 0;
}

List<_Field> _collect(_Ctx c, List<PdfPageInfo> pages) {
  final file = c.file;
  final fields = <_Field>[];
  final byDict = HashMap<PdfDict, _Field>.identity();
  for (var i = 0; i < pages.length; i++) {
    for (final raw in file.list(pages[i].dict['Annots'])) {
      final a = file.dict(raw);
      if (a == null || _nameOf(file, a['Subtype']) != 'Widget') continue;
      final chain = <PdfDict>[a];
      var cur = a;
      for (var depth = 0; depth < 24; depth++) {
        final parent = file.dict(cur['Parent']);
        if (parent == null || chain.any((x) => identical(x, parent))) break;
        chain.add(parent);
        cur = parent;
      }
      final ft = _inherited(file, chain, 'FT');
      final type = ft is PdfName ? ft.name : null;
      if (type == null || type == 'Sig') continue;
      final flags = _intOf(file, _inherited(file, chain, 'Ff')) ?? 0;
      final kind = switch (type) {
        'Tx' => FormFieldKind.text,
        'Ch' => FormFieldKind.choice,
        'Btn' => flags & 65536 != 0 ? null : (flags & 32768 != 0 ? FormFieldKind.radio : FormFieldKind.checkbox),
        _ => null,
      };
      if (kind == null) continue;
      final rect = file.numbers(a['Rect'], 4);
      if (rect == null) continue;
      final box = [math.min(rect[0], rect[2]), math.min(rect[1], rect[3]), math.max(rect[0], rect[2]), math.max(rect[1], rect[3])];
      final fieldDict = chain.firstWhere((x) => x['T'] != null, orElse: () => a);
      var field = byDict[fieldDict];
      if (field == null) {
        final names = [
          for (final d in chain.reversed)
            if (file.res(d['T']) case PdfString(:final bytes)) _decodeString(bytes),
        ];
        field = _Field(fields.length, fieldDict, names.join('.'), kind, flags);
        fields.add(field);
        byDict[fieldDict] = field;
      }
      field.widgets.add(_Widget(a, i, box, chain));
    }
  }
  return fields;
}

bool _hidden(PdfReader f, PdfDict annot) {
  final flags = _intOf(f, annot['F']) ?? 0;
  return flags & 2 != 0 || flags & 32 != 0;
}

/// The name of the "on" look of a check box or radio button, or null when it has none.
String? _onState(PdfReader f, PdfDict annot) {
  final n = f.res(f.dict(annot['AP'])?['N']);
  if (n is! PdfDict) return null;
  for (final key in n.entries.keys) {
    if (key != 'Off') return key;
  }
  return null;
}

String _textOf(PdfReader f, PdfObj? o) => switch (f.res(o)) {
  PdfString(:final bytes) => _decodeString(bytes),
  PdfName(:final name) => name,
  _ => '',
};

List<FormOption> _choiceOptions(PdfReader f, _Field field) {
  final opt = _inherited(f, [field.dict, ...field.widgets.first.chain], 'Opt');
  if (opt is! PdfArray) return const [];
  return [
    for (final o in opt.items)
      if (f.res(o) case final PdfArray pair when pair.items.length >= 2)
        FormOption(_textOf(f, pair.items[0]), _textOf(f, pair.items[1]))
      else if (f.res(o) is PdfString)
        FormOption(_textOf(f, o), _textOf(f, o)),
  ];
}

// ------------------------------------------------------------------ reading

/// The fill-in boxes of every page, and how many notes and boxes flattening would make permanent.
PdfFormInfo readPdfForm(Uint8List bytes) {
  final c = _Ctx(readPdfDocument(bytes));
  final pages = c.file.pages();
  if (pages.isEmpty) throw const PdfFormException('This PDF has no pages.');
  final fields = _collect(c, pages);
  final perPage = List.generate(pages.length, (_) => <FormFieldInfo>[]);
  for (final field in fields) {
    final options = switch (field.kind) {
      FormFieldKind.choice => _choiceOptions(c.file, field),
      FormFieldKind.radio => [
        for (final w in field.widgets)
          if (_onState(c.file, w.annot) case final on?) FormOption(on, on),
      ],
      _ => const <FormOption>[],
    };
    final stored = _textOf(c.file, _inherited(c.file, [field.dict, ...field.widgets.first.chain], 'V'));
    for (var wi = 0; wi < field.widgets.length; wi++) {
      final w = field.widgets[wi];
      if (_hidden(c.file, w.annot) || w.width <= 0 || w.height <= 0) continue;
      final geo = PageGeometry(pages[w.page]);
      final box = geo.normalize(PdfBox(w.rect[0], w.rect[1], w.rect[2], w.rect[3]));
      final on = _onState(c.file, w.annot);
      final state = _nameOf(c.file, w.annot['AS']);
      final value = switch (field.kind) {
        FormFieldKind.checkbox => (state != null ? state != 'Off' : (stored.isNotEmpty && stored != 'Off')) ? 'on' : 'off',
        FormFieldKind.radio => stored == 'Off' ? '' : stored,
        FormFieldKind.choice => stored,
        FormFieldKind.text => stored,
      };
      perPage[w.page].add(
        FormFieldInfo(
          id: field.id,
          widget: wi,
          name: field.name,
          kind: field.kind,
          page: w.page,
          box: FormBox(box.left, box.top, box.right, box.bottom),
          value: value,
          options: options,
          option: field.kind == FormFieldKind.radio ? on : null,
          multiline: field.multiline,
          maxLength: _intOf(c.file, _inherited(c.file, [field.dict, ...w.chain], 'MaxLen')) ?? 0,
        ),
      );
    }
  }
  var notes = 0;
  for (final page in pages) {
    for (final raw in c.file.list(page.dict['Annots'])) {
      final a = c.file.dict(raw);
      if (a != null && _flattenable(c.file, a) != null) notes++;
    }
  }
  return PdfFormInfo(
    pages: [
      for (var i = 0; i < pages.length; i++)
        PdfFormPageInfo(
          aspect: PageGeometry(pages[i]).aspect,
          widthPt: (PageGeometry(pages[i]).rotation == 90 || PageGeometry(pages[i]).rotation == 270) ? PageGeometry(pages[i]).h : PageGeometry(pages[i]).w,
          fields: perPage[i],
        ),
    ],
    notes: notes,
    bytes: bytes.length,
  );
}

// ------------------------------------------------------------------ writing

/// What goes onto one page: more drawing instructions, the fonts and pictures they use, and the annotations that are left.
class _PageEdit {
  _PageEdit(this.info);
  final PdfPageInfo info;
  final ops = StringBuffer();
  final fonts = <String, PdfObj>{};
  final xobjects = <String, PdfObj>{};
  List<PdfObj>? annots;

  void commit(_Ctx c) {
    if (ops.isNotEmpty) {
      final existing = c.file.res(info.dict['Contents']);
      final refs = existing is PdfArray ? [...existing.items] : [if (existing != null) info.dict['Contents']!];
      // The page's own instructions are fenced off so a state they leave behind cannot change what is added.
      info.dict['Contents'] = PdfArray([c.addRef(c.stream('q\n')), ...refs, c.addRef(c.stream('Q\n')), c.addRef(c.stream(ops.toString()))]);
      if (fonts.isNotEmpty || xobjects.isNotEmpty) {
        final resources = PdfDict(Map.of(info.resources?.entries ?? const <String, PdfObj>{}));
        if (fonts.isNotEmpty) resources['Font'] = PdfDict({...?c.file.dict(resources['Font'])?.entries, ...fonts});
        if (xobjects.isNotEmpty) resources['XObject'] = PdfDict({...?c.file.dict(resources['XObject'])?.entries, ...xobjects});
        info.dict['Resources'] = resources;
      }
    }
    final left = annots;
    if (left != null) {
      if (left.isEmpty) {
        info.dict.entries.remove('Annots');
      } else {
        info.dict['Annots'] = PdfArray(left);
      }
    }
  }
}

/// Applies [plan] to the PDF and returns the new file: field values, marks, and (when asked) everything made part of the pages.
Uint8List applyPdfFormPlan(Uint8List bytes, PdfFormPlan plan) {
  final c = _Ctx(readPdfDocument(bytes));
  final pages = c.file.pages();
  if (pages.isEmpty) throw const PdfFormException('This PDF has no pages.');
  final edits = <int, _PageEdit>{};
  _PageEdit editOf(int i) => edits.putIfAbsent(i, () => _PageEdit(pages[i]));

  if (plan.values.isNotEmpty) {
    for (final field in _collect(c, pages)) {
      final value = plan.values[field.id];
      if (value != null) _setField(c, field, value);
    }
  }
  for (final mark in plan.marks) {
    if (mark.page < 0 || mark.page >= pages.length) throw const PdfFormException('A mark is on a page that is not in this PDF.');
    _drawMark(c, editOf(mark.page), mark);
  }
  if (plan.flatten) {
    for (var i = 0; i < pages.length; i++) {
      _flattenPage(c, editOf(i));
    }
    final root = c.root;
    root?.entries.remove('AcroForm');
    root?.entries.remove('NeedAppearances');
  }
  for (final e in edits.values) {
    e.commit(c);
  }
  return writePdfDocument(c.doc);
}

// region marks

void _drawMark(_Ctx c, _PageEdit e, PdfMark m) {
  final geo = PageGeometry(e.info);
  final shownHeight = (geo.rotation == 90 || geo.rotation == 270) ? geo.w : geo.h;
  final angle = geo.rotation * math.pi / 180;
  final cs = _n(math.cos(angle)), sn = _n(math.sin(angle)), msn = _n(-math.sin(angle));
  final size = m.sizePt;
  switch (m.kind) {
    case MarkKind.text:
      final lines = m.text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) return;
      final encoded = <Uint8List>[];
      for (final line in lines) {
        final b = winAnsiBytes(line);
        if (b == null) throw PdfFormException('The text "${unsupportedCharacters(line)}" cannot be placed in a PDF. Use letters, numbers and common symbols.');
        encoded.add(b);
      }
      final (ux, uy) = geo.toPageUnits(m.u, m.v + 0.3 * size / shownHeight);
      e.fonts['SVHelv'] = c.helvetica;
      e.ops.write('q 0 g BT /SVHelv ${_n(size)} Tf ${_n(size * 1.2)} TL $cs $sn $msn $cs ${_n(ux)} ${_n(uy)} Tm\n');
      for (var i = 0; i < encoded.length; i++) {
        e.ops.write('${i == 0 ? '' : 'T* '}${_hex(encoded[i])} Tj\n');
      }
      e.ops.write('ET Q\n');
    case MarkKind.tick:
      final (ux, uy) = geo.toPageUnits(m.u, m.v);
      e.ops.write(
        'q $cs $sn $msn $cs ${_n(ux)} ${_n(uy)} cm 1 J 1 j ${_n(size * 0.13)} w 0 G '
        '${_n(-0.38 * size)} ${_n(-0.02 * size)} m ${_n(-0.12 * size)} ${_n(-0.30 * size)} l ${_n(0.40 * size)} ${_n(0.34 * size)} l S Q\n',
      );
    case MarkKind.cross:
      final (ux, uy) = geo.toPageUnits(m.u, m.v);
      e.ops.write(
        'q $cs $sn $msn $cs ${_n(ux)} ${_n(uy)} cm 1 J ${_n(size * 0.12)} w 0 G '
        '${_n(-0.3 * size)} ${_n(-0.3 * size)} m ${_n(0.3 * size)} ${_n(0.3 * size)} l ${_n(-0.3 * size)} ${_n(0.3 * size)} m ${_n(0.3 * size)} ${_n(-0.3 * size)} l S Q\n',
      );
  }
}

// endregion

// region setting values

void _setField(_Ctx c, _Field f, String value) {
  switch (f.kind) {
    case FormFieldKind.text || FormFieldKind.choice:
      var stored = value;
      var shown = value;
      if (f.kind == FormFieldKind.choice) {
        final match = _choiceOptions(c.file, f).where((o) => o.value == value);
        if (match.isNotEmpty) shown = match.first.label;
      }
      final maxLen = _intOf(c.file, _inherited(c.file, [f.dict, ...f.widgets.first.chain], 'MaxLen')) ?? 0;
      if (maxLen > 0 && f.kind == FormFieldKind.text && shown.length > maxLen) {
        stored = shown = shown.substring(0, maxLen);
      }
      if (winAnsiBytes(shown) == null) {
        throw PdfFormException('The text "${unsupportedCharacters(shown)}" cannot be placed in a PDF. Use letters, numbers and common symbols.');
      }
      f.dict['V'] = PdfString(_utf16(stored));
      f.dict.entries.remove('RV');
      for (final w in f.widgets) {
        w.annot['AP'] = PdfDict({'N': c.addRef(_textAppearance(c, f, w, shown))});
      }
    case FormFieldKind.checkbox:
      final on = value == 'on';
      var name = 'Yes';
      for (final w in f.widgets) {
        var state = _onState(c.file, w.annot);
        if (state == null) {
          state = 'Yes';
          w.annot['AP'] = PdfDict({
            'N': PdfDict({'Yes': c.addRef(_markAppearance(w, round: false)), 'Off': c.addRef(_blankAppearance(w))}),
          });
        }
        name = state;
        w.annot['AS'] = PdfName(on ? state : 'Off');
      }
      f.dict['V'] = PdfName(on ? name : 'Off');
    case FormFieldKind.radio:
      var chosenFound = false;
      for (var i = 0; i < f.widgets.length; i++) {
        final w = f.widgets[i];
        var state = _onState(c.file, w.annot);
        if (state == null) {
          state = 'Choice${i + 1}';
          w.annot['AP'] = PdfDict({
            'N': PdfDict({state: c.addRef(_markAppearance(w, round: true)), 'Off': c.addRef(_blankAppearance(w))}),
          });
        }
        final chosen = state == value;
        chosenFound |= chosen;
        w.annot['AS'] = PdfName(chosen ? state : 'Off');
      }
      if (value.isNotEmpty && !chosenFound) throw const PdfFormException('That choice is not offered by this form.');
      f.dict['V'] = PdfName(value.isEmpty ? 'Off' : value);
  }
}

String _color(PdfReader file, PdfObj? o, {required bool stroke}) {
  final a = file.res(o);
  if (a is! PdfArray) return '';
  final v = [for (final i in a.items) file.number(i) ?? 0];
  return switch (v.length) {
    1 => '${_n(v[0])} ${stroke ? 'G' : 'g'}',
    3 => '${_n(v[0])} ${_n(v[1])} ${_n(v[2])} ${stroke ? 'RG' : 'rg'}',
    4 => '${_n(v[0])} ${_n(v[1])} ${_n(v[2])} ${_n(v[3])} ${stroke ? 'K' : 'k'}',
    _ => '',
  };
}

/// The background and border a widget asks for, so a new look keeps the form's design.
String _frame(_Ctx c, _Widget w) {
  final mk = c.file.dict(w.annot['MK']);
  if (mk == null) return '';
  final out = StringBuffer();
  final bg = _color(c.file, mk['BG'], stroke: false);
  if (bg.isNotEmpty) out.write('q $bg 0 0 ${_n(w.width)} ${_n(w.height)} re f Q\n');
  final bc = _color(c.file, mk['BC'], stroke: true);
  if (bc.isNotEmpty) {
    final bw = c.file.number(c.file.dict(w.annot['BS'])?['W']) ?? 1;
    if (bw > 0) out.write('q $bc ${_n(bw)} w ${_n(bw / 2)} ${_n(bw / 2)} ${_n(w.width - bw)} ${_n(w.height - bw)} re S Q\n');
  }
  return out.toString();
}

PdfStream _form(_Ctx c, _Widget w, String content, {bool fonts = false}) => c.stream(content, {
  'Type': const PdfName('XObject'),
  'Subtype': const PdfName('Form'),
  'BBox': PdfArray([const PdfInt(0), const PdfInt(0), PdfReal(_n(w.width)), PdfReal(_n(w.height))]),
  if (fonts)
    'Resources': PdfDict({
      'Font': PdfDict({'Helv': c.helvetica}),
    }),
});

PdfStream _blankAppearance(_Widget w) => PdfStream(
  PdfDict({
    'Type': const PdfName('XObject'),
    'Subtype': const PdfName('Form'),
    'BBox': PdfArray([const PdfInt(0), const PdfInt(0), PdfReal(_n(w.width)), PdfReal(_n(w.height))]),
  }),
  Uint8List(0),
);

/// A tick (or a round dot for a radio button) that fills a widget.
PdfStream _markAppearance(_Widget w, {required bool round}) {
  final width = w.width, height = w.height;
  final b = StringBuffer('q 0 g 0 G ');
  if (round) {
    final r = math.min(width, height) * 0.28, cx = width / 2, cy = height / 2, k = r * 0.5523;
    b.write(
      '${_n(cx + r)} ${_n(cy)} m ${_n(cx + r)} ${_n(cy + k)} ${_n(cx + k)} ${_n(cy + r)} ${_n(cx)} ${_n(cy + r)} c '
      '${_n(cx - k)} ${_n(cy + r)} ${_n(cx - r)} ${_n(cy + k)} ${_n(cx - r)} ${_n(cy)} c '
      '${_n(cx - r)} ${_n(cy - k)} ${_n(cx - k)} ${_n(cy - r)} ${_n(cx)} ${_n(cy - r)} c '
      '${_n(cx + k)} ${_n(cy - r)} ${_n(cx + r)} ${_n(cy - k)} ${_n(cx + r)} ${_n(cy)} c f',
    );
  } else {
    b.write(
      '1 J 1 j ${_n(math.min(width, height) * 0.13)} w ${_n(width * 0.2)} ${_n(height * 0.52)} m ${_n(width * 0.42)} ${_n(height * 0.26)} l ${_n(width * 0.8)} ${_n(height * 0.78)} l S',
    );
  }
  b.write(' Q');
  return PdfStream(
    PdfDict({
      'Type': const PdfName('XObject'),
      'Subtype': const PdfName('Form'),
      'BBox': PdfArray([const PdfInt(0), const PdfInt(0), PdfReal(_n(width)), PdfReal(_n(height))]),
    }),
    Uint8List.fromList(latin1.encode(b.toString())),
  );
}

double _textWidth(Uint8List bytes, double size) {
  final widths = standardWidths('Helvetica');
  var sum = 0.0;
  for (final b in bytes) {
    sum += widths(b);
  }
  return sum * size / 1000;
}

PdfStream _textAppearance(_Ctx c, _Field f, _Widget w, String text) {
  final file = c.file;
  final acro = file.dict(c.root?['AcroForm']);
  final da = _textOf(file, _inherited(file, [f.dict, ...w.chain], 'DA')).isNotEmpty
      ? _textOf(file, _inherited(file, [f.dict, ...w.chain], 'DA'))
      : _textOf(file, acro?['DA']);
  final fontSize = double.tryParse(RegExp(r'([\d.]+)\s+Tf').firstMatch(da)?.group(1) ?? '') ?? 0;
  final colorOps = RegExp(r'((?:[\d.]+\s+){1,4}(?:g|rg|k))').firstMatch(da)?.group(1) ?? '0 g';
  final quad = _intOf(file, _inherited(file, [f.dict, ...w.chain], 'Q')) ?? _intOf(file, acro?['Q']) ?? 0;
  final border = file.number(file.dict(w.annot['BS'])?['W']) ?? (file.dict(w.annot['MK'])?['BC'] != null ? 1 : 0);
  final pad = 2.0 + border;
  final availW = math.max(1.0, w.width - 2 * pad);
  final shown = f.password ? '\u2022' * text.length : text;

  final lines = <(Uint8List, double)>[];
  late double size;
  late double lineHeight;
  if (f.multiline) {
    size = fontSize > 0 ? fontSize : 12;
    lineHeight = size * 1.15;
    final wrapped = <String>[];
    for (final paragraph in shown.split(RegExp(r'\r?\n'))) {
      var line = '';
      for (final word in paragraph.split(' ')) {
        final candidate = line.isEmpty ? word : '$line $word';
        if (line.isNotEmpty && _textWidth(winAnsiBytes(candidate)!, size) > availW) {
          wrapped.add(line);
          line = word;
        } else {
          line = candidate;
        }
      }
      wrapped.add(line);
    }
    for (final line in wrapped) {
      lines.add((winAnsiBytes(line)!, 0));
    }
  } else {
    final single = shown.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final bytes = winAnsiBytes(single)!;
    size = fontSize > 0 ? fontSize : math.min(12.0, math.max(4.0, w.height - 2 * pad));
    final natural = _textWidth(bytes, size);
    if (fontSize == 0 && natural > availW) size = math.max(4.0, size * availW / natural);
    lineHeight = size * 1.15;
    lines.add((bytes, 0));
  }

  final b = StringBuffer(_frame(c, w));
  b.write('/Tx BMC\nq\n${_n(pad / 2)} ${_n(pad / 2)} ${_n(w.width - pad)} ${_n(w.height - pad)} re W n\nBT\n/Helv ${_n(size)} Tf\n$colorOps\n');
  for (var i = 0; i < lines.length; i++) {
    final bytes = lines[i].$1;
    if (bytes.isEmpty) continue;
    final tw = _textWidth(bytes, size);
    final x = quad == 1 ? (w.width - tw) / 2 : (quad == 2 ? w.width - pad - tw : pad);
    final y = f.multiline ? w.height - pad - size * 0.93 - i * lineHeight : (w.height - 0.925 * size) / 2 + 0.207 * size;
    b.write('1 0 0 1 ${_n(x)} ${_n(y)} Tm ${_hex(bytes)} Tj\n');
  }
  b.write('ET\nQ\nEMC\n');
  return _form(c, w, b.toString(), fonts: true);
}

// endregion

// region flattening

/// The look of an annotation as a picture reference, or null when it has none or is not meant to be shown.
({PdfObj ref, PdfStream stream})? _flattenable(PdfReader f, PdfDict a) {
  final subtype = _nameOf(f, a['Subtype']);
  if (subtype == 'Link' || subtype == 'Popup' || _hidden(f, a)) return null;
  final ap = f.dict(a['AP']);
  final n = ap?['N'];
  if (n == null) return null;
  var target = n;
  final resolved = f.res(n);
  if (resolved is PdfDict) {
    final state = _nameOf(f, a['AS']);
    if (state == null || resolved[state] == null) return null;
    target = resolved[state]!;
  }
  final stream = f.res(target);
  if (stream is! PdfStream || target is! PdfRef) return null;
  return (ref: target, stream: stream);
}

void _flattenPage(_Ctx c, _PageEdit e) {
  final file = c.file;
  final raws = file.list(e.info.dict['Annots']);
  if (raws.isEmpty) return;
  final keep = <PdfObj>[];
  var k = 0;
  for (final raw in raws) {
    final a = file.dict(raw);
    if (a == null) {
      keep.add(raw);
      continue;
    }
    final subtype = _nameOf(file, a['Subtype']);
    if (subtype == 'Link') {
      keep.add(raw);
      continue;
    }
    final look = _flattenable(file, a);
    final rect = file.numbers(a['Rect'], 4);
    if (look == null || rect == null) continue;
    final dict = look.stream.dict;
    final bbox = file.numbers(dict['BBox'], 4);
    if (bbox == null) continue;
    final m = file.numbers(dict['Matrix'], 6) ?? const [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
    final xs = <double>[], ys = <double>[];
    for (final (x, y) in [(bbox[0], bbox[1]), (bbox[2], bbox[1]), (bbox[2], bbox[3]), (bbox[0], bbox[3])]) {
      xs.add(m[0] * x + m[2] * y + m[4]);
      ys.add(m[1] * x + m[3] * y + m[5]);
    }
    final tl = xs.reduce(math.min), tb = ys.reduce(math.min), tr = xs.reduce(math.max), tt = ys.reduce(math.max);
    final rl = math.min(rect[0], rect[2]), rb = math.min(rect[1], rect[3]), rr = math.max(rect[0], rect[2]), rt = math.max(rect[1], rect[3]);
    if (tr - tl <= 0 || tt - tb <= 0 || rr - rl <= 0 || rt - rb <= 0) continue;
    final sx = (rr - rl) / (tr - tl), sy = (rt - rb) / (tt - tb);
    if (dict['Subtype'] == null) dict['Subtype'] = const PdfName('Form');
    final name = 'SVFlat${++k}';
    e.xobjects[name] = look.ref;
    e.ops.write('q ${_n(sx)} 0 0 ${_n(sy)} ${_n(rl - tl * sx)} ${_n(rb - tb * sy)} cm /$name Do Q\n');
  }
  e.annots = keep;
}

// endregion
