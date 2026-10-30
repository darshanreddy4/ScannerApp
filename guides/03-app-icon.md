# 03 Update the app icon

Three places hold the icon. Change all three so the phone, the Play Store listing and the in-store graphics match.

| Where | File(s) | Size |
|---|---|---|
| Phone launcher (Android 8 and newer, adaptive) | `app/android/app/src/main/res/mipmap-*/ic_launcher_foreground.png` and `drawable/ic_launcher_background.xml` | layer is 108 dp: 108, 162, 216, 324, 432 px for mdpi to xxxhdpi |
| Phone launcher, themed icon (Android 13 and newer) | `app/android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png` | same sizes as the foreground |
| Phone launcher (Android 7 to 7.1) | `app/android/app/src/main/res/mipmap-*/ic_launcher.png` | 48, 72, 96, 144, 192 px |
| Google Play listing | `store/play-store-icon-512.png` (upload in Play Console) | 512 x 512 PNG, under 1 MB |
| Master picture | `store/app-icon-1024.png` | 1024 x 1024 |

`app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` ties the background, foreground and monochrome layers together; it normally needs no change. The app name under the icon is `android:label` in `AndroidManifest.xml`.

## Prepare the pictures

1. **Master icon (1024 x 1024 PNG, no transparency, square corners).** Google Play rounds the corners itself. Save it as `store/app-icon-1024.png`.
2. **Foreground layer (1024 x 1024 PNG, transparent background).** Only the picture, no background colour. Android masks the layer into a circle, squircle or square, so keep all important artwork inside the **centre 66 percent** (about 676 x 676 px of 1024). Anything outside can be cut off.
3. **Monochrome layer (1024 x 1024 PNG, transparent background).** The same shape in one flat colour (for example solid black); Android tints it for themed icons.
4. **Background:** a flat colour or gradient. Edit `app/android/app/src/main/res/drawable/ic_launcher_background.xml` (it holds a gradient now; change the colours or replace the path fill with a single `android:fillColor`).

## Generate the launcher files

The script `store/make_launcher_icons.py` resizes the pictures to every density and writes them into the `res` folders. It needs Pillow (`pip3 install pillow`).

```bash
python3 store/make_launcher_icons.py \
  --legacy store/app-icon-1024.png \
  --foreground path/to/foreground-1024.png \
  --monochrome path/to/monochrome-1024.png
```

Give only the layers you changed; the others are left alone. It prints each file it writes.

Play Store icon (512 px) from the master:

```bash
python3 -c "from PIL import Image; Image.open('store/app-icon-1024.png').convert('RGB').resize((512,512), Image.LANCZOS).save('store/play-store-icon-512.png')"
```

### Alternative: Android Studio

Open `app/android` in Android Studio, right-click `app/src/main/res` > New > Image Asset > Launcher Icons (Adaptive and Legacy). Pick the foreground and background layers, tick "Monochrome" for the themed icon, and finish. It writes the same files. Make sure the legacy files are named `ic_launcher.png` as above.

## Check it

```bash
cd app
flutter clean
flutter run --release          # or flutter build apk --release and install it
```

Look at the icon on the home screen, in the app drawer, and with a different launcher shape (long-press the home screen > Wallpaper and style > Icon shape on Pixel phones). On Android 13 or newer turn on Themed icons to check the monochrome layer. An old icon that stays after reinstalling is cached by the launcher: restart the phone or the emulator.

## Other places that show the icon

- **Play Console:** Grow users > Store presence > Main store listing > App icon (the 512 px file). The feature graphic (`store/feature-graphic-1024x500.png`) is built from the app icon by `python3 store/make_feature_graphic.py`, so rebuild it after a redesign. Screenshots are made by `store/make_screenshots.py`.
- **iOS** (not published yet): in Xcode open `app/ios/Runner/Assets.xcassets/AppIcon.appiconset` and drop in a 1024 x 1024 picture without transparency.
- **Privacy policy page** (`docs/privacy-policy.html`) uses no icon file.
