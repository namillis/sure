import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/metadata_manage_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import 'budget_progress_bar.dart' show parseCategoryColor;
import 'sure_button.dart';
import 'sure_text_field.dart';

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

/// A row of the web's color swatches ([kMetadataColors]). Each swatch is a
/// 44pt button with a label and a check mark when selected, so the choice
/// doesn't rest on color alone. With [allowAutomatic], a leading swatch
/// stands for "let the server pick" (value null).
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
    final theme = Theme.of(context);

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
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onChanged(hex),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color ?? palette.surfaceInset,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? palette.textPrimary
                        : palette.borderSecondary,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check,
                        size: 18,
                        color: color == null
                            ? palette.textPrimary
                            : Colors.white)
                    : (color == null
                        ? Icon(Icons.auto_awesome,
                            size: 16, color: palette.textSecondary)
                        : null),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.manageColor,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: palette.textSecondary)),
        const SizedBox(height: SureSpacing.sm),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (allowAutomatic)
              swatch(hex: null, label: l.manageColorAutomatic),
            for (var i = 0; i < kMetadataColors.length; i++)
              swatch(hex: kMetadataColors[i], label: l.manageColorOption(i + 1)),
          ],
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => SureTextField(
          controller: controller,
          hint: l.manageSearch,
          prefixIcon: const Icon(Icons.search),
          textInputAction: TextInputAction.search,
          onChanged: onChanged,
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: l.manageClearSearch,
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// A centered empty, error or info state.
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

/// Shows [child] as a scrollable bottom sheet that rises with the keyboard.
Future<T?> showManageSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: builder(sheetContext),
      ),
    ),
  );
}

/// The info sheet a read-only row opens: a title, details, and an
/// "Edit on the web" button.
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            leading,
            const SizedBox(width: SureSpacing.lg),
            Expanded(
              child: Text(title, style: theme.textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: SureSpacing.lg),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: SureSpacing.sm),
            child: Text(line,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: palette.textSecondary)),
          ),
        if (onEditOnWeb != null) ...[
          const SizedBox(height: SureSpacing.lg),
          SureButton(
            label: l.manageEditOnWeb,
            leading: const Icon(Icons.language, size: 16),
            variant: SureButtonVariant.outline,
            fullWidth: true,
            onPressed: onEditOnWeb,
          ),
        ],
      ],
    );
  }
}
