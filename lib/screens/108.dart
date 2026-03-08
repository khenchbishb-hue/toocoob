import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:toocoob/screens/player_selection_page.dart';

class Game108Page extends StatefulWidget {
  const Game108Page({
    super.key,
    this.selectedUserIds = const [],
  });

  final List<String> selectedUserIds;

  @override
  State<Game108Page> createState() => _Game108PageState();
}

class _Game108PageState extends State<Game108Page> {
  int _roundNumber = 1;
  static const int _targetWinnerScore = 108;
  static const Color _tableOrange = Color(0xFFE67E22);

  late final List<String> _selectedUserIdsSnapshot;
  bool _selectedProfilesLoaded = true;
  bool _playerOrderSelected = false;
  List<_Game108Seat> _seats = [];
  List<_Game108Seat> _orderedSeats = [];
  final Set<String> _restingSeatKeys = <String>{};
  final Set<String> _roundSubmittedSeatKeys = <String>{};
  final Map<String, TextEditingController> _scoreInputControllers = {};
  final Map<String, FocusNode> _scoreInputFocusNodes = {};

  int get _playerCount => _selectedUserIdsSnapshot.isNotEmpty
      ? _selectedUserIdsSnapshot.length
      : _seats
          .where((seat) => seat.userId != null && seat.userId!.isNotEmpty)
          .length;

