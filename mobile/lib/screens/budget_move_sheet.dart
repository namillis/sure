import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/budget.dart';
import '../models/category.dart' as models;
import '../providers/budgets_provider.dart';
import '../providers/privacy_provider.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import '../widgets/category_picker_sheet.dart';
import '../widgets/ds/ds.dart';
import '../widgets/form_error_text.dart';
import 'form_sheet_fields.dart';

/// Opens the Sure+ (`budgets.allocations`) sheet that moves part of [from]'s
/// budget to another category of the same budget, picked from [categories]
/// (the month's lines). Resolves `true` once moved.
Future<bool?> showBudgetMoveSheet(
  BuildContext context, {
  required BudgetsProvider provider,
  required BudgetCategory from,
  required List<BudgetCategory> categories,
  required Future<String?> Function() accessToken,
  required VoidCallback onUnauthorized,
}) {
  return showSureSheet<bool>(
    context: context,
    builder: (_) => BudgetMoveSheet(
      provider: provider,
      from: from,
      categories: categories,
      accessToken: accessToken,
      onUnauthorized: onUnauthorized,
    ),
  );
}

/// The lines [from] can move budget to: the others in its budget, except
/// its own parent or subcategories (the server refuses those as
/// `parent_child`).
List<BudgetCategory> budgetMoveTargets(
  BudgetCategory from,
  List<BudgetCategory> categories,
) {
  final fromCategoryId = from.category.id;
  return [
    for (final c in categories)
      if (c.id != from.id &&
          c.budgetId == from.budgetId &&
          c.category.id.isNotEmpty &&
          c.category.id != from.parentCategoryId &&
          c.parentCategoryId != fromCategoryId)
        c,
  ];
}

/// The plain message for a refused move: the server's 422 `reason`, falling
/// back to its `message`.
String budgetMoveError(AppLocalizations l, Map<String, dynamic> result) {
  if (result['code'] == 'insufficient_scope') return l.spmReadOnlyAccess;
  if (result['code'] == 'forbidden') return l.spbSharedReadOnly;
  switch (result['reason']) {
    case 'insufficient_funds':
      return l.sb2ErrInsufficientFunds;
    case 'different_budgets':
      return l.sb2ErrDifferentBudgets;
    case 'non_positive_amount':
      return l.sb2ErrNonPositive;
    case 'same_category':
      return l.sb2ErrSameCategory;
    case 'parent_child':
      return l.sb2ErrParentChild;
    case 'uncategorized':
      return l.sb2ErrUncategorized;
  }
  if (result['code'] == 'validation_failed') {
    final message = result['error']?.toString();
    if (message != null && message.isNotEmpty) return message;
  }
  return l.sb2MoveFailed;
}

class BudgetMoveSheet extends StatefulWidget {
  const BudgetMoveSheet({
    super.key,
    required this.provider,
    required this.from,
    required this.categories,
    required this.accessToken,
    required this.onUnauthorized,
  });

  final BudgetsProvider provider;
  final BudgetCategory from;
  final List<BudgetCategory> categories;
  final Future<String?> Function() accessToken;
  final VoidCallback onUnauthorized;

  @override
  State<BudgetMoveSheet> createState() => _BudgetMoveSheetState();
}

class _BudgetMoveSheetState extends State<BudgetMoveSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final List<BudgetCategory> _targets =
      budgetMoveTargets(widget.from, widget.categories);
  BudgetCategory? _to;
  bool _busy = false;
  String? _error;

  String get _locale => Localizations.localeOf(context).toString();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The amount as the API's decimal string, or null unless it is above 0.
  String? _canonical(String text) {
    try {
      final parsed = AmountParser.parse(text, locale: _locale);
      return parsed.value > 0 ? parsed.canonicalValue : null;
    } on FormatException {
      return null;
    }
  }

  String? _validate(String? value) => _canonical(value ?? '') == null
      ? AppLocalizations.of(context).sb2ErrNonPositive
      : null;

  Future<void> _pickTarget() async {
    // The picker groups by parent, so each line becomes a Category keyed by
    // its budget-category id, with its parent line (when listed) as parent.
    final byCategoryId = {for (final c in _targets) c.category.id: c};
    final parentNames = {
      for (final c in widget.categories) c.category.id: c.category.name,
    };
    models.Category toCategory(BudgetCategory c) {
      final parentId = c.parentCategoryId;
      final parent = parentId == null
          ? null
          : byCategoryId[parentId] != null
              ? toCategory(byCategoryId[parentId]!)
              : models.Category(id: parentId, name: parentNames[parentId] ?? '');
      return models.Category(
        id: c.id,
        name: c.name,
        color: c.category.color,
        icon: c.category.lucideIcon,
        parent: parent,
      );
    }

    final picked = await CategoryPickerSheet.show(
      context,
      categories: [for (final c in _targets) toCategory(c)],
      selectedId: _to?.id,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _to = _targets.firstWhere((c) => c.id == picked.id, orElse: () => _to!);
      _error = null;
    });
  }

  Future<void> _move() async {
    final to = _to;
    if (to == null || !_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final token = await widget.accessToken();
    if (!mounted) return;
    if (token == null) {
      navigator.pop();
      widget.onUnauthorized();
      return;
    }
    final result = await widget.provider.moveAllocation(
      accessToken: token,
      from: widget.from,
      to: to,
      amount: _canonical(_amount.text)!,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.sb2Moved)));
      navigator.pop(true);
      return;
    }
    if (result['error'] == 'unauthorized') {
      navigator.pop();
      widget.onUnauthorized();
      return;
    }
    setState(() {
      _busy = false;
      _error = budgetMoveError(l, result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    final from = widget.from;
    final to = _to;
    final left = from.availableToSpend;

    return SureSheet(
      title: l.sb2MoveTitle,
      actionLabel: l.sb2Move,
      actionKey: const ValueKey('budgetMoveAction'),
      onAction: _move,
      actionEnabled: to != null,
      busy: _busy,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SurePanel.rows(
                children: [
                  SureListRow(
                    key: const ValueKey('budgetMoveFrom'),
                    title: l.sb2From,
                    subtitle: left == null
                        ? null
                        : l.sb2AmountLeft(
                            MoneyMasker.mask(left, hidden: hidden),
                          ),
                    value: from.name,
                  ),
                  SureListRow(
                    key: const ValueKey('budgetMoveTo'),
                    title: l.sb2To,
                    value: to?.name ?? l.sb2Choose,
                    showChevron: true,
                    enabled: !_busy,
                    onTap: _pickTarget,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FormSheetAmountField(
                key: const ValueKey('budgetMoveAmount'),
                controller: _amount,
                validator: _validate,
                enabled: !_busy,
                autofocus: false,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                FormErrorText(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
