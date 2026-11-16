# Doculoom

An offline document app for Android, built with Flutter. Scan and crop pages with live edge detection, apply filters, export PDF and Word, and work with files using on-device tools: lock and unlock, compress, split, sign and redact PDFs, text recognition (OCR), spreadsheets, presentations, passport photos, QR sharing and more. Documents stay on the phone; the only network use is ads and the optional end-to-end encrypted "Anywhere" QR share.

| | |
|---|---|
| Package | `com.doculoom.app` |
| Platform | Android 7.0 (API 24) and newer; iOS project present but not published |
| Stack | Flutter 3.44 / Dart 3.12, BLoC (`flutter_bloc`), `get_it`, `go_router`, SQLite (`sqflite`), Google ML Kit, Google Mobile Ads |
| Architecture | Feature-first Clean Architecture (`presentation -> domain <- data`) |
| Store page | https://play.google.com/store/apps/details?id=com.doculoom.app |

## Quick start

```bash
git clone https://github.com/darshanreddy4/ScannerApp.git
cd ScannerApp/app
flutter pub get
flutter doctor -v        # Android toolchain must be ticked
flutter run              # phone or emulator; uses Google test ads
```

Requirements: Flutter 3.44, JDK 17, Android SDK with command-line tools, a phone or emulator running Android 7.0 or newer.

## Guides

Step-by-step guides are in [`guides/`](guides):

| Guide | Covers |
|---|---|
| [01 Getting started](guides/01-getting-started.md) | Tools to install, running on a phone or emulator, building an APK, folder map, troubleshooting |
| [02 Testing](guides/02-testing.md) | Running all, single and layout-sweep tests, relay tests, checking the release build |
| [03 App icon](guides/03-app-icon.md) | Changing the launcher, themed and Play Store icons |
| [04 Configuration](guides/04-configuration.md) | Build-time settings, Gradle properties, package name, version, permissions |
| [05 Build the .aab and add AdMob IDs](guides/05-build-aab-and-ads.md) | Upload key, signed bundle, where the AdMob IDs go, uploading to Google Play |
| [06 Raise the target API level](guides/06-raise-target-api.md) | Meeting Google Play's yearly target API rule: upgrade Flutter, rebuild, test, release |

The sections below hold the detailed feature status, Play Store checklist, relay deployment and roadmap.

<details>
<summary>Original project brief</summary>

Act as a Senior Mobile App Developer and Systems Architect. I want you to write the complete blueprint and initial foundational code for a cross-platform mobile scanner and document-intelligence application built using [Flutter / React Native - CHOOSE ONE].
 
The app must be modular, adhering to Clean Architecture principles, ensuring that Phase 1 features function perfectly before Phase 2 AI features are integrated.
 
---
 
### CORE SYSTEM SPECIFICATIONS
 
#### PHASE 1: SMART DOCUMENT SCANNER & SHARING (Core Foundation)
1. Camera & File Import:
   - Implement a custom camera preview with automatic edge-detection for documents.
   - Support file picking for external images (JPEG, PNG).
2. Image Processing & Cropping Logic:
   - Integrate a responsive quadrangle/polygon cropping UI allowing the user to adjust the 4 corners of the document.
   - Implement image manipulation filters using native platform channels or high-performance canvas drawing: B&W/Document enhancer, Magic Color, grayscale, and brightness/contrast adjustments.
3. Export & Share Pipeline:
   - Package processed images into a multi-page PDF generation engine.
   - Implement a basic DOCX exporter that wraps images into a standardized document structure.
   - Use the native OS share sheet to allow sharing generated .pdf and .docx files.
4. Local Storage Architecture:
   - Set up a secure local database (SQLite/Room/Hive) to manage scanned documents, metadata, page order, and raw file paths locally on the device.
5. Monetization Integration:
   - Integrate the Google Mobile Ads SDK.
   - Implement an architecture that displays Interstitial ads after a document is successfully saved/exported, and a Banner ad at the bottom of the main dashboard, restricted strictly to "Free Plan" users.
 
#### PHASE 2: LOCAL DOCUMENT INTELLIGENCE AGENT (On-Device Local AI)
1. Local Text & Data Parsing:
   - Build a local file ingestion service. For .txt, .csv, and structured files, parse them natively into string data.
2. Multilingual OCR & Math Parsing Pipeline:
   - Implement a lightweight, on-device OCR engine (such as Google ML Kit Document Text Recognition or a highly optimized local ONNX pipeline) capable of extracting Hindi, Arabic (Right-to-Left formatting), and alphanumeric text.
   - Set up a text regex and parsing cleaner to isolate math notation and maintain structure.
3. On-Device RAG & Vector Database:
   - Integrate a lightweight embedded vector database or text indexing system (e.g., ObjectBox Vector DB or custom local TF-IDF/embeddings engine) to index the extracted text of saved documents.
4. Local Inference VLM/LLM Executor:
   - Set up an on-device execution layer using [MLC LLM / ExecuTorch] running an optimized, quantized small language model (e.g., Llama-3.2-3B-Instruct or Phi-3.5-mini quantized to 4-bit) to act as the offline chat agent.
   - Create a chat UI interface that allows users to query their saved documents, pulls relevant document text chunks from the local vector database (RAG), feeds them as context to the local model, and streams the answer back.
 
---
 
### ARCHITECTURAL REQUIREMENTS
- Language & Framework: Use [Dart for Flutter / TypeScript for React Native].
- State Management: Implement a clean state management pattern ([BLoC/Provider for Flutter] or [Redux/Zustand for React Native]).
- Security: Document text and processed images must remain strictly local to the user's device for complete privacy.
- Error Handling: Provide robust try-catch wrappers for file system reading/writing and image processing memory management to avoid app crashes during large PDF exports.
 
