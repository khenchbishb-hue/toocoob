import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/muushig_voice_command.dart';

void main() {
  test('revised accumulated speech cannot replay an old player or score', () {
    expect(muushigUnconsumedSpeech('шовгор үндэст орлоо 210 35',
        'шовгор орлоо 2'), '');
    expect(muushigUnconsumedSpeech('шовгор хоёр', 'шовгор хоёр'), '');
    expect(muushigUnconsumedSpeech('шовгор', 'шовгор хоёр'), '');
    expect(muushigUnconsumedSpeech('шовгор хоёр нэг', 'шовгор хоёр'), 'нэг');
    expect(muushigUnconsumedSpeech('шовгор гурав', ''), 'шовгор гурав');
  });
  test('oroogui means skip', () {
    expect(parseMuushigVoiceCommand('ороогүй')?.action, MuushigVoiceAction.skip);
  });
  test('voice scores cannot exceed remaining tricks and last must match', () {
    expect(validateMuushigVoiceScore(2, [null, null]).accepted, true);
    expect(validateMuushigVoiceScore(1, [2, null]).accepted, true);
    expect(validateMuushigVoiceScore(2, [2, 1]).accepted, true);
    expect(validateMuushigVoiceScore(2, [2, 2]).accepted, false);
    expect(validateMuushigVoiceScore(0, [2, 1]).accepted, false);
    expect(validateMuushigVoiceScore(4, [2, null]).accepted, false);
    expect(validateMuushigVoiceScore(0, [2, 3]).accepted, true);
    expect(validateMuushigVoiceScore(1, [2, 3]).accepted, false);
    expect(validateMuushigVoiceScore(5, [0, 0]).accepted, true);
    // Correction replaces an old value: only the other players are summed.
    expect(validateMuushigVoiceScore(3, [null, 2]).accepted, true);
  });
  test('next player decision cannot replace the preceding decision', () {
    for (final text in [
      'орлоо',
      'орлоо шов',
      'орлоо шовгор өнжлөө',
      'орлоо танигдаагүй өнжлөө',
    ]) {
      expect(parseMuushigVoiceCommand(text)?.action, MuushigVoiceAction.play);
    }
    expect(parseMuushigVoiceCommand('өнжлөө мс орлоо')?.action,
        MuushigVoiceAction.skip);
  });

  test('next player score cannot replace the preceding score', () {
    for (final text in ['2', '2 шов', '2 шовгор 3', 'хоёр шовгор 3']) {
      expect(parseMuushigVoiceCommand(text)?.score, 2);
    }
    expect(parseMuushigVoiceCommand('0 шовгор 5')?.score, 0);
    expect(parseMuushigVoiceCommand('уналаа шовгор 3')?.score, 0);
  });

  test('unknown names and unfinished commands do not supply a score', () {
    for (final text in ['', 'ор', 'өнж', 'шовгор 3', 'танигдаагүй 2', '12']) {
      expect(parseMuushigVoiceCommand(text), isNull);
    }
  });

  test('completed commands support new endings and all five scores', () {
    for (var score = 0; score <= 5; score++) {
      expect(parseMuushigVoiceCommand('$score')?.score, score);
    }
    for (final word in ['уналаа', 'унасан', 'уначихлаа', 'үсэрлээ', 'үсэрсэн', 'үсэрчихлээ', 'үхлээ', 'үхсэн']) {
      expect(parseMuushigVoiceCommand(word)?.score, 0);
    }
    expect(parseMuushigVoiceCommand('өнжлөө')?.action, MuushigVoiceAction.skip);
    expect(parseMuushigVoiceCommand('орлоо')?.action, MuushigVoiceAction.play);
    expect(parseMuushigVoiceCommand('орсон')?.action, MuushigVoiceAction.play);
    expect(parseMuushigVoiceCommand('өнжсөн')?.action, MuushigVoiceAction.skip);
  });
}
