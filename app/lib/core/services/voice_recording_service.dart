import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

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
  Future<String?> startRecording({String? refId}) async {
    try {
      final hasPerms = await _recorder.hasPermission();
      if (!hasPerms) return null;

      final dir = await getTemporaryDirectory();
      final id = refId ?? const Uuid().v4();
      final path = '${dir.path}/voice_$id.m4a';

      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 22050,
        ),
        path: path,
      );

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

      final file = File(path);
      final exists = await file.exists();
      if (!exists) return null;

      // Estimate duration from file size (rough: 64kbps Opus)
      final bytes = await file.length();
      final durationSeconds = (bytes * 8) ~/ 64000;

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
