import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sure_mobile/utils/sure_dates.dart';

import '../support/ds_harness.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('sv');
  });

  String rel(DateTime date, DateTime now, {String locale = 'en'}) =>
      SureDates.relativeDay(date,
          locale: locale, today: 'Today', yesterday: 'Yesterday', now: now);

  group('SureDates.relativeDay', () {
    final now = DateTime(2026, 11, 11, 14, 47);

    test('today and yesterday by calendar day, not 24 hours', () {
      expect(rel(DateTime(2026, 11, 11), now), 'Today');
      expect(rel(DateTime(2026, 11, 11, 23, 59), now), 'Today');
      expect(rel(DateTime(2026, 11, 10, 23, 59), now), 'Yesterday');
      expect(rel(DateTime(2026, 11, 10), now), 'Yesterday');
    });

    test('other days this year have no year', () {
      expect(rel(DateTime(2026, 11, 9), now), 'Nov 9');
      expect(rel(DateTime(2026, 1, 1), now), 'Jan 1');
    });

    test('other years add the year', () {
      expect(rel(DateTime(2025, 11, 10), now), 'Nov 10, 2025');
    });

    test('year boundary: Dec 31 is yesterday on Jan 1, with no year', () {
      final newYear = DateTime(2027, 1, 1, 9);
      expect(rel(DateTime(2026, 12, 31), newYear), 'Yesterday');
      expect(rel(DateTime(2026, 12, 30), newYear), 'Dec 30, 2026');
      expect(rel(DateTime(2027, 1, 1), newYear), 'Today');
    });

    test('a future date this year reads as a plain date', () {
      expect(rel(DateTime(2026, 11, 12), now), 'Nov 12');
    });

    test('across a daylight-saving change', () {
      // Nov 1 2026 is the US fall-back day; the day count must stay whole.
      expect(rel(DateTime(2026, 11, 1), DateTime(2026, 11, 2, 0, 30)),
          'Yesterday');
      expect(
          rel(DateTime(2026, 3, 8), DateTime(2026, 3, 9, 0, 30)), 'Yesterday');
    });

    test('Swedish formats day-first', () {
      expect(rel(DateTime(2026, 11, 9), now, locale: 'sv'), '9 nov.');
    });
  });

  group('SureDates.range', () {
    final now = DateTime(2026, 11, 11);

    test('within a month', () {
      expect(
          SureDates.range(DateTime(2026, 11, 1), now, locale: 'en', now: now),
          'Nov 1–11');
      expect(
          SureDates.range(DateTime(2026, 11, 1), now, locale: 'sv', now: now),
          '1–11 nov.');
    });

    test('across months', () {
      expect(
          SureDates.range(DateTime(2026, 10, 28), DateTime(2026, 11, 3),
              locale: 'en', now: now),
          'Oct 28 – Nov 3');
    });

    test('across a year boundary shows years', () {
      expect(
          SureDates.range(DateTime(2025, 12, 28), DateTime(2026, 1, 3),
              locale: 'en', now: now),
          'Dec 28, 2025 – Jan 3, 2026');
    });

    test('one day', () {
      expect(SureDates.range(now, now, locale: 'en', now: now), 'Nov 11');
    });
  });

  test('full always has the year', () {
    expect(SureDates.full(DateTime(2026, 11, 5), locale: 'en'), 'Nov 5, 2026');
  });

  test('parseDay reads API dates and rejects junk', () {
    expect(SureDates.parseDay('2026-11-09'), DateTime(2026, 11, 9));
    expect(SureDates.parseDay('2026-11-09T23:10:00'), DateTime(2026, 11, 9));
    expect(SureDates.parseDay('nope'), isNull);
    expect(SureDates.parseDay(null), isNull);
  });

  testWidgets('relativeDayOf uses the app strings', (tester) async {
    late String label;
    await pumpDs(
      tester,
      Builder(builder: (context) {
        label = SureDates.relativeDayOf(context, DateTime(2026, 11, 10),
            now: DateTime(2026, 11, 11));
        return const SizedBox();
      }),
    );
    expect(label, 'Yesterday');
  });
}
