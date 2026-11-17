import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/connection_setup.dart';
import '../providers/privacy_provider.dart';
import '../services/connection_setup_service.dart';
import '../theme/sure_colors.dart';
import '../utils/money_masker.dart';
import '../widgets/ds/ds.dart';
import '../widgets/metadata_picker_sheet.dart';
import 'form_sheet_fields.dart';
import 'settings_links.dart';

/// Sure+ round 4a: the sheets of the Connections screen's add flow.

/// A plain message for a failed connection-setup result (handoff, create,
/// pending accounts, complete setup). 403 and other 422s show the server's
/// own message.
String connectionSetupErrorMessage(
    AppLocalizations l, Map<String, dynamic> result) {
  final code = result['code'] as String?;
  final status = result['status'];
  return switch (code) {
    'rate_limit_exceeded' => l.s4cTooManyAttempts,
    'path_not_allowed' => l.s4cConnectError,
    'blank_token' => l.s4cErrorBlankToken,
    'invalid_token' => l.s4cErrorInvalidToken,
    'token_compromised' => l.s4cErrorTokenCompromised,
    'create_failed' => l.s4cErrorCreateFailed,
    'unexpected' => l.s4cErrorUnexpected,
    'invalid_account_type' => l.s4cErrorInvalidType,
    'invalid_subtype' => l.s4cErrorInvalidSubtype,
    'unknown_account' => l.s4cErrorUnknownAccount,
    'link_not_supported' => l.s4cErrorLinkNotSupported,
    'invalid_sync_start_date' => l.s4cErrorInvalidDate,
    'setup_failed' => l.s4cErrorSetupFailed,
    _ when status == 429 => l.s4cTooManyAttempts,
    _ when status == 403 || status == 422 =>
      result['error'] as String? ?? l.s4cErrorUnexpected,
    _ => l.s4cErrorUnexpected,
  };
}

/// One year before [now], the default "Sync history from".
DateTime defaultSyncStart(DateTime now) =>
    DateTime(now.year - 1, now.month, now.day);

// ---------------------------------------------------------------------------
// Add connection

/// The "Add connection" sheet: the server's available providers. Pops with
/// the tapped [AvailableConnection].
class AddConnectionSheet extends StatefulWidget {
  const AddConnectionSheet({super.key, required this.load});

  /// `ConnectionSetupService.available`, with the token already applied.
  final Future<Map<String, dynamic>> Function() load;

  @override
  State<AddConnectionSheet> createState() => _AddConnectionSheetState();
}

class _AddConnectionSheetState extends State<AddConnectionSheet> {
  List<AvailableConnection>? _entries;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final result = await widget.load();
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (result['success'] == true) {
        // Plaid covers most banks: list it first, then the server's order.
        final all = (result['connections'] as List<dynamic>)
            .cast<AvailableConnection>();
        _entries = [
          ...all.where((e) => e.provider == 'plaid'),
          ...all.where((e) => e.provider != 'plaid'),
        ];
      } else {
        _failed = true;
      }
    });
  }

  String? _subtitle(AppLocalizations l, AvailableConnection e) {
    if (e.key == 'plaid_us') return l.s4cPlaidUs;
    if (e.key == 'plaid_eu') return l.s4cPlaidEu;
    if (!e.isToken) return null;
    return e.provider == 'simplefin' ? l.s4cPasteSetupToken : l.s4cApiKeySubtitle;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final entries = _entries;

    final Widget body;
    if (entries == null && !_failed) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (entries == null) {
      body = SureEmptyState(
        icon: SureIcons.circleAlert,
        title: l.s4cLoadAvailableFailed,
        secondaryLabel: l.commonTryAgain,
        onSecondary: _load,
      );
    } else if (entries.isEmpty) {
      body = SureEmptyState(icon: 'unplug', title: l.s4cNoneAvailable);
    } else {
      body = SurePanel.rows(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          for (final e in entries)
            SureListRow(
              key: ValueKey('s4cAvailable-${e.key}'),
              title: e.name,
              subtitle: _subtitle(l, e),
              trailing: e.isToken
                  ? SureIcon(SureIcons.chevronRight,
                      size: 16, color: palette.textSubdued)
                  : const SettingsWebMark(),
              onTap: () => Navigator.of(context).pop(e),
            ),
        ],
      );
    }

    return SureSheet(
      title: l.s4cAddConnection,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 24),
        child: body,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Token connection form

