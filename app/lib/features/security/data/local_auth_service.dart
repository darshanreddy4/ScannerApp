import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/auth_service.dart';

class LocalAuthService implements AuthService {
  LocalAuthService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<Result<AuthOutcome>> authenticate(String reason) => guard(() async {
    if (!await _auth.isDeviceSupported()) return AuthOutcome.unavailable;
    try {
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok ? AuthOutcome.success : AuthOutcome.cancelled;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled => AuthOutcome.unavailable,
        _ => AuthOutcome.cancelled,
      };
    } on PlatformException {
      return AuthOutcome.unavailable;
    }
  }, onError: (e) => UnexpectedFailure('Authentication is not available right now.', cause: e));
}
