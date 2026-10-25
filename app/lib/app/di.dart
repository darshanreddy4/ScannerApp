import 'dart:io' show Directory, Platform;

import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/temp_files.dart';
import '../features/office/convert/office_converter.dart';
import '../features/office/slides/data/slide_export.dart';
import '../features/ocr/data/mlkit_ocr_engine.dart';
import '../features/photo_tools/data/business_profile_store.dart';
import '../features/id_card/data/id_card_processor.dart';
import '../features/markup/data/markup_renderer_impl.dart';
import '../features/markup/domain/markup_renderer.dart';
import '../features/id_card/domain/id_card.dart';
import '../features/pdf_tools/data/pdf_compress_processor.dart';
import '../features/pdf_tools/data/pdf_protect_processor.dart';
import '../features/pdf_tools/domain/pdf_protector.dart';
import '../features/signature/data/document_signer.dart';
import '../features/signature/data/signature_processor.dart';
import '../features/signature/data/signature_store.dart';
import '../features/signature/domain/signature.dart';
import '../features/pdf_tools/data/pdf_pages_processor.dart';
import '../features/pdf_tools/domain/pdf_compressor.dart';
import '../features/pdf_tools/domain/pdf_pages.dart';
import '../features/photo_tools/data/image_compressor.dart';
import '../features/photo_tools/data/photo_metadata.dart';
import '../features/photo_tools/domain/metadata_cleaner.dart';
import '../features/photo_tools/data/watermark_processor.dart';
import '../features/photo_tools/domain/watermark_service.dart';
import '../features/photo_tools/data/passport_processor.dart';
import '../features/photo_tools/domain/passport_maker.dart';
import '../features/photo_tools/domain/photo_compressor.dart';
import '../features/qr/data/native_share_server.dart';
import '../features/qr/data/share_store.dart';
import '../features/qr/domain/share_sessions.dart';
import '../features/ocr/data/text_repository_impl.dart';
import '../features/ocr/domain/ocr_engine.dart';
import '../features/ocr/domain/recognize_document_text.dart';
import '../features/ocr/domain/text_repository.dart';
import '../features/rewards/data/coin_wallet_impl.dart';
import '../features/rewards/domain/coin_wallet.dart';
import '../features/rewards/presentation/coins_cubit.dart';
import 'app_config.dart';
import '../features/documents/data/datasources/document_local_data_source.dart';
import '../features/documents/data/repositories/document_repository_impl.dart';
import '../features/documents/domain/repositories/document_repository.dart';
import '../features/documents/domain/usecases/document_usecases.dart';
import '../features/documents/presentation/bloc/document_detail_cubit.dart';
import '../features/documents/presentation/bloc/documents_cubit.dart';
import '../features/export/data/export_repository_impl.dart';
import '../features/export/domain/repositories/export_repository.dart';
import '../features/export/domain/usecases/export_usecases.dart';
import '../features/importer/data/importer_impl.dart';
import '../features/importer/domain/importer.dart';
import '../features/monetization/data/admob_service.dart';
import '../features/print/data/print_service_impl.dart';
import '../features/print/domain/print_service.dart';
import '../features/qr/data/local_share_server.dart';
import '../features/qr/data/relay_share_service.dart';
import '../features/qr/domain/share_options.dart';
import '../features/qr/domain/local_share.dart';
import '../features/monetization/data/plan_repository_impl.dart';
import '../features/monetization/domain/repositories/monetization_contracts.dart';
import '../features/monetization/presentation/plan_cubit.dart';
import '../features/scanner/data/datasources/image_processing_service.dart';
import '../features/scanner/data/repositories/scanner_repository_impl.dart';
import '../features/scanner/domain/repositories/scanner_repository.dart';
import '../features/scanner/domain/usecases/scanner_usecases.dart';
import '../features/scanner/data/datasources/camera_access.dart';
import '../features/scanner/presentation/bloc/camera_cubit.dart';
import '../features/scanner/presentation/bloc/scan_session_cubit.dart';
import '../features/security/data/local_auth_service.dart';
import '../features/security/domain/auth_service.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/presentation/settings_cubit.dart';

final GetIt sl = GetIt.instance;

