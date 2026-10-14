import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../platform/file_support.dart';

/// Voice recording service.
///
/// CRITICAL rule: audio is always kept, even if transcription fails.
/// Voice notes are first-class data, not just UI input.
///
/// Records in Opus format (compressed, ~1MB/min).
class VoiceRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _currentPath;

  bool get isRecording => _isRecording;
  String? get currentPath => _currentPath;

  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  /// Start recording to a temp file. Returns the file path.
  /// On web, path_provider is unavailable — record package handles temp path.
  Future<String?> startRecording({String? refId}) async {
    try {
      final hasPerms = await _recorder.hasPermission();
      if (!hasPerms) return null;

      final id = refId ?? const Uuid().v4();
      String path;

      if (kIsWeb) {
        // On web, record package manages its own blob URL — we use a virtual path
        path = '/voice_$id.m4a';
      } else {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_$id.m4a';
      }

      if (kIsWeb) {
        await _recorder.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 22050,
          ),
          path: '',  // Web: record package manages its own blob URL
        );
      } else {
        await _recorder.start(
          RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 64000,
            sampleRate: 22050,
          ),
          path: path,
        );
      }

      _isRecording = true;
      _currentPath = path;
      return path;
    } catch (e) {
      debugPrint('VoiceRecordingService.startRecording failed: $e');
      return null;
    }
  }

  /// Stop recording. Returns the final file path + duration.
  Future<RecordingResult?> stopRecording() async {
    if (!_isRecording) return null;
    try {
      final path = await _recorder.stop();
      _isRecording = false;
      if (path == null) return null;

      int durationSeconds = 0;

      if (!kIsWeb) {
        // On native: estimate duration from file size
        final file = File(path);
        final exists = await file.exists();
        if (!exists) return null;
        final bytes = await file.length();
        durationSeconds = (bytes * 8) ~/ 64000;
      }
      // On web: duration estimation not available via File system

      _currentPath = null;
      return RecordingResult(
        path: path,
        durationSeconds: durationSeconds.clamp(0, 3600),
      );
    } catch (e) {
      debugPrint('VoiceRecordingService.stopRecording failed: $e');
      _isRecording = false;
      _currentPath = null;
      return null;
    }
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.cancel();
      _isRecording = false;
      _currentPath = null;
    } catch (_) {}
  }

  void dispose() {
    _recorder.dispose();
  }
}

class RecordingResult {
  final String path;
  final int durationSeconds;
  const RecordingResult({required this.path, required this.durationSeconds});
}

final voiceRecordingServiceProvider = Provider<VoiceRecordingService>((ref) {
  final service = VoiceRecordingService();
  ref.onDispose(service.dispose);
  return service;
});
