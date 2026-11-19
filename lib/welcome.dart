import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'util.dart';
import 'version.dart';
import 'widgets.dart';
import 'whats_new.g.dart';

class _Card {
  final String title, body;
  final List<Color> hero;
  final Widget Function() art;
  const _Card(this.title, this.body, this.hero, this.art);
}

/// 3.0: "Poyraz Player'a hoş geldin" turu (tam ekran, kaydırmalı kartlar)
class WelcomeTour extends StatefulWidget {
  const WelcomeTour({super.key});
  @override
  State<WelcomeTour> createState() => _WelcomeTourState();
}

class _WelcomeTourState extends State<WelcomeTour> {
  final pc = PageController();
  int i = 0;

  static Widget _glassBox(Widget child, {double w = 150, double h = 150, double r = 34}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: const Color(0x8C16171B),
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: Colors.white.withAlpha(46)),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 20))],
        ),
        child: Center(child: child),
      );

  late final cards = <_Card>[
    _Card('Poyraz Player’a hoş geldin',
        'Jelly+ artık Poyraz Player. Yeni isim, yeni logo ve baştan tasarlanmış sade bir arayüz.',
        const [Color(0xFF2F4A63), Color(0xFF1A2A3A)],
        () => _glassBox(const PMark(size: 104))),
    _Card('Tam bir iPhone uygulaması',
        'iOS anahtarları, cam menüler, havada duran alt bar. Dokunuşlarda hafif titreşim; dalga efektleri yok.',
        const [Color(0xFF3A3F57), Color(0xFF1B1D2A)],
        () => _glassBox(const Icon(Icons.phone_iphone_rounded, size: 76, color: Colors.white), w: 130, h: 180)),
    _Card('Yepyeni oynatıcı',
        'Sade kontroller, altta bölüm kartları. Sol tarafta kaydırarak parlaklık; karanlık sahneler için görüntü ayarları.',
        const [Color(0xFF3E352B), Color(0xFF1D1914)],
        () => _glassBox(
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.replay_10_rounded, size: 34, color: Colors.white),
              SizedBox(width: 18),
              Icon(Icons.pause_circle_filled_rounded, size: 64, color: Colors.white),
              SizedBox(width: 18),
              Icon(Icons.forward_10_rounded, size: 34, color: Colors.white),
            ]),
            w: 270,
            h: 150,
            r: 24)),
    _Card('Her şey yerinde',
        'Girişlerin, indirdiklerin, izleme geçmişin ve ayarların olduğu gibi duruyor. iPad düzeni ve keşif özellikleri sonraki betalarda.',
        const [Color(0xFF34506B), Color(0xFF16222E)],
        () => Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(26), shape: BoxShape.circle, border: Border.all(color: Colors.white.withAlpha(46))),
              child: const Icon(Icons.check_rounded, size: 72, color: Colors.white),
            )),
  ];

  void next() {
    HapticFeedback.selectionClick();
    if (i == cards.length - 1) {
      Navigator.of(context).pop();
    } else {
      pc.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = cards[i];
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          height: h * .62,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomCenter,
              colors: [c.hero[0], c.hero[1], kBg],
              stops: const [0, .55, 1],
            ),
          ),
        ),
        Container(
          height: h * .62,
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.5, -.5),
              radius: .8,
              colors: [Color(0x4DFFD6AA), Color(0x00FFD6AA)],
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                child: Opacity(
                  opacity: i == cards.length - 1 ? 0 : 1,
                  child: Pressable(
                    onTap: () => pc.animateToPage(cards.length - 1,
                        duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic),
                    child: Glass(
                      radius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: const Text('Atla', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pc,
                itemCount: cards.length,
                onPageChanged: (k) => setState(() => i = k),
                itemBuilder: (_, k) {
                  final x = cards[k];
                  return Column(children: [
                    Expanded(flex: 11, child: Center(child: x.art())),
                    Expanded(
                      flex: 9,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(x.title,
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.9, height: 1.1)),
                          const SizedBox(height: 12),
                          Text(x.body, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xB8F5F5F7))),
                        ]),
                      ),
                    ),
                  ]);
                },
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 0; k < cards.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: k == i ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: k == i ? Colors.white : Colors.white30, borderRadius: BorderRadius.circular(3)),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
              child: PillButton(i == cards.length - 1 ? 'Başla' : 'Devam', height: 54, expand: true, onTap: next),
            ),
          ]),
        ),
      ]),
    );
  }
}

const _icons = {
  'download': Icons.download_for_offline_outlined,
  'request': Icons.playlist_add,
  'preview': Icons.view_carousel_outlined,
  'next': Icons.skip_next_outlined,
  'subtitles': Icons.subtitles_outlined,
  'layout': Icons.dashboard_outlined,
  'person': Icons.person_outline,
  'library': Icons.video_library_outlined,
  'update': Icons.new_releases_outlined,
  'audio': Icons.graphic_eq,
  'night': Icons.nightlight_outlined,
  'speed': Icons.speed,
};

/// 3.1 ve sonrası: küçük güncellemelerde uygulamanın üstüne açılan cam yenilikler sayfası.
Future<void> showSmallWhatsNew(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF2202026),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: const Color(0xFF16171B), borderRadius: BorderRadius.circular(11)),
                child: const Center(child: PMark(size: 30)),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${kVersion.split('-').first.split('.').take(2).join('.')}\'de yeni',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -.5)),
                Text('Poyraz Player $kVersion', style: const TextStyle(fontSize: 12, color: Color(0x8CF5F5F7))),
              ]),
            ]),
            const SizedBox(height: 18),
            for (final w in kWhatsNew)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: Colors.white.withAlpha(26), shape: BoxShape.circle),
                    child: Icon(_icons[w[0]] ?? Icons.auto_awesome_outlined, size: 20, color: kAccent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(w[1], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(w[2], style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xADF5F5F7))),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            PillButton('Tamam', height: 52, expand: true, onTap: () => Navigator.pop(c)),
          ]),
        ),
      ),
    );
