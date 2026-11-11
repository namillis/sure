import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/category.dart' as models;
import '../models/offline_transaction.dart';
import '../models/transaction.dart';
import '../models/transaction_split.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/merchants_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/tags_provider.dart';
import '../providers/transactions_provider.dart';
import '../l10n/app_localizations.dart';
import '../services/connectivity_service.dart';
import '../services/transaction_split_service.dart';
import '../services/transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/amount_parser.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/split_math.dart';
import '../utils/transaction_amount_display.dart';
import '../widgets/ds/ds.dart';
import '../widgets/metadata_picker_sheet.dart';
import '../widgets/transaction_metadata_pickers.dart';
import 'transaction_split_screen.dart';
import 'web_view_screen.dart';

/// Edits one synced transaction: name, date, type, amount, category,
/// merchant, tags, notes and its split, and deletes it. Pops with `true` when
/// anything was saved (including a split change or a delete), so the caller
/// can reload.
///
/// Laid out as the redesign's transaction sheet: a centered hero (category
/// icon, name, amount, "Nov 6 · Account"), then panels for the category (and
/// split lines), merchant / tags / notes / date, recurring / web, and delete.
/// [showTransactionSheet] presents it as a bottom sheet ([asSheet]); pushed as
/// a route it shows the same content under an app bar with Save.
///
/// Edits are online-only, as before: the offline queue holds creates and
/// deletes, not updates.
class TransactionEditScreen extends StatefulWidget {
  final OfflineTransaction transaction;

  /// Render as the body of a Sure sheet (grabber, Cancel / Save toolbar)
  /// instead of a full page.
  final bool asSheet;

  /// Called when something was saved, split or deleted, before the screen
  /// pops. Lets a sheet's caller learn about a change even when the sheet is
  /// dismissed by a drag.
  final VoidCallback? onChanged;

  /// Overrides for tests.
  final TransactionsService? transactionsService;
  final TransactionSplitService? splitService;

  const TransactionEditScreen({
    super.key,
    required this.transaction,
    this.asSheet = false,
    this.onChanged,
    this.transactionsService,
    this.splitService,
  });

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  static const _maxNameLength = 255;
  static const _maxNotesLength = 2000;

  final _formKey = GlobalKey<FormState>();
  late final TransactionsService _transactionsService =
      widget.transactionsService ?? TransactionsService();
  late final TransactionSplitService _splitService =
      widget.splitService ?? TransactionSplitService();
  final _pickers = TransactionMetadataPickers();

  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late final TextEditingController _amountController;
  String _initialAmountText = '';
  late String _date;
  late String _nature;
  bool _editingAmount = false;

  String? _selectedCategoryId;
  String? _selectedCategoryLabel;
  String? _selectedMerchantId;
  String? _selectedMerchantLabel;
  late List<String> _selectedTagIds;
  final Map<String, String> _tagLabels = {};

  /// The transaction as the server has it now: carries `amount_decimal`,
  /// `split_parent` and `entry_id`, which the local cache doesn't store.
  Transaction? _fresh;
  TransactionSplit? _split;
  bool _loadingDetails = false;
  String? _splitError;
  bool _splitChanged = false;

  bool _isSaving = false;
  bool _isDeleting = false;
  String? _error;

