import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/sure_colors.dart';
import '../../theme/sure_theme.dart';

/// Opens a Sure bottom sheet: `surface` background with 16 px top corners.
/// Build its content with [SureSheet], which adds the grabber and the
/// "Cancel · Title · Save" toolbar. The sheet takes its height from the
/// content, up to [maxHeightFraction] of the screen.
///
/// ```dart
/// final saved = await showSureSheet<bool>(
///   context: context,
///   builder: (context) => SureSheet(
///     title: 'Category',
///     actionLabel: l.dsDone,
///     onAction: () => Navigator.pop(context, true),
///     child: picker,
///   ),
/// );
/// ```
Future<T?> showSureSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  double maxHeightFraction = 0.92,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    showDragHandle: false,
    backgroundColor: SureColors.of(context).palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(SureTheme.sheetRadius)),
    ),
    clipBehavior: Clip.antiAlias,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFraction,
    ),
  );
}

/// The body of a Sure sheet: a grabber, an optional toolbar, then [child].
///
/// The toolbar shows when [title], [onCancel] or [onAction] is set: "Cancel"
/// in the link color on the left (pops the sheet unless [onCancel] is given),
/// [title] centered, and a bold [actionLabel] ("Save"/"Done") on the right.
/// While [busy] is true the action shows a spinner and does nothing.
class SureSheet extends StatelessWidget {
  const SureSheet({
    super.key,
    required this.child,
    this.title,
    this.actionLabel,
    this.onAction,
    this.actionEnabled = true,
    this.busy = false,
    this.showCancel = true,
    this.cancelLabel,
    this.onCancel,
    this.scrollable = true,
    this.actionKey,
  });

  final Widget child;
  final String? title;

  /// Right-hand action label. Defaults to the localized "Save".
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Key on the right-hand action button, for tests.
  final Key? actionKey;
  final bool actionEnabled;
  final bool busy;
  final bool showCancel;

  /// Defaults to the localized "Cancel".
  final String? cancelLabel;

  /// Defaults to popping the sheet with no result.
  final VoidCallback? onCancel;

  /// Wrap [child] in a scroll view. Set false when [child] scrolls itself
  /// (a ListView), and give it a bounded height or `Flexible` parent.
  final bool scrollable;

  bool get _hasToolbar => title != null || onAction != null || onCancel != null;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final l = AppLocalizations.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    final body = scrollable ? SingleChildScrollView(child: child) : child;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SureSheetGrabber(),
          if (_hasToolbar)
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: showCancel
                        ? Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: onCancel ??
                                  () => Navigator.of(context).maybePop(),
                              style: TextButton.styleFrom(
                                foregroundColor: palette.link,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: Text(
                                cancelLabel ?? l.dsCancel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      title ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: onAction == null
                        ? null
                        : Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: busy
                                ? const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 16),
                                    child: SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : TextButton(
                                    key: actionKey,
                                    onPressed: actionEnabled ? onAction : null,
                                    style: TextButton.styleFrom(
                                      foregroundColor: palette.link,
                                      disabledForegroundColor:
                                          palette.textSubdued,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                    ),
                                    child: Text(
                                      actionLabel ?? l.dsSave,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                          ),
                  ),
                ],
              ),
            ),
          Flexible(child: body),
        ],
      ),
    );
  }
}

/// The iOS sheet grabber: a 36×5 rounded bar, 6 px from the top.
class SureSheetGrabber extends StatelessWidget {
  const SureSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: palette.textSubdued.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }
}
