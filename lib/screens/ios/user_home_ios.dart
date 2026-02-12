import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class UserHomeIOS extends StatelessWidget {
  const UserHomeIOS({super.key, required this.userId, required this.username});

  final String userId;
  final String username;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Миний мэдээлэл'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            label: const Text('Буцах', style: TextStyle(color: Colors.white, fontSize: 14)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Firebase.apps.isEmpty
                  ? const Center(
                      child: Text('Firebase эхлүүлэгдээгүй байна.'),
                    )
                  : StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(userId)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Алдаа: ${snapshot.error}');
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const Center(
                            child: Text('Таны мэдээлэл олдсонгүй.'),
                          );
                        }

                        final data =
                            snapshot.data!.data() as Map<String, dynamic>;
                        final displayName = data['displayName'] ?? '—';
                        final phone = data['phone'] ?? '—';
                        final bank = data['bank'] ?? '—';
                        final photoUrl = data['photoUrl'];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            // Profile Image
                            CircleAvatar(
                              radius: 80,
                              backgroundColor: Colors.deepPurple[100],
                              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                  ? (photoUrl.startsWith('http')
                                      ? NetworkImage(photoUrl)
                                      : AssetImage('assets/$photoUrl') as ImageProvider)
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? const Icon(Icons.person, size: 60, color: Colors.deepPurple)
                                  : null,
                            ),
                            const SizedBox(height: 20),
                            // Display Name
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            // Info Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey[300]!,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInfoRow('Нэвтрэх нэр', username),
                                  const SizedBox(height: 12),
                                  _buildInfoRow('Утас', phone),
                                  const SizedBox(height: 12),
                                  _buildInfoRow('Данс', bank),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Таны мэдээллийг зөвхөн админ өөрчилнө.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
