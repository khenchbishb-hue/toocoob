import 'package:firebase_auth/firebase_auth.dart';
import '../utils/player_profiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:uuid/uuid.dart';
import '13_card_poker.dart';
import '5_card_texas.dart';
import 'muushig.dart';
import 'buur.dart';
import '108.dart';
import 'xodrox.dart';
import 'nvx_shaxax.dart';
import 'durak.dart';
import '501.dart';
import 'canasta.dart';
import 'cai_xuraax.dart';
import 'other_game.dart';
import 'saved_sessions_page.dart';
import 'statistics_dashboard.dart';
import 'player_selection_page.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'package:toocoob/utils/active_tables_repository.dart';
import 'package:toocoob/widgets/active_table_route_scope.dart';

class KindsOfGamePage extends StatefulWidget {
  const KindsOfGamePage({
    super.key,
    required this.selectedUserIds,
    this.playingFormat = 'multi',
    this.currentUserId,
    this.canManageGames = false,
    this.initialSavedSessionId,
    this.createAdditionalTable = false,
  });

  final List<String> selectedUserIds;
  final String playingFormat;
  final String? currentUserId;
  final bool canManageGames;
  final String? initialSavedSessionId;
  final bool createAdditionalTable;

  @override
  State<KindsOfGamePage> createState() => _KindsOfGamePageState();
}

class _KindsOfGamePageState extends State<KindsOfGamePage> {
  String? get _effectiveUserId => widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
  bool _openingTable = false;

  int _multiSettlementUnit = 10000;

  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();
  final ActiveTablesRepository _activeTablesRepo = ActiveTablesRepository();
  final Set<int> _completedGameIndexes = <int>{};

  // In 2-player multi-format, only these 7 game types are allowed.
  static const Set<int> _twoPlayerAllowedGameIndices = <int>{
    0, // 13 модны покер
    1, // 5 модны Техас
    2, // Муушиг
    3, // Буур
    4, // 108
    5, // Ходрох
    7, // Дурак
  };
  static const int _index501 = 8;
  static const int _indexCanasta = 9;
  static const Map<int, Set<int>> _exactPlayerCountsByGameIndex =
      <int, Set<int>>{
    _index501: <int>{3, 4, 5, 6, 7},
    _indexCanasta: <int>{4, 6},
  };

  // For multi-format: track per-player wins (userId → count)
  final Map<String, int> _multiWins = {};
  // Loaded player info
  Map<String, String> _playerDisplayNames = {};
  Map<String, String> _playerUsernames = {};
  Map<String, String> _playerPhotoUrls = {};
  bool _namesLoaded = false;
  bool _include501ForMulti = false;
  bool _includeCanastaForMulti = false;
  bool _isThreePlayerTieBreaker = false;
  List<String> _threePlayerTieBreakerUserIds = const <String>[];
  final Map<String, List<int>> _multiWinGameIndices = <String, List<int>>{};
  String? _activeSavedSessionId;

  static const Map<String, int> _gameKeyToIndex = {
    'durak': 7,
  };

  static const Map<int, String> _indexToGameKey = {
    0: '13_card_poker',
    1: 'card_texas',
    2: 'muushig',
    3: 'buur',
    4: 'game108',
    5: 'xodrox',
    6: 'nvx_shaxax',
    7: 'durak',
    8: 'game501',
    9: 'canasta',
    10: 'cai_xuraax',
    11: 'other_game',
  };

  static const List<String> _gameNames = [
    '13 модны\nпокер',
    '5 модны\nТехас',
    'Муушиг',
    'Буур',
    '108',
    'Ходрох',
    'Нүх\nшахах',
    'Дурак',
    '501',
    'Канастер',
    'Цай\nхураах',
    '...',
  ];

  static const List<String> _gameImages = [
    'assets/13.jpg',
    'assets/5.jpg',
    'assets/muushig.jpg',
    'assets/buur.jpg',
    'assets/108.jpg',
    'assets/21.jpg',
    'assets/nvx.jpg',
    'assets/durak.jpg',
    'assets/501.jpg',
    'assets/canasta.jpg',
    'assets/daaluu.jpg',
    '',
  ];

  // Minimum player count required for each game (index matches games list).
  // 99 = not eligible for multi-format (no score tracking).
  static const List<int> _gameMinPlayers = [
    2, // 0: 13 модны покер
    2, // 1: 5 модны Техас
    2, // 2: Муушиг
    2, // 3: Буур
    2, // 4: 108
    2, // 5: Ходрох
    2, // 6: Нүх шахах
    2, // 7: Дурак
    1, // 8: 501
    2, // 9: Канастер
    99, // 10: Цай хураах (score tracking not supported)
    99, // 11: ...
  ];

  @override
  void initState() {
    super.initState();
    if (widget.playingFormat == 'multi') {
      _loadPlayerNames();
      _tryRestoreMultiSession();
    }
  }

  int get _playedMultiGamesCount => _multiWinGameIndices.values
      .fold<int>(0, (sum, indices) => sum + indices.length);

  bool get _canEditParticipants =>
      widget.playingFormat == 'multi' &&
      _completedGameIndexes.isEmpty &&
      !_isThreePlayerTieBreaker;

  Future<void> _loadPlayerNames() async {
    final Map<String, String> displayNames = {};
    final Map<String, String> usernames = {};
    final Map<String, String> photoUrls = {};
    for (final uid in widget.selectedUserIds) {
      try {
        final data = await loadPlayerProfile(uid);
        if (data != null) {
          final uname = (data['username'] as String?)?.trim() ?? uid;
          final dname = (data['displayName'] as String?)?.trim() ?? uname;
          final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
          usernames[uid] = uname;
          displayNames[uid] = dname;
          photoUrls[uid] = photoUrl;
        } else {
          usernames[uid] = uid;
          displayNames[uid] = uid;
          photoUrls[uid] = '';
        }
      } catch (_) {
        usernames[uid] = uid;
        displayNames[uid] = uid;
        photoUrls[uid] = '';
      }
    }
    if (!mounted) return;
    setState(() {
      _playerUsernames = usernames;
      _playerDisplayNames = displayNames;
      _playerPhotoUrls = photoUrls;
      _namesLoaded = true;
    });
  }

