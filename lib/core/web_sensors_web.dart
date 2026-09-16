/// Web implementation of the orientation-sensor bridge, using raw
/// `dart:js_interop`/`dart:js_interop_unsafe` calls against
/// `window`/`DeviceOrientationEvent` — no `flutter_compass_v2` (web
/// unsupported) and no extra pub dependency (`package:web` isn't in
/// pubspec.yaml; the two `dart:js_interop*` core libraries are enough).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'web_sensors.dart';

bool _hasProperty(JSObject o, String name) => o.has(name);

JSObject? get _deviceOrientationEventClass {
  if (!globalContext.has('DeviceOrientationEvent')) return null;
  return globalContext.getProperty<JSObject?>('DeviceOrientationEvent'.toJS);
}

/// Whether this browser has the `DeviceOrientationEvent` API at all. If not,
/// there is no point prompting the user — the compass can never work here.
bool get hasDeviceOrientationApi => globalContext.has('DeviceOrientationEvent');

/// Geolocation and device-orientation sensors are both restricted by
/// browsers to secure contexts (HTTPS, or localhost). On a plain HTTP page
/// `navigator.geolocation`/orientation events silently fail or throw
/// unhelpful errors — detecting this lets the UI explain the real cause.
bool get isSecureContext =>
    globalContext.getProperty<JSBoolean?>('isSecureContext'.toJS)?.toDart ?? true;

/// iOS Safari (13+) gates motion/orientation events behind an explicit,
/// user-gesture-triggered permission prompt. Other browsers (incl. Android
/// Chrome) expose the events directly with no separate JS-level permission.
bool get needsMotionPermission {
  final doe = _deviceOrientationEventClass;
  return doe != null && doe.has('requestPermission');
}

/// Must be invoked directly from a tap/click handler (no `await` before this
/// call in the caller) — iOS Safari only honors the permission prompt when
/// it can trace the call back to a user gesture.
Future<bool> requestMotionPermission() async {
  final doe = _deviceOrientationEventClass;
  if (doe == null || !doe.has('requestPermission')) return true;
  try {
    final promise = doe.callMethod<JSPromise<JSString>>('requestPermission'.toJS);
    final result = await promise.toDart;
    return result.toDart == 'granted';
  } catch (_) {
    // Thrown when the call can't be tied to a user gesture, or the API
    // rejects for any other reason — treat as denied rather than crash.
    return false;
  }
}

double _screenOrientationAngle() {
  if (!globalContext.has('screen')) return 0;
  final screen = globalContext.getProperty<JSObject?>('screen'.toJS);
  if (screen == null) return 0;
  if (screen.has('orientation')) {
    final orientation = screen.getProperty<JSObject?>('orientation'.toJS);
    if (orientation != null && orientation.has('angle')) {
      return orientation.getProperty<JSNumber?>('angle'.toJS)?.toDartDouble ?? 0;
    }
  }
  // Legacy fallback for older/WebKit browsers without `screen.orientation`.
  if (globalContext.has('orientation')) {
    return globalContext.getProperty<JSNumber?>('orientation'.toJS)?.toDartDouble ?? 0;
  }
  return 0;
}

double? _extractHeading(JSObject event) {
  // iOS Safari: non-standard but always an absolute true-north heading when
  // present, regardless of the (always-false-on-iOS) `absolute` flag.
  double? webkitHeading;
  if (_hasProperty(event, 'webkitCompassHeading')) {
    webkitHeading = event.getProperty<JSNumber?>('webkitCompassHeading'.toJS)?.toDartDouble;
    // Apple docs: a negative `webkitCompassAccuracy` means the reading is
    // invalid and must not be used.
    if (_hasProperty(event, 'webkitCompassAccuracy')) {
      final accuracy = event.getProperty<JSNumber?>('webkitCompassAccuracy'.toJS)?.toDartDouble;
      if (accuracy != null && accuracy < 0) webkitHeading = null;
    }
  }
  if (webkitHeading != null) {
    return (webkitHeading - _screenOrientationAngle() + 360) % 360;
  }

  final isAbsolute = _hasProperty(event, 'absolute') &&
      (event.getProperty<JSBoolean?>('absolute'.toJS)?.toDart ?? false);
  if (!isAbsolute) {
    // Only relative `deviceorientation` data with no absolute reference —
    // per spec this must never be presented as a true-north heading.
    return null;
  }
  final alpha = event.getProperty<JSNumber?>('alpha'.toJS)?.toDartDouble;
  if (alpha == null) return null;
  final compassHeading = (360 - alpha) % 360;
  return (compassHeading - _screenOrientationAngle() + 360) % 360;
}

Stream<WebOrientationEvent> orientationEvents() {
  if (!hasDeviceOrientationApi) return const Stream.empty();

  late final StreamController<WebOrientationEvent> controller;
  JSFunction? jsListener;
  // Chrome/Android expose a dedicated absolute-only event; prefer it when
  // present so we never have to guess from the ambiguous plain event.
  final eventName = globalContext.has('ondeviceorientationabsolute')
      ? 'deviceorientationabsolute'
      : 'deviceorientation';

  void handle(JSObject event) {
    controller.add(WebOrientationEvent(_extractHeading(event)));
  }

  controller = StreamController<WebOrientationEvent>.broadcast(
    onListen: () {
      jsListener = ((JSObject event) => handle(event)).toJS;
      globalContext.callMethod('addEventListener'.toJS, eventName.toJS, jsListener);
    },
    onCancel: () {
      final listener = jsListener;
      if (listener != null) {
        globalContext.callMethod('removeEventListener'.toJS, eventName.toJS, listener);
      }
      jsListener = null;
    },
  );
  return controller.stream;
}
