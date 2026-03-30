import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/statistics_repository.dart';
import '../utils/saved_game_sessions_repository.dart';
import '../utils/active_tables_repository.dart';
import 'statistics_dashboard.dart';
import '108.dart';
import '5_card_texas.dart';
import '501.dart';
import 'buur.dart';
import 'canasta.dart';
import 'durak.dart';
import 'muushig.dart';
import 'nvx_shaxax.dart';
import 'player_selection_page.dart';
import 'playing_format.dart';
import 'kinds_of_game.dart';
import 'xodrox.dart';
import '../widgets/unified_game_app_bar.dart';
import '../widgets/active_table_route_scope.dart';
import '../utils/active_table_route_registry.dart';

// PlayerSelectScreen for inviting new player
class PlayerSelectScreen extends StatefulWidget {
  final List<String> availablePlayers;
  const PlayerSelectScreen({super.key, required this.availablePlayers});

  @override
  State<PlayerSelectScreen> createState() => _PlayerSelectScreenState();
}

class _PlayerSelectScreenState extends State<PlayerSelectScreen> {
  int? _selectedIdx;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Тоглогч сонгох'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: widget.availablePlayers.length,
                itemBuilder: (context, i) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[300],
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(widget.availablePlayers[i]),
                    trailing: Radio<int>(
                      value: i,
                      groupValue: _selectedIdx,
                      onChanged: (val) {
                        setState(() {
                          _selectedIdx = val;
                        });
                      },
                    ),
                    onTap: () {
                      setState(() {
                        _selectedIdx = i;
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Болих'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedIdx != null
                      ? () {
                          Navigator.of(context)
                              .pop(widget.availablePlayers[_selectedIdx!]);
                        }
                      : null,
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

class ThirteenCardPokerScreen extends StatefulWidget {
  final String gameType;
  final List<String> selectedUserIds;
  final String? currentRegistrarUserId;
  final bool canManageGames;
  final String? initialSavedSessionId;
  final bool autoReturnOnWinner;
  final Map<String, int>? multiWinsByUserId;
  final int? multiCurrentTypeNumber;
  final int? multiTotalTypeCount;
  final bool promptInitialPlayerOrder;
  const ThirteenCardPokerScreen({
    super.key,
    required this.gameType,
    this.selectedUserIds = const [],
    this.currentRegistrarUserId,
    this.canManageGames = false,
    this.initialSavedSessionId,
    this.autoReturnOnWinner = false,
    this.multiWinsByUserId,
    this.multiCurrentTypeNumber,
    this.multiTotalTypeCount,
    this.promptInitialPlayerOrder = true,
  });

  @override
  State<ThirteenCardPokerScreen> createState() => _PlayingTableScreenState();
}

class _PlayingTableScreenState extends State<ThirteenCardPokerScreen> {
  static const String _statisticsPrefsKey = 'toocoob.statistics.v1';
  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();
  final ActiveTablesRepository _activeTablesRepo = ActiveTablesRepository();

  // --- State variables ---
  int currentTable = 1;
  List<String> userNames = [];
  List<String> displayNames = [];
  List<String> _orderedUserNames = [];
  List<String> _orderedDisplayNames = [];
  List<String> _table1UserNames = [];
  List<String> _table1DisplayNames = [];
  List<String> _table2UserNames = [];
  List<String> _table2DisplayNames = [];
  final Map<String, Map<String, dynamic>> _userProfiles = {};
  int playerCount = 0;
  int roundNumber = 1;
  int _scoreLimit = 25;
  int _betAmount = 5000;
  int _boltScoreLimit = 30;
  int _boltBetAmount = 10000;
  dynamic _pokerGame; // Use correct type if available
  bool _playerOrderSelected = false;
  bool _tableSplitSelected = false;
  final Map<String, int> _roundScores = {};
  final Map<String, int> _totalScores = {};
  final Map<String, int> _winsByUserId = {};
  final Map<String, int> _moneyByUserId = {};
  final Map<String, TextEditingController> _scoreControllers = {};
  final Map<String, FocusNode> _scoreFocusNodes = {};
  final List<TextEditingController> _eighthBlockScoreControllers =
      List<TextEditingController>.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _eighthBlockFocusNodes =
      List<FocusNode>.generate(4, (_) => FocusNode());
  final Map<String, int> _eighthRoundScoresByUserId = {};
  final Set<String> _explicitZeroRoundUserIds = <String>{};
  final Set<String> _forcedEliminatedUserIds = <String>{};
  final Set<String> _paidOutRoundLoserUserIds = <String>{};
  // Tracks elimination order: userId → U-rank (1=first eliminated, 2=second, …)
  final Map<String, int> _uRankings = {};
  bool _isResolvingRound = false;
  bool _isSubmittingInlineScore = false;
  bool _isProcessingEighthSubmit = false;
  bool _sessionAddedToStatistics = false;
  final List<String> _benchedUserIds = [];
  final List<String> _table1BenchedUserIds = [];
  final List<String> _table2BenchedUserIds = [];
  final List<String> _pinnedSubstituteUserIds = [];
  final List<String> _table1PinnedSubstituteUserIds = [];
  final List<String> _table2PinnedSubstituteUserIds = [];
  bool _isBoltMode = false;
  int _boltRoundNumber = 0;
  bool _middleTieDecisionMade = false;
  String? _currentBoltUserId;
  final Set<String> _completedBoltUserIds = <String>{};
  final List<String> _sessionAllUserIds = <String>[];
  int _sessionInitialPlayerCount = 0;
  int _sessionAddedPlayers = 0;
  int _sessionRemovedPlayers = 0;
  int _sessionOrdinaryRounds = 0;
  int _sessionBoltRounds = 0;
  int _sessionMiddleBoltRounds = 0;
  final List<List<String>> _durakBlocks = [];
  final int _durakWinThreshold = 8;
  String? _currentRegistrarUserId;
  String? _activeSavedSessionId;
  bool _multiAutoReturnTriggered = false;

  bool get _canTransferRegistrarPermission {
    return widget.canManageGames &&
        widget.currentRegistrarUserId != null &&
        widget.currentRegistrarUserId == _currentRegistrarUserId;
  }

  bool _isEligibleRegistrarUser(String userId) {
    final profile = _userProfiles[userId];
    final hasManagerRole = profile?['canManageGames'] == true;
    // During a running game the current registrar is always eligible,
    // even before role persistence to Firestore.
    return hasManagerRole || userId == _currentRegistrarUserId;
  }

  Future<void> _showTransferRegistrarDialog() async {
    if (!_canTransferRegistrarPermission) return;

    final candidates = _orderedUserNames
        .where((userId) => userId != _currentRegistrarUserId)
        .where(_isEligibleRegistrarUser)
        .toList();
    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Эрх шилжүүлэх боломжтой бүртгэл хөтлөгч тоглогч олдсонгүй.',
            ),
          ),
        );
      }
      return;
    }