void configureDependencies() {
  sl
    ..registerLazySingleton(() => TempFiles())
    ..registerLazySingleton<PhotoCompressor>(() => const ImageCompressor())
    ..registerLazySingleton<PassportMaker>(() => const PassportProcessor())
    ..registerLazySingleton<MetadataCleaner>(() => const PhotoMetadataCleaner())
    ..registerLazySingleton<PdfPageService>(
      () => PdfPagesProcessor(
        pdfToImages: (path) async {
          final result = await sl<DocumentImporter>().import(kind: ImportKind.pdf, path: path);
          final failure = result.failureOrNull;
          if (failure != null) throw failure;
          return result.valueOrNull!.imagePaths;
        },
      ),
    )
    ..registerLazySingleton<IdCardMaker>(() => const IdCardProcessor())
    ..registerLazySingleton<SignatureStore>(() => SignatureStoreImpl(appDir: getApplicationDocumentsDirectory))
    ..registerLazySingleton<SignatureMaker>(() => const SignatureProcessor())
    ..registerLazySingleton<DocumentSigner>(
      () => DocumentSignerProcessor(
        pdfToImages: (path) async {
          final result = await sl<DocumentImporter>().import(kind: ImportKind.pdf, path: path);
          final failure = result.failureOrNull;
          if (failure != null) throw failure;
          return result.valueOrNull!.imagePaths;
        },
      ),
    )
    ..registerLazySingleton<MarkupRenderer>(
      () => MarkupRendererImpl(
        scanner: sl<ScannerRepository>(),
        workDir: () async => Directory(p.join((await getTemporaryDirectory()).path, 'scan_work')).create(recursive: true),
      ),
    )
    ..registerLazySingleton<PdfProtector>(() => const PdfProtectProcessor())
    ..registerLazySingleton(() => SlideConverter(importer: sl()))
    ..registerLazySingleton(() => OfficeConverter(workDir: getTemporaryDirectory, slideConversions: sl<SlideConverter>().convert))
    ..registerLazySingleton<PdfCompressor>(
      () => PdfCompressProcessor(
        pdfToImages: (path) async {
          final result = await sl<DocumentImporter>().import(kind: ImportKind.pdf, path: path);
          final failure = result.failureOrNull;
          if (failure != null) throw failure;
          return result.valueOrNull!.imagePaths;
        },
      ),
    )
    ..registerLazySingleton<BusinessProfileStore>(() => BusinessProfileStoreImpl(appDir: getApplicationDocumentsDirectory))
    ..registerLazySingleton<WatermarkService>(
      () => WatermarkProcessor(
        pdfToImages: (path) async {
          final result = await sl<DocumentImporter>().import(kind: ImportKind.pdf, path: path);
          final failure = result.failureOrNull;
          if (failure != null) throw failure;
          return result.valueOrNull!.imagePaths;
        },
      ),
    )
    ..registerLazySingleton<OcrEngine>(() => MlKitOcrEngine())
    ..registerLazySingleton<TextRepository>(() => TextRepositoryImpl(sl()))
    ..registerLazySingleton(() => RecognizeDocumentText(sl(), sl()))
    ..registerLazySingleton<CoinWallet>(() => CoinWalletImpl())
    ..registerFactory(() => CoinsCubit(wallet: sl(), ads: sl()))
    // Scanner
    ..registerLazySingleton<ImageProcessingService>(() => const ImageProcessingService())
    ..registerLazySingleton<ScannerRepository>(() => ScannerRepositoryImpl(sl()))
    ..registerLazySingleton(() => PrepareImage(sl()))
    ..registerLazySingleton(() => InspectImage(sl()))
    ..registerLazySingleton(() => CropDocument(sl()))
    ..registerLazySingleton(() => RotateImage(sl()))
    ..registerLazySingleton(() => PreviewFilter(sl()))
    ..registerLazySingleton(() => PreviewFilterBatch(sl()))
    ..registerLazySingleton(() => ApplyFilter(sl()))
    // Documents
    ..registerLazySingleton(() => DocumentLocalDataSource())
    ..registerLazySingleton(() => DocumentRepositoryImpl(sl()))
    ..registerLazySingleton<DocumentRepository>(() => sl<DocumentRepositoryImpl>())
    ..registerLazySingleton<FolderRepository>(() => sl<DocumentRepositoryImpl>())
    ..registerLazySingleton(() => ListDocuments(sl()))
    ..registerLazySingleton(() => GetDocument(sl()))
    ..registerLazySingleton(() => SaveDocument(sl()))
    ..registerLazySingleton(() => RenameDocument(sl()))
    ..registerLazySingleton(() => UpdateDocument(sl()))
    ..registerLazySingleton(() => UpdateDocumentMeta(sl()))
    ..registerLazySingleton(() => DuplicateDocument(sl()))
    ..registerLazySingleton(() => SplitDocument(sl()))
    ..registerLazySingleton(() => CompressDocument(sl()))
    ..registerLazySingleton(() => GetDocumentSize(sl()))
    ..registerLazySingleton(() => MoveDocument(sl()))
    ..registerLazySingleton(() => MergeDocuments(sl()))
    ..registerLazySingleton(() => DeleteDocument(sl()))
    ..registerLazySingleton(() => DeleteAllData(sl(), sl()))
    ..registerLazySingleton(() => ListFolders(sl()))
    ..registerLazySingleton(() => CreateFolder(sl()))
    ..registerLazySingleton(() => RenameFolder(sl()))
    ..registerLazySingleton(() => UpdateFolderMeta(sl()))
    ..registerLazySingleton(() => DeleteFolder(sl()))
    // Export
    ..registerLazySingleton<DocumentImporter>(() => DocumentImporterImpl())
    ..registerLazySingleton(() => ImportDocumentFile(sl()))
    ..registerLazySingleton<ExportRepository>(() => ExportRepositoryImpl())
    ..registerLazySingleton<ShareService>(() => SharePlusService())
    ..registerLazySingleton<SaveService>(() => DeviceSaveService())
    ..registerLazySingleton<AuthService>(() => LocalAuthService())
    ..registerLazySingleton(() => ExportDocument(sl()))
    ..registerLazySingleton(() => ShareFile(sl()))
    // Monetization
    ..registerLazySingleton<PrintService>(() => PrintServiceImpl())
    ..registerLazySingleton<LocalShareServer>(() => Platform.isAndroid ? NativeLocalShareServer() : LocalShareServerImpl())
    ..registerLazySingleton<RemoteShareService>(() => RelayShareService(baseUrl: AppConfig.shareRelayUrl))
    ..registerLazySingleton(() => ShareSessions(local: sl(), remote: sl(), store: SharedPrefsShareStore()))
    ..registerLazySingleton<PlanRepository>(() => PlanRepositoryImpl())
    ..registerLazySingleton<AdService>(() => AdMobService())
    // Presentation
    ..registerFactory(() => PlanCubit(sl()))
    ..registerLazySingleton<SettingsRepository>(() => SettingsRepositoryImpl())
    ..registerFactory(() => SettingsCubit(sl()))
    ..registerFactory(
      () => DocumentsCubit(
        textRepository: sl(),
        listDocuments: sl(),
        listFolders: sl(),
        deleteDocument: sl(),
        renameDocument: sl(),
        moveDocument: sl(),
        mergeDocuments: sl(),
        createFolder: sl(),
        renameFolder: sl(),
        updateFolderMeta: sl(),
        deleteFolder: sl(),
      ),
    )
    ..registerLazySingleton<CameraAccess>(() => const SystemCameraAccess())
    ..registerFactory(() => CameraCubit(access: sl()))
    ..registerFactory(
      () => ScanSessionCubit(
        prepareImage: sl(),
        inspectImage: sl(),
        cropDocument: sl(),
        rotateImage: sl(),
        previewFilter: sl(),
        previewFilterBatch: sl(),
        applyFilter: sl(),
        saveDocument: sl(),
        updateDocument: sl(),
        importDocumentFile: sl(),
        clearWorkFiles: sl<TempFiles>().clearScanWork,
        markupRenderer: sl<MarkupRenderer>(),
      ),
    )
    ..registerFactoryParam<DocumentDetailCubit, String, void>(
      (id, _) => DocumentDetailCubit(documentId: id, getDocument: sl(), renameDocument: sl(), deleteDocument: sl(), exportDocument: sl(), shareFile: sl()),
    );
}
