import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

class SettingsCubit extends Cubit<AppSettings> {
  SettingsCubit(this._repo) : super(const AppSettings());

  final SettingsRepository _repo;

  Future<void> load() async => emit(await _repo.load());

  Future<void> update(AppSettings Function(AppSettings current) change) async {
    final next = change(state);
    emit(next);
    await _repo.save(next);
  }
}
