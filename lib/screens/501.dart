import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:toocoob/screens/statistics_dashboard.dart';
import 'package:toocoob/utils/active_tables_repository.dart';
import 'package:toocoob/utils/game_registrar_transfer.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';
import 'package:toocoob/screens/kinds_of_game.dart';
import 'player_selection_page.dart';

class Game501Page extends StatefulWidget {
  const Game501Page({
    super.key,
    this.selectedUserIds = const [],
    this.currentUserId,
    this.canManageGames = false,
    this.initialSavedSessionId,
    this.autoReturnOnWinner = false,
    this.multiWinsByUserId,
  });

  final List<String> selectedUserIds;
  final String? currentUserId;
  final bool canManageGames;
  final String? initialSavedSessionId;
  final bool autoReturnOnWinner;
  final Map<String, int>? multiWinsByUserId;

  @override
  State<Game501Page> createState() => _Game501PageState();
}

class _Game501PageState extends State<Game501Page> {
  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();
  final ActiveTablesRepository _activeTablesRepo = ActiveTablesRepository();
  static const int _seatCount = 7;
  static const int _minimumActiveSeats = 3;
  static const int _baseScore = 501;

  late final String _sessionId;
  bool _loadingProfiles = false;
  bool _sessionAddedToStatistics = false;
  bool _isBoltMode = false;
  int _normalBasePrice = 5000;
  int _boltBasePrice = 10000;
  int _activeSeatCount = _minimumActiveSeats;
  int _roundNumber = 1;
  int _sessionFinishedGames = 0;
  int _sessionOrdinaryRounds = 0;
  int _sessionBoltRounds = 0;
  String? _currentRegistrarUserId;
  String? _activeSavedSessionId;
  late List<_PlayerSeat> _seats;
  late final List<TextEditingController> _takenPriceControllers;
  late final List<TextEditingController> _playPriceControllers;
  late final List<TextEditingController> _scoreInputControllers;
  late final List<FocusNode> _takenPriceFocusNodes;
  late final List<FocusNode> _playPriceFocusNodes;
  late final List<FocusNode> _scoreInputFocusNodes;
  late final List<List<FocusNode>> _scoreButtonFocusNodes;
  late final List<Set<_ScoreButtonType>> _selectedScoreButtons;
  final Set<int> _autoCorrectSeatIndexes = <int>{};
  int? _activeRecommendedSeatIndex;
  bool _multiAutoReturnTriggered = false;

