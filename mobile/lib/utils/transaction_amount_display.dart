import 'package:flutter/material.dart';

import '../widgets/money_text.dart';
import 'amount_parser.dart';

/// How a transaction amount reads in a list row: signed text, direction and
/// icon. The same rules as the account transaction list
/// (`TransactionsListScreen._getAmountDisplayInfo`): the API's amount is in
/// the entry's sign convention (positive = money out), so for asset and
/// liability accounts the sign is flipped, and a non-negative result is
/// money in.
class TransactionAmountDisplay {
  const TransactionAmountDisplay({
    required this.text,
    required this.trend,
    required this.icon,
  });

  /// The formatted amount with a leading `-` for money out, e.g. `-$12.00`.
  final String text;
  final MoneyTrend trend;
  final IconData icon;

  bool get isInflow => trend == MoneyTrend.inflow;

  factory TransactionAmountDisplay.of(
    String amount, {
    required bool isAsset,
    required bool isLiability,
  }) {
    try {
      final parsed = AmountParser.parse(amount);
      var value = parsed.value;
      if (isAsset || isLiability) value = -value;
      final positive = value >= 0;
      return TransactionAmountDisplay(
        text: '${positive ? '' : '-'}${parsed.displayText}',
        trend: positive ? MoneyTrend.inflow : MoneyTrend.outflow,
        icon: positive ? Icons.arrow_upward : Icons.arrow_downward,
      );
    } on FormatException {
      return TransactionAmountDisplay(
        text: amount,
        trend: MoneyTrend.neutral,
        icon: Icons.help_outline,
      );
    }
  }

  /// Account types (`accountable_type`, snake case) on each side of the
  /// balance sheet, for rows whose account is not in [AccountsProvider].
  static const assetAccountTypes = {
    'depository',
    'investment',
    'crypto',
    'property',
    'vehicle',
    'other_asset',
  };
  static const liabilityAccountTypes = {
    'credit_card',
    'loan',
    'other_liability',
  };
}
