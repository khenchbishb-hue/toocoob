import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'player_selection_page.dart';
import 'kinds_of_game.dart';
import 'package:toocoob/utils/game_registrar_transfer.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/widgets/unified_game_app_bar.dart';

class NyxShaxaxPage extends StatefulWidget {
  const NyxShaxaxPage({
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
  State<NyxShaxaxPage> createState() => _NyxShaxaxPageState();
}

class _NyxShaxaxPageState extends State<NyxShaxaxPage> {
  final SavedGameSessionsRepository _savedSessionsRepo =
      SavedGameSessionsRepository();
  static const Color _tableColor = Color(0xFF3B1F5C);
  static const int _maxSlots = 8;
  static const int _maxTargetWins = 8;
  static const List<Color> _slotBorderPalette = [
    Color(0xFF29B6F6),
    Color(0xFFFFCA28),
    Color(0xFF66BB6A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF26C6DA),
    Color(0xFFFF7043),
    Color(0xFF9CCC65),
  ];

  int _targetWins = 3;
  List<_TargetWinPlayer> _players = [];
  String? _activeSavedSessionId;
  String? _currentRegistrarUserId;
  bool _registrarEndDecisionHandled = false;
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

    final payload = saved.payload;
    final restoredTarget = (payload['targetWins'] as num?)?.toInt() ?? 3;
    final rawPlayers = (payload['players'] as List? ?? const <dynamic>[]);
    final restoredPlayers = rawPlayers
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (e) => _TargetWinPlayer(
            userId: (e['userId'] ?? '').toString().isEmpty
                ? null
                : (e['userId'] ?? '').toString(),
            displayName: (e['displayName'] ?? '').toString(),
            username: (e['username'] ?? '').toString(),
            photoUrl: (e['photoUrl'] ?? '').toString().isEmpty
                ? null
                : (e['photoUrl'] ?? '').toString(),
            wins: (e['wins'] as num? ?? 0).toInt(),
          ),
        )
        .toList();

    setState(() {
      _activeSavedSessionId = saved.id;
      _targetWins = restoredTarget.clamp(1, _maxTargetWins);
      if (restoredPlayers.isNotEmpty) {
        _players = restoredPlayers;
      }
    });
  }

