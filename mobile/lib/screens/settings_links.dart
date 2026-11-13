import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'calendar_screen.dart';
import 'categories_screen.dart';
import 'connections_screen.dart';
import 'export_screen.dart';
import 'import_screen.dart';
import 'merchants_screen.dart';
import 'recent_transactions_screen.dart';
import 'rules_screen.dart';
import 'statement_upload_screen.dart';
import 'tags_screen.dart';

/// The Data and Tools groups of the settings screen.
///
/// Every row here opens a native screen. "Import · Upload statement" and
/// "Categories, tags, merchants" open a small chooser sheet first.
class SettingsLinkGroups extends StatelessWidget {
  const SettingsLinkGroups({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SureSectionHeader(label: l.shellSectionData),
        SurePanel.rows(
          margin: settingsPanelMargin,
          children: [
            _screenRow(context, l.shellConnections,
                (_) => const ConnectionsScreen()),
            SureListRow(
              key: const ValueKey('settingsImportRow'),
              title: l.ds2sImportUpload,
              showChevron: true,
              onTap: () => _showChooser(context, l.shellImport, [
                _Choice(l.ds2sImportCsv, (_) => const ImportScreen()),
                _Choice(l.dataInStatementTitle,
                    (_) => const StatementUploadScreen()),
              ]),
            ),
            SureListRow(
              key: const ValueKey('settingsMetadataRow'),
              title: l.ds2sMetadata,
              showChevron: true,
              onTap: () => _showChooser(context, l.ds2sMetadata, [
                _Choice(l.shellCategories, (_) => const CategoriesScreen()),
                _Choice(l.shellTags, (_) => const TagsScreen()),
                _Choice(l.shellMerchants, (_) => const MerchantsScreen()),
              ]),
            ),
            _screenRow(context, l.shellRules, (_) => const RulesScreen()),
            _screenRow(context, l.shellExport, (_) => const ExportScreen()),
          ],
        ),
        SureSectionHeader(label: l.shellSectionTools),
        SurePanel.rows(
          margin: settingsPanelMargin,
          children: [
            _screenRow(context, l.moreCalendar, (_) => const CalendarScreen(),
                subtitle: l.moreCalendarSubtitle),
            _screenRow(context, l.moreRecentTransactions,
                (_) => const RecentTransactionsScreen(),
                subtitle: l.moreRecentTransactionsSubtitle),
          ],
        ),
      ],
    );
  }

  static SureListRow _screenRow(
    BuildContext context,
    String title,
    WidgetBuilder builder, {
    String? subtitle,
  }) =>
      SureListRow(
        title: title,
        subtitle: subtitle,
        showChevron: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: builder)),
      );

  /// A small sheet listing [choices]; tapping one closes the sheet and opens
  /// that screen.
  static Future<void> _showChooser(
    BuildContext context,
    String title,
    List<_Choice> choices,
  ) async {
    final picked = await showSureSheet<_Choice>(
      context: context,
      builder: (sheetContext) => SureSheet(
        title: title,
        child: SafeArea(
          top: false,
          child: SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              for (final choice in choices)
                SureListRow(
                  title: choice.label,
                  showChevron: true,
                  onTap: () => Navigator.pop(sheetContext, choice),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: picked.builder));
  }
}

/// Horizontal margin of a settings panel, matching [SureSectionHeader]'s
/// 16 px inset.
const EdgeInsets settingsPanelMargin = EdgeInsets.symmetric(horizontal: 16);

/// A settings row that opens [path] in the in-app web view, marked with a
/// small arrow-up-right.
class SettingsWebRow extends StatelessWidget {
  const SettingsWebRow({
    super.key,
    required this.title,
    required this.path,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String path;
  final String? subtitle;

  /// Replaces opening [path] on the web (a native screen on servers that
  /// support it).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final native = onTap != null;
    return SureListRow(
      title: title,
      subtitle: subtitle,
      // A native screen gets a chevron; only a web page keeps the ↗ mark.
      trailing: native ? null : const SettingsWebMark(),
      showChevron: native,
      onTap: onTap ?? () => openWebFallback(context, title: title, path: path),
    );
  }
}

/// The arrow-up-right that marks a row opening outside the native app.
class SettingsWebMark extends StatelessWidget {
  const SettingsWebMark({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SureIcon(
      SureIcons.arrowUpRight,
      size: size,
      color: SureColors.of(context).palette.textSubdued,
      semanticLabel: AppLocalizations.of(context).shellOpensOnWeb,
    );
  }
}

class _Choice {
  const _Choice(this.label, this.builder);

  final String label;
  final WidgetBuilder builder;
}
