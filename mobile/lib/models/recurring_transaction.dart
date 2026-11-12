import '../utils/json_parsing.dart';

/// One rule of a recurring series' cadence, as `recurrence_rules` in
/// `GET /api/v1/recurring_transactions`.
class RecurrenceRule {
  const RecurrenceRule({required this.frequency, this.interval = 1});

  /// `weekly`, `monthly` or `yearly`.
  final String frequency;
  final int interval;

  factory RecurrenceRule.fromJson(Map<String, dynamic> json) {
    final interval = JsonParsing.parseInt(json['interval']) ?? 1;
    return RecurrenceRule(
      frequency: json['frequency']?.toString() ?? 'monthly',
      interval: interval < 1 ? 1 : interval,
    );
  }

  /// How many times this rule fires in an average month.
  double get perMonth {
    switch (frequency) {
      case 'weekly':
        return 52 / 12 / interval;
      case 'yearly':
        return 1 / 12 / interval;
      default:
        return 1 / interval;
    }
  }
}

/// A recurring bill, subscription or income from the recurring transactions
/// API. Amounts follow Sure's sign convention: positive is money out.
class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    this.amountCents,
    this.name,
    this.merchantName,
    this.merchantId,
    this.accountId,
    this.accountName,
    this.expectedDayOfMonth,
    this.lastOccurrenceDate,
    this.nextExpectedDate,
    this.rules = const [],
    this.autopay = false,
    this.paymentUrl,
    this.notes,
    this.billType,
    this.categoryId,
    this.expectedAmountMinCents,
    this.expectedAmountMaxCents,
  });

  final String id;

  /// Formatted by the server, e.g. `$19.99`.
  final String amount;
  final int? amountCents;
  final String currency;

  /// `suggested`, `active`, `paused`, `inactive` or `ended`. The API only
  /// writes `active` and `inactive`.
  final String status;
  final String? name;
  final String? merchantName;
  final String? merchantId;
  final String? accountId;
  final String? accountName;
  final int? expectedDayOfMonth;
  final DateTime? lastOccurrenceDate;
  final DateTime? nextExpectedDate;
  final List<RecurrenceRule> rules;
  final bool autopay;
  final String? paymentUrl;
  final String? notes;
  final String? billType;

  /// The server sends only the id (no name, color or icon); resolve it
  /// against the category list.
  final String? categoryId;

  /// The range detection expects, in minor units with [amountCents]' sign.
  /// Null for manual items without one.
  final int? expectedAmountMinCents;
  final int? expectedAmountMaxCents;

  static const writableStatuses = ['active', 'inactive'];

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>?;
    final merchant = json['merchant'] as Map<String, dynamic>?;
    return RecurringTransaction(
      id: JsonParsing.parseRequiredString(json['id'], 'id'),
      amount: json['amount']?.toString() ?? '',
      amountCents: JsonParsing.parseInt(json['amount_cents']),
      currency: json['currency']?.toString() ?? 'USD',
      status: json['status']?.toString() ?? 'active',
      name: _blankToNull(json['name']),
      merchantName: _blankToNull(merchant?['name']),
      merchantId: _blankToNull(merchant?['id']),
      accountId: account?['id']?.toString(),
      accountName: _blankToNull(account?['name']),
      expectedDayOfMonth: JsonParsing.parseInt(json['expected_day_of_month']),
      lastOccurrenceDate: _date(json['last_occurrence_date']),
      nextExpectedDate: _date(json['next_expected_date']),
      rules: (json['recurrence_rules'] as List<dynamic>? ?? [])
          .map((r) => RecurrenceRule.fromJson(r as Map<String, dynamic>))
          .toList(),
      autopay: json['autopay'] == true,
      paymentUrl: _blankToNull(json['payment_url']),
      notes: _blankToNull(json['notes']),
      billType: _blankToNull(json['bill_type']),
      categoryId: _blankToNull(json['category_id']),
      expectedAmountMinCents:
          JsonParsing.parseInt(json['expected_amount_min_cents']),
      expectedAmountMaxCents:
          JsonParsing.parseInt(json['expected_amount_max_cents']),
    );
  }

  /// What the user calls it: the typed name, else the merchant (as the web
  /// `display_name`).
  String get displayName => name ?? merchantName ?? '';

  bool get isActive => status == 'active';

  /// Money in (negative amounts, per Sure's sign convention).
  bool get isInflow =>
      amountCents != null ? amountCents! < 0 : amount.trim().startsWith('-');

  /// The first rule, or null for a legacy series that is monthly on
  /// [expectedDayOfMonth].
  RecurrenceRule? get primaryRule => rules.isEmpty ? null : rules.first;

  /// Expected occurrences per month across all rules (1 without rules).
  double get perMonth =>
      rules.isEmpty ? 1 : rules.fold(0.0, (sum, rule) => sum + rule.perMonth);

  static String? _blankToNull(dynamic value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
