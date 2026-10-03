import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/stt_service.dart';
import '../../core/services/voice_recording_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// 🎤 VoiceInput — mic button that records audio + attempts STT transcription.
///
/// Rules (§5.3, §5.4):
/// - Tap-and-hold to record (WhatsApp pattern)
/// - Release to send
/// - Records audio (ALWAYS kept as source of truth)
/// - Attempts Urdu STT transcription (best effort, not required)
/// - Shows waveform + timer while recording
/// - Transcript shown as editable text for munshi
/// - Used for: names, notes, token terms
///
/// Callback receives: transcript text + local audio file path.
/// Audio path is never null when recording succeeds.
class VoiceInput extends ConsumerStatefulWidget {
  final void Function(String? transcript, String? audioPath) onRecorded;
  final String? placeholder;

  const VoiceInput({
    required this.onRecorded,
    this.placeholder,
    super.key,
  });

  @override
  ConsumerState<VoiceInput> createState() => _VoiceInputState();
}

class _VoiceInputState extends ConsumerState<VoiceInput>
    with SingleTickerProviderStateMixin {
  _RecordState _recordState = _RecordState.idle;
  String _transcript = '';
  String? _audioPath;
  int _durationSeconds = 0;
  Timer? _timer;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final recorder = ref.read(voiceRecordingServiceProvider);
    final stt = ref.read(sttServiceProvider);

    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      _showPermissionDenied();
      return;
    }

    // Start audio recording
    final path = await recorder.startRecording();
    if (path == null) return;

    // Start STT in parallel (best-effort)
    stt.startListening(
      onResult: (text, isFinal) {
        if (mounted) setState(() => _transcript = text);
      },
    );

    // Start timer
    _durationSeconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });

    setState(() {
      _recordState = _RecordState.recording;
      _audioPath = path;
    });

    HapticFeedback.mediumImpact();
  }

  Future<void> _stopRecording() async {
    final recorder = ref.read(voiceRecordingServiceProvider);
    final stt = ref.read(sttServiceProvider);

    _timer?.cancel();
    await stt.stopListening();
    final result = await recorder.stopRecording();

    final audioPath = result?.path ?? _audioPath;

    setState(() => _recordState = _RecordState.done);
    HapticFeedback.lightImpact();

    widget.onRecorded(_transcript.isEmpty ? null : _transcript, audioPath);
  }

  Future<void> _cancelRecording() async {
    final recorder = ref.read(voiceRecordingServiceProvider);
    final stt = ref.read(sttServiceProvider);

    _timer?.cancel();
    await stt.cancelListening();
    await recorder.cancelRecording();

    setState(() {
      _recordState = _RecordState.idle;
      _transcript = '';
      _audioPath = null;
      _durationSeconds = 0;
    });
  }

  void _showPermissionDenied() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'مائیکروفون کی اجازت دیں',
          style: AppTypography.urBody.copyWith(color: Colors.white),
        ),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  String get _timerDisplay {
    final m = _durationSeconds ~/ 60;
    final s = _durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Transcript preview
        if (_transcript.isNotEmpty || _recordState == _RecordState.done)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.base,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.brand100,
              borderRadius: AppSpacing.cardRadius,
            ),
            child: Text(
              _transcript.isEmpty
                  ? (widget.placeholder ?? 'آواز ریکارڈ ہو گئی')
                  : _transcript,
              style: AppTypography.urBodyMedium,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
            ),
          ),

        // Mic button row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_recordState == _RecordState.recording) ...[
              // Cancel button
              IconButton(
                onPressed: _cancelRecording,
                icon: const Icon(Icons.close, color: AppColors.danger),
                iconSize: 28,
              ),
              const SizedBox(width: AppSpacing.sm),
              // Timer
              Text(
                _timerDisplay,
                style: AppTypography.moneyMedium.copyWith(
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.base),
            ],

            // Main mic button
            GestureDetector(
              onTapDown: (_) => _startRecording(),
              onTapUp: (_) {
                if (_recordState == _RecordState.recording) _stopRecording();
              },
              onTapCancel: () {
                if (_recordState == _RecordState.recording) _cancelRecording();
              },
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, child) {
                  final isRec = _recordState == _RecordState.recording;
                  return Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isRec ? AppColors.danger : AppColors.brand600,
                      boxShadow: isRec
                          ? [
                              BoxShadow(
                                color: AppColors.danger.withAlpha(
                                  (80 + (80 * _pulseCtrl.value)).round(),
                                ),
                                blurRadius: 16 + (8 * _pulseCtrl.value),
                                spreadRadius: 2,
                              ),
                            ]
                          : AppElevation.medium.cast(),
                    ),
                    child: Icon(
                      isRec ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        if (_recordState == _RecordState.idle)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'دبا کر بولیں',
              style: AppTypography.urCaption.copyWith(color: AppColors.ink300),
            ),
          ),
      ],
    );
  }
}

enum _RecordState { idle, recording, done }

extension _BoxShadowCast on List<BoxShadow> {
  List<BoxShadow> cast() => this;
}
