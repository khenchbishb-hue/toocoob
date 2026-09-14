import 'table_session.dart';
import 'browser_table_identity.dart';
import 'saved_game_sessions_repository.dart';
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
  Future<void> closePreviousBrowserTables(String ownerId) async {
    final snapshot = await _tables.where('ownerUserId', isEqualTo: ownerId).get();
    for (final doc in snapshot.docs) {
      if (!TableSession.current.isPreviousRun(doc.data(), browserTableIdentity, ownerId)) continue;
      final archived = await _firestore.runTransaction<bool>((tx) async {
        final data = (await tx.get(doc.reference)).data();
        if (data == null || !TableSession.current.isPreviousRun(data, browserTableIdentity, ownerId)) return false;
        tx.update(doc.reference, {
          'status': 'archived', 'updatedAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (archived) {
        // Only temporary recovery data is removed. Explicit saved games remain.
        await SavedGameSessionsRepository(storageKey: 'toocoob.live_game_checkpoints.v1')
            .removeById('live_${doc.id}');
      }
    }
  }
  ActiveTablesRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tables =>
      _firestore.collection('active_tables');

  CollectionReference<Map<String, dynamic>> _syncedPokerTables(
    String lockId,
  ) =>
      _tables.doc(lockId).collection('poker_table_states');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPokerTableStates(
    String lockId,
  ) =>
      _syncedPokerTables(lockId).snapshots();

  Future<void> writePokerTableState({
    required String lockId,
    required int tableNumber,
    required String writerUserId,
    required Map<String, dynamic> state,
  }) async {
    final ref = _syncedPokerTables(lockId).doc(tableNumber.toString());
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(ref);
      final revision =
          ((current.data()?['revision'] as num?)?.toInt() ?? 0) + 1;
      transaction.set(
          ref,
          <String, dynamic>{
            'tableNumber': tableNumber,
            'writerUserId': writerUserId,
            'revision': revision,
            'state': state,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  Stream<Set<String>> watchActivePlayerUserIds({
    String? currentOwnerUserId,
    bool Function(String tableId)? isOpenInThisSession,
  }) {
    return _tables.where('status', isEqualTo: 'active').snapshots().map((snap) {
      final ids = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        // A previous browser session must not prevent its owner from choosing
        // players and explicitly resuming a saved game. No server data changes.
        if (currentOwnerUserId != null &&
            data['ownerUserId'] == currentOwnerUserId &&
            isOpenInThisSession != null && !isOpenInThisSession(doc.id)) {
          continue;
        }
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
        if (!TableSession.current.contains(doc.id)) continue;
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

  Future<int> fetchNextTableNumber() async => TableSession.current.reserveNumber();

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
      if (!TableSession.current.contains(doc.id)) continue;
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
    String? replacingTableId,
  }) async {
    final ref = _tables.doc();
    final data = <String, dynamic>{
      'status': 'active',
      'gameKey': gameKey,
      'gameName': gameName,
      'playingFormat': playingFormat,
      'tableNumber': tableNumber ?? TableSession.current.reserveNumber(),
      'playerUserIds': playerUserIds,
      'ownerUserId': ownerUserId,
      'savedSessionId': null,
      'browserTabId': browserTableIdentity,
      'browserRunId': TableSession.current.runId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _firestore.runTransaction((transaction) async {
      if (replacingTableId != null) {
        final previousRef = _tables.doc(replacingTableId);
        final previous = (await transaction.get(previousRef)).data();
        if (previous == null || previous['status'] != 'active' ||
            ownerUserId == null || previous['ownerUserId'] != ownerUserId) {
          throw StateError('Ширээний төлөв өөрчлөгдсөн байна.');
        }
        transaction.update(previousRef, {
          'status': 'archived',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(ref, data);
    });
    TableSession.current.register(ref.id);
    return ref.id;
  }

  Future<void> updateSavedSessionId(String lockId, String? sessionId) async {
    await updateActiveTableState(
      lockId,
      savedSessionId: sessionId,
    );
  }

  Future<void> updatePokerTableRegistrars(
    String lockId, {
    required bool useSeparateRegistrars,
    required Map<int, String?> registrarUserIds,
  }) async {
    final id = lockId.trim();
    if (id.isEmpty) return;
    await _tables.doc(id).update({
      'useSeparateTableRegistrars': useSeparateRegistrars,
      'tableRegistrarUserIds': registrarUserIds.map(
        (table, userId) => MapEntry(table.toString(), userId),
      ),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  Future<void> archiveOwnedTable(String lockId, String ownerUserId) async {
    await _firestore.runTransaction((transaction) async {
      final ref = _tables.doc(lockId);
      final data = (await transaction.get(ref)).data();
      if (data == null || data['ownerUserId'] != ownerUserId) {
        throw StateError('Зөвхөн ширээний эзэмшигч хаана.');
      }
      transaction.update(ref, {'status': 'archived', 'updatedAt': FieldValue.serverTimestamp()});
    });
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
