import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_statement.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/account_statements_service.dart';
import '../services/file_pick.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/data_import_logic.dart';
import '../widgets/form_error_text.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_list_group.dart';
import 'import_screen.dart' show DataInLinkButton;

/// Settings -> Upload statement: pick a PDF, CSV or XLSX statement and an
/// account, upload it to the Statement Vault, and see that account's recent
/// statements.
class StatementUploadScreen extends StatefulWidget {
  const StatementUploadScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.accounts,
    this.pickFile,
    this.initialAccountId,
  });

  /// Injected for tests; otherwise the screen owns one.
  final AccountStatementsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Target accounts; defaults to [AccountsProvider.accounts].
  final List<Account>? accounts;

  /// Defaults to the system file picker.
  final FilePickFn? pickFile;

  /// Preselects an account, e.g. when opened from an account screen.
  final String? initialAccountId;

  /// The web page that lists statements (`account_statements#index`).
  static const webPath = '/account_statements';

  @override
  State<StatementUploadScreen> createState() => _StatementUploadScreenState();
}

enum _Outcome { uploaded, duplicate, error }

class _StatementUploadScreenState extends State<StatementUploadScreen> {
  late final AccountStatementsService _service;
  String? _accountId;
  PickedFileData? _file;
  String? _fileError;
  bool _uploading = false;
  _Outcome? _outcome;
  String? _message;
  AccountStatement? _result;