    String? selectedUserId = candidates.first;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Бүртгэл хөтлөгчийн эрх шилжүүлэх'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: candidates
                    .map(
                      (userId) => RadioListTile<String>(
                        dense: true,
                        value: userId,
                        groupValue: selectedUserId,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedUserId = value;
                          });
                        },
                        title: Text(_displayNameForUserId(userId, 0)),
                        subtitle: Text('@${_usernameForUserId(userId)}'),
                      ),
                    )
                    .toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: selectedUserId == null
                      ? null
                      : () => Navigator.pop(dialogContext, selectedUserId),
                  child: const Text('Шилжүүлэх'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() {
      _currentRegistrarUserId = result;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Бүртгэл хөтлөгчийн эрх ${_displayNameForUserId(result, 0)} руу шилжлээ.',
          ),
        ),
      );
    }
  }

  bool get _shouldAskRegistrarDecisionAtGameEnd {
    final originalRegistrar = widget.currentRegistrarUserId;
    if (originalRegistrar == null || originalRegistrar.isEmpty) return false;
    if (_currentRegistrarUserId == null || _currentRegistrarUserId!.isEmpty) {
      return false;
    }
    return _currentRegistrarUserId != originalRegistrar;
  }

  Future<String?> _showRegistrarTargetSelectionDialog({
    required List<String> candidateUserIds,
  }) {
    String? selectedUserId =
        candidateUserIds.isNotEmpty ? candidateUserIds.first : null;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Өөр хөтлөгч сонгох'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: candidateUserIds
                    .map(
                      (userId) => RadioListTile<String>(
                        dense: true,
                        value: userId,
                        groupValue: selectedUserId,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedUserId = value;
                          });
                        },
                        title: Text(_displayNameForUserId(userId, 0)),
                        subtitle: Text('@${_usernameForUserId(userId)}'),
                      ),
                    )
                    .toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Цуцлах'),
                ),
                ElevatedButton(
                  onPressed: selectedUserId == null
                      ? null
                      : () => Navigator.pop(dialogContext, selectedUserId),
                  child: const Text('Хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _persistGameManagerRole({
    required String newManagerUserId,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw Exception('Firebase эхлүүлэгдээгүй байна.');
    }

    final originalRegistrar = widget.currentRegistrarUserId;
    final previousRegistrar = _currentRegistrarUserId;
    if (originalRegistrar == null || previousRegistrar == null) return;

    final users = FirebaseFirestore.instance.collection('users');
    final batch = FirebaseFirestore.instance.batch();

    // Always grant manager role to selected user.
    batch.update(users.doc(newManagerUserId), {'canManageGames': true});

    // Original registrar keeps role only when user selects "Тийм".
    if (newManagerUserId == originalRegistrar) {
      batch.update(users.doc(originalRegistrar), {'canManageGames': true});
    } else {
      batch.update(users.doc(originalRegistrar), {'canManageGames': false});
    }

    // Previous transferred registrar loses role if different from selected.
    if (previousRegistrar != newManagerUserId) {
      batch.update(users.doc(previousRegistrar), {'canManageGames': false});
    }

    await batch.commit();
  }

  Future<void> _askRegistrarDecisionAtGameEndIfNeeded() async {
    if (!_shouldAskRegistrarDecisionAtGameEnd) return;

    final originalRegistrar = widget.currentRegistrarUserId!;
    final transferredRegistrar = _currentRegistrarUserId!;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Бүртгэл хөтлөгчийн эрх'),
          content: Text(
            'Та бүртгэл хөтлөх эрхээ буцааж авах уу?\n'
            'Одоогийн хөтлөгч: ${_displayNameForUserId(transferredRegistrar, 0)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'no'),
              child: const Text('Үгүй'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'transfer'),
              child: const Text('Өөр хөтлөгч рүү шилжүүлэх'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'yes'),
              child: const Text('Тийм'),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null) return;

    try {
      if (action == 'yes') {
        await _persistGameManagerRole(newManagerUserId: originalRegistrar);
        setState(() {
          _currentRegistrarUserId = originalRegistrar;
        });
        return;
      }

      if (action == 'no') {
        await _persistGameManagerRole(newManagerUserId: transferredRegistrar);
        return;
      }

      if (action == 'transfer') {
        final candidates = _orderedUserNames
            .where((userId) => userId != originalRegistrar)
            .where(_isEligibleRegistrarUser)
            .toList();
        if (candidates.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Шилжүүлэх боломжтой эрх бүхий тоглогч олдсонгүй.',
                ),
              ),
            );
          }
          return;
        }

        final selected = await _showRegistrarTargetSelectionDialog(
          candidateUserIds: candidates,
        );
        if (selected == null) return;

        await _persistGameManagerRole(newManagerUserId: selected);
        setState(() {
          _currentRegistrarUserId = selected;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Эрхийн шийдвэр хадгалахад алдаа: $e')),
      );
    }
  }

  int _roundScoreFor(String userId) => _roundScores[userId] ?? 0;
  int _totalScoreFor(String userId) => _totalScores[userId] ?? 0;

  String _roundScoreText(String userId) {
    return _roundScores.containsKey(userId)
        ? _roundScoreFor(userId).toString()
        : '-';
  }

  String _totalScoreText(String userId) {
    return _totalScores.containsKey(userId)
        ? _totalScoreFor(userId).toString()
        : '-';
  }

  int _winsForUserId(String userId) => _winsByUserId[userId] ?? 0;
  int _moneyForUserId(String userId) => _moneyByUserId[userId] ?? 0;

  int get _activeScoreLimit => _isBoltMode ? _boltScoreLimit : _scoreLimit;
  int get _activeBetAmount => _isBoltMode ? _boltBetAmount : _betAmount;

  String get _roundInfoLabel {
    if (widget.autoReturnOnWinner) {
      return 'Олон төрөлт';
    }
    if (_isBoltMode) {
      return 'Боолт №$_boltRoundNumber';
    }
    if (widget.multiWinsByUserId != null) {
      final current = widget.multiCurrentTypeNumber;
      final total = widget.multiTotalTypeCount;
      if (current != null && total != null && total > 0) {
        return 'Төрөл $current/$total';
      }
      return 'Төрөл №$roundNumber';
    }
    return 'Тоглолтын №$roundNumber';
  }

  Color _moneyColorForAmount(int amount) {
    return amount < 0 ? Colors.red : Colors.green;
  }

  bool _isEliminatedByScore(String userId) {
    if (_forcedEliminatedUserIds.contains(userId)) return true;
    return _totalScoreFor(userId) >= _activeScoreLimit;
  }

  int _benchCountForTable(List<String> tablePlayers) {
    final aliveCount =
        tablePlayers.where((userId) => !_isEliminatedByScore(userId)).length;
    if (aliveCount <= 4 || aliveCount > 7) return 0;
    return aliveCount - 4;
  }

  List<String> _preferredBenchedUsersForCurrentTable() {
    if (_tableSplitSelected) {
      return currentTable == 1
          ? List<String>.from(_table1BenchedUserIds)
          : List<String>.from(_table2BenchedUserIds);
    }
    return List<String>.from(_benchedUserIds);
  }

  void _setPreferredBenchedUsersForCurrentTable(List<String> userIds) {
    if (_tableSplitSelected) {
      if (currentTable == 1) {
        _table1BenchedUserIds
          ..clear()
          ..addAll(userIds);
      } else {
        _table2BenchedUserIds
          ..clear()
          ..addAll(userIds);
      }
      return;
    }

    _benchedUserIds
      ..clear()
      ..addAll(userIds);
  }

  List<String> _currentBenchedUsersForTable(List<String> tablePlayers) {
    if (widget.gameType == '13 МОДНЫ ПОКЕР' &&
        !_tableSplitSelected &&
        tablePlayers.length >= 5 &&
        tablePlayers.length <= 7) {
      return tablePlayers
          .skip(4)
          .where((userId) => !_isEliminatedByScore(userId))
          .toList();
    }

    final benchCount = _benchCountForTable(tablePlayers);
    if (benchCount <= 0) return <String>[];

    final preferred = _preferredBenchedUsersForCurrentTable();
    final aliveInOrder =
        tablePlayers.where((userId) => !_isEliminatedByScore(userId)).toList();

    final normalized = <String>[];
    for (final userId in preferred) {
      if (!aliveInOrder.contains(userId)) continue;
      if (normalized.contains(userId)) continue;
      normalized.add(userId);
      if (normalized.length == benchCount) return normalized;
    }

    for (final userId in aliveInOrder) {
      if (normalized.contains(userId)) continue;
      normalized.add(userId);
      if (normalized.length == benchCount) break;
    }

    return normalized;
  }

  List<String> _activePlayersByBenchForTable(List<String> tablePlayers) {
    final benched = _currentBenchedUsersForTable(tablePlayers).toSet();
    return tablePlayers
        .where((userId) =>
            !_isEliminatedByScore(userId) && !benched.contains(userId))
        .toList();
  }

  bool _isBenchedForCurrentTable(String userId) {
    return _currentBenchedUsersForTable(_activeUserNames).contains(userId);
  }

  void _advanceBenchByRoundScores(List<String> tablePlayers) {
    final benchCount = _benchCountForTable(tablePlayers);
    if (benchCount <= 0) {
      _setPreferredBenchedUsersForCurrentTable(const <String>[]);
      return;
    }

    final activePlayers = _activePlayersByBenchForTable(tablePlayers);
    if (activePlayers.isEmpty) return;

    final orderIndex = {
      for (int i = 0; i < tablePlayers.length; i++) tablePlayers[i]: i,
    };

    final sortedByRoundScore = List<String>.from(activePlayers)
      ..sort((a, b) {
        final aScore = _roundScores[a] ?? 0;
        final bScore = _roundScores[b] ?? 0;
        final byScore = aScore.compareTo(bScore);
        if (byScore != 0) return byScore;
        return (orderIndex[a] ?? 0).compareTo(orderIndex[b] ?? 0);
      });

    _setPreferredBenchedUsersForCurrentTable(
      sortedByRoundScore.take(benchCount).toList(),
    );
  }

  /// Applies the 5-7 player tournament movement after every committed round.
  /// Previously benched players must return to Н1-Н4 on the next round and can
  /// never remain in the Ш zone twice in a row.
  void _applyTournamentMovement7Players() {
    if (widget.gameType != '13 МОДНЫ ПОКЕР') return;
    if (_tableSplitSelected) return;
    final int total = _orderedUserNames.length;
    if (total < 5 || total > 7) return;

    const int shStart = 4;
    final int shEnd = total - 1;
    final originalBlocks = List<String>.from(_orderedUserNames);
    final nextBlocks = List<String?>.filled(total, null);

    final existingRedShIndices = <int>[];
    final aliveShPlayers = <String>[];
    for (int i = shStart; i <= shEnd; i++) {
      final userId = originalBlocks[i];
      if (_isEliminatedByScore(userId)) {
        existingRedShIndices.add(i);
      } else {
        aliveShPlayers.add(userId);
      }
    }

    final newlyEliminatedNs = [
      for (int i = 0; i <= 3; i++)
        if (_isEliminatedByScore(originalBlocks[i]) &&
            !_uRankings.containsKey(originalBlocks[i]))
          originalBlocks[i],
    ]..sort((a, b) {
        final byTotal = (_totalScores[b] ?? 0).compareTo(_totalScores[a] ?? 0);
        if (byTotal != 0) return byTotal;
        return (_roundScores[b] ?? 0).compareTo(_roundScores[a] ?? 0);
      });

    for (final userId in newlyEliminatedNs) {
      _uRankings[userId] = _uRankings.length + 1;
    }

    final assignedEliminationSlots = <String, int>{};
    final occupiedShIndices = <int>{...existingRedShIndices};
    for (final userId in newlyEliminatedNs) {
      for (int i = shEnd; i >= shStart; i--) {
        if (occupiedShIndices.contains(i)) continue;
        occupiedShIndices.add(i);
        assignedEliminationSlots[userId] = i;
        break;
      }
    }

    for (final i in existingRedShIndices) {
      nextBlocks[i] = originalBlocks[i];
    }
    assignedEliminationSlots.forEach((userId, slotIndex) {
      nextBlocks[slotIndex] = userId;
    });

    final aliveCount =
        originalBlocks.where((userId) => !_isEliminatedByScore(userId)).length;
    final nextBenchCount = aliveCount <= 4 ? 0 : aliveCount - 4;

    final rankedAliveNs = [
      for (int i = 0; i <= 3; i++)
        if (!_isEliminatedByScore(originalBlocks[i])) originalBlocks[i],
    ]..sort((a, b) {
        final byRound = (_roundScores[a] ?? 0).compareTo(_roundScores[b] ?? 0);
        if (byRound != 0) return byRound;
        return originalBlocks.indexOf(a).compareTo(originalBlocks.indexOf(b));
      });

    final promotedNs = rankedAliveNs.take(nextBenchCount).toList();
    final promotedNSet = promotedNs.toSet();
    final remainingIncomingFromSh =
        aliveShPlayers.skip(promotedNs.length).toList();
    final remainingNs = rankedAliveNs
        .where((userId) => !promotedNSet.contains(userId))
        .toList();

    final freeBenchIndices = [
      for (int i = shStart; i <= shEnd; i++)
        if (!occupiedShIndices.contains(i)) i,
    ];
    final pairedIncomingByNIndex = <int, String>{};
    final promotedCount = promotedNs.length < freeBenchIndices.length
        ? promotedNs.length
        : freeBenchIndices.length;

    for (int i = 0; i < promotedCount; i++) {
      final promotedUser = promotedNs[i];
      final targetShIndex = freeBenchIndices[i];
      nextBlocks[targetShIndex] = promotedUser;

      if (i < aliveShPlayers.length) {
        final promotedNIndex = originalBlocks.indexOf(promotedUser);
        pairedIncomingByNIndex[promotedNIndex] = aliveShPlayers[i];
      }
    }

    for (int i = 0; i <= 3; i++) {
      final userId = originalBlocks[i];
      final movedToSh = assignedEliminationSlots.containsKey(userId);
      if (_isEliminatedByScore(userId) && !movedToSh) {
        nextBlocks[i] = userId;
        continue;
      }

      final pairedIncoming = pairedIncomingByNIndex[i];
      if (pairedIncoming != null) {
        nextBlocks[i] = pairedIncoming;
        continue;
      }

      if (remainingIncomingFromSh.isNotEmpty) {
        nextBlocks[i] = remainingIncomingFromSh.removeAt(0);
        continue;
      }

      if (remainingNs.isNotEmpty) {
        nextBlocks[i] = remainingNs.removeAt(0);
      }
    }

    _orderedUserNames = nextBlocks.map((userId) => userId ?? '').toList();
    _refreshDisplayNamesFromProfiles();

    _setPreferredBenchedUsersForCurrentTable([
      for (int i = shStart; i <= shEnd; i++)
        if (i < _orderedUserNames.length &&
            _orderedUserNames[i].isNotEmpty &&
            !_isEliminatedByScore(_orderedUserNames[i]))
          _orderedUserNames[i],
    ]);
  }

  void _updateBoltModeForNextRound() {
    if (_isBoltMode && _currentBoltUserId != null) {
      _completedBoltUserIds.add(_currentBoltUserId!);
    }

    final totalPlayersForMode = _activeUserNames.length;
    if (totalPlayersForMode < 2) {
      _isBoltMode = false;
      _currentBoltUserId = null;
      return;
    }

    final ordinaryRoundsCompleted = roundNumber > totalPlayersForMode;
    final maxBoltRounds = totalPlayersForMode - 1;
    final boltCandidates = _activeUserNames
        .where((userId) =>
            _winsForUserId(userId) == 0 &&
            !_completedBoltUserIds.contains(userId))
        .toList();

    if (ordinaryRoundsCompleted &&
        boltCandidates.isNotEmpty &&
        _boltRoundNumber < maxBoltRounds) {
      _isBoltMode = true;
      _boltRoundNumber += 1;
      _currentBoltUserId = boltCandidates.first;
      return;
    }

    _isBoltMode = false;
    _currentBoltUserId = null;
  }

  bool _isCurrentCycleCompleted() {
    final totalPlayersForMode = _activeUserNames.length;
    if (totalPlayersForMode < 2) return false;

    final ordinaryRoundsCompleted = roundNumber > totalPlayersForMode;
    if (!ordinaryRoundsCompleted || _isBoltMode) return false;

    final maxBoltRounds = totalPlayersForMode - 1;
    if (_boltRoundNumber >= maxBoltRounds) return true;

    final hasRemainingBoltCandidate = _activeUserNames.any(
      (userId) =>
          _winsForUserId(userId) == 0 &&
          !_completedBoltUserIds.contains(userId),
    );

    return !hasRemainingBoltCandidate;
  }

  bool _allActivePlayersHaveExactlyOneWin() {
    final activePlayers = List<String>.from(_activeUserNames);
    if (activePlayers.length < 2 || activePlayers.length > 7) return false;
    return activePlayers.every((userId) => _winsForUserId(userId) == 1);
  }

  bool _shouldShowMiddleTieDecisionDialog() {
    if (_middleTieDecisionMade) return false;
    if (_isBoltMode) return false;
    return _allActivePlayersHaveExactlyOneWin();
  }

  Future<String?> _showMiddleTieDecisionDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтын шийдвэр'),
          content: const Text(
            'Бүх тоглогч 1 хожилтой боллоо. Дундаа боох нь ганц удаа Боолт горимоор тоглоод тоглолтыг дуусгана.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('finish'),
              child: const Text('Дуусгах'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('replay'),
              child: const Text('Дахин тойрох'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop('bolt'),
              child: const Text('Дундаа боох'),
            ),
          ],
        );
      },
    );
  }

  void _resetForReplayKeepingMoney() {
    _roundScores.clear();
    _explicitZeroRoundUserIds.clear();
    _paidOutRoundLoserUserIds.clear();
    _totalScores.clear();
    _winsByUserId.clear();
    _forcedEliminatedUserIds.clear();
    _benchedUserIds.clear();
    _uRankings.clear();
    _table1BenchedUserIds.clear();
    _table2BenchedUserIds.clear();
    _pinnedSubstituteUserIds.clear();
    _table1PinnedSubstituteUserIds.clear();
    _table2PinnedSubstituteUserIds.clear();
    _isBoltMode = false;
    _boltRoundNumber = 0;
    _middleTieDecisionMade = false;
    _playerOrderSelected = false;
    _currentBoltUserId = null;
    _completedBoltUserIds.clear();
    roundNumber = 1;

    for (final userId in _orderedUserNames) {
      _clearScoreInput(userId);
    }
    _eighthRoundScoresByUserId.clear();
    for (final controller in _eighthBlockScoreControllers) {
      controller.clear();
    }
  }

  void _registerSessionUsers(Iterable<String> userIds) {
    for (final userId in userIds) {
      if (!_sessionAllUserIds.contains(userId)) {
        _sessionAllUserIds.add(userId);
      }
    }
  }

  Future<void> _tryRestoreSavedSession() async {
    final id = widget.initialSavedSessionId;
    if (id == null || id.isEmpty) return;

    final saved = await _savedSessionsRepo.findById(id);
    if (!mounted || saved == null || saved.gameKey != '13_card_poker') {
      return;
    }

    final payload = saved.payload;
    final restoredUserNames =
        (payload['userNames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false);
    final restoredOrderedUserNames =
        (payload['orderedUserNames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false);
    if (restoredUserNames.isEmpty || restoredOrderedUserNames.isEmpty) return;

    final scoreInputs = Map<String, dynamic>.from(
      payload['scoreInputs'] as Map? ?? const {},
    );
    final restoredScoreControllers = <String, TextEditingController>{};
    final restoredScoreFocusNodes = <String, FocusNode>{};
    for (final userId in scoreInputs.keys) {
      restoredScoreControllers[userId] = TextEditingController(
        text: (scoreInputs[userId] as String? ?? '').trim(),
      );
      restoredScoreFocusNodes[userId] = FocusNode();
    }

    for (final controller in _scoreControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _scoreFocusNodes.values) {
      focusNode.dispose();
    }

    final eighthInputs =
        (payload['eighthBlockInputs'] as List<dynamic>? ?? const [])
            .map((value) => (value as String? ?? '').trim())
            .toList(growable: false);

    if (!mounted) return;
    setState(() {
      _activeSavedSessionId = id;
      currentTable = (payload['currentTable'] as num?)?.toInt() ?? currentTable;
      userNames = restoredUserNames;
      displayNames = (payload['displayNames'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList();
      _orderedUserNames = restoredOrderedUserNames;
      _orderedDisplayNames =
          (payload['orderedDisplayNames'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      _table1UserNames =
          (payload['table1UserNames'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      _table1DisplayNames =
          (payload['table1DisplayNames'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      _table2UserNames =
          (payload['table2UserNames'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      _table2DisplayNames =
          (payload['table2DisplayNames'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList();
      _userProfiles
        ..clear()
        ..addAll(
          Map<String, dynamic>.from(payload['userProfiles'] as Map? ?? const {})
              .map(
            (key, value) => MapEntry(
              key,
              value is Map<String, dynamic>
                  ? value
                  : Map<String, dynamic>.from(value as Map),
            ),
          ),
        );
      playerCount = (payload['playerCount'] as num?)?.toInt() ?? playerCount;
      roundNumber = (payload['roundNumber'] as num?)?.toInt() ?? roundNumber;
      _scoreLimit = (payload['scoreLimit'] as num?)?.toInt() ?? _scoreLimit;
      _betAmount = (payload['betAmount'] as num?)?.toInt() ?? _betAmount;
      _boltScoreLimit =
          (payload['boltScoreLimit'] as num?)?.toInt() ?? _boltScoreLimit;
      _boltBetAmount =
          (payload['boltBetAmount'] as num?)?.toInt() ?? _boltBetAmount;
      _playerOrderSelected =
          payload['playerOrderSelected'] as bool? ?? _playerOrderSelected;
      _tableSplitSelected =
          payload['tableSplitSelected'] as bool? ?? _tableSplitSelected;
      _roundScores
        ..clear()
        ..addAll(
          Map<String, dynamic>.from(payload['roundScores'] as Map? ?? const {})
              .map((key, value) => MapEntry(key, (value as num).toInt())),
        );
      _totalScores
        ..clear()
        ..addAll(
          Map<String, dynamic>.from(payload['totalScores'] as Map? ?? const {})
              .map((key, value) => MapEntry(key, (value as num).toInt())),
        );
      _winsByUserId
        ..clear()
        ..addAll(Map<String, dynamic>.from(
          payload['winsByUserId'] as Map? ?? const {},
        ).map((key, value) => MapEntry(key, (value as num).toInt())));
      _moneyByUserId
        ..clear()
        ..addAll(Map<String, dynamic>.from(
          payload['moneyByUserId'] as Map? ?? const {},
        ).map((key, value) => MapEntry(key, (value as num).toInt())));
      _scoreControllers
        ..clear()
        ..addAll(restoredScoreControllers);
      _scoreFocusNodes
        ..clear()
        ..addAll(restoredScoreFocusNodes);
      for (var i = 0; i < _eighthBlockScoreControllers.length; i++) {
        _eighthBlockScoreControllers[i].text =
            i < eighthInputs.length ? eighthInputs[i] : '';
      }
      _eighthRoundScoresByUserId
        ..clear()
        ..addAll(Map<String, dynamic>.from(
          payload['eighthRoundScoresByUserId'] as Map? ?? const {},
        ).map((key, value) => MapEntry(key, (value as num).toInt())));
      _explicitZeroRoundUserIds
        ..clear()
        ..addAll(
            (payload['explicitZeroRoundUserIds'] as List<dynamic>? ?? const [])
                .whereType<String>());
      _forcedEliminatedUserIds
        ..clear()
        ..addAll(
            (payload['forcedEliminatedUserIds'] as List<dynamic>? ?? const [])
                .whereType<String>());
      _uRankings
        ..clear()
        ..addAll((payload['uRankings'] as Map? ?? const {}).map(
          (k, v) => MapEntry(k as String, (v as num).toInt()),
        ));
      _paidOutRoundLoserUserIds
        ..clear()
        ..addAll(
            (payload['paidOutRoundLoserUserIds'] as List<dynamic>? ?? const [])
                .whereType<String>());
      _isResolvingRound = payload['isResolvingRound'] as bool? ?? false;
      _isSubmittingInlineScore =
          payload['isSubmittingInlineScore'] as bool? ?? false;
      _isProcessingEighthSubmit =
          payload['isProcessingEighthSubmit'] as bool? ?? false;
      _sessionAddedToStatistics =
          payload['sessionAddedToStatistics'] as bool? ?? false;
      _benchedUserIds
        ..clear()
        ..addAll((payload['benchedUserIds'] as List<dynamic>? ?? const [])
            .whereType<String>());
      _table1BenchedUserIds
        ..clear()
        ..addAll((payload['table1BenchedUserIds'] as List<dynamic>? ?? const [])
            .whereType<String>());
      _table2BenchedUserIds
        ..clear()
        ..addAll((payload['table2BenchedUserIds'] as List<dynamic>? ?? const [])
            .whereType<String>());
      _pinnedSubstituteUserIds
        ..clear()
        ..addAll(
            (payload['pinnedSubstituteUserIds'] as List<dynamic>? ?? const [])
                .whereType<String>());
      _table1PinnedSubstituteUserIds
        ..clear()
        ..addAll((payload['table1PinnedSubstituteUserIds'] as List<dynamic>? ??
                const [])
            .whereType<String>());
      _table2PinnedSubstituteUserIds
        ..clear()
        ..addAll((payload['table2PinnedSubstituteUserIds'] as List<dynamic>? ??
                const [])
            .whereType<String>());
      _isBoltMode = payload['isBoltMode'] as bool? ?? false;
      _boltRoundNumber =
          (payload['boltRoundNumber'] as num?)?.toInt() ?? _boltRoundNumber;
      _middleTieDecisionMade =
          payload['middleTieDecisionMade'] as bool? ?? false;
      _currentBoltUserId = payload['currentBoltUserId'] as String?;
      _completedBoltUserIds
        ..clear()
        ..addAll((payload['completedBoltUserIds'] as List<dynamic>? ?? const [])
            .whereType<String>());
      _sessionAllUserIds
        ..clear()
        ..addAll((payload['sessionAllUserIds'] as List<dynamic>? ?? const [])
            .whereType<String>());
      _sessionInitialPlayerCount =
          (payload['sessionInitialPlayerCount'] as num?)?.toInt() ??
              _sessionInitialPlayerCount;
      _sessionAddedPlayers =
          (payload['sessionAddedPlayers'] as num?)?.toInt() ??
              _sessionAddedPlayers;
      _sessionRemovedPlayers =
          (payload['sessionRemovedPlayers'] as num?)?.toInt() ??
              _sessionRemovedPlayers;
      _sessionOrdinaryRounds =
          (payload['sessionOrdinaryRounds'] as num?)?.toInt() ??
              _sessionOrdinaryRounds;
      _sessionBoltRounds =
          (payload['sessionBoltRounds'] as num?)?.toInt() ?? _sessionBoltRounds;
      _sessionMiddleBoltRounds =
          (payload['sessionMiddleBoltRounds'] as num?)?.toInt() ??
              _sessionMiddleBoltRounds;
      _currentRegistrarUserId = payload['currentRegistrarUserId'] as String? ??
          _currentRegistrarUserId;
    });
  }

  Future<void> _saveProgress() async {
    final sessionId = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: '13_card_poker',
      gameLabel: widget.gameType,
      selectedUserIds: List<String>.from(_orderedUserNames),
      payload: {
        'currentTable': currentTable,
        'userNames': userNames,
        'displayNames': displayNames,
        'orderedUserNames': _orderedUserNames,
        'orderedDisplayNames': _orderedDisplayNames,
        'table1UserNames': _table1UserNames,
        'table1DisplayNames': _table1DisplayNames,
        'table2UserNames': _table2UserNames,
        'table2DisplayNames': _table2DisplayNames,
        'userProfiles': _userProfiles,
        'playerCount': playerCount,
        'roundNumber': roundNumber,
        'scoreLimit': _scoreLimit,
        'betAmount': _betAmount,
        'boltScoreLimit': _boltScoreLimit,
        'boltBetAmount': _boltBetAmount,
        'playerOrderSelected': _playerOrderSelected,
        'tableSplitSelected': _tableSplitSelected,
        'roundScores': _roundScores,
        'totalScores': _totalScores,
        'winsByUserId': _winsByUserId,
        'moneyByUserId': _moneyByUserId,
        'scoreInputs': _scoreControllers.map(
          (key, controller) => MapEntry(key, controller.text),
        ),
        'eighthBlockInputs': _eighthBlockScoreControllers
            .map((controller) => controller.text)
            .toList(),
        'eighthRoundScoresByUserId': _eighthRoundScoresByUserId,
        'explicitZeroRoundUserIds': _explicitZeroRoundUserIds.toList(),
        'forcedEliminatedUserIds': _forcedEliminatedUserIds.toList(),
        'paidOutRoundLoserUserIds': _paidOutRoundLoserUserIds.toList(),
        'uRankings': _uRankings,
        'isResolvingRound': _isResolvingRound,
        'isSubmittingInlineScore': _isSubmittingInlineScore,
        'isProcessingEighthSubmit': _isProcessingEighthSubmit,
        'sessionAddedToStatistics': _sessionAddedToStatistics,
        'benchedUserIds': _benchedUserIds,
        'table1BenchedUserIds': _table1BenchedUserIds,
        'table2BenchedUserIds': _table2BenchedUserIds,
        'pinnedSubstituteUserIds': _pinnedSubstituteUserIds,
        'table1PinnedSubstituteUserIds': _table1PinnedSubstituteUserIds,
        'table2PinnedSubstituteUserIds': _table2PinnedSubstituteUserIds,
        'isBoltMode': _isBoltMode,
        'boltRoundNumber': _boltRoundNumber,
        'middleTieDecisionMade': _middleTieDecisionMade,
        'currentBoltUserId': _currentBoltUserId,
        'completedBoltUserIds': _completedBoltUserIds.toList(),
        'sessionAllUserIds': _sessionAllUserIds,
        'sessionInitialPlayerCount': _sessionInitialPlayerCount,
        'sessionAddedPlayers': _sessionAddedPlayers,
        'sessionRemovedPlayers': _sessionRemovedPlayers,
        'sessionOrdinaryRounds': _sessionOrdinaryRounds,
        'sessionBoltRounds': _sessionBoltRounds,
        'sessionMiddleBoltRounds': _sessionMiddleBoltRounds,
        'currentRegistrarUserId': _currentRegistrarUserId,
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

  String _buildSessionReportText() {
    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;
    final rows = <String>[];
    for (int i = 0; i < _sessionAllUserIds.length; i++) {
      final userId = _sessionAllUserIds[i];
      final name = _displayNameForUserId(userId, i);
      final username = _usernameForUserId(userId);
      final money = _moneyForUserId(userId);
      rows.add('${i + 1}. $name (@$username): ₮$money');
    }

    return [
      '13 МОДНЫ ПОКЕР - ТОГЛОЛТЫН ТАЙЛАН',
      'Эхний тоглогчийн тоо: $_sessionInitialPlayerCount',
      'Нийт оролцсон тоглогч: ${_sessionAllUserIds.length}',
      'Нэмсэн тоглогч: $_sessionAddedPlayers',
      'Хассан тоглогч: $_sessionRemovedPlayers',
      'Нийт раунд: $totalRounds',
      'Энгийн тоглолт: $_sessionOrdinaryRounds',
      'Боолт тоглолт: $_sessionBoltRounds',
      'Дундын боолт: $_sessionMiddleBoltRounds',
      '',
      'Тоглогч тус бүрийн мөнгөн дүн:',
      ...rows,
    ].join('\n');
  }

  Future<void> _addCurrentSessionToStatisticsV2IfNeeded() async {
    if (_sessionAddedToStatistics) return;

    final repository = StatsRepository();
    final players = List<StatsPlayerResult>.generate(
      _sessionAllUserIds.length,
      (index) {
        final userId = _sessionAllUserIds[index];
        return StatsPlayerResult(
          userId: userId,
          username: _usernameForUserId(userId),
          displayName: _displayNameForUserId(userId, index),
          money: _moneyForUserId(userId),
        );
      },
    );

    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;

    final session = StatsSession(
      sessionId:
          '13-${DateTime.now().microsecondsSinceEpoch}-${_sessionAllUserIds.length}',
      gameKey: '13_card_poker',
      gameLabel: '13 МОДНЫ ПОКЕР',
      playedAt: DateTime.now(),
      players: players,
      totalRounds: totalRounds,
    );

    await repository.addSession(session);
    _sessionAddedToStatistics = true;
  }

  Future<void> _openStatisticsDashboard() async {
    await _addCurrentSessionToStatisticsV2IfNeeded();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const StatisticsDashboardPage()),
    );
  }

  Future<Map<String, dynamic>> _loadStatisticsStore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statisticsPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return {
        'sessions': 0,
        'users': <String, dynamic>{},
        'updatedAt': DateTime.now().toIso8601String(),
      };
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        decoded.putIfAbsent('sessions', () => 0);
        decoded.putIfAbsent('users', () => <String, dynamic>{});
        decoded.putIfAbsent(
            'updatedAt', () => DateTime.now().toIso8601String());
        return decoded;
      }
    } catch (_) {
      // Fallback to clean structure if local stats became invalid JSON.
    }

    return {
      'sessions': 0,
      'users': <String, dynamic>{},
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _saveStatisticsStore(Map<String, dynamic> store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statisticsPrefsKey, jsonEncode(store));
  }

  Future<Map<String, dynamic>> _addCurrentSessionToStatisticsIfNeeded() async {
    final store = await _loadStatisticsStore();
    if (_sessionAddedToStatistics) return store;

    final users = Map<String, dynamic>.from(store['users'] as Map? ?? {});
    for (final userId in _sessionAllUserIds) {
      final existing = Map<String, dynamic>.from(
          users[userId] as Map? ?? const <String, dynamic>{});

      final fallbackIndex = _sessionAllUserIds.indexOf(userId);
      final displayName = _displayNameForUserId(userId, fallbackIndex);
      final username = _usernameForUserId(userId);
      final money = _moneyForUserId(userId);

      users[userId] = {
        'displayName': displayName,
        'username': username,
        'totalMoney': (existing['totalMoney'] as num? ?? 0).toInt() + money,
        'games': (existing['games'] as num? ?? 0).toInt() + 1,
      };
    }

    store['sessions'] = (store['sessions'] as num? ?? 0).toInt() + 1;
    store['users'] = users;
    store['updatedAt'] = DateTime.now().toIso8601String();
    await _saveStatisticsStore(store);
    _sessionAddedToStatistics = true;
    return store;
  }

  String _buildStatisticsText(Map<String, dynamic> store) {
    final users = Map<String, dynamic>.from(store['users'] as Map? ?? {});
    final rows = users.entries.toList()
      ..sort((a, b) {
        final aMoney = (a.value['totalMoney'] as num? ?? 0).toInt();
        final bMoney = (b.value['totalMoney'] as num? ?? 0).toInt();
        return bMoney.compareTo(aMoney);
      });

    final lines = <String>[
      'TOOCOOB - НЭГДСЭН СТАТИСТИК',
      'Нэмсэн тоглолтын тайлан: ${(store['sessions'] as num? ?? 0).toInt()}',
      'Нийт тоглогч: ${rows.length}',
      '',
      'Тоглогч тус бүрийн хураагдсан дүн:',
    ];

    for (int i = 0; i < rows.length; i++) {
      final value = Map<String, dynamic>.from(rows[i].value as Map);
      final displayName = (value['displayName'] ?? '').toString();
      final username = (value['username'] ?? '').toString();
      final totalMoney = (value['totalMoney'] as num? ?? 0).toInt();
      final games = (value['games'] as num? ?? 0).toInt();
      lines.add(
          '${i + 1}. $displayName (@$username): ₮$totalMoney | тоглосон: $games');
    }

    return lines.join('\n');
  }

  Future<Uint8List> _buildStatisticsPdfBytes(Map<String, dynamic> store) async {
    final doc = pw.Document();
    final baseFontData =
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldFontData =
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final baseFont = pw.Font.ttf(baseFontData);
    final boldFont = pw.Font.ttf(boldFontData);

    final users = Map<String, dynamic>.from(store['users'] as Map? ?? {});
    final rows = users.entries.toList()
      ..sort((a, b) {
        final aMoney = (a.value['totalMoney'] as num? ?? 0).toInt();
        final bMoney = (b.value['totalMoney'] as num? ?? 0).toInt();
        return bMoney.compareTo(aMoney);
      });

    final tableData = List<List<String>>.generate(rows.length, (index) {
      final value = Map<String, dynamic>.from(rows[index].value as Map);
      return [
        '${index + 1}',
        (value['displayName'] ?? '').toString(),
        '@${(value['username'] ?? '').toString()}',
        '${(value['totalMoney'] as num? ?? 0).toInt()}',
        '${(value['games'] as num? ?? 0).toInt()}',
      ];
    });

    doc.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        build: (context) => [
          pw.Text(
            'TOOCOOB - НЭГДСЭН СТАТИСТИК',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
              'Нэмсэн тоглолтын тайлан: ${(store['sessions'] as num? ?? 0).toInt()}'),
          pw.Text('Нийт тоглогч: ${rows.length}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'Display name',
              'Username',
              'Хураагдсан мөнгө (₮)',
              'Тоглосон'
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

  Future<void> _showStatisticsSummaryDialog(Map<String, dynamic> store) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Нэгдсэн статистик'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: SelectableText(_buildStatisticsText(store)),
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

  Future<void> _addToStatisticsAndShowSummary() async {
    final store = await _addCurrentSessionToStatisticsIfNeeded();
    if (!mounted) return;
    await _showStatisticsSummaryDialog(store);
  }

  Future<void> _printStatisticsReport() async {
    final store = await _addCurrentSessionToStatisticsIfNeeded();
    final bytes = await _buildStatisticsPdfBytes(store);
    await Printing.layoutPdf(
      name: 'toocoob_statistics',
      onLayout: (_) async => bytes,
    );
  }

  Future<void> _saveStatisticsJsonFile() async {
    final store = await _addCurrentSessionToStatisticsIfNeeded();
    final prettyJson = const JsonEncoder.withIndent('  ').convert(store);
    await _saveBytesByPlatform(
      bytes: Uint8List.fromList(utf8.encode(prettyJson)),
      defaultFileName: 'toocoob_statistics.json',
      typeLabel: 'JSON File',
      extensions: ['json'],
      mimeType: 'application/json',
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

    final tableData = List<List<String>>.generate(
      _sessionAllUserIds.length,
      (index) {
        final userId = _sessionAllUserIds[index];
        return [
          '${index + 1}',
          _displayNameForUserId(userId, index),
          '@${_usernameForUserId(userId)}',
          '${_moneyForUserId(userId)}',
        ];
      },
    );

    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;

    doc.addPage(
      pw.MultiPage(
        theme: pdfTheme,
        build: (context) => [
          pw.Text('13 МОДНЫ ПОКЕР - ТОГЛОЛТЫН ТАЙЛАН',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Эхний тоглогчийн тоо: $_sessionInitialPlayerCount'),
          pw.Text('Нийт оролцсон тоглогч: ${_sessionAllUserIds.length}'),
          pw.Text('Нэмсэн тоглогч: $_sessionAddedPlayers'),
          pw.Text('Хассан тоглогч: $_sessionRemovedPlayers'),
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
        name: 'toocoob_report',
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Хэвлэх цонх нээгдсэнгүй. PDF хадгалалтыг нээнэ.'),
        ),
      );
      final bytes = await _buildSessionReportPdfBytes();
      await _saveBytesByPlatform(
        bytes: bytes,
        defaultFileName: 'toocoob_report.pdf',
        typeLabel: 'PDF File',
        extensions: ['pdf'],
        mimeType: 'application/pdf',
      );
    }
  }

  Future<void> _runAfterSheetDismiss(
    BuildContext sheetContext,
    Future<void> Function() action,
  ) async {
    Navigator.of(sheetContext).pop();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    await action();
    _focusFirstMainScoreField();
  }

  Future<void> _shareReportToApps() async {
    try {
      final pdfBytes = await _buildSessionReportPdfBytes();
      final result = await SharePlus.instance.share(
        ShareParams(
          text: _buildSessionReportText(),
          subject: 'Тоглолтын тайлан',
          files: [
            XFile.fromData(
              pdfBytes,
              mimeType: 'application/pdf',
              name: 'toocoob_report.pdf',
            ),
          ],
        ),
      );

      if (result.status == ShareResultStatus.unavailable && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Төхөөрөмжийн Share дэмжлэггүй байна. PDF хадгалалт руу шилжүүллээ.',
            ),
          ),
        );
        await _saveBytesByPlatform(
          bytes: pdfBytes,
          defaultFileName: 'toocoob_report.pdf',
          typeLabel: 'PDF File',
          extensions: ['pdf'],
          mimeType: 'application/pdf',
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Илгээх үйлдэл амжилтгүй. PDF хадгалалтыг ашиглана.'),
        ),
      );
      final bytes = await _buildSessionReportPdfBytes();
      await _saveBytesByPlatform(
        bytes: bytes,
        defaultFileName: 'toocoob_report.pdf',
        typeLabel: 'PDF File',
        extensions: ['pdf'],
        mimeType: 'application/pdf',
      );
    }
  }

  Future<void> _showReportShareActions() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('Өөр апп-руу илгээх'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    _shareReportToApps,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Хэвлэх'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    _printSessionReport,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Файл болгон хадгалах'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    _showSaveFormatDialog,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.query_stats),
                title: const Text('Статистикт нэмэх / харах'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    _openStatisticsDashboard,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Статистик хуудас нээх'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    _openStatisticsDashboard,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.data_object),
                title: const Text('Статистикт нэмэх'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    _addCurrentSessionToStatisticsV2IfNeeded,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSaveFormatDialog() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        Future<void> savePdf() async {
          final bytes = await _buildSessionReportPdfBytes();
          await _saveBytesByPlatform(
            bytes: bytes,
            defaultFileName: 'toocoob_report.pdf',
            typeLabel: 'PDF File',
            extensions: ['pdf'],
            mimeType: 'application/pdf',
          );
        }

        Future<void> saveCsv() async {
          final csvRows = <List<String>>[
            ['#', 'display_name', 'username', 'money'],
            ...List<List<String>>.generate(_sessionAllUserIds.length, (index) {
              final userId = _sessionAllUserIds[index];
              return [
                '${index + 1}',
                _displayNameForUserId(userId, index),
                _usernameForUserId(userId),
                _moneyForUserId(userId).toString(),
              ];
            }),
          ];
          final content = csvRows
              .map((row) => row
                  .map((value) => '"${value.replaceAll('"', '""')}"')
                  .join(','))
              .join('\n');

          await _saveBytesByPlatform(
            bytes: Uint8List.fromList(utf8.encode(content)),
            defaultFileName: 'toocoob_report.csv',
            typeLabel: 'CSV File',
            extensions: ['csv'],
            mimeType: 'text/csv',
          );
        }

        Future<void> unsupported(String ext) async {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$ext формат одоогоор дэмжигдээгүй. PDF эсвэл CSV сонгоно уу.',
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('.pdf'),
                subtitle: const Text('Хэвлэх/хадгалах бүрэн дэмжинэ'),
                onTap: () async {
                  await _runAfterSheetDismiss(sheetContext, savePdf);
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('.csv (Excel нээдэг)'),
                subtitle: const Text('Excel дээр шууд нээгдэнэ'),
                onTap: () async {
                  await _runAfterSheetDismiss(sheetContext, saveCsv);
                },
              ),
              ListTile(
                leading: const Icon(Icons.grid_on),
                title: const Text('.xlsx'),
                subtitle: const Text('Тун удахгүй'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    () => unsupported('.xlsx'),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.slideshow),
                title: const Text('.pptx'),
                subtitle: const Text('Тун удахгүй'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    () => unsupported('.pptx'),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('.docx'),
                subtitle: const Text('Тун удахгүй'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    () => unsupported('.docx'),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('.jpg'),
                subtitle: const Text('Тун удахгүй'),
                onTap: () async {
                  await _runAfterSheetDismiss(
                    sheetContext,
                    () => unsupported('.jpg'),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
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
          subject: 'Тоглолтын тайлан',
        ),
      );
      return;
    }

    final saveLocation = await getSaveLocation(
      suggestedName: defaultFileName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: typeLabel,
          extensions: extensions,
        ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Файл хадгаллаа: ${saveLocation.path}')),
    );
  }

  Future<void> _showSessionSummaryDialog() async {
    final totalRounds =
        _sessionOrdinaryRounds + _sessionBoltRounds + _sessionMiddleBoltRounds;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтын тайлан'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSummaryPill(
                            'Эхний', _sessionInitialPlayerCount.toString()),
                        _buildSummaryPill('Нийт оролцсон',
                            _sessionAllUserIds.length.toString()),
                        _buildSummaryPill(
                            'Нэмсэн', _sessionAddedPlayers.toString()),
                        _buildSummaryPill(
                            'Хассан', _sessionRemovedPlayers.toString()),
                        _buildSummaryPill('Нийт раунд', totalRounds.toString()),
                        _buildSummaryPill(
                            'Энгийн', _sessionOrdinaryRounds.toString()),
                        _buildSummaryPill(
                            'Боолт', _sessionBoltRounds.toString()),
                        _buildSummaryPill('Дундын боолт',
                            _sessionMiddleBoltRounds.toString()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('#')),
                        DataColumn(label: Text('Display name')),
                        DataColumn(label: Text('Username')),
                        DataColumn(label: Text('Мөнгө (₮)')),
                      ],
                      rows: List<DataRow>.generate(
                        _sessionAllUserIds.length,
                        (index) {
                          final userId = _sessionAllUserIds[index];
                          return DataRow(
                            cells: [
                              DataCell(Text('${index + 1}')),
                              DataCell(
                                  Text(_displayNameForUserId(userId, index))),
                              DataCell(Text('@${_usernameForUserId(userId)}')),
                              DataCell(
                                Text(
                                  _moneyForUserId(userId).toString(),
                                  style: TextStyle(
                                    color: _moneyColorForAmount(
                                        _moneyForUserId(userId)),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await _showReportShareActions();
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
            ElevatedButton(
              onPressed: () async {
                await _askRegistrarDecisionAtGameEndIfNeeded();
                await _removeSavedProgressIfAny();
                await _releaseCurrentActiveTableLockIfAny();
                Navigator.of(dialogContext).pop();
                await _goToPlayerSelectionPage();
              },
              child: const Text('Гарах'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCycleCompletedDialog() async {
    final shouldReplay = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолт дууслаа'),
          content: const Text('Бүх энгийн + боолт тоглолт дууссан.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Дуусгах'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Дахин тойрох'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (shouldReplay == true) {
      setState(_resetForReplayKeepingMoney);
      return;
    }

    await _showSessionSummaryDialog();
  }

  Widget _buildSummaryPill(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _maintainActiveScoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (_isResolvingRound || _isSubmittingInlineScore) return;

      final primaryFocus = FocusManager.instance.primaryFocus;
      if (primaryFocus != null &&
          _eighthBlockFocusNodes.contains(primaryFocus)) {
        // Keep focus within 8th block inputs; do not force-jump to main fields.
        return;
      }

      final activeScorers = _scoringPlayersForTable(_activeUserNames);
      if (activeScorers.isEmpty) return;

      final candidateIds = activeScorers
          .where((userId) => !_isEliminatedByScore(userId))
          .toList();
      final focusNodes = candidateIds.map(_scoreFocusNodeFor).toList();
      if (focusNodes.isEmpty) return;

      if (primaryFocus != null && focusNodes.contains(primaryFocus)) {
        return;
      }

      String? targetUserId;
      for (final userId in candidateIds) {
        if (!_isScoreEnteredForCurrentRound(userId)) {
          targetUserId = userId;
          break;
        }
      }

      if (targetUserId == null) return;
      FocusScope.of(context).requestFocus(_scoreFocusNodeFor(targetUserId));
    });
  }

  void _maintainEighthScoreFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (_isResolvingRound || _isSubmittingInlineScore) return;

      final activeCells = _activeEighthCellCount;
      if (activeCells <= 0) return;

      final primaryFocus = FocusManager.instance.primaryFocus;
      if (primaryFocus != null &&
          _eighthBlockFocusNodes.contains(primaryFocus)) {
        return;
      }

      FocusScope.of(context).requestFocus(_eighthBlockFocusNodes[0]);
    });
  }

  bool _isScoreEnteredForCurrentRound(String userId) {
    if (_roundScores.containsKey(userId) ||
        _explicitZeroRoundUserIds.contains(userId)) {
      return true;
    }

    final text = _scoreControllerFor(userId).text.trim();
    if (text.isEmpty) return false;
    return int.tryParse(text) != null;
  }

  int _scoreContribution(int rawScore) {
    if (rawScore >= 10 && rawScore <= 12) return rawScore * 2;
    if (rawScore == 13) return rawScore * 3;
    return rawScore;
  }

  void _addScoreToTotal(String userId, int rawScore) {
    final currentTotal = _totalScores[userId] ?? 0;
    final contribution = _scoreContribution(rawScore);
    _totalScores[userId] = currentTotal + contribution;
  }

  TextEditingController _scoreControllerFor(String userId) {
    return _scoreControllers.putIfAbsent(userId, () {
      final hasScore = _roundScores.containsKey(userId);
      return TextEditingController(
        text: hasScore ? _roundScoreFor(userId).toString() : '',
      );
    });
  }

  FocusNode _scoreFocusNodeFor(String userId) {
    return _scoreFocusNodes.putIfAbsent(userId, FocusNode.new);
  }

  void _clearScoreInput(String userId) {
    final controller = _scoreControllerFor(userId);
    if (controller.text.isNotEmpty) {
      controller.value = TextEditingValue(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  void _disposeScoreInputFor(String userId) {
    _scoreControllers.remove(userId)?.dispose();
    _scoreFocusNodes.remove(userId)?.dispose();
  }

  void _disposeDetachedScoreInputs() {
    final active = _orderedUserNames.toSet();
    final detached = _scoreControllers.keys
        .where((userId) => !active.contains(userId))
        .toList();
    for (final userId in detached) {
      _disposeScoreInputFor(userId);
    }
  }

  void _focusNextScoreField(String currentUserId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final allScoreUserIds = _scoringPlayersForTable(_activeUserNames)
          .where((userId) => !_isEliminatedByScore(userId))
          .toList();
      if (allScoreUserIds.isEmpty) {
        FocusScope.of(context).unfocus();
        return;
      }

      final currentIndex = allScoreUserIds.indexOf(currentUserId);
      final startIndex = currentIndex >= 0 ? currentIndex : -1;

      for (int step = 1; step <= allScoreUserIds.length; step++) {
        final nextIndex = (startIndex + step) % allScoreUserIds.length;
        final candidateUserId = allScoreUserIds[nextIndex];
        if (_isScoreEnteredForCurrentRound(candidateUserId)) {
          continue;
        }
        final nextFocus = _scoreFocusNodeFor(candidateUserId);
        FocusScope.of(context).requestFocus(nextFocus);
        return;
      }

      FocusScope.of(context).unfocus();
    });
  }

  bool _isRoundCompletedFor(List<String> roundPlayers) {
    if (roundPlayers.length < 2) return false;
    final aliveCount =
        roundPlayers.where((userId) => !_isEliminatedByScore(userId)).length;
    return aliveCount == 1;
  }

  bool _isSpecialInstantWinInput(String rawText) {
    return rawText.trim() == '1331';
  }

  void _clearRoundStateForPlayers(List<String> roundPlayers) {
    for (final userId in roundPlayers) {
      _roundScores.remove(userId);
      _explicitZeroRoundUserIds.remove(userId);
      _paidOutRoundLoserUserIds.remove(userId);
      _totalScores.remove(userId);
      _eighthRoundScoresByUserId.remove(userId);
      _forcedEliminatedUserIds.remove(userId);
      _removeUserFromPinnedSubstitutes(userId);
      _clearScoreInput(userId);
    }
    _setPreferredBenchedUsersForCurrentTable(const <String>[]);
  }

  void _clearHandScoresForPlayers(List<String> players) {
    for (final userId in players) {
      _explicitZeroRoundUserIds.remove(userId);
      _clearScoreInput(userId);
    }
  }

  int get _activeEighthCellCount {
    return _activeEighthScoringUserIds.length;
  }

  List<String> get _activeEighthScoringUserIds {
    return _scoringPlayersForTable(_activeUserNames);
  }

  bool _applyEighthInputsToRoundScores() {
    final scoringUserIds = _activeEighthScoringUserIds;
    final activeCells = scoringUserIds.length;
    final parsedByUserId = <String, int>{};
    final rawTextByUserId = <String, String>{};

    for (int i = 0; i < activeCells; i++) {
      final userId = scoringUserIds[i];
      final rawText = _eighthBlockScoreControllers[i].text.trim();
      final normalizedText =
          (rawText.isEmpty || rawText == '-') ? '0' : rawText;
      final parsed = int.tryParse(normalizedText);
      if (parsed == null) {
        return false;
      }

      parsedByUserId[userId] = parsed;
      rawTextByUserId[userId] = normalizedText;
    }

    // Apply only after full validation so partial input never leaks into state.
    parsedByUserId.forEach((userId, parsed) {
      _roundScores[userId] = parsed;
      _explicitZeroRoundUserIds.remove(userId);
      _eighthRoundScoresByUserId[userId] = parsed;

      final rawText = rawTextByUserId[userId] ?? parsed.toString();
      final scoreController = _scoreControllerFor(userId);
      if (scoreController.text != rawText) {
        scoreController.text = rawText;
      }
    });

    return true;
  }

  void _clearEighthDraftStateForActivePlayers() {
    final scoringUserIds = _activeEighthScoringUserIds;
    final activeCells = scoringUserIds.length;
    for (int i = 0; i < activeCells; i++) {
      final userId = scoringUserIds[i];
      _roundScores.remove(userId);
      _explicitZeroRoundUserIds.remove(userId);
      _eighthRoundScoresByUserId.remove(userId);

      final scoreController = _scoreControllerFor(userId);
      if (scoreController.text.isNotEmpty) {
        scoreController.clear();
      }
    }
  }

  void _clearInactiveEighthInputs() {
    final activeCells = _activeEighthCellCount;

    for (int i = activeCells; i < 4; i++) {
      _eighthBlockScoreControllers[i].clear();
    }
  }

  void _clearActiveEighthInputs() {
    final activeCells = _activeEighthCellCount;
    for (int i = 0; i < activeCells; i++) {
      _eighthBlockScoreControllers[i].clear();
    }
  }

  void _focusEighthCell(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activeCells = _activeEighthCellCount;
      if (index < 0 || index >= activeCells) return;
      FocusScope.of(context).requestFocus(_eighthBlockFocusNodes[index]);
    });
  }

  Future<void> _onEighthCellSubmitted(int index) async {
    final activeCells = _activeEighthCellCount;
    if (index < 0 || index >= activeCells) return;

    if (index < activeCells - 1) {
      _focusEighthCell(index + 1);
      return;
    }

    final tablePlayers = List<String>.from(_activeUserNames);
    bool readyToCommit = false;

    setState(() {
      _clearInactiveEighthInputs();
      readyToCommit = _applyEighthInputsToRoundScores();
    });

    if (!readyToCommit) {
      // Incomplete row on last-cell Enter: clear draft values and restart from 1.
      setState(() {
        _clearEighthDraftStateForActivePlayers();
        _clearActiveEighthInputs();
      });
      _focusEighthCell(0);
      return;
    }

    final instantWinnerUserId = _activeEighthScoringUserIds.firstWhere(
      (userId) => _roundScores[userId] == 1331,
      orElse: () => '',
    );
    if (instantWinnerUserId.isNotEmpty) {
      await _completeRoundWithWinner(
        tablePlayers,
        instantWinnerUserId,
        isInstantSpecialWin: true,
      );
      return;
    }

    setState(() {
      _commitHandScoresToTotals(tablePlayers);
      _applyImmediateLoserMoneyUpdates(tablePlayers);
    });

    await _applyPostCommitMovement(tablePlayers);

    final tablePlayersAfterCommit = List<String>.from(_activeUserNames);
    if (_isRoundCompletedFor(tablePlayersAfterCommit)) {
      await _handleRoundCompletion(tablePlayersAfterCommit);
      return;
    }

    setState(() {
      // Keep committed round scores visible on blocks until the next submit.
      _clearActiveEighthInputs();
    });

    if (!mounted) return;
    // After a full valid row is submitted, clear and return cursor to cell 1.
    _focusEighthCell(0);
  }

  Future<void> _submitEighthCellFromKeyboard(int index) async {
    if (_isProcessingEighthSubmit) return;
    _isProcessingEighthSubmit = true;
    try {
      await _onEighthCellSubmitted(index);
    } finally {
      _isProcessingEighthSubmit = false;
    }
  }

  List<String> _getPinnedSubstitutesForCurrentTable() {
    if (_tableSplitSelected) {
      return currentTable == 1
          ? List<String>.from(_table1PinnedSubstituteUserIds)
          : List<String>.from(_table2PinnedSubstituteUserIds);
    }
    return List<String>.from(_pinnedSubstituteUserIds);
  }

  void _setPinnedSubstitutesForCurrentTable(List<String> value) {
    if (_tableSplitSelected) {
      if (currentTable == 1) {
        _table1PinnedSubstituteUserIds
          ..clear()
          ..addAll(value);
      } else {
        _table2PinnedSubstituteUserIds
          ..clear()
          ..addAll(value);
      }
      return;
    }
    _pinnedSubstituteUserIds
      ..clear()
      ..addAll(value);
  }

  void _removeUserFromPinnedSubstitutes(String userId) {
    _pinnedSubstituteUserIds.remove(userId);
    _table1PinnedSubstituteUserIds.remove(userId);
    _table2PinnedSubstituteUserIds.remove(userId);
  }

  int _rotatingSubstituteCountForTable(List<String> tablePlayers) {
    if (tablePlayers.length < 5 || tablePlayers.length > 7) return 0;
    final pinned = _getPinnedSubstitutesForCurrentTable();
    final activeNonPinnedCount = tablePlayers
        .where((userId) =>
            !_isEliminatedByScore(userId) && !pinned.contains(userId))
        .length;
    final rotatingCount = activeNonPinnedCount - 4;
    return rotatingCount > 0 ? rotatingCount : 0;
  }

  bool _isSubstitutionModeForCurrentTable([List<String>? tablePlayers]) {
    final players = tablePlayers ?? _activeUserNames;
    return _rotatingSubstituteCountForTable(players) > 0;
  }

  void _relocateEliminatedMainPlayersToSubstitutes(List<String> tablePlayers) {
    if (tablePlayers.length < 5 || tablePlayers.length > 7) return;

    final substituteSlotCount = tablePlayers.length - 4;
    final mainPlayers = tablePlayers.take(4).toList();
    final currentPinned = _getPinnedSubstitutesForCurrentTable()
        .where(tablePlayers.contains)
        .toList();

    final nextPinned = List<String>.from(currentPinned);
    if (nextPinned.length > substituteSlotCount) {
      nextPinned.removeRange(substituteSlotCount, nextPinned.length);
    }

    final activeSubstitutes = tablePlayers
        .skip(4)
        .where((userId) =>
            !_isEliminatedByScore(userId) && !nextPinned.contains(userId))
        .toList();

    final nextMain = <String>[];

    for (final userId in mainPlayers) {
      if (!_isEliminatedByScore(userId)) {
        nextMain.add(userId);
        continue;
      }

      final alreadyPinned = nextPinned.contains(userId);
      final hasSubstituteCapacity = nextPinned.length < substituteSlotCount;
      final canMoveToSubstitute = alreadyPinned || hasSubstituteCapacity;

      if (activeSubstitutes.isNotEmpty && canMoveToSubstitute) {
        if (!alreadyPinned) {
          nextPinned.add(userId);
        }
        nextMain.add(activeSubstitutes.removeAt(0));
        continue;
      }

      // If this eliminated main player cannot be replaced right now,
      // keep the player locked on the same main seat (red state in UI).
      nextMain.add(userId);
    }

    final nextRotatingSubs = List<String>.from(activeSubstitutes);
    final pinnedForSlots = nextPinned.reversed.toList();
    final reordered = _normalizeReorderedPlayers(
      [...nextMain, ...nextRotatingSubs, ...pinnedForSlots],
      tablePlayers,
    );

    _setPinnedSubstitutesForCurrentTable(nextPinned);
    _applyReorderedPlayersForCurrentTable(reordered);
  }

  bool _areAllMainScoresEntered(List<String> tablePlayers) {
    final mainPlayers = tablePlayers.take(4).toList();
    if (mainPlayers.length < 4) return false;
    return mainPlayers.every((userId) => _roundScores.containsKey(userId));
  }

  void _fillMissingMainScoresAsZero(List<String> tablePlayers) {
    final mainPlayers = tablePlayers.take(4).toList();
    for (final userId in mainPlayers) {
      if (_roundScores.containsKey(userId)) continue;
      _roundScores[userId] = 0;
    }
  }

  List<String> _scoringPlayersForTable(List<String> tablePlayers) {
    return _activePlayersByBenchForTable(tablePlayers);
  }

  bool _areAllScoringPlayersEntered(List<String> tablePlayers) {
    final scoringPlayers = _scoringPlayersForTable(tablePlayers);
    if (scoringPlayers.isEmpty) return false;
    return scoringPlayers.every((userId) => _roundScores.containsKey(userId));
  }

  void _syncScoringInputsToRoundScores(List<String> tablePlayers) {
    final scoringPlayers = _scoringPlayersForTable(tablePlayers);
    for (final scoringUserId in scoringPlayers) {
      final text = _scoreControllerFor(scoringUserId).text.trim();
      final parsed = int.tryParse(text);
      if (parsed != null) {
        _roundScores[scoringUserId] = parsed;
        _explicitZeroRoundUserIds.remove(scoringUserId);
      } else if (text.isEmpty) {
        if (_explicitZeroRoundUserIds.contains(scoringUserId)) {
          _roundScores[scoringUserId] = 0;
        } else {
          _roundScores.remove(scoringUserId);
        }
      }
    }
  }

  void _commitHandScoresToTotals(List<String> tablePlayers) {
    final scoringPlayers = _scoringPlayersForTable(tablePlayers);
    for (final userId in scoringPlayers) {
      final score = _roundScores[userId];
      if (score == null) continue;
      _addScoreToTotal(userId, score);
    }
  }

  Future<void> _applyPostCommitMovement(List<String> tablePlayers) async {
    if (widget.gameType != '13 МОДНЫ ПОКЕР' ||
        tablePlayers.length < 5 ||
        tablePlayers.length > 7) {
      if (!mounted) return;
      setState(() {
        _advanceBenchByRoundScores(tablePlayers);
        _applyTournamentMovement7Players();
      });
      return;
    }

    final reordered =
        await _buildSubstitutionReorderForCurrentTable(tablePlayers);
    if (!mounted) return;

    setState(() {
      if (reordered != null && reordered.isNotEmpty) {
        _applyReorderedPlayersForCurrentTable(reordered);
      }

      // Keep eliminated main player on the same seat when no substitute
      // slot/candidate is available for replacement.
      _relocateEliminatedMainPlayersToSubstitutes(_activeUserNames);
      _advanceBenchByRoundScores(_activeUserNames);
    });
  }

  void _applyImmediateLoserMoneyUpdates(List<String> tablePlayers) {
    for (final userId in tablePlayers) {
      if (!_isEliminatedByScore(userId)) continue;
      if (_paidOutRoundLoserUserIds.contains(userId)) continue;

      _moneyByUserId[userId] = _moneyForUserId(userId) - _activeBetAmount;
      _paidOutRoundLoserUserIds.add(userId);
    }
  }

  Future<List<String>?> _showTieBreakOrderDialog(
      List<String> tiedUserIds) async {
    final tiedDisplayNames = List<String>.generate(
      tiedUserIds.length,
      (index) => _displayNameForUserId(tiedUserIds[index], index),
    );

    final tiedUserNames = tiedUserIds.map(_usernameForUserId).toList();
    final selectedOrder = List<int?>.filled(tiedUserIds.length, null);
    int currentOrder = 1;

    final orderedIndices = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Тэнцсэн онооны дараалал'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Тэнцсэн тоглогчдыг дарааллаар эрэмбэлнэ. Эхний дугааруудаас С блокуудад шилжинэ.',
                    ),
                    const SizedBox(height: 12),
                    for (int i = 0; i < tiedUserIds.length; i++)
                      ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: selectedOrder[i] != null
                                ? Colors.blue
                                : Colors.grey.shade300,
                          ),
                        ),
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: selectedOrder[i] != null
                              ? Colors.blue
                              : Colors.grey.shade400,
                          child: Text(
                            selectedOrder[i]?.toString() ?? '-',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          tiedDisplayNames[i],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(tiedUserNames[i]),
                        onTap: () {
                          if (selectedOrder[i] == null &&
                              currentOrder <= tiedUserIds.length) {
                            setState(() {
                              selectedOrder[i] = currentOrder;
                              currentOrder++;
                            });
                          } else if (selectedOrder[i] != null) {
                            setState(() {
                              final removedOrder = selectedOrder[i]!;
                              selectedOrder[i] = null;
                              for (int j = 0; j < selectedOrder.length; j++) {
                                if (selectedOrder[j] != null &&
                                    selectedOrder[j]! > removedOrder) {
                                  selectedOrder[j] = selectedOrder[j]! - 1;
                                }
                              }
                              currentOrder--;
                            });
                          }
                        },
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
                  onPressed:
                      selectedOrder.where((value) => value != null).length ==
                              tiedUserIds.length
                          ? () {
                              final ordered =
                                  List<int>.filled(tiedUserIds.length, 0);
                              for (int i = 0; i < tiedUserIds.length; i++) {
                                if (selectedOrder[i] != null) {
                                  ordered[selectedOrder[i]! - 1] = i;
                                }
                              }
                              Navigator.of(dialogContext).pop(ordered);
                            }
                          : null,
                  child: const Text('Дараалал хадгалах'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || orderedIndices == null || orderedIndices.isEmpty) {
      return null;
    }

    return orderedIndices.map((index) => tiedUserIds[index]).toList();
  }

  Future<List<String>?> _buildSubstitutionReorderForCurrentTable(
      List<String> tablePlayers) async {
    if (tablePlayers.length < 5 || tablePlayers.length > 7) return null;

    final substituteSlotCount = tablePlayers.length - 4;
    final pinned = _getPinnedSubstitutesForCurrentTable()
        .where(tablePlayers.contains)
        .toList();
    final visibleMainPlayers = tablePlayers.take(4).toList();

    final nextPinned = List<String>.from(pinned);

    // Keep only available C-slot amount.
    if (nextPinned.length > substituteSlotCount) {
      nextPinned.removeRange(substituteSlotCount, nextPinned.length);
    }

    final nextMainPlayers = List<String>.from(visibleMainPlayers);
    final availableSubstitutes = tablePlayers
        .skip(4)
        .where((userId) =>
            !_isEliminatedByScore(userId) && !nextPinned.contains(userId))
        .toList();

    final eliminatedVisibleMain = visibleMainPlayers
        .where((userId) => _isEliminatedByScore(userId))
        .toList();
    final eliminatedVisibleMainThisHand = eliminatedVisibleMain
        .where((userId) => _roundScores.containsKey(userId))
        .toList();

    if (eliminatedVisibleMainThisHand.isNotEmpty &&
        availableSubstitutes.isNotEmpty) {
      // Excel-aligned flow: do score-based moving first (among still-active
      // main players), then resolve newly eliminated main seats.
      final scoringMainPlayers = visibleMainPlayers
          .where((userId) => !_isEliminatedByScore(userId))
          .where((userId) => _roundScores.containsKey(userId))
          .toList();

      final activeNonPinnedCount = tablePlayers
          .where((userId) =>
              !_isEliminatedByScore(userId) && !nextPinned.contains(userId))
          .length;
      // During elimination rounds, keep at least one score-based rotation
      // before elimination seat replacement.
      final rotatingSubstituteCount = (activeNonPinnedCount - 4).clamp(0, 3) < 1
          ? 1
          : (activeNonPinnedCount - 4).clamp(0, 3);

      final movingToSubstituteByScore = <String>[];
      if (rotatingSubstituteCount > 0 && scoringMainPlayers.isNotEmpty) {
        final scoredMain = List<MapEntry<String, int>>.generate(
          scoringMainPlayers.length,
          (index) => MapEntry(
            scoringMainPlayers[index],
            _roundScoreFor(scoringMainPlayers[index]),
          ),
        );

        scoredMain.sort((a, b) {
          final byScore = a.value.compareTo(b.value);
          if (byScore != 0) return byScore;
          final aIndex = scoringMainPlayers.indexOf(a.key);
          final bIndex = scoringMainPlayers.indexOf(b.key);
          return aIndex.compareTo(bIndex);
        });

        final scoreGroups = <int, List<String>>{};
        for (final entry in scoredMain) {
          scoreGroups.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
        }

        final sortedScores = scoreGroups.keys.toList()..sort();
        int remainingSlots = rotatingSubstituteCount;

        for (final score in sortedScores) {
          if (remainingSlots <= 0) break;
          final group =
              List<String>.from(scoreGroups[score] ?? const <String>[]);
          if (group.isEmpty) continue;

          List<String> orderedGroup = group;
          if (group.length >= 2) {
            final selectedOrder = await _showTieBreakOrderDialog(group);
            if (selectedOrder != null && selectedOrder.isNotEmpty) {
              orderedGroup = selectedOrder;
            }
          }

          if (orderedGroup.length <= remainingSlots) {
            movingToSubstituteByScore.addAll(orderedGroup);
            remainingSlots -= orderedGroup.length;
          } else {
            movingToSubstituteByScore.addAll(orderedGroup.take(remainingSlots));
            remainingSlots = 0;
          }
        }
      }

      final remainingSubstitutes = List<String>.from(availableSubstitutes);
      final scoreMovedApplied = <String>[];

      for (final movingOut in movingToSubstituteByScore) {
        if (remainingSubstitutes.isEmpty) break;
        final targetMainIndex = nextMainPlayers.indexOf(movingOut);
        if (targetMainIndex < 0) continue;
        nextMainPlayers[targetMainIndex] = remainingSubstitutes.removeAt(0);
        scoreMovedApplied.add(movingOut);
      }

      final movedEliminatedMain = <String>[];
      for (final eliminatedUserId in eliminatedVisibleMainThisHand) {
        final loserIndex = visibleMainPlayers.indexOf(eliminatedUserId);
        if (loserIndex < 0) continue;

        final alreadyPinned = nextPinned.contains(eliminatedUserId);
        final hasSubstituteCapacity = nextPinned.length < substituteSlotCount;
        final canMoveToSubstitute = alreadyPinned || hasSubstituteCapacity;
        if (!canMoveToSubstitute) {
          continue;
        }

        movedEliminatedMain.add(eliminatedUserId);
        if (!alreadyPinned) {
          nextPinned.add(eliminatedUserId);
        }

        String? incomingUserId;
        // Fill with untouched substitutes first; if none left,
        // fallback to players moved out by score this hand.
        if (remainingSubstitutes.isNotEmpty) {
          incomingUserId = remainingSubstitutes.removeAt(0);
        } else if (scoreMovedApplied.isNotEmpty) {
          incomingUserId = scoreMovedApplied.removeAt(0);
        }

        if (incomingUserId != null) {
          nextMainPlayers[loserIndex] = incomingUserId;
        }
      }

      final nextSubstitutesAfterElimination = <String>[
        ...scoreMovedApplied.where((userId) => !nextPinned.contains(userId)),
        ...remainingSubstitutes,
      ];

      _setPinnedSubstitutesForCurrentTable(nextPinned);
      final pinnedForSlots = nextPinned.reversed.toList();
      return _normalizeReorderedPlayers(
        [
          ...nextMainPlayers,
          ...nextSubstitutesAfterElimination,
          ...pinnedForSlots,
        ],
        tablePlayers,
      );
    }

    // Tie-break must use only players who actually played this hand
    // (the originally visible main players), not newly swapped-in substitutes.
    final scoringMainPlayers = visibleMainPlayers
        .where((userId) => !_isEliminatedByScore(userId))
        .where((userId) => _roundScores.containsKey(userId))
        .toList();

    final activeNonPinnedCount = tablePlayers
        .where((userId) =>
            !_isEliminatedByScore(userId) && !nextPinned.contains(userId))
        .length;
    final rotatingSubstituteCount = (activeNonPinnedCount - 4).clamp(0, 3);

    if (rotatingSubstituteCount <= 0) {
      _setPinnedSubstitutesForCurrentTable(nextPinned);
      final pinnedForSlots = nextPinned.reversed.toList();
      return _normalizeReorderedPlayers(
        [...nextMainPlayers, ...pinnedForSlots],
        tablePlayers,
      );
    }

    final scoredMain = List<MapEntry<String, int>>.generate(
      scoringMainPlayers.length,
      (index) => MapEntry(
          scoringMainPlayers[index], _roundScoreFor(scoringMainPlayers[index])),
    );

    scoredMain.sort((a, b) {
      final byScore = a.value.compareTo(b.value);
      if (byScore != 0) return byScore;
      final aIndex = scoringMainPlayers.indexOf(a.key);
      final bIndex = scoringMainPlayers.indexOf(b.key);
      return aIndex.compareTo(bIndex);
    });

    final scoreGroups = <int, List<String>>{};
    for (final entry in scoredMain) {
      scoreGroups.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
    }

    final sortedScores = scoreGroups.keys.toList()..sort();
    final movingToSubstitute = <String>[];
    int remainingSlots = rotatingSubstituteCount;

    for (final score in sortedScores) {
      if (remainingSlots <= 0) break;
      final group = List<String>.from(scoreGroups[score] ?? const <String>[]);
      if (group.isEmpty) continue;

      List<String> orderedGroup = group;
      if (group.length >= 2) {
        final selectedOrder = await _showTieBreakOrderDialog(group);
        if (selectedOrder != null && selectedOrder.isNotEmpty) {
          orderedGroup = selectedOrder;
        }
      }

      if (orderedGroup.length <= remainingSlots) {
        movingToSubstitute.addAll(orderedGroup);
        remainingSlots -= orderedGroup.length;
      } else {
        movingToSubstitute.addAll(orderedGroup.take(remainingSlots));
        remainingSlots = 0;
      }
    }

    // Newly eliminated main players must also vacate main seats in this hand,
    // so append them after score-based movers (low -> high order stays intact).
    for (final eliminatedUserId in eliminatedVisibleMainThisHand) {
      if (movingToSubstitute.contains(eliminatedUserId)) continue;
      movingToSubstitute.add(eliminatedUserId);
    }

    final movedOutCount = [
      availableSubstitutes.length,
      movingToSubstitute.length,
    ].reduce((a, b) => a < b ? a : b);

    for (int i = 0; i < movedOutCount; i++) {
      final movingOut = movingToSubstitute[i];
      final targetMainIndex = visibleMainPlayers.indexOf(movingOut);
      if (targetMainIndex >= 0) {
        nextMainPlayers[targetMainIndex] = availableSubstitutes[i];
      }
    }

    final nextSubstitutes = <String>[
      ...movingToSubstitute
          .take(movedOutCount)
          .where((userId) => !nextPinned.contains(userId)),
      ...availableSubstitutes.skip(movedOutCount),
    ];

    _setPinnedSubstitutesForCurrentTable(nextPinned);
    final pinnedForSlots = nextPinned.reversed.toList();
    return _normalizeReorderedPlayers(
      [...nextMainPlayers, ...nextSubstitutes, ...pinnedForSlots],
      tablePlayers,
    );
  }

  List<String> _normalizeReorderedPlayers(
    List<String> reordered,
    List<String> sourcePlayers,
  ) {
    final sourceSet = sourcePlayers.toSet();
    final normalized = <String>[];

    for (final userId in reordered) {
      if (!sourceSet.contains(userId)) continue;
      if (normalized.contains(userId)) continue;
      normalized.add(userId);
    }

    for (final userId in sourcePlayers) {
      if (!normalized.contains(userId)) {
        normalized.add(userId);
      }
    }

    if (normalized.length > sourcePlayers.length) {
      normalized.removeRange(sourcePlayers.length, normalized.length);
    }

    return normalized;
  }

  void _applyReorderedPlayersForCurrentTable(List<String> reorderedForBoard) {
    if (_tableSplitSelected) {
      if (currentTable == 1) {
        _table1UserNames = reorderedForBoard;
      } else {
        _table2UserNames = reorderedForBoard;
      }
    } else {
      _orderedUserNames = reorderedForBoard;
    }

    _refreshDisplayNamesFromProfiles();
    playerCount = _orderedUserNames.length;
  }

  void _focusFirstMainScoreField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mainPlayers = _activeUserNames.take(4).toList();
      for (final userId in mainPlayers) {
        if (_isEliminatedByScore(userId)) {
          continue;
        }
        FocusScope.of(context).requestFocus(_scoreFocusNodeFor(userId));
        return;
      }
      FocusScope.of(context).unfocus();
    });
  }

  void _focusFirstActiveScoringField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;

      final scorers = _scoringPlayersForTable(_activeUserNames)
          .where((userId) => !_isEliminatedByScore(userId))
          .toList();
      if (scorers.isEmpty) {
        FocusScope.of(context).unfocus();
        return;
      }

      FocusScope.of(context).requestFocus(_scoreFocusNodeFor(scorers.first));
    });
  }

  List<String> _arrangePlayersForBoardLayout(
      List<String> playersInSelectedOrder) {
    final arranged = List<String>.from(playersInSelectedOrder);
    // 13-card tournament slots: 1-4 are always N-zone (green/red),
    // 5..N are Sh-zone (yellow). Move first N-4 selected players to Sh slots.
    if (widget.gameType == '13 МОДНЫ ПОКЕР' &&
        arranged.length >= 5 &&
        arranged.length <= 7) {
      final yellowCount = arranged.length - 4;
      return <String>[
        ...arranged.skip(yellowCount),
        ...arranged.take(yellowCount),
      ];
    }
    return arranged;
  }

  void _applyRoundOrderForCurrentTable(
      List<String> roundPlayers, List<int> orderedIndices) {
    final reordered = orderedIndices.map((i) => roundPlayers[i]).toList();
    final arranged = _arrangePlayersForBoardLayout(reordered);

    if (_tableSplitSelected) {
      final targetUsers = currentTable == 1
          ? List<String>.from(_table1UserNames)
          : List<String>.from(_table2UserNames);
      for (int i = 0; i < arranged.length && i < targetUsers.length; i++) {
        targetUsers[i] = arranged[i];
      }
      if (currentTable == 1) {
        _table1UserNames = targetUsers;
      } else {
        _table2UserNames = targetUsers;
      }
    } else {
      final targetUsers = List<String>.from(_orderedUserNames);
      for (int i = 0; i < arranged.length && i < targetUsers.length; i++) {
        targetUsers[i] = arranged[i];
      }
      _orderedUserNames = targetUsers;
    }

    _refreshDisplayNamesFromProfiles();
    playerCount = _orderedUserNames.length;
  }

  Future<void> _completeRoundWithWinner(
      List<String> roundPlayers, String winnerUserId,
      {bool isInstantSpecialWin = false}) async {
    if (_isResolvingRound || !mounted) return;
    if (!roundPlayers.contains(winnerUserId)) return;

    if (widget.autoReturnOnWinner && !_multiAutoReturnTriggered) {
      _multiAutoReturnTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop(<String, dynamic>{
          'completedGame': '13_card_poker',
          'winnerUserId': winnerUserId,
        });
      });
      return;
    }

    final wasBoltRound = _isBoltMode;

    _isResolvingRound = true;
    final loserUserIds =
        roundPlayers.where((userId) => userId != winnerUserId).toList();

    setState(() {
      if (wasBoltRound) {
        if (_middleTieDecisionMade) {
          _sessionMiddleBoltRounds += 1;
        } else {
          _sessionBoltRounds += 1;
        }
      } else {
        _sessionOrdinaryRounds += 1;
      }

      _winsByUserId[winnerUserId] = _winsForUserId(winnerUserId) + 1;
      _forcedEliminatedUserIds.remove(winnerUserId);
      _paidOutRoundLoserUserIds.remove(winnerUserId);

      final pot = loserUserIds.length * _activeBetAmount;
      _moneyByUserId[winnerUserId] = _moneyForUserId(winnerUserId) + pot;
      for (final loserUserId in loserUserIds) {
        if (isInstantSpecialWin) {
          _roundScores[loserUserId] = 39;
          _eighthRoundScoresByUserId[loserUserId] = 39;
          _addScoreToTotal(loserUserId, 39);
        }
        _forcedEliminatedUserIds.add(loserUserId);
        if (!_paidOutRoundLoserUserIds.contains(loserUserId)) {
          _moneyByUserId[loserUserId] =
              _moneyForUserId(loserUserId) - _activeBetAmount;
        }
        _paidOutRoundLoserUserIds.add(loserUserId);
        if (!isInstantSpecialWin) {
          final loserTotal = _totalScoreFor(loserUserId);
          if (loserTotal < _activeScoreLimit) {
            _totalScores[loserUserId] = _activeScoreLimit;
          }
        }
      }
    });

    setState(() {
      roundNumber += 1;
      if (!_middleTieDecisionMade) {
        _updateBoltModeForNextRound();
      } else if (wasBoltRound) {
        _isBoltMode = false;
        _currentBoltUserId = null;
      }
    });

    if (wasBoltRound && _middleTieDecisionMade) {
      await _showCycleCompletedDialog();
      _isResolvingRound = false;
      return;
    }

    if (_shouldShowMiddleTieDecisionDialog()) {
      final decision = await _showMiddleTieDecisionDialog();
      if (!mounted) {
        _isResolvingRound = false;
        return;
      }

      if (decision == 'replay') {
        setState(_resetForReplayKeepingMoney);
        _isResolvingRound = false;
        return;
      }

      if (decision == 'finish' || decision == null) {
        await _showSessionSummaryDialog();
        _isResolvingRound = false;
        return;
      }

      if (decision == 'bolt') {
        setState(() {
          _middleTieDecisionMade = true;
          _isBoltMode = true;
          _boltRoundNumber = 1;
        });
      }
    }

    if (!_middleTieDecisionMade && _isCurrentCycleCompleted()) {
      await _showCycleCompletedDialog();
      _isResolvingRound = false;
      return;
    }

    if (roundPlayers.length >= 3) {
      final roundDisplayNames = List<String>.generate(
        roundPlayers.length,
        (index) => _displayNameForUserId(roundPlayers[index], index),
      );

      await showPlayerOrderDialog(
        roundPlayers,
        roundDisplayNames,
        (orderedIndices) {
          setState(() {
            _applyRoundOrderForCurrentTable(roundPlayers, orderedIndices);
            _clearRoundStateForPlayers(roundPlayers);
          });
        },
      );
    } else {
      setState(() {
        _clearRoundStateForPlayers(roundPlayers);
      });
    }

    _isResolvingRound = false;
  }

  Future<void> _handleRoundCompletion(List<String> roundPlayers) async {
    if (_isResolvingRound || !mounted) return;
    if (!_isRoundCompletedFor(roundPlayers)) return;

    final alivePlayers =
        roundPlayers.where((userId) => !_isEliminatedByScore(userId)).toList();
    if (alivePlayers.length != 1) return;

    await _completeRoundWithWinner(roundPlayers, alivePlayers.first);
  }

  Future<void> _submitInlineScore(String userId,
      {String? submittedText}) async {
    if (_isResolvingRound || _isSubmittingInlineScore) return;

    _isSubmittingInlineScore = true;
    try {
      if (_isEliminatedByScore(userId)) {
        _focusNextScoreField(userId);
        return;
      }

      final roundPlayers = List<String>.from(_activeUserNames);
      final controller = _scoreControllerFor(userId);
      final rawText = (submittedText ?? controller.text).trim();
      final parsed = int.tryParse(rawText);

      if (_isSpecialInstantWinInput(rawText) || parsed == 1331) {
        _clearScoreInput(userId);
        await _completeRoundWithWinner(
          roundPlayers,
          userId,
          isInstantSpecialWin: true,
        );
        return;
      }

      setState(() {
        _syncScoringInputsToRoundScores(roundPlayers);
        if (parsed != null) {
          _roundScores[userId] = parsed;
          _explicitZeroRoundUserIds.remove(userId);
        } else if (rawText.isEmpty) {
          _roundScores[userId] = 0;
          _explicitZeroRoundUserIds.add(userId);
        }
      });

      final tablePlayersAfterInput = List<String>.from(_activeUserNames);

      if (!_areAllScoringPlayersEntered(tablePlayersAfterInput)) {
        _focusNextScoreField(userId);
        return;
      }

      setState(() {
        _commitHandScoresToTotals(tablePlayersAfterInput);
        _applyImmediateLoserMoneyUpdates(tablePlayersAfterInput);
      });

      await _applyPostCommitMovement(tablePlayersAfterInput);

      final tablePlayersAfterCommit = List<String>.from(_activeUserNames);

      if (_isRoundCompletedFor(tablePlayersAfterCommit)) {
        await _handleRoundCompletion(tablePlayersAfterCommit);
        return;
      }

      // Hand inputs are reset after post-commit movement is applied.
      setState(() {
        _clearHandScoresForPlayers(List<String>.from(_activeUserNames));
      });
      _focusFirstActiveScoringField();
    } finally {
      _isSubmittingInlineScore = false;
    }
  }

  int _requiredTable1Count(int totalPlayers) {
    if (totalPlayers <= 7) return totalPlayers;
    final balanced = (totalPlayers / 2).ceil();
    return balanced > 7 ? 7 : balanced;
  }

  String _usernameForUserId(String userId) {
    final profile = _userProfiles[userId];
    final username = (profile?['username'] ?? '').toString().trim();
    if (username.isNotEmpty) return username;
    return userId;
  }

  String _displayNameForUserId(String userId, int fallbackIndex) {
    final profile = _userProfiles[userId];
    final displayName = (profile?['displayName'] ?? '').toString().trim();
    final username = (profile?['username'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;
    if (username.isNotEmpty) return username;
    return 'Тоглогч ${fallbackIndex + 1}';
  }

  String? _photoUrlForUserId(String userId) {
    final profile = _userProfiles[userId];
    final photoUrl = (profile?['photoUrl'] ?? '').toString().trim();
    if (photoUrl.isEmpty) return null;
    return photoUrl;
  }

  void _refreshDisplayNamesFromProfiles() {
    _orderedDisplayNames = List<String>.generate(
      _orderedUserNames.length,
      (index) => _displayNameForUserId(_orderedUserNames[index], index),
    );

    if (_tableSplitSelected) {
      _table1DisplayNames = List<String>.generate(
        _table1UserNames.length,
        (index) => _displayNameForUserId(_table1UserNames[index], index),
      );
      _table2DisplayNames = List<String>.generate(
        _table2UserNames.length,
        (index) => _displayNameForUserId(_table2UserNames[index], index),
      );
    }
  }

  List<List<String>> _chunkIds(List<String> ids, int size) {
    final chunks = <List<String>>[];
    for (int i = 0; i < ids.length; i += size) {
      final end = (i + size < ids.length) ? i + size : ids.length;
      chunks.add(ids.sublist(i, end));
    }
    return chunks;
  }

  Future<void> _loadUserProfilesByIds(List<String> ids) async {
    final uniqueIds = ids.toSet().where((id) => id.trim().isNotEmpty).toList();
    if (uniqueIds.isEmpty) return;

    final fetched = <String, Map<String, dynamic>>{};
    for (final chunk in _chunkIds(uniqueIds, 10)) {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        fetched[doc.id] = doc.data();
      }
    }

    if (!mounted) return;
    setState(() {
      _userProfiles.addAll(fetched);
      _refreshDisplayNamesFromProfiles();
      playerCount = _orderedUserNames.length;
    });
  }

  bool _areProfilesLoadedFor(List<String> ids) {
    if (ids.isEmpty) return true;
    return ids.every((id) => _userProfiles.containsKey(id));
  }

  List<String> get _activeUserNames {
    if (_tableSplitSelected) {
      return currentTable == 1 ? _table1UserNames : _table2UserNames;
    }
    return _orderedUserNames;
  }

  List<String> get _activeDisplayNames {
    if (_tableSplitSelected) {
      return currentTable == 1 ? _table1DisplayNames : _table2DisplayNames;
    }
    return _orderedDisplayNames;
  }

  Future<void> _showBelowEightSplitDecisionDialog() async {
    final shouldMerge = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглогчийн тоо буурлаа'),
          content: const Text(
              'Нийт тоглогч 8-аас бага боллоо. 2 ширээг нэгтгэх үү эсвэл 2 ширээндээ тоглож дуусгах уу?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Үгүй, 2 ширээнд дуусгах'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Нэгтгэх'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldMerge != true) return;

    final mergedUsers = [
      ..._table1UserNames,
      ..._table2UserNames,
    ];
    final mergedDisplayNames = List<String>.generate(
      mergedUsers.length,
      (index) => _displayNameForUserId(mergedUsers[index], index),
    );

    if (mergedUsers.isEmpty) {
      setState(() {
        _orderedUserNames = [];
        _orderedDisplayNames = [];
        _tableSplitSelected = false;
        _table1UserNames = [];
        _table1DisplayNames = [];
        _table2UserNames = [];
        _table2DisplayNames = [];
        currentTable = 1;
        playerCount = 0;
      });
      return;
    }

    if (mergedUsers.length < 3) {
      setState(() {
        _orderedUserNames = List<String>.from(mergedUsers);
        _orderedDisplayNames = List<String>.from(mergedDisplayNames);
        _tableSplitSelected = false;
        _table1UserNames = [];
        _table1DisplayNames = [];
        _table2UserNames = [];
        _table2DisplayNames = [];
        currentTable = 1;
        playerCount = _orderedUserNames.length;
      });
      return;
    }

    await showPlayerOrderDialog(
      mergedUsers,
      List<String>.from(mergedDisplayNames),
      (orderedIndices) {
        setState(() {
          final selectedOrderUsers =
              orderedIndices.map((i) => mergedUsers[i]).toList();
          _orderedUserNames = _arrangePlayersForBoardLayout(selectedOrderUsers);
          _refreshDisplayNamesFromProfiles();
          _tableSplitSelected = false;
          _table1UserNames = [];
          _table1DisplayNames = [];
          _table2UserNames = [];
          _table2DisplayNames = [];
          currentTable = 1;
          playerCount = _orderedUserNames.length;
        });
      },
    );
  }

  Future<void> _applySplitAndPromptTableOrders(List<int> table1Indices) async {
    final sortedTable1 = List<int>.from(table1Indices)..sort();
    final allIndices = List<int>.generate(_orderedUserNames.length, (i) => i);
    final table2Indices =
        allIndices.where((index) => !sortedTable1.contains(index)).toList();

    setState(() {
      _table1UserNames = sortedTable1.map((i) => _orderedUserNames[i]).toList();
      _table1DisplayNames =
          sortedTable1.map((i) => _orderedDisplayNames[i]).toList();
      _table2UserNames =
          table2Indices.map((i) => _orderedUserNames[i]).toList();
      _table2DisplayNames =
          table2Indices.map((i) => _orderedDisplayNames[i]).toList();
      _tableSplitSelected = true;
      currentTable = 1;
    });

    await showPlayerOrderDialog(
      _table1UserNames,
      List<String>.from(_table1DisplayNames),
      (orderedIndices) {
        setState(() {
          final prevUsers = List<String>.from(_table1UserNames);
          final selectedOrderUsers =
              orderedIndices.map((i) => prevUsers[i]).toList();
          _table1UserNames = _arrangePlayersForBoardLayout(selectedOrderUsers);
          _refreshDisplayNamesFromProfiles();
        });
      },
    );

    if (!mounted || !_tableSplitSelected) return;

    setState(() {
      currentTable = 2;
    });

    await showPlayerOrderDialog(
      _table2UserNames,
      List<String>.from(_table2DisplayNames),
      (orderedIndices) {
        setState(() {
          final prevUsers = List<String>.from(_table2UserNames);
          final selectedOrderUsers =
              orderedIndices.map((i) => prevUsers[i]).toList();
          _table2UserNames = _arrangePlayersForBoardLayout(selectedOrderUsers);
          _refreshDisplayNamesFromProfiles();
        });
      },
    );

    if (!mounted || !_tableSplitSelected) return;
    setState(() {
      currentTable = 1;
    });
  }

  @override
  void initState() {
    super.initState();
    _currentRegistrarUserId = widget.currentRegistrarUserId;
    if (widget.selectedUserIds.isNotEmpty) {
      userNames = List<String>.from(widget.selectedUserIds);
      _orderedUserNames = List.from(userNames);
      _refreshDisplayNamesFromProfiles();
      _loadUserProfilesByIds(_orderedUserNames);
    } else {
      userNames = [
        'user1',
        'user2',
        'user3',
        'user4',
        'user5',
        'user6',
        'user7',
        'user8'
      ];
      displayNames = [
        'Тоглогч 1',
        'Тоглогч 2',
        'Тоглогч 3',
        'Тоглогч 4',
        'Тоглогч 5',
        'Тоглогч 6',
        'Тоглогч 7',
        'Тоглогч 8'
      ];
      _orderedUserNames = List.from(userNames.take(4));
      _orderedDisplayNames = List.from(displayNames.take(4));
    }
    playerCount = _orderedDisplayNames.length;
    _sessionInitialPlayerCount = _orderedUserNames.length;
    _registerSessionUsers(_orderedUserNames);
    _tryRestoreSavedSession();
  }

  @override
  void dispose() {
    for (final controller in _scoreControllers.values) {
      controller.dispose();
    }
    for (final controller in _eighthBlockScoreControllers) {
      controller.dispose();
    }
    for (final focusNode in _eighthBlockFocusNodes) {
      focusNode.dispose();
    }
    for (final focusNode in _scoreFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String? _currentActiveTableLockId() {
    final routeName = ModalRoute.of(context)?.settings.name;
    if (routeName == null || !routeName.startsWith('active-table:')) {
      return null;
    }

    final lockId = routeName.substring('active-table:'.length).trim();
    return lockId.isEmpty ? null : lockId;
  }

  Future<void> _releaseCurrentActiveTableLockIfAny() async {
    final lockId = _currentActiveTableLockId();
    if (lockId == null) return;

    try {
      await _activeTablesRepo.releaseActiveTableLock(lockId);
    } catch (_) {
      // Best-effort release. Navigation should still continue.
    }
  }

  Future<void> _goToPlayerSelectionPage() async {
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _handleBackFromGameAppBar() async {
    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => KindsOfGamePage(
          selectedUserIds: List<String>.from(_orderedUserNames),
          playingFormat: widget.multiWinsByUserId != null ? 'multi' : 'single',
        ),
      ),
    );
  }

  Future<void> _showExitDecisionDialog() async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтоос гарах'),
          content: const Text('Гарахаас өмнө одоогийн тоглолтыг хадгалах уу?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('cancel'),
              child: const Text('Болих'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('no_save'),
              child: const Text('Үгүй'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop('save'),
              child: const Text('Тийм'),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null || action == 'cancel') return;

    if (action == 'save') {
      await _saveProgress();
      await _releaseCurrentActiveTableLockIfAny();
      await _goToPlayerSelectionPage();
      return;
    }

    await _showSessionSummaryDialog();
  }

  Future<void> _showRemovePlayerDialogFromAppBar() async {
    if (_orderedUserNames.length <= 2) return;

    final maxRemovable = _orderedUserNames.length - 2;
    final playersForRemove = _tableSplitSelected
        ? List<String>.from(_activeUserNames)
        : List<String>.from(_orderedUserNames);
    final displayNamesForRemove = _tableSplitSelected
        ? List<String>.from(_activeDisplayNames)
        : List<String>.from(_orderedDisplayNames);

    await showPlayerRemoveDialog(
      playersForRemove,
      displayNamesForRemove,
      maxRemovable,
      (removeIndices) {
        if (removeIndices.isEmpty) return;
        bool shouldAskBelowEightDecision = false;
        Set<String> removedUserIds = <String>{};
        setState(() {
          final previousPlayerCount = _orderedUserNames.length;
          removedUserIds =
              removeIndices.map((i) => playersForRemove[i]).toSet();
          for (final removedUserId in removedUserIds) {
            _roundScores.remove(removedUserId);
            _explicitZeroRoundUserIds.remove(removedUserId);
            _totalScores.remove(removedUserId);
            _winsByUserId.remove(removedUserId);
            _completedBoltUserIds.remove(removedUserId);
            _removeUserFromPinnedSubstitutes(removedUserId);
            if (_currentBoltUserId == removedUserId) {
              _currentBoltUserId = null;
            }
            _disposeScoreInputFor(removedUserId);
          }
          _sessionRemovedPlayers += removedUserIds.length;
          _registerSessionUsers(removedUserIds);
          _orderedUserNames = _orderedUserNames
              .where((u) => !removedUserIds.contains(u))
              .toList();
          _refreshDisplayNamesFromProfiles();
          playerCount = _orderedUserNames.length;
          if (_tableSplitSelected) {
            _table1UserNames = _table1UserNames
                .where((u) => !removedUserIds.contains(u))
                .toList();
            _table2UserNames = _table2UserNames
                .where((u) => !removedUserIds.contains(u))
                .toList();
            _refreshDisplayNamesFromProfiles();
            if (currentTable == 2 && _table2UserNames.isEmpty) {
              currentTable = 1;
            } else if (currentTable == 1 &&
                _table1UserNames.isEmpty &&
                _table2UserNames.isNotEmpty) {
              currentTable = 2;
            }
            shouldAskBelowEightDecision =
                previousPlayerCount >= 8 && playerCount < 8;
          }
        });

        if (removedUserIds.isNotEmpty) {
          Future.microtask(
            () => _activeTablesRepo
                .releasePlayersFromActiveTables(removedUserIds.toList()),
          );
        }

        if (shouldAskBelowEightDecision) {
          Future.microtask(_showBelowEightSplitDecisionDialog);
        }
      },
    );
  }

  Future<void> _addPlayerFromAppBar() async {
    if (playerCount >= 14) return;

    final selectedToAdd = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: _orderedUserNames,
        ),
      ),
    );

    if (selectedToAdd == null || selectedToAdd.isEmpty) return;

    setState(() {
      final addedNow = <String>[];
      for (final userId in selectedToAdd) {
        if (_orderedUserNames.length >= 14) break;
        if (_orderedUserNames.contains(userId)) continue;
        _orderedUserNames.add(userId);
        addedNow.add(userId);
      }
      if (addedNow.isNotEmpty) {
        _sessionAddedPlayers += addedNow.length;
        _registerSessionUsers(addedNow);
      }
      _refreshDisplayNamesFromProfiles();
      playerCount = _orderedUserNames.length;
      if (playerCount > 7) {
        _tableSplitSelected = false;
      }
      _disposeDetachedScoreInputs();
    });
    _loadUserProfilesByIds(selectedToAdd);
  }

  Future<void> _showTableSettingsDialog() async {
    final scoreController = TextEditingController(text: _scoreLimit.toString());
    final betController = TextEditingController(text: _betAmount.toString());
    final boltScoreController =
        TextEditingController(text: _boltScoreLimit.toString());
    final boltBetController =
        TextEditingController(text: _boltBetAmount.toString());

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Тоглох ширээний тохиргоо'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Энгийн тоглолт',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: scoreController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Онооны хязгаар',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: betController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Бооцооны дүн',
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Боолт тоглолт',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: boltScoreController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Боолт үеийн онооны хязгаар',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: boltBetController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Боолт үеийн бооцооны дүн',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Болих'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  final nextScore = int.tryParse(scoreController.text);
                  final nextBet = int.tryParse(betController.text);
                  final nextBoltScore = int.tryParse(boltScoreController.text);
                  final nextBoltBet = int.tryParse(boltBetController.text);

                  if (nextScore != null && nextScore > 0) {
                    _scoreLimit = nextScore;
                  }
                  if (nextBet != null && nextBet > 0) {
                    _betAmount = nextBet;
                  }
                  if (nextBoltScore != null && nextBoltScore > 0) {
                    _boltScoreLimit = nextBoltScore;
                  }
                  if (nextBoltBet != null && nextBoltBet > 0) {
                    _boltBetAmount = nextBoltBet;
                  }
                });
                Navigator.of(context).pop();
              },
              child: const Text('Хадгалах'),
            ),
          ],
        );
      },
    );

    scoreController.dispose();
    betController.dispose();
    boltScoreController.dispose();
    boltBetController.dispose();
  }

  Future<void> _openNewActiveTableSelection() async {
    await _persistCurrentActiveTableState();
    if (!mounted) return;

    final lockedUserIds =
        await _activeTablesRepo.watchActivePlayerUserIds().first;
    if (!mounted) return;

    final selected = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: lockedUserIds.toList(),
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
        ),
      ),
    );

    if (!mounted || selected == null || selected.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayingFormatPage(
          selectedUserIds: selected,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
        ),
      ),
    );
  }

  Future<void> _jumpToActiveTable(ActiveTableSummary table) async {
    try {
      final routeName = 'active-table:${table.id}';
      final currentRouteName = ModalRoute.of(context)?.settings.name;
      if (currentRouteName == routeName) return;

      await _persistCurrentActiveTableState();
      if (!mounted) return;

      if (!ActiveTableRouteRegistry.contains(routeName)) {
        await _reopenActiveTableRoute(table.id);
        return;
      }

      Navigator.of(context)
          .popUntil((route) => route.settings.name == routeName);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ширээ солих үед алдаа гарлаа. Дахин оролдоно уу.'),
        ),
      );
    }
  }

  Future<void> _persistCurrentActiveTableState() async {
    final currentRouteName = ModalRoute.of(context)?.settings.name;
    if (currentRouteName == null ||
        !currentRouteName.startsWith('active-table:')) {
      return;
    }

    final lockId = currentRouteName.substring('active-table:'.length).trim();
    if (lockId.isEmpty) return;

    try {
      await _saveProgress();
    } catch (_) {
      // Local save failure should not block table switching.
    }
    if (!mounted) return;

    final orderedIds = _orderedUserNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    try {
      await _activeTablesRepo
          .updateActiveTableState(
            lockId,
            savedSessionId: _activeSavedSessionId,
            playerUserIds: orderedIds.isEmpty ? null : orderedIds,
          )
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Remote sync failures are tolerated; local session is already persisted.
    }
  }

  Future<bool> _reopenActiveTableRoute(String lockId) async {
    final details = await _activeTablesRepo.fetchActiveTableDetails(lockId);
    if (!mounted || details == null || details.status != 'active') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Энэ ширээ идэвхгүй болсон байна.')),
      );
      return false;
    }

    String? resolvedSavedSessionId = details.savedSessionId;
    if (resolvedSavedSessionId == null || resolvedSavedSessionId.isEmpty) {
      final latest = await _savedSessionsRepo.findLatestByGameAndPlayers(
        gameKey: details.gameKey,
        selectedUserIds: details.playerUserIds,
      );
      resolvedSavedSessionId = latest?.id;
      if (resolvedSavedSessionId != null && resolvedSavedSessionId.isNotEmpty) {
        // Best-effort backfill so next reopen can use the lock directly.
        _activeTablesRepo.updateSavedSessionId(
          lockId,
          resolvedSavedSessionId,
        );
      }
    }

    final page = _buildPageForActiveTable(
      details,
      initialSavedSessionId: resolvedSavedSessionId,
    );
    if (page == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Энэ ширээний тоглоомыг дахин нээх боломжгүй байна.'),
        ),
      );
      return false;
    }

    final routeName = 'active-table:${details.id}';
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: routeName),
        builder: (_) => ActiveTableRouteScope(
          routeName: routeName,
          child: page,
        ),
      ),
    );
    return true;
  }

  Widget? _buildPageForActiveTable(
    ActiveTableDetails details, {
    String? initialSavedSessionId,
  }) {
    final ids = List<String>.from(details.playerUserIds);
    final isMulti = details.playingFormat == 'multi';
    final restoredSessionId = initialSavedSessionId ?? details.savedSessionId;

    switch (details.gameKey) {
      case '13_card_poker':
        return ThirteenCardPokerScreen(
          gameType: '13 МОДНЫ ПОКЕР',
          selectedUserIds: ids,
          currentRegistrarUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
          promptInitialPlayerOrder: false,
        );
      case 'card_texas':
        return CardTexasPage(
          selectedUserIds: ids,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'muushig':
        return MuushigPage(
          selectedUserIds: ids,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'buur':
        return BuurPage(
          selectedUserIds: ids,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'game108':
        return Game108Page(
          selectedUserIds: ids,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'xodrox':
        return HodrokhPage(
          selectedUserIds: ids,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'nvx_shaxax':
        return NyxShaxaxPage(
          selectedUserIds: ids,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'durak':
        return DurakPage(
          selectedUserIds: ids,
          playingFormat: details.playingFormat,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'game501':
        return Game501Page(
          selectedUserIds: ids,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
          autoReturnOnWinner: isMulti,
          multiWinsByUserId: isMulti ? const <String, int>{} : null,
        );
      case 'canasta':
        return CanastaPage(
          selectedUserIds: ids,
          playingFormat: details.playingFormat,
          currentUserId: widget.currentRegistrarUserId,
          canManageGames: widget.canManageGames,
          initialSavedSessionId: restoredSessionId,
        );
      default:
        return null;
    }
  }

  BoxDecoration _inlineActiveTableDecoration(
    ActiveTableSummary table,
    bool isCurrent,
  ) {
    final border = Border.all(
      color: isCurrent ? const Color(0xFF111111) : Colors.white,
      width: isCurrent ? 3 : 1.5,
    );

    switch (table.playingFormat) {
      case 'multi':
        return BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFE53935),
              Color(0xFFFB8C00),
              Color(0xFFFDD835),
              Color(0xFF43A047),
              Color(0xFF1E88E5),
              Color(0xFF8E24AA),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        );
      case 'crazy':
        return BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFFFFC107),
              Color(0xFFFF7043),
              Color(0xFFE65100),
            ],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33FF7043),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        );
      default:
        return BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          color: const Color(0xFF1E88E5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        );
    }
  }

  Widget _buildInlineActiveTableControls() {
    return StreamBuilder<List<ActiveTableSummary>>(
      stream: _activeTablesRepo.watchActiveTableSummaries(),
      builder: (context, snapshot) {
        final tables = snapshot.data ?? const <ActiveTableSummary>[];
        final currentRouteName = ModalRoute.of(context)?.settings.name;
        return Row(
          children: [
            for (final table in tables)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: 'Ширээ ${table.tableNumber}: ${table.gameName}',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _jumpToActiveTable(table),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: _inlineActiveTableDecoration(
                        table,
                        currentRouteName == 'active-table:${table.id}',
                      ),
                      child: Text(
                        '${table.tableNumber}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Tooltip(
              message: 'Ширээ нэмэх',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openNewActiveTableSelection,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00A86B),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Color tableBgColor =
        currentTable == 1 ? Colors.blue[300]! : Colors.green[100]!;
    final hasFirestoreBackedSelection = widget.selectedUserIds.isNotEmpty;
    final profilesReadyForOrderedUsers = !hasFirestoreBackedSelection ||
        _areProfilesLoadedFor(_orderedUserNames);

    // Show player order dialog only once at game start, and only for 3-7 players
    // Skip showing dialog if restoring from a saved session
    final isRestoringFromSavedSession = widget.initialSavedSessionId != null &&
        widget.initialSavedSessionId!.isNotEmpty;
    if (widget.promptInitialPlayerOrder &&
        !_playerOrderSelected &&
        !isRestoringFromSavedSession &&
        profilesReadyForOrderedUsers &&
        _orderedDisplayNames.length >= 3 &&
        _orderedDisplayNames.length <= 7 &&
        ModalRoute.of(context)?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showPlayerOrderDialog(
          _orderedUserNames,
          List.from(_orderedDisplayNames),
          (orderedIndices) {
            setState(() {
              final previousUsers = List<String>.from(_orderedUserNames);
              final selectedOrderUsers =
                  orderedIndices.map((i) => previousUsers[i]).toList();
              _playerOrderSelected = true;
              _orderedUserNames =
                  _arrangePlayersForBoardLayout(selectedOrderUsers);
              _refreshDisplayNamesFromProfiles();
              playerCount = _orderedDisplayNames.length;
              // TODO: Replace with real poker game logic
              // _pokerGame = ThirteenCardPokerGame(...);
            });
          },
        );
      });
    }

    if (!_tableSplitSelected &&
        profilesReadyForOrderedUsers &&
        _orderedDisplayNames.length > 7 &&
        ModalRoute.of(context)?.isCurrent == true) {
      final requiredForTable1 =
          _requiredTable1Count(_orderedDisplayNames.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showTableSplitDialog(
          _orderedUserNames.map(_usernameForUserId).toList(),
          List<String>.from(_orderedDisplayNames),
          requiredForTable1,
          (table1Indices) {
            _applySplitAndPromptTableOrders(table1Indices);
          },
        );
      });
    }

    if (widget.gameType == '13 МОДНЫ ПОКЕР') {
      _maintainEighthScoreFocus();
    } else {
      _maintainActiveScoreFocus();
    }

    return Scaffold(
      backgroundColor: tableBgColor,
      appBar: UnifiedGameAppBar(
        showGlobalTableBar: true,
        currentUserId: widget.currentRegistrarUserId,
        canManageGames: widget.canManageGames,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                widget.gameType,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_tableSplitSelected && _table2UserNames.isNotEmpty) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      currentTable = 1;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        currentTable == 1 ? Colors.blue : Colors.grey[300],
                    foregroundColor:
                        currentTable == 1 ? Colors.white : Colors.black,
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('T1'),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      currentTable = 2;
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        currentTable == 2 ? Colors.blue : Colors.grey[300],
                    foregroundColor:
                        currentTable == 2 ? Colors.white : Colors.black,
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('T2'),
                ),
              ],
              if (!widget.autoReturnOnWinner) ...[
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      _roundInfoLabel,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
              if (_isBoltMode) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'БООЛТ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
              if (_currentRegistrarUserId != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'Бүртгэл хөтлөгч: ${_displayNameForUserId(_currentRegistrarUserId!, 0)}',
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/buttons/keyboard.png',
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _displayNameForUserId(_currentRegistrarUserId!, 0),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        onBack: () {
          _handleBackFromGameAppBar();
        },
        onRemovePlayer: _orderedUserNames.length > 2
            ? _showRemovePlayerDialogFromAppBar
            : null,
        onAddPlayer: playerCount < 14 ? _addPlayerFromAppBar : null,
        onSave: _saveProgress,
        onStatistics: _openStatisticsDashboard,
        onReport: _showSessionSummaryDialog,
        onPrint: _printSessionReport,
        onSettings: _showTableSettingsDialog,
        onExit: _showExitDecisionDialog,
        preferCustomExitAction: true,
        extraActions: [
          IconButton(
            icon: Opacity(
              opacity: _canTransferRegistrarPermission ? 1 : 0.45,
              child: Image.asset(
                'assets/buttons/keyboard.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
              ),
            ),
            onPressed: _canTransferRegistrarPermission
                ? _showTransferRegistrarDialog
                : null,
            tooltip: _canTransferRegistrarPermission
                ? 'Бүртгэл хөтлөгчийн эрхийг нэг тоглогч руу шилжүүлэх'
                : 'Бүртгэл хөтлөгчийн эрх шилжүүлэх боломжгүй',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: buildGameTableUI(tableBgColor),
      ),
    );
  }

  Widget buildGameTableUI(Color tableBgColor) {
    switch (widget.gameType) {
      case '13 МОДНЫ ПОКЕР':
        const int totalSlots = 8;
        const int columns = 4;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileAspectRatio = (constraints.maxWidth / columns) /
                      (constraints.maxHeight / 2);
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: totalSlots,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: tileAspectRatio,
                    ),
                    itemBuilder: (context, index) {
                      if (index == 7) {
                        return _buildEighthScoreBlock(tableBgColor);
                      }

                      if (index < _activeDisplayNames.length && index < 7) {
                        return buildPlayerBlock(index, tableBgColor);
                      }

                      return Card(
                        color: tableBgColor.withOpacity(0.3),
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(
                            color: Colors.white,
                            width: 8,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person_outline,
                            size: 48,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      case 'Дурак':
        return _buildDurakTableUI();
      default:
        return Center(
            child: Text('Тоглоомын төрөл сонгоогүй байна',
                style: const TextStyle(fontSize: 18)));
    }
  }

  void _syncDurakBlocksWithPlayers(List<String> players) {
    final knownPlayers = players.toSet();

    for (int i = _durakBlocks.length - 1; i >= 0; i--) {
      _durakBlocks[i].removeWhere((userId) => !knownPlayers.contains(userId));
      if (_durakBlocks[i].isEmpty) {
        _durakBlocks.removeAt(i);
      }
    }

    final assigned = _durakBlocks.expand((block) => block).toSet();
    for (final userId in players) {
      if (!assigned.contains(userId)) {
        _durakBlocks.add([userId]);
      }
    }
  }

  int _durakBlockWins(List<String> blockUserIds) {
    int total = 0;
    for (final userId in blockUserIds) {
      total += _winsForUserId(userId);
    }
    return total;
  }

  Widget _buildDurakMemberChip(String userId, {bool compact = false}) {
    final photoUrl = _photoUrlForUserId(userId);
    final displayName = _displayNameForUserId(userId, 0);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          CircleAvatar(
            radius: compact ? 10 : 12,
            backgroundColor: Colors.blueGrey.shade700,
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                ? NetworkImage(photoUrl)
                : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? Icon(
                    Icons.person,
                    size: compact ? 12 : 14,
                    color: Colors.white,
                  )
                : null,
          ),
          SizedBox(width: compact ? 4 : 6),
          Expanded(
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 11.5 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurakBlock(int blockIndex) {
    final blockUserIds = _durakBlocks[blockIndex];
    final blockWins = _durakBlockWins(blockUserIds);

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != blockIndex,
      onAcceptWithDetails: (details) {
        final sourceIndex = details.data;
        if (sourceIndex == blockIndex) return;
        if (sourceIndex < 0 || sourceIndex >= _durakBlocks.length) return;

        setState(() {
          final moving = List<String>.from(_durakBlocks[sourceIndex]);
          _durakBlocks[blockIndex].addAll(moving);
          _durakBlocks[blockIndex] = _durakBlocks[blockIndex].toSet().toList();

          if (sourceIndex > blockIndex) {
            _durakBlocks.removeAt(sourceIndex);
          } else {
            _durakBlocks.removeAt(sourceIndex);
          }
        });
      },
      builder: (context, candidateData, rejectedData) {
        final isActiveTarget = candidateData.isNotEmpty;

        return LongPressDraggable<int>(
          data: blockIndex,
          feedback: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: _durakBlockCard(
                blockUserIds: blockUserIds,
                blockWins: blockWins,
                highlight: true,
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _durakBlockCard(
              blockUserIds: blockUserIds,
              blockWins: blockWins,
              highlight: false,
            ),
          ),
          child: _durakBlockCard(
            blockUserIds: blockUserIds,
            blockWins: blockWins,
            highlight: isActiveTarget,
          ),
        );
      },
    );
  }

  Widget _durakBlockCard({
    required List<String> blockUserIds,
    required int blockWins,
    required bool highlight,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF152029),
        border: Border.all(
          color: highlight ? Colors.orangeAccent : Colors.deepOrangeAccent,
          width: highlight ? 3 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = blockUserIds.length >= 4;

              if (blockUserIds.length <= 4) {
                return Row(
                  children: [
                    for (int i = 0; i < blockUserIds.length; i++) ...[
                      Expanded(
                        child: _buildDurakMemberChip(
                          blockUserIds[i],
                          compact: isCompact,
                        ),
                      ),
                      if (i != blockUserIds.length - 1)
                        const SizedBox(width: 8),
                    ],
                  ],
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < blockUserIds.length; i++) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 110),
                        child: _buildDurakMemberChip(
                          blockUserIds[i],
                          compact: true,
                        ),
                      ),
                      if (i != blockUserIds.length - 1)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          Wrap(
            spacing: 4,
            children: List<Widget>.generate(
              _durakWinThreshold,
              (index) {
                final filled = index < blockWins;
                return GestureDetector(
                  onTap: filled
                      ? null
                      : () {
                          if (blockUserIds.isEmpty) return;
                          final winnerUserId = blockUserIds.first;
                          setState(() {
                            _winsByUserId[winnerUserId] =
                                _winsForUserId(winnerUserId) + 1;
                          });
                        },
                  child: Icon(
                    Icons.star,
                    size: 18,
                    color: filled ? Colors.amber : Colors.white30,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurakTableUI() {
    final players = List<String>.from(_activeUserNames);
    _syncDurakBlocksWithPlayers(players);

    if (_durakBlocks.isEmpty) {
      return const Center(
        child: Text('Тоглогч байхгүй байна', style: TextStyle(fontSize: 18)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < _durakBlocks.length; i++) ...[
                Expanded(child: _buildDurakBlock(i)),
                if (i != _durakBlocks.length - 1) const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget buildPlayerBlock(int index, Color tableBgColor) {
    final userIdForBlock = (index >= 0 && _activeUserNames.length > index)
        ? _activeUserNames[index]
        : null;
    final isTournamentSlotMode = widget.gameType == '13 МОДНЫ ПОКЕР' &&
        !_tableSplitSelected &&
        _activeUserNames.length >= 5 &&
        _activeUserNames.length <= 7;
    final isFixedYellowZoneSlot =
        isTournamentSlotMode && index >= 4 && index < _activeUserNames.length;

    final isEliminatedForBorder =
        userIdForBlock != null && _isEliminatedByScore(userIdForBlock);
    final isBenchedForBorder = userIdForBlock != null &&
        (isFixedYellowZoneSlot ||
            (!isTournamentSlotMode &&
                _isBenchedForCurrentTable(userIdForBlock)));
    final borderColor = isEliminatedForBorder
        ? Colors.red
        : (isBenchedForBorder ? Colors.yellow : Colors.green);
    final badgeBgColor = isEliminatedForBorder
        ? Colors.red
        : (isBenchedForBorder ? Colors.yellow.shade700 : Colors.green.shade700);
    final badgeFgColor = isEliminatedForBorder
        ? Colors.white
        : (isBenchedForBorder ? Colors.black87 : Colors.white);

    return Card(
      color: tableBgColor,
      margin: EdgeInsets.zero,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: 8),
      ),
      child: LayoutBuilder(
        builder: (context, cardConstraints) {
          final userId = (index >= 0 && _activeUserNames.length > index)
              ? _activeUserNames[index]
              : null;
          final photoUrl = userId == null ? null : _photoUrlForUserId(userId);
          final isEliminated = userId != null && _isEliminatedByScore(userId);
          final isBenched = userId != null &&
              (isFixedYellowZoneSlot ||
                  (!isTournamentSlotMode && _isBenchedForCurrentTable(userId)));
          final scoreValueColor = isEliminated
              ? Colors.red
              : (isBenched ? Colors.amber.shade700 : Colors.black87);

          final compact = cardConstraints.maxHeight < 320;
          final badgeRadius = compact ? 15.0 : 18.0;
          final cellGap = compact ? 6.0 : 8.0;
          final labelFont = compact ? 10.5 : 12.5;
          final scoreFont = compact ? 28.0 : 36.0;
          final moneyFont = compact ? 30.0 : 40.0;
          final nameFont = compact ? 12.0 : 14.0;
          final displayNameFont = compact ? 15.0 : 17.0;
          final starFont = compact ? 15.0 : 17.0;

          final roundScoreText = userId == null ? '-' : _roundScoreText(userId);
          final totalScoreText = userId == null ? '-' : _totalScoreText(userId);
          final amount =
              userIdForBlock == null ? 0 : _moneyForUserId(userIdForBlock);
          final winsCount =
              userIdForBlock == null ? 0 : _winsForUserId(userIdForBlock);
          final userName = (index >= 0 && _activeUserNames.length > index)
              ? _usernameForUserId(_activeUserNames[index])
              : '';
          final displayName = (index >= 0 &&
                  _activeDisplayNames.isNotEmpty &&
                  _activeDisplayNames.length > index)
              ? _activeDisplayNames[index]
              : ((index >= 0 && displayNames.length > index)
                  ? displayNames[index]
                  : '');

          Widget cellContainer(Widget child) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: child,
            );
          }

          Widget scoreCell({
            required String label,
            required String value,
            required bool highlight,
            required Color valueColor,
          }) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent, width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: labelFont,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            value,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: highlight ? scoreFont + 4 : scoreFont,
                              color: valueColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(10.0),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: cellContainer(
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: (photoUrl != null &&
                                            photoUrl.isNotEmpty)
                                        ? Image.network(
                                            photoUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Center(
                                              child: Icon(
                                                Icons.person,
                                                size: compact ? 44 : 56,
                                                color: Colors.blue[700],
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Icon(
                                              Icons.person,
                                              size: compact ? 44 : 56,
                                              color: Colors.blue[700],
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              SizedBox(width: cellGap),
                              Expanded(
                                child: cellContainer(
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          userName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: nameFont,
                                            color: Colors.blueGrey.shade900,
                                          ),
                                        ),
                                        Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: displayNameFont,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.star,
                                              size: compact ? 18 : 20,
                                              color: Colors.amber,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              winsCount.toString(),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: starFont,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              '${amount.abs()}₮',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: moneyFont,
                                                height: 0.95,
                                                color: _moneyColorForAmount(
                                                    amount),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: cellGap),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: scoreCell(
                                  label: 'Оноо',
                                  value: roundScoreText,
                                  highlight: false,
                                  valueColor: scoreValueColor,
                                ),
                              ),
                              SizedBox(width: cellGap),
                              Expanded(
                                child: scoreCell(
                                  label: 'Нийт',
                                  value: totalScoreText,
                                  highlight: true,
                                  valueColor: scoreValueColor,
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
                  top: compact ? 2 : 4,
                  left: compact ? 2 : 4,
                  child: CircleAvatar(
                    backgroundColor: badgeBgColor,
                    foregroundColor: badgeFgColor,
                    radius: badgeRadius,
                    child: Text(
                      '${_dynamicBadgeNumberForUser(userIdForBlock, index)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 16 : 18,
                      ),
                    ),
                  ),
                ),
                if (widget.multiWinsByUserId != null)
                  Positioned(
                    top: compact ? 4 : 8,
                    right: compact ? 2 : 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: Colors.amber,
                            size: 14,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${widget.multiWinsByUserId?[userIdForBlock ?? ''] ?? 0}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  int _dynamicBadgeNumberForUser(String? userId, int fallbackIndex) {
    if (userId == null) return fallbackIndex + 1;

    final List<String> candidates = _activeUserNames.take(7).toList();
    if (candidates.isEmpty) return fallbackIndex + 1;

    final benched = _currentBenchedUsersForTable(candidates);
    final active = _activePlayersByBenchForTable(candidates);
    final eliminated =
        candidates.where((id) => _isEliminatedByScore(id)).toList();

    if (_isEliminatedByScore(userId)) {
      final rank = _uRankings[userId];
      if (rank != null) return rank;
      final fallbackRank = eliminated.indexOf(userId);
      return fallbackRank >= 0 ? fallbackRank + 1 : fallbackIndex + 1;
    }

    if (benched.contains(userId)) {
      return benched.indexOf(userId) + 1;
    }

    if (active.contains(userId)) {
      return active.indexOf(userId) + 1;
    }

    return fallbackIndex + 1;
  }

  Widget _buildEighthScoreBlock(Color tableBgColor) {
    return Card(
      color: tableBgColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.white, width: 8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildEighthScoreCell(0)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildEighthScoreCell(1)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildEighthScoreCell(2)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildEighthScoreCell(3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEighthScoreCell(int index) {
    final activeCells = _activeEighthCellCount;
    final isEnabled = index < activeCells;

    if (!isEnabled && _eighthBlockScoreControllers[index].text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _eighthBlockScoreControllers[index].clear();
      });
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isEnabled
            ? Colors.white.withOpacity(0.4)
            : Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEnabled ? Colors.blueAccent : Colors.blueGrey,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isEnabled ? Colors.blueGrey : Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Center(
              child: TextField(
                controller: _eighthBlockScoreControllers[index],
                focusNode: _eighthBlockFocusNodes[index],
                enabled: isEnabled,
                readOnly: !isEnabled,
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.-]')),
                ],
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 34,
                  color: isEnabled ? Colors.black87 : Colors.grey,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '-',
                ),
                onSubmitted: (_) {
                  _submitEighthCellFromKeyboard(index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFifthColumn(Color tableBgColor) {
    const int startIndex = 4;
    final activeCount = _activeDisplayNames.length;
    return Column(
      children: [
        for (int slot = 0; slot < 3; slot++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: slot < 2 ? 8 : 0),
              child: (startIndex + slot < activeCount)
                  ? _buildSubstituteBlock(
                      startIndex + slot,
                      tableBgColor,
                      substitutionNumber: slot + 1,
                    )
                  : Card(
                      color: tableBgColor.withOpacity(0.3),
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Colors.white24, width: 4),
                      ),
                      child: const Center(
                        child: Icon(Icons.person_outline,
                            size: 32, color: Colors.grey),
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildSubstituteBlock(int index, Color tableBgColor,
      {int substitutionNumber = 1}) {
    final userId = (index >= 0 && _activeUserNames.length > index)
        ? _activeUserNames[index]
        : null;
    final isEliminated = userId != null && _isEliminatedByScore(userId);
    return Card(
      color: tableBgColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isEliminated ? Colors.red : Colors.yellow,
          width: 8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                foregroundColor: Colors.yellow[900],
                radius: 16,
                child: Text('С$substitutionNumber',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 36.0, top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (index >= 0 && _activeUserNames.length > index)
                        ? _usernameForUserId(_activeUserNames[index])
                        : '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  Text(
                    (index >= 0 &&
                            _activeDisplayNames.isNotEmpty &&
                            _activeDisplayNames.length > index)
                        ? _activeDisplayNames[index]
                        : ((index >= 0 && displayNames.length > index)
                            ? displayNames[index]
                            : ''),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 2),
                            child: Text('Нийт',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.blueAccent, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              userId == null ? '-' : _totalScoreText(userId),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Хожил:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 15)),
                              SizedBox(width: 6),
                              Icon(Icons.star, color: Colors.amber, size: 22),
                              SizedBox(width: 4),
                              Text(
                                userId == null
                                    ? '0'
                                    : _winsForUserId(userId).toString(),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('₮',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              SizedBox(width: 4),
                              Builder(builder: (context) {
                                final amount = userId == null
                                    ? 0
                                    : _moneyForUserId(userId);
                                return Text(
                                  amount.abs().toString(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: _moneyColorForAmount(amount),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showPlayerOrderDialog(
      List<String> playerUserIds,
      List<String> playerDisplayNames,
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
            final cardWidth =
                (maxDialogWidth - cardSpacing * (7 - 1)) / 7; // fixed size
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
                                                  _photoUrlForUserId(
                                                      playerUserIds[i]);
                                              if (photoUrl != null &&
                                                  photoUrl.isNotEmpty) {
                                                return Image.network(
                                                  photoUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
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
                                                _usernameForUserId(
                                                    playerUserIds[i]),
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

  Future<void> showTableSplitDialog(
      List<String> playerUserNames,
      List<String> playerDisplayNames,
      int requiredForTable1,
      void Function(List<int>) onSplitConfirmed) async {
    final Set<int> selectedForTable1 = {};
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('2 ширээнд хуваарилах'),
              content: SizedBox(
                width: 780,
                height: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ширээ №1-д $requiredForTable1 тоглогч сонгоно уу (${selectedForTable1.length}/$requiredForTable1)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: playerUserNames.length,
                        itemBuilder: (context, index) {
                          final isSelected = selectedForTable1.contains(index);
                          final canSelect = isSelected ||
                              selectedForTable1.length < requiredForTable1;
                          return GestureDetector(
                            onTap: canSelect
                                ? () {
                                    setState(() {
                                      if (isSelected) {
                                        selectedForTable1.remove(index);
                                      } else {
                                        selectedForTable1.add(index);
                                      }
                                    });
                                  }
                                : null,
                            child: Opacity(
                              opacity: canSelect ? 1.0 : 0.45,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      border: isSelected
                                          ? Border.all(
                                              color: Colors.deepPurple,
                                              width: 3,
                                            )
                                          : null,
                                      borderRadius: BorderRadius.circular(200),
                                    ),
                                    child: CircleAvatar(
                                      radius: 80,
                                      backgroundColor: Colors.deepPurple[100],
                                      child: const Icon(Icons.person,
                                          size: 48, color: Colors.deepPurple),
                                    ),
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      top: 0,
                                      right: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.deepPurple,
                                          borderRadius:
                                              BorderRadius.circular(50),
                                        ),
                                        padding: const EdgeInsets.all(6),
                                        child: const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          playerDisplayNames[index],
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '@${playerUserNames[index]}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (!mounted) return;
                    Navigator.of(this.context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const PlayerSelectionPage(),
                      ),
                      (route) => false,
                    );
                  },
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: selectedForTable1.length == requiredForTable1
                      ? () {
                          final picked = selectedForTable1.toList()..sort();
                          Navigator.of(context).pop();
                          Future.microtask(() => onSplitConfirmed(picked));
                        }
                      : null,
                  child: const Text('Ширээнд хуваарилах'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> showPlayerRemoveDialog(
      List<String> players,
      List<String> playerDisplayNames,
      int maxRemovable,
      void Function(List<int>) onRemove) async {
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
                                            child: Builder(
                                              builder: (context) {
                                                final photoUrl =
                                                    _photoUrlForUserId(
                                                        players[i]);
                                                if (photoUrl != null &&
                                                    photoUrl.isNotEmpty) {
                                                  return Image.network(
                                                    photoUrl,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
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
                                                  i < playerDisplayNames.length
                                                      ? playerDisplayNames[i]
                                                      : 'Тоглогч ${i + 1}',
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
                                                  _usernameForUserId(
                                                      players[i]),
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
  // END OF CLASS METHODS
}
