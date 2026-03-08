// Validation sandbox for 13-card poker seat/order flow.
// Run with:
//   dart lib/screens/13_card_poker_backup.dart

class ScoreCell {
  ScoreCell({
    required this.userId,
    required this.totalBefore,
    required this.rawScore,
    required this.totalAfter,
  });

  final String userId;
  final int totalBefore;
  final int rawScore;
  final int totalAfter;
}

class ExtractedRound {
  ExtractedRound({
    required this.round,
    required this.mainBefore,
    required this.cBefore,
    required this.scoreCells,
    required this.mainAfter,
    required this.cAfter,
  });

  final int round;
  final List<String> mainBefore;
  final List<String> cBefore;
  final List<ScoreCell> scoreCells;
  final List<String> mainAfter;
  final List<String> cAfter;
}

class RoundInput {
  RoundInput({
    required this.label,
    required this.mainBefore,
    required this.cBefore,
    required this.mainScores,
    required this.expectedMainAfter,
    required this.expectedCAfter,
  });

  final String label;
  final List<String> mainBefore;
  final List<String> cBefore;
  final List<int> mainScores;
  final List<String> expectedMainAfter;
  final List<String> expectedCAfter;
}

class SimulationResult {
  SimulationResult({
    required this.mainAfter,
    required this.cAfter,
    required this.totals,
  });

  final List<String> mainAfter;
  final List<String> cAfter;
  final Map<String, int> totals;
}

class SeatEngine {
  SeatEngine({required this.scoreLimit});

  final int scoreLimit;
  final Map<String, int> totals = <String, int>{};
  final List<String> pinned = <String>[];

  int _totalOf(String userId) => totals[userId] ?? 0;

  bool _isEliminated(String userId) => _totalOf(userId) >= scoreLimit;

  int _scoreContribution(int rawScore) {
    if (rawScore >= 10 && rawScore <= 12) return rawScore * 2;
    if (rawScore == 13) return rawScore * 3;
    return rawScore;
  }

  List<String> _normalizeReorderedPlayers(
    List<String> reordered,
    List<String> sourcePlayers,
  ) {
    final sourceSet = sourcePlayers.toSet();
    final normalized = <String>[];

    for (final userId in reordered) {
      if (!sourceSet.contains(userId)) continue;
      if (normalized.contains(userId)) continue;
      normalized.add(userId);
    }

    for (final userId in sourcePlayers) {
      if (!normalized.contains(userId)) {
        normalized.add(userId);
      }
    }

    if (normalized.length > sourcePlayers.length) {
      normalized.removeRange(sourcePlayers.length, normalized.length);
    }

    return normalized;
  }

