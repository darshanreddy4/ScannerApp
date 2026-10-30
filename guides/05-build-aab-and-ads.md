# 05 Build the .aab and add AdMob IDs

Google Play takes an **Android App Bundle** (`.aab`), not an APK. Play builds the small per-phone APKs from it. The steps below create a signed `.aab` and show exactly where the AdMob IDs go.

## Part A. One-time setup

### A1. Create the upload key

The upload key proves that updates come from you. Make it once and keep it safe.

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` asks for a password (twice), then your name and organisation. Use a **strong** password and store it in a password manager. Back up `~/upload-keystore.jks` somewhere private (not in the repository). If it is lost you must ask Google Play support to reset the upload key.

To change a password later:

```bash
keytool -storepasswd -keystore ~/upload-keystore.jks
keytool -keypasswd  -alias upload -keystore ~/upload-keystore.jks
```

### A2. Tell Gradle about the key

```bash
cd app/android
cp key.properties.example key.properties
```

Edit `key.properties`:

```
storeFile=/Users/you/upload-keystore.jks
storePassword=...your password...
keyAlias=upload
keyPassword=...your password...
```

`key.properties` is ignored by git. Never paste its content into chat, tickets or commits. Without this file the release build is signed with the debug key and Google Play rejects it.

### A3. Play App Signing

In Play Console, the first upload asks you to enrol in Play App Signing. Accept: Google keeps the final app signing key, and you keep only the upload key above.

## Part B. Create the AdMob IDs

Do this when you are ready for real ads. **Until the closed test (12 testers, 14 days) is finished, keep the Google test IDs** that are built into the app. Showing real ads to your own testers and tapping them risks an AdMob ban.

1. Open <https://admob.google.com> and sign in with the Google account that owns the app.
2. **Apps > Add app** > Android > "Yes, it is listed on Google Play" (or "No" before publishing and link it later) > enter `com.doculoom.app`.
3. AdMob shows the **App ID**. It looks like `ca-app-pub-1234567890123456~1234567890` (a **tilde** `~`).
4. In the app open **Ad units > Add ad unit** and create four units. Each gives an **ad unit ID** (a **slash** `/`): `ca-app-pub-1234567890123456/1234567890`.

| Ad unit to create | Format in AdMob | Used for | Build setting |
|---|---|---|---|
| Banner | Banner | Bottom of Documents, Tools, Settings and folders | `ADMOB_BANNER_ANDROID` |
| Interstitial | Interstitial | After saving or exporting (at most once every 2 minutes) | `ADMOB_INTERSTITIAL_ANDROID` |
| Native | Native advanced | Cards inside lists (falls back to a banner) | `ADMOB_NATIVE_ANDROID` |
| Rewarded | Rewarded | "Watch a video for 10 coins" | `ADMOB_REWARDED_ANDROID` |

5. **Privacy & messaging > Create a message** for the EEA/UK consent form (Google UMP) and publish it. Without it the consent form never appears and ads may be limited in Europe.
6. Add payment details and complete the account information so AdMob can pay you.
7. Add `app-ads.txt` to your developer website once the app is live (see the README section "Linking AdMob after launch").

## Part C. Where each ID goes

| ID | Looks like | Put it here |
|---|---|---|
| App ID (Android) | `ca-app-pub-...~...` | Gradle property **`admobAppId`**: `-PadmobAppId=ca-app-pub-...~...` on the build command. It fills `com.google.android.gms.ads.APPLICATION_ID` in `app/android/app/src/main/AndroidManifest.xml` through `app/android/app/build.gradle.kts` |
| Ad unit IDs (Android) | `ca-app-pub-.../...` | `--dart-define=ADMOB_BANNER_ANDROID=...` and the other three names above. Read in `app/lib/app/app_config.dart` |
| iOS (only if you publish on iOS) | | App ID in `app/ios/Runner/Info.plist` key `GADApplicationIdentifier`; ad units `ADMOB_*_IOS` dart-defines |

Do not edit the test IDs inside the code. Keep them as defaults and pass the real values only when building the release. A mix-up (the app ID in an ad unit setting or the reverse) shows no ads, so check the `~` and `/`.

To avoid typing the IDs each time, create `app/release.defines.json` (ignored by git):

```json
{
  "ADMOB_BANNER_ANDROID": "ca-app-pub-XXXXXXXXXXXXXXXX/1111111111",
  "ADMOB_INTERSTITIAL_ANDROID": "ca-app-pub-XXXXXXXXXXXXXXXX/2222222222",
  "ADMOB_NATIVE_ANDROID": "ca-app-pub-XXXXXXXXXXXXXXXX/3333333333",
  "ADMOB_REWARDED_ANDROID": "ca-app-pub-XXXXXXXXXXXXXXXX/4444444444",
  "PRIVACY_POLICY_URL": "https://example.com/privacy",
  "SUPPORT_EMAIL": "help@example.com",
  "SHARE_RELAY_URL": "https://doculoom-share.your-name.workers.dev"
}
```

Leave out `SHARE_RELAY_URL` if you have not deployed the relay; leave out any name to keep its default.

## Part D. Build the bundle

### D1. Test build (Google test ads, what the closed test uses)

```bash
cd app
# raise the number after + in pubspec.yaml first (see below)
flutter pub get
flutter analyze
flutter build appbundle --release
```

### D2. Production build (real ads)

```bash
cd app
flutter build appbundle --release \
  --dart-define-from-file=release.defines.json \
  -PadmobAppId=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY
