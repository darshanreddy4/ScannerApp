import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/features/photo_tools/data/business_profile_store.dart';
import 'package:scanvault/features/photo_tools/domain/watermark.dart';
import 'package:scanvault/features/photo_tools/domain/watermark_service.dart';
import 'package:scanvault/features/photo_tools/presentation/watermark_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Service implements WatermarkService {
  final calls = <({String input, WatermarkStyle style, String name})>[];
  final failFor = <String>{};

  @override
  Future<Result<WatermarkOutput>> apply({
    required String inputPath,
    required WatermarkStyle style,
    required String outputDir,
    String businessName = '',
    void Function(int done, int total)? onProgress,
  }) async {
    calls.add((input: inputPath, style: style, name: businessName));
    if (failFor.any(inputPath.endsWith)) return const Err(ExportFailure('The watermark could not be added.'));
    final pdf = inputPath.endsWith('.pdf');
    return Ok(
      WatermarkOutput(
        path: p.join(outputDir, 'out_${p.basename(inputPath)}'),
        mimeType: pdf ? 'application/pdf' : 'image/jpeg',
        name: p.basename(inputPath),
        pages: pdf ? 3 : 1,
      ),
    );
  }
}

class _Profiles implements BusinessProfileStore {
  _Profiles();
  BusinessProfile profile = const BusinessProfile();
  bool fail = false;

  @override
  Future<BusinessProfile> load() async => profile;

  @override
  Future<BusinessProfile> save(BusinessProfile profile, {String? newLogoSource}) async {
    if (fail) throw const FormatException('nope');
    return this.profile = BusinessProfile(name: profile.name, details: profile.details, logoPath: newLogoSource ?? profile.logoPath);
  }
}

