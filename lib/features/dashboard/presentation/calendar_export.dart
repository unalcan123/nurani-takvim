import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bir namaz vaktini cihazın takvimine ekler.
///
/// Mobil/masaüstü (Android/iOS/macOS/Windows/Linux): `add_2_calendar`
/// paketiyle işletim sisteminin kendi takvim uygulamasını açar.
/// Web: `add_2_calendar` içeride `dart:io Platform` kullandığı için web'de
/// çalışmaz — bunun yerine Google Takvim'in "etkinlik ekle" linkini yeni
/// sekmede açar.
Future<void> addPrayerToDeviceCalendar(
  BuildContext context, {
  required String title,
  required DateTime start,
  Duration duration = const Duration(minutes: 30),
}) async {
  final end = start.add(duration);

  if (kIsWeb) {
    final uri = _googleCalendarUri(title: title, start: start, end: end);
    final launched = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takvim sayfası açılamadı.')),
      );
    }
    return;
  }

  final added = await Add2Calendar.addEvent2Cal(
    Event(title: title, startDate: start, endDate: end, description: 'Ezan Vakti uygulamasından eklendi.'),
  );
  if (!added && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Takvime eklenemedi.')),
    );
  }
}

Uri _googleCalendarUri({required String title, required DateTime start, required DateTime end}) {
  String fmt(DateTime d) {
    final utc = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${fmt(start)}/${fmt(end)}',
  });
}
