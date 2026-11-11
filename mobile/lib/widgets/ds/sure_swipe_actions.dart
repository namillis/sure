import 'package:flutter/material.dart';

import '../../utils/sure_haptics.dart';

/// One action revealed by [SureSwipeActions].
class SureSwipeAction {
  const SureSwipeAction({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;

  /// Fill behind the white label.
  final Color color;
  final VoidCallback onPressed;
}

/// Swipe-left-to-reveal trailing actions (iOS style). Dragging left past half
/// the actions' width snaps them open; tapping one plays the swipe-commit
/// haptic, closes the row and calls it. Tapping the open row closes it.
///
/// With no [actions] (or [enabled] false) the child is returned unchanged.
class SureSwipeActions extends StatefulWidget {
  const SureSwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.enabled = true,
    this.actionWidth = 80,
  });

  final Widget child;
  final List<SureSwipeAction> actions;
  final bool enabled;
  final double actionWidth;

  @override
  State<SureSwipeActions> createState() => _SureSwipeActionsState();
}

class _SureSwipeActionsState extends State<SureSwipeActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  double get _revealWidth => widget.actionWidth * widget.actions.length;

  bool get _isOpen => _controller.value > 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final delta = -(details.primaryDelta ?? 0) / _revealWidth;
    _controller.value = (_controller.value + delta).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final open =
        velocity < -300 || (velocity <= 300 && _controller.value > 0.5);
    open ? _controller.fling(velocity: 1) : _controller.fling(velocity: -1);
  }

  void _close() => _controller.fling(velocity: -1);

  void _run(SureSwipeAction action) {
    SureHaptics.swipeCommit();
    _close();
    action.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final action in widget.actions)
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => SizedBox(
                        width: widget.actionWidth * _controller.value,
                        child: child,
                      ),
                      child: Semantics(
                        button: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _run(action),
                          child: ColoredBox(
                            color: action.color,
                            child: Center(
                              child: Text(
                                action.label,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                // While open, a tap on the row closes the actions instead of
                // reaching the row.
                final open = _isOpen;
                return Transform.translate(
                  offset: Offset(-_revealWidth * _controller.value, 0),
                  child: Stack(
                    children: [
                      AbsorbPointer(absorbing: open, child: child),
                      if (open)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _close,
                          ),
                        ),
                    ],
                  ),
                );
              },
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
