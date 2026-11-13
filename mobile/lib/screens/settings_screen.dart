import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/merchants_provider.dart';
import '../providers/tags_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/offline_storage_service.dart';
import '../services/log_service.dart';
import '../services/biometric_service.dart';
import '../services/preferences_service.dart';
import '../services/user_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'backend_config_screen.dart';
import 'log_viewer_screen.dart';
import 'profile_screen.dart';
import 'settings_links.dart';
import '../models/custom_proxy_header.dart';
import '../services/api_config.dart';
import '../services/custom_proxy_headers_service.dart';
import '../widgets/custom_proxy_headers_editor.dart';
import '../l10n/app_localizations.dart';

/// The label of the app-lock switch: "Face ID lock" / "Touch ID lock" on iOS
/// when the device reports that biometric, else "Biometric lock".
@visibleForTesting
String biometricLockLabel(
  AppLocalizations l,
  List<BiometricType> types,
  TargetPlatform platform,
) {
  if (platform == TargetPlatform.iOS) {
    if (types.contains(BiometricType.face)) return l.ds2sFaceIdLock;
    if (types.contains(BiometricType.fingerprint)) return l.ds2sTouchIdLock;
  }
  return l.ds2sBiometricLock;
}

/// Up to two initials for the profile circle: first and last name, else the
/// first letter of the display name (the email when there is no name).
@visibleForTesting
String profileInitials(User? user) {
  if (user == null) return 'U';
  String first(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? '' : t.characters.first.toUpperCase();
  }

  final initials = first(user.firstName) + first(user.lastName);
  if (initials.isNotEmpty) return initials;
  final fallback = first(user.displayName);
  return fallback.isEmpty ? 'U' : fallback;
}

/// The host of [baseUrl] ("demo.sure.am"), or the URL itself when it has none.
@visibleForTesting
String serverHost(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  return host.isEmpty ? baseUrl : host;
}

