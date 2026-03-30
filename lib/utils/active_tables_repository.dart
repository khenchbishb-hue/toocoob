import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveTableSummary {
  const ActiveTableSummary({
    required this.id,
    required this.tableNumber,
    required this.gameName,
    required this.status,
    required this.playingFormat,
  });

  final String id;
  final int tableNumber;
  final String gameName;
  final String status;
  final String playingFormat;
}

class ActiveTableDetails {
  const ActiveTableDetails({
    required this.id,
    required this.gameKey,
    required this.gameName,
    required this.playingFormat,
    required this.playerUserIds,
    required this.tableNumber,
    required this.status,
    this.savedSessionId,
    this.ownerUserId,
  });

  final String id;
  final String gameKey;
  final String gameName;
  final String playingFormat;
  final List<String> playerUserIds;
  final int tableNumber;
  final String status;
  final String? savedSessionId;
  final String? ownerUserId;
}

class ActiveTablesRepository {
  ActiveTablesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tables =>
      _firestore.collection('active_tables');

  Stream<Set<String>> watchActivePlayerUserIds() {
    return _tables.where('status', isEqualTo: 'active').snapshots().map((snap) {
      final ids = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final players = (data['playerUserIds'] as List<dynamic>? ?? const [])
            .whereType<String>();
        ids.addAll(players);
      }
      return ids;
    });
  }

  Stream<List<ActiveTableSummary>> watchActiveTableSummaries() {
    return _tables.where('status', isEqualTo: 'active').snapshots().map((snap) {
      final tables = <ActiveTableSummary>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        tables.add(
          ActiveTableSummary(
            id: doc.id,
            tableNumber: (data['tableNumber'] as num?)?.toInt() ?? 1,
            gameName: (data['gameName'] as String?)?.trim().isNotEmpty == true
                ? (data['gameName'] as String)
                : 'Тоглоом',
            status: (data['status'] as String?) ?? 'active',
            playingFormat: (data['playingFormat'] as String?) ?? 'single',
          ),
        );
      }
      tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
      return tables;
    });
  }

  Future<int> fetchNextTableNumber() async {
    final snap = await _tables.get();
    int maxNo = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final no = (data['tableNumber'] as num?)?.toInt() ?? 0;
      if (no > maxNo) maxNo = no;
    }
    return maxNo + 1;
  }

  Future<List<ActiveTableSummary>> fetchActiveTableSummaries({
    String? ownerUserId,
  }) async {
    Query<Map<String, dynamic>> query =
        _tables.where('status', isEqualTo: 'active');
    final owner = ownerUserId?.trim();
    if (owner != null && owner.isNotEmpty) {
      query = query.where('ownerUserId', isEqualTo: owner);
    }

    final snap = await query.get();
    final tables = <ActiveTableSummary>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      tables.add(
        ActiveTableSummary(
          id: doc.id,
          tableNumber: (data['tableNumber'] as num?)?.toInt() ?? 1,
          gameName: (data['gameName'] as String?)?.trim().isNotEmpty == true
              ? (data['gameName'] as String)
              : 'Тоглоом',
          status: (data['status'] as String?) ?? 'active',
          playingFormat: (data['playingFormat'] as String?) ?? 'single',
        ),
      );
    }
    tables.sort((a, b) => a.tableNumber.compareTo(b.tableNumber));
    return tables;
  }

  Future<ActiveTableDetails?> fetchActiveTableDetails(String lockId) async {
    final id = lockId.trim();
    if (id.isEmpty) return null;

    final doc = await _tables.doc(id).get();
    if (!doc.exists) return null;

    final data = doc.data();
    if (data == null) return null;

    return ActiveTableDetails(
      id: doc.id,
      gameKey: (data['gameKey'] as String?) ?? '',
      gameName: (data['gameName'] as String?)?.trim().isNotEmpty == true
          ? (data['gameName'] as String)
          : 'Тоглоом',
      playingFormat: (data['playingFormat'] as String?) ?? 'single',
      playerUserIds:
          (data['playerUserIds'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      tableNumber: (data['tableNumber'] as num?)?.toInt() ?? 1,
      status: (data['status'] as String?) ?? 'active',
      savedSessionId: (data['savedSessionId'] as String?)?.trim(),
      ownerUserId: (data['ownerUserId'] as String?)?.trim(),
    );
  }

  Future<String> createActiveTableLock({
    required String gameKey,
    required String gameName,
    required List<String> playerUserIds,
    required String playingFormat,
    String? ownerUserId,
    int? tableNumber,
  }) async {
    final ref = _tables.doc();
    await ref.set({
      'status': 'active',
      'gameKey': gameKey,
      'gameName': gameName,
      'playingFormat': playingFormat,
      'tableNumber': tableNumber ?? 1,
      'playerUserIds': playerUserIds,
      'ownerUserId': ownerUserId,
      'savedSessionId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateSavedSessionId(String lockId, String? sessionId) async {
    await updateActiveTableState(
      lockId,
      savedSessionId: sessionId,
    );
  }

  Future<void> updateActiveTableState(
    String lockId, {
    String? savedSessionId,
    List<String>? playerUserIds,
  }) async {
    final id = lockId.trim();
    if (id.isEmpty) return;

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Only update savedSessionId if a non-null value is provided (preserve existing).
    if (savedSessionId != null) {
      updates['savedSessionId'] = savedSessionId;
    }

    if (playerUserIds != null) {
      updates['playerUserIds'] = playerUserIds;
    }

    await _tables.doc(id).update(updates);
  }

  Future<void> releaseActiveTableLock(String lockId) async {
    if (lockId.trim().isEmpty) return;
    await _tables.doc(lockId).delete();
  }

  Future<void> releaseOwnedActiveTableLocks(String ownerUserId) async {
    final owner = ownerUserId.trim();
    if (owner.isEmpty) return;

    final snap = await _tables
        .where('status', isEqualTo: 'active')
        .where('ownerUserId', isEqualTo: owner)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> releaseAllActiveTableLocks() async {
    final snap = await _tables.where('status', isEqualTo: 'active').get();
    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Future<void> releasePlayersFromActiveTables(List<String> userIds) async {
    final uniqueIds = userIds.where((e) => e.trim().isNotEmpty).toSet();
    if (uniqueIds.isEmpty) return;

    final batch = _firestore.batch();
    for (final userId in uniqueIds) {
      final snap = await _tables
          .where('status', isEqualTo: 'active')
          .where('playerUserIds', arrayContains: userId)
          .get();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {
          'playerUserIds': FieldValue.arrayRemove([userId]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }
}
