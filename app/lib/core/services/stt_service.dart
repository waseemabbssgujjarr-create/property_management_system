import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Speech-to-Text service for Urdu name/note capture.
///
/// Rules (§5.4):
/// - On-device preferred (works offline)
/// - Transcription shown as editable text for munshi
/// - Audio ALWAYS kept as source of truth — transcription is best-effort
/// - Must degrade gracefully: if STT unavailable, show mic icon that saves
///   audio without transcription
class STTService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _available = false;
  bool _initialized = false;

  bool get isAvailable => _available;
  bool get isListening => _stt.isListening;

  Future<bool> init() async {
    if (_initialized) return _available;
    try {
      _available = await _stt.initialize(
        onError: (error) => debugPrint('STT error: $error'),
        debugLogging: kDebugMode,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('STTService init failed: $e');
      _available = false;
      _initialized = true;
    }
    return _available;
  }

  /// Start listening. Returns transcript updates via [onResult].
  /// Stops automatically after [listenFor] duration.
  Future<void> startListening({
    required void Function(String transcript, bool isFinal) onResult,
    Duration listenFor = const Duration(seconds: 30),
    String localeId = 'ur_PK',
  }) async {
    if (!await init()) {
      debugPrint('STT not available');
      return;
    }

    try {
      await _stt.listen(
        onResult: (result) => onResult(
          result.recognizedWords,
          result.finalResult,
        ),
        listenFor: listenFor,
        localeId: localeId,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('STTService.startListening failed: $e');
    }
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  Future<void> cancelListening() async {
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  void dispose() {
    _stt.cancel();
  }
}

final sttServiceProvider = Provider<STTService>((ref) {
  final service = STTService();
  ref.onDispose(service.dispose);
  return service;
});
