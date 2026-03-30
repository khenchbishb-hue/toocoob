import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:toocoob/screens/statistics_dashboard.dart';
import 'package:toocoob/utils/game_registrar_transfer.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';
import 'package:toocoob/screens/kinds_of_game.dart';

class BuurPage extends StatefulWidget {
  const BuurPage({
    super.key,
    this.selectedUserIds = const [],
    this.currentUserId,
    this.canManageGames = false,
    this.initialSavedSessionId,
    this.autoReturnOnWinner = false,
    this.multiWinsByUserId,
    this.multiCurrentTypeNumber,
    this.multiTotalTypeCount,
  });

  final List<String> selectedUserIds;
  final String? currentUserId;
  final bool canManageGames;
  final String? initialSavedSessionId;
  final bool autoReturnOnWinner;
  final Map<String, int>? multiWinsByUserId;
  final int? multiCurrentTypeNumber;
  final int? multiTotalTypeCount;

  @override
  State<BuurPage> createState() => _BuurPageState();
}

class _BuurPageState extends State<BuurPage> {
  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();
  static const List<_BuurAction> _actions = [
    _BuurAction(
      keyLabel: '31',
      transfer: 1,
      color: Color(0xFF2E7D32),
      textColor: Colors.white,
      imagePath: 'assets/buttons/buur.jpg',
    ),
    _BuurAction(
      keyLabel: '3 A',
      keySubLabel: '♠ ♥ ♦',
      transfer: 3,
      color: Color(0xFF1B5E20),
      textColor: Colors.white,
      imagePath: 'assets/buttons/tamgan buur.jpg',
    ),
    _BuurAction(
      keyLabel: '♣ ♣ ♣',
      transfer: 2,
      color: Color(0xFFC62828),
      textColor: Colors.white,
      imagePath: 'assets/buttons/xuzur buur.jpg',
    ),
    _BuurAction(
      keyLabel: '7 7 7',
      transfer: 4,
      color: Color(0xFF8E0000),
      textColor: Colors.white,
      imagePath: 'assets/buttons/botgon buur.jpg',
    ),
  ];

  late List<_BuurPlayer> _players;
  late int _initialCenterScore;
  late int _centerScore;
  int _roundNumber = 1;
  int _lossAmount = 5000;
  bool _isBoltMode = false;
  int _boltRoundNumber = 0;
  int _sessionOrdinaryRounds = 0;
  int _sessionBoltRounds = 0;
  String? _winnerPlayerKey;
  String? _activeSavedSessionId;
  String? _currentRegistrarUserId;
  bool _sessionAddedToStatistics = false;
  bool _multiAutoReturnTriggered = false;

  bool get _canTransferRegistrar =>
      widget.canManageGames &&
      widget.currentUserId != null &&
      _currentRegistrarUserId == widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _players = _buildInitialPlayers(widget.selectedUserIds);
    _currentRegistrarUserId = widget.currentUserId;
    _initialCenterScore = _calculateInitialCenterScore(_players.length);
    _centerScore = _initialCenterScore;

    _tryRestoreSavedSession();

