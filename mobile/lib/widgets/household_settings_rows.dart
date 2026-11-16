import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/household.dart';
import '../providers/auth_provider.dart';
import '../providers/server_features_provider.dart';
import '../screens/household_screen.dart';
import '../screens/settings_links.dart';
import '../screens/sharing_screens.dart';
import '../services/household_service.dart';
import 'ds/ds.dart';

/// The Settings "Household" group on Sure+ servers: "Household" with
/// `household.members`, and "Budget sharing" with `budgets.sharing` once
/// `GET /budget_shares` says the family uses personal budgets. Renders
/// nothing when neither row applies.
class HouseholdSettingsRows extends StatefulWidget {
  const HouseholdSettingsRows({
    super.key,
    this.service,
    this.accessTokenLoader,
  });

  final HouseholdService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  @override
  State<HouseholdSettingsRows> createState() => _HouseholdSettingsRowsState();
}

class _HouseholdSettingsRowsState extends State<HouseholdSettingsRows> {
  HouseholdService? _ownService;

  /// Null until checked; any failure counts as false (the row stays hidden).
  bool? _personalBudgets;
  bool _checking = false;

  HouseholdService get _service =>
      widget.service ?? (_ownService ??= HouseholdService());

  @override
  void dispose() {
    _ownService?.close();
    super.dispose();
  }

  Future<void> _checkPersonalBudgets() async {
    _checking = true;
    final loader = widget.accessTokenLoader;
    final token = await (loader != null
        ? loader()
        : context.read<AuthProvider>().getValidAccessToken());
    if (!mounted) return;
    var personal = false;
    if (token != null) {
      final result = await _service.budgetSharing(accessToken: token);
      if (!mounted) return;
      personal = result['success'] == true &&
          (result['sharing'] as BudgetSharing).personalBudgets;
    }
    setState(() {
      _checking = false;
      _personalBudgets = personal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    bool members;
    bool budgets;
    try {
      final features = context.watch<ServerFeaturesProvider>();
      members = features.has(ServerFeaturesProvider.householdMembers);
      budgets = features.has(ServerFeaturesProvider.budgetsSharing);
    } on ProviderNotFoundException {
      members = budgets = false;
    }
    if (budgets && _personalBudgets == null && !_checking) {
      _checking = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _checkPersonalBudgets());
    }
    final showBudgets = budgets && _personalBudgets == true;
    if (!members && !showBudgets) return const SizedBox.shrink();

    void open(Widget screen) => Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => screen));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SureSectionHeader(label: l.s4hHousehold),
        SurePanel.rows(
          margin: settingsPanelMargin,
          children: [
            if (members)
              SureListRow(
                key: const ValueKey('settingsHouseholdRow'),
                title: l.s4hHousehold,
                showChevron: true,
                onTap: () => open(HouseholdScreen(service: widget.service)),
              ),
            if (showBudgets)
              SureListRow(
                key: const ValueKey('settingsBudgetSharingRow'),
                title: l.s4hBudgetSharing,
                showChevron: true,
                onTap: () => open(BudgetSharingScreen(service: widget.service)),
              ),
          ],
        ),
      ],
    );
  }
}
