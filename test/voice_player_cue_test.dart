import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/widgets/voice_player_cue.dart';
import 'package:toocoob/utils/voice_player_selection.dart';

void main() {
  test('whole names switch focus and ambiguous aliases cannot select a player',
      () {
    const aliases = [
      ['шовгор', 'shovgor'],
      ['мс', 'эм эс'],
      ['мс']
    ];
    expect(lastVoicePlayerMention('шов', aliases), isNull);
    expect(lastVoicePlayerMention('шовгор хөзрөн', aliases)?.playerIndex, 0);
    expect(lastVoicePlayerMention('шовгор эм эс', aliases)?.playerIndex, 1);
    expect(lastVoicePlayerMention('мс', aliases)?.playerIndex, isNull);
    expect(lastVoicePlayerMention('шовгор мс', aliases)?.playerIndex, isNull);
    expect(lastVoicePlayerMention('хөзрөн буур', aliases), isNull);
  });

  testWidgets('cue moves while selected and resets immediately when completed',
      (tester) async {
    Widget build(bool active, {bool reduceMotion = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Center(
                child: VoicePlayerCue(
                    active: active,
                    child: const SizedBox(
                        width: 200, height: 120, child: Text('Шовгор')))),
          ),
        );
    await tester.pumpWidget(build(true));
    final origin = tester.getTopLeft(find.text('Шовгор'));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getTopLeft(find.text('Шовгор')).dx, greaterThan(origin.dx));
    await tester.pumpWidget(build(false));
    expect(tester.getTopLeft(find.text('Шовгор')), origin);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text('Шовгор')), origin);
    await tester.pumpWidget(build(true, reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getTopLeft(find.text('Шовгор')), origin);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
