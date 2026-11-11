import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/custom_proxy_header.dart';
import '../services/api_config.dart';
import '../services/custom_proxy_headers_service.dart';
import '../services/log_service.dart';
import '../services/offline_cache_store.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/custom_proxy_headers_editor.dart';
import '../widgets/ds/ds.dart';
import '../widgets/sure_button.dart';
import '../l10n/app_localizations.dart';

class BackendConfigScreen extends StatefulWidget {
  final VoidCallback? onConfigSaved;

  const BackendConfigScreen({super.key, this.onConfigSaved});

  @override
  State<BackendConfigScreen> createState() => _BackendConfigScreenState();
}

class _BackendConfigScreenState extends State<BackendConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  bool _isLoading = false;
  bool _isTesting = false;
  bool _hasLoadedConfig = false;
  String? _errorMessage;
  String? _successMessage;
  List<CustomProxyHeader> _customHeaders = [];

  @override
  void initState() {
    super.initState();
    _loadSavedUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedUrl() async {
    String urlToShow = ApiConfig.baseUrl;
    List<CustomProxyHeader> headers = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('backend_url');
      headers = await CustomProxyHeadersService.instance.loadHeaders();
      if (savedUrl != null && savedUrl.isNotEmpty) {
        urlToShow = savedUrl;
      }
    } catch (e) {
      // Swallow storage failures so the screen still becomes interactive with
      // sensible defaults; the user can re-enter and re-save.
      LogService.instance.warning(
        'BackendConfigScreen',
        'Failed to load saved backend config with ${e.runtimeType}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _urlController.text = urlToShow;
          _customHeaders = headers;
          _hasLoadedConfig = true;
        });
      }
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    final l = AppLocalizations.of(context);

    setState(() {
      _isTesting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final previousHeaders = ApiConfig.customProxyHeaders;
    try {
      // Normalize base URL by removing trailing slashes
      final normalizedUrl = _urlController.text.trim().replaceAll(
            RegExp(r'/+$'),
            '',
          );

      // Apply the unsaved edits only for the duration of this probe so the
      // test reflects what the user is about to save. Restored in `finally`.
      ApiConfig.setCustomProxyHeaders(_customHeaders);

      // Check /sessions/new page to verify it's a Sure backend
      final sessionsUrl = Uri.parse('$normalizedUrl/sessions/new');
      final sessionsResponse =
          await http.get(sessionsUrl, headers: ApiConfig.htmlHeaders()).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(l.backendConfigTimeout);
        },
      );

      if (sessionsResponse.statusCode >= 200 &&
          sessionsResponse.statusCode < 400) {
        if (mounted) {
          setState(() {
            _successMessage = l.backendConfigSuccess;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage =
                l.backendConfigServerError(sessionsResponse.statusCode);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = l.backendConfigConnectionFailed(e.toString());
        });
      }
    } finally {
      ApiConfig.setCustomProxyHeaders(previousHeaders);
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _saveAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

    final l = AppLocalizations.of(context);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Normalize base URL by removing trailing slashes
      final normalizedUrl = _urlController.text.trim().replaceAll(
            RegExp(r'/+$'),
            '',
          );

      // Save URL to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backend_url', normalizedUrl);

      // Save custom proxy headers
      await CustomProxyHeadersService.instance.saveHeaders(_customHeaders);
      ApiConfig.setCustomProxyHeaders(_customHeaders);

      // Update ApiConfig. Cached data belongs to the old server, so drop it.
      if (normalizedUrl != ApiConfig.baseUrl) {
        await OfflineCacheStore.instance.clearAll();
      }
      ApiConfig.setBaseUrl(normalizedUrl);

      // Notify parent that config is saved
      if (mounted && widget.onConfigSaved != null) {
        widget.onConfigSaved!();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = l.backendConfigSaveFailed(e.toString());
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validateUrl(String? value, AppLocalizations l) {
    if (value == null || value.isEmpty) {
      return l.backendConfigUrlRequired;
    }

    final trimmedValue = value.trim();

    // Check if it starts with http:// or https://
    if (!trimmedValue.startsWith('http://') &&
        !trimmedValue.startsWith('https://')) {
      return l.backendConfigUrlScheme;
    }

    // Basic URL validation
    try {
      final uri = Uri.parse(trimmedValue);
      if (!uri.hasScheme || uri.host.isEmpty) {
        return l.backendConfigUrlInvalid;
      }
    } catch (e) {
      return l.backendConfigUrlInvalid;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canPop)
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: SureBackButton(),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: canPop ? 8 : 48),
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.surfaceInset,
                            shape: BoxShape.circle,
                          ),
                          child: SureIcon(
                            SureIcons.settings,
                            size: 30,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l.backendConfigTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.backendConfigSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Example URLs
                      SurePanel(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                SureIcon(SureIcons.info,
                                    size: 18, color: palette.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l.backendConfigExampleUrlsLabel,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'https://demo.sure.am\n'
                              'https://your-domain.com\n'
                              'http://localhost:3000',
                              style: TextStyle(
                                fontFamily: SureTokens.fontMono,
                                fontFamilyFallback: const <String>[
                                  'Menlo',
                                  'monospace'
                                ],
                                fontSize: 13,
                                height: 1.5,
                                color: palette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      if (_errorMessage != null)
                        _StatusMessage(
                          key: const ValueKey('backendConfigError'),
                          message: _errorMessage!,
                          icon: SureIcons.circleAlert,
                          color: palette.destructive,
                          onDismiss: () => setState(() => _errorMessage = null),
                        ),

                      if (_successMessage != null)
                        _StatusMessage(
                          key: const ValueKey('backendConfigSuccess'),
                          message: _successMessage!,
                          icon: SureIcons.circleCheck,
                          color: palette.success,
                          onDismiss: () =>
                              setState(() => _successMessage = null),
                        ),

                      // URL Field
                      TextFormField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l.backendConfigUrlLabel,
                          prefixIcon: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SureIcon('globe',
                                size: 20, color: palette.textSecondary),
                          ),
                          hintText: l.backendConfigUrlHint,
                        ),
                        validator: (value) => _validateUrl(value, l),
                        onFieldSubmitted: (_) => _saveAndContinue(),
                      ),
                      const SizedBox(height: 16),
                      SurePanel(
                        child: Material(
                          // ExpansionTile's ListTile paints ink on the
                          // nearest Material; keep it inside the panel.
                          type: MaterialType.transparency,
                          child: Theme(
                            // No ExpansionTile dividers inside the panel.
                            data: Theme.of(context)
                                .copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(14, 0, 14, 14),
                              iconColor: palette.textSubdued,
                              collapsedIconColor: palette.textSubdued,
                              title: Text(
                                l.backendConfigProxyHeadersLabel,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: SureTokens.weightMedium,
                                  color: palette.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                _customHeaders.isEmpty
                                    ? l.backendConfigProxyHeadersSubtitle
                                    : l.backendConfigProxyHeadersCount(
                                        _customHeaders.length),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: palette.textSecondary,
                                ),
                              ),
                              children: [
                                const SizedBox(height: 8),
                                if (_hasLoadedConfig)
                                  CustomProxyHeadersEditor(
                                    initialHeaders: _customHeaders,
                                    onChanged: (headers) {
                                      setState(() => _customHeaders = headers);
                                    },
                                  )
                                else
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  l.backendConfigHeadersHelp,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      SureButton(
                        label: _isTesting
                            ? l.backendConfigTesting
                            : l.backendConfigTestButton,
                        variant: SureButtonVariant.outline,
                        size: SureButtonSize.lg,
                        fullWidth: true,
                        loading: _isTesting,
                        leading: SureIcon('plug',
                            size: 18, color: palette.textPrimary),
                        onPressed:
                            _isTesting || _isLoading ? null : _testConnection,
                      ),
                      const SizedBox(height: 12),
                      SureButton(
                        label: l.backendConfigContinueButton,
                        size: SureButtonSize.lg,
                        fullWidth: true,
                        loading: _isLoading,
                        onPressed:
                            _isLoading || _isTesting ? null : _saveAndContinue,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l.backendConfigChangeHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textSubdued,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dismissible result line under the examples: a ~12% fill of [color]
/// with an icon, the message and a close button.
class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    super.key,
    required this.message,
    required this.icon,
    required this.color,
    required this.onDismiss,
  });

  final String message;
  final String icon;
  final Color color;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      child: Row(
        children: [
          SureIcon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                message,
                style: TextStyle(fontSize: 14, color: palette.textPrimary),
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: SureIcon(SureIcons.x, size: 18, color: palette.textSecondary),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
