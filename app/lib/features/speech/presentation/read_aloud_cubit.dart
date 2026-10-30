import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/speech_chunks.dart';
import '../domain/speech_service.dart';

enum ReadStatus { loading, idle, speaking, paused, unavailable, languageMissing, failed }

class ReadAloudState extends Equatable {
  const ReadAloudState({this.chunks = const [], this.index = 0, this.status = ReadStatus.loading, this.rate = 1.0, this.language, this.message});

  final List<String> chunks;

  /// The piece being spoken, or the one that will be spoken next.
  final int index;
  final ReadStatus status;

  /// 1.0 is the voice's normal speed.
  final double rate;

  /// The voice language the person chose; null follows the text and the phone.
  final String? language;
  final String? message;

  bool get speaking => status == ReadStatus.speaking;
  bool get hasText => chunks.isNotEmpty;

  ReadAloudState copyWith({List<String>? chunks, int? index, ReadStatus? status, double? rate, Object? language = _keep, Object? message = _keep}) =>
      ReadAloudState(
        chunks: chunks ?? this.chunks,
        index: index ?? this.index,
        status: status ?? this.status,
        rate: rate ?? this.rate,
        language: identical(language, _keep) ? this.language : language as String?,
        message: identical(message, _keep) ? this.message : message as String?,
      );

  static const _keep = Object();

  @override
  List<Object?> get props => [chunks, index, status, rate, language, message];
}

class ReadAloudCubit extends Cubit<ReadAloudState> {
  ReadAloudCubit({required SpeechService service, required String text, String? language})
    : _service = service,
      _text = text,
      _language = language,
      super(const ReadAloudState());

  static const rates = [0.75, 1.0, 1.25, 1.5, 2.0];

  final SpeechService _service;
  final String _text;
  final String? _language;
  StreamSubscription<SpeechEvent>? _sub;
  var _busy = false;

  String? get _effectiveLanguage => state.language ?? guessSpeechLanguage(_text);

  Future<void> start() async {
    final chunks = splitForSpeech(_text);
    _sub = _service.events.listen(_onEvent);
    final available = await _service.isAvailable();
    if (isClosed) return;
    emit(
      ReadAloudState(
        chunks: chunks,
        language: _language,
        status: available ? ReadStatus.idle : ReadStatus.unavailable,
        message: available ? null : 'This phone has no text-to-speech engine. Install or turn one on in the phone\'s settings.',
      ),
    );
  }

  void _onEvent(SpeechEvent e) {
    if (isClosed) return;
    switch (e) {
      case SpeechChunk(:final index):
        if (state.status == ReadStatus.speaking && index < state.chunks.length) emit(state.copyWith(index: index));
      case SpeechDone():
        if (state.status == ReadStatus.speaking) emit(state.copyWith(status: ReadStatus.idle, index: 0));
      case SpeechFailed(:final message):
        if (state.status == ReadStatus.speaking) emit(state.copyWith(status: ReadStatus.failed, message: message));
    }
  }

  Future<void> _speakFrom(int index) async {
    if (_busy || !state.hasText) return;
    _busy = true;
    try {
      emit(state.copyWith(index: index, status: ReadStatus.speaking, message: null));
      final result = await _service.speak(state.chunks, from: index, language: _effectiveLanguage, rate: state.rate);
      if (isClosed) return;
      switch (result) {
        case SpeechStart.started:
          break;
        case SpeechStart.languageMissing:
          emit(
            state.copyWith(
              status: ReadStatus.languageMissing,
              message: 'This phone has no voice for that language. Choose another language, or add the voice in the phone\'s text-to-speech settings.',
            ),
          );
        case SpeechStart.unavailable:
          emit(
            state.copyWith(
              status: ReadStatus.unavailable,
              message: 'This phone has no text-to-speech engine. Install or turn one on in the phone\'s settings.',
            ),
          );
      }
    } finally {
      _busy = false;
    }
  }

  /// Starts reading, or carries on from where it paused.
  Future<void> play() async {
    if (state.speaking) return;
    await _speakFrom(state.index.clamp(0, state.chunks.isEmpty ? 0 : state.chunks.length - 1));
  }

  Future<void> pause() async {
    if (!state.speaking) return;
    await _service.stop();
    if (!isClosed) emit(state.copyWith(status: ReadStatus.paused));
  }

  Future<void> toggle() => state.speaking ? pause() : play();

  Future<void> stop() async {
    await _service.stop();
    if (!isClosed) emit(state.copyWith(status: ReadStatus.idle, index: 0, message: null));
  }

  /// Moves to piece [index]; when reading it carries on from there.
  Future<void> seek(int index) async {
    if (!state.hasText) return;
    final target = index.clamp(0, state.chunks.length - 1);
    if (state.speaking) {
      await _speakFrom(target);
    } else {
      emit(state.copyWith(index: target, status: state.status == ReadStatus.paused ? ReadStatus.paused : ReadStatus.idle));
    }
  }

  Future<void> next() => seek(state.index + 1);

  Future<void> previous() => seek(state.index - 1);

  Future<void> setRate(double rate) async {
    emit(state.copyWith(rate: rate));
    if (state.speaking) await _speakFrom(state.index);
  }

  Future<void> setLanguage(String? language) async {
    final wasSpeaking = state.speaking;
    emit(state.copyWith(language: language, status: state.status == ReadStatus.languageMissing ? ReadStatus.idle : state.status, message: null));
    if (wasSpeaking) await _speakFrom(state.index);
  }

  Future<void> openVoiceSettings() => _service.openVoiceSettings();

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _service.stop();
    return super.close();
  }
}
