import 'dart:async';
import 'dart:convert';
import 'live_game_transport.dart';
import 'package:flutter/material.dart';
import 'saved_game_sessions_repository.dart';

/// Live checkpoints and explicit saved games use separate storage.
class LiveGameSessionsRepository extends SavedGameSessionsRepository {
  LiveGameSessionsRepository(
      {LiveGameTransport Function(String)? transportFactory})
      : _transportFactory = transportFactory ?? FirestoreLiveGameTransport.new;
  static final Object _checkpointZone = Object();
  final SavedGameSessionsRepository _checkpoints = SavedGameSessionsRepository(
      storageKey: 'toocoob.live_game_checkpoints.v1');

  /// Unsaved games stay temporary; saved games continue updating their save.
  Future<void> checkpoint(Future<void> Function() capture) =>
      runZoned(capture, zoneValues: {_checkpointZone: true});

  @override
  Future<SavedGameSession?> findById(String id) async {
    final saved = await super.findById(id);
    if (saved != null) {
      _manualId = saved.id;
      return saved;
    }
    final checkpoint = await _checkpoints.findById(id);
    _manualId = checkpoint?.payload['_savedGameId'] as String? ?? _manualId;
    return checkpoint;
  }

  Future<void> _updateSavedGame(SavedGameSession state) async {
    _manualId = state.payload['_savedGameId'] as String? ?? _manualId;
    if (_manualId == null) return;
    await super.saveOrUpdate(
        sessionId: _manualId,
        gameKey: state.gameKey,
        gameLabel: state.gameLabel,
        selectedUserIds: state.selectedUserIds,
        payload: Map<String, dynamic>.from(state.payload)
          ..remove('_livePendingRevision'));
  }

  final LiveGameTransport Function(String) _transportFactory;
  final ValueNotifier<String> status = ValueNotifier('Ачаалж байна…');
  LiveGameTransport? _transport;
  Map<String, dynamic>? _deferred;
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  Future<void> Function(SavedGameSession)? _restore;
  String? Function()? registrar;
  String? _owner;
  String? _uid;
  String? _id;
  String? get checkpointId => _id;
  String? _manualId;
  int _revision = 0;
  String? _accepted;
  String? _localHash;
  SavedGameSession? _pending;
  SavedGameSession? _recovery;
  bool _writing = false;
  bool _applying = false;
  bool _closed = false;
  bool ready = false;
  bool localOnly = false;
  String? _serverRegistrar;
  bool get canEdit =>
      ready &&
      (localOnly || (_uid != null && _uid == (_serverRegistrar ?? _owner)));

  Future<void> connect(
      String? lockId, Future<void> Function(SavedGameSession) restore,
      {bool onlyLocal = false}) async {
    _restore = restore;
    if (lockId == null || onlyLocal) {
      if (lockId != null) _id = 'live_$lockId';
      localOnly = true;
      ready = true;
      status.value = 'Тоглолтын явцыг хамгаалж байна';
      return;
    }
    _transport = _transportFactory(lockId);
    _uid = _transport!.userId;
    try {
      _owner = await _transport!.ownerId();
      if (_closed) return;
      _id = 'live_$lockId';
      _recovery = await _checkpoints.findById(_id!);
      final first = Completer<void>();
      _subscription = _transport!.watch().asyncMap((data) async {
        try {
          if (_closed) return data;
          if (!_writing && !_applying) {
            await _receive(data);
          } else {
            _deferred = data;
          }
          ready = true;
          if (!_closed) {
            status.value = canEdit ? 'Синк идэвхтэй' : 'Шууд үзэж байна';
          }
          if (!first.isCompleted) first.complete();
        } catch (error) {
          if (!_closed) status.value = 'Синк сэргээж чадсангүй';
          if (!first.isCompleted) first.completeError(error);
        }
        return data;
      }).listen((_) {}, onError: (Object error) {
        if (!_closed) status.value = 'Синк холбогдсонгүй';
        if (!first.isCompleted) first.completeError(error);
      });
      await first.future;
    } catch (_) {
      if (!_closed) status.value = 'Синк холбогдсонгүй — дахин нээнэ үү';
    }
  }

