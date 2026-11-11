import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../sure_icon.dart';

/// A page with an iOS large title: [SureLargeTitleHeader] pinned at the top of
/// a CustomScrollView over [slivers], on the `surface` page color.
///
/// ```dart
/// SureLargeTitleScaffold(
///   title: 'Activity',
///   actions: [SureNavIconButton(icon: SureIcons.plus, semanticLabel: 'New', onPressed: add)],
///   slivers: [SliverList.list(children: rows)],
/// )
/// ```
class SureLargeTitleScaffold extends StatelessWidget {
  const SureLargeTitleScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.automaticallyImplyLeading = true,
    this.onRefresh,
    this.controller,
    this.floatingActionButton,
    this.bottomPadding = 24,
  });

  final String title;

  /// A line under the large title (e.g. "Brokerage · synced 9h ago").
  final String? subtitle;
  final List<Widget> slivers;

  /// Top-left widget, e.g. [SureBackButton]. When null and the route can pop,
  /// a [SureBackButton] is shown unless [automaticallyImplyLeading] is false.
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;

  /// Adds pull-to-refresh.
  final RefreshCallback? onRefresh;
  final ScrollController? controller;
  final Widget? floatingActionButton;

  /// Space after the last sliver.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    Widget scroll = CustomScrollView(
      controller: controller,
      // Always scrollable so the title can collapse on short pages too.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SureLargeTitleHeader(
          title: title,
          subtitle: subtitle,
          leading: leading,
          actions: actions,
          automaticallyImplyLeading: automaticallyImplyLeading,
        ),
        ...slivers,
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: bottomPadding + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(
        onRefresh: onRefresh!,
        edgeOffset:
            MediaQuery.paddingOf(context).top + SureLargeTitleHeader.barHeight,
        child: scroll,
      );
    }
    return Scaffold(
      backgroundColor: SureColors.of(context).palette.surface,
      floatingActionButton: floatingActionButton,
      body: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: scroll,
      ),
    );
  }
}

/// The pinned large-title sliver: a 44 px bar (leading, small centered title,
/// trailing actions) over a 30–34 pt weight 600 title that collapses into the
/// small 17 pt centered title as the page scrolls. A hairline appears under
/// the bar once collapsed. Includes the top safe area.
class SureLargeTitleHeader extends StatelessWidget {
  const SureLargeTitleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.automaticallyImplyLeading = true,
  });

  static const double barHeight = 44;
  static const double largeTitleHeight = 48;
  static const double subtitleHeight = 20;

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    Widget? lead = leading;
    if (lead == null &&
        automaticallyImplyLeading &&
        (ModalRoute.of(context)?.canPop ?? false)) {
      lead = const SureBackButton();
    }
    return SliverPersistentHeader(
      pinned: true,
      delegate: _LargeTitleDelegate(
        title: title,
        subtitle: subtitle,
        leading: lead,
        actions: actions,
        topPadding: MediaQuery.paddingOf(context).top,
        colors: SureColors.of(context),
      ),
    );
  }
}

class _LargeTitleDelegate extends SliverPersistentHeaderDelegate {
  _LargeTitleDelegate({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.actions,
    required this.topPadding,
    required this.colors,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final double topPadding;
  final SureColors colors;

  double get _largeHeight =>
      SureLargeTitleHeader.largeTitleHeight +
      (subtitle == null ? 0 : SureLargeTitleHeader.subtitleHeight);

  @override
  double get minExtent => topPadding + SureLargeTitleHeader.barHeight;

  @override
  double get maxExtent => minExtent + _largeHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final palette = colors.palette;
    final progress = (shrinkOffset / _largeHeight).clamp(0.0, 1.0);
    // The small title fades in over the last 30% of the collapse; the large
    // one fades out over the first 70%.
    final smallOpacity = ((progress - 0.7) / 0.3).clamp(0.0, 1.0);
    final largeOpacity = (1 - progress / 0.7).clamp(0.0, 1.0);
    final visibleLarge = math.max(0.0, _largeHeight - shrinkOffset);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.hairline
                .withValues(alpha: colors.hairline.a * smallOpacity),
          ),
        ),
      ),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topPadding),
            SizedBox(
              height: SureLargeTitleHeader.barHeight,
              child: NavigationToolbar(
                leading: leading,
                middle: Semantics(
                  // The large title already names the page; read the small
                  // one only once it is the visible title.
                  excludeSemantics: smallOpacity == 0,
                  header: smallOpacity > 0,
                  child: Opacity(
                    opacity: smallOpacity,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
                trailing: actions.isEmpty
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: actions),
                middleSpacing: 8,
              ),
            ),
            SizedBox(
              height: visibleLarge,
              child: OverflowBox(
                alignment: Alignment.bottomLeft,
                minHeight: _largeHeight,
                maxHeight: _largeHeight,
                child: Opacity(
                  opacity: largeOpacity,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          excludeSemantics: largeOpacity == 0,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: MediaQuery.textScalerOf(context)
                                .clamp(maxScaleFactor: 1.3),
                            style: TextStyle(
                              fontSize: 32,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.6,
                              color: palette.textPrimary,
                            ),
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textScaler: MediaQuery.textScalerOf(context)
                                .clamp(maxScaleFactor: 1.3),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              color: palette.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_LargeTitleDelegate old) =>
      title != old.title ||
      subtitle != old.subtitle ||
      leading != old.leading ||
      actions != old.actions ||
      topPadding != old.topPadding ||
      !identical(colors.palette, old.colors.palette);
}

/// iOS back link: a chevron plus an optional [label] ("‹ Home") in the link
/// color. Pops the route unless [onPressed] is given.
class SureBackButton extends StatelessWidget {
  const SureBackButton({super.key, this.label, this.onPressed});

  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final tooltip = MaterialLocalizations.of(context).backButtonTooltip;
    return Semantics(
      button: true,
      label: label ?? tooltip,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed ?? () => Navigator.of(context).maybePop(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SureIcon(SureIcons.chevronLeft, size: 24, color: palette.link),
                if (label != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, color: palette.link),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44 px nav-bar icon button for [SureLargeTitleHeader.actions].
class SureNavIconButton extends StatelessWidget {
  const SureNavIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
  });

  /// Lucide icon name.
  final String icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Defaults to `textPrimary`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: semanticLabel,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: SureIcon(
                icon,
                size: 22,
                color: onPressed == null
                    ? palette.textSubdued
                    : (color ?? palette.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A nav-bar text action (e.g. "Cancel" or "Done") in the link color, 17 pt
/// weight 600, with a 44 px hit area. Grays out when [onPressed] is null.
class SureNavTextButton extends StatelessWidget {
  const SureNavTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: palette.link,
        disabledForegroundColor: palette.textSubdued,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    );
  }
}
