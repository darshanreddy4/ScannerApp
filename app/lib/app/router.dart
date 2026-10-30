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
import '../features/backup/presentation/backup_page.dart';
import '../features/contacts/presentation/contact_page.dart';
import '../features/text_edit/docx/docx_edit_page.dart';
import '../features/text_edit/pdf/pdf_edit_page.dart';
import '../features/office/slides/presentation/slides_page.dart';
import '../features/photo_tools/presentation/compress_photo_page.dart';
import '../features/id_card/presentation/id_card_page.dart';
import '../features/markup/presentation/markup_page.dart';
import '../features/pdf_tools/presentation/pdf_compress_page.dart';
import '../features/signature/domain/signature.dart' show SignatureKind;
import '../features/signature/presentation/sign_document_page.dart';
import '../features/signature/presentation/signature_pages.dart';
import '../features/pdf_tools/presentation/pdf_crop_page.dart';
import '../features/ocr_tool/presentation/ocr_tool_page.dart';
import '../features/expenses/presentation/expenses_page.dart';
import '../features/pdf_compare/presentation/pdf_compare_page.dart';
import '../features/tables/presentation/table_page.dart';
import '../features/speech/presentation/read_aloud_page.dart';
import '../features/pdf_tools/presentation/pdf_form_page.dart';
import '../features/pdf_tools/presentation/pdf_images_page.dart';
import '../features/pdf_tools/presentation/pdf_pages_page.dart';
import '../features/pdf_tools/presentation/pdf_redact_page.dart';
import '../features/pdf_tools/presentation/pdf_password_page.dart';
import '../features/photo_tools/presentation/passport_photo_page.dart';
import '../features/photo_tools/presentation/privacy_clean_page.dart';
import '../features/photo_tools/presentation/watermark_page.dart';
import '../features/print/presentation/print_page.dart';
import '../features/cv/presentation/cv_page.dart';
import '../features/vat_refund/presentation/vat_refund_page.dart';
import '../features/amount_words/presentation/amount_words_page.dart';
import '../features/cards/presentation/card_edit_page.dart';
import '../features/checklists/presentation/checklists_page.dart';
import '../features/packet/presentation/packet_page.dart';
import '../features/hijri/presentation/hijri_page.dart';
import '../features/reminders/presentation/reminder_help_page.dart';
import '../features/safe_id/presentation/safe_id_page.dart';
import '../features/taxinvoice/presentation/gst_invoice_page.dart';
import '../features/taxinvoice/presentation/us_invoice_page.dart';
import '../features/taxinvoice/presentation/zatca_invoice_page.dart';
import '../features/cards/presentation/card_scan_page.dart';
import '../features/cards/presentation/card_view_page.dart';
import '../features/cards/presentation/cards_page.dart';
import '../features/signing/presentation/certificate_sign_page.dart';
import '../features/einvoice/presentation/einvoice_page.dart';
import '../features/invoice/presentation/invoice_page.dart';
import '../features/qr/domain/payments.dart' show SepaPrefill;
import '../features/qr/presentation/qr_generator_page.dart';
import '../features/qr/presentation/qr_scan_page.dart';
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
        GoRoute(
          path: 'read-aloud',
          builder: (_, state) => ReadAloudPage(args: state.extra! as ReadAloudArgs),
        ),
        GoRoute(path: 'ocr-tool', builder: (_, _) => const OcrToolPage()),
        GoRoute(path: 'expenses', builder: (_, _) => const ExpensesPage()),
        GoRoute(path: 'compare-pdf', builder: (_, _) => const PdfComparePage()),
        GoRoute(
          path: 'table',
          builder: (_, state) => TablePage(args: state.extra! as TableArgs),
        ),
        GoRoute(path: 'pdf-form', builder: (_, _) => const PdfFormPage()),
        GoRoute(path: 'pdf-flatten', builder: (_, _) => const PdfFormPage(flattenOnly: true)),
        GoRoute(path: 'pdf-crop', builder: (_, _) => const PdfCropPage()),
        GoRoute(path: 'pdf-images', builder: (_, _) => const PdfImagesPage()),
        GoRoute(path: 'pdf-redact', builder: (_, _) => const PdfRedactPage()),
        GoRoute(
          path: 'id-card',
          builder: (_, state) => IdCardPage(photos: state.extra is List<String> ? state.extra! as List<String> : const []),
        ),
        GoRoute(path: 'signature', builder: (_, _) => const SignatureHubPage()),
        GoRoute(
          path: 'signature-draw',
          builder: (_, state) => SignatureDrawPage(kind: state.extra is SignatureKind ? state.extra! as SignatureKind : SignatureKind.signature),
        ),
        GoRoute(
          path: 'signature-photo',
          builder: (_, state) => SignaturePhotoPage(kind: state.extra is SignatureKind ? state.extra! as SignatureKind : SignatureKind.signature),
        ),
        GoRoute(path: 'sign-document', builder: (_, _) => const SignDocumentPage()),
        GoRoute(path: 'privacy', builder: (_, _) => const PrivacyPage()),
        GoRoute(path: 'terms', builder: (_, _) => const TermsPage()),
        GoRoute(path: 'support', builder: (_, _) => const SupportPage()),
        GoRoute(path: 'paywall', builder: (_, _) => const PaywallPage()),
        GoRoute(path: 'qr', builder: (_, _) => const QrGeneratorPage()),
        GoRoute(
          path: 'qr-payment',
          builder: (_, state) => QrGeneratorPage(payment: true, prefill: state.extra is SepaPrefill ? state.extra! as SepaPrefill : null),
        ),
        GoRoute(path: 'qr-upi', builder: (_, _) => const QrGeneratorPage(upi: true)),
        GoRoute(path: 'einvoice', builder: (_, _) => const EInvoicePage()),
        GoRoute(path: 'invoice', builder: (_, _) => const InvoicePage()),
        GoRoute(path: 'cv', builder: (_, _) => const CvPage()),
        GoRoute(path: 'vat-refund', builder: (_, _) => const VatRefundPage()),
        GoRoute(path: 'amount-words', builder: (_, _) => const AmountWordsPage()),
        GoRoute(path: 'cards', builder: (_, _) => const CardsPage()),
        GoRoute(
          path: 'card-view',
          builder: (_, state) => CardViewPage(cardId: state.extra is String ? state.extra! as String : ''),
        ),
        GoRoute(
          path: 'card-edit',
          builder: (_, state) => CardEditPage(args: state.extra is CardEditArgs ? state.extra! as CardEditArgs : const CardEditArgs()),
        ),
        GoRoute(path: 'card-scan', builder: (_, _) => const CardScanPage()),
        GoRoute(path: 'checklists', builder: (_, _) => const ChecklistsPage()),
        GoRoute(path: 'safe-id', builder: (_, _) => const SafeIdPage()),
        GoRoute(path: 'hijri', builder: (_, _) => const HijriPage()),
        GoRoute(path: 'reminder-help', builder: (_, _) => const ReminderHelpPage()),
        GoRoute(path: 'gst-invoice', builder: (_, _) => const GstInvoicePage()),
        GoRoute(path: 'us-invoice', builder: (_, _) => const UsInvoicePage()),
        GoRoute(path: 'zatca-invoice', builder: (_, _) => const ZatcaInvoicePage()),
        GoRoute(
          path: 'packet',
          builder: (_, state) => PacketPage(initial: state.extra is List<String> ? state.extra! as List<String> : const []),
        ),
        GoRoute(
          path: 'checklist',
          builder: (_, state) => ChecklistPage(listId: state.extra is String ? state.extra! as String : ''),
        ),
        GoRoute(path: 'pdf-certificate', builder: (_, _) => const CertificateSignPage()),
        GoRoute(path: 'qr-scan', builder: (_, _) => const QrScanPage()),
        GoRoute(path: 'qr-history', builder: (_, _) => const QrHistoryPage()),
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
        GoRoute(path: 'backup', builder: (_, _) => const BackupPage()),
        GoRoute(
          path: 'contact',
          builder: (_, state) => ContactPage(text: state.extra! as String),
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
