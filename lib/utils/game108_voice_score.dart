import 'poker_voice_score.dart';

/// A spoken seven represents the zero-value seven card in 108 only.
int? parseGame108VoiceScore(String text) {
  final normalized = text.trim().toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r'\s+оноо$'), '');
  if (normalized == 'нойл') return 0;
  final score = parsePokerVoiceScore(normalized);
  return score == 7 ? 0 : score;
}
