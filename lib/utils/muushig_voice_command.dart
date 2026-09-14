enum MuushigVoiceAction { play, skip, score }

/// Only an exact extension of consumed speech can donate another command.
/// A recognizer rewriting the old prefix must never replay its player name.
String muushigUnconsumedSpeech(String text, String consumed) {
  if (consumed.isEmpty) return text;
  if (text == consumed || consumed.startsWith('$text ')) return '';
  if (text.startsWith('$consumed ')) return text.substring(consumed.length).trim();
  if (text.split(' ').first == consumed.split(' ').first) return '';
  return text;
}

class MuushigVoiceCommand {
  const MuushigVoiceCommand(this.action, [this.score]);

  final MuushigVoiceAction action;
  final int? score;
}

/// Reads only the command immediately following a player's name.
/// An unfinished or unrecognized next name must never donate its score or
/// decision to the preceding player in a growing speech transcript.
MuushigVoiceCommand? parseMuushigVoiceCommand(String text) {
  final match = RegExp(
    r'^(орлоо|орсон|орно|тоглоно|өнжлөө|өнжинө|өнжсөн|ороогүй|суухгүй|уналаа|унасан|уначихлаа|үсэрлээ|үсэрсэн|үсэрчихлээ|үхлээ|үхсэн|[0-5]|тэг|нэг|хоёр|гурав|дөрөв|тав)(?=\s|$)',
  ).firstMatch(text.trim());
  if (match == null) return null;
  final word = match.group(1)!;
  if (const {'орлоо', 'орсон', 'орно', 'тоглоно'}.contains(word)) {
    return const MuushigVoiceCommand(MuushigVoiceAction.play);
  }
  if (const {'өнжлөө', 'өнжинө', 'өнжсөн', 'ороогүй', 'суухгүй'}.contains(word)) {
    return const MuushigVoiceCommand(MuushigVoiceAction.skip);
  }
  const scores = {
    'уналаа': 0,
    'унасан': 0,
    'уначихлаа': 0,
    'үсэрсэн': 0,
    'үсэрчихлээ': 0,
    'үхсэн': 0,
    'үсэрлээ': 0,
    'үхлээ': 0,
    'тэг': 0,
    'нэг': 1,
    'хоёр': 2,
    'гурав': 3,
    'дөрөв': 4,
    'тав': 5,
  };
  return MuushigVoiceCommand(
    MuushigVoiceAction.score,
    scores[word] ?? int.parse(word),
  );
}

/// Other players' trick counts: null is unentered, zero is a fall, not its
/// displayed five-point penalty. The current player's old value is excluded.
({bool accepted, int remaining, bool last}) validateMuushigVoiceScore(
    int score, Iterable<int?> otherScores) {
  final others = otherScores.toList();
  final remaining = 5 - others.fold<int>(0, (sum, value) => sum + (value ?? 0));
  final last = !others.contains(null);
  return (accepted: score >= 0 && score <= 5 && score <= remaining &&
      (!last || score == remaining), remaining: remaining, last: last);
}
