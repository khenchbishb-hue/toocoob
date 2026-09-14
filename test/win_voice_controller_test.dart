import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/win_voice_controller.dart';
void main() {
  test('threshold and start phrases are distinct from scoring commands', () {
    expect(parseWinThreshold('босго 3'), 3);
    expect(parseWinThreshold('хожлын босго гурав'), 3);
    expect(parseWinThreshold('хожлоо'), isNull);
    expect(parseWinThreshold('баг 3'), isNull);
    for (final phrase in ['эхлэе', 'тоглолт эхлүүл', 'тоглоё']) {
      expect(isStartGameCommand(phrase), isTrue);
    }
    expect(isStartGameCommand('хожлоо'), isFalse);
    expect(isStartGameCommand('эхлүүлэх'), isFalse);
  });
  test('correction aliases undo one win', () {
    for (final word in ['хасах', 'буцаах', 'засвар', 'засах', 'буруу']) {
      expect(parseWinVoiceAction(word), -1);
    }
    expect(parseWinVoiceAction('хожлоо'), 1);
  });
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
  testWidgets('shared win voice selects, adds, corrects, and stops', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'locales') return ['mn-MN:Монгол'];
      return true;
    });
    final wins = [0, 0];
    final voice = WinVoiceController(names: () => [['Шовгор'], ['МС']],
      canEdit: () => true, apply: (i, delta) {
        if (wins[i] + delta < 0) return false;
        wins[i] += delta; return true;
      });
    Future<void> say(String text) async {
      await binding.defaultBinaryMessenger.handlePlatformMessage(channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('textRecognition', jsonEncode({
          'alternates': [{'recognizedWords': text, 'confidence': 1.0}], 'resultType': 2,
        }))), (_) {});
      await tester.pump();
      await tester.pump();
    }
    await voice.toggle();
    await say('Шовгор');
    expect(voice.target, 0);
    await say('хожлоо');
    expect(wins, [1, 0]);
    expect(voice.target, null);
    await say('хожлоо');
    expect(wins, [1, 0]); // A fresh action always requires a name.
    await say('Шовгор хасах');
    expect(wins, [0, 0]);
    await say('боллоо');
    expect(voice.enabled, false);
    voice.dispose();
  });
}
