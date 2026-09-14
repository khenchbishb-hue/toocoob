import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

const String kSavedGameSessionsKey = 'toocoob.saved_game_sessions.v1';

class SavedGameSession {
  SavedGameSession({
    required this.id,
    required this.gameKey,
    required this.gameLabel,
    required this.selectedUserIds,
    required this.createdAt,
    required this.updatedAt,
    required this.payload,
  });

  final String id;
  final String gameKey;
  final String gameLabel;
  final List<String> selectedUserIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;

  SavedGameSession copyWith({
    DateTime? updatedAt,
    Map<String, dynamic>? payload,
    List<String>? selectedUserIds,
  }) {
    return SavedGameSession(
      id: id,
      gameKey: gameKey,
      gameLabel: gameLabel,
      selectedUserIds:
          List<String>.from(selectedUserIds ?? this.selectedUserIds),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payload: payload ?? this.payload,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameKey': gameKey,
        'gameLabel': gameLabel,
        'selectedUserIds': selectedUserIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'payload': payload,
      };

  static SavedGameSession fromJson(Map<String, dynamic> json) {
    final rawIds = (json['selectedUserIds'] as List? ?? const <dynamic>[]);
    return SavedGameSession(
      id: (json['id'] ?? '').toString(),
      gameKey: (json['gameKey'] ?? '').toString(),
      gameLabel: (json['gameLabel'] ?? '').toString(),
      selectedUserIds: rawIds.map((e) => e.toString()).toList(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      payload: Map<String, dynamic>.from(
          json['payload'] as Map? ?? const <String, dynamic>{}),
    );
  }
}

class SavedGameSessionsRepository {
  SavedGameSessionsRepository({this.storageKey = kSavedGameSessionsKey});

  final String storageKey;
  static Future<void> _writeQueue = Future<void>.value();
  static Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _writeQueue.then((_) => operation());
    _writeQueue =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<List<SavedGameSession>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.trim().isEmpty) return <SavedGameSession>[];

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final list = (decoded['sessions'] as List? ?? const <dynamic>[]);
      final sessions = list
          .whereType<Map>()
          .map((e) => SavedGameSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } catch (_) {
      return <SavedGameSession>[];
    }
  }

  Future<void> saveSessions(List<SavedGameSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'updatedAt': DateTime.now().toIso8601String(),
      'sessions': sessions.map((e) => e.toJson()).toList(),
    };
    await prefs.setString(storageKey, jsonEncode(payload));
  }

  Future<String> saveOrUpdate({
    String? sessionId,
    required String gameKey,
    required String gameLabel,
    required List<String> selectedUserIds,
    required Map<String, dynamic> payload,
  }) =>
      _serialize(() => _saveOrUpdate(
          sessionId: sessionId,
          gameKey: gameKey,
          gameLabel: gameLabel,
          selectedUserIds: selectedUserIds,
          payload: payload));

  Future<String> _saveOrUpdate({
    String? sessionId,
    required String gameKey,
    required String gameLabel,
    required List<String> selectedUserIds,
    required Map<String, dynamic> payload,
  }) async {
    final sessions = await loadSessions();
    final now = DateTime.now();
    final id = sessionId ?? '${gameKey}_${now.microsecondsSinceEpoch}';
    final existingIndex = sessions.indexWhere((e) => e.id == id);

    if (existingIndex >= 0) {
      final existing = sessions[existingIndex];
      sessions[existingIndex] = existing.copyWith(
        updatedAt: now,
        selectedUserIds: selectedUserIds,
        payload: payload,
      );
    } else {
      sessions.add(
        SavedGameSession(
          id: id,
          gameKey: gameKey,
          gameLabel: gameLabel,
          selectedUserIds: List<String>.from(selectedUserIds),
          createdAt: now,
          updatedAt: now,
          payload: payload,
        ),
      );
    }

    await saveSessions(sessions);
    return id;
  }

  Future<SavedGameSession?> findById(String id) async {
    final sessions = await loadSessions();
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> removeById(String id) => _serialize(() => _removeById(id));

  Future<void> _removeById(String id) async {
    final sessions = await loadSessions();
    sessions.removeWhere((e) => e.id == id);
    await saveSessions(sessions);
  }

  Future<SavedGameSession?> findLatestByGameAndPlayers({
    required String gameKey,
    required List<String> selectedUserIds,
  }) async {
    final sessions = await loadSessions();
    final target = selectedUserIds.toSet();
    if (target.isEmpty) return null;

    for (final session in sessions) {
      if (session.gameKey != gameKey) continue;
      final sessionPlayers = session.selectedUserIds.toSet();
      if (sessionPlayers.length == target.length &&
          sessionPlayers.containsAll(target)) {
        return session;
      }
    }
    return null;
  }

  Future<List<SavedGameSession>> findUnfinishedByPlayers(
      List<String> selectedUserIds) async {
    final target = selectedUserIds.toSet();
    if (target.isEmpty) return [];
    return (await loadSessions()).where((session) {
      final players = session.selectedUserIds.toSet();
      final p = session.payload;
      return !session.id.startsWith('live_') &&
          players.length == target.length && players.containsAll(target) &&
          p['sessionCompleted'] != true && p['completed'] != true &&
          p['championBlockIndex'] == null && p['winnerPlayerKey'] == null;
    }).toList();
  }
}
