import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/api_key.dart';
import '../providers/auth_provider.dart';
import '../services/api_keys_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import 'form_sheet_fields.dart';

/// Settings → API keys (Sure+ `settings.api_keys`): the signed-in user's
/// keys. Swiping a key revokes it, except the key this app uses; "+" creates
/// one and shows its full value once, in a banner that lives only as long as
/// this screen.
class ApiKeysScreen extends StatefulWidget {
  const ApiKeysScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.now,
  });

  final ApiKeysService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Clock for "Used 5m ago"; defaults to [DateTime.now].
  final DateTime Function()? now;

  /// "Used 5m ago" for [at] seen from [now]; null means never used.
  static String usedLabel(BuildContext context, DateTime? at,
      {required DateTime now}) {
    final l = AppLocalizations.of(context);
    if (at == null) return l.s4sApiKeyNeverUsed;
    final age = now.difference(at);
    if (age.inMinutes < 1) return l.s4sApiKeyUsedJustNow;
    if (age.inHours < 1) return l.s4sApiKeyUsedMinutesAgo(age.inMinutes);
    if (age.inDays < 1) return l.s4sApiKeyUsedHoursAgo(age.inHours);
    if (age.inDays < 7) return l.s4sApiKeyUsedDaysAgo(age.inDays);
    return l.s4sApiKeyUsedOn(SureDates.shortOf(context, at, now: now));
  }

  /// The message for a failed key write: 429, a read-only sign-in, else the
  /// server's message for 403/422.
  static String errorMessage(AppLocalizations l, Map<String, dynamic> result) {
    if (result['status'] == 429) return l.s4sApiKeyTooMany;
    if (result['code'] == 'insufficient_scope') return l.s4sApiKeyNeedsWrite;
    final status = result['status'];
    if (status == 403 || status == 422) {
      return result['error']?.toString() ?? l.s4sActionFailed;
    }
    return l.s4sActionFailed;
  }

  @override
  State<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

/// A just-created key. Held only in this screen's state.
typedef _CreatedKey = ({String name, String plainKey});

class _ApiKeysScreenState extends State<ApiKeysScreen> {
  late final ApiKeysService _service;
  List<ApiKey>? _keys;
  bool _loading = true;
  _CreatedKey? _created;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ApiKeysService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _created = null;
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

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.list(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    final ok = result['success'] == true;
    if (!ok && _keys != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).s4sApiKeysLoadFailed)));
    }
    setState(() {
      _loading = false;
      if (ok) _keys = result['keys'] as List<ApiKey>;
    });
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
    return result;
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final created = await showSureSheet<_CreatedKey>(
      context: context,
      builder: (sheetContext) => _ApiKeyForm(
        onSubmit: (name, scope) async {
          final result = await _run((token) =>
              _service.create(accessToken: token, name: name, scope: scope));
          if (result == null) return l.s4sActionFailed;
          if (result['success'] != true) {
            return ApiKeysScreen.errorMessage(l, result);
          }
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop<_CreatedKey>((
              name: (result['key'] as ApiKey).name,
              plainKey: result['plainKey'] as String,
            ));
          }
          return null;
        },
      ),
    );
    if (created == null || !mounted) return;
    SureHaptics.success();
    setState(() => _created = created);
    await _load();
  }

  Future<void> _revoke(ApiKey key) async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.s4sApiKeyRevokeTitle(key.name)),
        content: Text(l.s4sApiKeyRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: palette.destructive),
            child: Text(l.s4sApiKeyRevoke),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result =
        await _run((token) => _service.revoke(accessToken: token, id: key.id));
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (result['success'] != true) {
      messenger.showSnackBar(SnackBar(
          content: Text(ApiKeysScreen.errorMessage(l, result)),
          duration: const Duration(seconds: 6)));
      return;
    }
    SureHaptics.success();
    setState(() => _keys = [
          for (final k in _keys ?? const <ApiKey>[])
            if (k.id != key.id) k,
        ]);
    messenger.showSnackBar(SnackBar(content: Text(l.s4sApiKeyRevoked)));
  }

  Future<void> _copy(String plainKey) async {
    await Clipboard.setData(ClipboardData(text: plainKey));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).s4sApiKeyCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final keys = _keys;
    final now = (widget.now ?? DateTime.now)();
    final created = _created;

    final Widget content;
    if (keys == null && _loading) {
      content = const ManageLoading();
    } else if (keys == null) {
      content = SureEmptyState(
        icon: SureIcons.circleAlert,
        title: l.s4sApiKeysLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _load,
      );
    } else if (keys.isEmpty) {
      content = SureEmptyState(
        icon: 'key',
        title: l.s4sApiKeysEmpty,
        body: l.s4sApiKeysEmptyBody,
        primaryLabel: l.s4sApiKeyNew,
        onPrimary: _create,
      );
    } else {
      content = SurePanel.rows(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final key in keys)
            _ApiKeyRow(
              key: ValueKey('apiKey-${key.id}'),
              apiKey: key,
              used: ApiKeysScreen.usedLabel(context, key.lastUsedAt?.toLocal(),
                  now: now),
              onRevoke: key.current ? null : () => _revoke(key),
            ),
        ],
      );
    }

    return SureLargeTitleScaffold(
      title: l.s4sApiKeysTitle,
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      actions: [
        SureNavIconButton(
          icon: SureIcons.plus,
          semanticLabel: l.s4sApiKeyNew,
          onPressed: keys == null ? null : _create,
        ),
      ],
      onRefresh: _load,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              if (created != null)
                _CreatedKeyBanner(
                  created: created,
                  onCopy: () => _copy(created.plainKey),
                  onDismiss: () => setState(() => _created = null),
                ),
              content,
            ],
          ),
        ),
      ],
    );
  }
}

