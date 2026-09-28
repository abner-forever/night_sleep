/// Turns the form's `HH:mm` inputs into the UTC instants a record stores.
///
/// The form collects a wake **date** plus two wall-clock times, which is how a
/// person thinks about a night. The database stores instants plus the zone they
/// were entered in. Doing that conversion in one place keeps the midnight
/// roll-over rule consistent between manual logging and imports, and keeps it
/// out of the widgets.
library;

class SleepWindow {
  const SleepWindow({
    required this.startAtUtc,
    required this.endAtUtc,
    required this.timeZoneId,
    required this.durationHours,
  });

  final DateTime startAtUtc;
  final DateTime endAtUtc;
  final String timeZoneId;

  /// Derived from the instants, never typed by the user.
  final double durationHours;

  bool get isPlausible => durationHours > 0 && durationHours <= 24;
}

/// Builds a window from a wake date and two `HH:mm` strings.
///
/// Bedtime rolls back a day when it is not earlier than the wake time, so
/// `23:15 → 07:20` crosses midnight while `00:30 → 07:00` stays on one day.
/// When [now] is supplied the resulting zone id comes from it; this is also the
/// seam tests use to pin the time zone.
SleepWindow buildSleepWindow({
  required DateTime wakeDate,
  required String bedtime,
  required String wakeTime,
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final end = _atClock(wakeDate, wakeTime);
  var start = _atClock(wakeDate, bedtime);

  if (!start.isBefore(end)) {
    start = start.subtract(const Duration(days: 1));
  }

  return SleepWindow(
    startAtUtc: start.toUtc(),
    endAtUtc: end.toUtc(),
    timeZoneId: reference.timeZoneName,
    durationHours: end.difference(start).inMinutes / 60,
  );
}

DateTime _atClock(DateTime day, String clock) {
  final parts = clock.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// `HH:mm` for a local [DateTime].
String formatClock(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}';

/// `YYYY-MM-DD` for a local [DateTime].
String formatIsoDate(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

/// Parses `YYYY-MM-DD` back to a date, falling back to [fallback].
DateTime parseIsoDate(String value, DateTime fallback) {
  final parts = value.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((part) => part == null)) return fallback;
  return DateTime(parts[0]!, parts[1]!, parts[2]!);
}
