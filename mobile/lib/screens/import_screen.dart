import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/data_import.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/file_pick.dart';
import '../services/imports_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/data_import_logic.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';

/// Settings -> Import: import history, then a four-step CSV transaction
/// import (choose file and account, map columns, preview, publish).
///
/// The API cannot publish an import that already exists (only
/// `POST /imports` with `publish=true` starts one), so step 2 maps columns
/// from preflight, step 3 previews locally parsed rows checked against the
/// chosen formats, and step 4 is the single create-and-publish call. If the
/// server then rejects the rows, the screen loads that import's rows and
/// shows their errors.
class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.accounts,
    this.pickFile,
    this.clock,
    this.sleep,
  });

  /// Injected for tests; otherwise the screen owns one.
  final ImportsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Target accounts; defaults to [AccountsProvider.accounts].
  final List<Account>? accounts;

  /// Defaults to the system file picker.
  final FilePickFn? pickFile;

  /// Clock and sleep for status polling; injected for tests.
  final DateTime Function()? clock;
  final Future<void> Function(Duration)? sleep;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

enum _Step { file, map, preview, publish }

class _ImportScreenState extends State<ImportScreen> {
  static const _previewRows = 20;

  late final ImportsService _service;

  // History.
  List<DataImport>? _history;
  bool _historyLoading = true;
  bool _historyFailed = false;

