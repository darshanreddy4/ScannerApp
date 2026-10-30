import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/utils/region.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

class SettingsCubit extends Cubit<AppSettings> {
  SettingsCubit(this._repo) : super(const AppSettings());

  final SettingsRepository _repo;

  @override
  void onChange(Change<AppSettings> change) {
    super.onChange(change);
    _apply(change.nextState);
  }

  void _apply(AppSettings s) {
    Region.apply(paper: s.paper, date: s.dateStyle, tools: s.toolRegion, showAll: s.showAllTools);
    Strings.use(s.language);
  }

  Future<void> load() async {
    final loaded = await _repo.load();
    _apply(loaded);
    emit(loaded);
  }

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    final next = change(state);
    emit(next);
    await _repo.save(next);
  }
}
