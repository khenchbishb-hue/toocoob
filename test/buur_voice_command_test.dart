import 'package:flutter_test/flutter_test.dart';
import 'package:toocoob/utils/buur_voice_command.dart';

void main() {
  test('short spoken aliases work alone and after a player name', () {
    const aliases = {'оноо хүрлээ': 1, 'оноо': 1, '31': 1, 'гучин нэг': 1,
      'хөзөр': 2, 'тамга': 3, 'хайбар': 3, 'хайбар сэнгээ': 3,
      'ботго': 4, 'гурван 7': 4, 'гурван долоо': 4};
    for (final entry in aliases.entries) {
      expect(parseBuurVoiceAction(entry.key), entry.value);
      expect(parseBuurVoiceCommand('Шовгор ${entry.key}', [['Шовгор']]),
          (playerIndex: 0, transfer: entry.value));
    }
  });
  const names = [
    ['Шовгор', 'shovgor'],
    ['МС', 'ms']
  ];
  test('resolves each named player independently', () {
    expect(parseBuurVoiceCommand('Шовгор хөзрөн буур', names),
        (playerIndex: 0, transfer: 2));
    expect(parseBuurVoiceCommand('МС хөзрөн буур', names),
        (playerIndex: 1, transfer: 2));
    expect(parseBuurVoiceCommand(' SHOVGOR хөзрийн буур!', names),
        (playerIndex: 0, transfer: 2));
  });
  test('all four commands map to their existing chip amounts', () {
    const commands = {
      'тоо хүрлээ': 1,
      'хөзрөн буур': 2,
      'тамган буур': 3,
      'ботгон буур': 4
    };
    for (final entry in commands.entries) {
      expect(parseBuurVoiceCommand('Шовгор ${entry.key}', names),
          (playerIndex: 0, transfer: entry.value));
      expect(parseBuurVoiceCommand('МС ${entry.key}', names),
          (playerIndex: 1, transfer: entry.value));
      expect(parseBuurVoiceCommand(entry.key, names), isNull);
    }
  });
  test('rejects unfinished, unknown and combined commands', () {
    for (final text in [
      'Шовгор хөзрөн',
      'хөзрөн буур',
      'Бат хөзрөн буур',
      'Шовгор тамган',
      'МС ботгон',
      'МС тоо',
      'МС тоо хүр',
      'Шовгор тамган буур МС ботгон буур',
      'Шовгор хөзрөн буур МС хөзрөн буур'
    ]) {
      expect(parseBuurVoiceCommand(text, names), isNull);
    }
  });
  test('rejects ambiguous names', () {
    expect(
        parseBuurVoiceCommand('Шовгор хөзрөн буур', [
          ['Шовгор'],
          ['Шовгор']
        ]),
        isNull);
  });
  test('recognizes spoken names for Latin usernames', () {
    const players = [
      ['shovgor'],
      ['ms'],
      ['syska'],
      ['shuumul'],
      ['indian']
    ];
    for (final entry in {
      'шовгор': 0,
      'эм эс': 1,
      'мс': 1,
      'сисга': 2,
      'шумуул': 3,
      'индиан': 4
    }.entries) {
      expect(parseBuurVoiceCommand('${entry.key} тамган буур', players),
          (playerIndex: entry.value, transfer: 3));
    }
  });
  test('spoken aliases cannot select an ambiguous player', () {
    expect(
        parseBuurVoiceCommand('эм эс тамган буур', [
          ['ms'],
          ['Эм Эс']
        ]),
        isNull);
  });
  test('recognizes the screenshot transcript once', () {
    expect(
        parseBuurVoiceCommand(
            'шовгор өдөр шовгор хөзрэн буусан шовгор хөзрөн буурсан боллоо',
            names),
        (playerIndex: 0, transfer: 2));
    expect(parseBuurVoiceCommand('Шовгор хөзрөн буур боллоо', names),
        (playerIndex: 0, transfer: 2));
    expect(
        parseBuurVoiceCommand('Шовгор хөзрөн буур Шовгор хөзрөн буур', names),
        (playerIndex: 0, transfer: 2));
  });
  test('retries cannot change the player or amount', () {
    for (final text in [
      'МС хөзрөн Шовгор хөзрөн буур боллоо',
      'Шовгор тамган буур Шовгор хөзрөн буур боллоо',
      'Шовгор хөзрөн буур Шовгор хөзрөн',
      'Шовгор үгүй хөзрөн буур боллоо',
      'Бат хөзрөн буур Шовгор хөзрөн буур',
    ]) {
      expect(parseBuurVoiceCommand(text, names), isNull, reason: text);
    }
  });
  test('completion marker is optional for a complete named command', () {
    for (final ending in ['', ' боллоо']) {
      expect(parseBuurVoiceCommand('Шовгор хөзрөн буур$ending', names),
          (playerIndex: 0, transfer: 2));
    }
    expect(parseBuurVoiceCommand('боллоо', names), isNull);
  });
  test('acknowledged players accept each action without repeating the name',
      () {
    for (final entry in {
      'тоо хүрлээ': 1,
      'хөзрөн буур': 2,
      'тамган буур': 3,
      'ботгон буур': 4
    }.entries) {
      expect(parseBuurVoiceAction(entry.key), entry.value);
      expect(parseBuurVoiceAction('${entry.key} боллоо'), entry.value);
    }
    for (final fragment in ['тоо', 'тоо хүр', 'хөзрөн', 'тамган', 'ботгон']) {
      expect(isBuurVoiceActionPrefix(fragment), isTrue);
      expect(parseBuurVoiceAction(fragment), isNull);
    }
    for (final invalid in [
      'буур',
      'Бат тамган буур',
      'үгүй тамган буур',
      'тамган буур ботгон буур'
    ]) {
      expect(parseBuurVoiceAction(invalid), isNull);
    }
  });
}
