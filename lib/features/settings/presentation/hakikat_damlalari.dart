import 'dart:async';
import 'dart:convert';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HakikatDamlalariPage extends StatefulWidget {
  const HakikatDamlalariPage({super.key});

  @override
  State<HakikatDamlalariPage> createState() => _HakikatDamlalariPageState();
}

class _HakikatDamlalariPageState extends State<HakikatDamlalariPage> {
  final CarouselSliderController _carouselController =
  CarouselSliderController();

  final ValueNotifier<int> _currentIndex = ValueNotifier<int>(0);

  List<SlideItem> slides = [];
  bool isLoading = true;
  bool autoPlay = true;
  int autoSeconds = 8;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadSlides();
  }

  Future<void> _loadSlides() async {
    try {
      final jsonString =
      await rootBundle.loadString('assets/data/slides.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      slides = jsonList.map((e) => SlideItem.fromJson(e)).toList();
    } catch (e, s) {
      debugPrint('SLIDES HATASI: $e');
      debugPrint('$s');
      slides = [];
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();

    if (!autoPlay || slides.isEmpty) return;

    _timer = Timer.periodic(Duration(seconds: autoSeconds), (_) {
      if (!mounted || slides.isEmpty) return;
      final next = (_currentIndex.value + 1) % slides.length;
      _carouselController.animateToPage(next);
    });
  }

  void _toggleAutoPlay() {
    setState(() {
      autoPlay = !autoPlay;
    });
    _startTimer();
  }

  void _goNext() {
    if (slides.isEmpty) return;
    final next = (_currentIndex.value + 1) % slides.length;
    _carouselController.animateToPage(next);
  }

  void _goPrev() {
    if (slides.isEmpty) return;
    final prev = (_currentIndex.value - 1 + slides.length) % slides.length;
    _carouselController.animateToPage(prev);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _currentIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (slides.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Hakikat Damlaları'),
          backgroundColor: Colors.black,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'slides.json bulunamadı, boş ya da hatalı.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CarouselSlider.builder(
              carouselController: _carouselController,
              itemCount: slides.length,
              itemBuilder: (context, index, realIndex) {
                return _SlideCard(item: slides[index]);
              },
              options: CarouselOptions(
                viewportFraction: 1,
                height: double.infinity,
                autoPlay: false,
                enlargeCenterPage: false,
                onPageChanged: (index, reason) {
                  _currentIndex.value = index;
                },
              ),
            ),
          ),

          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_stories, color: Colors.white),
                    const SizedBox(width: 10),
                    const Text(
                      'Hakikat Damlaları',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      tooltip: autoPlay ? 'Durdur' : 'Başlat',
                      onPressed: _toggleAutoPlay,
                      icon: Icon(
                        autoPlay ? Icons.pause_circle : Icons.play_circle,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Yavaşlat',
                      onPressed: () {
                        if (autoSeconds < 20) {
                          setState(() {
                            autoSeconds++;
                          });
                          _startTimer();
                        }
                      },
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${autoSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Hızlandır',
                      onPressed: () {
                        if (autoSeconds > 3) {
                          setState(() {
                            autoSeconds--;
                          });
                          _startTimer();
                        }
                      },
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavButton(
                icon: Icons.arrow_back_ios_new,
                onTap: _goPrev,
              ),
            ),
          ),

          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _NavButton(
                icon: Icons.arrow_forward_ios,
                onTap: _goNext,
              ),
            ),
          ),

          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: _currentIndex,
              builder: (context, current, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(slides.length, (index) {
                    final active = index == current;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 28 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(30),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SlideItem {
  final int image;
  final String category;
  final String title;
  final String source;
  final String date;
  final String text;

  SlideItem({
    required this.image,
    required this.category,
    required this.title,
    required this.source,
    required this.date,
    required this.text,
  });

  factory SlideItem.fromJson(Map<String, dynamic> json) {
    return SlideItem(
      image: json['image'] ?? 1,
      category: json['category'] ?? '',
      title: json['title'] ?? '',
      source: json['source'] ?? '',
      date: json['date'] ?? '',
      text: json['text'] ?? '',
    );
  }
}

class _SlideCard extends StatelessWidget {
  final SlideItem item;

  const _SlideCard({required this.item});

  double _calculateFontSize(String text) {
    final length = text.length;

    if (length <= 60) return 34;
    if (length <= 110) return 30;
    if (length <= 180) return 27;
    if (length <= 260) return 24;
    return 21;
  }

  @override
  Widget build(BuildContext context) {
    final textFontSize = _calculateFontSize(item.text);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/all/img_${item.image}.jpg',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade900,
              alignment: Alignment.center,
              child: Text(
                'Resim bulunamadı:\nimg_${item.image}.jpg',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),

        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x99000000),
                Color(0x44000000),
                Color(0xCC000000),
              ],
            ),
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 34, 48, 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.source,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.category,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 26,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    item.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: textFontSize,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 18),

              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.25),
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}