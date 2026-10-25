import 'package:go_router/go_router.dart';

import '../features/documents/domain/entities/scanned_document.dart';
import '../features/documents/presentation/pages/document_detail_page.dart';
import '../features/documents/presentation/pages/folder_page.dart';
import '../features/documents/presentation/pages/home_page.dart';
import '../features/ocr/presentation/ocr_page.dart';
import '../features/office/convert/office_converter.dart';
import '../features/office/presentation/office_convert_page.dart';
import '../features/office/presentation/office_hub_page.dart';
import '../features/office/sheets/presentation/sheet_page.dart';
import '../features/text_edit/docx/docx_edit_page.dart';
import '../features/text_edit/pdf/pdf_edit_page.dart';
import '../features/office/slides/presentation/slides_page.dart';
import '../features/photo_tools/presentation/compress_photo_page.dart';
import '../features/id_card/presentation/id_card_page.dart';
import '../features/markup/presentation/markup_page.dart';
import '../features/pdf_tools/presentation/pdf_compress_page.dart';
import '../features/signature/presentation/sign_document_page.dart';
import '../features/signature/presentation/signature_pages.dart';
import '../features/pdf_tools/presentation/pdf_pages_page.dart';
import '../features/pdf_tools/presentation/pdf_password_page.dart';
import '../features/photo_tools/presentation/passport_photo_page.dart';
import '../features/photo_tools/presentation/privacy_clean_page.dart';
import '../features/photo_tools/presentation/watermark_page.dart';
import '../features/print/presentation/print_page.dart';
import '../features/qr/presentation/qr_generator_page.dart';
import '../features/qr/presentation/qr_share_page.dart';
import '../features/reader/presentation/reader_page.dart';
import '../features/scanner/presentation/pages/camera_page.dart';
import '../features/scanner/presentation/pages/crop_page.dart';
import '../features/scanner/presentation/pages/edit_page.dart';
import '../features/settings/presentation/paywall_page.dart';
import '../features/settings/presentation/privacy_page.dart';
import '../features/settings/presentation/support_page.dart';
import '../features/settings/presentation/terms_page.dart';
import 'router_observer.dart';

/// Scan sub-routes are nested under `/scan` so `pop()` from crop/enhance/review returns to the camera.
final GoRouter appRouter = GoRouter(
  observers: [routeObserver],
  // Android can hand an opened file's content:// or file:// address to the router; the file itself is imported separately.
  redirect: (context, state) => state.uri.scheme == 'content' || state.uri.scheme == 'file' ? '/' : null,
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const HomePage(),
      routes: [
        GoRoute(
          path: 'document/:id',
          builder: (_, state) => DocumentDetailPage(documentId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: 'ocr',
          builder: (_, state) => OcrPage(document: state.extra! as ScannedDocument),
        ),
        GoRoute(path: 'compress-photo', builder: (_, _) => const CompressPhotoPage()),
        GoRoute(path: 'passport-photo', builder: (_, _) => const PassportPhotoPage()),
        GoRoute(path: 'watermark', builder: (_, _) => const WatermarkPage()),
        GoRoute(path: 'privacy-clean', builder: (_, _) => const PrivacyCleanPage()),
        GoRoute(path: 'compress-pdf', builder: (_, _) => const PdfCompressPage()),
        GoRoute(path: 'pdf-pages', builder: (_, _) => const PdfPagesPage()),
        GoRoute(path: 'pdf-password', builder: (_, _) => const PdfPasswordPage()),
        GoRoute(path: 'id-card', builder: (_, _) => const IdCardPage()),
        GoRoute(path: 'signature', builder: (_, _) => const SignatureHubPage()),
        GoRoute(path: 'signature-draw', builder: (_, _) => const SignatureDrawPage()),
        GoRoute(path: 'signature-photo', builder: (_, _) => const SignaturePhotoPage()),
        GoRoute(path: 'sign-document', builder: (_, _) => const SignDocumentPage()),
        GoRoute(path: 'privacy', builder: (_, _) => const PrivacyPage()),
        GoRoute(path: 'terms', builder: (_, _) => const TermsPage()),
        GoRoute(path: 'support', builder: (_, _) => const SupportPage()),
        GoRoute(path: 'paywall', builder: (_, _) => const PaywallPage()),
        GoRoute(path: 'qr', builder: (_, _) => const QrGeneratorPage()),
        GoRoute(
          path: 'office-sheets',
          builder: (_, _) => const OfficeHubPage(hub: OfficeHub.sheets),
        ),
        GoRoute(
          path: 'office-slides',
          builder: (_, _) => const OfficeHubPage(hub: OfficeHub.slides),
        ),
        GoRoute(
          path: 'office-convert',
          builder: (_, state) => OfficeConvertPage(conversion: state.extra! as OfficeConversion),
        ),
        GoRoute(
          path: 'slides',
          builder: (_, state) => SlidesPage(path: state.extra is String ? state.extra! as String : null),
        ),
        GoRoute(
          path: 'sheet',
          builder: (_, state) => SheetPage(args: state.extra is SheetArgs ? state.extra! as SheetArgs : const SheetArgs()),
        ),
        GoRoute(
          path: 'print',
          builder: (_, state) => PrintPage(document: state.extra! as ScannedDocument),
        ),
        GoRoute(
          path: 'qr-share',
          builder: (_, state) => QrSharePage(args: state.extra! as QrShareArgs),
        ),
        GoRoute(
          path: 'pdf-edit',
          builder: (_, state) => PdfEditPage(path: state.extra! as String),
        ),
        GoRoute(
          path: 'docx-edit',
          builder: (_, state) => DocxEditPage(path: state.extra! as String),
        ),
        GoRoute(
          path: 'reader',
          builder: (_, state) => ReaderPage(args: state.extra! as ReaderArgs),
        ),
        GoRoute(
          path: 'folder/:id',
          builder: (_, state) => FolderPage(folderId: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(
      path: '/scan',
      builder: (_, _) => const CameraPage(),
      routes: [
        GoRoute(path: 'crop', builder: (_, _) => const CropPage()),
        GoRoute(path: 'edit', builder: (_, _) => const EditPage()),
        GoRoute(
          path: 'markup',
          builder: (_, state) => MarkupPage(args: state.extra! as MarkupArgs),
        ),
      ],
    ),
  ],
);
