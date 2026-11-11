import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_list_group.dart';
import 'calendar_screen.dart';
import 'cash_flow_screen.dart';
import 'categories_screen.dart';
import 'export_screen.dart';
import 'import_screen.dart';
import 'merchants_screen.dart';
import 'recent_transactions_screen.dart';
import 'statement_upload_screen.dart';
import 'tags_screen.dart';

/// The Data, Tools and You sections at the top of the settings screen.
///
/// Rows with a globe icon open the web page in the in-app web view
/// (Connections, Rules and the You section); the rest are native screens.
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

    // A native screen with no subtitle, sitting among web rows.
    SureListRow screen(IconData icon, String title, WidgetBuilder builder) =>
        SureListRow(
          leading: _iconBadge(context, icon),
          title: title,
          showChevron: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: builder),
          ),
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
            screen(Icons.upload_file_outlined, l.shellImport,
                (_) => const ImportScreen()),
            screen(Icons.description_outlined, l.dataInStatementTitle,
                (_) => const StatementUploadScreen()),
            screen(Icons.category_outlined, l.shellCategories,
                (_) => const CategoriesScreen()),
            screen(Icons.sell_outlined, l.shellTags,
                (_) => const TagsScreen()),
            screen(Icons.storefront_outlined, l.shellMerchants,
                (_) => const MerchantsScreen()),
            web(Icons.rule, l.shellRules, '/rules'),
            screen(Icons.download_outlined, l.shellExport,
                (_) => const ExportScreen()),
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
