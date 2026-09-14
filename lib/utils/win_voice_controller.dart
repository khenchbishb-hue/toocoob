import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'game_speech.dart';
import 'buur_voice_command.dart';
import 'voice_player_selection.dart';
import 'poker_voice_score.dart';

int? parseWinThreshold(String text) {
  final match = RegExp(r'^(?:хожлын )?босго (.+)$').firstMatch(normalizeBuurSpeech(text));
  return match == null ? null : parsePokerVoiceScore(match.group(1)!);
}

bool isStartGameCommand(String text) => const {'эхлэе', 'тоглолт эхлүүл', 'тоглоё'}
    .contains(normalizeBuurSpeech(text));

int? parseWinVoiceAction(String text) => switch (normalizeBuurSpeech(text)) {
  'хожлоо' || 'хожсон' || 'хожил' || 'нэмэх' => 1,
  'хасах' || 'буцаах' || 'засвар' || 'засах' || 'буруу' => -1,
  _ => null,
};

/// Shared microphone behavior for the three games that count wins.
class WinVoiceController extends ChangeNotifier {
  WinVoiceController({required this.names, required this.canEdit, required this.apply,
    this.parseAction = parseWinVoiceAction, this.nextTarget, this.unit = 'хожил', this.formatResult,
    this.onGlobalCommand, this.onCommand});
  final FutureOr<String> Function(String text)? onCommand;
  final List<List<String>> Function() names;
  final bool Function() canEdit;
  final FutureOr<bool> Function(int index, int delta) apply;
  final int? Function(String) parseAction;
  final int? Function() ? nextTarget;
  final String unit;
  final String Function(String name, int value)? formatResult;
  final String? Function(String text)? onGlobalCommand;
  final _speech = stt.SpeechToText();
  bool enabled = false, listening = false, hint = true;
  bool _closed = false, _renewing = false;
  int _session = 0;
  int? target;
  String message = 'Командаа хэлнэ үү';
  String? _feedback;
  Timer? _stable;
  Timer? _receiptTimer;
  int? receiptPlayer;
  int receiptDelta = 0;
  void receipt(int index, int delta) {
    if (delta == 0 || _closed) return;
    receiptPlayer = index; receiptDelta = delta; _notify();
    _receiptTimer?.cancel();
    _receiptTimer = Timer(const Duration(milliseconds: 1200), () {
      receiptPlayer = null; _notify();
    });
  }
  Widget badge() => IgnorePointer(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: receiptDelta > 0 ? Colors.green.shade800 : Colors.red.shade800,
      borderRadius: BorderRadius.circular(16)),
    child: Text('${receiptDelta > 0 ? '+' : '−'}${receiptDelta.abs()}',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
  ));
  void _notify() { if (!_closed) notifyListeners(); }
  Future<void> toggle() async {
    if (enabled) {
      enabled = false; listening = false; target = null;
      _session++; _stable?.cancel(); _notify();
      await _speech.cancel(); return;
    }
    if (!canEdit()) return;
    enabled = true; hint = true; _feedback = null; _notify();
    final ready = await initializeGameSpeech(_speech, onStatus: (status) {
      if (_closed || !enabled) return;
      if (status == 'listening') {
        listening = true;
        message = '${_feedback == null ? '' : '${_feedback!} • '}Командаа хэлнэ үү';
        _notify();
      } else if ((status == 'done' || status == 'notListening') && !_renewing) {
        renew();
      }
    }, onError: (error) {
      if (_closed) return;
      listening = false;
      message = 'Дуу таних алдаа: ${error.errorMsg}. Микрофоныг дахин асаана уу';
      _notify();
    });
    if (_closed || !enabled) return;
    if (!ready) { message = 'Микрофон ашиглах боломжгүй'; _notify(); return; }
    await renew();
  }
  Future<void> renew() async {
    if (_closed || !enabled || _renewing) return;
    _renewing = true;
    final session = ++_session;
    _stable?.cancel(); listening = false;
    message = '${_feedback ?? ''} Түр хүлээнэ үү…'.trim(); _notify();
    try {
      await _speech.cancel();
      final locales = await _speech.locales();
      if (_closed || !enabled || session != _session) return;
      await _speech.listen(listenOptions: stt.SpeechListenOptions(partialResults: true,
        localeId: locales.where((l) => l.localeId.toLowerCase().startsWith('mn')).firstOrNull?.localeId),
        onResult: (result) {
          if (_closed || !enabled || session != _session || !canEdit()) return;
          final text = normalizeBuurSpeech(result.recognizedWords);
          message = 'Таны команд: ${result.recognizedWords}'; _notify();
          _stable?.cancel();
          if (result.finalResult) consume(text, session);
          else _stable = Timer(const Duration(milliseconds: 650), () => consume(text, session));
        });
    } finally { _renewing = false; }
  }
  Future<void> consume(String text, int session) async {
    if (_closed || !enabled || session != _session || !canEdit()) return;
    _session++; _stable?.cancel();
    if (RegExp(r'(^|\s)боллоо($|\s)').hasMatch(text)) { await toggle(); return; }
    if (onCommand != null) {
      _feedback = await onCommand!(text);
      _notify(); await renew(); return;
    }
    final globalFeedback = onGlobalCommand?.call(text);
    if (globalFeedback != null) {
      target = null;
      _feedback = globalFeedback;
      _notify();
      await renew();
      return;
    }
    final players = names();
    final mention = lastVoicePlayerMention(text, players.map((n) => n.expand(buurNameAliases)).toList());
    if (mention != null && mention.playerIndex == null) {
      _feedback = 'Нэр давхцаж байна. Хочоор хэлнэ үү';
    } else {
      if (mention != null) {
        target = mention.playerIndex;
        hint = false;
        text = text.substring(mention.end).trim();
      }
      if (target == null || target! >= players.length) {
        target = null; _feedback = 'Эхлээд тоглогчийн нэр, хочийг хэлнэ үү';
      } else if (text.isEmpty) {
        _feedback = '${players[target!].first}: командаа хэлнэ үү';
      } else {
        final selectedName = players[target!].first;
        final delta = parseAction(text);
        if (delta == null) _feedback = 'Танигдсангүй. Дахин хэлнэ үү';
        else if (await apply(target!, delta)) {
          if (_closed) return;
          _feedback = formatResult?.call(selectedName, delta) ?? '✓ $selectedName: ${unit == 'хожил' && delta > 0 ? '+' : ''}$delta $unit';
          target = nextTarget?.call(); hint = target == null;
        } else _feedback = 'Бүртгэх боломжгүй. Дахин хэлнэ үү';
      }
    }
    _notify(); await renew();
  }
  void manual() {
    _session++; _stable?.cancel(); target = null;
    _feedback = 'Гараар бүртгэлээ';
    if (enabled) renew();
  }
  Widget? get indicator => !enabled ? null : Text(message,
    maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
    style: TextStyle(color: listening ? Colors.lightGreenAccent : Colors.white70, fontSize: 13));
  Widget? get stopHint => enabled && hint ? const Text('Микрофон унтраах: “Боллоо”',
    style: TextStyle(color: Colors.white70, fontSize: 12)) : null;
  @override
  void dispose() {
    _receiptTimer?.cancel(); _closed = true; enabled = false; _session++; _stable?.cancel(); _speech.cancel(); super.dispose();
  }
}