  bool _isCompatibleForMulti(int index) {
    if (_isThreePlayerTieBreaker) {
      final tiePlayerCount = _threePlayerTieBreakerUserIds.length;
      // A tie-break must produce one person; team-based Canasta cannot do that.
      if (index == _indexCanasta) return false;
      if (tiePlayerCount == 2) {
        return _twoPlayerAllowedGameIndices.contains(index);
      }
      if (index == _index501) {
        return (tiePlayerCount >= 3 && tiePlayerCount <= 7) &&
            _include501ForMulti;
      }
      if (index == _indexCanasta) {
        return (tiePlayerCount == 4 || tiePlayerCount == 6) &&
            _includeCanastaForMulti;
      }
      return index < _gameMinPlayers.length &&
          _gameMinPlayers[index] < 99 &&
          tiePlayerCount >= _gameMinPlayers[index];
    }

    if (index >= _gameMinPlayers.length) return false;
    if (!_isPlayerCountAllowed(index, widget.selectedUserIds.length)) {
      return false;
    }
    final min = _gameMinPlayers[index];
    if (min >= 99 || widget.selectedUserIds.length < min) return false;

    // Special multi-format rule for exactly 2 players.
    if (widget.selectedUserIds.length == 2) {
      return _twoPlayerAllowedGameIndices.contains(index);
    }

    final playerCount = widget.selectedUserIds.length;
    if (index == _index501) {
      return (playerCount >= 3 && playerCount <= 7) && _include501ForMulti;
    }
    if (index == _indexCanasta) {
      return (playerCount == 4 || playerCount == 6) && _includeCanastaForMulti;
    }

    return true;
  }

  bool _isPlayerCountAllowed(int index, int playerCount) {
    if (index < 0 || index >= _gameMinPlayers.length) return false;
    final exactCounts = _exactPlayerCountsByGameIndex[index];
    if (exactCounts != null) return exactCounts.contains(playerCount);
    final minimum = _gameMinPlayers[index];
    return minimum < 99 && playerCount >= minimum;
  }

  String _playerCountRequirementLabel(int index) {
    final exactCounts = _exactPlayerCountsByGameIndex[index];
    if (exactCounts != null) {
      final sorted = exactCounts.toList()..sort();
      return '${sorted.join(' эсвэл ')} тоглогч';
    }
    return '${_gameMinPlayers[index]}+ тоглогч';
  }

  List<int> get _compatibleGameIndices =>
      List.generate(_gameMinPlayers.length, (i) => i)
          .where(_isCompatibleForMulti)
          .toList();

  bool get _allMultiGamesCompleted {
    final compatible = _compatibleGameIndices;
    return compatible.isNotEmpty &&
        compatible.every((i) => _completedGameIndexes.contains(i));
  }

  int get _multiTotalTypeCount {
    final total = _compatibleGameIndices.length;
    return total <= 0 ? 1 : total;
  }

  int get _multiCurrentTypeNumber {
    final current = _completedGameIndexes.length + 1;
    final total = _multiTotalTypeCount;
    if (current < 1) return 1;
    if (current > total) return total;
    return current;
  }

  bool get _hasUncatchableMultiLeader {
    if (_isThreePlayerTieBreaker || widget.selectedUserIds.length < 2) {
      return false;
    }
    final remainingTypes = _compatibleGameIndices
        .where((index) => !_completedGameIndexes.contains(index))
        .length;
    final wins = widget.selectedUserIds
        .map((userId) => _multiWins[userId] ?? 0)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return wins.length >= 2 && wins.first > wins[1] + remainingTypes;
  }

  List<String> get _activeGameUserIds {
    if (_isThreePlayerTieBreaker && _threePlayerTieBreakerUserIds.length >= 2) {
      return List<String>.from(_threePlayerTieBreakerUserIds);
    }
    return List<String>.from(widget.selectedUserIds);
  }

  bool _shouldStartThreePlayerTieBreaker() {
    if (_isThreePlayerTieBreaker) return false;

    final sorted = List<String>.from(widget.selectedUserIds)
      ..sort((a, b) => (_multiWins[b] ?? 0).compareTo(_multiWins[a] ?? 0));
    if (sorted.length < 2) return false;

    final topWins = _multiWins[sorted[0]] ?? 0;
    if ((_multiWins[sorted[1]] ?? 0) != topWins) return false;
    final topPlayers = sorted.where((uid) => (_multiWins[uid] ?? 0) == topWins);
    return topPlayers.length >= 2;
  }

