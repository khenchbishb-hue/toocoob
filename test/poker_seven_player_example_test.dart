import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/13_card_poker.dart';
import 'package:toocoob/utils/demo_players.dart';

void main() {
  testWidgets('seven players: first elimination on fourth hand with exact seats', (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final players = DemoPlayers.all.take(7).toList();
    await tester.pumpWidget(MaterialApp(home: ThirteenCardPokerScreen(
      gameType: '13 МОДНЫ ПОКЕР', promptInitialPlayerOrder: false,
      selectedUserIds: players.map((p) => p.id).toList())));
    await tester.pumpAndSettle();
    const scores = [[0,2,4,7], [0,2,4,8], [0,2,4,9], [2,0,6,1]];
    const expected = [[4,5,6,3,0,1,2], [0,1,2,3,4,5,6],
      [4,5,6,3,0,1,2], [1,0,6,2,5,4,3]];
    for (var hand = 0; hand < 4; hand++) {
      final fields = find.byType(TextField);
      for (var i = 0; i < 4; i++) {
        await tester.enterText(fields.at(i), '${scores[hand][i]}');
      }
      tester.widget<TextField>(fields.at(3)).onSubmitted!('');
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final order = List.generate(7, (i) => i)..sort((a,b) {
        final p = tester.getCenter(find.text(players[a].displayName));
        final q = tester.getCenter(find.text(players[b].displayName));
        return (p.dy-q.dy).abs() > 10 ? p.dy.compareTo(q.dy) : p.dx.compareTo(q.dx);
      });
      expect(order, expected[hand], reason: 'Seats after hand ${hand+1}');
    }
    await tester.pumpWidget(const SizedBox());
  });
}
