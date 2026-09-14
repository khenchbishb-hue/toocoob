import 'buur_voice_command.dart';

int? parseDurakTeamCommand(String text) {
  final match = RegExp(r'^баг ([1-8]|нэг|хоёр|гурав|дөрөв|тав|зургаа|долоо|найм)$')
      .firstMatch(normalizeBuurSpeech(text));
  if (match == null) return null;
  const words = ['нэг', 'хоёр', 'гурав', 'дөрөв', 'тав', 'зургаа', 'долоо', 'найм'];
  final value = match.group(1)!;
  return int.tryParse(value) ?? words.indexOf(value) + 1;
}
