import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/entities/plan_status.dart';
import '../domain/repositories/monetization_contracts.dart';

class PlanCubit extends Cubit<PlanStatus> {
  PlanCubit(this._repo) : super(PlanStatus.free);

  final PlanRepository _repo;

  Future<void> load() async => emit(await _repo.current());

  Future<void> setPlan(PlanStatus plan) async {
    await _repo.setPlan(plan);
    emit(plan);
  }
}
