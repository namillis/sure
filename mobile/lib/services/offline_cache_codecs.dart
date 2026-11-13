import '../models/account.dart';
import '../models/budget.dart';

/// JSON for models the offline cache stores. Each map uses the API's own
/// field names, so the model's `fromJson` reads it back unchanged.
class OfflineCacheCodecs {
  OfflineCacheCodecs._();

  static Map<String, dynamic> account(Account a) => {
        'id': a.id,
        'name': a.name,
        'balance': a.balance,
        'balance_cents': a.balanceCents,
        'cash_balance': a.cashBalance,
        'cash_balance_cents': a.cashBalanceCents,
        'currency': a.currency,
        'classification': a.classification,
        'account_type': a.accountType,
        'subtype': a.subtype,
        'status': a.status,
        'institution_name': a.institutionName,
        'institution_domain': a.institutionDomain,
        'created_at': a.createdAt?.toIso8601String(),
        'updated_at': a.updatedAt?.toIso8601String(),
      };

  static Map<String, dynamic> budget(Budget b) => {
        'id': b.id,
        'start_date': _date(b.startDate),
        'end_date': _date(b.endDate),
        'name': b.name,
        'currency': b.currency,
        'initialized': b.initialized,
        'current': b.current,
        if (b.canEdit != null) 'can_edit': b.canEdit,
        'budgeted_spending': b.budgetedSpending,
        'budgeted_spending_cents': b.budgetedSpendingCents,
        'expected_income': b.expectedIncome,
        'expected_income_cents': b.expectedIncomeCents,
        'allocated_spending': b.allocatedSpending,
        'allocated_spending_cents': b.allocatedSpendingCents,
        'actual_spending': b.actualSpending,
        'actual_spending_cents': b.actualSpendingCents,
        'actual_income': b.actualIncome,
        'actual_income_cents': b.actualIncomeCents,
        'available_to_spend': b.availableToSpend,
        'available_to_spend_cents': b.availableToSpendCents,
        'available_to_allocate': b.availableToAllocate,
        'available_to_allocate_cents': b.availableToAllocateCents,
      };

  static Map<String, dynamic> budgetCategory(BudgetCategory c) => {
        'id': c.id,
        'budget_id': c.budgetId,
        'currency': c.currency,
        'subcategory': c.subcategory,
        'inherits_parent_budget': c.inheritsParentBudget,
        'rollover_enabled': c.rolloverEnabled,
        'category': {
          'id': c.category.id,
          'name': c.category.name,
          'color': c.category.color,
          'lucide_icon': c.category.lucideIcon,
          'parent_id': c.category.parentId,
        },
        'budgeted_spending': c.budgetedSpending,
        'budgeted_spending_cents': c.budgetedSpendingCents,
        'display_budgeted_spending': c.displayBudgetedSpending,
        'display_budgeted_spending_cents': c.displayBudgetedSpendingCents,
        'actual_spending': c.actualSpending,
        'actual_spending_cents': c.actualSpendingCents,
        'rolled_over_amount': c.rolledOverAmount,
        'rolled_over_amount_cents': c.rolledOverAmountCents,
        'available_to_spend': c.availableToSpend,
        'available_to_spend_cents': c.availableToSpendCents,
        'median_spent': c.medianSpent,
        'median_spent_cents': c.medianSpentCents,
      };

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
