# 02 Testing

The Flutter tests need no phone or emulator. They are in `app/test/` (one `*_test.dart` file per area: PDF security, OCR structuring, coins, folders, share packaging, translations and more). The sharing relay has its own tests in `relay/test/`.

## Run all app tests

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

`flutter test` includes `layout_sweep_test.dart`, which opens every screen at many phone sizes and font scales in English, Arabic, Russian and German. It is slow. For a quick run without it:

```bash
flutter test $(ls test/*_test.dart | grep -v layout_sweep)
```

## Run one file, one test, or a group

```bash
flutter test test/pdf_protect_processor_test.dart
flutter test test/reader_search_test.dart test/quick_actions_test.dart
flutter test --plain-name "a wrong password gives a password failure"
flutter test test/layout_sweep_test.dart        # the slow screen sweep only
```

## Coverage

```bash
flutter test --coverage         # writes coverage/lcov.info
```

Open it with any lcov viewer (for example `genhtml coverage/lcov.info -o coverage/html` when `lcov` is installed).

## Relay tests

```bash
cd relay
npm install
npm test
```

## Check the release build on a device

Unit tests do not run R8 (the code shrinker), and R8 has broken release builds before. Before every upload run the real release build on a phone or emulator:

```bash
cd app
flutter build apk --release
adb uninstall com.doculoom.app            # only if a differently signed build is installed
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -n com.doculoom.app/.MainActivity
adb logcat -d | grep -E "FATAL EXCEPTION|NoSuchMethodError|ClassNotFound|Uncaught error"
```

No output from the last command means no crash or missing-class errors were logged. Then open the main screens by hand: Documents, Tools, Settings, scan or import a file, open a PDF (including a locked one), share.

To test the bundle the way Google Play installs it (split APKs), use [bundletool](https://developer.android.com/tools/bundletool) (`brew install bundletool`):

```bash
bundletool build-apks --bundle=app/build/app/outputs/bundle/release/app-release.aab --output=/tmp/out.apks \
  --connected-device --ks=$HOME/upload-keystore.jks --ks-key-alias=upload
bundletool install-apks --apks=/tmp/out.apks
```

`bundletool` asks for the keystore password.

## Writing a new test

- Put it in `app/test/<name>_test.dart`, import with `package:doculoom/...`.
- Use fake engines or classes for anything that needs the phone (camera, ML Kit, PDF renderer). The existing tests show how (for example the fake OCR engine).
- Do not assert exact results that depend on timing or on real network speed. Test the decision logic with prepared values instead.
- Database tests use `sqflite_common_ffi`, so they run on a computer.
- Text on screens goes through `Text` from `lib/core/widgets/text.dart` or `tr()` so it can be translated. New visible strings should be added to the translation files in `lib/core/i18n/lang/`.
- Run `flutter analyze` as well; it is part of the checks.
