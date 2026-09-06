import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;

/// Bu platformda bildirim/ses sisteminin *gerçekte* ne yapabildiğini
/// anlatan, kullanıcıya gösterilecek dürüst bir özet.
///
/// Hiçbir platformda desteklenmeyen bir davranış "çalışıyor" gibi
/// gösterilmez; burada anlatılanlar koddaki gerçek davranışla eşleşir
/// (bkz. `notification_service.dart`, `alarm_page.dart`).
class NotificationCapabilities {
  final String platformLabel;
  final bool backgroundSchedulingWorks;
  final bool fullLengthAdhanInBackground;
  final bool fullLengthCustomAudioInBackground;
  final String note;

  const NotificationCapabilities({
    required this.platformLabel,
    required this.backgroundSchedulingWorks,
    required this.fullLengthAdhanInBackground,
    required this.fullLengthCustomAudioInBackground,
    required this.note,
  });

  static NotificationCapabilities current() {
    if (kIsWeb) {
      return const NotificationCapabilities(
        platformLabel: 'Web',
        backgroundSchedulingWorks: false,
        fullLengthAdhanInBackground: false,
        fullLengthCustomAudioInBackground: false,
        note: 'Tarayıcıda arka plan bildirimi yoktur: ezan ve bildirim sesleri yalnızca bu sekme açık ve '
            'uygulama önplandayken çalışır. Sekme kapatılır veya cihaz uykuya geçerse ses çalınmaz.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const NotificationCapabilities(
          platformLabel: 'Android',
          backgroundSchedulingWorks: true,
          fullLengthAdhanInBackground: true,
          fullLengthCustomAudioInBackground: true,
          note: 'Vakit geldiğinde tam ekran bildirim istenir. Android izinlerine ve cihaz durumuna göre '
              'ezan ekranı açılır veya bildirime dokunmanız gerekir. Seçilen ses ekran açıldığında başlar; '
              'ezan başladıktan sonra ekran kilitlense de oynatma servisiyle devam eder.',
        );
      case TargetPlatform.iOS:
        return const NotificationCapabilities(
          platformLabel: 'iOS',
          backgroundSchedulingWorks: true,
          fullLengthAdhanInBackground: false,
          fullLengthCustomAudioInBackground: false,
          note: 'iOS, arka planda çalan bildirim seslerini işletim sistemi düzeyinde 30 saniyeyle sınırlar. '
              'Bu nedenle uzun ezan kaydı veya kendi ses dosyanız yalnızca uygulama açıkken tam olarak çalar; '
              'uygulama kapalıyken/arka plandayken bildirim varsayılan kısa iOS bildirim sesiyle gelir.',
        );
      default:
        return const NotificationCapabilities(
          platformLabel: 'Masaüstü',
          backgroundSchedulingWorks: false,
          fullLengthAdhanInBackground: false,
          fullLengthCustomAudioInBackground: false,
          note: 'Bu platformda arka plan bildirimi desteklenmiyor; ses yalnızca uygulama açıkken çalar.',
        );
    }
  }
}
