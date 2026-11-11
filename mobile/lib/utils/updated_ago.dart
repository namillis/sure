import '../l10n/app_localizations.dart';

/// "Updated 5 minutes ago" for data last loaded from the server at
/// [updatedAt]. A time in the future (clock change) reads as just now.
String updatedAgoLabel(
  AppLocalizations l,
  DateTime updatedAt,
  DateTime now,
) {
  final age = now.difference(updatedAt);
  if (age.inMinutes < 1) return l.p3ocUpdatedJustNow;
  if (age.inHours < 1) return l.p3ocUpdatedMinutesAgo(age.inMinutes);
  if (age.inDays < 1) return l.p3ocUpdatedHoursAgo(age.inHours);
  return l.p3ocUpdatedDaysAgo(age.inDays);
}
