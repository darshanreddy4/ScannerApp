# 06 Raise the target API level

Google Play requires new uploads to target a recent Android version (the "target API level"). Doing it is usually a small change, because Doculoom takes the number from Flutter. Most of the work is testing.

Current values (checked on the Flutter 3.44 setup in this repo):

| Setting | Value | Where it comes from |
|---|---|---|
| `targetSdk` | 36 (Android 16) | `flutter.targetSdkVersion`, used in `app/android/app/build.gradle.kts` |
| `compileSdk` | 36 | `flutter.compileSdkVersion`, same file |
| `minSdk` | 24 (Android 7.0) | set in `build.gradle.kts`; raising the target does not change it |
| Android Gradle Plugin | 9.0.1 | `app/android/settings.gradle.kts` |
| Gradle | 9.1.0 | `app/android/gradle/wrapper/gradle-wrapper.properties` |
| Kotlin plugin | 2.3.20 | `app/android/settings.gradle.kts` |

Flutter's own numbers live in `FlutterExtension.kt` inside the Flutter SDK (see step 2).

## 1. Find out which level you need

- Read the current rule: <https://support.google.com/googleplay/android-developer/answer/11926878>. It lists the level and the date.
- Play Console also shows a warning in your notifications before a deadline.
- Check what you have now in a built bundle:

```bash
bundletool dump manifest --bundle=app/build/app/outputs/bundle/release/app-release.aab | grep -o 'targetSdkVersion="[0-9]*"'
```

The examples below use 37 (Android 17). Replace it with the level Google asks for.

## 2. Path A (normal): upgrade Flutter

A newer Flutter normally raises `targetSdkVersion` by itself, so no file changes are needed.

```bash
flutter upgrade                 # if Flutter was installed with Homebrew and this fails: brew upgrade --cask flutter
flutter --version
flutter doctor -v               # fix anything marked with a cross
```

Check what the new Flutter uses:

```bash
FR=$(dirname $(dirname $(readlink -f $(which flutter))))
grep -n "compileSdkVersion\|targetSdkVersion" "$FR/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
```

- If it shows the level you need, go to step 4.
- If it still shows the old level, use Path B (step 3).

Then refresh the packages and check the project still builds:

```bash
cd app
flutter pub get
flutter pub outdated             # packages that have newer versions
flutter pub upgrade              # stays inside the ranges in pubspec.yaml
flutter analyze
flutter test
```

If Gradle complains that the Android Gradle Plugin or Gradle is too old, raise them:
- AGP: change `com.android.application` version in `app/android/settings.gradle.kts`.
- Gradle: change `distributionUrl` in `app/android/gradle/wrapper/gradle-wrapper.properties`.
- Use the pair the error message asks for; do not guess. AGP release notes list the Gradle version each AGP needs.

## 3. Path B: set the level by hand

Use this only when the installed Flutter does not yet use the new level.

1. Install the Android platform for that level (look the exact name up first):

```bash
SDKM=~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager
$SDKM --list | grep "platforms;android-37"
$SDKM "platforms;android-37.0"
```

2. In `app/android/app/build.gradle.kts` replace two lines:

```kotlin
compileSdk = 37      // was: flutter.compileSdkVersion
...
targetSdk = 37       // was: flutter.targetSdkVersion
```

3. If Gradle says the Android Gradle Plugin does not support `compileSdk 37`, raise AGP and Gradle as in step 2. Do not silence the warning.
4. Go back to Flutter's default once a Flutter release supports the level, so the numbers stay in one place.

## 4. Build and check

```bash
cd app
flutter clean
flutter pub get
flutter build appbundle --release
bundletool dump manifest --bundle=build/app/outputs/bundle/release/app-release.aab | grep -o 'targetSdkVersion="[0-9]*"'
```

It must print the new number. Raise the version in `app/pubspec.yaml` before you upload (see [05](05-build-aab-and-ads.md)).

## 5. Test on the new Android version

A higher target turns on newer Android behaviour for the app, so run it on a phone or emulator with that Android version.

```bash
SDKM=~/Library/Android/sdk/cmdline-tools/latest/bin
$SDKM/sdkmanager --list | grep "system-images;android-37"
$SDKM/sdkmanager "system-images;android-37.0;google_apis_playstore_ps16k;arm64-v8a"
$SDKM/avdmanager create avd -n Pixel_37 -k "system-images;android-37.0;google_apis_playstore_ps16k;arm64-v8a" -d pixel_8
~/Library/Android/sdk/emulator/emulator -avd Pixel_37 &
```

The `Pixel_8` virtual device on the development Mac already uses this Android 37.0 image, so it can be used as it is. For another level, pick its image from the `--list` output. On Intel Macs use `x86_64` instead of `arm64-v8a`.

Read the official list of behaviour changes for the new level (<https://developer.android.com/about/versions>, then the release and "Behavior changes: apps targeting Android N"). Then try what Doculoom uses:

- Start-up, Documents, Tools and Settings screens; screens look right with gesture and 3-button navigation (edge to edge).
- Camera scan, import from gallery and files, save to gallery, share, print.
- OCR, translate, PDF tools (including a locked PDF), signing, backup and restore.
- QR share on the same Wi-Fi (it runs a foreground service with a notification and a Stop button). Newer Android versions limit how long some foreground service types may run, so also try a longer share.
- Reminders and notifications: the notification permission prompt, a reminder arriving on time, and after a phone restart.
- Phone lock (fingerprint, face, PIN), folder lock.
- Ads: test ads load and the consent form appears.
- Quick settings tiles, home-screen widget and "Open with" from another app.
- Rotate on a tablet or a resizable emulator.
- Back gesture on every screen.

Then run the automatic checks and the real release build from [02 Testing](02-testing.md):

```bash
cd app
flutter analyze
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -d | grep -E "FATAL EXCEPTION|NoSuchMethodError|ClassNotFound|Uncaught error"
```

## 6. Release it safely

1. Upload to the closed testing track first and ask testers to update.
2. Watch Android vitals for crashes for a few days.
3. Upload to production with a staged rollout (10 to 20 percent), then raise it.
4. Add a short release note such as "Compatibility update for the latest Android".

## If you are short of time

Play offers an extension request for a deadline (a form linked from your Play Console notifications). It only delays the deadline; it does not remove the requirement.

## If something breaks

- Build error about SDK or AGP versions: read the message, raise AGP or Gradle as in step 2.
- Crash only in release: the code shrinker (R8) is the usual cause. Add a keep rule in `app/android/app/proguard-rules.pro` and see [01 Getting started](01-getting-started.md), Troubleshooting.
- A screen looks cut off at the top or bottom: the system bars now draw over the app; use `SafeArea` or padding on that screen.
- Temporary fallback: set `targetSdk` back to the old number only if Google still accepts it for your deadline.
