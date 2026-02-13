import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../player_selection_page.dart';

class CardPokerPageIOS extends StatefulWidget {
  const CardPokerPageIOS({super.key, required this.selectedUserIds});

  final List<String> selectedUserIds;

  @override
  State<CardPokerPageIOS> createState() => _CardPokerPageIOSState();
}

class _CardPokerPageIOSState extends State<CardPokerPageIOS>
    with SingleTickerProviderStateMixin {
  String selectedGame = '1';
  late List<String> currentPlayerIds;
  final int _currentPlayerIndex = 0;
  late PageController _pageController;
  Map<int, String> playerScores = {};
  List<String> _orderedPlayerIds = [];
  Map<String, int> _playerOrder = {};
  int _activeScoreIndex = 0;
  Map<String, int> _totalScores = {};
  Set<int> _submittedScoreIndices = {};
  final List<String> _borrowedFromBench = [];
  Set<String> _failedPlayerIds = {};
  String _currentWinnerId = '';
  int _currentWinnerPrize = 0;
  int _gameRoundNumber = 1;
  int _booltRoundNumber = 0; // Боолтын дугаар (0 = энгийн тоглолт)
  bool _isBooltMode = false; // Боолт горимд байгаа эсэх
  Map<String, int> _winAmounts = {};
  Map<String, int> _lossAmounts = {};
  Map<String, int> _winStars = {};

  @override
  void initState() {
    super.initState();
    currentPlayerIds = List.from(widget.selectedUserIds);
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && currentPlayerIds.isNotEmpty) {
        // 2 тоглогч байхан дараалал сонгох цонхгүй
        if (currentPlayerIds.length == 2) {
          setState(() {
            playerScores = {};
            _totalScores = {for (final id in currentPlayerIds) id: 0};
            _submittedScoreIndices = {};
            _failedPlayerIds = {};
            _currentWinnerId = '';
            _currentWinnerPrize = 0;
            _activeScoreIndex = 0;

            // Бүх тоглогчдыг инициализ хийх
            for (final id in currentPlayerIds) {
              _winAmounts.putIfAbsent(id, () => 0);
              _lossAmounts.putIfAbsent(id, () => 0);
              _winStars.putIfAbsent(id, () => 0);
            }
          });
        } else {
          _showStartOrderSheet();
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPlayer() {
    if (_currentPlayerIndex < currentPlayerIds.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _previousPlayer() {
    if (_currentPlayerIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _demoteActiveToBench({String? excludeId}) {
    if (currentPlayerIds.length <= 4) return;

    final activeStart = currentPlayerIds.length - 4;
    String? toDemote;

    for (int i = activeStart; i < currentPlayerIds.length; i++) {
      final id = currentPlayerIds[i];
      if (id != excludeId) {
        toDemote = id;
        break;
      }
    }

    if (toDemote == null) return;

    currentPlayerIds.remove(toDemote);
    final newBenchSize = currentPlayerIds.length - 4;
    currentPlayerIds.insert(newBenchSize, toDemote);
  }

  Future<void> _addPlayers() async {
    final result = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerSelectionPage(
          excludedUserIds: currentPlayerIds,
          isAddingMode: true,
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (result.length == 1) {
        // Single player - automatically add to end
        setState(() {
          final newId = result[0];
          currentPlayerIds.add(newId);
          _totalScores.putIfAbsent(newId, () => 0);
          _demoteActiveToBench(excludeId: newId);
          _orderedPlayerIds = [];
          _playerOrder = {};
          playerScores = {};
          _submittedScoreIndices = {};
          _activeScoreIndex =
              currentPlayerIds.length > 4 ? currentPlayerIds.length - 4 : 0;
        });
      } else {
        // Multiple players - show selection dialog for new players only
        await _showStartOrderSheetForNewPlayers(result);
      }
    }
  }

  Future<void> _removePlayers() async {
    final players = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId,
            whereIn: currentPlayerIds.isEmpty ? [''] : currentPlayerIds)
        .get();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 30,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Тоглогч хасах',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: GridView.builder(
                        shrinkWrap: true,
                        cacheExtent: 300,
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: true,
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.8,
                        ),
                        itemCount: players.docs.length,
                        itemBuilder: (context, index) {
                          final player = players.docs[index];
                          final data = player.data();
                          final displayName = data['displayName'] ??
                              data['username'] ??
                              'Хэрэглэгч';
                          final photoUrl = data['photoUrl'];

                          return GestureDetector(
                            onTap: () {
                              setStateModal(() {
                                setState(() {
                                  if (currentPlayerIds.contains(player.id)) {
                                    final removedIndex =
                                        currentPlayerIds.indexOf(player.id);
                                    final totalBefore = currentPlayerIds.length;
                                    // Bench players are always 4 or more if total > 4
                                    // For 5+ players: bench size = total - 4
                                    // For <=4 players: no bench (bench size = 0)
                                    final benchSizeBefore =
                                        totalBefore > 4 ? totalBefore - 4 : 0;

                                    // Check if removed from active zone (active starts at benchSizeBefore)
                                    final wasRemovedFromActive =
                                        removedIndex >= benchSizeBefore;

                                    // Remove the player
                                    currentPlayerIds.remove(player.id);

                                    // Remove this player's accumulated scores
                                    _totalScores.remove(player.id);
                                    _borrowedFromBench.remove(player.id);

                                    final totalAfter = currentPlayerIds.length;

                                    // If we have 4+ players and removed from active zone, move last bench player to active
                                    if (totalAfter >= 4 &&
                                        wasRemovedFromActive &&
                                        benchSizeBefore > 0) {
                                      // Take last bench player and move to end
                                      final lastBenchIndex =
                                          benchSizeBefore - 1;
                                      if (lastBenchIndex <
                                          currentPlayerIds.length) {
                                        final benchPlayer = currentPlayerIds
                                            .removeAt(lastBenchIndex);
                                        currentPlayerIds.add(benchPlayer);
                                        _borrowedFromBench.remove(benchPlayer);
                                        _borrowedFromBench.add(benchPlayer);
                                      }
                                    }

                                    // Reset only game order tracking, preserve session scores
                                    _orderedPlayerIds = [];
                                    _playerOrder = {};
                                    _submittedScoreIndices = {};
                                    _activeScoreIndex =
                                        currentPlayerIds.length > 4
                                            ? currentPlayerIds.length - 4
                                            : 0;
                                  }
                                });
                              });
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: currentPlayerIds.contains(player.id)
                                      ? 1
                                      : 0.5,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RepaintBoundary(
                                        child: CircleAvatar(
                                          radius: 25,
                                          backgroundColor: Colors.grey[300],
                                          backgroundImage: photoUrl != null &&
                                                  photoUrl.isNotEmpty
                                              ? (photoUrl.startsWith('http')
                                                  ? NetworkImage(photoUrl)
                                                  : AssetImage('assets/$photoUrl')
                                                      as ImageProvider)
                                              : null,
                                          child: photoUrl == null ||
                                                  photoUrl.isEmpty
                                              ? const Icon(Icons.person, size: 25)
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        displayName,
                                        style: const TextStyle(fontSize: 10),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (currentPlayerIds.contains(player.id))
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(50),
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
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

  Future<void> _showStartOrderSheetForNewPlayers(
      List<String> newPlayerIds) async {
    if (newPlayerIds.isEmpty) return;
    final selectedOrder = <String>[];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Шинээр нэмэгдсэн тоглогчдын дарааллыг сонго',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: SingleChildScrollView(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .where(FieldPath.documentId,
                                      whereIn: newPlayerIds)
                                  .snapshots()
                                  .distinct((prev, next) {
                                    if (prev.docs.length != next.docs.length) return false;
                                    for (int i = 0; i < prev.docs.length; i++) {
                                      if (prev.docs[i].id != next.docs[i].id) return false;
                                    }
                                    return true;
                                  }),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }

                                final players = snapshot.data!.docs;
                                const spacing = 4.0;

                                return Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: spacing,
                                  runSpacing: spacing,
                                  children: players.map((doc) {
                                    final data =
                                        doc.data() as Map<String, dynamic>;
                                    final displayName =
                                        data['displayName'] ?? 'Player';
                                    final photoUrl =
                                        data['photoURL'] as String?;
                                    final playerId = doc.id;
                                    final orderIndex =
                                        selectedOrder.indexOf(playerId);
                                    final isSelected = orderIndex >= 0;

                                    return SizedBox(
                                      width: 70,
                                      child: GestureDetector(
                                        onTap: () {
                                          setStateModal(() {
                                            if (isSelected) {
                                              selectedOrder.remove(playerId);
                                            } else {
                                              selectedOrder.add(playerId);
                                            }
                                          });
                                        },
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          alignment: Alignment.center,
                                          children: [
                                            Opacity(
                                              opacity: isSelected ? 1 : 0.5,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  RepaintBoundary(
                                                    child: CircleAvatar(
                                                      radius: 28,
                                                      backgroundColor:
                                                          Colors.grey[300],
                                                      backgroundImage: photoUrl !=
                                                                  null &&
                                                              photoUrl.isNotEmpty
                                                          ? (photoUrl.startsWith(
                                                                  'http')
                                                              ? NetworkImage(photoUrl)
                                                              : AssetImage(
                                                                      'assets/$photoUrl')
                                                                  as ImageProvider)
                                                          : null,
                                                      child: photoUrl == null ||
                                                              photoUrl.isEmpty
                                                          ? const Icon(
                                                              Icons.person,
                                                            size: 28,)
                                                        : null,
                                                  ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    displayName,
                                                    style: const TextStyle(
                                                        fontSize: 10),
                                                    textAlign: TextAlign.center,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              Positioned(
                                                bottom: -6,
                                                left: 0,
                                                right: 0,
                                                child: Center(
                                                  child: Container(
                                                    width: 20,
                                                    height: 20,
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '${orderIndex + 1}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('Цуцлах'),
                            ),
                            ElevatedButton(
                              onPressed: selectedOrder.length ==
                                      newPlayerIds.length
                                  ? () {
                                      setState(() {
                                        for (final id in selectedOrder) {
                                          currentPlayerIds.add(id);
                                          _totalScores.putIfAbsent(id, () => 0);
                                          _demoteActiveToBench(excludeId: id);
                                        }
                                        _orderedPlayerIds = [];
                                        _playerOrder = {};
                                        playerScores = {};
                                        _submittedScoreIndices = {};
                                        _activeScoreIndex =
                                            currentPlayerIds.length > 4
                                                ? currentPlayerIds.length - 4
                                                : 0;
                                      });
                                      Navigator.of(context).pop();
                                    }
                                  : null,
                              child: Text(
                                  'Баталгаажуулах (${selectedOrder.length}/${newPlayerIds.length})'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showStartOrderSheet() async {
    if (currentPlayerIds.isEmpty) return;
    final selectedOrder = <String>[];
    final scrollController = ScrollController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              child: Container(
                padding: const EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Тоглолт № $_gameRoundNumber Суух дараалал сонгох',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '${selectedOrder.length}/${currentPlayerIds.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .where(FieldPath.documentId,
                                      whereIn: currentPlayerIds.isEmpty
                                          ? ['']
                                          : currentPlayerIds)
                                  .snapshots()
                                  .distinct((prev, next) {
                                    if (prev.docs.length != next.docs.length) return false;
                                    for (int i = 0; i < prev.docs.length; i++) {
                                      if (prev.docs[i].id != next.docs[i].id) return false;
                                    }
                                    return true;
                                  }),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final docsById = {
                                  for (final doc in snapshot.data!.docs)
                                    doc.id: doc
                                };
                                final orderedDocs = currentPlayerIds
                                    .where((id) => docsById.containsKey(id))
                                    .map((id) => docsById[id]!)
                                    .toList();

                                return Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: orderedDocs.map((player) {
                                    final data = player.data()
                                        as Map<String, dynamic>;
                                    final displayName =
                                        data['displayName'] ??
                                            data['username'] ??
                                            'Хэрэглэгч';
                                    final photoUrl = data['photoUrl'];
                                    final orderIndex =
                                        selectedOrder.indexOf(player.id);

                                    return SizedBox(
                                      width: 70,
                                      child: GestureDetector(
                                        onTap: () {
                                          setStateModal(() {
                                            if (orderIndex != -1) {
                                              selectedOrder
                                                  .remove(player.id);
                                            } else if (selectedOrder
                                                    .length <
                                                currentPlayerIds.length) {
                                              selectedOrder
                                                  .add(player.id);
                                            }
                                          });
                                        },
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white
                                                    .withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        12),
                                                border: Border.all(
                                                  color: orderIndex != -1
                                                      ? Colors.amber
                                                      : Colors
                                                          .transparent,
                                                  width: 2,
                                                ),
                                              ),
                                              padding:
                                                  const EdgeInsets.all(4),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .center,
                                                children: [
                                                  RepaintBoundary(
                                                    child: CircleAvatar(
                                                      radius: 18,
                                                      backgroundColor:
                                                          Colors.grey[300],
                                                      backgroundImage: photoUrl !=
                                                                  null &&
                                                              photoUrl
                                                                  .isNotEmpty
                                                          ? (photoUrl
                                                                  .startsWith(
                                                                      'http')
                                                              ? NetworkImage(photoUrl)
                                                            : AssetImage(
                                                                    'assets/$photoUrl')
                                                                as ImageProvider)
                                                        : null,
                                                    child: photoUrl ==
                                                                null ||
                                                            photoUrl
                                                                .isEmpty
                                                        ? const Icon(
                                                            Icons.person,
                                                            size: 16,)
                                                        : null,
                                                  ),
                                                  ),
                                                  const SizedBox(
                                                      height: 3),
                                                  Text(
                                                    displayName,
                                                    style:
                                                        const TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow
                                                        .ellipsis,
                                                    textAlign:
                                                        TextAlign.center,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (orderIndex != -1)
                                              Positioned(
                                                bottom: -6,
                                                left: 0,
                                                right: 0,
                                                child: Center(
                                                  child: Container(
                                                    width: 22,
                                                    height: 22,
                                                    decoration:
                                                        BoxDecoration(
                                                      color: Colors.amber,
                                                      shape:
                                                          BoxShape.circle,
                                                      border: Border.all(
                                                        color:
                                                            Colors.blue,
                                                        width: 2,
                                                      ),
                                                    ),
                                                    alignment:
                                                        Alignment.center,
                                                    child: Text(
                                                      '${orderIndex + 1}',
                                                      style:
                                                          const TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight
                                                                .bold,
                                                        color:
                                                            Colors.black,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setStateModal(() {
                                selectedOrder.clear();
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white70),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text(
                              'Цэвэрлэх',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedOrder.length ==
                                    currentPlayerIds.length
                                ? () {
                                    setState(() {
                                      // Өмнөх тоглолтын мэдээллийг бүхэлд нь хадгалах
                                      final preservedWinAmounts =
                                          Map<String, int>.from(_winAmounts);
                                      final preservedLossAmounts =
                                          Map<String, int>.from(_lossAmounts);
                                      final preservedWinStars =
                                          Map<String, int>.from(_winStars);

                                      _orderedPlayerIds =
                                          List.from(selectedOrder);
                                      _playerOrder = {
                                        for (int i = 0;
                                            i < _orderedPlayerIds.length;
                                            i++)
                                          _orderedPlayerIds[i]: i + 1,
                                      };
                                      currentPlayerIds =
                                          List.from(_orderedPlayerIds);
                                      playerScores = {};
                                      _totalScores = {
                                        for (final id in currentPlayerIds) id: 0
                                      };
                                      _submittedScoreIndices = {};
                                      _failedPlayerIds = {};
                                      _currentWinnerId = '';
                                      _currentWinnerPrize = 0;
                                      _activeScoreIndex =
                                          currentPlayerIds.length > 4
                                              ? currentPlayerIds.length - 4
                                              : 0;

                                      // Өмнөх бүх мэдээллийг сэргээх (зөвхөн шинэ дарааллын биш)
                                      _winAmounts = Map<String, int>.from(
                                          preservedWinAmounts);
                                      _lossAmounts = Map<String, int>.from(
                                          preservedLossAmounts);
                                      _winStars = Map<String, int>.from(
                                          preservedWinStars);

                                      // Шинэ тоглогчдыг инициализ хийх
                                      for (final playerId in currentPlayerIds) {
                                        _winAmounts.putIfAbsent(
                                            playerId, () => 0);
                                        _lossAmounts.putIfAbsent(
                                            playerId, () => 0);
                                        _winStars.putIfAbsent(
                                            playerId, () => 0);
                                      }
                                    });
                                    Navigator.pop(context);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text(
                              'Тоглолт эхлүүл',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
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

  void _startNextRoundDirectly() {
    setState(() {
      // Өмнөх тоглолтын мэдээллийг хадгалах
      final preservedWinAmounts = Map<String, int>.from(_winAmounts);
      final preservedLossAmounts = Map<String, int>.from(_lossAmounts);
      final preservedWinStars = Map<String, int>.from(_winStars);

      // Тоглолтын төлөв цэвэрлэх
      playerScores = {};
      _totalScores = {for (final id in currentPlayerIds) id: 0};
      _submittedScoreIndices = {};
      _failedPlayerIds = {};
      _currentWinnerId = '';
      _currentWinnerPrize = 0;
      _activeScoreIndex =
          currentPlayerIds.length > 4 ? currentPlayerIds.length - 4 : 0;

      // Өмнөх бүх мэдээллийг сэргээх
      _winAmounts = Map<String, int>.from(preservedWinAmounts);
      _lossAmounts = Map<String, int>.from(preservedLossAmounts);
      _winStars = Map<String, int>.from(preservedWinStars);

      // Бүх тоглогчдыг инициализ хийх
      for (final playerId in currentPlayerIds) {
        _winAmounts.putIfAbsent(playerId, () => 0);
        _lossAmounts.putIfAbsent(playerId, () => 0);
        _winStars.putIfAbsent(playerId, () => 0);
      }
    });
  }

  List<int> _scoreOrderIndices(int totalPlayers) {
    if (totalPlayers <= 4) {
      return List.generate(totalPlayers, (i) => i);
    }
    return List.generate(totalPlayers - 3, (i) => i + 3);
  }

  Future<void> _showDundaaBoohDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade800,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Дундаа боох уу?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Бүх тоглогч тэнцэж байна',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            _isBooltMode = true;
                            _booltRoundNumber++;
                          });
                          // 2 тоглогч байхан дараалал сонгох цонхгүй шууд эхлүүлэх
                          if (currentPlayerIds.length == 2) {
                            _startNextRoundDirectly();
                          } else {
                            _showStartOrderSheet();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Дундаа боох',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            // Бүх накопилсан мэдээллийг цэвэрлэх - шинээр эхлүүлэх
                            playerScores = {};
                            _submittedScoreIndices = {};
                            _failedPlayerIds = {};
                            _totalScores = {
                              for (final id in currentPlayerIds) id: 0
                            };
                            _activeScoreIndex = currentPlayerIds.length > 4
                                ? currentPlayerIds.length - 4
                                : 0;
                            _gameRoundNumber = 1;
                            _booltRoundNumber = 0;
                            _isBooltMode = false;
                            _winAmounts = {};
                            _lossAmounts = {};
                            _winStars = {};
                            // Инициализ хийх
                            for (final id in currentPlayerIds) {
                              _winAmounts.putIfAbsent(id, () => 0);
                              _lossAmounts.putIfAbsent(id, () => 0);
                              _winStars.putIfAbsent(id, () => 0);
                            }
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Дахин тойрох',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBooltOrContinueDialog(
      List<QueryDocumentSnapshot> players) async {
    // Хожсон тоглогчдын нийт тоог шалгах
    final totalWinsAcrossPlayers =
        _winStars.values.fold<int>(0, (sum, wins) => sum + wins);
    final requiredRoundsBeforeBoolt = currentPlayerIds.length;
    final hasAnyLoss = _failedPlayerIds.isNotEmpty;
    final shouldShowBooltOption =
        totalWinsAcrossPlayers >= requiredRoundsBeforeBoolt || hasAnyLoss;

    // Бүх тоглогч ижил хожилттай эсэхийг шалгах (жишээ: 2 тоглогч, хоёулаа 1×1)
    final winCounts = currentPlayerIds.map((id) => _winStars[id] ?? 0).toList();
    final maxWins =
        winCounts.isEmpty ? 0 : winCounts.reduce((a, b) => a > b ? a : b);
    final minWins =
        winCounts.isEmpty ? 0 : winCounts.reduce((a, b) => a < b ? a : b);
    final allTied = maxWins == minWins && maxWins > 0;

    // Хожоогүй тоглогчдын нэрийг олох
    final nonFailedPlayers = players
        .where((player) => !_failedPlayerIds.contains(player.id))
        .map((player) => player['name'] as String? ?? 'Тоглогч')
        .toList();
    final nonFailedNames = nonFailedPlayers.join(', ');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade800,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  allTied
                      ? 'Дундаа боох уу?'
                      : _isBooltMode
                          ? '$nonFailedNames хожоогүй байна'
                          : shouldShowBooltOption
                              ? 'Боолт хийх уу?'
                              : 'Тоглолт үргэлжлүүлэх үү?',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  allTied
                      ? 'Бүх тоглогч тэнцсэн'
                      : nonFailedPlayers.length == 1
                          ? '$nonFailedNames хожоогүй байна'
                          : '$nonFailedNames хожоогүй байна',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                if (allTied)
                  // Бүх тоглогч тэнцсэн үед "Дундаа боох" товч
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            // Дундаа боох логик: Бүгд хожигдох
                            final moneyPerPlayer = _isBooltMode ? 10000 : 5000;
                            setState(() {
                              for (final id in currentPlayerIds) {
                                _lossAmounts[id] =
                                    (_lossAmounts[id] ?? 0) + moneyPerPlayer;
                              }
                              _isBooltMode = false;
                              _gameRoundNumber = 1;
                              _booltRoundNumber = 0;
                            });
                            // Дараагийн тоглолт эхлүүлэх
                            if (currentPlayerIds.length == 2) {
                              _startNextRoundDirectly();
                            } else {
                              _showStartOrderSheet();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Дундаа боох',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              // Шинэ тоглоом эхлүүлэх - Тоглолт№ 1-ээс эхлэх
                              _gameRoundNumber = 1;
                            });
                            // Дараагийн тоглолт эхлүүлэх
                            if (currentPlayerIds.length == 2) {
                              _startNextRoundDirectly();
                            } else {
                              _showStartOrderSheet();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Дахин тойрох',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (shouldShowBooltOption && !_isBooltMode)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _isBooltMode = true;
                              _booltRoundNumber++;
                            });
                            // 2 тоглогч байхан дараалал сонгох цонхгүй шууд эхлүүлэх
                            if (currentPlayerIds.length == 2) {
                              _startNextRoundDirectly();
                            } else {
                              _showStartOrderSheet();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Боолт хийх',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              // Шинэ тоглоом эхлүүлэх - Тоглолт№ 1-ээс эхлэх
                              _gameRoundNumber = 1;
                            });
                            // Дараагийн тоглолт эхлүүлэх
                            if (currentPlayerIds.length == 2) {
                              _startNextRoundDirectly();
                            } else {
                              _showStartOrderSheet();
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Дахин тойрох',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else if (_isBooltMode)
                  // Боолт горимд байхад зөвхөн "Дараагийн тоглолт" товч
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // Дараагийн боолт тоглолт эхлүүлэх
                      if (currentPlayerIds.length == 2) {
                        _startNextRoundDirectly();
                      } else {
                        _showStartOrderSheet();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Дараагийн тоглолт',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        playerScores = {};
                        _submittedScoreIndices = {};
                        _activeScoreIndex =
                            _firstActiveScoreIndex(currentPlayerIds);
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Дахин тойрох',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<String>> _showTieOrderDialog(
    String title,
    List<String> tiedIds,
  ) async {
    final selectedOrder = <String>[];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 20,
              ),
              child: Container(
                padding: const EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '${selectedOrder.length}/${tiedIds.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .where(FieldPath.documentId,
                              whereIn: tiedIds.isEmpty ? [''] : tiedIds)
                          .snapshots()
                          .distinct((prev, next) {
                            if (prev.docs.length != next.docs.length) return false;
                            for (int i = 0; i < prev.docs.length; i++) {
                              if (prev.docs[i].id != next.docs[i].id) return false;
                            }
                            return true;
                          }),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docsById = {
                          for (final doc in snapshot.data!.docs) doc.id: doc
                        };
                        final orderedDocs = tiedIds
                            .where((id) => docsById.containsKey(id))
                            .map((id) => docsById[id]!)
                            .toList();

                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 4,
                          runSpacing: 4,
                          children: orderedDocs.map((player) {
                            final data =
                                player.data() as Map<String, dynamic>;
                            final displayName = data['displayName'] ??
                                data['username'] ??
                                'Хэрэглэгч';
                            final photoUrl = data['photoUrl'];
                            final orderIndex =
                                selectedOrder.indexOf(player.id);

                            return SizedBox(
                              width: 65,
                              child: GestureDetector(
                                onTap: () {
                                  setStateModal(() {
                                    if (orderIndex != -1) {
                                      selectedOrder.remove(player.id);
                                    } else if (selectedOrder.length <
                                        tiedIds.length) {
                                      selectedOrder.add(player.id);
                                    }
                                  });
                                },
                                child: Stack(
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                          color: orderIndex != -1
                                              ? Colors.amber
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          RepaintBoundary(
                                            child: CircleAvatar(
                                              radius: 16,
                                              backgroundColor:
                                                  Colors.grey[300],
                                              backgroundImage: photoUrl !=
                                                          null &&
                                                      photoUrl.isNotEmpty
                                                  ? (photoUrl.startsWith(
                                                          'http')
                                                      ? NetworkImage(photoUrl)
                                                      : AssetImage(
                                                              'assets/$photoUrl')
                                                          as ImageProvider)
                                                  : null,
                                            child: photoUrl == null ||
                                                    photoUrl.isEmpty
                                                ? const Icon(Icons.person,
                                                    size: 14)
                                                : null,
                                          ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (orderIndex != -1)
                                      Positioned(
                                        right: 3,
                                        top: 3,
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: const BoxDecoration(
                                            color: Colors.amber,
                                            shape: BoxShape.circle,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${orderIndex + 1}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setStateModal(() {
                                selectedOrder.clear();
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white70),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text(
                              'Цэвэрлэх',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedOrder.length == tiedIds.length
                                ? () {
                                    Navigator.pop(context);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text(
                              'Дуусгах',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
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

    return selectedOrder.isEmpty ? tiedIds : selectedOrder;
  }

  Future<void> _finalizeRound(
    List<QueryDocumentSnapshot> players,
    List<int> scoreOrderIndices,
  ) async {
    if (players.length <= 4) return;

    final activeIds =
        scoreOrderIndices.map((i) => players[i].id).toList(growable: false);
    final scoreMap = <String, int>{};

    for (final index in scoreOrderIndices) {
      final raw = playerScores[index] ?? '0';
      final parsed = int.tryParse(raw.trim()) ?? 0;
      scoreMap[players[index].id] = parsed;
    }

    activeIds.sort((a, b) {
      final scoreA = scoreMap[a] ?? 0;
      final scoreB = scoreMap[b] ?? 0;
      return scoreA.compareTo(scoreB);
    });

    // Bench байгаа үед л тэнцүү онооны дарааллаа сонгох цонх гарч ирнэ
    // ГЭХДЭЭ bench нь бүгд хожигдсон бол цонх гарах шаардлагагүй
    final benchCount =
        currentPlayerIds.length > 4 ? currentPlayerIds.length - 4 : 0;
    final benchIds = currentPlayerIds.take(benchCount).toList();
    final hasActiveBench = benchIds.any((id) => !_failedPlayerIds.contains(id));

    if (hasActiveBench) {
      int i = 0;
      while (i < activeIds.length) {
        final score = scoreMap[activeIds[i]] ?? 0;
        int j = i + 1;
        while (j < activeIds.length && scoreMap[activeIds[j]] == score) {
          j++;
        }

        final groupSize = j - i;
        if (groupSize > 1 && score > 0) {
          final tiedIds = activeIds.sublist(i, j);
          final resolved = await _showTieOrderDialog(
            'Тэнцүү оноо - дараалал сонгох',
            tiedIds,
          );
          for (int k = 0; k < groupSize; k++) {
            activeIds[i + k] = resolved[k];
          }
        }

        i = j;
      }
    }

    final lowestIds = List<String>.from(activeIds);
    final newOrder = List<String>.from(currentPlayerIds);

    // хожигдоогүй bench тоглогчдыг л орүүл
    int benchIndex = 0;
    int activeIndex = 0;
    final incomingBenchPlayers = <String>[];
    for (int k = 0;
        k < benchCount &&
            benchIndex < benchIds.length &&
            activeIndex < lowestIds.length;
        k++) {
      final incomingId = benchIds[k];
      // хожигдсон бол skip
      if (_failedPlayerIds.contains(incomingId)) {
        continue;
      }
      final outgoingId = lowestIds[activeIndex++];
      final outgoingPos = newOrder.indexOf(outgoingId);
      if (outgoingPos != -1) {
        newOrder[outgoingPos] = incomingId;
      }
      newOrder[k] = outgoingId;
      incomingBenchPlayers.add(incomingId);
    }

    // Хожигдсон тоглогчдыг bench-д шилжүүлэх
    if (benchCount > 0) {
      final activeBenchSize = currentPlayerIds.length - 4;
      final failedInActive = currentPlayerIds
          .sublist(activeBenchSize)
          .where((id) => _failedPlayerIds.contains(id))
          .toList();

      for (int i = 0; i < failedInActive.length; i++) {
        final failedId = failedInActive[i];
        final activePos = newOrder.indexOf(failedId);
        if (activePos != -1) {
          newOrder.removeAt(activePos);
          final benchPos = i;
          if (benchPos < newOrder.length) {
            newOrder.insert(benchPos, failedId);
          } else {
            newOrder.add(failedId);
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        currentPlayerIds = newOrder;
        playerScores = {};
        _submittedScoreIndices = {};
        _activeScoreIndex = _firstActiveScoreIndex(newOrder);

        // Bench-д шилжүүлэх шинэ тоглогчдын мэдээлэл инициализ хийх
        for (final incomingId in incomingBenchPlayers) {
          _winAmounts.putIfAbsent(incomingId, () => 0);
          _lossAmounts.putIfAbsent(incomingId, () => 0);
          _winStars.putIfAbsent(incomingId, () => 0);
        }

        // Бүх тоглогчдын мэдээлэл инициализ хийх (аль ч төлөвт байх)
        for (final playerId in newOrder) {
          _winAmounts.putIfAbsent(playerId, () => 0);
          _lossAmounts.putIfAbsent(playerId, () => 0);
          _winStars.putIfAbsent(playerId, () => 0);
        }
      });

      // Хожигдоогүй тоглогчдын тоог тоолох
      final nonFailedCount =
          currentPlayerIds.where((id) => !_failedPlayerIds.contains(id)).length;

      // Нэг л тоглогч үлдсэн бол хожсон гэж тэмдэглэх
      if (nonFailedCount == 1) {
        final winnerId = currentPlayerIds.firstWhere(
          (id) => !_failedPlayerIds.contains(id),
          orElse: () => '',
        );

        if (winnerId.isNotEmpty) {
          final moneyPerPlayer = _isBooltMode ? 10000 : 5000;
          final totalPrize = _failedPlayerIds.length * moneyPerPlayer;

          setState(() {
            _currentWinnerId = winnerId;
            _currentWinnerPrize = totalPrize;
            _winAmounts[winnerId] = (_winAmounts[winnerId] ?? 0) + totalPrize;
            _winStars[winnerId] = (_winStars[winnerId] ?? 0) + 1;

            // Хожигдсон бүх тоглогчдын алдах мөнгө нэмэх
            for (final loserId in _failedPlayerIds) {
              _lossAmounts[loserId] =
                  (_lossAmounts[loserId] ?? 0) + moneyPerPlayer;
            }

            // Боолт горимыг цэвэрлэх
            _isBooltMode = false;
            _booltRoundNumber = 0;
            _gameRoundNumber++; // Дараагийн тоглолтын дугаарыг нэмэгдүүлэх
          });

          // Bench тоглогч байхгүй бол (2-4 тоглогч) шууд дараагийн тоглолт эхлүүлэх
          final hasBench = currentPlayerIds.length > 4;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (hasBench) {
              _showStartOrderSheet();
            } else {
              _startNextRoundDirectly();
            }
          });
        }
      } else if (nonFailedCount >= 2) {
        // 2+ тоглогч хожигдоогүй бол Боолт эсвэл Дахин тойрох сонголт өгөх
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showBooltOrContinueDialog(players);
        });
      }
    }
  }

  int _firstActiveScoreIndex(List<String> order) {
    final start = order.length > 4 ? order.length - 4 : 0;
    for (int i = start; i < order.length; i++) {
      if (!_failedPlayerIds.contains(order[i])) {
        return i;
      }
    }
    return start;
  }

  int _applyScoreMultiplier(int score) {
    if (score >= 1 && score <= 9) {
      return score; // 1x
    } else if (score >= 10 && score <= 12) {
      return score * 2; // 2x
    } else if (score == 13) {
      return score * 3; // 3x
    }
    return score;
  }

  void _moveBenchedPlayer(String playerId) {
    // 4+ тоглогч байвал л bench-д шилжүүлнэ
    if (currentPlayerIds.length <= 4) return;

    final oldOrder = List<String>.from(currentPlayerIds);
    final scoreById = <String, String>{};
    for (int i = 0; i < oldOrder.length; i++) {
      if (playerScores.containsKey(i)) {
        scoreById[oldOrder[i]] = playerScores[i] ?? '';
      }
    }

    final benchSize = currentPlayerIds.length - 4;
    final playerIdx = currentPlayerIds.indexOf(playerId);

    // Хожигдсон тоглогчийг идэвхтэй сонгосны сүүлийн цэгээс bench-д шилжүүлэх
    if (playerIdx >= benchSize) {
      currentPlayerIds.removeAt(playerIdx);
      final newBenchSize = currentPlayerIds.length - 4;
      currentPlayerIds.insert(newBenchSize, playerId);
    }

    final newScores = <int, String>{};
    for (int i = 0; i < currentPlayerIds.length; i++) {
      final id = currentPlayerIds[i];
      final score = scoreById[id];
      if (score != null && score.isNotEmpty) {
        newScores[i] = score;
      }
    }
    playerScores = newScores;

    final newSubmitted = <int>{};
    for (int i = 0; i < currentPlayerIds.length; i++) {
      final id = currentPlayerIds[i];
      final oldIndex = oldOrder.indexOf(id);
      if (oldIndex != -1 && _submittedScoreIndices.contains(oldIndex)) {
        newSubmitted.add(i);
      }
    }
    _submittedScoreIndices = newSubmitted;
  }

  Future<void> _handleScoreSubmit(
    int actualIndex,
    List<int> scoreOrderIndices,
    List<QueryDocumentSnapshot> players,
  ) async {
    final position = scoreOrderIndices.indexOf(actualIndex);
    if (position == -1) return;

    final playerId = players[actualIndex].id;
    final raw = playerScores[actualIndex] ?? '0';
    final parsed = int.tryParse(raw.trim()) ?? 0;

    final isFirstSubmit = !_submittedScoreIndices.contains(actualIndex);

    setState(() {
      final multipliedScore = _applyScoreMultiplier(parsed);
      final newTotal = (_totalScores[playerId] ?? 0) + multipliedScore;
      _totalScores[playerId] = newTotal;

      if (isFirstSubmit) {
        _submittedScoreIndices.add(actualIndex);
        final failThreshold = _isBooltMode ? 30 : 25;
        final moneyPerPlayer = _isBooltMode ? 10000 : 5000;
        if (newTotal >= failThreshold && !_failedPlayerIds.contains(playerId)) {
          _failedPlayerIds.add(playerId);
          _lossAmounts[playerId] =
              (_lossAmounts[playerId] ?? 0) + moneyPerPlayer;
        }
      }
    });

    if (position < scoreOrderIndices.length - 1) {
      setState(() {
        // Дараагийн хожигдоогүй тоглогч руу очих
        int nextPos = position + 1;
        while (nextPos < scoreOrderIndices.length) {
          final nextIndex = scoreOrderIndices[nextPos];
          final nextPlayerId = players[nextIndex].id;
          if (!_failedPlayerIds.contains(nextPlayerId)) {
            _activeScoreIndex = nextIndex;
            break;
          }
          nextPos++;
        }
        // Хэрвээ бүгд хожигдсон бол эхний хожигдоогүй рүү буцах
        if (nextPos >= scoreOrderIndices.length) {
          for (final idx in scoreOrderIndices) {
            if (!_failedPlayerIds.contains(players[idx].id)) {
              _activeScoreIndex = idx;
              break;
            }
          }
        }
      });
      return;
    }

    // Зөвхөн эхний удаа оноо оруулж дуусгах үед winner шалгах
    if (!isFirstSubmit) {
      return; // Оноо засч байгаа бол winner шалгах хэрэггүй
    }

    // 2-4 тоглогч: Bench байхгүй тул шууд winner шалгах
    if (players.length <= 4) {
      // Хожигдоогүй тоглогчдын тоог тоолох
      final nonFailedCount =
          currentPlayerIds.where((id) => !_failedPlayerIds.contains(id)).length;

      // Нэг л тоглогч үлдсэн бол
      if (nonFailedCount == 1) {
        final winnerId = currentPlayerIds.firstWhere(
          (id) => !_failedPlayerIds.contains(id),
          orElse: () => '',
        );

        if (winnerId.isNotEmpty) {
          final moneyPerPlayer = _isBooltMode ? 10000 : 5000;
          final totalPrize = _failedPlayerIds.length * moneyPerPlayer;

          // Хангалттай тоглолт дүүрсэн эсэхийг _winStars нэмэгдэхээс ӨМНӨ шалгах
          final totalWinsAcrossPlayers =
              _winStars.values.fold<int>(0, (sum, wins) => sum + wins);
          final requiredRoundsBeforeAsking = currentPlayerIds.length;
          final hasAnyLoss = _failedPlayerIds.isNotEmpty;
          final willHaveEnoughRounds =
              (totalWinsAcrossPlayers + 1) >= requiredRoundsBeforeAsking;
          final shouldAskBoolt = willHaveEnoughRounds || hasAnyLoss;

          setState(() {
            _currentWinnerId = winnerId;
            _currentWinnerPrize = totalPrize;
            _winAmounts[winnerId] = (_winAmounts[winnerId] ?? 0) + totalPrize;
            _winStars[winnerId] = (_winStars[winnerId] ?? 0) + 1;

            // Хожигдсон бүх тоглогчдын алдах мөнгө нэмэх (аль хэдийн _handleScoreSubmit дээр хийгдсэн)

            // Боолт горимд байхгүй үед боолт горимыг цэвэрлэх
            if (!_isBooltMode) {
              // Энгийн горимд байвал цэвэрлэхгүй (аль хэдийн энгийн горим)
            } else {
              // Боолт горимд байвал цэвэрлэх (боолт дүүрсэн гэсэн үг)
              _isBooltMode = false;
              _booltRoundNumber = 0;
            }

            // Хангалттай тоглолт дүүрээгүй бол л _gameRoundNumber нэмэгдүүлэх
            if (!willHaveEnoughRounds) {
              _gameRoundNumber++;
            }
          });

          // Хангалттай тоглолт дүүрсэн бол Боолт хийх эсэхийг асуух
          if (shouldAskBoolt) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showBooltOrContinueDialog(players);
            });
          } else {
            // Шууд дараагийн тоглолт эхлүүлэх
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _startNextRoundDirectly();
            });
          }
        }
      } else if (nonFailedCount >= 2) {
        // 2+ тоглогч хожигдоогүй байвал шалгаж асуух
        // Хожсон тоглогчдын нийт тоог шалгах (идэвхтэй тоглогчийн тоотой тэнцэх үед л асуух)
        final totalWinsAcrossPlayers =
            _winStars.values.fold<int>(0, (sum, wins) => sum + wins);
        final requiredRoundsBeforeAsking = currentPlayerIds.length;

        // Боолт горимд байхад диалог гаргахгүй
        final hasAnyLoss = _failedPlayerIds.isNotEmpty;
        if ((totalWinsAcrossPlayers >= requiredRoundsBeforeAsking ||
                hasAnyLoss) &&
            !_isBooltMode) {
          // Хангалттай тоглолт дүүрсэн тул сонголт өгөх
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showBooltOrContinueDialog(players);
          });
        } else {
          // Дахин тойрох (асуухгүй) - оноонуудыг цэвэрлэх
          // _totalScores хадгалагдсаар байна (хожигдох хүртэл хуримтлагдана)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              playerScores = {};
              _submittedScoreIndices = {};
              _activeScoreIndex = scoreOrderIndices.first;
            });
          });
        }
      } else {
        // Бүх тоглогч хожигдсон бол зүгээр цэвэрлэх
        setState(() {
          playerScores = {};
          _submittedScoreIndices = {};
          _activeScoreIndex = scoreOrderIndices.first;
        });
      }
      return;
    }

    await _finalizeRound(players, scoreOrderIndices);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final gameOptions = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      'БООЛТ1',
      'БООЛТ2',
      'БООЛТ3',
      'БООЛТ4',
      'БООЛТ5',
      'БООЛТ6'
    ];

    int currentGameIndex = gameOptions.indexOf(selectedGame);
    if (currentGameIndex == -1) currentGameIndex = 0;

    return Scaffold(
      backgroundColor: Colors.blue,
      appBar: AppBar(
        backgroundColor: Colors.blue,
        toolbarHeight: 65,
        leadingWidth: 130,
        leading: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Тоглогч',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _addPlayers,
                  child: const Icon(Icons.add, size: 24),
                ),
              ),
              const SizedBox(width: 2),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _removePlayers,
                  child: const Icon(Icons.remove, size: 24),
                ),
              ),
            ],
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '13 модны покер',
              style: TextStyle(fontSize: screenWidth < 380 ? 18 : 22),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ширээний №: 1',
                  style: TextStyle(fontSize: screenWidth < 380 ? 11 : 13),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isBooltMode ? 'Боолтын №:' : 'Тоглолтын №:',
                  style: TextStyle(fontSize: screenWidth < 380 ? 11 : 13, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Text(
                  _isBooltMode
                      ? _booltRoundNumber.toString()
                      : _gameRoundNumber.toString(),
                  style: TextStyle(
                      fontSize: screenWidth < 380 ? 11 : 13,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      // Settings logic
                    },
                    child: const Icon(Icons.settings, size: 20),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            label: const Text('Буцах', style: TextStyle(color: Colors.white, fontSize: 14)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId,
                  whereIn: currentPlayerIds.isEmpty ? [''] : currentPlayerIds)
              .snapshots()
              .distinct((prev, next) {
                // Only rebuild if document IDs or data actually changed
                if (prev.docs.length != next.docs.length) return false;
                for (int i = 0; i < prev.docs.length; i++) {
                  if (prev.docs[i].id != next.docs[i].id) return false;
                  final prevData = prev.docs[i].data() as Map<String, dynamic>;
                  final nextData = next.docs[i].data() as Map<String, dynamic>;
                  if (prevData['displayName'] != nextData['displayName'] ||
                      prevData['username'] != nextData['username'] ||
                      prevData['photoUrl'] != nextData['photoUrl']) {
                    return false;
                  }
                }
                return true; // Data is the same, skip rebuild
              }),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Алдаа: ${snapshot.error}'),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text('Тоглогч олдсонгүй'),
              );
            }

            final playersById = {
              for (final doc in snapshot.data!.docs) doc.id: doc
            };
            final players = currentPlayerIds
                .where((id) => playersById.containsKey(id))
                .map((id) => playersById[id]!)
                .toList();
            final scoreOrderIndices = _scoreOrderIndices(players.length);
            final effectiveActiveIndex = scoreOrderIndices
                    .contains(_activeScoreIndex)
                ? _activeScoreIndex
                : (scoreOrderIndices.isNotEmpty ? scoreOrderIndices.first : -1);

            // For 1-4 players: show in grid layout (2 columns for iOS)
            if (players.length <= 4) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.builder(
                  cacheExtent: 500,
                  addAutomaticKeepAlives: true,
                  addRepaintBoundaries: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: screenWidth < 380 ? 2 : 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    final data = player.data() as Map<String, dynamic>;
                    final displayName =
                        data['displayName'] ?? data['username'] ?? 'Хэрэглэгч';
                    final photoUrl = data['photoUrl'];
                    final actualIndex = index;

                    return RepaintBoundary(
                      child: Card(
                        key: ValueKey(player.id),
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.blue.shade700,
                                Colors.blue.shade400,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _failedPlayerIds.contains(player.id)
                                  ? Colors.red
                                  : Colors.green.shade400,
                              width: _failedPlayerIds.contains(player.id) ? 3 : 2,
                            ),
                          ),
                          child: PlayerScoreCardIOS(
                          playerIndex: actualIndex,
                          totalPlayers: players.length,
                          displayName: displayName,
                          photoUrl: photoUrl,
                          score: playerScores[actualIndex] ?? '',
                          totalScore: _totalScores[player.id] ?? 0,
                          autoFocus: actualIndex == effectiveActiveIndex &&
                              !_failedPlayerIds.contains(player.id),
                          isFailed: _failedPlayerIds.contains(player.id),
                          winAmount: _winAmounts[player.id] ?? 0,
                          lossAmount: _lossAmounts[player.id] ?? 0,
                          winStars: _winStars[player.id] ?? 0,
                          onScoreChanged: (score) {
                            setState(() {
                              playerScores[actualIndex] = score;
                            });
                          },
                          onSubmit: () => _handleScoreSubmit(
                            actualIndex,
                            scoreOrderIndices,
                            players,
                          ),
                          onPrevious: _previousPlayer,
                        ),
                      ),
                      ),
                    );
                  },
                ),
              );
            }

            // For 5+ players: keep 4 active (large) and the rest on bench (small)
            final benchCount = players.length > 4 ? players.length - 4 : 0;
            final largePlayers = players.sublist(benchCount);
            final smallPlayers =
                benchCount > 0 ? players.sublist(0, benchCount) : [];

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Top: Players 4-7 in grid (2 columns for iOS)
                  Expanded(
                    child: GridView.builder(
                      cacheExtent: 300,
                      addAutomaticKeepAlives: true,
                      addRepaintBoundaries: true,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.66,
                      ),
                      itemCount: largePlayers.length,
                      itemBuilder: (context, index) {
                        final player = largePlayers[index];
                        final data = player.data() as Map<String, dynamic>;
                        final displayName = data['displayName'] ??
                            data['username'] ??
                            'Хэрэглэгч';
                        final photoUrl = data['photoUrl'];
                        final actualIndex = players.indexOf(player);

                        return RepaintBoundary(
                          child: Card(
                            key: ValueKey(player.id),
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.blue.shade700,
                                    Colors.blue.shade400,
                                  ],
                                ),
                                border: Border.all(
                                  color: _failedPlayerIds.contains(player.id)
                                      ? Colors.red
                                      : Colors.green.shade400,
                                  width: _failedPlayerIds.contains(player.id)
                                      ? 3
                                      : 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: PlayerScoreCardIOS(
                                playerIndex: actualIndex,
                                totalPlayers: players.length,
                                displayName: displayName,
                                photoUrl: photoUrl,
                                score: playerScores[actualIndex] ?? '',
                                totalScore: _totalScores[player.id] ?? 0,
                                autoFocus:
                                    actualIndex == effectiveActiveIndex &&
                                        !_failedPlayerIds.contains(player.id),
                                isFailed: _failedPlayerIds.contains(player.id),
                                winAmount: _winAmounts[player.id] ?? 0,
                                lossAmount: _lossAmounts[player.id] ?? 0,
                                winStars: _winStars[player.id] ?? 0,
                                onScoreChanged: (score) {
                                  setState(() {
                                    playerScores[actualIndex] = score;
                                  });
                                },
                                onSubmit: () => _handleScoreSubmit(
                                  actualIndex,
                                  scoreOrderIndices,
                                  players,
                                ),
                                onPrevious: _previousPlayer,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (smallPlayers.isNotEmpty) const SizedBox(height: 10),
                  // Bottom: Players 1-3 in 3 columns (square blocks)
                  if (smallPlayers.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 8.0;
                        final blockSize = (constraints.maxWidth - spacing * 2) / 3;
                        final benchPlayers =
                            smallPlayers.take(3).toList().asMap().entries;

                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: spacing,
                            crossAxisSpacing: spacing,
                            childAspectRatio: 1.1,
                          ),
                          itemCount: benchPlayers.length,
                          itemBuilder: (context, index) {
                            final entry =
                                benchPlayers.elementAt(index);
                            final player = entry.value;
                            final data = player.data() as Map<String, dynamic>;
                            final displayName = data['displayName'] ??
                                data['username'] ??
                                'Хэрэглэгч';
                            final username = data['username'] ?? '';
                            final totalScore =
                                (_totalScores[player.id] ?? 0).toString();
                            final stars =
                                (_winStars[player.id] ?? 0).toString();

                            final isFailed =
                                _failedPlayerIds.contains(player.id);
                            final winAmount = _winAmounts[player.id] ?? 0;
                            final lossAmount = _lossAmounts[player.id] ?? 0;
                            final netAmount = winAmount - lossAmount;
                            final netMoney = netAmount.toString();
                            final actualIndex = players.indexOf(player);

                            return Stack(
                              children: [
                                // Main card
                                Card(
                                  elevation: 8,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.blue.shade700,
                                          Colors.blue.shade400,
                                        ],
                                      ),
                                      border: Border.all(
                                        color: isFailed
                                            ? Colors.red
                                            : Colors.amber.shade400,
                                        width: isFailed ? 3 : 2,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Top: Player name
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                displayName,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Middle: Score and stars
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              totalScore,
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isFailed
                                                    ? Colors.red
                                                    : Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              width: 3,
                                              height: 16,
                                              color: Colors.white30,
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.star,
                                              color: Colors.amber,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 2),
                                            Text(
                                              'x $stars',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Bottom: Money
                                        Text(
                                          netMoney,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: netAmount >= 0
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Number badge (top left)
                                Positioned(
                                  top: -8,
                                  left: -8,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade600,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${actualIndex + 1}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class PlayerScoreCardIOS extends StatefulWidget {
  final int playerIndex;
  final int totalPlayers;
  final String displayName;
  final String? photoUrl;
  final String score;
  final int totalScore;
  final bool autoFocus;
  final bool isFailed;
  final int winAmount;
  final int lossAmount;
  final int winStars;
  final Function(String) onScoreChanged;
  final VoidCallback onSubmit;
  final VoidCallback onPrevious;

  const PlayerScoreCardIOS({
    super.key,
    required this.playerIndex,
    required this.totalPlayers,
    required this.displayName,
    this.photoUrl,
    required this.score,
    required this.totalScore,
    required this.autoFocus,
    required this.isFailed,
    this.winAmount = 0,
    this.lossAmount = 0,
    this.winStars = 0,
    required this.onScoreChanged,
    required this.onSubmit,
    required this.onPrevious,
  });

  @override
  State<PlayerScoreCardIOS> createState() => _PlayerScoreCardIOSState();
}

class _PlayerScoreCardIOSState extends State<PlayerScoreCardIOS> 
    with AutomaticKeepAliveClientMixin {
  late TextEditingController _scoreController;
  late FocusNode _focusNode;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scoreController = TextEditingController(text: widget.score);
    _focusNode = FocusNode();

    // Add controller listener to always keep cursor at end
    _scoreController.addListener(() {
      final text = _scoreController.text;
      final selection = _scoreController.selection;

      // Only update if selection is not already at the end
      if (selection.baseOffset != text.length ||
          selection.extentOffset != text.length) {
        _scoreController.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
      }
    });

    // Add listener to prevent text selection on focus
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Always move cursor to end, never select all
        final text = _scoreController.text;
        _scoreController.selection = TextSelection.fromPosition(
          TextPosition(offset: text.length),
        );
      }
    });

    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(PlayerScoreCardIOS oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerIndex != widget.playerIndex) {
      _scoreController.text = widget.score;
      if (widget.autoFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      }
    } else if (!oldWidget.autoFocus && widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _showInvalidScoreDialog(BuildContext context, int score) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Буруу утга', style: TextStyle(fontSize: 16)),
          content:
              Text('Оноо 1-13 хүртэл байх ёстой. Та $score оруулсан байна.', style: const TextStyle(fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Clear the invalid input and refocus
                _scoreController.clear();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _focusNode.requestFocus();
                });
              },
              child: const Text('Зөв'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Must call for AutomaticKeepAliveClientMixin
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar - centered, sized to fit block
            LayoutBuilder(
              builder: (context, constraints) {
                final avatarSize = constraints.maxWidth * 0.68;
                return RepaintBoundary(
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child:
                          widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                              ? (widget.photoUrl!.startsWith('http')
                                  ? Image.network(
                                      widget.photoUrl!,
                                      fit: BoxFit.cover,
                                      cacheWidth: 200,
                                      cacheHeight: 200,
                                    )
                                  : Image.asset(
                                      'assets/${widget.photoUrl}',
                                      fit: BoxFit.cover,
                                      cacheWidth: 200,
                                      cacheHeight: 200,
                                    ))
                              : const Icon(Icons.person,
                                  size: 40, color: Colors.white),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            // Player name
            Text(
              widget.displayName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            // Win calculation (Хожил)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Хожил: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Icon(Icons.star, color: Colors.amber, size: 14),
                const SizedBox(width: 1),
                const Text(
                  '×',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 1),
                Text(
                  widget.winStars.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Two boxes in one row: Score input + Total score
            Row(
              children: [
                // Score input box
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Opacity(
                      opacity: widget.isFailed ? 0.5 : 1.0,
                      child: Column(
                        children: [
                          const Text(
                            'Оноо',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            height: 32,
                            child: TextField(
                              controller: _scoreController,
                              focusNode: _focusNode,
                              enabled: !widget.isFailed,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.3),
                                  fontSize: 18,
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 0),
                              ),
                              inputFormatters: [
                                LimitRangeTextInputFormatter(),
                              ],
                              onTap: () {
                                // Move cursor to end on tap to prevent text selection
                                final text = _scoreController.text;
                                _scoreController.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(offset: text.length),
                                );
                              },
                              onChanged: widget.onScoreChanged,
                              onSubmitted: (value) {
                                final normalized =
                                    value.trim().isEmpty ? '0' : value.trim();

                                // Validate score
                                if (normalized != '0') {
                                  try {
                                    final score = int.parse(normalized);
                                    if (score > 13) {
                                      _showInvalidScoreDialog(context, score);
                                      return;
                                    }
                                  } catch (e) {
                                    _showInvalidScoreDialog(context, 0);
                                    return;
                                  }
                                }

                                if (normalized != _scoreController.text) {
                                  _scoreController.text = normalized;
                                  _scoreController.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: normalized.length,
                                  );
                                }
                                widget.onScoreChanged(normalized);
                                widget.onSubmit();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Total score display box
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Opacity(
                      opacity: widget.isFailed ? 0.5 : 1.0,
                      child: Column(
                        children: [
                          const Text(
                            'Нийт',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Center(
                            child: Text(
                              widget.totalScore.toString(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
            const SizedBox(height: 8),
            // Win/Loss stats row (larger font)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Бооцоо: ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  (widget.winAmount - widget.lossAmount).toString(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: (widget.winAmount - widget.lossAmount) >= 0
                        ? Colors.green.shade300
                        : Colors.red.shade300,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Text input formatter to limit score input to 1-13 range
class LimitRangeTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allow empty input
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Only allow digits
    if (!RegExp(r'^[0-9]*$').hasMatch(newValue.text)) {
      return oldValue;
    }

    try {
      final value = int.parse(newValue.text);

      // Allow 0-13
      if (value <= 13) {
        return newValue;
      } else {
        // If number is > 13, reject it
        return oldValue;
      }
    } catch (e) {
      return oldValue;
    }
  }
}