/// True when the server edits the profile through the API (Sure+
/// `profile.write`). Off when the app's providers aren't mounted (tests).
bool _hasNativeProfile(BuildContext context) {
  try {
    return context
        .watch<ServerFeaturesProvider>()
        .has(ServerFeaturesProvider.profileWrite);
  } on ProviderNotFoundException {
    return false;
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _appVersion;
  // Identifiers for the in-progress destructive action. Defined once so the
  // discriminator can't drift via a mistyped string literal across handlers and
  // tiles.
  static const String _clearAction = 'clear';
  static const String _resetAction = 'reset';
  static const String _deleteAction = 'delete';
  // Tracks which destructive action is in progress (one of the constants above),
  // or null when idle. Used to disable all three tiles while any one is running.
  String? _activeDestructiveAction;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  bool _isTogglingBiometric = false;
  List<BiometricType> _biometricTypes = const [];
  List<CustomProxyHeader> _customHeaders = [];
  bool _isCheckingForUpdate = false;
  late final Upgrader _manualUpgrader;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _loadBiometricState();
    _loadCustomHeaders();
    _manualUpgrader = Upgrader(
      durationUntilAlertAgain: Duration.zero,
      countryCode: 'us',
    );
  }

  Future<void> _checkForUpdate() async {
    if (_isCheckingForUpdate) return;
    setState(() => _isCheckingForUpdate = true);
    try {
      await _manualUpgrader.initialize();
      if (!mounted) {
        _manualUpgrader.dispose();
        return;
      }
      await _manualUpgrader.updateVersionInfo();
      if (!mounted) return;

      final available = _manualUpgrader.isUpdateAvailable();
      final storeVersion = _manualUpgrader.versionInfo?.appStoreVersion?.toString();
      final storeUrl = _manualUpgrader.versionInfo?.appStoreListingURL;

      if (available) {
        await _showUpdateDialog(
          storeVersion ??
              AppLocalizations.of(context).settingsUpdateNewerVersionFallback,
          storeUrl,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsNoUpdateAvailable)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsUpdateError)),
        );
      }
    } finally {
      if (mounted) setState(() => _isCheckingForUpdate = false);
    }
  }

  Future<void> _showUpdateDialog(String version, String? storeUrl) async {
    final launch = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).settingsUpdateAvailableTitle),
        content: Text(AppLocalizations.of(ctx).settingsUpdateAvailableContent(version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx).commonCancel),
          ),
          TextButton(
            onPressed: storeUrl == null ? null : () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(ctx).settingsUpdateNow),
          ),
        ],
      ),
    );

    if (launch == true && storeUrl != null && mounted) {
      final uri = Uri.tryParse(storeUrl);
      final opened = uri != null
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : false;
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsUpdateOpenStoreError)),
        );
      }
    }
  }

  @override
  void dispose() {
    _manualUpgrader.dispose();
    super.dispose();
  }

  Future<void> _loadBiometricState() async {
    final supported = await BiometricService.instance.isDeviceSupported();
    final enabled = await PreferencesService.instance.getBiometricEnabled();
    final types = supported
        ? await BiometricService.instance.getAvailableBiometrics()
        : const <BiometricType>[];
    if (!supported && enabled) {
      await PreferencesService.instance.setBiometricEnabled(false);
    }
    if (mounted) {
      setState(() {
        _biometricSupported = supported;
        _biometricEnabled = supported && enabled;
        _biometricTypes = types;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (_isTogglingBiometric) return;
    setState(() => _isTogglingBiometric = true);
    try {
      if (value) {
        final success = await BiometricService.instance.authenticate(
          reason: AppLocalizations.of(context).settingsBiometricVerifyReason,
        );
        if (!mounted) return;
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).settingsBiometricFailed)),
          );
          return;
        }
      }
      await PreferencesService.instance.setBiometricEnabled(value);
      if (mounted) setState(() => _biometricEnabled = value);
    } finally {
      if (mounted) setState(() => _isTogglingBiometric = false);
    }
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      final build = packageInfo.buildNumber;
      final display = build.isNotEmpty
          ? '${packageInfo.version} ($build)'
          : packageInfo.version;
      setState(() => _appVersion = display);
    }
  }

  Future<void> _loadCustomHeaders() async {
    try {
      final headers = await CustomProxyHeadersService.instance.loadHeaders();
      if (mounted) {
        setState(() => _customHeaders = headers);
      }
    } catch (e) {
      LogService.instance.warning(
        'SettingsScreen',
        'Failed to load custom headers with ${e.runtimeType}',
      );
      // Keep the existing _customHeaders state so the screen remains usable.
    }
  }

  Future<void> _handleClearLocalData(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
        title: Text(l.settingsClearDataTitle),
        content: Text(l.settingsClearDataContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: SureColors.of(context).palette.destructive,
            ),
            child: Text(l.settingsClearData),
          ),
        ],
      );},
    );

    if (confirmed == true && context.mounted) {
      setState(() => _activeDestructiveAction = _clearAction);
      try {
        final offlineStorage = OfflineStorageService();
        final log = LogService.instance;

        log.info('Settings', 'Clearing all local data...');
        await offlineStorage.clearAllData();
        if (context.mounted) {
          Provider.of<CategoriesProvider>(context, listen: false).clear();
          Provider.of<MerchantsProvider>(context, listen: false).clear();
          Provider.of<TagsProvider>(context, listen: false).clear();
        }
        log.info('Settings', 'Local data cleared successfully');

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.settingsClearDataSuccessDetailed),
              backgroundColor: SureColors.of(context).palette.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        final log = LogService.instance;
        log.error(
          'Settings',
          'Failed to clear local data with ${e.runtimeType}',
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.settingsClearDataFailed),
              backgroundColor: SureColors.of(context).palette.destructive,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _activeDestructiveAction = null);
      }
    }
  }

  Future<void> _launchContactUrl(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final uri = Uri.parse('https://discord.com/invite/36ZGBsxYEK');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsContactOpenLinkError)),
      );
    }
  }

  Future<void> _handleResetAccount(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.settingsResetAccount),
          content: Text(dl.settingsResetAccountContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: SureColors.of(context).palette.destructive,
              ),
              child: Text(dl.settingsResetAccount),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    setState(() => _activeDestructiveAction = _resetAction);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final accessToken = await authProvider.getValidAccessToken();
      if (accessToken == null) {
        await _signOut(authProvider);
        return;
      }

      final result = await UserService().resetAccount(accessToken: accessToken);

      if (!context.mounted) return;

      if (result['success'] == true) {
        await OfflineStorageService().clearAllData();
        if (context.mounted) {
          Provider.of<CategoriesProvider>(context, listen: false).clear();
          Provider.of<MerchantsProvider>(context, listen: false).clear();
          Provider.of<TagsProvider>(context, listen: false).clear();
        }

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.settingsResetAccountInitiated),
            backgroundColor: SureColors.of(context).palette.success,
          ),
        );

        await _signOut(authProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? l.settingsResetAccountFailed),
            backgroundColor: SureColors.of(context).palette.destructive,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activeDestructiveAction = null);
    }
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.settingsDeleteAccountTitle),
          content: Text(dl.settingsDeleteAccountConfirmContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                foregroundColor: SureColors.of(context).palette.destructive,
              ),
              child: Text(dl.settingsDeleteAccount),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    setState(() => _activeDestructiveAction = _deleteAction);
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final accessToken = await authProvider.getValidAccessToken();
      if (accessToken == null) {
        await _signOut(authProvider);
        return;
      }

      final result =
          await UserService().deleteAccount(accessToken: accessToken);

      if (!context.mounted) return;

      if (result['success'] == true) {
        await _signOut(authProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? l.settingsDeleteAccountFailed),
            backgroundColor: SureColors.of(context).palette.destructive,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _activeDestructiveAction = null);
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
        title: Text(l.settingsSignOutTitle),
        content: Text(l.settingsSignOutContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.settingsSignOut),
          ),
        ],
      );},
    );

    if (confirmed == true && context.mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await _signOut(authProvider);
    }
  }

  /// Settings is pushed over the shell, so leave it before signing out;
  /// otherwise it would stay on top of the login screen.
  Future<void> _signOut(AuthProvider authProvider) async {
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    await authProvider.logout();
  }

  Future<void> _showCustomHeadersDialog() async {
    final l = AppLocalizations.of(context);
    final formKey = GlobalKey<FormState>();
    final latestHeaders =
        await CustomProxyHeadersService.instance.loadHeaders();
    if (!mounted) return;

    setState(() => _customHeaders = latestHeaders);
    var draftHeaders = List<CustomProxyHeader>.from(latestHeaders);

    final saved = await showSureSheet<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return SureSheet(
          title: l.settingsProxyHeadersTileTitle,
          onAction: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(context, true);
          },
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CustomProxyHeadersEditor(
                      initialHeaders: draftHeaders,
                      onChanged: (headers) => draftHeaders = headers,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.settingsProxyHeadersNote,
                      style:
                          TextStyle(fontSize: 13, color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (saved != true) return;

    try {
      await CustomProxyHeadersService.instance.saveHeaders(draftHeaders);
      ApiConfig.setCustomProxyHeaders(draftHeaders);
      if (!mounted) return;
      setState(() => _customHeaders = draftHeaders);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsProxyHeadersSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      LogService.instance.warning(
        'Settings',
        'Failed to save custom proxy headers with ${e.runtimeType}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.settingsProxyHeadersSaveFailed),
          backgroundColor: SureColors.of(context).palette.destructive,
        ),
      );
    }
  }

  /// Opens the server screen. A saved change of server signs out, since the
  /// session belongs to the old server.
  Future<void> _openServerConfig() async {
    final previousUrl = ApiConfig.baseUrl;
    var saved = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => BackendConfigScreen(
          onConfigSaved: () {
            saved = true;
            Navigator.of(routeContext).pop();
          },
        ),
      ),
    );
    if (!mounted) return;
    // The server screen also saves proxy headers.
    await _loadCustomHeaders();
    if (!mounted) return;
    setState(() {});
    if (saved && ApiConfig.baseUrl != previousUrl) {
      await _signOut(context.read<AuthProvider>());
    }
  }

  /// The "Account actions" sheet: clear local data, reset and delete. Each
  /// action then runs its own confirm dialog.
  Future<void> _showAccountActions() async {
    final action = await showSureSheet<String>(
      context: context,
      builder: (sheetContext) {
        final l = AppLocalizations.of(sheetContext);
        final palette = SureColors.of(sheetContext).palette;
        return SureSheet(
          title: l.ds2sAccountActions,
          showCancel: false,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SurePanel.rows(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  children: [
                    SureListRow(
                      key: const ValueKey('accountActionClear'),
                      title: l.ds2sClearLocalData,
                      subtitle: l.settingsClearDataTileSubtitle,
                      onTap: () => Navigator.pop(sheetContext, _clearAction),
                    ),
                    SureListRow(
                      key: const ValueKey('accountActionReset'),
                      title: l.ds2sResetAccount,
                      subtitle: l.settingsResetAccountTileSubtitle,
                      destructive: true,
                      onTap: () => Navigator.pop(sheetContext, _resetAction),
                    ),
                    SureListRow(
                      key: const ValueKey('accountActionDelete'),
                      title: l.ds2sDeleteAccount,
                      subtitle: l.settingsDeleteAccountTileSubtitle,
                      destructive: true,
                      onTap: () => Navigator.pop(sheetContext, _deleteAction),
                    ),
                  ],
                ),
                _CenteredButtonPanel(
                  key: const ValueKey('accountActionCancel'),
                  label: l.dsCancel,
                  color: palette.link,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _clearAction:
        await _handleClearLocalData(context);
      case _resetAction:
        await _handleResetAccount(context);
      case _deleteAction:
        await _handleDeleteAccount(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final authProvider = Provider.of<AuthProvider>(context);
    final l = AppLocalizations.of(context);
    final user = authProvider.user;
    final host = serverHost(ApiConfig.baseUrl);
    final busy = _activeDestructiveAction != null;
    final nativeProfile = _hasNativeProfile(context);
    void openProfile() => Navigator.push(context,
        MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

    return SureLargeTitleScaffold(
      title: l.shellSettingsTitle,
      // Settings only opens from Home's gear, so the back link names Home.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.navHome)
          : null,
      slivers: [
        SliverList.list(
          children: [
            _ProfileRow(
              initials: profileInitials(user),
              name: user?.displayName ?? l.settingsUserFallback,
              host: host,
              onTap: nativeProfile
                  ? openProfile
                  : () => openWebFallback(
                        context,
                        title: l.shellProfile,
                        path: '/settings/profile',
                      ),
            ),
            const SettingsLinkGroups(),
            SureSectionHeader(label: l.settingsSectionDisplay),
            SurePanel.rows(
              margin: settingsPanelMargin,
              children: [
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) => SureListRow(
                    title: l.settingsThemeLabel,
                    trailing: SizedBox(
                      width: 176,
                      child: SureSegmentedControl<ThemeMode>(
                        key: const ValueKey('settingsThemeControl'),
                        segments: [
                          SureSegment(
                              value: ThemeMode.light,
                              label: l.settingsThemeLight),
                          SureSegment(
                              value: ThemeMode.system,
                              label: l.ds2sThemeAuto),
                          SureSegment(
                              value: ThemeMode.dark,
                              label: l.settingsThemeDark),
                        ],
                        selected: themeProvider.themeMode,
                        onChanged: themeProvider.setThemeMode,
                      ),
                    ),
                  ),
                ),
                SureListRow(
                  title: l.settingsPrivacyHideAmountsLabel,
                  trailing: _SettingsSwitch(
                    key: const ValueKey('settingsHideAmountsSwitch'),
                    value: context.watch<PrivacyProvider>().hidden,
                    onChanged: (value) =>
                        context.read<PrivacyProvider>().setHidden(value),
                  ),
                ),
                SettingsWebRow(
                  title: l.shellPreferences,
                  path: '/settings/preferences',
                  onTap: nativeProfile ? openProfile : null,
                ),
              ],
            ),
            SureSectionHeader(label: l.settingsSectionSecurity),
            SurePanel.rows(
              margin: settingsPanelMargin,
              children: [
                if (_biometricSupported)
                  SureListRow(
                    title: biometricLockLabel(
                        l, _biometricTypes, defaultTargetPlatform),
                    trailing: _SettingsSwitch(
                      key: const ValueKey('settingsBiometricSwitch'),
                      value: _biometricEnabled,
                      onChanged:
                          _isTogglingBiometric ? null : _toggleBiometric,
                    ),
                  ),
                SettingsWebRow(
                  title: l.ds2sPasswordPasskeys,
                  path: '/settings/security',
                ),
              ],
            ),
            SureSectionHeader(label: l.shellSectionApp),
            SurePanel.rows(
              margin: settingsPanelMargin,
              children: [
                SureListRow(
                  key: const ValueKey('settingsServerRow'),
                  title: l.shellServer,
                  value: host,
                  showChevron: true,
                  onTap: _openServerConfig,
                ),
                SureListRow(
                  key: const ValueKey('settingsProxyHeadersRow'),
                  title: l.settingsProxyHeadersTileTitle,
                  value: _customHeaders.isEmpty
                      ? null
                      : l.settingsProxyHeadersTileSubtitleCount(
                          _customHeaders.length),
                  showChevron: true,
                  onTap: _showCustomHeadersDialog,
                ),
                SureListRow(
                  title: l.ds2sVersion,
                  trailing: Text(
                    _appVersion ?? '…',
                    style: TextStyle(
                      fontFamily: SureTokens.fontMono,
                      fontFamilyFallback: const <String>['Menlo', 'monospace'],
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 15,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                SureListRow(
                  key: const ValueKey('settingsCheckUpdatesRow'),
                  title: l.ds2sCheckForUpdates,
                  trailing: _isCheckingForUpdate
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _isCheckingForUpdate ? null : _checkForUpdate,
                ),
                SureListRow(
                  title: l.settingsContactUs,
                  trailing: const SettingsWebMark(),
                  onTap: () => _launchContactUrl(context),
                ),
                SureListRow(
                  title: l.ds2sDebugLogs,
                  showChevron: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LogViewerScreen()),
                  ),
                ),
              ],
            ),
            _CenteredButtonPanel(
              key: const ValueKey('settingsSignOut'),
              label: l.ds2sSignOut,
              color: palette.destructive,
              margin: const EdgeInsets.fromLTRB(16, 28, 16, 0),
              onTap: () => _handleLogout(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Semantics(
                button: true,
                enabled: !busy,
                child: GestureDetector(
                  key: const ValueKey('settingsAccountActionsLink'),
                  behavior: HitTestBehavior.opaque,
                  onTap: busy ? null : _showAccountActions,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (busy) ...[
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            l.ds2sAccountActionsLink,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.textSubdued,
                            ),
                          ),
                        ),
                        if (!busy) ...[
                          const SizedBox(width: 2),
                          SureIcon(SureIcons.chevronRight,
                              size: 14, color: palette.textSubdued),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The profile panel: a 30 px inverse circle with initials, the name, and
/// "host · Profile on web ↗". Tapping opens the web profile page.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.initials,
    required this.name,
    required this.host,
    required this.onTap,
  });

  final String initials;
  final String name;
  final String host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final l = AppLocalizations.of(context);
    return SurePanel(
      key: const ValueKey('settingsProfileRow'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      onTap: onTap,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.bgInverse,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initials,
                    maxLines: 1,
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.2),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textInverse,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$host · ${l.ds2sProfileOnWeb}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const SettingsWebMark(size: 12),
                        ],
                      ),
                    ],
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

/// A panel holding one centered label (Sign out, Cancel).
class _CenteredButtonPanel extends StatelessWidget {
  const _CenteredButtonPanel({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.margin,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return SurePanel(
      margin: margin,
      onTap: onTap,
      child: Semantics(
        button: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The platform switch (Cupertino on iOS), tinted with `success` when on.
class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: SureColors.of(context).palette.success,
    );
  }
}
