import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/poker_voice_score.dart';
void main() {
  test('poker scores accept signed integers and Mongolian words', () {
    expect(parsePokerVoiceScore('арван гурав'), 13);
    expect(parsePokerVoiceScore('хасах арван хоёр оноо'), -12);
    expect(parsePokerVoiceScore('0'), 0);
    expect(parsePokerVoiceScore('1331'), 1331);
    expect(parsePokerVoiceScore('хоёр гурав'), null);
    expect(parsePokerVoiceScore('орлоо'), null);
    expect(parsePokerVoiceScore('2.5'), null);
  });
}
