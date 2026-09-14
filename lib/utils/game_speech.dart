import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// SpeechToText is shared across game pages. initialize() only installs its
/// listeners the first time, so explicitly hand callbacks to the current page.
Future<bool> initializeGameSpeech(
  SpeechToText speech, {
  required void Function(String) onStatus,
  required void Function(SpeechRecognitionError) onError,
}) {
  speech.statusListener = onStatus;
  speech.errorListener = onError;
  return speech.initialize(onStatus: onStatus, onError: onError);
}
