import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/muushig.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('manual second hand accepts final 1 after 1, 1, 2 and a skip', (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: MuushigPage(selectedUserIds: [
      'demo_player_02', 'demo_player_04', 'demo_player_03', 'demo_player_01', 'demo_player_05',
    ])));
    await tester.pumpAndSettle();
    for (final name in ['МС', 'Шовгор', 'Сыска', 'Индиан', 'Шумуул']) {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(name)));
      await tester.pump();
    }
    await tester.tap(find.text('Дараалал хадгалах'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    Future<void> decisions(List<bool> choices) async {
      for (var i = 0; i < choices.length; i++) {
        await tester.tap(fields.at(i));
        await tester.sendKeyEvent(choices[i] ? LogicalKeyboardKey.enter : LogicalKeyboardKey.space);
        await tester.pump();
      }
      await tester.pump();
    }
    Future<void> score(int index, String value) async {
      expect(tester.widget<TextField>(fields.at(index)).readOnly, false);
      expect(tester.widget<TextField>(fields.at(index)).focusNode!.hasFocus, true);
      tester.testTextInput.enterText(value);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }
    await decisions([true, false, true, true, false]);
    await score(0, '2');
    await score(2, '3');
    await score(3, '0');
    await tester.pumpAndSettle();
    await decisions([true, true, true, false, true]);
    await score(0, '1');
    await score(1, '1');
    await score(2, '2');
    expect(tester.widget<TextField>(fields.at(4)).readOnly, false);
    expect(tester.widget<TextField>(fields.at(4)).focusNode!.hasFocus, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(4)).controller!.text, '');
    expect(tester.widget<TextField>(fields.at(4)).focusNode!.hasFocus, true);
    // Browser/IME submission must also leave an empty final field editable.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(4)).controller!.text, '');
    expect(tester.widget<TextField>(fields.at(4)).focusNode!.hasFocus, true);
    await tester.tap(fields.at(4));
    tester.testTextInput.enterText('2');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(4)).readOnly, false);
    expect(tester.widget<TextField>(fields.at(4)).controller!.text, '2');
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(4)).controller!.text, '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(4)).controller!.text, '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.at(4)).controller!.text, '');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