  // Wizard.
  _Step _step = _Step.file;
  bool _busy = false;
  String? _error;
  String? _accountId;
  PickedFileData? _file;
  Uint8List? _bytes;
  String? _fileError;
  ImportPreflight? _preflight;
  Map<ImportColumn, String?> _mapping = {
    for (final c in ImportColumn.values) c: null,
  };
  String _dateFormat = importDateFormats.first.$2;
  String _numberFormat = importNumberFormats.first;
  String _signage = importSignageConventions.first;
  String _colSep = importColumnSeparators.first;
  DataImport? _published;
  bool _timedOut = false;
  bool _stopPolling = false;
  List<DataImportRow> _rejectedRows = const [];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ImportsService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
      final accounts = _accounts;
      if (_accountId == null && accounts.length == 1) {
        setState(() => _accountId = accounts.single.id);
      }
    });
  }

  @override
  void dispose() {
    _stopPolling = true;
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

  /// Runs [call] with a valid token; null after logging out on 401.
  Future<Map<String, dynamic>?> _authed(
      Future<Map<String, dynamic>> Function(String token) call) async {
    final token = await _token();
    if (!mounted) return null;
    if (token == null) {
      await _unauthorized();
      return null;
    }
    final result = await call(token);
    if (!mounted) return null;
    if (result['error'] == 'unauthorized') {
      await _unauthorized();
      return null;
    }
    return result;
  }

  Future<void> _loadHistory() async {
    if (mounted) setState(() => _historyLoading = true);
    final result = await _authed((t) => _service.list(accessToken: t, perPage: 10));
    if (result == null) return;
    setState(() {
      _historyLoading = false;
      _historyFailed = result['success'] != true;
      if (!_historyFailed) {
        _history = (result['imports'] as List).cast<DataImport>();
      }
    });
  }

  Map<String, String> get _config => {
        for (final c in ImportColumn.values)
          if ((_mapping[c] ?? '').isNotEmpty) c.param: _mapping[c]!,
        'date_format': _dateFormat,
        'number_format': _numberFormat,
        'signage_convention': _signage,
        'col_sep': _colSep,
      };

  // Step 1.

  Future<void> _chooseFile() async {
    final picker = widget.pickFile ?? pickFileWithExtensions;
    final file = await picker(const ['csv']);
    if (file == null || !mounted) return;
    final l = AppLocalizations.of(context);
    String? error;
    if (!hasAllowedExtension(file.name, const ['csv'])) {
      error = l.dataInNotCsv;
    } else if (!isUploadSizeAllowed(file.size, maxCsvImportBytes)) {
      error = file.size == 0
          ? l.dataInFileEmpty
          : l.dataInFileTooLarge(formatByteSize(maxCsvImportBytes));
    }
    setState(() {
      _file = file;
      _bytes = null;
      _fileError = error;
      _preflight = null;
      _error = null;
    });
  }

  Future<void> _runPreflight({bool resetMapping = true}) async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _bytes ??= await file.read();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppLocalizations.of(context).dataInReadFailed;
      });
      return;
    }
    if (resetMapping) {
      _colSep = detectColumnSeparator(_text(maxChars: 4096));
    }
    final result = await _authed((t) => _service.preflight(
          accessToken: t,
          csv: _bytes!,
          filename: file.name,
          accountId: _accountId,
          config: {'col_sep': _colSep},
        ));
    if (result == null) return;
    setState(() {
      _busy = false;
      if (result['success'] != true) {
        _error = result['error'] as String?;
        return;
      }
      final preflight = result['preflight'] as ImportPreflight;
      _preflight = preflight;
      if (resetMapping || !_mappingFits(preflight.headers)) {
        _mapping = prefillColumnMapping(preflight.headers);
        final dateColumn = _mapping[ImportColumn.date];
        if (dateColumn != null) {
          final detected = detectDateFormat(
              columnValues(_records(maxRecords: 51), dateColumn));
          if (detected != null) _dateFormat = detected;
        }
      }
      _step = _Step.map;
    });
  }

  bool _mappingFits(List<String> headers) =>
      _mapping.values.every((h) => h == null || headers.contains(h));

  String _text({int? maxChars}) {
    final bytes = _bytes;
    if (bytes == null) return '';
    final slice = maxChars != null && bytes.length > maxChars
        ? bytes.sublist(0, maxChars)
        : bytes;
    return utf8.decode(slice, allowMalformed: true);
  }

  List<List<String>> _records({int? maxRecords}) =>
      parseCsv(_text(), separator: _colSep, maxRecords: maxRecords);

  // Step 4.

  Future<void> _publish() async {
    final file = _file;
    final bytes = _bytes;
    final accountId = _accountId;
    if (file == null || bytes == null || accountId == null) return;
    final startedAt = DateTime.now().toUtc();
    setState(() {
      _step = _Step.publish;
      _busy = true;
      _error = null;
      _published = null;
      _timedOut = false;
      _stopPolling = false;
      _rejectedRows = const [];
    });
    final result = await _authed((t) => _service.create(
          accessToken: t,
          csv: bytes,
          filename: file.name,
          accountId: accountId,
          config: _config,
        ));
    if (result == null) return;
    if (result['success'] != true) {
      setState(() {
        _busy = false;
        _error = result['error'] as String?;
      });
      await _loadRejectedRows(startedAt);
      _loadHistory();
      return;
    }
    final created = result['import'] as DataImport;
    setState(() => _published = created);
    final polled = await _authed((t) => _service.waitForCompletion(
          accessToken: t,
          id: created.id,
          clock: widget.clock ?? DateTime.now,
          sleep: widget.sleep,
          cancelled: () => _stopPolling,
          onUpdate: (update) {
            if (mounted) setState(() => _published = update);
          },
        ));
    if (polled == null) return;
    setState(() {
      _busy = false;
      if (polled['success'] == true) {
        _published = polled['import'] as DataImport;
        _timedOut = polled['timedOut'] == true;
      } else {
        _error = polled['error'] as String?;
      }
    });
    _loadHistory();
  }

  /// After the server refused to publish, finds the import it saved anyway
  /// (the newest one, made after [since]) and shows its invalid rows.
  Future<void> _loadRejectedRows(DateTime since) async {
    final list = await _authed((t) => _service.list(accessToken: t, perPage: 1));
    if (list == null || list['success'] != true) return;
    final newest = (list['imports'] as List).cast<DataImport>().firstOrNull;
    final created = newest?.createdAt;
    if (newest == null ||
        created == null ||
        created.isBefore(since.subtract(const Duration(minutes: 1))) ||
        newest.status != 'pending') {
      return;
    }
    final rows = await _authed((t) => _service.rows(accessToken: t, id: newest.id, perPage: 100));
    if (rows == null || rows['success'] != true) return;
    setState(() {
      _rejectedRows =
          (rows['rows'] as List).cast<DataImportRow>().where((r) => !r.valid).toList();
    });
  }

  void _keepInBackground() {
    _stopPolling = true;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.dataInRunningInBackground)));
    _reset();
  }

  void _reset() {
    setState(() {
      _step = _Step.file;
      _busy = false;
      _error = null;
      _file = null;
      _bytes = null;
      _fileError = null;
      _preflight = null;
      _published = null;
      _timedOut = false;
      _rejectedRows = const [];
    });
    _loadHistory();
  }

  // UI.

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SureLargeTitleScaffold(
      title: l.dataInImportTitle,
      leading: manageBackLink(context),
      actions: [
        SureNavIconButton(
          icon: SureIcons.externalLink,
          semanticLabel: l.shellOpenOnWeb,
          onPressed: () => openWebFallback(context,
              title: l.dataInImportTitle, path: '/imports'),
        ),
      ],
      onRefresh: _loadHistory,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _historySection(context),
              _wizard(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Center(
                  child: DataInLinkButton(
                    label: l.dataInMoreTypesOnWeb,
                    icon: SureIcons.arrowUpRight,
                    onPressed: () => openWebFallback(context,
                        title: l.dataInImportTitle, path: '/imports/new'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _hMargin = EdgeInsets.symmetric(horizontal: 16);

  Widget _historySection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final history = _history;
    if (history == null && _historyLoading) {
      return const Padding(
        padding: EdgeInsets.all(SureSpacing.xxxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final Widget panel;
    if (history == null || (_historyFailed && history.isEmpty)) {
      panel = SurePanel(
        margin: _hMargin,
        child: SureEmptyState(
          key: const ValueKey('importHistoryError'),
          icon: SureIcons.circleAlert,
          title: l.dataInHistoryFailed,
          primaryLabel: l.dataInRetry,
          onPrimary: _loadHistory,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      );
    } else if (history.isEmpty) {
      panel = SurePanel(
        margin: _hMargin,
        child: SureEmptyState(
          key: const ValueKey('importHistoryEmpty'),
          icon: SureIcons.inbox,
          title: l.dataInHistoryEmpty,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
      );
    } else {
      panel = SurePanel.rows(
        margin: _hMargin,
        dividerIndent: SurePanel.iconRowDividerIndent,
        children: [
          for (final item in history)
            SureListRow(
              leading: _statusBadge(item),
              title: dataInTypeLabel(l, item.type),
              subtitle: [
                if (item.createdAt != null)
                  SureDates.shortOf(context, item.createdAt!.toLocal()),
                dataInStatusLabel(l, item.status),
                if (item.rowsCount != null) l.dataInRowCount(item.rowsCount!),
              ].join(' · '),
              showChevron: true,
              onTap: () => _showStatus(item),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SureSectionHeader(label: l.dataInHistoryHeader),
        panel,
      ],
    );
  }

  /// Decorative: the row or line next to it states the status in words.
  Widget _statusBadge(DataImport item) {
    final palette = SureColors.of(context).palette;
    if (item.isComplete) {
      return ManageIconBadge(icon: SureIcons.circleCheck, color: palette.success);
    }
    if (item.isFailed) {
      return ManageIconBadge(
          icon: SureIcons.circleAlert, color: palette.destructive);
    }
    if (item.inProgress) return const ManageIconBadge(icon: SureIcons.clock);
    return const ManageIconBadge(icon: SureIcons.circleDashed);
  }

  Future<void> _showStatus(DataImport item) async {
    await showSureSheet<void>(
      context: context,
      builder: (_) => _ImportStatusSheet(
        initial: item,
        load: () => _authed((t) => _service.show(accessToken: t, id: item.id)),
      ),
    );
  }

  Widget _wizard(BuildContext context) {
    final l = AppLocalizations.of(context);
    final titles = [
      l.dataInStepFile,
      l.dataInStepMap,
      l.dataInStepPreview,
      l.dataInStepPublish,
    ];
    final body = switch (_step) {
      _Step.file => _fileStep(context),
      _Step.map => _mapStep(context),
      _Step.preview => _previewStep(context),
      _Step.publish => _publishStep(context),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepIndicator(
          step: _step.index,
          count: titles.length,
          label: l.dataInStepOf(_step.index + 1, titles.length,
              titles[_step.index]),
        ),
        body,
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: ManageErrorText(_error!),
          ),
      ],
    );
  }

  Widget _buttons({VoidCallback? onBack, required String next, VoidCallback? onNext}) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          if (onBack != null) ...[
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: SureButton(
                  label: l.dataInBack,
                  variant: SureButtonVariant.outline,
                  fullWidth: true,
                  onPressed: _busy ? null : onBack,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: SureButton(
                label: next,
                fullWidth: true,
                loading: _busy,
                onPressed: _busy ? null : onNext,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A step's lead-in line in `textSecondary`.
  Widget _help(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: SureColors.of(context).palette.textSecondary,
          ),
        ),
      );

  Future<void> _pickAccount() async {
    final l = AppLocalizations.of(context);
    final picked = await showManageOptionSheet<String?>(
      context,
      title: l.dataInAccountLabel,
      selected: _accountId,
      options: [for (final a in _accounts) (a.id, a.name)],
    );
    if (picked != null && mounted) setState(() => _accountId = picked.value);
  }

  Widget _fileStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accounts = _accounts;
    final file = _file;
    final canContinue = file != null && _fileError == null && _accountId != null;
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _help(l.dataInFileHelp(formatByteSize(maxCsvImportBytes))),
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
                key: const ValueKey('importAccountRow'),
                title: l.dataInAccountLabel,
                value: account?.name ?? l.ds4dChoose,
                showChevron: true,
                onTap: _busy ? null : _pickAccount,
              ),
            DataInFileRow(
              file: file,
              chooseLabel: l.dataInChooseCsv,
              onTap: _busy ? null : _chooseFile,
            ),
          ],
        ),
        if (_fileError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: ManageErrorText(_fileError!),
          ),
        _buttons(
          next: l.dataInContinue,
          onNext: canContinue ? () => _runPreflight() : null,
        ),
      ],
    );
  }

  /// A panel row showing the chosen option's label; tapping opens a picker
  /// sheet of [options].
  Widget _optionRow<T>({
    required Key key,
    required String label,
    required T value,
    required List<ManageOption<T>> options,
    required ValueChanged<T> onChanged,
  }) {
    final current =
        options.where((o) => o.$1 == value).map((o) => o.$2).firstOrNull;
    return SureListRow(
      key: key,
      title: label,
      value: current ?? value?.toString(),
      showChevron: true,
      onTap: _busy
          ? null
          : () async {
              final picked = await showManageOptionSheet<T>(
                context,
                title: label,
                selected: value,
                options: options,
              );
              if (picked != null && mounted) onChanged(picked.value);
            },
    );
  }

  Widget _mapStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final preflight = _preflight!;
    final headers = preflight.headers;
    final columnLabels = {
      ImportColumn.date: l.dataInColumnDate,
      ImportColumn.amount: l.dataInColumnAmount,
      ImportColumn.name: l.dataInColumnName,
      ImportColumn.category: l.dataInColumnCategory,
      ImportColumn.tags: l.dataInColumnTags,
      ImportColumn.notes: l.dataInColumnNotes,
    };
    final ready = hasRequiredColumns(_mapping);
    // Missing-header errors refer to the server's default labels, which the
    // mapping below replaces, so only other errors are shown.
    final errors = preflight.errors
        .where((e) => !e.startsWith('Missing required columns'))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _help(l.dataInDetected(headers.length, preflight.rowsCount)),
        for (final e in errors)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: ManageErrorText(e),
          ),
        for (final w in preflight.warnings)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ManageNotice(w),
          ),
        SurePanel.rows(
          margin: _hMargin,
          children: [
            for (final column in ImportColumn.values)
              _optionRow<String?>(
                key: ValueKey('importMap-${column.param}'),
                label: column.required
                    ? l.dataInRequiredLabel(columnLabels[column]!)
                    : columnLabels[column]!,
                value: _mapping[column],
                options: [
                  (null, l.dataInColumnNone),
                  for (final h in headers) (h, h),
                ],
                onChanged: (v) => setState(() {
                  _mapping = {..._mapping, column: v};
                  if (column == ImportColumn.date && v != null) {
                    final detected = detectDateFormat(
                        columnValues(_records(maxRecords: 51), v));
                    if (detected != null) _dateFormat = detected;
                  }
                }),
              ),
          ],
        ),
        SureSectionHeader(label: l.ds4dFormatsHeader),
        SurePanel.rows(
          margin: _hMargin,
          children: [
            _optionRow<String>(
              key: const ValueKey('importDateFormat'),
              label: l.dataInDateFormat,
              value: _dateFormat,
              options: [for (final (label, v) in importDateFormats) (v, label)],
              onChanged: (v) => setState(() => _dateFormat = v),
            ),
            _optionRow<String>(
              key: const ValueKey('importNumberFormat'),
              label: l.dataInNumberFormat,
              value: _numberFormat,
              options: [for (final f in importNumberFormats) (f, f)],
              onChanged: (v) => setState(() => _numberFormat = v),
            ),
            _optionRow<String>(
              key: const ValueKey('importSignage'),
              label: l.dataInSignage,
              value: _signage,
              options: [
                ('inflows_positive', l.dataInSignagePositive),
                ('inflows_negative', l.dataInSignageNegative),
              ],
              onChanged: (v) => setState(() => _signage = v),
            ),
            _optionRow<String>(
              key: const ValueKey('importSeparator'),
              label: l.dataInSeparator,
              value: _colSep,
              options: [
                (',', l.dataInSeparatorComma),
                (';', l.dataInSeparatorSemicolon),
              ],
              onChanged: (v) {
                if (v == _colSep) return;
                setState(() => _colSep = v);
                _runPreflight(resetMapping: false);
              },
            ),
          ],
        ),
        if (!ready)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: ManageErrorText(l.dataInNeedDateAndAmount),
          ),
        _buttons(
          onBack: () => setState(() => _step = _Step.file),
          next: l.dataInContinue,
          onNext: ready ? () => setState(() => _step = _Step.preview) : null,
        ),
      ],
    );
  }

  Widget _previewStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final records = _records(maxRecords: _previewRows + 1);
    final header = records.isEmpty ? const <String>[] : records.first;
    String cell(List<String> row, ImportColumn column) {
      final name = _mapping[column];
      if (name == null) return '';
      final i = header.indexOf(name);
      return i >= 0 && i < row.length ? row[i].trim() : '';
    }

    final rows = records.skip(1).toList();
    var invalid = 0;
    final tiles = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final date = cell(row, ImportColumn.date);
      final amount = cell(row, ImportColumn.amount);
      final problems = [
        if (!dateMatchesFormat(date, _dateFormat)) l.dataInRowBadDate(date),
        if (!amountParses(amount, _numberFormat)) l.dataInRowBadAmount(amount),
      ];
      if (problems.isNotEmpty) invalid++;
      tiles.add(_PreviewRow(
        number: i + 1,
        title: cell(row, ImportColumn.name).isEmpty
            ? l.dataInRowUntitled
            : cell(row, ImportColumn.name),
        detail: [date, cell(row, ImportColumn.category)]
            .where((s) => s.isNotEmpty)
            .join(' · '),
        amount: amount,
        errors: problems,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _help(l.dataInPreviewSummary(
            rows.length, _preflight?.rowsCount ?? rows.length)),
        if (invalid > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ManageNotice(l.dataInPreviewInvalid(invalid)),
          ),
        if (_mapping[ImportColumn.category] != null ||
            _mapping[ImportColumn.tags] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ManageNotice(l.dataInCategoriesNote, info: true),
          ),
        if (tiles.isEmpty)
          SurePanel(
            margin: _hMargin,
            child: SureEmptyState(
              key: const ValueKey('importPreviewEmpty'),
              icon: SureIcons.inbox,
              title: l.dataInPreviewEmpty,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          )
        else
          SurePanel.rows(
            margin: _hMargin,
            dividerIndent: _PreviewRow.dividerIndent,
            children: tiles,
          ),
        _buttons(
          onBack: () => setState(() => _step = _Step.map),
          next: l.dataInPublish,
          onNext: tiles.isEmpty ? null : _publish,
        ),
      ],
    );
  }

  Widget _publishStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final item = _published;
    final status = <Widget>[];
    if (item == null && _busy) {
      status.add(_statusLine(
        leading: const SizedBox.square(
            dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        text: l.dataInUploading,
      ));
    } else if (item != null) {
      final done = item.isComplete;
      status.add(_statusLine(
        leading: _busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : _statusBadge(item),
        text: done ? l.dataInComplete : dataInStatusLabel(l, item.status),
      ));
      if (item.rowsCount != null) {
        status.add(Padding(
          padding: const EdgeInsets.only(top: 4, left: 40),
          child: Text(l.dataInRowCount(item.rowsCount!),
              style: TextStyle(fontSize: 13, color: palette.textSecondary)),
        ));
      }
      if (item.error != null) {
        status.add(Padding(
          padding: const EdgeInsets.only(top: 10),
          child: ManageErrorText(item.error!),
        ));
      }
    }
    if (_busy) {
      status.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            key: const ValueKey('importPublishProgress'),
            minHeight: 3,
            color: palette.textPrimary,
            backgroundColor: palette.surfaceInset,
          ),
        ),
      ));
    }
    final polling = _busy && item != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status.isNotEmpty)
          SurePanel(
            margin: _hMargin,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: status,
            ),
          ),
        if (_timedOut)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: ManageNotice(l.dataInStillRunning),
          ),
        if (_rejectedRows.isNotEmpty) ...[
          SureSectionHeader(label: l.dataInRejectedRows),
          SurePanel.rows(
            margin: _hMargin,
            dividerIndent: _PreviewRow.dividerIndent,
            children: [
              for (final row in _rejectedRows.take(_previewRows))
                _PreviewRow(
                  number: row.rowNumber,
                  title: row.name ?? l.dataInRowUntitled,
                  detail: row.date ?? '',
                  amount: row.amount ?? '',
                  errors: row.errors,
                ),
            ],
          ),
        ],
        if (polling)
          // Stays enabled while busy, unlike the shared button row.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DataInLinkButton(
                label: l.dataInKeepInBackground,
                icon: SureIcons.clock,
                onPressed: _keepInBackground,
              ),
            ),
          )
        else if (_error != null)
          _buttons(
            onBack: () => setState(() {
              _step = _Step.map;
              _error = null;
              _rejectedRows = const [];
            }),
            next: l.dataInStartOver,
            onNext: _reset,
          )
        else if (!_busy)
          _buttons(next: l.dataInImportAnother, onNext: _reset),
      ],
    );
  }

  Widget _statusLine({required Widget leading, required String text}) {
    final palette = SureColors.of(context).palette;
    return Row(
      children: [
        SizedBox(width: 28, child: Center(child: leading)),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A text link with a Lucide icon whose label wraps instead of overflowing,
/// for actions with long labels (SureButton keeps its label on one line).
class DataInLinkButton extends StatelessWidget {
  const DataInLinkButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;

  /// Lucide icon name.
  final String icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: palette.link,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      icon: SureIcon(icon,
          size: 16, color: onPressed == null ? palette.textSubdued : palette.link),
      label: Text(label, textAlign: TextAlign.start),
      onPressed: onPressed,
    );
  }
}

/// The file row of the import and statement forms: "Choose file" in the
/// link color until a file is picked, then its name and size with a
/// "Change file" link.
class DataInFileRow extends StatelessWidget {
  const DataInFileRow({
    super.key,
    required this.file,
    required this.chooseLabel,
    required this.onTap,
  });

  final PickedFileData? file;
  final String chooseLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final picked = file;
    return SureListRow(
      key: const ValueKey('dataInFileRow'),
      leading: ManageIconBadge(
        icon: picked == null ? SureIcons.cloudUpload : ManageIcons.receiptText,
        color: picked == null ? palette.link : null,
      ),
      title: picked?.name ?? chooseLabel,
      titleColor: picked == null ? palette.link : null,
      subtitle: picked == null ? null : formatByteSize(picked.size),
      trailing: picked == null
          ? null
          : Text(
              l.dataInChooseAnother,
              style: TextStyle(fontSize: 15, color: palette.link),
            ),
      onTap: onTap,
    );
  }
}

