/// What the speech engine tells the app while it reads.
sealed class SpeechEvent {
  const SpeechEvent();
}

/// Piece [index] has started to be spoken.
class SpeechChunk extends SpeechEvent {
  const SpeechChunk(this.index);
  final int index;
}

/// The last piece has been spoken.
class SpeechDone extends SpeechEvent {
  const SpeechDone();
}

class SpeechFailed extends SpeechEvent {
  const SpeechFailed(this.message);
  final String message;
}

/// How a request to speak ended up.
enum SpeechStart {
  started,

  /// The phone has no voice for the language asked for.
  languageMissing,

  /// The phone has no text-to-speech engine, or it did not start.
  unavailable,
}

abstract interface class SpeechService {
  Stream<SpeechEvent> get events;

  /// False when the phone has no text-to-speech engine.
  Future<bool> isAvailable();

  /// Speaks [chunks] one after the other, beginning with piece [from]. Anything being spoken stops first.
  Future<SpeechStart> speak(List<String> chunks, {required int from, String? language, required double rate});

  Future<void> stop();

  /// Opens the phone's text-to-speech settings, where voices are chosen and installed.
  Future<bool> openVoiceSettings();
}
