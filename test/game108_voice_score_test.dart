import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/game108_voice_score.dart';
import 'package:toocoob/utils/poker_voice_score.dart';

void main() {
  test('108 zero aliases include the seven card', () {
    for (final text in ['0', 'тэг', 'нойл', '7', 'долоо', '7 оноо', 'нойл оноо']) {
      expect(parseGame108VoiceScore(text), 0, reason: text);
    }
    expect(parseGame108VoiceScore('17'), 17);
    expect(parseGame108VoiceScore('далан долоо'), 77);
    expect(parseGame108VoiceScore('танигдаагүй'), isNull);
    expect(parsePokerVoiceScore('7'), 7);
    expect(parsePokerVoiceScore('долоо'), 7);
  });
}