class _ApiKeyRow extends StatelessWidget {
  const _ApiKeyRow({
    super.key,
    required this.apiKey,
    required this.used,
    this.onRevoke,
  });

  final ApiKey apiKey;
  final String used;

  /// Null for the current key: it gets no revoke action at all.
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final secondary = TextStyle(fontSize: 13, color: palette.textSecondary);
    final scope =
        apiKey.canWrite ? l.s4sApiKeyScopeReadWrite : l.s4sApiKeyScopeRead;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  apiKey.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (apiKey.current) ...[
                const SizedBox(width: 8),
                Text(
                  l.s4sApiKeyThisDevice,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: palette.success,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            apiKey.displayKey,
            style: SureMoney.tabular(TextStyle(
              fontFamily: SureTokens.fontMono,
              fontFamilyFallback: const <String>['Menlo', 'monospace'],
              fontSize: 13,
              color: palette.textSecondary,
            )),
          ),
          Text('$scope · $used',
              maxLines: 2, overflow: TextOverflow.ellipsis, style: secondary),
        ],
      ),
    );

    final revoke = onRevoke;
    if (revoke == null) return body;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: l.s4sApiKeyRevoke): revoke,
      },
      child: SureSwipeActions(
        actionWidth: 96,
        actions: [
          SureSwipeAction(
            label: l.s4sApiKeyRevoke,
            color: palette.destructive,
            onPressed: revoke,
          ),
        ],
        child: ColoredBox(color: palette.container, child: body),
      ),
    );
  }
}

/// The new key, once: its value in mono, Copy and Done.
class _CreatedKeyBanner extends StatelessWidget {
  const _CreatedKeyBanner({
    required this.created,
    required this.onCopy,
    required this.onDismiss,
  });

  final _CreatedKey created;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return SurePanel(
      key: const ValueKey('apiKeyCreatedBanner'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SureIcon(SureIcons.circleCheck, size: 16, color: palette.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.s4sApiKeyCreated(created.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              created.plainKey,
              key: const ValueKey('apiKeyPlainKey'),
              style: TextStyle(
                fontFamily: SureTokens.fontMono,
                fontFamilyFallback: const <String>['Menlo', 'monospace'],
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SureIcon(SureIcons.triangleAlert,
                    size: 14, color: palette.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.s4sApiKeyShownOnce,
                    style: TextStyle(fontSize: 13, color: palette.warning),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                      foregroundColor: palette.textSecondary),
                  child: Text(l.s4sApiKeyDismiss),
                ),
                TextButton.icon(
                  key: const ValueKey('apiKeyCopy'),
                  onPressed: onCopy,
                  style: TextButton.styleFrom(foregroundColor: palette.link),
                  icon: SureIcon('copy', size: 16, color: palette.link),
                  label: Text(l.s4sApiKeyCopy,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The create sheet: a Name field and Read / Read & write. [onSubmit]
/// returns an error message to show, or null when the key was created (and
/// the caller closed the sheet).
class _ApiKeyForm extends StatefulWidget {
  const _ApiKeyForm({required this.onSubmit});

  final Future<String?> Function(String name, String scope) onSubmit;

  @override
  State<_ApiKeyForm> createState() => _ApiKeyFormState();
}

class _ApiKeyFormState extends State<_ApiKeyForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _scope = 'read';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(_name.text.trim(), _scope);
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
      title: l.s4sApiKeyNew,
      actionLabel: l.s4sApiKeyCreate,
      actionKey: const ValueKey('apiKeyFormCreate'),
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
                    fieldKey: const ValueKey('apiKeyName'),
                    label: l.s4sApiKeyName,
                    hint: l.s4sApiKeyNameHint,
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l.s4sApiKeyNameRequired
                        : null,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text(l.s4sApiKeyAccess,
                    style:
                        TextStyle(fontSize: 13, color: palette.textSecondary)),
              ),
              SureSegmentedControl<String>(
                key: const ValueKey('apiKeyScope'),
                segments: [
                  SureSegment(value: 'read', label: l.s4sApiKeyScopeRead),
                  SureSegment(
                      value: 'read_write', label: l.s4sApiKeyScopeReadWrite),
                ],
                selected: _scope,
                onChanged: _busy ? (_) {} : (v) => setState(() => _scope = v),
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