  @override
  void initState() {
    super.initState();
    _selectedUserIdsSnapshot = List<String>.from(widget.selectedUserIds);

    _seats = _buildSeatSlots(_selectedUserIdsSnapshot);
    _orderedSeats = _activeSeatsFrom(_seats);
    _syncScoreInputs(_orderedSeats);
    _ensureFocusOnActiveScoreField();
    if (_selectedUserIdsSnapshot.isNotEmpty) {
      _selectedProfilesLoaded = false;
      _loadSelectedUserProfiles();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPlayerOrderDialogIfNeeded();
      });
    }
  }

  List<_Game108Seat> _activeSeatsFrom(List<_Game108Seat> source) {
    if (_selectedUserIdsSnapshot.isNotEmpty) {
      final count = _selectedUserIdsSnapshot.length.clamp(0, source.length);
      final withUser = source
          .where((seat) => seat.userId != null && seat.userId!.isNotEmpty)
          .toList();
      return withUser.take(count).toList();
    }
    final withUser = source
        .where((seat) => seat.userId != null && seat.userId!.isNotEmpty)
        .toList();
    if (withUser.isNotEmpty) return withUser;
    return source.take(5).toList();
  }

  List<_Game108Seat> _buildSeatSlots(List<String> selectedUserIds) {
    final base = List<_Game108Seat>.generate(7, (index) {
      return _emptySeat();
    });

    for (int i = 0; i < selectedUserIds.length && i < base.length; i++) {
      base[i] = base[i].copyWith(userId: selectedUserIds[i]);
    }

    return base;
  }

  _Game108Seat _emptySeat() {
    return const _Game108Seat(
      displayName: '',
      username: '',
      score: 0,
      wins: 0,
      money: 0,
      roundScore: 0,
      isEliminated: false,
    );
  }

  String _seatKey(_Game108Seat seat) {
    final userId = seat.userId;
    if (userId != null && userId.isNotEmpty) return 'id:$userId';
    return 'u:${seat.username}';
  }

  bool _isPlaceholderSeat(_Game108Seat seat) {
    return seat.userId == null &&
        seat.username.isEmpty &&
        seat.displayName.isEmpty &&
        seat.score == 0 &&
        seat.wins == 0 &&
        seat.money == 0 &&
        seat.roundScore == 0 &&
        !seat.isEliminated;
  }

  void _syncScoreInputs(List<_Game108Seat> seats) {
    final keys = seats.map(_seatKey).toSet();

    for (final key in keys) {
      _scoreInputControllers.putIfAbsent(key, () => TextEditingController());
      _scoreInputFocusNodes.putIfAbsent(key, () => FocusNode());
    }

    final removedControllers = _scoreInputControllers.keys
        .where((key) => !keys.contains(key))
        .toList(growable: false);
    for (final key in removedControllers) {
      _scoreInputControllers.remove(key)?.dispose();
    }

    final removedFocusNodes = _scoreInputFocusNodes.keys
        .where((key) => !keys.contains(key))
        .toList(growable: false);
    for (final key in removedFocusNodes) {
      _scoreInputFocusNodes.remove(key)?.dispose();
    }
  }

  void _ensureFocusOnActiveScoreField({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activeRoute = ModalRoute.of(context);
      if (activeRoute != null && !activeRoute.isCurrent) return;

      final scoringSeats = _currentScoringSeats();
      if (scoringSeats.isEmpty) return;
      final scoringKeys = scoringSeats.map(_seatKey).toList(growable: false);

      final hasFocusedScoring = scoringKeys.any(
        (key) => _scoreInputFocusNodes[key]?.hasFocus ?? false,
      );
      if (!force && hasFocusedScoring) return;

      final targetKey = scoringKeys.first;
      final targetNode = _scoreInputFocusNodes[targetKey];
      final targetController = _scoreInputControllers[targetKey];
      if (targetNode == null || targetController == null) return;

      targetNode.requestFocus();
      targetController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: targetController.text.length,
      );
    });
  }

  List<_Game108Seat> _rebuildOrderedSeats(List<_Game108Seat> source) {
    final active = _activeSeatsFrom(source).take(7).toList();
    if (_orderedSeats.isEmpty) return active;

    final byKey = {for (final seat in active) _seatKey(seat): seat};
    final List<_Game108Seat> rebuilt = [];

    for (final seat in _orderedSeats) {
      final key = _seatKey(seat);
      final found = byKey.remove(key);
      if (found != null) rebuilt.add(found);
    }

    rebuilt.addAll(byKey.values);
    return rebuilt;
  }

  void _updateSeatByKey(
      String key, _Game108Seat Function(_Game108Seat) update) {
    _seats = _seats.map((seat) {
      if (_seatKey(seat) == key) return update(seat);
      return seat;
    }).toList();
  }

  List<_Game108Seat> _activeNotEliminatedSeats() {
    return _orderedSeats.where((seat) => !seat.isEliminated).toList();
  }

  bool _isSeatResting(_Game108Seat seat) {
    return _restingSeatKeys.contains(_seatKey(seat));
  }

  int _restingCountFor(List<_Game108Seat> activeSeats) {
    if (activeSeats.length <= 5) return 0;
    return activeSeats.length - 5;
  }

  List<_Game108Seat> _currentScoringSeats() {
    final active = _activeNotEliminatedSeats();
    return active
        .where((seat) => !_restingSeatKeys.contains(_seatKey(seat)))
        .toList();
  }

  void _initializeRestingByOrder() {
    final active = _activeNotEliminatedSeats();
    final restingCount = _restingCountFor(active);
    _restingSeatKeys
      ..clear()
      ..addAll(active.take(restingCount).map(_seatKey));
    _roundSubmittedSeatKeys.clear();
  }

  void _recalculateRestingAfterRound() {
    final active = _activeNotEliminatedSeats();
    final restingCount = _restingCountFor(active);
    if (restingCount == 0) {
      _restingSeatKeys.clear();
      return;
    }

    final List<_Game108Seat> eligible = _currentScoringSeats()
        .where((seat) => seat.score >= 0)
        .toList(growable: false)
      ..sort((a, b) {
        final roundScoreCompare = a.roundScore.compareTo(b.roundScore);
        if (roundScoreCompare != 0) return roundScoreCompare;
        final aIndex =
            _orderedSeats.indexWhere((s) => _seatKey(s) == _seatKey(a));
        final bIndex =
            _orderedSeats.indexWhere((s) => _seatKey(s) == _seatKey(b));
        return aIndex.compareTo(bIndex);
      });

    final selected = eligible.take(restingCount).map(_seatKey).toSet();
    _restingSeatKeys
      ..clear()
      ..addAll(selected);
  }

  Future<void> _onTopScoreSubmitted(_Game108Seat seat) async {
    final key = _seatKey(seat);
    final controller = _scoreInputControllers[key];
    if (controller == null) return;
    final roundInputCandidates = _currentScoringSeats();
    final roundInputKeys = roundInputCandidates.map(_seatKey).toSet();
    final currentRoundIndex =
        roundInputCandidates.indexWhere((s) => _seatKey(s) == key);

    final currentSeat = _seats.firstWhere(
      (s) => _seatKey(s) == key,
      orElse: () => seat,
    );
    if (currentSeat.isEliminated || _isSeatResting(currentSeat)) {
      controller.clear();
      return;
    }

    final input = controller.text.trim();
    final parsed = input.isEmpty ? 0 : int.tryParse(input);
    if (parsed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Оноонд дурын бүхэл тоо оруулна.'),
          ),
        );
      }
      return;
    }

    setState(() {
      _updateSeatByKey(key, (current) {
        var nextScore = current.score + parsed;
        var eliminated = current.isEliminated;

        if (nextScore > _targetWinnerScore) {
          eliminated = true;
        } else if (nextScore == _targetWinnerScore) {
          nextScore = 54;
        }

        return current.copyWith(
          roundScore: parsed,
          score: nextScore,
          isEliminated: eliminated,
        );
      });
      _orderedSeats = _rebuildOrderedSeats(_seats);
    });

    controller.clear();

    _roundSubmittedSeatKeys.add(key);

    final activePlayers = _activeNotEliminatedSeats();
    if (activePlayers.length == 1) {
      await _handleWinner(activePlayers.first);
      return;
    }

    if (roundInputKeys.isNotEmpty &&
        _roundSubmittedSeatKeys.containsAll(roundInputKeys)) {
      setState(() {
        _recalculateRestingAfterRound();
        _roundSubmittedSeatKeys.clear();
      });
      _ensureFocusOnActiveScoreField(force: true);
      return;
    }

    if (currentRoundIndex != -1 &&
        currentRoundIndex + 1 < roundInputCandidates.length) {
      final nextKey = _seatKey(roundInputCandidates[currentRoundIndex + 1]);
      _scoreInputFocusNodes[nextKey]?.requestFocus();
      return;
    }

    _ensureFocusOnActiveScoreField(force: true);
  }

  Future<void> _handleWinner(_Game108Seat winner) async {
    final winnerKey = _seatKey(winner);

    setState(() {
      _seats = _seats
          .map((seat) => _seatKey(seat) == winnerKey
              ? seat.copyWith(wins: seat.wins + 1)
              : seat)
          .toList();

      _seats = _seats
          .map((seat) => seat.copyWith(
                score: 0,
                roundScore: 0,
                isEliminated: false,
              ))
          .toList();

      _orderedSeats = _rebuildOrderedSeats(_seats);
      _playerOrderSelected = false;
      _roundNumber += 1;
      _restingSeatKeys.clear();
      _roundSubmittedSeatKeys.clear();
      _syncScoreInputs(_orderedSeats);
    });

    for (final controller in _scoreInputControllers.values) {
      controller.clear();
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Тоглолт дууслаа'),
        content: Text('${winner.displayName} ялагч боллоо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ОК'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPlayerOrderDialogIfNeeded();
    });
  }

  Future<void> _loadSelectedUserProfiles() async {
    final updatedSeats = List<_Game108Seat>.from(_seats);

    for (int i = 0; i < updatedSeats.length; i++) {
      final seat = updatedSeats[i];
      final userId = seat.userId;
      if (userId == null || userId.isEmpty) continue;

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        final data = snapshot.data();
        if (data == null) continue;

        final fetchedUsername = (data['username'] as String?)?.trim();
        final fetchedDisplayName = (data['displayName'] as String?)?.trim();
        final fetchedPhotoUrl = (data['photoUrl'] as String?)?.trim();

        updatedSeats[i] = seat.copyWith(
          username: fetchedUsername != null && fetchedUsername.isNotEmpty
              ? fetchedUsername
              : seat.username,
          displayName:
              fetchedDisplayName != null && fetchedDisplayName.isNotEmpty
                  ? fetchedDisplayName
                  : seat.displayName,
          photoUrl: fetchedPhotoUrl != null && fetchedPhotoUrl.isNotEmpty
              ? fetchedPhotoUrl
              : seat.photoUrl,
        );
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _seats = updatedSeats;
      _orderedSeats = _rebuildOrderedSeats(updatedSeats);
      _selectedProfilesLoaded = true;
      _syncScoreInputs(_orderedSeats);
    });
    _ensureFocusOnActiveScoreField();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPlayerOrderDialogIfNeeded();
    });
  }

  Future<void> _showPlayerOrderDialogIfNeeded() async {
    if (!mounted || _playerOrderSelected || !_selectedProfilesLoaded) return;

    final activeSeats = _activeSeatsFrom(_seats);
    if (activeSeats.length < 2) return;

    final cappedSeats = activeSeats.take(7).toList();
    final playerUserNames = cappedSeats.map((seat) => seat.username).toList();
    final playerDisplayNames =
        cappedSeats.map((seat) => seat.displayName).toList();

    await showPlayerOrderDialog(
      playerUserNames,
      playerDisplayNames,
      (orderedIndices) {
        if (!mounted) return;
        setState(() {
          _orderedSeats = [for (final i in orderedIndices) cappedSeats[i]];
          _playerOrderSelected = true;
          _initializeRestingByOrder();
          _syncScoreInputs(_orderedSeats);
        });
        _ensureFocusOnActiveScoreField(force: true);
      },
      onCancelled: () {
        if (!mounted) return;
        setState(() {
          _orderedSeats = cappedSeats;
          _playerOrderSelected = true;
          _initializeRestingByOrder();
          _syncScoreInputs(_orderedSeats);
        });
        _ensureFocusOnActiveScoreField(force: true);
      },
    );
  }

  Future<void> showPlayerOrderDialog(
    List<String> playerUserNames,
    List<String> playerDisplayNames,
    void Function(List<int>) onOrderConfirmed, {
    VoidCallback? onCancelled,
  }) async {
    List<int?> selectedOrder = List.filled(playerDisplayNames.length, null);
    int currentOrder = 1;
    await showDialog(
      context: context,
      barrierDismissible: false,
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
                                          child: Image.asset(
                                            'assets/13.jpg',
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return Container(
                                                color: Colors.blue[200],
                                                alignment: Alignment.center,
                                                child: Icon(
                                                  Icons.person,
                                                  size: 36,
                                                  color: Colors.blue[700],
                                                ),
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
                            onCancelled?.call();
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

  void _showPlayerActionInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            '108 тоглоомын тоглогч +/- логик дараагийн алхамд холбогдоно.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onRemovePlayerPressed() async {
    final currentPlayers = _orderedSeats
        .where((seat) => seat.userId != null && seat.userId!.isNotEmpty)
        .toList(growable: false);

    if (currentPlayers.length <= 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Хамгийн багадаа 2 тоглогч үлдэнэ.')),
        );
      }
      return;
    }

    final maxRemovable = currentPlayers.length - 2;
    await showPlayerRemoveDialog(
      currentPlayers,
      maxRemovable,
      (removeIndices) {
        if (removeIndices.isEmpty) return;

        setState(() {
          final removeKeys = removeIndices
              .where((i) => i >= 0 && i < currentPlayers.length)
              .map((i) => _seatKey(currentPlayers[i]))
              .toSet();

          final removeUserIds = currentPlayers
              .where((seat) => removeKeys.contains(_seatKey(seat)))
              .map((seat) => seat.userId)
              .whereType<String>()
              .toSet();

          for (int i = 0; i < _seats.length; i++) {
            if (removeKeys.contains(_seatKey(_seats[i]))) {
              _seats[i] = _emptySeat();
            }
          }

          _selectedUserIdsSnapshot
              .removeWhere((id) => removeUserIds.contains(id));

          _restingSeatKeys.removeWhere(removeKeys.contains);
          _roundSubmittedSeatKeys.removeWhere(removeKeys.contains);

          _orderedSeats = _rebuildOrderedSeats(_seats);
          _syncScoreInputs(_orderedSeats);
        });
        _ensureFocusOnActiveScoreField(force: true);
      },
    );
  }

  Future<void> showPlayerRemoveDialog(
    List<_Game108Seat> players,
    int maxRemovable,
    void Function(List<int>) onRemove,
  ) async {
    final Set<int> selectedIndices = {};
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final screenWidth = MediaQuery.of(context).size.width;
            const cardSpacing = 6.0;
            final maxDialogWidth = screenWidth * 0.9;
            final cardWidth = (maxDialogWidth - cardSpacing * (7 - 1)) / 7;
            final dialogWidth = players.isEmpty
                ? cardWidth
                : players.length * cardWidth +
                    (players.length - 1) * cardSpacing;

            return AlertDialog(
              title: const Text('Хасах тоглогч сонгох'),
              content: SizedBox(
                width: dialogWidth,
                height: 220,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Сонгосон: ${selectedIndices.length}/$maxRemovable (хамгийн багадаа 2 тоглогч үлдэнэ)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < players.length; i++) ...[
                            SizedBox(
                              width: cardWidth,
                              height: 150,
                              child: GestureDetector(
                                onTap: () {
                                  final isSelected =
                                      selectedIndices.contains(i);
                                  final canSelectMore = isSelected ||
                                      selectedIndices.length < maxRemovable;
                                  if (!canSelectMore) return;
                                  setState(() {
                                    if (isSelected) {
                                      selectedIndices.remove(i);
                                    } else {
                                      selectedIndices.add(i);
                                    }
                                  });
                                },
                                child: Opacity(
                                  opacity: selectedIndices.contains(i) ||
                                          selectedIndices.length < maxRemovable
                                      ? 1.0
                                      : 0.45,
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
                                            child: Image.asset(
                                              'assets/13.jpg',
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, _, __) {
                                                return Container(
                                                  color: Colors.blue[200],
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    Icons.person,
                                                    size: 36,
                                                    color: Colors.blue[700],
                                                  ),
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
                                                    Colors.black
                                                        .withOpacity(0.7),
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
                                                  players[i].displayName.isEmpty
                                                      ? 'Тоглогч ${i + 1}'
                                                      : players[i].displayName,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  players[i].username,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                            ),
                            if (i != players.length - 1)
                              const SizedBox(width: cardSpacing),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: selectedIndices.isNotEmpty
                      ? () {
                          final ordered = selectedIndices.toList()..sort();
                          onRemove(ordered);
                          Navigator.of(context).pop();
                        }
                      : null,
                  child: const Text('Хасах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _onAddPlayerPressed() async {
    final existingUserIds = _seats
        .where((seat) => seat.userId != null && seat.userId!.isNotEmpty)
        .map((seat) => seat.userId!)
        .toList(growable: false);

    if (existingUserIds.length >= 7) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Хамгийн ихдээ 7 тоглогчтой байна.')),
        );
      }
      return;
    }

    final selectedToAdd = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: existingUserIds,
        ),
      ),
    );

    if (selectedToAdd == null || selectedToAdd.isEmpty) return;

    final toAdd = <String>[];
    for (final userId in selectedToAdd) {
      if (existingUserIds.contains(userId) || toAdd.contains(userId)) continue;
      toAdd.add(userId);
      if (existingUserIds.length + toAdd.length >= 7) break;
    }
    if (toAdd.isEmpty) return;

    setState(() {
      for (final userId in toAdd) {
        if (!_selectedUserIdsSnapshot.contains(userId)) {
          _selectedUserIdsSnapshot.add(userId);
        }

        final emptyIndex = _seats
            .indexWhere((seat) => seat.userId == null || seat.userId!.isEmpty);
        if (emptyIndex == -1) continue;

        _seats[emptyIndex] = _seats[emptyIndex].copyWith(
          userId: userId,
          username: 'u${emptyIndex + 1}',
          displayName: 'Тоглогч ${emptyIndex + 1}',
          score: 0,
          wins: 0,
          money: 0,
          roundScore: 0,
          isEliminated: false,
        );
      }

      _orderedSeats = _rebuildOrderedSeats(_seats);
      _syncScoreInputs(_orderedSeats);
      _selectedProfilesLoaded = false;
    });

    _ensureFocusOnActiveScoreField(force: true);

    await _loadSelectedUserProfiles();
  }

  Future<void> _showSettingsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('108 тохиргоо'),
          content:
              const Text('108 тохиргооны дэлгэрэнгүйг дараагийн алхамд нэмнэ.'),
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

  Widget _buildMainBlock({required _Game108Seat seat, required int slotIndex}) {
    final seatKey = _seatKey(seat);
    final isEliminated = seat.isEliminated;
    final isResting = !isEliminated && _isSeatResting(seat);
    final borderColor = isEliminated
        ? Colors.red
        : (isResting ? Colors.yellow : const Color(0xFFF8EFE7));

    return Card(
      elevation: 0,
      color: _tableOrange,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildTopImageWithIndex(
              seat: seat,
              slotIndex: slotIndex,
              widthFactor: 1,
              badgeRadius: 14,
              badgeFontSize: 14,
            ),
            const SizedBox(height: 6),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 6),
            _buildTotalCell(
              value: seat.score,
              small: false,
              isEliminated: isEliminated,
            ),
            const SizedBox(height: 6),
            _buildBottomMetricsRow(
              seat: seat,
              small: false,
              scoreField: TextField(
                controller: _scoreInputControllers[seatKey],
                focusNode: _scoreInputFocusNodes[seatKey],
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: false,
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  color: Color(0xFF1F1F28),
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '0',
                ),
                enabled: !(isEliminated || isResting),
                onSubmitted: (_) => _onTopScoreSubmitted(seat),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallBlock(
      {required _Game108Seat seat, required int slotIndex}) {
    final isPlaceholder = _isPlaceholderSeat(seat);
    final isEliminated = seat.isEliminated;
    final isResting = !isEliminated && _isSeatResting(seat);
    final borderColor = isEliminated
        ? Colors.red
        : (isResting ? Colors.yellow : const Color(0xFFF8EFE7));

    return Card(
      elevation: 0,
      color: _tableOrange,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: borderColor, width: 5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (isPlaceholder) {
              return const SizedBox.expand();
            }

            final imageSide = (constraints.maxHeight - 10).clamp(24.0, 52.0);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 30,
                  alignment: Alignment.center,
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF7A2E16),
                    child: Text(
                      '${slotIndex + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: imageSide,
                  height: imageSide,
                  child: _buildSquareImageArea(seat),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPlaceholder ? '' : seat.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        isPlaceholder ? '' : seat.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildCompactMetricCell(
                  value: isPlaceholder ? '' : '${seat.score}',
                  compact: true,
                  showTitle: false,
                  width: 98,
                  fullHeight: true,
                  fullHeightScale: 0.6,
                  valueColor: isEliminated ? Colors.red : Colors.black,
                ),
                const SizedBox(width: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Text(
                        isPlaceholder ? '' : '⭐',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 3),
                    _buildCompactMetricCell(
                      value: isPlaceholder ? '' : '${seat.wins}',
                      compact: true,
                      showTitle: false,
                      width: 64,
                      fullHeight: true,
                      fullHeightScale: 0.6,
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Text(
                        isPlaceholder ? '' : '₮',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          height: 0.95,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    _buildCompactMetricCell(
                      value: isPlaceholder ? '' : '${seat.money}',
                      compact: true,
                      showTitle: false,
                      width: 112,
                      fullHeight: true,
                      fullHeightScale: 0.6,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCompactMetricCell({
    String title = '',
    required String value,
    bool compact = false,
    bool showTitle = true,
    double? width,
    bool fullHeight = false,
    double fullHeightScale = 1,
    Color valueColor = Colors.black,
  }) {
    return Container(
      width: width ?? (compact ? 66 : 86),
      height: fullHeight ? double.infinity : null,
      padding: EdgeInsets.symmetric(
        vertical: fullHeight ? 0 : (compact ? 2 : 6),
        horizontal: fullHeight ? 2 : (compact ? 4 : 6),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9C2B8), width: 1.2),
      ),
      child: (fullHeight && !showTitle)
          ? LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: SizedBox(
                    height: constraints.maxHeight * fullHeightScale,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        value,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: constraints.maxHeight,
                          height: 1,
                          color: valueColor,
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showTitle)
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: compact ? 9 : 10)),
                if (showTitle) SizedBox(height: compact ? 1 : 2),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 18 : 28,
                    height: 0.95,
                    color: valueColor,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCompactWinCell({required int wins}) {
    return Container(
      width: 86,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9C2B8), width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '⭐',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(width: 4),
          Text(
            '$wins',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              height: 0.95,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMoneyCell({required int money}) {
    return Container(
      width: 86,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9C2B8), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '₮',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  height: 0.95,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                '$money',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  height: 0.95,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWinMoneyCell({required int wins, required int money}) {
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9C2B8), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '⭐',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              const Text('Хожил',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
              const SizedBox(width: 4),
              Text('$wins',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text('₮$money',
              style:
                  const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildTotalCell({
    required int value,
    required bool small,
    bool isEliminated = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: small ? 3 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEliminated ? Colors.red : const Color(0xFFB34A33),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: small ? 52 : 74,
              height: 0.95,
              color: isEliminated ? Colors.red : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomMetricsRow({
    required _Game108Seat seat,
    required bool small,
    Widget? scoreField,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildRoundScoreCell(
            value: seat.roundScore,
            small: small,
            scoreField: scoreField,
          ),
        ),
        SizedBox(width: small ? 4 : 6),
        Expanded(
          child: _buildWinMoneyCell(
            wins: seat.wins,
            money: seat.money,
            small: small,
          ),
        ),
      ],
    );
  }

  Widget _buildRoundScoreCell({
    required int value,
    required bool small,
    Widget? scoreField,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: small ? 3 : 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9C2B8), width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          scoreField ??
              Text(
                '$value',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: small ? 24 : 30,
                  color: const Color(0xFF1F1F28),
                ),
              ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _scoreInputControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _scoreInputFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Widget _buildWinMoneyCell({
    required int wins,
    required int money,
    required bool small,
  }) {
    final labelStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: small ? 10 : 12,
      color: const Color(0xFF231F20),
    );
    final valueStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: small ? 12 : 15,
      color: const Color(0xFF231F20),
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8,
        vertical: small ? 6 : 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC9C2B8), width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '⭐',
                style: TextStyle(fontSize: small ? 13 : 15),
              ),
              const SizedBox(width: 3),
              Text('$wins', style: valueStyle),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('₮', style: valueStyle),
              const SizedBox(width: 2),
              Text('$money', style: valueStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopImageWithIndex({
    required _Game108Seat seat,
    required int slotIndex,
    required double widthFactor,
    required double badgeRadius,
    required double badgeFontSize,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: _buildSquareImageArea(seat),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: CircleAvatar(
                radius: badgeRadius,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF7A2E16),
                child: Text(
                  '${slotIndex + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: badgeFontSize,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareImageArea(_Game108Seat seat) {
    final borderRadius = BorderRadius.circular(8);
    if (seat.photoUrl != null && seat.photoUrl!.isNotEmpty) {
      final photo = seat.photoUrl!;
      final provider = photo.startsWith('http')
          ? NetworkImage(photo) as ImageProvider
          : AssetImage('assets/$photo');
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image(
          image: provider,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.28),
              borderRadius: borderRadius,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final iconSize = constraints.maxWidth * 0.38;
                return Center(
                  child: Icon(Icons.person,
                      size: iconSize, color: const Color(0xFF8E2F1E)),
                );
              },
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.28),
        borderRadius: borderRadius,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize = constraints.maxWidth * 0.38;
          return Center(
            child: Icon(Icons.person,
                size: iconSize, color: const Color(0xFF8E2F1E)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _tableOrange,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 8),
            const Text(
              '108',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _onRemovePlayerPressed,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.remove, size: 20),
            ),
            const SizedBox(width: 4),
            Text('Тоглогч: $_playerCount',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: _onAddPlayerPressed,
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
              child: Text('Тоглолтын №$_roundNumber',
                  style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsDialog,
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: const Color(0xFFE7DDD4),
        foregroundColor: Colors.black87,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;

            final activeSeats = _orderedSeats.isNotEmpty
                ? _orderedSeats
                : _activeSeatsFrom(_seats).take(7).toList();

            final List<MapEntry<int, _Game108Seat>> topEntries = [];
            final List<MapEntry<int, _Game108Seat>> bottomEntries = [];

            if (activeSeats.length <= 5) {
              for (int i = 0; i < activeSeats.length; i++) {
                topEntries.add(MapEntry(i + 1, activeSeats[i]));
              }
            } else {
              final bottomKeys = <String>{};
              final int bottomCapacity = (activeSeats.length - 5).clamp(1, 2);

              void addBottomByFilter(bool Function(_Game108Seat) test) {
                for (final seat in activeSeats) {
                  if (bottomKeys.length >= bottomCapacity) break;
                  final key = _seatKey(seat);
                  if (bottomKeys.contains(key)) continue;
                  if (!test(seat)) continue;
                  bottomKeys.add(key);
                }
              }

              addBottomByFilter((seat) => seat.isEliminated);
              addBottomByFilter((seat) =>
                  !seat.isEliminated &&
                  _restingSeatKeys.contains(_seatKey(seat)));

              for (int i = activeSeats.length - 1;
                  i >= 0 && bottomKeys.length < bottomCapacity;
                  i--) {
                bottomKeys.add(_seatKey(activeSeats[i]));
              }

              final selectedBottomSeats = <_Game108Seat>[];
              for (final seat in activeSeats) {
                if (bottomKeys.contains(_seatKey(seat))) {
                  selectedBottomSeats.add(seat);
                } else {
                  topEntries.add(MapEntry(topEntries.length + 1, seat));
                }
              }

              for (int i = 0; i < selectedBottomSeats.length; i++) {
                bottomEntries.add(MapEntry(6 + i, selectedBottomSeats[i]));
              }
            }

            if (activeSeats.length <= 5) {
              const emptySeat = _Game108Seat(
                displayName: '',
                username: '',
                score: 0,
                wins: 0,
                money: 0,
                roundScore: 0,
                isEliminated: false,
              );
              bottomEntries
                ..clear()
                ..add(const MapEntry(6, emptySeat))
                ..add(const MapEntry(7, emptySeat));
            }

            return Column(
              children: [
                if (!_selectedProfilesLoaded)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int i = 0; i < 5; i++) ...[
                              Expanded(
                                child: i < topEntries.length
                                    ? _buildMainBlock(
                                        seat: topEntries[i].value,
                                        slotIndex: topEntries[i].key - 1,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (i != 4) const SizedBox(width: gap),
                            ],
                          ],
                        ),
                      ),
                      if (bottomEntries.isNotEmpty) ...[
                        const SizedBox(height: gap),
                        Expanded(
                          flex: 1,
                          child: Row(
                            children: [
                              for (int i = 0;
                                  i < bottomEntries.length;
                                  i++) ...[
                                Expanded(
                                  child: _buildSmallBlock(
                                    seat: bottomEntries[i].value,
                                    slotIndex: bottomEntries[i].key - 1,
                                  ),
                                ),
                                if (i != bottomEntries.length - 1)
                                  const SizedBox(width: gap),
                              ],
                              if (bottomEntries.length == 1)
                                const Expanded(child: SizedBox.shrink()),
                            ],
                          ),
                        ),
                      ] else
                        const SizedBox(height: 0),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Game108Seat {
  const _Game108Seat({
    required this.displayName,
    required this.username,
    required this.score,
    required this.wins,
    required this.money,
    required this.roundScore,
    required this.isEliminated,
    this.userId,
    this.photoUrl,
  });

  final String displayName;
  final String username;
  final int score;
  final int wins;
  final int money;
  final int roundScore;
  final bool isEliminated;
  final String? userId;
  final String? photoUrl;

  _Game108Seat copyWith({
    String? displayName,
    String? username,
    int? score,
    int? wins,
    int? money,
    int? roundScore,
    bool? isEliminated,
    String? userId,
    String? photoUrl,
  }) {
    return _Game108Seat(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      score: score ?? this.score,
      wins: wins ?? this.wins,
      money: money ?? this.money,
      roundScore: roundScore ?? this.roundScore,
      isEliminated: isEliminated ?? this.isEliminated,
      userId: userId ?? this.userId,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
