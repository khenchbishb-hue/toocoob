import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/501.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

void main() {
TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('six-player initial order rests the first two choices', (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Game501Page(selectedUserIds: [
      'demo_player_01','demo_player_02','demo_player_03',
      'demo_player_04','demo_player_05','demo_player_06',
    ])));
    await tester.pump(); await tester.pump();
    for (final name in ['Индиан','МС','Сыска','Шовгор','Шумуул','Базилио']) {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(name)));
      await tester.pump();
    }
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ElevatedButton)));
    await tester.pump(const Duration(milliseconds: 500)); await tester.pump();
    final saved = await SavedGameSessionsRepository(storageKey: 'toocoob.live_game_checkpoints.v1').loadSessions();
    final p = saved.firstWhere((s) => s.gameKey == 'game501').payload;
    expect(p['seats'].take(6).map((s) => s['displayName']),
      ['Сыска','Шовгор','Шумуул','Базилио','Индиан','МС']);
    await tester.pumpWidget(const SizedBox()); await tester.pump(const Duration(seconds: 2));
  });
}
