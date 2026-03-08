// --- BEGIN ORIGINAL CONTENT ---
// Clean, valid 13_card_poker.dart

enum GameMode { round, multi, single }

class Player {
  final String name;
  int totalScore = 0;
  int wins = 0;
  int totalBet = 0;
  int totalGameBet = 0;
  Player(this.name);
}

class _PlayerCardReveal {
  final Player player;
  final int card;
  _PlayerCardReveal(this.player, this.card);
}

class ThirteenCardPokerGame {
  List<Player> allPlayers;
  List<Player> activeTable = [];
  List<Player> sittingOut = [];
  int roundNumber = 1;
  int booltRoundsRemaining = 0;
  bool isBoolt = false;
  int eliminationThreshold = 25;
  int booltEliminationThreshold = 30;
  List<Player> eliminated = [];
  List<Player> winners = [];
  List<Player> instantWinners = [];
  int cycleRounds = 0;
  int totalRounds = 0;
  int initialPlayerCount = 0;
  bool isMiddleBoolt = false;
  bool middleBooltPlayed = false;

  final GameMode gameMode;
  int scoreLimit;
  int betAmount;

  ThirteenCardPokerGame(
    this.allPlayers, {
    this.gameMode = GameMode.round,
    this.scoreLimit = 100,
    this.betAmount = 10,
  }) {
    _setupInitialSeating();
  }

  void addPlayerMidGame(Player player) {
    allPlayers.add(player);
    _setupInitialSeating();
    cycleRounds = allPlayers.length;
    checkBoolt();
  }

  bool shouldAskForBoolt() {
    return totalRounds >= cycleRounds;
  }

  String getBooltPrompt() {
    if (allPlayers.length + eliminated.length == 5 && allPlayers.length == 4) {
      return "Одоо боох уу? 5 тоглоод боох уу?";
    } else {
      return "Одоо боолт хийх үү?";
    }
  }

  void checkMiddleBoolt() {
    bool allWon = allPlayers.every((p) => p.wins > 0 || eliminated.contains(p));
    if (allWon && !middleBooltPlayed) {
      isMiddleBoolt = true;
      middleBooltPlayed = true;
      eliminationThreshold = 30;
    } else {
      isMiddleBoolt = false;
    }
  }

  void applyMiddleBooltScoring(Player player, int score) {
    int addScore = score * 2;
    player.totalScore += addScore;
    if (player.totalScore >= eliminationThreshold) {
      eliminated.add(player);
    }
  }

  void removePlayerMidGame(Player player) {
    allPlayers.remove(player);
    activeTable.remove(player);
    sittingOut.remove(player);
    eliminated.add(player);
    cycleRounds = allPlayers.length;
    checkBoolt();
  }

  int getRoundsUntilBoolt() {
    int played = totalRounds;
    int cycle = cycleRounds;
    int winless =
        allPlayers.where((p) => p.wins == 0 && !eliminated.contains(p)).length;
    if (played < cycle) {
      return cycle - played;
    } else {
      return winless;
    }
  }

  void updateSettings({int? newScoreLimit, int? newBetAmount}) {
    if (newScoreLimit != null) scoreLimit = newScoreLimit;
    if (newBetAmount != null) betAmount = newBetAmount;
  }

  void processRound(
      {required Map<Player, int> roundScores,
      int bet = 0,
      bool isBoolt = false}) {
    switch (gameMode) {
      case GameMode.round:
        scoreRound(roundScores);
        if (bet > 0) {
          List<Player> sorted = roundScores.keys.toList()
            ..sort((a, b) => roundScores[a]!.compareTo(roundScores[b]!));
          Player winner = sorted.first;
          calculateBet(
              players: roundScores.keys.toList(),
              winner: winner,
              bet: bet,
              isBoolt: isBoolt);
        }
        break;
      case GameMode.multi:
        scoreRound(roundScores);
        break;
      case GameMode.single:
        scoreRound(roundScores);
        break;
    }
  }

  void _setupInitialSeating() {
    List<_PlayerCardReveal> reveals =
        allPlayers.map((p) => _PlayerCardReveal(p, _randomCard())).toList();
    reveals.sort((a, b) => b.card.compareTo(a.card));

    if (initialPlayerCount == 0) {
      initialPlayerCount = allPlayers.length;
    }

    int n = allPlayers.length;
    List<Player> eliminatedThisCycle =
        eliminated.where((p) => !sittingOut.contains(p)).toList();
    sittingOut.addAll(eliminatedThisCycle);

    if (n == 4) {
      if (activeTable.isEmpty) {
        activeTable = reveals.map((r) => r.player).toList();
      }
      sittingOut = sittingOut.where((p) => !activeTable.contains(p)).toList();
    } else if (n == 2 || n == 3) {
      activeTable = reveals.map((r) => r.player).toList();
      sittingOut = sittingOut.where((p) => !activeTable.contains(p)).toList();
    } else if (n >= 5) {
      activeTable = reveals.sublist(n - 4, n).map((r) => r.player).toList();
      sittingOut = reveals.sublist(0, n - 4).map((r) => r.player).toList() +
          sittingOut.where((p) => !activeTable.contains(p)).toList();
    }
    roundNumber = 1;
    isBoolt = false;
    booltRoundsRemaining = 0;
    winners.clear();
    instantWinners.clear();
    cycleRounds = initialPlayerCount;
    totalRounds = 0;
  }

  int _randomCard() {
    return 1 + (DateTime.now().millisecondsSinceEpoch % 13);
  }

  void startNextRound() {
    roundNumber++;
    totalRounds++;
  }

  void scoreRound(Map<Player, int> roundScores) {
    List<Player> sorted = roundScores.keys.toList()
      ..sort((a, b) => roundScores[a]!.compareTo(roundScores[b]!));
    int minScore = roundScores[sorted.first]!;
    for (var player in roundScores.keys) {
      int score = roundScores[player]!;
      if (score == minScore) {
        player.wins++;
        continue;
      }
      int addScore = score;
      if (score >= 10 && score <= 12) {
        addScore *= 2;
      } else if (score == 13) {
        addScore *= 3;
      }
      player.totalScore += addScore;
      int threshold =
          isBoolt ? booltEliminationThreshold : eliminationThreshold;
      if (player.totalScore >= threshold) {
        eliminated.add(player);
      }
    }
    activeTable.removeWhere((p) => eliminated.contains(p));
    checkBoolt();
  }

  void checkBoolt() {
    // Stub for Boolt logic
  }

  void handleInstantWin(Player player) {
    instantWinners.add(player);
  }

  void calculateBet(
      {required List<Player> players,
      required Player winner,
      required int bet,
      bool isBoolt = false}) {
    int n = players.length;
    int winAmount = (n - 1) * bet;
    winner.totalBet += winAmount;
    for (var p in players) {
      if (p == winner) continue;
      p.totalBet -= bet;
    }
    winner.totalGameBet += winAmount;
  }

  Map<String, int> getFinalBetResults() {
    Map<String, int> results = {};
    for (var p in allPlayers) {
      results[p.name] = p.totalBet;
    }
    for (var p in eliminated) {
      results[p.name] = p.totalBet;
    }
    return results;
  }
}

// --- END ORIGINAL CONTENT ---
