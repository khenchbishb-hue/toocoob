import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../playing_format.dart';

/// Android optimized player selection with mobile-first UI
class AndroidPlayerSelectionPage extends StatefulWidget {
  const AndroidPlayerSelectionPage({
    super.key,
    this.isAdmin = false,
    this.excludedUserIds = const [],
    this.isAddingMode = false,
  });

  final bool isAdmin;
  final List<String> excludedUserIds;
  final bool isAddingMode;

  @override
  State<AndroidPlayerSelectionPage> createState() =>
      _AndroidPlayerSelectionPageState();
}

class _AndroidPlayerSelectionPageState
    extends State<AndroidPlayerSelectionPage> {
  final Set<String> _selectedUsers = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedUsers.contains(userId)) {
        _selectedUsers.remove(userId);
      } else {
        if (_selectedUsers.length < 7) {
          _selectedUsers.add(userId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Максимум 7 хэрэглэгч сонгож болно'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Хэрэглэгчид сонгох'),
        centerTitle: true,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Selected count and Play button row
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.deepPurple[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Сонгогдсон: ${_selectedUsers.length} / 7',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _selectedUsers.isNotEmpty
                      ? () {
                          if (widget.isAddingMode) {
                            Navigator.pop(context, _selectedUsers.toList());
                          } else {
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
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Ширээнд урих'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
              decoration: InputDecoration(
                hintText: 'Хэрэглэгч хайх...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Users list
          Expanded(
            child: Firebase.apps.isEmpty
                ? const Center(
                    child: Text('Firebase эхлүүлэгдээгүй байна.'),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Алдаа: ${snapshot.error}'),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final users = snapshot.data?.docs ?? [];
                      var filteredUsers = users.where((user) {
                        if (widget.excludedUserIds.contains(user.id)) {
                          return false;
                        }
                        if (_searchQuery.isEmpty) return true;

                        final data = user.data() as Map<String, dynamic>;
                        final name = (data['displayName'] ?? '')
                            .toString()
                            .toLowerCase();
                        final username =
                            (data['username'] ?? '').toString().toLowerCase();

                        return name.contains(_searchQuery) ||
                            username.contains(_searchQuery);
                      }).toList();

                      if (filteredUsers.isEmpty) {
                        return Center(
                          child: Text(
                            _searchQuery.isEmpty
                                ? 'Хэрэглэгч байхгүй байна'
                                : 'Илэрсэн хэрэглэгч байхгүй',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final userDoc = filteredUsers[index];
                          final userId = userDoc.id;
                          final data = userDoc.data() as Map<String, dynamic>;
                          final displayName = data['displayName'] ?? 'Unknown';
                          final photoUrl = data['photoUrl'];
                          final isSelected = _selectedUsers.contains(userId);
                          final isExcluded =
                              widget.excludedUserIds.contains(userId);

                          final username = data['username'] ?? '';
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: isExcluded
                                    ? null
                                    : () => _toggleSelection(userId),
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
                                                  size: 24,
                                                  color: Colors.deepPurple)
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
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayName,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '@$username',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
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
