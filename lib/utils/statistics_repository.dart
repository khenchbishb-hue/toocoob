import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String kStatisticsStoreKey = 'toocoob.statistics.sessions.v1';

class StatsPlayerResult {
  StatsPlayerResult({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.money,
  });

  final String userId;
  final String username;
  final String displayName;
  final int money;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'username': username,
        'displayName': displayName,
        'money': money,
      };

  static StatsPlayerResult fromJson(Map<String, dynamic> json) {
    return StatsPlayerResult(
      userId: (json['userId'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      money: (json['money'] as num? ?? 0).toInt(),
    );
  }
}

class StatsSession {
  StatsSession({
    required this.sessionId,
    required this.gameKey,
    required this.gameLabel,
    required this.playedAt,
    required this.players,
    required this.totalRounds,
  });

  final String sessionId;
  final String gameKey;
  final String gameLabel;
  final DateTime playedAt;
  final List<StatsPlayerResult> players;
  final int totalRounds;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'gameKey': gameKey,
        'gameLabel': gameLabel,
        'playedAt': playedAt.toIso8601String(),
        'totalRounds': totalRounds,
        'players': players.map((p) => p.toJson()).toList(),
      };

  static StatsSession fromJson(Map<String, dynamic> json) {
    final rawPlayers = (json['players'] as List? ?? const <dynamic>[]);
    return StatsSession(
      sessionId: (json['sessionId'] ?? '').toString(),
      gameKey: (json['gameKey'] ?? '').toString(),
      gameLabel: (json['gameLabel'] ?? '').toString(),
      playedAt: DateTime.tryParse((json['playedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      totalRounds: (json['totalRounds'] as num? ?? 0).toInt(),
      players: rawPlayers
          .whereType<Map>()
          .map((e) => StatsPlayerResult.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

enum StatsPeriod { all, month, quarter, year }

class StatsRepository {
  Future<List<StatsSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kStatisticsStoreKey);
    if (raw == null || raw.trim().isEmpty) return <StatsSession>[];

    try {
      final decoded = jsonDecode(raw);
      final rawSessions = (decoded is Map<String, dynamic>
              ? decoded['sessions']
              : decoded) as List? ??
          const <dynamic>[];
      return rawSessions
          .whereType<Map>()
          .map((e) => StatsSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <StatsSession>[];
    }
  }

  Future<void> saveSessions(List<StatsSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'updatedAt': DateTime.now().toIso8601String(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
    };
    await prefs.setString(kStatisticsStoreKey, jsonEncode(payload));
  }

  Future<void> addSession(StatsSession session) async {
    final sessions = await loadSessions();
    final exists = sessions.any((s) => s.sessionId == session.sessionId);
    if (!exists) {
      sessions.add(session);
      await saveSessions(sessions);
    }
  }

  List<StatsSession> filterByPeriod(
    List<StatsSession> sessions,
    StatsPeriod period,
    DateTime anchor,
  ) {
    if (period == StatsPeriod.all) return sessions;

    DateTime start;
    DateTime end;

    if (period == StatsPeriod.month) {
      start = DateTime(anchor.year, anchor.month, 1);
      end = DateTime(anchor.year, anchor.month + 1, 1);
    } else if (period == StatsPeriod.quarter) {
      final quarterStartMonth = ((anchor.month - 1) ~/ 3) * 3 + 1;
      start = DateTime(anchor.year, quarterStartMonth, 1);
      end = DateTime(anchor.year, quarterStartMonth + 3, 1);
    } else {
      start = DateTime(anchor.year, 1, 1);
      end = DateTime(anchor.year + 1, 1, 1);
    }

    return sessions
        .where((s) => !s.playedAt.isBefore(start) && s.playedAt.isBefore(end))
        .toList();
  }

  Map<String, int> aggregateMoneyByPlayer(List<StatsSession> sessions) {
    final result = <String, int>{};
    for (final session in sessions) {
      for (final player in session.players) {
        final key = '${player.displayName} (@${player.username})';
        result[key] = (result[key] ?? 0) + player.money;
      }
    }
    return result;
  }

  Map<String, int> aggregateMoneyByGame(List<StatsSession> sessions) {
    final result = <String, int>{};
    for (final session in sessions) {
      int sessionTotal = 0;
      for (final p in session.players) {
        sessionTotal += p.money;
      }
      result[session.gameLabel] =
          (result[session.gameLabel] ?? 0) + sessionTotal;
    }
    return result;
  }

  Map<String, int> countSessionsByGame(List<StatsSession> sessions) {
    final result = <String, int>{};
    for (final session in sessions) {
      result[session.gameLabel] = (result[session.gameLabel] ?? 0) + 1;
    }
    return result;
  }
}
