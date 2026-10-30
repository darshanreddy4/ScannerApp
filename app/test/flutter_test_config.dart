import 'dart:async';

import 'package:doculoom/core/utils/region.dart';

/// Every test starts from the same region (dates written day first, A4 paper), whatever the machine running them is set to.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Region.countryOverride = 'IN';
  await testMain();
}
