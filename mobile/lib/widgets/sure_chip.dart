import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import '../utils/sure_haptics.dart';
import 'sure_icon.dart';

/// Sure filter / range chip: a 32 px pill with a 1 px hairline on the panel
/// color; selected = inverse fill with no outline. A [dropdown] chip ends with
/// a small chevron. The hit area is at least 44 px tall even though the pill
/// is 32. Tapping plays the selection haptic.
///
/// ```dart
/// SureChip(label: '3M', selected: range == '3M', onSelected: (_) => pick('3M'))
/// SureChip(label: 'Category', dropdown: true, onSelected: (_) => openPicker())
/// ```
class SureChip extends StatelessWidget {
  const SureChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onSelected,
    this.leading,
    this.enabled = true,
    this.dropdown = false,
  });

  final String label;
  final bool selected;

  /// Called with the next selected value when tapped. When null the chip is
  /// non-interactive (still renders its selected/unselected state).
  final ValueChanged<bool>? onSelected;

  /// Optional leading widget (e.g. a color dot or icon).
  final Widget? leading;

  final bool enabled;

  /// End with a chevron-down, for chips that open a picker.
  final bool dropdown;

  static const double pillHeight = 32;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final interactive = enabled && onSelected != null;
    final fg = selected ? palette.textInverse : palette.textSecondary;

    void handleTap() {
      SureHaptics.selection();
      onSelected!(!selected);
    }

    final shape = StadiumBorder(
      side: selected ? BorderSide.none : BorderSide(color: colors.hairline),
    );

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: pillHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (dropdown) ...[
              const SizedBox(width: 4),
              SureIcon(SureIcons.chevronDown, size: 14, color: fg),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      // Announce as a button only when it's actually tappable; a display-only
      // chip is just a selected indicator, not a disabled button.
      button: interactive ? true : null,
      enabled: interactive ? true : null,
      selected: selected,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        // The outer detector extends the hit area to 44 px above and below
        // the 32 px pill; taps on the pill itself go to the InkWell.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? handleTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Material(
              color: selected ? palette.buttonPrimary : palette.container,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: interactive ? handleTap : null,
                customBorder: shape,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
