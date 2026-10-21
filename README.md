# ScannerApp
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

---

# Project Status

**Stack:** Flutter 3 / Dart 3, BLoC (`flutter_bloc`), `get_it`, `go_router`, SQLite (`sqflite`), Phosphor icons.
**Location:** Flutter app in [`app/`](app), screen prototype in [`prototype/index.html`](prototype/index.html).
**Decisions:** Flutter, BLoC and MLC LLM (for Phase 2).

## Run and verify

```bash
cd app
flutter pub get
flutter analyze
flutter test            # 14 unit tests
flutter run             # needs a simulator or a connected phone
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
| Camera with live edge detection | Done | Region-based detector (Otsu + largest region + extreme corners) on a downscaled frame, about 5 fps. Auto-capture when the outline is steady. Flash toggle. |
| Image import (JPEG/PNG) | Done | Gallery picker, extension check, EXIF baked in, long side capped at 2400 px. |
| Polygon crop UI | Done | 4 corner handles, 4 edge handles, magnifier, rotate, full page, reset. Perspective-correct warp via homography with bilinear sampling. |
| Filters | Done | Original, Document B&W (adaptive threshold), Magic Color (illumination flattening + saturation), Grayscale, brightness, contrast. Debounced live preview, full-res render on Done. All in isolates. |
| Multi-page review | Done | Add, delete, drag-reorder, rename. |
| Local storage | Done | SQLite (`documents`, `pages`), files in the app-private folder, relative paths, transactional save with cleanup on failure. |
| PDF export | Done | One page per image, High/Medium/Low quality, built in an isolate. |
| DOCX export | Done | Standard OOXML package, one image per page. |
| Share | Done | Native OS share sheet. |
| Ads | Done (test IDs) | Banner on the dashboard, interstitial after save and export, 2-minute cooldown, Free plan only. |
| Error handling | Done | Typed failures for storage, memory, permission, camera, database and export, shown as user-readable messages. |
| Design system | Done | Neutral enterprise theme, single icon source (Phosphor), no emoji. |
| Tests | Done | 14 tests: edge detector, perspective warp, filters, PDF and DOCX output, ad policy, Quad geometry. |
| Android and iOS config | Done | Camera and photo permission strings, AdMob test app IDs, `minSdk 24`, backup disabled. |

## Phase 1: left to do

- **Run on a real device** and tune edge-detection thresholds against real photos (low light, patterned backgrounds, white-on-white).
- **APK build:** debug APK not yet produced. Blocked by the proxy certificate issue above; retry with the truststore setting.
- **Re-edit saved pages:** the original image is stored (`raw_*.jpg`) but there is no "edit again" flow yet.
- **Multi-image import:** the picker takes one image at a time.
- **Library tab and search:** the dashboard only lists documents. Search and sort are not built.
- **Real purchases:** paywall is a debug-only stub. Add `in_app_purchase` with receipt validation.
- **Production ad IDs:** replace Google test IDs in `admob_service.dart`, `AndroidManifest.xml` and `Info.plist`. Add the consent flow (UMP) where required.
- **Database encryption:** swap plain SQLite for SQLCipher if encryption at rest is required.
- **Optional app lock** (biometric) and settings for PDF quality and auto-capture.
- **Widget and integration tests** for the scan flow, plus CI.
- **App icon, splash screen, onboarding** and store assets.
- **Release signing and store builds.**
- **Update `prototype/index.html`** to use the final icon set instead of emoji placeholders.

## Phase 2: not started

| # | Item | Plan |
|---|---|---|
| 1 | Local file ingestion | Parse `.txt`, `.csv` and structured files to text in a `features/ingestion` module. |
| 2 | Multilingual OCR | Google ML Kit text recognition (Latin and Devanagari scripts). Arabic needs a separate model or an ONNX pipeline, because ML Kit does not support it on-device. Keep RTL ordering when storing text. |
| 3 | Math and text cleaner | Regex pass that isolates math notation and keeps line and paragraph structure. |
| 4 | Index and vector store | Chunk the text, embed it and store it locally. Options: ObjectBox vector DB or a custom TF-IDF / embedding index. Hook into the document save flow. |
| 5 | Local LLM runtime | MLC LLM behind a platform channel (Kotlin and Swift), running a 4-bit Llama-3.2-3B-Instruct or Phi-3.5-mini. Includes model download, checksum check, a device RAM check and streaming tokens. |
| 6 | RAG chat | Retrieve top chunks, build the prompt, stream the answer with source citations. Chat UI and citation viewer from the prototype (screens 17 to 22). |
| 7 | Index and model screens | AI model setup and download, index status, ingest files. |
| 8 | Privacy review | Confirm no network calls other than the model download and AdMob. |

Suggested order: ingestion, OCR, cleaner, index, LLM runtime, chat UI.

## Known limitations

- The detector finds a document that fills most of the frame less reliably; the crop screen falls back to an inset rectangle you can adjust.
- DOCX holds images only. There is no text layer until Phase 2 OCR exists.
- Very large exports (dozens of pages at High quality) can run out of memory on low-end phones. The app shows a message suggesting a lower quality. 