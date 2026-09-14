import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/buur.dart';
import 'package:toocoob/screens/muushig.dart';
import 'package:toocoob/widgets/voice_player_cue.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';

void main() {
  const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  var listenCalls = 0;
  var stopCalls = 0;
  Future<void> emit(String method, Object value) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)),
        (_) {});
  }

  Future<void> say(WidgetTester tester, String words,
      {bool finalResult = false}) async {
    await emit(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': words, 'confidence': 1.0}
          ],
          'resultType': finalResult ? 2 : 0,
        }));
    await tester.pump();
  }

  Finder activeCue() =>
      find.byWidgetPredicate((w) => w is VoicePlayerCue && w.active);
  Future<Map<String, dynamic>> payload(WidgetTester tester, String game) async {
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    final sessions = await SavedGameSessionsRepository(storageKey: 'toocoob.live_game_checkpoints.v1').loadSessions();
    return sessions.firstWhere((s) => s.gameKey == game).payload;
  }

  setUp(() async {
    listenCalls = 0;
    stopCalls = 0;
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'listen') listenCalls++;
      if (call.method == 'stop') stopCalls++;
      if (call.method == 'locales') return ['mn-MN:Монгол'];
      return true;
    });
  });
  testWidgets('voice feedback selects, applies once, and cancels in both games',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: BuurPage()));
    await tester.pump();
    final before = await payload(tester, 'buur');
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();
    await say(tester, 'Тоглогч 1');
    expect(activeCue(), findsOneWidget);
    expect(find.descendant(of: activeCue(), matching: find.text('Тоглогч 1')),
        findsOneWidget);
    await say(tester, 'Тоглогч 2');
    expect(find.descendant(of: activeCue(), matching: find.text('Тоглогч 2')),
        findsOneWidget);
    await say(tester, 'хөзрөн буур', finalResult: true);
    expect(activeCue(), findsNothing);
    await say(tester, 'хөзрөн буур', finalResult: true);
    final after = await payload(tester, 'buur');
    expect(after['centerScore'], (before['centerScore'] as int) - 2);
    expect(after['players'][1]['pishka'], 2);
    expect(after['players'][0]['pishka'], 0);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await say(tester, 'Тоглогч 1');
    expect(activeCue(), findsOneWidget);
    // A browser recognition session may end after only the name.
    await say(tester, 'Тоглогч 1', finalResult: true);
    await emit('notifyStatus', 'notListening');
    await emit('notifyStatus', 'done');
    await tester.pump(const Duration(milliseconds: 500));
    await say(tester, 'тамган', finalResult: true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(activeCue(), findsOneWidget);
    await say(tester, 'буур', finalResult: true);
    expect(activeCue(), findsNothing);
    final splitAction = await payload(tester, 'buur');
    expect(splitAction['players'][0]['pishka'], 3);
    expect(splitAction['centerScore'], (after['centerScore'] as int) - 3);
    await tester.pump(const Duration(milliseconds: 500));
    await say(tester, 'Тоглогч 1');
    await say(tester, 'боллоо', finalResult: true);
    await tester.pump();
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(activeCue(), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));

    Future<void> speak(String words) async {
      await say(tester, words, finalResult: true);
      await emit('notifyStatus', 'notListening');
      await emit('notifyStatus', 'done');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }
    // Switch games in the same session to verify microphone callbacks move too.
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        const MaterialApp(home: MuushigPage(initialSavedSessionId: 'test')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Тоглогчийн дараалал сонгох'), findsOneWidget);
    for (final name in ['Индиан', 'МС', 'Сыска', 'Шовгор', 'Шумуул', 'Базилио']) {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(name)));
      await tester.pump();
    }
    await tester.tap(find.text('Дараалал хадгалах'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();
    await speak('Индиан');
    await emit('notifyStatus', 'listening');
    await tester.pump();
    expect(find.textContaining('Дууны оношилгоо (түр)'), findsNothing);
    expect(find.textContaining('Дараагийн командаа хэлнэ үү'), findsOneWidget);
    expect(activeCue(), findsOneWidget);
    final listensBeforeCommand = listenCalls;
    final stopsBeforeCommand = stopCalls;
    await say(tester, 'Индиан орлоо', finalResult: true);
    await tester.pump();
    expect(stopCalls, greaterThan(stopsBeforeCommand));
    expect(listenCalls, greaterThan(listensBeforeCommand));
    expect(find.descendant(of: activeCue(), matching: find.text('МС')), findsOneWidget);
    await say(tester, 'танигдаагүй төлөв', finalResult: true);
    expect(find.descendant(of: activeCue(), matching: find.text('МС')), findsOneWidget);
    await emit('notifyStatus', 'notListening');
    await emit('notifyStatus', 'done');
    await tester.pump(const Duration(milliseconds: 500));
    var saved = await payload(tester, 'muushig');
    expect(saved['roundPlayChoices']['Энхжин'], true, reason: saved.toString());
    // Repeating a name explicitly edits the current decision.
    await speak('Индиан өнжлөө');
    saved = await payload(tester, 'muushig');
    expect(saved['roundPlayChoices']['Энхжин'], false);
    await speak('Индиан орлоо');
    await speak('МС орлоо');
    await speak('Сыска өнжлөө');
    await speak('Шовгор өнжлөө');
    await speak('Шумуул өнжлөө');
    await speak('Базилио өнжлөө');
    saved = await payload(tester, 'muushig');
    expect(saved['roundSelectionConfirmed'], true);
    expect(activeCue(), findsOneWidget);
    expect(find.descendant(of: activeCue(), matching: find.byType(TextField)), findsOneWidget);
    await speak('Индиан өнжлөө');
    saved = await payload(tester, 'muushig');
    expect(saved['roundPlayChoices']['Энхжин'], true, reason: saved.toString());
    await speak('Индиан хоёр');
    await speak('Индиан гурав');
    saved = await payload(tester, 'muushig');
    expect(saved['roundScoreInputs']['Энхжин'], '3');

    await speak('МС хоёр');
    saved = await payload(tester, 'muushig');
    expect((saved['seats'] as List).firstWhere((s) => s['username'] == 'Энхжин')['totalScoreText'], '12');
    expect(saved['roundScoreInputs']['Энхжин'], '');
    expect(saved['roundSelectionConfirmed'], false);
    // Start in the middle: unnamed decisions rotate and wrap, then scores
    // begin at the same starting seat. A stable interim result commits once.
    await speak('Шовгор');
    await say(tester, 'орсон');
    await tester.pump(const Duration(milliseconds: 700));
    saved = await payload(tester, 'muushig');
    expect(saved['roundPlayChoices']['Баарсайхан'], true);
    expect(find.descendant(of: activeCue(), matching: find.text('Шумуул')), findsOneWidget);
    saved = await payload(tester, 'muushig');
    expect(saved['roundPlayChoices'].containsKey('Лхаямгар'), false);
    await speak('өнжсөн'); // Шумуул
    await speak('өнжлөө'); // Базилио
    await speak('орлоо'); // Индиан
    await speak('өнжсөн'); // МС
    await speak('өнжлөө'); // Сыска
    saved = await payload(tester, 'muushig');
    expect(saved['roundSelectionConfirmed'], true);
    final field = tester.widget<TextField>(find.descendant(
        of: activeCue(), matching: find.byType(TextField)));
    await speak('хоёр');
    expect(field.controller!.text, '2');
    saved = await payload(tester, 'muushig');
    expect(saved['roundScoreInputs']['Баарсайхан'], '2');
    expect(saved['roundScoreInputs']['Энхжин'], '');
    // Unrecognized speech in a fresh session leaves the current target intact.
    await say(tester, 'үндэст');
    await tester.pump(const Duration(milliseconds: 700));
    expect(field.controller!.text, '2');
    expect(tester.widget<TextField>(find.descendant(
        of: activeCue(), matching: find.byType(TextField))).controller!.text, '');
    await emit('notifyStatus', 'notListening');
    await emit('notifyStatus', 'done');
    await tester.pump(const Duration(milliseconds: 500));
    await speak('Шовгор гурав'); // correction does not change the round's start
    await speak('хоёр'); // next missing player is Индиан
    saved = await payload(tester, 'muushig');
    expect(saved['roundSelectionConfirmed'], false);
    expect(activeCue(), findsNothing); // next round needs a starting name
    // Three players: reject a wrong final score without changing its field.
    await speak('Индиан орлоо');
    await speak('орсон'); // МС
    await speak('орлоо'); // Сыска
    await speak('ороогүй'); // Шовгор
    await speak('өнжсөн'); // Шумуул
    await speak('өнжлөө'); // Базилио
    await speak('хоёр');
    await speak('2');
    final waiting = tester.widget<TextField>(find.descendant(
        of: activeCue(), matching: find.byType(TextField)));
    await speak('хоёр'); // 2 + 2 + 2 is rejected
    expect(waiting.controller!.text, '');
    expect(activeCue(), findsOneWidget);
    saved = await payload(tester, 'muushig');
    expect(saved['roundSelectionConfirmed'], true);
    expect(saved['roundScoreInputs']['Батмагнай'], '');
    // Mouse-selected final input must retain focus despite a stale voice name.
    final lastInput = find.descendant(of: activeCue(), matching: find.byType(TextField));
    await tester.tap(lastInput);
    await tester.pump();
    await speak('Индиан гурав');
    expect(waiting.focusNode!.hasFocus, true);
    expect(waiting.controller!.text, '');
    tester.testTextInput.enterText('1');
    await tester.pump();
    expect(waiting.controller!.text, '1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    saved = await payload(tester, 'muushig');
    expect(saved['roundSelectionConfirmed'], false);
    // Five tricks already taken: last player must explicitly report a fall.
    await speak('Индиан орлоо');
    await speak('орсон');
    await speak('орлоо');
    await speak('ороогүй');
    await speak('өнжсөн');
    await speak('өнжлөө');
    await speak('хоёр');
    await speak('гурав');
    await speak('нэг');
    saved = await payload(tester, 'muushig');
    expect(saved['roundScoreInputs']['Батмагнай'], '');
    expect(activeCue(), findsOneWidget);
    await speak('унасан');
    saved = await payload(tester, 'muushig');
    expect(saved['roundSelectionConfirmed'], false);
    await speak('боллоо');
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(activeCue(), findsNothing);
    await speak('Индиан орлоо');
    final stopped = await payload(tester, 'muushig');
    expect(stopped['roundPlayChoices'], saved['roundPlayChoices']);    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
