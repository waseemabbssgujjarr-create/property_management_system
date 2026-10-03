import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/tts_service.dart';
import '../../core/state/voice_state.dart';
import '../../core/theme/app_colors.dart';

/// 🔊 SpeakButton — taps to speak any string via Urdu TTS.
///
/// Rules (§5.3):
/// - Tap → speaks text
/// - Shows animated waveform bars while speaking
/// - Second tap stops speech
/// - Voice off toggle respected for auto-speak; manual tap always works
enum SpeakButtonSize { small, medium, large }

class SpeakButton extends ConsumerStatefulWidget {
  final String text;
  final SpeakButtonSize size;
  final Color? color;

  const SpeakButton({
    required this.text,
    this.size = SpeakButtonSize.medium,
    this.color,
    super.key,
  });

  @override
  ConsumerState<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends ConsumerState<SpeakButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveCtrl;
  bool _isSpeaking = false;

  double get _iconSize => switch (widget.size) {
    SpeakButtonSize.small  => 18,
    SpeakButtonSize.medium => 24,
    SpeakButtonSize.large  => 32,
  };

  double get _buttonSize => switch (widget.size) {
    SpeakButtonSize.small  => 32,
    SpeakButtonSize.medium => 44,
    SpeakButtonSize.large  => 56,
  };

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final tts = ref.read(ttsServiceProvider);
    if (_isSpeaking) {
      await tts.stop();
      setState(() => _isSpeaking = false);
    } else {
      setState(() => _isSpeaking = true);
      await tts.speak(widget.text);
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        (_isSpeaking ? AppColors.brand600 : AppColors.ink500);

    return Tooltip(
      message: widget.text,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(_buttonSize / 2),
        child: SizedBox(
          width: _buttonSize,
          height: _buttonSize,
          child: Center(
            child: _isSpeaking
                ? _WaveformIcon(controller: _waveCtrl, size: _iconSize, color: color)
                : Icon(Icons.volume_up_rounded, size: _iconSize, color: color),
          ),
        ),
      ),
    );
  }
}

/// Animated waveform bars shown while TTS is playing.
class _WaveformIcon extends AnimatedWidget {
  final double size;
  final Color color;

  const _WaveformIcon({
    required AnimationController controller,
    required this.size,
    required this.color,
  }) : super(listenable: controller);

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    final t = animation.value;
    return SizedBox(
      width: size,
      height: size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(4, (i) {
          final height = size * (0.3 + 0.5 * _wave(t, i));
          return AnimatedContainer(
            duration: Duration.zero,
            width: size / 6,
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  double _wave(double t, int i) {
    return (math.sin((t * 2 * math.pi) + (i * math.pi / 2)) + 1) / 2;
  }
}

/// Wrapper that exposes TTS speak function to non-Riverpod widgets
/// (used by Pressable's speak-on-hold).
class SpeakOnHold extends ConsumerWidget {
  final Widget child;
  final String text;

  const SpeakOnHold({required this.child, required this.text, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onLongPress: () async {
        final tts = ref.read(ttsServiceProvider);
        await tts.speak(text);
      },
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
