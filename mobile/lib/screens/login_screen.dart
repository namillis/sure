import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/sso_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_config.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_logo.dart';
import 'auth_fields.dart';
import 'backend_config_screen.dart';
import '../l10n/app_localizations.dart';

/// The server row's value: the backend URL without its scheme.
@visibleForTesting
String loginServerLabel(String baseUrl) =>
    baseUrl.replaceFirst(RegExp(r'^https?://'), '');

class LoginScreen extends StatefulWidget {
  final VoidCallback? onGoToSettings;

  const LoginScreen({super.key, this.onGoToSettings});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _emailPlaceholder = 'user@example.com';
  static const _passwordPlaceholder = 'Password1!';
  final _emailController = TextEditingController(text: _emailPlaceholder);
  final _passwordController = TextEditingController(text: _passwordPlaceholder);
  final _otpController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  late final TapGestureRecognizer _signUpTapRecognizer;
  static const _legacyProviders = [
    SsoProvider(name: 'google_oauth2', strategy: 'google_oauth2', label: ''),
  ];
  Future<List<SsoProvider>?>? _ssoProvidersFuture;
  String? _ssoProvidersBaseUrl;

  @override
  void initState() {
    super.initState();
    _signUpTapRecognizer = TapGestureRecognizer()..onTap = _openSignUpPage;
    _emailFocus.addListener(() => _clearPlaceholderOnFocus(
          _emailFocus, _emailController, _emailPlaceholder));
    _passwordFocus.addListener(() => _clearPlaceholderOnFocus(
          _passwordFocus, _passwordController, _passwordPlaceholder));
  }

  Future<void> _openSettings() async {
    if (widget.onGoToSettings != null) {
      widget.onGoToSettings!();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => BackendConfigScreen(
          onConfigSaved: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
    // Rebuild so the backend URL card and SSO providers reflect the new server.
    if (mounted) setState(() {});
  }

  /// Refetches when the backend URL changes (e.g. after editing settings).
  Future<List<SsoProvider>?> _ssoProviders(AuthProvider authProvider) {
    if (_ssoProvidersFuture == null ||
        _ssoProvidersBaseUrl != ApiConfig.baseUrl) {
      _ssoProvidersBaseUrl = ApiConfig.baseUrl;
      // A failed fetch isn't cached, so the next rebuild (e.g. returning from
      // settings) retries instead of keeping the Google fallback.
      late final Future<List<SsoProvider>?> future;
      future = authProvider.fetchSsoProviders().then((providers) {
        if (providers == null && identical(_ssoProvidersFuture, future)) {
          _ssoProvidersFuture = null;
        }
        return providers;
      });
      _ssoProvidersFuture = future;
    }
    return _ssoProvidersFuture!;
  }

  void _clearPlaceholderOnFocus(
      FocusNode node, TextEditingController controller, String placeholder) {
    if (node.hasFocus && controller.text == placeholder) {
      controller.clear();
    }
  }

  @override
  void dispose() {
    _signUpTapRecognizer.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _openSignUpPage() async {
    final l = AppLocalizations.of(context);
    final signUpUrl = Uri.parse('${ApiConfig.defaultBaseUrl}/registration/new');
    final launched = await launchUrl(
      signUpUrl,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.loginSignUpOpenError)),
      );
    }
  }

