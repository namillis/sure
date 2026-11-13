import 'dart:convert';

/// One recurring transaction as the API's `_recurring_transaction` partial
/// renders it.
Map<String, dynamic> recurringJson({
  String id = 'rt_1',
  String? name = 'Gym Membership',
  String amount = r'$49.99',
  int amountCents = 4999,
  String currency = 'USD',
  String status = 'active',
  String nextDate = '2026-11-20',
  String lastDate = '2026-10-20',
  int day = 20,
  List<Map<String, dynamic>> rules = const [],
  Map<String, dynamic>? account = const {
    'id': 'acct_1',
    'name': 'Checking',
    'account_type': 'depository',
  },
  Map<String, dynamic>? merchant,
  String? categoryId,

  /// Sure+ (`recurring.category`) embeds the category; stock Sure has no
  /// `category` key. Pass [embedCategory] to render the Sure+ shape.
  Map<String, dynamic>? category,
  bool embedCategory = false,
}) =>
    {
      'id': id,
      'amount': amount,
      'amount_cents': amountCents,
      'currency': currency,
      'expected_day_of_month': day,
      'last_occurrence_date': lastDate,
      'next_expected_date': nextDate,
      'status': status,
      'occurrence_count': 3,
      'name': name,
      'manual': true,
      'payment_url': null,
      'autopay': false,
      'notes': null,
      'expected_amount_min': null,
      'expected_amount_min_cents': null,
      'expected_amount_max': null,
      'expected_amount_max_cents': null,
      'expected_amount_avg': null,
      'expected_amount_avg_cents': null,
      'bill_type': 'bill',
      'category_id': categoryId,
      if (embedCategory || category != null) 'category': category,
      'anchor_date': null,
      'weekend_adjust': 'none',
      'end_mode': 'never',
      'end_on': null,
      'end_after_count': null,
      'renews_on': null,
      'trial_ends_on': null,
      'cancelled_on': null,
      'recurrence_rules': rules,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'account': account,
      'merchant': merchant,
    };

String recurringIndexBody(
  List<Map<String, dynamic>> items, {
  int page = 1,
  int totalPages = 1,
}) =>
    jsonEncode({
      'recurring_transactions': items,
      'pagination': {
        'page': page,
        'per_page': 100,
        'total_count': items.length,
        'total_pages': totalPages,
      },
    });

/// A `spending_vs_normal` response for the current month.
Map<String, dynamic> spendingJson({
  bool comparable = true,
  List<Map<String, dynamic>>? categories,
}) =>
    {
      'currency': 'USD',
      'period': {'start_date': '2026-11-01', 'end_date': '2026-11-10'},
      'in_progress': true,
      'baseline_period': {'start_date': '2025-11-01', 'end_date': '2026-10-31'},
      'comparable': comparable,
      'total': '1200.0',
      'normal_total': comparable ? '1000.0' : null,
      'categories': categories ??
          [
            _category('c1', 'Groceries', '500.0', '450.0', '50.0', '0.1111'),
            _category('c2', 'Dining', '330.0', '250.0', '80.0', '0.32'),
            _category('c3', 'Rent', '300.0', '300.0', '0.0', '0.0'),
            _category('c4', 'Gifts', '70.0', '0.0', '70.0', null),
          ],
    };

Map<String, dynamic> _category(String id, String name, String total,
        String? normal, String? change, String? ratio) =>
    {
      'id': id,
      'name': name,
      'color': '#e99537',
      'filter_value': name,
      'total': total,
      'normal': normal,
      'change': change,
      'ratio': ratio,
      'subcategories': <Map<String, dynamic>>[],
    };
