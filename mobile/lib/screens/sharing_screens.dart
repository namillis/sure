import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/household.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/household_service.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';

/// Lucide `users` (bundled as a category icon; no [SureIcons] constant).
const String householdIcon = 'users';

/// Token and sign-out handling shared by the household and sharing screens.
mixin HouseholdCalls<T extends StatefulWidget> on State<T> {
  /// Defaults to [AuthProvider.getValidAccessToken].
  Future<String?> Function()? get accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  Future<void> Function()? get onUnauthorized;

  /// Runs [call] with a token. Null when the screen went away or the session
  /// ended (the user is then signed out).
  Future<Map<String, dynamic>?> runHousehold(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final loader = accessTokenLoader;
    final token = await (loader != null
        ? loader()
        : context.read<AuthProvider>().getValidAccessToken());
    if (!mounted) return null;
    if (token == null) {
      await _signOut();
      return null;
    }
    final result = await call(token);
    if (!mounted) return null;
    if (result['error'] == 'unauthorized') {
      await _signOut();
      return null;
    }
    return result;
  }

  Future<void> _signOut() async {
    final handler = onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }

  void showHouseholdError(Map<String, dynamic> result) {
    final message = result['error']?.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message == null || message.isEmpty
          ? AppLocalizations.of(context).manageActionFailed
          : message),
    ));
  }
}

/// A member's name over a full-width segmented permission choice.
class ShareMemberRow extends StatelessWidget {
  const ShareMemberRow({
    super.key,
    required this.member,
    required this.segments,
    required this.onChanged,
  });

  final ShareMember member;
  final List<SureSegment<String>> segments;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final known = segments.any((s) => s.value == member.permission);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SureSegmentedControl<String>(
            key: ValueKey('shareMember-${member.userId}'),
            segments: segments,
            // A permission this control can't show reads as "None".
            selected: known ? member.permission : 'none',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// The footnote under a sharing panel.
class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: SureColors.of(context).palette.textSecondary,
          ),
        ),
      );
}

/// The member list of a sharing screen: one [ShareMemberRow] per member, each
/// change applied at once and reverted when the server refuses it.
class _ShareMemberList extends StatelessWidget {
  const _ShareMemberList({
    required this.members,
    required this.segments,
    required this.footnote,
    required this.onChanged,
  });

  final List<ShareMember> members;
  final List<SureSegment<String>> segments;
  final String footnote;
  final void Function(ShareMember member, String permission) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (members.isEmpty) {
      return SureEmptyState(
        icon: householdIcon,
        title: l.s4hNoOtherMembers,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurePanel.rows(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final member in members)
              ShareMemberRow(
                member: member,
                segments: segments,
                onChanged: (value) => onChanged(member, value),
              ),
          ],
        ),
        _Footnote(footnote),
      ],
    );
  }
}