Please begin by generating the directory structure for this Clean Architecture setup, followed by the foundational code for Phase 1 (Camera, Polygon Cropping UI, and Image Filter processing).

before writing code i want you to design a protype model of all mobile screens and share with me

</details>

---

# Project Status

**Stack:** Flutter 3 / Dart 3, BLoC (`flutter_bloc`), `get_it`, `go_router`, SQLite (`sqflite`), Lucide icons (`lucide_icons_flutter`).
**Location:** Flutter app in [`app/`](app), screen prototype in [`prototype/index.html`](prototype/index.html).
**Decisions:** Flutter, BLoC and MLC LLM (for Phase 2).

## Run and verify

```bash
cd app
flutter pub get
flutter analyze
flutter test            # all tests (see guides/02-testing.md for single files and the slow layout sweep)
flutter run             # needs an emulator or a connected phone
```

The camera needs a real device. Import, crop, filters, save, export and share also work on a simulator.

Behind a TLS-inspecting proxy (e.g. Netskope), Gradle may fail with `PKIX path building failed`. Fix: build a Java truststore that includes the company root CA and pass it through `JAVA_TOOL_OPTIONS`:

```bash
export JAVA_TOOL_OPTIONS="-Djavax.net.ssl.trustStore=$HOME/.scanvault-build/cacerts -Djavax.net.ssl.trustStorePassword=changeit"
flutter build apk --debug
```

## Architecture

Feature-first Clean Architecture. Dependencies point inward: `presentation -> domain <- data`.

```
app/lib/
  main.dart                      bootstrap, error zone, portrait lock, temp cleanup
  app/                           di.dart (get_it), router.dart (go_router), app.dart, router_observer.dart
  core/
    error/                       Failure types, Result<T>, guard() wrapper
    theme/                       app_colors.dart (tokens), app_theme.dart, app_icons.dart (all icons)
    utils/                       date and label formatting
    widgets/                     BusyOverlay, showFailure()
  features/
    scanner/                     camera, edge detection, crop, filters
      domain/                    Quad, FilterSettings, ScannerRepository, use cases
      data/                      document_edge_detector, rgb_buffer (+ perspective warp), image_filters,
                                 image_processing_service (isolates), ScannerRepositoryImpl
      presentation/              CameraCubit, ScanSessionCubit; camera, crop, enhance pages
    documents/                   library, review, detail
      domain/                    ScannedDocument, DocumentPage, DocumentRepository, use cases
      data/                      SQLite data source + app-private file storage
      presentation/              DocumentsCubit, DocumentDetailCubit; home, review, detail pages
    export/                      PDF and DOCX builders, share sheet
    monetization/                PlanStatus, AdPolicy, AdMob service, banner slot, PlanCubit
    settings/                    settings tab, paywall stub
```

## Phase 1: done

