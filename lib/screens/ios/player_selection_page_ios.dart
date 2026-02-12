import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../admin_dashboard.dart';
import 'playing_format_ios.dart';

class PlayerSelectionPageIOS extends StatefulWidget {
  const PlayerSelectionPageIOS({
    super.key,
    this.isAdmin = false,
    this.excludedUserIds = const [],
    this.isAddingMode = false,
  });

  final bool isAdmin;
  final List<String> excludedUserIds;
  final bool isAddingMode;

  @override
  State<PlayerSelectionPageIOS> createState() => _PlayerSelectionPageIOSState();
}

class _PlayerSelectionPageIOSState extends State<PlayerSelectionPageIOS> {
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
    final screenWidth = MediaQuery.of(context).size.width;
    // iPhone: 2-3 columns based on screen size
    final crossAxisCount = screenWidth < 400 ? 2 : 3;
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Хэрэглэгчид"),
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            label: const Text('Буцах', style: TextStyle(color: Colors.white, fontSize: 14)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
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
      ),
      body: Firebase.apps.isEmpty
          ? const Center(
              child: Text('Firebase эхлүүлэгдээгүй байна.'),
            )
          : Column(
              children: [
                // Header section with selection count and button
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
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
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _selectedUsers.isNotEmpty
                              ? () {
                                  if (widget.isAddingMode) {
                                    Navigator.pop(context, _selectedUsers.toList());
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PlayingFormatPageIOS(
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
                              horizontal: 20,
                              vertical: 8,
                            ),
                            backgroundColor: Colors.yellow,
                            disabledBackgroundColor: Colors.grey[300],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // User grid
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
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
                        padding: const EdgeInsets.all(12),
                        cacheExtent: 500,
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: true,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.75,
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
                            key: ValueKey(userId),
                            onTap: isExcluded ? null : () => _toggleSelection(userId),
                            child: Opacity(
                              opacity: isExcluded ? 0.3 : 1.0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        RepaintBoundary(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: isSelected
                                                  ? Border.all(
                                                      color: Colors.deepPurple,
                                                      width: 3,
                                                    )
                                                  : isExcluded
                                                      ? Border.all(
                                                          color: Colors.grey,
                                                          width: 2,
                                                        )
                                                      : null,
                                              shape: BoxShape.circle,
                                            ),
                                            child: CircleAvatar(
                                              radius: 50,
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
                                                      size: 35, color: Colors.deepPurple)
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.deepPurple,
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              child: const Icon(
                                                Icons.check,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        if (isExcluded)
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              child: const Icon(
                                                Icons.block,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontSize: 12,
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
                                            fontSize: 10,
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
                  ),
                ),
              ],
            ),
    );
  }
}
