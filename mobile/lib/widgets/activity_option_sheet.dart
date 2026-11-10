import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import 'sure_button.dart';
import 'sure_text_field.dart';

/// One choice in an [ActivityOptionSheet].
class ActivityOption {
  const ActivityOption({required this.id, required this.label, this.color});

  final String id;
  final String label;

  /// Optional color dot (category or tag color).
  final Color? color;
}

/// A bottom sheet listing [options], used by the Activity tab's category,
/// account and tag filters (multi-select, returns the chosen ids on Apply) and
/// by bulk categorize (single-select, returns the tapped id).
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
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityOptionSheet(
        title: title,
        options: options,
        selected: selected,
      ),
    );
  }

  /// Single-select: resolves to the tapped id, or null when dismissed.
  static Future<String?> pickOne(
    BuildContext context, {
    required String title,
    required List<ActivityOption> options,
  }) async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityOptionSheet(
        title: title,
        options: options,
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final textTheme = Theme.of(context).textTheme;
    final visible = _visible;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SureSpacing.xl,
                SureSpacing.xl,
                SureSpacing.xl,
                SureSpacing.md,
              ),
              child: Text(
                widget.title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: SureTokens.weightSemibold,
                ),
              ),
            ),
            if (widget.options.length > ActivityOptionSheet.searchThreshold)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SureSpacing.xl,
                  vertical: SureSpacing.sm,
                ),
                child: SureTextField(
                  hint: l.activityFilterSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            if (widget.options.isEmpty)
              Padding(
                padding: const EdgeInsets.all(SureSpacing.xxxl),
                child: Text(
                  l.activityFilterNoOptions,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  itemBuilder: (context, index) => _tile(visible[index]),
                ),
              ),
            if (widget.multiSelect)
              Padding(
                padding: const EdgeInsets.all(SureSpacing.xl),
                child: Row(
                  children: [
                    Expanded(
                      child: SureButton(
                        label: l.activityFilterClear,
                        onPressed: _selected.isEmpty
                            ? null
                            : () => setState(_selected.clear),
                        variant: SureButtonVariant.outline,
                        fullWidth: true,
                      ),
                    ),
                    const SizedBox(width: SureSpacing.lg),
                    Expanded(
                      child: SureButton(
                        label: l.activityFilterApply,
                        onPressed: () =>
                            Navigator.pop(context, Set<String>.of(_selected)),
                        fullWidth: true,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: SureSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _tile(ActivityOption option) {
    final dot = option.color == null
        ? null
        : Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: option.color,
              shape: BoxShape.circle,
            ),
          );

    if (!widget.multiSelect) {
      return ListTile(
        minTileHeight: 48,
        leading: dot,
        title: Text(option.label),
        onTap: () => Navigator.pop(context, {option.id}),
      );
    }

    return CheckboxListTile(
      value: _selected.contains(option.id),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: dot,
      title: Text(option.label),
      onChanged: (checked) => setState(() {
        if (checked == true) {
          _selected.add(option.id);
        } else {
          _selected.remove(option.id);
        }
      }),
    );
  }
}
