// Working version of _handleScoreSubmit function
Future<void> _handleScoreSubmit(
  int actualIndex,
  List<int> scoreOrderIndices,
  List<QueryDocumentSnapshot> players,
) async {
  final position = scoreOrderIndices.indexOf(actualIndex);
  if (position == -1) return;

  final playerId = players[actualIndex].id;
  final raw = playerScores[actualIndex] ?? '0';
  final parsed = int.tryParse(raw.trim()) ?? 0;

  final isFirstSubmit = !_submittedScoreIndices.contains(actualIndex);

  setState(() {
    final multipliedScore = _applyScoreMultiplier(parsed);
    final newTotal = (_totalScores[playerId] ?? 0) + multipliedScore;
    _totalScores[playerId] = newTotal;

    if (isFirstSubmit) {
      _submittedScoreIndices.add(actualIndex);
      final failThreshold = _isBooltMode ? 30 : 25;
      final moneyPerPlayer = _isBooltMode ? 10000 : 5000;
      if (newTotal >= failThreshold && !_failedPlayerIds.contains(playerId)) {
        _failedPlayerIds.add(playerId);
        _lossAmounts[playerId] = (_lossAmounts[playerId] ?? 0) + moneyPerPlayer;
      }
    }
  });

  if (position < scoreOrderIndices.length - 1) {
    setState(() {
      int nextPos = position + 1;
      while (nextPos < scoreOrderIndices.length) {
        final nextIndex = scoreOrderIndices[nextPos];
        final nextPlayerId = players[nextIndex].id;
        if (!_failedPlayerIds.contains(nextPlayerId)) {
          _activeScoreIndex = nextIndex;
          break;
        }
        nextPos++;
      }
      if (nextPos >= scoreOrderIndices.length) {
        for (final idx in scoreOrderIndices) {
          if (!_failedPlayerIds.contains(players[idx].id)) {
            _activeScoreIndex = idx;
            break;
          }
        }
      }
    });
    return;
  }

  if (players.length <= 4) {
    final nonFailedCount =
        currentPlayerIds.where((id) => !_failedPlayerIds.contains(id)).length;

    if (nonFailedCount == 1) {
      final winnerId = currentPlayerIds.firstWhere(
        (id) => !_failedPlayerIds.contains(id),
        orElse: () => '',
      );

      if (winnerId.isNotEmpty) {
        final moneyPerPlayer = _isBooltMode ? 10000 : 5000;
        final totalPrize = _failedPlayerIds.length * moneyPerPlayer;

        final totalWinsAcrossPlayers =
            _winStars.values.fold<int>(0, (sum, wins) => sum + wins);
        final requiredRoundsBeforeAsking = currentPlayerIds.length;
        final willHaveEnoughRounds =
            (totalWinsAcrossPlayers + 1) >= requiredRoundsBeforeAsking;

        setState(() {
          _currentWinnerId = winnerId;
          _currentWinnerPrize = totalPrize;
          _winAmounts[winnerId] = (_winAmounts[winnerId] ?? 0) + totalPrize;
          _winStars[winnerId] = (_winStars[winnerId] ?? 0) + 1;

          if (!_isBooltMode) {
          } else {
            _isBooltMode = false;
            _booltRoundNumber = 0;
          }

          if (!willHaveEnoughRounds) {
            _gameRoundNumber++;
          }
        });

        if (willHaveEnoughRounds) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showBooltOrContinueDialog(players);
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startNextRoundDirectly();
          });
        }
      }
    } else if (nonFailedCount >= 2) {
      final totalWinsAcrossPlayers =
          _winStars.values.fold<int>(0, (sum, wins) => sum + wins);
      final requiredRoundsBeforeAsking = currentPlayerIds.length;

      if (totalWinsAcrossPlayers >= requiredRoundsBeforeAsking &&
          !_isBooltMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showBooltOrContinueDialog(players);
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            playerScores = {};
            _submittedScoreIndices = {};
            _activeScoreIndex = scoreOrderIndices.first;
          });
        });
      }
    } else {
      setState(() {
        playerScores = {};
        _submittedScoreIndices = {};
        _activeScoreIndex = scoreOrderIndices.first;
      });
    }
    return;
  }

  await _finalizeRound(players, scoreOrderIndices);
}
