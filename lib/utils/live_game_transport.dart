import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract class LiveGameTransport {
  String? get userId;
  Future<String?> ownerId();
  Stream<Map<String, dynamic>?> watch();

  /// Returns the current document on a revision conflict, null on success.
  Future<Map<String, dynamic>?> compareAndSet(
      int revision, Map<String, dynamic> data);
}

class FirestoreLiveGameTransport implements LiveGameTransport {
  FirestoreLiveGameTransport(String lockId)
      : _table =
            FirebaseFirestore.instance.collection('active_tables').doc(lockId);
  final DocumentReference<Map<String, dynamic>> _table;
  DocumentReference<Map<String, dynamic>> get _state =>
      _table.collection('game_states').doc('session');
  @override
  String? get userId => FirebaseAuth.instance.currentUser?.uid;
  @override
  Future<String?> ownerId() async =>
      (await _table.get()).data()?['ownerUserId'] as String?;
  @override
  Stream<Map<String, dynamic>?> watch() => _state
      .snapshots()
      .where((snapshot) => !snapshot.metadata.hasPendingWrites)
      .map((snapshot) => snapshot.data());
  @override
  Future<Map<String, dynamic>?> compareAndSet(
          int revision, Map<String, dynamic> data) =>
      FirebaseFirestore.instance
          .runTransaction<Map<String, dynamic>?>((tx) async {
        final snapshot = await tx.get(_state);
        final current = snapshot.data();
        final actual = (current?['revision'] as num?)?.toInt() ?? 0;
        if (actual != revision) return current;
        tx.update(_table, {
          'playerUserIds': data['playerUserIds'],
          'savedSessionId': data['savedSessionId'],
          'updatedAt': FieldValue.serverTimestamp()
        });
        tx.set(_state, {
          ...data,
          'revision': actual + 1,
          'updatedAt': FieldValue.serverTimestamp()
        });
        return null;
      });
}