class _TokenField {
  const _TokenField(this.key, {this.secret = false, this.optional = false});

  /// The `connection` attribute the server permits.
  final String key;
  final bool secret;

  /// Optional fields go in the "More" section.
  final bool optional;
}

/// What a [TokenConnectionSheet] ended with: the create result, or a request
/// to connect on the web instead (`provider_not_supported`).
class TokenConnectionResult {
  const TokenConnectionResult.created(this.result) : fallbackToWeb = false;
  const TokenConnectionResult.useWeb()
      : result = const {},
        fallbackToWeb = true;

  final Map<String, dynamic> result;
  final bool fallbackToWeb;
}

/// The native create form for a `kind: token` provider (round 4a
/// `connections.token_create`). Secrets are obscured, without autocorrect
/// or suggestions, and cleared as soon as the request finishes.
class TokenConnectionSheet extends StatefulWidget {
  const TokenConnectionSheet({
    super.key,
    required this.entry,
    required this.onConnect,
    this.now,
  });

  final AvailableConnection entry;

  /// Sends `POST /api/v1/provider_connections` with these attributes.
  final Future<Map<String, dynamic>> Function(Map<String, String> fields)
      onConnect;

  final DateTime Function()? now;

  /// The server's `permitted_attributes` per provider, minus
  /// `sync_start_date` (see [_syncDateAtCreate]).
  static const _fields = <String, List<_TokenField>>{
    'simplefin': [_TokenField('setup_token', secret: true)],
    'lunchflow': [
      _TokenField('api_key', secret: true),
      _TokenField('base_url', optional: true),
      _TokenField('name', optional: true),
    ],
    'mercury': [
      _TokenField('token', secret: true),
      _TokenField('base_url', optional: true),
      _TokenField('name', optional: true),
    ],
    'brex': [
      _TokenField('token', secret: true),
      _TokenField('base_url', optional: true),
      _TokenField('name', optional: true),
    ],
    'kraken': _keyAndSecret,
    'binance': _keyAndSecret,
    'coinspot': _keyAndSecret,
    'ibkr': [
      _TokenField('query_id'),
      _TokenField('token', secret: true),
      _TokenField('name', optional: true),
    ],
  };

  static const _keyAndSecret = [
    _TokenField('api_key', secret: true),
    _TokenField('api_secret', secret: true),
    _TokenField('name', optional: true),
  ];

  /// SimpleFIN takes its start date at account setup; IBKR has none.
  static const _syncDateAtCreate = {
    'lunchflow',
    'mercury',
    'brex',
    'kraken',
    'binance',
    'coinspot',
  };

  /// Providers this form (and the account setup sheet) supports.
  static Set<String> get providers => _fields.keys.toSet();

  static bool supports(String provider) => _fields.containsKey(provider);

  @override
  State<TokenConnectionSheet> createState() => _TokenConnectionSheetState();
}

