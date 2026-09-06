import 'package:shared_preferences/shared_preferences.dart';

/// Shared by timer and notification entry points, including cold starts.
class PrayerEventStore {
  PrayerEventStore(this.prefs);
  final SharedPreferences prefs;
  static const key = 'adhan_handled_events_v2';

  static String eventId(DateTime date, String prayer) =>
      '${date.year}-${date.month}-${date.day}:$prayer';

  Future<bool> claim(DateTime date, String prayer) async {
    final id = eventId(date, prayer);
    final events = prefs.getStringList(key) ?? [];
    if (events.contains(id)) return false;
    events.add(id);
    await prefs.setStringList(
      key,
      events.length > 35 ? events.sublist(events.length - 35) : events,
    );
    return true;
  }
}
