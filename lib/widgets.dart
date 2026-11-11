import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'nav.dart';
import 'util.dart';

Widget netImg(String? url,
    {BoxFit fit = BoxFit.cover, Alignment align = Alignment.center, Widget? error}) {
  if (url == null || url.isEmpty) return error ?? const SizedBox.shrink();
  return CachedNetworkImage(
    imageUrl: url,
    fit: fit,
    alignment: align,
    fadeInDuration: const Duration(milliseconds: 200),
    placeholder: (_, __) => const SizedBox.shrink(),
    errorWidget: (_, __, ___) => error ?? const SizedBox.shrink(),
  );
}

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => RichText(
        text: TextSpan(
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -.5),
          children: const [
            TextSpan(text: 'Jelly', style: TextStyle(color: Colors.white)),
            TextSpan(text: '+', style: TextStyle(color: kBlue)),
          ],
        ),
      );
}

class AgeBadge extends StatelessWidget {
  final String? rating;
  final double size;
  const AgeBadge(this.rating, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) {
    final k = ageKey(rating);
    if (k == null) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black45,
        border: Border.all(color: Colors.white, width: size * .09),
      ),
      child: k == 'all'
          ? Icon(Icons.family_restroom, size: size * .6, color: Colors.white)
          : Padding(
              padding: EdgeInsets.all(size * .13),
              child: FittedBox(
                child: Text('$k+',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
              ),
            ),
    );
  }
}

class DescIcon extends StatelessWidget {
  final String k;
  final double size;
  const DescIcon(this.k, {super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle, border: Border.all(color: Colors.white70, width: 1)),
        child: ClipOval(child: Image.asset('assets/desc_$k.png', fit: BoxFit.cover)),
      );
}

/// Yatay (16:9) kart — Disney+ tarzı
class WideCard extends StatelessWidget {
  final J item;
  final double width;
  final bool text;
  final VoidCallback? onTap;
  const WideCard(this.item, {super.key, required this.width, this.text = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = wideImg(item);
    final ep = item['Type'] == 'Episode';
    final s = item['ParentIndexNumber'], e = item['IndexNumber'];
    final name = ep
        ? '${item['SeriesName'] != null ? '${item['SeriesName']} · ' : ''}${s != null && e != null ? 'S$s:B$e ' : ''}${item['Name'] ?? ''}'
        : '${item['Name'] ?? ''}';
    final lg = (!w.art && !ep && !text) ? logoUrl(item, w: 360) : null;
    final showT = text || ep || (!w.art && lg == null);
    final p = ((item['UserData']?['PlayedPercentage']) as num?)?.toDouble() ?? 0;
    final ds = descs(item);
    Widget title() => Text(name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontWeight: FontWeight.w700, fontSize: 13, shadows: [Shadow(blurRadius: 6)]));

    return GestureDetector(
      onTap: onTap ?? () => openItem(context, item),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(26), width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 6))],
          ),
          child: Stack(fit: StackFit.expand, children: [
            netImg(w.url, align: w.poster ? const Alignment(0, -.5) : Alignment.center),
            if (lg != null || showT)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [Color(0xCC000000), Color(0x00000000)]),
                ),
              ),
            if (lg != null)
              Positioned(
                left: width * .07,
                bottom: width * .06,
                width: width * .62,
                height: width * .2,
                child: CachedNetworkImage(
                  imageUrl: lg,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomLeft,
                  errorWidget: (_, __, ___) => Align(alignment: Alignment.bottomLeft, child: title()),
                ),
              ),
            if (showT) Positioned(left: 8, right: 8, bottom: 8, child: title()),
            Positioned(
              top: 5,
              right: 5,
              child: Row(children: [
                AgeBadge(item['OfficialRating'], size: 18),
                for (final k in ds) Padding(padding: const EdgeInsets.only(left: 3), child: DescIcon(k, size: 18)),
              ]),
            ),
            if (p > 0 && p < 100)
              Positioned(
                  left: 0,
                  bottom: 0,
                  height: 3,
                  width: (width - 4) * p / 100,
                  child: const ColoredBox(color: Color(0xFF4DA6FF))),
          ]),
        ),
      ),
    );
  }
}