/// Localized name of an import `status`.
String dataInStatusLabel(AppLocalizations l, String status) => switch (status) {
      'pending' => l.dataInStatusPending,
      'importing' => l.dataInStatusImporting,
      'complete' => l.dataInStatusComplete,
      'failed' => l.dataInStatusFailed,
      'reverting' => l.dataInStatusReverting,
      'revert_failed' => l.dataInStatusRevertFailed,
      _ => status,
    };

/// Localized name of an import `type`.
String dataInTypeLabel(AppLocalizations l, String type) => switch (type) {
      'TransactionImport' => l.dataInTypeTransactions,
      'TradeImport' => l.dataInTypeTrades,
      'AccountImport' => l.dataInTypeAccounts,
      _ => type.endsWith('Import') ? type.substring(0, type.length - 6) : type,
    };

/// The slim step indicator: "Step 2 of 4: Map columns" over [count] short
/// bars, the ones up to [step] filled.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.step,
    required this.count,
    required this.label,
  });

  final int step;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      key: ValueKey('importStepBar-$i'),
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= step
                            ? palette.textPrimary
                            : palette.surfaceInset,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One CSV row in the preview (or one row the server rejected): the row
/// number, its name over date and category, the raw amount, and any
/// problems inline under it.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.number,
    required this.title,
    required this.detail,
    required this.amount,
    this.errors = const [],
  });

  /// Lines the dividers up with the title: 14 padding + 28 number + 8 gap.
  static const double dividerIndent = 50;

  final int number;
  final String title;
  final String detail;

  /// The amount as written in the file (not parsed, so not a MoneyText).
  final String amount;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final mono = SureMoney.tabular(
        TextStyle(fontSize: 13, color: palette.textSubdued));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('$number',
                  style: mono.copyWith(
                      color: errors.isEmpty
                          ? palette.textSubdued
                          : palette.destructive)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    if (amount.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.35),
                        child: Text(
                          amount,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SureMoney.tabular(TextStyle(
                            fontSize: 15,
                            height: 1.25,
                            color: palette.textPrimary,
                          )),
                        ),
                      ),
                    ],
                  ],
                ),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: palette.textSecondary),
                    ),
                  ),
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ManageErrorText(e, compact: true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Status of one import, refreshed from the server when opened.
class _ImportStatusSheet extends StatefulWidget {
  const _ImportStatusSheet({
    required this.initial,
    required this.load,
  });

  final DataImport initial;
  final Future<Map<String, dynamic>?> Function() load;

  @override
  State<_ImportStatusSheet> createState() => _ImportStatusSheetState();
}

class _ImportStatusSheetState extends State<_ImportStatusSheet> {
  late DataImport _item = widget.initial;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final result = await widget.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = result == null || result['success'] != true;
      if (!_failed) _item = result!['import'] as DataImport;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final item = _item;
    return SureSheet(
      title: dataInTypeLabel(l, item.type),
      showCancel: false,
      actionLabel: l.dsDone,
      onAction: () => Navigator.of(context).maybePop(),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurePanel.rows(
              children: [
                SureListRow(
                  key: const ValueKey('importStatusRow'),
                  title: l.dataInStatusLabel,
                  value: dataInStatusLabel(l, item.status),
                ),
                if (item.createdAt != null)
                  SureListRow(
                    title: l.dataInCreatedLabel,
                    value: SureDates.fullOf(context, item.createdAt!.toLocal()),
                  ),
                if (item.rowsCount != null)
                  SureListRow(title: l.dataInRowCount(item.rowsCount!)),
                if (item.invalidRowsCount != null && item.invalidRowsCount! > 0)
                  SureListRow(
                    title: l.dataInInvalidRowCount(item.invalidRowsCount!),
                    titleColor: palette.destructive,
                  ),
              ],
            ),
            if (item.error != null) ...[
              const SizedBox(height: 12),
              ManageErrorText(item.error!),
            ],
            if (_failed) ...[
              const SizedBox(height: 12),
              ManageErrorText(l.dataInStatusLoadFailed),
            ],
            SureButtonPanel(
              label: l.dataInRefresh,
              busy: _loading,
              margin: const EdgeInsets.only(top: 16),
              onPressed: _loading ? null : _refresh,
            ),
          ],
        ),
      ),
    );
  }
}
