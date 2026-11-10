import '../services/budgets_service.dart';

/// Date windows the Activity tab offers.
enum ActivityDatePreset {
  thisMonth,
  lastMonth,
  last90Days,
  thisYear,
  all,
  custom
}

/// The transaction type filter. The API's `type` param only knows income and
/// expense; it has no transfer filter.
enum ActivityTypeFilter { expense, income }

/// An inclusive date range; either end may be open.
class ActivityDateRange {
  const ActivityDateRange(this.start, this.end);

  final DateTime? start;
  final DateTime? end;
}

/// Search text plus every filter the Activity tab sends to
/// `GET /api/v1/transactions`. Immutable; change it with [copyWith].
class ActivityFilters {
  const ActivityFilters({
    this.search = '',
    this.datePreset = ActivityDatePreset.thisMonth,
    this.customStart,
    this.customEnd,
    this.categoryIds = const {},
    this.accountIds = const {},
    this.tagIds = const {},
    this.type,
  });

  final String search;
  final ActivityDatePreset datePreset;

  /// Only read when [datePreset] is [ActivityDatePreset.custom].
  final DateTime? customStart;
  final DateTime? customEnd;
  final Set<String> categoryIds;
  final Set<String> accountIds;
  final Set<String> tagIds;

  /// Null means both income and expense.
  final ActivityTypeFilter? type;

  static const _unset = Object();

  ActivityFilters copyWith({
    String? search,
    ActivityDatePreset? datePreset,
    DateTime? customStart,
    DateTime? customEnd,
    Set<String>? categoryIds,
    Set<String>? accountIds,
    Set<String>? tagIds,
    Object? type = _unset,
  }) {
    return ActivityFilters(
      search: search ?? this.search,
      datePreset: datePreset ?? this.datePreset,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
      categoryIds: categoryIds ?? this.categoryIds,
      accountIds: accountIds ?? this.accountIds,
      tagIds: tagIds ?? this.tagIds,
      type: identical(type, _unset) ? this.type : type as ActivityTypeFilter?,
    );
  }

  /// Whether anything differs from the default view (this month, no search,
  /// no other filter). Drives "Clear all" and the filtered empty state.
  bool get hasActiveFilters =>
      search.trim().isNotEmpty ||
      datePreset != ActivityDatePreset.thisMonth ||
      categoryIds.isNotEmpty ||
      accountIds.isNotEmpty ||
      tagIds.isNotEmpty ||
      type != null;

  /// The inclusive date range [datePreset] covers on [now]'s calendar day.
  ActivityDateRange dateRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (datePreset) {
      case ActivityDatePreset.thisMonth:
        return ActivityDateRange(
          DateTime(today.year, today.month, 1),
          DateTime(today.year, today.month + 1, 0),
        );
      case ActivityDatePreset.lastMonth:
        return ActivityDateRange(
          DateTime(today.year, today.month - 1, 1),
          DateTime(today.year, today.month, 0),
        );
      case ActivityDatePreset.last90Days:
        // Today plus the 89 days before it.
        return ActivityDateRange(
          DateTime(today.year, today.month, today.day - 89),
          today,
        );
      case ActivityDatePreset.thisYear:
        return ActivityDateRange(
          DateTime(today.year, 1, 1),
          DateTime(today.year, 12, 31),
        );
      case ActivityDatePreset.all:
        return const ActivityDateRange(null, null);
      case ActivityDatePreset.custom:
        return ActivityDateRange(customStart, customEnd);
    }
  }

  /// Query parameters for `GET /api/v1/transactions`, without paging. List
  /// values become repeated Rails array params (`account_ids[]=a&...`).
  Map<String, dynamic> queryParameters(DateTime now) {
    final range = dateRange(now);
    final term = search.trim();
    return {
      if (term.isNotEmpty) 'search': term,
      if (range.start != null)
        'start_date': BudgetsService.formatApiDate(range.start!),
      if (range.end != null)
        'end_date': BudgetsService.formatApiDate(range.end!),
      if (accountIds.isNotEmpty) 'account_ids[]': _sorted(accountIds),
      if (categoryIds.isNotEmpty) 'category_ids[]': _sorted(categoryIds),
      if (tagIds.isNotEmpty) 'tag_ids[]': _sorted(tagIds),
      if (type != null) 'type': type!.name,
    };
  }

  static List<String> _sorted(Set<String> ids) => ids.toList()..sort();
}