| Area | Status | Notes |
|---|---|---|
| Front and back camera | Done | A switch button appears when the device has both cameras (and the app falls back to the only camera on front-only tablets). The front camera captures manually (no live outline, no flash). Tablet and landscape support is described below. |
| Tablets and large screens | Done | Phones stay in portrait; tablets and foldables rotate freely. Windows 600 dp and wider get a navigation rail instead of the bottom bar, a multi-column library, readable centred content, and side-by-side layouts (crop, editor, print) in landscape. The camera moves its controls to the side when held sideways. Not yet verified on real tablets. |
| Camera with live edge detection | Done | Region-based detector (Otsu + largest region + extreme corners) on a downscaled frame, about 5 fps. Auto-capture when the outline is steady (re-arms only after the document leaves the frame). Flash and auto/manual toggles. |
| Multi-page capture | Done | Capture many pages in one session. After each photo: crop screen with Retake / Continue; Continue returns to the camera. Last-page thumbnail with a page counter and a Done button. |
| Image import (JPEG/PNG) | Done | Multi-select gallery picker. Selected images are queued through the crop screen one by one (Retake skips an image). Unreadable images are skipped. EXIF baked in, long side capped at 2400 px. |
| Crop screen | Done | 4 corner + 4 edge handles, magnifier, rotate, full page, auto-detect reset, document name, current-filter dropdown, and an option to skip the crop screen after capture. |
| Page editor | Done | Swipe between pages, real filter thumbnails per page, brightness/contrast, Apply to all pages, hold-to-compare with original, Crop again, Rotate, Rearrange/delete, Add more pages, editable document name. Heavy rendering happens once, on save, with progress. |
| Folders | Done | Create, rename, delete folders (documents move back to the main list). Move documents between folders, scan straight into a folder. |
| Import PDF | Done | Each page is rendered to an image (about 2000 px) with the platform PDF renderer, then opens in the page editor. Up to 200 pages. Password-protected files show a clear message. |
| Import Word (.docx) | Done | Images are extracted in document order. Text is laid out onto A4 pages (formatting is not preserved). Legacy `.doc` is rejected with a message. |
| Merge documents | Done | Long-press to select documents (numbered in pick order), then Merge into a new document, with an option to delete the originals. Bulk move and bulk delete use the same selection. |
| Edit saved documents | Done | Edit button on the document screen reopens it in the page editor with every page's crop, filter and sliders restored (original, cropped and processed images are stored). Add pages from camera, gallery, PDF or Word, reorder, delete, re-crop, rotate, rename, then save in place. Pages saved before this feature open using the finished image as the source. Database upgraded to v3 with a migration. |
| Feature access control | Done | `FeatureAccess` decides who sees a feature. Editing is a Premium feature with an owner switch in Settings (debug builds): off hides the Edit button for everyone, on unlocks it for Premium users and shows a lock plus Upgrade prompt for Free users. Replace the local switch with remote config for production. |
| Tools hub | Done | Third tab with file tools: Read PDF or Word, Edit a PDF, Combine files, QR code generator. |
| Files kept in the app | Done | Everything the app makes (Word, Excel, PowerPoint, PDF, text, pictures) is also kept in the library, so it shows on the home screen and in folders next to scans and can be renamed, moved, tagged, favourited, locked, shared, saved to Files, duplicated, deleted and backed up. A file is added when it is shared or saved to Files or the gallery (the same name and content is never added twice); the Word, PDF, Excel and PowerPoint editors also have **Save in Doculoom**, which adds the file or, when it was opened from the library, puts the new version in its place. Tapping a file opens it in its own tool (Word editor, spreadsheet, slides, PDF reader, text viewer). Pictures are kept as one document with a page each. Exports of a scan and backup files are not added again. DB version 9 adds the file column; backups include the files. |
| Use files from Doculoom in any tool | Done | Wherever a tool asks for a file or a photo (PDF tools, photo tools, OCR, sign, watermark, expenses, ID card, office converters, scanner import, and more) the picker first asks **From this device** or **From Doculoom**. The Doculoom list shows only what the tool can use: matching files, and scans as a PDF (tools that take PDFs) or as pictures (tools that take pictures); it has search, folders, locked folders ask for the phone lock, and multi-select where a tool takes several. Tools get a private copy, so the library file is never changed by a tool. If nothing in the library fits, the normal device picker opens directly. |
| Spreadsheets | Done | Tools > Spreadsheets opens .xlsx and .csv files, or starts a new one. Grid with frozen panes, merged cells and sheet tabs; edit cells and formulas, bold/italic/underline, colours, number formats, wrap, merge, insert/delete rows and columns, sort, find, copy/paste, fill, AutoSum, undo/redo. About 140 functions are recalculated (SUM, IF, VLOOKUP, XLOOKUP, SUMIFS, AVERAGEIFS, TEXTJOIN, DATEDIF, NETWORKDAYS, STDEV, RANK, PERCENTILE, PMT, FV and more); the **fx button** next to the formula bar opens a searchable function list by category (Math, Statistics, Logic, Text, Date and time, Lookup, Money) with the syntax and a one-line description, and puts the chosen function into the cell. **Starters:** New spreadsheet offers 11 ready-made sheets with sample rows and the formulas in place: marks and grades (total, percent, grade, rank), attendance, weekly timetable, monthly budget, expense tracker (totals by category), savings goal, loan calculator, invoice, project tracker, sales summary and stock list. Yellow cells are for typing. **Save as my template** (in the Save sheet) keeps any workbook under My templates. Other functions keep the value stored in the file and Excel recalculates them on opening. Images and pivot tables are kept in the file but not shown. **Charts** (sheet menu, Add chart from selection): column, bar, line, area, pie, doughnut and scatter charts of the selected cells (a top row of words names the series, a first column of words names the points, each column of numbers is a series; one cell stands for the block around it). Charts sit over the grid: tap one to select it, drag to move it (it snaps to cells), drag the corner to resize it, or use the pencil and bin on it. The Charts list also shows every chart and lets you share it as a picture, save the picture in Doculoom or remove it. Piled bars and areas can be shown as shares of 100%. They are written as real Excel charts with a cached copy of the values, so Excel, LibreOffice and Google Sheets show them. Charts already in a file are listed and drawn when they are one of those kinds (changing one resets its colours and styling unless the colours are plain ones the app can read; 3-D charts become flat ones); charts the app cannot draw (bubble, stock, radar, sideways bars mixed with other kinds and so on) are kept as they are and can only be moved or removed. **Series settings** (pencil, then Series, colours and trend lines): the colour of each series, how it is drawn (columns, a line or an area in the same chart), a second scale at the right edge for a series with very different numbers, a trend line (straight, exponential, curved or moving average) that can show its equation and R squared, value labels (and percentages on pies and doughnuts), and the colour of single bars or slices, all written as real Excel combined charts, series colours, trendlines, data labels and data points. A chart follows rows and columns inserted or deleted and renamed sheets, and undo covers it. Charts are included in the Excel to PDF export, on pages after the cells of their sheet. Not yet: bubble charts, chart styles, label positions and number formats. **Highlight cells by value** (sheet menu): greater than, less than, equal, not equal, between, text contains, duplicate values and 2- or 3-colour scales, with ready looks (light red, yellow, green, blue, red text, bold green); shown in the grid and in PDF export, written as real conditional formatting (rules the app does not know, such as data bars or formula rules, stay in the file). **Allow only certain values:** a list of choices (the cell gets a drop-down arrow beside the formula bar) or a whole or decimal number between two limits; other entries are refused with a message; written as real data validation. Rules follow their cells when rows or columns are inserted or deleted, and undo covers them. Convert: Excel to PDF, Excel to CSV, CSV to Excel. |
| Presentations | Done | Tools > Presentations opens .pptx files, or starts a new one. Slides are drawn with theme, layout and master inheritance (text, shapes, pictures, tables); edit text, move and resize items, add text, shapes and pictures, add, duplicate, reorder and delete slides, change backgrounds. Not drawn: SmartArt, charts, video and animations (kept in the file). **Slide show effects:** fade, push, wipe or cover for one slide or all slides (written as real transitions, seen in the slide show with swipe or tap, and other kinds of effect in a file are kept). **Speaker notes:** edit the notes of each slide (real notes pages and a notes master are written; python-pptx reads them) and show them in the slide show with the notes button. Convert: PowerPoint to PDF or images, images to PowerPoint, PDF to PowerPoint (pages as pictures). **Starters and layouts:** New presentation offers 7 ready-made sets (school project, book or topic report, study summary, business pitch, team update, results review, training) in 8 colour themes (including a dark one), each with a title slide, section headers, two-column and bullet slides and suggested headings to overwrite. The Slide layouts button adds a slide with the Title Slide, Title and Content, Section Header, Two Content, Title Only or Blank arrangement. **Save as my template** (in the Save sheet) keeps the deck under My templates for later. **Picture crop:** select a picture and tap Crop for a slider on each edge with a live preview, and an outline of rectangle, rounded or oval; the picture keeps its scale and the frame shrinks to what stays. It is written as a real crop, so the file keeps the whole picture and Reset gives it back. Files are real .pptx with their own layouts and theme (python-pptx reads them). |
| New Word document and templates | Done | Tools > New Word document: blank page or ready-made templates for school and work (assignment, study notes, weekly study plan, report, meeting minutes, formal letter, leave application, resume). The file opens in the Word text editor, where each paragraph can be set to Title, Heading 1 to 3 or Normal, turned into a bullet or numbered list, and given bold, italic, underline, size, colour and alignment. Save as a copy, share it, or **Save as my template** to start later documents from it (My templates list, stored on the phone). Files are real .docx (styles and numbering included) and also open in Word. New documents use A4, or Letter when the region is the US. **Header and footer** (button in the editor): text at the top and bottom of every page and "Page x of y" numbers, written as real header and footer parts. **Pictures:** Picture below adds a JPG or PNG (from the phone or from Doculoom) in its own paragraph, scaled to fit the page. |
| PDF and Word reader | Done | Opens a file without importing it (PDF with pinch zoom and page counter; Word rendered to pages). Menu: Edit pages, Save to library, Share file, Share with QR code. **Search in file:** a magnifier opens a search bar; matches are highlighted on the page with a count and next/previous arrows. PDF text is read on the phone by the app's own parser (embedded fonts, accents, turned pages); scanned PDFs show a message to use OCR instead. Word files are drawn page by page the way they are designed (page size and margins, fonts and colours, lists, tab stops, tables with shaded cells and borders, pictures, coloured sidebars), and the text is searched on those pages; a file that is only pictures, or one this drawing cannot read, falls back to the plain text and picture pages. Editing a Word file as pages uses the same drawing. |
| Edit a PDF | Done | Tools > Edit text in a PDF. **Edit text:** tap a line to retype or remove it (standard fonts of the same kind, size and colour). **Add text:** tap the page, choose size, colour, bold, italic and sans, serif or mono; drag added text to move it. **Mark:** drag on the page to draw a highlight (colour shows through the text), a cover-up that hides what is under it, a box or a line, in six colours; tap a drawing to recolour or remove it. **Picture:** tap the page to place a JPG or PNG (a logo, stamp or photo; transparent PNGs keep their see-through parts), drag it to move it and set its size. Everything is written into the PDF on the phone (nothing is uploaded), works on turned pages, and undo covers every change. **Hindi, Arabic, Chinese and other scripts:** text the built-in fonts cannot show (typed as new text or when retyping a line) is drawn by the phone's own text engine and placed as a picture, so it looks right in every language; it cannot be selected or searched afterwards. **Scanned pages:** a page with no text layer offers Find text in this scan (English and other Latin letters, or Hindi and Marathi), using the on-device text recognition; tap a framed line to retype it, and the old writing is covered with the colour of the paper while the new words take its size and colour. Limits: the file's own text can only be retyped in standard fonts of the same kind; password-protected PDFs must be unlocked first. |
| Coins and rewarded videos | Done | Free users earn 10 coins per rewarded video (10 videos a day) from the Coins card in Settings or from a prompt when a feature is short on coins. Coins pay for Edit saved pages (5 per use) and a custom QR share time (2 per share screen). Premium users never need coins. The balance is local (SharedPreferences), so it can be tampered with on a rooted phone and is lost on uninstall; server-side reward verification would need a backend. Disable with `--dart-define=REWARDS_ENABLED=false`. Rewarded ad unit IDs: `ADMOB_REWARDED_ANDROID` / `ADMOB_REWARDED_IOS`. Coin purchases are not built (they would need Google Play Billing). |
| Photo tools (standalone, offline) | Done | **Compress photos:** target size (20 kB to 1 MB or custom), resize by longest side, JPG or PNG; lowers quality first and pixel size only if needed. **Passport and ID photos:** about 40 countries with their sizes (India, US, UK, Canada, Australia, EU, Gulf, East and South Asia and more) plus custom mm, inch or pixel sizes, crop with a head guide, optional background replacement on plain walls, 300 or 600 dpi, "under 20/50/100/200/500 kB" without changing pixels, and print sheets (4x6, 5x7, A4, Letter) as exact-size PDF and JPG. **Add watermark:** text, logo or both on photos and PDF pages, one mark or a repeated pattern, size, strength, angle, colour, live preview, presets, saved business profile (name, GST/phone line, logo).  **Remove photo data:** shows the location, phone or camera, date and editing program hidden in JPG and PNG photos and writes clean copies without touching the picture (the JPEG scan data is copied byte for byte; only the orientation flag is kept). **Compress PDF:** redraws the pages at lower quality step by step (2000 px / quality 85 down to 700 px / 40) until a target size is met, shows before and after, and keeps the original when it cannot get smaller; text becomes picture. **Split and number PDF:** select pages by tap, odd/even or ranges, keep or remove them, turn them, split into single pages, every N pages or ranges, add page numbers (3 styles, 3 positions), a header and a footer printed with the phone's own text engine so every script works. **Markup (in the page editor):** pen, pencil and highlighter (see-through, multiply blended) with colour grid and ring picker, opacity and thickness; square, circle, arrow and line shapes with optional fill; emoji stickers from a built-in palette or typed in, which can be moved, pinched to resize and turned; eraser (removes the touched mark), undo/redo, zoom, move and delete. Marks are stored relative to the page and drawn on the full-size page with the same painter used on screen, after the colour filter; they work on pages from scans, PDFs and Word files, and become part of the page picture. **Lock or unlock PDF:** adds a password with AES 256-bit encryption (standard security handler, revision 6) or removes it when the password is known (RC4 40 and 128 bit, AES 128 and 256 bit, revisions 2 to 6, owner or user password), by rewriting the PDF structure itself so text, images, links and forms stay intact; the PDF reader/writer is Dart code checked against files from pikepdf and pypdf, and the output was opened with both. Wrong passwords are refused, nothing is cracked, and forgotten passwords cannot be recovered. **ID card copy:** front and back (back optional) cropped to 85.6 x 54 mm, passport page, A6 or a custom size, placed on A4 or Letter at real size or enlarged, optional black and white and cut line, as a 300 dpi JPG and an exact paper size PDF with a Print button. **Signature:** draw with a finger (3 pens, 3 inks) or lift ink from a photo of a signature on white paper (uneven light evened out, adjustable for faint lines), keep up to five on the phone, drag and resize the signature on a preview of any PDF page or photo, and apply it to this page, the last page or every page. It is a picture of a signature, not a certified digital signature. All of it runs on the phone; sizes are common values and the screens tell people to confirm them with the issuing office. Background replacement only works on plain, evenly lit backgrounds, and the head guide is manual (no face detection). |
| Share by QR code | Done | Two modes. **Same Wi-Fi:** the phone serves the file behind a random 128-bit link (stop any time, live download counter); nothing is uploaded. **Anywhere:** the file is encrypted on the phone (AES-256-GCM), uploaded to the sharing relay (`relay/`) and opened in any browser on any network or mobile data; the key lives only in the link's `#fragment`. Free users get 5 minutes; Premium users choose 15 min, 30 min, 1 hour (both modes), 6 hours, 1 day or 7 days (Anywhere). Files up to 25 MB. **Optional password:** Wi-Fi shares show a password page served by the phone (constant-time check, link locks after 5 wrong tries, 4+ characters; sent over the local network without encryption). Internet shares derive the key from the password (PBKDF2-SHA256, 300,000 rounds, 8+ characters), so the link holds no key and the browser page asks for the password before decrypting; the password never leaves the phone. A QR code cannot hold a PDF itself (about 2.9 KB limit), so the QR carries the download link. **Keeps running:** a share belongs to the app, not to the QR screen. Going back, minimising or closing the app does not end it; only its timer, "Stop sharing" (screen, Documents tab list or notification) does. On Android the Wi-Fi server runs natively in a foreground service (`ShareServer.kt`, `ShareService.kt`) with a Wi-Fi and wake lock, a countdown notification and a Stop action, and works on a private copy of the file; internet shares are saved so Stop still reaches the relay after a restart. **Download page:** opening a link always shows a page with a Download button (no download is used up by link previews or scanner apps); protected shares check the password in the page without reloading, with tries left, lock after 5 wrong tries, progress and a "Download complete" message; a download counts only when the whole file arrived. Needs the relay redeployed (`npm run deploy` in `relay/`) for the small internet-page message. |
| QR code generator | Done | Text, link or Wi-Fi network (standard `WIFI:` format) to a QR code, shareable as an image. |
| Combine files | Done | Merge several PDF and Word files in the order picked into one editable document. |
| Document actions sheet | Done | The three-dot menu on any document (and on the detail screen) opens one sheet: header with thumbnail, name (tap to rename), pages, size and date; quick tiles for Share PDF, Share images (JPG), Print, Compress, Lock and Delete; rows for Save to Files or Drive, Save images to gallery, Share as Word, Share with QR code, Move to folder; expandable Edit (Edit pages, Split, Rename) and More (Favourite, Pin to top, Tags, Duplicate, Date and time). |
| Print | Done | Settings page with live preview: copies, orientation, page range, colour or black and white, paper size, margins, pages per sheet, fit or fill, and presets. The final step opens the Android print sheet, where the printer, two-sided printing and paper tray (Xerox, HP, Canon, Epson, Brother, any Mopria or print-service printer) is chosen. |
| Folder lock and favourites | Done | Folders can be locked (phone lock needed to open, rename or delete) and marked favourite. A Favourites chip on the Documents tab lists favourite folders and documents. Search and Favourites never show documents inside a locked folder. Database v5. |
| Text recognition (OCR, Phase 2) | Done, untested on a device | Document menu > Extract text (OCR). Runs fully on the phone with Google ML Kit (Latin and Devanagari models bundled; pick the language on the screen or in Settings). Each page is turned into Markdown (headings from line height, paragraphs from line gaps, bullet and numbered lists, de-hyphenated line breaks) and shown with `flutter_markdown`; formulas such as `x^2`, square roots, fractions like `a/b = c/d`, Greek letters and symbols are converted to LaTeX and typeset with `flutter_math_fork` (inline `$...$`, display `$$...$$`; a formula that cannot be parsed falls back to plain text). Edit mode corrects mistakes by hand, with Copy all and Share as Markdown file. Text is saved in the new `page_text` table (database v6), searched by the Documents search box (two or more characters) and removed with the document or when its pages are edited. |
| Terms, privacy and support | Done | Settings > About: Help and support (email, report a problem with app version, FAQ), Terms and conditions, Privacy policy, open-source licences, version. |
| Lock | Done | Lock a document with the phone's fingerprint, face, PIN, pattern or password (`local_auth`). Locked documents hide their thumbnail and need the phone lock to open or act on. |
| Library | Done | Search, sort (newest, oldest, name), list/grid view, rename, move, delete. |
| Settings | Done | Crop screen after capture, auto-capture, default filter, default export quality. Persisted locally. |
| Local storage | Done | SQLite (`documents`, `pages`), files in the app-private folder, relative paths, transactional save with cleanup on failure. |
| PDF export | Done | One page per image, High/Medium/Low quality, built in an isolate. |
| DOCX export | Done | Standard OOXML package, one image per page. |
| Share | Done | Native OS share sheet. |
| Ads | Done (test IDs) | Banner on the dashboard, interstitial after save and export, 2-minute cooldown, Free plan only. |
| Error handling | Done | Typed failures for storage, memory, permission, camera, database and export, shown as user-readable messages. |
| Design system | Done | Neutral enterprise theme, single icon source (Lucide), no emoji. Dashboard has search, quick actions, page-count badges, delete, and a call-to-action empty state. Detail page has a thumbnail strip and one-tap PDF/DOCX share. |
| Tests | Done | 210 tests, including OCR storage, structuring, formula conversion, Markdown/math rendering, the OCR screen at 320 dp and tablet widths, v5 to v6 migration and library text search (ML Kit itself cannot run in unit tests; a fake engine stands in); earlier 96 tests, including folder lock and favourites, v4 to v5 migration, including the actions sheet, favourite/pin/lock/tags, split, duplicate, compress, v3 to v4 migration and delete-all. Earlier coverage: edge detector, perspective warp, filters, PDF and DOCX output, DOCX import parsing, ad policy, Quad geometry, the multi-page scan session (queue, retake, apply to all, re-crop, reorder, file import, edit and update saved documents), the SQLite layer (edit metadata, replace pages, failed replace, v2 to v3 migration) and feature access. |
| Android and iOS config | Done | Camera and photo permission strings, AdMob test app IDs, `minSdk 24`, backup disabled. |

