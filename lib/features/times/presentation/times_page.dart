import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_drawer.dart';
import '../../daily_content/presentation/daily_content_page.dart';
import '../../locations/data/location_providers.dart';
import '../../locations/data/models.dart';
import '../../../theme.dart';
import 'slayt_widget.dart';
import 'time_utils.dart';

final timesProvider = FutureProvider.family<List<Vakit>, String>((ref, ilceId) async {
  final repo = ref.watch(locationRepoProvider);
  return repo.vakitler(ilceId);
});

class TimesPage extends ConsumerStatefulWidget {
  final Ulke ulke;
  final Sehir sehir;
  final Ilce ilce;

  const TimesPage({super.key, required this.ulke, required this.sehir, required this.ilce});

  @override
  ConsumerState<TimesPage> createState() => _TimesPageState();
}

class _TimesPageState extends ConsumerState<TimesPage> {
  Timer? _timer;

  List<Vakit>? _list; // ✅ listeyi sakla
  Vakit? _today;

  DateTime _now = DateTime.now();
  DateTime _lastDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day); // ✅

  ({String name, DateTime time})? _nextPrayer;
  String? _currentPrayerName;
  Duration _remaining = Duration.zero;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final list = await ref.read(timesProvider(widget.ilce.ilceId).future);
    if (!mounted) return;

    _list = list; // ✅

    final initialNow = phoneLocalNow();
    final today = _findToday(list, initialNow);
    if (today != null) {
      setState(() {
        _today = today;
        _now = phoneLocalNow();
        _lastDay = DateTime(_now.year, _now.month, _now.day);
        _updateCountdown(today);
      });

      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _today == null) return;

      final now = phoneLocalNow();
      final dayKey = DateTime(now.year, now.month, now.day);

      // ✅ Gün değişti mi?
      if (_list != null && dayKey != _lastDay) {
        final oldMoonUrl = _today?.ayinSekliURL;

        _lastDay = dayKey;
        final newToday = _findToday(_list!, now);

        if (newToday != null) {
          setState(() {
            _today = newToday;
          });
          if (oldMoonUrl != null) {
            await NetworkImage(oldMoonUrl).evict();
          }
          await NetworkImage(newToday.ayinSekliURL).evict();
        } else {
          // liste yeni günü kapsamıyorsa yeniden çek
          await _initData();
          return;
        }
      }

      setState(() {
        _now = now;
        _updateCountdown(_today!);
      });
    });
  }

  DateTime _parsePrayerTime(String timeStr, DateTime date) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  void _updateCountdown(Vakit today) {
    final tomorrow = _list == null ? null : _findToday(_list!, _now.add(const Duration(days: 1)));
    _nextPrayer = nextPrayerInfo(today, _now, tomorrow: tomorrow);
    _remaining = _nextPrayer!.time.difference(_now);

    final prayers = [
      (name: 'İmsak', time: _parsePrayerTime(today.imsak, _now)),
      (name: 'Güneş', time: _parsePrayerTime(today.gunes, _now)),
      (name: 'Öğle', time: _parsePrayerTime(today.ogle, _now)),
      (name: 'İkindi', time: _parsePrayerTime(today.ikindi, _now)),
      (name: 'Akşam', time: _parsePrayerTime(today.aksam, _now)),
      (name: 'Yatsı', time: _parsePrayerTime(today.yatsi, _now)),
    ];

    final passedPrayers = prayers.where((p) => p.time.isBefore(_now));
    if (passedPrayers.isNotEmpty) {
      _currentPrayerName = passedPrayers.last.name;
    } else {
      _currentPrayerName = 'Yatsı';
    }
  }

  Vakit? _findToday(List<Vakit> list, DateTime now) {
    try {
      return list.firstWhere((v) {
        final parts = v.miladiTarihKisaIso8601.split('.');
        if (parts.length != 3) return false;

        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d == null || m == null || y == null) return false;

        final date = DateTime(y, m, d);
        return date.year == now.year && date.month == now.month && date.day == now.day;
      });
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTimes = ref.watch(timesProvider(widget.ilce.ilceId));

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: tvBgDark,
        child: SafeArea(
          child: asyncTimes.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
            error: (e, _) => Center(child: Text("Hata: $e", style: const TextStyle(color: Colors.white))),
            data: (list) {
              // liste yeni geldiyse cache'i güncelle (hot reload / refetch durumları için)
              _list ??= list;

              if (_today == null) return const Center(child: CircularProgressIndicator(color: Colors.white));

              return OrientationBuilder(
                builder: (context, orientation) {
                  final isPortrait = orientation == Orientation.portrait;

                  Widget bottomBar() {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xCC000000), Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildPrayerTimesHorizontalStrip(_today!, _currentPrayerName, context),
                          ),
                          const SizedBox(width: 10),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const DailyContentPage()),
                              ),
                              borderRadius: BorderRadius.circular(30),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(Icons.auto_stories_outlined, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _scaffoldKey.currentState?.openDrawer(),
                              borderRadius: BorderRadius.circular(30),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Icon(Icons.menu, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (isPortrait) {
                    return Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: SlaytWidget(
                                height: double.infinity,
                                userImages: const [],
                                hideOnPortrait: false,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              color: const Color(0x22000000),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              child: Column(
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      widget.ilce.ilceAdi.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Divider(color: Colors.white10, height: 10),
                                  NextPrayerCountdownWidget(
                                    remaining: _remaining,
                                    nextPrayer: _nextPrayer,
                                    today: _today!,
                                    now: _now,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        bottomBar(),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 75,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 10, 4, 4),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: const SlaytWidget(
                                    height: double.infinity,
                                    userImages: [],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 25,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2, right: 4, bottom: 4),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 2),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            widget.ilce.ilceAdi.toUpperCase(),
                                            maxLines: 1,
                                            softWrap: false,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Divider(color: Colors.white10, height: 2),
                                      NextPrayerCountdownWidget(
                                        remaining: _remaining,
                                        nextPrayer: _nextPrayer,
                                        today: _today!,
                                        now: _now,
                                        compact: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      bottomBar(),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPrayerTimesHorizontalStrip(Vakit today, String? currentPrayerName, BuildContext context) {
    final prayerTimes = {
      'İmsak': today.imsak,
      'Güneş': today.gunes,
      'Öğle': today.ogle,
      'İkindi': today.ikindi,
      'Akşam': today.aksam,
      'Yatsı': today.yatsi,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: prayerTimes.entries.map((entry) {
        final name = entry.key;
        final time = entry.value;
        final isCurrent = name == currentPrayerName;

        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: isCurrent ? dashboardAccentGold.withValues(alpha: 0.35) : const Color(0x33000000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCurrent ? dashboardAccentGold : Colors.white24,
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    time,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

String formatDurationHHMMSS(Duration d) {
  if (d.isNegative) return '00:00:00';
  String twoDigits(int n) => n.toString().padLeft(2, "0");
  return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
}

class NextPrayerCountdownWidget extends StatelessWidget {
  final Duration remaining;
  final ({String name, DateTime time})? nextPrayer;
  final Vakit today;
  final DateTime now;
  final bool compact;

  const NextPrayerCountdownWidget({
    super.key,
    required this.remaining,
    required this.nextPrayer,
    required this.today,
    required this.now,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final prayerName = nextPrayer?.name ?? '';
    final title = prayerName == 'Güneş' ? 'Güneşin Doğmasına' : '$prayerName Vaktine';

    final titleGap = compact ? 10.0 : 20.0;
    final countdownFont = compact ? 38.0 : 50.0;
    final clockFont = compact ? 16.0 : 20.0;
    final moonHeight = compact ? 48.0 : 65.0;
    final boxVPad = compact ? 6.0 : 10.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        LiveClock(time: now, fontSize: clockFont),
        const Divider(color: Colors.white24, height: 1),
        SizedBox(height: titleGap),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ),
        ),
        const SizedBox(height: 6),
        CountdownText(
          value: formatDurationHHMMSS(remaining),
          fontSize: countdownFont,
        ),
        const SizedBox(height: 4),
        Image.network(
          today.ayinSekliURL,
          key: ValueKey('${today.ayinSekliURL}-${today.miladiTarihKisaIso8601}'),
          height: moonHeight,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.brightness_3, color: Colors.white70, size: moonHeight),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: boxVPad),
          decoration: BoxDecoration(
            color: const Color(0x4D000000),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  today.miladiTarihUzun,
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 14 : null,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  today.hicriTarihUzun,
                  textAlign: TextAlign.center,
                  style: textTheme.titleSmall?.copyWith(
                    color: Colors.white70,
                    fontSize: compact ? 12 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CountdownText extends StatelessWidget {
  final String value;
  final double fontSize;

  const CountdownText({
    super.key,
    required this.value,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: fontSize + 4,
      child: CustomPaint(
        painter: CountdownTextPainter(
          value: value,
          fontSize: fontSize,
        ),
      ),
    );
  }
}

class CountdownTextPainter extends CustomPainter {
  final String value;
  final double fontSize;

  const CountdownTextPainter({
    required this.value,
    required this.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontFamily: 'monospace',
          height: 1.0,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: double.infinity);

    final scale = painter.width > size.width ? size.width / painter.width : 1.0;
    final dx = (size.width - painter.width * scale) / 2;
    final dy = (size.height - painter.height * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CountdownTextPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.fontSize != fontSize;
  }
}

class LiveClock extends StatelessWidget {
  final DateTime time;
  final double fontSize;

  const LiveClock({super.key, required this.time, this.fontSize = 20});

  @override
  Widget build(BuildContext context) {
    final time =
        "${this.time.hour.toString().padLeft(2, '0')}:"
        "${this.time.minute.toString().padLeft(2, '0')}:"
        "${this.time.second.toString().padLeft(2, '0')}";

    return Text(
      time,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: Colors.white60,
        fontFamily: 'monospace',
      ),
    );
  }
}
