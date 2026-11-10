import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
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
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../utils/amount_parser.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/split_math.dart';
import '../widgets/metadata_picker_sheet.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_list_group.dart';
import '../widgets/sure_segmented_control.dart';
import '../widgets/sure_text_field.dart';
import '../widgets/transaction_metadata_pickers.dart';
import 'transaction_split_screen.dart';

/// Edits one synced transaction: name, date, type, amount, category,
/// merchant, tags, notes, and its split. Pops with `true` when anything was
/// saved (including a split change), so the caller can reload.
///
/// Edits are online-only, as before: the offline queue holds creates and
/// deletes, not updates.
class TransactionEditScreen extends StatefulWidget {
  final OfflineTransaction transaction;

  const TransactionEditScreen({super.key, required this.transaction});

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  static const _maxNameLength = 255;
  static const _maxNotesLength = 2000;

  final _formKey = GlobalKey<FormState>();
  final _transactionsService = TransactionsService();
  final _splitService = TransactionSplitService();
  final _pickers = TransactionMetadataPickers();

  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late final TextEditingController _amountController;
  String _initialAmountText = '';
  late String _date;
  late String _nature;

  String? _selectedCategoryId;
  String? _selectedCategoryLabel;
  String? _selectedMerchantId;
  String? _selectedMerchantLabel;
  late List<String> _selectedTagIds;
  final Map<String, String> _tagLabels = {};

  /// The transaction as the server has it now: carries `amount_decimal` and
  /// `split_parent`, which the local cache doesn't store.
  Transaction? _fresh;
  TransactionSplit? _split;
  bool _loadingDetails = false;
  String? _splitError;
  bool _splitChanged = false;

