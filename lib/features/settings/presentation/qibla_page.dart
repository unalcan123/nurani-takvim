import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/web_sensors.dart' as web_sensors;
import '../data/prefs_repository.dart';

// Kabe koordinatları
const double _kaabaLat = 21.4225;
const double _kaabaLon = 39.8262;

/// Kuzeyden Kabe'ye olan açıyı hesapla (derece)
double _qiblaDegreeFromLocation(double lat, double lon) {
  final userLat = lat * pi / 180;
  final userLon = lon * pi / 180;
  final kaabaLat = _kaabaLat * pi / 180;
  final kaabaLon = _kaabaLon * pi / 180;
  final deltaLon = kaabaLon - userLon;

  final bearing = atan2(
    sin(deltaLon),
    cos(userLat) * tan(kaabaLat) - sin(userLat) * cos(deltaLon),
  );

  return (bearing * 180 / pi + 360) % 360;
}

/// Kıble açısı ile telefon yönü arasındaki farkı hesapla (-180 ile 180 arası)
double _qiblaOffset(double qiblaDegree, double phoneHeading) {
  var offset = (qiblaDegree - phoneHeading) % 360;
  if (offset > 180) offset -= 360;
  if (offset < -180) offset += 360;
  return offset;
}

class _LocationFailure implements Exception {
  final String message;
  const _LocationFailure(this.message);
}

/// Sayfanın hangi aşamada olduğu.
enum _Stage {
  /// Yalnızca web: konum/pusula isteği kullanıcı dokunuşuyla başlamadan önce.
  needsGesture,
  locating,
  ready,
  error,
}

class QiblaPage extends ConsumerStatefulWidget {
  const QiblaPage({super.key});

  @override
  ConsumerState<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends ConsumerState<QiblaPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _wasAligned = false;
  bool _isAligned = false;
  late AnimationController _pulseController;

  _Stage _stage = _Stage.locating;
  String? _errorMessage;

  // Konum & pusula verileri
  double? _qiblaDegree; // Kuzeyden Kabe'ye sabit açı (konuma göre)
  double _heading = 0; // Pusulanın anlık heading'i
  String _locationInfo = '';
  bool _locationApprox = false;

  /// Pusuladan en az bir kullanılabilir (mutlak) okuma geldi mi?
  bool _compassLive = false;
  String? _compassUnavailableReason;
  bool _motionPermissionDenied = false;
  StreamSubscription<double?>? _compassSub;
  Timer? _compassTimeoutTimer;

  // Kıble hizası eşiği (derece)
  static const double _alignmentThreshold = 5.0;