## Phase 1: left to do

- **Run on a real device** and tune edge-detection thresholds against real photos (low light, patterned backgrounds, white-on-white).
- **APK build:** debug APK builds successfully (`Doculoom-debug.apk`, git-ignored). Needs the truststore setting above on networks that inspect TLS. `phosphor_flutter` was replaced by Lucide because it does not compile on Flutter 3.44.
- **Remote feature switches:** the owner switch for editing is a local setting shown in debug builds only; move it to remote config (and server-verified entitlements) before release.
- **Word import fidelity:** layout, fonts, tables and RTL alignment are not reproduced for text; legacy `.doc` is unsupported.
- **Real purchases:** paywall is a debug-only stub. Until `in_app_purchase` with receipt validation is built, release builds run with `BILLING_ENABLED=false`: no Premium screen, nothing is locked.
- **Database encryption:** swap plain SQLite for SQLCipher if encryption at rest is required.
- **Optional app lock** (biometric) and settings for PDF quality and auto-capture.
- **Widget and integration tests** for the scan flow, plus CI.
- **Splash screen, onboarding** and Play screenshots.
- **Not built from the reference screens:** Send to Email (use Share, which lists email apps), Add to Home Screen, Collage / multi-side document, OCR Text (now built, see Phase 2).
- **Update `prototype/index.html`** to use the final icon set instead of emoji placeholders.

