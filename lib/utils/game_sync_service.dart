import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class GameSyncState {
  const GameSyncState({
    required this.key,
    required this.gameKey,
    required this.writerUserId,
    required this.revision,
    required this.payload,
  });

  final String key;
  final String gameKey;
  final String writerUserId;
  final int revision;
  final Map<String, dynamic> payload;
}

/// Shared realtime-state transport for every game type and table count.
///
/// A game owns the shape of [payload]. This service only handles Firestore
/// transport, revisions, timestamps, and stable state keys.
class GameSyncService {
  GameSyncService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _states(String sessionId) =>
      _firestore.collection('active_tables').doc(sessionId).collection(
            'game_states',
          );

  Stream<List<GameSyncState>> watchSession(String sessionId) {
    return _states(sessionId).snapshots().map(
          (snapshot) => snapshot.docs.map((document) {
            final data = document.data();
            return GameSyncState(
              key: document.id,
              gameKey: (data['gameKey'] as String?) ?? '',
              writerUserId: (data['writerUserId'] as String?) ?? '',
              revision: (data['revision'] as num?)?.toInt() ?? 0,
              payload: Map<String, dynamic>.from(
                data['payload'] as Map? ?? const <String, dynamic>{},
              ),
            );
          }).toList(growable: false),
        );
  }

  Future<int> writeState({
    required String sessionId,
    required String stateKey,
    int? expectedRevision,
    required String gameKey,
    required String writerUserId,
    required Map<String, dynamic> payload,
  }) async {
    final reference = _states(sessionId).doc(stateKey);
    return _firestore.runTransaction<int>((transaction) async {
      final current = await transaction.get(reference);
      final revision =
          ((current.data()?['revision'] as num?)?.toInt() ?? 0) + 1;
      if (expectedRevision != null && revision != expectedRevision + 1) {
        throw StateError('A newer table revision exists');
      }
      transaction.set(
        reference,
        <String, dynamic>{
          'gameKey': gameKey,
          'stateKey': stateKey,
          'writerUserId': writerUserId,
          'revision': revision,
          'payload': payload,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return revision;
    });
  }
}

/// Firestore may return map keys in a different order than the local model.
String gameStateFingerprint(Map<String, dynamic> state) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  return jsonEncode(canonical(state));
}
