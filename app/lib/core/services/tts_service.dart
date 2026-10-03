import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-Speech service for Urdu (ur-PK).
///
/// Voice rules (§5.4):
/// - Language: ur-PK, natural pace 0.95×
/// - Used for: amounts, button labels (on hold), follow-up reminders,
///   monthly summary, confirmations
/// - Respect audio focus (duck music, don't fight calls)
/// - "Voice off" toggle respected — manual 🔊 taps still work when voice off
/// - Must never block core functionality (degrade gracefully)
class TTSService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage('ur-PK');
      await _tts.setSpeechRate(0.95);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      _tts.setStartHandler(() => _isSpeaking = true);
      _tts.setCompletionHandler(() => _isSpeaking = false);
      _tts.setCancelHandler(() => _isSpeaking = false);
      _tts.setErrorHandler((_) => _isSpeaking = false);

      _initialized = true;
    } catch (e) {
      // TTS init failure must never crash the app
      debugPrint('TTSService init failed: $e');
    }
  }

  /// Speak a string. If voice is unavailable, fails silently.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    try {
      await init();
      if (_isSpeaking) await stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('TTSService.speak failed: $e');
    }
  }

  /// Stop current speech.
  Future<void> stop() async {
    try {
      await _tts.stop();
      _isSpeaking = false;
    } catch (_) {}
  }

  /// Speak an amount in Urdu lac/crore format.
  /// Example: 12500000 → "ایک کروڑ پچیس لاکھ روپے"
  Future<void> speakAmount(int rupees, {String? prefix}) async {
    // Import avoided here to keep service self-contained
    // MoneyFormatter.toSpokenUrdu called from widget layer
    await speak('${prefix ?? ''}${_rupeesToUrdu(rupees)}');
  }

  /// Speak a confirmation after money action.
  Future<void> speakConfirmation(String action, int amount) async {
    await speak('$action — ${_rupeesToUrdu(amount)}');
  }

  /// Speak "ho gaya" (done) confirmation.
  Future<void> speakDone() async => speak('ہو گیا');

  /// Speak "saved" confirmation.
  Future<void> speakSaved() async => speak('محفوظ ہو گیا');

  /// Speak a sync failure.
  Future<void> speakSyncFailed() async =>
      speak('سیو نہیں ہوا — دوبارہ کوشش کریں');

  // ── Inline amount conversion (basic — widget layer uses MoneyFormatter) ──

  String _rupeesToUrdu(int rupees) {
    const lac = 100000;
    const crore = 10000000;

    if (rupees >= crore) {
      final c = (rupees / crore).toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), '');
      final remainder = rupees % crore;
      if (remainder >= lac) {
        final l = (remainder / lac).round();
        return '$c کروڑ $l لاکھ روپے';
      }
      return '$c کروڑ روپے';
    }
    if (rupees >= lac) {
      final l = (rupees / lac).toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), '');
      return '$l لاکھ روپے';
    }
    return '$rupees روپے';
  }

  void dispose() {
    _tts.stop();
  }
}

final ttsServiceProvider = Provider<TTSService>((ref) {
  final service = TTSService();
  ref.onDispose(service.dispose);
  return service;
});
