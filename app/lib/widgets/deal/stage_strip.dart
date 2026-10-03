import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../primitives/speak_button.dart';

/// StageStrip — deal pipeline stages as color + icon chips.
///
/// Rules (§5.3):
/// - 6 stages as color + icon chips in horizontal strip
/// - Current stage pulses
/// - Tappable to advance (with voice confirmation)
/// - Tokens expiring ≤3 days pulse red
/// - NO reading required — color + icon is the entire signal
///
/// Stage colors are FIXED and must never change (§5.2):
/// Inquiry=gray 👁 / Token=amber 🤝 / Bayana=blue 📄 / Registry=purple 🏛 / Closed=gold 🏆 / Lost=dark ✕
enum DealStage {
  inquiry,
  token,
  bayana,
  registry,
  closed,
  lost;

  String get dbValue => name;

  String get labelUr => switch (this) {
    DealStage.inquiry  => 'انکوائری',
    DealStage.token    => 'ٹوکن',
    DealStage.bayana   => 'بیعانہ',
    DealStage.registry => 'رجسٹری',
    DealStage.closed   => 'مکمل',
    DealStage.lost     => 'ختم',
  };

  String get labelEn => switch (this) {
    DealStage.inquiry  => 'Inquiry',
    DealStage.token    => 'Token',
    DealStage.bayana   => 'Bayana',
    DealStage.registry => 'Registry',
    DealStage.closed   => 'Closed',
    DealStage.lost     => 'Lost',
  };

  IconData get icon => switch (this) {
    DealStage.inquiry  => Icons.visibility_rounded,       // 👁
    DealStage.token    => Icons.handshake_rounded,         // 🤝
    DealStage.bayana   => Icons.description_rounded,       // 📄
    DealStage.registry => Icons.account_balance_rounded,   // 🏛
    DealStage.closed   => Icons.emoji_events_rounded,      // 🏆
    DealStage.lost     => Icons.cancel_rounded,            // ✕
  };

  Color get color => switch (this) {
    DealStage.inquiry  => AppColors.stageInquiry,
    DealStage.token    => AppColors.stageToken,
    DealStage.bayana   => AppColors.stageBayana,
    DealStage.registry => AppColors.stageRegistry,
    DealStage.closed   => AppColors.stageClosed,
    DealStage.lost     => AppColors.stageLost,
  };

  static DealStage? fromDb(String? value) => switch (value) {
    'inquiry'  => DealStage.inquiry,
    'token'    => DealStage.token,
    'bayana'   => DealStage.bayana,
    'registry' => DealStage.registry,
    'closed'   => DealStage.closed,
    'lost'     => DealStage.lost,
    _          => null,
  };

  /// Valid next stages from this stage.
  List<DealStage> get nextStages => switch (this) {
    DealStage.inquiry  => [DealStage.token, DealStage.lost],
    DealStage.token    => [DealStage.bayana, DealStage.lost],
    DealStage.bayana   => [DealStage.registry, DealStage.lost],
    DealStage.registry => [DealStage.closed, DealStage.lost],
    DealStage.closed   => [],
    DealStage.lost     => [],
  };

  bool get isTerminal => this == DealStage.closed || this == DealStage.lost;
}

/// Horizontal stage strip widget.
class StageStrip extends StatelessWidget {
  final DealStage currentStage;
  final bool compact;
  final void Function(DealStage)? onStageTap;

  const StageStrip({
    required this.currentStage,
    this.compact = false,
    this.onStageTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: DealStage.values
            .where((s) => s != DealStage.lost) // Lost shown separately
            .map((stage) {
          final isCurrent = stage == currentStage;
          final isPast = _isPast(stage);

          return Padding(
            padding: EdgeInsets.only(
              right: compact ? AppSpacing.xs : AppSpacing.sm,
            ),
            child: _StageChip(
              stage: stage,
              isCurrent: isCurrent,
              isPast: isPast,
              compact: compact,
              onTap: onStageTap != null ? () => onStageTap!(stage) : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _isPast(DealStage stage) {
    final order = [
      DealStage.inquiry,
      DealStage.token,
      DealStage.bayana,
      DealStage.registry,
      DealStage.closed,
    ];
    final currentIdx = order.indexOf(currentStage);
    final stageIdx = order.indexOf(stage);
    return stageIdx < currentIdx;
  }
}

class _StageChip extends StatefulWidget {
  final DealStage stage;
  final bool isCurrent;
  final bool isPast;
  final bool compact;
  final VoidCallback? onTap;

  const _StageChip({
    required this.stage,
    required this.isCurrent,
    required this.isPast,
    required this.compact,
    this.onTap,
  });

  @override
  State<_StageChip> createState() => _StageChipState();
}

class _StageChipState extends State<_StageChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isCurrent) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StageChip old) {
    super.didUpdateWidget(old);
    if (widget.isCurrent && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.isCurrent && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.stage.color;
    final bg = widget.isCurrent
        ? color.withAlpha(30)
        : widget.isPast
            ? color.withAlpha(15)
            : Colors.transparent;

    return SpeakOnHold(
      text: widget.stage.labelUr,
      child: GestureDetector(
        onTap: () {
          if (widget.onTap != null) {
            HapticFeedback.selectionClick();
            widget.onTap!();
          }
        },
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, child) {
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? AppSpacing.sm : AppSpacing.md,
                vertical: widget.compact ? AppSpacing.xs : AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppSpacing.pillRadius,
                border: Border.all(
                  color: widget.isCurrent
                      ? color.withAlpha((150 + (105 * _pulse.value)).round())
                      : widget.isPast
                          ? color.withAlpha(60)
                          : AppColors.ink100,
                  width: widget.isCurrent ? 2 : 1,
                ),
                boxShadow: widget.isCurrent
                    ? [
                        BoxShadow(
                          color: color.withAlpha(
                            (20 + (40 * _pulse.value)).round(),
                          ),
                          blurRadius: 8 + (4 * _pulse.value),
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isPast
                        ? Icons.check_circle_rounded
                        : widget.stage.icon,
                    size: widget.compact ? 14 : 18,
                    color: widget.isCurrent
                        ? color
                        : widget.isPast
                            ? color.withAlpha(180)
                            : AppColors.ink300,
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(width: 4),
                    Text(
                      widget.stage.labelUr,
                      style: AppTypography.urCaption.copyWith(
                        color: widget.isCurrent
                            ? color
                            : widget.isPast
                                ? color.withAlpha(180)
                                : AppColors.ink300,
                        fontWeight: widget.isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
