import 'dart:async';
import 'package:toocoob/utils/voice_player_selection.dart';
import 'package:toocoob/utils/game_speech.dart';
import 'package:toocoob/widgets/voice_player_cue.dart';
import 'package:toocoob/utils/live_game_state.dart';
import 'package:flutter/material.dart';
import 'package:toocoob/utils/muushig_voice_command.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:toocoob/screens/statistics_dashboard.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'package:toocoob/utils/game_registrar_transfer.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/utils/demo_players.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';
import 'package:toocoob/screens/kinds_of_game.dart';

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
  State<MuushigPage> createState() => _MuushigPageState();
}

class _MuushigPageState extends State<MuushigPage>
    with LiveGameState<MuushigPage> {
  @override
  LiveGameSessionsRepository get liveRepository => _savedSessionsRepo;
  @override
  String? get liveRegistrar => _currentRegistrarUserId;
  @override
  Future<void> saveLiveProgress() => _saveProgress();
  @override
  Future<void> restoreLiveProgress(SavedGameSession saved) async {
    await _tryRestoreSavedSession(remote: saved);
    _currentRegistrarUserId =
        saved.payload['currentRegistrarUserId'] as String? ??
            _currentRegistrarUserId;
  }

  final LiveGameSessionsRepository _savedSessionsRepo =
      LiveGameSessionsRepository();
  late final List<String> _selectedUserIdsSnapshot;
  int _roundNumber = 1;
  bool _playerOrderSelected = false;
  bool _orderDialogScheduled = false;
  String? _voiceRoundStart;
  Timer? _voiceStableTimer;
  String _voiceStableText = '';
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
  final Map<String, FocusNode> _roundDecisionFocusNodes = {};
  final Set<String> _penaltyFiveUsernames = <String>{};
  final List<String> _roundSelectionHistory = <String>[];
  String? _roundSelectionCursorUsername;
  bool _selectedProfilesLoaded = true;
  bool _sessionAddedToStatistics = false;
  String? _currentRegistrarUserId;
  String? _activeSavedSessionId;
  bool _multiAutoReturnTriggered = false;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _isListeningForVoiceCommand = false;
  String _voiceTranscript = '';
  bool _voiceTranscriptFinal = false;
  String? _voiceFeedback;
  @override
  Widget? get liveCommandIndicator {
    if (!_handsFreeVoiceMode) return null;
    final ready = _isListeningForVoiceCommand && !_voiceRenewing;
    final message = _manualScoreUsername != null
        ? 'Гараар оруулж байна — Enter дарж баталгаажуулна уу'
        : !ready
            ? '${_voiceFeedback ?? ''} Түр хүлээнэ үү…'.trim()
            : _voiceTranscript.isNotEmpty
                ? 'Таны команд: $_voiceTranscript'
                : '${_voiceFeedback == null ? '' : '${_voiceFeedback!} • '}${_voicePendingUsername == null ? 'Командаа хэлнэ үү' : 'Дараагийн командаа хэлнэ үү'}';
    return Text(message, maxLines: 2, overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(color: ready ? Colors.lightGreenAccent : Colors.white70, fontSize: 13));
  }
  bool _showVoiceStopHint = false;
  @override
  Widget? get liveCommandHint => _handsFreeVoiceMode && _showVoiceStopHint
      ? const Text('Микрофон унтраах: “Боллоо”',
          textAlign: TextAlign.right,
          style: TextStyle(color: Colors.white70, fontSize: 12))
      : null;
  String? _manualScoreUsername;
  String _voiceLastAccepted = 'Одоогоор команд бүртгэгдээгүй';
  String? _voicePendingUsername;
  String _lastVoiceInput = '';
  int _voiceSession = 0;
  bool _voiceRenewing = false;
  bool _handsFreeVoiceMode = false;
  bool _handsFreeCommandArmed = false;

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
  bool _roundSelectionConfirmed = false;

  bool get _isTwoPlayerMode => _activeSeatCount == 2;

  List<_MuushigSeat> get _activeSeats =>
      _seats.where((seat) => seat.isActive).toList(growable: false);

  int get _activeSeatCount => _activeSeats.length;

  void _applyTwoPlayerAlwaysPlaying() {
    if (_activeSeatCount != 2) return;
    _applyAllActivePlayersPlaying();
  }

  void _applyAllActivePlayersPlaying() {
    _needsPlaySelectionPrompt = false;
    _roundSelectionHistory.clear();
    _roundSelectionCursorUsername = null;
    _roundPlayChoices
      ..clear()
      ..addEntries(_activeSeats.map((seat) => MapEntry(seat.username, true)));
    _activePlayingUsernames
      ..clear()
      ..addAll(_activeSeats.map((seat) => seat.username));
    _roundSelectionConfirmed = true;
  }

  void _activatePendingRejoins() {
    _seats = _seats
        .map(
          (seat) => seat.isPendingRejoin
              ? seat.copyWith(
                  isActive: true,
                  isFinancialParticipant: true,
                  isPendingRejoin: false,
                )
              : seat,
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _currentRegistrarUserId = widget.currentUserId;

    _selectedUserIdsSnapshot = List<String>.from(widget.selectedUserIds);

    _seats = _selectedUserIdsSnapshot.isNotEmpty
        ? _buildSeatsFromSelectedUsers(_selectedUserIdsSnapshot)
        : _buildDefaultSeats();
    _selectedProfilesLoaded = _selectedUserIdsSnapshot.isEmpty;
    initializeLiveGame(() async {
      if (widget.selectedUserIds.isNotEmpty) {
        await _loadSelectedUserProfiles();
      }
      if (mounted) await _tryRestoreSavedSession();
    });



    for (final seat in _seats) {
      _roundScoreControllers[seat.username] = TextEditingController();
      _roundScoreFocusNodes[seat.username] = FocusNode();
      _roundDecisionFocusNodes[seat.username] = FocusNode();
    }

    if (_seats.length < 3 || _seats.length > 7) {
      _playerOrderSelected = true;
      _needsPlaySelectionPrompt = false;
    }

    if (_selectedUserIdsSnapshot.isNotEmpty) {}

    _applyTwoPlayerAlwaysPlaying();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
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

      if (userId != null &&
          userId.isNotEmpty &&
          !DemoPlayers.isDemoId(userId)) {
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
    final updatedDecisionFocusNodes = <String, FocusNode>{};
    final updatedActivePlaying = <String>{};
    final updatedPenaltyFive = <String>{};
    final updatedRoundChoices = <String, bool>{};

    for (final oldSeat in previousSeats) {
      final oldKey = oldSeat.username;
      final newKey = keyMapping[oldKey] ?? oldKey;

      final controller =
          _roundScoreControllers[oldKey] ?? TextEditingController();
      final focusNode = _roundScoreFocusNodes[oldKey] ?? FocusNode();
      final decisionFocusNode = _roundDecisionFocusNodes[oldKey] ?? FocusNode();

      updatedControllers[newKey] = controller;
      updatedFocusNodes[newKey] = focusNode;
      updatedDecisionFocusNodes[newKey] = decisionFocusNode;

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
      _roundDecisionFocusNodes
        ..clear()
        ..addAll(updatedDecisionFocusNodes);
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
      _applyTwoPlayerAlwaysPlaying();
    });
  }

  bool _areAllSeatChoicesMade() => _activeSeats
      .every((seat) => _roundPlayChoices.containsKey(seat.username));

  List<_MuushigSeat> _buildDefaultSeats() {
    return const [
      _MuushigSeat(
        username: 'Энхжин',
        displayName: 'Индиан',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        normalWins: 0,
        boltWins: 0,
        money: 0,
        bombs: 0,
        totalBombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Оч-Эрдэнэ',
        displayName: 'МС',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        normalWins: 0,
        boltWins: 0,
        money: 0,
        bombs: 0,
        totalBombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Батмагнай',
        displayName: 'Сыска',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        normalWins: 0,
        boltWins: 0,
        money: 0,
        bombs: 0,
        totalBombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Баарсайхан',
        displayName: 'Шовгор',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        normalWins: 0,
        boltWins: 0,
        money: 0,
        bombs: 0,
        totalBombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Лхаямгар',
        displayName: 'Шумуул',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        normalWins: 0,
        boltWins: 0,
        money: 0,
        bombs: 0,
        totalBombs: 0,
        isRoundPenaltyFive: false,
      ),
      _MuushigSeat(
        username: 'Сарантуяа',
        displayName: 'Базилио',
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        normalWins: 0,
        boltWins: 0,
        money: 0,
        bombs: 0,
        totalBombs: 0,
        isRoundPenaltyFive: false,
      ),
    ];
  }

  List<_MuushigSeat> _buildSeatsFromSelectedUsers(
      List<String> selectedUserIds) {
    return List<_MuushigSeat>.generate(selectedUserIds.length, (index) {
      final userId = selectedUserIds[index];
      final demo = DemoPlayers.byId(userId);
      return _MuushigSeat(
        username: demo?.username ?? 'u${index + 1}',
        displayName: demo?.displayName ?? 'Тоглогч ${index + 1}',
        userId: userId,
        roundScoreText: '-',
        totalScoreText: '15',
        wins: 0,
        normalWins: 0,
        boltWins: 0,
        money: 0,
        bombs: 0,
        totalBombs: 0,
        isRoundPenaltyFive: false,
      );
    });
  }

  Future<void> _tryRestoreSavedSession({SavedGameSession? remote}) async {
    final id = remote?.id ?? widget.initialSavedSessionId;
    if (id == null || id.isEmpty) return;

    final saved = remote ?? await _savedSessionsRepo.findById(id);
    if (!mounted || saved == null || saved.gameKey != 'muushig') return;

    final payload = saved.payload;
    final seatsPayload = (payload['seats'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
    if (seatsPayload.isEmpty) return;

    final restoredSeats = seatsPayload
        .map(
          (entry) => _MuushigSeat(
            userId: entry['userId'] as String?,
            username: (entry['username'] as String? ?? '').trim(),
            displayName: (entry['displayName'] as String? ?? '').trim(),
            photoUrl: entry['photoUrl'] as String?,
            roundScoreText: (entry['roundScoreText'] as String? ?? '-').trim(),
            totalScoreText: (entry['totalScoreText'] as String? ?? '15').trim(),
            wins: (entry['wins'] as num?)?.toInt() ?? 0,
            normalWins: (entry['normalWins'] as num?)?.toInt() ?? 0,
            boltWins: (entry['boltWins'] as num?)?.toInt() ?? 0,
            money: (entry['money'] as num?)?.toInt() ?? 0,
            bombs: (entry['bombs'] as num?)?.toInt() ?? 0,
            totalBombs: (entry['totalBombs'] as num?)?.toInt() ?? 0,
            isActive: entry['isActive'] as bool? ?? true,
            isFinancialParticipant:
                entry['isFinancialParticipant'] as bool? ?? true,
            isPendingRejoin: entry['isPendingRejoin'] as bool? ?? false,
            isRoundPenaltyFive: entry['isRoundPenaltyFive'] as bool? ?? false,
            isTotalScoreRed: entry['isTotalScoreRed'] as bool? ?? false,
          ),
        )
        .where((seat) => seat.username.isNotEmpty)
        .toList(growable: false);
    if (restoredSeats.isEmpty) return;

    final roundScoreInputs = Map<String, dynamic>.from(
      payload['roundScoreInputs'] as Map? ?? const {},
    );
    final restoredControllers = <String, TextEditingController>{};
    final restoredFocusNodes = <String, FocusNode>{};
    final restoredDecisionFocusNodes = <String, FocusNode>{};
    for (final seat in restoredSeats) {
      restoredControllers[seat.username] = TextEditingController(
        text: (roundScoreInputs[seat.username] as String? ?? '').trim(),
      );
      restoredFocusNodes[seat.username] = FocusNode();
      restoredDecisionFocusNodes[seat.username] = FocusNode();
    }

    for (final controller in _roundScoreControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _roundScoreFocusNodes.values) {
      focusNode.dispose();
    }
    for (final focusNode in _roundDecisionFocusNodes.values) {
      focusNode.dispose();
    }

    if (!mounted) return;
    setState(() {
      _activeSavedSessionId = id;
      _roundNumber = (payload['roundNumber'] as num?)?.toInt() ?? _roundNumber;
      _voiceRoundStart = payload['voiceRoundStart'] as String?;
      _playerOrderSelected =
          payload['playerOrderSelected'] as bool? ?? _playerOrderSelected;
      _isBoltMode = payload['isBoltMode'] as bool? ?? _isBoltMode;
      _isMiddleBoltMode =
          payload['isMiddleBoltMode'] as bool? ?? _isMiddleBoltMode;
      _normalRoundsPlayed = (payload['normalRoundsPlayed'] as num?)?.toInt() ??
          _normalRoundsPlayed;
      _totalBoltRounds =
          (payload['totalBoltRounds'] as num?)?.toInt() ?? _totalBoltRounds;
      _boltRoundsPlayed =
          (payload['boltRoundsPlayed'] as num?)?.toInt() ?? _boltRoundsPlayed;
      _sessionOrdinaryRounds =
          (payload['sessionOrdinaryRounds'] as num?)?.toInt() ??
              _sessionOrdinaryRounds;
      _sessionBoltRounds =
          (payload['sessionBoltRounds'] as num?)?.toInt() ?? _sessionBoltRounds;
      _sessionMiddleBoltRounds =
          (payload['sessionMiddleBoltRounds'] as num?)?.toInt() ??
              _sessionMiddleBoltRounds;
      _sessionCompleted =
          payload['sessionCompleted'] as bool? ?? _sessionCompleted;
      _needsPlaySelectionPrompt =
          payload['needsPlaySelectionPrompt'] as bool? ??
              _needsPlaySelectionPrompt;
      _selectedProfilesLoaded =
          payload['selectedProfilesLoaded'] as bool? ?? _selectedProfilesLoaded;
      _sessionAddedToStatistics =
          payload['sessionAddedToStatistics'] as bool? ?? false;
      _currentRegistrarUserId = payload['currentRegistrarUserId'] as String? ??
          _currentRegistrarUserId;
      _settlementMode = _MuushigSettlementMode.values[
          ((payload['settlementMode'] as num?)?.toInt() ??
                  _settlementMode.index)
              .clamp(0, _MuushigSettlementMode.values.length - 1)];
      _baseNormalAmount =
          (payload['baseNormalAmount'] as num?)?.toInt() ?? _baseNormalAmount;
      _baseBoltAmount =
          (payload['baseBoltAmount'] as num?)?.toInt() ?? _baseBoltAmount;
      _penaltyPerBomb =
          (payload['penaltyPerBomb'] as num?)?.toInt() ?? _penaltyPerBomb;
      _scoreRateNormal =
          (payload['scoreRateNormal'] as num?)?.toInt() ?? _scoreRateNormal;
      _scoreRateBolt =
          (payload['scoreRateBolt'] as num?)?.toInt() ?? _scoreRateBolt;
      _flatLoserNormal =
          (payload['flatLoserNormal'] as num?)?.toInt() ?? _flatLoserNormal;
      _flatLoserBolt =
          (payload['flatLoserBolt'] as num?)?.toInt() ?? _flatLoserBolt;
      _seats = restoredSeats;
      _roundScoreControllers
        ..clear()
        ..addAll(restoredControllers);
      _roundScoreFocusNodes
        ..clear()
        ..addAll(restoredFocusNodes);
      _roundDecisionFocusNodes
        ..clear()
        ..addAll(restoredDecisionFocusNodes);
      _activePlayingUsernames
        ..clear()
        ..addAll(
          (payload['activePlayingUsernames'] as List<dynamic>? ?? const [])
              .whereType<String>(),
        );
      _roundPlayChoices
        ..clear()
        ..addAll(
          Map<String, dynamic>.from(
            payload['roundPlayChoices'] as Map? ?? const {},
          ).map(
            (key, value) => MapEntry(key, value == true),
          ),
        );
      _penaltyFiveUsernames
        ..clear()
        ..addAll(
          (payload['penaltyFiveUsernames'] as List<dynamic>? ?? const [])
              .whereType<String>(),
        );
      _roundSelectionConfirmed =
          payload['roundSelectionConfirmed'] as bool? ?? _isTwoPlayerMode;
      _roundSelectionHistory.clear();
      _roundSelectionCursorUsername =
          _roundSelectionConfirmed ? null : _firstPendingSelectionUsername();
      _applyTwoPlayerAlwaysPlaying();
    });
  }

  Future<void> _saveProgress() async {
    final selectedUserIds = _seats
        .map((seat) => seat.userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final sessionId = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: 'muushig',
      gameLabel: 'Муушиг',
      selectedUserIds: selectedUserIds,
      payload: {
        'roundNumber': _roundNumber,
        'voiceRoundStart': _voiceRoundStart,
        'playerOrderSelected': _playerOrderSelected,
        'isBoltMode': _isBoltMode,
        'isMiddleBoltMode': _isMiddleBoltMode,
        'normalRoundsPlayed': _normalRoundsPlayed,
        'totalBoltRounds': _totalBoltRounds,
        'boltRoundsPlayed': _boltRoundsPlayed,
        'sessionOrdinaryRounds': _sessionOrdinaryRounds,
        'sessionBoltRounds': _sessionBoltRounds,
        'sessionMiddleBoltRounds': _sessionMiddleBoltRounds,
        'sessionCompleted': _sessionCompleted,
        'needsPlaySelectionPrompt': _needsPlaySelectionPrompt,
        'selectedProfilesLoaded': _selectedProfilesLoaded,
        'sessionAddedToStatistics': _sessionAddedToStatistics,
        'currentRegistrarUserId': _currentRegistrarUserId,
        'settlementMode': _settlementMode.index,
        'baseNormalAmount': _baseNormalAmount,
        'baseBoltAmount': _baseBoltAmount,
        'penaltyPerBomb': _penaltyPerBomb,
        'scoreRateNormal': _scoreRateNormal,
        'scoreRateBolt': _scoreRateBolt,
        'flatLoserNormal': _flatLoserNormal,
        'flatLoserBolt': _flatLoserBolt,
        'activePlayingUsernames': _activePlayingUsernames.toList(),
        'roundPlayChoices': Map<String, bool>.from(_roundPlayChoices),
        'roundSelectionConfirmed': _roundSelectionConfirmed,
        'penaltyFiveUsernames': _penaltyFiveUsernames.toList(),
        'roundScoreInputs': _roundScoreControllers.map(
          (key, controller) => MapEntry(key, controller.text),
        ),
        'seats': _seats
            .map(
              (seat) => {
                'userId': seat.userId,
                'username': seat.username,
                'displayName': seat.displayName,
                'photoUrl': seat.photoUrl,
                'roundScoreText': seat.roundScoreText,
                'totalScoreText': seat.totalScoreText,
                'wins': seat.wins,
                'normalWins': seat.normalWins,
                'boltWins': seat.boltWins,
                'money': seat.money,
                'bombs': seat.bombs,
                'totalBombs': seat.totalBombs,
                'isActive': seat.isActive,
                'isFinancialParticipant': seat.isFinancialParticipant,
                'isPendingRejoin': seat.isPendingRejoin,
                'isRoundPenaltyFive': seat.isRoundPenaltyFive,
                'isTotalScoreRed': seat.isTotalScoreRed,
              },
            )
            .toList(growable: false),
      },
    );

    _activeSavedSessionId = sessionId;
  }

  Future<void> _removeSavedProgressIfAny() async {
    final id = _activeSavedSessionId;
    if (id == null || id.isEmpty) return;
    await _savedSessionsRepo.removeById(id);
    _activeSavedSessionId = null;
  }

  @override
  void dispose() {
    _voiceStableTimer?.cancel();
    _voiceSession++;
    stopLiveGame();
    _handsFreeVoiceMode = false;
    _speech.stop();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    for (final controller in _roundScoreControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _roundScoreFocusNodes.values) {
      focusNode.dispose();
    }
    for (final focusNode in _roundDecisionFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String _normalizeVoiceText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^а-яөүёa-z0-9@]+'), ' ')
      .replaceAllMapped(
        RegExp(r'([а-яөүёa-z])([0-9])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'([0-9])([а-яөүёa-z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String? _nextVoiceScoreUsername() {
    for (final username in _voiceSeatOrder().where(_activePlayingUsernames.contains)) {
      if ((_roundScoreControllers[username]?.text.trim() ?? '').isEmpty) {
        return username;
      }
    }
    return null;
  }

  Set<String> _voiceAliasesForSeat(_MuushigSeat seat) {
    final aliases = <String>{
      _normalizeVoiceText(seat.displayName),
      _normalizeVoiceText(seat.username),
    };
    // Chrome Web Speech-ийн туршилтын нэрс дээр тогтмол гарч буй
    // дуудлагын хувилбарууд. Цаашид профайлд voice alias хадгалж өргөтгөнө.
    const commonAliases = <String, List<String>>{
      'ms': ['мс', 'эм эс'],
      'shovgor': ['шовгор'],
      'syska': ['сыска', 'сиска', 'сиська', 'сисга', 'систем'],
      'shuumul': ['шумуул', 'шуумул'],
      'indian': ['индиан', 'индианчук'],
    };
    aliases.addAll(commonAliases[seat.username.toLowerCase()] ?? const []);
    aliases.removeWhere((alias) => alias.isEmpty);
    return aliases;
  }

  void _showBriefVoiceMessage(String message) {
    setState(() => _voiceFeedback = message);
  }

  Future<void> _applyVoiceCommands(String spokenText, {bool isFinal = true}) async {
    if (!liveCanEdit || _isResolvingRound || _sessionCompleted) return;
    var text = _normalizeVoiceText(spokenText);
    if (text.isEmpty) return;
    final seats = _activeSeats.toList();
    final mention = lastVoicePlayerMention(text,
        seats.map(_voiceAliasesForSeat).toList());
    if (mention != null) {
      if (mention.playerIndex == null) {
        _showBriefVoiceMessage('Ижил нэртэй тоглогч байна. Өөр нэр, хочоор хэлнэ үү.');
        return;
      }
      final username = seats[mention.playerIndex!].username;
      if (_roundSelectionConfirmed && !_activePlayingUsernames.contains(username)) return;
      // A provisional name must not pull the cue back to an already entered
      // player. Confirmed name commands still allow intentional corrections.
      final alreadyEntered = _roundSelectionConfirmed
          ? (_roundScoreControllers[username]?.text.trim().isNotEmpty ?? false)
          : _roundPlayChoices.containsKey(username);
      if (!isFinal && alreadyEntered && username != _voicePendingUsername) return;
      setState(() => _voicePendingUsername = username);
      text = text.substring(mention.end).trim();
    }
    // Interim recognition selects a player, but never commits provisional scores.
    if (!isFinal || text.isEmpty) return;
    final command = parseMuushigVoiceCommand(text);
    if (command == null) {
      _showBriefVoiceMessage('Танигдсангүй. Дахин хэлнэ үү');
      return;
    }
    if (_voiceRoundStart == null && _voicePendingUsername == null) return;
    final username = _voicePendingUsername ?? (_roundSelectionConfirmed
        ? _nextVoiceScoreUsername() : _nextVoiceDecisionUsername());
    if (username == null) return;
    _voiceRoundStart ??= username;
    if (_roundSelectionConfirmed) {
      final score = command.score;
      if (score == null) {
        _showBriefVoiceMessage('Одоо зөвхөн оноо оруулна.');
        return;
      }
      final check = validateMuushigVoiceScore(score,
          _activePlayingUsernames.where((name) => name != username).map((name) {
        final raw = _roundScoreControllers[name]?.text.trim() ?? '';
        if (raw.isEmpty) return null;
        return _penaltyFiveUsernames.contains(name) ? 0 : int.tryParse(raw);
      }));
      if (!check.accepted) {
        setState(() => _voicePendingUsername = username);
        _roundScoreFocusNodes[username]?.requestFocus();
        _showBriefVoiceMessage(check.remaining == 0
            ? 'Идээ үлдээгүй. Уналт эсвэл 0 гэж хэлнэ үү.'
            : check.last
                ? 'Үлдсэн идээ ${check.remaining}. Оноогоо дахин хэлнэ үү.'
                : 'Үлдсэн идээ ${check.remaining}. Үүнээс их оноо оруулахгүй.');
        return;
      }
      setState(() {
        _roundScoreControllers[username]?.text = (score == 0 ? 5 : score).toString();
        _voiceLastAccepted = '${seats.firstWhere((s) => s.username == username).displayName}: оноо $score';
        _voiceFeedback = '✓ $_voiceLastAccepted';
        if (score == 0) {
          _penaltyFiveUsernames.add(username);
        } else {
          _penaltyFiveUsernames.remove(username);
        }
        _voicePendingUsername = _nextVoiceScoreUsername();
      });
      if (_voicePendingUsername == null) {
        await _completeScoreEntryAndPromptNextRoundPlayers();
        if (!mounted) return;
        setState(() => _voicePendingUsername = _voiceRoundStart == null ? null : (_roundSelectionConfirmed
            ? _nextVoiceScoreUsername() : _nextVoiceDecisionUsername()));
      }
    } else {
      if (command.score != null) {
        _showBriefVoiceMessage('Эхлээд орсон, өнжсөн төлвийг оруулна.');
        return;
      }
      final play = command.action == MuushigVoiceAction.play;
      if (_isBoltMode && !play) return;
      setState(() {
        _roundPlayChoices[username] = play;
        _showVoiceStopHint = false;
        _voiceLastAccepted = '${seats.firstWhere((s) => s.username == username).displayName}: ${play ? 'орсон' : 'өнжсөн'}';
        _voiceFeedback = '✓ $_voiceLastAccepted';
        if (play) {
          _activePlayingUsernames.add(username);
        } else {
          _activePlayingUsernames.remove(username);
        }
        if (_areAllSeatChoicesMade() && _activePlayingUsernames.length >= 2) {
          _roundSelectionConfirmed = true;
          _roundSelectionHistory.clear();
          _roundSelectionCursorUsername = null;
        }
        _voicePendingUsername = _roundSelectionConfirmed
            ? _nextVoiceScoreUsername() : _nextVoiceDecisionUsername();
      });
    }
    if (_roundSelectionConfirmed && _voicePendingUsername != null) {
      _roundScoreFocusNodes[_voicePendingUsername]?.requestFocus();
    }
  }

  List<String> _voiceSeatOrder() {
    final seats = _activeSeats.map((s) => s.username).toList();
    final start = seats.indexOf(_voiceRoundStart ?? '');
    if (start < 0) return seats;
    return [...seats.skip(start), ...seats.take(start)];
  }

  String? _nextVoiceDecisionUsername() => _voiceSeatOrder()
      .where((name) => !_roundPlayChoices.containsKey(name)).firstOrNull;
  Future<void> _handleHandsFreeFinalResult(String spokenText,
      {bool isFinal = true}) async {
    if (!_handsFreeVoiceMode) return;
    // A mouse-selected score field owns input until Enter submits it. Late
    // speech results must not move focus or overwrite an ongoing manual edit.
    if (_manualScoreUsername != null) {
      _voiceStableTimer?.cancel();
      _voiceStableText = '';
      _lastVoiceInput = _normalizeVoiceText(spokenText);
      if (isFinal && RegExp(r'(^|\s)боллоо(?=\s|$)').hasMatch(_lastVoiceInput)) {
        await _toggleHandsFreeVoiceMode();
      }
      return;
    }
    var text = _normalizeVoiceText(spokenText);
    if (text.isEmpty) return;
    text = muushigUnconsumedSpeech(text, _lastVoiceInput);
    if (text.isEmpty) {
      _voiceStableTimer?.cancel();
      _voiceStableText = '';
      return;
    }
    final finish = RegExp(r'(^|\s)боллоо(?=\s|$)').firstMatch(text);
    final command = finish == null ? text : text.substring(0, finish.start).trim();
    if (isFinal) _lastVoiceInput = _normalizeVoiceText(spokenText);
    if (isFinal) {
      _voiceStableTimer?.cancel();
      _voiceStableText = '';
    } else if (_voiceStableText != spokenText) {
      _voiceStableTimer?.cancel();
      _voiceStableText = spokenText;
      final session = _voiceSession;
      _voiceStableTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted || !_handsFreeVoiceMode || session != _voiceSession) return;
        _handleHandsFreeFinalResult(spokenText, isFinal: true);
      });
    }
    if (command.isNotEmpty) await _applyVoiceCommands(command, isFinal: isFinal);
    if (finish != null && isFinal && mounted && _handsFreeVoiceMode) {
      await _toggleHandsFreeVoiceMode();
    } else if (isFinal && mounted && _handsFreeVoiceMode) {
      await _renewVoiceCommandSession();
    }
  }
  Future<void> _renewVoiceCommandSession() async {
    if (_voiceRenewing || !mounted || !_handsFreeVoiceMode) return;
    _voiceRenewing = true;
    setState(() => _isListeningForVoiceCommand = false);
    _voiceSession++; // Invalidate late callbacks before stopping recognition.
    _voiceStableTimer?.cancel();
    _voiceStableText = '';
    try {
      await _speech.stop();
      if (mounted && _handsFreeVoiceMode) {
        await _startHandsFreeListeningSession();
      }
    } finally {
      if (mounted) setState(() => _voiceRenewing = false);
      else _voiceRenewing = false;
    }
  }

  Future<void> _restartHandsFreeListening() async {
    if (!_handsFreeVoiceMode || !mounted || _voiceRenewing) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!_handsFreeVoiceMode || !mounted || _speech.isListening || _voiceRenewing) return;
    await _startHandsFreeListeningSession();
  }

  Future<void> _startHandsFreeListeningSession() async {
    if (!_handsFreeVoiceMode || !mounted) return;
    _voiceStableTimer?.cancel();
    _voiceStableText = '';
    final session = ++_voiceSession;
    if (!_speechReady) {
      return;
    }
    final locales = await _speech.locales();
    final mongolian = locales
        .where((locale) => locale.localeId.toLowerCase().startsWith('mn'))
        .firstOrNull;
    if (!mounted || !_handsFreeVoiceMode || session != _voiceSession) return;
    setState(() {
      _isListeningForVoiceCommand = false;
      _voiceTranscript = '';
      _lastVoiceInput = '';
    });
    await _speech.listen(
      onResult: (result) {
        if (!mounted || session != _voiceSession) return;
        setState(() {
          _voiceTranscript = result.recognizedWords;
          _voiceTranscriptFinal = result.finalResult;
        });

        _handleHandsFreeFinalResult(result.recognizedWords,
            isFinal: result.finalResult);
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: mongolian?.localeId,
        partialResults: true,
      ),
    );
  }

  Future<void> _toggleHandsFreeVoiceMode() async {
    _manualScoreUsername = null;
    if (_handsFreeVoiceMode) {
      _voiceStableTimer?.cancel();
      _voiceStableText = '';
      _voiceSession++;
      setState(() {
        _handsFreeVoiceMode = false;
        _isListeningForVoiceCommand = false;
        _handsFreeCommandArmed = false;
        _voicePendingUsername = null;
      });
      await _speech.stop();
      return;
    }

    {
      _speechReady = await initializeGameSpeech(_speech,
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'listening') {
            setState(() => _isListeningForVoiceCommand = true);
          }
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListeningForVoiceCommand = false);
            _restartHandsFreeListening();
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isListeningForVoiceCommand = false;
            _handsFreeVoiceMode = false;
        _isListeningForVoiceCommand = false;
            _handsFreeCommandArmed = false;
            _voicePendingUsername = null;
            _voiceSession++;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Дуу таних алдаа: ${error.errorMsg}')),
          );
        },
      );
    }
    if (!mounted || !_speechReady) return;
    setState(() {
      _handsFreeVoiceMode = true;
      _handsFreeCommandArmed = true;
      _voiceTranscript = '';
      _voiceFeedback = null;
      _showVoiceStopHint = true;
      _voiceTranscriptFinal = false;
      _voiceLastAccepted = 'Одоогоор команд бүртгэгдээгүй';
      _voicePendingUsername = null;
    });
    await _startHandsFreeListeningSession();
  }

  Future<void> _removePlayerFromGame() async {
    final candidates = _activeSeats;
    if (candidates.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Хамгийн багадаа 2 тоглогч үлдэнэ.')),
      );
      return;
    }

    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Тоглолтоос гарах тоглогч'),
        children: candidates
            .map(
              (seat) => SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(seat.username),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(seat.displayName),
                  subtitle: Text('@${seat.username}'),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (!mounted || username == null) return;

    final seat = _seats.firstWhere((item) => item.username == username);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Тоглолтоос гаргах уу?'),
        content: Text(
          '${seat.displayName} цааш тоглохгүй. Өмнө тоглосон гаруудын мөнгө, уналтын торгууль хадгалагдаж, дараагийн гаруудаас төлбөр тооцохгүй.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Болих'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Тоглолтоос гаргах'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() {
      final index = _seats.indexWhere((item) => item.username == username);
      if (index < 0) return;
      _seats[index] = _seats[index].copyWith(
        isActive: false,
        isFinancialParticipant: false,
        roundScoreText: '-',
        isRoundPenaltyFive: false,
      );
      _activePlayingUsernames.remove(username);
      _roundPlayChoices.remove(username);
      _penaltyFiveUsernames.remove(username);
      _roundSelectionHistory.remove(username);
      _roundScoreControllers[username]?.clear();

      if (_isBoltMode) {
        _applyAllActivePlayersPlaying();
      } else if (_activeSeatCount == 2) {
        _applyTwoPlayerAlwaysPlaying();
      }
    });
  }

  Future<void> _restorePlayerToGame() async {
    final candidates = _seats
        .where((seat) => !seat.isActive && !seat.isPendingRejoin)
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Буцаан оруулах тоглогч алга.')),
      );
      return;
    }

    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Тоглолтод буцаан оруулах'),
        children: candidates
            .map(
              (seat) => SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(seat.username),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(seat.displayName),
                  subtitle: Text('@${seat.username}'),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (!mounted || username == null) return;

    final startsNextHand = _roundSelectionConfirmed;
    setState(() {
      final index = _seats.indexWhere((seat) => seat.username == username);
      if (index < 0) return;
      _seats[index] = _seats[index].copyWith(
        isActive: !startsNextHand,
        isFinancialParticipant: !startsNextHand,
        isPendingRejoin: startsNextHand,
        roundScoreText: '-',
        totalScoreText: '15',
        bombs: 0,
        isRoundPenaltyFive: false,
        isTotalScoreRed: false,
      );
      if (!startsNextHand && _isBoltMode) {
        _applyAllActivePlayersPlaying();
      } else if (!startsNextHand && _activeSeatCount == 2) {
        _applyTwoPlayerAlwaysPlaying();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(startsNextHand
            ? 'Тоглогч дараагийн гараас оролцоно.'
            : 'Тоглогч тоглолтод буцаж орлоо.'),
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
                            const Text('Суурь (5000/10000) + Уналт × 500'),
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
                              labelText: 'Торгууль / уналт'),
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
    if (widget.autoReturnOnWinner) {
      return;
    }

    var winnerGain = 0;
    for (int i = 0; i < updatedSeats.length; i++) {
      if (i == winnerIndex) continue;
      final loser = updatedSeats[i];
      if (!loser.isFinancialParticipant) continue;
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
      updatedSeats[winnerIndex] = winner.copyWith(
        wins: winner.wins + 1,
        normalWins: _isBoltMode ? winner.normalWins : winner.normalWins + 1,
        boltWins: _isBoltMode ? winner.boltWins + 1 : winner.boltWins,
      );
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
      final activeBeforeOrdering = _activeSeats;
      await showPlayerOrderDialog(
        activeBeforeOrdering.map((seat) => seat.username).toList(),
        activeBeforeOrdering.map((seat) => seat.displayName).toList(),
        activeBeforeOrdering.map((seat) => seat.photoUrl).toList(),
        (orderedIndices) {
          setState(() {
            final inactiveSeats =
                _seats.where((seat) => !seat.isActive).toList(growable: false);
            _seats = [
              ...orderedIndices.map((index) => activeBeforeOrdering[index]),
              ...inactiveSeats,
            ];
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
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('middle_bolt'),
              child: const Text('Дундаа боох'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop('exit'),
              child: const Text('Дуусгах'),
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
    final removedPlayers = _seats.where((seat) => !seat.isActive).length;
    final rows = <String>[];
    for (int i = 0; i < _seats.length; i++) {
      final seat = _seats[i];
      rows.add(
        '${i + 1}. ${seat.displayName} (@${seat.username}): '
        '₮${seat.money}, нийт унасан: ${seat.totalBombs}'
        '${seat.isActive ? '' : seat.isPendingRejoin ? ', дараагийн гараас орно' : ', тоглолтоос гарсан'}',
      );
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
          '${seat.totalBombs}',
          seat.isActive
              ? 'Идэвхтэй'
              : seat.isPendingRejoin
                  ? 'Дараагийн гараас орно'
                  : 'Тоглолтоос гарсан',
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
          pw.Text(
              'Хассан тоглогч: ${_seats.where((seat) => !seat.isActive).length}'),
          pw.Text('Нийт раунд: $totalRounds'),
          pw.Text('Энгийн тоглолт: $_sessionOrdinaryRounds'),
          pw.Text('Боолт тоглолт: $_sessionBoltRounds'),
          pw.Text('Дундын боолт: $_sessionMiddleBoltRounds'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'Display name',
              'Username',
              'Мөнгө (₮)',
              'Нийт унасан',
              'Төлөв'
            ],
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

  Future<void> _shareSessionReport() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _buildSessionReportText(),
          subject: 'Муушиг - тоглолтын тайлан',
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
      Navigator.of(context).pop();
    }
  }

  Future<bool> _showExitReportDialog() async {
    await _showExitReportAndFinish();
    return false;
  }

  void _resetBoardForNextGame() {
    _activatePendingRejoins();
    _seats = _seats
        .map(
          (seat) => seat.copyWith(
            roundScoreText: '-',
            totalScoreText: '15',
            bombs: 0,
            isRoundPenaltyFive: false,
            isTotalScoreRed: false,
          ),
        )
        .toList();

    for (final controller in _roundScoreControllers.values) {
      controller.clear();
    }
    _penaltyFiveUsernames.clear();
    _roundPlayChoices.clear();
    _activePlayingUsernames.clear();
    _roundSelectionHistory.clear();
    _roundSelectionCursorUsername = null;
    _roundSelectionConfirmed = false;
    if (_isBoltMode) {
      _applyAllActivePlayersPlaying();
    } else {
      _applyTwoPlayerAlwaysPlaying();
    }
    _focusFirstDecisionNode();
  }

  void _resetForReplayKeepingMoneyOnly() {
    _seats = _seats
        .map(
          (seat) => seat.copyWith(
            wins: 0,
            normalWins: 0,
            boltWins: 0,
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
    _roundSelectionHistory.clear();
    _roundSelectionCursorUsername = null;
    _roundSelectionConfirmed = false;
    _applyTwoPlayerAlwaysPlaying();
    _sessionCompleted = false;
  }

  Future<void> _handleCycleCompletedFlow() async {
    final action = await _showCycleCompletedDialog();
    if (!mounted) return;

    if (action == 'replay') {
      setState(_resetForReplayKeepingMoneyOnly);
      return;
    }

    if (action == 'middle_bolt') {
      setState(() {
        _sessionCompleted = false;
        _isBoltMode = true;
        _isMiddleBoltMode = true;
        _totalBoltRounds = 1;
        _boltRoundsPlayed = 0;
      });
      await _prepareNextBoltRound();
      if (mounted) setState(_resetBoardForNextGame);
      return;
    }

    if (action == 'exit') {
      await _showExitReportAndFinish();
    }
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
        _activeSeats.isNotEmpty && _activeSeats.every((seat) => seat.wins == 1);
    if (allSingleWin) {
      _sessionCompleted = true;
      if (!mounted) return;
      await _handleCycleCompletedFlow();
      return;
    }

    final winlessCount = _activeSeats.where((seat) => seat.wins == 0).length;
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
                                                      'assets/muushig.jpg',
                                                      fit: BoxFit.cover,
                                                    );
                                                  },
                                                );
                                              }
                                              return Image.asset(
                                                'assets/muushig.jpg',
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
                                                      .withValues(alpha: 0.05),
                                                  Colors.black
                                                      .withValues(alpha: 0.7),
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
                            Navigator.of(this.context).pop();
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
    final selectableSeats = _activeSeats;
    final Set<int> selectedIndices = <int>{
      for (int i = 0; i < selectableSeats.length; i++)
        if (_activePlayingUsernames.contains(selectableSeats[i].username)) i,
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
            final dialogWidth = selectableSeats.length * cardWidth +
                (selectableSeats.length - 1) * cardSpacing;

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
                          for (int i = 0; i < selectableSeats.length; i++) ...[
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
                                                  selectableSeats[i].photoUrl;
                                              if (photoUrl != null &&
                                                  photoUrl.isNotEmpty) {
                                                return Image.network(
                                                  photoUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (context, _, __) {
                                                    return Image.asset(
                                                      'assets/muushig.jpg',
                                                      fit: BoxFit.cover,
                                                    );
                                                  },
                                                );
                                              }
                                              return Image.asset(
                                                'assets/muushig.jpg',
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
                                                      .withValues(alpha: 0.05),
                                                  Colors.black
                                                      .withValues(alpha: 0.7),
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
                                                selectableSeats[i].displayName,
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
                                                selectableSeats[i].username,
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
                            if (i != selectableSeats.length - 1)
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
                                      ..addAll(selectedIndices.map((index) =>
                                          selectableSeats[index].username));
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
    if (!_roundSelectionConfirmed) return;
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

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (!liveCanEdit) return false;
    if (event is! KeyDownEvent) return false;
    if (!mounted) return false;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null) return false;

    String? scoreUsername;
    for (final entry in _roundScoreFocusNodes.entries) {
      if (entry.value == primaryFocus) {
        scoreUsername = entry.key;
        break;
      }
    }
    if (scoreUsername != null) {
      if (!_roundSelectionConfirmed) {
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _undoLastSeatSelection();
          return true;
        }
        if (event.logicalKey == LogicalKeyboardKey.space) {
          _markSeatSelectionAndAdvance(scoreUsername, false);
          return true;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          _markSeatSelectionAndAdvance(scoreUsername, true);
          return true;
        }
        return false;
      }

      if (event.logicalKey == LogicalKeyboardKey.space) {
        return false;
      }
      // Keep physical number entry working even when the browser's text-input
      // connection has not reopened after the read-only decision phase.
      final keyboard = HardwareKeyboard.instance;
      if (!keyboard.isControlPressed && !keyboard.isMetaPressed &&
          !keyboard.isAltPressed && !keyboard.isShiftPressed &&
          _activePlayingUsernames.contains(scoreUsername)) {
        final digits = <LogicalKeyboardKey, int>{
          LogicalKeyboardKey.digit0: 0, LogicalKeyboardKey.numpad0: 0,
          LogicalKeyboardKey.digit1: 1, LogicalKeyboardKey.numpad1: 1,
          LogicalKeyboardKey.digit2: 2, LogicalKeyboardKey.numpad2: 2,
          LogicalKeyboardKey.digit3: 3, LogicalKeyboardKey.numpad3: 3,
          LogicalKeyboardKey.digit4: 4, LogicalKeyboardKey.numpad4: 4,
          LogicalKeyboardKey.digit5: 5, LogicalKeyboardKey.numpad5: 5,
        };
        final score = digits[event.logicalKey];
        if (score != null) {
          final controller = _roundScoreControllers[scoreUsername];
          if (controller == null) return false;
          _voiceStableTimer?.cancel();
          _voiceStableText = '';
          setState(() {
            _manualScoreUsername = scoreUsername;
            _voicePendingUsername = scoreUsername;
            controller.value = TextEditingValue(
              text: '$score', selection: const TextSelection.collapsed(offset: 1));
            _penaltyFiveUsernames.remove(scoreUsername);
          });
          return true;
        }
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        if (_roundPlayChoices[scoreUsername] == true) {
          _onRoundScoreSubmitted(scoreUsername);
        } else {
          _focusNextActiveScoreNode(scoreUsername);
        }
        return true;
      }
      return false;
    }

    return false;
  }

  void _focusFirstDecisionNode() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_roundSelectionConfirmed) {
        if (_roundSelectionCursorUsername != null) {
          setState(() {
            _roundSelectionCursorUsername = null;
          });
        }
        _focusFirstActiveScoreField();
        return;
      }
      for (final seat in _activeSeats) {
        if (_roundPlayChoices[seat.username] == null) {
          if (_roundSelectionCursorUsername != seat.username) {
            setState(() {
              _roundSelectionCursorUsername = seat.username;
            });
          }
          _roundScoreFocusNodes[seat.username]?.requestFocus();
          return;
        }
      }
      if (_roundSelectionCursorUsername != null) {
        setState(() {
          _roundSelectionCursorUsername = null;
        });
      }
      _focusFirstActiveScoreField();
    });
  }

  void _focusNextActiveScoreNode(String currentUsername) {
    if (!_areAllSeatChoicesMade()) {
      _focusNextSelectionOrActive(currentUsername);
      return;
    }
    final activePlayers = _activePlayersInSeatOrder();
    if (activePlayers.isEmpty) return;
    final currentIdx = activePlayers.indexOf(currentUsername);
    if (currentIdx == -1) {
      _roundScoreFocusNodes[activePlayers.first]?.requestFocus();
      return;
    }
    final nextIdx = (currentIdx + 1) % activePlayers.length;
    _roundScoreFocusNodes[activePlayers[nextIdx]]?.requestFocus();
  }

  void _focusNextSelectionOrActive(String currentUsername) {
    final seatOrder = _activeSeats.map((s) => s.username).toList();
    final currentIdx = seatOrder.indexOf(currentUsername);
    if (currentIdx == -1 || seatOrder.isEmpty) return;
    for (int i = 1; i < seatOrder.length; i++) {
      final nextIdx = (currentIdx + i) % seatOrder.length;
      final nextUsername = seatOrder[nextIdx];
      if (_roundPlayChoices[nextUsername] == null) {
        if (_roundSelectionCursorUsername != nextUsername) {
          setState(() {
            _roundSelectionCursorUsername = nextUsername;
          });
        }
        _roundScoreFocusNodes[nextUsername]?.requestFocus();
        return;
      }
    }
    if (_roundSelectionCursorUsername != null) {
      setState(() {
        _roundSelectionCursorUsername = null;
      });
    }
    _focusFirstActiveScoreField();
  }

  void _completeSelectionStep(String currentUsername) {
    if (!_areAllSeatChoicesMade()) {
      _focusNextSelectionOrActive(currentUsername);
      return;
    }
    if (_activePlayingUsernames.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Хамгийн багадаа 2 тоглогч орсон байх ёстой.'),
        ),
      );
      return;
    }
    setState(() {
      _roundSelectionConfirmed = true;
      _roundSelectionCursorUsername = null;
      _roundSelectionHistory.clear();
    });
    _focusFirstActiveScoreField();
  }

  String? _firstPendingSelectionUsername() {
    for (final seat in _activeSeats) {
      if (_roundPlayChoices[seat.username] == null) {
        return seat.username;
      }
    }
    return null;
  }

  void _markSeatSelectionAndAdvance(String username, bool shouldPlay) {
    if (_isTwoPlayerMode || _roundSelectionConfirmed) return;
    if (!_activeSeats.any((seat) => seat.username == username)) return;

    setState(() {
      _roundPlayChoices[username] = shouldPlay;
      _showVoiceStopHint = false;
      if (shouldPlay) {
        _activePlayingUsernames.add(username);
      } else {
        _activePlayingUsernames.remove(username);
        _roundScoreControllers[username]?.clear();
        _penaltyFiveUsernames.remove(username);
      }
      _roundSelectionHistory.remove(username);
      _roundSelectionHistory.add(username);
    });

    _completeSelectionStep(username);
  }

  void _undoLastSeatSelection() {
    if (_isTwoPlayerMode || _roundSelectionConfirmed) return;
    if (_roundSelectionHistory.isEmpty) return;

    final username = _roundSelectionHistory.removeLast();
    setState(() {
      _roundPlayChoices.remove(username);
      _activePlayingUsernames.remove(username);
      _roundScoreControllers[username]?.clear();
      _penaltyFiveUsernames.remove(username);
      _roundSelectionCursorUsername = username;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _roundScoreFocusNodes[username]?.requestFocus();
    });
  }

  Future<void> _onRoundScoreSubmitted(String username) async {
    if (!_roundSelectionConfirmed || !_activePlayingUsernames.contains(username)) return;

    final controller = _roundScoreControllers[username];
    final rawText = controller?.text.trim() ?? '';
    final score = int.tryParse(rawText);
    if (score == null || score < 0 || score > 5) {
      _roundScoreFocusNodes[username]?.requestFocus();
      return;
    }
    if (rawText == '0') {
      controller?.text = '5';
      controller?.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
      if (!_penaltyFiveUsernames.contains(username)) {
        setState(() {
          _penaltyFiveUsernames.add(username);
        });
      }
    } else if (rawText != '5' && _penaltyFiveUsernames.contains(username)) {
      setState(() {
        _penaltyFiveUsernames.remove(username);
      });
    }

    final activePlayers = _activePlayersInSeatOrder();
    final currentIndex = activePlayers.indexOf(username);
    if (currentIndex == -1) return;

    if (currentIndex < activePlayers.length - 1) {
      _manualScoreUsername = null;
      _voicePendingUsername = activePlayers[currentIndex + 1];
      final nextFocus = _roundScoreFocusNodes[activePlayers[currentIndex + 1]];
      nextFocus?.requestFocus();
      return;
    }

    await _completeScoreEntryAndPromptNextRoundPlayers();
  }

  Future<void> _completeScoreEntryAndPromptNextRoundPlayers() async {
    final activePlayers = _activePlayersInSeatOrder();
    if (activePlayers.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Space дарж хамгийн багадаа 2 тоглогчийг идэвхжүүлнэ үү.'),
        ),
      );
      return;
    }

    // An empty field is still awaiting input, never an implicit penalty.
    for (final username in activePlayers) {
      final score = int.tryParse(_roundScoreControllers[username]?.text.trim() ?? '');
      if (score == null || score < 0 || score > 5) {
        _roundScoreFocusNodes[username]?.requestFocus();
        return;
      }
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
        totalBombs: isPenaltyFive ? seat.totalBombs + 1 : seat.totalBombs,
        isRoundPenaltyFive: isPenaltyFive,
        isTotalScoreRed: isPenaltyFive,
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
      if (updatedSeats[i].isActive && total <= 0) {
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
        final winnerSeat = updatedSeats[winnerIndex];
        updatedSeats[winnerIndex] = winnerSeat.copyWith(
          wins: winnerSeat.wins + 1,
          normalWins:
              _isBoltMode ? winnerSeat.normalWins : winnerSeat.normalWins + 1,
          boltWins: _isBoltMode ? winnerSeat.boltWins + 1 : winnerSeat.boltWins,
        );
        _applySettlementForWinner(updatedSeats, winnerIndex);
      }

      _seats = updatedSeats;
      _voiceRoundStart = null;
      _voicePendingUsername = null;
      _activatePendingRejoins();

      for (final controller in _roundScoreControllers.values) {
        controller.clear();
      }
      _penaltyFiveUsernames.clear();
      _roundPlayChoices.clear();
      _activePlayingUsernames.clear();
      _roundSelectionHistory.clear();
      _roundSelectionCursorUsername = null;
      _roundSelectionConfirmed = false;
      _manualScoreUsername = null;
      _showVoiceStopHint = true;
      if (_isBoltMode) {
        _applyAllActivePlayersPlaying();
      } else {
        _applyTwoPlayerAlwaysPlaying();
      }
    });

    if (winnerIndex == null) {
      _focusFirstDecisionNode();
      return;
    }

    if (widget.autoReturnOnWinner && !_multiAutoReturnTriggered) {
      _multiAutoReturnTriggered = true;
      final winnerSeat = _seats[winnerIndex];
      final winnerUserId = winnerSeat.userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop(<String, dynamic>{
          'completedGame': 'muushig',
          if (winnerUserId != null && winnerUserId.isNotEmpty)
            'winnerUserId': winnerUserId,
        });
      });
      return;
    }
    await _advanceAfterWinner();
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
                                                'assets/muushig.jpg',
                                                fit: BoxFit.cover,
                                              );
                                            },
                                          );
                                        }
                                        return Image.asset(
                                          'assets/muushig.jpg',
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
                                                .withValues(alpha: 0.05),
                                            Colors.black.withValues(alpha: 0.7),
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
    if (widget.autoReturnOnWinner && !_multiAutoReturnTriggered) {
      _multiAutoReturnTriggered = true;
      final winnerUserId = winnerSeat.userId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop(<String, dynamic>{
          'completedGame': 'muushig',
          if (winnerUserId != null && winnerUserId.isNotEmpty)
            'winnerUserId': winnerUserId,
        });
      });
      return;
    }

    await _removeSavedProgressIfAny();
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

  Color _bottomCellBorderColor(_MuushigSeat? seat) {
    if (seat == null) return Colors.white24;
    if (!_roundSelectionConfirmed &&
        _roundSelectionCursorUsername == seat.username) {
      return Colors.white;
    }
    return _seatStateBorderColor(seat);
  }

  double _bottomCellBorderWidth(_MuushigSeat? seat) {
    if (seat != null &&
        !_roundSelectionConfirmed &&
        _roundSelectionCursorUsername == seat.username) {
      return 3;
    }
    return 2;
  }

  _MuushigSeat? _seatForVisualSlot(int index) {
    if (index < 0 || index >= 7 || index >= _seats.length) {
      return null;
    }
    return _seats[index];
  }

  Color _seatStateBorderColor(_MuushigSeat? seat) {
    if (seat == null) return Colors.white24;
    if (!seat.isActive) return Colors.black54;
    final playChoice = _roundPlayChoices[seat.username];
    if (playChoice == true) {
      return Colors.green;
    }
    if (playChoice == false) return Colors.red;
    return Colors.white54;
  }

  Color _seatStateBadgeFillColor(_MuushigSeat? seat) {
    if (seat == null) return const Color(0xFFCC6046);
    if (!seat.isActive) return Colors.grey.shade700;
    final playChoice = _roundPlayChoices[seat.username];
    if (playChoice == true) return const Color(0xFF2E9B43);
    if (playChoice == false) return const Color(0xFFD3B12E);
    return const Color(0xFFCC6046);
  }

  Color _seatStateBadgeTextColor(_MuushigSeat? seat) {
    if (seat == null) return Colors.white;
    if (!seat.isActive) return Colors.white70;
    final playChoice = _roundPlayChoices[seat.username];
    if (playChoice == false) return Colors.black;
    return Colors.white;
  }

  void _handleWrittenSeatTap(_MuushigSeat? seat) {
    if (seat == null || !seat.isActive) return;
    if (_roundSelectionConfirmed) {
      if (_roundPlayChoices[seat.username] == true) {
        _roundScoreFocusNodes[seat.username]?.requestFocus();
      }
      return;
    }
    final current = _roundPlayChoices[seat.username];
    // Эхний даралт = орсон, хоёр дахь = өнжсөн, гурав дахь = орсон.
    _markSeatSelectionAndAdvance(seat.username, current != true);
  }

  Widget _buildSeatCard(
      int index, _MuushigSeat? seat, double blockWidth, double blockHeight,
      [bool compact = false]) => VoicePlayerCue(
        active: liveCanEdit && !_roundSelectionConfirmed && !_sessionCompleted && seat != null &&
            seat.isActive && seat.username == _voicePendingUsername &&
            (_isListeningForVoiceCommand || _handsFreeVoiceMode),
        child: _buildSeatCardContent(index, seat, blockWidth, blockHeight, compact),
      );

  Widget _buildSeatCardContent(
      int index, _MuushigSeat? seat, double blockWidth, double blockHeight,
      [bool compact = false]) {
    final isTopCard = !compact;
    final borderColor = _seatStateBorderColor(seat);
    final multiWins =
        seat == null ? 0 : (widget.multiWinsByUserId?[seat.userId ?? ''] ?? 0);

    if (isTopCard) {
      final imageHeight = (blockHeight * 0.43).clamp(98.0, 176.0).toDouble();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleWrittenSeatTap(seat),
        child: SizedBox(
          width: blockWidth,
          height: blockHeight,
          child: Card(
            elevation: 0,
            color: seat == null
                ? const Color(0xFFBE755F)
                : const Color(0xFFCC6046),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: borderColor, width: 4),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: imageHeight,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: seat == null
                              ? Container(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  child: const Center(
                                    child: Icon(
                                      Icons.person_outline,
                                      size: 56,
                                      color: Colors.white70,
                                    ),
                                  ),
                                )
                              : (seat.photoUrl != null &&
                                      seat.photoUrl!.isNotEmpty)
                                  ? Image.network(
                                      seat.photoUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, _, __) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.28),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.person,
                                            size: 56,
                                            color: Color(0xFF8E2F1E),
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.28),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.person,
                                        size: 56,
                                        color: Color(0xFF8E2F1E),
                                      ),
                                    ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF7A2E16),
                          foregroundColor: Colors.white,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (seat != null && widget.multiWinsByUserId != null)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.emoji_events,
                                    color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '$multiWins',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (seat != null) ...[
                    Text(
                      seat.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      seat.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                  ] else
                    const SizedBox(height: 40),
                  const SizedBox(height: 2),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: blockWidth * 0.50,
                        height: 102,
                        child: _buildRightScoreCell(
                          title: 'Нийт',
                          value: seat?.totalScoreText ?? '-',
                          isRed: seat?.isTotalScoreRed ?? false,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star,
                                        color: Colors.amber, size: 18),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${seat?.normalWins ?? 0}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        color: seat == null
                                            ? Colors.white70
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star,
                                        color: Colors.amber, size: 16),
                                    const SizedBox(width: 1),
                                    const Icon(Icons.star,
                                        color: Colors.amber, size: 16),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${seat?.boltWins ?? 0}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                        color: seat == null
                                            ? Colors.white70
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('💣',
                                        style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 3),
                                    Text(
                                      'x ${seat?.bombs ?? 0}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        color: seat == null
                                            ? Colors.white70
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '∑ ${seat?.totalBombs ?? 0}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: seat == null
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Text(
                                  '₮',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '${seat?.money ?? 0}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 24,
                                    color: seat == null
                                        ? Colors.white70
                                        : (seat.money < 0
                                            ? Colors.black
                                            : Colors.green),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final rowBorder = _seatStateBorderColor(seat);
    final nameColor = seat == null ? Colors.white70 : Colors.white;
    final imageHeight = (blockHeight - 16).clamp(72.0, 160.0).toDouble();
    final imageWidth = imageHeight;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleWrittenSeatTap(seat),
      child: SizedBox(
        width: blockWidth,
        height: blockHeight,
        child: Card(
          elevation: 0,
          color:
              seat == null ? const Color(0xFFB16D59) : const Color(0xFF9A4A37),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: rowBorder, width: 3),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: seat == null
                              ? Container(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  child: const Icon(
                                    Icons.person_outline,
                                    color: Colors.white70,
                                    size: 48,
                                  ),
                                )
                              : (seat.photoUrl != null &&
                                      seat.photoUrl!.isNotEmpty)
                                  ? Image.network(
                                      seat.photoUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, _, __) {
                                        return Container(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          child: const Icon(
                                            Icons.person,
                                            color: Colors.white70,
                                            size: 44,
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      color:
                                          Colors.white.withValues(alpha: 0.2),
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white70,
                                        size: 44,
                                      ),
                                    ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF7A2E16),
                          foregroundColor: Colors.white,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        seat?.displayName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        seat?.username ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: seat == null ? Colors.white60 : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            '₮',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 22),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${seat?.money ?? 0}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: seat == null
                                      ? Colors.white70
                                      : (seat.money < 0
                                          ? Colors.black
                                          : Colors.lightGreenAccent),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 17),
                              const SizedBox(width: 3),
                              Text(
                                '${seat?.normalWins ?? 0}',
                                style: TextStyle(
                                  color: seat == null
                                      ? Colors.white70
                                      : Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 14),
                              const SizedBox(width: 1),
                              const Icon(Icons.star,
                                  color: Colors.amber, size: 14),
                              const SizedBox(width: 3),
                              Text(
                                '${seat?.boltWins ?? 0}',
                                style: TextStyle(
                                  color: seat == null
                                      ? Colors.white70
                                      : Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('💣', style: TextStyle(fontSize: 16)),
                              const SizedBox(width: 3),
                              Text(
                                'x ${seat?.bombs ?? 0}',
                                style: TextStyle(
                                  color: seat == null
                                      ? Colors.white70
                                      : Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '∑ ${seat?.totalBombs ?? 0}',
                            style: TextStyle(
                              color:
                                  seat == null ? Colors.white70 : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox.expand(
                    child: _buildRightScoreCell(
                      title: 'Нийт',
                      value: seat?.totalScoreText ?? '-',
                      isRed: seat?.isTotalScoreRed ?? false,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomScoreControlBar(double blockWidth, double blockHeight) {
    return SizedBox(
      width: blockWidth,
      height: blockHeight,
      child: Card(
        elevation: 0,
        color: const Color(0xFF733429),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.white, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  children: List<Widget>.generate(14, (cellIndex) {
                    final seatIndex = cellIndex ~/ 2;
                    final isNumberCell = cellIndex.isEven;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: isNumberCell
                            ? _buildBottomNumberCell(
                                seatIndex,
                                _seatForVisualSlot(seatIndex),
                              )
                            : _buildBottomScoreInputCell(
                                seat: _seatForVisualSlot(seatIndex),
                              ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNumberCell(int index, _MuushigSeat? seat) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size =
            (constraints.maxHeight - 2).clamp(22.0, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _seatStateBadgeFillColor(seat),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _bottomCellBorderColor(seat),
                  width: _bottomCellBorderWidth(seat),
                ),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: _seatStateBadgeTextColor(seat),
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomScoreInputCell({required _MuushigSeat? seat}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            (constraints.maxHeight - 2).clamp(22.0, constraints.maxWidth);
        if (seat == null) {
          return Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24, width: 2),
                ),
              ),
            ),
          );
        }

        final isPlaying = _roundPlayChoices[seat.username] == true;
        final isPenaltyFive = _penaltyFiveUsernames.contains(seat.username);
        final activePlayers = _activePlayersInSeatOrder();
        final activeIndex = activePlayers.indexOf(seat.username);
        final isLastActive =
            activeIndex != -1 && activeIndex == activePlayers.length - 1;
        final decisionFocusNode =
            _roundDecisionFocusNodes[seat.username] ??= FocusNode();

        return Focus(
          focusNode: decisionFocusNode,
          skipTraversal: true,
          canRequestFocus: true,
          child: Center(
            child: SizedBox(
              width: side,
              height: side,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? const Color(0xFFF4E3D6)
                      : const Color(0xFFE6D9CF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _bottomCellBorderColor(seat),
                    width: _bottomCellBorderWidth(seat),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Center(
                  child: VoicePlayerCue(
                    active: _handsFreeVoiceMode && _roundSelectionConfirmed && _voicePendingUsername == seat.username,
                    child: TextField(
                    controller: _roundScoreControllers[seat.username],
                    focusNode: _roundScoreFocusNodes[seat.username],
                    enabled: true,
                    readOnly: !(_roundSelectionConfirmed && isPlaying),
                    onTap: () {
                      if (!_roundSelectionConfirmed || !isPlaying) return;
                      _voiceStableTimer?.cancel();
                      _voiceStableText = '';
                      setState(() {
                        _manualScoreUsername = seat.username;
                        _voicePendingUsername = seat.username;
                      });
                    },
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    textInputAction: isLastActive
                        ? TextInputAction.done
                        : TextInputAction.next,
                    // Submission below owns focus, including rejected input.
                    onEditingComplete: () {},
                    onChanged: (_) {
                      if (_penaltyFiveUsernames.contains(seat.username)) {
                        setState(
                            () => _penaltyFiveUsernames.remove(seat.username));
                      }
                    },
                    onSubmitted: isPlaying
                        ? (_) => _onRoundScoreSubmitted(seat.username)
                        : null,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: '0',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: side * 0.58,
                      height: 1,
                      color: isPenaltyFive ? Colors.red : Colors.black,
                    ),
                  ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRightScoreCell({
    required String title,
    required String value,
    bool isRed = false,
  }) {
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fontSize =
              (constraints.maxHeight * 0.62).clamp(30.0, 72.0).toDouble();
          return Column(
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
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: fontSize,
                        color: isRed ? Colors.red : Colors.black,
                        height: 0.95,
                        shadows: const [
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
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => buildLiveGame(_buildGame(context));

  Widget _buildGame(BuildContext context) {

    if (liveCanEdit &&
        !_playerOrderSelected &&
        !_orderDialogScheduled &&
        _selectedProfilesLoaded &&
        _seats.length >= 3 &&
        _seats.length <= 7 &&
        ModalRoute.of(context)?.isCurrent == true) {
      _orderDialogScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showPlayerOrderDialog(
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
            _focusFirstDecisionNode();
          },
        );
        _orderDialogScheduled = false;
      });
    }

    return WillPopScope(
      onWillPop: () async {
        if (!mounted) return false;
        if (widget.autoReturnOnWinner) {
          Navigator.of(context).pop();
          return false;
        }
        return _showExitReportDialog();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF9D2F2F),
        appBar: UnifiedGameAppBar(
          currentUserId: widget.currentUserId,
          canManageGames: widget.canManageGames,
          title: Text(
            (() {
              final isMulti = widget.multiWinsByUserId != null;
              final roundLabel = isMulti
                  ? 'Төрөл ${widget.multiCurrentTypeNumber ?? _roundNumber}/${widget.multiTotalTypeCount ?? _roundNumber}'
                  : 'Тоглолтын №$_roundNumber';
              return _isBoltMode
                  ? (_isMiddleBoltMode
                      ? 'Муушиг  |  Дундын боолт №$_roundNumber'
                      : 'Муушиг  |  Боолт №$_roundNumber')
                  : 'Муушиг  |  $roundLabel';
            })(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onBack: () async {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            final selectedUserIds = _seats
                .map((seat) => seat.userId)
                .whereType<String>()
                .where((id) => id.isNotEmpty)
                .toList(growable: false);
            if (!mounted) return;
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
          onRemovePlayer: _activeSeatCount > 2 ? _removePlayerFromGame : null,
          onAddPlayer:
              _seats.any((seat) => !seat.isActive && !seat.isPendingRejoin)
                  ? _restorePlayerToGame
                  : null,
          onSave: _saveProgress,
          onCheckpoint: () => liveRepository.checkpoint(saveLiveProgress),
          onStatistics: _openStatisticsDashboard,
          onReport: _showExitReportAndFinish,
          onPrint: _printSessionReport,
          onSettings: _showMuushigSettingsDialog,
          onExit: () async {
            if (!mounted) return;
            if (widget.autoReturnOnWinner) {
              Navigator.of(context).pop();
              return;
            }
            await _showExitReportAndFinish();
          },
          extraActions: [
            IconButton(
              tooltip: _handsFreeVoiceMode
                  ? (_handsFreeCommandArmed
                      ? 'Команд сонсож байна — “Боллоо” гэж дуусгана'
                      : 'Дуугаар бүртгэх')
                  : 'Дуугаар бүртгэх',
              onPressed: liveCanEdit ? _toggleHandsFreeVoiceMode : null,
              icon: Icon(
                _handsFreeVoiceMode ? Icons.mic : Icons.mic_none,
                color: _handsFreeVoiceMode
                    ? (_handsFreeCommandArmed
                        ? Colors.greenAccent
                        : Colors.amberAccent)
                    : null,
              ),
            ),
            IconButton(
              tooltip: _canTransferRegistrar
                  ? 'Тоглолт бүртгэх эрх шилжүүлэх'
                  : 'Бүртгэл хөтлөгчийн эрх шилжүүлэх боломжгүй',
              onPressed: _canTransferRegistrar ? _transferRegistrarRole : null,
              icon: Opacity(
                opacity: _canTransferRegistrar ? 1 : 0.45,
                child: const Icon(Icons.manage_accounts_rounded),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 3.0;
              final viewportWidth = constraints.maxWidth;
              final viewportHeight = constraints.maxHeight;
              final contentWidth = viewportWidth;
              final showVoicePhase = _handsFreeVoiceMode || _voiceTranscript.isNotEmpty;
              final contentHeight = viewportHeight - (showVoicePhase ? 30 : 0);
              final topBlockWidth =
                  (contentWidth - spacing * 4).clamp(0.0, double.infinity) / 5;
              final bottomBlockWidth =
                  (contentWidth - spacing).clamp(0.0, double.infinity) / 2;
              final topRowHeight = ((contentHeight - spacing * 2) * 0.68)
                  .clamp(240.0, 460.0)
                  .toDouble();
              final middleRowHeight = ((contentHeight - spacing * 2) * 0.18)
                  .clamp(84.0, 150.0)
                  .toDouble();
              final bottomRowHeight =
                  (contentHeight - topRowHeight - middleRowHeight - spacing * 2)
                      .clamp(70.0, 120.0)
                      .toDouble();
              return SizedBox(
                width: contentWidth,
                height: viewportHeight,
                child: Column(
                  children: [
                    if (showVoicePhase)
                      SizedBox(
                        height: 30,
                        child: Center(child: Text(
                          _roundSelectionConfirmed
                              ? 'Төлөвүүд баталгаажлаа — оноо оруулна уу'
                              : 'Төлөв сонголт: ${_activeSeats.where((seat) => _roundPlayChoices.containsKey(seat.username)).length}/${_activeSeats.length}',
                          style: const TextStyle(color: Colors.white),
                        )),
                      ),
                    SizedBox(
                      height: topRowHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(5, (index) {
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == 4 ? 0 : spacing,
                            ),
                            child: _buildSeatCard(
                              index,
                              _seatForVisualSlot(index),
                              topBlockWidth,
                              topRowHeight,
                              false,
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: spacing),
                    SizedBox(
                      height: middleRowHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: spacing),
                            child: _buildSeatCard(
                              5,
                              _seatForVisualSlot(5),
                              bottomBlockWidth,
                              middleRowHeight,
                              true,
                            ),
                          ),
                          _buildSeatCard(
                            6,
                            _seatForVisualSlot(6),
                            bottomBlockWidth,
                            middleRowHeight,
                            true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: spacing),
                    Expanded(
                      child: _buildBottomScoreControlBar(
                        contentWidth,
                        bottomRowHeight,
                      ),
                    ),
                  ],
                ),
              );
            },
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
  final int normalWins;
  final int boltWins;
  final int money;
  final int bombs;
  final int totalBombs;
  final bool isRoundPenaltyFive;
  final bool isTotalScoreRed;
  final bool isActive;
  final bool isFinancialParticipant;
  final bool isPendingRejoin;

  const _MuushigSeat({
    this.userId,
    required this.username,
    required this.displayName,
    this.photoUrl,
    required this.roundScoreText,
    required this.totalScoreText,
    required this.wins,
    required this.normalWins,
    required this.boltWins,
    required this.money,
    required this.bombs,
    required this.totalBombs,
    required this.isRoundPenaltyFive,
    this.isTotalScoreRed = false,
    this.isActive = true,
    this.isFinancialParticipant = true,
    this.isPendingRejoin = false,
  });

  _MuushigSeat copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? photoUrl,
    String? roundScoreText,
    String? totalScoreText,
    int? wins,
    int? normalWins,
    int? boltWins,
    int? money,
    int? bombs,
    int? totalBombs,
    bool? isRoundPenaltyFive,
    bool? isTotalScoreRed,
    bool? isActive,
    bool? isFinancialParticipant,
    bool? isPendingRejoin,
  }) {
    return _MuushigSeat(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      roundScoreText: roundScoreText ?? this.roundScoreText,
      totalScoreText: totalScoreText ?? this.totalScoreText,
      wins: wins ?? this.wins,
      normalWins: normalWins ?? this.normalWins,
      boltWins: boltWins ?? this.boltWins,
      money: money ?? this.money,
      bombs: bombs ?? this.bombs,
      totalBombs: totalBombs ?? this.totalBombs,
      isRoundPenaltyFive: isRoundPenaltyFive ?? this.isRoundPenaltyFive,
      isTotalScoreRed: isTotalScoreRed ?? this.isTotalScoreRed,
      isActive: isActive ?? this.isActive,
      isFinancialParticipant:
          isFinancialParticipant ?? this.isFinancialParticipant,
      isPendingRejoin: isPendingRejoin ?? this.isPendingRejoin,
    );
  }
}