/// Who an account is shared with (Sure+ `accounts.sharing`). The owner sets
/// each member's permission; someone it's shared with sees the owner and
/// their permission and chooses whether it counts in their own finances.
class AccountSharingScreen extends StatefulWidget {
  const AccountSharingScreen({
    super.key,
    required this.accountId,
    this.accountName,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final String accountId;
  final String? accountName;
  final HouseholdService? service;
  final Future<String?> Function()? accessTokenLoader;
  final Future<void> Function()? onUnauthorized;

  @override
  State<AccountSharingScreen> createState() => _AccountSharingScreenState();
}

class _AccountSharingScreenState extends State<AccountSharingScreen>
    with HouseholdCalls {
  late final HouseholdService _service;
  AccountSharing? _sharing;
  List<ShareMember> _members = const [];
  bool _loading = true;
  bool _savingInclude = false;

  @override
  Future<String?> Function()? get accessTokenLoader =>
      widget.accessTokenLoader;
  @override
  Future<void> Function()? get onUnauthorized => widget.onUnauthorized;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HouseholdService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await runHousehold((token) =>
        _service.accountSharing(accessToken: token, accountId: widget.accountId));
    if (result == null) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _sharing = result['sharing'] as AccountSharing;
        _members = _sharing!.members;
      }
    });
  }

  Future<void> _setMember(ShareMember member, String permission) async {
    final previous = member.permission;
    void apply(String value) => setState(() => _members = [
          for (final m in _members)
            m.userId == member.userId ? m.withPermission(value) : m,
        ]);
    apply(permission);
    final result = await runHousehold((token) => _service.setAccountMember(
        accessToken: token,
        accountId: widget.accountId,
        userId: member.userId,
        permission: permission));
    if (result == null || result['success'] == true) return;
    apply(previous);
    showHouseholdError(result);
  }

  Future<void> _setInclude(bool include) async {
    final sharing = _sharing;
    if (sharing == null) return;
    setState(() => _savingInclude = true);
    final result = await runHousehold((token) => _service.setIncludeInFinances(
        accessToken: token, accountId: widget.accountId, include: include));
    if (result == null) return;
    final ok = result['success'] == true;
    setState(() {
      _savingInclude = false;
      if (ok) _sharing = result['sharing'] as AccountSharing;
    });
    if (ok) {
      // Totals on Home and in groups change with this switch: reload them.
      _refreshAccounts();
    } else {
      showHouseholdError(result);
    }
  }

  Future<void> _refreshAccounts() async {
    final AccountsProvider accounts;
    final AuthProvider auth;
    try {
      accounts = context.read<AccountsProvider>();
      auth = context.read<AuthProvider>();
    } on ProviderNotFoundException {
      return;
    }
    final token = await auth.getValidAccessToken();
    if (token != null) await accounts.fetchAccounts(accessToken: token);
  }

  String _permissionLabel(AppLocalizations l, String? permission) =>
      switch (permission) {
        'full_control' => l.s4hPermissionFullControl,
        'read_write' => l.s4hPermissionReadWrite,
        _ => l.s4hPermissionReadOnly,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final sharing = _sharing;

    final Widget content;
    if (sharing == null && _loading) {
      content = const ManageLoading();
    } else if (sharing == null) {
      content = SureEmptyState(
        key: const ValueKey('accountSharingError'),
        icon: SureIcons.circleAlert,
        title: l.s4hSharingLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _load,
      );
    } else if (sharing.isOwner) {
      content = _ShareMemberList(
        members: _members,
        footnote: l.s4hAccountSharingFooter,
        segments: [
          SureSegment(value: 'none', label: l.s4hPermNone),
          SureSegment(value: 'read_only', label: l.s4hPermView),
          SureSegment(value: 'read_write', label: l.s4hPermEdit),
          SureSegment(value: 'full_control', label: l.s4hPermFull),
        ],
        onChanged: _setMember,
      );
    } else {
      content = SurePanel.rows(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          SureListRow(
            title: l.s4hSharedBy(sharing.ownerName ?? '',
                _permissionLabel(l, sharing.permission)),
          ),
          SureListRow(
            title: l.s4hIncludeInFinances,
            trailing: Switch.adaptive(
              key: const ValueKey('includeInFinancesSwitch'),
              value: sharing.includeInFinances ?? true,
              onChanged: _savingInclude ? null : _setInclude,
              activeTrackColor: palette.success,
            ),
          ),
        ],
      );
    }

    return SureLargeTitleScaffold(
      title: l.s4hSharing,
      subtitle: widget.accountName,
      onRefresh: _load,
      slivers: [SliverToBoxAdapter(child: content)],
    );
  }
}

/// Who can see the user's personal budget (Sure+ `budgets.sharing`).
class BudgetSharingScreen extends StatefulWidget {
  const BudgetSharingScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final HouseholdService? service;
  final Future<String?> Function()? accessTokenLoader;
  final Future<void> Function()? onUnauthorized;

  @override
  State<BudgetSharingScreen> createState() => _BudgetSharingScreenState();
}

class _BudgetSharingScreenState extends State<BudgetSharingScreen>
    with HouseholdCalls {
  late final HouseholdService _service;
  List<ShareMember>? _members;
  bool _loading = true;

  @override
  Future<String?> Function()? get accessTokenLoader =>
      widget.accessTokenLoader;
  @override
  Future<void> Function()? get onUnauthorized => widget.onUnauthorized;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? HouseholdService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result =
        await runHousehold((token) => _service.budgetSharing(accessToken: token));
    if (result == null) return;
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _members = (result['sharing'] as BudgetSharing).members;
      }
    });
  }

  Future<void> _setMember(ShareMember member, String permission) async {
    final previous = member.permission;
    void apply(String value) => setState(() => _members = [
          for (final m in _members ?? const <ShareMember>[])
            m.userId == member.userId ? m.withPermission(value) : m,
        ]);
    apply(permission);
    final result = await runHousehold((token) => _service.setBudgetMember(
        accessToken: token, userId: member.userId, permission: permission));
    if (result == null || result['success'] == true) return;
    apply(previous);
    showHouseholdError(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final members = _members;
    final Widget content;
    if (members == null && _loading) {
      content = const ManageLoading();
    } else if (members == null) {
      content = SureEmptyState(
        key: const ValueKey('budgetSharingError'),
        icon: SureIcons.circleAlert,
        title: l.s4hSharingLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _load,
      );
    } else {
      content = _ShareMemberList(
        members: members,
        footnote: l.s4hBudgetSharingFooter,
        segments: [
          SureSegment(value: 'none', label: l.s4hPermNone),
          SureSegment(value: 'read_only', label: l.s4hPermView),
          SureSegment(value: 'read_write', label: l.s4hPermEdit),
        ],
        onChanged: _setMember,
      );
    }
    return SureLargeTitleScaffold(
      title: l.s4hBudgetSharing,
      leading: manageBackLink(context),
      onRefresh: _load,
      slivers: [SliverToBoxAdapter(child: content)],
    );
  }
}