  Future<void> _startThreePlayerTieBreaker() async {
    final sorted = List<String>.from(widget.selectedUserIds)
      ..sort((a, b) => (_multiWins[b] ?? 0).compareTo(_multiWins[a] ?? 0));
    final topWins = _multiWins[sorted.first] ?? 0;
    final tied = sorted
        .where((uid) => (_multiWins[uid] ?? 0) == topWins)
        .toList(growable: false);
    if (tied.length < 2) return;

    if (mounted) {
      setState(() {
        _isThreePlayerTieBreaker = true;
        _threePlayerTieBreakerUserIds = tied;
      });
    }

    if (!mounted) return;
    final tiedNames =
        tied.map((userId) => _playerDisplayNames[userId] ?? userId).join(', ');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Эцсийн ялалт тодруулах тоглолт'),
        content: Text(
          '$tiedNames тэнцсэн байна.\n\n'
          'Эдгээр тоглогчдын тоонд тохирох төрлөөс сонгон цор ганц ялагчийг тодруулна уу.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ойлголоо'),
          ),
        ],
      ),
    );
  }

  String _gameNameForIndex(int index) {
    if (index >= 0 && index < _gameNames.length) {
      return _gameNames[index].replaceAll('\n', ' ').trim();
    }
    return 'Тоглоом';
  }

  Future<dynamic> _pushGameWithActiveTableLock({
    required int gameIndex,
    required Widget page,
    required List<String> activeUserIds,
  }) async {
    if (_openingTable) return null;
    _openingTable = true;
    try {
      return await _openGameTable(gameIndex: gameIndex, page: page, activeUserIds: activeUserIds);
    } finally {
      _openingTable = false;
    }
  }

  Future<dynamic> _openGameTable({
    required int gameIndex,
    required Widget page,
    required List<String> activeUserIds,
  }) async {
    final gameKey = _indexToGameKey[gameIndex];

    String? lockId;
    int? tableNumber;
    try {
      tableNumber = await _activeTablesRepo.fetchNextTableNumber();
      lockId = await _activeTablesRepo.createActiveTableLock(
        gameKey: gameKey ?? 'unknown_game',
        gameName: _gameNameForIndex(gameIndex),
        playerUserIds: List<String>.from(activeUserIds),
        playingFormat: widget.playingFormat,
        ownerUserId: _effectiveUserId,
        tableNumber: tableNumber,

      );

    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ширээ нээж чадсангүй. Холболтоо шалгаад дахин оролдоно уу.'),
        ));
      }
      return null;
    }

    if (!mounted) return null;
    final routeName = 'active-table:$lockId';
    return Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: routeName),
        builder: (context) => ActiveTableRouteScope(
                routeName: routeName,
                child: page,
              ),
      ),
    );
  }

  Future<void> _tryRestoreMultiSession() async {
    final id = widget.initialSavedSessionId;
    if (id == null || id.isEmpty) return;
    final saved = await _savedSessionsRepo.findById(id);
    if (!mounted || saved == null || saved.gameKey != 'multi_format') return;
    final payload = saved.payload;

    final restoredWins = <String, int>{};
    final rawWins = payload['multiWins'];
    if (rawWins is Map) {
      for (final entry in rawWins.entries) {
        restoredWins[entry.key.toString()] = (entry.value as num? ?? 0).toInt();
      }
    }

    final restoredWinGames = <String, List<int>>{};
    final rawWinGames = payload['multiWinGameIndices'];
    if (rawWinGames is Map) {
      for (final entry in rawWinGames.entries) {
        final values = (entry.value as List? ?? const <dynamic>[])
            .map((value) => (value as num?)?.toInt())
            .whereType<int>()
            .toList(growable: false);
        restoredWinGames[entry.key.toString()] = values;
      }
    }

    if (!mounted) return;
    setState(() {
      _activeSavedSessionId = saved.id;
      _completedGameIndexes
        ..clear()
        ..addAll((payload['completedGameIndexes'] as List? ?? const <dynamic>[])
            .map((value) => (value as num?)?.toInt())
            .whereType<int>());
      _multiWins
        ..clear()
        ..addAll(restoredWins);
      _multiWinGameIndices
        ..clear()
        ..addAll(restoredWinGames);
      _include501ForMulti = payload['include501ForMulti'] == true ||
          payload['include501ForThreePlayers'] == true;
      _includeCanastaForMulti = payload['includeCanastaForMulti'] == true;
      _isThreePlayerTieBreaker = payload['isThreePlayerTieBreaker'] == true;
      _threePlayerTieBreakerUserIds =
          (payload['threePlayerTieBreakerUserIds'] as List? ??
                  const <dynamic>[])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
    });
  }

  Future<void> _saveMultiProgress() async {
    final payload = <String, dynamic>{
      'completedGameIndexes': _completedGameIndexes.toList(growable: false),
      'multiWins': Map<String, int>.from(_multiWins),
      'multiWinGameIndices': _multiWinGameIndices.map(
        (key, value) => MapEntry(key, List<int>.from(value)),
      ),
      'include501ForMulti': _include501ForMulti,
      'includeCanastaForMulti': _includeCanastaForMulti,
      // Backward-compatible key for previously saved sessions.
      'include501ForThreePlayers': _include501ForMulti,
      'isThreePlayerTieBreaker': _isThreePlayerTieBreaker,
      'threePlayerTieBreakerUserIds':
          List<String>.from(_threePlayerTieBreakerUserIds),
    };

    final sessionId = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: 'multi_format',
      gameLabel: 'Олон төрөлт',
      selectedUserIds: List<String>.from(widget.selectedUserIds),
      payload: payload,
    );

    _activeSavedSessionId = sessionId;
    if (!mounted) return;
  }

  Future<void> _removeSavedMultiProgressIfAny() async {
    final id = _activeSavedSessionId;
    if (id == null || id.isEmpty) return;
    await _savedSessionsRepo.removeById(id);
    _activeSavedSessionId = null;
  }

  String _cleanGameName(String value) => value.replaceAll('\n', ' ');

  Map<int, int> _aggregateWonGameCounts(String userId) {
    final result = <int, int>{};
    for (final gameIndex in _multiWinGameIndices[userId] ?? const <int>[]) {
      result[gameIndex] = (result[gameIndex] ?? 0) + 1;
    }
    return result;
  }

  List<String> _wonGameLabels(String userId) {
    final aggregated = _aggregateWonGameCounts(userId);
    final sortedKeys = aggregated.keys.toList()..sort();
    return sortedKeys.map((index) {
      final count = aggregated[index] ?? 0;
      final label = index >= 0 && index < _gameNames.length
          ? _cleanGameName(_gameNames[index])
          : 'Төрөл #${index + 1}';
      return count > 1 ? '$label x$count' : label;
    }).toList(growable: false);
  }

  Map<String, int> _calculateSettlementAmounts(List<String> winners) {
    final settlements = <String, int>{
      for (final uid in widget.selectedUserIds) uid: 0,
    };
    if (winners.isEmpty) return settlements;

    final winnerWins = winners
        .map((uid) => _multiWins[uid] ?? 0)
        .fold<int>(0, (maxValue, value) => value > maxValue ? value : maxValue);

    int totalPositive = 0;
    for (final uid in widget.selectedUserIds) {
      if (winners.contains(uid)) continue;
      final wins = _multiWins[uid] ?? 0;
      final loss =
          (winnerWins - wins).clamp(1, winnerWins) * _multiSettlementUnit;
      settlements[uid] = -loss;
      totalPositive += loss;
    }

    final split = winners.isEmpty ? 0 : totalPositive ~/ winners.length;
    int remainder = winners.isEmpty ? 0 : totalPositive % winners.length;
    for (final uid in winners) {
      settlements[uid] = split + (remainder > 0 ? _multiSettlementUnit : 0);
      if (remainder > 0) remainder -= _multiSettlementUnit;
    }
    return settlements;
  }

  String _buildMultiFormatReportText({List<String>? forcedWinners}) {
    int maxWins = 0;
    for (final wins in _multiWins.values) {
      if (wins > maxWins) maxWins = wins;
    }
    final winners = forcedWinners == null
        ? widget.selectedUserIds
            .where((uid) => (_multiWins[uid] ?? 0) == maxWins)
            .toList(growable: false)
        : List<String>.from(forcedWinners);
    final settlements = _calculateSettlementAmounts(winners);
    final ranking = List<String>.from(widget.selectedUserIds)
      ..sort((a, b) => (_multiWins[b] ?? 0).compareTo(_multiWins[a] ?? 0));

    final lines = <String>[
      'ОЛОН ТӨРӨЛТ - ТАЙЛАН',
      'Тоглосон төрөл: $_playedMultiGamesCount',
      'Ялагч: ${winners.map((uid) => _playerDisplayNames[uid] ?? uid).join(', ')}',
      '',
      'Чансаа:',
    ];

    for (int i = 0; i < ranking.length; i++) {
      final uid = ranking[i];
      final wins = _multiWins[uid] ?? 0;
      final settlement = settlements[uid] ?? 0;
      final wonGames = _wonGameLabels(uid);
      lines.add(
        '${i + 1}. ${_playerDisplayNames[uid] ?? uid} - $wins ялалт - ${settlement >= 0 ? '+' : ''}₮$settlement',
      );
      lines.add(
        wonGames.isEmpty
            ? '   Ялсан төрөл: -'
            : '   Ялсан төрөл: ${wonGames.join(', ')}',
      );
    }

    return lines.join('\n');
  }

  Future<void> _showMultiFormatReportDialog(
      {List<String>? forcedWinners}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Олон төрөлтийн тайлан'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(_buildMultiFormatReportText(
              forcedWinners: forcedWinners,
            )),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Хаах'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMultiSettingsDialog() async {
    if (!mounted) return;

    int settlementUnit = _multiSettlementUnit;
    final settlementController =
        TextEditingController(text: settlementUnit.toString());

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AlertDialog(
          title: const Text('Олон төрөлтийн тохиргоо'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Хожлын мөнгөний нэгж (₮)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: settlementController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Жишээ: 10000',
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  setInnerState(() {
                    settlementUnit = parsed ?? 0;
                  });
                },
              ),
              const SizedBox(height: 6),
              Text(
                settlementUnit > 0
                    ? 'Одоогийн дүн: ₮$settlementUnit'
                    : '1-ээс их дүн оруулна уу.',
                style: TextStyle(
                  fontSize: 12,
                  color: settlementUnit > 0 ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Болих'),
            ),
            ElevatedButton(
              onPressed: settlementUnit > 0
                  ? () {
                      setState(() {
                        _multiSettlementUnit = settlementUnit;
                      });
                      Navigator.pop(ctx);
                    }
                  : null,
              child: const Text('Хадгалах'),
            ),
          ],
        ),
      ),
    );

    settlementController.dispose();
  }

  Future<void> _openAddPlayersFlow() async {
    if (!_canEditParticipants) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Тоглолт эхэлсний дараа бүрэлдэхүүн солихгүй.')),
      );
      return;
    }

    final addedUserIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: List<String>.from(widget.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
        ),
      ),
    );

    if (!mounted || addedUserIds == null || addedUserIds.isEmpty) return;
    final nextUserIds = <String>[
      ...widget.selectedUserIds,
      ...addedUserIds
          .where((userId) => !widget.selectedUserIds.contains(userId)),
    ];

    if (nextUserIds.length < 2) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => KindsOfGamePage(
          selectedUserIds: nextUserIds,
          playingFormat: widget.playingFormat,
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
        ),
      ),
    );
  }

  Future<void> _openRemovePlayersFlow() async {
    if (!_canEditParticipants) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Тоглолт эхэлсний дараа бүрэлдэхүүн солихгүй.')),
      );
      return;
    }

    final selectedForRemoval = <String>{};
    final removedUserIds = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AlertDialog(
          title: const Text('Тоглогч хасах'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.selectedUserIds.map((uid) {
                  final displayName = _playerDisplayNames[uid] ?? uid;
                  final checked = selectedForRemoval.contains(uid);
                  return CheckboxListTile(
                    value: checked,
                    title: Text(displayName),
                    subtitle: Text(_playerUsernames[uid] ?? uid),
                    onChanged: (value) {
                      setInnerState(() {
                        if (value == true) {
                          selectedForRemoval.add(uid);
                        } else {
                          selectedForRemoval.remove(uid);
                        }
                      });
                    },
                  );
                }).toList(growable: false),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Болих'),
            ),
            ElevatedButton(
              onPressed:
                  widget.selectedUserIds.length - selectedForRemoval.length >= 2
                      ? () => Navigator.pop(ctx, selectedForRemoval.toList())
                      : null,
              child: const Text('Хасах'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || removedUserIds == null || removedUserIds.isEmpty) return;
    final nextUserIds = widget.selectedUserIds
        .where((uid) => !removedUserIds.contains(uid))
        .toList(growable: false);
    if (nextUserIds.length < 2) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => KindsOfGamePage(
          selectedUserIds: nextUserIds,
          playingFormat: widget.playingFormat,
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
        ),
      ),
    );
  }

  Widget _buildAppBarAssetButton({
    required String assetPath,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Image.asset(
        assetPath,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildDialogAssetButton({
    required String assetPath,
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: primary ? 2 : 0,
        backgroundColor: primary ? Colors.deepPurple : Colors.white,
        foregroundColor: primary ? Colors.white : Colors.black87,
        side: primary ? null : BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      icon: Image.asset(
        assetPath,
        width: 18,
        height: 18,
        fit: BoxFit.contain,
      ),
      label: Text(label),
    );
  }

  Widget _buildPlayerAvatar(String? uid, {double radius = 24}) {
    final name = uid == null ? '' : (_playerDisplayNames[uid] ?? uid);
    final photoUrl = uid == null ? '' : (_playerPhotoUrls[uid] ?? '');
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.deepPurple.withValues(alpha: 0.12),
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            )
          : null,
    );
  }

  bool _showsInclusionButtonOnCard(int index) {
    final playerCount = widget.selectedUserIds.length;
    return widget.playingFormat == 'multi' &&
        !_isThreePlayerTieBreaker &&
        ((index == _index501 && (playerCount >= 3 && playerCount <= 7)) ||
            (index == _indexCanasta && (playerCount == 4 || playerCount == 6)));
  }

  bool _isCardIncludedForMulti(int index) {
    if (index == _index501) return _include501ForMulti;
    if (index == _indexCanasta) return _includeCanastaForMulti;
    return true;
  }

  void _toggleCardInclusionForMulti(int index) {
    if (_completedGameIndexes.contains(index)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Дууссан төрлийг оруулах/хасах боломжгүй.')),
      );
      return;
    }

    setState(() {
      if (index == _index501) {
        _include501ForMulti = !_include501ForMulti;
      } else if (index == _indexCanasta) {
        _includeCanastaForMulti = !_includeCanastaForMulti;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Буцах',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Image.asset(
            'assets/buttons/back.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        ),
        title: Text(widget.playingFormat == 'multi'
            ? 'Олон төрөлт'
            : widget.playingFormat == 'crazy'
                ? 'Галзуу ганц'
                : 'Тоглолтын төрөл'),
        elevation: 0,
        actions: [
          if (widget.playingFormat == 'multi') ...[
            _buildAppBarAssetButton(
              assetPath: 'assets/buttons/remove user.png',
              tooltip: 'Тоглогч хасах',
              onPressed: _openRemovePlayersFlow,
            ),
            _buildAppBarAssetButton(
              assetPath: 'assets/buttons/add user.webp',
              tooltip: 'Тоглогч нэмэх',
              onPressed: _openAddPlayersFlow,
            ),
            _buildAppBarAssetButton(
              assetPath: 'assets/buttons/stats.png',
              tooltip: 'Статистик',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StatisticsDashboardPage(),
                  ),
                );
              },
            ),
            _buildAppBarAssetButton(
              assetPath: 'assets/buttons/report.png',
              tooltip: 'Тайлан',
              onPressed: _showMultiFormatReportDialog,
            ),
            _buildAppBarAssetButton(
              assetPath: 'assets/buttons/save.png',
              tooltip: 'Хадгалах',
              onPressed: _saveMultiProgress,
            ),
            _buildAppBarAssetButton(
              assetPath: 'assets/buttons/settings.png',
              tooltip: 'Тохиргоо',
              onPressed: _showMultiSettingsDialog,
            ),
          ],
          if (widget.playingFormat != 'multi')
            IconButton(
              tooltip: 'Сүүлд тоглосон',
              icon: const Icon(Icons.history),
              onPressed: () async {
                final saved = await Navigator.push<SavedGameSession>(
                  context,
                  MaterialPageRoute(builder: (_) => const SavedSessionsPage()),
                );
                if (!mounted || saved == null) return;
                await _resumeSavedSession(saved);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.playingFormat == 'multi') _buildMultiFormatHeader(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _gameNames.length,
              itemBuilder: (context, index) {
                final hasImage = _gameImages[index].isNotEmpty;
                final isCompleted = _completedGameIndexes.contains(index);
                final isPlayerCountIncompatible = !_isPlayerCountAllowed(
                    index, widget.selectedUserIds.length);
                final bool isIncompatible = isPlayerCountIncompatible ||
                    (widget.playingFormat == 'multi' &&
                        !_isCompatibleForMulti(index));
                final canReplayCompleted =
                    widget.playingFormat == 'multi' && _isThreePlayerTieBreaker;

                final bool effectivelyDisabled =
                    isIncompatible || (isCompleted && !canReplayCompleted);

                return Opacity(
                    opacity: effectivelyDisabled ? 0.4 : 1,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isIncompatible
                            ? Colors.grey.shade700
                            : Colors.deepPurple,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: effectivelyDisabled
                              ? null
                              : () {
                                  _navigateToGame(context, index);
                                },
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: hasImage
                                    ? Column(
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(6.0),
                                              child: Image.asset(
                                                _gameImages[index],
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    const BorderRadius.only(
                                                  bottomLeft:
                                                      Radius.circular(12),
                                                  bottomRight:
                                                      Radius.circular(12),
                                                ),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.black
                                                        .withValues(alpha: 0.3),
                                                    Colors.black
                                                        .withValues(alpha: 0.7),
                                                  ],
                                                ),
                                              ),
                                              child: Align(
                                                alignment:
                                                    Alignment.bottomCenter,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(6.0),
                                                  child: Text(
                                                    _gameNames[index],
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.black
                                                  .withValues(alpha: 0.3),
                                              Colors.black
                                                  .withValues(alpha: 0.7),
                                            ],
                                          ),
                                        ),
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.all(6.0),
                                            child: Text(
                                              _gameNames[index],
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              if (isCompleted && !canReplayCompleted)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.32),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.check_circle,
                                        color: Colors.lightGreenAccent,
                                        size: 64,
                                      ),
                                    ),
                                  ),
                                ),
                              // Incompatible label
                              if (isIncompatible)
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    child: Text(
                                      _showsInclusionButtonOnCard(index) &&
                                              !_isCardIncludedForMulti(index)
                                          ? 'Оруулаагүй'
                                          : _playerCountRequirementLabel(index),
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                                ),
                              if (_showsInclusionButtonOnCard(index))
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: TextButton(
                                    onPressed: () =>
                                        _toggleCardInclusionForMulti(index),
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 30),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      backgroundColor:
                                          _isCardIncludedForMulti(index)
                                              ? Colors.green.shade600
                                              : Colors.orange.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      _isCardIncludedForMulti(index)
                                          ? 'Хасах'
                                          : 'Оруулах',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiFormatHeader() {
    final sortedPlayers = List<String>.from(widget.selectedUserIds)
      ..sort((a, b) => (_multiWins[b] ?? 0).compareTo(_multiWins[a] ?? 0));
    final visiblePlayers = sortedPlayers.take(8).toList(growable: false);

    final headerRow = Row(
      children: List<Widget>.generate(8, (i) {
        final hasPlayer = i < visiblePlayers.length;
        final uid = hasPlayer ? visiblePlayers[i] : null;
        final name = uid == null ? '' : (_playerDisplayNames[uid] ?? uid);
        final wins = uid == null ? 0 : (_multiWins[uid] ?? 0);
        final username = uid == null ? '' : (_playerUsernames[uid] ?? uid);
        final photoUrl = uid == null ? '' : (_playerPhotoUrls[uid] ?? '');

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 7 ? 0 : 6),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: hasPlayer
                            ? Colors.deepPurple.shade400
                            : Colors.deepPurple.shade700,
                        image: photoUrl.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(photoUrl),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(
                              alpha: photoUrl.isNotEmpty ? 0.08 : 0.18,
                            ),
                            Colors.black.withValues(
                              alpha: photoUrl.isNotEmpty ? 0.20 : 0.30,
                            ),
                            Colors.black.withValues(alpha: 0.72),
                          ],
                          stops: const [0.0, 0.52, 1.0],
                        ),
                      ),
                    ),
                    if (photoUrl.isEmpty)
                      Center(
                        child: Text(
                          hasPlayer
                              ? (name.isNotEmpty
                                  ? name.characters.first.toUpperCase()
                                  : '?')
                              : '-',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hasPlayer ? name : 'Хоосон',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 8,
                                        color: Colors.black54,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  hasPlayer ? username : 'Хоосон',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 6,
                                        color: Colors.black45,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 46,
                            height: 46,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (hasPlayer)
                                  const Icon(
                                    Icons.star_outline_rounded,
                                    size: 46,
                                    color: Color(0xFF8F6200),
                                  ),
                                Icon(
                                  Icons.star_rounded,
                                  size: 42,
                                  color: hasPlayer
                                      ? const Color(0xFFFFD54F)
                                      : Colors.white24,
                                ),
                                if (hasPlayer)
                                  Text(
                                    '$wins',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );

    return Container(
      color: Colors.deepPurple.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          headerRow,
          if (_isThreePlayerTieBreaker &&
              _threePlayerTieBreakerUserIds.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Хайн хагалах: ${_threePlayerTieBreakerUserIds.map((userId) => _playerDisplayNames[userId] ?? userId).join(', ')}',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _navigateToGame(BuildContext context, int index) async {
    if (!_isPlayerCountAllowed(index, widget.selectedUserIds.length)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_gameNameForIndex(index)} тоглоомд ${_playerCountRequirementLabel(index)} шаардлагатай.',
          ),
        ),
      );
      return;
    }
    final canReplayCompleted =
        widget.playingFormat == 'multi' && _isThreePlayerTieBreaker;
    if (widget.playingFormat == 'multi' &&
        _completedGameIndexes.contains(index) &&
        !canReplayCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Энэ төрөл аль хэдийн тоглогдсон. Өөр төрөл сонгоно уу.'),
        ),
      );
      return;
    }

    final activeUserIds = _activeGameUserIds;
    Widget? page;
    switch (index) {
      case 0:
        if (activeUserIds.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Дор хаяж 2 тоглогч сонгоно уу')),
          );
          return;
        }
        page = ThirteenCardPokerScreen(
          gameType: '13 МОДНЫ ПОКЕР',
          selectedUserIds: activeUserIds,
          currentRegistrarUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
          multiCurrentTypeNumber: widget.playingFormat == 'multi'
              ? _multiCurrentTypeNumber
              : null,
          multiTotalTypeCount: widget.playingFormat == 'multi'
              ? _multiTotalTypeCount
              : null,
        );
        break;
      case 1:
        page = CardTexasPage(
          selectedUserIds: List<String>.from(activeUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
        );
        break;
      case 2:
        if (activeUserIds.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Дор хаяж 2 тоглогч сонгоно уу')),
          );
          return;
        }
        page = MuushigPage(
          selectedUserIds: List<String>.from(activeUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
          multiCurrentTypeNumber:
              widget.playingFormat == 'multi' ? _multiCurrentTypeNumber : null,
          multiTotalTypeCount:
              widget.playingFormat == 'multi' ? _multiTotalTypeCount : null,
        );
        break;
      case 3:
        page = BuurPage(
          selectedUserIds: List<String>.from(activeUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
          multiCurrentTypeNumber:
              widget.playingFormat == 'multi' ? _multiCurrentTypeNumber : null,
          multiTotalTypeCount:
              widget.playingFormat == 'multi' ? _multiTotalTypeCount : null,
        );
        break;
      case 4:
        if (activeUserIds.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Дор хаяж 2 тоглогч сонгоно уу')),
          );
          return;
        }
        page = Game108Page(
          selectedUserIds: List<String>.from(activeUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
          multiCurrentTypeNumber:
              widget.playingFormat == 'multi' ? _multiCurrentTypeNumber : null,
          multiTotalTypeCount:
              widget.playingFormat == 'multi' ? _multiTotalTypeCount : null,
        );
        break;
      case 5:
        page = HodrokhPage(
          selectedUserIds: List<String>.from(activeUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
        );
        break;
      case 6:
        page = NyxShaxaxPage(
          selectedUserIds: List<String>.from(activeUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
        );
        break;
      case 7:
        page = DurakPage(
          selectedUserIds: List<String>.from(activeUserIds),
          playingFormat: widget.playingFormat,
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
        );
        break;
      case 8:
        page = Game501Page(
          selectedUserIds: List<String>.from(activeUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          autoReturnOnWinner: widget.playingFormat != 'single',
          multiWinsByUserId: widget.playingFormat == 'multi'
              ? Map<String, int>.from(_multiWins)
              : null,
        );
        break;
      case 9:
        page = CanastaPage(
          selectedUserIds: List<String>.from(activeUserIds),
          playingFormat: widget.playingFormat,
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
        );
        break;
      case 10:
        page = const CaiXuraaxPage();
        break;
      case 11:
        page = const OtherGamePage();
        break;
    }

    if (page != null) {
      final result = await _pushGameWithActiveTableLock(
        gameIndex: index,
        page: page,
        activeUserIds: activeUserIds,
      );

      if (!mounted) return;

      if (widget.playingFormat == 'multi') {
        final winnerIds =
            await _extractWinnerUserIds(index, result, activeUserIds);
        if (winnerIds.isNotEmpty) {
          if (_isThreePlayerTieBreaker) {
            final winnerId = winnerIds.first;
            setState(() {
              _multiWins[winnerId] = (_multiWins[winnerId] ?? 0) + 1;
              _multiWinGameIndices
                  .putIfAbsent(winnerId, () => <int>[])
                  .add(index);
              _isThreePlayerTieBreaker = false;
              _threePlayerTieBreakerUserIds = const <String>[];
            });
            await _showMultiFormatFinalResult(
                forcedWinners: <String>[winnerId]);
            return;
          }

          setState(() {
            for (final winnerId in winnerIds) {
              _multiWins[winnerId] = (_multiWins[winnerId] ?? 0) + 1;
              _multiWinGameIndices
                  .putIfAbsent(winnerId, () => <int>[])
                  .add(index);
            }
            _completedGameIndexes.add(index);
          });

          if (_hasUncatchableMultiLeader) {
            await _showMultiFormatFinalResult();
            return;
          }

          if (_allMultiGamesCompleted) {
            if (_shouldStartThreePlayerTieBreaker()) {
              await _startThreePlayerTieBreaker();
            } else {
              await _showMultiFormatFinalResult();
            }
          }
        }
      } else if (widget.playingFormat == 'crazy') {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    }
  }

  Future<void> _resumeSavedSession(SavedGameSession saved) async {
    Widget? page;
    switch (saved.gameKey) {
      case '13_card_poker':
        page = ThirteenCardPokerScreen(
          gameType: '13 МОДНЫ ПОКЕР',
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentRegistrarUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'canasta':
        page = CanastaPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          playingFormat: widget.playingFormat,
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'durak':
        page = DurakPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          playingFormat: widget.playingFormat,
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'xodrox':
        page = HodrokhPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'card_texas':
        page = CardTexasPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'nvx_shaxax':
        page = NyxShaxaxPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'buur':
        page = BuurPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'game108':
        page = Game108Page(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'muushig':
        page = MuushigPage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'game501':
        page = Game501Page(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      case 'multi_format':
        page = KindsOfGamePage(
          selectedUserIds: List<String>.from(saved.selectedUserIds),
          playingFormat: 'multi',
          currentUserId: _effectiveUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: saved.id,
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Энэ тоглоомын үргэлжлүүлэх дэмжлэг хараахан нэмэгдээгүй байна.')),
        );
        return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page!),
    );
  }

  Future<List<String>> _extractWinnerUserIds(
    int index,
    Object? result,
    List<String> activeUserIds,
  ) async {
    if (result is Map) {
      final map = Map<String, dynamic>.from(result.cast<String, dynamic>());
      final multiple = (map['winnerUserIds'] as List? ?? const <dynamic>[])
          .whereType<String>()
          .map((userId) => userId.trim())
          .where((userId) => activeUserIds.contains(userId))
          .toSet()
          .toList(growable: false);
      if (multiple.isNotEmpty) return multiple;
    }
    final winner = await _extractWinnerUserId(index, result, activeUserIds);
    return winner == null ? const <String>[] : <String>[winner];
  }

  Future<String?> _extractWinnerUserId(
    int index,
    Object? result,
    List<String> activeUserIds,
  ) async {
    if (result is Map) {
      final map = Map<String, dynamic>.from(result.cast<String, dynamic>());
      for (final key in const [
        'winnerUserId',
        'winnerId',
        'winner_user_id',
        'championUserId',
      ]) {
        final v = map[key];
        if (v is String &&
            v.trim().isNotEmpty &&
            activeUserIds.contains(v.trim())) {
          return v.trim();
        }
      }
    }

    final gameKey = _indexToGameKey[index];
    if (gameKey == null) return null;

    try {
      final sessions = await StatsRepository().loadSessions();
      if (sessions.isEmpty) return null;

      final now = DateTime.now();
      final candidates = sessions
          .where((s) => s.gameKey == gameKey)
          .where((s) => now.difference(s.playedAt).inMinutes <= 10)
          .where(
              (s) => s.players.every((p) => activeUserIds.contains(p.userId)))
          .toList()
        ..sort((a, b) => b.playedAt.compareTo(a.playedAt));

      if (candidates.isEmpty) return null;
      final latest = candidates.first;
      if (latest.players.isEmpty) return null;

      final sorted = List<StatsPlayerResult>.from(latest.players)
        ..sort((a, b) => b.money.compareTo(a.money));
      final top = sorted.first;
      return activeUserIds.contains(top.userId) ? top.userId : null;
    } catch (_) {
      return null;
    }
  }

  // Shows the final multi-format result dialog and saves to statistics.
  Future<void> _showMultiFormatFinalResult(
      {List<String>? forcedWinners}) async {
    if (!mounted) return;

    // Find winner(s) — player(s) with the most wins
    int maxWins = 0;
    for (final w in _multiWins.values) {
      if (w > maxWins) maxWins = w;
    }
    final winners = forcedWinners == null
        ? widget.selectedUserIds
            .where((uid) => (_multiWins[uid] ?? 0) == maxWins)
            .toList()
        : List<String>.from(forcedWinners);

    // Build sorted leaderboard
    final sorted = List<String>.from(widget.selectedUserIds)
      ..sort((a, b) => (_multiWins[b] ?? 0).compareTo(_multiWins[a] ?? 0));
    final settlements = _calculateSettlementAmounts(winners);

    // Save to statistics
    await _saveMultiFormatStats(winners);
    await _removeSavedMultiProgressIfAny();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final championId = winners.isNotEmpty ? winners.first : null;
        final championGames =
            championId == null ? const <String>[] : _wonGameLabels(championId);
        final others = sorted
            .where((uid) => !winners.contains(uid))
            .toList(growable: false);
        final maxDialogHeight = MediaQuery.of(ctx).size.height * 0.86;

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: 760, maxHeight: maxDialogHeight),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (championId != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F0FF),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.deepPurple.shade100),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPlayerAvatar(championId, radius: 52),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _playerDisplayNames[championId] ??
                                        championId,
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$maxWins ялалт',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Хожлын мөнгө: ₮${(settlements[championId] ?? 0).abs()}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Ялсан төрлүүд',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: championGames.isEmpty
                                        ? const [
                                            Chip(
                                                label: Text(
                                                    'Ялалт бүртгэгдээгүй')),
                                          ]
                                        : championGames
                                            .map((label) =>
                                                Chip(label: Text(label)))
                                            .toList(growable: false),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 132,
                              child: Image.asset(
                                'assets/buttons/cup.png',
                                fit: BoxFit.fitHeight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: others.isEmpty
                        ? const Center(
                            child: Text(
                              'Бусад оролцогч алга.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                        : ListView.builder(
                            itemCount: others.length,
                            itemBuilder: (context, i) {
                              final uid = others[i];
                              final rank = sorted.indexOf(uid) + 1;
                              final wins = _multiWins[uid] ?? 0;
                              final money = settlements[uid] ?? 0;
                              final wonGames = _wonGameLabels(uid);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple
                                            .withValues(alpha: 0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$rank',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    _buildPlayerAvatar(uid, radius: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _playerDisplayNames[uid] ?? uid,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text('$wins ялалт'),
                                          const SizedBox(height: 6),
                                          Text(
                                            wonGames.isEmpty
                                                ? 'Ялсан төрөл: -'
                                                : 'Ялсан төрөл: ${wonGames.join(', ')}',
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '₮${money.abs()}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        color: money >= 0
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildDialogAssetButton(
                        assetPath: 'assets/buttons/report.png',
                        label: 'Тайлан',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showMultiFormatReportDialog(forcedWinners: winners);
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildDialogAssetButton(
                        assetPath: 'assets/buttons/stats.png',
                        label: 'Статистик',
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StatisticsDashboardPage(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildDialogAssetButton(
                        assetPath: 'assets/buttons/quit.png',
                        label: 'Дуусгах',
                        primary: true,
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveMultiFormatStats(List<String> winnerIds) async {
    try {
      final sessionId =
          'multi_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';
      final settlements = _calculateSettlementAmounts(winnerIds);

      final players = widget.selectedUserIds.map((uid) {
        return StatsPlayerResult(
          userId: uid,
          username: _playerUsernames[uid] ?? uid,
          displayName: _playerDisplayNames[uid] ?? uid,
          money: settlements[uid] ?? 0,
        );
      }).toList()
        ..sort((a, b) => b.money.compareTo(a.money));

      final session = StatsSession(
        sessionId: sessionId,
        gameKey: 'multi_format',
        gameLabel: 'Олон төрөлт',
        playedAt: DateTime.now(),
        players: players,
        totalRounds: _playedMultiGamesCount,
      );

      await StatsRepository().addSession(session);
    } catch (_) {}
  }
}
