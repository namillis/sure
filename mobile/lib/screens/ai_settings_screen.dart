import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/ai_settings.dart';
import '../providers/auth_provider.dart';
import '../services/ai_settings_service.dart';
import '../services/api_config.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import 'classifier_settings_screen.dart';

/// Whether Settings shows the "AI" row (Sure+ `settings.ai`, admins only),
/// remembered per server and user for this app session: the role once
/// known, and a 403 from the AI endpoints, which hides the row until the
/// app restarts.
abstract final class AiSettingsAccess {
  static final Map<String, bool> _admin = {};
  static final Set<String> _forbidden = {};

  static String _key(String? userId) => '${ApiConfig.baseUrl}|$userId';

  /// True, false, or null while the role isn't known yet.
  static bool? isAdmin(String? userId) => _admin[_key(userId)];

  static void setAdmin(String? userId, bool admin) =>
      _admin[_key(userId)] = admin;

  static bool hidden(String? userId) => _forbidden.contains(_key(userId));

  static void hide(String? userId) => _forbidden.add(_key(userId));

  @visibleForTesting
  static void reset() {
    _admin.clear();
    _forbidden.clear();
  }
}

/// The plain name of a prompt key; unknown keys read as their key.
String aiPromptName(AppLocalizations l, String key) => switch (key) {
      'chat_system' => l.s4sAiPromptChatSystem,
      'categorizer_openai' => l.s4sAiPromptCategorizerOpenai,
      'categorizer_anthropic' => l.s4sAiPromptCategorizerAnthropic,
      'merchant_openai' => l.s4sAiPromptMerchantOpenai,
      'merchant_anthropic' => l.s4sAiPromptMerchantAnthropic,
      'insight_dig_in' => l.s4sAiPromptInsightDigIn,
      _ => key,
    };

/// The total cost to show: the server's formatted string, or the unrounded
/// amount when that rounds a real cost down to $0.00.
@visibleForTesting
String aiCostLabel(AiUsage usage) {
  final amount = double.tryParse(usage.totalCostAmount ?? '');
  if (amount != null && amount > 0 && amount < 0.005) {
    return '\$${amount.toStringAsFixed(4)}';
  }
  return usage.totalCost;
}