  // Titreşim için platform channel
  static const _vibrationChannel = MethodChannel('com.tvaap/vibration');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (kIsWeb) {
      // Web'de konum/pusula izinleri sayfa açılır açılmaz değil, kullanıcı
      // "Etkinleştir" düğmesine dokununca istenir (bkz. _onEnablePressed).
      _stage = _Stage.needsGesture;
    } else {
      _stage = _Stage.locating;
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _compassSub?.cancel();
    _compassTimeoutTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Arka plana giderken sensör dinleyicisini kapat, öne dönünce (aynı
    // kıble açısıyla) yeniden başlat — pusula donanımı bazı cihazlarda
    // arka plandan sonra sessiz kalabiliyor.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _compassSub?.cancel();
      _compassSub = null;
      _compassTimeoutTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_stage == _Stage.ready && _compassSub == null) {
        _startCompass();
      }
    }
  }

  /// Web'de yalnızca kullanıcı dokunuşuyla çağrılmalı: iOS Safari, hareket
  /// sensörü iznini yalnızca doğrudan bir dokunuş işleyicisinden gelen
  /// çağrılarda (öncesinde `await` olmadan) gösterir.
  Future<void> _onEnablePressed() async {
    var motionGranted = true;
    if (kIsWeb && web_sensors.needsMotionPermission) {
      motionGranted = await web_sensors.requestMotionPermission();
    }
    _motionPermissionDenied = !motionGranted;
    await _start();
  }

  Future<void> _start() async {
    setState(() {
      _stage = _Stage.locating;
      _errorMessage = null;
    });

    if (kIsWeb && !web_sensors.isSecureContext) {
      setState(() {
        _stage = _Stage.error;
        _errorMessage =
            'Konum ve pusula özellikleri yalnızca güvenli (https://) bağlantılarda çalışır.\nLütfen siteyi https ile açın.';
      });
      return;
    }

    Position? position;
    String? locationError;
    try {
      position = await _getPosition();
    } on _LocationFailure catch (e) {
      locationError = e.message;
    } catch (e) {
      locationError = 'Konum alınamadı: $e';
    }

    double? qibla;
    var locationInfo = '';
    var approx = false;
    if (position != null) {
      qibla = _qiblaDegreeFromLocation(position.latitude, position.longitude);
      locationInfo = _formatLocationInfo(position);
    } else {
      final fallback = await _cityFallback();
      if (fallback != null) {
        qibla = fallback.angle;
        locationInfo = fallback.label;
        approx = true;
      }
    }

    if (!mounted) return;
    if (qibla == null) {
      setState(() {
        _stage = _Stage.error;
        _errorMessage = locationError ??
            'Konum alınamadı ve kayıtlı bir şehir de bulunamadı.';
      });
      return;
    }

    setState(() {
      _qiblaDegree = qibla;
      _locationInfo = locationInfo;
      _locationApprox = approx;
      _stage = _Stage.ready;
    });
    _startCompass();
  }

  Future<Position> _getPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const _LocationFailure('GPS kapalı. Lütfen konum servisini açın.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const _LocationFailure('Konum izni reddedildi.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const _LocationFailure(
        'Konum izni kalıcı olarak reddedildi.\nAyarlardan izin verin.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }

  /// Konum alınamazsa, kayıtlı (namaz vakitleri için seçilmiş) şehri
  /// yaklaşık bir kıble açısı için kullan — şehir merkezine göre yaklaşık
  /// olduğu açıkça belirtilir.
  Future<({double angle, String label})?> _cityFallback() async {
    final saved = ref.read(prefsRepositoryProvider).getRecentLocations();
    if (saved.isEmpty) return null;
    final loc = saved.first;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final query = '${loc.ilce.ilceAdi}, ${loc.sehir.sehirAdi}, ${loc.ulke.ulkeAdi}';
      final response = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {'q': query, 'format': 'jsonv2', 'limit': 1},
        options: Options(headers: {'User-Agent': 'NuraniTakvimApp/1.0'}),
      );
      final results = response.data as List;
      if (results.isEmpty) return null;
      final first = results.first as Map<String, dynamic>;
      final lat = double.parse(first['lat'] as String);
      final lon = double.parse(first['lon'] as String);
      return (
        angle: _qiblaDegreeFromLocation(lat, lon),
        label: '${loc.ilce.ilceAdi}, ${loc.sehir.sehirAdi} (yaklaşık, şehir merkezine göre)',
      );
    } catch (_) {
      return null;
    }
  }

  void _startCompass() {
    _compassSub?.cancel();
    _compassTimeoutTimer?.cancel();
    _compassLive = false;
    _compassUnavailableReason = null;

    if (kIsWeb && web_sensors.needsMotionPermission && _motionPermissionDenied) {
      setState(() => _compassUnavailableReason =
          'Pusula izni reddedildi. Sabit yön gösterimi kullanılıyor.');
      return;
    }

    Stream<double?> stream;
    if (kIsWeb) {
      if (!web_sensors.hasDeviceOrientationApi) {
        setState(() => _compassUnavailableReason =
            'Bu tarayıcı pusula sensörünü desteklemiyor. Sabit yön gösterimi kullanılıyor.');
        return;
      }
      stream = web_sensors.orientationEvents().map((e) => e.heading);
    } else {
      final native = FlutterCompass.events;
      if (native == null) {
        setState(() => _compassUnavailableReason =
            'Bu cihazda pusula sensörü bulunamadı. Sabit yön gösterimi kullanılıyor.');
        return;
      }
      stream = native.map((e) => e.heading);
    }

    // Sensör hiç veri göndermezse (desteklenmiyor, izin yok, donanım arızalı)
    // kullanıcıyı sonsuz beklemede bırakma — birkaç saniye sonra sabit
    // görünüme düş.
    _compassTimeoutTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _compassLive) return;
      setState(() => _compassUnavailableReason =
          'Canlı pusula verisi alınamadı. Sabit yön gösterimi kullanılıyor.');
    });

    _compassSub = stream.listen((heading) {
      if (!mounted || _qiblaDegree == null || heading == null) return;
      _compassTimeoutTimer?.cancel();
      final diff = _qiblaOffset(_qiblaDegree!, heading);
      final aligned = diff.abs() < _alignmentThreshold;

      if (aligned && !_wasAligned) {
        _vibrate();
        _pulseController.repeat(reverse: true);
      } else if (!aligned && _wasAligned) {
        _pulseController.stop();
        _pulseController.reset();
      }
      _wasAligned = aligned;

      setState(() {
        _heading = heading;
        _isAligned = aligned;
        _compassLive = true;
        _compassUnavailableReason = null;
      });
    });
  }

  /// Titreşim — birden fazla yöntem dener
  Future<void> _vibrate() async {
    // 1. Önce platform channel ile dene (en güvenilir)
    try {
      await _vibrationChannel.invokeMethod('vibrate', {'duration': 500});
      return;
    } catch (_) {}

    // 2. HapticFeedback ile dene (yedek)
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Kıble ile telefon yönü arasındaki farkı hesapla (-180 ile 180 arası)
  double _calculateDifference() {
    if (_qiblaDegree == null) return 180;
    return _qiblaOffset(_qiblaDegree!, _heading);
  }

  String _formatLocationInfo(Position position) {
    final savedLocations = ref.read(prefsRepositoryProvider).getRecentLocations();
    final savedLocation = savedLocations.isEmpty ? null : savedLocations.first;
    final coordinates = '${position.latitude.toStringAsFixed(2)}°, ${position.longitude.toStringAsFixed(2)}°';

    if (savedLocation == null) return coordinates;

    return '${savedLocation.ilce.ilceAdi}, ${savedLocation.sehir.sehirAdi} - $coordinates';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Kıble Yönü', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _Stage.needsGesture:
        return _EnableView(onPressed: _onEnablePressed);
      case _Stage.locating:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Konumunuz alınıyor...', style: TextStyle(fontSize: 16, color: Colors.black54)),
            ],
          ),
        );
      case _Stage.error:
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_off, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Konum alınamadı.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _onEnablePressed,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tekrar Dene', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        );
      case _Stage.ready:
        return _CompassBody(
          qiblaDegree: _qiblaDegree!,
          heading: _heading,
          isAligned: _isAligned,
          liveCompass: _compassUnavailableReason == null,
          compassUnavailableReason: _compassUnavailableReason,
          locationInfo: _locationInfo,
          locationApprox: _locationApprox,
          diff: _calculateDifference(),
          pulseController: _pulseController,
          onRetryCompass: _onEnablePressed,
        );
    }
  }
}

