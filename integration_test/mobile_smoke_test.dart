import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/main.dart' as app;
import 'package:toocoob/screens/13_card_poker.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Firebase starts and login form accepts input',
      (tester) async {
    app.main();
    // Native Firebase initialization completes asynchronously before runApp.
    for (var i = 0;
        i < 100 && find.byType(app.LoginScreen).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(app.firebaseInitialized, isTrue);
    expect(find.byType(app.LoginScreen), findsOneWidget);
    expect(find.text('И-мэйл хаяг'), findsOneWidget);
    expect(find.text('Нууц үг'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'mobile-smoke@example.invalid');
    await tester.enterText(fields.at(1), 'Smoke-input-only-123!');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Do not submit synthetic credentials to the production Auth service.
    await tester.enterText(fields.first, '');
    await tester.enterText(fields.at(1), '');
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
  });

  testWidgets('demo poker accepts a hand and saves it on the device',
      (tester) async {
    final repository = SavedGameSessionsRepository();
    final before = (await repository.loadSessions()).map((s) => s.id).toSet();
    addTearDown(() async {
      for (final session in await repository.loadSessions()) {
        if (!before.contains(session.id) &&
            session.selectedUserIds
                .every((id) => id.startsWith('demo_player_'))) {
          await repository.removeById(session.id);
        }
      }
    });
    await tester.pumpWidget(const MaterialApp(
        home: ThirteenCardPokerScreen(
      gameType: '13 МОДНЫ ПОКЕР',
      promptInitialPlayerOrder: false,
      selectedUserIds: [
        'demo_player_01',
        'demo_player_02',
        'demo_player_03',
        'demo_player_04'
      ],
    )));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('poker-score-input-0')), 200,
        scrollable: find
            .descendant(
                of: find.byType(GridView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(fields, findsAtLeastNWidgets(4));
    for (var i = 0; i < 4; i++) {
      await tester.ensureVisible(fields.at(i));
      await tester.enterText(fields.at(i), ['0', '2', '4', '5'][i]);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Хадгалах').first);
    await tester.pumpAndSettle();
    final saved = (await repository.loadSessions())
        .where((s) => !before.contains(s.id))
        .single;
    expect(saved.gameKey, '13_card_poker');
    expect(
        (saved.payload['totalScores'] as Map).values, containsAll([2, 4, 5]));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('native local game storage persists and reloads scores',
      (tester) async {
    const key = 'toocoob.mobile_smoke.sessions';
    final preferences = await SharedPreferences.getInstance();
    addTearDown(() async {
      await preferences.remove(key);
    });
    final repository = SavedGameSessionsRepository(storageKey: key);
    final id = await repository.saveOrUpdate(
      gameKey: '13_card_poker',
      gameLabel: '13 МОДНЫ ПОКЕР',
      selectedUserIds: ['demo_player_01', 'demo_player_02'],
      payload: {
        'roundNumber': 2,
        'totalScores': [0, 5]
      },
    );
    await preferences.reload();
    final restored =
        await SavedGameSessionsRepository(storageKey: key).findById(id);
    expect(restored, isNotNull);
    expect(restored!.payload['totalScores'], [0, 5]);
    expect(restored.payload['roundNumber'], 2);
  });
}
