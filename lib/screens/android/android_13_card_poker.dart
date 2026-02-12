import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Android optimized 13 Card Poker game screen
class Android13CardPokerPage extends StatefulWidget {
  const Android13CardPokerPage({super.key, required this.selectedUserIds});

  final List<String> selectedUserIds;

  @override
  State<Android13CardPokerPage> createState() => _Android13CardPokerPageState();
}

class _Android13CardPokerPageState extends State<Android13CardPokerPage> {
  late List<String> currentPlayerIds;
  final Map<String, int> _totalScores = {};
  int _currentPlayerIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    currentPlayerIds = List.from(widget.selectedUserIds);
    _pageController = PageController(initialPage: 0);
    _initScores();
  }

  void _initScores() {
    for (final id in currentPlayerIds) {
      _totalScores.putIfAbsent(id, () => 0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPlayer() {
    if (_currentPlayerIndex < currentPlayerIds.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPlayer() {
    if (_currentPlayerIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Гарах'),
            content: const Text('Тоглолтоос гарахдаа зөв үү?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Үгүй'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Тийм'),
              ),
            ],
          ),
        );
        if (confirm ?? false) {
          if (context.mounted) {
            Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('13 Карт Покер'),
          centerTitle: true,
          elevation: 2,
        ),
        body: Column(
          children: [
            // Player indicator and score display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.deepPurple[50],
              child: Column(
                children: [
                  Text(
                    'Сонгогдсон тоглогчид: ${currentPlayerIds.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        currentPlayerIds.length,
                        (index) => GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: index == _currentPlayerIndex
                                      ? Colors.deepPurple
                                      : Colors.grey[300],
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: index == _currentPlayerIndex
                                          ? Colors.white
                                          : Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_totalScores[currentPlayerIds[index]] ?? 0}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main game area - PageView for player rotation
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPlayerIndex = index;
                  });
                },
                children: List.generate(
                  currentPlayerIds.length,
                  (index) => _buildPlayerGameScreen(
                    currentPlayerIds[index],
                    index,
                  ),
                ),
              ),
            ),

            // Controls
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _previousPlayer,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Өмнөх'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _nextPlayer,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Дараах'),
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

  Widget _buildPlayerGameScreen(String playerId, int playerIndex) {
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('users').doc(playerId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final displayName = userData['displayName'] ?? 'Unknown';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Player info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundImage: userData['photoUrl'] != null
                            ? NetworkImage(userData['photoUrl'])
                            : null,
                        child: userData['photoUrl'] == null
                            ? const Icon(Icons.person, size: 40)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Нийт оноо: ${_totalScores[playerId] ?? 0}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.deepPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Game play section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Тоглолтын оноо нэмэх',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Score input area
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Оноо оруулах',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),

                      // Quick action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                // Add score action
                              },
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('Нэмэх'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                // Clear action
                              },
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: Colors.grey,
                              ),
                              child: const Text('Цэвэрлэх'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Game rules info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Дүрэм:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Максимум оноо: 130\n'
                      '• Тоглоом дугаарыг дахин сонгох боломжгүй\n'
                      '• Эхний буго: 13 карт\n'
                      '• Цаашдын буго: хожсон карт + 1',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