/// Web'de konum/pusula erişimini kullanıcı dokunuşuyla başlatan giriş ekranı.
/// Tarayıcılar bu izinleri sayfa açılışında değil, açık bir kullanıcı
/// eylemine bağlı olarak istemeyi bekler (özellikle iOS Safari'nin hareket
/// sensörü izni bunu şart koşar).
class _EnableView extends StatelessWidget {
  const _EnableView({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_outlined, size: 72, color: Colors.black45),
            const SizedBox(height: 20),
            const Text(
              'Kıble yönünü gösterebilmek için konumunuzu ve (varsa) pusula '
              'sensörünüzü kullanmamız gerekiyor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tarayıcınız bunun için izin isteyecek.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.my_location),
                label: const Text(
                  'Konumu ve Pusulayı Etkinleştir',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompassBody extends StatelessWidget {
  const _CompassBody({
    required this.qiblaDegree,
    required this.heading,
    required this.isAligned,
    required this.liveCompass,
    required this.compassUnavailableReason,
    required this.locationInfo,
    required this.locationApprox,
    required this.diff,
    required this.pulseController,
    required this.onRetryCompass,
  });

  final double qiblaDegree;
  final double heading;
  final bool isAligned;
  final bool liveCompass;
  final String? compassUnavailableReason;
  final String locationInfo;
  final bool locationApprox;
  final double diff;
  final AnimationController pulseController;
  final VoidCallback onRetryCompass;

  @override
  Widget build(BuildContext context) {
    // Canlı pusula yoksa kuzeyi sabit "yukarı" kabul eden statik bir
    // görünüme düş — bu, telefonun dönüşünü takip ETMEZ, yalnızca konumdan
    // hesaplanan sabit kıble açısını kuzeye göre gösterir.
    final effectiveHeading = liveCompass ? heading : 0.0;
    final effectiveAligned = liveCompass && isAligned;
    final indicatorColor = effectiveAligned
        ? Colors.green
        : (diff.abs() < 30 && liveCompass ? Colors.orange : Colors.red.shade300);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final compassSize = isLandscape
            ? (constraints.maxHeight * 0.46).clamp(160.0, 220.0)
            : (constraints.maxWidth * 0.72).clamp(220.0, 300.0);
        final gap = isLandscape ? 8.0 : 24.0;

        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: isLandscape ? 8 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (liveCompass)
                  AnimatedBuilder(
                    animation: pulseController,
                    builder: (context, child) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: effectiveAligned
                              ? Colors.green.withValues(alpha: 0.1 + pulseController.value * 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: indicatorColor.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              effectiveAligned ? Icons.check_circle : Icons.explore,
                              color: indicatorColor,
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                effectiveAligned
                                    ? "Kıble Yönündesiniz!"
                                    : "${diff.abs().toStringAsFixed(0)}° ${diff > 0 ? 'sağa' : 'sola'} dönün",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: indicatorColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                else
                  _StaticCompassNotice(reason: compassUnavailableReason, onRetry: onRetryCompass),

                SizedBox(height: gap),

                _CompassView(
                  size: compassSize,
                  heading: effectiveHeading,
                  qiblaDegree: qiblaDegree,
                  isAligned: effectiveAligned,
                  pulseController: pulseController,
                ),

                SizedBox(height: gap),

                Text(
                  "Kıble açısı: ${qiblaDegree.toStringAsFixed(1)}°",
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  "${locationApprox ? '≈ ' : ''}Konum: $locationInfo",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black38),
                ),

                SizedBox(height: gap),
                Text(
                  liveCompass
                      ? (isLandscape
                          ? "Telefonu düz tutun; ok Kabe'yi gösterdiğinde titreşim hissedeceksiniz."
                          : "Telefonu düz tutun ve yavaşça çevirin.\nOk Kabe'yi gösterdiğinde titreşim hissedeceksiniz.")
                      : "Bu görünüm telefonun dönüşünü TAKİP ETMİYOR — üstteki ok, kuzeye göre sabit kıble yönünü gösteriyor.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black45, fontSize: 14),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StaticCompassNotice extends StatelessWidget {
  const _StaticCompassNotice({required this.reason, required this.onRetry});
  final String? reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_off_outlined, color: Colors.orange.shade800, size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  reason ?? 'Canlı pusula kullanılamıyor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Pusulayı tekrar dene', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassView extends StatelessWidget {
  final double size;
  final double heading;
  final double qiblaDegree;
  final bool isAligned;
  final Animation<double> pulseController;

  const _CompassView({
    required this.size,
    required this.heading,
    required this.qiblaDegree,
    required this.isAligned,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    final compassAngle = -heading * (pi / 180);
    final qiblaOffset = _qiblaOffset(qiblaDegree, heading);
    final needleAngle = qiblaOffset * (pi / 180);

    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isAligned)
            AnimatedBuilder(
              animation: pulseController,
              builder: (context, child) {
                return Container(
                  width: size + 10 + pulseController.value * 20,
                  height: size + 10 + pulseController.value * 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.6 - pulseController.value * 0.4),
                      width: 4,
                    ),
                  ),
                );
              },
            ),
          SizedBox(
            width: size * 0.93,
            height: size * 0.93,
            child: Transform.rotate(
              angle: compassAngle,
              child: SvgPicture.asset(
                'assets/image/compass.svg',
                width: size * 0.93,
                height: size * 0.93,
                fit: BoxFit.contain,
              ),
            ),
          ),
          SizedBox(
            width: size * 0.8,
            height: size * 0.8,
            child: Transform.rotate(
              angle: needleAngle,
              child: SvgPicture.asset(
                'assets/image/needle.svg',
                width: size * 0.8,
                height: size * 0.8,
                fit: BoxFit.contain,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAligned ? Colors.green : Colors.black,
              boxShadow: isAligned ? [BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 2)] : [],
            ),
            padding: EdgeInsets.all(size * 0.02),
            child: Icon(
              isAligned ? Icons.check : Icons.location_on,
              color: Colors.white,
              size: size * 0.07,
            ),
          ),
        ],
      ),
    );
  }
}
