import 'transaction.dart';

/// One row of the Activity tab: a [Transaction] plus the display context the
/// `/api/v1/transactions` JSON carries that [Transaction] does not keep
/// (account name and type, category color, split and transfer flags).
class ActivityTransaction {
  const ActivityTransaction({
    required this.transaction,
    this.accountName,
    this.accountType,
    this.categoryColor,
    this.isSplitParent = false,
    this.isTransfer = false,
    this.transferAccountName,
  });

  final Transaction transaction;
  final String? accountName;

  /// The account's `accountable_type` in snake case (`depository`,
  /// `credit_card`, ...).
  final String? accountType;

  /// The category's `#rrggbb` color, when it has a category.
  final String? categoryColor;
  final bool isSplitParent;
  final bool isTransfer;

  /// The other side's account name, when this row is part of a transfer.
  final String? transferAccountName;

  String? get id => transaction.id;

  /// The entry date (`yyyy-MM-dd`), or null when it does not parse.
  DateTime? get date => DateTime.tryParse(transaction.date);

  factory ActivityTransaction.fromJson(Map<String, dynamic> json) {
    final account = json['account'];
    final category = json['category'];
    final transfer = json['transfer'];
    final otherAccount = transfer is Map ? transfer['other_account'] : null;

    return ActivityTransaction(
      transaction: Transaction.fromJson(json),
      accountName: account is Map ? account['name']?.toString() : null,
      accountType: account is Map ? account['account_type']?.toString() : null,
      categoryColor: category is Map ? category['color']?.toString() : null,
      isSplitParent: json['split_parent'] == true,
      isTransfer: transfer is Map,
      transferAccountName:
          otherAccount is Map ? otherAccount['name']?.toString() : null,
    );
  }

  /// Consecutive rows that share a date, in the order given. The API returns
  /// newest first, so the groups come out newest first too. Rows whose date
  /// does not parse go into a group with a null [ActivityDayGroup.day].
  static List<ActivityDayGroup> groupByDay(List<ActivityTransaction> rows) {
    final groups = <ActivityDayGroup>[];
    for (final row in rows) {
      final date = row.date;
      final day =
          date == null ? null : DateTime(date.year, date.month, date.day);
      if (groups.isNotEmpty && groups.last.day == day) {
        groups.last.rows.add(row);
      } else {
        groups.add(ActivityDayGroup(day, [row]));
      }
    }
    return groups;
  }

  /// This row with its category replaced, after a successful categorize.
  ActivityTransaction withCategory({
    required String id,
    required String name,
    String? color,
  }) {
    final t = transaction;
    return ActivityTransaction(
      transaction: Transaction(
        id: t.id,
        accountId: t.accountId,
        name: t.name,
        date: t.date,
        amount: t.amount,
        currency: t.currency,
        nature: t.nature,
        notes: t.notes,
        categoryId: id,
        categoryName: name,
        categoryProvided: true,
        merchantId: t.merchantId,
        merchantName: t.merchantName,
        merchantProvided: t.merchantProvided,
        tagIds: t.tagIds,
        tagNames: t.tagNames,
        tagsProvided: t.tagsProvided,
        amountDecimal: t.amountDecimal,
        kind: t.kind,
        excluded: t.excluded,
        splitParent: t.splitParent,
      ),
      accountName: accountName,
      accountType: accountType,
      categoryColor: color,
      isSplitParent: isSplitParent,
      isTransfer: isTransfer,
      transferAccountName: transferAccountName,
    );
  }
}

/// The rows of one calendar day in the Activity list.
class ActivityDayGroup {
  ActivityDayGroup(this.day, this.rows);

  final DateTime? day;
  final List<ActivityTransaction> rows;
}
