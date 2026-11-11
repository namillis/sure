import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/transaction.dart';
import '../models/transaction_split.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/connectivity_service.dart';
import '../services/transaction_split_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/split_math.dart';
import '../widgets/ds/ds.dart';
import '../widgets/metadata_picker_sheet.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_text_field.dart';
import '../widgets/transaction_metadata_pickers.dart';

/// Splits [transaction] into parts, or edits the parts of an existing
/// [split]. Pops with `true` when the split was saved or removed.
///
/// [transaction] should be fresh from the server so its `amountDecimal` (the
/// exact stored total the parts must match) is known.
class TransactionSplitScreen extends StatefulWidget {
  const TransactionSplitScreen({
    super.key,
    required this.transaction,
    this.split,
    this.splitService,
    this.pickers,
  });

  final Transaction transaction;
  final TransactionSplit? split;
  final TransactionSplitService? splitService;
  final TransactionMetadataPickers? pickers;

  @override
  State<TransactionSplitScreen> createState() => _TransactionSplitScreenState();
}

class _SplitRow {
  _SplitRow({
    String name = '',
    String amount = '',
    this.categoryId,
    this.categoryLabel,
    this.merchantId,
    this.tagIds,
    this.excluded,
  })  : name = TextEditingController(text: name),
        amount = TextEditingController(text: amount);

  final TextEditingController name;
  final TextEditingController amount;
  String? categoryId;
  String? categoryLabel;

