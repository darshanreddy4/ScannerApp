import 'package:get_it/get_it.dart';

import '../features/documents/data/datasources/document_local_data_source.dart';
import '../features/documents/data/repositories/document_repository_impl.dart';
import '../features/documents/domain/repositories/document_repository.dart';
import '../features/documents/domain/usecases/document_usecases.dart';
import '../features/documents/presentation/bloc/document_detail_cubit.dart';
import '../features/documents/presentation/bloc/documents_cubit.dart';
import '../features/export/data/export_repository_impl.dart';
import '../features/export/domain/repositories/export_repository.dart';
import '../features/export/domain/usecases/export_usecases.dart';
import '../features/monetization/data/admob_service.dart';
import '../features/monetization/data/plan_repository_impl.dart';
import '../features/monetization/domain/repositories/monetization_contracts.dart';
import '../features/monetization/presentation/plan_cubit.dart';
import '../features/scanner/data/datasources/image_processing_service.dart';
import '../features/scanner/data/repositories/scanner_repository_impl.dart';
import '../features/scanner/domain/repositories/scanner_repository.dart';
import '../features/scanner/domain/usecases/scanner_usecases.dart';
import '../features/scanner/presentation/bloc/camera_cubit.dart';
import '../features/scanner/presentation/bloc/scan_session_cubit.dart';

final GetIt sl = GetIt.instance;

void configureDependencies() {
  sl
    // Scanner
    ..registerLazySingleton<ImageProcessingService>(() => const ImageProcessingService())
    ..registerLazySingleton<ScannerRepository>(() => ScannerRepositoryImpl(sl()))
    ..registerLazySingleton(() => PrepareImage(sl()))
    ..registerLazySingleton(() => CropDocument(sl()))
    ..registerLazySingleton(() => RotateImage(sl()))
    ..registerLazySingleton(() => PreviewFilter(sl()))
    ..registerLazySingleton(() => ApplyFilter(sl()))
    // Documents
    ..registerLazySingleton(() => DocumentLocalDataSource())
    ..registerLazySingleton<DocumentRepository>(() => DocumentRepositoryImpl(sl()))
    ..registerLazySingleton(() => ListDocuments(sl()))
    ..registerLazySingleton(() => GetDocument(sl()))
    ..registerLazySingleton(() => SaveDocument(sl()))
    ..registerLazySingleton(() => RenameDocument(sl()))
    ..registerLazySingleton(() => DeleteDocument(sl()))
    // Export
    ..registerLazySingleton<ExportRepository>(() => ExportRepositoryImpl())
    ..registerLazySingleton<ShareService>(() => SharePlusService())
    ..registerLazySingleton(() => ExportDocument(sl()))
    ..registerLazySingleton(() => ShareFile(sl()))
    // Monetization
    ..registerLazySingleton<PlanRepository>(() => PlanRepositoryImpl())
    ..registerLazySingleton<AdService>(() => AdMobService())
    // Presentation
    ..registerFactory(() => PlanCubit(sl()))
    ..registerFactory(() => DocumentsCubit(listDocuments: sl(), deleteDocument: sl()))
    ..registerFactory(() => CameraCubit())
    ..registerFactory(
      () => ScanSessionCubit(
        prepareImage: sl(),
        cropDocument: sl(),
        rotateImage: sl(),
        previewFilter: sl(),
        applyFilter: sl(),
        saveDocument: sl(),
      ),
    )
    ..registerFactoryParam<DocumentDetailCubit, String, void>(
      (id, _) => DocumentDetailCubit(
        documentId: id,
        getDocument: sl(),
        renameDocument: sl(),
        deleteDocument: sl(),
        exportDocument: sl(),
        shareFile: sl(),
      ),
    );
}