/// Başlıklı yatay sıra
class Shelf extends StatelessWidget {
  final String title;
  final List<J> items;
  final bool resume;
  const Shelf(this.title, this.items, {super.key, this.resume = false});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cw = cardWidth(context), pad = hPad(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(pad, 18, pad, 4),
        child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: cw * 9 / 16 + 24,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (c, i) => WideCard(items[i],
              width: cw, text: resume, onTap: resume ? () => openPlayer(c, items[i]) : null),
        ),
      ),
    ]);
  }
}

/// Disney+ stüdyo kutusu
class BrandTile extends StatelessWidget {
  final String title;
  final String? image;
  final IconData? icon;
  final double width;
  final VoidCallback onTap;
  const BrandTile(
      {super.key, required this.title, this.image, this.icon, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final txt = Padding(
      padding: const EdgeInsets.all(8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(icon, size: 20)),
        Flexible(
          child: Text(title.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 13)),
        ),
      ]),
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: width * 9 / 16,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(26), width: 2),
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF30323E), Color(0xFF1E1F2A)]),
          boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 8))],
        ),
        alignment: Alignment.center,
        child: image == null
            ? txt
            : Padding(
                padding: EdgeInsets.all(width * .12),
                child: CachedNetworkImage(
                    imageUrl: image!, fit: BoxFit.contain, errorWidget: (_, __, ___) => txt)),
      ),
    );
  }
}

/// Kenarları görünen, kendiliğinden dönen vitrin
class HeroCarousel extends StatefulWidget {
  final List<J> items;
  const HeroCarousel(this.items, {super.key});
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  static const big = 100000;
  late final PageController pc;
  Timer? t;
  int page = 0;
  DateTime touched = DateTime.fromMillisecondsSinceEpoch(0);

  int get n => widget.items.length;

  @override
  void initState() {
    super.initState();
    page = n > 1 ? (big ~/ 2) - ((big ~/ 2) % n) : 0;
    pc = PageController(viewportFraction: .9, initialPage: page);
    if (n > 1) {
      t = Timer.periodic(const Duration(seconds: 7), (_) {
        if (!mounted || !pc.hasClients) return;
        if (DateTime.now().difference(touched).inSeconds < 6) return;
        pc.nextPage(duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic);
      });
    }
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (n == 0) return const SizedBox(height: 12);
    final w = MediaQuery.sizeOf(context).width;
    final aspect = w > 700 ? 3.2 : 16 / 9;
    final h = w * .9 / aspect;
    return Column(children: [
      SizedBox(
        height: h + 12,
        child: NotificationListener<ScrollStartNotification>(
          onNotification: (_) {
            touched = DateTime.now();
            return false;
          },
          child: PageView.builder(
            controller: pc,
            itemCount: n > 1 ? big : 1,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (c, i) {
              final it = widget.items[i % n];
              final lg = logoUrl(it, w: 600);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                child: GestureDetector(
                  onTap: () => openItem(c, it),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: kCard,
                      boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 14, offset: Offset(0, 8))],
                    ),
                    child: Stack(fit: StackFit.expand, children: [
                      netImg(backdrop(it), align: const Alignment(0, -.3)),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                              colors: [Color(0xC0000000), Color(0x00000000)],
                              stops: [0, .6]),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        bottom: 16,
                        width: w * .45,
                        height: h * .34,
                        child: lg != null
                            ? CachedNetworkImage(
                                imageUrl: lg,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                errorWidget: (_, __, ___) => _heroTitle(it))
                            : _heroTitle(it),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      if (n > 1)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < n; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: k == page % n ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                    color: k == page % n ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(3)),
              ),
          ]),
        ),
    ]);
  }

  Widget _heroTitle(J it) => Align(
        alignment: Alignment.bottomLeft,
        child: Text('${it['Name'] ?? ''}',
            maxLines: 2,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 12)])),
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2.5));
}

class ErrorView extends StatelessWidget {
  final String text;
  final VoidCallback? retry;
  const ErrorView(this.text, {super.key, this.retry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 42, color: kMuted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kMuted)),
            if (retry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: retry, child: const Text('Tekrar dene')),
            ],
          ]),
        ),
      );
}
