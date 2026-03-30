import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:toocoob/screens/statistics_dashboard.dart';
import 'package:toocoob/utils/active_tables_repository.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'player_selection_page.dart';
import 'package:toocoob/utils/game_registrar_transfer.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';
import 'package:toocoob/screens/kinds_of_game.dart';

class DurakPage extends StatefulWidget {
  const DurakPage({
    super.key,
    this.selectedUserIds = const [],
    this.playingFormat = 'multi',
    this.currentUserId,
    this.canManageGames = false,
    this.initialSavedSessionId,
    this.multiWinsByUserId,
  });

  final List<String> selectedUserIds;
  final String playingFormat;
  final String? currentUserId;
  final bool canManageGames;
  final String? initialSavedSessionId;
  final Map<String, int>? multiWinsByUserId;

  @override
  State<DurakPage> createState() => _DurakPageState();
}

enum _DurakStage { setup, direct, group, finalStage, completed }

enum _DurakBetMode { perMember, perTeam }

class _DurakPageState extends State<DurakPage> {
  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();
  final ActiveTablesRepository _activeTablesRepo = ActiveTablesRepository();
  static const int _maxPlayers = 8;
  static const Color _tableColor = Color(0xFF263238);

  int _targetWins = 3;
  int _betAmount = 5000;
  int _boltBetAmount = 10000;
  _DurakBetMode _betMode = _DurakBetMode.perMember;
  int _roundNumber = 1;
  bool _isMiddleBooltMode = false;
  bool _isSingleBooltPhase = false;
  int _sessionInitialPlayerCount = 0;
  int _sessionAddedPlayers = 0;
  int _sessionRemovedPlayers = 0;
  int _sessionOrdinaryRounds = 0;
  int _sessionBoltRounds = 0;
  int _sessionMiddleBoltRounds = 0;
  _DurakStage _stage = _DurakStage.setup;
  List<_DurakPlayer> _players = [];
  List<List<int>> _setupBlocks = List<List<int>>.generate(8, (_) => []);
  Set<int> _activeBlockIndexes = <int>{};
  Set<int> _inactiveBlockIndexes = <int>{};
  final Map<int, int> _blockWins = <int, int>{};
  final Map<int, int> _teamRoundWins = <int, int>{};
  final Map<int, int> _teamMoneyByBlock = <int, int>{};
  int? _lastWinnerBlockIndex;
  int? _championBlockIndex;
  bool _sessionAddedToStatistics = false;
  String? _currentRegistrarUserId;
  String? _activeSavedSessionId;

  bool get _canTransferRegistrar =>
      widget.canManageGames &&
      widget.currentUserId != null &&
      _currentRegistrarUserId == widget.currentUserId;

  bool get _isSingleTypeMode => widget.playingFormat == 'single';
  bool get _isMultiTypeMode => widget.playingFormat == 'multi';
  bool get _isSingleGroupMode =>
      _isSingleTypeMode && _stage == _DurakStage.group && !_isSingleBooltPhase;
  bool get _isBoltMode =>
      _stage == _DurakStage.finalStage ||
      (_isSingleTypeMode && _stage == _DurakStage.group && _isSingleBooltPhase);
  int get _activeBetAmount => _isBoltMode ? _boltBetAmount : _betAmount;

  int _moneyColorSign(int amount) => amount < 0 ? -1 : 1;

  int _blockMoney(int blockIndex) => _teamMoneyByBlock[blockIndex] ?? 0;