  SimulationResult runRound(RoundInput input) {
    final main = List<String>.from(input.mainBefore);
    final c = List<String>.from(input.cBefore);
    final tablePlayers = <String>[...main, ...c];
    final substituteSlotCount = c.length;

    for (int i = 0; i < main.length && i < input.mainScores.length; i++) {
      final userId = main[i];
      totals[userId] =
          _totalOf(userId) + _scoreContribution(input.mainScores[i]);
    }

    final nextPinned = List<String>.from(pinned.where(tablePlayers.contains));
    if (nextPinned.length > substituteSlotCount) {
      nextPinned.removeRange(substituteSlotCount, nextPinned.length);
    }

    final nextMain = List<String>.from(main);
    final availableSubstitutes = c
        .where(
            (userId) => !_isEliminated(userId) && !nextPinned.contains(userId))
        .toList();
    final eliminatedMainThisHand = main
        .where((userId) => _isEliminated(userId))
        .where((userId) => main.contains(userId))
        .toList();

    if (eliminatedMainThisHand.isNotEmpty && availableSubstitutes.isNotEmpty) {
      final scoringMainPlayers =
          main.where((userId) => !_isEliminated(userId)).toList();
      final activeNonPinnedCount = tablePlayers
          .where((userId) =>
              !_isEliminated(userId) && !nextPinned.contains(userId))
          .length;
      final rotatingSubstituteCount = (activeNonPinnedCount - 4).clamp(0, 3) < 1
          ? 1
          : (activeNonPinnedCount - 4).clamp(0, 3);

      final scoredMain = List<MapEntry<String, int>>.generate(
        scoringMainPlayers.length,
        (index) {
          final userId = scoringMainPlayers[index];
          final seatIndex = main.indexOf(userId);
          final raw = seatIndex >= 0 && seatIndex < input.mainScores.length
              ? input.mainScores[seatIndex]
              : 0;
          return MapEntry(userId, raw);
        },
      )..sort((a, b) {
          final byScore = a.value.compareTo(b.value);
          if (byScore != 0) return byScore;
          return main.indexOf(a.key).compareTo(main.indexOf(b.key));
        });

      final movingToSubstituteByScore =
          scoredMain.take(rotatingSubstituteCount).map((e) => e.key).toList();

      final remainingSubstitutes = List<String>.from(availableSubstitutes);
      final scoreMovedApplied = <String>[];

      for (final movingOut in movingToSubstituteByScore) {
        if (remainingSubstitutes.isEmpty) break;
        final idx = nextMain.indexOf(movingOut);
        if (idx < 0) continue;
        nextMain[idx] = remainingSubstitutes.removeAt(0);
        scoreMovedApplied.add(movingOut);
      }

      for (final eliminatedUserId in eliminatedMainThisHand) {
        final loserIndex = main.indexOf(eliminatedUserId);
        if (loserIndex < 0) continue;

        final alreadyPinned = nextPinned.contains(eliminatedUserId);
        final hasSubstituteCapacity = nextPinned.length < substituteSlotCount;
        final canMoveToSubstitute = alreadyPinned || hasSubstituteCapacity;
        if (!canMoveToSubstitute) continue;

        if (!alreadyPinned) {
          nextPinned.add(eliminatedUserId);
        }

        String? incomingUserId;
        if (remainingSubstitutes.isNotEmpty) {
          incomingUserId = remainingSubstitutes.removeAt(0);
        } else if (scoreMovedApplied.isNotEmpty) {
          incomingUserId = scoreMovedApplied.removeAt(0);
        }

        if (incomingUserId != null) {
          nextMain[loserIndex] = incomingUserId;
        }
      }

      final pinnedForSlots = nextPinned.reversed.toList();
      final reordered = _normalizeReorderedPlayers(
        [
          ...nextMain,
          ...scoreMovedApplied.where((userId) => !nextPinned.contains(userId)),
          ...remainingSubstitutes,
          ...pinnedForSlots,
        ],
        tablePlayers,
      );

      pinned
        ..clear()
        ..addAll(nextPinned);

      final mainSeatCount =
          (reordered.length - substituteSlotCount).clamp(0, reordered.length);

      return SimulationResult(
        mainAfter: reordered.take(mainSeatCount).toList(),
        cAfter: reordered.skip(mainSeatCount).toList(),
        totals: Map<String, int>.from(totals),
      );
    }

    final scoringMainPlayers =
        main.where((userId) => !_isEliminated(userId)).toList();
    final activeNonPinnedCount = tablePlayers
        .where(
            (userId) => !_isEliminated(userId) && !nextPinned.contains(userId))
        .length;
    final rotatingSubstituteCount = (activeNonPinnedCount - 4).clamp(0, 3);

    if (rotatingSubstituteCount <= 0) {
      final relocatedMain = <String>[];
      final removedFromTable = <String>{};

      for (final userId in main) {
        if (!_isEliminated(userId)) {
          relocatedMain.add(userId);
          continue;
        }

        final alreadyPinned = nextPinned.contains(userId);
        final hasSubstituteCapacity = nextPinned.length < substituteSlotCount;
        final canMoveToSubstitute = alreadyPinned || hasSubstituteCapacity;

        if (!alreadyPinned && canMoveToSubstitute) {
          nextPinned.add(userId);
        }

        if (availableSubstitutes.isNotEmpty) {
          relocatedMain.add(availableSubstitutes.removeAt(0));
          continue;
        }

        if (!canMoveToSubstitute) {
          removedFromTable.add(userId);
        }
      }

      final sourcePlayersForNormalization = tablePlayers
          .where((userId) => !removedFromTable.contains(userId))
          .toList();
      final pinnedForSlots = nextPinned.reversed.toList();
      final reordered = _normalizeReorderedPlayers(
        [...relocatedMain, ...availableSubstitutes, ...pinnedForSlots],
        sourcePlayersForNormalization,
      );

      pinned
        ..clear()
        ..addAll(nextPinned);

      final mainSeatCount =
          (reordered.length - substituteSlotCount).clamp(0, reordered.length);

      return SimulationResult(
        mainAfter: reordered.take(mainSeatCount).toList(),
        cAfter: reordered.skip(mainSeatCount).toList(),
        totals: Map<String, int>.from(totals),
      );
    }

    final scoredMain = List<MapEntry<String, int>>.generate(
      scoringMainPlayers.length,
      (index) {
        final userId = scoringMainPlayers[index];
        final seatIndex = main.indexOf(userId);
        final raw = seatIndex >= 0 && seatIndex < input.mainScores.length
            ? input.mainScores[seatIndex]
            : 0;
        return MapEntry(userId, raw);
      },
    )..sort((a, b) {
        final byScore = a.value.compareTo(b.value);
        if (byScore != 0) return byScore;
        return main.indexOf(a.key).compareTo(main.indexOf(b.key));
      });

    final movingToSubstituteByScore =
        scoredMain.take(rotatingSubstituteCount).map((e) => e.key).toList();

    final remainingSubstitutes = List<String>.from(availableSubstitutes);
    final scoreMovedApplied = <String>[];
    for (final movingOut in movingToSubstituteByScore) {
      if (remainingSubstitutes.isEmpty) break;
      final idx = nextMain.indexOf(movingOut);
      if (idx < 0) continue;
      nextMain[idx] = remainingSubstitutes.removeAt(0);
      scoreMovedApplied.add(movingOut);
    }

    final pinnedForSlots = nextPinned.reversed.toList();
    final reordered = _normalizeReorderedPlayers(
      [
        ...nextMain,
        ...scoreMovedApplied.where((userId) => !nextPinned.contains(userId)),
        ...remainingSubstitutes,
        ...pinnedForSlots,
      ],
      tablePlayers,
    );

    pinned
      ..clear()
      ..addAll(nextPinned);

    final mainSeatCount =
        (reordered.length - substituteSlotCount).clamp(0, reordered.length);

    return SimulationResult(
      mainAfter: reordered.take(mainSeatCount).toList(),
      cAfter: reordered.skip(mainSeatCount).toList(),
      totals: Map<String, int>.from(totals),
    );
  }
}

