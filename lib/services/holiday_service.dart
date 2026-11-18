import 'absence_rules.dart';
import 'supabase_client.dart';

class HolidayService {
  static Future<List<Map<String, dynamic>>> all() async {
    final rows = await supabase
        .from('holidays')
        .select('id, name, start_date, end_date')
        .order('start_date');
    return List<Map<String, dynamic>>.from(rows);
  }

  static Map<String, dynamic>? onDate(
      List<Map<String, dynamic>> list, DateTime d) {
    final day = dateOnly(d);
    for (final h in list) {
      if ((h['start_date'] as String).compareTo(day) <= 0 &&
          (h['end_date'] as String).compareTo(day) >= 0) {
        return h;
      }
    }
    return null;
  }

  /// Today's holiday, or null (also null if the check fails, e.g. offline).
  static Future<Map<String, dynamic>?> today() async {
    try {
      return onDate(await all(), DateTime.now());
    } catch (_) {
      return null;
    }
  }
}