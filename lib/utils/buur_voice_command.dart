String normalizeBuurSpeech(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-zа-яёөү0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Iterable<String> buurNameAliases(String name) sync* {
  final normalized = normalizeBuurSpeech(name);
  yield normalized;
  const aliases = <String, List<String>>{
    'ms': ['мс', 'эм эс'],
    'мс': ['эм эс'],
    'shovgor': ['шовгор'],
    'syska': ['сыска', 'сиска', 'сиська', 'сисга', 'систем'],
    'shuumul': ['шумуул', 'шуумул'],
    'indian': ['индиан', 'индианчук'],
  };
  yield* aliases[normalized] ?? const <String>[];
}

/// Read an action after the player has already been acknowledged.
int? parseBuurVoiceAction(String text) {
  final normalized =
      normalizeBuurSpeech(text).replaceFirst(RegExp(r' боллоо$'), '');
  const aliases = {
    'тоо хүрлээ': 1, 'оноо хүрлээ': 1, 'оноо': 1, '31': 1, 'гучин нэг': 1,
    'хөзөр': 2,
    'тамга': 3, 'хайбар': 3, 'хайбар сэнгээ': 3,
    'ботго': 4, 'гурван 7': 4, 'гурван долоо': 4,
  };
  if (aliases.containsKey(normalized)) return aliases[normalized];
  final match = RegExp(
          r'^(хөзрөн|хөзрэн|хөзөр|хөзрийн|тамган|ботгон) (буур|буусан|буурсан)$')
      .firstMatch(normalized);
  if (match == null) return null;
  return switch (match.group(1)) {
    'тамган' => 3,
    'ботгон' => 4,
    _ => 2,
  };
}

bool isBuurVoiceActionPrefix(String text) => const {
      'тоо',
      'тоо хүр',
      'хөзрөн',
      'хөзрэн',
      'хөзөр',
      'хөзрийн',
      'тамган',
      'ботгон',
      'оноо хүр',
      'гучин',
      'гурван',
    }.contains(normalizeBuurSpeech(text));

/// Repeated attempts must agree on both the player and the amount.
({int playerIndex, int transfer})? parseBuurVoiceCommand(
    String text, List<List<String>> playerNames) {
  final normalized =
      normalizeBuurSpeech(text).replaceFirst(RegExp(r' боллоо$'), '');
  final aliases = playerNames
      .expand((names) => names.expand(buurNameAliases))
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (aliases.isEmpty) return null;
  final mentions =
      RegExp('(^| )(${aliases.map(RegExp.escape).join('|')})(?= |\$)')
          .allMatches(normalized)
          .toList();
  if (mentions.length > 1) {
    if (mentions.first.start != 0) return null;
    ({int playerIndex, int transfer})? command;
    for (int i = 0; i < mentions.length; i++) {
      final segment = normalized
          .substring(
              mentions[i].start,
              i + 1 < mentions.length
                  ? mentions[i + 1].start
                  : normalized.length)
          .trim();
      final parsed = parseBuurVoiceCommand(segment, playerNames);
      if (parsed == null) {
        final fragment = normalized
            .substring(
                mentions[i].end,
                i + 1 < mentions.length
                    ? mentions[i + 1].start
                    : normalized.length)
            .trim();
        if (i + 1 == mentions.length ||
            !const {'', 'өдөр', 'хөзрөн', 'хөзрэн'}.contains(fragment)) {
          return null;
        }
      } else if (command != null && command != parsed) {
        return null;
      } else {
        command = parsed;
      }
    }
    if (command == null) return null;
    // Even unfinished attempts must name the same unambiguous player.
    for (final mention in mentions) {
      final probe =
          parseBuurVoiceCommand('${mention.group(2)} хөзрөн буур', playerNames);
      if (probe == null || probe.playerIndex != command.playerIndex) {
        return null;
      }
    }
    return command;
  }
  final match = RegExp(
          r'^(.+) ((?:хөзрөн|хөзрэн|хөзөр|хөзрийн|тамган|ботгон) (?:буур|буусан|буурсан)|тоо хүрлээ|оноо хүрлээ|оноо|31|гучин нэг|хөзөр|тамга|хайбар сэнгээ|хайбар|ботго|гурван 7|гурван долоо)$')
      .firstMatch(normalized);
  if (match == null) return null;
  final name = match.group(1)!;
  final matches = <int>[];
  for (int i = 0; i < playerNames.length; i++) {
    if (playerNames[i].expand(buurNameAliases).contains(name)) {
      matches.add(i);
    }
  }
  if (matches.length != 1) return null;
  final transfer = parseBuurVoiceAction(match.group(2)!)!;
  return (playerIndex: matches.single, transfer: transfer);
}