## Publishing to Google Play

What the code already does for store rules:

- **Terms and conditions, Help and support** and open-source licences inside the app (Settings > About).
- **Privacy policy** inside the app (Settings > Privacy > Privacy policy) and an optional public link (`PRIVACY_POLICY_URL`).
- **Ad consent** with Google's User Messaging Platform (EEA/UK form, "Ad privacy choices" entry in Settings where required). No ad is requested before consent is resolved.
- **Delete all my data** in Settings, plus per-document delete.
- **Minimal permissions:** camera (only while scanning), biometric (lock), internet (ads and Wi-Fi sharing), storage write requested only on Android 9 (API 28) and older, for saving images to the gallery; Android 10 and newer need no storage permission. The app supports Android 7.0 (API 24) and newer. No contacts, location, microphone or broad file access.
- **No misleading Premium:** release builds hide the Premium screen and lock nothing until real billing exists (`BILLING_ENABLED`).
- **Release signing**, code shrinking, no debug-key release, app icon, AdMob IDs injected at build time.

Steps only you can do:

1. **Developer account** (one-time fee) and an app named per Play's naming rules.
2. **Upload key:** `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`, then copy `android/key.properties.example` to `android/key.properties` and fill it in. Never commit either. Enrol in Play App Signing.
3. **AdMob:** create the app and ad units. Build with the real IDs:
   `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-.../... --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-.../... --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-.../... --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-.../... --dart-define=PRIVACY_POLICY_URL=https://your-site/privacy --dart-define=TERMS_URL=https://your-site/terms --dart-define=SHARE_RELAY_URL=https://doculoom-share.your-name.workers.dev --dart-define=SUPPORT_EMAIL=you@your-site -PadmobAppId=ca-app-pub-...~...`
   Create the UMP consent message in the AdMob console (Privacy and messaging) or the consent form will not appear. Full walk-through: [guides/05-build-aab-and-ads.md](guides/05-build-aab-and-ads.md).
