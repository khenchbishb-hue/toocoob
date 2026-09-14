import 'package:toocoob/utils/game_sync_service.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/utils/live_game_state.dart';
import 'package:toocoob/utils/live_game_transport.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

class MemoryServer {
  Map<String, dynamic>? data;
  final changes = StreamController<Map<String, dynamic>?>.broadcast();
  int writes = 0;
  bool offline = false;
}

class MemoryTransport implements LiveGameTransport {
  MemoryTransport(this.server, this.userId);
  final MemoryServer server;
  @override
  final String userId;
  @override
  Future<String?> ownerId() async => 'owner';
  @override
  Stream<Map<String, dynamic>?> watch() async* {
    yield server.data;
    yield* server.changes.stream;
  }

  @override
  Future<Map<String, dynamic>?> compareAndSet(
      int revision, Map<String, dynamic> data) async {
    if (server.offline) throw StateError('offline');
    if ((server.data?['revision'] ?? 0) != revision) return server.data;
    server.data = {...data, 'revision': revision + 1};
    server.writes++;
    server.changes.add(server.data);
    return null;
  }
}

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> save(LiveGameSessionsRepository repo, int score) async {
  await repo.checkpoint(() async {
    await repo.saveOrUpdate(
        gameKey: 'muushig',
        gameLabel: 'Муушиг',
        selectedUserIds: ['owner', 'viewer'],
        payload: {'score': score});
  });
  await settle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save at 3, reopen, play to 9, reopen without pressing save again', () async {
    final first = LiveGameSessionsRepository();
    await first.connect(null, (_) async {});
    final id = await first.saveOrUpdate(
        gameKey: 'muushig', gameLabel: 'Муушиг',
        selectedUserIds: ['owner'], payload: {'score': 3});
    first.close();
    final resumed = LiveGameSessionsRepository();
    expect((await resumed.findById(id))!.payload['score'], 3);
    await resumed.connect(null, (_) async {});
    await save(resumed, 9);
    resumed.close();
    final next = LiveGameSessionsRepository();
    expect((await next.findById(id))!.payload['score'], 9);
    expect((await SavedGameSessionsRepository().loadSessions()).length, 1);
    next.close();
  });

  test('saved games keep the latest progress across reconnects',
      () async {
    final server = MemoryServer();
    final repo = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    await repo.connect('separate', (_) async {});
    await save(repo, 3);
    final manual = SavedGameSessionsRepository();
    expect(await manual.loadSessions(), isEmpty);
    final id = await repo.saveOrUpdate(
        gameKey: 'muushig',
        gameLabel: 'Муушиг',
        selectedUserIds: ['owner', 'viewer'],
        payload: {'score': 3});
    await save(repo, 9);
    expect((await manual.findById(id))!.payload['score'], 9);
    repo.close();
    await settle();
    final reopened = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    var score = 0;
    await reopened.connect(
        'separate', (s) async => score = s.payload['score'] as int);
    expect(score, 9);
    expect((await manual.findById(id))!.payload['score'], 9);
    final updatedId = await reopened.saveOrUpdate(
        gameKey: 'muushig',
        gameLabel: 'Муушиг',
        selectedUserIds: ['owner', 'viewer'],
        payload: {'score': 9});
    expect(updatedId, id);
    expect((await manual.loadSessions()).length, 1);
    expect((await manual.findById(id))!.payload['score'], 9);
    reopened.close();
    await server.changes.close();
  });

  test('local checkpoints update a resumed saved game', () async {
    final repo = LiveGameSessionsRepository();
    await repo.connect(null, (_) async {});
    final payload = <String, dynamic>{'score': 4};
    final id = await repo.saveOrUpdate(
        sessionId: 'existing',
        gameKey: 'muushig',
        gameLabel: 'Муушиг',
        selectedUserIds: ['owner'],
        payload: payload);
    payload['score'] = 8;
    await save(repo, 8);
    expect((await SavedGameSessionsRepository().findById(id))!.payload['score'],
        8);
    expect((await SavedGameSessionsRepository().loadSessions()).length, 1);
    final nextId = await repo.saveOrUpdate(
        sessionId: id,
        gameKey: 'muushig',
        gameLabel: 'Муушиг',
        selectedUserIds: ['owner'],
        payload: payload);
    expect(nextId, id);
    expect((await SavedGameSessionsRepository().findById(id))!.payload['score'],
        8);
    repo.close();
  });

  test('owner changes reach viewer, repeated payloads do not write', () async {
    final server = MemoryServer();
    final owner = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    final viewer = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'viewer'));
    SavedGameSession? received;
    await owner.connect('a', (_) async {});
    await viewer.connect('a', (saved) async => received = saved);
    expect(owner.canEdit, isTrue);
    expect(viewer.canEdit, isFalse);
    await save(owner, 3);
    expect(received?.payload['score'], 3);
    await save(owner, 3);
    await save(viewer, 99);
    expect(server.writes, 1);
    owner.close();
    viewer.close();
    await server.changes.close();
  });

  test('server state restores before a new device may upload defaults',
      () async {
    final server = MemoryServer();
    final first = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    await first.connect('b', (_) async {});
    await save(first, 15);
    final second = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    var score = 0;
    await second.connect(
        'b', (saved) async => score = saved.payload['score'] as int);
    expect(score, 15);
    expect(server.writes, 1);
    first.close();
    second.close();
    await server.changes.close();
  });

  test('offline writes stay local and retry the latest score', () async {
    final server = MemoryServer();
    final repo = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    await repo.connect('c', (_) async {});
    server.offline = true;
    await save(repo, 1);
    await save(repo, 4);
    expect(server.writes, 0);
    final cached = await SavedGameSessionsRepository(
            storageKey: 'toocoob.live_game_checkpoints.v1')
        .findById('live_c');
    expect(cached?.payload['score'], 4);
    server.offline = false;
    await repo.flush();
    await settle();
    final data = jsonDecode(server.data!['payloadJson'] as String) as Map;
    expect((data['payload'] as Map)['score'], 4);
    repo.close();
    await server.changes.close();
  });

  test('stale device cannot overwrite a newer revision', () async {
    final server = MemoryServer();
    final repo = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    var restored = 0;
    await repo.connect(
        'd', (saved) async => restored = saved.payload['score'] as int);
    await save(repo, 1);
    final raw = jsonDecode(server.data!['payloadJson'] as String)
        as Map<String, dynamic>;
    (raw['payload'] as Map)['score'] = 8;
    // Simulate a newer write before the stream notification reaches this client.
    server.data = {
      ...server.data!,
      'revision': 2,
      'payloadJson': jsonEncode(raw)
    };
    await save(repo, 2);
    expect(restored, 8);
    expect(server.data!['revision'], 2);
    repo.close();
    await server.changes.close();
  });

  test('registrar transfer switches writer and viewer permissions', () async {
    final server = MemoryServer();
    final owner = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    final viewer = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'viewer'));
    await owner.connect('e', (_) async {});
    await viewer.connect('e', (_) async {});
    owner.registrar = () => 'viewer';
    await save(owner, 5);
    expect(owner.canEdit, isFalse);
    expect(viewer.canEdit, isTrue);
    viewer.registrar = () => 'viewer';
    await save(viewer, 6);
    expect(server.writes, 2);
    owner.close();
    viewer.close();
    await server.changes.close();
  });

  test('simultaneous local saves preserve both sessions and updated players',
      () async {
    final a = SavedGameSessionsRepository(), b = SavedGameSessionsRepository();
    await Future.wait([
      a.saveOrUpdate(
          sessionId: 'a',
          gameKey: 'a',
          gameLabel: 'a',
          selectedUserIds: ['1'],
          payload: {}),
      b.saveOrUpdate(
          sessionId: 'b',
          gameKey: 'b',
          gameLabel: 'b',
          selectedUserIds: ['2'],
          payload: {}),
    ]);
    expect((await a.loadSessions()).length, 2);
    await a.saveOrUpdate(
        sessionId: 'a',
        gameKey: 'a',
        gameLabel: 'a',
        selectedUserIds: ['1', '3'],
        payload: {});
    expect((await a.findById('a'))!.selectedUserIds, ['1', '3']);
  });
  test('unsent local score survives reopening at the same server revision',
      () async {
    final server = MemoryServer();
    final first = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    await first.connect('restart', (_) async {});
    await save(first, 1);
    server.offline = true;
    await save(first, 7);
    first.close();
    await settle();
    server.offline = false;
    final reopened = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    var score = 0;
    await reopened.connect(
        'restart', (saved) async => score = saved.payload['score'] as int);
    expect(score, 7);
    await reopened.flush();
    await settle();
    final stored = jsonDecode(server.data!['payloadJson'] as String) as Map;
    expect((stored['payload'] as Map)['score'], 7);
    reopened.close();
    await server.changes.close();
  });

  test('a stale offline checkpoint yields to the newer server score', () async {
    final server = MemoryServer();
    final first = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    await first.connect('stale', (_) async {});
    await save(first, 1);
    server.offline = true;
    await save(first, 7);
    first.close();
    await settle();
    final data = jsonDecode(server.data!['payloadJson'] as String)
        as Map<String, dynamic>;
    (data['payload'] as Map)['score'] = 9;
    server.data = {
      ...server.data!,
      'revision': 2,
      'payloadJson': jsonEncode(data)
    };
    server.offline = false;
    final reopened = LiveGameSessionsRepository(
        transportFactory: (_) => MemoryTransport(server, 'owner'));
    var score = 0;
    await reopened.connect(
        'stale', (saved) async => score = saved.payload['score'] as int);
    expect(score, 9);
    await reopened.flush();
    expect(server.data!['revision'], 2);
    reopened.close();
    await server.changes.close();
  });

  test('Firestore map key order does not create an echo upload', () {
    expect(
        gameStateFingerprint({
          'a': 1,
          'b': {'x': 2, 'y': 3}
        }),
        gameStateFingerprint({
          'b': {'y': 3, 'x': 2},
          'a': 1
        }));
    expect(
        gameStateFingerprint({
          'players': ['a', 'b']
        }),
        isNot(gameStateFingerprint({
          'players': ['b', 'a']
        })));
  });
}
