import 'dart:io';

import 'failures.dart';

sealed class Result<T> {
  const Result();

  R when<R>({required R Function(T value) ok, required R Function(Failure failure) err});

  bool get isOk => this is Ok<T>;
  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };
  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  R when<R>({required R Function(T value) ok, required R Function(Failure failure) err}) => ok(value);
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;

  @override
  R when<R>({required R Function(T value) ok, required R Function(Failure failure) err}) => err(failure);
}

/// Runs [body] and converts any thrown error into a typed [Failure].
Future<Result<T>> guard<T>(
  Future<T> Function() body, {
  Failure Function(Object error)? onError,
}) async {
  try {
    return Ok(await body());
  } on Failure catch (f) {
    return Err(f);
  } on OutOfMemoryError catch (e) {
    return Err(ImageProcessingFailure('Not enough memory to complete this operation.', cause: e));
  } on FileSystemException catch (e) {
    final noSpace = e.osError?.errorCode == 28;
    return Err(StorageFailure(
      noSpace ? 'The device is out of storage space.' : 'Could not access a file on the device.',
      cause: e,
    ));
  } catch (e) {
    return Err(onError?.call(e) ?? UnexpectedFailure('Something went wrong. Please try again.', cause: e));
  }
}
