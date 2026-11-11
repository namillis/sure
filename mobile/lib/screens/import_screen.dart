import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
import '../widgets/form_error_text.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_list_group.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(l.dataInImportTitle),
        actions: const [OpenOnWebAction(path: '/imports')],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: SureSpacing.huge),
          children: [
            _historySection(context),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SureSpacing.xl),
              child: SureCard(child: _wizard(context)),
            ),
            Padding(
              padding: const EdgeInsets.all(SureSpacing.xl),
              child: Center(
                child: DataInLinkButton(
                  label: l.dataInMoreTypesOnWeb,
                  icon: Icons.language,
                  onPressed: () => openWebFallback(context,
                      title: l.dataInImportTitle, path: '/imports/new'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _historySection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final history = _history;
    const margin = EdgeInsets.fromLTRB(
        SureSpacing.xl, SureSpacing.lg, SureSpacing.xl, SureSpacing.xl);
    if (history == null && _historyLoading) {
      return const Padding(
        padding: EdgeInsets.all(SureSpacing.xxxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (history == null || (_historyFailed && history.isEmpty)) {
      return Padding(
        padding: margin,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FormErrorText(l.dataInHistoryFailed),
            const SizedBox(height: SureSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: SureButton(
                label: l.dataInRetry,
                variant: SureButtonVariant.outline,
                onPressed: _loadHistory,
              ),
            ),
          ],
        ),
      );
    }
    if (history.isEmpty) {
      return Padding(
        padding: margin,
        child: Text(l.dataInHistoryEmpty,
            style: TextStyle(color: SureColors.of(context).palette.textSubdued)),
      );
    }
    return SureListGroup(
      header: l.dataInHistoryHeader,
      margin: margin,
      children: [
        for (final item in history)
          SureListRow(
            leading: Icon(_statusIcon(item), semanticLabel: dataInStatusLabel(l, item.status)),
            title: dataInTypeLabel(l, item.type),
            subtitle: [
              if (item.createdAt != null) _date(context, item.createdAt!),
              dataInStatusLabel(l, item.status),
              if (item.rowsCount != null) l.dataInRowCount(item.rowsCount!),
            ].join(' · '),
            showChevron: true,
            onTap: () => _showStatus(item),
          ),
      ],
    );
  }

  IconData _statusIcon(DataImport item) {
    if (item.isComplete) return Icons.check_circle_outline;
    if (item.isFailed) return Icons.error_outline;
    if (item.inProgress) return Icons.hourglass_top;
    return Icons.pending_outlined;
  }

  String _date(BuildContext context, DateTime date) =>
      DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
          .format(date.toLocal());

  Future<void> _showStatus(DataImport item) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ImportStatusSheet(
        initial: item,
        load: () => _authed((t) => _service.show(accessToken: t, id: item.id)),
        formatDate: (d) => _date(context, d),
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
    final theme = Theme.of(context);
    final body = switch (_step) {
      _Step.file => _fileStep(context),
      _Step.map => _mapStep(context),
      _Step.preview => _previewStep(context),
      _Step.publish => _publishStep(context),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(l.dataInStepOf(_step.index + 1, 4, titles[_step.index]),
              style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: SureSpacing.lg),
        body,
        if (_error != null) ...[
          const SizedBox(height: SureSpacing.lg),
          FormErrorText(_error!),
        ],
      ],
    );
  }

  Widget _buttons({VoidCallback? onBack, required String next, VoidCallback? onNext}) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: SureSpacing.xl),
      child: Row(
        children: [
          if (onBack != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: SureButton(
                label: l.dataInBack,
                variant: SureButtonVariant.outline,
                onPressed: _busy ? null : onBack,
              ),
            ),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: SureButton(
              label: next,
              loading: _busy,
              onPressed: _busy ? null : onNext,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accounts = _accounts;
    final file = _file;
    final canContinue = file != null && _fileError == null && _accountId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.dataInFileHelp(formatByteSize(maxCsvImportBytes)),
            style: TextStyle(color: palette.textSubdued)),
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
                DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _busy ? null : (v) => setState(() => _accountId = v),
          ),
        const SizedBox(height: SureSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: SureButton(
              label: file == null ? l.dataInChooseCsv : l.dataInChooseAnother,
              variant: SureButtonVariant.outline,
              leading: const Icon(Icons.upload_file, size: 16),
              onPressed: _busy ? null : _chooseFile,
            ),
          ),
        ),
        if (file != null) ...[
          const SizedBox(height: SureSpacing.md),
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 20),
              const SizedBox(width: SureSpacing.md),
              Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
              Text(formatByteSize(file.size), style: TextStyle(color: palette.textSubdued)),
            ],
          ),
        ],
        if (_fileError != null) ...[
          const SizedBox(height: SureSpacing.md),
          FormErrorText(_fileError!),
        ],
        _buttons(
          next: l.dataInContinue,
          onNext: canContinue ? () => _runPreflight() : null,
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<(T?, String)> options,
    required ValueChanged<T?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: SureSpacing.lg),
        child: DropdownButtonFormField<T>(
          key: ValueKey('$label-$value-${options.length}'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final (v, text) in options)
              DropdownMenuItem<T>(value: v, child: Text(text, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _busy ? null : onChanged,
        ),
      );

  Widget _mapStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
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
        Text(l.dataInDetected(headers.length, preflight.rowsCount),
            style: TextStyle(color: palette.textSubdued)),
        for (final e in errors) ...[
          const SizedBox(height: SureSpacing.md),
          FormErrorText(e),
        ],
        for (final w in preflight.warnings) ...[
          const SizedBox(height: SureSpacing.md),
          _Warning(w),
        ],
        const SizedBox(height: SureSpacing.lg),
        for (final column in ImportColumn.values)
          _dropdown<String>(
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
        _dropdown<String>(
          label: l.dataInDateFormat,
          value: _dateFormat,
          options: [for (final (label, v) in importDateFormats) (v, label)],
          onChanged: (v) => setState(() => _dateFormat = v ?? _dateFormat),
        ),
        _dropdown<String>(
          label: l.dataInNumberFormat,
          value: _numberFormat,
          options: [for (final f in importNumberFormats) (f, f)],
          onChanged: (v) => setState(() => _numberFormat = v ?? _numberFormat),
        ),
        _dropdown<String>(
          label: l.dataInSignage,
          value: _signage,
          options: [
            ('inflows_positive', l.dataInSignagePositive),
            ('inflows_negative', l.dataInSignageNegative),
          ],
          onChanged: (v) => setState(() => _signage = v ?? _signage),
        ),
        _dropdown<String>(
          label: l.dataInSeparator,
          value: _colSep,
          options: [
            (',', l.dataInSeparatorComma),
            (';', l.dataInSeparatorSemicolon),
          ],
          onChanged: (v) {
            if (v == null || v == _colSep) return;
            setState(() => _colSep = v);
            _runPreflight(resetMapping: false);
          },
        ),
        if (!ready) FormErrorText(l.dataInNeedDateAndAmount),
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
    final palette = SureColors.of(context).palette;
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
        detail: [date, amount, cell(row, ImportColumn.category)]
            .where((s) => s.isNotEmpty)
            .join(' · '),
        errors: problems,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.dataInPreviewSummary(rows.length, _preflight?.rowsCount ?? rows.length),
          style: TextStyle(color: palette.textSubdued),
        ),
        if (invalid > 0) ...[
          const SizedBox(height: SureSpacing.md),
          _Warning(l.dataInPreviewInvalid(invalid)),
        ],
        if (_mapping[ImportColumn.category] != null || _mapping[ImportColumn.tags] != null) ...[
          const SizedBox(height: SureSpacing.md),
          _Warning(l.dataInCategoriesNote),
        ],
        const SizedBox(height: SureSpacing.md),
        if (tiles.isEmpty) Text(l.dataInPreviewEmpty) else ...tiles,
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
    final theme = Theme.of(context);
    final item = _published;
    final children = <Widget>[];
    if (item == null && _busy) {
      children.add(Row(children: [
        const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: SureSpacing.lg),
        Expanded(child: Text(l.dataInUploading)),
      ]));
    } else if (item != null) {
      final done = item.isComplete;
      children.add(Row(children: [
        if (_busy)
          const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(_statusIcon(item)),
        const SizedBox(width: SureSpacing.lg),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              done ? l.dataInComplete : dataInStatusLabel(l, item.status),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ),
      ]));
      if (item.rowsCount != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: SureSpacing.md),
          child: Text(l.dataInRowCount(item.rowsCount!)),
        ));
      }
      if (item.error != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: SureSpacing.md),
          child: FormErrorText(item.error!),
        ));
      }
      if (_timedOut) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: SureSpacing.md),
          child: _Warning(l.dataInStillRunning),
        ));
      }
    }
    if (_rejectedRows.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: SureSpacing.lg),
        child: Text(l.dataInRejectedRows, style: theme.textTheme.titleSmall),
      ));
      for (final row in _rejectedRows.take(_previewRows)) {
        children.add(_PreviewRow(
          number: row.rowNumber,
          title: row.name ?? l.dataInRowUntitled,
          detail: [row.date, row.amount].whereType<String>().join(' · '),
          errors: row.errors,
        ));
      }
    }
    final polling = _busy && item != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        if (polling)
          // Stays enabled while busy, unlike the shared button row.
          Padding(
            padding: const EdgeInsets.only(top: SureSpacing.xl),
            child: Align(
              alignment: Alignment.centerRight,
              child: DataInLinkButton(
                label: l.dataInKeepInBackground,
                icon: Icons.schedule,
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
}

/// A text link with an icon whose label wraps instead of overflowing, for
/// actions with long labels (SureButton keeps its label on one line).
class DataInLinkButton extends StatelessWidget {
  const DataInLinkButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: palette.link,
        minimumSize: const Size(44, 44),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, textAlign: TextAlign.start),
      onPressed: onPressed,
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

class _Warning extends StatelessWidget {
  const _Warning(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = SureColors.of(context).palette.warning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 20, color: color),
        const SizedBox(width: SureSpacing.md),
        Expanded(child: Text(message)),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.number,
    required this.title,
    required this.detail,
    this.errors = const [],
  });

  final int number;
  final String title;
  final String detail;
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SureSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text('$number', style: TextStyle(color: palette.textSubdued)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (detail.isNotEmpty)
                  Text(detail,
                      style: theme.textTheme.bodySmall?.copyWith(color: palette.textSubdued)),
                for (final e in errors) FormErrorText(e),
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
    required this.formatDate,
  });

  final DataImport initial;
  final Future<Map<String, dynamic>?> Function() load;
  final String Function(DateTime) formatDate;

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
    final theme = Theme.of(context);
    final item = _item;
    String line(String label, String value) => '$label: $value';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            SureSpacing.xl, 0, SureSpacing.xl, SureSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dataInTypeLabel(l, item.type), style: theme.textTheme.titleMedium),
            const SizedBox(height: SureSpacing.md),
            Text(line(l.dataInStatusLabel, dataInStatusLabel(l, item.status))),
            if (item.createdAt != null)
              Text(line(l.dataInCreatedLabel, widget.formatDate(item.createdAt!))),
            if (item.rowsCount != null) Text(l.dataInRowCount(item.rowsCount!)),
            if (item.invalidRowsCount != null && item.invalidRowsCount! > 0)
              Text(l.dataInInvalidRowCount(item.invalidRowsCount!)),
            if (item.error != null) ...[
              const SizedBox(height: SureSpacing.md),
              FormErrorText(item.error!),
            ],
            if (_failed) ...[
              const SizedBox(height: SureSpacing.md),
              FormErrorText(l.dataInStatusLoadFailed),
            ],
            const SizedBox(height: SureSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: SureButton(
                label: l.dataInRefresh,
                variant: SureButtonVariant.outline,
                loading: _loading,
                onPressed: _loading ? null : _refresh,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
