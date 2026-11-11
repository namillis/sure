import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/utils/updated_ago.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final sv = lookupAppLocalizations(const Locale('sv'));
  final now = DateTime(2026, 11, 11, 12);

  String label(Duration age, [AppLocalizations? l]) =>
      updatedAgoLabel(l ?? en, now.subtract(age), now);

  test('picks the largest whole unit', () {
    expect(label(const Duration(seconds: 30)), 'Updated just now');
    expect(label(const Duration(minutes: 1)), 'Updated 1 minute ago');
    expect(label(const Duration(minutes: 59)), 'Updated 59 minutes ago');
    expect(label(const Duration(hours: 2)), 'Updated 2 hours ago');
    expect(label(const Duration(days: 1, hours: 5)), 'Updated 1 day ago');
    expect(label(const Duration(days: 3)), 'Updated 3 days ago');
  });

  test('a time in the future reads as just now', () {
    expect(label(const Duration(minutes: -5)), 'Updated just now');
  });

  test('Swedish', () {
    expect(label(const Duration(hours: 1), sv), 'Uppdaterad för 1 timme sedan');
  });
}