/// Settings → AI: the classifier switch and jobs, the prompt overrides, the
/// classifier's settings and the last 30 days' usage.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.onForbidden,
  });

  final AiSettingsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Called on a 403, so Settings can hide the row for the session.
  final VoidCallback? onForbidden;

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  static const _bayes = 'bayes_categorize';

  late final AiSettingsService _service;
  AiSettings? _settings;
  AiUsage? _usage;
  bool _loading = true;
  String? _loadError;
  bool _ruleMissing = false;
  bool _togglingRule = false;
  bool _addingRule = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AiSettingsService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<String?> _token() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _unauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }

  /// Runs [call] with a token. Returns the result, or null after a sign-out.
  Future<Map<String, dynamic>?> _run(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final token = await _token();
    if (token == null) {
      await _unauthorized();
      return null;
    }
    final result = await call(token);
    if (result['error'] == 'unauthorized') {
      await _unauthorized();
      return null;
    }
    if (result['status'] == 403 && result['code'] != 'insufficient_scope') {
      widget.onForbidden?.call();
    }
    return result;
  }

  String _message(Map<String, dynamic> result) {
    final l = AppLocalizations.of(context);
    final status = result['status'];
    return status == 403 || status == 422
        ? result['error']?.toString() ?? l.s4sActionFailed
        : l.s4sActionFailed;
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final result = await _run((token) => _service.get(accessToken: token));
    if (result == null || !mounted) return;
    final ok = result['success'] == true;
    if (!ok && _settings != null) _snack(_message(result));
    setState(() {
      _loading = false;
      if (ok) {
        _settings = result['settings'] as AiSettings;
        _loadError = null;
      } else {
        _loadError = result['status'] == 403
            ? result['error']?.toString()
            : null;
      }
    });
    if (ok) await _loadUsage();
  }

  Future<void> _loadUsage() async {
    final result = await _run((token) => _service.usage(accessToken: token));
    if (result == null || !mounted) return;
    if (result['success'] == true) {
      setState(() => _usage = result['usage'] as AiUsage);
    }
  }

  /// PATCHes [body]. Returns the saved settings, or the message saying why
  /// it failed (`classifier_rule_missing` also raises the banner).
  Future<({AiSettings? settings, String? error})> _patch(
      Map<String, dynamic> body) async {
    final result = await _run(
        (token) => _service.update(accessToken: token, aiSettings: body));
    if (!mounted) return (settings: null, error: null);
    if (result == null) {
      return (settings: null, error: AppLocalizations.of(context).s4sActionFailed);
    }
    if (result['success'] == true) {
      final saved = result['settings'] as AiSettings;
      setState(() {
        _settings = saved;
        _ruleMissing = false;
      });
      return (settings: saved, error: null);
    }
    if (result['code'] == 'classifier_rule_missing') {
      setState(() => _ruleMissing = true);
      return (settings: null, error: AppLocalizations.of(context).s4sAiRuleMissing);
    }
    return (settings: null, error: _message(result));
  }

  /// [_patch], showing a failure in a snackbar (the banner covers a missing
  /// classifier rule).
  Future<AiSettings?> _save(Map<String, dynamic> body) async {
    final saved = await _patch(body);
    final error = saved.error;
    if (error != null && mounted &&
        error != AppLocalizations.of(context).s4sAiRuleMissing) {
      _snack(error);
    }
    return saved.settings;
  }

  Future<void> _toggleRule(bool active) async {
    setState(() => _togglingRule = true);
    await _save({
      'classifier': {
        'rules_active': {_bayes: active},
      },
    });
    if (mounted) setState(() => _togglingRule = false);
  }

  Future<void> _addRule() async {
    setState(() => _addingRule = true);
    final result = await _run(
        (token) => _service.addClassifierRule(accessToken: token));
    if (!mounted) return;
    setState(() => _addingRule = false);
    if (result == null) return;
    // 409 means the rule is already back; either way reload the switch.
    if (result['success'] == true || result['status'] == 409) {
      setState(() {
        _ruleMissing = false;
        if (result['settings'] is AiSettings) {
          _settings = result['settings'] as AiSettings;
        }
      });
      _snack(AppLocalizations.of(context).s4sAiRuleAdded);
      if (result['settings'] is! AiSettings) await _load();
      return;
    }
    _snack(_message(result));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _queue({
    required String title,
    required String body,
    required String action,
    required Future<Map<String, dynamic>> Function(String token) call,
  }) async {
    if (!await _confirm(title: title, body: body, action: action)) return;
    if (!mounted) return;
    final result = await _run(call);
    if (result == null || !mounted) return;
    if (result['success'] == true) {
      SureHaptics.success();
      _snack(AppLocalizations.of(context).s4sAiQueued);
    } else {
      _snack(_message(result));
    }
  }

  Future<void> _editPrompt(AiPrompt prompt, int maxLength) async {
    final l = AppLocalizations.of(context);
    final saved = await showSureSheet<bool>(
      context: context,
      builder: (sheetContext) => AiPromptSheet(
        prompt: prompt,
        maxLength: maxLength,
        onSave: (text) async {
          final saved = await _patch({
            'prompts': {prompt.key: text},
          });
          if (saved.settings != null && sheetContext.mounted) {
            Navigator.of(sheetContext).pop(true);
          }
          return saved.error;
        },
      ),
    );
    if (saved == true && mounted) _snack(l.s4sAiPromptSaved);
  }

  void _openClassifierSettings(AiSettings settings) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ClassifierSettingsScreen(
        initial: settings.classifier,
        onSave: (values) async =>
            (await _save({
              'classifier': {'settings': values},
            }))
                ?.classifier,
      ),
    ));
  }

  void _openUsageByModel(AiUsage usage) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AiUsageByModelScreen(usage: usage),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final settings = _settings;

    final List<Widget> children;
    if (settings == null && _loading) {
      children = const [ManageLoading()];
    } else if (settings == null) {
      children = [
        SureEmptyState(
          icon: SureIcons.circleAlert,
          title: _loadError ?? l.s4sAiLoadFailed,
          primaryLabel: _loadError == null ? l.commonTryAgain : null,
          onPrimary: _loadError == null ? _load : null,
        ),
      ];
    } else {
      final rule = settings.classifier.rule(_bayes);
      final usage = _usage;
      final mono = SureMoney.tabular(TextStyle(
        fontFamily: SureTokens.fontMono,
        fontFamilyFallback: const <String>['Menlo', 'monospace'],
        fontSize: 15,
        color: palette.textSecondary,
      ));
      final locale = Localizations.localeOf(context).toString();
      children = [
        if (_ruleMissing)
          _RuleMissingBanner(
            key: const ValueKey('aiRuleMissingBanner'),
            onAdd: _addingRule ? null : _addRule,
          ),
        SureSectionHeader(label: l.s4sAiClassifierSection),
        SurePanel.rows(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            SureListRow(
              title: l.s4sAiClassifierSwitch,
              subtitle: l.s4sAiClassifierSwitchSub,
              trailing: Switch.adaptive(
                key: const ValueKey('aiClassifierSwitch'),
                value: rule?.active ?? false,
                activeTrackColor: palette.success,
                onChanged: _togglingRule ? null : _toggleRule,
              ),
            ),
            SureListRow(
              key: const ValueKey('aiRunNow'),
              title: l.s4sAiRunNow,
              titleColor: palette.link,
              onTap: () => _queue(
                title: l.s4sAiRunNowTitle,
                body: l.s4sAiRunNowBody,
                action: l.s4sAiRun,
                call: (token) => _service.runClassifier(accessToken: token),
              ),
            ),
            SureListRow(
              key: const ValueKey('aiClearLocks'),
              title: l.s4sAiClearLocks,
              titleColor: palette.link,
              onTap: () => _queue(
                title: l.s4sAiClearLocksTitle,
                body: l.s4sAiClearLocksBody,
                action: l.s4sAiClearLocksConfirm,
                call: (token) => _service.clearLocks(accessToken: token),
              ),
            ),
            SureListRow(
              key: const ValueKey('aiClassifierSettings'),
              title: l.s4sAiClassifierSettings,
              showChevron: true,
              onTap: () => _openClassifierSettings(settings),
            ),
          ],
        ),
        if (settings.prompts.isNotEmpty) ...[
          SureSectionHeader(label: l.s4sAiPromptsSection),
          SurePanel.rows(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final prompt in settings.prompts)
                SureListRow(
                  key: ValueKey('aiPrompt-${prompt.key}'),
                  title: aiPromptName(l, prompt.key),
                  value: prompt.custom
                      ? l.s4sAiPromptCustom
                      : l.s4sAiPromptDefault,
                  leading: prompt.formatRisk
                      ? SureIcon(SureIcons.triangleAlert,
                          size: 18, color: palette.warning)
                      : null,
                  showChevron: true,
                  onTap: () => _editPrompt(prompt, settings.promptMaxLength),
                ),
            ],
          ),
        ],
        if (usage != null) ...[
          SureSectionHeader(label: l.s4sAiUsageSection),
          SurePanel.rows(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              SureListRow(
                title: l.s4sAiUsageCost,
                trailing: Text(aiCostLabel(usage),
                    key: const ValueKey('aiUsageCost'), style: mono),
              ),
              SureListRow(
                title: l.s4sAiUsageRequests,
                trailing: Text(
                    NumberFormat.decimalPattern(locale)
                        .format(usage.totalRequests),
                    style: mono),
              ),
              SureListRow(
                key: const ValueKey('aiUsageByModel'),
                title: l.s4sAiUsageByModel,
                showChevron: true,
                onTap: () => _openUsageByModel(usage),
              ),
            ],
          ),
        ],
        const SizedBox(height: SureSpacing.lg),
      ];
    }

    return SureLargeTitleScaffold(
      title: l.s4sAiTitle,
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      onRefresh: _load,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// The `classifier_rule_missing` banner. [SureBanner] is one line with an
/// inline action, which a long action label overflows, so this one puts the
/// message on its own lines and the action under it.
class _RuleMissingBanner extends StatelessWidget {
  const _RuleMissingBanner({super.key, required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SureIcon(SureIcons.triangleAlert,
                  size: 16, color: palette.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.s4sAiRuleMissing,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: SureTokens.weightMedium,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                foregroundColor: palette.link,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(l.s4sAiRuleAddAgain,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Edits one prompt: a multi-line field with a character count against
/// [maxLength], the format warning, and "Reset to default" (sends blank).
/// [onSave] returns an error message, or null when the server saved it (and
/// the caller closed the sheet).
class AiPromptSheet extends StatefulWidget {
  const AiPromptSheet({
    super.key,
    required this.prompt,
    required this.maxLength,
    required this.onSave,
  });

  final AiPrompt prompt;
  final int maxLength;
  final Future<String?> Function(String text) onSave;

  @override
  State<AiPromptSheet> createState() => _AiPromptSheetState();
}

class _AiPromptSheetState extends State<AiPromptSheet> {
  late final TextEditingController _text;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.prompt.effective)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _tooLong => _text.text.length > widget.maxLength;

  Future<void> _submit(String text) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSave(text);
    if (error != null && mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  Future<void> _save() async {
    final text = _text.text;
    // Unchanged default text stays the default instead of becoming an
    // override that matches it.
    if (!widget.prompt.custom && text == widget.prompt.defaultText) {
      Navigator.of(context).pop();
      return;
    }
    await _submit(text.trim().isEmpty ? '' : text);
  }

  Future<void> _reset() async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.s4sAiPromptResetTitle),
        content: Text(l.s4sAiPromptResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: palette.destructive),
            child: Text(l.s4sAiPromptReset2),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _submit('');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final number =
        NumberFormat.decimalPattern(Localizations.localeOf(context).toString());
    final prompt = widget.prompt;
    final riskKey = prompt.formatRiskKey;
    return SureSheet(
      title: aiPromptName(l, prompt.key),
      actionLabel: l.commonSave,
      actionKey: const ValueKey('aiPromptSave'),
      actionEnabled: !_tooLong,
      busy: _busy,
      onAction: _save,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prompt.formatRisk)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SureIcon(SureIcons.triangleAlert,
                        size: 16, color: palette.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.s4sAiPromptFormatRisk(riskKey ?? prompt.key),
                        key: const ValueKey('aiPromptFormatRisk'),
                        style: TextStyle(fontSize: 13, color: palette.warning),
                      ),
                    ),
                  ],
                ),
              ),
            SurePanel(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: TextField(
                  key: const ValueKey('aiPromptField'),
                  controller: _text,
                  enabled: !_busy,
                  minLines: 8,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(fontSize: 14, color: palette.textPrimary),
                  decoration: const InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _tooLong
                        ? Text(l.s4sAiPromptTooLong,
                            style: TextStyle(
                                fontSize: 13, color: palette.destructive))
                        : const SizedBox.shrink(),
                  ),
                  Text(
                    l.s4sAiPromptCount(number.format(_text.text.length),
                        number.format(widget.maxLength)),
                    key: const ValueKey('aiPromptCount'),
                    style: SureMoney.tabular(TextStyle(
                      fontSize: 12,
                      color:
                          _tooLong ? palette.destructive : palette.textSecondary,
                    )),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: SureSpacing.lg),
              ManageErrorText(_error!),
            ],
            if (prompt.custom)
              SureButtonPanel(
                key: const ValueKey('aiPromptReset'),
                label: l.s4sAiPromptReset,
                destructive: true,
                busy: _busy,
                margin: const EdgeInsets.only(top: SureSpacing.xxxl),
                onPressed: _reset,
              ),
          ],
        ),
      ),
    );
  }
}

/// The last 30 days' usage per model.
class AiUsageByModelScreen extends StatelessWidget {
  const AiUsageByModelScreen({super.key, required this.usage});

  final AiUsage usage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final mono = SureMoney.tabular(TextStyle(
      fontFamily: SureTokens.fontMono,
      fontFamilyFallback: const <String>['Menlo', 'monospace'],
      fontSize: 15,
      color: palette.textPrimary,
    ));
    return SureLargeTitleScaffold(
      title: l.s4sAiUsageByModel,
      leading: SureBackButton(label: l.s4sAiTitle),
      slivers: [
        SliverToBoxAdapter(
          child: usage.byModel.isEmpty
              ? SureEmptyState(
                  icon: SureIcons.sparkles, title: l.s4sAiUsageNone)
              : SurePanel.rows(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  children: [
                    for (final row in usage.byModel)
                      SureListRow(
                        title: row.model,
                        subtitle: l.s4sAiUsageModelRequests(row.totalRequests),
                        trailing: Text(row.cost, style: mono),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