4. **Host the privacy policy** on a public URL (same content as the in-app page) and enter it in Play Console > App content. Have a lawyer review the privacy policy and terms (`privacy_page.dart`, `terms_page.dart`) for your country and company name; they are plain-language drafts, not legal advice. Set up a real support mailbox for `SUPPORT_EMAIL`.

   **Earning from ads:** create an AdMob account, link payment details, and add `app-ads.txt` to the website listed as your developer website in Play Console (AdMob shows the exact line). Revenue depends on installs and use. Never tap your own live ads (use test devices); invalid traffic gets the account banned. Banners show on the Documents, Tools and Settings tabs and inside folders. Interstitials show after saving or exporting, at most once every 2 minutes.
5. **Data safety form:** answer as follows. Data collected and shared: Device or other IDs and App activity/diagnostics via Google AdMob, used for advertising and analytics, processed ephemerally off-device by Google. Documents, photos and files are processed on-device and not collected, with one exception: if the user chooses QR sharing > Anywhere, an end-to-end encrypted copy of that one file is sent to your sharing relay and deleted at expiry. Declare **Files and docs** as collected, purpose App functionality, optional, encrypted in transit, deletable (automatic expiry and Stop sharing). Check Google's current Data safety help to confirm how it classifies user-initiated uploads. Without `SHARE_RELAY_URL` this feature is hidden and the exception does not apply. Data is encrypted in transit; users can request deletion (in-app option). If you later add crash reporting, analytics or sign-in, update the form first.
6. **Content rating questionnaire**, **target audience** (13+ or 18+; do not choose children), **Ads declaration** ("contains ads": yes), **News/health/finance declarations** (none apply).
7. **Store listing:** short and full description that do not promise features that are missing, 2 to 8 phone screenshots, feature graphic 1024x500, icon `store/play-store-icon-512.png`.
8. **Testing track:** new personal accounts must run a closed test with at least 12 testers for 14 days before production (current Play policy; check the console for the latest numbers).
9. **Target API level:** Flutter's template follows Play's requirement, but confirm `targetSdk` in the release bundle each year.
10. **If you add Premium purchases later:** use Google Play Billing only (`in_app_purchase`), state price and renewal terms on the paywall, offer a way to cancel, and set `BILLING_ENABLED=true`.

