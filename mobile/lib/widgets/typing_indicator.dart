import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';

/// Animated "Thinking" label with three bouncing dots, shown while the AI
/// writes a reply. Each dot bounces in sequence.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final dotColor = palette.textSubdued;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          AppLocalizations.of(context).ds3aThinking,
          style: TextStyle(fontSize: 15, color: palette.textSecondary),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (index) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final offset = _dotOffset(index, _controller.value);
                  return Padding(
                    padding: EdgeInsets.only(right: index < 2 ? 4 : 0),
                    child: Transform.translate(
                      offset: Offset(0, offset),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ),
        ),
      ],
    );
  }

  /// Returns the vertical offset (px) for a dot at [index] given the
  /// controller's current [value] in [0, 1).
  /// Each dot is delayed by 1/3 of the cycle so they bounce in sequence.
  double _dotOffset(int index, double value) {
    const bounceHeight = 5.0;
    const dotCount = 3;
    final phase = (value - index / dotCount + 1.0) % 1.0;

    // Bounce occupies the first 40% of each dot's phase; rest is idle.
    if (phase < 0.2) {
      // Rising: 0 → peak
      return -bounceHeight * (phase / 0.2);
    } else if (phase < 0.4) {
      // Falling: peak → 0
      return -bounceHeight * (1.0 - (phase - 0.2) / 0.2);
    }
    return 0.0;
  }
}
