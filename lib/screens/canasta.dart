import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:toocoob/utils/game_registrar_transfer.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';
import 'package:toocoob/screens/kinds_of_game.dart';
import 'package:toocoob/screens/player_selection_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry widget
// ─────────────────────────────────────────────────────────────────────────────
enum _CanastaBetMode { perTeam, perMember }

class CanastaPage extends StatefulWidget {
  const CanastaPage({
    super.key,
    this.selectedUserIds = const [],
    this.playingFormat = 'single',
    this.currentUserId,
    this.canManageGames = false,
    this.initialSavedSessionId,
  });

  final List<String> selectedUserIds;
  final String playingFormat;
  final String? currentUserId;
  final bool canManageGames;
  final String? initialSavedSessionId;

  @override
  State<CanastaPage> createState() => _CanastaPageState();
}

class _CanastaPageState extends State<CanastaPage> {
  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();
  final Map<String, _PlayerProfile> _profiles = {};
  bool _loading = true;

  List<String> _team1Ids = [];
  List<String> _team2Ids = [];
  bool _teamsAssigned = false;

  final List<_TeamScore> _scores = [_TeamScore(), _TeamScore()];

  int _targetScore = 2500;
  int _betAmount = 5000;
  _CanastaBetMode _betMode = _CanastaBetMode.perTeam;
  int _roundNumber = 1;
  bool _checkingWin = false;
  final List<int> _teamWins = [0, 0];
  final List<int> _teamMoney = [0, 0];
  final Map<String, int> _playerMoney = {};
  String? _activeSavedSessionId;
  String? _currentRegistrarUserId;
  bool _restoredSessionState = false;
  bool _sessionAddedToStatistics = false;

  bool get _canTransferRegistrar =>
      widget.canManageGames &&
      widget.currentUserId != null &&
      _currentRegistrarUserId == widget.currentUserId;

  @override
  void initState() {
    super.initState();
    _currentRegistrarUserId = widget.currentUserId;
    _initializePage();
  }

  Future<void> _initializePage() async {
    await _tryRestoreSavedSession();
    await _loadProfiles();
  }

  Future<void> _tryRestoreSavedSession() async {
    final id = widget.initialSavedSessionId;
    if (id == null || id.isEmpty) return;
    final saved = await _savedSessionsRepo.findById(id);
    if (saved == null) return;
    if (!mounted) return;
    setState(() {
      _activeSavedSessionId = saved.id;
      _restoredSessionState = _restoreFromPayload(saved.payload);
    });
  }