  OfflineTransaction get _txn => widget.transaction;
  bool get _isSplitParent => _fresh?.splitParent == true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _txn.name);
    _notesController = TextEditingController(text: _txn.notes ?? '');
    _amountController = TextEditingController();
    _date = _txn.date;
    _nature = _txn.nature;
    _selectedCategoryId = _txn.categoryId;
    _selectedCategoryLabel = _txn.categoryName;
    _selectedMerchantId = _txn.merchantId;
    _selectedMerchantLabel = _txn.merchantName;
    _selectedTagIds = [..._txn.tagIds];
    for (var i = 0; i < _txn.tagIds.length; i++) {
      final name = i < _txn.tagNames.length ? _txn.tagNames[i] : '';
      if (name.isNotEmpty) _tagLabels[_txn.tagIds[i]] = name;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _amountController.text = _initialAmountText = SplitMath.toEditText(
        _amountUnits(_txn).abs(),
        locale: _locale(),
      );
      _loadMetadata();
      _loadDetails();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _locale() =>
      Localizations.maybeLocaleOf(context)?.toString() ??
      Intl.getCurrentLocale();

  /// The stored amount in units, positive = outflow.
  int _amountUnits(Transaction transaction) {
    final exact = SplitMath.toUnits(transaction.amountDecimal);
    if (exact != null) return exact;
    final parsed = InvestmentMath.parse(transaction.amount) ?? 0;
    return SplitMath.toUnits(parsed.toStringAsFixed(SplitMath.scale)) ?? 0;
  }

  Future<void> _loadMetadata() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final categoriesProvider = Provider.of<CategoriesProvider>(
      context,
      listen: false,
    );
    final merchantsProvider = Provider.of<MerchantsProvider>(
      context,
      listen: false,
    );
    final tagsProvider = Provider.of<TagsProvider>(context, listen: false);
    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken == null || !mounted) return;

    try {
      await Future.wait([
        categoriesProvider.fetchCategories(accessToken: accessToken),
        merchantsProvider.fetchMerchants(accessToken: accessToken),
        tagsProvider.fetchTags(accessToken: accessToken),
      ]);
    } catch (_) {
      // Providers expose their own error state; avoid an uncaught async error.
    }
  }

  /// Fetches the server's copy of the transaction and, when it is split, the
  /// split. Skipped offline; the screen then works from the cached copy.
  Future<void> _loadDetails() async {
    final id = _txn.id;
    if (id == null || !mounted) return;
    if (!context.read<ConnectivityService>().isOnline) return;

    setState(() {
      _loadingDetails = true;
      _splitError = null;
    });
    final l = AppLocalizations.of(context);
    final token = await context.read<AuthProvider>().getValidAccessToken();
    if (token == null || !mounted) {
      if (mounted) setState(() => _loadingDetails = false);
      return;
    }

    final result = await _transactionsService.getTransaction(
      accessToken: token,
      transactionId: id,
    );
    if (!mounted) return;
    final fresh = result['transaction'];
    TransactionSplit? split;
    String? splitError;
    if (fresh is Transaction && fresh.splitParent == true) {
      final splitResult =
          await _splitService.getSplit(accessToken: token, transactionId: id);
      if (!mounted) return;
      if (splitResult['success'] == true) {
        split = splitResult['split'] as TransactionSplit;
      } else if (splitResult['notSplit'] != true) {
        splitError = l.txnDetailSplitLoadFailed;
      }
    }

    setState(() {
      _loadingDetails = false;
      if (fresh is Transaction) {
        _fresh = fresh;
        // Show the exact stored amount unless the user already typed one.
        if (_amountController.text == _initialAmountText) {
          _amountController.text = _initialAmountText = SplitMath.toEditText(
            _amountUnits(fresh).abs(),
            locale: _locale(),
          );
        }
      } else {
        splitError = l.txnDetailSplitLoadFailed;
      }
      _split = split;
      _splitError = splitError;
    });
  }

  Future<void> _openSplit() async {
    final fresh = _fresh;
    if (fresh == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionSplitScreen(
          transaction: fresh,
          split: _split,
          splitService: _splitService,
          pickers: _pickers,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() => _splitChanged = true);
      widget.onChanged?.call();
      await _loadDetails();
    }
  }

  void _openWeb(String title, String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewScreen(title: title, path: path),
      ),
    );
  }

  void _close() => Navigator.of(context).pop(_splitChanged ? true : null);

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate() || _txn.id == null) {
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final transactionsProvider = Provider.of<TransactionsProvider>(
      context,
      listen: false,
    );
    final accessToken = await authProvider.getValidAccessToken();

    if (accessToken == null) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = l.transactionEditSessionExpired;
      });
      return;
    }

    // Empty notes intentionally clear the server-side note.
    final notesText = _notesController.text.trim();

    // A split parent's amount, date and type belong to the split; the server
    // refuses them even unchanged, so they are only sent when edited.
    String? date;
    String? amount;
    String? nature;
    if (!_isSplitParent) {
      if (_date != _txn.date) date = _date;
      final amountChanged = _amountController.text != _initialAmountText;
      if (amountChanged || _nature != _txn.nature) {
        amount = AmountParser.canonicalize(
          _amountController.text,
          locale: _locale(),
        ).replaceFirst('-', '');
        nature = _nature;
      }
    }

    final success = await transactionsProvider.updateTransaction(
      accessToken: accessToken,
      transaction: _txn,
      name: _nameController.text.trim(),
      notes: notesText,
      categoryId: _selectedCategoryId,
      merchantId: _selectedMerchantId,
      tagIds: _selectedTagIds,
      date: date,
      amount: amount,
      nature: nature,
    );

    if (!mounted) return;

    if (success) {
      SureHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.transactionEditUpdated)),
      );
      widget.onChanged?.call();
      Navigator.pop(context, true);
      return;
    }

    final error = transactionsProvider.error;
    setState(() {
      _isSaving = false;
      _error = error == 'unauthorized'
          ? l.transactionEditSessionExpired
          : error ?? l.transactionEditUpdateFailed;
    });
    if (error == 'unauthorized') await authProvider.logout();
  }

  Future<void> _delete() async {
    final id = _txn.id;
    if (id == null || _isDeleting || _isSaving) return;
    final l = AppLocalizations.of(context);
    final authProvider = context.read<AuthProvider>();
    final transactionsProvider = context.read<TransactionsProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return AlertDialog(
          title: Text(dl.transactionsListDeleteTitle),
          content: Text(dl.transactionsListDeleteSingleContent(_txn.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: palette.destructive),
              child: Text(dl.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });
    final token = await authProvider.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      setState(() {
        _isDeleting = false;
        _error = l.transactionEditSessionExpired;
      });
      return;
    }

    final success = await transactionsProvider.deleteTransaction(
      accessToken: token,
      transactionId: id,
    );
    if (!mounted) return;
    if (success) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.transactionsListDeletedSuccess)),
      );
      widget.onChanged?.call();
      Navigator.pop(context, true);
      return;
    }

    final error = transactionsProvider.error;
    setState(() {
      _isDeleting = false;
      _error = error == 'unauthorized'
          ? l.transactionEditSessionExpired
          : l.transactionsListSingleDeleteFailed;
    });
    if (error == 'unauthorized') await authProvider.logout();
  }

  String? _validateName(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return l.transactionEditNameRequired;
    }

    if (value.trim().length > _maxNameLength) {
      return l.transactionEditNameMaxLength(_maxNameLength);
    }

    if (_containsControlCharacter(value)) {
      return l.transactionEditNameInvalidChars;
    }

    return null;
  }

  String? _validateNotes(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    if (value.trim().length > _maxNotesLength) {
      return l.transactionEditNotesMaxLength(_maxNotesLength);
    }

    if (_containsControlCharacter(value, allowWhitespace: true)) {
      return l.transactionEditNotesInvalidChars;
    }

    return null;
  }

  String? _validateAmount(String? value) {
    final l = AppLocalizations.of(context);
    if (_isSplitParent) return null;
    if (value == null || value.trim().isEmpty) {
      return l.transactionFormAmountRequiredPrompt;
    }
    final double amount;
    try {
      amount = AmountParser.parse(value, locale: _locale()).value;
    } on FormatException {
      return l.transactionFormAmountInvalidNumber;
    }
    if (amount <= 0) return l.transactionFormAmountTooSmall;
    return null;
  }

  bool _containsControlCharacter(
    String value, {
    bool allowWhitespace = false,
  }) {
    for (final codeUnit in value.codeUnits) {
      if (codeUnit == 127) return true;
      if (codeUnit < 32) {
        final allowedWhitespace = allowWhitespace &&
            (codeUnit == 9 || codeUnit == 10 || codeUnit == 13);
        if (!allowedWhitespace) return true;
      }
    }

    return false;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_date) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
  }

  Future<void> _pickCategory(bool online) async {
    final picked = await _pickers.pickCategory(
      context,
      online: online,
      selectedId: _selectedCategoryId,
      extraOptions: [
        if (_selectedCategoryId != null)
          PickerOption(
            id: _selectedCategoryId!,
            label: _selectedCategoryLabel ??
                AppLocalizations.of(context).transactionEditCurrentCategory,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedCategoryId = picked.id;
      _selectedCategoryLabel = picked.label;
    });
  }

  Future<void> _pickMerchant(bool online) async {
    final picked = await _pickers.pickMerchant(
      context,
      online: online,
      selectedId: _selectedMerchantId,
      extraOptions: [
        if (_selectedMerchantId != null)
          PickerOption(
            id: _selectedMerchantId!,
            label: _selectedMerchantLabel ??
                AppLocalizations.of(context).transactionEditCurrentMerchant,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedMerchantId = picked.id;
      _selectedMerchantLabel = picked.label;
    });
  }

  Future<void> _pickTags(bool online) async {
    final l = AppLocalizations.of(context);
    final picked = await _pickers.pickTags(
      context,
      online: online,
      selectedIds: _selectedTagIds.toSet(),
      extraOptions: [
        for (final id in _selectedTagIds)
          PickerOption(
              id: id, label: _tagLabels[id] ?? l.transactionEditUnknownTag),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedTagIds = [for (final option in picked) option.id];
      for (final option in picked) {
        _tagLabels[option.id] = option.label;
      }
    });
  }

  models.Category? _category(CategoriesProvider provider, String? id) {
    if (id == null) return null;
    for (final category in provider.categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  String? _categoryLabel(CategoriesProvider provider) {
    if (_selectedCategoryId == null) return null;
    return _category(provider, _selectedCategoryId)?.displayName ??
        _selectedCategoryLabel ??
        AppLocalizations.of(context).transactionEditCurrentCategory;
  }

  String? _merchantLabel(MerchantsProvider provider) {
    if (_selectedMerchantId == null) return null;
    for (final merchant in provider.merchants) {
      if (merchant.id == _selectedMerchantId) return merchant.name;
    }
    return _selectedMerchantLabel ??
        AppLocalizations.of(context).transactionEditCurrentMerchant;
  }

  String _tagLabel(String id, TagsProvider provider) {
    for (final tag in provider.tags) {
      if (tag.id == id) return tag.name;
    }
    return _tagLabels[id] ??
        AppLocalizations.of(context).transactionEditUnknownTag;
  }

  String _formatDate(String date) {
    final parsed = SureDates.parseDay(date);
    if (parsed == null) return date;
    return SureDates.shortOf(context, parsed);
  }

  Account? _account() {
    try {
      final accounts = context.watch<AccountsProvider>().accounts;
      for (final Account account in accounts) {
        if (account.id == _txn.accountId) return account;
      }
    } on ProviderNotFoundException {
      // No accounts provider above this screen.
    }
    return null;
  }

  /// Signed amount text and color, the way the transaction row shows it:
  /// expenses with a minus in `textPrimary`, income with a plus in `success`.
  /// The account decides the sign convention; an unknown account is read as
  /// an asset, like most accounts.
  ({String text, MoneyTrend trend, Color color}) _amountDisplay(
    String amount,
    Account? account,
    SureTokenPalette palette,
  ) {
    final display = TransactionAmountDisplay.of(
      amount,
      isAsset: account == null || account.isAsset,
      isLiability: account?.isLiability ?? false,
    );
    return switch (display.trend) {
      MoneyTrend.inflow => (
          text: '+${display.text}',
          trend: display.trend,
          color: palette.success,
        ),
      MoneyTrend.outflow => (
          text: display.text,
          trend: display.trend,
          color: palette.textPrimary,
        ),
      MoneyTrend.neutral => (
          text: display.text,
          trend: display.trend,
          color: palette.textSubdued,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final online = context.watch<ConnectivityService>().isOnline;
    final categories = context.watch<CategoriesProvider>();
    final merchants = context.watch<MerchantsProvider>();
    final tags = context.watch<TagsProvider>();

    final canEdit = _txn.id != null && _txn.syncStatus == SyncStatus.synced;
    final busy = _isSaving || _isDeleting;
    final enabled = canEdit && !busy;
    final financialEnabled = enabled && !_isSplitParent;
    final account = _account();

    final form = Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!canEdit)
              SureBanner(
                message: l.transactionEditSyncedOnly,
                icon: SureIcons.info,
                margin: const EdgeInsets.only(bottom: 12),
              )
            else if (!online)
              SureBanner(
                message: l.txnDetailOfflineNote,
                icon: SureIcons.cloudOff,
                margin: const EdgeInsets.only(bottom: 12),
              ),
            _buildHero(l, palette, categories, hidden, account, enabled,
                financialEnabled),
            const SizedBox(height: 20),
            _buildCategoryPanel(
                l, palette, categories, hidden, account, online, enabled),
            const SizedBox(height: 16),
            _buildDetailsPanel(
                l, palette, merchants, tags, online, enabled, financialEnabled),
            const SizedBox(height: 16),
            _buildWebPanel(l, palette, online),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: palette.destructive),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildDeletePanel(l, palette),
          ],
        ),
      ),
    );

    final Widget content;
    if (widget.asSheet) {
      content = SureSheet(
        onCancel: _close,
        actionLabel: l.dsSave,
        onAction: _save,
        actionEnabled: enabled,
        busy: _isSaving,
        child: form,
      );
    } else {
      content = Scaffold(
        backgroundColor: palette.surface,
        appBar: AppBar(
          title: Text(l.txnDetail),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: enabled ? _save : null,
                style: TextButton.styleFrom(foregroundColor: palette.link),
                child: Text(
                  l.dsSave,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(child: form),
      );
    }

    return PopScope(
      // After a split change the caller must reload even if nothing else is
      // saved, so report it on the way out.
      canPop: !_splitChanged,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: content,
    );
  }

  Widget _buildHero(
    AppLocalizations l,
    SureTokenPalette palette,
    CategoriesProvider categories,
    bool hidden,
    Account? account,
    bool enabled,
    bool financialEnabled,
  ) {
    final category = _category(categories, _selectedCategoryId);
    final Widget icon = _isSplitParent
        ? const SureCategoryIcon.split(size: SureCategoryIcon.heroSize)
        : SureCategoryIcon(
            name: category?.name ??
                (_selectedCategoryId == null ? null : _selectedCategoryLabel),
            color: category?.color,
            icon: category?.icon,
            size: SureCategoryIcon.heroSize,
          );

    final details = [
      _formatDate(_date),
      if (account != null && account.name.isNotEmpty) account.name,
    ].join(' · ');

    final heroAmountStyle = TextStyle(
      fontSize: 32,
      height: 1.15,
      fontWeight: FontWeight.w600,
      color: palette.textPrimary,
    );

    final Widget amount;
    if (_editingAmount && financialEnabled) {
      amount = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SureSegmentedControl<String>(
            selected: _nature,
            onChanged: (value) => setState(() => _nature = value),
            segments: [
              SureSegment(
                value: 'expense',
                label: l.transactionFormTypeExpense,
                icon: const SureIcon(SureIcons.arrowDown, size: 16),
              ),
              SureSegment(
                value: 'income',
                label: l.transactionFormTypeIncome,
                icon: const SureIcon(SureIcons.arrowUp, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('transaction-amount-field'),
            controller: _amountController,
            autofocus: true,
            enabled: financialEnabled,
            obscureText: hidden,
            validator: _validateAmount,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            style: SureMoney.tabular(heroAmountStyle),
            decoration: _inlineDecoration(
              palette,
              hint: l.transactionFormAmountLabel,
              suffix: _txn.currency,
            ),
          ),
        ],
      );
    } else {
      final display = _amountDisplay(_txn.amount, account, palette);
      final shown = MoneyMasker.mask(display.text, hidden: hidden);
      amount = Semantics(
        button: financialEnabled,
        label: financialEnabled ? l.dstEditAmount : shown,
        value: financialEnabled ? shown : null,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: financialEnabled
              ? () => setState(() => _editingAmount = true)
              : null,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MoneyText(
              shown,
              trend: display.trend,
              color: display.color,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: heroAmountStyle,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(child: icon),
        const SizedBox(height: 10),
        TextFormField(
          key: const ValueKey('transaction-name-field'),
          controller: _nameController,
          enabled: enabled,
          validator: _validateName,
          maxLength: _maxNameLength,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
          decoration: _inlineDecoration(
            palette,
            hint: l.transactionEditNameLabel,
          ),
        ),
        const SizedBox(height: 2),
        amount,
        if (_isSplitParent) ...[
          const SizedBox(height: 4),
          Text(
            l.txnDetailSplitLockedFields,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: palette.textSubdued),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          details,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: palette.textSecondary),
        ),
      ],
    );
  }

  /// A borderless field that reads as text until focused; errors still show
  /// under it.
  InputDecoration _inlineDecoration(
    SureTokenPalette palette, {
    required String hint,
    String? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: palette.textSubdued),
      isDense: true,
      filled: false,
      counterText: '',
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      errorStyle: TextStyle(color: palette.destructive),
      errorMaxLines: 2,
      suffixText: suffix,
      suffixStyle: TextStyle(fontSize: 15, color: palette.textSecondary),
    );
  }

  Widget _buildCategoryPanel(
    AppLocalizations l,
    SureTokenPalette palette,
    CategoriesProvider categories,
    bool hidden,
    Account? account,
    bool online,
    bool enabled,
  ) {
    final split = _split;
    final canOpenSplit =
        enabled && online && _fresh != null && !_loadingDetails;
    final rows = <Widget>[];

    if (_isSplitParent) {
      rows.add(_dim(
        enabled: canOpenSplit && split != null,
        child: SureListRow(
          key: const ValueKey('transaction-category-row'),
          title: l.transactionEditCategoryLabel,
          value: split != null
              ? l.dstSplitValue(split.children.length)
              : l.dsSplit,
          showChevron: true,
          onTap: canOpenSplit && split != null ? _openSplit : null,
        ),
      ));
      if (split != null && split.children.isNotEmpty) {
        rows.add(_SplitLines(
          onTap: canOpenSplit ? _openSplit : null,
          children: [
            for (final child in split.children)
              _splitLine(child, categories, palette, hidden, account),
          ],
        ));
      }
    } else {
      rows.add(_dim(
        enabled: enabled,
        child: SureListRow(
          key: const ValueKey('transaction-category-row'),
          title: l.transactionEditCategoryLabel,
          value: _categoryLabel(categories) ?? l.transactionEditNoCategory,
          showChevron: true,
          onTap: enabled ? () => _pickCategory(online) : null,
        ),
      ));
      rows.add(_dim(
        enabled: canOpenSplit,
        child: SureListRow(
          title: l.txnDetailSplitAction,
          titleColor: palette.link,
          trailing: _loadingDetails
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: canOpenSplit ? _openSplit : null,
        ),
      ));
    }

    String? note;
    if (!online) {
      note = l.txnDetailSplitOffline;
    } else if (_splitError != null) {
      note = _splitError;
    }
    if (note != null) {
      rows.add(SureListRow(
        title: note,
        titleColor: _splitError != null && online
            ? palette.destructive
            : palette.textSecondary,
        trailing: _splitError != null && online
            ? TextButton(
                onPressed: _loadingDetails ? null : _loadDetails,
                style: TextButton.styleFrom(foregroundColor: palette.link),
                child: Text(l.commonTryAgain),
              )
            : null,
      ));
    }

    return SurePanel.rows(children: rows);
  }

  _SplitLine _splitLine(
    Transaction child,
    CategoriesProvider categories,
    SureTokenPalette palette,
    bool hidden,
    Account? account,
  ) {
    final category = _category(categories, child.categoryId);
    final categoryName = category?.name ?? child.categoryName;
    final display = _amountDisplay(child.amount, account, palette);
    final name = child.name.trim().isNotEmpty
        ? child.name
        : (categoryName ?? AppLocalizations.of(context).dsUncategorized);
    return _SplitLine(
      dot: SureCategoryIcon(
        name: categoryName,
        color: category?.color,
        icon: category?.icon,
        size: SureCategoryIcon.dotSize,
      ),
      name: name,
      amount: MoneyText(
        MoneyMasker.mask(display.text, hidden: hidden),
        trend: display.trend,
        color: display.color,
        maxLines: 1,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildDetailsPanel(
    AppLocalizations l,
    SureTokenPalette palette,
    MerchantsProvider merchants,
    TagsProvider tags,
    bool online,
    bool enabled,
    bool financialEnabled,
  ) {
    return SurePanel.rows(
      children: [
        _dim(
          enabled: enabled,
          child: SureListRow(
            key: const ValueKey('transaction-merchant-row'),
            title: l.transactionEditMerchantLabel,
            value: _merchantLabel(merchants) ?? l.transactionEditNoMerchant,
            showChevron: true,
            onTap: enabled ? () => _pickMerchant(online) : null,
          ),
        ),
        _dim(
          enabled: enabled,
          child: _TagsRow(
            title: l.transactionEditTagsLabel,
            addLabel: l.dstAddTag,
            tags: [for (final id in _selectedTagIds) _tagLabel(id, tags)],
            onEdit: enabled ? () => _pickTags(online) : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: TextFormField(
            key: const ValueKey('transaction-notes-field'),
            controller: _notesController,
            enabled: enabled,
            validator: _validateNotes,
            maxLength: _maxNotesLength,
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 15, color: palette.textPrimary),
            decoration: _inlineDecoration(palette, hint: l.dstAddNote),
          ),
        ),
        _dim(
          enabled: financialEnabled,
          child: SureListRow(
            key: const ValueKey('transaction-date-row'),
            title: l.transactionFormDateLabel,
            value: _formatDate(_date),
            showChevron: true,
            onTap: financialEnabled ? _pickDate : null,
          ),
        ),
      ],
    );
  }

  Widget _buildWebPanel(
    AppLocalizations l,
    SureTokenPalette palette,
    bool online,
  ) {
    final entryId = _fresh?.entryId;
    final available = online && entryId != null;
    return SurePanel.rows(
      children: [
        _dim(
          enabled: available,
          child: SureListRow(
            title: l.dstRecurring,
            value: l.dstRecurringSetUp,
            showChevron: true,
            onTap: available
                ? () => _openWeb(
                      l.dstRecurring,
                      '/recurring_transactions/new?entry_id='
                      '${Uri.encodeQueryComponent(entryId)}',
                    )
                : null,
          ),
        ),
        _dim(
          enabled: available,
          child: SureListRow(
            title: l.dstOpenOnWeb,
            titleColor: palette.link,
            trailing: SureIcon(
              SureIcons.arrowUpRight,
              size: 18,
              color: palette.link,
            ),
            onTap: available
                ? () => _openWeb(
                      l.txnDetail,
                      '/transactions/${Uri.encodeComponent(entryId)}',
                    )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDeletePanel(AppLocalizations l, SureTokenPalette palette) {
    final enabled = _txn.id != null && !_isSaving && !_isDeleting;
    return _dim(
      enabled: enabled,
      child: SurePanel(
        onTap: enabled ? _delete : null,
        child: Semantics(
          button: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: _isDeleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      l.dstDeleteTransaction,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: SureTokens.weightMedium,
                        color: palette.destructive,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dim({required bool enabled, required Widget child}) =>
      Opacity(opacity: enabled ? 1 : 0.5, child: child);
}

/// The split's parts listed under the Category row, indented: a 16 px
/// category dot, the part's name and its mono amount. Tapping opens the split
/// editor.
class _SplitLines extends StatelessWidget {
  const _SplitLines({required this.children, required this.onTap});

  final List<_SplitLine> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    if (onTap == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _SplitLine extends StatelessWidget {
  const _SplitLine({
    required this.dot,
    required this.name,
    required this.amount,
  });

  final Widget dot;
  final String name;
  final Widget amount;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          dot,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: palette.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          amount,
        ],
      ),
    );
  }
}

/// The Tags row: the title, the selected tags as chips, and a "+" that opens
/// the tag picker (where tags are also removed).
class _TagsRow extends StatelessWidget {
  const _TagsRow({
    required this.title,
    required this.addLabel,
    required this.tags,
    required this.onEdit,
  });

  final String title;
  final String addLabel;
  final List<String> tags;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: SureTokens.weightMedium,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  SureChip(
                    label: tag,
                    onSelected: onEdit == null ? null : (_) => onEdit!(),
                    enabled: onEdit != null,
                  ),
              ],
            ),
          ),
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              tooltip: addLabel,
              onPressed: onEdit,
              icon: SureIcon(SureIcons.plus, size: 18, color: palette.link),
            ),
          ),
        ],
      ),
    );
  }
}
