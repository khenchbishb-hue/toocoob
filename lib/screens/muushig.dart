import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:toocoob/screens/statistics_dashboard.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'package:toocoob/screens/player_selection_page.dart';
import 'package:toocoob/utils/game_registrar_transfer.dart';

enum _MuushigSettlementMode {
  basePenalty,
  byScore,
  flatLoser,
}

class MuushigPage extends StatefulWidget {
  const MuushigPage({
    super.key,
    this.selectedUserIds = const [],
    this.currentUserId,
    this.canManageGames = false,
  });

  final List<String> selectedUserIds;
  final String? currentUserId;
  final bool canManageGames;

  @override
  State<MuushigPage> createState() => _MuushigPageState();
}

class _MuushigPageState extends State<MuushigPage> {
  late final List<String> _selectedUserIdsSnapshot;
  int _roundNumber = 1;
  bool _playerOrderSelected = false;
  bool _isBoltMode = false;
  bool _isMiddleBoltMode = false;
  int _normalRoundsPlayed = 0;
  int _totalBoltRounds = 0;
  int _boltRoundsPlayed = 0;
  int _sessionOrdinaryRounds = 0;
  int _sessionBoltRounds = 0;
  int _sessionMiddleBoltRounds = 0;
  bool _isResolvingRound = false;
  bool _sessionCompleted = false;
  bool _needsPlaySelectionPrompt = false;
  final Set<String> _activePlayingUsernames = <String>{};
  final Map<String, bool> _roundPlayChoices = <String, bool>{};
  final Map<String, TextEditingController> _roundScoreControllers = {};
  final Map<String, FocusNode> _roundScoreFocusNodes = {};
  final Set<String> _penaltyFiveUsernames = <String>{};
  bool _selectedProfilesLoaded = true;
  bool _sessionAddedToStatistics = false;
  String? _currentRegistrarUserId;

  bool get _canTransferRegistrar =>
      widget.canManageGames &&
      widget.currentUserId != null &&
      _currentRegistrarUserId == widget.currentUserId;

  _MuushigSettlementMode _settlementMode = _MuushigSettlementMode.basePenalty;
  int _baseNormalAmount = 5000;
  int _baseBoltAmount = 10000;
  int _penaltyPerBomb = 500;
  int _scoreRateNormal = 500;
  int _scoreRateBolt = 1000;
  int _flatLoserNormal = 5000;
  int _flatLoserBolt = 10000;

  List<_MuushigSeat> _seats = [];

  @override
  void initState() {
    super.initState();
    _currentRegistrarUserId = widget.currentUserId;

    _selectedUserIdsSnapshot = List<String>.from(widget.selectedUserIds);

    _seats = _selectedUserIdsSnapshot.isNotEmpty
        ? _buildSeatsFromSelectedUsers(_selectedUserIdsSnapshot)
        : _buildDefaultSeats();

    if (_selectedUserIdsSnapshot.isNotEmpty) {
      _selectedProfilesLoaded = false;
    }

    for (final seat in _seats) {
      _roundScoreControllers[seat.username] = TextEditingController();
      _roundScoreFocusNodes[seat.username] = FocusNode();
    }

    if (_seats.length < 3 || _seats.length > 7) {
      _playerOrderSelected = true;
      _needsPlaySelectionPrompt = false;
    }

    if (_selectedUserIdsSnapshot.isNotEmpty) {
      _loadSelectedUserProfiles();
    }
  }

  Future<void> _transferRegistrarRole() async {
    final registrarId = _currentRegistrarUserId;
    if (!_canTransferRegistrar || registrarId == null || registrarId.isEmpty) {
      return;
    }

    final playerUserIds = _seats
        .map((seat) => seat.userId)
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
      playerUserIds: _seats
          .map((seat) => seat.userId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      displayNameForUserId: (userId) {
        for (final seat in _seats) {
          if (seat.userId == userId) return seat.displayName;
        }
        return 'Тоглогч';
      },
      usernameForUserId: (userId) {
        for (final seat in _seats) {
          if (seat.userId == userId) return seat.username;
        }
        return '';
      },
    );

    if (!mounted || resolvedRegistrarUserId == null) return;
    setState(() {
      _currentRegistrarUserId = resolvedRegistrarUserId;
    });
  }

  Future<void> _loadSelectedUserProfiles() async {
    final previousSeats = List<_MuushigSeat>.from(_seats);
    final updatedSeats = List<_MuushigSeat>.from(_seats);
    final Set<String> usedKeys = <String>{};
    final Map<String, String> keyMapping = {};

    for (int i = 0; i < previousSeats.length; i++) {
      final seat = previousSeats[i];
      final userId = seat.userId;
      var nextSeat = seat;
      var newKey = seat.username;

      if (userId != null && userId.isNotEmpty) {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
          final data = snapshot.data();
          if (data != null) {
            final fetchedUsername = (data['username'] as String?)?.trim();
            final fetchedDisplayName = (data['displayName'] as String?)?.trim();

            if (fetchedUsername != null && fetchedUsername.isNotEmpty) {
              newKey = fetchedUsername;
            }

            nextSeat = nextSeat.copyWith(
              username: fetchedUsername != null && fetchedUsername.isNotEmpty
                  ? fetchedUsername
                  : nextSeat.username,
              displayName:
                  fetchedDisplayName != null && fetchedDisplayName.isNotEmpty
                      ? fetchedDisplayName
                      : nextSeat.displayName,
              photoUrl: (data['photoUrl'] as String?)?.trim(),
            );
          }
        } catch (_) {}
      }

      if (usedKeys.contains(newKey)) {
        newKey = '${newKey}_${i + 1}';
        nextSeat = nextSeat.copyWith(username: newKey);
      }

      usedKeys.add(newKey);
      keyMapping[seat.username] = newKey;
      updatedSeats[i] = nextSeat;
    }

