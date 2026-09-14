import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/utils/statistics_repository.dart';
import 'package:toocoob/utils/demo_players.dart';

void main() {
  test('mixed trial retains real identity and notifies profile after saving', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = StatsRepository();
    final revision = StatsRepository.revision.value;
    final session = StatsSession(sessionId: 'trial', gameKey: 'muushig',
      gameLabel: 'МУУШИГ', playedAt: DateTime(2026, 9, 14), totalRounds: 2,
      players: [
        StatsPlayerResult(userId: 'real-uid', username: 'Чоно', displayName: 'Хэнчбиш', money: 100),
        StatsPlayerResult(userId: DemoPlayers.all.first.id, username: 'demo', displayName: 'Demo', money: -100),
      ]);
    await repository.addSession(session);
    final saved = (await repository.loadSessions()).single;
    expect(saved.players.first.userId, 'real-uid');
    expect(saved.players.first.money, 100);
    expect(saved.players.any((p) => DemoPlayers.isDemoId(p.userId)), isTrue);
    expect(StatsRepository.revision.value, revision + 1);
    await repository.addSession(session);
    expect(await repository.loadSessions(), hasLength(1));
  });
}
