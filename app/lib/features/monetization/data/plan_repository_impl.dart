import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/plan_status.dart';
import '../domain/repositories/monetization_contracts.dart';

class PlanRepositoryImpl implements PlanRepository {
  static const _key = 'plan_status';

  @override
  Future<PlanStatus> current() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == PlanStatus.premium.name ? PlanStatus.premium : PlanStatus.free;
  }

  @override
  Future<void> setPlan(PlanStatus plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, plan.name);
  }
}
