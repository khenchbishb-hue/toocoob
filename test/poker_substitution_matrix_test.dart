import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/13_card_poker.dart';
import 'package:toocoob/utils/demo_players.dart';

void main() {
  // Explicit seat expectations: original Sh1..Sh4 = 0..3, C1..C3 = 4..6.
  // Keep the highest-scoring survivor in their own seat. Substitutes enter
  // other score-ranked seats first, then fill eliminated seats; displaced
  // scorers fill any remaining vacancies.
  const expectedSeats = {
    '5/1': [4, 1, 2, 0, 3],
    '5/2': [4, 1, 0, 3, 2],
    '5/3': [0, 4, 2, 3, 1],
    '6/1': [4, 5, 2, 0, 1, 3],
    '6/2': [4, 1, 5, 0, 3, 2],
    '6/3': [0, 4, 5, 3, 2, 1],
    '7/1': [4, 5, 2, 6, 0, 1, 3],
    '7/2': [4, 1, 5, 6, 0, 3, 2],
    '7/3': [0, 4, 5, 6, 3, 2, 1],
  };
  for (final count in [5, 6, 7]) {
    for (final eliminatedCount in [1, 2, 3]) {
      testWidgets('$count players, $eliminatedCount eliminated: fill seats without losing identities', (tester) async {
        setupFirebaseCoreMocks();
        await Firebase.initializeApp();
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final players = DemoPlayers.all.take(count).toList();
        await tester.pumpWidget(MaterialApp(home: ThirteenCardPokerScreen(
          gameType: '13 МОДНЫ ПОКЕР', promptInitialPlayerOrder: false,
          selectedUserIds: players.map((p) => p.id).toList())));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        for (var i = 0; i < 4; i++) {
          await tester.enterText(fields.at(i), i >= 4 - eliminatedCount ? '13' : '${i * 2}');
        }
        tester.widget<TextField>(fields.at(3)).onSubmitted!('');
        await tester.pumpAndSettle();
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          for (final player in players.skip(4 - eliminatedCount).take(eliminatedCount)) {
            await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(player.displayName)));
            await tester.pump();
          }
          await tester.tap(find.text('Дараалал хадгалах'));
          await tester.pumpAndSettle();
        }
        final positions = <String, Offset>{};
        for (final player in players) {
          final name = find.text(player.displayName);
          expect(name, findsOneWidget);
          positions[player.id] = tester.getCenter(name);
        }
        final topY = positions.values.map((p) => p.dy).reduce((a,b) => a < b ? a : b);
        final seatOrder = List.generate(count, (i) => i)..sort((a,b) {
          final left = positions[players[a].id]!;
          final right = positions[players[b].id]!;
          if ((left.dy - right.dy).abs() > 10) return left.dy.compareTo(right.dy);
          return left.dx.compareTo(right.dx);
        });
        expect(seatOrder, expectedSeats['$count/$eliminatedCount'], reason: 'Exact Sh1–Sh4 then C1–C3 positions');
        final stationaryPlayer = 3 - eliminatedCount;
        expect(seatOrder[stationaryPlayer], stationaryPlayer,
            reason: 'Highest-scoring survivor must keep their original seat');
        final alive = [...players.take(4 - eliminatedCount), ...players.skip(4)];
        final mainAlive = alive.where((p) => (positions[p.id]!.dy - topY).abs() < 10).length;
        expect(mainAlive, (count - eliminatedCount).clamp(0, 4));
        expect(positions.values.toSet(), hasLength(count));
        if (mainAlive >= 3) {
          // A second elimination with already pinned, inactive substitutes.
          final currentFields = find.byType(TextField);
          for (var i = 0; i < mainAlive; i++) {
            await tester.enterText(currentFields.at(i), i == mainAlive - 1 ? '13' : '$i');
          }
          tester.widget<TextField>(currentFields.at(mainAlive - 1)).onSubmitted!('');
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          for (final player in players) {
            expect(find.text(player.displayName), findsOneWidget);
          }
          final secondPositions = players.map((p) => tester.getCenter(find.text(p.displayName))).toList();
          expect(secondPositions.toSet(), hasLength(count));
          final top = secondPositions.map((p) => p.dy).reduce((a,b) => a < b ? a : b);
          // Every surviving bench player must enter when fewer than four remain.
          if (count - eliminatedCount - 1 <= 4) {
            for (final player in players.skip(4)) {
              final before = positions[player.id]!;
              if (before.dy > topY + 10) {
                expect(tester.getCenter(find.text(player.displayName)).dy, closeTo(top, 10));
              }
            }
          }
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