  Future<void> _showApiKeyDialog() async {
    // The dialog owns its TextEditingController and disposes it in its own
    // State.dispose(), so the controller's lifecycle is tied to the dialog's
    // widget tree: no leak on barrier/back dismissal, and it is never disposed
    // out from under a still-mounted TextField during the exit transition.
    final result = await showSureSheet<bool>(
      context: context,
      builder: (_) => const ApiKeyLoginDialog(),
    );

    // result: true = signed in, false = login attempt failed, null = dismissed.
    if (result == false && mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authProvider.errorMessage ??
                AppLocalizations.of(context).loginApiKeyInvalid,
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final hadOtpCode =
        authProvider.showMfaInput && _otpController.text.isNotEmpty;

    final success = await authProvider.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      otpCode: authProvider.showMfaInput ? _otpController.text.trim() : null,
    );

    // Check if widget is still mounted after async operation
    if (!mounted) return;

    // Clear OTP field if login failed and user had entered an OTP code
    // This allows user to easily try again with a new code
    if (!success && hadOtpCode && authProvider.errorMessage != null) {
      _otpController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: SureLogo(size: 64)),
                        const SizedBox(height: 20),
                        Text(
                          l.loginSignIn,
                          key: const ValueKey('login-title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              color: palette.textSecondary,
                            ),
                            children: [
                              TextSpan(text: l.loginDemoOrSignUpPrefix),
                              TextSpan(
                                text: l.loginSignUpLink,
                                style: TextStyle(
                                  color: palette.link,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: _signUpTapRecognizer,
                              ),
                              TextSpan(text: l.loginSignUpSuffix),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),

                        // Error message
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, _) {
                            final message = authProvider.errorMessage;
                            if (message == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: AuthErrorPanel(
                                message: message,
                                dismissLabel: l.ds4aDismissError,
                                onDismiss: authProvider.clearError,
                              ),
                            );
                          },
                        ),

                        // Email, password and (when required) MFA code
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, _) =>
                              _buildFields(l, authProvider.showMfaInput),
                        ),

                        const SizedBox(height: 20),

                        // Sign-in button
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, _) {
                            return SureButton(
                              key: const ValueKey('login-submit'),
                              label: l.loginSignIn,
                              size: SureButtonSize.lg,
                              fullWidth: true,
                              loading: authProvider.isLoading,
                              onPressed: _handleLogin,
                            );
                          },
                        ),

                        FutureBuilder<List<SsoProvider>?>(
                          future: _ssoProviders(
                              Provider.of<AuthProvider>(context, listen: false)),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const SizedBox.shrink();
                            }
                            // Servers without the providers endpoint only
                            // supported Google on mobile.
                            final providers = snapshot.data ?? _legacyProviders;
                            if (providers.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Expanded(child: SureHairline()),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(
                                        l.loginOrDivider,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: palette.textSubdued,
                                        ),
                                      ),
                                    ),
                                    const Expanded(child: SureHairline()),
                                  ],
                                ),
                                for (final provider in providers) ...[
                                  const SizedBox(height: 12),
                                  _SsoButton(provider: provider),
                                ],
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 28),

                        // Server URL
                        SurePanel.rows(
                          children: [
                            SureListRow(
                              key: const ValueKey('login-server-row'),
                              title: l.ds4aServerRow,
                              value: loginServerLabel(ApiConfig.baseUrl),
                              showChevron: true,
                              onTap: _openSettings,
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // API-key login
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, _) {
                            return AuthQuietLink(
                              key: const ValueKey('login-api-key'),
                              label: l.ds4aApiKeyLink,
                              onPressed: authProvider.isLoading
                                  ? null
                                  : _showApiKeyDialog,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              end: 4,
              top: 0,
              child: SureNavIconButton(
                icon: SureIcons.settings,
                semanticLabel: l.loginBackendSettingsTooltip,
                onPressed: _openSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFields(AppLocalizations l, bool showOtp) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurePanel.rows(
          children: [
            AuthFieldRow(
              fieldKey: const ValueKey('login-email'),
              label: l.loginEmailLabel,
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.loginEmailRequired;
                }
                if (!value.contains('@')) {
                  return l.loginEmailInvalid;
                }
                return null;
              },
            ),
            AuthFieldRow(
              fieldKey: const ValueKey('login-password'),
              label: l.loginPasswordLabel,
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              textInputAction:
                  showOtp ? TextInputAction.next : TextInputAction.done,
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
              onFieldSubmitted: showOtp ? null : (_) => _handleLogin(),
            ),
          ],
        ),

        // MFA step: shown when the server asks for a code.
        if (showOtp) ...[
          const SizedBox(height: 12),
          AuthNotePanel(icon: AuthIcons.shield, message: l.loginMfaInfo),
          const SizedBox(height: 12),
          SurePanel.rows(
            children: [
              AuthFieldRow(
                fieldKey: const ValueKey('login-otp'),
                label: l.ds4aCodeLabel,
                controller: _otpController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                mono: true,
                autofillHints: const [AutofillHints.oneTimeCode],
                hint: l.loginMfaLabel,
                validator: (value) {
                  if (showOtp && (value == null || value.isEmpty)) {
                    return l.loginMfaCodeRequired;
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleLogin(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// API-key login sheet. Owns its [TextEditingController] so it is disposed
/// with the sheet's State — never leaked (barrier/back dismissal) and never
/// disposed while the field is still mounted. Pops `true` on a successful
/// sign-in, `false` on a failed attempt, and `null` when dismissed.
@visibleForTesting
class ApiKeyLoginDialog extends StatefulWidget {
  const ApiKeyLoginDialog({super.key, this.controller});

  /// Test seam: a controller the sheet will adopt and dispose, so a test can
  /// assert disposal. Production passes none and the sheet creates its own.
  @visibleForTesting
  final TextEditingController? controller;

  @override
  State<ApiKeyLoginDialog> createState() => _ApiKeyLoginDialogState();
}

class _ApiKeyLoginDialogState extends State<ApiKeyLoginDialog> {
  late final TextEditingController _apiKeyController =
      widget.controller ?? TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _apiKeyController.removeListener(_onTextChanged);
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty || _isLoading) return;

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.loginWithApiKey(apiKey: apiKey);

    if (!mounted) return;
    Navigator.of(context).pop(success);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return SureSheet(
      title: l.loginApiKeyDialogTitle,
      actionLabel: l.loginApiKeySignIn,
      actionKey: const ValueKey('api-key-submit'),
      onAction: _submit,
      actionEnabled: _apiKeyController.text.trim().isNotEmpty,
      busy: _isLoading,
      // Cancel does nothing while the sign-in request is in flight.
      onCancel: _isLoading ? () {} : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.loginApiKeyDialogBody,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            SurePanel.rows(
              children: [
                AuthFieldRow(
                  fieldKey: const ValueKey('api-key-field'),
                  label: l.loginApiKeyLabel,
                  controller: _apiKeyController,
                  obscureText: true,
                  autocorrect: false,
                  enabled: !_isLoading,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SsoButton extends StatelessWidget {
  final SsoProvider provider;

  const _SsoButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return SureButton(
          label: provider.isGoogle ? l.loginSignInWithGoogle : provider.label,
          variant: SureButtonVariant.outline,
          size: SureButtonSize.lg,
          fullWidth: true,
          leading: provider.isGoogle
              ? SvgPicture.asset(
                  'assets/images/google_g_logo.svg',
                  width: 18,
                  height: 18,
                )
              : const SureIcon(AuthIcons.logIn, size: 18),
          onPressed: authProvider.isLoading
              ? null
              : () => authProvider.startSsoLogin(provider.name),
        );
      },
    );
  }
}
