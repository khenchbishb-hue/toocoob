import 'poker_voice_score.dart';

int? parse501Number(String text) {
  if (const {'нойл', 'оноо аваагүй'}.contains(text)) return 0;
  if (const {'хожлоо', 'хожсон'}.contains(text)) return null;
  final direct = parsePokerVoiceScore(text);
  if (direct != null) return direct;
  final match = RegExp(
          r'^(хоёр|гурван|дөрвөн|таван|зургаан|долоон|найман|есөн) зуу(?:н)?(?: (.+))?$')
      .firstMatch(text);
  if (match == null) return null;
  const hundreds = {
    'хоёр': 2,
    'гурван': 3,
    'дөрвөн': 4,
    'таван': 5,
    'зургаан': 6,
    'долоон': 7,
    'найман': 8,
    'есөн': 9
  };
  final rest =
      match.group(2) == null ? 0 : parsePokerVoiceScore(match.group(2)!);
  if (rest == null || rest < 0 || rest >= 100) return null;
  return hundreds[match.group(1)]! * 100 + rest;
}

List<({int suit, bool remove})> parse501Suits(String text) {
  const suits = {'гил': 0, 'цэцэг': 1, 'дөрвөлжин': 2, 'бунд': 3};
  final words = text.replaceAll(',', ' ').split(RegExp(r'\s+'));
  final remove = words.contains('хасах') || words.contains('цуцлах');
  if (words.any((w) =>
      !suits.containsKey(w) && !{'хасах', 'цуцлах', 'ба', ''}.contains(w)))
    return [];
  return [
    for (final word in words)
      if (suits.containsKey(word)) (suit: suits[word]!, remove: remove)
  ];
}

int score501Result(
    {required int before,
    required bool isTaker,
    required int playPrice,
    required int cardPoints,
    required int suitPoints,
    bool bolt = false}) {
  if (isTaker && before > 0 && before < 121) {
    return cardPoints == 121 ? 0 : before + 121;
  }
  if (!isTaker) return before - cardPoints - suitPoints;
  final price = playPrice;
  return before + (cardPoints + suitPoints >= price ? -price : price);
}

List<int> rank501Round(List<({int points, int suitQuality, int originalOrder})> results) {
  final indexes = List.generate(results.length, (i) => i);
  indexes.sort((a, b) {
    final points = results[b].points.compareTo(results[a].points);
    if (points != 0) return points;
    final quality = results[b].suitQuality.compareTo(results[a].suitQuality);
    return quality != 0 ? quality : results[a].originalOrder.compareTo(results[b].originalOrder);
  });
  return indexes;
}