void main() {
  late Directory dir;
  late _Service service;
  late _Profiles profiles;

  File file(String name, {int size = 100}) => File(p.join(dir.path, name))..writeAsBytesSync(List.filled(size, 1));

  WatermarkCubit cubit() => WatermarkCubit(service: service, profiles: profiles, outputDir: () async => dir);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('sv_wmc');
    service = _Service();
    profiles = _Profiles();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('WatermarkCubit', () {
    test('accepts pictures and PDFs once, and counts files it cannot mark', () async {
      final c = cubit();
      final a = file('a.jpg'), b = file('b.PNG'), d = file('d.pdf');
      await c.add([a.path, a.path, b.path, d.path, file('notes.docx').path, file('clip.mp4').path, p.join(dir.path, 'missing.jpg')]);
      expect(c.state.inputs.map((i) => i.name), ['a.jpg', 'b.PNG', 'd.pdf']);
      expect(c.state.inputs.last.isPdf, isTrue);
      expect(c.state.skipped, 2);
    });

    test('stops at 30 files', () async {
      final c = cubit();
      await c.add([for (var i = 0; i < 35; i++) file('p$i.jpg').path]);
      expect(c.state.inputs, hasLength(WatermarkCubit.maxFiles));
    });

    test('marks every file with the style and the business name and keeps going after a failure', () async {
      profiles.profile = const BusinessProfile(name: 'Asha Traders');
      final c = cubit();
      await c.load();
      await c.add([file('a.jpg').path, file('bad.jpg').path, file('c.pdf').path]);
      c.setText('COPY');
      service.failFor.add('bad.jpg');
      await c.run();

      expect(service.calls, hasLength(3));
      expect(service.calls.first.style.text, 'COPY');
      expect(service.calls.first.name, 'Asha Traders');
      expect(c.state.status, WatermarkStatus.done);
      expect(c.state.progress, 3);
      expect(c.state.outcomes[1].failure, isNotNull);
      expect(c.state.outputs.map((o) => o.name), ['a.jpg', 'c.pdf']);
      expect(c.state.outputs.last.pages, 3);
    });

    test('changing the style discards earlier results', () async {
      final c = cubit();
      await c.add([file('a.jpg').path]);
      await c.run();
      expect(c.state.outputs, isNotEmpty);
      c.setOpacity(0.8);
      expect(c.state.outputs, isEmpty);
      expect(c.state.status, WatermarkStatus.idle);
    });

    test('an empty watermark is refused with a reason and nothing runs', () async {
      final c = cubit();
      await c.add([file('a.jpg').path]);
      c.setText('   ');
      await c.run();
      expect(service.calls, isEmpty);
      expect(c.state.failure!.message, contains('Type the words'));
    });

    test('a logo alone is enough', () async {
      final c = cubit();
      await c.add([file('a.jpg').path]);
      c.setText('');
      c.setLogo('/logo.png');
      await c.run();
      expect(service.calls, hasLength(1));
    });

    test('business details fill the words and the logo', () async {
      profiles.profile = const BusinessProfile(name: 'Asha Traders', details: 'GST 27ABCDE1234F1Z5', logoPath: '/l.png');
      final c = cubit();
      await c.load();
      c.useBusinessDetails();
      expect(c.state.style.text, 'Asha Traders\nGST 27ABCDE1234F1Z5');
      expect(c.state.style.logoPath, '/l.png');
    });

    test('without saved business details nothing changes', () async {
      final c = cubit();
      final before = c.state.style;
      c.useBusinessDetails();
      expect(c.state.style, before);
    });

    test('saving details updates the profile, and a failure is reported', () async {
      final c = cubit();
      await c.saveProfile(const BusinessProfile(name: 'Asha', details: 'Pune'));
      expect(c.state.profile.name, 'Asha');
      profiles.fail = true;
      await c.saveProfile(const BusinessProfile(name: 'X'));
      expect(c.state.failure, isA<StorageFailure>());
      expect(c.state.profile.name, 'Asha', reason: 'the old details stay');
    });

    test('repeated marks start smaller than a single big stamp', () {
      final c = cubit();
      c.setLayout(WatermarkLayout.single);
      c.setSize(0.15);
      c.setLayout(WatermarkLayout.tiled);
      expect(c.state.style.size, lessThanOrEqualTo(0.09));
    });

    test('remove and clear', () async {
      final c = cubit();
      final a = file('a.jpg');
      await c.add([a.path, file('b.jpg').path]);
      c.remove(a.path);
      expect(c.state.inputs.single.name, 'b.jpg');
      c.clear();
      expect(c.state.inputs, isEmpty);
    });
  });

  group('business profile storage', () {
    late BusinessProfileStoreImpl store;
    setUp(() => store = BusinessProfileStoreImpl(appDir: () async => dir));

    String logo(String name, int w, int h) =>
        (File(p.join(dir.path, name))..writeAsBytesSync(img.encodePng(img.Image(width: w, height: h, numChannels: 4)))).path;

    test('nothing is saved at first', () async {
      expect((await store.load()).isEmpty, isTrue);
    });

    test('keeps name and details between launches', () async {
      await store.save(const BusinessProfile(name: '  Asha Traders ', details: ' Pune '));
      final again = await BusinessProfileStoreImpl(appDir: () async => dir).load();
      expect((again.name, again.details), ('Asha Traders', 'Pune'));
    });

    test('copies the logo into the app, small and as PNG', () async {
      final saved = await store.save(const BusinessProfile(name: 'A'), newLogoSource: logo('big.png', 1500, 900));
      expect(saved.logoPath, contains('branding'));
      final copy = img.decodePng(File(saved.logoPath!).readAsBytesSync())!;
      expect(copy.width, BusinessProfileStoreImpl.logoMaxSide);
      expect(copy.height, 360);
      expect((await store.load()).logoPath, saved.logoPath);
    });

    test('a new logo replaces the old file, and removing it deletes the file', () async {
      final first = await store.save(const BusinessProfile(name: 'A'), newLogoSource: logo('one.png', 100, 100));
      final second = await store.save(
        BusinessProfile(name: 'A', logoPath: first.logoPath),
        newLogoSource: logo('two.png', 100, 100),
      );
      expect(File(first.logoPath!).existsSync(), isFalse);
      expect(File(second.logoPath!).existsSync(), isTrue);
      final removed = await store.save(const BusinessProfile(name: 'A'));
      expect(removed.logoPath, isNull);
      expect(File(second.logoPath!).existsSync(), isFalse);
    });

    test('saving empty details forgets everything', () async {
      await store.save(const BusinessProfile(name: 'A'));
      await store.save(const BusinessProfile());
      expect((await store.load()).isEmpty, isTrue);
    });

    test('a logo file that went missing is dropped on load', () async {
      final saved = await store.save(const BusinessProfile(name: 'A'), newLogoSource: logo('l.png', 50, 50));
      File(saved.logoPath!).deleteSync();
      final loaded = await store.load();
      expect(loaded.logoPath, isNull);
      expect(loaded.name, 'A');
    });

    test('a file that is not a picture is refused', () async {
      final bad = (File(p.join(dir.path, 'bad.png'))..writeAsBytesSync(List.filled(20, 1))).path;
      expect(() => store.save(const BusinessProfile(name: 'A'), newLogoSource: bad), throwsA(isA<FormatException>()));
    });
  });
}
