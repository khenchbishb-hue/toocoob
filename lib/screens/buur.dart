import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BuurPage extends StatefulWidget {
  const BuurPage({
    super.key,
    this.selectedUserIds = const [],
  });

  final List<String> selectedUserIds;

  @override
  State<BuurPage> createState() => _BuurPageState();
}

class _BuurPageState extends State<BuurPage> {
  static const List<_BuurAction> _actions = [
    _BuurAction(
      keyLabel: '31',
      transfer: 1,
      color: Color(0xFF2E7D32),
      textColor: Colors.white,
    ),
    _BuurAction(
      keyLabel: '3 A',
      keySubLabel: '♠ ♥ ♦',
      transfer: 3,
      color: Color(0xFF1B5E20),
      textColor: Colors.white,
    ),
    _BuurAction(
      keyLabel: '♣ ♣ ♣',
      transfer: 2,
      color: Color(0xFFC62828),
      textColor: Colors.white,
    ),
    _BuurAction(
      keyLabel: '7 7 7',
      transfer: 4,
      color: Color(0xFF8E0000),
      textColor: Colors.white,
    ),
  ];

  late List<_BuurPlayer> _players;
  late int _initialCenterScore;
  late int _centerScore;
  String? _winnerPlayerKey;

  @override
  void initState() {
    super.initState();
    _players = _buildInitialPlayers(widget.selectedUserIds);
    _initialCenterScore = _calculateInitialCenterScore(_players.length);
    _centerScore = _initialCenterScore;
    if (widget.selectedUserIds.isNotEmpty) {
      _loadSelectedUserProfiles();
    }
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
        final moneyRaw = data['money'];
        final money = moneyRaw is num ? moneyRaw.toInt() : updated[i].money;

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
          money: money,
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Буур'),
        elevation: 0,
        actions: [
          if (_winnerPlayerKey != null)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Ялагч тодорсон',
                  style: TextStyle(fontWeight: FontWeight.bold),
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
                            child: SizedBox(
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
                              valueColor: Colors.black,
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
                constraints: const BoxConstraints(maxWidth: 170),
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
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4E3D6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB34A33), width: 1.8),
      ),
      alignment: Alignment.center,
      child: Text(
        '$_centerScore',
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
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
          decoration: BoxDecoration(
            color: isHovering
                ? action.color.withOpacity(0.85)
                : action.color.withOpacity(0.72),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                action.keyLabel,
                style: TextStyle(
                  color: action.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              if (action.keySubLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  action.keySubLabel!,
                  style: TextStyle(
                    color: action.textColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
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
  });

  final String keyLabel;
  final String? keySubLabel;
  final int transfer;
  final Color color;
  final Color textColor;
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