  bool _isSaving = false;
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
      Localizations.maybeLocaleOf(context)?.toString() ?? Intl.getCurrentLocale();

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
      await _loadDetails();
    }
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.transactionEditUpdated)),
      );
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
          PickerOption(id: id, label: _tagLabels[id] ?? l.transactionEditUnknownTag),
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

  String? _categoryLabel(CategoriesProvider provider) {
    if (_selectedCategoryId == null) return null;
    for (final category in provider.categories) {
      if (category.id == _selectedCategoryId) return category.displayName;
    }
    return _selectedCategoryLabel ??
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
    return _tagLabels[id] ?? AppLocalizations.of(context).transactionEditUnknownTag;
  }

  String _formatDate(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return date;
    return DateFormat.yMMMd(_locale()).format(parsed);
  }

  String? _accountName() {
    try {
      final accounts = context.watch<AccountsProvider>().accounts;
      for (final Account account in accounts) {
        if (account.id == _txn.accountId) return account.name;
      }
    } on ProviderNotFoundException {
      // No accounts provider above this screen.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    final online = context.watch<ConnectivityService>().isOnline;
    final categories = context.watch<CategoriesProvider>();
    final merchants = context.watch<MerchantsProvider>();
    final tags = context.watch<TagsProvider>();

    final canEdit = _txn.id != null && _txn.syncStatus == SyncStatus.synced;
    final enabled = canEdit && !_isSaving;
    final financialEnabled = enabled && !_isSplitParent;
    final accountName = _accountName();
    final categoryLabel = _categoryLabel(categories);
    final merchantLabel = _merchantLabel(merchants);

    return PopScope(
      // After a split change the caller must reload even if nothing else is
      // saved, so report it on the way out.
      canPop: !_splitChanged,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l.txnDetail)),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(SureSpacing.xl),
            children: [
              _buildHeader(l, palette, theme, hidden, accountName),
              const SizedBox(height: SureSpacing.xl),
              if (!canEdit) ...[
                _notice(l.transactionEditSyncedOnly, palette.destructive, theme),
                const SizedBox(height: SureSpacing.lg),
              ] else if (!online) ...[
                _notice(l.txnDetailOfflineNote, palette.warning, theme),
                const SizedBox(height: SureSpacing.lg),
              ],
              SureTextField(
                controller: _nameController,
                label: l.transactionEditNameLabel,
                enabled: enabled,
                validator: _validateName,
                maxLength: _maxNameLength,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: SureSpacing.lg),
              Opacity(
                opacity: financialEnabled ? 1 : 0.5,
                child: IgnorePointer(
                  ignoring: !financialEnabled,
                  child: SureSegmentedControl<String>(
                    selected: _nature,
                    onChanged: (value) => setState(() => _nature = value),
                    segments: [
                      SureSegment(
                        value: 'expense',
                        label: l.transactionFormTypeExpense,
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      SureSegment(
                        value: 'income',
                        label: l.transactionFormTypeIncome,
                        icon: const Icon(Icons.arrow_upward),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SureSpacing.lg),
              SureTextField(
                controller: _amountController,
                label: l.transactionFormAmountLabel,
                enabled: financialEnabled,
                obscureText: hidden,
                validator: _validateAmount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: SureSpacing.lg),
                  child: Center(
                    widthFactor: 1,
                    child: Text(_txn.currency),
                  ),
                ),
              ),
              if (_isSplitParent) ...[
                const SizedBox(height: SureSpacing.sm),
                Text(
                  l.txnDetailSplitLockedFields,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary),
                ),
              ],
              const SizedBox(height: SureSpacing.lg),
              SureListGroup(
                children: [
                  _row(
                    title: l.transactionFormDateLabel,
                    value: _formatDate(_date),
                    icon: Icons.event,
                    onTap: financialEnabled ? _pickDate : null,
                    palette: palette,
                  ),
                  _row(
                    title: l.transactionEditCategoryLabel,
                    value: categoryLabel ?? l.transactionEditNoCategory,
                    icon: Icons.category_outlined,
                    onTap: enabled ? () => _pickCategory(online) : null,
                    palette: palette,
                  ),
                  _row(
                    title: l.transactionEditMerchantLabel,
                    value: merchantLabel ?? l.transactionEditNoMerchant,
                    icon: Icons.storefront_outlined,
                    onTap: enabled ? () => _pickMerchant(online) : null,
                    palette: palette,
                  ),
                  _row(
                    title: l.transactionEditTagsLabel,
                    value: _selectedTagIds.isEmpty
                        ? l.transactionEditNoTags
                        : l.txnDetailTagCount(_selectedTagIds.length),
                    icon: Icons.sell_outlined,
                    onTap: enabled ? () => _pickTags(online) : null,
                    palette: palette,
                  ),
                ],
              ),
              if (_selectedTagIds.isNotEmpty) ...[
                const SizedBox(height: SureSpacing.md),
                Wrap(
                  spacing: SureSpacing.md,
                  runSpacing: SureSpacing.md,
                  children: [
                    for (final id in _selectedTagIds)
                      InputChip(
                        label: Text(_tagLabel(id, tags)),
                        onDeleted: enabled
                            ? () => setState(() => _selectedTagIds.remove(id))
                            : null,
                        deleteButtonTooltipMessage: l.txnDetailRemoveTag,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: SureSpacing.lg),
              SureTextField(
                controller: _notesController,
                label: l.transactionEditNotesLabel,
                enabled: enabled,
                validator: _validateNotes,
                maxLength: _maxNotesLength,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: SureSpacing.lg),
              _buildSplitSection(l, palette, theme, hidden, online, enabled),
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
                label: _isSaving ? l.transactionEditSaving : l.commonSave,
                fullWidth: true,
                size: SureButtonSize.lg,
                loading: _isSaving,
                onPressed: enabled ? _save : null,
              ),
              const SizedBox(height: SureSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(String text, Color color, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: color, size: 20),
        const SizedBox(width: SureSpacing.md),
        Expanded(
          child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
        ),
      ],
    );
  }

  Widget _row({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
    required SureTokenPalette palette,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: SureListRow(
        title: title,
        subtitle: value,
        leading: Icon(icon, color: palette.textSecondary),
        showChevron: onTap != null,
        onTap: onTap,
      ),
    );
  }

  Widget _buildHeader(
    AppLocalizations l,
    SureTokenPalette palette,
    ThemeData theme,
    bool hidden,
    String? accountName,
  ) {
    final details = [
      _formatDate(_txn.date),
      if (accountName != null && accountName.isNotEmpty) accountName,
    ].join(' · ');

    return SureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            MoneyMasker.mask(_txn.amount, hidden: hidden),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: SureSpacing.xs),
          Text(
            _txn.isIncome
                ? l.transactionFormTypeIncome
                : l.transactionFormTypeExpense,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: SureSpacing.md),
          Text(
            details,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitSection(
    AppLocalizations l,
    SureTokenPalette palette,
    ThemeData theme,
    bool hidden,
    bool online,
    bool enabled,
  ) {
    final split = _split;
    final canOpen = enabled && online && _fresh != null && !_loadingDetails;

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              l.txnDetailSplitHeading,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (_loadingDetails)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    ];

    if (split != null) {
      for (final child in split.children) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: SureSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(child.name, style: theme.textTheme.bodyLarge),
                      if (child.categoryName != null)
                        Text(
                          child.categoryName!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: palette.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: SureSpacing.lg),
                Text(
                  MoneyMasker.mask(child.amount, hidden: hidden),
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        );
      }
    }

    String? note;
    if (!online) {
      note = l.txnDetailSplitOffline;
    } else if (_splitError != null) {
      note = _splitError;
    }
    if (note != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: SureSpacing.md),
          child: Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _splitError != null && online
                  ? palette.destructive
                  : palette.textSecondary,
            ),
          ),
        ),
      );
    }

    children.add(
      Padding(
        padding: const EdgeInsets.only(top: SureSpacing.lg),
        child: Wrap(
          spacing: SureSpacing.md,
          runSpacing: SureSpacing.md,
          children: [
            SureButton(
              label: _isSplitParent ? l.txnDetailEditSplit : l.txnDetailSplitAction,
              variant: SureButtonVariant.outline,
              leading: const Icon(Icons.call_split),
              onPressed: canOpen && (!_isSplitParent || split != null)
                  ? _openSplit
                  : null,
            ),
            if (_splitError != null && online)
              SureButton(
                label: l.commonTryAgain,
                variant: SureButtonVariant.ghost,
                onPressed: _loadingDetails ? null : _loadDetails,
              ),
          ],
        ),
      ),
    );

    return SureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