  Future<void> _receive(Map<String, dynamic>? data) async {
    final recovery = _recovery;
    _recovery = null;
    final serverRevision = (data?['revision'] as num?)?.toInt() ?? 0;
    if (recovery != null &&
        recovery.payload['_livePendingRevision'] == serverRevision &&
        _uid == (data?['registrarUserId'] ?? _owner)) {
      final recoveredPayload = Map<String, dynamic>.from(recovery.payload)
        ..remove('_livePendingRevision');
      final recovered = recovery.copyWith(payload: recoveredPayload);
      _revision = serverRevision;
      _serverRegistrar = data?['registrarUserId'] as String? ?? _owner;
      _pending = recovered;
      _localHash = jsonEncode(recoveredPayload);
      _applying = true;
      try {
        await _restore!(recovered);
        await _updateSavedGame(recovered);
      } finally {
        _applying = false;
      }
      return;
    }
    if (data == null) return;
    final revision = (data['revision'] as num?)?.toInt() ?? 0;
    if (revision <= _revision) return;
    final raw = data['payloadJson'] as String?;
    if (raw == null) return;
    final saved = SavedGameSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
    final hash = jsonEncode(saved.payload);
    _serverRegistrar =
        saved.payload['currentRegistrarUserId'] as String? ?? _owner;
    if (hash == _accepted) {
      _revision = revision;
      return;
    }
    _pending = null;
    _applying = true;
    try {
      await _restore!(saved);
      await _updateSavedGame(saved);
      await _checkpoints.saveOrUpdate(
          sessionId: _id,
          gameKey: saved.gameKey,
          gameLabel: saved.gameLabel,
          selectedUserIds: saved.selectedUserIds,
          payload: saved.payload);
      _revision = revision;
      _accepted = hash;
      _localHash = hash;
    } finally {
      _applying = false;
    }
  }

  @override
  Future<String> saveOrUpdate(
      {String? sessionId,
      required String gameKey,
      required String gameLabel,
      required List<String> selectedUserIds,
      required Map<String, dynamic> payload}) async {
    if (Zone.current[_checkpointZone] != true) {
      if (!ready || _closed || _applying || !canEdit) {
        throw StateError('Тоглолт хадгалахад бэлэн биш байна.');
      }
      final savedId = _manualId ??
          (sessionId != null && !sessionId.startsWith('live_')
              ? sessionId
              : (_id == null ? null : 'saved_$_id'));
      // Freeze the current input before asynchronous persistence.
      final frozen =
          Map<String, dynamic>.from(jsonDecode(jsonEncode(payload)) as Map);
      final result = await super.saveOrUpdate(
          sessionId: savedId,
          gameKey: gameKey,
          gameLabel: gameLabel,
          selectedUserIds: List<String>.from(selectedUserIds),
          payload: frozen);
      _manualId = result;
      _localHash = null;
      return result;
    }
    final id = _id ??=
        'live_local_${gameKey}_${DateTime.now().microsecondsSinceEpoch}';
    if (!ready || _closed || _applying || !canEdit) return id;
    final frozen = Map<String, dynamic>.from(jsonDecode(jsonEncode({
      ...payload,
      if (_manualId != null) '_savedGameId': _manualId,
      'currentRegistrarUserId': registrar?.call() ?? _owner,
    })) as Map);
    final hash = jsonEncode(frozen);
    if (_localHash != hash) {
      final now = DateTime.now();
      await _updateSavedGame(SavedGameSession(
          id: id, gameKey: gameKey, gameLabel: gameLabel,
          selectedUserIds: selectedUserIds, createdAt: now, updatedAt: now,
          payload: frozen));
      await _checkpoints.saveOrUpdate(
          sessionId: id,
          gameKey: gameKey,
          gameLabel: gameLabel,
          selectedUserIds: selectedUserIds,
          payload: {
            ...frozen,
            if (!localOnly) '_livePendingRevision': _revision
          });
      _localHash = hash;
    }
    if (!localOnly && hash != _accepted) {
      final now = DateTime.now();
      _pending = SavedGameSession(
          id: id,
          gameKey: gameKey,
          gameLabel: gameLabel,
          selectedUserIds: selectedUserIds,
          createdAt: now,
          updatedAt: now,
          payload: frozen);
      unawaited(flush());
    }
    return sessionId ?? id;
  }

  Future<void> flush() async {
    if (_writing || _applying || _pending == null || _transport == null) return;
    _writing = true;
    final saved = _pending!;
    final baseRevision = _revision;
    final raw = jsonEncode(saved.toJson());
    var succeeded = false;
    try {
      final conflicting = await _transport!.compareAndSet(baseRevision, {
        'stateKey': 'session',
        'gameKey': saved.gameKey,
        'writerUserId': _uid,
        'playerUserIds': saved.selectedUserIds,
        'savedSessionId': saved.id,
        'registrarUserId': saved.payload['currentRegistrarUserId'],
        'payloadJson': raw,
      });
      if (conflicting != null) {
        if (!_closed) await _receive(conflicting);
        if (!_closed) status.value = 'Өөр төхөөрөмжийн шинэ төлвийг авлаа';
      } else {
        succeeded = true;
        _revision = baseRevision + 1;
        _accepted = jsonEncode(saved.payload);
        _serverRegistrar =
            saved.payload['currentRegistrarUserId'] as String? ?? _owner;
        if (identical(saved, _pending)) {
          _pending = null;
          await _checkpoints.saveOrUpdate(
              sessionId: saved.id,
              gameKey: saved.gameKey,
              gameLabel: saved.gameLabel,
              selectedUserIds: saved.selectedUserIds,
              payload: saved.payload);
        } else if (_pending != null) {
          final pending = _pending!;
          await _checkpoints.saveOrUpdate(
              sessionId: pending.id,
              gameKey: pending.gameKey,
              gameLabel: pending.gameLabel,
              selectedUserIds: pending.selectedUserIds,
              payload: {...pending.payload, '_livePendingRevision': _revision});
        }
        if (!_closed) {
          status.value = canEdit ? 'Хадгалагдлаа' : 'Шууд үзэж байна';
        }
      }
    } catch (_) {
      if (!_closed) status.value = 'Төхөөрөмжид хадгалсан · синк хүлээж байна';
    } finally {
      _writing = false;
      final deferred = _deferred;
      _deferred = null;
      if (!_closed && deferred != null) await _receive(deferred);
      if (_closed && succeeded && _pending != null) unawaited(flush());
    }
  }

