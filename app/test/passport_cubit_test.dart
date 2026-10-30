import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/photo_tools/domain/crop_math.dart';
import 'package:doculoom/features/photo_tools/domain/passport_maker.dart';
import 'package:doculoom/features/photo_tools/domain/photo_compressor.dart';
import 'package:doculoom/features/photo_tools/domain/photo_specs.dart';
import 'package:doculoom/features/photo_tools/presentation/passport_cubit.dart';

class _Maker implements PassportMaker {
  int width = 4000, height = 3000;
  bool failPrepare = false;
  final rendered = <RenderRequest>[];
  final sheets = <({SheetPaper paper, int? copies, PhotoSpec spec})>[];

  @override
  Future<Result<WorkingPhoto>> prepare({required String sourcePath, required String outputPath, bool rotateRight = false}) async {
    if (failPrepare) return const Err(ExportFailure('This photo could not be opened.'));
    if (rotateRight) {
      final t = width;
      width = height;
      height = t;
    }
    return Ok(WorkingPhoto(path: outputPath, width: width, height: height));
  }

  @override
  Future<Result<RenderedPhoto>> render(RenderRequest request) async {
    rendered.add(request);
    return Ok(RenderedPhoto(path: request.outputPath, bytes: 90000, width: request.outWidth, height: request.outHeight));
  }

  @override
  Future<Result<SheetFiles>> sheet({
    required String photoPath,
    required PhotoSpec spec,
    required SheetPaper paper,
    int? copies,
    required String outputBase,
  }) async {
    sheets.add((paper: paper, copies: copies, spec: spec));
    return Ok(SheetFiles(jpgPath: '$outputBase.jpg', pdfPath: '$outputBase.pdf', copies: copies ?? 6, columns: 2, rows: 3));
  }
}

class _Compressor implements PhotoCompressor {
  final calls = <CompressOptions>[];
  bool miss = false;

  @override
  Future<Result<CompressedPhoto>> compress({required String sourcePath, required String outputPath, required CompressOptions options}) async {
    calls.add(options);
    return Ok(
      CompressedPhoto(
        path: outputPath,
        bytes: miss ? 60000 : options.targetBytes! - 1000,
        width: 413,
        height: 531,
        originalBytes: 90000,
        metTarget: !miss,
        quality: 70,
      ),
    );
  }
}