class _TokenConnectionSheetState extends State<TokenConnectionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final List<_TokenField> _fields =
      TokenConnectionSheet._fields[widget.entry.provider] ?? const [];
  late final Map<String, TextEditingController> _controllers = {
    for (final f in _fields) f.key: TextEditingController(),
  };
  late DateTime _syncStart =
      defaultSyncStart((widget.now ?? DateTime.now)());
  bool _busy = false;
  String? _error;

  bool get _hasSyncDate =>
      TokenConnectionSheet._syncDateAtCreate.contains(widget.entry.provider);

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  void _clearSecrets() {
    for (final f in _fields) {
      if (f.secret) _controllers[f.key]!.clear();
    }
  }

  Future<void> _connect() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final fields = <String, String>{
      for (final f in _fields)
        if (_controllers[f.key]!.text.trim().isNotEmpty)
          f.key: _controllers[f.key]!.text.trim(),
      if (_hasSyncDate) 'sync_start_date': _isoDay(_syncStart),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    final Map<String, dynamic> result;
    try {
      result = await widget.onConnect(fields);
    } finally {
      // The secrets live only as long as the request.
      fields.clear();
      _clearSecrets();
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (result['success'] == true || result['error'] == 'unauthorized') {
      nav.pop(TokenConnectionResult.created(result));
      return;
    }
    if (result['code'] == 'provider_not_supported') {
      nav.pop(const TokenConnectionResult.useWeb());
      return;
    }
    setState(() {
      _busy = false;
      _error = connectionSetupErrorMessage(AppLocalizations.of(context), result);
    });
  }

  static String _isoDay(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _label(AppLocalizations l, String key) => switch (key) {
        'setup_token' => l.s4cSetupToken,
        'api_key' => l.s4cApiKey,
        'api_secret' => l.s4cApiSecret,
        'token' => l.s4cToken,
        'query_id' => l.s4cQueryId,
        'base_url' => l.s4cBaseUrl,
        'name' => l.s4cName,
        _ => key,
      };

  Widget _row(AppLocalizations l, _TokenField f) => FormSheetFieldRow(
        fieldKey: ValueKey('s4cField-${f.key}'),
        label: _label(l, f.key),
        controller: _controllers[f.key]!,
        hint: f.optional ? l.s4cOptional : l.s4cRequired,
        secret: f.secret,
        enabled: !_busy,
        keyboardType: f.key == 'base_url' ? TextInputType.url : null,
        validator: f.optional
            ? null
            : (v) => (v == null || v.trim().isEmpty) ? l.s4cRequired : null,
      );

  Future<void> _pickDate() async {
    final now = (widget.now ?? DateTime.now)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _syncStart,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _syncStart = DateUtils.dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final required = _fields.where((f) => !f.optional).toList();
    final optional = _fields.where((f) => f.optional).toList();

    return SureSheet(
      title: widget.entry.name,
      actionLabel: l.s4cConnect,
      actionKey: const ValueKey('s4cConnect'),
      busy: _busy,
      onAction: _connect,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SurePanel.rows(children: [
                for (final f in required) _row(l, f),
                if (_hasSyncDate)
                  SureListRow(
                    key: const ValueKey('s4cSyncFrom'),
                    title: l.s4cSyncFrom,
                    value: SureDates.fullOf(context, _syncStart),
                    showChevron: true,
                    onTap: _busy ? null : _pickDate,
                  ),
              ]),
              if (widget.entry.provider == 'simplefin')
                const _SimplefinHelp(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Text(
                    _error!,
                    style: TextStyle(fontSize: 13, color: palette.destructive),
                  ),
                ),
              if (optional.isNotEmpty) ...[
                SureSectionHeader(label: l.s4cMore),
                SurePanel.rows(children: [
                  for (final f in optional) _row(l, f),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Get a setup token at bridge.simplefin.org." with the site as a link.
class _SimplefinHelp extends StatefulWidget {
  const _SimplefinHelp();

  static const site = 'bridge.simplefin.org';

  @override
  State<_SimplefinHelp> createState() => _SimplefinHelpState();
}

class _SimplefinHelpState extends State<_SimplefinHelp> {
  late final _tap = TapGestureRecognizer()..onTap = _open;

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await launchUrl(Uri.https(_SimplefinHelp.site),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser to open; nothing else to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    const site = _SimplefinHelp.site;
    final text = l.s4cSimplefinHelp(site);
    final at = text.indexOf(site);
    final base = TextStyle(fontSize: 13, color: palette.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Semantics(
        link: true,
        child: Text.rich(
          at < 0
              ? TextSpan(text: text, recognizer: _tap)
              : TextSpan(children: [
                  TextSpan(text: text.substring(0, at)),
                  TextSpan(
                    text: site,
                    style: TextStyle(color: palette.link),
                    recognizer: _tap,
                  ),
                  TextSpan(text: text.substring(at + site.length)),
                ]),
          style: base,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account setup

enum AccountSetupOutcome { imported, timedOut, nothingPending, linkExisting }

/// How an [AccountSetupSheet] closed; a null sheet result means "Later".
class AccountSetupResult {
  const AccountSetupResult(this.outcome, {this.count = 0, this.linkPath});

  final AccountSetupOutcome outcome;

  /// Accounts created, for [AccountSetupOutcome.imported].
  final int count;

  /// The web page to hand off to, for [AccountSetupOutcome.linkExisting].
  final String? linkPath;
}

class _Selection {
  _Selection({required this.import, this.type, this.subtype});

  bool import;
  String? type;
  String? subtype;
}

/// Picks which of a new connection's accounts to import and as what type
/// (`GET pending_accounts`, `POST complete_setup`). While the provider's
/// first sync runs (`awaiting_accounts`) it polls every [pollInterval] for
/// up to [waitLimit], then closes with [AccountSetupOutcome.timedOut].
class AccountSetupSheet extends StatefulWidget {
  const AccountSetupSheet({
    super.key,
    required this.connectionId,
    required this.provider,
    required this.providerName,
    required this.service,
    required this.token,
    required this.onUnauthorized,
    this.linkableAccounts = const [],
    this.now,
  });

  static const pollInterval = Duration(seconds: 4);
  static const waitLimit = Duration(minutes: 3);

  /// Providers whose web setup takes the start date here, not at create.
  static const syncDateAtSetup = {'simplefin', 'binance'};

  final String connectionId;
  final String provider;
  final String providerName;
  final ConnectionSetupService service;
  final Future<String?> Function() token;
  final Future<void> Function() onUnauthorized;

  /// Sure accounts the provider's `select_existing_account` page can link.
  final List<Account> linkableAccounts;
  final DateTime Function()? now;

  @override
  State<AccountSetupSheet> createState() => _AccountSetupSheetState();
}

class _AccountSetupSheetState extends State<AccountSetupSheet> {
  List<PendingAccount>? _accounts;
  final Map<String, _Selection> _selections = {};
  bool _waiting = false;
  bool _loadFailed = false;
  int _polls = 0;
  Timer? _timer;
  late DateTime _syncStart = defaultSyncStart((widget.now ?? DateTime.now)());
  bool _busy = false;
  String? _error;

  static final int _maxPolls = AccountSetupSheet.waitLimit.inSeconds ~/
      AccountSetupSheet.pollInterval.inSeconds;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _unauthorized() async {
    Navigator.of(context).pop();
    await widget.onUnauthorized();
  }

  Future<void> _fetch() async {
    final token = await widget.token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await widget.service.pendingAccounts(
      accessToken: token,
      connectionId: widget.connectionId,
      provider: widget.provider,
    );
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();

    final ok = result['success'] == true;
    if (ok && result['awaitingAccounts'] != true) {
      final accounts =
          (result['accounts'] as List<dynamic>).cast<PendingAccount>();
      if (accounts.isEmpty) {
        Navigator.of(context).pop(
            const AccountSetupResult(AccountSetupOutcome.nothingPending));
        return;
      }
      setState(() {
        _waiting = false;
        _loadFailed = false;
        _accounts = accounts;
        for (final a in accounts) {
          _selections[a.id] = _initialSelection(a);
        }
      });
      return;
    }

    // Still waiting for the first sync, or a failed poll while waiting.
    if (ok || _waiting) {
      if (_polls >= _maxPolls) {
        Navigator.of(context)
            .pop(const AccountSetupResult(AccountSetupOutcome.timedOut));
        return;
      }
      setState(() => _waiting = true);
      _polls++;
      _timer = Timer(AccountSetupSheet.pollInterval, _fetch);
      return;
    }
    setState(() {
      _loadFailed = true;
      _error = connectionSetupErrorMessage(AppLocalizations.of(context), result);
    });
  }

  _Selection _initialSelection(PendingAccount a) {
    final types = a.allowedTypes;
    final suggested = types
        .where((t) => t.accountableType == a.suggestedAccountableType)
        .firstOrNull;
    final type = suggested ?? types.firstOrNull;
    final subtype = type?.subtypes
        .where((s) => s.value == a.suggestedSubtype)
        .firstOrNull
        ?.value;
    return _Selection(
      import: true,
      type: type?.accountableType ?? a.suggestedAccountableType,
      subtype: subtype,
    );
  }

  String _typeLabel(PendingAccount a, _Selection s) {
    final type =
        a.allowedTypes.where((t) => t.accountableType == s.type).firstOrNull;
    final subtype =
        type?.subtypes.where((o) => o.value == s.subtype).firstOrNull;
    return subtype?.label ?? type?.label ?? s.type ?? '';
  }

  Future<void> _pickType(PendingAccount a) async {
    final l = AppLocalizations.of(context);
    final s = _selections[a.id]!;
    final options = <PickerOption>[
      for (final t in a.allowedTypes)
        if (t.subtypes.isEmpty)
          PickerOption(id: '${t.accountableType}|', label: t.label)
        else
          for (final sub in t.subtypes)
            PickerOption(
              id: '${t.accountableType}|${sub.value}',
              label: '${t.label} · ${sub.label}',
            ),
    ];
    final picked = await MetadataPickerSheet.show(
      context,
      title: l.s4cAccountType,
      options: options,
      initialSelection: {'${s.type}|${s.subtype ?? ''}'},
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final parts = picked.first.split('|');
    setState(() {
      s.type = parts.first;
      s.subtype = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _syncStart,
      firstDate: DateTime(1990),
      lastDate: (widget.now ?? DateTime.now)(),
    );
    if (picked == null || !mounted) return;
    setState(() => _syncStart = DateUtils.dateOnly(picked));
  }

  Future<void> _linkExisting() async {
    final l = AppLocalizations.of(context);
    final picked = await MetadataPickerSheet.show(
      context,
      title: l.s4cChooseAccount,
      options: [
        for (final a in widget.linkableAccounts)
          PickerOption(id: a.id, label: a.name),
      ],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final path = Uri(
      path: '/${widget.provider}_items/select_existing_account',
      queryParameters: {'account_id': picked.first},
    ).toString();
    Navigator.of(context).pop(AccountSetupResult(
        AccountSetupOutcome.linkExisting,
        linkPath: path));
  }

  Future<void> _import() async {
    final accounts = _accounts;
    if (accounts == null || _busy) return;
    final token = await widget.token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.service.completeSetup(
      accessToken: token,
      connectionId: widget.connectionId,
      provider: widget.provider,
      syncStartDate:
          AccountSetupSheet.syncDateAtSetup.contains(widget.provider)
              ? _syncStart
              : null,
      accounts: [
        for (final a in accounts)
          if (_selections[a.id]!.import)
            {
              'id': a.id,
              'import': true,
              if (_selections[a.id]!.type != null)
                'accountable_type': _selections[a.id]!.type,
              if (_selections[a.id]!.subtype != null)
                'subtype': _selections[a.id]!.subtype,
            }
          else
            {'id': a.id, 'import': false},
      ],
    );
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] == true) {
      SureHaptics.success();
      Navigator.of(context).pop(AccountSetupResult(
        AccountSetupOutcome.imported,
        count: (result['createdAccountIds'] as List<dynamic>).length,
      ));
      return;
    }
    setState(() {
      _busy = false;
      _error = connectionSetupErrorMessage(AppLocalizations.of(context), result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accounts = _accounts;

    final Widget body;
    if (accounts == null && _loadFailed) {
      body = SureEmptyState(
        icon: SureIcons.circleAlert,
        title: l.s4cPendingLoadFailed,
        body: _error,
        secondaryLabel: l.commonTryAgain,
        onSecondary: () {
          setState(() {
            _loadFailed = false;
            _error = null;
          });
          _fetch();
        },
      );
    } else if (accounts == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            if (_waiting) ...[
              const SizedBox(height: 16),
              Text(
                l.s4cWaiting(widget.providerName),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: palette.textSecondary),
              ),
            ],
          ],
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurePanel.rows(
            dividerIndent: 54,
            children: [
              for (final a in accounts)
                _PendingAccountRow(
                  account: a,
                  selected: _selections[a.id]!.import,
                  typeLabel: _typeLabel(a, _selections[a.id]!),
                  enabled: !_busy,
                  onToggle: (v) =>
                      setState(() => _selections[a.id]!.import = v),
                  onPickType: a.allowedTypes.isEmpty
                      ? null
                      : () => _pickType(a),
                ),
            ],
          ),
          if (AccountSetupSheet.syncDateAtSetup.contains(widget.provider))
            SurePanel.rows(
              margin: const EdgeInsets.only(top: 16),
              children: [
                SureListRow(
                  key: const ValueKey('s4cSetupSyncFrom'),
                  title: l.s4cSyncFrom,
                  value: SureDates.fullOf(context, _syncStart),
                  showChevron: true,
                  onTap: _busy ? null : _pickDate,
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 13, color: palette.destructive),
              ),
            ),
          if (widget.linkableAccounts.isNotEmpty)
            SurePanel.rows(
              margin: const EdgeInsets.only(top: 16),
              children: [
                SureListRow(
                  title: l.s4cLinkExisting,
                  titleColor: palette.link,
                  trailing: const SettingsWebMark(),
                  onTap: _busy ? null : _linkExisting,
                ),
              ],
            ),
        ],
      );
    }

    return SureSheet(
      title: l.s4cSetupTitle,
      cancelLabel: l.s4cLater,
      actionLabel: l.s4cImport,
      actionKey: const ValueKey('s4cImport'),
      actionEnabled: accounts != null,
      busy: _busy,
      onAction: _import,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: body,
      ),
    );
  }
}

class _PendingAccountRow extends StatelessWidget {
  const _PendingAccountRow({
    required this.account,
    required this.selected,
    required this.typeLabel,
    required this.enabled,
    required this.onToggle,
    required this.onPickType,
  });

  final PendingAccount account;
  final bool selected;
  final String typeLabel;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onPickType;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final institution = account.institution?.trim() ?? '';
    final secondary = TextStyle(fontSize: 13, color: palette.textSecondary);

    return InkWell(
      onTap: enabled ? () => onToggle(!selected) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
        child: Row(
          children: [
            Semantics(
              label: l.s4cImportAccount(account.name),
              child: Checkbox(
                value: selected,
                onChanged: enabled ? (v) => onToggle(v ?? false) : null,
                activeColor: palette.buttonPrimary,
                checkColor: palette.textInverse,
                side: BorderSide(color: palette.textSubdued, width: 1.5),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: palette.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      if (institution.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            '$institution · ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary,
                          ),
                        ),
                      ],
                      Flexible(
                        child: MoneyText(
                          MoneyMasker.mask(account.balance, hidden: hidden),
                          trend: MoneyTrend.neutral,
                          color: palette.textSecondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w400),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (typeLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.36,
                ),
                child: SureChip(
                  label: typeLabel,
                  dropdown: onPickType != null,
                  enabled: enabled && selected,
                  onSelected: onPickType == null ? null : (_) => onPickType!(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