```

Output: `app/build/app/outputs/bundle/release/app-release.aab`.

**Version number:** in `app/pubspec.yaml` change `version: 0.1.0+3` so the number after `+` is higher than every build you uploaded before (Play rejects a repeated number). Production builds also need a higher number than the closed-test build.

**Obfuscation mapping:** `app/build/app/outputs/mapping/release/mapping.txt` translates crash reports. In Play Console, open the release and upload it as the deobfuscation file, so crashes in Android vitals are readable.

## Part E. Check the bundle before uploading

```bash
AAB=app/build/app/outputs/bundle/release/app-release.aab
ls -l $AAB
jarsigner -verify $AAB | head -2                                               # "jar verified."
bundletool dump manifest --bundle=$AAB --xpath /manifest/@android:versionCode  # expected build number
bundletool dump manifest --bundle=$AAB | grep -A1 APPLICATION_ID               # the AdMob app ID
mkdir -p /tmp/aab && unzip -q -o $AAB base/lib/arm64-v8a/libapp.so -d /tmp/aab
strings /tmp/aab/base/lib/arm64-v8a/libapp.so | grep -o "ca-app-pub-[0-9]*/[0-9]*" | sort -u   # the ad unit IDs
```

- Test builds must show only `ca-app-pub-3940256099942544` IDs (Google's).
- Production builds must show your own publisher number and no `3940256099942544`.
- `bundletool` is installed with `brew install bundletool`.

Run the release app once on a device before uploading: see [02 Testing](02-testing.md), "Check the release build on a device".

## Part F. Upload to Google Play

1. Play Console > your app > **Testing > Closed testing** (or **Production**) > **Create new release**.
2. Upload `app-release.aab`. Wait until Play shows the name and version.
3. Write release notes, for example "Fixes startup crash and adds a password prompt for locked PDFs".
4. **Save > Review release > Start rollout**. Closed-test releases go through a review before testers can update.
5. Testers who are already opted in receive the update from the Play Store; no new link is needed.
6. After the 12-tester / 14-day closed test, apply for production access, build with the **real** ad IDs (Part D2) and a higher version number, and create the production release.

## Quick checklist

- [ ] `key.properties` exists and the build says signed (`jar verified.`)
- [ ] Version number higher than the last upload
- [ ] Test IDs for the closed test, real IDs only for production
- [ ] AdMob consent message published
- [ ] Release build opened on a device with no crash
- [ ] `.aab` uploaded, `mapping.txt` attached
