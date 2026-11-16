import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/app_localizations.dart';
import '../models/household.dart';
import '../services/household_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import 'form_sheet_fields.dart';
import 'settings_links.dart';
import 'sharing_screens.dart';

/// The web page that lists pending invitations with their accept links.
const String householdWebProfilePath = '/settings/profile';

/// The household's members and pending invitations (Sure+
/// `household.members`). Admins invite with "+" and revoke by swiping an
/// invitation. Accepting an invitation stays on the web.
class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final HouseholdService? service;
  final Future<String?> Function()? accessTokenLoader;
  final Future<void> Function()? onUnauthorized;

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

/// The label of a household [role].
String householdRoleLabel(AppLocalizations l, String role) => switch (role) {
      'admin' => l.s4hRoleAdmin,
      'super_admin' => l.s4hRoleSuperAdmin,
      'guest' => l.s4hRoleGuest,
      _ => l.s4hRoleMember,
    };

class _HouseholdScreenState extends State<HouseholdScreen>
    with HouseholdCalls {
  late final HouseholdService _service;
  Household? _household;
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
        await runHousehold((token) => _service.members(accessToken: token));
    if (result == null) return;
    if (result['success'] != true && _household != null) {
      showHouseholdError(result);
    }
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _household = result['household'] as Household;
      }
    });
  }

  Future<void> _invite() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showSureSheet<({String email, String? delivery})>(
      context: context,
      builder: (sheetContext) => _InviteSheet(
        onSubmit: (email, role) async {
          final result = await runHousehold((token) =>
              _service.invite(accessToken: token, email: email, role: role));
          if (result == null) return l.manageActionFailed;
          if (result['success'] != true) {
            return result['error']?.toString() ?? l.manageActionFailed;
          }
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop(
                (email: email, delivery: result['delivery'] as String?));
          }
          return null;
        },
      ),
    );
    if (sent == null || !mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(sent.delivery == 'link_only'
          ? l.s4hInviteCreated
          : l.s4hInviteSent(sent.email)),
    ));
    await _load();
  }

  Future<void> _revoke(HouseholdInvitation invitation) async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.s4hRevokeTitle(invitation.email)),
        content: Text(l.s4hRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: palette.destructive),
            child: Text(l.s4hRevoke),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await runHousehold((token) =>
        _service.revokeInvitation(accessToken: token, id: invitation.id));
    if (result == null || !mounted) return;
    if (result['success'] != true) return showHouseholdError(result);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.s4hRevoked)));
    await _load();
  }

  Widget _invitationRow(
      AppLocalizations l, Household household, HouseholdInvitation invitation) {
    final palette = SureColors.of(context).palette;
    final role = householdRoleLabel(l, invitation.role);
    final expires = invitation.expiresAt;
    final row = SureListRow(
      title: invitation.email,
      subtitle: expires == null
          ? role
          : l.s4hInvitedSubtitle(role, SureDates.shortOf(context, expires)),
    );
    // Only admins may revoke.
    if (!household.canManageInvitations) return row;
    void revoke() => _revoke(invitation);
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l.s4hRevoke): revoke,
      },
      child: SureSwipeActions(
        key: ValueKey('invitation-${invitation.id}'),
        actionWidth: 96,
        actions: [
          SureSwipeAction(
            label: l.s4hRevoke,
            color: palette.destructive,
            onPressed: revoke,
          ),
        ],
        child: ColoredBox(color: palette.container, child: row),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final household = _household;

    final Widget content;
    if (household == null && _loading) {
      content = const ManageLoading();
    } else if (household == null) {
      content = SureEmptyState(
        key: const ValueKey('householdError'),
        icon: SureIcons.circleAlert,
        title: l.s4hLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _load,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SureSectionHeader(label: l.s4hMembers),
          SurePanel.rows(
            margin: settingsPanelMargin,
            children: [
              for (final member in household.members)
                SureListRow(
                  title: () {
                    final name =
                        member.name.isEmpty ? member.email : member.name;
                    return member.isCurrentUser ? l.s4hYou(name) : name;
                  }(),
                  subtitle: member.name.isEmpty ? null : member.email,
                  subtitleMaxLines: 1,
                  value: householdRoleLabel(l, member.role),
                ),
            ],
          ),
          if (household.invitations.isNotEmpty) ...[
            SureSectionHeader(label: l.s4hInvited),
            SurePanel.rows(
              margin: settingsPanelMargin,
              children: [
                for (final invitation in household.invitations)
                  _invitationRow(l, household, invitation),
              ],
            ),
          ],
          // The web profile shows every member the accept links when the
          // server doesn't email them.
          if (household.linkOnly) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(32, SureSpacing.md, 32, 0),
              child: Text(
                l.s4hLinkOnlyNote,
                key: const ValueKey('householdLinkOnlyNote'),
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
            SurePanel.rows(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              children: [
                SureListRow(
                  key: const ValueKey('householdOpenProfileOnWeb'),
                  title: l.s4hOpenProfileOnWeb,
                  titleColor: palette.link,
                  trailing: const SettingsWebMark(),
                  onTap: () => openWebFallback(
                    context,
                    title: l.s4hHousehold,
                    path: householdWebProfilePath,
                    backLabel: l.s4hHousehold,
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return SureLargeTitleScaffold(
      title: l.s4hHousehold,
      leading: manageBackLink(context),
      actions: [
        if (household?.canManageInvitations == true)
          SureNavIconButton(
            key: const ValueKey('householdInvite'),
            icon: SureIcons.plus,
            semanticLabel: l.s4hInvite,
            onPressed: _invite,
          ),
      ],
      onRefresh: _load,
      slivers: [SliverToBoxAdapter(child: content)],
    );
  }
}

/// The invite form: an email and a role. [onSubmit] returns an error to
/// show, or null once the invitation exists (it closes the sheet itself).
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.onSubmit});

  final Future<String?> Function(String email, String role) onSubmit;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _emailFocus = FocusNode();
  String _role = 'member';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _emailFocus.requestFocus());
  }

  @override
  void dispose() {
    _email.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(_email.text.trim(), _role);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return SureSheet(
      title: l.s4hInviteTitle,
      actionLabel: l.s4hInvite,
      actionKey: const ValueKey('inviteSubmit'),
      busy: _busy,
      onAction: _submit,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SurePanel.rows(
                children: [
                  FormSheetFieldRow(
                    label: l.s4hEmail,
                    fieldKey: const ValueKey('inviteEmail'),
                    controller: _email,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        _emailPattern.hasMatch((value ?? '').trim())
                            ? null
                            : l.s4hEmailInvalid,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  l.s4hRole,
                  style: TextStyle(fontSize: 13, color: palette.textSecondary),
                ),
              ),
              SureSegmentedControl<String>(
                key: const ValueKey('inviteRole'),
                segments: [
                  SureSegment(value: 'admin', label: l.s4hRoleAdmin),
                  SureSegment(value: 'member', label: l.s4hRoleMember),
                  SureSegment(value: 'guest', label: l.s4hRoleGuest),
                ],
                selected: _role,
                onChanged: (value) => setState(() => _role = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: SureSpacing.lg),
                ManageErrorText(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
