import 'package:cloud_firestore/cloud_firestore.dart';
import 'demo_players.dart';

/// Demo identities are local; real identities retain their Firestore profiles.
Future<Map<String, dynamic>?> loadPlayerProfile(String userId) async {
  final demo = DemoPlayers.profileForId(userId);
  if (demo != null) return demo;
  final data = (await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get())
      .data();
  if (data == null) return null;
  return {
    ...data,
    'username': data['username'] ?? data['nickname'] ?? userId,
    'displayName': data['displayName'] ?? data['nickname'] ?? data['firstName'] ?? userId,
    'fullName': data['fullName'] ?? '${data['lastName'] ?? ''} ${data['firstName'] ?? ''}'.trim(),
  };
}
