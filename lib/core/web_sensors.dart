/// Browser-only geo-compass sensor access for the Qibla page.
///
/// `flutter_compass_v2` has no web implementation at all (its `events`
/// getter just returns `Stream.empty()` on web — see its source), so on
/// Flutter Web we talk to the `deviceorientation`/`deviceorientationabsolute`
/// browser APIs directly via `dart:js_interop`. Native Android/iOS builds
/// never import the web implementation (conditional export below), so the
/// existing native compass path is completely unaffected.
library;

export 'web_sensors_stub.dart' if (dart.library.js_interop) 'web_sensors_web.dart';

/// One reading from the browser's orientation sensor.
class WebOrientationEvent {
  /// True-north heading in degrees (0-360, clockwise), or null if this
  /// reading cannot be trusted as an absolute compass bearing (e.g. a
  /// browser that only ever exposes relative `deviceorientation` data with
  /// no `absolute` flag and no `webkitCompassHeading`).
  final double? heading;

  const WebOrientationEvent(this.heading);
}
