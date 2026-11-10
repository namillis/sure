import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_list_group.dart';
import 'calendar_screen.dart';
import 'cash_flow_screen.dart';
import 'recent_transactions_screen.dart';

/// The Data, Tools and You sections at the top of the settings screen.
///
/// Data and You rows open the matching web page in the in-app web view and
/// carry a globe icon saying so; Tools rows open native screens.
class SettingsLinkGroups extends StatelessWidget {
  const SettingsLinkGroups({super.key});

  static const _groupMargin = EdgeInsets.fromLTRB(
    SureSpacing.xl,
    SureSpacing.md,
    SureSpacing.xl,
    SureSpacing.xl,
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    SureListRow web(IconData icon, String title, String path) => SureListRow(
          leading: _iconBadge(context, icon),
          title: title,
          trailing: Icon(
            Icons.language,
            size: 18,
            color: SureColors.of(context).palette.textSubdued,
            semanticLabel: l.shellOpensOnWeb,
          ),
          onTap: () => openWebFallback(context, title: title, path: path),
        );

    SureListRow native(
      IconData icon,
      String title,
      String subtitle,
      WidgetBuilder builder,
    ) =>
        SureListRow(
          leading: _iconBadge(context, icon),
          title: title,
          subtitle: subtitle,
          showChevron: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: builder),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SureListGroup(
          header: l.shellSectionData,
          margin: _groupMargin,
          children: [
            web(Icons.link, l.shellConnections, '/settings/providers'),
            web(Icons.upload_file_outlined, l.shellImport, '/imports'),
            web(Icons.category_outlined, l.shellCategories, '/categories'),
            web(Icons.sell_outlined, l.shellTags, '/tags'),
            web(Icons.storefront_outlined, l.shellMerchants,
                '/family_merchants'),
            web(Icons.rule, l.shellRules, '/rules'),
            web(Icons.download_outlined, l.shellExport, '/family_exports'),
          ],
        ),
        SureListGroup(
          header: l.shellSectionTools,
          margin: _groupMargin,
          children: [
            native(Icons.calendar_month, l.moreCalendar,
                l.moreCalendarSubtitle, (_) => const CalendarScreen()),
            native(Icons.insights, l.moreCashFlow, l.moreCashFlowSubtitle,
                (_) => const CashFlowScreen()),
            native(
                Icons.receipt_long,
                l.moreRecentTransactions,
                l.moreRecentTransactionsSubtitle,
                (_) => const RecentTransactionsScreen()),
          ],
        ),
        SureListGroup(
          header: l.shellSectionYou,
          margin: _groupMargin,
          children: [
            web(Icons.person_outline, l.shellProfile, '/settings/profile'),
            web(Icons.tune, l.shellPreferences, '/settings/preferences'),
            web(Icons.shield_outlined, l.shellSecurity, '/settings/security'),
          ],
        ),
      ],
    );
  }

  Widget _iconBadge(BuildContext context, IconData icon) {
    final palette = SureColors.of(context).palette;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.surfaceInset,
        borderRadius: BorderRadius.circular(SureTokens.radiusMd),
      ),
      child: Icon(icon, color: palette.textPrimary),
    );
  }
}
