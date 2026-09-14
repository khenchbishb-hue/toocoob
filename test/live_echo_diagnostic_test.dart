import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/utils/live_game_state.dart';
import 'live_game_state_test.dart' show MemoryServer, MemoryTransport, settle;

class DelayedAckTransport extends MemoryTransport {
  DelayedAckTransport(super.server, super.userId);
  final started = Completer<void>();
  final publish = Completer<void>();
  final acknowledge = Completer<void>();
  @override
  Future<Map<String, dynamic>?> compareAndSet(int revision, Map<String, dynamic> data) async {
    started.complete();
    await publish.future;
    final result = await super.compareAndSet(revision, data);
    await acknowledge.future;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('own snapshot before acknowledgement preserves local decision', () async {
    SharedPreferences.setMockInitialValues({});
    final server = MemoryServer();
    final transport = DelayedAckTransport(server, 'owner');
    final repo = LiveGameSessionsRepository(transportFactory: (_) => transport);
    var decisions = 0;
    await repo.connect('echo-diagnostic', (saved) async {
      decisions = saved.payload['decisions'] as int;
    });
    await repo.checkpoint(() async {
      await repo.saveOrUpdate(gameKey: 'muushig', gameLabel: 'Muushig',
        selectedUserIds: ['owner'], payload: {'decisions': decisions});
    });
    await transport.started.future;
    decisions = 1; // A voice command arrives while the older upload is pending.
    transport.publish.complete();
    await settle();
    expect(decisions, 1, reason: 'Own older snapshot must not overwrite the new local decision');
    transport.acknowledge.complete();
    await settle();
    expect(decisions, 1);
    repo.close();
    await server.changes.close();
  });
}