  List<AccountStatement>? _statements;
  bool _listLoading = false;
  bool _listFailed = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AccountStatementsService();
    _accountId = widget.initialAccountId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final accounts = _accounts;
      if (_accountId == null && accounts.length == 1) {
        setState(() => _accountId = accounts.single.id);
      }
      _loadStatements();
    });
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

  List<Account> get _accounts {
    if (widget.accounts != null) return widget.accounts!;
    try {
      return context.read<AccountsProvider>().accounts;
    } on ProviderNotFoundException {
      return const [];
    }
  }

  Future<void> _loadStatements() async {
    final accountId = _accountId;
    if (accountId == null) {
      setState(() => _statements = null);
      return;
    }
    setState(() => _listLoading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.list(accessToken: token, accountId: accountId);
    if (!mounted || accountId != _accountId) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    setState(() {
      _listLoading = false;
      _listFailed = result['success'] != true;
      if (!_listFailed) {
        _statements = (result['statements'] as List).cast<AccountStatement>();
      }
    });
  }

  Future<void> _chooseFile() async {
    final picker = widget.pickFile ?? pickFileWithExtensions;
    final extensions = statementContentTypes.keys.toList();
    final file = await picker(extensions);
    if (file == null || !mounted) return;
    final l = AppLocalizations.of(context);
    String? error;
    if (!hasAllowedExtension(file.name, extensions)) {
      error = l.dataInStatementWrongType;
    } else if (!isUploadSizeAllowed(file.size, maxStatementBytes)) {
      error = file.size == 0
          ? l.dataInFileEmpty
          : l.dataInFileTooLarge(formatByteSize(maxStatementBytes));
    }
    setState(() {
      _file = file;
      _fileError = error;
      _outcome = null;
    });
  }

  Future<void> _upload() async {
    final file = _file;
    final accountId = _accountId;
    if (file == null || accountId == null) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _uploading = true;
      _outcome = null;
    });
    final List<int> bytes;
    try {
      bytes = await file.read();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _outcome = _Outcome.error;
        _message = l.dataInReadFailed;
      });
      return;
    }
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.upload(
        accessToken: token, bytes: bytes, filename: file.name, accountId: accountId);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    setState(() {
      _uploading = false;
      if (result['success'] == true) {
        _result = result['statement'] as AccountStatement;
        _outcome = result['duplicate'] == true ? _Outcome.duplicate : _Outcome.uploaded;
        _message = null;
        if (_outcome == _Outcome.uploaded) _file = null;
      } else if (result['code'] == 'duplicate') {
        _result = null;
        _outcome = _Outcome.duplicate;
        _message = l.dataInStatementDuplicateHidden;
      } else {
        _outcome = _Outcome.error;
        _message = result['error'] as String?;
      }
    });
    if (result['success'] == true) _loadStatements();
  }

  String _date(DateTime date) =>
      DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
          .format(date.toLocal());

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accounts = _accounts;
    final file = _file;
    final canUpload =
        file != null && _fileError == null && _accountId != null && !_uploading;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.dataInStatementTitle),
        actions: const [OpenOnWebAction(path: StatementUploadScreen.webPath)],
      ),
      body: RefreshIndicator(
        onRefresh: _loadStatements,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              SureSpacing.xl, SureSpacing.lg, SureSpacing.xl, SureSpacing.huge),
          children: [
            SureCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.dataInStatementHelp(formatByteSize(maxStatementBytes)),
                    style: TextStyle(color: palette.textSubdued),
                  ),
                  const SizedBox(height: SureSpacing.lg),
                  if (accounts.isEmpty)
                    FormErrorText(l.dataInNoAccounts)
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey('account-$_accountId'),
                      initialValue: _accountId,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.dataInAccountLabel),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: _uploading
                          ? null
                          : (v) {
                              setState(() {
                                _accountId = v;
                                _statements = null;
                                _outcome = null;
                              });
                              _loadStatements();
                            },
                    ),
                  const SizedBox(height: SureSpacing.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: SureButton(
                        label: file == null ? l.dataInChooseFile : l.dataInChooseAnother,
                        variant: SureButtonVariant.outline,
                        leading: const Icon(Icons.upload_file, size: 16),
                        onPressed: _uploading ? null : _chooseFile,
                      ),
                    ),
                  ),
                  if (file != null) ...[
                    const SizedBox(height: SureSpacing.md),
                    Row(children: [
                      const Icon(Icons.description_outlined, size: 20),
                      const SizedBox(width: SureSpacing.md),
                      Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
                      Text(formatByteSize(file.size),
                          style: TextStyle(color: palette.textSubdued)),
                    ]),
                  ],
                  if (_fileError != null) ...[
                    const SizedBox(height: SureSpacing.md),
                    FormErrorText(_fileError!),
                  ],
                  const SizedBox(height: SureSpacing.xl),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: SureButton(
                      label: l.dataInUpload,
                      fullWidth: true,
                      loading: _uploading,
                      onPressed: canUpload ? _upload : null,
                    ),
                  ),
                  if (_outcome != null) ...[
                    const SizedBox(height: SureSpacing.lg),
                    _outcomeView(context),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SureSpacing.xl),
            _recent(context),
          ],
        ),
      ),
    );
  }

  Widget _outcomeView(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    switch (_outcome!) {
      case _Outcome.error:
        return FormErrorText(_message ?? l.dataInStatementFailed);
      case _Outcome.duplicate:
        final created = _result?.createdAt;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 20, color: palette.info),
            const SizedBox(width: SureSpacing.md),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(created != null
                    ? l.dataInStatementDuplicate(_date(created))
                    : (_message ?? l.dataInStatementDuplicateHidden)),
              ),
            ),
          ],
        );
      case _Outcome.uploaded:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.check_circle_outline, size: 20, color: palette.success),
              const SizedBox(width: SureSpacing.md),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(l.dataInStatementUploaded(_result?.filename ?? '')),
                ),
              ),
            ]),
            DataInLinkButton(
              label: l.dataInStatementViewOnWeb,
              icon: Icons.language,
              onPressed: () => openWebFallback(context,
                  title: l.dataInStatementTitle, path: StatementUploadScreen.webPath),
            ),
          ],
        );
    }
  }

  Widget _recent(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final statements = _statements;
    if (_accountId == null) {
      return Text(l.dataInStatementPickAccount,
          style: TextStyle(color: palette.textSubdued));
    }
    if (statements == null && _listLoading) {
      return const Padding(
        padding: EdgeInsets.all(SureSpacing.xxxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (statements == null || (_listFailed && statements.isEmpty)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormErrorText(l.dataInStatementListFailed),
          const SizedBox(height: SureSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: SureButton(
              label: l.dataInRetry,
              variant: SureButtonVariant.outline,
              onPressed: _loadStatements,
            ),
          ),
        ],
      );
    }
    if (statements.isEmpty) {
      return Text(l.dataInStatementListEmpty,
          style: TextStyle(color: palette.textSubdued));
    }
    return SureListGroup(
      header: l.dataInStatementRecent,
      children: [
        for (final s in statements)
          SureListRow(
            leading: const Icon(Icons.description_outlined),
            title: s.filename,
            subtitle: [
              if (s.periodStart != null && s.periodEnd != null)
                l.dataInStatementPeriod(_date(s.periodStart!), _date(s.periodEnd!)),
              if (s.createdAt != null) l.dataInStatementAdded(_date(s.createdAt!)),
            ].join(' · '),
            showChevron: true,
            onTap: () => openWebFallback(context,
                title: s.filename,
                path: '${StatementUploadScreen.webPath}/${Uri.encodeComponent(s.id)}'),
          ),
      ],
    );
  }
}
