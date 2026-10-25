import 'package:equatable/equatable.dart';

sealed class Failure extends Equatable implements Exception {
  const Failure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  List<Object?> get props => [message];

  @override
  String toString() => '$runtimeType: $message';
}

class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.cause});
}

class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.cause});
}

class ImageProcessingFailure extends Failure {
  const ImageProcessingFailure(super.message, {super.cause});
}

class ExportFailure extends Failure {
  const ExportFailure(super.message, {super.cause});
}

class ImportFailure extends Failure {
  const ImportFailure(super.message, {super.cause});
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {super.cause});
}

class CameraFailure extends Failure {
  const CameraFailure(super.message, {super.cause});
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.cause});
}

class PasswordFailure extends Failure {
  const PasswordFailure(super.message, {super.cause});
}

class OcrFailure extends Failure {
  const OcrFailure(super.message, {super.cause});
}
