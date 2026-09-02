import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';

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

class QiblaPage extends ConsumerStatefulWidget {
  const QiblaPage({super.key});

  @override
  ConsumerState<QiblaPage> createState() => _QiblaPageState();
}

class _QiblaPageState extends ConsumerState<QiblaPage> with TickerProviderStateMixin {
  bool _wasAligned = false;
  bool _isAligned = false;
  late AnimationController _pulseController;

  // Konum & pusula verileri
  double? _qiblaDegree; // Kuzeyden Kabe'ye sabit açı (konuma göre)
  double _heading = 0; // Pusulanın anlık heading'i
  bool _locationLoading = true;
  String? _errorMessage;
  String _locationInfo = '';
  StreamSubscription? _compassSubscription;

  // Kıble hizası eşiği (derece)
  static const double _alignmentThreshold = 5.0;

  // Titreşim için platform channel
  static const _vibrationChannel = MethodChannel('com.tvaap/vibration');

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _initQibla();
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initQibla() async {
    try {
      // 1. Konum izni kontrol
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationLoading = false;
          _errorMessage = 'GPS kapalı. Lütfen konum servisini açın.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationLoading = false;
            _errorMessage = 'Konum izni reddedildi.';
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationLoading = false;
          _errorMessage = 'Konum izni kalıcı olarak reddedildi.\nAyarlardan izin verin.';
        });
        return;
      }

      // 2. Güncel konumu al (her sayfa açılışında taze konum)
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // 3. Kıble açısını hesapla
      final qiblaDegree = _qiblaDegreeFromLocation(position.latitude, position.longitude);

      setState(() {
        _qiblaDegree = qiblaDegree;
        _locationLoading = false;
        _locationInfo = _formatLocationInfo(position);
      });

      // 4. Pusula dinlemeye başla — hizalama kontrolü BURADA yapılıyor
      _compassSubscription = FlutterCompass.events?.listen((event) {
        if (!mounted || _qiblaDegree == null) return;

        final heading = event.heading ?? 0;
        final diff = _qiblaOffset(_qiblaDegree!, heading);
        final aligned = diff.abs() < _alignmentThreshold;

        // Hizaya yeni girdiyse titret
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
        });
      });
    } catch (e) {
      setState(() {
        _locationLoading = false;
        _errorMessage = 'Konum alınamadı: $e';
      });
    }
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Yükleniyor
    if (_locationLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Konumunuz alınıyor...', style: TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }

    // Hata
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _locationLoading = true;
                    _errorMessage = null;
                  });
                  _initQibla();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    // Pusula
    final double diff = _calculateDifference();
    final bool isAligned = _isAligned;

    // Yakınlık göstergesi rengi
    final Color indicatorColor = isAligned
        ? Colors.green
        : (diff.abs() < 30 ? Colors.orange : Colors.red.shade300);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final compassSize = isLandscape ? (constraints.maxHeight * 0.46).clamp(160.0, 220.0) : 300.0;
        final gap = isLandscape ? 8.0 : 24.0;

        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: isLandscape ? 8 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
        children: [
          // Durum göstergesi
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: isAligned
                      ? Colors.green.withValues(alpha: 0.1 + _pulseController.value * 0.15)
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
                      isAligned ? Icons.check_circle : Icons.explore,
                      color: indicatorColor,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isAligned
                          ? "Kıble Yönündesiniz!"
                          : "${diff.abs().toStringAsFixed(0)}° ${diff > 0 ? 'sağa' : 'sola'} dönün",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: indicatorColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

                  SizedBox(height: gap),

          // PUSULA ALANI
                  _CompassView(
                    size: compassSize,
                    heading: _heading,
                    qiblaDegree: _qiblaDegree!,
                    isAligned: isAligned,
                    pulseController: _pulseController,
          ),

                  SizedBox(height: gap),

          // Kıble açısı ve konum bilgisi
          Text(
            "Kıble açısı: ${_qiblaDegree!.toStringAsFixed(1)}°",
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            "Konum: $_locationInfo",
                    textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black38),
          ),

                  SizedBox(height: gap),
                  Text(
                    isLandscape
                        ? "Telefonu düz tutun; ok Kabe'yi gösterdiğinde titreşim hissedeceksiniz."
                        : "Telefonu düz tutun ve yavaşça çevirin.\nOk Kabe'yi gösterdiğinde titreşim hissedeceksiniz.",
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
