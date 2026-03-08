import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DurakPage extends StatefulWidget {
  const DurakPage({
    super.key,
    this.selectedUserIds = const [],
  });

  final List<String> selectedUserIds;

  @override
  State<DurakPage> createState() => _DurakPageState();
}

enum _DurakStage { setup, direct, group, finalStage, completed }

class _DurakPageState extends State<DurakPage> {
  static const int _maxPlayers = 6;
  static const Color _tableColor = Color(0xFF263238);

  int _targetWins = 3;
  int _roundNumber = 1;
  _DurakStage _stage = _DurakStage.setup;
  List<_DurakPlayer> _players = [];
  List<List<int>> _setupBlocks = List<List<int>>.generate(8, (_) => []);
  Set<int> _activeBlockIndexes = <int>{};
  Set<int> _inactiveBlockIndexes = <int>{};
  final Map<int, int> _blockWins = <int, int>{};
  int? _championBlockIndex;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _players = _buildInitialPlayers(widget.selectedUserIds);
    if (widget.selectedUserIds.isNotEmpty) {
      await _loadSelectedUserProfiles();
    }
    if (!mounted) return;
    _resetToSetup();
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

  void _resetToSetup() {
    final blocks = List<List<int>>.generate(8, (_) => []);
    for (int i = 0; i < _players.length; i++) {
      final targetBlock = i < 3 ? i : (i - 3) + 3;
      blocks[targetBlock].add(i);
    }

    setState(() {
      _stage = _DurakStage.setup;
      _roundNumber = 1;
      _championBlockIndex = null;
      _setupBlocks = blocks;
      _activeBlockIndexes = <int>{};
      _inactiveBlockIndexes = <int>{};
      _blockWins.clear();
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
      for (int i = 0; i < activeSourceIndexes.length && i < 3; i++) {
        if (nextBlocks[i].isNotEmpty) nextActive.add(i);
      }
    } else {
      if (nextBlocks[0].isNotEmpty) nextActive.add(0);
      if (nextBlocks[2].isNotEmpty) nextActive.add(2);
    }

    setState(() {
      _championBlockIndex = null;
      _stage = nextStage;
      _setupBlocks = nextBlocks;
      _activeBlockIndexes = nextActive;
      _inactiveBlockIndexes = <int>{
        for (int i = 0; i < 8; i++)
          if (!nextActive.contains(i) && nextBlocks[i].isNotEmpty) i,
      };
      _blockWins
        ..clear()
        ..addEntries(nextActive.map((index) => MapEntry(index, 0)));
      _roundNumber = 1;
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
    if (_stage == _DurakStage.group) {
      await _startFinalFromWinningBlock(winnerBlockIndex);
      return;
    }
    await _declareChampionFromBlock(winnerBlockIndex);
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

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ялагч тодорлоо'),
          content: Text('$winnerNames яллаа.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Хаах'),
            ),
          ],
        );
      },
    );
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
      ...winningMembers.skip(2),
    ];

    final nextBlocks = List<List<int>>.generate(8, (_) => []);
    nextBlocks[0] = [winningMembers[0]];
    nextBlocks[2] = [winningMembers[1]];

    int target = 3;
    for (final member in carryMembers) {
      if (target >= nextBlocks.length) break;
      nextBlocks[target] = [member];
      target += 1;
    }

    setState(() {
      _stage = _DurakStage.finalStage;
      _roundNumber += 1;
      _setupBlocks = nextBlocks;
      _activeBlockIndexes = <int>{0, 2};
      _inactiveBlockIndexes = <int>{
        for (int i = 0; i < 8; i++)
          if ((i != 0 && i != 2) && nextBlocks[i].isNotEmpty) i,
      };
      _blockWins
        ..clear()
        ..addAll({0: 0, 2: 0});
      _championBlockIndex = null;
    });
  }

  void _addPlayerFromAppBar() {
    if (_stage != _DurakStage.setup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тоглолтын явцад тоглогч нэмэхгүй')),
      );
      return;
    }
    if (_players.length >= _maxPlayers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ихдээ 6 тоглогчтой байна')),
      );
      return;
    }

    final nextIndex = _players.length + 1;
    final nextPlayer = _DurakPlayer(
      displayName: 'Тоглогч $nextIndex',
      username: 'u$nextIndex',
    );

    final nextBlocks =
        _setupBlocks.map((block) => List<int>.from(block)).toList();
    int? targetBlock;
    for (int i = 3; i < nextBlocks.length; i++) {
      if (nextBlocks[i].isEmpty) {
        targetBlock = i;
        break;
      }
    }
    targetBlock ??= nextBlocks.indexWhere((block) => block.isEmpty);
    targetBlock = targetBlock == -1 ? 7 : targetBlock;
    nextBlocks[targetBlock].add(_players.length);

    setState(() {
      _players = [..._players, nextPlayer];
      _setupBlocks = nextBlocks;
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
    });
  }

  Future<void> _showRemovePlayerDialog() async {
    if (_stage != _DurakStage.setup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тоглолтын явцад тоглогч хасахгүй')),
      );
      return;
    }
    if (_players.isEmpty) return;

    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Хасах тоглогч'),
          children: List<Widget>.generate(
            _players.length,
            (index) => SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(index),
              child: Text(_players[index].displayName),
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    _removePlayerAt(selected);
  }

  String _stageText() {
    switch (_stage) {
      case _DurakStage.setup:
        return '';
      case _DurakStage.direct:
        return 'Шууд шат';
      case _DurakStage.group:
        return 'Багийн шат (${_activeBlockIndexes.length} баг)';
      case _DurakStage.finalStage:
        return 'Финал шат';
      case _DurakStage.completed:
        return 'Тоглолт дууссан';
    }
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
                    child: Wrap(
                      spacing: isLarge ? 14 : 10,
                      runSpacing: isLarge ? 12 : 8,
                      children: members
                          .map(
                            (player) => SizedBox(
                              width: isLarge ? 112 : 84,
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: isLarge ? 30 : 24,
                                    backgroundColor: Colors.white24,
                                    backgroundImage:
                                        _resolveImage(player.photoUrl),
                                    child: (player.photoUrl == null ||
                                            player.photoUrl!.isEmpty)
                                        ? Icon(
                                            Icons.person,
                                            color: Colors.white,
                                            size: isLarge ? 34 : 26,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    player.displayName,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: isLarge ? 16 : 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ),
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
                        isLarge ? 14.0 : 10.0, isLarge ? 26.0 : 18.0);

                    return Row(
                      children: List<Widget>.generate(
                        starCount,
                        (index) => Padding(
                          padding: EdgeInsets.only(
                            right: index == starCount - 1 ? 0 : spacing,
                          ),
                          child: GestureDetector(
                            onTap: isInteractive
                                ? () => _changeBlockWins(blockIndex, 1)
                                : null,
                            onLongPress: isInteractive
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

  @override
  Widget build(BuildContext context) {
    final hasChampion = _championBlockIndex != null;
    final isSetup = _stage == _DurakStage.setup;
    final stageTitle = _stageText();

    return Scaffold(
      backgroundColor: _tableColor,
      appBar: AppBar(
        title: const Text('Дурак'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                'Тоглолтын №$_roundNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Тоглогч нэмэх',
            onPressed: _addPlayerFromAppBar,
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            tooltip: 'Тоглогч хасах',
            onPressed: _showRemovePlayerDialog,
            icon: const Icon(Icons.person_remove_alt_1),
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
                      if (stageTitle.isNotEmpty) ...[
                        Text(
                          stageTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      const Spacer(),
                      if (isSetup)
                        ElevatedButton(
                          onPressed: _startFromSetupBlocks,
                          child: const Text('Эхлүүлэх'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Хожлын босго:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const starCount = 8;
                            final starSize =
                                (constraints.maxWidth / (starCount + 0.8))
                                    .clamp(20.0, 54.0);

                            return SizedBox(
                              width: double.infinity,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children:
                                    List<Widget>.generate(starCount, (index) {
                                  final value = index + 1;
                                  final active = value <= _targetWins;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(24),
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
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _buildSetupBoard(),
            ),
            if (hasChampion)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton.icon(
                  onPressed: _resetToSetup,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Дахин эхлүүлэх'),
                ),
              ),
          ],
        ),
      ),
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
  });

  final String? userId;
  final String displayName;
  final String username;
  final String? photoUrl;

  _DurakPlayer copyWith({
    String? userId,
    String? displayName,
    String? username,
    String? photoUrl,
  }) {
    return _DurakPlayer(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}
