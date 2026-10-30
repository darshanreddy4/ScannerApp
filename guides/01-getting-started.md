# 01 Getting started

## What the app is

Doculoom is an offline document app for Android: scan and crop pages, filters, PDF and Word export, PDF tools (lock, unlock, compress, split, sign, redact), OCR, spreadsheets, presentations, QR sharing and more. Documents stay on the phone. The only network use is ads (AdMob) and the optional "Anywhere" QR share, which needs the relay in `relay/`.

Package name: `com.doculoom.app`. Dart package: `doculoom`. Minimum Android: 7.0 (API 24).

## 1. Install the tools (once)

| Tool | Version used | Check with |
|---|---|---|
| Flutter | 3.44 (Dart 3.12, see `environment` in `app/pubspec.yaml`) | `flutter --version` |
| JDK | 17 | `java -version` |
| Android SDK with command-line tools | platform 36, build-tools, cmdline-tools | `flutter doctor -v` |
| Android phone or emulator | Android 7.0 or newer | `flutter devices` |
| Python 3 with Pillow (only for store graphics) | any recent | `python3 -c "import PIL"` |
| Node.js (only for the sharing relay) | LTS | `node -v` |

Android command-line tools are required. Without them release builds can fail with "failed to strip debug symbols". Install them from Android Studio (SDK Manager > SDK Tools > Android SDK Command-line Tools) or with `sdkmanager "cmdline-tools;latest"`, then accept the licences:

```bash
flutter doctor --android-licenses
flutter doctor -v          # everything for Android must be ticked
```

## 2. Get the code and dependencies

```bash
git clone https://github.com/darshanreddy4/ScannerApp.git
cd ScannerApp/app
flutter pub get
```

## 3. Run the app

Use a real phone for the camera. Everything except the live camera also works on an emulator.

**Real phone:** turn on Developer options and USB debugging, connect it, accept the prompt on the phone.

**Emulator:** create one in Android Studio (Device Manager), or from the command line:

```bash
~/Library/Android/sdk/emulator/emulator -list-avds
~/Library/Android/sdk/emulator/emulator -avd Pixel_8 &
```

Then:

```bash
flutter devices                       # copy the device id
flutter run                           # debug build, hot reload with r, quit with q
flutter run -d <device-id>            # when more than one device is connected
flutter run --release                 # speed and R8 behaviour of the real app
```

The app starts with Google's **test ads** and test AdMob IDs, so running it is safe.

## 4. Build a file you can install

```bash
cd app
flutter build apk --debug                     # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release                   # signed with the upload key if android/key.properties exists
flutter build apk --release --split-per-abi   # smaller per-CPU files for sideloading
```

Install on a connected phone: `adb install -r build/app/outputs/flutter-apk/app-release.apk`.
If it says `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, the phone has a build signed with a different key: run `adb uninstall com.doculoom.app` first.

For the Play Store file (`.aab`) read [05 Build the .aab](05-build-aab-and-ads.md).

## 5. Folder map

```
app/                    the Flutter app
  lib/main.dart         start-up
  lib/app/              dependency injection (di.dart), routes (router.dart), app_config.dart (build settings)
  lib/core/             errors, theme, icons, translations (core/i18n), shared widgets
  lib/features/         one folder per feature: domain (rules), data (storage, engines), presentation (screens, cubits)
  android/              Android project (build.gradle.kts, AndroidManifest.xml, proguard-rules.pro, Kotlin code)
  ios/                  iOS project (not published yet)
  test/                 unit and widget tests
docs/                   privacy policy page (published with GitHub Pages)
relay/                  Cloudflare Worker for "Anywhere" QR sharing, with its own tests
store/                  Play Store icon, feature graphic, screenshots and the scripts that make them
prototype/, prototypes/ HTML mock-ups of the screens
guides/                 these guides
```

The code follows feature-first Clean Architecture: `presentation -> domain <- data`. State is held in BLoC/Cubit classes, objects are wired in `lib/app/di.dart` with `get_it`, and screens are routed with `go_router`.

## 6. Everyday commands

```bash
cd app
flutter pub get                 # after pulling or editing pubspec.yaml
flutter analyze                 # static checks
dart format lib test            # formatting
flutter clean                   # when a build behaves strangely, then flutter pub get
```

## 7. Troubleshooting

- **Gradle fails with `PKIX path building failed`** (company network that inspects TLS): build a Java truststore that contains the company root certificate and pass it on:
  ```bash
  export JAVA_TOOL_OPTIONS="-Djavax.net.ssl.trustStore=$HOME/.scanvault-build/cacerts -Djavax.net.ssl.trustStorePassword=changeit"
  ```
- **Release app crashes at start but debug works:** R8 shrinking removed or renamed something. Keep rules live in `app/android/app/proguard-rules.pro`. Reproduce with `flutter run --release` and read `adb logcat`. Release builds also write `app/build/app/outputs/mapping/release/mapping.txt` to translate crash traces.
- **`flutter doctor` shows Android licences not accepted:** run `flutter doctor --android-licenses`.
- **Camera is black on an emulator:** use a real phone, or set the emulator's back camera to a webcam in the AVD settings.
