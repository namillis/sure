import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// The one place the UI turns dates into text: "Today", "Yesterday",
/// "Nov 10", and "Nov 10, 2025" only when the year is not the current one.
/// Never ISO dates.
///
/// The pure functions take `now` and the locale so they are testable; the
/// `BuildContext` overloads read both from the app.
abstract final class SureDates {
  /// Parses the API's `yyyy-MM-dd` (or a full timestamp) into a local calendar
  /// day, or null when it does not parse.
  static DateTime? parseDay(String? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// "Today", "Yesterday", or [short] for any other day.
  static String relativeDay(
    DateTime date, {
    required String locale,
    required String today,
    required String yesterday,
    DateTime? now,
  }) {
    final reference = _day(now ?? DateTime.now());
    final day = _day(date);
    final diff = _dayDifference(reference, day);
    if (diff == 0) return today;
    if (diff == 1) return yesterday;
    return short(date, locale: locale, now: reference);
  }

  /// "Nov 10", or "Nov 10, 2025" when [date] is not in the current year.
  static String short(DateTime date, {required String locale, DateTime? now}) {
    final year = (now ?? DateTime.now()).year;
    final format =
        date.year == year ? DateFormat.MMMd(locale) : DateFormat.yMMMd(locale);
    return format.format(date);
  }

  /// "Nov 5, 2026": always with the year, e.g. for a chart scrub label.
  static String full(DateTime date, {required String locale}) =>
      DateFormat.yMMMd(locale).format(date);

  /// A compact range: "Nov 1–11" within a month, "Oct 28 – Nov 3" across
  /// months, with years only when either end is outside the current year.
  static String range(
    DateTime start,
    DateTime end, {
    required String locale,
    DateTime? now,
  }) {
    final year = (now ?? DateTime.now()).year;
    if (_dayDifference(_day(end), _day(start)) == 0) {
      return short(start, locale: locale, now: now);
    }
    final sameYear = start.year == end.year;
    if (sameYear && start.month == end.month && start.year == year) {
      final startText = DateFormat.MMMd(locale).format(start);
      final startDay = '${start.day}';
      // "Nov 1" -> "Nov 1–11"; day-first locales ("1 nov.") -> "1–11 nov.".
      if (startText.endsWith(startDay)) return '$startText–${end.day}';
      final endText = DateFormat.MMMd(locale).format(end);
      return '$startDay–$endText';
    }
    final withYear = start.year != year || end.year != year;
    final format =
        withYear ? DateFormat.yMMMd(locale) : DateFormat.MMMd(locale);
    return '${format.format(start)} – ${format.format(end)}';
  }

  /// [relativeDay] with the app's locale and strings.
  static String relativeDayOf(BuildContext context, DateTime date,
      {DateTime? now}) {
    final l = AppLocalizations.of(context);
    return relativeDay(
      date,
      locale: _locale(context),
      today: l.dsToday,
      yesterday: l.dsYesterday,
      now: now,
    );
  }

  /// [short] with the app's locale.
  static String shortOf(BuildContext context, DateTime date, {DateTime? now}) =>
      short(date, locale: _locale(context), now: now);

  /// [full] with the app's locale.
  static String fullOf(BuildContext context, DateTime date) =>
      full(date, locale: _locale(context));

  /// [range] with the app's locale.
  static String rangeOf(BuildContext context, DateTime start, DateTime end,
          {DateTime? now}) =>
      range(start, end, locale: _locale(context), now: now);

  static String _locale(BuildContext context) =>
      Localizations.localeOf(context).toString();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Whole calendar days from [b] to [a]. Uses UTC dates so a daylight-saving
  /// change between them does not make a day 23 or 25 hours long.
  static int _dayDifference(DateTime a, DateTime b) =>
      DateTime.utc(a.year, a.month, a.day)
          .difference(DateTime.utc(b.year, b.month, b.day))
          .inDays;
}