  @override
  Future<void> removeById(String id) async {
    // Live checkpoints remain available until the table itself is closed.
    if (_transport != null && id == _id) return;
    await super.removeById(id);
    if (_manualId == id) _manualId = null;
  }

  void close() {
    _closed = true;
    _subscription?.cancel();
    unawaited(flush());
  }
}

mixin LiveGameState<T extends StatefulWidget> on State<T> {
  LiveGameSessionsRepository get liveRepository;
  Future<void> saveLiveProgress();
  Future<void> restoreLiveProgress(SavedGameSession saved);
  String? get liveRegistrar;
  bool get usesSeparateTableSync => false;
  void onLiveReady() {}
  Future<void> _initialization = Future<void>.value();
  Timer? _liveTimer;
  AppLifecycleListener? _liveLifecycle;
  bool _savingLive = false;
  bool _stoppingLive = false;
  bool _liveStarted = false;
  bool get liveCanEdit => liveRepository.canEdit;

  void initializeLiveGame(Future<void> Function() initialize) {
    _initialization = initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_liveStarted) return;
    _liveStarted = true;
    final name = ModalRoute.of(context)?.settings.name;
    final lock = name != null && name.startsWith('active-table:')
        ? name.substring('active-table:'.length)
        : null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _initialization;
        if (!mounted) return;
        liveRepository.registrar = () => liveRegistrar;
        await liveRepository.connect(lock, restoreLiveProgress,
            onlyLocal: usesSeparateTableSync);
        if (!mounted) return;
        setState(() {});
        onLiveReady();
        _liveLifecycle =
            AppLifecycleListener(onInactive: _saveLive, onPause: _saveLive);
        _liveTimer = Timer.periodic(
            const Duration(milliseconds: 400), (_) => _saveLive());
        await _saveLive();
      } catch (_) {
        liveRepository.status.value = 'Тоглолт сэргээж чадсангүй';
      }
    });
  }

  Future<void> _saveLive() async {
    if (!mounted || _savingLive || !liveRepository.ready) return;
    _savingLive = true;
    try {
      await liveRepository.checkpoint(saveLiveProgress);
      await liveRepository.flush();
    } catch (_) {
      liveRepository.status.value = 'Явцын хадгалалтыг дахин оролдоно';
    } finally {
      _savingLive = false;
    }
  }

  Widget? get liveCommandIndicator => null;
  Widget? get liveCommandHint => null;

  Widget buildLiveGame(Widget child) => ValueListenableBuilder<String>(
        valueListenable: liveRepository.status,
        builder: (context, status, _) => Column(children: [
          Material(
              color: const Color(0xFF263238),
              child: SafeArea(
                  bottom: false,
                  child: Row(children: [
                    if (!liveCanEdit)
                      IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white)),
                    const SizedBox(width: 12),
                    const Icon(Icons.cloud_sync,
                        size: 16, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(status,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)))),
                    if (liveCommandIndicator != null)
                      Expanded(flex: 3, child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: liveCommandIndicator!,
                      )),
                    if (liveCommandHint != null)
                      Flexible(child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: liveCommandHint!,
                      )),
                  ]))),
          Expanded(
              child: ExcludeFocus(
                  excluding: !liveCanEdit,
                  child: AbsorbPointer(absorbing: !liveCanEdit, child: child))),
        ]),
      );

  /// Capture final input, also updating the saved game when one is linked.
  void stopLiveGame() {
    if (_stoppingLive) return;
    _stoppingLive = true;
    _liveTimer?.cancel();
    _liveLifecycle?.dispose();
    _liveLifecycle = null;
    if (liveRepository.ready && liveCanEdit) {
      unawaited(liveRepository
          .checkpoint(saveLiveProgress)
          .whenComplete(liveRepository.close));
    } else {
      liveRepository.close();
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _liveLifecycle?.dispose();
    if (!_stoppingLive) liveRepository.close();
    super.dispose();
  }
}
