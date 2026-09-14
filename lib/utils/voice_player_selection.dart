/// Finds the last whole player name in an already normalized transcript.
/// A shared alias remains ambiguous instead of choosing an arbitrary player.
({int? playerIndex, int start, int end})? lastVoicePlayerMention(
    String text, List<Iterable<String>> playerAliases) {
  final owners = <String, Set<int>>{};
  for (var i = 0; i < playerAliases.length; i++) {
    for (final alias in playerAliases[i]) {
      if (alias.isNotEmpty) (owners[alias] ??= <int>{}).add(i);
    }
  }
  if (owners.isEmpty) return null;
  final aliases = owners.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final matches =
      RegExp('(?<!\\S)(${aliases.map(RegExp.escape).join('|')})(?= |\$)')
          .allMatches(text);
  if (matches.isEmpty) return null;
  final match = matches.last;
  final players = owners[match.group(1)]!;
  return (
    playerIndex: players.length == 1 ? players.single : null,
    start: match.start,
    end: match.end,
  );
}
