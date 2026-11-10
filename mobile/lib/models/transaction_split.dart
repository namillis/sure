import 'transaction.dart';

/// A split transaction as `GET /api/v1/transactions/:id/split` returns it:
/// the parent's total and the child transactions that add up to it.
class TransactionSplit {
  const TransactionSplit({
    required this.transactionId,
    required this.amount,
    required this.currency,
    required this.children,
    this.amountDecimal,
  });

  final String transactionId;

  /// The parent's formatted amount (`$100.00`).
  final String amount;

  /// The parent's stored amount, unrounded, positive = outflow.
  final String? amountDecimal;

  final String currency;
  final List<Transaction> children;

  factory TransactionSplit.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final decimal = json['amount_decimal']?.toString().trim();
    return TransactionSplit(
      transactionId: json['transaction_id']?.toString() ?? '',
      amount: json['amount']?.toString() ?? '',
      amountDecimal: decimal == null || decimal.isEmpty ? null : decimal,
      currency: json['currency']?.toString() ?? '',
      children: rawChildren is List
          ? rawChildren
              .whereType<Map>()
              .map((child) => Transaction.fromJson(child.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }
}

/// One part of a split as `POST`/`PATCH .../split` expects it. [amount] is a
/// canonical decimal string in the parent's sign convention (positive =
/// outflow). Null fields are left out so the server applies its defaults: the
/// parent's name and merchant, no tags, not excluded.
class SplitPart {
  const SplitPart({
    required this.amount,
    this.name,
    this.categoryId,
    this.merchantId,
    this.tagIds,
    this.excluded,
  });

  final String amount;
  final String? name;
  final String? categoryId;
  final String? merchantId;
  final List<String>? tagIds;
  final bool? excluded;

  Map<String, dynamic> toJson() {
    final trimmedName = name?.trim();
    return {
      'amount': amount,
      if (trimmedName != null && trimmedName.isNotEmpty) 'name': trimmedName,
      if (categoryId != null) 'category_id': categoryId,
      if (merchantId != null) 'merchant_id': merchantId,
      if (tagIds != null) 'tag_ids': tagIds,
      if (excluded != null) 'excluded': excluded,
    };
  }
}