### Sharing over the internet: deploy the relay

"Anywhere" QR sharing needs a small service because a phone on mobile data or another Wi-Fi cannot be reached directly. The code is in `relay/` (a Cloudflare Worker plus an R2 bucket). The app encrypts the file before upload and the key never leaves the link, so the service stores only unreadable bytes.

One-time setup (free Cloudflare plan is enough to start; R2 needs a payment method on file, with a free monthly allowance):

1. Create a Cloudflare account and install Node.js.
2. In `relay/` run `npm install`, then `npx wrangler login`.
3. Create the bucket: `npx wrangler r2 bucket create doculoom-share-files`.
4. Deploy: `npx wrangler deploy`. Note the address it prints, for example `https://doculoom-share.your-name.workers.dev` (or attach your own domain in the Cloudflare dashboard).
5. Add a rate-limiting rule in Cloudflare (Security > WAF > Rate limiting) for `POST /api/upload`, for example 20 requests per minute per IP, so nobody can fill the bucket.
6. Build the app with `--dart-define=SHARE_RELAY_URL=<that address>` (no trailing path). Without it the "Anywhere" option shows as not set up.
7. To try it before deploying, run `npx wrangler dev` in `relay/` and point a test build at your computer's address.

How it behaves: files up to 25 MB, lifetime 1 minute to 7 days (the app sends the chosen time, the server enforces the 7-day cap), an hourly job deletes expired files, and "Stop sharing" deletes immediately. `npm test` in `relay/` runs the server and download-page tests.

Limits to know: the app cannot prove someone paid for Premium without real billing, so the longer times are enforced in the app only; the server cap and rate limit protect your costs. Anyone who has the full link can download the file until it expires.

### Linking AdMob after launch: app-ads.txt

Do this once the app is live and has users; it is not needed for testing.

`app-ads.txt` is a small text file that proves to advertisers that you own the app, so they are willing to bid on its ads. Without it some advertisers skip your ad space and earnings can drop.

1. Have a website (a free GitHub Pages, Google Sites or Netlify page is enough). The file must be reachable at the site root: `https://your-site.com/app-ads.txt`.
2. In AdMob open **Apps > View all apps > your app > App settings > app-ads.txt**. Copy the exact line it shows. It looks like `google.com, pub-1234567890123456, DIRECT, f08c47fec0942fa0`, where the `pub-` number is your own publisher ID.
3. Save that line in a plain text file named `app-ads.txt` and upload it to the site root.
4. In Play Console set the same website as the **developer website** on the store listing.
5. AdMob re-checks the file from time to time. The same AdMob page shows the status; it can take a few days to turn green.
6. Link payment details in AdMob, replace the test ad unit IDs with your real ones (see step 3 above) and publish an update.

## Storage and size

