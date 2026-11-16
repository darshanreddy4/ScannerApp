// Browser preview of the Documents, Tools and Settings pages with sample data. Run: flutter run -d web-server -t lib/preview_main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/di.dart';
import 'core/error/result.dart';
import 'core/i18n/app_language.dart';
import 'core/i18n/tr.dart';
import 'core/theme/app_theme.dart';
import 'features/documents/domain/entities/scanned_document.dart';
import 'features/documents/domain/repositories/document_repository.dart';
import 'features/documents/domain/usecases/document_usecases.dart';
import 'features/documents/presentation/bloc/documents_cubit.dart';
import 'features/documents/presentation/pages/home_page.dart';
import 'features/monetization/domain/entities/plan_status.dart';
import 'features/monetization/domain/repositories/monetization_contracts.dart';
import 'features/monetization/presentation/plan_cubit.dart';
import 'features/qr/domain/local_share.dart';
import 'features/qr/domain/share_options.dart';
import 'features/qr/domain/share_sessions.dart';
import 'features/rewards/domain/coin_wallet.dart';
import 'features/rewards/presentation/coins_cubit.dart';
import 'features/settings/data/settings_repository.dart';
import 'features/settings/domain/app_settings.dart';
import 'features/settings/presentation/settings_cubit.dart';

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  AppSettings _saved = const AppSettings();
  @override
  Future<AppSettings> load() async => _saved;
  @override
  Future<void> save(AppSettings settings) async => _saved = settings;
}

class _Wallet implements CoinWallet {
  int balance = 120;
  bool claimed = false;
  CoinSnapshot get _s => CoinSnapshot(balance: balance, adsToday: 0, dailyClaimed: claimed);
  @override
  Future<CoinSnapshot> read() async => _s;
  @override
  Future<CoinSnapshot> earnFromAd(int coins) async {
    balance += coins;
    return _s;
  }

  @override
  Future<bool> spend(int coins) async => balance >= coins && (balance -= coins) >= 0;
  @override
  Future<void> refund(int coins) async => balance += coins;
  @override
  Future<int> claimDaily(int coins) async {
    if (claimed) return 0;
    claimed = true;
    balance += coins;
    return coins;
  }

  @override
  Future<CoinSnapshot> countPassVideo({required int minutes, required int needed, required Duration length}) async => _s;
  @override
  Future<bool> useFreeDaily(String id) async => true;
}

class _Ads implements AdService {
  @override
  Future<void> initialize() async {}
  @override
  Future<RewardResult> showRewarded() async => RewardResult.unavailable;
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<void> showInterstitialIfEligible(PlanStatus plan) async {}
}

class _Local implements LocalShareServer {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Remote implements RemoteShareService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Sample library; anything the preview does not need answers with an empty success.
class _Library implements DocumentRepository, FolderRepository {
  final _now = DateTime.now();
  final _folders = <Folder>[];

  ScannedDocument _doc(String id, String title, {bool favorite = false, List<String> tags = const [], int hours = 0}) => ScannedDocument(
    id: id,
    title: title,
    createdAt: _now.subtract(Duration(hours: hours)),
    updatedAt: _now.subtract(Duration(hours: hours)),
    pages: const [],
    favorite: favorite,
    tags: tags,
  );

  @override
  Future<Result<List<ScannedDocument>>> listDocuments() async => Ok([
    _doc('1', 'Passport copy', favorite: true, tags: ['ID'], hours: 3),
    _doc('2', 'Electricity bill', tags: ['Receipt'], hours: 30),
    _doc('3', 'Rent agreement', hours: 90),
    _doc('4', 'Lunch receipt', tags: ['Receipt'], hours: 120),
  ]);

  @override
  Future<Result<List<Folder>>> listFolders() async => Ok([
    Folder(id: 'f1', name: 'Work', createdAt: _now),
    Folder(id: 'f2', name: 'Travel', createdAt: _now, favorite: true),
    Folder(id: 'f3', name: 'Receipts', createdAt: _now),
    ..._folders,
  ]);

  @override
  Future<Result<Folder>> createFolder(String name, {FolderStyle style = const FolderStyle()}) async {
    final f = Folder(id: 'n${_folders.length}', name: name, createdAt: _now, icon: style.icon, color: style.color);
    _folders.add(f);
    return Ok(f);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(const Ok<void>(null));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Strings.use(AppLanguage.system);
  sl
    ..registerSingleton<AdService>(_Ads())
    ..registerSingleton<ShareSessions>(ShareSessions(local: _Local(), remote: _Remote()));
  final library = _Library();
  final docs = DocumentsCubit(
    listDocuments: ListDocuments(library),
    listFolders: ListFolders(library),
    deleteDocument: DeleteDocument(library),
    renameDocument: RenameDocument(library),
    moveDocument: MoveDocument(library),
    mergeDocuments: MergeDocuments(library),
    createFolder: CreateFolder(library),
    renameFolder: RenameFolder(library),
    updateFolderMeta: UpdateFolderMeta(library),
    deleteFolder: DeleteFolder(library),
  )..load();
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => PlanCubit(_Plans())..load()),
        BlocProvider(create: (_) => SettingsCubit(_Prefs())..load()),
        BlocProvider.value(value: docs),
        BlocProvider(
          create: (_) => CoinsCubit(wallet: _Wallet(), ads: _Ads())..load(),
        ),
      ],
      child: BlocSelector<SettingsCubit, AppSettings, AppLanguage>(
        selector: (s) => s.language,
        builder: (context, language) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          locale: language.locale,
          supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
          localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
          home: const HomePage(),
        ),
      ),
    ),
  );
}
