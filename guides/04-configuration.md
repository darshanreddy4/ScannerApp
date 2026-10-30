# 04 Configure the app

Settings come from four places: build-time values (`--dart-define`), Gradle properties, Android project files, and `pubspec.yaml`. Nothing secret is stored in the repository.

## 1. Build-time values (Dart)

Defined in `app/lib/app/app_config.dart`. Pass them to any `flutter run` or `flutter build` command with `--dart-define=NAME=value`, or put many in one JSON file (see below).

| Name | Default | What it does |
|---|---|---|
| `PRIVACY_POLICY_URL` | the GitHub Pages policy of Doculoom | Public privacy policy link shown in Settings and required by Google Play |
| `TERMS_URL` | empty | Optional public terms link (the in-app terms are always available) |
| `SUPPORT_EMAIL` | the developer's address | Contact shown on the privacy, terms and support pages |
| `APP_STORE_URL` | the Google Play page of `com.doculoom.app` | Link used by Rate us and Share this app |
| `SHARE_RELAY_URL` | empty | Address of the deployed `relay/` Worker. Empty hides "Anywhere" in QR sharing |
| `REWARDS_ENABLED` | `true` | `false` turns off coins and rewarded videos |
| `BILLING_ENABLED` | `false` | Keep `false` until real Google Play Billing is built. `false` hides the Premium screen and locks nothing |
| `ADMOB_BANNER_ANDROID`, `ADMOB_INTERSTITIAL_ANDROID`, `ADMOB_NATIVE_ANDROID`, `ADMOB_REWARDED_ANDROID` | Google test IDs | Ad unit IDs, see [05](05-build-aab-and-ads.md) |
| `ADMOB_BANNER_IOS`, `ADMOB_INTERSTITIAL_IOS`, `ADMOB_NATIVE_IOS`, `ADMOB_REWARDED_IOS` | Google test IDs | Same for iOS |

Example:

```bash
cd app
flutter run --dart-define=SUPPORT_EMAIL=help@example.com --dart-define=REWARDS_ENABLED=false
```

To avoid long commands, keep the values in a JSON file that is **not committed** (`app/release.defines.json` is in `.gitignore`):

```json
{
  "PRIVACY_POLICY_URL": "https://example.com/privacy",
  "SUPPORT_EMAIL": "help@example.com",
  "SHARE_RELAY_URL": "https://doculoom-share.your-name.workers.dev",
  "ADMOB_BANNER_ANDROID": "ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN"
}
```

```bash
flutter build appbundle --release --dart-define-from-file=release.defines.json
```

Values given with `--dart-define` win over the file. A new setting is added by adding a `static const x = String.fromEnvironment('NAME', defaultValue: '...')` line to `app_config.dart`.

## 2. Gradle properties (Android)

| Property | Default | What it does |
|---|---|---|
| `admobAppId` | Google's test app ID | AdMob **app** ID written into the manifest (`com.google.android.gms.ads.APPLICATION_ID`) |

Pass it with `-P` (for example `flutter build appbundle --release -PadmobAppId=ca-app-pub-...~...`). The property is read in `app/android/app/build.gradle.kts`.

## 3. Android project files

| What | Where |
|---|---|
| App name under the icon | `android:label="Doculoom"` in `app/android/app/src/main/AndroidManifest.xml` |
| Package name (`com.doculoom.app`) | `namespace` and `applicationId` in `app/android/app/build.gradle.kts`, and the Kotlin folder `app/android/app/src/main/kotlin/com/doculoom/app`. `AppConfig.androidPackage` must match. Changing it later makes a new app on Google Play |
| Minimum / target Android | `minSdk = 24`, `targetSdk` follows Flutter (Google Play requires API 36 from 31 Aug 2026) |
| Permissions | `uses-permission` lines at the top of `AndroidManifest.xml`: camera, internet, biometric, foreground service (QR sharing), notifications (reminders, share countdown), Wi-Fi state, boot (reminders), write storage only on Android 9 and older. Fewer permissions is better for the Play review |
| Code shrinking (R8) rules | `app/android/app/proguard-rules.pro`. A plugin that works in debug but crashes in release usually needs a keep rule here |
| Release signing | `app/android/key.properties` (see [05](05-build-aab-and-ads.md)) |
| Gradle memory | `app/android/gradle.properties` (`org.gradle.jvmargs`) |

## 4. Version

In `app/pubspec.yaml`:

```yaml
version: 0.1.0+3      # name (shown to users) + build number (Android versionCode)
```

Every upload to Google Play needs a build number higher than any earlier upload, even for a rejected release. Raise the part after `+` for each upload. You can also set it at build time with `--build-number=4`.

## 5. Where texts and data live

| Thing | Where |
|---|---|
| In-app privacy policy and terms text | `app/lib/features/settings/presentation/privacy_page.dart`, `terms_page.dart` |
| Public privacy policy (website) | `docs/privacy-policy.html`, published with GitHub Pages. Update it together with the in-app text |
| Translations | `app/lib/core/i18n/` (`lang/` holds one file per language group) |
| Colours and theme | `app/lib/core/theme/app_colors.dart`, `app_theme.dart` |
| All icons used in screens | `app/lib/core/theme/app_icons.dart` |
| Coin prices and daily reward limit | `app/lib/features/rewards/` |
| Share relay (server) | `relay/` (`wrangler.toml` holds the bucket name; see the README section "Sharing over the internet") |

## 6. Files that must never be committed

`app/android/key.properties`, any `*.jks` or `*.keystore`, `app/release.defines.json`, and APK/AAB files. `.gitignore` already covers them. Keep a private backup of the keystore and its passwords: losing the upload key means asking Google to reset it.
