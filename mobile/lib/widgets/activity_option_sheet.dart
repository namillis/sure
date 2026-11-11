import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import 'ds/ds.dart';

/// One choice in an [ActivityOptionSheet].
class ActivityOption {
  const ActivityOption({required this.id, required this.label, this.color});

  final String id;
  final String label;

  /// Optional color dot (category or tag color).
  final Color? color;
}

/// A [SureSheet] listing [options], used by the Activity tab's filters
/// (multi-select: "Done" returns the chosen ids), its date and type pickers
/// and bulk categorize (single-select: returns the tapped id).
class ActivityOptionSheet extends StatefulWidget {
  const ActivityOptionSheet({
    super.key,
    required this.title,
    required this.options,
    this.selected = const {},
    this.multiSelect = true,
  });

  final String title;
  final List<ActivityOption> options;

  /// Checked rows. In single-select it marks the current choice.
  final Set<String> selected;
  final bool multiSelect;

  /// Lists with more options than this get a find field.
  static const int searchThreshold = 8;

  /// Multi-select: resolves to the chosen ids, or null when dismissed.
  static Future<Set<String>?> pickMany(
    BuildContext context, {
    required String title,
    required List<ActivityOption> options,
    required Set<String> selected,
  }) {
    return showSureSheet<Set<String>>(
      context: context,
      builder: (_) => ActivityOptionSheet(
        title: title,
        options: options,
        selected: selected,
      ),
    );
  }

  /// Single-select: resolves to the tapped id, or null when dismissed.
  /// [selected] gets a check mark.
  static Future<String?> pickOne(
    BuildContext context, {
    required String title,
    required List<ActivityOption> options,
    String? selected,
  }) async {
    final result = await showSureSheet<Set<String>>(
      context: context,
      builder: (_) => ActivityOptionSheet(
        title: title,
        options: options,
        selected: {if (selected != null) selected},
        multiSelect: false,
      ),
    );
    return result == null || result.isEmpty ? null : result.first;
  }

  @override
  State<ActivityOptionSheet> createState() => _ActivityOptionSheetState();
}

class _ActivityOptionSheetState extends State<ActivityOptionSheet> {
  late final Set<String> _selected = {...widget.selected};
  String _query = '';

  List<ActivityOption> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where((option) => option.label.toLowerCase().contains(query))
        .toList();
  }

  void _tap(ActivityOption option) {
    if (!widget.multiSelect) {
      Navigator.pop(context, {option.id});
      return;
    }
    SureHaptics.selection();
    setState(() {
      if (!_selected.remove(option.id)) _selected.add(option.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final visible = _visible;

    final Widget body;
    if (widget.options.isEmpty) {
      body = SureEmptyState(
        icon: SureIcons.inbox,
        title: l.activityFilterNoOptions,
      );
    } else {
      body = ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          SurePanel.rows(
            dividerIndent: visible.any((o) => o.color != null) ? 42 : 14,
            children: [for (final option in visible) _row(option, palette)],
          ),
          if (widget.multiSelect && _selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: () => setState(_selected.clear),
                  style: TextButton.styleFrom(foregroundColor: palette.link),
                  child: Text(l.activityFilterClear),
                ),
              ),
            ),
        ],
      );
    }

    return SureSheet(
      title: widget.title,
      actionLabel: l.dsDone,
      onAction: widget.multiSelect
          ? () => Navigator.pop(context, Set<String>.of(_selected))
          : null,
      // A single-select sheet with no action still needs its toolbar.
      onCancel: () => Navigator.of(context).maybePop(),
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.options.length > ActivityOptionSheet.searchThreshold)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SureSearchField(
                hintText: l.activityFilterSearchHint,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          Flexible(child: body),
        ],
      ),
    );
  }

  Widget _row(ActivityOption option, SureTokenPalette palette) {
    final checked = _selected.contains(option.id);
    final color = option.color;
    return Semantics(
      selected: checked,
      child: SureListRow(
        title: option.label,
        leading: color == null
            ? null
            : Container(
                width: SureCategoryIcon.dotSize,
                height: SureCategoryIcon.dotSize,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
        trailing: checked
            ? SureIcon(SureIcons.check, size: 18, color: palette.link)
            : null,
        onTap: () => _tap(option),
      ),
    );
  }
}
