import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/features/signature/data/document_signer.dart';
import 'package:doculoom/features/signature/data/signature_processor.dart';
import 'package:doculoom/features/signature/data/signature_store.dart';
import 'package:doculoom/features/signature/domain/signature.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sv_sig'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A photo of paper with uneven light and a curved line of dark ink.
  String paperPhoto(String name, {int ink = 40, bool withInk = true, bool shade = true, int w = 800, int h = 500}) {
    final image = img.Image(width: w, height: h, numChannels: 3);
    for (final px in image) {
      final light = shade ? 245 - (px.x / w * 45).round() : 240;
      px
        ..r = light
        ..g = light
        ..b = light - 4;
    }
    if (withInk) {
      for (var x = 150; x < 650; x++) {
        final y = 250 + (math.sin(x / 40) * 60).round();
        img.fillCircle(image, x: x, y: y, radius: 5, color: img.ColorRgb8(ink, ink, ink + 30));
      }
    }
    final path = p.join(dir.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 92));
    return path;
  }

  img.Image load(String path) => img.decodePng(File(path).readAsBytesSync())!;

  group('signature from a photo', () {
    const maker = SignatureProcessor();

    test('keeps the ink, makes the paper transparent and cuts to the signature', () async {
      final r = (await maker.fromPhoto(
        sourcePath: paperPhoto('a.jpg'),
        outputPath: p.join(dir.path, 'a.png'),
        sensitivity: 0.5,
        ink: InkColor.black,
      )).valueOrNull!;
      final png = load(r.path);
      expect((png.width, png.height), (r.width, r.height));
      expect(png.width, lessThan(560), reason: 'cut to the ink');
      expect(png.width, greaterThan(480));
      expect(png.height, lessThan(200));
      expect(png.numChannels, 4);
      // Corners are paper: transparent. Somewhere along the line there is solid ink.
      expect(png.getPixel(0, 0).a, 0);
      expect(png.getPixel(png.width - 1, png.height - 1).a, 0);
      var solid = 0, clear = 0;
      for (final px in png) {
        if (px.a > 230) solid++;
        if (px.a == 0) clear++;
      }
      expect(solid, greaterThan(1500));
      expect(clear, greaterThan(png.width * png.height ~/ 2));
    });

    test('shadows and uneven light do not leave a grey box', () async {
      final r = (await maker.fromPhoto(sourcePath: paperPhoto('s.jpg', shade: true), outputPath: p.join(dir.path, 's.png'), sensitivity: 0.5)).valueOrNull!;
      final png = load(r.path);
      var faint = 0;
      for (final px in png) {
        if (px.a > 20 && px.a < 120) faint++;
      }
      // Only the soft edges of the line may be partly see-through, not the paper.
      expect(faint, lessThan(png.width * png.height ~/ 5));
    });

    test('the pen colour can be changed or kept', () async {
      final src = paperPhoto('c.jpg');
      final blue = load(
        (await maker.fromPhoto(sourcePath: src, outputPath: p.join(dir.path, 'blue.png'), sensitivity: 0.5, ink: InkColor.blue)).valueOrNull!.path,
      );
      final solidBlue = blue.where((px) => px.a == 255).first;
      expect((solidBlue.r.toInt(), solidBlue.g.toInt(), solidBlue.b.toInt()), (0x1B, 0x3F, 0xA0));
      final kept = load((await maker.fromPhoto(sourcePath: src, outputPath: p.join(dir.path, 'kept.png'), sensitivity: 0.5)).valueOrNull!.path);
      final k = kept.where((px) => px.a == 255).first;
      expect(k.b, greaterThan(k.r), reason: 'the photo pen was bluish and stays bluish');
      expect(k.r, lessThan(120));
    });

    test('higher sensitivity picks up fainter ink', () async {
      final src = paperPhoto('f.jpg', ink: 150);
      final low = load((await maker.fromPhoto(sourcePath: src, outputPath: p.join(dir.path, 'lo.png'), sensitivity: 0)).valueOrNull!.path);
      final high = load((await maker.fromPhoto(sourcePath: src, outputPath: p.join(dir.path, 'hi.png'), sensitivity: 1)).valueOrNull!.path);
      int total(img.Image i) => i.fold<int>(0, (sum, px) => sum + px.a.toInt());
      expect(total(high), greaterThan(total(low)));
    });

    test('a photo of empty paper says no signature was found', () async {
      final r = await maker.fromPhoto(sourcePath: paperPhoto('e.jpg', withInk: false), outputPath: p.join(dir.path, 'e.png'), sensitivity: 0.5);
      expect(r.failureOrNull!.message, contains('No signature found'));
    });

    test('a file that is not a photo is reported', () async {
      final bad = File(p.join(dir.path, 'bad.jpg'))..writeAsBytesSync([1, 2, 3]);
      final r = await maker.fromPhoto(sourcePath: bad.path, outputPath: p.join(dir.path, 'bad.png'), sensitivity: 0.5);
      expect(r.failureOrNull!.message, contains('could not be read'));
    });
  });

  group('signature from drawing', () {
    const maker = SignatureProcessor();

    Stroke line(double x0, double y0, double x1, double y1, {int n = 20}) =>
        Stroke([for (var i = 0; i <= n; i++) (x: x0 + (x1 - x0) * i / n, y: y0 + (y1 - y0) * i / n)]);

    test('draws the strokes as a transparent PNG cut to the ink', () async {
      final r = (await maker.fromStrokes(
        strokes: [line(40, 60, 200, 100), line(60, 120, 220, 70)],
        padWidth: 340,
        padHeight: 180,
        penWidth: 3,
        ink: InkColor.blue,
        outputPath: p.join(dir.path, 'd.png'),
      )).valueOrNull!;
      final png = load(r.path);
      expect(png.width, lessThan(340 * 3));
      expect(png.width, greaterThan(150 * 3));
      expect(png.getPixel(0, 0).a, 0);
      final solid = png.where((px) => px.a == 255).first;
      expect((solid.r.toInt(), solid.g.toInt(), solid.b.toInt()), (0x1B, 0x3F, 0xA0));
    });

    test('a thicker pen gives more ink', () async {
      Future<int> ink(double pen) async {
        final r = (await maker.fromStrokes(
          strokes: [line(20, 20, 200, 20)],
          padWidth: 240,
          padHeight: 60,
          penWidth: pen,
          ink: InkColor.black,
          outputPath: p.join(dir.path, 'pen$pen.png'),
        )).valueOrNull!;
        return load(r.path).fold<int>(0, (sum, px) => sum + px.a.toInt());
      }

      expect(await ink(6), greaterThan(await ink(2) * 2));
    });

    test('a single tap is a dot and curves work', () async {
      final dot = await maker.fromStrokes(
        strokes: const [
          Stroke([(x: 50.0, y: 50.0)]),
        ],
        padWidth: 100,
        padHeight: 100,
        penWidth: 4,
        ink: InkColor.black,
        outputPath: p.join(dir.path, 'dot.png'),
      );
      expect(dot.valueOrNull, isNotNull);
      final curve = Stroke([for (var i = 0; i < 40; i++) (x: 20.0 + i * 5, y: 60 + math.sin(i / 4) * 30)]);
      final c = await maker.fromStrokes(
        strokes: [curve],
        padWidth: 240,
        padHeight: 120,
        penWidth: 3,
        ink: InkColor.black,
        outputPath: p.join(dir.path, 'curve.png'),
      );
      expect(c.valueOrNull, isNotNull);
    });

    test('nothing drawn gives a clear message', () async {
      final r = await maker.fromStrokes(
        strokes: const [],
        padWidth: 300,
        padHeight: 150,
        penWidth: 3,
        ink: InkColor.black,
        outputPath: p.join(dir.path, 'none.png'),
      );
      expect(r.failureOrNull!.message, 'Draw your signature first.');
      final empty = await maker.fromStrokes(
        strokes: const [Stroke([])],
        padWidth: 300,
        padHeight: 150,
        penWidth: 3,
        ink: InkColor.black,
        outputPath: p.join(dir.path, 'none2.png'),
      );
      expect(empty.failureOrNull, isNotNull);
    });
  });

  group('store', () {
    late SignatureStoreImpl store;
    late String png;

    setUp(() {
      store = SignatureStoreImpl(appDir: () async => dir);
      png = p.join(dir.path, 'sig.png');
      File(png).writeAsBytesSync(img.encodePng(img.Image(width: 120, height: 40, numChannels: 4)));
    });

    test('starts empty and keeps what is saved, with sizes', () async {
      expect(await store.list(), isEmpty);
      final saved = (await store.save(png)).valueOrNull!;
      expect((saved.width, saved.height), (120, 40));
      expect(saved.aspect, 3);
      final list = await store.list();
      expect(list.single.id, saved.id);
      expect(File(list.single.path).existsSync(), isTrue);
    });

    test('keeps at most twenty and says how to make room', () async {
      for (var i = 0; i < SignatureStore.maxSaved; i++) {
        expect((await store.save(png)).failureOrNull, isNull);
      }
      final extra = await store.save(png);
      expect(extra.failureOrNull!.message, contains('up to 20 signatures'));
      final first = (await store.list()).first;
      await store.delete(first.id);
      expect((await store.save(png)).valueOrNull, isNotNull);
    });

    test('delete and delete all remove the files', () async {
      final a = (await store.save(png)).valueOrNull!;
      await store.save(png);
      await store.delete(a.id);
      expect((await store.list()).length, 1);
      await store.deleteAll();
      expect(await store.list(), isEmpty);
      await store.deleteAll();
      await store.delete('missing');
    });

    test('a file that is not a picture is refused and not kept', () async {
      final bad = File(p.join(dir.path, 'bad.png'))..writeAsBytesSync([1, 2, 3]);
      final r = await store.save(bad.path);
      expect(r.failureOrNull, isNotNull);
      expect(await store.list(), isEmpty);
    });

    test('a damaged saved file is skipped', () async {
      await store.save(png);
      File(p.join(dir.path, 'signatures', 'zzz.png')).writeAsBytesSync([9, 9]);
      expect((await store.list()).length, 1);
    });

    group('library', () {
      test('the first of each kind is the default, and names are cleaned', () async {
        final a = (await store.save(png, name: '  Work   copy  ')).valueOrNull!;
        final b = (await store.save(png)).valueOrNull!;
        final i = (await store.save(png, kind: SignatureKind.initials, name: 'x' * 60)).valueOrNull!;
        final list = await store.list();
        expect([for (final s in list) s.id], [a.id, b.id, i.id]);
        expect([for (final s in list) s.isDefault], [true, false, true]);
        expect(list.first.name, 'Work copy');
        expect(list.last.kind, SignatureKind.initials);
        expect(list.last.name.length, 40);
      });

      test('setDefault moves the star within its kind only', () async {
        final a = (await store.save(png)).valueOrNull!;
        final b = (await store.save(png)).valueOrNull!;
        final i = (await store.save(png, kind: SignatureKind.initials)).valueOrNull!;
        await store.setDefault(b.id);
        final list = {for (final s in await store.list()) s.id: s};
        expect(list[a.id]!.isDefault, isFalse);
        expect(list[b.id]!.isDefault, isTrue);
        expect(list[i.id]!.isDefault, isTrue);
      });

      test('rename and change of kind are kept, and a moved kind gets a default', () async {
        final a = (await store.save(png)).valueOrNull!;
        final b = (await store.save(png)).valueOrNull!;
        await store.update(a.id, name: 'Mine', kind: SignatureKind.initials);
        var list = {for (final s in await store.list()) s.id: s};
        expect(list[a.id]!.name, 'Mine');
        expect(list[a.id]!.kind, SignatureKind.initials);
        expect(list[a.id]!.isDefault, isTrue);
        expect(list[b.id]!.isDefault, isTrue, reason: 'the only signature is the default');
        await store.update(a.id, name: '   ');
        list = {for (final s in await store.list()) s.id: s};
        expect(list[a.id]!.name, isEmpty);
        await store.update('missing', name: 'x');
      });

      test('move reorders and survives a new store over the same folder', () async {
        final ids = [for (var i = 0; i < 3; i++) (await store.save(png)).valueOrNull!.id];
        await store.move(ids[2], 0);
        expect([for (final s in await store.list()) s.id], [ids[2], ids[0], ids[1]]);
        await store.move(ids[2], 99);
        expect([for (final s in await store.list()) s.id], [ids[0], ids[1], ids[2]]);
        final again = SignatureStoreImpl(appDir: () async => dir);
        expect([for (final s in await again.list()) s.id], ids);
      });

      test('deleting the default hands the star to the next of its kind', () async {
        final a = (await store.save(png)).valueOrNull!;
        final b = (await store.save(png)).valueOrNull!;
        await store.delete(a.id);
        expect((await store.list()).single.id, b.id);
        expect((await store.list()).single.isDefault, isTrue);
      });

      test('recolor changes only the colour and keeps alpha, place and name', () async {
        final image = img.Image(width: 20, height: 10, numChannels: 4);
        img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
        image.setPixelRgba(5, 5, 200, 10, 10, 255);
        image.setPixelRgba(6, 5, 200, 10, 10, 90);
        final src = File(p.join(dir.path, 'ink.png'))..writeAsBytesSync(img.encodePng(image));
        final a = (await store.save(src.path, name: 'Red')).valueOrNull!;
        await store.save(png);
        final r = await store.recolor(a.id, InkColor.blue);
        expect(r.failureOrNull, isNull);
        final out = img.decodePng(File(a.path).readAsBytesSync())!;
        final solid = out.getPixel(5, 5), soft = out.getPixel(6, 5), blank = out.getPixel(0, 0);
        expect((solid.r, solid.g, solid.b, solid.a), (0x1B, 0x3F, 0xA0, 255));
        expect(soft.a, 90);
        expect(soft.b, 0xA0);
        expect(blank.a, 0);
        final list = await store.list();
        expect(list.first.id, a.id);
        expect(list.first.name, 'Red');
        expect((await store.recolor('missing', InkColor.black)).failureOrNull, isNotNull);
      });

      test('duplicate places a copy after the original and respects the limit', () async {
        final a = (await store.save(png, name: 'Work')).valueOrNull!;
        final b = (await store.save(png)).valueOrNull!;
        final copy = (await store.duplicate(a.id)).valueOrNull!;
        final list = await store.list();
        expect([for (final s in list) s.id], [a.id, copy.id, b.id]);
        expect(list[1].name, 'Work copy');
        expect(list[1].isDefault, isFalse);
        expect(File(list[1].path).existsSync(), isTrue);
        expect(list[1].path, isNot(a.path));
        while ((await store.list()).length < SignatureStore.maxSaved) {
          await store.save(png);
        }
        expect((await store.duplicate(a.id)).failureOrNull, isNotNull);
        expect((await store.duplicate('missing')).failureOrNull, isNotNull);
      });

      test('an unreadable index loses the names, not the pictures', () async {
        await store.save(png, name: 'Keep');
        File(p.join(dir.path, 'signatures', 'library.json')).writeAsStringSync('{ not json');
        final list = await store.list();
        expect(list.length, 1);
        expect(list.single.name, isEmpty);
        expect(list.single.isDefault, isTrue);
      });

      test('pictures saved before the library existed still show up', () async {
        final folder = Directory(p.join(dir.path, 'signatures'))..createSync();
        File(png).copySync(p.join(folder.path, '111_0.png'));
        File(png).copySync(p.join(folder.path, '222_1.png'));
        final list = await store.list();
        expect([for (final s in list) s.id], ['111_0', '222_1']);
        expect(list.first.isDefault, isTrue);
        expect(list.last.isDefault, isFalse);
      });
    });
  });

  group('placement', () {
    test('a signature is kept on the page', () {
      const far = SignPlacement(centerX: 1.4, centerY: -0.2, width: 0.3);
      final fitted = far.clamped(aspect: 3, pageAspect: 0.7);
      expect(fitted.centerX, closeTo(0.85, 0.0001));
      expect(fitted.centerY, greaterThan(0));
      expect(fitted.centerX + fitted.width / 2, lessThanOrEqualTo(1.0001));
    });

    test('the size is limited', () {
      expect(const SignPlacement(width: 5).clamped(aspect: 3, pageAspect: 0.7).width, SignPlacement.maxWidth);
      expect(const SignPlacement(width: 0.001).clamped(aspect: 3, pageAspect: 0.7).width, SignPlacement.minWidth);
    });

    test('pages are chosen by the setting', () {
      expect(SignPages.thisPage.resolve(current: 2, count: 5), [2]);
      expect(SignPages.thisPage.resolve(current: 9, count: 5), [4]);
      expect(SignPages.lastPage.resolve(current: 0, count: 5), [4]);
      expect(SignPages.allPages.resolve(current: 0, count: 3), [0, 1, 2]);
    });
  });

  group('signing', () {
    late String sig;
    late List<String> pages;
    late DocumentSignerProcessor signer;

    setUp(() {
      final signature = img.Image(width: 200, height: 80, numChannels: 4);
      img.fill(signature, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(signature, x1: 0, y1: 0, x2: 199, y2: 79, color: img.ColorRgba8(200, 0, 0, 255));
      sig = p.join(dir.path, 'sig.png');
      File(sig).writeAsBytesSync(img.encodePng(signature));
      pages = [];
      for (var i = 0; i < 3; i++) {
        final page = img.Image(width: 600, height: 800, numChannels: 3);
        img.fill(page, color: img.ColorRgb8(255, 255, 255));
        final path = p.join(dir.path, 'page$i.jpg');
        File(path).writeAsBytesSync(img.encodeJpg(page, quality: 95));
        pages.add(path);
      }
      File(p.join(dir.path, 'in.pdf')).writeAsBytesSync([1]);
      signer = DocumentSignerProcessor(pdfToImages: (_) async => pages);
    });

    int pageCount(String path) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(String.fromCharCodes(File(path).readAsBytesSync())).length;

    test('opens a PDF as pages and a photo as one page', () async {
      final pdf = (await signer.open(p.join(dir.path, 'in.pdf'))).valueOrNull!;
      expect((pdf.isPdf, pdf.pages.length, pdf.name), (true, 3, 'in'));
      final photo = (await signer.open(pages.first)).valueOrNull!;
      expect((photo.isPdf, photo.pages.length), (false, 1));
    });

    test('opening problems are explained', () async {
      expect((await signer.open(p.join(dir.path, 'no.pdf'))).failureOrNull!.message, contains('could not be found'));
      final empty = DocumentSignerProcessor(pdfToImages: (_) async => const []);
      expect((await empty.open(p.join(dir.path, 'in.pdf'))).failureOrNull!.message, contains('Nothing could be read'));
      final locked = DocumentSignerProcessor(pdfToImages: (_) async => throw const ImportFailure('This file is password protected.'));
      expect((await locked.open(p.join(dir.path, 'in.pdf'))).failureOrNull!.message, 'This file is password protected.');
      final bad = File(p.join(dir.path, 'bad.jpg'))..writeAsBytesSync([1, 2, 3]);
      expect((await signer.open(bad.path)).failureOrNull, isNotNull);
    });

    test('signs the chosen page of a PDF and keeps all pages', () async {
      final doc = (await signer.open(p.join(dir.path, 'in.pdf'))).valueOrNull!;
      final progress = <int>[];
      final r = (await signer.sign(
        document: doc,
        signaturePath: sig,
        placement: const SignPlacement(centerX: 0.5, centerY: 0.5, width: 0.5),
        pages: [1],
        outputDir: p.join(dir.path, 'out'),
        onProgress: (d, t) => progress.add(d * 10 + t),
      )).valueOrNull!;
      expect((r.pages, r.signedPages, r.mimeType), (3, 1, 'application/pdf'));
      expect(r.name, 'in signed.pdf');
      expect(pageCount(r.path), 3);
      expect(progress, [11]);
      expect(Directory(p.join(dir.path, 'out')).listSync().whereType<File>().map((f) => p.extension(f.path)).toSet(), {
        '.pdf',
      }, reason: 'page pictures are cleaned up');
    });

    test('signing a photo gives a JPG with the signature where it was placed', () async {
      final doc = (await signer.open(pages.first)).valueOrNull!;
      final r = (await signer.sign(
        document: doc,
        signaturePath: sig,
        placement: const SignPlacement(centerX: 0.5, centerY: 0.5, width: 0.5),
        pages: [0],
        outputDir: p.join(dir.path, 'o2'),
      )).valueOrNull!;
      expect(r.mimeType, 'image/jpeg');
      final out = img.decodeJpg(File(r.path).readAsBytesSync())!;
      expect((out.width, out.height), (600, 800));
      final middle = out.getPixel(300, 400);
      expect(middle.r, greaterThan(150));
      expect(middle.g, lessThan(90), reason: 'red ink in the middle of the page');
      expect(out.getPixel(20, 20).g, greaterThan(240), reason: 'the rest of the page is untouched');
      // Width is half of the page: 300 px, so 150 to 450 across the middle.
      expect(out.getPixel(160, 400).g, lessThan(90));
      expect(out.getPixel(100, 400).g, greaterThan(240));
    });

    test('transparent parts of the signature let the page show through', () async {
      final signature = img.Image(width: 100, height: 40, numChannels: 4);
      img.fill(signature, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(signature, x1: 0, y1: 0, x2: 9, y2: 39, color: img.ColorRgba8(0, 0, 0, 255));
      final path = p.join(dir.path, 'half.png');
      File(path).writeAsBytesSync(img.encodePng(signature));
      final doc = (await signer.open(pages.first)).valueOrNull!;
      final r = (await signer.sign(
        document: doc,
        signaturePath: path,
        placement: const SignPlacement(centerX: 0.5, centerY: 0.5, width: 0.5),
        pages: [0],
        outputDir: p.join(dir.path, 'o3'),
      )).valueOrNull!;
      final out = img.decodeJpg(File(r.path).readAsBytesSync())!;
      expect(out.getPixel(160, 400).r, lessThan(60), reason: 'ink at the left end');
      expect(out.getPixel(400, 400).r, greaterThan(240), reason: 'transparent part shows the white page');
    });

    test('every page can be signed', () async {
      final doc = (await signer.open(p.join(dir.path, 'in.pdf'))).valueOrNull!;
      final r = (await signer.sign(
        document: doc,
        signaturePath: sig,
        placement: const SignPlacement(),
        pages: [0, 1, 2],
        outputDir: p.join(dir.path, 'o4'),
      )).valueOrNull!;
      expect(r.signedPages, 3);
      expect(pageCount(r.path), 3);
    });

    test('bad requests are refused clearly', () async {
      final doc = (await signer.open(p.join(dir.path, 'in.pdf'))).valueOrNull!;
      Future<String?> fail({List<int> pages = const [0], String? signature}) async => (await signer.sign(
        document: doc,
        signaturePath: signature ?? sig,
        placement: const SignPlacement(),
        pages: pages,
        outputDir: p.join(dir.path, 'o5'),
      )).failureOrNull?.message;
      expect(await fail(pages: const []), 'Choose the page to sign.');
      expect(await fail(pages: const [7]), 'Choose the page to sign.');
      expect(await fail(signature: p.join(dir.path, 'gone.png')), contains('could not be found'));
    });
  });
}