void main() {
  late Directory dir;
  late _Maker maker;
  late _Compressor compressor;

  PassportCubit cubit({String? country}) => PassportCubit(maker: maker, compressor: compressor, workDir: () async => dir, countryCode: country);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_pc');
    maker = _Maker();
    compressor = _Compressor();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('starts with India passport size and changes with the country', () {
    final c = cubit();
    expect(c.state.country.name, 'India');
    expect(c.state.spec.sizeLabel, '35 x 45 mm');
    c.selectCountry('US');
    expect(c.state.country.name, 'United States');
    expect((c.state.spec.widthMm, c.state.spec.heightMm), (51, 51));
    c.selectCountry('CA');
    c.selectSpec(c.state.country.specs.last);
    expect(c.state.spec.id, 'visa');
    c.selectCountry('XX');
    expect(c.state.countryCode, 'CA', reason: 'an unknown country changes nothing');
  });

  test('a custom size is kept and can be picked again', () {
    final c = cubit();
    final custom = PhotoSpec.custom(widthMm: 30, heightMm: 40);
    c.useCustom(custom);
    expect(c.state.spec.id, 'custom');
    c.selectSpec(c.state.country.specs.first);
    expect(c.state.spec.id, 'passport');
    expect(c.state.custom, isNotNull);
  });

  test('picking a photo opens the crop with the photo covering the frame', () async {
    final c = cubit();
    await c.pickPhoto('/x/photo.jpg');
    expect(c.state.step, PassportStep.edit);
    expect(c.state.working!.width, 4000);
    expect(c.state.view!.zoom, 1);
    expect((c.state.view!.centerX, c.state.view!.centerY), (2000, 1500));
  });

  test('a photo that cannot be opened stays on the first step with the reason', () async {
    maker.failPrepare = true;
    final c = cubit();
    await c.pickPhoto('/x/bad.jpg');
    expect(c.state.step, PassportStep.choose);
    expect(c.state.failure!.message, contains('could not be opened'));
    expect(c.state.busy, isFalse);
  });

  test('rotating turns the photo a quarter and restarts the crop', () async {
    final c = cubit();
    await c.pickPhoto('/x/photo.jpg');
    c.setZoom(3);
    await c.rotate();
    expect((c.state.working!.width, c.state.working!.height), (3000, 4000));
    expect(c.state.view!.zoom, 1);
  });

  test('panning and zooming keep the visible part inside the photo', () async {
    final c = cubit();
    await c.pickPhoto('/x/photo.jpg');
    c.setZoom(2);
    for (var i = 0; i < 30; i++) {
      c.pan(i.isEven ? 0.2 : -0.35, 0.1);
      final r = c.state.view!.rect(4000, 3000, c.state.frameW, c.state.frameH);
      expect(r.left, greaterThanOrEqualTo(-0.001));
      expect(r.right, lessThanOrEqualTo(4000.001));
    }
    c.setZoom(100);
    expect(c.state.view!.zoom, CropView.maxZoom);
    c.resetView();
    expect(c.state.view!.zoom, 1);
  });

  test('creating the photo sends the crop, the exact pixel size and the background choice', () async {
    final c = cubit();
    await c.pickPhoto('/x/photo.jpg');
    c.setZoom(2);
    c.setReplaceBackground(true);
    c.setBackground(PhotoBackground.lightBlue);
    c.setStrength(70);
    await c.create();

    final r = maker.rendered.single;
    expect((r.outWidth, r.outHeight), (413, 531));
    expect(r.backgroundArgb, PhotoBackground.lightBlue.argb);
    expect(r.cleanStrength, 70);
    expect(r.width / r.height, closeTo(35 / 45, 1e-6), reason: 'the crop has the shape of the photo');
    expect(r.width, closeTo(3000 * 35 / 45 / 2, 0.01), reason: 'a wide photo, covered then zoomed 2x');
    expect(c.state.step, PassportStep.result);
    expect(c.state.rendered!.width, 413);
  });

  test('without replacing the background none is requested, and 600 dpi doubles the pixels', () async {
    final c = cubit();
    await c.pickPhoto('/x/photo.jpg');
    c.setDpi(600);
    await c.create();
    final r = maker.rendered.single;
    expect(r.backgroundArgb, isNull);
    expect((r.outWidth, r.outHeight), (827, 1063));
  });

  test('a size in pixels gives exactly those pixels whatever the resolution', () async {
    final c = cubit();
    c.useCustom(PhotoSpec.custom(widthMm: 25.4, heightMm: 33.87, widthPx: 200, heightPx: 267));
    await c.pickPhoto('/x/photo.jpg');
    c.setDpi(600);
    await c.create();
    expect((maker.rendered.single.outWidth, maker.rendered.single.outHeight), (200, 267));
  });

  test('compressing for upload keeps the pixel size and updates the file', () async {
    final c = cubit();
    await c.pickPhoto('/x/photo.jpg');
    await c.create();
    final before = c.state.rendered!.path;
    await c.compressTo(50 * 1024);
    expect(compressor.calls.single.keepPixelSize, isTrue);
    expect(compressor.calls.single.targetBytes, 50 * 1024);
    expect(c.state.rendered!.path, isNot(before));
    expect(c.state.rendered!.bytes, lessThan(50 * 1024));
    expect(c.state.compressNote, isNull);

    compressor.miss = true;
    await c.compressTo(10 * 1024);
    expect(c.state.compressNote, contains('little above the limit'));
  });

  test('a print sheet uses the finished photo and the chosen paper and copies', () async {
    final c = cubit();
    await c.pickPhoto('/x/photo.jpg');
    await c.create();
    await c.makeSheet(paper: SheetPaper.a4, copies: 8);
    expect(maker.sheets.single.paper, SheetPaper.a4);
    expect(maker.sheets.single.copies, 8);
    expect(maker.sheets.single.spec.widthMm, 35);
    expect(c.state.sheet!.pdfPath, endsWith('.pdf'));
  });

  test('going back keeps the crop, starting over keeps the country', () async {
    final c = cubit(country: 'GB');
    await c.pickPhoto('/x/photo.jpg');
    c.setZoom(2.5);
    await c.create();
    c.backToEdit();
    expect(c.state.step, PassportStep.edit);
    expect(c.state.view!.zoom, 2.5);
    c.startOver();
    expect(c.state.step, PassportStep.choose);
    expect(c.state.countryCode, 'GB');
    expect(c.state.working, isNull);
  });

  test('nothing happens without a photo', () async {
    final c = cubit();
    await c.create();
    await c.compressTo(1000);
    await c.makeSheet(paper: SheetPaper.a4);
    c.pan(0.1, 0.1);
    c.setZoom(2);
    expect(maker.rendered, isEmpty);
    expect(c.state.step, PassportStep.choose);
  });

  group('head guide', () {
    test('a 35 x 45 passport asks for a head of 32 to 36 mm', () {
      final g = HeadGuide.forPhoto(headMm: 34, photoWidthMm: 35, photoHeightMm: 45);
      expect(g.height, closeTo(34 / 45, 1e-9));
      expect(g.top, closeTo(0.0815, 0.001), reason: "a third of the space above and below the head");
      expect(g.chin, lessThan(1));
      expect(g.eyeLine, inExclusiveRange(g.top, g.chin));
      expect(g.width, inExclusiveRange(0.3, 0.95));
    });

    test('the guide always fits inside the photo, even for odd sizes', () {
      for (final spec in [for (final c in PhotoCatalog.countries) ...c.specs]) {
        final g = HeadGuide.forPhoto(headMm: spec.headTargetMm, photoWidthMm: spec.widthMm, photoHeightMm: spec.heightMm);
        expect(g.top, greaterThanOrEqualTo(0), reason: '${spec.name} ${spec.sizeLabel}');
        expect(g.chin, lessThan(1), reason: '${spec.name} ${spec.sizeLabel}');
      }
    });
  });
}
