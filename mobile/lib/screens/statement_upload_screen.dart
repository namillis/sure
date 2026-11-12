import 'package:flutter/material.dart';
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
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import 'import_screen.dart' show DataInFileRow;

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

  Future<void> _pickAccount() async {
    final l = AppLocalizations.of(context);
    final picked = await showManageOptionSheet<String?>(
      context,
      title: l.dataInAccountLabel,
      selected: _accountId,
      options: [for (final a in _accounts) (a.id, a.name)],
    );
    if (picked == null || !mounted || picked.value == _accountId) return;
    setState(() {
      _accountId = picked.value;
      _statements = null;
      _outcome = null;
    });
    _loadStatements();
  }

  static const _hMargin = EdgeInsets.symmetric(horizontal: 16);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accounts = _accounts;
    final file = _file;
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final canUpload =
        file != null && _fileError == null && _accountId != null && !_uploading;

    return SureLargeTitleScaffold(
      title: l.dataInStatementTitle,
      leading: manageBackLink(context),
      actions: [
        SureNavIconButton(
          icon: SureIcons.externalLink,
          semanticLabel: l.shellOpenOnWeb,
          onPressed: () => openWebFallback(context,
              title: l.dataInStatementTitle,
              path: StatementUploadScreen.webPath),
        ),
      ],
      onRefresh: _loadStatements,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Text(
                  l.dataInStatementHelp(formatByteSize(maxStatementBytes)),
                  style: TextStyle(
                      fontSize: 13, height: 1.35, color: palette.textSecondary),
                ),
              ),
              if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: ManageErrorText(l.dataInNoAccounts),
                ),
              SurePanel.rows(
                margin: _hMargin,
                children: [
                  if (accounts.isNotEmpty)
                    SureListRow(
                      key: const ValueKey('statementAccountRow'),
                      title: l.dataInAccountLabel,
                      value: account?.name ?? l.ds4dChoose,
                      showChevron: true,
                      onTap: _uploading ? null : _pickAccount,
                    ),
                  DataInFileRow(
                    file: file,
                    chooseLabel: l.dataInChooseFile,
                    onTap: _uploading ? null : _chooseFile,
                  ),
                ],
              ),
              if (_fileError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: ManageErrorText(_fileError!),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: SureButton(
                    label: l.dataInUpload,
                    fullWidth: true,
                    loading: _uploading,
                    onPressed: canUpload ? _upload : null,
                  ),
                ),
              ),
              if (_outcome != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _outcomeView(context),
                ),
              _recent(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _outcomeView(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    switch (_outcome!) {
      case _Outcome.error:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ManageErrorText(_message ?? l.dataInStatementFailed),
        );
      case _Outcome.duplicate:
        final created = _result?.createdAt;
        return Semantics(
          liveRegion: true,
          child: ManageNotice(
            created != null
                ? l.dataInStatementDuplicate(
                    SureDates.fullOf(context, created.toLocal()))
                : (_message ?? l.dataInStatementDuplicateHidden),
            info: true,
          ),
        );
      case _Outcome.uploaded:
        return SurePanel.rows(
          children: [
            Semantics(
              liveRegion: true,
              child: SureListRow(
                leading: ManageIconBadge(
                    icon: SureIcons.circleCheck, color: palette.success),
                title: l.dataInStatementUploaded(_result?.filename ?? ''),
              ),
            ),
            SureListRow(
              title: l.dataInStatementViewOnWeb,
              titleColor: palette.link,
              trailing: SureIcon(SureIcons.arrowUpRight,
                  size: 16, color: palette.link),
              onTap: () => openWebFallback(context,
                  title: l.dataInStatementTitle,
                  path: StatementUploadScreen.webPath),
            ),
          ],
        );
    }
  }

  Widget _recent(BuildContext context) {
    final l = AppLocalizations.of(context);
    final statements = _statements;
    const compact = EdgeInsets.symmetric(horizontal: 20, vertical: 20);
    final Widget panel;
    if (_accountId == null) {
      panel = SurePanel(
        margin: _hMargin,
        child: SureEmptyState(
          key: const ValueKey('statementsPickAccount'),
          icon: SureIcons.landmark,
          title: l.dataInStatementPickAccount,
          padding: compact,
        ),
      );
    } else if (statements == null && _listLoading) {
      panel = const Padding(
        padding: EdgeInsets.all(SureSpacing.xxxl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (statements == null || (_listFailed && statements.isEmpty)) {
      panel = SurePanel(
        margin: _hMargin,
        child: SureEmptyState(
          key: const ValueKey('statementsError'),
          icon: SureIcons.circleAlert,
          title: l.dataInStatementListFailed,
          primaryLabel: l.dataInRetry,
          onPrimary: _loadStatements,
          padding: compact,
        ),
      );
    } else if (statements.isEmpty) {
      panel = SurePanel(
        margin: _hMargin,
        child: SureEmptyState(
          key: const ValueKey('statementsEmpty'),
          icon: SureIcons.inbox,
          title: l.dataInStatementListEmpty,
          padding: compact,
        ),
      );
    } else {
      panel = SurePanel.rows(
        margin: _hMargin,
        dividerIndent: SurePanel.iconRowDividerIndent,
        children: [
          for (final s in statements)
            SureListRow(
              leading: const ManageIconBadge(icon: ManageIcons.receiptText),
              title: s.filename,
              subtitle: [
                if (s.periodStart != null && s.periodEnd != null)
                  l.dataInStatementPeriod(
                      SureDates.shortOf(context, s.periodStart!),
                      SureDates.shortOf(context, s.periodEnd!)),
                if (s.createdAt != null)
                  l.dataInStatementAdded(
                      SureDates.shortOf(context, s.createdAt!.toLocal())),
              ].join(' · '),
              showChevron: true,
              onTap: () => openWebFallback(context,
                  title: s.filename,
                  path:
                      '${StatementUploadScreen.webPath}/${Uri.encodeComponent(s.id)}'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SureSectionHeader(label: l.dataInStatementRecent),
        panel,
      ],
    );
  }
}