bool _same(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _scoreContribution(int rawScore) {
  if (rawScore >= 10 && rawScore <= 12) return rawScore * 2;
  if (rawScore == 13) return rawScore * 3;
  return rawScore;
}

void _printComparison(RoundInput input, SimulationResult result) {
  final mainOk = _same(input.expectedMainAfter, result.mainAfter);
  final cOk = _same(input.expectedCAfter, result.cAfter);
  final status = (mainOk && cOk) ? 'PASS' : 'FAIL';

  print('\n[${input.label}] $status');
  print('  main expected: ${input.expectedMainAfter.join(', ')}');
  print('  main actual  : ${result.mainAfter.join(', ')}');
  print('  C expected   : ${input.expectedCAfter.join(', ')}');
  print('  C actual     : ${result.cAfter.join(', ')}');
}

void _validateExtractedArithmetic(List<ExtractedRound> rounds) {
  print('\n=== Extracted Arithmetic Validation (R1-R10) ===');
  int pass = 0;
  int fail = 0;

  for (final round in rounds) {
    for (final cell in round.scoreCells) {
      final expected = cell.totalBefore + _scoreContribution(cell.rawScore);
      final ok = expected == cell.totalAfter;
      if (ok) {
        pass += 1;
      } else {
        fail += 1;
      }
      final status = ok ? 'PASS' : 'FAIL';
      print(
        '[R${round.round}] $status ${cell.userId}: '
        '${cell.totalBefore} + ${cell.rawScore} => $expected '
        '(sheet: ${cell.totalAfter})',
      );
    }
  }

  print('Arithmetic summary: PASS=$pass FAIL=$fail');
}

void _validateRoundContinuity(List<ExtractedRound> rounds) {
  print('\n=== Extracted Continuity Validation (R1-R10) ===');
  int pass = 0;
  int fail = 0;

  for (int i = 0; i < rounds.length - 1; i++) {
    final current = rounds[i];
    final next = rounds[i + 1];
    final mainOk = _same(current.mainAfter, next.mainBefore);
    final cOk = _same(current.cAfter, next.cBefore);
    final ok = mainOk && cOk;

    if (ok) {
      pass += 1;
    } else {
      fail += 1;
    }

    final status = ok ? 'PASS' : 'FAIL';
    print('[R${current.round} -> R${next.round}] $status');
  }

  print('Continuity summary: PASS=$pass FAIL=$fail');
}

void main() {
  final extractedRounds = <ExtractedRound>[
    ExtractedRound(
      round: 1,
      mainBefore: ['Пат', 'Шовгор', 'МС', 'Гавар'],
      cBefore: ['Чоно', 'Шумуул', 'Үнэг'],
      scoreCells: [
        ScoreCell(userId: 'Пат', totalBefore: 0, rawScore: 5, totalAfter: 5),
        ScoreCell(userId: 'Шовгор', totalBefore: 0, rawScore: 0, totalAfter: 0),
        ScoreCell(userId: 'МС', totalBefore: 0, rawScore: 3, totalAfter: 3),
        ScoreCell(userId: 'Гавар', totalBefore: 0, rawScore: 7, totalAfter: 7),
      ],
      mainAfter: ['Үнэг', 'Чоно', 'Шумуул', 'Гавар'],
      cAfter: ['Шовгор', 'МС', 'Пат'],
    ),
    ExtractedRound(
      round: 2,
      mainBefore: ['Үнэг', 'Чоно', 'Шумуул', 'Гавар'],
      cBefore: ['Шовгор', 'МС', 'Пат'],
      scoreCells: [
        ScoreCell(userId: 'Үнэг', totalBefore: 0, rawScore: 6, totalAfter: 6),
        ScoreCell(userId: 'Чоно', totalBefore: 0, rawScore: 8, totalAfter: 8),
        ScoreCell(userId: 'Шумуул', totalBefore: 0, rawScore: 0, totalAfter: 0),
        ScoreCell(
            userId: 'Гавар', totalBefore: 7, rawScore: 10, totalAfter: 27),
      ],
      mainAfter: ['МС', 'Чоно', 'Шовгор', 'Пат'],
      cAfter: ['Шумуул', 'Үнэг', 'Гавар'],
    ),
    ExtractedRound(
      round: 3,
      mainBefore: ['МС', 'Чоно', 'Шовгор', 'Пат'],
      cBefore: ['Шумуул', 'Үнэг', 'Гавар'],
      scoreCells: [
        ScoreCell(userId: 'МС', totalBefore: 3, rawScore: 0, totalAfter: 3),
        ScoreCell(userId: 'Чоно', totalBefore: 8, rawScore: 7, totalAfter: 15),
        ScoreCell(
            userId: 'Шовгор', totalBefore: 0, rawScore: 13, totalAfter: 39),
        ScoreCell(userId: 'Пат', totalBefore: 5, rawScore: 9, totalAfter: 14),
      ],
      mainAfter: ['Шумуул', 'Чоно', 'Үнэг', 'Пат'],
      cAfter: ['МС', 'Шовгор', 'Гавар'],
    ),
    ExtractedRound(
      round: 4,
      mainBefore: ['Шумуул', 'Чоно', 'Үнэг', 'Пат'],
      cBefore: ['МС', 'Шовгор', 'Гавар'],
      scoreCells: [
        ScoreCell(userId: 'Шумуул', totalBefore: 0, rawScore: 1, totalAfter: 1),
        ScoreCell(userId: 'Чоно', totalBefore: 15, rawScore: 6, totalAfter: 21),
        ScoreCell(userId: 'Үнэг', totalBefore: 6, rawScore: 0, totalAfter: 6),
        ScoreCell(userId: 'Пат', totalBefore: 14, rawScore: 1, totalAfter: 15),
      ],
      mainAfter: ['Шумуул', 'Чоно', 'МС', 'Пат'],
      cAfter: ['Үнэг', 'Шовгор', 'Гавар'],
    ),
    ExtractedRound(
      round: 5,
      mainBefore: ['Шумуул', 'Чоно', 'МС', 'Пат'],
      cBefore: ['Үнэг', 'Шовгор', 'Гавар'],
      scoreCells: [
        ScoreCell(
            userId: 'Шумуул', totalBefore: 1, rawScore: 9, totalAfter: 10),
        ScoreCell(userId: 'Чоно', totalBefore: 21, rawScore: 0, totalAfter: 21),
        ScoreCell(userId: 'МС', totalBefore: 3, rawScore: 2, totalAfter: 5),
        ScoreCell(userId: 'Пат', totalBefore: 15, rawScore: 4, totalAfter: 19),
      ],
      mainAfter: ['Шумуул', 'Үнэг', 'МС', 'Пат'],
      cAfter: ['Чоно', 'Шовгор', 'Гавар'],
    ),
    ExtractedRound(
      round: 6,
      mainBefore: ['Шумуул', 'Үнэг', 'МС', 'Пат'],
      cBefore: ['Чоно', 'Шовгор', 'Гавар'],
      scoreCells: [
        ScoreCell(
            userId: 'Шумуул', totalBefore: 10, rawScore: 7, totalAfter: 17),
        ScoreCell(userId: 'Үнэг', totalBefore: 6, rawScore: 4, totalAfter: 10),
        ScoreCell(userId: 'МС', totalBefore: 5, rawScore: 0, totalAfter: 5),
        ScoreCell(userId: 'Пат', totalBefore: 19, rawScore: 6, totalAfter: 25),
      ],
      mainAfter: ['Шумуул', 'Үнэг', 'Чоно', 'МС'],
      cAfter: ['Пат', 'Шовгор', 'Гавар'],
    ),
    ExtractedRound(
      round: 7,
      mainBefore: ['Шумуул', 'Үнэг', 'Чоно', 'МС'],
      cBefore: ['Пат', 'Шовгор', 'Гавар'],
      scoreCells: [
        ScoreCell(
            userId: 'Шумуул', totalBefore: 17, rawScore: 4, totalAfter: 21),
        ScoreCell(userId: 'Үнэг', totalBefore: 10, rawScore: 0, totalAfter: 10),
        ScoreCell(userId: 'Чоно', totalBefore: 21, rawScore: 6, totalAfter: 27),
        ScoreCell(userId: 'МС', totalBefore: 5, rawScore: 3, totalAfter: 8),
      ],
      mainAfter: ['Шумуул', 'Үнэг', 'МС'],
      cAfter: ['Пат', 'Шовгор', 'Гавар'],
    ),
    ExtractedRound(
      round: 8,
      mainBefore: ['Шумуул', 'Үнэг', 'МС'],
      cBefore: ['Пат', 'Шовгор', 'Гавар'],
      scoreCells: [
        ScoreCell(
            userId: 'Шумуул', totalBefore: 21, rawScore: 3, totalAfter: 24),
        ScoreCell(userId: 'Үнэг', totalBefore: 10, rawScore: 0, totalAfter: 10),
        ScoreCell(userId: 'МС', totalBefore: 8, rawScore: 4, totalAfter: 12),
      ],
      mainAfter: ['Шумуул', 'Үнэг', 'МС'],
      cAfter: ['Пат', 'Шовгор', 'Гавар'],
    ),
    ExtractedRound(
      round: 9,
      mainBefore: ['Шумуул', 'Үнэг', 'МС'],
      cBefore: ['Пат', 'Шовгор', 'Гавар'],
      scoreCells: [
        ScoreCell(
            userId: 'Шумуул', totalBefore: 24, rawScore: 0, totalAfter: 24),
        ScoreCell(
            userId: 'Үнэг', totalBefore: 10, rawScore: 10, totalAfter: 30),
        ScoreCell(userId: 'МС', totalBefore: 12, rawScore: 7, totalAfter: 19),
      ],
      mainAfter: ['Шумуул', 'МС'],
      cAfter: ['Пат', 'Шовгор', 'Гавар'],
    ),
    ExtractedRound(
      round: 10,
      mainBefore: ['Шумуул', 'МС'],
      cBefore: ['Пат', 'Шовгор', 'Гавар'],
      scoreCells: [
        ScoreCell(
            userId: 'Шумуул', totalBefore: 24, rawScore: 0, totalAfter: 24),
        ScoreCell(userId: 'МС', totalBefore: 19, rawScore: 7, totalAfter: 26),
      ],
      mainAfter: ['Шумуул'],
      cAfter: ['Пат', 'Шовгор', 'Гавар'],
    ),
  ];

  _validateExtractedArithmetic(extractedRounds);
  _validateRoundContinuity(extractedRounds);

  final chainCases = <RoundInput>[];
  for (final round in extractedRounds) {
    if (round.mainBefore.length < 4) continue;
    chainCases.add(
      RoundInput(
        label: 'CHAIN R${round.round}->R${round.round + 1}',
        mainBefore: List<String>.from(round.mainBefore),
        cBefore: List<String>.from(round.cBefore),
        mainScores: round.scoreCells.map((cell) => cell.rawScore).toList(),
        expectedMainAfter: List<String>.from(round.mainAfter),
        expectedCAfter: List<String>.from(round.cAfter),
      ),
    );
  }

  final chainEngine = SeatEngine(scoreLimit: 25);
  print('\n=== Excel Chain Validation ===');
  for (final c in chainCases) {
    final result = chainEngine.runRound(c);
    _printComparison(c, result);
  }

  print('\nDone.');
}
