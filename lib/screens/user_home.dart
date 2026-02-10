import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'dart:math' show min;

class UserHome extends StatelessWidget {
  const UserHome({super.key, required this.userId, required this.username});

  final String userId;
  final String username;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Миний мэдээлэл'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
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

                      return LayoutBuilder(builder: (context, constraints) {
                        final screenWidth = MediaQuery.of(context).size.width;
                        final isSmallScreen = screenWidth < 600;
                        final imageSize = min(300.0, screenWidth * 0.4);

                        if (isSmallScreen) {
                          // Жижиг дэлгэц: босоо байдлаар
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Зураг
                              CircleAvatar(
                                radius: imageSize / 2,
                                backgroundImage: photoUrl != null
                                    ? NetworkImage(photoUrl)
                                    : null,
                                child: photoUrl == null
                                    ? Icon(Icons.person, size: imageSize / 3)
                                    : null,
                              ),
                              const SizedBox(height: 24),
                              // Мэдээлэл
                              Container(
                                padding: const EdgeInsets.all(20),
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
                                    Text(
                                      displayName,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    _buildInfoRow('Нэвтрэх нэр', username),
                                    const SizedBox(height: 12),
                                    _buildInfoRow('Утас', phone),
                                    const SizedBox(height: 12),
                                    _buildInfoRow('Данс', bank),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Таны мэдээллийг зөвхөн админ өөрчилнө.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          );
                        }

                        // Том дэлгэц: 2 баганат
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Зүүн тал: Зураг + Хоч
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: imageSize / 2,
                                    backgroundImage: photoUrl != null
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    child: photoUrl == null
                                        ? Icon(Icons.person,
                                            size: imageSize / 3)
                                        : null,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 40),
                            // Баруун тал: Мэдээлэл
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(24),
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
                                    const SizedBox(height: 16),
                                    _buildInfoRow('Утас', phone),
                                    const SizedBox(height: 16),
                                    _buildInfoRow('Данс', bank),
                                    const SizedBox(height: 32),
                                    const Text(
                                      'Таны мэдээллийг зөвхөн админ өөрчилнө.',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      });
                    },
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
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
