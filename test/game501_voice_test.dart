import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toocoob/screens/501.dart';
import 'package:toocoob/utils/game501_voice.dart';
import 'package:toocoob/utils/saved_game_sessions_repository.dart';
import 'package:toocoob/widgets/voice_player_cue.dart';

void main() {
  test('rotation ranks actual points, highest suit, then original order', () {
    expect(rank501Round([
      (points: 180, suitQuality: 80, originalOrder: 0),
      (points: 180, suitQuality: 120, originalOrder: 1),
      (points: 121, suitQuality: 100, originalOrder: 2),
      (points: 0, suitQuality: 0, originalOrder: 3),
    ]), [1, 0, 2, 3]);
    expect(rank501Round([
      (points: 30, suitQuality: 0, originalOrder: 3),
      (points: 30, suitQuality: 0, originalOrder: 1),
      (points: 30, suitQuality: 0, originalOrder: 2),
      (points: 0, suitQuality: 0, originalOrder: 0),
    ]), [1, 2, 0, 3]);
    expect(score501Result(before: 501, isTaker: true, playPrice: 180,
      cardPoints: 40, suitPoints: 140, bolt: true), 321);
  });
  test('501 prices, suits and ordinary / collecting results', () {
    expect(parse501Number('зуун жаран долоо'), 167);
    expect(parse501Number('хоёр зуун дөчин нэг'), 241);
    expect(parse501Number('нойл'), 0);
    expect(parse501Number('хожлоо'), isNull);
    expect(parse501Suits('гил цэцэг').map((c) => c.suit), [0, 1]);
    expect(parse501Suits('гил хасах').single.remove, isTrue);
    expect(
        score501Result(
            before: 501,
            isTaker: true,
            playPrice: 180,
            cardPoints: 40,
            suitPoints: 140),
        321);
    expect(
        score501Result(
            before: 501,
            isTaker: true,
            playPrice: 150,
            cardPoints: 121,
            suitPoints: 0),
        651);
    expect(
        score501Result(
            before: 501,
            isTaker: false,
            playPrice: 0,
            cardPoints: 40,
            suitPoints: 60),
        401);
    expect(
        score501Result(
            before: 80,
            isTaker: true,
            playPrice: 121,
            cardPoints: 120,
            suitPoints: 120),
        201);
    expect(
        score501Result(
            before: 80,
            isTaker: true,
            playPrice: 121,
            cardPoints: 121,
            suitPoints: 0),
        0);
  });

  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  testWidgets(
      '501 staged commands, correction, other players, surrender and manual priority',
      (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'locales') return ['mn-MN:Монгол'];
      return true;
    });
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: Game501Page()));
    await tester.pump();
    Future<void> say(String words) async {
      await binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(
              'textRecognition',
              jsonEncode({
                'alternates': [
                  {'recognizedWords': words, 'confidence': 1.0}
                ],
                'resultType': 2,
              }))),
          (_) {});
      await tester.pump();
      await tester.pump();
    }

    Future<Map<String, dynamic>> payload() async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      final saved = await SavedGameSessionsRepository(
              storageKey: 'toocoob.live_game_checkpoints.v1')
          .loadSessions();
      return saved.firstWhere((s) => s.gameKey == 'game501').payload;
    }

    int cues() => find
        .byWidgetPredicate((w) => w is VoicePlayerCue && w.active)
        .evaluate()
        .length;
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    await say('Тоглогч 1');
    expect(cues(), 1);
    await say('авлаа');
    expect(cues(), 2);
    await say('120');
    expect((await payload())['takenInputs'][0], '');
    await say('167');
    await say('160');
    expect((await payload())['playInputs'][0], '');
    await say('180');
    await say('дүн');
    expect(cues(), 5);
    await say('гил');
    expect(find.text('+60'), findsOneWidget);
    await say('гил'); // Repeating a suit does not toggle it off.
    await say('цэцэг');
    await say('оноо');
    expect(cues(), 2);
    await say('40');
    expect(cues(), 5);
    var p = await payload();
    expect(p['seats'][0]['currentScore'], 321);
    await say('Тоглогч 1');
    await say('оноо');
    await say('30');
    p = await payload();
    expect(p['seats'][0]['currentScore'], 681);
    await say('Тоглогч 1');
    await say('оноо');
    await say('40');
    await say('бунд');
    await say('оноо');
    await say('60');
    p = await payload();
    expect(p['seats'][1]['currentScore'], 321);
    await say('оноо');
    await say('21');
    p = await payload();
    expect(p['seats'][2]['currentScore'], 480);
    expect(cues(), 0);
    await say('Тоглогч 1');
    await say('авлаа');
    await say('121');
    await say('150');
    await say('бууж өгье');
    p = await payload();
    expect(p['seats'][0]['currentScore'], 471);
    expect(p['seats'][1]['currentScore'], 281);
    expect(p['seats'][2]['currentScore'], 440);
    expect(p['scoreInputs'].take(3), ['', '', '']);
    await say('Тоглогч 1');
    await say('авлаа');
    final firstInput = find.byType(TextField).first;
    await tester.enterText(firstInput, '167');
    await say('190');
    expect(tester.widget<TextField>(firstInput).controller!.text, '167');
    await say('боллоо');
    expect(cues(), 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));

    // Four-player surrender deducts only 30 per opponent, ignoring draft suits.
    p['activeSeatCount'] = 4;
    p['recommendedSeat'] = null;
    p['roundBefore501'] = <String, int>{};
    for (var i = 0; i < 4; i++) {
      p['seats'][i]['currentScore'] = 501;
      p['takenInputs'][i] = '';
      p['playInputs'][i] = '';
      p['scoreInputs'][i] = '';
      p['selectedButtons'][i] = <int>[];
    }
    final repository = SavedGameSessionsRepository();
    final fourId = await repository.saveOrUpdate(
        gameKey: 'game501', gameLabel: '501', selectedUserIds: [], payload: p);
    await tester.pumpWidget(
        MaterialApp(home: Game501Page(initialSavedSessionId: fourId)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    await say('Тоглогч 1');
    await say('авлаа');
    await say('150');
    await say('180');
    await say('дүн');
    await say('гил');
    await say('бууж өгье');
    p = await payload();
    expect(p['seats'][0]['currentScore'], 681);
    for (var i = 1; i < 4; i++) {
      expect(p['seats'][i]['currentScore'], 471);
    }
    expect(p['selectedButtons'][0], isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));

    // A low-score taker cannot use a suit to make up missing card points.
    p['seats'][0]['currentScore'] = 80;
    p['autoCorrectSeats'] = [0];
    p['recommendedSeat'] = 0;
    p['takenInputs'][0] = '121';
    p['playInputs'][0] = '121';
    final lowId = await repository.saveOrUpdate(
        gameKey: 'game501', gameLabel: '501', selectedUserIds: [], payload: p);
    await tester.pumpWidget(
        MaterialApp(home: Game501Page(initialSavedSessionId: lowId)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.mic));
    await tester.pump();
    await say('Тоглогч 1');
    expect(cues(), 2);
    await say('гил');
    await say('120');
    p = await payload();
    expect(p['seats'][0]['currentScore'], 201);
    await say('Тоглогч 1');
    await say('оноо');
    await say('121');
    p = await payload();
    expect(p['seats'][0]['wins'], 1);
    expect(p['seats'][0]['currentScore'], 501);
    expect(cues(), 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));

    p['activeSeatCount'] = 6;
    p['originalOrder501'] = [for (var i = 1; i <= 6; i++) 'seat_$i'];
    p['recommendedSeat'] = null;
    p['autoCorrectSeats'] = [];
    final sixId = await repository.saveOrUpdate(
        gameKey: 'game501', gameLabel: '501', selectedUserIds: [], payload: p);
    await tester.pumpWidget(MaterialApp(home: Game501Page(initialSavedSessionId: sixId)));
    await tester.pump(); await tester.pump();
    await tester.tap(find.byIcon(Icons.mic)); await tester.pump();
    await say('Тоглогч 1'); await say('авлаа'); await say('167'); await say('180');
    await say('дүн'); await say('гил'); await say('цэцэг'); await say('оноо'); await say('40');
    await say('бунд'); await say('оноо'); await say('60');
    await say('дөрвөлжин'); await say('оноо'); await say('21');
    await say('оноо'); await say('0');
    p = await payload();
    expect(p['seats'].take(6).map((s) => s['displayName']),
      ['Тоглогч 6', 'Тоглогч 5', 'Тоглогч 3', 'Тоглогч 4', 'Тоглогч 2', 'Тоглогч 1']);
    expect(p['seats'][4]['currentScore'], 321);
    expect(p['seats'][5]['currentScore'], 321);
    expect(p['originalOrder501'], [for (var i = 1; i <= 6; i++) 'seat_$i']);
    await tester.pumpWidget(const SizedBox()); await tester.pump(const Duration(seconds: 2));
  });
}
