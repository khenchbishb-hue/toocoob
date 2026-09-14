import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/13_card_poker.dart';

void main() {
  testWidgets('duplicate winners cannot commit; cancelling a tie keeps score inputs', (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ThirteenCardPokerScreen(
      gameType: '13 МОДНЫ ПОКЕР', promptInitialPlayerOrder: false,
      selectedUserIds: ['demo_player_01', 'demo_player_02', 'demo_player_03', 'demo_player_04', 'demo_player_05'])));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsAtLeastNWidgets(4));
    Future<void> submit(List<String> values) async {
      for (var i = 0; i < 4; i++) {
        await tester.enterText(fields.at(i), values[i]);
      }
      tester.widget<TextField>(fields.at(3)).onSubmitted!('');
      await tester.pumpAndSettle();
    }
    await submit(['0', '22', '4', '5']);
    expect(find.text('Нэг үеийн оноо 0–13 байна. Оноогоо засна уу.'), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '22');
    await tester.pump(const Duration(seconds: 5));
    await submit(['0', '0', '4', '5']);
    expect(find.text('Зөвхөн нэг тоглогч 0 оноотой хожно. Оноогоо засна уу.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await submit(['0', '2', '2', '5']);
    expect(find.text('Оноо тэнцсэн тоглогчдын дарааллыг сонгоно уу'), findsOneWidget);
    await tester.tap(find.text('Болих'));
    await tester.pumpAndSettle();
    expect(find.byType(ThirteenCardPokerScreen), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(1)).controller!.text, '2');
    expect(tester.widget<TextField>(fields.at(2)).controller!.text, '2');
    // Sh2 wins, Sh4 is eliminated (13 contributes 39 to the total).
    await submit(['2', '0', '4', '13']);
    final incoming = tester.getCenter(find.text('Шумуул').first);
    final winner = tester.getCenter(find.text('МС').first);
    final eliminated = tester.getCenter(find.text('Шовгор').first);
    expect(incoming.dx, lessThan(winner.dx));
    expect((incoming.dy - winner.dy).abs(), lessThan(10));
    expect(eliminated.dy, greaterThan(winner.dy));
    await tester.pumpWidget(const SizedBox());
  });
}