  int _extractDurakCups(Map<String, dynamic> data) {
    final value = data['durakCups'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  List<int> _splitAmount(int amount, int parts) {
    if (parts <= 0) return const <int>[];
    final sign = _moneyColorSign(amount);
    var absAmount = amount.abs();
    final base = absAmount ~/ parts;
    var residue = absAmount % parts;
    return List<int>.generate(parts, (_) {
      final extra = residue > 0 ? 1 : 0;
      if (residue > 0) residue -= 1;
      return (base + extra) * sign;
    });
  }

  Map<int, int> _remapTeamMoney(
    List<List<int>> oldBlocks,
    List<List<int>> newBlocks,
  ) {
    final next = <int, int>{};
    for (final entry in _teamMoneyByBlock.entries) {
      final oldIndex = entry.key;
      final amount = entry.value;
      if (amount == 0 || oldIndex < 0 || oldIndex >= oldBlocks.length) continue;
      final oldMembers = oldBlocks[oldIndex].toSet();
      if (oldMembers.isEmpty) continue;

      final targets = <int>[];
      for (int i = 0; i < newBlocks.length; i++) {
        if (newBlocks[i].any(oldMembers.contains)) {
          targets.add(i);
        }
      }
      if (targets.isEmpty) continue;

      final shares = _splitAmount(amount, targets.length);
      for (int i = 0; i < targets.length; i++) {
        next[targets[i]] = (next[targets[i]] ?? 0) + shares[i];
      }
    }
    return next;
  }

  @override
  void initState() {
    super.initState();
    _currentRegistrarUserId = widget.currentUserId;
    _initialize();
  }

  Future<void> _transferRegistrarRole() async {
    final registrarId = _currentRegistrarUserId;
    if (!_canTransferRegistrar || registrarId == null || registrarId.isEmpty) {
      return;
    }

    final playerUserIds = _players
        .map((player) => player.userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final nextRegistrarUserId = await GameRegistrarTransfer.transfer(
      context,
      currentRegistrarUserId: registrarId,
      playerUserIds: playerUserIds,
    );

    if (!mounted || nextRegistrarUserId == null) return;
    setState(() {
      _currentRegistrarUserId = nextRegistrarUserId;
    });
  }

  Future<void> _askRegistrarDecisionAtGameEndIfNeeded() async {
    final resolvedRegistrarUserId =
        await GameRegistrarTransfer.resolveAtGameEnd(
      context,
      originalRegistrarUserId: widget.currentUserId,
      currentRegistrarUserId: _currentRegistrarUserId,
      playerUserIds: _players
          .map((player) => player.userId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      displayNameForUserId: (userId) {
        for (final player in _players) {
          if (player.userId == userId) return player.displayName;
        }
        return 'Тоглогч';
      },
      usernameForUserId: (userId) {
        for (final player in _players) {
          if (player.userId == userId) return player.username;
        }
        return '';
      },
    );

    if (!mounted || resolvedRegistrarUserId == null) return;
    setState(() {
      _currentRegistrarUserId = resolvedRegistrarUserId;
    });
  }

  Future<void> _initialize() async {
    final restored = await _tryRestoreSavedSession();
    if (restored) {
      if (widget.selectedUserIds.isNotEmpty) {
        await _loadSelectedUserProfiles();
      }
      return;
    }

    _players = _buildInitialPlayers(widget.selectedUserIds);
    _sessionInitialPlayerCount = _players.length;
    if (widget.selectedUserIds.isNotEmpty) {
      await _loadSelectedUserProfiles();
    }
    if (!mounted) return;
    _resetToSetup();
  }

  Future<bool> _tryRestoreSavedSession() async {
    final id = widget.initialSavedSessionId;
    if (id == null || id.isEmpty) return false;
    final saved = await _savedSessionsRepo.findById(id);
    if (saved == null || !mounted) return false;

    final p = saved.payload;
    List<_DurakPlayer> playersFromPayload() {
      final raw = (p['players'] as List? ?? const <dynamic>[]);
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(
            (e) => _DurakPlayer(
              userId: (e['userId'] ?? '').toString().isEmpty
                  ? null
                  : (e['userId'] ?? '').toString(),
              displayName: (e['displayName'] ?? '').toString(),
              username: (e['username'] ?? '').toString(),
              photoUrl: (e['photoUrl'] ?? '').toString().isEmpty
                  ? null
                  : (e['photoUrl'] ?? '').toString(),
              money: (e['money'] as num? ?? 0).toInt(),
              durakCups: (e['durakCups'] as num? ?? 0).toInt(),
            ),
          )
          .toList();
    }

    List<List<int>> blocksFromPayload() {
      final raw = (p['setupBlocks'] as List? ?? const <dynamic>[]);
      return raw
          .map((e) => (e as List).map((i) => (i as num).toInt()).toList())
          .toList();
    }

    Map<int, int> intMap(dynamic raw) {
      final map =
          Map<String, dynamic>.from(raw as Map? ?? const <String, dynamic>{});
      return map
          .map((k, v) => MapEntry(int.tryParse(k) ?? 0, (v as num).toInt()));
    }

    setState(() {
      _activeSavedSessionId = saved.id;
      _targetWins = (p['targetWins'] as num? ?? _targetWins).toInt();
      _betAmount = (p['betAmount'] as num? ?? _betAmount).toInt();
      _boltBetAmount = (p['boltBetAmount'] as num? ?? _boltBetAmount).toInt();
      _betMode = _DurakBetMode
          .values[((p['betMode'] as num? ?? 0).toInt().clamp(0, 1))];
      _roundNumber = (p['roundNumber'] as num? ?? _roundNumber).toInt();
      _isMiddleBooltMode = p['isMiddleBooltMode'] == true;
      _isSingleBooltPhase = p['isSingleBooltPhase'] == true;
      _stage = _DurakStage.values[((p['stage'] as num? ?? 0)
          .toInt()
          .clamp(0, _DurakStage.values.length - 1))];
      _players = playersFromPayload();
      _setupBlocks = blocksFromPayload();
      _activeBlockIndexes =
          ((p['activeBlockIndexes'] as List? ?? const <dynamic>[])
              .map((e) => (e as num).toInt())).toSet();
      _inactiveBlockIndexes =
          ((p['inactiveBlockIndexes'] as List? ?? const <dynamic>[])
              .map((e) => (e as num).toInt())).toSet();
      _blockWins
        ..clear()
        ..addAll(intMap(p['blockWins']));
      _teamRoundWins
        ..clear()
        ..addAll(intMap(p['teamRoundWins']));
      _teamMoneyByBlock
        ..clear()
        ..addAll(intMap(p['teamMoneyByBlock']));
      _lastWinnerBlockIndex = p['lastWinnerBlockIndex'] as int?;
      _championBlockIndex = p['championBlockIndex'] as int?;
      _sessionInitialPlayerCount =
          (p['sessionInitialPlayerCount'] as num? ?? _players.length).toInt();
      _sessionAddedPlayers = (p['sessionAddedPlayers'] as num? ?? 0).toInt();
      _sessionRemovedPlayers =
          (p['sessionRemovedPlayers'] as num? ?? 0).toInt();
      _sessionOrdinaryRounds =
          (p['sessionOrdinaryRounds'] as num? ?? 0).toInt();
      _sessionBoltRounds = (p['sessionBoltRounds'] as num? ?? 0).toInt();
      _sessionMiddleBoltRounds =
          (p['sessionMiddleBoltRounds'] as num? ?? 0).toInt();
    });

    return true;
  }

  Future<void> _saveProgress() async {
    final payload = {
      'targetWins': _targetWins,
      'betAmount': _betAmount,
      'boltBetAmount': _boltBetAmount,
      'betMode': _betMode.index,
      'roundNumber': _roundNumber,
      'isMiddleBooltMode': _isMiddleBooltMode,
      'isSingleBooltPhase': _isSingleBooltPhase,
      'stage': _stage.index,
      'players': _players
          .map((p) => {
                'userId': p.userId,
                'displayName': p.displayName,
                'username': p.username,
                'photoUrl': p.photoUrl,
                'money': p.money,
                'durakCups': p.durakCups,
              })
          .toList(),
      'setupBlocks': _setupBlocks,
      'activeBlockIndexes': _activeBlockIndexes.toList(),
      'inactiveBlockIndexes': _inactiveBlockIndexes.toList(),
      'blockWins': _blockWins.map((k, v) => MapEntry('$k', v)),
      'teamRoundWins': _teamRoundWins.map((k, v) => MapEntry('$k', v)),
      'teamMoneyByBlock': _teamMoneyByBlock.map((k, v) => MapEntry('$k', v)),
      'lastWinnerBlockIndex': _lastWinnerBlockIndex,
      'championBlockIndex': _championBlockIndex,
      'sessionInitialPlayerCount': _sessionInitialPlayerCount,
      'sessionAddedPlayers': _sessionAddedPlayers,
      'sessionRemovedPlayers': _sessionRemovedPlayers,
      'sessionOrdinaryRounds': _sessionOrdinaryRounds,
      'sessionBoltRounds': _sessionBoltRounds,
      'sessionMiddleBoltRounds': _sessionMiddleBoltRounds,
    };

    final id = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: 'durak',
      gameLabel: 'Дурак',
      selectedUserIds: List<String>.from(widget.selectedUserIds),
      payload: payload,
    );
    _activeSavedSessionId = id;
  }

  Future<void> _removeSavedProgressIfAny() async {
    final id = _activeSavedSessionId;
    if (id == null || id.isEmpty) return;
    await _savedSessionsRepo.removeById(id);
    _activeSavedSessionId = null;
  }

  List<_DurakPlayer> _buildInitialPlayers(List<String> selectedUserIds) {
    if (selectedUserIds.isEmpty) {
      return List<_DurakPlayer>.generate(
        4,
        (index) => _DurakPlayer(
          displayName: 'Тоглогч ${index + 1}',
          username: 'u${index + 1}',
        ),
      );
    }

    final count = selectedUserIds.length.clamp(0, _maxPlayers);
    return List<_DurakPlayer>.generate(
      count,
      (index) => _DurakPlayer(
        userId: selectedUserIds[index],
        displayName: 'Тоглогч ${index + 1}',
        username: 'u${index + 1}',
      ),
    );
  }

  Future<void> _loadSelectedUserProfiles() async {
    final updated = List<_DurakPlayer>.from(_players);

    for (int i = 0; i < updated.length; i++) {
      final userId = updated[i].userId;
      if (userId == null || userId.isEmpty) continue;

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        final data = snapshot.data();
        if (data == null) continue;

        final username = (data['username'] as String?)?.trim();
        final displayName = (data['displayName'] as String?)?.trim();
        final photoUrl = (data['photoUrl'] as String?)?.trim();
        final durakCups = _isMultiTypeMode ? _extractDurakCups(data) : 0;

        updated[i] = updated[i].copyWith(
          username: username != null && username.isNotEmpty
              ? username
              : updated[i].username,
          displayName: displayName != null && displayName.isNotEmpty
              ? displayName
              : updated[i].displayName,
          photoUrl: photoUrl != null && photoUrl.isNotEmpty
              ? photoUrl
              : updated[i].photoUrl,
          durakCups: durakCups,
        );
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _players = updated;
    });
  }

  void _resetToSetup() {
    final blocks = List<List<int>>.generate(8, (_) => []);
    for (int i = 0; i < _players.length; i++) {
      final targetBlock = i < 3 ? i : (i - 3) + 3;
      blocks[targetBlock].add(i);
    }

    setState(() {
      _stage = _DurakStage.setup;
      _roundNumber = 1;
      _isMiddleBooltMode = false;
      _isSingleBooltPhase = false;
      _championBlockIndex = null;
      _setupBlocks = blocks;
      _activeBlockIndexes = <int>{};
      _inactiveBlockIndexes = <int>{};
      _blockWins.clear();
      _teamRoundWins.clear();
      _teamMoneyByBlock.clear();
      _lastWinnerBlockIndex = null;
    });
  }

  void _setTargetWins(int value) {
    if (value < 1 || value > 8) return;
    setState(() {
      _targetWins = value;
      _blockWins.updateAll(
        (_, wins) => wins > _targetWins ? _targetWins : wins,
      );
    });
  }

  String _playerKey(_DurakPlayer player) {
    if (player.userId != null && player.userId!.isNotEmpty) {
      return 'id:${player.userId}';
    }
    return 'u:${player.username}';
  }

  void _mergeSetupBlocks(int sourceIndex, int targetIndex) {
    if (sourceIndex == targetIndex) return;
    if (_setupBlocks[sourceIndex].isEmpty ||
        _setupBlocks[targetIndex].isEmpty) {
      return;
    }

    setState(() {
      _setupBlocks[targetIndex].addAll(_setupBlocks[sourceIndex]);
      _setupBlocks[sourceIndex] = [];
    });
  }

  void _startFromSetupBlocks() {
    final nonEmptyBlockIndexes = <int>[];
    for (int i = 0; i < _setupBlocks.length; i++) {
      if (_setupBlocks[i].isNotEmpty) {
        nonEmptyBlockIndexes.add(i);
      }
    }

    if (nonEmptyBlockIndexes.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дор хаяж 2 блок идэвхтэй байх ёстой')),
      );
      return;
    }

    final activeSourceIndexes = nonEmptyBlockIndexes.take(3).toList();
    final passiveSourceIndexes = nonEmptyBlockIndexes.skip(3).toList();
    final nextBlocks = List<List<int>>.generate(8, (_) => []);

    if (activeSourceIndexes.length == 2) {
      nextBlocks[0] = List<int>.from(_setupBlocks[activeSourceIndexes[0]]);
      nextBlocks[2] = List<int>.from(_setupBlocks[activeSourceIndexes[1]]);
    } else {
      for (int i = 0; i < activeSourceIndexes.length; i++) {
        nextBlocks[i] = List<int>.from(_setupBlocks[activeSourceIndexes[i]]);
      }
    }

    int passiveTarget = 3;
    for (final sourceIndex in passiveSourceIndexes) {
      if (passiveTarget >= nextBlocks.length) break;
      nextBlocks[passiveTarget] = List<int>.from(_setupBlocks[sourceIndex]);
      passiveTarget += 1;
    }

    final hasTeamBlock =
        activeSourceIndexes.any((source) => _setupBlocks[source].length > 1);
    final nextStage = activeSourceIndexes.length >= 3 || hasTeamBlock
        ? _DurakStage.group
        : _DurakStage.direct;

    final nextActive = <int>{};
    if (nextStage == _DurakStage.group) {
      // When two sources become group-stage candidates, they are laid out at
      // block 0 and block 2. Keep both interactive.
      if (activeSourceIndexes.length == 2) {
        if (nextBlocks[0].isNotEmpty) nextActive.add(0);
        if (nextBlocks[2].isNotEmpty) nextActive.add(2);
      } else {
        for (int i = 0; i < activeSourceIndexes.length && i < 3; i++) {
          if (nextBlocks[i].isNotEmpty) nextActive.add(i);
        }
      }
    } else {
      if (nextBlocks[0].isNotEmpty) nextActive.add(0);
      if (nextBlocks[2].isNotEmpty) nextActive.add(2);
    }

    setState(() {
      _championBlockIndex = null;
      _stage = nextStage;
      final previousBlocks = _setupBlocks;
      _setupBlocks = nextBlocks;
      _activeBlockIndexes = nextActive;
      _inactiveBlockIndexes = <int>{
        for (int i = 0; i < 8; i++)
          if (!nextActive.contains(i) && nextBlocks[i].isNotEmpty) i,
      };
      _blockWins
        ..clear()
        ..addEntries(nextActive.map((index) => MapEntry(index, 0)));
      _teamRoundWins
        ..clear()
        ..addEntries(nextActive.map((index) => MapEntry(index, 0)));
      _roundNumber = 1;
      _isMiddleBooltMode = false;
      _isSingleBooltPhase = false;
      _lastWinnerBlockIndex = null;
      _teamMoneyByBlock
        ..clear()
        ..addAll(_remapTeamMoney(previousBlocks, nextBlocks));
    });
  }

  bool _isBlockInteractive(int blockIndex) {
    if (_stage == _DurakStage.setup || _stage == _DurakStage.completed) {
      return false;
    }
    return _activeBlockIndexes.contains(blockIndex);
  }

  Future<void> _changeBlockWins(int blockIndex, int delta) async {
    if (!_isBlockInteractive(blockIndex)) return;

    final currentWins = _blockWins[blockIndex] ?? 0;
    final nextWins = (currentWins + delta).clamp(0, _targetWins);
    setState(() {
      _blockWins[blockIndex] = nextWins;
    });

    if (nextWins < _targetWins) return;
    await _resolveBlockWinner(blockIndex);
  }

  Future<void> _resolveBlockWinner(int winnerBlockIndex) async {
    _lastWinnerBlockIndex = winnerBlockIndex;
    if (_stage == _DurakStage.group) {
      if (_isSingleTypeMode) {
        if (_isSingleBooltPhase) {
          _applyMoneyForWinnerBlock(winnerBlockIndex);
          if (_isMiddleBooltMode) {
            _sessionMiddleBoltRounds += 1;
          } else {
            _sessionBoltRounds += 1;
          }
          await _declareChampionFromBlock(winnerBlockIndex);
          return;
        }
        await _handleSingleTypeTeamRoundWinner(winnerBlockIndex);
        return;
      }
      _applyMoneyForWinnerBlock(winnerBlockIndex);
      _sessionOrdinaryRounds += 1;
      await _startFinalFromWinningBlock(winnerBlockIndex);
      return;
    }
    if (_stage == _DurakStage.finalStage || _stage == _DurakStage.direct) {
      _applyMoneyForWinnerBlock(winnerBlockIndex);
      if (_stage == _DurakStage.finalStage) {
        if (_isMiddleBooltMode) {
          _sessionMiddleBoltRounds += 1;
        } else {
          _sessionBoltRounds += 1;
        }

        if (!_isSingleTypeMode) {
          final winnerMembers = _setupBlocks[winnerBlockIndex];
          if (winnerMembers.length > 1) {
            await _startFinalFromWinningBlock(winnerBlockIndex);
            return;
          }
        }
      } else {
        _sessionOrdinaryRounds += 1;
      }
    }
    await _declareChampionFromBlock(winnerBlockIndex);
  }

  Future<void> _handleSingleTypeTeamRoundWinner(int winnerBlockIndex) async {
    if (!_activeBlockIndexes.contains(winnerBlockIndex)) return;

    _applyMoneyForWinnerBlock(winnerBlockIndex);
    _sessionOrdinaryRounds += 1;

    setState(() {
      _roundNumber += 1;
    });

    _startSingleModeTeamBoolt();
  }

  void _startSingleModeTeamBoolt() {
    setState(() {
      _isMiddleBooltMode = false;
      _isSingleBooltPhase = true;
      _blockWins
        ..clear()
        ..addEntries(_activeBlockIndexes.map((index) => MapEntry(index, 0)));
      _championBlockIndex = null;
      _lastWinnerBlockIndex = null;
    });
  }

  Future<void> _declareChampionFromBlock(int blockIndex) async {
    if (blockIndex < 0 || blockIndex >= _setupBlocks.length) return;
    final members = _setupBlocks[blockIndex];
    if (members.isEmpty) return;

    final winnerNames = members
        .map((index) => _players[index].displayName)
        .toList(growable: false)
        .join(', ');

    setState(() {
      _championBlockIndex = blockIndex;
      _stage = _DurakStage.completed;
    });

    await _removeSavedProgressIfAny();

    if (!_isSingleTypeMode) {
      final winnerUserId = members
          .map((index) => _players[index].userId)
          .whereType<String>()
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      if (!mounted) return;
      Navigator.of(context).pop({
        'completedGame': 'durak',
        if (winnerUserId.isNotEmpty) 'winnerUserId': winnerUserId,
      });
      return;
    }

    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ялагч тодорлоо'),
          content: Text('$winnerNames яллаа.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'replay'),
              child: const Text('Дахин тойрох'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'close'),
              child: const Text('Хаах'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'finish'),
              child: const Text('Дуусгах'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (action == 'replay') {
      setState(_resetForReplayKeepingMoney);
      return;
    }
    if (action == 'finish') {
      await _showExitReportAndFinish();
    }
  }

  Future<void> _startFinalFromWinningBlock(int winnerBlockIndex) async {
    if (winnerBlockIndex < 0 || winnerBlockIndex >= _setupBlocks.length) {
      return;
    }

    final winningMembers = List<int>.from(_setupBlocks[winnerBlockIndex]);
    if (winningMembers.isEmpty) return;
    if (winningMembers.length == 1) {
      await _declareChampionFromBlock(winnerBlockIndex);
      return;
    }

    final loserMembers = <int>[];
    for (final blockIndex in _activeBlockIndexes) {
      if (blockIndex == winnerBlockIndex) continue;
      loserMembers.addAll(_setupBlocks[blockIndex]);
    }

    final previouslyInactiveMembers = <int>[];
    for (final blockIndex in _inactiveBlockIndexes) {
      previouslyInactiveMembers.addAll(_setupBlocks[blockIndex]);
    }

    final carryMembers = <int>[
      ...loserMembers,
      ...previouslyInactiveMembers,
    ];

    final nextBlocks = List<List<int>>.generate(8, (_) => []);
    final nextActive = <int>{};

    if (!_isSingleTypeMode) {
      if (winningMembers.length == 2) {
        nextBlocks[0] = [winningMembers[0]];
        nextBlocks[2] = [winningMembers[1]];
        nextActive.addAll(<int>{0, 2});
      } else if (winningMembers.length == 3) {
        nextBlocks[0] = [winningMembers[0]];
        nextBlocks[1] = [winningMembers[1]];
        nextBlocks[2] = [winningMembers[2]];
        nextActive.addAll(<int>{0, 1, 2});
      } else if (winningMembers.length == 4) {
        nextBlocks[0] = [winningMembers[0], winningMembers[1]];
        nextBlocks[2] = [winningMembers[2], winningMembers[3]];
        nextActive.addAll(<int>{0, 2});
      } else {
        final split = (winningMembers.length + 1) ~/ 2;
        nextBlocks[0] = List<int>.from(winningMembers.take(split));
        nextBlocks[2] = List<int>.from(winningMembers.skip(split));
        if (nextBlocks[0].isNotEmpty) nextActive.add(0);
        if (nextBlocks[2].isNotEmpty) nextActive.add(2);
      }
    } else {
      nextBlocks[0] = [winningMembers[0]];
      nextBlocks[2] = [winningMembers[1]];
      nextActive.addAll(<int>{0, 2});
    }

    int target = 3;
    for (final member in carryMembers) {
      if (target >= nextBlocks.length) break;
      nextBlocks[target] = [member];
      target += 1;
    }

    final previousBlocks = _setupBlocks;

    setState(() {
      _stage = _DurakStage.finalStage;
      _roundNumber += 1;
      _setupBlocks = nextBlocks;
      _activeBlockIndexes = nextActive;
      _inactiveBlockIndexes = <int>{
        for (int i = 0; i < 8; i++)
          if (!nextActive.contains(i) && nextBlocks[i].isNotEmpty) i,
      };
      _blockWins
        ..clear()
        ..addEntries(nextActive.map((index) => MapEntry(index, 0)));
      _teamRoundWins
        ..clear()
        ..addEntries(nextActive.map((index) => MapEntry(index, 0)));
      _isSingleBooltPhase = false;
      _championBlockIndex = null;
      _lastWinnerBlockIndex = nextActive.contains(0)
          ? 0
          : (nextActive.isEmpty ? null : nextActive.first);
      _teamMoneyByBlock
        ..clear()
        ..addAll(_remapTeamMoney(previousBlocks, nextBlocks));
    });
  }

  void _applyMoneyForWinnerBlock(int winnerBlockIndex) {
    // In multi-format marathon flow, settlement is handled after all game types.
    if (_isMultiTypeMode) return;

    final participants = _activeBlockIndexes.toList(growable: false);
    if (participants.length < 2) return;

    final winnerMembers = _setupBlocks[winnerBlockIndex];
    if (winnerMembers.isEmpty) return;

    final loserTeamBlocks = <int>[];
    final loserIndexes = <int>[];
    for (final blockIndex in participants) {
      if (blockIndex == winnerBlockIndex) continue;
      loserTeamBlocks.add(blockIndex);
      loserIndexes.addAll(_setupBlocks[blockIndex]);
    }
    if (loserTeamBlocks.isEmpty) return;

    if (_betMode == _DurakBetMode.perTeam) {
      var pot = 0;
      setState(() {
        for (final loserBlock in loserTeamBlocks) {
          _teamMoneyByBlock[loserBlock] =
              _blockMoney(loserBlock) - _activeBetAmount;
          pot += _activeBetAmount;
        }
        _teamMoneyByBlock[winnerBlockIndex] =
            _blockMoney(winnerBlockIndex) + pot;
      });
      return;
    }

    if (loserIndexes.isEmpty) return;

    final nextPlayers = List<_DurakPlayer>.from(_players);
    var pot = 0;
    if (_betMode == _DurakBetMode.perMember) {
      for (final loserIndex in loserIndexes) {
        final loser = nextPlayers[loserIndex];
        nextPlayers[loserIndex] =
            loser.copyWith(money: loser.money - _activeBetAmount);
        pot += _activeBetAmount;
      }
    }

    final gainPerWinner =
        winnerMembers.isEmpty ? 0 : (pot ~/ winnerMembers.length);
    int residue = winnerMembers.isEmpty ? 0 : (pot % winnerMembers.length);
    for (final winnerIndex in winnerMembers) {
      final winner = nextPlayers[winnerIndex];
      final extra = residue > 0 ? 1 : 0;
      nextPlayers[winnerIndex] =
          winner.copyWith(money: winner.money + gainPerWinner + extra);
      if (residue > 0) residue -= 1;
    }

    setState(() {
      _players = nextPlayers;
    });
  }

  Future<void> _showDurakSettingsDialog() async {
    final normalController = TextEditingController(text: _betAmount.toString());
    final boltController =
        TextEditingController(text: _boltBetAmount.toString());
    var tempBetMode = _betMode;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final unit = tempBetMode == _DurakBetMode.perMember
                ? 'нэг гишүүн'
                : 'нэг баг';
            return AlertDialog(
              title: const Text('Дурак тохиргоо'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Мөнгө бодох хэлбэр',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    RadioListTile<_DurakBetMode>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _DurakBetMode.perMember,
                      groupValue: tempBetMode,
                      title: const Text('Гишүүн тус бүрээр'),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => tempBetMode = value);
                      },
                    ),
                    RadioListTile<_DurakBetMode>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _DurakBetMode.perTeam,
                      groupValue: tempBetMode,
                      title: const Text('Багийн дүнгээр'),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => tempBetMode = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: normalController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Энгийн мөнгө ($unit)',
                        helperText: 'Жишээ: 5000',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: boltController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Боолтын мөнгө ($unit)',
                        helperText: 'Жишээ: 10000',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final normalParsed =
                        int.tryParse(normalController.text.trim());
                    final boltParsed = int.tryParse(boltController.text.trim());
                    if (normalParsed == null || normalParsed <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Энгийн мөнгөний дүн зөв оруулна уу')),
                      );
                      return;
                    }
                    if (boltParsed == null || boltParsed <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Боолтын мөнгөний дүн зөв оруулна уу')),
                      );
                      return;
                    }
                    setState(() {
                      _betAmount = normalParsed;
                      _boltBetAmount = boltParsed;
                      _betMode = tempBetMode;
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
    normalController.dispose();
    boltController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSetup = _stage == _DurakStage.setup;

    return Scaffold(
      backgroundColor: _tableColor,
      appBar: UnifiedGameAppBar(
        title: Text(
            !_isMultiTypeMode ? 'Дурак  |  Тоглолтын №$_roundNumber' : 'Дурак'),
        currentUserId: widget.currentUserId,
        canManageGames: widget.canManageGames,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          final selectedUserIds = _players
              .map((player) => player.userId)
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList(growable: false);
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => KindsOfGamePage(
                selectedUserIds: selectedUserIds,
                playingFormat: widget.playingFormat,
              ),
            ),
          );
        },
        onRemovePlayer: _showRemovePlayerDialog,
        onAddPlayer: _addPlayerFromAppBar,
        onSave: _saveProgress,
        onStatistics: _openStatisticsDashboard,
        onReport: _showExitReportAndFinish,
        onPrint: _printSessionReport,
        onSettings: _showDurakSettingsDialog,
        onExit: _showExitReportAndFinish,
        extraActions: [
          IconButton(
            tooltip: _canTransferRegistrar
                ? 'Тоглолт бүртгэх эрх шилжүүлэх'
                : 'Бүртгэл хөтлөгчийн эрх шилжүүлэх боломжгүй',
            onPressed: _canTransferRegistrar ? _transferRegistrarRole : null,
            icon: Opacity(
              opacity: _canTransferRegistrar ? 1 : 0.45,
              child: Image.asset(
                'assets/buttons/keyboard.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 7,
                        child: Row(
                          children: [
                            const Text(
                              'Хожлын босго:',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  const starCount = 8;
                                  final starSize =
                                      (constraints.maxWidth / (starCount + 0.8))
                                          .clamp(20.0, 40.0);

                                  return SizedBox(
                                    width: double.infinity,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: List<Widget>.generate(starCount,
                                          (index) {
                                        final value = index + 1;
                                        final active = value <= _targetWins;
                                        return InkWell(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                          onTap: () => _setTargetWins(value),
                                          child: Icon(
                                            Icons.star_rounded,
                                            size: starSize,
                                            color: active
                                                ? Colors.amber
                                                : Colors.white24,
                                          ),
                                        );
                                      }),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: _buildMatchupIndicator(),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: isSetup ? _startFromSetupBlocks : null,
                            child: const Text('Эхлүүлэх'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildSetupBoard(),
            ),
          ],
        ),
      ),
    );
  }

  void _resetForReplayKeepingMoney() {
    final blocks = List<List<int>>.generate(8, (_) => []);
    for (int i = 0; i < _players.length; i++) {
      final targetBlock = i < 3 ? i : (i - 3) + 3;
      blocks[targetBlock].add(i);
    }

    final remappedMoney = _remapTeamMoney(_setupBlocks, blocks);

    _stage = _DurakStage.setup;
    _roundNumber = 1;
    _isMiddleBooltMode = false;
    _isSingleBooltPhase = false;
    _championBlockIndex = null;
    _setupBlocks = blocks;
    _activeBlockIndexes = <int>{};
    _inactiveBlockIndexes = <int>{};
    _blockWins.clear();
    _teamRoundWins.clear();
    _lastWinnerBlockIndex = null;
    _teamMoneyByBlock
      ..clear()
      ..addAll(remappedMoney);
  }

  String _buildSessionReportText() {
    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;
    final rows = <String>[];
    if (_betMode == _DurakBetMode.perTeam) {
      for (int i = 0; i < _setupBlocks.length; i++) {
        final members = _setupBlocks[i];
        if (members.isEmpty) continue;
        rows.add('Блок ${i + 1}: ₮${_blockMoney(i)}');
      }
    } else {
      for (int i = 0; i < _players.length; i++) {
        final player = _players[i];
        rows.add(
            '${i + 1}. ${player.displayName} (@${player.username}): ₮${player.money}');
      }
    }

    return [
      'ДУРАК - ТОГЛОЛТЫН ТАЙЛАН',
      'Эхний тоглогчийн тоо: $_sessionInitialPlayerCount',
      'Одоогийн тоглогчийн тоо: ${_players.length}',
      'Нэмсэн тоглогч: $_sessionAddedPlayers',
      'Хассан тоглогч: $_sessionRemovedPlayers',
      'Нийт раунд: $totalRounds',
      'Энгийн тоглолт: $_sessionOrdinaryRounds',
      'Боолт тоглолт: $_sessionBoltRounds',
      'Дундаа боосон: $_sessionMiddleBoltRounds',
      '',
      _betMode == _DurakBetMode.perTeam
          ? 'Блок тус бүрийн мөнгөн дүн:'
          : 'Тоглогч тус бүрийн мөнгөн дүн:',
      ...rows,
    ].join('\n');
  }

  Future<void> _addCurrentSessionToStatisticsIfNeeded() async {
    if (_sessionAddedToStatistics) return;

    final repository = StatsRepository();
    final players = List<StatsPlayerResult>.generate(_players.length, (index) {
      final player = _players[index];
      return StatsPlayerResult(
        userId: player.userId ?? player.username,
        username: player.username,
        displayName: player.displayName,
        money: player.money,
      );
    });

    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;

    final session = StatsSession(
      sessionId:
          'durak-${DateTime.now().microsecondsSinceEpoch}-${_players.length}',
      gameKey: 'durak',
      gameLabel: 'ДУРАК',
      playedAt: DateTime.now(),
      players: players,
      totalRounds: totalRounds,
    );

    await repository.addSession(session);
    _sessionAddedToStatistics = true;
  }

  Future<void> _openStatisticsDashboard() async {
    await _addCurrentSessionToStatisticsIfNeeded();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const StatisticsDashboardPage()),
    );
  }

  Future<Uint8List> _buildSessionReportPdfBytes() async {
    final doc = pw.Document();
    final baseFontData =
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldFontData =
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final baseFont = pw.Font.ttf(baseFontData);
    final boldFont = pw.Font.ttf(boldFontData);

    final pdfTheme = pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
    );

    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;

    final headers = _betMode == _DurakBetMode.perTeam
        ? const ['#', 'Блок', 'Мөнгө (₮)']
        : const ['#', 'Display name', 'Username', 'Мөнгө (₮)'];

    final tableData = _betMode == _DurakBetMode.perTeam
        ? List<List<String>>.generate(_setupBlocks.length, (index) {
            final members = _setupBlocks[index];
            if (members.isEmpty) return <String>[];
            return [
              '${index + 1}',
              'Блок ${index + 1}',
              '${_blockMoney(index)}',
            ];
          }).where((row) => row.isNotEmpty).toList()
        : List<List<String>>.generate(_players.length, (index) {
            final player = _players[index];
            return [
              '${index + 1}',
              player.displayName,
              '@${player.username}',
              '${player.money}',
            ];
          });

    doc.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        build: (context) => [
          pw.Text(
            'ДУРАК - ТОГЛОЛТЫН ТАЙЛАН',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Эхний тоглогчийн тоо: $_sessionInitialPlayerCount'),
          pw.Text('Одоогийн тоглогчийн тоо: ${_players.length}'),
          pw.Text('Нэмсэн тоглогч: $_sessionAddedPlayers'),
          pw.Text('Хассан тоглогч: $_sessionRemovedPlayers'),
          pw.Text('Нийт раунд: $totalRounds'),
          pw.Text('Энгийн тоглолт: $_sessionOrdinaryRounds'),
          pw.Text('Боолт тоглолт: $_sessionBoltRounds'),
          pw.Text('Дундаа боосон: $_sessionMiddleBoltRounds'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: tableData,
            headerStyle: pw.TextStyle(font: boldFont),
            cellStyle: pw.TextStyle(font: baseFont),
          ),
        ],
      ),
    );

    return await doc.save();
  }

  Future<void> _printSessionReport() async {
    try {
      final bytes = await _buildSessionReportPdfBytes();
      await Printing.layoutPdf(
        name: 'toocoob_report_durak',
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Хэвлэх цонх нээгдсэнгүй.')),
      );
    }
  }

  Future<void> _shareSessionReport() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _buildSessionReportText(),
          subject: 'Дурак - тоглолтын тайлан',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Илгээх үйлдэл амжилтгүй.')),
      );
    }
  }

  Future<void> _showExitReportAndFinish() async {
    final shouldFinish = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтын тайлан'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(_buildSessionReportText()),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop(false);
                await _shareSessionReport();
              },
              icon: Image.asset(
                'assets/buttons/send.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              label: const Text('Илгээх'),
            ),
            TextButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop(false);
                await _printSessionReport();
              },
              icon: Image.asset(
                'assets/buttons/print.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              label: const Text('Хэвлэх'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop(false);
                await _openStatisticsDashboard();
              },
              child: const Text('Статистик'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Буцах'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Дуусгах'),
            ),
          ],
        );
      },
    );

    if (shouldFinish == true && mounted) {
      await _askRegistrarDecisionAtGameEndIfNeeded();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PlayerSelectionPage()),
        (route) => false,
      );
    }
  }

  Future<void> _addPlayerFromAppBar() async {
    if (_stage != _DurakStage.setup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тоглолтын явцад тоглогч нэмэхгүй')),
      );
      return;
    }
    if (_players.length >= _maxPlayers) {
      return;
    }

    final excludedUserIds = _players
        .where((player) => player.userId != null && player.userId!.isNotEmpty)
        .map((player) => player.userId!)
        .toList(growable: false);

    final selectedToAdd = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: excludedUserIds,
        ),
      ),
    );

    if (!mounted || selectedToAdd == null || selectedToAdd.isEmpty) return;

    final existingKeys = _players.map(_playerKey).toSet();
    final docs = await Future.wait(
      selectedToAdd.map(
        (userId) =>
            FirebaseFirestore.instance.collection('users').doc(userId).get(),
      ),
    );

    final toAppend = <_DurakPlayer>[];
    for (final doc in docs) {
      final data = doc.data();
      final userId = doc.id;
      final key = 'id:$userId';
      if (existingKeys.contains(key)) continue;
      if (_players.length + toAppend.length >= _maxPlayers) break;

      final username = ((data?['username'] ?? '').toString().trim());
      final displayName = ((data?['displayName'] ?? '').toString().trim());
      final photoUrl = ((data?['photoUrl'] ?? '').toString().trim());
      final durakCups =
          (!_isMultiTypeMode || data == null) ? 0 : _extractDurakCups(data);

      final fallbackIndex = _players.length + toAppend.length + 1;
      toAppend.add(
        _DurakPlayer(
          userId: userId,
          username: username.isNotEmpty ? username : 'u$fallbackIndex',
          displayName:
              displayName.isNotEmpty ? displayName : 'Тоглогч $fallbackIndex',
          photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
          durakCups: durakCups,
        ),
      );
      existingKeys.add(key);
    }

    if (toAppend.isEmpty) return;

    final nextBlocks = _setupBlocks
        .map((block) => List<int>.from(block))
        .toList(growable: false);
    int nextIndexBase = _players.length;
    for (final _ in toAppend) {
      int targetBlock = -1;
      for (int i = 3; i < nextBlocks.length; i++) {
        if (nextBlocks[i].isEmpty) {
          targetBlock = i;
          break;
        }
      }
      targetBlock = targetBlock == -1
          ? nextBlocks.indexWhere((block) => block.isEmpty)
          : targetBlock;
      if (targetBlock == -1) {
        targetBlock = 7;
      }
      nextBlocks[targetBlock].add(nextIndexBase);
      nextIndexBase += 1;
    }

    setState(() {
      _players = [..._players, ...toAppend];
      _setupBlocks = nextBlocks;
      _sessionAddedPlayers += toAppend.length;
      _teamMoneyByBlock.removeWhere(
        (index, _) => index >= nextBlocks.length || nextBlocks[index].isEmpty,
      );
    });
  }

  void _removePlayerAt(int playerIndex) {
    if (playerIndex < 0 || playerIndex >= _players.length) return;

    final nextPlayers = List<_DurakPlayer>.from(_players)
      ..removeAt(playerIndex);
    final nextBlocks = _setupBlocks
        .map(
          (block) => block
              .where((index) => index != playerIndex)
              .map((index) => index > playerIndex ? index - 1 : index)
              .toList(growable: false),
        )
        .toList(growable: false);

    setState(() {
      _players = nextPlayers;
      _setupBlocks = nextBlocks;
      _activeBlockIndexes = _activeBlockIndexes
          .where((index) =>
              index < nextBlocks.length && nextBlocks[index].isNotEmpty)
          .toSet();
      _inactiveBlockIndexes = _inactiveBlockIndexes
          .where((index) =>
              index < nextBlocks.length && nextBlocks[index].isNotEmpty)
          .toSet();
      _blockWins.removeWhere(
        (index, _) => index >= nextBlocks.length || nextBlocks[index].isEmpty,
      );
      _teamRoundWins.removeWhere(
        (index, _) => index >= nextBlocks.length || nextBlocks[index].isEmpty,
      );
      _teamMoneyByBlock.removeWhere(
        (index, _) => index >= nextBlocks.length || nextBlocks[index].isEmpty,
      );
      _sessionRemovedPlayers += 1;
    });
  }

  Future<void> _showRemovePlayerDialog() async {
    if (_players.isEmpty) return;

    final selectedIndexes = <int>{};

    final selected = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Хасах тоглогчид'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List<Widget>.generate(_players.length, (index) {
                    final isChecked = selectedIndexes.contains(index);
                    return CheckboxListTile(
                      value: isChecked,
                      title: Text(_players[index].displayName),
                      dense: true,
                      onChanged: (value) {
                        setStateDialog(() {
                          if (value == true) {
                            selectedIndexes.add(index);
                          } else {
                            selectedIndexes.remove(index);
                          }
                        });
                      },
                    );
                  }),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Болих'),
              ),
              ElevatedButton(
                onPressed: selectedIndexes.isEmpty
                    ? null
                    : () {
                        final ordered = selectedIndexes.toList()..sort();
                        Navigator.of(dialogContext).pop(ordered);
                      },
                child: const Text('Хасах'),
              ),
            ],
          );
        });
      },
    );

    if (selected == null || selected.isEmpty) return;

    final removedUserIds = selected
        .where((index) => index >= 0 && index < _players.length)
        .map((index) => _players[index].userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    for (final index in selected.reversed) {
      _removePlayerAt(index);
    }

    if (removedUserIds.isNotEmpty) {
      Future.microtask(
        () => _activeTablesRepo.releasePlayersFromActiveTables(removedUserIds),
      );
    }
  }

  Widget _buildMatchupIndicator() {
    const iconSize = 30.0;
    const gap = 8.0;

    if (_stage == _DurakStage.group) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_2_rounded, size: iconSize, color: Colors.white),
          SizedBox(width: gap),
          Icon(Icons.swap_horiz_rounded, size: iconSize, color: Colors.white70),
          SizedBox(width: gap),
          Icon(Icons.groups_2_rounded, size: iconSize, color: Colors.white),
        ],
      );
    }

    if (_stage == _DurakStage.finalStage && _isSingleTypeMode) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_2_rounded, size: iconSize, color: Colors.white),
          SizedBox(width: gap),
          Icon(Icons.swap_horiz_rounded, size: iconSize, color: Colors.white70),
          SizedBox(width: gap),
          Icon(Icons.groups_2_rounded, size: iconSize, color: Colors.white),
        ],
      );
    }

    if (_stage == _DurakStage.finalStage || _stage == _DurakStage.direct) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_rounded, size: iconSize, color: Colors.white),
          SizedBox(width: gap),
          Icon(Icons.swap_horiz_rounded, size: iconSize, color: Colors.white70),
          SizedBox(width: gap),
          Icon(Icons.person_rounded, size: iconSize, color: Colors.white),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSetupBlock(int blockIndex, {required bool isLarge}) {
    final memberIndexes = _setupBlocks[blockIndex];
    final hasMembers = memberIndexes.isNotEmpty;
    final members =
        memberIndexes.map((i) => _players[i]).toList(growable: false);
    final isInteractive = _isBlockInteractive(blockIndex);
    final isInactive = _inactiveBlockIndexes.contains(blockIndex);
    final isChampion = _championBlockIndex == blockIndex;
    final currentWins = _blockWins[blockIndex] ?? 0;
    final canDrag = _stage == _DurakStage.setup;

    final content = Container(
      decoration: BoxDecoration(
        color: hasMembers
            ? (isInactive
                ? Colors.black.withOpacity(0.18)
                : Colors.black.withOpacity(0.35))
            : Colors.white10,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isChampion
              ? Colors.amber
              : hasMembers
                  ? Colors.deepOrangeAccent
                  : Colors.white24,
          width: 2,
        ),
      ),
      padding: EdgeInsets.all(isLarge ? 10 : 6),
      child: hasMembers
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final memberCount = members.length;
                        final columns = memberCount <= 1
                            ? 1
                            : memberCount == 2
                                ? 2
                                : memberCount == 3
                                    ? 3
                                    : 2;
                        final spacing = isLarge ? 12.0 : 8.0;
                        final tileWidth =
                            (constraints.maxWidth - (columns - 1) * spacing) /
                                columns;

                        final avatarRadius = isLarge
                            ? (memberCount <= 2
                                ? 28.0
                                : memberCount == 3
                                    ? 22.0
                                    : 18.0)
                            : (memberCount <= 2 ? 22.0 : 16.0);
                        final displayNameSize = isLarge
                            ? (memberCount <= 2
                                ? 40.0
                                : memberCount == 3
                                    ? 24.0
                                    : 18.0)
                            : (memberCount <= 2 ? 24.0 : 14.0);
                        final usernameSize = isLarge
                            ? (memberCount <= 2
                                ? 20.0
                                : memberCount == 3
                                    ? 14.0
                                    : 12.0)
                            : (memberCount <= 2 ? 14.0 : 11.0);
                        final moneySize = isLarge
                            ? (memberCount <= 2
                                ? 24.0
                                : memberCount == 3
                                    ? 18.0
                                    : 14.0)
                            : (memberCount <= 2 ? 16.0 : 12.0);
                        final cupSize = isLarge
                            ? (memberCount <= 2
                                ? 24.0
                                : memberCount == 3
                                    ? 18.0
                                    : 14.0)
                            : (memberCount <= 2 ? 18.0 : 14.0);

                        return Wrap(
                          spacing: spacing,
                          runSpacing: isLarge ? 12 : 8,
                          children: members
                              .map(
                                (player) => SizedBox(
                                  width: tileWidth,
                                  child: Column(
                                    children: [
                                      CircleAvatar(
                                        radius: avatarRadius,
                                        backgroundColor: Colors.white24,
                                        backgroundImage:
                                            _resolveImage(player.photoUrl),
                                        child: (player.photoUrl == null ||
                                                player.photoUrl!.isEmpty)
                                            ? Icon(
                                                Icons.person,
                                                color: Colors.white,
                                                size: avatarRadius + 4,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        player.displayName,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: displayNameSize,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '@${player.username}',
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: usernameSize,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (_betMode ==
                                          _DurakBetMode.perMember) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          '₮${player.money}',
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: player.money < 0
                                                ? Colors.redAccent
                                                : Colors.lightGreenAccent,
                                            fontSize: moneySize,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                      if (_isMultiTypeMode) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.emoji_events_rounded,
                                              size: cupSize,
                                              color: _lastWinnerBlockIndex ==
                                                      blockIndex
                                                  ? Colors.amber
                                                  : Colors.white70,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${widget.multiWinsByUserId != null ? (widget.multiWinsByUserId?[player.userId ?? ''] ?? 0) : player.durakCups}',
                                              style: TextStyle(
                                                color: _lastWinnerBlockIndex ==
                                                        blockIndex
                                                    ? Colors.amber
                                                    : Colors.white70,
                                                fontSize: cupSize,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    ),
                  ),
                ),
                if (_betMode == _DurakBetMode.perTeam) ...[
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Баг: ₮${_blockMoney(blockIndex)}',
                      style: TextStyle(
                        color: _blockMoney(blockIndex) < 0
                            ? Colors.redAccent
                            : Colors.lightGreenAccent,
                        fontSize: isLarge ? 24 : 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final starCount = _targetWins;
                    if (starCount <= 0) return const SizedBox.shrink();
                    final spacing = isLarge ? 6.0 : 4.0;
                    final computed =
                        (constraints.maxWidth - (starCount - 1) * spacing) /
                            starCount;
                    final starSize = computed.clamp(
                        isLarge ? 20.0 : 14.0, isLarge ? 36.0 : 26.0);

                    return Row(
                      children: List<Widget>.generate(
                        starCount,
                        (index) => Padding(
                          padding: EdgeInsets.only(
                            right: index == starCount - 1 ? 0 : spacing,
                          ),
                          child: GestureDetector(
                            onTap: isInteractive && !isInactive
                                ? () => _changeBlockWins(blockIndex, 1)
                                : null,
                            onLongPress: isInteractive &&
                                    !isInactive &&
                                    !_isSingleGroupMode
                                ? () => _changeBlockWins(blockIndex, -1)
                                : null,
                            child: Icon(
                              Icons.star_rounded,
                              size: starSize,
                              color: index < currentWins
                                  ? Colors.amber
                                  : Colors.white24,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            )
          : Center(
              child: Text(
                'Хоосон',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: isLarge ? 16 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
    );

    final target = DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        final source = details.data;
        if (source == blockIndex) return false;
        if (!hasMembers) return false;
        return _setupBlocks[source].isNotEmpty;
      },
      onAcceptWithDetails: (details) {
        _mergeSetupBlocks(details.data, blockIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: isHovering
                ? [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.45),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: content,
        );
      },
    );

    if (!hasMembers || !canDrag) return target;

    return Draggable<int>(
      data: blockIndex,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: isLarge ? 230 : 140,
          height: isLarge ? 170 : 110,
          child: content,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: target),
      child: target,
    );
  }

  Widget _buildSetupBoard() {
    return Column(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: List<Widget>.generate(
                    3,
                    (index) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _buildSetupBlock(index, isLarge: true),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: List<Widget>.generate(
                    5,
                    (offset) {
                      final index = offset + 3;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: _buildSetupBlock(index, isLarge: false),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  ImageProvider? _resolveImage(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
      return NetworkImage(photoUrl);
    }
    return null;
  }
}

class _DurakPlayer {
  const _DurakPlayer({
    this.userId,
    required this.displayName,
    required this.username,
    this.photoUrl,
    this.money = 0,
    this.durakCups = 0,
  });

  final String? userId;
  final String displayName;
  final String username;
  final String? photoUrl;
  final int money;
  final int durakCups;

  _DurakPlayer copyWith({
    String? userId,
    String? displayName,
    String? username,
    String? photoUrl,
    int? money,
    int? durakCups,
  }) {
    return _DurakPlayer(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      money: money ?? this.money,
      durakCups: durakCups ?? this.durakCups,
    );
  }
}