    final updatedControllers = <String, TextEditingController>{};
    final updatedFocusNodes = <String, FocusNode>{};
    final updatedActivePlaying = <String>{};
    final updatedPenaltyFive = <String>{};
    final updatedRoundChoices = <String, bool>{};

    for (final oldSeat in previousSeats) {
      final oldKey = oldSeat.username;
      final newKey = keyMapping[oldKey] ?? oldKey;

      final controller =
          _roundScoreControllers[oldKey] ?? TextEditingController();
      final focusNode = _roundScoreFocusNodes[oldKey] ?? FocusNode();

      updatedControllers[newKey] = controller;
      updatedFocusNodes[newKey] = focusNode;

      if (_activePlayingUsernames.contains(oldKey)) {
        updatedActivePlaying.add(newKey);
      }
      if (_penaltyFiveUsernames.contains(oldKey)) {
        updatedPenaltyFive.add(newKey);
      }
      if (_roundPlayChoices.containsKey(oldKey)) {
        updatedRoundChoices[newKey] = _roundPlayChoices[oldKey]!;
      }
    }

    if (!mounted) return;
    setState(() {
      _seats = updatedSeats;
      _roundScoreControllers
        ..clear()
        ..addAll(updatedControllers);
      _roundScoreFocusNodes
        ..clear()
        ..addAll(updatedFocusNodes);
      _activePlayingUsernames
        ..clear()
        ..addAll(updatedActivePlaying);
      _penaltyFiveUsernames
        ..clear()
        ..addAll(updatedPenaltyFive);
      _roundPlayChoices
        ..clear()
        ..addAll(updatedRoundChoices);
      _selectedProfilesLoaded = true;

      _needsPlaySelectionPrompt = false;
    });
  }

  bool _areAllSeatChoicesMade() => _roundPlayChoices.length == _seats.length;

  List<_MuushigSeat> _buildDefaultSeats() {
    return const [
      _MuushigSeat(
        username: 'Энхжин',
        displayName: 'Индиан',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        money: 0,
        bombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Оч-Эрдэнэ',
        displayName: 'МС',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        money: 0,
        bombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Батмагнай',
        displayName: 'Сыска',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        money: 0,
        bombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Баарсайхан',
        displayName: 'Шовгор',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        money: 0,
        bombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Лхаямгар',
        displayName: 'Шуумул',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        money: 0,
        bombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Сарантуяа',
        displayName: 'Базилио',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        money: 0,
        bombs: 0,
        isRoundPenaltyFive: false,
      ),
    ];
  }

  List<_MuushigSeat> _buildSeatsFromSelectedUsers(
      List<String> selectedUserIds) {
    return List<_MuushigSeat>.generate(selectedUserIds.length, (index) {
      final userId = selectedUserIds[index];
      return _MuushigSeat(
        username: 'u${index + 1}',
        displayName: 'Тоглогч ${index + 1}',
        userId: userId,
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        money: 0,
        bombs: 0,
        isRoundPenaltyFive: false,
      );
    });
  }

  @override
  void dispose() {
    for (final controller in _roundScoreControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _roundScoreFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _showPlayerActionInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Муушигийн тоглогч +/- логик дараагийн алхамд холбогдоно.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showMuushigSettingsDialog() async {
    var tempMode = _settlementMode;
    var tempBaseNormal = _baseNormalAmount;
    var tempBaseBolt = _baseBoltAmount;
    var tempPenaltyPerBomb = _penaltyPerBomb;
    var tempScoreRateNormal = _scoreRateNormal;
    var tempScoreRateBolt = _scoreRateBolt;
    var tempFlatLoserNormal = _flatLoserNormal;
    var tempFlatLoserBolt = _flatLoserBolt;

    int parseNonNegative(String value, int fallback) {
      final parsed = int.tryParse(value.trim());
      if (parsed == null || parsed < 0) return fallback;
      return parsed;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Муушиг тохиргоо'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Бооцоо бодох арга',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      RadioListTile<_MuushigSettlementMode>(
                        value: _MuushigSettlementMode.basePenalty,
                        groupValue: tempMode,
                        title: const Text('1) Суурь + Торгууль'),
                        subtitle:
                            const Text('Суурь (5000/10000) + Бөмбөг × 500'),
                        onChanged: (value) {
                          if (value == null) return;
                          setLocalState(() => tempMode = value);
                        },
                      ),
                      RadioListTile<_MuushigSettlementMode>(
                        value: _MuushigSettlementMode.byScore,
                        groupValue: tempMode,
                        title: const Text('2) Очковоор'),
                        subtitle:
                            const Text('Нийт оноо × 500, Боолт бол × 1000'),
                        onChanged: (value) {
                          if (value == null) return;
                          setLocalState(() => tempMode = value);
                        },
                      ),
                      RadioListTile<_MuushigSettlementMode>(
                        value: _MuushigSettlementMode.flatLoser,
                        groupValue: tempMode,
                        title: const Text('3) Хожигдсон бүр тогтмол'),
                        subtitle: const Text('Ж: 5000 (Боолтод тусдаа)'),
                        onChanged: (value) {
                          if (value == null) return;
                          setLocalState(() => tempMode = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      if (tempMode == _MuushigSettlementMode.basePenalty) ...[
                        TextFormField(
                          initialValue: tempBaseNormal.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Суурь (Энгийн)'),
                          onChanged: (value) => tempBaseNormal =
                              parseNonNegative(value, tempBaseNormal),
                        ),
                        TextFormField(
                          initialValue: tempBaseBolt.toString(),
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Суурь (Боолт)'),
                          onChanged: (value) => tempBaseBolt =
                              parseNonNegative(value, tempBaseBolt),
                        ),
                        TextFormField(
                          initialValue: tempPenaltyPerBomb.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Торгууль / бөмбөг'),
                          onChanged: (value) => tempPenaltyPerBomb =
                              parseNonNegative(value, tempPenaltyPerBomb),
                        ),
                      ],
                      if (tempMode == _MuushigSettlementMode.byScore) ...[
                        TextFormField(
                          initialValue: tempScoreRateNormal.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Үржвэр (Энгийн)'),
                          onChanged: (value) => tempScoreRateNormal =
                              parseNonNegative(value, tempScoreRateNormal),
                        ),
                        TextFormField(
                          initialValue: tempScoreRateBolt.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Үржвэр (Боолт)'),
                          onChanged: (value) => tempScoreRateBolt =
                              parseNonNegative(value, tempScoreRateBolt),
                        ),
                      ],
                      if (tempMode == _MuushigSettlementMode.flatLoser) ...[
                        TextFormField(
                          initialValue: tempFlatLoserNormal.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Хожигдсон бүр (Энгийн)'),
                          onChanged: (value) => tempFlatLoserNormal =
                              parseNonNegative(value, tempFlatLoserNormal),
                        ),
                        TextFormField(
                          initialValue: tempFlatLoserBolt.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Хожигдсон бүр (Боолт)'),
                          onChanged: (value) => tempFlatLoserBolt =
                              parseNonNegative(value, tempFlatLoserBolt),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _settlementMode = tempMode;
                      _baseNormalAmount = tempBaseNormal;
                      _baseBoltAmount = tempBaseBolt;
                      _penaltyPerBomb = tempPenaltyPerBomb;
                      _scoreRateNormal = tempScoreRateNormal;
                      _scoreRateBolt = tempScoreRateBolt;
                      _flatLoserNormal = tempFlatLoserNormal;
                      _flatLoserBolt = tempFlatLoserBolt;
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
  }

  int _calculateLoserPayment(_MuushigSeat loserSeat) {
    final isBolt = _isBoltMode;
    switch (_settlementMode) {
      case _MuushigSettlementMode.basePenalty:
        final base = isBolt ? _baseBoltAmount : _baseNormalAmount;
        return base + (loserSeat.bombs * _penaltyPerBomb);
      case _MuushigSettlementMode.byScore:
        final total = int.tryParse(loserSeat.totalScoreText) ?? 0;
        final rate = isBolt ? _scoreRateBolt : _scoreRateNormal;
        return total * rate;
      case _MuushigSettlementMode.flatLoser:
        return isBolt ? _flatLoserBolt : _flatLoserNormal;
    }
  }

  void _applySettlementForWinner(
      List<_MuushigSeat> updatedSeats, int winnerIndex) {
    var winnerGain = 0;
    for (int i = 0; i < updatedSeats.length; i++) {
      if (i == winnerIndex) continue;
      final loser = updatedSeats[i];
      final payment = _calculateLoserPayment(loser);
      if (payment <= 0) continue;
      updatedSeats[i] = loser.copyWith(money: loser.money - payment);
      winnerGain += payment;
    }

    final winner = updatedSeats[winnerIndex];
    updatedSeats[winnerIndex] =
        winner.copyWith(money: winner.money + winnerGain);
  }

  Future<void> _showRoundWinnerDialog() async {
    if (_isResolvingRound || _seats.isEmpty || _sessionCompleted) return;

    _isResolvingRound = true;
    try {
      final winnerIndex = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(_isBoltMode
                ? 'Боолт №${_boltRoundsPlayed + 1} ялагч'
                : 'Тоглолтын №$_roundNumber ялагч'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_seats.length, (index) {
                  final seat = _seats[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(index),
                        child: Text('${seat.displayName} (${seat.username})'),
                      ),
                    ),
                  );
                }),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Болих'),
              ),
            ],
          );
        },
      );

      if (!mounted || winnerIndex == null) return;

      _applyRoundWinner(winnerIndex);

      if (_isBoltMode) {
        await _handleBoltProgression();
      } else {
        await _handleNormalRoundProgression();
      }
    } finally {
      _isResolvingRound = false;
    }
  }

  void _applyRoundWinner(int winnerIndex) {
    setState(() {
      final updatedSeats = List<_MuushigSeat>.from(_seats);
      final winner = updatedSeats[winnerIndex];
      updatedSeats[winnerIndex] = winner.copyWith(wins: winner.wins + 1);
      _seats = updatedSeats;
    });
  }

  Future<void> _handleNormalRoundProgression() async {
    _normalRoundsPlayed += 1;

    if (_normalRoundsPlayed < _seats.length) {
      if (!mounted) return;
      setState(() {
        _roundNumber = _normalRoundsPlayed + 1;
      });
      return;
    }

    final winlessCount = _seats.where((seat) => seat.wins == 0).length;
    if (winlessCount <= 0) {
      _sessionCompleted = true;
      if (!mounted) return;
      await _handleCycleCompletedFlow();
      return;
    }

    _isBoltMode = true;
    _totalBoltRounds = winlessCount;
    _boltRoundsPlayed = 0;
    if (!mounted) return;
    await _prepareNextBoltRound();
  }

  Future<void> _handleBoltProgression() async {
    _boltRoundsPlayed += 1;
    if (_boltRoundsPlayed >= _totalBoltRounds) {
      _sessionCompleted = true;
      if (!mounted) return;
      await _handleCycleCompletedFlow();
      return;
    }

    if (!mounted) return;
    await _prepareNextBoltRound();
  }

  Future<void> _prepareNextBoltRound() async {
    final shouldChangeOrder = await _showBoltOrderDecisionDialog();
    if (!mounted) return;

    if (shouldChangeOrder == true) {
      await showPlayerOrderDialog(
        _seats.map((seat) => seat.username).toList(),
        _seats.map((seat) => seat.displayName).toList(),
        _seats.map((seat) => seat.photoUrl).toList(),
        (orderedIndices) {
          setState(() {
            final previousSeats = List<_MuushigSeat>.from(_seats);
            _seats =
                orderedIndices.map((index) => previousSeats[index]).toList();
          });
        },
      );
    }

    if (!mounted) return;
    setState(() {
      _roundNumber = _boltRoundsPlayed + 1;
    });
  }

  Future<bool?> _showBoltOrderDecisionDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Боолт №${_boltRoundsPlayed + 1}'),
          content: const Text('Боохдоо байрлал солих уу?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Үгүй'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Тийм'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _showCycleCompletedDialog() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тойрч тоглоод дууслаа'),
          content: const Text('Дараагийн үйлдлээ сонгоно уу.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('replay'),
              child: const Text('Дахин тойрох'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop('exit'),
              child: const Text('Гарах'),
            ),
          ],
        );
      },
    );
  }

  String _buildSessionReportText() {
    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;
    final initialPlayerCount = _selectedUserIdsSnapshot.isNotEmpty
        ? _selectedUserIdsSnapshot.length
        : _seats.length;
    final totalParticipatedPlayers = _seats.length;
    const addedPlayers = 0;
    const removedPlayers = 0;
    final rows = <String>[];
    for (int i = 0; i < _seats.length; i++) {
      final seat = _seats[i];
      rows.add(
          '${i + 1}. ${seat.displayName} (@${seat.username}): ₮${seat.money}');
    }

    return [
      'МУУШИГ - ТОГЛОЛТЫН ТАЙЛАН',
      'Эхний тоглогчийн тоо: $initialPlayerCount',
      'Нийт оролцсон тоглогч: $totalParticipatedPlayers',
      'Нэмсэн тоглогч: $addedPlayers',
      'Хассан тоглогч: $removedPlayers',
      'Нийт раунд: $totalRounds',
      'Энгийн тоглолт: $_sessionOrdinaryRounds',
      'Боолт тоглолт: $_sessionBoltRounds',
      'Дундын боолт: $_sessionMiddleBoltRounds',
      '',
      'Тоглогч тус бүрийн мөнгөн дүн:',
      ...rows,
    ].join('\n');
  }

  Future<void> _addCurrentSessionToStatisticsIfNeeded() async {
    if (_sessionAddedToStatistics) return;

    final repository = StatsRepository();
    final players = List<StatsPlayerResult>.generate(_seats.length, (index) {
      final seat = _seats[index];
      return StatsPlayerResult(
        userId: seat.userId ?? seat.username,
        username: seat.username,
        displayName: seat.displayName,
        money: seat.money,
      );
    });

    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;

    final session = StatsSession(
      sessionId:
          'muushig-${DateTime.now().microsecondsSinceEpoch}-${_seats.length}',
      gameKey: 'muushig',
      gameLabel: 'МУУШИГ',
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
    final initialPlayerCount = _selectedUserIdsSnapshot.isNotEmpty
        ? _selectedUserIdsSnapshot.length
        : _seats.length;

    final tableData = List<List<String>>.generate(
      _seats.length,
      (index) {
        final seat = _seats[index];
        return [
          '${index + 1}',
          seat.displayName,
          '@${seat.username}',
          '${seat.money}',
        ];
      },
    );

    doc.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        build: (context) => [
          pw.Text(
            'МУУШИГ - ТОГЛОЛТЫН ТАЙЛАН',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Эхний тоглогчийн тоо: $initialPlayerCount'),
          pw.Text('Нийт оролцсон тоглогч: ${_seats.length}'),
          pw.Text('Нэмсэн тоглогч: 0'),
          pw.Text('Хассан тоглогч: 0'),
          pw.Text('Нийт раунд: $totalRounds'),
          pw.Text('Энгийн тоглолт: $_sessionOrdinaryRounds'),
          pw.Text('Боолт тоглолт: $_sessionBoltRounds'),
          pw.Text('Дундын боолт: $_sessionMiddleBoltRounds'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['#', 'Display name', 'Username', 'Мөнгө (₮)'],
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
        name: 'toocoob_report_muushig',
        onLayout: (_) async => bytes,
      );
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
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop(false);
                await _printSessionReport();
              },
              child: const Text('Хэвлэх'),
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

  Future<bool> _showExitReportDialog() async {
    await _showExitReportAndFinish();
    return false;
  }

  void _resetBoardForNextGame() {
    _seats = _seats
        .map(
          (seat) => seat.copyWith(
            roundScoreText: '-',
            totalScoreText: '15',
            isRoundPenaltyFive: false,
          ),
        )
        .toList();

    for (final controller in _roundScoreControllers.values) {
      controller.clear();
    }
    _penaltyFiveUsernames.clear();
    _roundPlayChoices.clear();
    _activePlayingUsernames.clear();
  }

  void _resetForReplayKeepingMoneyOnly() {
    _seats = _seats
        .map(
          (seat) => seat.copyWith(
            wins: 0,
            bombs: 0,
            roundScoreText: '-',
            totalScoreText: '15',
            isRoundPenaltyFive: false,
          ),
        )
        .toList();

    _isBoltMode = false;
    _isMiddleBoltMode = false;
    _normalRoundsPlayed = 0;
    _totalBoltRounds = 0;
    _boltRoundsPlayed = 0;
    _roundNumber = 1;

    for (final controller in _roundScoreControllers.values) {
      controller.clear();
    }
    _penaltyFiveUsernames.clear();
    _roundPlayChoices.clear();
    _activePlayingUsernames.clear();
    _sessionCompleted = false;
  }

  Future<void> _handleCycleCompletedFlow() async {
    final action = await _showCycleCompletedDialog();
    if (!mounted) return;

    if (action == 'replay') {
      setState(_resetForReplayKeepingMoneyOnly);
      return;
    }

    if (action == 'exit') {
      await _showExitReportAndFinish();
    }
  }

  Future<bool?> _showMiddleBoltDecisionDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Дундын боолт'),
          content:
              const Text('Бүгд хожил x1 боллоо. Дундын боолт эхлүүлэх үү?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Үгүй'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Тийм'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _advanceAfterWinner() async {
    if (_isBoltMode) {
      if (_isMiddleBoltMode) {
        _sessionMiddleBoltRounds += 1;
      } else {
        _sessionBoltRounds += 1;
      }

      _boltRoundsPlayed += 1;
      if (_boltRoundsPlayed >= _totalBoltRounds) {
        _sessionCompleted = true;
        if (!mounted) return;
        await _handleCycleCompletedFlow();
        return;
      }

      if (!mounted) return;
      await _prepareNextBoltRound();
      if (!mounted) return;
      setState(_resetBoardForNextGame);
      return;
    }

    _normalRoundsPlayed += 1;
    _sessionOrdinaryRounds += 1;
    if (_normalRoundsPlayed < _seats.length) {
      setState(() {
        _roundNumber = _normalRoundsPlayed + 1;
        _resetBoardForNextGame();
      });
      return;
    }

    final allSingleWin =
        _seats.isNotEmpty && _seats.every((seat) => seat.wins == 1);
    if (allSingleWin) {
      final shouldStartMiddleBolt = await _showMiddleBoltDecisionDialog();
      if (shouldStartMiddleBolt != true) {
        _sessionCompleted = true;
        if (!mounted) return;
        await _handleCycleCompletedFlow();
        return;
      }

      _isBoltMode = true;
      _isMiddleBoltMode = true;
      _totalBoltRounds = 1;
      _boltRoundsPlayed = 0;
      if (!mounted) return;
      await _prepareNextBoltRound();
      if (!mounted) return;
      setState(_resetBoardForNextGame);
      return;
    }

    final winlessCount = _seats.where((seat) => seat.wins == 0).length;
    if (winlessCount <= 0) {
      _sessionCompleted = true;
      if (!mounted) return;
      await _handleCycleCompletedFlow();
      return;
    }

    _isBoltMode = true;
    _isMiddleBoltMode = false;
    _totalBoltRounds = winlessCount;
    _boltRoundsPlayed = 0;
    if (!mounted) return;
    await _prepareNextBoltRound();
    if (!mounted) return;
    setState(_resetBoardForNextGame);
  }

  Future<void> showPlayerOrderDialog(
      List<String> playerUserNames,
      List<String> playerDisplayNames,
      List<String?> playerPhotoUrls,
      void Function(List<int>) onOrderConfirmed) async {
    List<int?> selectedOrder = List.filled(playerDisplayNames.length, null);
    int currentOrder = 1;
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final screenWidth = MediaQuery.of(context).size.width;
            const cardSpacing = 6.0;
            final maxDialogWidth = screenWidth * 0.9;
            final cardWidth = (maxDialogWidth - cardSpacing * (7 - 1)) / 7;
            final dialogWidth = playerDisplayNames.length * cardWidth +
                (playerDisplayNames.length - 1) * cardSpacing;
            return AlertDialog(
              title: const Text('Тоглогчийн дараалал сонгох'),
              content: SizedBox(
                width: dialogWidth,
                height: 220,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0;
                              i < playerDisplayNames.length;
                              i++) ...[
                            SizedBox(
                              width: cardWidth,
                              height: 150,
                              child: GestureDetector(
                                onTap: () {
                                  if (selectedOrder[i] == null &&
                                      currentOrder <=
                                          playerDisplayNames.length) {
                                    setState(() {
                                      selectedOrder[i] = currentOrder;
                                      currentOrder++;
                                    });
                                  } else if (selectedOrder[i] != null) {
                                    setState(() {
                                      final removedOrder = selectedOrder[i]!;
                                      selectedOrder[i] = null;
                                      for (int j = 0;
                                          j < selectedOrder.length;
                                          j++) {
                                        if (selectedOrder[j] != null &&
                                            selectedOrder[j]! > removedOrder) {
                                          selectedOrder[j] =
                                              selectedOrder[j]! - 1;
                                        }
                                      }
                                      currentOrder--;
                                    });
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 0, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedOrder[i] != null
                                          ? Colors.blue
                                          : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Builder(
                                            builder: (context) {
                                              final photoUrl =
                                                  i < playerPhotoUrls.length
                                                      ? playerPhotoUrls[i]
                                                      : null;
                                              if (photoUrl != null &&
                                                  photoUrl.isNotEmpty) {
                                                return Image.network(
                                                  photoUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (context, _, __) {
                                                    return Image.asset(
                                                      'assets/13.jpg',
                                                      fit: BoxFit.cover,
                                                    );
                                                  },
                                                );
                                              }
                                              return Image.asset(
                                                'assets/13.jpg',
                                                fit: BoxFit.cover,
                                              );
                                            },
                                          ),
                                        ),
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.black
                                                      .withOpacity(0.05),
                                                  Colors.black.withOpacity(0.7),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (selectedOrder[i] != null)
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Colors.blue,
                                              child: Text(
                                                selectedOrder[i].toString(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          left: 8,
                                          right: 8,
                                          bottom: 6,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                playerDisplayNames[i],
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                playerUserNames[i],
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (i != playerDisplayNames.length - 1)
                              const SizedBox(width: cardSpacing),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            if (!mounted) return;
                            Navigator.of(this.context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PlayerSelectionPage(),
                              ),
                              (route) => false,
                            );
                          },
                          child: const Text('Болих'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: selectedOrder
                                      .where((e) => e != null)
                                      .length ==
                                  playerDisplayNames.length
                              ? () {
                                  List<int> orderedIndices =
                                      List.filled(playerDisplayNames.length, 0);
                                  for (int i = 0;
                                      i < playerDisplayNames.length;
                                      i++) {
                                    if (selectedOrder[i] != null) {
                                      orderedIndices[selectedOrder[i]! - 1] = i;
                                    }
                                  }
                                  onOrderConfirmed(orderedIndices);
                                  Navigator.of(context).pop();
                                }
                              : null,
                          child: const Text('Дараалал хадгалах'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showRoundPlayersSelectionDialog() async {
    final Set<int> selectedIndices = <int>{
      for (int i = 0; i < _seats.length; i++)
        if (_activePlayingUsernames.contains(_seats[i].username)) i,
    };

    final started = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final screenWidth = MediaQuery.of(context).size.width;
            const cardSpacing = 6.0;
            final maxDialogWidth = screenWidth * 0.9;
            final cardWidth = (maxDialogWidth - cardSpacing * (7 - 1)) / 7;
            final dialogWidth =
                _seats.length * cardWidth + (_seats.length - 1) * cardSpacing;

            return AlertDialog(
              title: const Text('Тоглох тоглогчдыг сонгоно уу.'),
              content: SizedBox(
                width: dialogWidth,
                height: 220,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Сонгосон: ${selectedIndices.length} (хамгийн багадаа 2)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < _seats.length; i++) ...[
                            SizedBox(
                              width: cardWidth,
                              height: 150,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (selectedIndices.contains(i)) {
                                      selectedIndices.remove(i);
                                    } else {
                                      selectedIndices.add(i);
                                    }
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 0, vertical: 4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selectedIndices.contains(i)
                                          ? Colors.blue
                                          : Colors.grey,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Builder(
                                            builder: (context) {
                                              final photoUrl =
                                                  _seats[i].photoUrl;
                                              if (photoUrl != null &&
                                                  photoUrl.isNotEmpty) {
                                                return Image.network(
                                                  photoUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (context, _, __) {
                                                    return Image.asset(
                                                      'assets/13.jpg',
                                                      fit: BoxFit.cover,
                                                    );
                                                  },
                                                );
                                              }
                                              return Image.asset(
                                                'assets/13.jpg',
                                                fit: BoxFit.cover,
                                              );
                                            },
                                          ),
                                        ),
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.black
                                                      .withOpacity(0.05),
                                                  Colors.black.withOpacity(0.7),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (selectedIndices.contains(i))
                                          Positioned(
                                            top: 6,
                                            left: 6,
                                            child: CircleAvatar(
                                              radius: 14,
                                              backgroundColor: Colors.blue,
                                              child: const Icon(
                                                Icons.check,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          left: 8,
                                          right: 8,
                                          bottom: 6,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _seats[i].displayName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                _seats[i].username,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (i != _seats.length - 1)
                              const SizedBox(width: cardSpacing),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: selectedIndices.length < 2
                              ? null
                              : () {
                                  this.setState(() {
                                    _activePlayingUsernames
                                      ..clear()
                                      ..addAll(selectedIndices.map(
                                          (index) => _seats[index].username));
                                  });
                                  Navigator.of(context).pop(true);
                                },
                          child: const Text('Тоглолт Эхлүүл'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || started != true) return;

    setState(() {
      _penaltyFiveUsernames.clear();
    });

    for (final seat in _seats) {
      if (!_activePlayingUsernames.contains(seat.username)) {
        _roundScoreControllers[seat.username]?.clear();
      }
    }

    _focusFirstActiveScoreField();
  }

  List<String> _activePlayersInSeatOrder() {
    return _seats
        .where((seat) => _activePlayingUsernames.contains(seat.username))
        .map((seat) => seat.username)
        .toList();
  }

  void _focusFirstActiveScoreField() {
    if (!_areAllSeatChoicesMade()) return;
    final activePlayers = _activePlayersInSeatOrder();
    if (activePlayers.length < 2) return;
    if (activePlayers.isEmpty) return;
    final firstFocus = _roundScoreFocusNodes[activePlayers.first];
    if (firstFocus == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      firstFocus.requestFocus();
    });
  }

  Future<void> _onRoundScoreSubmitted(String username) async {
    if (!_activePlayingUsernames.contains(username)) return;
    if (!_areAllSeatChoicesMade()) return;

    final controller = _roundScoreControllers[username];
    final rawText = controller?.text.trim() ?? '';
    if (rawText.isEmpty || rawText == '0') {
      controller?.text = '5';
      controller?.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
      if (!_penaltyFiveUsernames.contains(username)) {
        setState(() {
          _penaltyFiveUsernames.add(username);
        });
      }
    } else if (_penaltyFiveUsernames.contains(username)) {
      setState(() {
        _penaltyFiveUsernames.remove(username);
      });
    }

    final activePlayers = _activePlayersInSeatOrder();
    final currentIndex = activePlayers.indexOf(username);
    if (currentIndex == -1) return;

    if (currentIndex < activePlayers.length - 1) {
      final nextFocus = _roundScoreFocusNodes[activePlayers[currentIndex + 1]];
      nextFocus?.requestFocus();
      return;
    }

    await _completeScoreEntryAndPromptNextRoundPlayers();
  }

  Future<void> _completeScoreEntryAndPromptNextRoundPlayers() async {
    if (!_areAllSeatChoicesMade()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Бүх тоглогч дээр ✅ эсвэл ❌ сонгоно уу.')),
      );
      return;
    }

    final activePlayers = _activePlayersInSeatOrder();
    if (activePlayers.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Хамгийн багадаа 2 тоглогч тоглоно.')),
      );
      return;
    }

    final updatedSeats = List<_MuushigSeat>.from(_seats);
    int distributedTotal = 0;
    for (int i = 0; i < updatedSeats.length; i++) {
      final seat = updatedSeats[i];
      final isPlaying = _activePlayingUsernames.contains(seat.username);
      if (!isPlaying) {
        updatedSeats[i] = seat.copyWith(
          roundScoreText: '-',
          isRoundPenaltyFive: false,
        );
        continue;
      }

      final controller = _roundScoreControllers[seat.username];
      final rawText = controller?.text.trim() ?? '';
      final parsedScore = int.tryParse(rawText) ?? 0;
      final isPenaltyFive = _penaltyFiveUsernames.contains(seat.username) ||
          rawText.isEmpty ||
          rawText == '0';
      if (!isPenaltyFive) {
        distributedTotal += parsedScore;
      }

      final currentTotal = int.tryParse(seat.totalScoreText) ?? 0;
      final rawNextTotal =
          isPenaltyFive ? currentTotal + 5 : currentTotal - parsedScore;
      final nextTotal = rawNextTotal <= 0 ? 0 : rawNextTotal;

      updatedSeats[i] = seat.copyWith(
        roundScoreText: (isPenaltyFive ? 5 : parsedScore).toString(),
        totalScoreText: nextTotal.toString(),
        bombs: isPenaltyFive ? seat.bombs + 1 : seat.bombs,
        isRoundPenaltyFive: isPenaltyFive,
      );
    }

    if (distributedTotal != 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Тоглож байгаа тоглогчдын онооны нийлбэр 5 байх ёстой (одоогоор $distributedTotal).'),
        ),
      );
      return;
    }

    final finishedIndices = <int>[];
    for (int i = 0; i < updatedSeats.length; i++) {
      final total = int.tryParse(updatedSeats[i].totalScoreText) ?? 0;
      if (total <= 0) {
        finishedIndices.add(i);
      }
    }

    int? winnerIndex;
    if (finishedIndices.length == 1) {
      winnerIndex = finishedIndices.first;
    } else if (finishedIndices.length > 1) {
      winnerIndex = await _showFirstFinisherDialog(finishedIndices);
      if (winnerIndex == null) return;
    }

    setState(() {
      if (winnerIndex != null) {
        updatedSeats[winnerIndex] = updatedSeats[winnerIndex]
            .copyWith(wins: updatedSeats[winnerIndex].wins + 1);
        _applySettlementForWinner(updatedSeats, winnerIndex);
      }

      _seats = updatedSeats;

      for (final controller in _roundScoreControllers.values) {
        controller.clear();
      }
      _penaltyFiveUsernames.clear();
      _roundPlayChoices.clear();
      _activePlayingUsernames.clear();
    });

    if (winnerIndex != null) {
      await _advanceAfterWinner();
    }
  }

  Future<int?> _showFirstFinisherDialog(List<int> candidateSeatIndices) async {
    int? selectedWinnerSeatIndex;

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final screenWidth = MediaQuery.of(context).size.width;
            const cardSpacing = 6.0;
            final maxDialogWidth = screenWidth * 0.9;
            final cardWidth = (maxDialogWidth - cardSpacing * (7 - 1)) / 7;
            final dialogWidth = candidateSeatIndices.length * cardWidth +
                (candidateSeatIndices.length - 1) * cardSpacing;

            return AlertDialog(
              title: const Text('Хэн нь түрүүлсэн бэ?'),
              content: SizedBox(
                width: dialogWidth,
                height: 220,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < candidateSeatIndices.length; i++) ...[
                      SizedBox(
                        width: cardWidth,
                        height: 150,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedWinnerSeatIndex = candidateSeatIndices[i];
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 0, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selectedWinnerSeatIndex ==
                                        candidateSeatIndices[i]
                                    ? Colors.blue
                                    : Colors.grey,
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Builder(
                                      builder: (context) {
                                        final photoUrl =
                                            _seats[candidateSeatIndices[i]]
                                                .photoUrl;
                                        if (photoUrl != null &&
                                            photoUrl.isNotEmpty) {
                                          return Image.network(
                                            photoUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, _, __) {
                                              return Image.asset(
                                                'assets/13.jpg',
                                                fit: BoxFit.cover,
                                              );
                                            },
                                          );
                                        }
                                        return Image.asset(
                                          'assets/13.jpg',
                                          fit: BoxFit.cover,
                                        );
                                      },
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withOpacity(0.05),
                                            Colors.black.withOpacity(0.7),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (selectedWinnerSeatIndex ==
                                      candidateSeatIndices[i])
                                    const Positioned(
                                      top: 6,
                                      left: 6,
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: Colors.blue,
                                        child: Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    left: 8,
                                    right: 8,
                                    bottom: 6,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _seats[candidateSeatIndices[i]]
                                              .displayName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          _seats[candidateSeatIndices[i]]
                                              .username,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (i != candidateSeatIndices.length - 1)
                        const SizedBox(width: cardSpacing),
                    ],
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: selectedWinnerSeatIndex == null
                      ? null
                      : () =>
                          Navigator.of(context).pop(selectedWinnerSeatIndex),
                  child: const Text('Ялагчийг батлах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showGameWinnerDialog(_MuushigSeat winnerSeat) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолт дууслаа'),
          content: Text('${winnerSeat.displayName} түрүүлж хожлоо.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Хаах'),
            ),
          ],
        );
      },
    );
  }

  void _setSeatPlayingStatus(String username, bool shouldPlay) {
    final currentChoice = _roundPlayChoices[username];
    if (currentChoice == shouldPlay) return;

    setState(() {
      _roundPlayChoices[username] = shouldPlay;
      if (shouldPlay) {
        _activePlayingUsernames.add(username);
      } else {
        _activePlayingUsernames.remove(username);
        _roundScoreControllers[username]?.clear();
        _penaltyFiveUsernames.remove(username);
      }
    });

    if (_areAllSeatChoicesMade() && _activePlayingUsernames.length >= 2) {
      _focusFirstActiveScoreField();
    }
  }

  Widget _buildSeatCard(int index, _MuushigSeat seat, double blockWidth) {
    final playChoice = _roundPlayChoices[seat.username];
    final isPlaying = playChoice == true;
    final isRestingSelected = playChoice == false;
    final activePlayers = _activePlayersInSeatOrder();
    final activeIndex = activePlayers.indexOf(seat.username);
    final isLastActive =
        activeIndex != -1 && activeIndex == activePlayers.length - 1;
    const verticalGap = 6.0;
    final imageSide = blockWidth - 16;

    return SizedBox(
      width: blockWidth,
      child: Card(
        elevation: 0,
        color: const Color(0xFFCC6046),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isPlaying
                ? Colors.green
                : (isRestingSelected ? Colors.yellow : Colors.white),
            width: 5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: imageSide,
                    height: imageSide,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          (seat.photoUrl != null && seat.photoUrl!.isNotEmpty)
                              ? Image.network(
                                  seat.photoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, _, __) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.28),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        size: imageSide * 0.62,
                                        color: const Color(0xFF8E2F1E),
                                      ),
                                    );
                                  },
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.28),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    size: imageSide * 0.62,
                                    color: const Color(0xFF8E2F1E),
                                  ),
                                ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF7A2E16),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: verticalGap),
              Text(
                seat.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              Text(
                seat.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: verticalGap),
              _buildRightScoreCell(
                title: 'Нийт',
                value: seat.totalScoreText,
              ),
              const SizedBox(height: verticalGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 22),
                      const SizedBox(width: 3),
                      Text(
                        seat.wins.toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('💣', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 3),
                      Text(
                        'x ${seat.bombs}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '₮',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    seat.money.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      color: seat.money < 0 ? Colors.black : Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: verticalGap),
              _buildRoundScoreCell(
                seat: seat,
                isPlaying: isPlaying,
                isRestingSelected: isRestingSelected,
                isLastActive: isLastActive,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoundScoreCell({
    required _MuushigSeat seat,
    required bool isPlaying,
    required bool isRestingSelected,
    required bool isLastActive,
  }) {
    final isPenaltyFive = _penaltyFiveUsernames.contains(seat.username);
    final canStartRound =
        _areAllSeatChoicesMade() && _activePlayingUsernames.length >= 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color:
                  isPlaying ? const Color(0xFFF4E3D6) : const Color(0xFFE6D9CF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFB34A33),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Text(
                  'Оноо',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 1),
                SizedBox(
                  width: 56,
                  height: 56,
                  child: TextField(
                    controller: _roundScoreControllers[seat.username],
                    focusNode: _roundScoreFocusNodes[seat.username],
                    enabled: isPlaying && canStartRound,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    textInputAction: isLastActive
                        ? TextInputAction.done
                        : TextInputAction.next,
                    onSubmitted: isPlaying
                        ? (_) => _onRoundScoreSubmitted(seat.username)
                        : null,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: isPlaying ? '0' : '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 48,
                      height: 1,
                    ).copyWith(
                      color: isPenaltyFive ? Colors.red : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            InkWell(
              onTap: () => _setSeatPlayingStatus(seat.username, true),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isPlaying ? Colors.green : Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.green,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.check,
                  size: 17,
                  color: isPlaying ? Colors.white : Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _setSeatPlayingStatus(seat.username, false),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isRestingSelected ? Colors.red : Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.red,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.close,
                  size: 17,
                  color: isRestingSelected ? Colors.white : Colors.red,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRightScoreCell({required String title, required String value}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFB34A33),
          width: 2,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 64,
                    color: Colors.black,
                    height: 0.95,
                    shadows: [
                      Shadow(
                        color: Colors.black38,
                        offset: Offset(0.6, 0.6),
                        blurRadius: 0.8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_playerOrderSelected &&
        _selectedProfilesLoaded &&
        _seats.length >= 3 &&
        _seats.length <= 7 &&
        ModalRoute.of(context)?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showPlayerOrderDialog(
          _seats.map((seat) => seat.username).toList(),
          _seats.map((seat) => seat.displayName).toList(),
          _seats.map((seat) => seat.photoUrl).toList(),
          (orderedIndices) {
            setState(() {
              final previousSeats = List<_MuushigSeat>.from(_seats);
              _seats =
                  orderedIndices.map((index) => previousSeats[index]).toList();
              _playerOrderSelected = true;
            });
          },
        );
      });
    }

    return WillPopScope(
      onWillPop: () async {
        if (!mounted) return false;
        return _showExitReportDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF9D2F2F),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  if (!mounted) return;
                  await _showExitReportAndFinish();
                },
              ),
              const SizedBox(width: 8),
              const Text(
                'Муушиг',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _showPlayerActionInfo,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.remove, size: 20),
              ),
              const SizedBox(width: 4),
              Text('Тоглогч: ${_seats.length}',
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: _showPlayerActionInfo,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.add, size: 20),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(36, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  _isBoltMode
                      ? (_isMiddleBoltMode
                          ? 'Дундын боолт №$_roundNumber'
                          : 'Боолт №$_roundNumber')
                      : 'Тоглолтын №$_roundNumber',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
              if (_canTransferRegistrar)
                IconButton(
                  tooltip: 'Тоглолт бүртгэх эрх шилжүүлэх',
                  onPressed: _transferRegistrarRole,
                  icon: const Icon(Icons.keyboard),
                ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: _showMuushigSettingsDialog,
              ),
            ],
          ),
          elevation: 0,
          backgroundColor: const Color(0xFFE7DDD4),
          foregroundColor: Colors.black87,
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final blockWidth = ((constraints.maxWidth - spacing * 5) / 6)
                      .clamp(150.0, 220.0);

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(_seats.length, (index) {
                        return Padding(
                          padding: EdgeInsets.only(
                            right: index == _seats.length - 1 ? 0 : spacing,
                          ),
                          child:
                              _buildSeatCard(index, _seats[index], blockWidth),
                        );
                      }),
                    ),
                  );
                },
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MuushigSeat {
  final String? userId;
  final String username;
  final String displayName;
  final String? photoUrl;
  final String roundScoreText;
  final String totalScoreText;
  final int wins;
  final int money;
  final int bombs;
  final bool isRoundPenaltyFive;

  const _MuushigSeat({
    this.userId,
    required this.username,
    required this.displayName,
    this.photoUrl,
    required this.roundScoreText,
    required this.totalScoreText,
    required this.wins,
    required this.money,
    required this.bombs,
    required this.isRoundPenaltyFive,
  });

  _MuushigSeat copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? photoUrl,
    String? roundScoreText,
    String? totalScoreText,
    int? wins,
    int? money,
    int? bombs,
    bool? isRoundPenaltyFive,
  }) {
    return _MuushigSeat(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      roundScoreText: roundScoreText ?? this.roundScoreText,
      totalScoreText: totalScoreText ?? this.totalScoreText,
      wins: wins ?? this.wins,
      money: money ?? this.money,
      bombs: bombs ?? this.bombs,
      isRoundPenaltyFive: isRoundPenaltyFive ?? this.isRoundPenaltyFive,
    );
  }
}
