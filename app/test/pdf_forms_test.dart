import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:doculoom/features/pdf_tools/data/forms/pdf_forms_engine.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_page_tools.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_model.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_rewriter.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_forms.dart';
import 'package:doculoom/features/reader/data/pdf_page_reader.dart';

import 'support/pdf_builder.dart';

String hexOf(String s) => s.codeUnits.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

PdfReader read(Uint8List bytes) => PdfReader(readPdfDocument(bytes));

/// Everything a page draws, as text.
String contentOf(PdfReader file, int page) {
  final info = file.pages()[page];
  final c = file.res(info.dict['Contents']);
  final parts = c is PdfArray ? c.items : [info.dict['Contents']!];
  return parts.map((p) => latin1.decode(file.decoded(p) ?? Uint8List(0))).join('\n');
}

FormFieldInfo fieldNamed(PdfFormInfo info, String name, {int widget = 0}) =>
    [for (final p in info.pages) ...p.fields].firstWhere((f) => f.name == name && f.widget == widget);

void main() {
  group('reading a form', () {
    test('finds text, check box, radio and drop-down boxes with their place on the shown page', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'name', [100, 700, 300, 720], value: 'Asha');
      t.checkbox(page, 'agree', [100, 600, 114, 614], on: true);
      t.radio(page, 'size', [
        ('S', [100, 500, 112, 512]),
        ('L', [140, 500, 152, 512]),
      ], chosen: 'L');
      t.combo(page, 'city', [100, 400, 250, 420], [('PNQ', 'Pune'), ('BOM', 'Mumbai')], value: 'BOM');
      final info = readPdfForm(t.finish());

      expect(info.hasFields, isTrue);
      expect(info.fieldCount, 4);
      final name = fieldNamed(info, 'name');
      expect(name.kind, FormFieldKind.text);
      expect(name.value, 'Asha');
      expect(name.box.left, closeTo(100 / 612, 0.001));
      expect(name.box.top, closeTo(1 - 720 / 792, 0.001));
      expect(name.box.right, closeTo(300 / 612, 0.001));
      expect(fieldNamed(info, 'agree').checked, isTrue);
      final s = fieldNamed(info, 'size', widget: 0), l = fieldNamed(info, 'size', widget: 1);
      expect([s.option, l.option], ['S', 'L']);
      expect(s.value, 'L');
      expect(s.options.map((o) => o.value), ['S', 'L']);
      final city = fieldNamed(info, 'city');
      expect(city.kind, FormFieldKind.choice);
      expect(city.options.map((o) => o.label), ['Pune', 'Mumbai']);
      expect(city.value, 'BOM');
      expect(info.pages.single.aspect, closeTo(612 / 792, 0.001));
      expect(info.pages.single.widthPt, 612);
    });

    test('a PDF without a form has no fields and nothing to flatten', () {
      final t = TestPdf()..page();
      final info = readPdfForm(t.finish());
      expect(info.hasFields, isFalse);
      expect(info.notes, 0);
    });

    test('hidden boxes and push buttons are not offered, and links are not counted as notes', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'shown', [10, 10, 100, 30]);
      final hidden = t.textField(page, 'hidden', [10, 40, 100, 60]);
      (t.objects[hidden.number]! as PdfDict)['F'] = const PdfInt(2);
      t.link(page, [0, 0, 50, 50]);
      final info = readPdfForm(t.finish());
      expect(info.pages.single.fields.map((f) => f.name), ['shown']);
      expect(info.notes, 0);
    });

    test('on a turned page the boxes are placed as the page is shown', () {
      final t = TestPdf();
      final page = t.page(rotate: 90);
      t.textField(page, 'a', [0, 0, 100, 50]);
      final info = readPdfForm(t.finish());
      expect(info.pages.single.aspect, closeTo(792 / 612, 0.001));
      final box = fieldNamed(info, 'a').box;
      // The bottom left corner of an upright page is the top left of a page turned a quarter clockwise.
      expect(box.left, closeTo(0, 0.001));
      expect(box.top, closeTo(0, 0.001));
      expect(box.width, closeTo(50 / 792, 0.001));
      expect(box.height, closeTo(100 / 612, 0.001));
    });

    test('a file that is not a PDF is refused', () {
      expect(() => readPdfForm(Uint8List.fromList(utf8.encode('hello'))), throwsA(isA<PdfFormatException>()));
    });
  });

  test('a form made by another program (the pdf package) is read, filled and flattened', () async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (_) => pw.Column(
          children: [
            pw.Text('Registration'),
            pw.SizedBox(height: 20),
            pw.TextField(name: 'full_name', width: 200, height: 24),
            pw.SizedBox(height: 20),
            pw.Checkbox(name: 'newsletter', value: false, width: 16, height: 16),
          ],
        ),
      ),
    );
    final bytes = Uint8List.fromList(await doc.save());
    final info = readPdfForm(bytes);
    expect(info.fieldCount, 2);
    final name = fieldNamed(info, 'full_name');
    final tick = fieldNamed(info, 'newsletter');
    final filled = applyPdfFormPlan(bytes, PdfFormPlan(values: {name.id: 'Asha Rao', tick.id: 'on'}));
    final again = readPdfForm(filled);
    expect(fieldNamed(again, 'full_name').value, 'Asha Rao');
    expect(fieldNamed(again, 'newsletter').checked, isTrue);
    final flat = applyPdfFormPlan(filled, const PdfFormPlan(flatten: true));
    expect(readPdfForm(flat).hasFields, isFalse);
    expect(contentOf(read(flat), 0), contains('Do'));
  });

  group('filling', () {
    test('text goes into the field and into a new look that shows it', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'name', [100, 700, 300, 720]);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(values: {0: 'Asha Rao'}));

      final info = readPdfForm(out);
      expect(fieldNamed(info, 'name').value, 'Asha Rao');
      final file = read(out);
      final widget = file.dict(file.list(file.pages().single.dict['Annots']).single)!;
      final look = file.res(file.dict(widget['AP'])!['N'])! as PdfStream;
      final stream = latin1.decode(file.decoded(file.dict(widget['AP'])!['N'])!);
      expect(stream, contains(hexOf('Asha Rao')));
      expect(stream, contains('/Helv'));
      expect(stream, contains('re S'), reason: 'the border is kept');
      expect(look.dict.nameOf('Subtype'), 'Form');
    });

    test('latin letters with accents are accepted; other scripts are refused with a clear message', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'name', [100, 700, 300, 720]);
      final bytes = t.finish();
      expect(readPdfForm(applyPdfFormPlan(bytes, const PdfFormPlan(values: {0: 'José Müller'}))).pages.single.fields.single.value, 'José Müller');
      expect(
        () => applyPdfFormPlan(bytes, const PdfFormPlan(values: {0: 'आशा'})),
        throwsA(isA<PdfFormException>().having((e) => e.message, 'message', contains('cannot be placed'))),
      );
    });

    test('a long text is made smaller to fit one line, and a multi-line box wraps', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'one', [100, 700, 160, 720]);
      t.textField(page, 'many', [100, 500, 200, 600], flags: 4096);
      final out = applyPdfFormPlan(
        t.finish(),
        const PdfFormPlan(values: {0: 'A very long sentence that cannot fit', 1: 'one two three four five six seven eight nine ten'}),
      );
      final file = read(out);
      String lookOf(int i) {
        final w = file.dict(file.list(file.pages().single.dict['Annots'])[i])!;
        return latin1.decode(file.decoded(file.dict(w['AP'])!['N'])!);
      }

      final size = double.parse(RegExp(r'/Helv ([\d.]+) Tf').firstMatch(lookOf(0))!.group(1)!);
      expect(size, lessThan(12));
      expect(size, greaterThanOrEqualTo(4));
      expect(RegExp(r'Tm <').allMatches(lookOf(1)).length, greaterThan(1), reason: 'wrapped into lines');
    });

    test('a maximum length cuts the text', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'code', [100, 700, 200, 720], maxLen: 4);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(values: {0: 'ABCDEFG'}));
      expect(fieldNamed(readPdfForm(out), 'code').value, 'ABCD');
    });

    test('a check box is switched on and off', () {
      final t = TestPdf();
      final page = t.page();
      t.checkbox(page, 'agree', [100, 600, 114, 614]);
      final bytes = t.finish();
      final on = applyPdfFormPlan(bytes, const PdfFormPlan(values: {0: 'on'}));
      expect(fieldNamed(readPdfForm(on), 'agree').checked, isTrue);
      final off = applyPdfFormPlan(on, const PdfFormPlan(values: {0: 'off'}));
      expect(fieldNamed(readPdfForm(off), 'agree').checked, isFalse);
    });

    test('a check box with no looks of its own gets a tick', () {
      final t = TestPdf();
      final page = t.page();
      t.checkbox(page, 'agree', [100, 600, 114, 614], withLook: false);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(values: {0: 'on'}));
      expect(fieldNamed(readPdfForm(out), 'agree').checked, isTrue);
      final file = read(out);
      final widget = file.dict(file.list(file.pages().single.dict['Annots']).single)!;
      final n = file.dict(file.dict(widget['AP'])!['N'])!;
      expect(n.entries.keys, containsAll(['Yes', 'Off']));
    });

    test('choosing one radio button clears the others, and an unknown choice is refused', () {
      final t = TestPdf();
      final page = t.page();
      t.radio(page, 'size', [
        ('S', [100, 500, 112, 512]),
        ('L', [140, 500, 152, 512]),
      ], chosen: 'S');
      final bytes = t.finish();
      final out = applyPdfFormPlan(bytes, const PdfFormPlan(values: {0: 'L'}));
      final info = readPdfForm(out);
      expect(fieldNamed(info, 'size').value, 'L');
      final file = read(out);
      final states = [for (final raw in file.list(file.pages().single.dict['Annots'])) (file.dict(raw)!['AS']! as PdfName).name];
      expect(states, ['Off', 'L']);
      expect(() => applyPdfFormPlan(bytes, const PdfFormPlan(values: {0: 'XL'})), throwsA(isA<PdfFormException>()));
    });

    test('a drop-down stores the value and shows its label', () {
      final t = TestPdf();
      final page = t.page();
      t.combo(page, 'city', [100, 400, 250, 420], [('PNQ', 'Pune'), ('BOM', 'Mumbai')]);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(values: {0: 'PNQ'}));
      expect(fieldNamed(readPdfForm(out), 'city').value, 'PNQ');
      final file = read(out);
      final widget = file.dict(file.list(file.pages().single.dict['Annots']).single)!;
      expect(latin1.decode(file.decoded(file.dict(widget['AP'])!['N'])!), contains(hexOf('Pune')));
    });

    test('fields that are not mentioned keep their value', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'a', [10, 10, 100, 30], value: 'one');
      t.textField(page, 'b', [10, 40, 100, 60], value: 'two');
      final info = readPdfForm(applyPdfFormPlan(t.finish(), const PdfFormPlan(values: {1: 'changed'})));
      expect(fieldNamed(info, 'a').value, 'one');
      expect(fieldNamed(info, 'b').value, 'changed');
    });

    test('the text of the page is left as it was', () {
      final t = TestPdf();
      final page = t.page(text: 'Application form');
      t.textField(page, 'a', [10, 10, 100, 30]);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(values: {0: 'x'}));
      expect(contentOf(read(out), 0), contains('(Application form) Tj'));
    });
  });

  group('marks', () {
    test('text, a date, a tick and a cross are drawn on the chosen page only', () {
      final t = TestPdf();
      t.page();
      t.page();
      final out = applyPdfFormPlan(
        t.finish(),
        const PdfFormPlan(
          marks: [
            PdfMark(page: 1, u: 0.25, v: 0.5, kind: MarkKind.text, text: '25 Oct 2026', sizePt: 12),
            PdfMark(page: 1, u: 0.5, v: 0.5, kind: MarkKind.tick, sizePt: 14),
            PdfMark(page: 1, u: 0.6, v: 0.5, kind: MarkKind.cross, sizePt: 14),
          ],
        ),
      );
      final file = read(out);
      expect(contentOf(file, 0), isNot(contains(hexOf('25 Oct 2026'))));
      final second = contentOf(file, 1);
      expect(second, contains(hexOf('25 Oct 2026')));
      expect(second, contains(' l S Q'));
      expect(second, contains('(Hello secret) Tj'));
      expect(file.pages(), hasLength(2));
    });

    test('text starts where it was put: x from the left and y from the top of the shown page', () {
      final t = TestPdf();
      t.page();
      final out = applyPdfFormPlan(
        t.finish(),
        const PdfFormPlan(
          marks: [PdfMark(page: 0, u: 0.5, v: 0.25, kind: MarkKind.text, text: 'x', sizePt: 10)],
        ),
      );
      final c = contentOf(read(out), 0);
      final tm = RegExp(r'([\d.]+) ([\d.-]+) ([\d.-]+) ([\d.]+) ([\d.]+) ([\d.]+) Tm').firstMatch(c)!;
      expect(double.parse(tm.group(5)!), closeTo(306, 0.5));
      expect(double.parse(tm.group(6)!), closeTo(792 - 0.25 * 792 - 3, 0.5));
    });

    test('on a turned page the mark is turned with it', () {
      final t = TestPdf();
      t.page(rotate: 90);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(marks: [PdfMark(page: 0, u: 0.5, v: 0.5, kind: MarkKind.tick, sizePt: 10)]));
      expect(contentOf(read(out), 0), contains('0 1 -1 0 '));
    });

    test('a mark on a page that does not exist, or text that cannot be written, is refused', () {
      final t = TestPdf()..page();
      final bytes = t.finish();
      expect(() => applyPdfFormPlan(bytes, const PdfFormPlan(marks: [PdfMark(page: 3, u: 0, v: 0, kind: MarkKind.tick)])), throwsA(isA<PdfFormException>()));
      expect(
        () => applyPdfFormPlan(
          bytes,
          const PdfFormPlan(
            marks: [PdfMark(page: 0, u: 0, v: 0, kind: MarkKind.text, text: '日本')],
          ),
        ),
        throwsA(isA<PdfFormException>()),
      );
    });
  });

  group('flattening', () {
    test('form boxes and notes become part of the page and the form goes away', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'name', [100, 700, 300, 720]);
      t.stamp(page, [400, 600, 450, 650]);
      t.link(page, [0, 0, 50, 50]);
      final filled = applyPdfFormPlan(t.finish(), const PdfFormPlan(values: {0: 'Asha'}));
      expect(readPdfForm(filled).notes, 2);

      final out = applyPdfFormPlan(filled, const PdfFormPlan(flatten: true));
      final file = read(out);
      final info = file.pages().single;
      final left = file.list(info.dict['Annots']).map((a) => (file.dict(a)!['Subtype']! as PdfName).name).toList();
      expect(left, ['Link'], reason: 'only the link is kept');
      expect(file.dict(file.doc.trailer['Root'])!['AcroForm'], isNull);
      final content = contentOf(file, 0);
      expect(RegExp(r'/SVFlat\d+ Do').allMatches(content).length, 2);
      expect(content, contains('(Hello secret) Tj'));
      expect(file.dict(file.dict(info.dict['Resources'])!['XObject'])!.entries.keys, containsAll(['SVFlat1', 'SVFlat2']));
      final again = readPdfForm(out);
      expect(again.hasFields, isFalse);
      expect(again.notes, 0);
    });

    test('a note is scaled to its place: a look drawn at another size fills the box of the note', () {
      final t = TestPdf();
      final page = t.page();
      t.stamp(page, [100, 100, 300, 200]);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(flatten: true));
      // The look is 200 x 100 and the box is 200 x 100, so it is placed without scaling, at the corner of the box.
      expect(contentOf(read(out), 0), contains('q 1 0 0 1 100 100 cm /SVFlat1 Do Q'));
    });

    test('empty boxes and hidden notes disappear without leaving a mark', () {
      final t = TestPdf();
      final page = t.page();
      t.checkbox(page, 'agree', [100, 600, 114, 614], withLook: false);
      final out = applyPdfFormPlan(t.finish(), const PdfFormPlan(flatten: true));
      final file = read(out);
      expect(file.list(file.pages().single.dict['Annots']), isEmpty);
      expect(contentOf(file, 0), isNot(contains(' Do')));
    });

    test('values, marks and flattening work together', () {
      final t = TestPdf();
      final page = t.page();
      t.textField(page, 'name', [100, 700, 300, 720]);
      t.checkbox(page, 'agree', [100, 600, 114, 614]);
      final out = applyPdfFormPlan(
        t.finish(),
        const PdfFormPlan(
          values: {0: 'Asha', 1: 'on'},
          marks: [PdfMark(page: 0, u: 0.5, v: 0.8, kind: MarkKind.text, text: 'Pune')],
          flatten: true,
        ),
      );
      final content = contentOf(read(out), 0);
      expect(RegExp(r'/SVFlat\d+ Do').allMatches(content).length, 2);
      expect(content, contains(hexOf('Pune')));
      expect(readPdfForm(out).hasFields, isFalse);
    });
  });

  group('cropping', () {
    Map<String, double> box(Uint8List bytes, int page) {
      final file = read(bytes);
      final b = file.numbers(file.pages()[page].dict['CropBox'], 4)!;
      return {'x0': b[0], 'y0': b[1], 'x1': b[2], 'y1': b[3]};
    }

    test('an upright page loses the shares cut from each side', () {
      final t = TestPdf()..page();
      final out = cropPdfPages(t.finish(), {0: const CropInsets(left: 0.1, top: 0.2, right: 0.05, bottom: 0.25)});
      final b = box(out, 0);
      expect(b['x0'], closeTo(61.2, 0.01));
      expect(b['x1'], closeTo(612 - 30.6, 0.01));
      expect(b['y1'], closeTo(792 - 158.4, 0.01));
      expect(b['y0'], closeTo(198, 0.01));
    });

    test('a page turned a quarter cuts the sides of its own box that are shown on those sides', () {
      final t = TestPdf()..page(rotate: 90);
      // Shown: left edge is the bottom of the page box, top edge is the left of the page box.
      final out = cropPdfPages(t.finish(), {0: const CropInsets(left: 0.1, top: 0.2)});
      final b = box(out, 0);
      expect(b['y0'], closeTo(79.2, 0.01));
      expect(b['x0'], closeTo(122.4, 0.01));
      expect(b['x1'], 612);
      expect(b['y1'], 792);
    });

    test('other pages and the page text are untouched', () {
      final t = TestPdf()
        ..page()
        ..page(text: 'second');
      final out = cropPdfPages(t.finish(), {1: const CropInsets(left: 0.1)});
      final file = read(out);
      expect(file.pages()[0].dict['CropBox'], isNull);
      expect(file.pages()[1].dict['CropBox'], isNotNull);
      expect(contentOf(file, 1), contains('(second) Tj'));
      expect(file.pages(), hasLength(2));
    });

    test('cutting everything, a bad page or nothing at all is handled', () {
      final t = TestPdf()..page();
      final bytes = t.finish();
      expect(() => cropPdfPages(bytes, {0: const CropInsets(left: 0.6, right: 0.6)}), throwsA(isA<PdfFormException>()));
      expect(() => cropPdfPages(bytes, {5: const CropInsets(left: 0.1)}), throwsA(isA<PdfFormException>()));
      final same = cropPdfPages(bytes, {0: const CropInsets()});
      expect(read(same).pages().single.dict['CropBox'], isNull);
    });

    test('cropping twice cuts from what is already shown', () {
      final t = TestPdf()..page();
      final once = cropPdfPages(t.finish(), {0: const CropInsets(left: 0.5)});
      final twice = cropPdfPages(once, {0: const CropInsets(left: 0.5)});
      expect(box(twice, 0)['x0'], closeTo(306 + 153, 0.01));
    });
  });

  group('pictures inside a PDF', () {
    PdfStream flatePicture(
      int w,
      int h,
      int Function(int x, int y, int c) sample, {
      String space = 'DeviceRGB',
      int comps = 3,
      Map<String, PdfObj> extra = const {},
    }) {
      final data = Uint8List(w * h * comps);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          for (var c = 0; c < comps; c++) {
            data[(y * w + x) * comps + c] = sample(x, y, c);
          }
        }
      }
      return PdfStream(
        PdfDict({
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Image'),
          'Width': PdfInt(w),
          'Height': PdfInt(h),
          'ColorSpace': PdfName(space),
          'BitsPerComponent': const PdfInt(8),
          'Filter': const PdfName('FlateDecode'),
          ...extra,
        }),
        Uint8List.fromList(zlib.encode(data)),
      );
    }

    test('a JPEG comes out unchanged, a flate picture is rebuilt as PNG, tiny ones are ignored', () {
      final t = TestPdf();
      final photo = img.Image(width: 40, height: 30);
      img.fill(photo, color: img.ColorRgb8(200, 50, 50));
      final jpg = Uint8List.fromList(img.encodeJpg(photo));
      final jpgRef = t.add(
        PdfStream(
          PdfDict({
            'Type': const PdfName('XObject'),
            'Subtype': const PdfName('Image'),
            'Width': const PdfInt(40),
            'Height': const PdfInt(30),
            'ColorSpace': const PdfName('DeviceRGB'),
            'BitsPerComponent': const PdfInt(8),
            'Filter': const PdfName('DCTDecode'),
          }),
          jpg,
        ),
      );
      final rgbRef = t.add(flatePicture(32, 32, (x, y, c) => c == 0 ? 255 : 0));
      final tinyRef = t.add(flatePicture(8, 8, (x, y, c) => 0));
      t.page(xobjects: {'Im1': jpgRef, 'Im2': rgbRef, 'Im3': tinyRef});

      final r = extractPdfPictures(t.finish());
      expect(r.pictures, hasLength(2));
      expect(r.skipped, 0);
      final first = r.pictures.firstWhere((p) => p.extension == 'jpg');
      expect(first.bytes, jpg);
      expect([first.width, first.height], [40, 30]);
      final png = r.pictures.firstWhere((p) => p.extension == 'png');
      final decoded = img.decodePng(png.bytes)!;
      expect(decoded.width, 32);
      final px = decoded.getPixel(5, 5);
      expect([px.r, px.g, px.b], [255, 0, 0]);
    });

    test('grey, indexed and see-through pictures are rebuilt with their colours', () {
      final t = TestPdf();
      final grey = t.add(flatePicture(30, 30, (x, y, c) => x * 8, space: 'DeviceGray', comps: 1));
      final palette = Uint8List.fromList([255, 0, 0, 0, 255, 0]);
      final indexedStream = PdfStream(
        PdfDict({
          'Type': const PdfName('XObject'),
          'Subtype': const PdfName('Image'),
          'Width': const PdfInt(30),
          'Height': const PdfInt(30),
          'ColorSpace': PdfArray([const PdfName('Indexed'), const PdfName('DeviceRGB'), const PdfInt(1), PdfString(palette)]),
          'BitsPerComponent': const PdfInt(8),
          'Filter': const PdfName('FlateDecode'),
        }),
        Uint8List.fromList(zlib.encode(Uint8List.fromList([for (var i = 0; i < 900; i++) i % 30 < 15 ? 0 : 1]))),
      );
      final indexed = t.add(indexedStream);
      final mask = t.add(flatePicture(30, 30, (x, y, c) => x < 15 ? 255 : 0, space: 'DeviceGray', comps: 1));
      final seeThrough = t.add(flatePicture(30, 30, (x, y, c) => 100, extra: {'SMask': mask}));
      t.page(xobjects: {'A': grey, 'B': indexed, 'C': seeThrough});

      final r = extractPdfPictures(t.finish());
      expect(r.pictures, hasLength(3));
      final decoded = [for (final p in r.pictures) img.decodePng(p.bytes)!];
      final withAlpha = decoded.firstWhere((d) => d.numChannels == 4);
      expect(withAlpha.getPixel(2, 2).a, 255);
      expect(withAlpha.getPixel(25, 2).a, 0);
      final colour = decoded.firstWhere((d) => d.numChannels == 3 && d.getPixel(2, 2).r == 255);
      expect(colour.getPixel(20, 2).g, 255);
    });

    test('a picture in a form of the page is found, repeated ones are saved once, and the page number is the first that shows it', () {
      final t = TestPdf();
      final shared = t.add(flatePicture(30, 30, (x, y, c) => 50));
      final form = t.add(
        PdfStream(
          PdfDict({
            'Type': const PdfName('XObject'),
            'Subtype': const PdfName('Form'),
            'BBox': pdfNums([0, 0, 100, 100]),
            'Resources': PdfDict({
              'XObject': PdfDict({'Inner': shared}),
            }),
          }),
          Uint8List(0),
        ),
      );
      t.page(xobjects: {'Fm': form});
      t.page(xobjects: {'Again': shared});
      final r = extractPdfPictures(t.finish());
      expect(r.pictures, hasLength(1));
      expect(r.pictures.single.page, 1);
    });

    test('a picture in a form that cannot be rebuilt is counted as skipped', () {
      final t = TestPdf();
      final fax = t.add(
        PdfStream(
          PdfDict({
            'Type': const PdfName('XObject'),
            'Subtype': const PdfName('Image'),
            'Width': const PdfInt(64),
            'Height': const PdfInt(64),
            'ColorSpace': const PdfName('DeviceGray'),
            'BitsPerComponent': const PdfInt(1),
            'Filter': const PdfName('CCITTFaxDecode'),
          }),
          Uint8List(16),
        ),
      );
      t.page(xobjects: {'Scan': fax});
      final r = extractPdfPictures(t.finish());
      expect(r.pictures, isEmpty);
      expect(r.skipped, 1);
    });

    test('a PDF with no pictures gives an empty list', () {
      final t = TestPdf()..page();
      final r = extractPdfPictures(t.finish());
      expect(r.pictures, isEmpty);
      expect(r.skipped, 0);
    });
  });
}