  bool get _canTransferRegistrar =>
      widget.canManageGames &&
      widget.currentUserId != null &&
      _currentRegistrarUserId == widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _sessionId = '501_${DateTime.now().millisecondsSinceEpoch}';
    _currentRegistrarUserId = widget.currentUserId;
    if (widget.selectedUserIds.isNotEmpty) {
      _activeSeatCount =
          widget.selectedUserIds.length.clamp(_minimumActiveSeats, _seatCount);
    }
    _takenPriceControllers = List<TextEditingController>.generate(
      _seatCount,
      (_) => TextEditingController(),
    );
    _playPriceControllers = List<TextEditingController>.generate(
      _seatCount,
      (_) => TextEditingController(),
    );
    _scoreInputControllers = List<TextEditingController>.generate(
      _seatCount,
      (_) => TextEditingController(),
    );
    _takenPriceFocusNodes = List<FocusNode>.generate(
      _seatCount,
      (_) => FocusNode(),
    );
    _playPriceFocusNodes = List<FocusNode>.generate(
      _seatCount,
      (_) => FocusNode(),
    );
    _scoreInputFocusNodes = List<FocusNode>.generate(
      _seatCount,
      (_) => FocusNode(),
    );
    _scoreButtonFocusNodes = List<List<FocusNode>>.generate(
      _seatCount,
      (_) => List<FocusNode>.generate(_scoreButtons.length, (_) => FocusNode()),
    );
    _selectedScoreButtons = List<Set<_ScoreButtonType>>.generate(
      _seatCount,
      (_) => <_ScoreButtonType>{},
    );
    _seats = List<_PlayerSeat>.generate(
      _seatCount,
      (index) => _PlayerSeat.empty(index + 1),
    );
    _tryRestoreSavedSession();
    if (widget.selectedUserIds.isNotEmpty) {
      _loadSelectedUserProfiles();
    }
  }

  @override
  void dispose() {
    for (final controller in _takenPriceControllers) {
      controller.dispose();
    }
    for (final controller in _playPriceControllers) {
      controller.dispose();
    }
    for (final controller in _scoreInputControllers) {
      controller.dispose();
    }
    for (final focusNode in _takenPriceFocusNodes) {
      focusNode.dispose();
    }
    for (final focusNode in _playPriceFocusNodes) {
      focusNode.dispose();
    }
    for (final focusNode in _scoreInputFocusNodes) {
      focusNode.dispose();
    }
    for (final row in _scoreButtonFocusNodes) {
      for (final focusNode in row) {
        focusNode.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadSelectedUserProfiles() async {
    setState(() {
      _loadingProfiles = true;
    });

    final updatedSeats = List<_PlayerSeat>.from(_seats);
    final count = widget.selectedUserIds.length > _seatCount
        ? _seatCount
        : widget.selectedUserIds.length;

    for (int i = 0; i < count; i++) {
      final userId = widget.selectedUserIds[i];
      if (userId.isEmpty) continue;

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        final data = snapshot.data();
        if (data == null) continue;

        final username = (data['username'] ?? '').toString().trim();
        final displayName = (data['displayName'] ?? '').toString().trim();
        final photoUrl = (data['photoUrl'] ?? '').toString().trim();
        final wins = _readInt(data['wins501']) ?? _readInt(data['wins']) ?? 0;
        final money = _readInt(data['money']) ?? 0;
        final score = _readInt(data['score501']) ?? 501;

        updatedSeats[i] = updatedSeats[i].copyWith(
          userId: userId,
          username: username,
          displayName: displayName.isNotEmpty
              ? displayName
              : updatedSeats[i].displayName,
          photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
          wins: wins,
          money: money,
          currentScore: score,
        );
      } catch (_) {
        updatedSeats[i] = updatedSeats[i].copyWith(userId: userId);
      }
    }

    if (!mounted) return;
    setState(() {
      _seats = updatedSeats;
      _loadingProfiles = false;
    });
  }

  int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  bool _isSeatInteractive(int seatIndex) {
    if (seatIndex >= _activeSeatCount) return false;
    if (_autoCorrectSeatIndexes.isNotEmpty) {
      return _activeRecommendedSeatIndex == seatIndex;
    }
    return _activeRecommendedSeatIndex == null ||
        _activeRecommendedSeatIndex == seatIndex;
  }

  Set<_ScoreButtonType> _lockedScoreButtonsForSeat(int seatIndex) {
    final activeSeatIndex = _activeRecommendedSeatIndex;
    if (activeSeatIndex == null) return const <_ScoreButtonType>{};
    if (activeSeatIndex < 0 || activeSeatIndex >= _activeSeatCount) {
      return const <_ScoreButtonType>{};
    }
    if (seatIndex == activeSeatIndex) return const <_ScoreButtonType>{};
    return Set<_ScoreButtonType>.from(_selectedScoreButtons[activeSeatIndex]);
  }

  void _activateRecommendedSeat(int seatIndex) {
    if (seatIndex >= _activeSeatCount) return;
    if (_autoCorrectSeatIndexes.contains(seatIndex)) return;
    if (_activeRecommendedSeatIndex == seatIndex) return;

    setState(() {
      _activeRecommendedSeatIndex = seatIndex;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestFocusAndSelect(
          _takenPriceFocusNodes[seatIndex], _takenPriceControllers[seatIndex]);
    });
  }

  void _cancelRecommendedSeat(int seatIndex) {
    if (_activeRecommendedSeatIndex != seatIndex) return;

    final playPrice =
        int.tryParse(_playPriceControllers[seatIndex].text.trim()) ?? 0;

    if (playPrice > 0 && !_autoCorrectSeatIndexes.contains(seatIndex)) {
      setState(() {
        final current = _seats[seatIndex];
        _seats[seatIndex] = current.copyWith(
          currentScore: current.currentScore + playPrice,
        );

        final otherIndexes = List<int>.generate(_activeSeatCount, (i) => i)
            .where((i) => i != seatIndex)
            .toList(growable: false);
        final othersCount = otherIndexes.length;
        final deduction = othersCount == 2
            ? 40
            : othersCount == 3
                ? 30
                : 0;

        if (deduction > 0) {
          for (final i in otherIndexes) {
            _seats[i] = _seats[i].copyWith(
              currentScore:
                  (_seats[i].currentScore - deduction).clamp(0, 99999),
            );
          }
        }

        _activeRecommendedSeatIndex = null;
        _applyAutoCorrectModeInState();
      });
      return;
    }

    setState(() {
      _activeRecommendedSeatIndex = null;
    });
  }

  void _toggleScoreButton(int seatIndex, _ScoreButtonType type) {
    if (seatIndex >= _activeSeatCount) return;
    if (_autoCorrectSeatIndexes.contains(seatIndex)) return;
    if (_lockedScoreButtonsForSeat(seatIndex).contains(type)) return;

    setState(() {
      final selected = _selectedScoreButtons[seatIndex];
      if (selected.contains(type)) {
        selected.remove(type);
      } else {
        selected.add(type);
      }
    });
  }

  void _focusScoreButton(int seatIndex, int buttonIndex) {
    if (seatIndex >= _activeSeatCount) return;
    if (buttonIndex < 0 || buttonIndex >= _scoreButtons.length) return;
    if (_autoCorrectSeatIndexes.contains(seatIndex)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scoreButtonFocusNodes[seatIndex][buttonIndex].requestFocus();
    });
  }

  void _onScoreButtonSpacePressed(int seatIndex, int buttonIndex) {
    if (seatIndex >= _activeSeatCount) return;
    if (buttonIndex < 0 || buttonIndex >= _scoreButtons.length) return;
    _toggleScoreButton(seatIndex, _scoreButtons[buttonIndex].type);
  }

  void _onScoreButtonEnterPressed(int seatIndex, int buttonIndex) {
    if (seatIndex >= _activeSeatCount) return;
    if (buttonIndex < 0 || buttonIndex >= _scoreButtons.length) return;

    final nextButtonIndex = buttonIndex + 1;
    if (nextButtonIndex < _scoreButtons.length) {
      _focusScoreButton(seatIndex, nextButtonIndex);
      return;
    }

    _requestFocusAndSelect(
      _scoreInputFocusNodes[seatIndex],
      _scoreInputControllers[seatIndex],
    );
  }

  void _focusNextSeatButtons(int currentSeatIndex) {
    if (_activeSeatCount <= 0) return;

    for (int step = 1; step <= _activeSeatCount; step++) {
      final index = (currentSeatIndex + step) % _activeSeatCount;
      if (_autoCorrectSeatIndexes.contains(index)) continue;
      if (_seats[index].currentScore >= 1000) continue;
      _focusScoreButton(index, 0);
      return;
    }
  }

  void _onTakenPriceSubmitted(int seatIndex, String _) {
    if (seatIndex >= _activeSeatCount) return;
    _requestFocusAndSelect(
      _playPriceFocusNodes[seatIndex],
      _playPriceControllers[seatIndex],
    );
  }

  void _onPlayPriceSubmitted(int seatIndex, String _) {
    if (seatIndex >= _activeSeatCount) return;
    _focusScoreButton(seatIndex, 0);
  }

  void _onScoreSubmitted(int seatIndex, String value) {
    if (seatIndex >= _activeSeatCount) return;

    final scoreInput = int.tryParse(value.trim()) ?? 0;

    final isAutoCorrectSeat = _autoCorrectSeatIndexes.contains(seatIndex);
    final playPrice =
        int.tryParse(_playPriceControllers[seatIndex].text.trim());

    if (!isAutoCorrectSeat && (playPrice == null || playPrice <= 0)) {
      _requestFocusAndSelect(
        _playPriceFocusNodes[seatIndex],
        _playPriceControllers[seatIndex],
      );
      return;
    }

    if (isAutoCorrectSeat) {
      final currentSeat = _seats[seatIndex];
      final nextScore = scoreInput >= 121
          ? currentSeat.currentScore - 121
          : currentSeat.currentScore + 121;
      final isWinner = nextScore <= 0;

      if (isWinner) {
        setState(() {
          _sessionFinishedGames += 1;
          if (_isBoltMode) {
            _sessionBoltRounds += 1;
          } else {
            _sessionOrdinaryRounds += 1;
          }

          _seats[seatIndex] = currentSeat.copyWith(
            wins: currentSeat.wins + 1,
            currentScore: _baseScore,
            money: currentSeat.money + (widget.autoReturnOnWinner ? 0 : 121),
          );

          for (int i = 0; i < _activeSeatCount; i++) {
            if (i == seatIndex) continue;
            _seats[i] = _seats[i].copyWith(currentScore: _baseScore);
          }

          _clearRoundInputs();
          _activeRecommendedSeatIndex = null;
          _roundNumber += 1;
          _isBoltMode = false;
          _applyAutoCorrectModeInState();
        });

        _showSnackBar(
            '${_seats[seatIndex].displayName} хожлоо. Шинэ тоглолт эхэллээ.');

        if (widget.autoReturnOnWinner && !_multiAutoReturnTriggered) {
          _multiAutoReturnTriggered = true;
          final winnerUserId = _seats[seatIndex].userId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pop(<String, dynamic>{
              'completedGame': '501',
              if (winnerUserId != null && winnerUserId.isNotEmpty)
                'winnerUserId': winnerUserId,
            });
          });
        }
      } else {
        setState(() {
          _seats[seatIndex] = currentSeat.copyWith(currentScore: nextScore);
          _scoreInputControllers[seatIndex].clear();
          _activeRecommendedSeatIndex = null;
          _applyAutoCorrectModeInState();
        });

        _focusNextSeatButtons(seatIndex);
      }
      return;
    }

    final selectedButtons = _selectedScoreButtons[seatIndex];
    final buttonSum = selectedButtons.fold<int>(
      0,
      (sum, type) => sum + _scoreButtonValueByType[type]!,
    );
    final multiplier = _isBoltMode ? 2 : 1;
    final effectivePlayPrice = playPrice! * multiplier;
    final total = scoreInput + buttonSum;

    final currentSeat = _seats[seatIndex];
    final nextScore = total >= effectivePlayPrice
        ? currentSeat.currentScore - effectivePlayPrice
        : currentSeat.currentScore + effectivePlayPrice;
    final isWinner = nextScore <= 0;

    if (isWinner) {
      setState(() {
        _sessionFinishedGames += 1;
        if (_isBoltMode) {
          _sessionBoltRounds += 1;
        } else {
          _sessionOrdinaryRounds += 1;
        }

        _seats[seatIndex] = currentSeat.copyWith(
          wins: currentSeat.wins + 1,
          currentScore: _baseScore,
          money: currentSeat.money +
              (widget.autoReturnOnWinner ? 0 : effectivePlayPrice),
        );

        for (int i = 0; i < _activeSeatCount; i++) {
          if (i == seatIndex) continue;
          _seats[i] = _seats[i].copyWith(currentScore: _baseScore);
        }

        _clearRoundInputs();
        _activeRecommendedSeatIndex = null;
        _roundNumber += 1;
        _isBoltMode = false;
        _applyAutoCorrectModeInState();
      });

      _showSnackBar(
          '${_seats[seatIndex].displayName} хожлоо. Шинэ тоглолт эхэллээ.');

      if (widget.autoReturnOnWinner && !_multiAutoReturnTriggered) {
        _multiAutoReturnTriggered = true;
        final winnerUserId = _seats[seatIndex].userId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pop(<String, dynamic>{
            'completedGame': '501',
            if (winnerUserId != null && winnerUserId.isNotEmpty)
              'winnerUserId': winnerUserId,
          });
        });
      }
    } else {
      setState(() {
        _seats[seatIndex] = currentSeat.copyWith(
          currentScore: nextScore < 0 ? 0 : nextScore,
        );
        _selectedScoreButtons[seatIndex].clear();
        _takenPriceControllers[seatIndex].clear();
        _playPriceControllers[seatIndex].clear();
        _scoreInputControllers[seatIndex].clear();
        _activeRecommendedSeatIndex = null;
        _applyAutoCorrectModeInState();
      });

      _focusNextSeatButtons(seatIndex);
    }
  }

  void _clearRoundInputs() {
    for (int i = 0; i < _activeSeatCount; i++) {
      _selectedScoreButtons[i].clear();
      _takenPriceControllers[i].clear();
      _playPriceControllers[i].clear();
      _scoreInputControllers[i].clear();
    }
    _autoCorrectSeatIndexes.clear();
  }

  void _applyAutoCorrectModeInState() {
    final lowScoreIndexes = <int>[];
    for (int i = 0; i < _activeSeatCount; i++) {
      final score = _seats[i].currentScore;
      if (score > 0 && score < 121) {
        lowScoreIndexes.add(i);
      }
    }

    _autoCorrectSeatIndexes
      ..clear()
      ..addAll(lowScoreIndexes);

    if (lowScoreIndexes.isEmpty) {
      if (_activeRecommendedSeatIndex != null &&
          _activeRecommendedSeatIndex! >= _activeSeatCount) {
        _activeRecommendedSeatIndex = null;
      }
      return;
    }

    lowScoreIndexes.sort((a, b) {
      final scoreCompare =
          _seats[a].currentScore.compareTo(_seats[b].currentScore);
      if (scoreCompare != 0) return scoreCompare;
      return a.compareTo(b);
    });

    for (final i in lowScoreIndexes) {
      _takenPriceControllers[i].text = '121';
      _playPriceControllers[i].text = '121';
      _selectedScoreButtons[i].clear();
    }

    _activeRecommendedSeatIndex = lowScoreIndexes.first;
  }

  List<String> _activePlayerUserIds() {
    return _seats
        .take(_activeSeatCount)
        .map((seat) => seat.userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  String _displayNameForUserId(String userId) {
    for (final seat in _seats.take(_activeSeatCount)) {
      if (seat.userId == userId) return seat.displayName;
    }
    return 'Тоглогч';
  }

  String _usernameForUserId(String userId) {
    for (final seat in _seats.take(_activeSeatCount)) {
      if (seat.userId == userId) return seat.username;
    }
    return '';
  }

  Future<void> _transferRegistrarRole() async {
    final registrarId = _currentRegistrarUserId;
    if (!_canTransferRegistrar || registrarId == null || registrarId.isEmpty) {
      return;
    }

    final nextRegistrarUserId = await GameRegistrarTransfer.transfer(
      context,
      currentRegistrarUserId: registrarId,
      playerUserIds: _activePlayerUserIds(),
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
      playerUserIds: _activePlayerUserIds(),
      displayNameForUserId: _displayNameForUserId,
      usernameForUserId: _usernameForUserId,
    );

    if (!mounted || resolvedRegistrarUserId == null) return;
    setState(() {
      _currentRegistrarUserId = resolvedRegistrarUserId;
    });
  }

  Future<void> _addPlayerFromSelectionPage() async {
    if (_activeSeatCount >= _seatCount) {
      _showSnackBar('Хамгийн ихдээ 7 тоглогч байна.');
      return;
    }

    final activeUserIds = <String>[];
    for (int i = 0; i < _activeSeatCount; i++) {
      final uid = _seats[i].userId;
      if (uid != null && uid.isNotEmpty) {
        activeUserIds.add(uid);
      }
    }

    final picked = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: activeUserIds,
          currentUserId: widget.currentUserId,
          canManageGames: widget.canManageGames,
        ),
      ),
    );

    if (!mounted || picked == null || picked.isEmpty) return;

    final requestedUserIds = <String>[];
    for (final raw in picked) {
      final userId = raw.trim();
      if (userId.isEmpty) continue;
      if (activeUserIds.contains(userId)) continue;
      if (requestedUserIds.contains(userId)) continue;
      requestedUserIds.add(userId);
    }

    if (requestedUserIds.isEmpty) {
      _showSnackBar('Нэмэх боломжтой тоглогч сонгогдоогүй байна.');
      return;
    }

    final availableSlots = _seatCount - _activeSeatCount;
    final userIdsToAdd = requestedUserIds.take(availableSlots).toList();
    if (userIdsToAdd.length < requestedUserIds.length) {
      _showSnackBar(
          'Суудал дүүрсэн тул ${userIdsToAdd.length} тоглогч нэмлээ.');
    }

    int addedCount = 0;
    for (final pickedUserId in userIdsToAdd) {
      if (!mounted || _activeSeatCount >= _seatCount) break;

      final existingIndex =
          _seats.indexWhere((seat) => seat.userId == pickedUserId);
      if (existingIndex >= 0 && existingIndex < _activeSeatCount) {
        continue;
      }

      final targetIndex = _activeSeatCount;
      if (existingIndex >= _activeSeatCount && existingIndex < _seatCount) {
        setState(() {
          _swapSeatSlots(targetIndex, existingIndex);
          _activeSeatCount += 1;
          _applyAutoCorrectModeInState();
        });
        addedCount += 1;
        continue;
      }

      final newSeat = await _buildSeatFromUserProfile(
        targetIndex: targetIndex,
        userId: pickedUserId,
      );
      if (!mounted) return;

      setState(() {
        _seats[targetIndex] = newSeat;
        _activeSeatCount += 1;
        _applyAutoCorrectModeInState();
      });
      addedCount += 1;
    }

    if (!mounted || addedCount == 0) return;

    if (_activeSeatCount >= 4) {
      await _showAndApplyPlayerOrderDialog();
    }
  }

  Future<_PlayerSeat> _buildSeatFromUserProfile({
    required int targetIndex,
    required String userId,
  }) async {
    _PlayerSeat seat = _seats[targetIndex].copyWith(
      userId: userId,
      displayName: _seats[targetIndex].displayName,
      username: '',
      photoUrl: null,
      wins: 0,
      money: 0,
      currentScore: _baseScore,
    );

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final data = snapshot.data();
      if (data == null) return seat;

      final username = (data['username'] ?? '').toString().trim();
      final displayName = (data['displayName'] ?? '').toString().trim();
      final photoUrl = (data['photoUrl'] ?? '').toString().trim();
      final wins = _readInt(data['wins501']) ?? _readInt(data['wins']) ?? 0;
      final money = _readInt(data['money']) ?? 0;
      final score = _readInt(data['score501']) ?? _baseScore;

      return seat.copyWith(
        username: username,
        displayName: displayName.isNotEmpty ? displayName : seat.displayName,
        photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
        wins: wins,
        money: money,
        currentScore: score,
      );
    } catch (_) {
      return seat;
    }
  }

  Future<void> _showAndApplyPlayerOrderDialog() async {
    if (!mounted) return;
    // Skip if restoring from saved session
    if (widget.initialSavedSessionId != null &&
        widget.initialSavedSessionId!.isNotEmpty) {
      return;
    }
    final candidates = <_SeatCandidate>[];
    for (int i = 0; i < _activeSeatCount; i++) {
      final seat = _seats[i];
      final userId = seat.userId;
      if (userId == null || userId.isEmpty) continue;
      candidates.add(
        _SeatCandidate(
          seatIndex: i,
          title: seat.displayName,
          subtitle: seat.username.isEmpty ? '' : '@${seat.username}',
          photoUrl: seat.photoUrl,
          userId: userId,
        ),
      );
    }

    if (candidates.length < 4) return;

    final orderedUserIds = await _showPlayerOrderDialog(candidates);
    if (!mounted || orderedUserIds == null || orderedUserIds.isEmpty) return;

    setState(() {
      for (int target = 0; target < orderedUserIds.length; target++) {
        final userId = orderedUserIds[target];
        final current = _seats.indexWhere((seat) => seat.userId == userId);
        if (current < 0 || current == target) continue;
        _swapSeatSlots(target, current);
      }
      _applyAutoCorrectModeInState();
    });
  }

  Future<List<String>?> _showPlayerOrderDialog(List<_SeatCandidate> players) {
    final selectedOrder = List<int?>.filled(players.length, null);
    int currentOrder = 1;

    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final screenWidth = MediaQuery.of(context).size.width;
            final maxDialogWidth = screenWidth * 0.9;
            const spacing = 6.0;
            final cardWidth = (maxDialogWidth - spacing * (7 - 1)) / 7;
            final dialogWidth =
                players.length * cardWidth + (players.length - 1) * spacing;
            return AlertDialog(
              title: const Text('Тоглогчдын дараалал сонгох'),
              content: SizedBox(
                width: dialogWidth,
                height: 230,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < players.length; i++) ...[
                            SizedBox(
                              width: cardWidth,
                              height: 170,
                              child: GestureDetector(
                                onTap: () {
                                  if (selectedOrder[i] == null &&
                                      currentOrder <= players.length) {
                                    setDialogState(() {
                                      selectedOrder[i] = currentOrder;
                                      currentOrder += 1;
                                    });
                                  } else if (selectedOrder[i] != null) {
                                    setDialogState(() {
                                      final removed = selectedOrder[i]!;
                                      selectedOrder[i] = null;
                                      for (int j = 0;
                                          j < selectedOrder.length;
                                          j++) {
                                        final value = selectedOrder[j];
                                        if (value != null && value > removed) {
                                          selectedOrder[j] = value - 1;
                                        }
                                      }
                                      currentOrder -= 1;
                                    });
                                  }
                                },
                                child: Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
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
                                            builder: (_) {
                                              final image =
                                                  _resolveSeatCandidateImage(
                                                players[i].photoUrl,
                                              );
                                              if (image == null) {
                                                return Container(
                                                  color:
                                                      Colors.deepPurple.shade50,
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    Icons.person,
                                                    color: Colors
                                                        .deepPurple.shade300,
                                                    size: 36,
                                                  ),
                                                );
                                              }
                                              return Image(
                                                image: image,
                                                fit: BoxFit.cover,
                                              );
                                            },
                                          ),
                                        ),
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: CircleAvatar(
                                            radius: 12,
                                            backgroundColor:
                                                selectedOrder[i] != null
                                                    ? Colors.blue
                                                    : Colors.white70,
                                            child: Text(
                                              selectedOrder[i]?.toString() ??
                                                  '',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 6),
                                            color: Colors.black54,
                                            child: Text(
                                              players[i].title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (i != players.length - 1)
                              const SizedBox(width: spacing),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Эхний 4 нь дээд блокт тоглоно, 4-с хойших нь доод блокт хүлээнэ.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
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
                  onPressed: selectedOrder.every((v) => v != null)
                      ? () {
                          final indexed = List<int>.generate(
                            players.length,
                            (i) => i,
                          )..sort(
                              (a, b) => selectedOrder[a]!
                                  .compareTo(selectedOrder[b]!),
                            );
                          final orderedUserIds = indexed
                              .map((i) => players[i].userId)
                              .whereType<String>()
                              .toList(growable: false);
                          Navigator.of(dialogContext).pop(orderedUserIds);
                        }
                      : null,
                  child: const Text('Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRemovePlayerDialog() async {
    if (_activeSeatCount <= _minimumActiveSeats) {
      _showSnackBar('Хамгийн багадаа 3 тоглогч тоглоно.');
      return;
    }

    final removable = <_SeatCandidate>[];
    for (int i = 0; i < _activeSeatCount; i++) {
      final seat = _seats[i];
      final userId = seat.userId;
      if (userId == null || userId.isEmpty) continue;
      removable.add(
        _SeatCandidate(
          seatIndex: i,
          title: seat.displayName,
          subtitle: seat.username.isEmpty ? '' : '@${seat.username}',
          photoUrl: seat.photoUrl,
        ),
      );
    }

    if (removable.isEmpty) {
      _showSnackBar('Хасах тоглогч алга.');
      return;
    }

    int selectedSeatIndex = removable.first.seatIndex;

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Хасах тоглогч сонгох'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final player in removable)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue[300],
                            backgroundImage:
                                _resolveSeatCandidateImage(player.photoUrl),
                            child: _resolveSeatCandidateImage(
                                        player.photoUrl) ==
                                    null
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                          ),
                          title: Text(player.title),
                          subtitle: player.subtitle.isEmpty
                              ? null
                              : Text(player.subtitle),
                          trailing: Radio<int>(
                            value: player.seatIndex,
                            groupValue: selectedSeatIndex,
                            onChanged: (value) {
                              if (value == null) return;
                              setLocalState(() => selectedSeatIndex = value);
                            },
                          ),
                          onTap: () {
                            setLocalState(
                              () => selectedSeatIndex = player.seatIndex,
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, selectedSeatIndex),
                  child: const Text('Хасах'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    final removedUserId = _seats[result].userId;

    setState(() {
      final lastActiveIndex = _activeSeatCount - 1;
      if (result != lastActiveIndex) {
        _swapSeatSlots(result, lastActiveIndex);
      }
      _activeSeatCount -= 1;
      if (_activeRecommendedSeatIndex != null &&
          _activeRecommendedSeatIndex! >= _activeSeatCount) {
        _activeRecommendedSeatIndex = null;
      }
      _applyAutoCorrectModeInState();
    });

    if (removedUserId != null && removedUserId.isNotEmpty) {
      Future.microtask(
        () => _activeTablesRepo.releasePlayersFromActiveTables([removedUserId]),
      );
    }
  }

  void _swapSeatSlots(int a, int b) {
    if (a == b) return;

    final seatA = _seats[a];
    final seatB = _seats[b];
    _seats[a] = seatB;
    _seats[b] = seatA;

    final selectedA = Set<_ScoreButtonType>.from(_selectedScoreButtons[a]);
    final selectedB = Set<_ScoreButtonType>.from(_selectedScoreButtons[b]);
    _selectedScoreButtons[a]
      ..clear()
      ..addAll(selectedB);
    _selectedScoreButtons[b]
      ..clear()
      ..addAll(selectedA);

    final takenA = _takenPriceControllers[a].text;
    final playA = _playPriceControllers[a].text;
    final scoreA = _scoreInputControllers[a].text;

    _takenPriceControllers[a].text = _takenPriceControllers[b].text;
    _playPriceControllers[a].text = _playPriceControllers[b].text;
    _scoreInputControllers[a].text = _scoreInputControllers[b].text;

    _takenPriceControllers[b].text = takenA;
    _playPriceControllers[b].text = playA;
    _scoreInputControllers[b].text = scoreA;

    final hadA = _autoCorrectSeatIndexes.contains(a);
    final hadB = _autoCorrectSeatIndexes.contains(b);
    _autoCorrectSeatIndexes
      ..remove(a)
      ..remove(b);
    if (hadA) _autoCorrectSeatIndexes.add(b);
    if (hadB) _autoCorrectSeatIndexes.add(a);

    if (_activeRecommendedSeatIndex == a) {
      _activeRecommendedSeatIndex = b;
    } else if (_activeRecommendedSeatIndex == b) {
      _activeRecommendedSeatIndex = a;
    }
  }

  String _buildSessionReportText() {
    final activeSeats = _seats.take(_activeSeatCount).toList(growable: false);
    final totalRounds = _sessionOrdinaryRounds + _sessionBoltRounds;
    final lines = <String>[
      '501 - ТОГЛОЛТЫН ТАЙЛАН',
      'Раунд: $_roundNumber',
      'Нийт дууссан тоглолт: $_sessionFinishedGames',
      'Энгийн тоглолт: $_sessionOrdinaryRounds',
      'Боолт тоглолт: $_sessionBoltRounds',
      'Нийт тоологдсон тоглолт: $totalRounds',
      '',
      'Тоглогчдын мэдээлэл:',
    ];

    for (int i = 0; i < activeSeats.length; i++) {
      final seat = activeSeats[i];
      final uname = seat.username.isEmpty ? '' : ' (@${seat.username})';
      lines.add(
        '${i + 1}. ${seat.displayName}$uname | x ${seat.wins} | ₮${seat.money} | Оноо ${seat.currentScore}',
      );
    }

    return lines.join('\n');
  }

  Future<Uint8List> _buildSessionReportPdfBytes() async {
    final activeSeats = _seats.take(_activeSeatCount).toList(growable: false);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Text(
            '501 - TOGLOLTYN TAILAN',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Round: $_roundNumber'),
          pw.Text('Finished games: $_sessionFinishedGames'),
          pw.Text('Ordinary rounds: $_sessionOrdinaryRounds'),
          pw.Text('Bolt rounds: $_sessionBoltRounds'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'Display',
              'Username',
              'Wins',
              'Money',
              'Score'
            ],
            data: List<List<String>>.generate(activeSeats.length, (index) {
              final seat = activeSeats[index];
              return [
                '${index + 1}',
                seat.displayName,
                seat.username,
                seat.wins.toString(),
                seat.money.toString(),
                seat.currentScore.toString(),
              ];
            }),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<void> _printSessionReport() async {
    try {
      final bytes = await _buildSessionReportPdfBytes();
      await Printing.layoutPdf(
        name: 'toocoob_report_501',
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Хэвлэх цонх нээгдсэнгүй.');
    }
  }

  Future<void> _shareReportToApps() async {
    try {
      final pdfBytes = await _buildSessionReportPdfBytes();
      await SharePlus.instance.share(
        ShareParams(
          text: _buildSessionReportText(),
          subject: '501 тоглолтын тайлан',
          files: [
            XFile.fromData(
              pdfBytes,
              mimeType: 'application/pdf',
              name: 'toocoob_501_report.pdf',
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Илгээх үйлдэл амжилтгүй.');
    }
  }

  Future<void> _saveBytesByPlatform({
    required Uint8List bytes,
    required String defaultFileName,
    required String typeLabel,
    required List<String> extensions,
    required String mimeType,
  }) async {
    if (kIsWeb) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: mimeType,
              name: defaultFileName,
            ),
          ],
          subject: '501 тоглолтын тайлан',
        ),
      );
      return;
    }

    final saveLocation = await getSaveLocation(
      suggestedName: defaultFileName,
      acceptedTypeGroups: [
        XTypeGroup(label: typeLabel, extensions: extensions),
      ],
    );

    if (saveLocation == null) return;

    final file = XFile.fromData(
      bytes,
      mimeType: mimeType,
      name: defaultFileName,
    );
    await file.saveTo(saveLocation.path);

    if (!mounted) return;
    _showSnackBar('Файл хадгаллаа: ${saveLocation.path}');
  }

  Future<void> _saveReportPdfFile() async {
    final bytes = await _buildSessionReportPdfBytes();
    await _saveBytesByPlatform(
      bytes: bytes,
      defaultFileName: 'toocoob_501_report.pdf',
      typeLabel: 'PDF File',
      extensions: ['pdf'],
      mimeType: 'application/pdf',
    );
  }

  Future<void> _addCurrentSessionToStatisticsIfNeeded() async {
    if (_sessionAddedToStatistics) return;

    final activeSeats = _seats.take(_activeSeatCount).toList(growable: false);
    final players = List<StatsPlayerResult>.generate(activeSeats.length, (i) {
      final seat = activeSeats[i];
      return StatsPlayerResult(
        userId: seat.userId ?? 'seat_${seat.index}',
        username: seat.username,
        displayName: seat.displayName,
        money: seat.money,
      );
    });

    final session = StatsSession(
      sessionId: _sessionId,
      gameKey: '501',
      gameLabel: '501',
      playedAt: DateTime.now(),
      players: players,
      totalRounds: _roundNumber - 1,
    );

    final repository = StatsRepository();
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

  Future<void> _showSessionSummaryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтын тайлан'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: SelectableText(_buildSessionReportText()),
            ),
          ),
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

  Future<void> _showReportActionsSheet() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        Future<void> run(Future<void> Function() action) async {
          Navigator.of(sheetContext).pop();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!mounted) return;
          await action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('Тайлан'),
                onTap: () => run(_showSessionSummaryDialog),
              ),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Хэвлэх'),
                onTap: () => run(_printSessionReport),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Хадгалах'),
                onTap: () => run(_saveReportPdfFile),
              ),
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('Илгээх'),
                onTap: () => run(_shareReportToApps),
              ),
              ListTile(
                leading: const Icon(Icons.query_stats),
                title: const Text('Статистик'),
                onTap: () => run(_openStatisticsDashboard),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showGameSettingsDialog() async {
    bool localBolt = _isBoltMode;
    final baseController =
        TextEditingController(text: _normalBasePrice.toString());
    final boltController =
        TextEditingController(text: _boltBasePrice.toString());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('501 тохиргоо'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('Боолт горим идэвхжүүлэх'),
                        ),
                        Switch(
                          value: localBolt,
                          onChanged: (value) {
                            setLocalState(() {
                              localBolt = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: baseController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Босго үнэ',
                        hintText: '5000',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: boltController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Боолтын үнэ',
                        hintText: '10000',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final normal = int.tryParse(baseController.text.trim()) ??
                        _normalBasePrice;
                    final bolt = int.tryParse(boltController.text.trim()) ??
                        _boltBasePrice;
                    setState(() {
                      _isBoltMode = localBolt;
                      _normalBasePrice = normal <= 0 ? 5000 : normal;
                      _boltBasePrice = bolt <= 0 ? 10000 : bolt;
                    });
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );

    baseController.dispose();
    boltController.dispose();
  }

  Future<void> _finishAndExit() async {
    await _addCurrentSessionToStatisticsIfNeeded();
    await _askRegistrarDecisionAtGameEndIfNeeded();
    await _removeSavedProgressIfAny();
    if (!mounted) return;
    Navigator.of(context).pop(<String, dynamic>{'completedGame': '501'});
  }

  Future<void> _tryRestoreSavedSession() async {
    final id = widget.initialSavedSessionId;
    if (id == null || id.isEmpty) return;
    final saved = await _savedSessionsRepo.findById(id);
    if (saved == null || !mounted) return;

    final p = saved.payload;
    final rawSeats = (p['seats'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (rawSeats.isEmpty) return;

    setState(() {
      _activeSavedSessionId = saved.id;
      _roundNumber = (p['roundNumber'] as num? ?? _roundNumber).toInt();
      _isBoltMode = p['isBoltMode'] == true;
      _normalBasePrice =
          (p['normalBasePrice'] as num? ?? _normalBasePrice).toInt();
      _boltBasePrice = (p['boltBasePrice'] as num? ?? _boltBasePrice).toInt();
      _activeSeatCount =
          (p['activeSeatCount'] as num? ?? _activeSeatCount).toInt();
      _sessionFinishedGames =
          (p['sessionFinishedGames'] as num? ?? _sessionFinishedGames).toInt();
      _sessionOrdinaryRounds =
          (p['sessionOrdinaryRounds'] as num? ?? _sessionOrdinaryRounds)
              .toInt();
      _sessionBoltRounds =
          (p['sessionBoltRounds'] as num? ?? _sessionBoltRounds).toInt();
      _seats = rawSeats
          .map(
            (e) => _PlayerSeat(
              index: (e['index'] as num? ?? 0).toInt(),
              userId: (e['userId'] ?? '').toString().isEmpty
                  ? null
                  : (e['userId'] ?? '').toString(),
              displayName: (e['displayName'] ?? '').toString(),
              username: (e['username'] ?? '').toString(),
              wins: (e['wins'] as num? ?? 0).toInt(),
              money: (e['money'] as num? ?? 0).toInt(),
              currentScore: (e['currentScore'] as num? ?? _baseScore).toInt(),
              photoUrl: (e['photoUrl'] ?? '').toString().isEmpty
                  ? null
                  : (e['photoUrl'] ?? '').toString(),
            ),
          )
          .toList();
    });
  }

  Future<void> _saveProgress() async {
    final payload = {
      'roundNumber': _roundNumber,
      'isBoltMode': _isBoltMode,
      'normalBasePrice': _normalBasePrice,
      'boltBasePrice': _boltBasePrice,
      'activeSeatCount': _activeSeatCount,
      'sessionFinishedGames': _sessionFinishedGames,
      'sessionOrdinaryRounds': _sessionOrdinaryRounds,
      'sessionBoltRounds': _sessionBoltRounds,
      'seats': _seats
          .map((s) => {
                'index': s.index,
                'userId': s.userId,
                'displayName': s.displayName,
                'username': s.username,
                'wins': s.wins,
                'money': s.money,
                'currentScore': s.currentScore,
                'photoUrl': s.photoUrl,
              })
          .toList(),
    };
    final id = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: 'game501',
      gameLabel: '501',
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

  Future<void> _showExitReportAndFinish() async {
    final shouldFinish = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтын тайлан'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(_buildSessionReportText()),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop(false);
                await _shareReportToApps();
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
                await _saveReportPdfFile();
              },
              child: const Text('Хадгалах'),
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

    if (shouldFinish == true) {
      await _finishAndExit();
    }
  }

  void _requestFocusAndSelect(
      FocusNode focusNode, TextEditingController controller) {
    focusNode.requestFocus();
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topSeats = _seats.take(4).toList(growable: false);
    final bottomSeats = _seats.skip(4).take(3).toList(growable: false);

    return Scaffold(
      appBar: UnifiedGameAppBar(
        title: const Text('501'),
        currentUserId: widget.currentUserId,
        canManageGames: widget.canManageGames,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          final selectedUserIds = _seats
              .take(_activeSeatCount)
              .map((seat) => seat.userId)
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
        onRemovePlayer: _activeSeatCount > _minimumActiveSeats
            ? _showRemovePlayerDialog
            : null,
        onAddPlayer:
            _activeSeatCount < _seatCount ? _addPlayerFromSelectionPage : null,
        onSave: _saveProgress,
        onStatistics: _openStatisticsDashboard,
        onReport: _showReportActionsSheet,
        onPrint: _printSessionReport,
        onSettings: _showGameSettingsDialog,
        onExit: _showExitReportAndFinish,
        extraActions: [
          IconButton(
            tooltip: _canTransferRegistrar
                ? 'Бүртгэл хөтлөгчийн эрх шилжүүлэх'
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
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_loadingProfiles)
              const LinearProgressIndicator(minHeight: 3)
            else
              const SizedBox(height: 3),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  for (int index = 0; index < topSeats.length; index++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _PlayerSeatCard(
                          seat: topSeats[index],
                          seatIndex: index,
                          takenPriceController: _takenPriceControllers[index],
                          playPriceController: _playPriceControllers[index],
                          scoreInputController: _scoreInputControllers[index],
                          takenPriceFocusNode: _takenPriceFocusNodes[index],
                          playPriceFocusNode: _playPriceFocusNodes[index],
                          scoreInputFocusNode: _scoreInputFocusNodes[index],
                          scoreButtonFocusNodes: _scoreButtonFocusNodes[index],
                          selectedScoreButtons: _selectedScoreButtons[index],
                          disabledScoreButtons:
                              _lockedScoreButtonsForSeat(index),
                          showPlayerInfo: index < _activeSeatCount,
                          controlsEnabled: _isSeatInteractive(index) &&
                              _seats[index].currentScore < 1000 &&
                              !_autoCorrectSeatIndexes.contains(index),
                          scoreControlsEnabled:
                              _seats[index].currentScore < 1000 &&
                                  !_autoCorrectSeatIndexes.contains(index),
                          scoreInputEnabled: true,
                          isRecommendedActive:
                              _activeRecommendedSeatIndex == index ||
                                  _autoCorrectSeatIndexes.contains(index),
                          recommendEnabled: _isSeatInteractive(index) &&
                              _seats[index].currentScore < 1000 &&
                              !_autoCorrectSeatIndexes.contains(index) &&
                              _activeRecommendedSeatIndex != index,
                          onRecommendPressed: () =>
                              _activateRecommendedSeat(index),
                          onCancelPressed: () => _cancelRecommendedSeat(index),
                          onTakenPriceSubmitted: (input) =>
                              _onTakenPriceSubmitted(index, input),
                          onPlayPriceSubmitted: (input) =>
                              _onPlayPriceSubmitted(index, input),
                          onScoreSubmitted: (input) =>
                              _onScoreSubmitted(index, input),
                          onScoreButtonToggled: (type) =>
                              _toggleScoreButton(index, type),
                          onScoreButtonSpacePressed: (buttonIndex) =>
                              _onScoreButtonSpacePressed(index, buttonIndex),
                          onScoreButtonEnterPressed: (buttonIndex) =>
                              _onScoreButtonEnterPressed(index, buttonIndex),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  for (int i = 0; i < bottomSeats.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _PlayerSeatCard(
                          seat: bottomSeats[i],
                          compact: true,
                          showPlayerInfo: (i + 4) < _activeSeatCount,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerSeatCard extends StatelessWidget {
  const _PlayerSeatCard({
    required this.seat,
    this.seatIndex,
    this.compact = false,
    this.takenPriceController,
    this.playPriceController,
    this.scoreInputController,
    this.takenPriceFocusNode,
    this.playPriceFocusNode,
    this.scoreInputFocusNode,
    this.scoreButtonFocusNodes,
    this.selectedScoreButtons = const <_ScoreButtonType>{},
    this.disabledScoreButtons = const <_ScoreButtonType>{},
    this.showPlayerInfo = true,
    this.controlsEnabled = true,
    this.scoreControlsEnabled = true,
    this.scoreInputEnabled = true,
    this.isRecommendedActive = false,
    this.recommendEnabled = true,
    this.onRecommendPressed,
    this.onCancelPressed,
    this.onTakenPriceSubmitted,
    this.onPlayPriceSubmitted,
    this.onScoreSubmitted,
    this.onScoreButtonToggled,
    this.onScoreButtonSpacePressed,
    this.onScoreButtonEnterPressed,
  });

  final _PlayerSeat seat;
  final int? seatIndex;
  final bool compact;
  final TextEditingController? takenPriceController;
  final TextEditingController? playPriceController;
  final TextEditingController? scoreInputController;
  final FocusNode? takenPriceFocusNode;
  final FocusNode? playPriceFocusNode;
  final FocusNode? scoreInputFocusNode;
  final List<FocusNode>? scoreButtonFocusNodes;
  final Set<_ScoreButtonType> selectedScoreButtons;
  final Set<_ScoreButtonType> disabledScoreButtons;
  final bool showPlayerInfo;
  final bool controlsEnabled;
  final bool scoreControlsEnabled;
  final bool scoreInputEnabled;
  final bool isRecommendedActive;
  final bool recommendEnabled;
  final VoidCallback? onRecommendPressed;
  final VoidCallback? onCancelPressed;
  final ValueChanged<String>? onTakenPriceSubmitted;
  final ValueChanged<String>? onPlayPriceSubmitted;
  final ValueChanged<String>? onScoreSubmitted;
  final ValueChanged<_ScoreButtonType>? onScoreButtonToggled;
  final ValueChanged<int>? onScoreButtonSpacePressed;
  final ValueChanged<int>? onScoreButtonEnterPressed;

  @override
  Widget build(BuildContext context) {
    final hasPlayer = seat.userId != null && seat.userId!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.deepPurple.shade300,
          width: compact ? 3.2 : 4.8,
        ),
        color:
            showPlayerInfo && hasPlayer ? Colors.white : Colors.grey.shade100,
      ),
      child: !showPlayerInfo
          ? _buildInactiveContent()
          : (compact ? _buildCompactContent() : _buildRegularContent()),
    );
  }

  Widget _buildInactiveContent() {
    if (compact) {
      return const Center(
        child: Text(
          'Хоосон',
          style: TextStyle(
            color: Colors.black45,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      );
    }
    return const Center(
      child: Text(
        'Хоосон суудал',
        style: TextStyle(
          color: Colors.black45,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _buildRegularContent() {
    final avatarImage = _resolveImage(seat.photoUrl);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.deepPurple.shade100,
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? const Icon(Icons.person, color: Colors.deepPurple)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seat.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            seat.username.isEmpty
                                ? 'Сонгогдоогүй'
                                : '@${seat.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: seat.username.isEmpty
                                  ? Colors.grey
                                  : Colors.black54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildWinLine(),
                    const SizedBox(height: 6),
                    _buildMoneyLine(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildScoreBoardSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBoardSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.shade200, width: 1.8),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Expanded(
                  flex: 7,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.deepPurple.shade100, width: 1.4),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: Text(
                              '${seat.currentScore}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.w900,
                                color: Colors.deepPurple.shade700,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              recommendEnabled ? onRecommendPressed : null,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, double.infinity),
                            backgroundColor: isRecommendedActive
                                ? Colors.green.shade700
                                : Colors.green.shade500,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Icon(Icons.check, size: 20),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: controlsEnabled ? onCancelPressed : null,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, double.infinity),
                            backgroundColor: Colors.red.shade400,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Icon(Icons.close, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: _buildInfoCell(
                    title: 'Авсан үнэ',
                    controller: takenPriceController!,
                    focusNode: takenPriceFocusNode,
                    enabled: controlsEnabled,
                    onSubmitted: onTakenPriceSubmitted,
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoCell(
                    title: 'Тоглох үнэ',
                    controller: playPriceController!,
                    focusNode: playPriceFocusNode,
                    enabled: controlsEnabled,
                    onSubmitted: onPlayPriceSubmitted,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: _buildButtonsGrid(),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 4,
                  child: _buildActionValueCell(
                    controller: scoreInputController!,
                    focusNode: scoreInputFocusNode,
                    enabled: scoreControlsEnabled,
                    onSubmitted: onScoreSubmitted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonsGrid() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildSquareButtonSlot(0),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildSquareButtonSlot(1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildSquareButtonSlot(2),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildSquareButtonSlot(3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSquareButtonSlot(int index) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: _buildAssetButton(index, _scoreButtons[index]),
      ),
    );
  }

  Widget _buildInfoCell({
    required String title,
    required TextEditingController controller,
    required bool enabled,
    FocusNode? focusNode,
    ValueChanged<String>? onSubmitted,
    TextInputAction textInputAction = TextInputAction.done,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade100, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              onSubmitted: onSubmitted,
              textAlign: TextAlign.center,
              textAlignVertical: TextAlignVertical.center,
              keyboardType: TextInputType.number,
              textInputAction: textInputAction,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionValueCell({
    required TextEditingController controller,
    required bool enabled,
    FocusNode? focusNode,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.shade100, width: 1.4),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: scoreInputEnabled,
        onSubmitted: onSubmitted,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
        ),
        style: TextStyle(
          fontSize: 22,
          color: Colors.deepPurple.shade700,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildAssetButton(int index, _ScoreButtonConfig config) {
    final isSelected = selectedScoreButtons.contains(config.type);
    final isLocked = disabledScoreButtons.contains(config.type);
    final isInteractive = scoreControlsEnabled && !isLocked;
    final selectedBorderColor =
        _isRedSuit(config.type) ? Colors.black : Colors.red.shade700;
    final focusNode =
        scoreButtonFocusNodes != null && index < scoreButtonFocusNodes!.length
            ? scoreButtonFocusNodes![index]
            : null;

    KeyEventResult onKeyEvent(FocusNode _, KeyEvent event) {
      if (!scoreControlsEnabled) return KeyEventResult.ignored;
      if (event is! KeyDownEvent) return KeyEventResult.ignored;

      if (event.logicalKey == LogicalKeyboardKey.space) {
        if (!isInteractive) return KeyEventResult.handled;
        onScoreButtonSpacePressed?.call(index);
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        onScoreButtonEnterPressed?.call(index);
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    return Material(
      color: isLocked
          ? Colors.grey.shade200
          : (isSelected ? Colors.amber.shade50 : Colors.white),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedBuilder(
        animation: focusNode ?? const AlwaysStoppedAnimation<double>(0),
        builder: (context, child) {
          final isFocused = focusNode?.hasFocus ?? false;
          final borderColor = isLocked
              ? Colors.grey.shade400
              : isSelected
                  ? selectedBorderColor
                  : isFocused
                      ? Colors.blue.shade700
                      : Colors.deepPurple.shade100;
          final borderWidth = isSelected ? 3.4 : (isFocused ? 3.2 : 1.4);

          return Focus(
            focusNode: focusNode,
            onKeyEvent: onKeyEvent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTapDown: (_) {
                focusNode?.requestFocus();
              },
              onTap: isInteractive
                  ? () {
                      focusNode?.requestFocus();
                      onScoreButtonToggled?.call(config.type);
                    }
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: borderColor,
                    width: borderWidth,
                  ),
                  boxShadow: isFocused
                      ? <BoxShadow>[
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.28),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                padding: const EdgeInsets.all(6),
                child: Opacity(
                  opacity: isInteractive ? 1 : 0.35,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Image.asset(config.assetPath, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isRedSuit(_ScoreButtonType type) {
    return type == _ScoreButtonType.diamonds || type == _ScoreButtonType.hearts;
  }

  Widget _buildWinLine() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 22),
        const SizedBox(width: 4),
        Text(
          'x ${seat.wins}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildMoneyLine() {
    final moneyColor = seat.money < 0 ? Colors.red : Colors.green;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text(
          '₮',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.black,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          seat.money.toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 22,
            color: moneyColor,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactContent() {
    final avatarImage = _resolveImage(seat.photoUrl);
    final nameText = seat.username.isEmpty
        ? seat.displayName
        : '${seat.displayName} @${seat.username}';
    final moneyColor = seat.money < 0 ? Colors.red : Colors.green;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.deepPurple.shade100,
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? const Icon(Icons.person, color: Colors.deepPurple, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    nameText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: seat.username.isEmpty
                          ? Colors.grey[700]
                          : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${seat.currentScore}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '★x${seat.wins}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '₮${seat.money}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: moneyColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider? _resolveImage(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
      return NetworkImage(photoUrl);
    }
    return AssetImage('assets/$photoUrl');
  }
}

const List<_ScoreButtonConfig> _scoreButtons = <_ScoreButtonConfig>[
  _ScoreButtonConfig(
    type: _ScoreButtonType.diamonds,
    assetPath: 'assets/buttons/4ljin.png',
    value: 100,
  ),
  _ScoreButtonConfig(
    type: _ScoreButtonType.hearts,
    assetPath: 'assets/buttons/bund.png',
    value: 120,
  ),
  _ScoreButtonConfig(
    type: _ScoreButtonType.clubs,
    assetPath: 'assets/buttons/ceceg.png',
    value: 80,
  ),
  _ScoreButtonConfig(
    type: _ScoreButtonType.spades,
    assetPath: 'assets/buttons/gil.png',
    value: 60,
  ),
];

final Map<_ScoreButtonType, int> _scoreButtonValueByType =
    <_ScoreButtonType, int>{
  for (final config in _scoreButtons) config.type: config.value,
};

enum _ScoreButtonType { spades, clubs, diamonds, hearts }

class _ScoreButtonConfig {
  const _ScoreButtonConfig({
    required this.type,
    required this.assetPath,
    required this.value,
  });

  final _ScoreButtonType type;
  final String assetPath;
  final int value;
}

class _PlayerSeat {
  const _PlayerSeat({
    required this.index,
    required this.displayName,
    required this.username,
    required this.wins,
    required this.money,
    required this.currentScore,
    this.userId,
    this.photoUrl,
  });

  final int index;
  final String? userId;
  final String displayName;
  final String username;
  final int wins;
  final int money;
  final int currentScore;
  final String? photoUrl;

  factory _PlayerSeat.empty(int index) {
    return _PlayerSeat(
      index: index,
      displayName: 'Тоглогч $index',
      username: '',
      wins: 0,
      money: 0,
      currentScore: _Game501PageState._baseScore,
    );
  }

  _PlayerSeat copyWith({
    int? index,
    String? userId,
    String? displayName,
    String? username,
    int? wins,
    int? money,
    int? currentScore,
    String? photoUrl,
  }) {
    return _PlayerSeat(
      index: index ?? this.index,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      wins: wins ?? this.wins,
      money: money ?? this.money,
      currentScore: currentScore ?? this.currentScore,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}

class _SeatCandidate {
  const _SeatCandidate({
    required this.seatIndex,
    required this.title,
    required this.subtitle,
    this.userId,
    this.photoUrl,
  });

  final int seatIndex;
  final String title;
  final String subtitle;
  final String? userId;
  final String? photoUrl;
}

class _PlayerSelectScreen501 extends StatefulWidget {
  const _PlayerSelectScreen501({required this.candidates});

  final List<_SeatCandidate> candidates;

  @override
  State<_PlayerSelectScreen501> createState() => _PlayerSelectScreen501State();
}

class _PlayerSelectScreen501State extends State<_PlayerSelectScreen501> {
  int? _selectedSeatIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Тоглогч сонгох'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: widget.candidates.length,
                itemBuilder: (context, index) {
                  final player = widget.candidates[index];
                  final avatarImage =
                      _resolveSeatCandidateImage(player.photoUrl);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[300],
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    title: Text(player.title),
                    subtitle:
                        player.subtitle.isEmpty ? null : Text(player.subtitle),
                    trailing: Radio<int>(
                      value: player.seatIndex,
                      groupValue: _selectedSeatIndex,
                      onChanged: (value) {
                        setState(() => _selectedSeatIndex = value);
                      },
                    ),
                    onTap: () => setState(() {
                      _selectedSeatIndex = player.seatIndex;
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Болих'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedSeatIndex == null
                      ? null
                      : () {
                          Navigator.of(context).pop(_selectedSeatIndex);
                        },
                  child: const Text('Ширээнд урих'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

ImageProvider? _resolveSeatCandidateImage(String? photoUrl) {
  if (photoUrl == null || photoUrl.isEmpty) return null;
  if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
    return NetworkImage(photoUrl);
  }
  return AssetImage('assets/$photoUrl');
}
