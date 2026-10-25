import '../../../core/error/result.dart';

enum AuthOutcome { success, cancelled, unavailable }

/// Confirms the person holding the phone is its owner (fingerprint, face, PIN, pattern or password).
abstract interface class AuthService {
  Future<Result<AuthOutcome>> authenticate(String reason);
}
