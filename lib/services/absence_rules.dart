// Absences for a day must be set before this time (6:00 AM).
// For testing, you can temporarily change cutoffHour to 23.
const cutoffHour = 6;
const cutoffMinute = 0;

/// '2026-11-10' style text, which is the format the database date column uses.
String dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _todayCutoff() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, cutoffHour, cutoffMinute);
}

bool isPastCutoff() => DateTime.now().isAfter(_todayCutoff());

/// Can an absence for [date] still be added or cancelled?
/// Future days: yes. Today: only before the cut-off. Past days: no.
bool canChangeAbsence(DateTime date) {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(date.year, date.month, date.day);
  if (d.isAfter(today)) return true;
  if (d.isBefore(today)) return false;
  return !isPastCutoff();
}

/// Before 12:00 is the morning trip, after that the afternoon trip.
String currentSession() => DateTime.now().hour < 12 ? 'morning' : 'afternoon';

String sessionLabel(String s) {
  if (s == 'morning') return 'Morning';
  if (s == 'afternoon') return 'Afternoon';
  return 'Full day';
}