import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import 'sure_large_title.dart';

/// A large-title page whose body is a [NestedScrollView], for screens with a
/// control (a SureSegmentedControl) that pins under the nav bar once the
/// header scrolls away: the account page, Invest and Plan.
///
/// [SureLargeTitleHeader] is a pinned sliver, which overlaps a
/// NestedScrollView's body, so this widget instead puts a [SureNavBar] above
/// the scroll view. The large title (and [subtitle]) plus [headerSlivers]
/// scroll away under the bar; [pinned] sits at the top of the body, so it
/// stays under the bar while [body] scrolls below it. The bar's small title
/// fades in, with a hairline under it, once most of the large title is gone.
///
/// Fills its parent; put it in a Scaffold's body. [body] should be a scroll
/// view that uses the PrimaryScrollController (the NestedScrollView's inner
/// controller), which ListView and CustomScrollView do by default.
///
/// ```dart
/// Scaffold(
///   body: SureCollapsingHeader(
///     title: 'Invest',
///     subtitle: '3 accounts',
///     leading: const SureBackButton(label: 'Home'),
///     actions: [menu],
///     headerSlivers: [SliverToBoxAdapter(child: summary)],
///     pinned: SureSegmentedControl(...),
///     body: list,
///   ),
/// )
/// ```
class SureCollapsingHeader extends StatefulWidget {
  const SureCollapsingHeader({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.headerSlivers = const <Widget>[],
    this.pinned,
    this.pinnedPadding = const EdgeInsets.fromLTRB(16, 4, 16, 4),
    this.controller,
    this.navBarKey,
    this.subtitleKey,
    this.pinnedKey,
  });

  /// The large title, and the small bar title once collapsed.
  final String title;

  /// A line under the large title (e.g. "Brokerage · synced 9h ago").
  final String? subtitle;

  /// Top-left widget, usually a [SureBackButton]. Nothing is implied.
  final Widget? leading;

  /// Trailing nav bar actions ([SureNavIconButton], [SureNavTextButton]).
  final List<Widget> actions;

  /// Slivers under the large title that scroll away with it (a hero, a
  /// chart).
  final List<Widget> headerSlivers;

  /// A control that stays pinned under the nav bar, on the page color.
  final Widget? pinned;
  final EdgeInsetsGeometry pinnedPadding;

  /// The scrolling content under [pinned].
  final Widget body;

  /// The NestedScrollView's outer controller. One is created when null.
  final ScrollController? controller;

  /// Keys for the nav bar, the subtitle text and the pinned control's
  /// container, so screens and tests can find them.
  final Key? navBarKey;
  final Key? subtitleKey;
  final Key? pinnedKey;

  /// Height of the large title block (with its subtitle, if any). The small
  /// title shows once 70% of it has scrolled away.
  static double largeTitleExtent({required bool hasSubtitle}) =>
      SureLargeTitleHeader.largeTitleHeight +
      (hasSubtitle ? SureLargeTitleHeader.subtitleHeight : 0);

  @override
  State<SureCollapsingHeader> createState() => _SureCollapsingHeaderState();
}

class _SureCollapsingHeaderState extends State<SureCollapsingHeader> {
  ScrollController? _ownController;
  bool _collapsed = false;

  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(SureCollapsingHeader old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onScroll);
      _controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _ownController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final threshold = SureCollapsingHeader.largeTitleExtent(
          hasSubtitle: widget.subtitle != null,
        ) *
        0.7;
    final collapsed =
        _controller.hasClients && _controller.offset > threshold;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final pinned = widget.pinned;
    return Column(
      children: [
        SureNavBar(
          key: widget.navBarKey,
          title: widget.title,
          showTitle: _collapsed,
          leading: widget.leading,
          actions: widget.actions,
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: NestedScrollView(
              controller: _controller,
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverToBoxAdapter(
                  child: SureLargeTitle(
                    title: widget.title,
                    subtitle: widget.subtitle,
                    subtitleKey: widget.subtitleKey,
                  ),
                ),
                ...widget.headerSlivers,
              ],
              body: pinned == null
                  ? widget.body
                  : Column(
                      children: [
                        Container(
                          key: widget.pinnedKey,
                          color: palette.surface,
                          padding: widget.pinnedPadding,
                          child: pinned,
                        ),
                        Expanded(child: widget.body),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A standalone 44 px iOS nav bar (plus the top safe area): [leading], a
/// small centered [title] that fades in when [showTitle] is true, trailing
/// [actions], and a hairline under it while the title shows. Used by
/// [SureCollapsingHeader]; use it directly for a bar outside a scroll view.
class SureNavBar extends StatelessWidget {
  const SureNavBar({
    super.key,
    required this.title,
    required this.showTitle,
    this.leading,
    this.actions = const <Widget>[],
  });

  final String title;
  final bool showTitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          bottom: BorderSide(
            color: showTitle ? colors.hairline : const Color(0x00000000),
          ),
        ),
      ),
      child: SizedBox(
        height: SureLargeTitleHeader.barHeight,
        child: NavigationToolbar(
          leading: leading,
          middle: Semantics(
            excludeSemantics: !showTitle,
            header: showTitle,
            child: AnimatedOpacity(
              opacity: showTitle ? 1 : 0,
              duration: const Duration(milliseconds: 150),
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
    );
  }
}

/// An iOS large title (32 pt weight 600, the same type as
/// [SureLargeTitleHeader]) with an optional subtitle, as a plain box for
/// scroll views that cannot use the pinned sliver.
class SureLargeTitle extends StatelessWidget {
  const SureLargeTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleKey,
  });

  final String title;
  final String? subtitle;
  final Key? subtitleKey;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Padding(
      // A subtitle block sits 4 px lower, as on the account page.
      padding: EdgeInsets.fromLTRB(16, subtitle == null ? 0 : 4, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: scaler,
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
              key: subtitleKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: scaler,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
