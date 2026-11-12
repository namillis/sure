import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/metadata_manage_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import 'budget_progress_bar.dart' show parseCategoryColor;
import 'ds/ds.dart';
import 'sure_button.dart';

/// Shared pieces of the Settings -> Data screens (import, statements,
/// categories, tags, merchants, export).

/// Lucide icons the Data screens use that ship as category icons but have no
/// [SureIcons] constant (they are in [SureIcons.category], so the SVGs are
/// bundled).
abstract final class ManageIcons {
  static const String package = 'package';
  static const String shield = 'shield';
  static const String receiptText = 'receipt-text';
}

/// The "‹ Settings" back link for a screen opened from Settings, or null
/// when the route cannot pop (e.g. a test host).
Widget? manageBackLink(BuildContext context) {
  if (!(ModalRoute.of(context)?.canPop ?? false)) return null;
  return SureBackButton(label: AppLocalizations.of(context).shellSettingsTitle);
}

/// A round color dot for a category, tag or merchant row. Falls back to the
/// subdued text color when [hex] is missing or invalid.
class ManageColorDot extends StatelessWidget {
  const ManageColorDot({super.key, this.hex, this.size = 12, this.child});

  final String? hex;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: parseCategoryColor(hex) ?? palette.textSubdued,
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}

/// A 28 px circle with a Lucide [icon] in [color] on a ~14% fill of the same
/// color (like a category icon), for status and file rows.
class ManageIconBadge extends StatelessWidget {
  const ManageIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = SureCategoryIcon.rowSize,
  });

  /// Lucide icon name.
  final String icon;

  /// Defaults to `textSecondary` on the neutral inset fill.
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final tint = color;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tint == null
              ? colors.palette.surfaceInset
              : tint.withValues(alpha: colors.isDark ? 0.18 : 0.14),
        ),
        child: SureIcon(icon,
            size: (size * 0.54).roundToDouble(),
            color: tint ?? colors.palette.textSecondary),
      ),
    );
  }
}

/// A server or validation error under a form or step: a Lucide alert icon
/// plus text in `destructive`, so it does not rely on color alone.
class ManageErrorText extends StatelessWidget {
  const ManageErrorText(this.message, {super.key, this.compact = false});

  final String message;

  /// 12 pt text and a 14 px icon, for errors inside a row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = SureColors.of(context).palette.destructive;
    return Semantics(
      liveRegion: !compact,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: compact ? 1 : 2),
            child: SureIcon(SureIcons.circleAlert,
                size: compact ? 14 : 16, color: color),
          ),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                height: 1.35,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A multi-line notice on a ~15% fill of `warning` (or `info` with [info])
/// with a Lucide icon: the wrapping sibling of [SureBanner] for messages that
/// may not fit one line.
class ManageNotice extends StatelessWidget {
  const ManageNotice(this.message, {super.key, this.info = false});

  final String message;
  final bool info;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final color = info ? palette.info : palette.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SureIcon(info ? SureIcons.info : SureIcons.triangleAlert,
                size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: SureTokens.weightMedium,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The web's color swatches ([kMetadataColors]) in a panel under a "Color"
/// header. Each swatch is a 44 pt button with a label and a check mark when
/// selected, so the choice doesn't rest on color alone. With
/// [allowAutomatic], a leading swatch stands for "let the server pick"
/// (value null).
class ManageColorPicker extends StatelessWidget {
  const ManageColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowAutomatic = false,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowAutomatic;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    Widget swatch({
      required String? hex,
      required String label,
    }) {
      final selected = value?.toLowerCase() == hex?.toLowerCase();
      final color = parseCategoryColor(hex);
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!selected) SureHaptics.selection();
            onChanged(hex);
          },
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color ?? palette.surfaceInset,
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: palette.textPrimary, width: 2)
                      : null,
                ),
                child: selected
                    ? SureIcon(SureIcons.check,
                        size: 16,
                        color: color == null
                            ? palette.textPrimary
                            : Colors.white)
                    : (color == null
                        ? SureIcon(SureIcons.sparkles,
                            size: 16, color: palette.textSecondary)
                        : null),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SureSectionHeader(
          label: l.manageColor,
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        ),
        SurePanel(
          padding: const EdgeInsets.all(6),
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              if (allowAutomatic)
                swatch(hex: null, label: l.manageColorAutomatic),
              for (var i = 0; i < kMetadataColors.length; i++)
                swatch(
                    hex: kMetadataColors[i], label: l.manageColorOption(i + 1)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The search field at the top of the management lists.
class ManageSearchField extends StatelessWidget {
  const ManageSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SureSearchField(
        controller: controller,
        hintText: l.manageSearch,
        clearSemanticLabel: l.manageClearSearch,
        onChanged: onChanged,
      ),
    );
  }
}

/// A centered empty, error or info state.
///
/// Kept for the Rules, Connections and Insights screens; the Data screens
/// use [SureEmptyState].
class ManageMessage extends StatelessWidget {
  const ManageMessage({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String? body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: palette.textSubdued),
          const SizedBox(height: SureSpacing.lg),
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (body != null) ...[
            const SizedBox(height: SureSpacing.sm),
            Text(body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: palette.textSecondary)),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: SureSpacing.xl),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: SureButton(
                label: l.commonTryAgain,
                variant: SureButtonVariant.outline,
                onPressed: onRetry,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The loading spinner of a Data screen, below the large title.
class ManageLoading extends StatelessWidget {
  const ManageLoading({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
}

/// Opens a Sure sheet; build its content with a [SureSheet].
Future<T?> showManageSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showSureSheet<T>(context: context, builder: builder);

/// One choice of [showManageOptionSheet].
typedef ManageOption<T> = (T value, String label);

/// A picker sheet: [title] in the toolbar, one row per option with a check
/// mark on [selected]. Tapping a row closes the sheet. Returns the picked
/// value wrapped in a record (so a null option can be told apart from
/// dismissing the sheet), or null when dismissed.
Future<({T value})?> showManageOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<ManageOption<T>> options,
  required T selected,
}) {
  return showSureSheet<({T value})>(
    context: context,
    builder: (sheetContext) {
      final palette = SureColors.of(sheetContext).palette;
      return SureSheet(
        title: title,
        child: SafeArea(
          top: false,
          child: SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              for (final (value, label) in options)
                Semantics(
                  selected: value == selected,
                  child: SureListRow(
                    title: label,
                    trailing: value == selected
                        ? SureIcon(SureIcons.check,
                            size: 18, color: palette.link)
                        : null,
                    onTap: () {
                      if (value != selected) SureHaptics.selection();
                      Navigator.of(sheetContext).pop((value: value));
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The info sheet a read-only row opens: a centered badge and title, the
/// detail lines, and an "Edit on the web ↗" row.
class ManageInfoSheet extends StatelessWidget {
  const ManageInfoSheet({
    super.key,
    required this.leading,
    required this.title,
    required this.lines,
    required this.onEditOnWeb,
  });

  final Widget leading;
  final String title;
  final List<String> lines;
  final VoidCallback? onEditOnWeb;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return SureSheet(
      showCancel: false,
      actionLabel: l.dsDone,
      onAction: () => Navigator.of(context).maybePop(),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: leading),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  line,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 1.35, color: palette.textSecondary),
                ),
              ),
            if (onEditOnWeb != null) ...[
              const SizedBox(height: 16),
              SurePanel.rows(
                children: [
                  SureListRow(
                    title: l.manageEditOnWeb,
                    titleColor: palette.link,
                    trailing: SureIcon(SureIcons.arrowUpRight,
                        size: 16, color: palette.link),
                    onTap: onEditOnWeb,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
