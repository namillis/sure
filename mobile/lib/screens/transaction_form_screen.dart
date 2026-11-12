import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/account.dart';
import '../models/category.dart' as models;
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/log_service.dart';
import '../services/connectivity_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/amount_parser.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/ds/ds.dart';
import '../l10n/app_localizations.dart';
import 'form_sheet_fields.dart';

/// Opens [TransactionFormScreen] for [account] as a Sure sheet. Resolves
/// `true` when the transaction was created (online or saved for sync);
/// otherwise null.
Future<bool?> showTransactionFormSheet(
  BuildContext context, {
  required Account account,
}) {
  return showSureSheet<bool>(
    context: context,
    builder: (_) => TransactionFormScreen(account: account),
  );
}

/// The new-transaction form as sheet content: "Cancel · New transaction ·
/// Add", Expense | Income, a large amount field focused on open, the account
/// under it, then Name, Category and Date rows. Pops `true` once the
/// transaction is created. Open it with [showTransactionFormSheet].
class TransactionFormScreen extends StatefulWidget {
  final Account account;

  const TransactionFormScreen({super.key, required this.account});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  /// Sent when the name is left empty, as the old form's default name.
  static const _defaultName = 'SureApp';

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  final _log = LogService.instance;

  String _nature = 'expense';
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _isSubmitting = false;
  models.Category? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final categoriesProvider = Provider.of<CategoriesProvider>(
      context,
      listen: false,
    );
    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken != null) {
      categoriesProvider.fetchCategories(accessToken: accessToken);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String? _validateAmount(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) {
      return l.transactionFormAmountRequiredPrompt;
    }

    final double amount;
    try {
      amount = AmountParser.parse(value, locale: _currentLocaleName()).value;
    } on FormatException {
      return l.transactionFormAmountInvalidNumber;
    }

    if (amount <= 0) {
      return l.transactionFormAmountTooSmall;
    }

    return null;
  }

  String _currentLocaleName() {
    return Localizations.maybeLocaleOf(context)?.toString() ??
        Intl.getCurrentLocale();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null && mounted) {
      setState(() => _date = DateUtils.dateOnly(picked));
    }
  }

  Future<void> _selectCategory() async {
    final provider = context.read<CategoriesProvider>();
    final picked = await CategoryPickerSheet.show(
      context,
      categories: provider.categories,
      selectedId: _selectedCategory?.id,
      loading: provider.isLoading,
    );
    if (picked == null || !mounted) return;
    final categories = context.read<CategoriesProvider>().categories;
    setState(() {
      _selectedCategory =
          categories.where((c) => c.id == picked.id).firstOrNull;
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    _log.info('TransactionForm', 'Starting transaction creation...');

    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final transactionsProvider = Provider.of<TransactionsProvider>(
        context,
        listen: false,
      );
      final accessToken = await authProvider.getValidAccessToken();

      if (accessToken == null) {
        _log.warning(
          'TransactionForm',
          'Access token is null, session expired',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.transactionFormSessionExpired),
              backgroundColor: palette.destructive,
            ),
          );
          await authProvider.logout();
        }
        return;
      }

      final apiDate = DateFormat('yyyy-MM-dd').format(_date);
      final name = _nameController.text.trim();
      final canonicalAmount = AmountParser.canonicalize(
        _amountController.text,
        locale: _currentLocaleName(),
      );

      _log.info(
        'TransactionForm',
        'Calling TransactionsProvider.createTransaction (offline-first)',
      );

      // Use TransactionsProvider for offline-first transaction creation
      final success = await transactionsProvider.createTransaction(
        accessToken: accessToken,
        accountId: widget.account.id,
        name: name.isEmpty ? _defaultName : name,
        date: apiDate,
        amount: canonicalAmount,
        currency: widget.account.currency,
        nature: _nature,
        notes: 'This transaction via mobile app.',
        categoryId: _selectedCategory?.id,
        categoryName: _selectedCategory?.name,
      );

      if (mounted) {
        if (success) {
          _log.info(
            'TransactionForm',
            'Transaction created successfully (saved locally)',
          );

          // Check current connectivity status to show appropriate message
          final connectivityService = Provider.of<ConnectivityService>(
            context,
            listen: false,
          );
          final isOnline = connectivityService.isOnline;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isOnline
                    ? l.transactionFormCreateSuccessOnline
                    : l.transactionFormCreateSuccessOffline,
              ),
              backgroundColor: palette.success,
            ),
          );
          Navigator.pop(context, true); // Return true to indicate success
        } else {
          _log.error('TransactionForm', 'Failed to create transaction');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.transactionFormCreateFailed),
              backgroundColor: palette.destructive,
            ),
          );
        }
      }
    } catch (e) {
      _log.error(
        'TransactionForm',
        'Exception during transaction creation: $e',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.transactionFormGenericError(e.toString())),
            backgroundColor: palette.destructive,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;

    return SureSheet(
      title: l.ds3fNewTransaction,
      actionLabel: l.ds3fAdd,
      actionKey: const ValueKey('transactionFormAdd'),
      onAction: _handleSubmit,
      busy: _isSubmitting,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SureSegmentedControl<String>(
                selected: _nature,
                onChanged: (value) => setState(() => _nature = value),
                segments: [
                  SureSegment<String>(
                    value: 'expense',
                    label: l.transactionFormTypeExpense,
                  ),
                  SureSegment<String>(
                    value: 'income',
                    label: l.transactionFormTypeIncome,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FormSheetAmountField(
                key: const ValueKey('transactionFormAmount'),
                controller: _amountController,
                validator: _validateAmount,
                suffix: widget.account.currency,
                obscure: hidden,
              ),
              const SizedBox(height: 4),
              Text(
                widget.account.name,
                key: const ValueKey('transactionFormAccount'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 20),
              SurePanel.rows(
                children: [
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('transactionFormName'),
                    label: l.transactionFormNameLabel,
                    controller: _nameController,
                    hint: _defaultName,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                  ),
                  _categoryRow(l, palette),
                  SureListRow(
                    key: const ValueKey('transactionFormDate'),
                    title: l.transactionFormDateLabel,
                    value: SureDates.relativeDayOf(context, _date),
                    showChevron: true,
                    onTap: _isSubmitting ? null : _selectDate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryRow(AppLocalizations l, SureTokenPalette palette) {
    final categories = context.watch<CategoriesProvider>();
    final category = _selectedCategory;
    final Widget value;
    if (category != null) {
      value = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SureCategoryIcon(
            name: category.name,
            color: category.color,
            icon: category.icon,
            size: SureCategoryIcon.dotSize,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.4,
            ),
            child: Text(
              category.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: palette.textSecondary),
            ),
          ),
          SizedBox.square(
            dimension: 32,
            child: IconButton(
              key: const ValueKey('transactionFormClearCategory'),
              padding: EdgeInsets.zero,
              tooltip: l.ds3fClearCategory,
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() => _selectedCategory = null),
              icon: SureIcon(SureIcons.x, size: 16, color: palette.textSubdued),
            ),
          ),
        ],
      );
    } else {
      value = Text(
        categories.isLoading
            ? l.transactionFormCategoryLoading
            : l.transactionFormNoCategory,
        style: TextStyle(fontSize: 15, color: palette.textSubdued),
      );
    }

    return SureListRow(
      key: const ValueKey('transactionFormCategory'),
      title: l.transactionFormCategoryLabel,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          value,
          const SizedBox(width: 4),
          SureIcon(
            SureIcons.chevronRight,
            size: 18,
            color: palette.textSubdued,
          ),
        ],
      ),
      onTap: _isSubmitting ? null : _selectCategory,
    );
  }
}
