import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'admin_dashboard.dart';
import 'playing_format.dart';

class PlayerSelectionPage extends StatefulWidget {
  const PlayerSelectionPage({
    super.key,
    this.isAdmin = false,
    this.excludedUserIds = const [],
    this.isAddingMode = false,
  });

  final bool isAdmin;
  final List<String> excludedUserIds;
  final bool isAddingMode;

  @override
  State<PlayerSelectionPage> createState() => _PlayerSelectionPageState();
}

class _PlayerSelectionPageState extends State<PlayerSelectionPage> {
  final Set<String> _selectedUsers = {};

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUsers.contains(userId)) {
        _selectedUsers.remove(userId);
      } else {
        if (_selectedUsers.length < 7) {
          _selectedUsers.add(userId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Максимум 7 хэрэглэгч сонгож болно')),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Хэрэглэгчид"),
        elevation: 0,
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
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
          preferredSize: const Size.fromHeight(150),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Navigation buttons row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.home, size: 18),
                          label: const Text('Нүүр'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            backgroundColor: Colors.deepPurple[300],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.sports_esports, size: 18),
                          label: const Text('Тоглоомууд'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            backgroundColor: Colors.deepPurple[300],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.leaderboard, size: 18),
                          label: const Text('Ранк'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            backgroundColor: Colors.deepPurple[300],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Сонгогдсон: ${_selectedUsers.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _selectedUsers.isNotEmpty
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
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        backgroundColor: Colors.yellow,
                        disabledBackgroundColor: Colors.grey[300],
                      ),
                    ),
                  ],
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
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 80, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Хэрэглэгч олдсонгүй',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                final users = snapshot.data!.docs;

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0,
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
                    final isExcluded = widget.excludedUserIds.contains(userId);

                    return GestureDetector(
                      onTap: isExcluded ? null : () => _toggleSelection(userId),
                      child: Opacity(
                        opacity: isExcluded ? 0.4 : 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.yellow[200]
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.deepPurple
                                  : isExcluded
                                      ? Colors.grey[400]!
                                      : Colors.deepPurple[200]!,
                              width: isSelected ? 3 : 2,
                            ),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.deepPurple[100],
                                backgroundImage:
                                    photoUrl != null && photoUrl.isNotEmpty
                                        ? (photoUrl.startsWith('http')
                                            ? NetworkImage(photoUrl)
                                            : AssetImage('assets/$photoUrl')
                                                as ImageProvider)
                                        : null,
                                child: photoUrl == null || photoUrl.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 24, color: Colors.deepPurple)
                                    : null,
                              ),
                              if (isSelected)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(3),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