    if (widget.selectedUserIds.isNotEmpty) {
      _loadSelectedUserProfiles();
    }
  }

  Future<void> _tryRestoreSavedSession() async {
    final id = widget.initialSavedSessionId;
    if (id == null || id.isEmpty) return;
    final saved = await _savedSessionsRepo.findById(id);
    if (saved == null || !mounted) return;
    final p = saved.payload;

    final rawPlayers = (p['players'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final restoredPlayers = rawPlayers
        .map(
          (e) => _BuurPlayer(
            userId: (e['userId'] ?? '').toString().isEmpty
                ? null
                : (e['userId'] ?? '').toString(),
            displayName: (e['displayName'] ?? '').toString(),
            username: (e['username'] ?? '').toString(),
            photoUrl: (e['photoUrl'] ?? '').toString().isEmpty
                ? null
                : (e['photoUrl'] ?? '').toString(),
            pishka: (e['pishka'] as num? ?? 0).toInt(),
            wins: (e['wins'] as num? ?? 0).toInt(),
            money: (e['money'] as num? ?? 0).toInt(),
            isEliminated: e['isEliminated'] == true,
          ),
        )
        .toList();

    setState(() {
      _activeSavedSessionId = saved.id;
      if (restoredPlayers.isNotEmpty) {
        _players = restoredPlayers;
      }
      _initialCenterScore =
          (p['initialCenterScore'] as num? ?? _initialCenterScore).toInt();
      _centerScore = (p['centerScore'] as num? ?? _centerScore).toInt();
      _roundNumber = (p['roundNumber'] as num? ?? _roundNumber).toInt();
      _lossAmount = (p['lossAmount'] as num? ?? _lossAmount).toInt();
      _isBoltMode = p['isBoltMode'] as bool? ?? _isBoltMode;
      _boltRoundNumber =
          (p['boltRoundNumber'] as num? ?? _boltRoundNumber).toInt();
      _sessionOrdinaryRounds =
          (p['sessionOrdinaryRounds'] as num? ?? _sessionOrdinaryRounds)
              .toInt();
      _sessionBoltRounds =
          (p['sessionBoltRounds'] as num? ?? _sessionBoltRounds).toInt();
      _sessionAddedToStatistics =
          p['sessionAddedToStatistics'] as bool? ?? _sessionAddedToStatistics;
      _winnerPlayerKey =
          (p['winnerPlayerKey'] as String?)?.trim().isEmpty == true
              ? null
              : (p['winnerPlayerKey'] as String?);
    });
  }

  Future<void> _saveProgress() async {
    final payload = {
      'players': _players
          .map((e) => {
                'userId': e.userId,
                'displayName': e.displayName,
                'username': e.username,
                'photoUrl': e.photoUrl,
                'pishka': e.pishka,
                'wins': e.wins,
                'money': e.money,
                'isEliminated': e.isEliminated,
              })
          .toList(),
      'initialCenterScore': _initialCenterScore,
      'centerScore': _centerScore,
      'roundNumber': _roundNumber,
      'lossAmount': _lossAmount,
      'isBoltMode': _isBoltMode,
      'boltRoundNumber': _boltRoundNumber,
      'sessionOrdinaryRounds': _sessionOrdinaryRounds,
      'sessionBoltRounds': _sessionBoltRounds,
      'sessionAddedToStatistics': _sessionAddedToStatistics,
      'winnerPlayerKey': _winnerPlayerKey,
    };
    final id = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: 'buur',
      gameLabel: 'Буур',
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

  String? _winnerUserId() {
    final winnerKey = _winnerPlayerKey;
    if (winnerKey == null || !winnerKey.startsWith('id:')) return null;
    return winnerKey.substring(3);
  }

  int _calculateInitialCenterScore(int playerCount) {
    final normalized = playerCount < 2 ? 2 : playerCount;
    return normalized * 2 + 1;
  }

  String _playerKey(_BuurPlayer player, int index) {
    final userId = player.userId;
    if (userId != null && userId.isNotEmpty) return 'id:$userId';
    return 'idx:$index';
  }

  List<_BuurPlayer> _buildInitialPlayers(List<String> selectedUserIds) {
    if (selectedUserIds.isEmpty) {
      return List<_BuurPlayer>.generate(
        4,
        (index) => _BuurPlayer(
          displayName: 'Тоглогч ${index + 1}',
          username: 'u${index + 1}',
          pishka: 0,
          wins: 0,
          money: 0,
          isEliminated: false,
        ),
      );
    }

    return List<_BuurPlayer>.generate(
      selectedUserIds.length > 8 ? 8 : selectedUserIds.length,
      (index) => _BuurPlayer(
        userId: selectedUserIds[index],
        displayName: 'Тоглогч ${index + 1}',
        username: 'u${index + 1}',
        pishka: 0,
        wins: 0,
        money: 0,
        isEliminated: false,
      ),
    );
  }

  Future<void> _loadSelectedUserProfiles() async {
    final updated = List<_BuurPlayer>.from(_players);

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
        );
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _players = updated;
    });
  }

  void _applyAction({required int playerIndex, required _BuurAction action}) {
    if (playerIndex < 0 || playerIndex >= _players.length) return;
    if (_winnerPlayerKey != null) return;

    final actor = _players[playerIndex];
    if (actor.isEliminated) return;

    setState(() {
      if (_centerScore > 0) {
        final fromCenter =
            _centerScore >= action.transfer ? action.transfer : _centerScore;
        if (fromCenter <= 0) return;

        _players[playerIndex] =
            actor.copyWith(pishka: actor.pishka + fromCenter);
        _centerScore -= fromCenter;

        if (_centerScore == 0) {
          _markZeroPishkaAsEliminated();
        }

        _resolveWinnerIfAny();
        return;
      }

      if (actor.pishka <= 0) return;

      int totalTaken = 0;
      for (int i = 0; i < _players.length; i++) {
        if (i == playerIndex) continue;
        final other = _players[i];
        if (other.isEliminated) continue;

        final taken =
            other.pishka >= action.transfer ? action.transfer : other.pishka;
        if (taken <= 0) continue;

        totalTaken += taken;
        final nextOther = other.pishka - taken;
        _players[i] = other.copyWith(
          pishka: nextOther,
          isEliminated: nextOther <= 0,
        );
      }

      if (totalTaken > 0) {
        final refreshedActor = _players[playerIndex];
        _players[playerIndex] =
            refreshedActor.copyWith(pishka: refreshedActor.pishka + totalTaken);
      }

      _resolveWinnerIfAny();
    });
  }

  void _markZeroPishkaAsEliminated() {
    _players = _players
        .map((player) => player.copyWith(isEliminated: player.pishka <= 0))
        .toList(growable: false);
  }

  void _resolveWinnerIfAny() {
    if (_winnerPlayerKey != null) return;

    for (int i = 0; i < _players.length; i++) {
      final player = _players[i];
      if (!player.isEliminated && player.pishka >= _initialCenterScore) {
        _winnerPlayerKey = _playerKey(player, i);
        _players[i] = player.copyWith(wins: player.wins + 1);
        if (widget.autoReturnOnWinner) {
          _returnToKindsIfNeeded(i);
        } else {
          _applyRoundMoneySettlement(winnerIndex: i);
          _advanceAfterWinner();
        }
        return;
      }
    }

    final alive = <int>[];
    for (int i = 0; i < _players.length; i++) {
      if (!_players[i].isEliminated) {
        alive.add(i);
      }
    }

    if (alive.length == 1) {
      final i = alive.first;
      _winnerPlayerKey = _playerKey(_players[i], i);
      _players[i] = _players[i].copyWith(wins: _players[i].wins + 1);
      if (widget.autoReturnOnWinner) {
        _returnToKindsIfNeeded(i);
      } else {
        _applyRoundMoneySettlement(winnerIndex: i);
        _advanceAfterWinner();
      }
    }
  }

  void _returnToKindsIfNeeded(int winnerIndex) {
    if (_multiAutoReturnTriggered) return;
    _multiAutoReturnTriggered = true;
    final winnerUserId = _players[winnerIndex].userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(<String, dynamic>{
        'completedGame': 'buur',
        if (winnerUserId != null && winnerUserId.isNotEmpty)
          'winnerUserId': winnerUserId,
      });
    });
  }

  Future<void> _advanceAfterWinner() async {
    if (_isBoltMode) {
      _sessionBoltRounds += 1;
    } else {
      _sessionOrdinaryRounds += 1;
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() {
      var nextBoltMode = _isBoltMode;
      var nextRoundNumber = _roundNumber;
      var nextBoltRoundNumber = _boltRoundNumber;

      if (!nextBoltMode && _sessionOrdinaryRounds >= _players.length) {
        nextBoltMode = true;
        nextBoltRoundNumber = 1;
      } else if (nextBoltMode) {
        nextBoltRoundNumber += 1;
      } else {
        nextRoundNumber += 1;
      }

      final allIndices = List<int>.generate(_players.length, (i) => i);
      var activeIndices = nextBoltMode
          ? allIndices.where((i) => _players[i].wins == 0).toList()
          : allIndices;

      if (nextBoltMode && activeIndices.length < 2) {
        nextBoltMode = false;
        nextRoundNumber = 1;
        nextBoltRoundNumber = 0;
        activeIndices = allIndices;
      }

      _isBoltMode = nextBoltMode;
      _roundNumber = nextRoundNumber;
      _boltRoundNumber = nextBoltRoundNumber;
      _winnerPlayerKey = null;

      final activeSet = activeIndices.toSet();
      _players = List<_BuurPlayer>.generate(_players.length, (i) {
        final player = _players[i];
        return player.copyWith(
          pishka: 0,
          isEliminated: !activeSet.contains(i),
        );
      });

      _initialCenterScore = _calculateInitialCenterScore(activeIndices.length);
      _centerScore = _initialCenterScore;
    });
  }

  void _applyRoundMoneySettlement({required int winnerIndex}) {
    final loserCount = _players.length - 1;
    if (loserCount <= 0) return;

    for (int i = 0; i < _players.length; i++) {
      final player = _players[i];
      if (i == winnerIndex) {
        _players[i] =
            player.copyWith(money: player.money + (_lossAmount * loserCount));
      } else {
        _players[i] = player.copyWith(money: player.money - _lossAmount);
      }
    }
  }

  int _completedRounds() {
    final rounds = _sessionOrdinaryRounds + _sessionBoltRounds;
    return rounds < 0 ? 0 : rounds;
  }

  String _buildSessionReportText() {
    final rows = <String>[];
    final sorted = List<_BuurPlayer>.from(_players)
      ..sort((a, b) => b.money.compareTo(a.money));

    for (int i = 0; i < sorted.length; i++) {
      final p = sorted[i];
      rows.add(
        '${i + 1}. ${p.displayName} (@${p.username}) | хожил: ${p.wins} | мөнгө: ₮${p.money}',
      );
    }

    return [
      'БУУР - ТОГЛОЛТЫН ТАЙЛАН',
      'Тоглосон тойрог: ${_completedRounds()}',
      'Энгийн тоглолт: $_sessionOrdinaryRounds',
      'Боолт тоглолт: $_sessionBoltRounds',
      'Хожигдлын дүн (нэг тоглогч): ₮$_lossAmount',
      '',
      'Эцсийн дүн:',
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

    final session = StatsSession(
      sessionId:
          'buur-${DateTime.now().microsecondsSinceEpoch}-${_players.length}',
      gameKey: 'buur',
      gameLabel: 'БУУР',
      playedAt: DateTime.now(),
      players: players,
      totalRounds: _completedRounds(),
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

  Future<void> _shareSessionReport() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _buildSessionReportText(),
          subject: 'Буур - тоглолтын тайлан',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Илгээх үйлдэл амжилтгүй.')),
      );
    }
  }

  Future<void> _printSessionReport() async {
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          build: (_) => pw.Text(_buildSessionReportText()),
        ),
      );
      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Хэвлэх цонх нээгдсэнгүй.')),
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
      await _addCurrentSessionToStatisticsIfNeeded();
      await _removeSavedProgressIfAny();
      await _askRegistrarDecisionAtGameEndIfNeeded();
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _showSessionReportDialog() async {
    await showDialog<void>(
      context: context,
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
                Navigator.of(dialogContext).pop();
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
                Navigator.of(dialogContext).pop();
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
                Navigator.of(dialogContext).pop();
                await _openStatisticsDashboard();
              },
              child: const Text('Статистик'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Хаах'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showExitReportDialog() async {
    await _showExitReportAndFinish();
    return false;
  }

  Future<void> _showSettingsDialog() async {
    final controller = TextEditingController(text: _lossAmount.toString());
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Буур тохиргоо'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Хожигдогчийн мөнгө (₮)',
              hintText: 'Ж: 5000',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Болих'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                if (parsed == null || parsed <= 0) {
                  Navigator.of(dialogContext).pop();
                  return;
                }
                Navigator.of(dialogContext).pop(parsed);
              },
              child: const Text('Хадгалах'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (!mounted || selected == null) return;
    setState(() {
      _lossAmount = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (widget.autoReturnOnWinner) {
          Navigator.of(context).pop();
          return false;
        }
        return _showExitReportDialog();
      },
      child: Scaffold(
        appBar: UnifiedGameAppBar(
          currentUserId: widget.currentUserId,
          canManageGames: widget.canManageGames,
          title: Text(
            _isBoltMode
                ? 'Буур  |  Боолт №$_boltRoundNumber'
                : 'Буур  |  ${widget.multiWinsByUserId != null ? 'Төрөл ${widget.multiCurrentTypeNumber ?? _roundNumber}/${widget.multiTotalTypeCount ?? _roundNumber}' : 'Тоглолтын №$_roundNumber'}',
          ),
          onBack: () async {
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
                  playingFormat:
                      widget.multiWinsByUserId != null ? 'multi' : 'single',
                ),
              ),
            );
          },
          onSave: _saveProgress,
          onStatistics: _openStatisticsDashboard,
          onReport: _showSessionReportDialog,
          onSettings: _showSettingsDialog,
          onExit: () async {
            if (widget.autoReturnOnWinner) {
              Navigator.of(context).pop();
              return;
            }
            await _showExitReportAndFinish();
          },
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
              Expanded(
                child: _buildPlayerRow(startSlot: 0),
              ),
              const SizedBox(height: 12),
              _buildActionRow(),
              const SizedBox(height: 12),
              Expanded(
                child: _buildPlayerRow(startSlot: 4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerRow({required int startSlot}) {
    return Row(
      children: [
        for (int i = 0; i < 4; i++) ...[
          Expanded(
            child: _buildPlayerSlot(startSlot + i),
          ),
          if (i != 3) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _buildPlayerSlot(int playerIndex) {
    if (playerIndex >= _players.length) {
      return _buildEmptyPlayerCard(playerIndex + 1);
    }

    final player = _players[playerIndex];
    if (player.isEliminated || _winnerPlayerKey != null) {
      return _buildPlayerCard(player, playerIndex + 1);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final feedbackWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : 220.0;
        final feedbackHeight =
            constraints.hasBoundedHeight ? constraints.maxHeight : 220.0;

        return Draggable<int>(
          data: playerIndex,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: feedbackWidth,
              height: feedbackHeight,
              child: _buildPlayerCard(player, playerIndex + 1, dragging: true),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _buildPlayerCard(player, playerIndex + 1),
          ),
          child: _buildPlayerCard(player, playerIndex + 1),
        );
      },
    );
  }

  Widget _buildPlayerCard(_BuurPlayer player, int order,
      {bool dragging = false}) {
    final isEliminated = player.isEliminated;
    final isWinner = _winnerPlayerKey == _playerKey(player, order - 1);
    final moneyColor = player.money < 0 ? Colors.red : Colors.green;
    final multiWins = widget.multiWinsByUserId?[player.userId ?? ''] ?? 0;

    return Card(
      elevation: dragging ? 10 : 2,
      color: const Color(0xFFE67E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isWinner
              ? Colors.green
              : (isEliminated
                  ? Colors.red
                  : (dragging ? Colors.blueAccent : const Color(0xFFF8EFE7))),
          width: 3,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 54),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final side =
                              constraints.maxWidth < constraints.maxHeight
                                  ? constraints.maxWidth
                                  : constraints.maxHeight;
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SizedBox(
                                  width: side,
                                  height: side,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      color: const Color(0xFFE3A25A),
                                      alignment: Alignment.center,
                                      child: (player.photoUrl != null &&
                                              player.photoUrl!.isNotEmpty)
                                          ? Image.network(
                                              player.photoUrl!,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              height: double.infinity,
                                              errorBuilder: (context, _, __) =>
                                                  const Icon(
                                                Icons.person,
                                                size: 52,
                                                color: Color(0xFF96311D),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.person,
                                              size: 52,
                                              color: Color(0xFF96311D),
                                            ),
                                    ),
                                  ),
                                ),
                                if (widget.multiWinsByUserId != null)
                                  Positioned(
                                    right: -14,
                                    top: 6,
                                    child: Column(
                                      children: [
                                        const Icon(Icons.emoji_events,
                                            color: Colors.amber, size: 20),
                                        Text(
                                          '$multiWins',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 78,
                      child: Column(
                        children: [
                          Expanded(
                            child: _buildTopRightMetricSquare(
                              title: 'Хожил',
                              value: '${player.wins}',
                              subValue: '₮${player.money}',
                              valueColor: moneyColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: _buildTopRightMetricSquare(
                              title: 'Пишка',
                              value: '${player.pishka}',
                              valueColor:
                                  isEliminated ? Colors.red : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      player.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      player.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isEliminated ? Colors.red : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPlayerCard(int order) {
    return Card(
      elevation: 1,
      color: const Color(0xFFE67E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFFF8EFE7), width: 2.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE3A25A),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRightMetricSquare({
    required String title,
    required String value,
    required Color valueColor,
    String? subValue,
    double titleFontSize = 10,
    double valueFontSize = 17,
    bool animateValue = false,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB34A33), width: 1.6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: titleFontSize,
            ),
          ),
          const SizedBox(height: 1),
          if (animateValue)
            _buildAnimatedMetricValue(
              keyValue: value,
              value: value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: valueFontSize,
                color: valueColor,
                height: 1,
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: valueFontSize,
                color: valueColor,
                height: 1,
              ),
            ),
          if (subValue != null) ...[
            const SizedBox(height: 1),
            Text(
              subValue,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                height: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedMetricValue({
    required String keyValue,
    required String value,
    required TextStyle style,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: Text(
        value,
        key: ValueKey<String>(keyValue),
        style: style,
      ),
    );
  }

  Widget _buildActionRow() {
    return SizedBox(
      height: 96,
      child: Row(
        children: [
          Expanded(child: _buildDropTarget(_actions[0])),
          const SizedBox(width: 10),
          Expanded(child: _buildDropTarget(_actions[1])),
          const SizedBox(width: 10),
          Expanded(child: _buildCenterValueCell()),
          const SizedBox(width: 10),
          Expanded(child: _buildDropTarget(_actions[2])),
          const SizedBox(width: 10),
          Expanded(child: _buildDropTarget(_actions[3])),
        ],
      ),
    );
  }

  Widget _buildCenterValueCell() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/buttons/huree buur.jpg',
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFFF4E3D6)),
          ),
          Center(
            child: _buildAnimatedMetricValue(
              keyValue: 'center-$_centerScore',
              value: '$_centerScore',
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 6),
                  Shadow(color: Colors.black54, blurRadius: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropTarget(_BuurAction action) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        if (_winnerPlayerKey != null) return false;
        final index = details.data;
        if (index < 0 || index >= _players.length) return false;
        final player = _players[index];
        if (player.isEliminated) return false;
        if (_centerScore > 0) {
          return true;
        }
        return player.pishka > 0;
      },
      onAcceptWithDetails: (details) {
        _applyAction(playerIndex: details.data, action: action);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: action.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovering ? Colors.white : Colors.black26,
              width: isHovering ? 3 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: isHovering ? 12 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (action.imagePath != null)
                Image.asset(action.imagePath!, fit: BoxFit.fill),
              if (isHovering) Container(color: Colors.white.withOpacity(0.18)),
            ],
          ),
        );
      },
    );
  }
}

class _BuurAction {
  const _BuurAction({
    required this.keyLabel,
    this.keySubLabel,
    required this.transfer,
    required this.color,
    required this.textColor,
    this.imagePath,
  });

  final String keyLabel;
  final String? keySubLabel;
  final int transfer;
  final Color color;
  final Color textColor;
  final String? imagePath;
}

class _BuurPlayer {
  const _BuurPlayer({
    this.userId,
    this.photoUrl,
    required this.displayName,
    required this.username,
    required this.pishka,
    required this.wins,
    required this.money,
    required this.isEliminated,
  });

  final String? userId;
  final String? photoUrl;
  final String displayName;
  final String username;
  final int pishka;
  final int wins;
  final int money;
  final bool isEliminated;

  _BuurPlayer copyWith({
    String? userId,
    String? photoUrl,
    String? displayName,
    String? username,
    int? pishka,
    int? wins,
    int? money,
    bool? isEliminated,
  }) {
    return _BuurPlayer(
      userId: userId ?? this.userId,
      photoUrl: photoUrl ?? this.photoUrl,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      pishka: pishka ?? this.pishka,
      wins: wins ?? this.wins,
      money: money ?? this.money,
      isEliminated: isEliminated ?? this.isEliminated,
    );
  }
}