  // Carried through unchanged so replacing a split doesn't drop them.
  final String? merchantId;
  final List<String>? tagIds;
  final bool? excluded;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _TransactionSplitScreenState extends State<TransactionSplitScreen> {
  late final TransactionSplitService _service =
      widget.splitService ?? TransactionSplitService();
  late final TransactionMetadataPickers _pickers =
      widget.pickers ?? TransactionMetadataPickers();
  final List<_SplitRow> _rows = [];
  late final int _parentUnits = _resolveParentUnits();
  bool _saving = false;
  String? _error;
  bool _initialized = false;

  bool get _isExisting => widget.split != null;

  String get _currency => widget.split?.currency.isNotEmpty == true
      ? widget.split!.currency
      : widget.transaction.currency;

  int _resolveParentUnits() {
    final exact = SplitMath.toUnits(
      widget.transaction.amountDecimal ?? widget.split?.amountDecimal,
    );
    if (exact != null) return exact;
    // Servers that predate amount_decimal: the formatted amount is signed the
    // same way (income is negative).
    final parsed = InvestmentMath.parse(widget.transaction.amount) ?? 0;
    return SplitMath.toUnits(parsed.toStringAsFixed(SplitMath.scale)) ?? 0;
  }

  String _locale() =>
      Localizations.maybeLocaleOf(context)?.toString() ??
      Intl.getCurrentLocale();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final children = widget.split?.children ?? const <Transaction>[];
    for (final child in children) {
      final serverUnits = SplitMath.toUnits(child.amountDecimal) ??
          SplitMath.toUnits(
            (InvestmentMath.parse(child.amount) ?? 0)
                .toStringAsFixed(SplitMath.scale),
          ) ??
          0;
      _rows.add(
        _SplitRow(
          name: child.name,
          amount: SplitMath.toEditText(
            SplitMath.toTypedUnits(serverUnits,
                parentServerUnits: _parentUnits),
            locale: _locale(),
          ),
          categoryId: child.categoryId,
          categoryLabel: child.categoryName,
          merchantId: child.merchantId,
          tagIds: child.tagIds,
          excluded: child.excluded,
        ),
      );
    }
    while (_rows.length < SplitMath.minRows) {
      _rows.add(_SplitRow());
    }
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  List<int?> get _typedParts => [
        for (final row in _rows)
          SplitMath.parseTyped(row.amount.text, locale: _locale()),
      ];

  SplitCheck get _check =>
      SplitMath.check(parentServerUnits: _parentUnits, typedParts: _typedParts);

  String _money(int units, {required bool hidden}) => MoneyMasker.mask(
        _formatUnits(units),
        hidden: hidden,
      );

  String _formatUnits(int units) {
    final formatted = InvestmentMath.formatMoney(
      SplitMath.toDouble(units),
      currency: _currency,
      locale: _locale(),
    );
    // A sub-cent difference would round to "0.00"; show it exactly instead.
    final rounded = InvestmentMath.parse(formatted) ?? 0;
    if (units != 0 && rounded == 0) {
      return '${SplitMath.fromUnits(units)} $_currency';
    }
    return formatted;
  }

  void _addRow() => setState(() => _rows.add(_SplitRow()));

  void _removeRow(int index) {
    final removed = _rows[index];
    setState(() => _rows.removeAt(index));
    // Dispose once the row's fields have left the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  void _fillRemaining(int index) {
    final parts = _typedParts;
    parts[index] = null;
    final check =
        SplitMath.check(parentServerUnits: _parentUnits, typedParts: parts);
    if (check.remainingUnits == 0) return;
    setState(() {
      _rows[index].amount.text =
          SplitMath.toEditText(check.remainingUnits, locale: _locale());
    });
  }

  Future<void> _pickCategory(int index, bool online) async {
    final row = _rows[index];
    final picked = await _pickers.pickCategory(
      context,
      online: online,
      selectedId: row.categoryId,
      extraOptions: [
        if (row.categoryId != null && row.categoryLabel != null)
          PickerOption(id: row.categoryId!, label: row.categoryLabel!),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      row.categoryId = picked.id;
      row.categoryLabel = picked.label;
    });
  }

  String? _categoryLabel(_SplitRow row, CategoriesProvider categories) {
    if (row.categoryId == null) return null;
    for (final category in categories.categories) {
      if (category.id == row.categoryId) return category.displayName;
    }
    return row.categoryLabel;
  }

  Future<String?> _token() async {
    final token = await context.read<AuthProvider>().getValidAccessToken();
    if (token == null && mounted) {
      setState(() =>
          _error = AppLocalizations.of(context).transactionEditSessionExpired);
    }
    return token;
  }

  Future<void> _handleResult(
    Map<String, dynamic> result, {
    required String successMessage,
  }) async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = result['error'] == 'unauthorized'
          ? l.transactionEditSessionExpired
          : result['error']?.toString() ?? l.transactionEditUpdateFailed;
    });
    if (result['error'] == 'unauthorized') {
      await context.read<AuthProvider>().logout();
    }
  }

  Future<void> _save() async {
    final transactionId = widget.transaction.id;
    final parts = _typedParts;
    if (transactionId == null || !_check.isValid || _saving) return;
    final l = AppLocalizations.of(context);

    setState(() {
      _saving = true;
      _error = null;
    });
    final token = await _token();
    if (token == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    final payload = [
      for (var i = 0; i < _rows.length; i++)
        SplitPart(
          amount: SplitMath.fromUnits(
            SplitMath.toServerUnits(parts[i]!, parentServerUnits: _parentUnits),
          ),
          name: _rows[i].name.text,
          categoryId: _rows[i].categoryId,
          merchantId: _rows[i].merchantId,
          tagIds: _rows[i].tagIds,
          excluded: _rows[i].excluded,
        ),
    ];

    final result = _isExisting
        ? await _service.updateSplit(
            accessToken: token,
            transactionId: transactionId,
            parts: payload,
          )
        : await _service.createSplit(
            accessToken: token,
            transactionId: transactionId,
            parts: payload,
          );
    await _handleResult(result, successMessage: l.txnDetailSplitSaved);
  }

  Future<void> _remove() async {
    final transactionId = widget.transaction.id;
    if (transactionId == null || _saving) return;
    final l = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.txnDetailSplitRemoveConfirmTitle),
        content: Text(l.txnDetailSplitRemoveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.txnDetailSplitRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final token = await _token();
    if (token == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final result = await _service.deleteSplit(
      accessToken: token,
      transactionId: transactionId,
    );
    await _handleResult(result, successMessage: l.txnDetailSplitRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    final online = context.watch<ConnectivityService>().isOnline;
    final categories = context.watch<CategoriesProvider>();
    final check = _check;
    final enabled = !_saving;

    final Widget status;
    if (check.balanced) {
      status = Row(
        children: [
          SureIcon(SureIcons.circleCheck, color: palette.success, size: 20),
          const SizedBox(width: SureSpacing.md),
          Expanded(child: Text(l.txnDetailSplitBalanced)),
        ],
      );
    } else {
      final over = check.remainingUnits < 0;
      final amount = _money(check.remainingUnits.abs(), hidden: hidden);
      status = Row(
        children: [
          SureIcon(
            over ? SureIcons.circleAlert : SureIcons.clock,
            color: over ? palette.destructive : palette.warning,
            size: 20,
          ),
          const SizedBox(width: SureSpacing.md),
          Expanded(
            child: Text(
              over
                  ? l.txnDetailSplitOver(amount)
                  : l.txnDetailSplitRemaining(amount),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(title: Text(l.txnDetailSplitTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SureSpacing.xl),
          children: [
            SurePanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.transaction.name,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: SureSpacing.xs),
                  Text(
                    l.txnDetailSplitTotal(
                      _money(_parentUnits.abs(), hidden: hidden),
                    ),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: palette.textSecondary),
                  ),
                  const SizedBox(height: SureSpacing.lg),
                  Semantics(liveRegion: true, child: status),
                  const SizedBox(height: SureSpacing.sm),
                  Text(
                    l.txnDetailSplitSignHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: palette.textSubdued),
                  ),
                ],
              ),
            ),
            if (!online) ...[
              const SizedBox(height: SureSpacing.lg),
              Text(
                l.txnDetailSplitOffline,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: palette.warning),
              ),
            ],
            const SizedBox(height: SureSpacing.xl),
            for (var i = 0; i < _rows.length; i++) ...[
              KeyedSubtree(
                key: ObjectKey(_rows[i]),
                child: _buildRow(
                    i, l, palette, theme, categories, hidden, online, enabled),
              ),
              const SizedBox(height: SureSpacing.lg),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled ? _addRow : null,
                icon: SureIcon(SureIcons.plus, size: 18, color: palette.link),
                label: Text(l.txnDetailSplitAddRow),
              ),
            ),
            if (!check.hasEnoughRows)
              Text(
                l.txnDetailSplitNeedTwo,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              ),
            if (_error != null) ...[
              const SizedBox(height: SureSpacing.lg),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: palette.destructive),
                ),
              ),
            ],
            const SizedBox(height: SureSpacing.xl),
            SureButton(
              label: l.txnDetailSplitSave,
              fullWidth: true,
              size: SureButtonSize.lg,
              loading: _saving,
              onPressed: online && check.isValid && enabled ? _save : null,
            ),
            if (_isExisting) ...[
              const SizedBox(height: SureSpacing.lg),
              SureButton(
                label: l.txnDetailSplitRemove,
                fullWidth: true,
                size: SureButtonSize.lg,
                variant: SureButtonVariant.destructive,
                onPressed: online && enabled ? _remove : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    int index,
    AppLocalizations l,
    SureTokenPalette palette,
    ThemeData theme,
    CategoriesProvider categories,
    bool hidden,
    bool online,
    bool enabled,
  ) {
    final row = _rows[index];
    final isLast = index == _rows.length - 1;
    final categoryLabel = _categoryLabel(row, categories);

    return SurePanel(
      padding: const EdgeInsets.fromLTRB(14, 4, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.txnDetailSplitPartLabel(index + 1),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: l.txnDetailSplitRemoveRow,
                icon: SureIcon(SureIcons.trash,
                    size: 18, color: palette.textSecondary),
                onPressed: enabled && _rows.length > 1
                    ? () => _removeRow(index)
                    : null,
              ),
            ],
          ),
          SureTextField(
            controller: row.name,
            label: l.txnDetailSplitRowName,
            hint: widget.transaction.name,
            enabled: enabled,
            maxLength: 255,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: SureSpacing.md),
          SureTextField(
            controller: row.amount,
            label: l.transactionFormAmountLabel,
            enabled: enabled,
            obscureText: hidden,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            textInputAction:
                isLast ? TextInputAction.done : TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (value) {
              final units =
                  SplitMath.parseTyped(value ?? '', locale: _locale());
              return units == null || units == 0
                  ? l.txnDetailSplitInvalidAmount
                  : null;
            },
            onChanged: (_) => setState(() {}),
            suffixIcon: IconButton(
              tooltip: l.txnDetailSplitUseRemaining,
              icon: SureIcon(SureIcons.arrowDown,
                  size: 18, color: palette.textSecondary),
              onPressed: enabled ? () => _fillRemaining(index) : null,
            ),
          ),
          const SizedBox(height: SureSpacing.md),
          Semantics(
            button: true,
            label: l.transactionEditCategoryLabel,
            child: InkWell(
              onTap: enabled ? () => _pickCategory(index, online) : null,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    SureIcon(SureIcons.shapes,
                        size: 20, color: palette.textSecondary),
                    const SizedBox(width: SureSpacing.lg),
                    Expanded(
                      child: Text(
                        categoryLabel ?? l.transactionEditNoCategory,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: categoryLabel == null
                              ? palette.textSubdued
                              : palette.textPrimary,
                        ),
                      ),
                    ),
                    SureIcon(SureIcons.chevronRight,
                        size: 18, color: palette.textSubdued),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
