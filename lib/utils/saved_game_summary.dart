import 'saved_game_sessions_repository.dart';

String savedGameSummary(SavedGameSession session) {
  final p = session.payload;
  const labels = {
    'score': 'Оноо', 'currentScore': 'Оноо', 'totalScoreText': 'Нийт оноо',
    'roundScore': 'Үеийн оноо', 'roundScoreText': 'Үеийн оноо',
    'wins': 'Хожил', 'money': 'Мөнгөн дүн', 'pishka': 'Пишка',
    'durakCups': 'Цом', 'bombs': 'Бөмбөг',
    'cleanCanastas': 'Цэвэр канаст', 'dirtyCanastas': 'Бохир канаст',
    'dranksCount': 'Авсан тоо',
  };
  String metrics(Map row) => labels.entries
      .where((e) => row[e.key] != null)
      .map((e) => '${e.value}: ${row[e.key]}').join(' · ');
  final lines = <String>[];
  if (p['roundNumber'] != null) lines.add('Үе: ${p['roundNumber']}');
  final rows = p['seats'] ?? p['players'];
  if (rows is List) {
    for (final row in rows.whereType<Map>()) {
      final name = row['displayName'] ?? row['username'] ?? row['userId'] ?? 'Тоглогч';
      lines.add('$name — ${metrics(row)}');
    }
  } else {
    final ids = p['orderedUserNames'] as List? ?? session.selectedUserIds;
    final names = p['orderedDisplayNames'] as List? ?? p['displayNames'] as List?;
    const maps = {'totalScores': 'Оноо', 'winsByUserId': 'Хожил',
      'moneyByUserId': 'Мөнгөн дүн', 'multiWins': 'Хожил', 'playerMoney': 'Мөнгөн дүн'};
    for (var i = 0; i < ids.length; i++) {
      final values = <String>[];
      for (final entry in maps.entries) {
        final map = p[entry.key];
        if (map is Map && map[ids[i]] != null) values.add('${entry.value}: ${map[ids[i]]}');
      }
      final name = names != null && i < names.length ? names[i] : ids[i];
      lines.add('$name${values.isEmpty ? '' : ' — ${values.join(' · ')}'}');
    }
  }
  if (p['scores'] is List) {
    final scores = p['scores'] as List;
    for (var i = 0; i < scores.length; i++) {
      if (scores[i] is Map) lines.add('Баг ${i + 1} — ${metrics(scores[i] as Map)}');
    }
  }
  for (final entry in const {'teamWins': 'Багийн хожил', 'teamMoney': 'Багийн мөнгөн дүн',
    'centerScore': 'Голын оноо', 'targetWins': 'Зорилтот хожил'}.entries) {
    if (p[entry.key] != null) lines.add('${entry.value}: ${p[entry.key]}');
  }
  return lines.join('\n');
}
