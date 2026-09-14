import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/main.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/13_card_poker.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('login fits phone ${size.width}x${size.height}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ToocoobApp());
      await tester.pumpAndSettle();
      expect(find.text('И-мэйл хаяг'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.ensureVisible(fields.first);
      await tester.enterText(fields.first, 'mobile@example.invalid');
      await tester.ensureVisible(fields.at(1));
      await tester.enterText(fields.at(1), 'Input-only-123!');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('poker accepts and saves scores in portrait and landscape',
      (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(390, 844), const Size(844, 390)]) {
      await tester.binding.setSurfaceSize(size);
      final before = (await SavedGameSessionsRepository().loadSessions())
          .map((s) => s.id)
          .toSet();
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
      final dynamic gameState =
          tester.state(find.byType(ThirteenCardPokerScreen));
      expect(gameState.liveRepository.ready, isTrue);
      expect(gameState.liveRepository.canEdit, isTrue);
      final fields = find.byType(TextField);
      expect(fields, findsAtLeastNWidgets(4));
      for (var i = 0; i < 4; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(fields.at(i), ['0', '2', '4', '5'][i]);
      }
      await tester.testTextInput.receiveAction(TextInputAction.done);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Хадгалах').first);
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        if ((await SavedGameSessionsRepository().loadSessions()).isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final saved = (await SavedGameSessionsRepository().loadSessions())
          .where((s) => !before.contains(s.id))
          .single;
      expect(
          (saved.payload['totalScores'] as Map).values, containsAll([2, 4, 5]));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
