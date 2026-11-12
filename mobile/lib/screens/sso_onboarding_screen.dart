import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../l10n/app_localizations.dart';
import '../widgets/ds/ds.dart';
import '../widgets/sure_button.dart';
import 'auth_fields.dart';

class SsoOnboardingScreen extends StatefulWidget {
  const SsoOnboardingScreen({super.key});

  @override
  State<SsoOnboardingScreen> createState() => _SsoOnboardingScreenState();
}

class _SsoOnboardingScreenState extends State<SsoOnboardingScreen> {
  bool _showLinkForm = true;
  final _linkFormKey = GlobalKey<FormState>();
  final _createFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _emailController.text = authProvider.ssoEmail ?? '';
    _firstNameController.text = authProvider.ssoFirstName ?? '';
    _lastNameController.text = authProvider.ssoLastName ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _handleLinkAccount() async {
    if (!_linkFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.ssoLinkAccount(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  Future<void> _handleCreateAccount() async {
    if (!_createFormKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.ssoCreateAccount(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return SureLargeTitleScaffold(
          title: l.ssoOnboardingTitle,
          subtitle: authProvider.ssoEmail != null
              ? l.ssoOnboardingSignedInAs(authProvider.ssoEmail!)
              : l.ssoOnboardingGoogleVerified,
          // Onboarding replaces the sign-in screen, so "back" cancels it.
          leading: SureBackButton(
            label: l.loginSignIn,
            onPressed: authProvider.cancelSsoOnboarding,
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.list(
                children: [
                  if (authProvider.errorMessage != null) ...[
                    AuthErrorPanel(
                      message: authProvider.errorMessage!,
                      dismissLabel: l.ds4aDismissError,
                      onDismiss: authProvider.clearError,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Link existing / create new
                  if (authProvider.ssoAllowAccountCreation) ...[
                    SureSegmentedControl<bool>(
                      key: const ValueKey('sso-onboarding-mode'),
                      segments: [
                        SureSegment(
                          value: true,
                          label: l.ssoOnboardingTabLink,
                        ),
                        SureSegment(
                          value: false,
                          label: authProvider.ssoHasPendingInvitation
                              ? l.ssoOnboardingAcceptInvitation
                              : l.ssoOnboardingTabCreate,
                        ),
                      ],
                      selected: _showLinkForm,
                      onChanged: (value) =>
                          setState(() => _showLinkForm = value),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_showLinkForm)
                    _buildLinkForm(authProvider, l)
                  else
                    _buildCreateForm(authProvider, l),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLinkForm(AuthProvider authProvider, AppLocalizations l) {
    return Form(
      key: _linkFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthNotePanel(
            icon: AuthIcons.link,
            message: l.ssoOnboardingLinkCredentialsNote,
          ),
          const SizedBox(height: 12),
          SurePanel.rows(
            children: [
              AuthFieldRow(
                fieldKey: const ValueKey('sso-link-email'),
                label: l.loginEmailLabel,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.loginEmailRequired;
                  }
                  if (!value.contains('@')) return l.loginEmailInvalid;
                  return null;
                },
              ),
              AuthFieldRow(
                fieldKey: const ValueKey('sso-link-password'),
                label: l.loginPasswordLabel,
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                trailing: AuthPasswordToggle(
                  obscured: _obscurePassword,
                  showLabel: l.ds4aShowPassword,
                  hideLabel: l.ds4aHidePassword,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.loginPasswordRequired;
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleLinkAccount(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SureButton(
            key: const ValueKey('sso-link-submit'),
            label: l.ssoOnboardingLinkButton,
            size: SureButtonSize.lg,
            fullWidth: true,
            loading: authProvider.isLoading,
            onPressed: _handleLinkAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildCreateForm(AuthProvider authProvider, AppLocalizations l) {
    final hasPendingInvitation = authProvider.ssoHasPendingInvitation;
    return Form(
      key: _createFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthNotePanel(
            icon: hasPendingInvitation ? AuthIcons.mail : AuthIcons.userPlus,
            message: hasPendingInvitation
                ? l.ssoOnboardingPendingInvitationNote
                : l.ssoOnboardingCreateIdentityNote,
          ),
          const SizedBox(height: 12),
          SurePanel.rows(
            children: [
              AuthFieldRow(
                fieldKey: const ValueKey('sso-create-first-name'),
                label: l.ssoOnboardingFirstNameLabel,
                controller: _firstNameController,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.ssoOnboardingFirstNameRequired;
                  }
                  return null;
                },
              ),
              AuthFieldRow(
                fieldKey: const ValueKey('sso-create-last-name'),
                label: l.ssoOnboardingLastNameLabel,
                controller: _lastNameController,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.familyName],
                textInputAction: TextInputAction.done,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return l.ssoOnboardingLastNameRequired;
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleCreateAccount(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SureButton(
            key: const ValueKey('sso-create-submit'),
            label: hasPendingInvitation
                ? l.ssoOnboardingAcceptInvitation
                : l.ssoOnboardingCreateButton,
            size: SureButtonSize.lg,
            fullWidth: true,
            loading: authProvider.isLoading,
            onPressed: _handleCreateAccount,
          ),
        ],
      ),
    );
  }
}
