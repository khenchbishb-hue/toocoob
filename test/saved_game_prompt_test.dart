import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/widgets/saved_game_prompt.dart';

SavedGameSession session(String id, List<String> players,
    {bool completed = false, int day = 10}) => SavedGameSession(
  id: id, gameKey: 'muushig', gameLabel: 'Муушиг', selectedUserIds: players,
  createdAt: DateTime(2026, 9, day), updatedAt: DateTime(2026, 9, day, 14, 30),
  payload: {'sessionCompleted': completed, 'seats': [
    for (var i = 0; i < players.length; i++)
      {'displayName': players[i], 'totalScoreText': [2, 0, 18, 7][i], 'wins': i},
  ]},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('exact unordered roster, unfinished only, latest first', () async {
    final repo = SavedGameSessionsRepository();
    await repo.saveSessions([
      session('older', ['А', 'Б', 'В', 'Г'], day: 9),
      session('latest', ['Г', 'В', 'Б', 'А']),
      session('finished', ['А', 'Б', 'В', 'Г'], completed: true),
      session('subset', ['А', 'Б', 'В']),
      session('different', ['А', 'Б', 'В', 'Д']),
      session('live_old', ['А', 'Б', 'В', 'Г']),
    ]);
    expect((await repo.findUnfinishedByPlayers(['Б', 'А', 'Г', 'В']))
        .map((s) => s.id), ['latest', 'older']);
    expect(await repo.findUnfinishedByPlayers([]), isEmpty);
  });

  for (final action in ['Үргэлжлүүлэх', 'Шинээр тоглох', 'Буцах']) {
    testWidgets('prompt shows results and handles $action', (tester) async {
      String? result = 'pending';
      final saved = session('saved', ['А', 'Б', 'В', 'Г']);
      await SavedGameSessionsRepository().saveSessions([saved]);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
        TextButton(onPressed: () async {
          result = await showSavedGamePrompt(context, [saved]);
        }, child: const Text('Open')))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Муушиг'), findsOneWidget);
      expect(find.textContaining('2026-09-10 14:30'), findsOneWidget);
      expect(find.textContaining('В — Нийт оноо: 18'), findsOneWidget);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(result, action == 'Үргэлжлүүлэх' ? 'saved' : action == 'Шинээр тоглох' ? '' : null);
      expect((await SavedGameSessionsRepository().loadSessions()).length, 1);
    });
  }
}
