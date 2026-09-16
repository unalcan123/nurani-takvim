/// Non-web fallback: native platforms keep using `flutter_compass_v2`
/// directly (see `qibla_page.dart`) and never call into this file, but it
/// must still exist and compile for non-web builds.
library;

import 'web_sensors.dart';

bool get hasDeviceOrientationApi => false;

bool get needsMotionPermission => false;

/// Non-web builds run as a native app, never an insecure page.
bool get isSecureContext => true;

Future<bool> requestMotionPermission() async => false;

Stream<WebOrientationEvent> orientationEvents() => const Stream.empty();