  Future<void> _loadProfiles() async {
    final ids = widget.selectedUserIds.toSet();
    final updated = <String, _PlayerProfile>{};
    for (final uid in ids) {
      if (uid.isEmpty) continue;
      try {
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = snap.data();
        if (data == null) continue;
        final displayName = (data['displayName'] ?? '').toString().trim();
        final username = (data['username'] ?? '').toString().trim();
        final photoUrl = (data['photoUrl'] ?? '').toString().trim();
        updated[uid] = _PlayerProfile(
          userId: uid,
          displayName: displayName.isNotEmpty
              ? displayName
              : (username.isNotEmpty ? username : uid),
          username: username,
          photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
        );
      } catch (_) {
        updated[uid] = _PlayerProfile(userId: uid, displayName: uid);
      }
    }
    if (!mounted) return;
    setState(() {
      _profiles.addAll(updated);
      _loading = false;
    });
    if (widget.selectedUserIds.length >= 2 && !_teamsAssigned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTeamSplitDialog();
      });
    }
  }

  Map<String, dynamic> _buildSessionPayload() {
    Map<String, dynamic> scoreToJson(_TeamScore s) => {
          'openedState': s.openedState.index,
          'cleanCanastas': s.cleanCanastas,
          'dirtyCanastas': s.dirtyCanastas,
          'dranksCount': s.dranksCount,
          'cardsInHand': s.cardsInHand
              .map((c) => {'count': c.count, 'multiplier': c.multiplier})
              .toList(),
          'closed': s.closed,
        };

    return {
      'version': 1,
      'team1Ids': List<String>.from(_team1Ids),
      'team2Ids': List<String>.from(_team2Ids),
      'teamsAssigned': _teamsAssigned,
      'scores': _scores.map(scoreToJson).toList(),
      'targetScore': _targetScore,
      'betAmount': _betAmount,
      'betMode': _betMode.index,
      'roundNumber': _roundNumber,
      'teamWins': List<int>.from(_teamWins),
      'teamMoney': List<int>.from(_teamMoney),
      'playerMoney': Map<String, int>.from(_playerMoney),
      'currentRegistrarUserId': _currentRegistrarUserId,
    };
  }

  bool _restoreFromPayload(Map<String, dynamic> payload) {
    try {
      final team1 = (payload['team1Ids'] as List? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList();
      final team2 = (payload['team2Ids'] as List? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList();
      final teamsAssigned = payload['teamsAssigned'] == true;
      final scoresRaw = (payload['scores'] as List? ?? const <dynamic>[]);

      if (scoresRaw.length < 2) return false;
      for (int i = 0; i < 2; i++) {
        final raw = Map<String, dynamic>.from(scoresRaw[i] as Map);
        final s = _scores[i];
        final openedStateIndex = (raw['openedState'] as num? ?? 0).toInt();
        s.openedState = _OpenedState
            .values[openedStateIndex.clamp(0, _OpenedState.values.length - 1)];
        s.cleanCanastas = (raw['cleanCanastas'] as num? ?? 0).toInt();
        s.dirtyCanastas = (raw['dirtyCanastas'] as num? ?? 0).toInt();
        s.dranksCount = (raw['dranksCount'] as num? ?? 0).toInt();
        s.closed = raw['closed'] == true;

        final cardsRaw =
            (raw['cardsInHand'] as List? ?? const <dynamic>[]).take(5).toList();
        for (int k = 0; k < s.cardsInHand.length; k++) {
          if (k < cardsRaw.length) {
            final cRaw = Map<String, dynamic>.from(cardsRaw[k] as Map);
            s.cardsInHand[k].count = (cRaw['count'] as num? ?? 0).toInt();
            s.cardsInHand[k].multiplier =
                (cRaw['multiplier'] as num? ?? s.cardsInHand[k].multiplier)
                    .toDouble();
          } else {
            s.cardsInHand[k].count = 0;
          }
        }
      }

      final wins = (payload['teamWins'] as List? ?? const <dynamic>[])
          .map((e) => (e as num).toInt())
          .toList();
      final money = (payload['teamMoney'] as List? ?? const <dynamic>[])
          .map((e) => (e as num).toInt())
          .toList();

      _team1Ids = team1;
      _team2Ids = team2;
      _teamsAssigned = teamsAssigned;
      _targetScore = (payload['targetScore'] as num? ?? 2500).toInt();
      _betAmount = (payload['betAmount'] as num? ?? 5000).toInt();
      _betMode = _CanastaBetMode
          .values[((payload['betMode'] as num? ?? 0).toInt().clamp(0, 1))];
      _roundNumber = (payload['roundNumber'] as num? ?? 1).toInt();
      _teamWins[0] = wins.isNotEmpty ? wins[0] : 0;
      _teamWins[1] = wins.length > 1 ? wins[1] : 0;
      _teamMoney[0] = money.isNotEmpty ? money[0] : 0;
      _teamMoney[1] = money.length > 1 ? money[1] : 0;
      _currentRegistrarUserId = payload['currentRegistrarUserId'] as String? ??
          _currentRegistrarUserId;
      _playerMoney
        ..clear()
        ..addAll((payload['playerMoney'] as Map? ?? const <String, dynamic>{})
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveProgress() async {
    final payload = _buildSessionPayload();
    final id = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: 'canasta',
      gameLabel: 'Канастер',
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

    final playerUserIds = widget.selectedUserIds
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
      playerUserIds: widget.selectedUserIds
          .where((id) => id.isNotEmpty)
          .toList(growable: false),
      displayNameForUserId: (userId) =>
          _profiles[userId]?.displayName ?? 'Тоглогч',
      usernameForUserId: (userId) => _profiles[userId]?.username ?? '',
    );

    if (!mounted || resolvedRegistrarUserId == null) return;
    setState(() {
      _currentRegistrarUserId = resolvedRegistrarUserId;
    });
  }

  Future<void> _handleExitFromCanasta() async {
    await _askRegistrarDecisionAtGameEndIfNeeded();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _showSessionSummaryDialog() async {
    final participants = widget.selectedUserIds
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтын тайлан'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('КАНАСТЕР - ТОГЛОЛТЫН ТАЙЛАН'),
                  const SizedBox(height: 8),
                  Text('Нийт раунд: $_roundNumber'),
                  Text('Нийт оролцсон тоглогч: ${participants.length}'),
                  const SizedBox(height: 10),
                  ...List.generate(participants.length, (index) {
                    final userId = participants[index];
                    final profile = _profiles[userId];
                    final displayName = profile?.displayName ?? 'Тоглогч';
                    final username = profile?.username ?? '';
                    final photoUrl = profile?.photoUrl;
                    final money = _playerMoney[userId] ?? 0;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? (photoUrl.startsWith('http')
                                ? NetworkImage(photoUrl)
                                : AssetImage('assets/$photoUrl')
                                    as ImageProvider)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text('${index + 1}. $displayName'),
                      subtitle: Text(username.isEmpty ? '@-' : '@$username'),
                      trailing: Text('₮$money'),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: _shareSessionReport,
              icon: Image.asset(
                'assets/buttons/send.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              label: const Text('Илгээх'),
            ),
            TextButton.icon(
              onPressed: _printSessionReport,
              icon: Image.asset(
                'assets/buttons/print.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              label: const Text('Хэвлэх'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: Image.asset(
                'assets/buttons/back.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              label: const Text('Буцах'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await _askRegistrarDecisionAtGameEndIfNeeded();
                await _removeSavedProgressIfAny();
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const PlayerSelectionPage(),
                  ),
                  (route) => false,
                );
              },
              icon: Image.asset(
                'assets/buttons/exit.webp',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
              label: const Text('Дуусгах'),
            ),
          ],
        );
      },
    );
  }

  String _buildSessionReportText() {
    final participants = widget.selectedUserIds
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final lines = <String>[
      'КАНАСТЕР - ТОГЛОЛТЫН ТАЙЛАН',
      'Нийт раунд: $_roundNumber',
      'Нийт оролцсон тоглогч: ${participants.length}',
      '',
      'Тоглогчдын дүн:',
    ];

    for (int i = 0; i < participants.length; i++) {
      final uid = participants[i];
      final profile = _profiles[uid];
      final displayName = profile?.displayName ?? 'Тоглогч';
      final username = profile?.username ?? '';
      final money = _playerMoney[uid] ?? 0;
      lines.add(
          '${i + 1}. $displayName (${username.isEmpty ? '@-' : '@$username'}) - ₮$money');
    }

    return lines.join('\n');
  }

  Future<void> _shareSessionReport() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _buildSessionReportText(),
          subject: 'Канастер - тоглолтын тайлан',
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

  Future<void> _addCurrentSessionToStatisticsIfNeeded() async {
    if (_sessionAddedToStatistics) return;

    final allPlayers = <StatsPlayerResult>[];
    for (final uid in widget.selectedUserIds) {
      final p = _profiles[uid];
      final displayName = p?.displayName ?? uid;
      final username = p?.username ?? '';

      int money = _playerMoney[uid] ?? 0;
      if (_betMode == _CanastaBetMode.perTeam) {
        if (_team1Ids.contains(uid)) {
          final per =
              _team1Ids.isEmpty ? 0 : (_teamMoney[0] ~/ _team1Ids.length);
          money = per;
        } else if (_team2Ids.contains(uid)) {
          final per =
              _team2Ids.isEmpty ? 0 : (_teamMoney[1] ~/ _team2Ids.length);
          money = per;
        }
      }

      allPlayers.add(
        StatsPlayerResult(
          userId: uid,
          username: username,
          displayName: displayName,
          money: money,
        ),
      );
    }

    final session = StatsSession(
      sessionId: 'canasta_${DateTime.now().millisecondsSinceEpoch}',
      gameKey: 'canasta',
      gameLabel: 'Канастер',
      playedAt: DateTime.now(),
      players: allPlayers,
      totalRounds: _roundNumber,
    );
    final repository = StatsRepository();
    await repository.addSession(session);
    _sessionAddedToStatistics = true;
  }

  Future<void> _showTeamSplitDialog() async {
    final allIds = widget.selectedUserIds.where((id) => id.isNotEmpty).toList();

    final List<String> unassigned = List<String>.from(allIds);
    final List<String> team1 = [];
    final List<String> team2 = [];

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            Widget playerChip(
              String uid, {
              VoidCallback? onRemove,
              bool small = false,
            }) {
              final p = _profiles[uid];
              final name = p?.displayName ?? uid;
              final photo = p?.photoUrl;
              return Draggable<String>(
                data: uid,
                feedback: Material(
                  color: Colors.transparent,
                  child:
                      _AvatarChip(name: name, photoUrl: photo, dragging: true),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.35,
                  child: _AvatarChip(name: name, photoUrl: photo),
                ),
                child: _AvatarChip(
                  name: name,
                  photoUrl: photo,
                  onRemove: onRemove,
                ),
              );
            }

            Widget dropZone({
              required String label,
              required Color color,
              required List<String> members,
              required void Function(String uid) onAccept,
            }) {
              return DragTarget<String>(
                onWillAcceptWithDetails: (d) => !members.contains(d.data),
                onAcceptWithDetails: (d) => setD(() => onAccept(d.data)),
                builder: (ctx, candidates, _) {
                  final highlight = candidates.isNotEmpty;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    constraints: const BoxConstraints(minHeight: 80),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: highlight
                          ? color.withOpacity(0.22)
                          : color.withOpacity(0.07),
                      border: Border.all(
                        color: highlight ? color : color.withOpacity(0.35),
                        width: highlight ? 2.4 : 1.4,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: color.withOpacity(0.85))),
                        const SizedBox(height: 6),
                        if (members.isEmpty)
                          Text('Энд чирж оруулна уу',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13))
                        else
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: members
                                .map((uid) => playerChip(uid, onRemove: () {
                                      setD(() {
                                        members.remove(uid);
                                        if (!unassigned.contains(uid)) {
                                          unassigned.add(uid);
                                        }
                                      });
                                    }))
                                .toList(),
                          ),
                      ],
                    ),
                  );
                },
              );
            }

            return AlertDialog(
              title: const Text('Баг хуваах'),
              content: SizedBox(
                width: 640,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (unassigned.isNotEmpty) ...[
                      Text('Сонгогдсон тоглогчид',
                          style: TextStyle(
                              color: Colors.grey.shade700, fontSize: 13)),
                      const SizedBox(height: 6),
                      DragTarget<String>(
                        onWillAcceptWithDetails: (d) =>
                            !unassigned.contains(d.data),
                        onAcceptWithDetails: (d) {
                          setD(() {
                            team1.remove(d.data);
                            team2.remove(d.data);
                            if (!unassigned.contains(d.data)) {
                              unassigned.add(d.data);
                            }
                          });
                        },
                        builder: (ctx, candidates, _) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: candidates.isNotEmpty
                                ? Colors.grey.shade200
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: unassigned
                                .map((uid) => playerChip(uid))
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: dropZone(
                            label: '🟣 Баг 1',
                            color: const Color(0xFF6A1B9A),
                            members: team1,
                            onAccept: (uid) {
                              unassigned.remove(uid);
                              team2.remove(uid);
                              if (!team1.contains(uid)) team1.add(uid);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: dropZone(
                            label: '🟠 Баг 2',
                            color: const Color(0xFFF57C00),
                            members: team2,
                            onAccept: (uid) {
                              unassigned.remove(uid);
                              team1.remove(uid);
                              if (!team2.contains(uid)) team2.add(uid);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: (team1.isNotEmpty && team2.isNotEmpty)
                      ? () => Navigator.of(dialogCtx).pop()
                      : null,
                  child: const Text('Тоглолт эхлэх'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _team1Ids = List<String>.from(team1);
      _team2Ids = List<String>.from(team2);
      _teamsAssigned = team1.isNotEmpty && team2.isNotEmpty;
    });
  }

  void _onScoreChanged() {
    setState(() {});
    if (_checkingWin) return;
    for (int i = 0; i < _scores.length; i++) {
      if (_scores[i].totalScore >= _targetScore) {
        _checkingWin = true;
        Future.microtask(() => _handleWin(i));
        break;
      }
    }
  }

  Future<void> _handleWin(int winnerIndex) async {
    final loserIndex = winnerIndex == 0 ? 1 : 0;
    final winnerIds = winnerIndex == 0 ? _team1Ids : _team2Ids;
    final loserIds = winnerIndex == 0 ? _team2Ids : _team1Ids;
    if (_betMode == _CanastaBetMode.perTeam) {
      setState(() {
        _teamMoney[winnerIndex] += _betAmount;
        _teamMoney[loserIndex] -= _betAmount;
        _teamWins[winnerIndex]++;
      });
    } else {
      final pot = loserIds.length * _betAmount;
      final gain = winnerIds.isEmpty ? 0 : pot ~/ winnerIds.length;
      setState(() {
        for (final uid in loserIds) {
          _playerMoney[uid] = (_playerMoney[uid] ?? 0) - _betAmount;
        }
        for (final uid in winnerIds) {
          _playerMoney[uid] = (_playerMoney[uid] ?? 0) + gain;
        }
        _teamWins[winnerIndex]++;
      });
    }
    await _addCurrentSessionToStatisticsIfNeeded();
    await _removeSavedProgressIfAny();
    await _showWinDialog(winnerIndex);
    _resetRound();
  }

  void _resetRound() {
    setState(() {
      _roundNumber++;
      _checkingWin = false;
      for (final score in _scores) {
        score.openedState = _OpenedState.clean;
        score.cleanCanastas = 0;
        score.dirtyCanastas = 0;
        score.dranksCount = 0;
        for (final card in score.cardsInHand) {
          card.count = 0;
        }
        score.closed = false;
      }
    });
  }

  Future<void> _showWinDialog(int winnerIndex) async {
    if (!mounted) return;
    final winnerLabel = winnerIndex == 0 ? 'Баг 1' : 'Баг 2';
    final wins = _teamWins[winnerIndex];
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 Тоглолт дууслаа!'),
        content: Text(
          '$winnerLabel хожлоо!\n\nНийт хожил: $wins\n\nДараагийн тоглолтыг эхлэх үү?',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Үргэлжлүүлэх'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsDialog() async {
    final betCtrl = TextEditingController(text: _betAmount.toString());
    final scoreCtrl = TextEditingController(text: _targetScore.toString());
    var tempMode = _betMode;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Канастер тохиргоо'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: scoreCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Хожлын хязгаар оноо',
                    helperText: 'Жишээ: 2500, 3000',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Мөнгө тооцох хэлбэр',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<_CanastaBetMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _CanastaBetMode.perTeam,
                  groupValue: tempMode,
                  title: const Text('Нэг баг'),
                  onChanged: (v) {
                    if (v != null) setD(() => tempMode = v);
                  },
                ),
                RadioListTile<_CanastaBetMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _CanastaBetMode.perMember,
                  groupValue: tempMode,
                  title: const Text('Гишүүн тус бүрээр'),
                  onChanged: (v) {
                    if (v != null) setD(() => tempMode = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: betCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))
                  ],
                  decoration: InputDecoration(
                    labelText:
                        'Тоглолт бүрийн мөнгө (${tempMode == _CanastaBetMode.perTeam ? "нэг баг" : "нэг гишүүн"})',
                    helperText: 'Жишээ: 5000',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Болих'),
            ),
            ElevatedButton(
              onPressed: () {
                final s = int.tryParse(scoreCtrl.text.trim());
                final b = int.tryParse(betCtrl.text.trim());
                if (s == null || s <= 0) return;
                if (b == null || b < 0) return;
                setState(() {
                  _targetScore = s;
                  _betAmount = b;
                  _betMode = tempMode;
                });
                Navigator.of(dialogCtx).pop();
              },
              child: const Text('Хадгалах'),
            ),
          ],
        ),
      ),
    );
    betCtrl.dispose();
    scoreCtrl.dispose();
  }

  ImageProvider? _resolvePhoto(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return NetworkImage(url);
    }
    return AssetImage('assets/$url');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UnifiedGameAppBar(
        currentUserId: widget.currentUserId,
        canManageGames: widget.canManageGames,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Канастер'),
              if (_currentRegistrarUserId != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'Бүртгэл хөтлөгч: ${_profiles[_currentRegistrarUserId!]?.displayName ?? 'Тоглогч'}',
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
                        _profiles[_currentRegistrarUserId!]?.displayName ??
                            'Тоглогч',
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
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          final selectedUserIds = widget.selectedUserIds
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
        onSave: _saveProgress,
        onReport: _showSessionSummaryDialog,
        onSettings: _showSettingsDialog,
        onExit: _showSessionSummaryDialog,
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
          if (_teamsAssigned)
            IconButton(
              tooltip: 'Баг дахин хуваах',
              onPressed: _showTeamSplitDialog,
              icon: const Icon(Icons.group),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_teamsAssigned
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Баг хуваагдаагүй байна.',
                          style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _showTeamSplitDialog,
                        icon: const Icon(Icons.group),
                        label: const Text('Баг хуваах'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _TeamScoreBlock(
                          key: ValueKey('team1-$_roundNumber'),
                          teamLabel: 'Баг 1',
                          color: Colors.blue,
                          borderColor: const Color(0xFF6A1B9A),
                          memberIds: _team1Ids,
                          profiles: _profiles,
                          score: _scores[0],
                          wins: _teamWins[0],
                          teamMoney: _teamMoney[0],
                          playerMoney: _playerMoney,
                          betMode: _betMode,
                          targetScore: _targetScore,
                          resolvePhoto: _resolvePhoto,
                          onChanged: _onScoreChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TeamScoreBlock(
                          key: ValueKey('team2-$_roundNumber'),
                          teamLabel: 'Баг 2',
                          color: Colors.green,
                          borderColor: const Color(0xFFF57C00),
                          memberIds: _team2Ids,
                          profiles: _profiles,
                          score: _scores[1],
                          wins: _teamWins[1],
                          teamMoney: _teamMoney[1],
                          playerMoney: _playerMoney,
                          betMode: _betMode,
                          targetScore: _targetScore,
                          resolvePhoto: _resolvePhoto,
                          onChanged: _onScoreChanged,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────
enum _OpenedState { clean, dirty, unopenedClean, unopenedDirty }

class _CardInHand {
  int count = 0;
  double multiplier = 0.5;
}

class _TeamScore {
  _OpenedState openedState = _OpenedState.clean;
  int cleanCanastas = 0;
  int dirtyCanastas = 0;
  int dranksCount = 0;
  final List<_CardInHand> cardsInHand = [
    _CardInHand()..multiplier = 0.5,
    _CardInHand()..multiplier = 1.0,
    _CardInHand()..multiplier = 2.0,
    _CardInHand()..multiplier = 5.0,
    _CardInHand()..multiplier = 10.0,
  ];
  bool closed = false;

  int get openedScore {
    switch (openedState) {
      case _OpenedState.clean:
        return 1000;
      case _OpenedState.dirty:
        return 500;
      case _OpenedState.unopenedClean:
        return 500;
      case _OpenedState.unopenedDirty:
        return 300;
    }
  }

  int get canastasScore => cleanCanastas * 500 + dirtyCanastas * 300;
  int get dranksScore => dranksCount * 100;
  int get cardsInHandTotal {
    int t = 0;
    for (final c in cardsInHand) {
      t += (c.count * c.multiplier).round();
    }
    return t;
  }

  int get closedScore => closed ? 200 : 0;
  int get totalScore =>
      openedScore +
      canastasScore +
      dranksScore +
      cardsInHandTotal +
      closedScore;
}

class _PlayerProfile {
  _PlayerProfile({
    required this.userId,
    required this.displayName,
    this.username = '',
    this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String username;
  final String? photoUrl;
}

// ─────────────────────────────────────────────────────────────────────────────
// Draggable avatar chip
// ─────────────────────────────────────────────────────────────────────────────
class _AvatarChip extends StatelessWidget {
  const _AvatarChip({
    required this.name,
    this.photoUrl,
    this.onRemove,
    this.dragging = false,
  });

  final String name;
  final String? photoUrl;
  final VoidCallback? onRemove;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    ImageProvider? img;
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      img = photoUrl!.startsWith('http')
          ? NetworkImage(photoUrl!)
          : AssetImage('assets/$photoUrl') as ImageProvider;
    }
    return Material(
      elevation: dragging ? 6 : 0,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: dragging ? Colors.deepPurple.shade50 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: dragging ? Colors.deepPurple.shade300 : Colors.grey.shade400,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple.shade100,
              backgroundImage: img,
              child: img == null
                  ? const Icon(Icons.person, size: 16, color: Colors.deepPurple)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(name,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (onRemove != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 16, color: Colors.black45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Team score block
// ─────────────────────────────────────────────────────────────────────────────
class _TeamScoreBlock extends StatefulWidget {
  const _TeamScoreBlock({
    super.key,
    required this.teamLabel,
    required this.color,
    required this.borderColor,
    required this.memberIds,
    required this.profiles,
    required this.score,
    required this.wins,
    required this.teamMoney,
    required this.playerMoney,
    required this.betMode,
    required this.targetScore,
    required this.resolvePhoto,
    required this.onChanged,
  });

  final String teamLabel;
  final Color color;
  final Color borderColor;
  final List<String> memberIds;
  final Map<String, _PlayerProfile> profiles;
  final _TeamScore score;
  final int wins;
  final int teamMoney;
  final Map<String, int> playerMoney;
  final _CanastaBetMode betMode;
  final int targetScore;
  final ImageProvider? Function(String?) resolvePhoto;
  final VoidCallback onChanged;

  @override
  State<_TeamScoreBlock> createState() => _TeamScoreBlockState();
}

class _TeamScoreBlockState extends State<_TeamScoreBlock> {
  late final TextEditingController _cleanCanCtrl;
  late final TextEditingController _dirtyCanCtrl;
  late final TextEditingController _drankCtrl;
  final List<TextEditingController> _cardCtrls = [];

  @override
  void initState() {
    super.initState();
    final s = widget.score;
    _cleanCanCtrl = TextEditingController(text: s.cleanCanastas.toString());
    _dirtyCanCtrl = TextEditingController(text: s.dirtyCanastas.toString());
    _drankCtrl = TextEditingController(text: s.dranksCount.toString());
    _syncCardCtrls();
  }

  void _syncCardCtrls() {
    final cards = widget.score.cardsInHand;
    while (_cardCtrls.length < cards.length) {
      final i = _cardCtrls.length;
      _cardCtrls.add(TextEditingController(text: cards[i].count.toString()));
    }
    while (_cardCtrls.length > cards.length) {
      _cardCtrls.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    _cleanCanCtrl.dispose();
    _dirtyCanCtrl.dispose();
    _drankCtrl.dispose();
    for (final c in _cardCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    setState(() {});
    widget.onChanged();
  }

  int _parseInt(String value) => int.tryParse(value.trim()) ?? 0;

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: widget.color.withOpacity(0.85),
          ),
        ),
      );

  Widget _scoreDisplay(int value) => Text(
        '= $value оноо',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: value < 0 ? Colors.red : Colors.black54,
        ),
      );

  Widget _intInput({
    required TextEditingController controller,
    required Color color,
    required ValueChanged<String> onChanged,
    double? width = 84,
    bool bordered = true,
    double fontSize = 16,
    bool fillHeight = false,
  }) {
    final field = TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
      minLines: fillHeight ? null : 1,
      maxLines: fillHeight ? null : 1,
      expands: fillHeight,
      textAlign: TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        isDense: !bordered,
        contentPadding: fillHeight
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: bordered
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: color.withOpacity(0.65), width: 1.3),
              )
            : InputBorder.none,
        enabledBorder: bordered ? null : InputBorder.none,
        focusedBorder: bordered
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: color, width: 1.8),
              )
            : InputBorder.none,
      ),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
      ),
      onChanged: onChanged,
    );
    return width != null ? SizedBox(width: width, child: field) : field;
  }

  Widget _buildMembersRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: widget.memberIds.map((uid) {
        final p = widget.profiles[uid];
        final img = widget.resolvePhoto(p?.photoUrl);
        final displayName = p?.displayName ?? uid;
        final username = (p?.username ?? '').trim();
        final shortId = uid.length > 10 ? uid.substring(0, 10) : uid;
        final secondary = username.isNotEmpty ? username : shortId;

        return SizedBox(
          width: 96,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: widget.color.withOpacity(0.18),
                backgroundImage: img,
                child: img == null
                    ? Icon(Icons.person, size: 32, color: widget.color)
                    : null,
              ),
              const SizedBox(height: 5),
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Text(
                secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWinsDisplay() {
    final wins = widget.wins;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.star, size: 18, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            '$wins хожил',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(width: 12),
          const Text('₮',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          if (widget.betMode == _CanastaBetMode.perTeam)
            _moneyChip(widget.teamMoney)
          else
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: widget.memberIds.map((uid) {
                    final m = widget.playerMoney[uid] ?? 0;
                    final p = widget.profiles[uid];
                    final name = (p?.displayName ?? uid).split(' ').first;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black54)),
                          _moneyChip(m),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _moneyChip(int amount) {
    final color = amount > 0
        ? Colors.green.shade700
        : (amount < 0 ? Colors.red : Colors.black54);
    final text = amount > 0 ? '+$amount₮' : '$amount₮';
    return Text(text,
        style:
            TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color));
  }

  Widget _buildTopSummary() {
    final total = widget.score.totalScore;
    final totalColor = total < 0 ? Colors.red : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: totalColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: totalColor.withOpacity(0.35)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    total.toString(),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: totalColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildMembersRow(),
                _buildWinsDisplay(),
              ],
            );
          }

          return SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildMembersRow(),
                        ),
                      ),
                      _buildWinsDisplay(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: totalColor.withOpacity(0.25)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Text(
                        total.toString(),
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w900,
                          color: totalColor,
                        ),
                      ),
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

  static const _openedOptions = [
    (
      state: _OpenedState.clean,
      opened: true,
      clean: true,
    ),
    (
      state: _OpenedState.dirty,
      opened: true,
      clean: false,
    ),
    (
      state: _OpenedState.unopenedClean,
      opened: false,
      clean: true,
    ),
    (
      state: _OpenedState.unopenedDirty,
      opened: false,
      clean: false,
    ),
  ];

  Widget _buildDoorIcon({required bool opened, required bool clean}) {
    final String assetPath;
    if (opened && clean) {
      assetPath = 'assets/buttons/nogoon xaalga.jpg';
    } else if (opened && !clean) {
      assetPath = 'assets/buttons/ulaan xaalga.jpg';
    } else if (!opened && clean) {
      assetPath = 'assets/buttons/green.png';
    } else {
      assetPath = 'assets/buttons/red.png';
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
    );
  }

  Widget _doorButton(
    _TeamScore s,
    ({
      _OpenedState state,
      bool opened,
      bool clean,
    }) opt,
  ) {
    final selected = s.openedState == opt.state;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() => s.openedState = opt.state);
          widget.onChanged();
        },
        child: Center(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: selected ? 1.0 : 0.72,
            child: _buildDoorIcon(opened: opt.opened, clean: opt.clean),
          ),
        ),
      ),
    );
  }

  Widget _buildOpenedSection() {
    final s = widget.score;
    return Row(
      children: _openedOptions.asMap().entries.map((e) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key > 0 ? 6 : 0),
            child: _doorButton(s, e.value),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCanastaAndDrankRow() {
    final s = widget.score;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 7, child: _buildCanastaPanel(s)),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _buildDrankPanel(s)),
      ],
    );
  }

  Widget _buildCanastaPanel(_TeamScore s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _intInput(
            controller: _cleanCanCtrl,
            color: Colors.green.shade700,
            onChanged: (v) {
              s.cleanCanastas = _parseInt(v);
              _rebuild();
            },
            width: null,
            bordered: false,
            fontSize: 26,
            fillHeight: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Image.asset(
            'assets/buttons/КАНАСТЕР бичиг, хээ .jpg',
            fit: BoxFit.contain,
          ),
        ),
        Expanded(
          child: _intInput(
            controller: _dirtyCanCtrl,
            color: Colors.red.shade700,
            onChanged: (v) {
              s.dirtyCanastas = _parseInt(v);
              _rebuild();
            },
            width: null,
            bordered: false,
            fontSize: 26,
            fillHeight: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDrankPanel(_TeamScore s) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 1,
          child: SizedBox.expand(
            child: Image.asset(
              'assets/buttons/drop.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: _intInput(
            controller: _drankCtrl,
            color: Colors.blue.shade700,
            onChanged: (v) {
              s.dranksCount = _parseInt(v);
              _rebuild();
            },
            width: null,
            bordered: false,
            fontSize: 26,
            fillHeight: true,
          ),
        ),
      ],
    );
  }

  static const _multiplierOptions = [0.5, 1.0, 2.0, 5.0, 10.0];
  static const _multiplierImages = [
    'assets/buttons/0.5.jpg',
    'assets/buttons/1.jpg',
    'assets/buttons/2.jpg',
    'assets/buttons/5.jpg',
    'assets/buttons/10.jpg',
  ];

  Widget _buildCardsAndCloseRow() {
    final s = widget.score;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 9, child: _buildCardsInHandSection(s)),
        const SizedBox(width: 8),
        Expanded(flex: 1, child: _buildCloseDoorButton(s)),
      ],
    );
  }

  Widget _buildCardsInHandSection(_TeamScore s) {
    _syncCardCtrls();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(_multiplierOptions.length, (i) {
        final m = _multiplierOptions[i];
        final card = s.cardsInHand[i];
        card.multiplier = m;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i > 0 ? 6 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Image.asset(
                    _multiplierImages[i],
                    fit: BoxFit.contain,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _intInput(
                    controller: _cardCtrls[i],
                    color: Colors.black87,
                    width: null,
                    fontSize: 22,
                    onChanged: (v) {
                      card.count = _parseInt(v);
                      _rebuild();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCloseDoorButton(_TeamScore s) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => s.closed = !s.closed);
        widget.onChanged();
      },
      child: Center(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: s.closed ? 1 : 0.78,
          child: Image.asset('assets/buttons/closed door.png',
              fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: widget.borderColor, width: 8),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopSummary(),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildOpenedSection()),
                const SizedBox(height: 8),
                Expanded(child: _buildCanastaAndDrankRow()),
                const SizedBox(height: 8),
                Expanded(child: _buildCardsAndCloseRow()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
