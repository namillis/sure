import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../sure_icon.dart';

/// One tab of a [SureTabBar].
class SureTabItem {
  const SureTabItem({required this.icon, required this.label});

  /// Lucide icon name.
  final String icon;
  final String label;
}

/// iOS-style bottom tab bar: Lucide icon over a label per tab; the selected
/// tab in `textPrimary` weight 600, the rest `textSubdued`. A translucent,
/// blurred page-color background with a top hairline. No indicator pill.
///
/// Content shows through only when the Scaffold has `extendBody: true`.
class SureTabBar extends StatelessWidget {
  const SureTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<SureTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// Height of the tab row, above the bottom safe area.
  static const double height = 50;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.85),
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _Tab(
                        item: items[i],
                        selected: i == currentIndex,
                        onTap: () => onSelected(i),
                        index: i,
                        count: items.length,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.index,
    required this.count,
  });

  final SureTabItem item;
  final bool selected;
  final VoidCallback onTap;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final color = selected ? palette.textPrimary : palette.textSubdued;
    final tabLabel = MaterialLocalizations.of(context)
        .tabLabel(tabIndex: index + 1, tabCount: count);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      hint: tabLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SureIcon(item.icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler:
                  MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
              style: TextStyle(
                fontSize: 10.5,
                height: 1.1,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