  Future<void> _saveProgress() async {
    final payload = {
      'targetWins': _targetWins,
      'players': _players
          .map((p) => {
                'userId': p.userId,
                'displayName': p.displayName,
                'username': p.username,
                'photoUrl': p.photoUrl,
                'wins': p.wins,
              })
          .toList(),
    };
    final id = await _savedSessionsRepo.saveOrUpdate(
      sessionId: _activeSavedSessionId,
      gameKey: 'nvx_shaxax',
      gameLabel: 'Нүх шахах',
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

  List<_TargetWinPlayer> _buildInitialPlayers(List<String> selectedUserIds) {
    final count = selectedUserIds.length.clamp(0, _maxSlots);
    return List<_TargetWinPlayer>.generate(
      count,
      (index) => _TargetWinPlayer(
        userId: selectedUserIds[index],
        displayName: 'Тоглогч ${index + 1}',
        username: 'u${index + 1}',
        wins: 0,
      ),
    );
  }

  Future<void> _loadSelectedUserProfiles() async {
    final updated = List<_TargetWinPlayer>.from(_players);

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

  void _setTargetWins(int value) {
    if (value < 1 || value > _maxTargetWins) return;
    setState(() {
      _targetWins = value;
      _players = _players
          .map((player) => player.copyWith(
                wins: player.wins > value ? value : player.wins,
              ))
          .toList(growable: false);
    });
  }

  Future<void> _addPlayerFromSelection() async {
    if (_players.length >= _maxSlots) return;

    final excludedIds = _players
        .map((player) => player.userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    final result = await Navigator.push<List<dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          isAddingMode: true,
          excludedUserIds: excludedIds,
        ),
      ),
    );

    final selectedIds =
        (result ?? const <dynamic>[]).whereType<String>().toList();

    if (selectedIds.isEmpty) return;

    final remaining = _maxSlots - _players.length;
    final idsToAdd = selectedIds
        .where((id) => !excludedIds.contains(id))
        .take(remaining)
        .toList(growable: false);

    if (idsToAdd.isEmpty) return;

    setState(() {
      for (final userId in idsToAdd) {
        final seatNumber = _players.length + 1;
        _players.add(
          _TargetWinPlayer(
            userId: userId,
            displayName: 'Тоглогч $seatNumber',
            username: 'u$seatNumber',
            wins: 0,
          ),
        );
      }
    });

    await _loadSelectedUserProfiles();
  }

  Future<void> _showRemovePlayersDialog() async {
    if (_players.isEmpty) return;

    final selectedIndexes = <int>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Тоглогч хасах'),
              content: SizedBox(
                width: 420,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _players.length,
                  itemBuilder: (context, index) {
                    final player = _players[index];
                    final checked = selectedIndexes.contains(index);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (value) {
                        setLocalState(() {
                          if (value == true) {
                            selectedIndexes.add(index);
                          } else {
                            selectedIndexes.remove(index);
                          }
                        });
                      },
                      title: Text(player.displayName),
                      subtitle: Text('@${player.username}'),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Болих'),
                ),
                ElevatedButton(
                  onPressed: selectedIndexes.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Хасах'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || selectedIndexes.isEmpty) return;

    setState(() {
      _players = [
        for (int i = 0; i < _players.length; i++)
          if (!selectedIndexes.contains(i)) _players[i],
      ];
    });
  }

  void _changeWins(int index, int delta) {
    if (index < 0 || index >= _players.length) return;
    setState(() {
      final player = _players[index];
      final nextWins = (player.wins + delta).clamp(0, _targetWins);
      _players[index] = player.copyWith(wins: nextWins);
    });

    final winner = _winner;
    if (winner != null &&
        widget.autoReturnOnWinner &&
        !_multiAutoReturnTriggered) {
      _multiAutoReturnTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final winnerUserId = winner.userId;
        Navigator.of(context).pop(<String, dynamic>{
          'completedGame': 'nvx_shaxax',
          if (winnerUserId != null && winnerUserId.isNotEmpty)
            'winnerUserId': winnerUserId,
        });
      });
      return;
    }

    if (winner != null && !_registrarEndDecisionHandled) {
      _registrarEndDecisionHandled = true;
      _removeSavedProgressIfAny();
      _askRegistrarDecisionAtGameEndIfNeeded();
    } else if (winner == null) {
      _registrarEndDecisionHandled = false;
    }
  }

  _TargetWinPlayer? get _winner {
    for (final player in _players) {
      if (player.wins >= _targetWins) return player;
    }
    return null;
  }

  String _buildSessionReportText() {
    final lines = <String>[
      'НҮХ ШАХАХ - ТОГЛОЛТЫН ТАЙЛАН',
      'Нийт тоглогч: ${_players.length}',
      'Хожлын босго: $_targetWins',
      '',
      'Тоглогчдын дүн:',
    ];
    for (int i = 0; i < _players.length; i++) {
      final p = _players[i];
      lines.add('${i + 1}. ${p.displayName} (@${p.username}) - ⭐ ${p.wins}');
    }
    return lines.join('\n');
  }

  Future<void> _shareSessionReport() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _buildSessionReportText(),
          subject: 'Нүх шахах - тоглолтын тайлан',
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

  Future<void> _showSessionSummaryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Тоглолтын тайлан'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('НҮХ ШАХАХ - ТОГЛОЛТЫН ТАЙЛАН'),
                  const SizedBox(height: 8),
                  Text('Нийт тоглогч: ${_players.length}'),
                  Text('Хожлын босго: $_targetWins'),
                  const SizedBox(height: 10),
                  ...List.generate(_players.length, (index) {
                    final player = _players[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundImage: player.photoUrl != null &&
                                player.photoUrl!.isNotEmpty
                            ? NetworkImage(player.photoUrl!)
                            : null,
                        child:
                            player.photoUrl == null || player.photoUrl!.isEmpty
                                ? const Icon(Icons.person)
                                : null,
                      ),
                      title: Text('${index + 1}. ${player.displayName}'),
                      subtitle: Text('@${player.username}'),
                      trailing: Text('⭐ ${player.wins}'),
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

  @override
  Widget build(BuildContext context) {
    final winner = _winner;

    return Scaffold(
      backgroundColor: _tableColor,
      appBar: UnifiedGameAppBar(
        title: const Text('Нүх шахах'),
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
                playingFormat:
                    widget.multiWinsByUserId != null ? 'multi' : 'single',
              ),
            ),
          );
        },
        onRemovePlayer: _players.isEmpty ? null : _showRemovePlayersDialog,
        onAddPlayer:
            _players.length >= _maxSlots ? null : _addPlayerFromSelection,
        onSave: _saveProgress,
        onReport: _showSessionSummaryDialog,
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
              child: Row(
                children: [
                  const Text(
                    'Хожлын босго:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 34,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: List<Widget>.generate(_maxTargetWins, (index) {
                        final value = index + 1;
                        final isActive = value <= _targetWins;
                        return InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => _setTargetWins(value),
                          child: Icon(
                            Icons.star_rounded,
                            size: 84,
                            color: isActive ? Colors.amber : Colors.white24,
                          ),
                        );
                      }),
                    ),
                  ),
                  if (winner != null)
                    Text(
                      'Ялагч: ${winner.displayName}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _buildBoardRow(0)),
                  const SizedBox(height: 10),
                  Expanded(child: _buildBoardRow(4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardRow(int startIndex) {
    return Row(
      children: List<Widget>.generate(4, (offset) {
        final slotIndex = startIndex + offset;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: offset == 3 ? 0 : 10),
            child: _buildSlot(slotIndex),
          ),
        );
      }),
    );
  }

