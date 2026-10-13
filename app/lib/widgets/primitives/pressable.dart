import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global pressable widget — scale 0.97 on press with spring-back.
/// Press-and-hold triggers TTS via [speakLabel] (requires ProviderScope ancestor).
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? speakLabel;
  final bool haptic;
  final bool enabled;

  const Pressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.speakLabel,
    this.haptic = false,
    this.enabled = true,
    super.key,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.enabled) return;
    _ctrl.forward();
    if (widget.haptic) HapticFeedback.lightImpact();
  }

  void _onTapUp(TapUpDetails _) => _ctrl.reverse();
  void _onTapCancel() => _ctrl.reverse();

  void _onTap() {
    if (!widget.enabled) return;
    widget.onTap?.call();
  }

  void _onLongPress() {
    if (!widget.enabled) return;
    if (widget.speakLabel != null) {
      HapticFeedback.mediumImpact();
      debugPrint('[TTS speak-on-hold]: ${widget.speakLabel}');
      // Real TTS wired via SpeakOnHold in speak_button.dart
    }
    widget.onLongPress?.call();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _onTap,
      onLongPress: widget.speakLabel != null ? _onLongPress : widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(
          scale: widget.enabled ? _scale.value : 1.0,
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.4,
            child: child,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}
// SpeakOnHold lives in speak_button.dart (ConsumerWidget with real TTS).
// Import speak_button.dart wherever SpeakOnHold is needed.
