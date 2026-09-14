import '../widgets/active_table_route_scope.dart';
import '../utils/saved_game_sessions_repository.dart';
import '../widgets/saved_game_prompt.dart';
import 'saved_game_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/active_table_route_registry.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'admin_dashboard.dart';
import 'playing_format.dart';
import '../utils/active_tables_repository.dart';
import '../utils/demo_players.dart';

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
  bool _demoMode = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _demoMode = widget.isAddingMode &&
        widget.excludedUserIds.any(DemoPlayers.isDemoId);
    // Keep a stable stream instance so selection rebuilds don't recreate it
    // and reset the grid scroll position.
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots();
    _activePlayerUserIdsStream = _activeTablesRepo.watchActivePlayerUserIds(
      currentOwnerUserId: widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid,
      isOpenInThisSession: (id) => ActiveTableRouteRegistry.contains('active-table:$id'),
    );
    _runInitialActiveTableCleanup();
  }

  Future<void> _runInitialActiveTableCleanup() async {
    try {
      if (!widget.isAddingMode) {
        final owner = widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
        if (owner != null && owner.isNotEmpty) {
          await _activeTablesRepo.closePreviousBrowserTables(owner);
        }
      }
      if (mounted) setState(() => _initialCleanupDone = true);
    } catch (error, stack) {
      debugPrint('Previous browser table cleanup failed: $error\n$stack');
      if (!mounted) return;
      final detail = error is FirebaseException
          ? '${error.plugin}/${error.code}'
          : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Өмнөх ширээг хааж чадсангүй: $detail'),
        action: SnackBarAction(label: 'Дахин оролдох', onPressed: _runInitialActiveTableCleanup),
      ));
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

  Future<void> _confirmPlayers() async {
    if (_confirming) return;
    final players = _selectedUsers.toList();
    if (widget.isAddingMode) {
      Navigator.pop(context, players);
      return;
    }
    setState(() => _confirming = true);
    try {
      var startFresh = false;
      final matches = await SavedGameSessionsRepository().findUnfinishedByPlayers(players);
      final supported = matches.where((s) => buildSavedGamePage(s) != null).toList();
      if (!mounted) return;
      if (supported.isNotEmpty) {
        final choice = await showSavedGamePrompt(context, supported);
        if (!mounted || choice == null) return;
        if (choice.isNotEmpty) {
          final saved = supported.firstWhere((s) => s.id == choice);
          final page = buildSavedGamePage(saved,
              currentUserId: widget.currentUserId, canManageGames: widget.canManageGames);
          if (saved.gameKey == 'multi_format') {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
          } else {
            final lockId = await _activeTablesRepo.createActiveTableLock(
              gameKey: saved.gameKey, gameName: saved.gameLabel,
              playerUserIds: saved.selectedUserIds, playingFormat: 'single',
              ownerUserId: widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid,
            );
            await _activeTablesRepo.updateSavedSessionId(lockId, saved.id);
            if (!mounted) return;
            final routeName = 'active-table:$lockId';
            await Navigator.push(context, MaterialPageRoute(
              settings: RouteSettings(name: routeName),
              builder: (_) => ActiveTableRouteScope(routeName: routeName, child: page!),
            ));
          }
          return;
        }
        startFresh = true;
      }
      await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayingFormatPage(
        selectedUserIds: players, currentUserId: widget.currentUserId,
        canManageGames: widget.canManageGames,
        createAdditionalTable: startFresh,
      )));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Хадгалсан тоглолтыг шалгаж чадсангүй. Дахин оролдоно уу.')));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
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
          IconButton(
            tooltip: _demoMode
                ? 'Бодит хэрэглэгчдийн жагсаалт'
                : 'Туршилтын 10 тоглогч',
            onPressed: () => setState(() {
              _demoMode = !_demoMode;
              _selectedUsers.clear();
            }),
            icon: Icon(_demoMode ? Icons.people : Icons.science),
          ),
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
                  onPressed: _initialCleanupDone && !_confirming && (widget.isAddingMode
                      ? _selectedUsers.isNotEmpty : _selectedUsers.length >= 2)
                      ? _confirmPlayers : null,
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
      body: _demoMode
          ? _buildDemoPlayersGrid()
          : Firebase.apps.isEmpty
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

                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
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
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: (MediaQuery.sizeOf(context).width / 180).floor().clamp(2, 7),
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.65,
                              ),
                              itemCount: users.length,
                              itemBuilder: (context, index) {
                                final user = users[index];
                                final data =
                                    user.data() as Map<String, dynamic>;
                                final username = data['username'] ?? '';
                                final displayName =
                                    data['displayName'] ?? username;
                                final photoUrl = data['photoUrl'];
                                final userId = user.id;
                                final isSelected =
                                    _selectedUsers.contains(userId);
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
                                            backgroundColor:
                                                Colors.deepPurple[100],
                                            backgroundImage: photoUrl != null &&
                                                    photoUrl.isNotEmpty
                                                ? (photoUrl.startsWith('http')
                                                    ? NetworkImage(photoUrl)
                                                    : AssetImage(
                                                            'assets/$photoUrl')
                                                        as ImageProvider)
                                                : null,
                                            child: photoUrl == null ||
                                                    photoUrl.isEmpty
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
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius:
                                                BorderRadius.circular(12),
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

  Widget _buildDemoPlayersGrid() {
    final available = DemoPlayers.all
        .where((player) => !widget.excludedUserIds.contains(player.id))
        .toList(growable: false);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (MediaQuery.sizeOf(context).width / 180).floor().clamp(2, 5),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: available.length + ((widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid) != null && !widget.excludedUserIds.contains(widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid) ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == available.length) {
          final uid = widget.currentUserId ?? FirebaseAuth.instance.currentUser!.uid;
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();
              if (data == null) return const Center(child: Text('Профайл ачаалж байна…'));
              final url = data['photoUrl'];
              final selected = _selectedUsers.contains(uid);
              return InkWell(
                onTap: () => _toggleSelection(uid),
                child: Card(
                  color: selected ? Colors.amber.shade100 : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: selected ? Colors.deepPurple : Colors.grey, width: selected ? 3 : 1)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    CircleAvatar(radius: 30,
                      backgroundImage: url is String && url.startsWith('https://') ? NetworkImage(url) : null,
                      child: url is String && url.startsWith('https://') ? null : const Icon(Icons.person)),
                    const SizedBox(height: 8),
                    Text('${data['nickname'] ?? data['firstName'] ?? 'Миний профайл'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${data['firstName'] ?? ''}'),
                    const Text('Миний бодит профайл'),
                  ]),
                ),
              );
            },
          );
        }
        final player = available[index];
        final selected = _selectedUsers.contains(player.id);
        return InkWell(
          onTap: () => _toggleSelection(player.id),
          borderRadius: BorderRadius.circular(16),
          child: Card(
            color: selected ? Colors.amber.shade100 : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: selected ? Colors.deepPurple : Colors.grey.shade300,
                width: selected ? 3 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.deepPurple.shade100,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    player.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  Text(player.fullName, textAlign: TextAlign.center),
                  Text('@${player.username}'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