  Widget _buildSlot(int index) {
    if (index >= _players.length) return _buildInactiveSlot();
    return _buildPlayerCard(_players[index], index);
  }

  Widget _buildPlayerCard(_TargetWinPlayer player, int index) {
    final isWinner = player.wins >= _targetWins;
    final borderColor = isWinner
        ? Colors.amber
        : _slotBorderPalette[index % _slotBorderPalette.length];
    final multiWins = widget.multiWinsByUserId?[player.userId ?? ''] ?? 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _changeWins(index, 1),
        onLongPress: () => _changeWins(index, -1),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2.4),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 56,
                        backgroundColor: Colors.white24,
                        backgroundImage: _resolveImage(player.photoUrl),
                        child:
                            player.photoUrl == null || player.photoUrl!.isEmpty
                                ? const Icon(Icons.person,
                                    color: Colors.white, size: 56)
                                : null,
                      ),
                      if (widget.multiWinsByUserId != null)
                        Positioned(
                          right: -14,
                          top: 8,
                          child: Column(
                            children: [
                              const Icon(Icons.emoji_events,
                                  color: Colors.amber, size: 20),
                              Text(
                                '$multiWins',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          player.displayName,
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                          ),
                        ),
                        Text(
                          '@${player.username}',
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 4.0;
                    final cellWidth = (constraints.maxWidth - spacing * 3) / 4;
                    final rowHeight = (constraints.maxHeight - spacing) / 2;
                    final iconSize = math.max(
                      8.0,
                      math.min(30.0, math.min(cellWidth, rowHeight) - 2),
                    );

                    Widget buildStar(int starIndex) {
                      final inTarget = starIndex < _targetWins;
                      final isActiveStar = inTarget && starIndex < player.wins;
                      return Icon(
                        Icons.star_rounded,
                        size: iconSize,
                        color: !inTarget
                            ? Colors.transparent
                            : isActiveStar
                                ? Colors.amber
                                : Colors.white24,
                      );
                    }

                    return Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              for (int i = 0; i < 4; i++) ...[
                                Expanded(child: Center(child: buildStar(i))),
                                if (i != 3) const SizedBox(width: spacing),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: spacing),
                        Expanded(
                          child: Row(
                            children: [
                              for (int i = 4; i < 8; i++) ...[
                                Expanded(child: Center(child: buildStar(i))),
                                if (i != 7) const SizedBox(width: spacing),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInactiveSlot() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: Icon(
          Icons.person_outline,
          color: Colors.white24,
          size: 54,
        ),
      ),
    );
  }

  ImageProvider? _resolveImage(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    if (photoUrl.startsWith('http')) {
      return NetworkImage(photoUrl);
    }
    return AssetImage('assets/$photoUrl');
  }
}

class _TargetWinPlayer {
  const _TargetWinPlayer({
    this.userId,
    required this.displayName,
    required this.username,
    this.photoUrl,
    required this.wins,
  });

  final String? userId;
  final String displayName;
  final String username;
  final String? photoUrl;
  final int wins;

  _TargetWinPlayer copyWith({
    String? userId,
    String? displayName,
    String? username,
    String? photoUrl,
    int? wins,
  }) {
    return _TargetWinPlayer(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
      wins: wins ?? this.wins,
    );
  }
}
