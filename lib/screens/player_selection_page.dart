import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'admin_dashboard.dart';
import 'playing_format.dart';
import '../utils/active_tables_repository.dart';

class PlayerSelectionPage extends StatefulWidget {
  const PlayerSelectionPage({
    super.key,
    this.isAdmin = false,
    this.excludedUserIds = const [],
    this.isAddingMode = false,
    this.currentUserId,
    this.canManageGames = false,
    this.resetOwnedActiveTablesOnOpen = false,
  });

  final bool isAdmin;
  final List<String> excludedUserIds;
  final bool isAddingMode;
  final String? currentUserId;
  final bool canManageGames;
  final bool resetOwnedActiveTablesOnOpen;

  @override
  State<PlayerSelectionPage> createState() => _PlayerSelectionPageState();
}

class _PlayerSelectionPageState extends State<PlayerSelectionPage> {
  final Set<String> _selectedUsers = {};
  final ActiveTablesRepository _activeTablesRepo = ActiveTablesRepository();
  late final Stream<QuerySnapshot> _usersStream;
  late final Stream<Set<String>> _activePlayerUserIdsStream;
  final ScrollController _usersGridScrollController = ScrollController();
  bool _initialCleanupDone = false;

  @override
  void initState() {
    super.initState();
    // Keep a stable stream instance so selection rebuilds don't recreate it
    // and reset the grid scroll position.
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots();
    _activePlayerUserIdsStream = _activeTablesRepo.watchActivePlayerUserIds();
    _runInitialActiveTableCleanup();
  }

  Future<void> _runInitialActiveTableCleanup() async {
    if (!widget.resetOwnedActiveTablesOnOpen || widget.isAddingMode) {
      if (mounted) {
        setState(() => _initialCleanupDone = true);
      }
      return;
    }

    try {
      // Fresh login entry: clear all active locks so stale unsaved sessions
      // do not keep players disabled after restart/redeploy.
      await _activeTablesRepo.releaseAllActiveTableLocks();
    } catch (_) {
      // Ignore cleanup failures and let selection still open.
    }

    if (mounted) {
      setState(() => _initialCleanupDone = true);
    }
  }

  @override
  void dispose() {
    _usersGridScrollController.dispose();
    super.dispose();
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUsers.contains(userId)) {
        _selectedUsers.remove(userId);
      } else {
        if (_selectedUsers.length < 14) {
          _selectedUsers.add(userId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Максимум 14 хэрэглэгч сонгож болно')),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Буцах',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Image.asset(
            'assets/buttons/back.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        ),
        title: const Text("Хэрэглэгчид"),
        elevation: 0,
        actions: [
          if (widget.isAdmin)
            IconButton(
              iconSize: 34,
              icon: Image.asset(
                'assets/buttons/edit.png',
                width: 34,
                height: 34,
                fit: BoxFit.contain,
              ),
              tooltip: 'Засах',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminDashboard(),
                  ),
                );
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Сонгогдсон: ${_selectedUsers.length}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: (widget.isAddingMode
                          ? _selectedUsers.isNotEmpty
                          : _selectedUsers.length >= 2)
                      ? () {
                          if (widget.isAddingMode) {
                            // Нэмэх горимд - буцаад өгөх
                            Navigator.pop(context, _selectedUsers.toList());
                          } else {
                            // Энгийн горимд - PlayingFormatPage рүү явах
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PlayingFormatPage(
                                  selectedUserIds: _selectedUsers.toList(),
                                  currentUserId: widget.currentUserId,
                                  canManageGames: widget.canManageGames,
                                ),
                              ),
                            );
                          }
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow, color: Colors.black),
                  label: const Text(
                    'Ширээнд урих',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 10,
                    ),
                    backgroundColor: Colors.yellow,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Firebase.apps.isEmpty
          ? const Center(
              child: Text('Firebase эхлүүлэгдээгүй байна.'),
            )
          : !_initialCleanupDone
              ? const Center(child: CircularProgressIndicator())
              : StreamBuilder<Set<String>>(
                  stream: _activePlayerUserIdsStream,
                  builder: (context, activeSnapshot) {
                    final lockedUserIds =
                        activeSnapshot.data ?? const <String>{};
                    return StreamBuilder<QuerySnapshot>(
                      stream: _usersStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Алдаа: ${snapshot.error}'),
                          );
                        }

                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline,
                                    size: 80, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'Хэрэглэгч олдсонгүй',
                                  style: TextStyle(
                                      fontSize: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }

                        final users = snapshot.data!.docs;

                        return GridView.builder(
                          key: const PageStorageKey<String>(
                              'player_selection_grid'),
                          controller: _usersGridScrollController,
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 0.65,
                          ),
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final data = user.data() as Map<String, dynamic>;
                            final username = data['username'] ?? '';
                            final displayName = data['displayName'] ?? username;
                            final photoUrl = data['photoUrl'];
                            final userId = user.id;
                            final isSelected = _selectedUsers.contains(userId);
                            final isExcluded =
                                widget.excludedUserIds.contains(userId);
                            final isLocked = lockedUserIds.contains(userId);
                            final isDisabled = isExcluded || isLocked;

                            return GestureDetector(
                              onTap: isDisabled
                                  ? null
                                  : () => _toggleSelection(userId),
                              child: Opacity(
                                opacity: isDisabled ? 0.3 : 1.0,
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
                                            : isDisabled
                                                ? Border.all(
                                                    color: Colors.grey,
                                                    width: 2,
                                                  )
                                                : null,
                                        borderRadius:
                                            BorderRadius.circular(200),
                                      ),
                                      child: CircleAvatar(
                                        radius: 140,
                                        backgroundColor: Colors.deepPurple[100],
                                        backgroundImage: photoUrl != null &&
                                                photoUrl.isNotEmpty
                                            ? (photoUrl.startsWith('http')
                                                ? NetworkImage(photoUrl)
                                                : AssetImage('assets/$photoUrl')
                                                    as ImageProvider)
                                            : null,
                                        child:
                                            photoUrl == null || photoUrl.isEmpty
                                                ? const Icon(Icons.person,
                                                    size: 50,
                                                    color: Colors.deepPurple)
                                                : null,
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
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    if (isDisabled && !isSelected)
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius:
                                                BorderRadius.circular(50),
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          child: const Icon(
                                            Icons.block,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '@$username',
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
                        );
                      },
                    );
                  },
                ),
    );
  }
}
