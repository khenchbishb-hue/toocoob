class DemoPlayer {
  const DemoPlayer({
    required this.id,
    required this.username,
    required this.displayName,
    required this.fullName,
  });

  final String id;
  final String username;
  final String displayName;
  final String fullName;
}

class DemoPlayers {
  DemoPlayers._();

  static const List<DemoPlayer> all = <DemoPlayer>[
    DemoPlayer(
        id: 'demo_player_01',
        username: 'indian',
        displayName: 'Индиан',
        fullName: 'Бат-Эрдэнэ'),
    DemoPlayer(
        id: 'demo_player_02',
        username: 'ms',
        displayName: 'МС',
        fullName: 'Оч-Эрдэнэ'),
    DemoPlayer(
        id: 'demo_player_03',
        username: 'syska',
        displayName: 'Сыска',
        fullName: 'Батмагнай'),
    DemoPlayer(
        id: 'demo_player_04',
        username: 'shovgor',
        displayName: 'Шовгор',
        fullName: 'Баарсайхан'),
    DemoPlayer(
        id: 'demo_player_05',
        username: 'shuumul',
        displayName: 'Шумуул',
        fullName: 'Лхагвасүрэн'),
    DemoPlayer(
        id: 'demo_player_06',
        username: 'bazilio',
        displayName: 'Базилио',
        fullName: 'Сарантуяа'),
    DemoPlayer(
        id: 'demo_player_07',
        username: 'ayanga',
        displayName: 'Аянга',
        fullName: 'Анхбаяр'),
    DemoPlayer(
        id: 'demo_player_08',
        username: 'boroo',
        displayName: 'Бороо',
        fullName: 'Болдбаатар'),
    DemoPlayer(
        id: 'demo_player_09',
        username: 'galaa',
        displayName: 'Галаа',
        fullName: 'Ганзориг'),
    DemoPlayer(
        id: 'demo_player_10',
        username: 'temuujin',
        displayName: 'Тэмүүжин',
        fullName: 'Тэмүүлэн'),
  ];

  static DemoPlayer? byId(String? id) {
    if (id == null) return null;
    for (final player in all) {
      if (player.id == id) return player;
    }
    return null;
  }

  static Map<String, dynamic>? profileForId(String id) {
    final player = byId(id);
    if (player == null) return null;
    return {
      'username': player.username,
      'displayName': player.displayName,
      'fullName': player.fullName,
    };
  }

  static bool isDemoId(String? id) => byId(id) != null;
}