- A debug APK (about 260 MB) is not what users download. Release builds are much smaller; build `flutter build appbundle --release` for Play (users get only the code for their phone's CPU), or `flutter build apk --release --split-per-abi` for sideloading.
- The cache folder is cleared at every launch (except files just received from other apps), scan working copies are removed after each save, picked-file copies are removed after an import, and exports and shared copies older than 30 minutes are removed when the app goes to the background. Page folders left behind by an interrupted save are removed at launch.
- Measured release sizes: arm64 phones 27 MB, older 32-bit phones 26 MB, universal APK 71 MB (the debug build is 261 MB because it holds unoptimised code for every CPU).
- Documents keep the original photo, the cropped image and the final image per page so edits stay lossless. A further lossless saving is to re-create the cropped image from the original on demand instead of storing it (about a third less storage for filtered pages); not built yet.

## Open with and Share to

Doculoom appears in "Open with" for PDF, Word (.docx), JPG and PNG files and in other apps' share sheets. PDF and Word open in the reader (edit, save to library, share); images go to the crop and edit flow, or join the scan in progress. Android copies the file into the cache first, so nothing is changed in the original. Files whose type the sending app does not report (shown as a generic file) may not list Doculoom.

## Enterprise roadmap (proposed)

Grouped by the real-world problem each feature solves. Items marked (P2) depend on Phase 2 OCR.

**Trust and compliance**
- App lock with biometrics/PIN and auto-lock timeout; hide content in the app switcher.
- Password-protected PDF export; visible watermark (for example CONFIDENTIAL) and a QR stamp carrying a document ID and hash so printed copies can be verified.
- Redaction tool that permanently blacks out areas before sharing (P2 can suggest names, ID numbers).
- Audit log of exports and shares kept on the device; export of the library for backup and migration.

**Speed for daily work**
- Sign and annotate: draw or type a signature, place it on a page, add text, date stamps and highlights.
- Scan modes: ID card (both sides on one page), business card to contact, receipts, whiteboard, book page flattening.
- Auto-naming templates and tags (for example Invoice-YYYY-MM-vendor), smart folders, pinned and recent files.
- Open-with and share-into the app for PDFs and images from other apps, home-screen widget and quick-scan shortcut.
- Batch export and share of many documents at once; target-size compression for upload portals.
- QR and barcode scanner with history; vCard and Wi-Fi QR import.

**Find and understand (Phase 2)**
- Searchable text from OCR (Hindi, Arabic, English), copy text, text overlay in PDFs.
- Ask questions about your documents with the on-device assistant; extract tables to CSV and invoice fields.

**Teams (needs a backend)**
- Optional end-to-end encrypted sync, shared folders, admin-managed feature switches and licences (replaces the local owner switch).

## Phase 2: OCR done, AI agent not started

**Built: on-device OCR with structured display** (see "Text recognition" in the feature table).

How it fits together: `features/ocr/` holds the engine interface and ML Kit implementation (`MlKitOcrEngine`), `TextStructurer` (layout to Markdown), `MathConverter` (formula detection and LaTeX), `RecognizeDocumentText` (the use case), `OcrCubit` and `OcrPage`, and `MarkdownMathView` (flutter_markdown with inline and display math builders).

Honest limits:
- Arabic (and so right-to-left layout) is not supported: ML Kit has no on-device Arabic model. It needs a separate ONNX or Tesseract pipeline.
- Formulas are recognised by heuristics on plain text lines. Simple one-line formulas work; multi-line fractions, matrices, integrals with limits and handwritten maths are not reconstructed. Edit mode is the fix.
- No table or multi-column reconstruction; columns can be read in the wrong order.
- Size: the release arm64 APK grew from about 27.4 MB to 42.9 MB (armeabi-v7a 37.1 MB, x86_64 45.1 MB) with the Latin and Devanagari models bundled. R8 builds cleanly with the ML Kit keep rules in `proguard-rules.pro`.
- The ML Kit part has only been compiled, not run on a real phone yet.

| # | Item | Status / plan |
|---|---|---|
| 1 | Local file ingestion | Not started. Parse `.txt`, `.csv` and structured files to text in a `features/ingestion` module. |
| 2 | Multilingual OCR | Done for Latin and Devanagari. Arabic still open. |
| 3 | Math and text cleaner | Done (`TextStructurer`, `MathConverter`). |
| 4 | Index and vector store | Not started. Keyword search over OCR text exists; chunk the text, embed it and store it locally (ObjectBox vector DB or custom index). |
| 5 | Local LLM runtime | Not started. MLC LLM behind a platform channel (Kotlin and Swift), 4-bit Llama-3.2-3B-Instruct or Phi-3.5-mini, with model download, checksum, RAM check and streaming. |
| 6 | RAG chat | Not started. Retrieve top chunks, build the prompt, stream the answer with source citations. |
| 7 | Index and model screens | Not started. |
| 8 | Privacy review | OCR makes no network calls. Remaining: model download and AdMob only. |

Suggested next order: ingestion, index, LLM runtime, chat UI.

## Later development (kept on the list)

- **Arabic OCR:** not supported; ML Kit has no on-device Arabic model, so it needs a separate ONNX or Tesseract pipeline (and right-to-left layout).
- **Maths recognition:** basic. Multi-line fractions, matrices, integrals with limits and handwriting are not reconstructed.
- **Tables and columns in OCR:** no table or multi-column reconstruction; columns can be read in the wrong order.
- **Tablet layouts:** built but not verified on real tablets, foldables or Chromebooks.

## Known limitations

- The detector finds a document that fills most of the frame less reliably; the crop screen falls back to an inset rectangle you can adjust.
- PDF and DOCX exports hold images only. OCR text is stored and shareable as Markdown but is not embedded as a text layer.
- Very large exports (dozens of pages at High quality) can run out of memory on low-end phones. The app shows a message suggesting a lower quality. 