import 'dart:async';
import 'dart:math' show min;
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Poyraz Player işareti: kalın P, içindeki boşluk sıcak renkli oynat üçgeni.
class PMark extends StatelessWidget {
  final double size;
  final Color color;
  final bool warm;
  const PMark({super.key, this.size = 24, this.color = const Color(0xFFF5F5F7), this.warm = true});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _PMarkPainter(color, warm ? kAccent : null));
}

class _PMarkPainter extends CustomPainter {
  final Color color;
  final Color? tri;
  _PMarkPainter(this.color, this.tri);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 100;
    final p = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(22 * k, 14 * k)
      ..lineTo(56 * k, 14 * k)
      ..arcToPoint(Offset(56 * k, 66 * k), radius: Radius.circular(26 * k))
      ..lineTo(40 * k, 66 * k)
      ..lineTo(40 * k, 86 * k)
      ..lineTo(22 * k, 86 * k)
      ..close()
      ..moveTo(44 * k, 27 * k)
      ..lineTo(69 * k, 40 * k)
      ..lineTo(44 * k, 53 * k)
      ..close();
    c.drawPath(p, Paint()..color = color);
    if (tri != null) {
      c.drawPath(
          Path()
            ..moveTo(47 * k, 32.5 * k)
            ..lineTo(61.5 * k, 40 * k)
            ..lineTo(47 * k, 47.5 * k)
            ..close(),
          Paint()..color = tri!);
    }
  }

  @override
  bool shouldRepaint(covariant _PMarkPainter o) => o.color != color || o.tri != tri;
}

/// İşaret + "Poyraz" yazısı
class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        PMark(size: size * 1.25),
        SizedBox(width: size * .3),
        Text('Poyraz', style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -.5, color: Colors.white)),
      ]);
}

/// Buğulu cam yüzey (A · Cam)
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final Color color;
  final double blur;
  const Glass({super.key, required this.child, this.radius = 20, this.padding, this.color = kGlass, this.blur = 22});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: child,
          ),
        ),
      );
}

/// Basınca hafifçe küçülen dokunma alanı (dalga efekti yerine, iOS gibi)
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.haptic = false});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => down = true),
        onTapCancel: () => setState(() => down = false),
        onTapUp: (_) => setState(() => down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.lightImpact();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedScale(
          scale: down ? .96 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedOpacity(opacity: down ? .75 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
        ),
      );
}

/// Cam yuvarlak simge düğmesi
class GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  const GlassIcon(this.icon, {super.key, required this.onTap, this.tooltip, this.size = 40});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: tooltip,
        child: Pressable(
          onTap: onTap,
          child: Glass(
            radius: size / 2,
            child: SizedBox(width: size, height: size, child: Icon(icon, size: size * .45, color: Colors.white)),
          ),
        ),
      );
}

/// Beyaz kapsül düğme (Oynat / Devam et)
class PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final double height;
  final bool expand;
  const PillButton(this.label, {super.key, this.icon, required this.onTap, this.height = 48, this.expand = false});
  @override
  Widget build(BuildContext context) => Pressable(
        haptic: true,
        onTap: onTap,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(height / 2)),
          child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, color: kInk, size: 24), const SizedBox(width: 6)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kInk, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
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

/// Yatay (16:9) kart — A · Cam: yuvarlak köşe, çerçevesiz, ilerleme çubuğu içeride
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
    final season = item['Type'] == 'Season';
    final name = season && item['SeriesName'] != null ? '${item['SeriesName']} · ${item['Name'] ?? ''}' : '${item['Name'] ?? ''}';
    final lg = (!w.art && !ep && !text) ? logoUrl(item, w: 360) : null;
    final showT = !text && (ep || season || (!w.art && lg == null));
    final p = ((item['UserData']?['PlayedPercentage']) as num?)?.toDouble() ?? 0;
    final r = width > 180 ? 14.0 : 12.0;
    Widget title() => Text(name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, shadows: [Shadow(blurRadius: 8)]));

    return Pressable(
      onTap: onTap ?? () => openItem(context, item),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(r),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 8))],
          ),
          child: Stack(fit: StackFit.expand, children: [
            netImg(w.url, align: w.poster ? const Alignment(0, -.5) : Alignment.center),
            if (lg != null || showT || (p > 0 && p < 100))
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.center, colors: [Color(0xB3000000), Color(0x00000000)]),
                ),
              ),
            if (lg != null)
              Positioned(
                left: width * .07,
                bottom: width * .07,
                width: width * .6,
                height: width * .19,
                child: CachedNetworkImage(
                  imageUrl: lg,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomLeft,
                  errorWidget: (_, __, ___) => Align(alignment: Alignment.bottomLeft, child: title()),
                ),
              ),
            if (showT) Positioned(left: 10, right: 10, bottom: (p > 0 && p < 100) ? 20 : 10, child: title()),
            if (p > 0 && p < 100)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(value: p / 100, color: kBlue, backgroundColor: const Color(0x40FFFFFF)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// "İzlemeye devam et" kartı: büyük görsel, altında başlık ve kalan süre
class ResumeCard extends StatelessWidget {
  final J item;
  final double width;
  const ResumeCard(this.item, {super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    final ep = item['Type'] == 'Episode';
    final s = item['ParentIndexNumber'], e = item['IndexNumber'];
    final left = ((item['RunTimeTicks'] as num?) ?? 0) - ((item['UserData']?['PlaybackPositionTicks'] as num?) ?? 0);
    final l = left > 0 ? rt(left) : '';
    final title = ep ? '${item['SeriesName'] ?? item['Name'] ?? ''}' : '${item['Name'] ?? ''}';
    final sub = [
      if (ep && s != null && e != null) 'S$s · B$e' else if (!ep) 'Film',
      if (l.isNotEmpty) '$l kaldı',
    ].join(' · ');
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        WideCard(item, width: width, text: true, onTap: () => openPlayer(context, item)),
        const SizedBox(height: 8),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0x99F5F5F7))),
      ]),
    );
  }
}

/// Başlıklı yatay sıra
class Shelf extends StatelessWidget {
  final String title;
  final List<J> items;
  final bool resume;
  final VoidCallback? more;
  const Shelf(this.title, this.items, {super.key, this.resume = false, this.more});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final pad = hPad(context);
    final sw = MediaQuery.sizeOf(context).width;
    final cw = resume ? (sw > 700 ? cardWidth(context) * 1.25 : sw * .56) : cardWidth(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 22, pad, 2),
        child: Pressable(
          onTap: more,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
            if (more != null) const Icon(Icons.chevron_right_rounded, size: 24, color: Color(0x99F5F5F7)),
          ]),
        ),
      ),
      SizedBox(
        height: cw * 9 / 16 + (resume ? 66 : 30),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 10, pad, 18),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (c, i) => resume ? ResumeCard(items[i], width: cw) : WideCard(items[i], width: cw),
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
/// A · Cam vitrini: kenardan kenara görsel, aşağı doğru zemine karışan kararma,
/// beyaz "Oynat", cam "+" ve sayfa noktaları. Üst kısma başlık çubuğu bindirilir.
class HeroCarousel extends StatefulWidget {
  final List<J> items;
  const HeroCarousel(this.items, {super.key});
  static double heightFor(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return w > 700 ? w * .52 : min(w * 1.28, 560);
  }

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  static const big = 100000;
  late final PageController pc;
  Timer? t;
  int page = 0;
  DateTime touched = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, bool> favs = {};

  int get n => widget.items.length;

  @override
  void initState() {
    super.initState();
    page = n > 1 ? (big ~/ 2) - ((big ~/ 2) % n) : 0;
    pc = PageController(initialPage: page);
    if (n > 1) {
      t = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!mounted || !pc.hasClients) return;
        if (DateTime.now().difference(touched).inSeconds < 7) return;
        pc.nextPage(duration: const Duration(milliseconds: 800), curve: Curves.easeInOutCubic);
      });
    }
  }

  @override
  void dispose() {
    t?.cancel();
    pc.dispose();
    super.dispose();
  }

  Future<void> _fav(J it) async {
    final id = '${it['Id']}';
    final now = !(favs[id] ?? ((it['UserData'] as Map?)?['IsFavorite'] == true));
    setState(() => favs[id] = now);
    HapticFeedback.selectionClick();
    try {
      final api = Api.I;
      now ? await api.post('/Users/${api.uid}/FavoriteItems/$id') : await api.delete('/Users/${api.uid}/FavoriteItems/$id');
      refreshBus.value++;
    } catch (_) {
      if (mounted) setState(() => favs[id] = !now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = HeroCarousel.heightFor(context);
    if (n == 0) return SizedBox(height: MediaQuery.paddingOf(context).top + 64);
    final w = MediaQuery.sizeOf(context).width;
    final wide = w > 700;
    final pad = wide ? 56.0 : 20.0;
    return SizedBox(
      height: h,
      child: Stack(children: [
        NotificationListener<ScrollStartNotification>(
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
              final isFav = favs['${it['Id']}'] ?? ((it['UserData'] as Map?)?['IsFavorite'] == true);
              final meta = [
                it['Type'] == 'Series' ? 'Dizi' : 'Film',
                ...((it['Genres'] as List?) ?? const []).take(2).map((e) => '$e'),
                if (it['ProductionYear'] != null) '${it['ProductionYear']}',
              ].join(' · ');
              return GestureDetector(
                onTap: () => openItem(c, it),
                child: Stack(fit: StackFit.expand, children: [
                  netImg(backdrop(it), align: wide ? const Alignment(.4, -.3) : const Alignment(0, -.2)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xCC0B0B0D), kBg],
                        stops: [0, .22, .5, .82, 1],
                      ),
                    ),
                  ),
                  if (wide)
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xB30B0B0D), Color(0x000B0B0D)], stops: [0, .55]),
                      ),
                    ),
                  Positioned(
                    left: pad,
                    right: wide ? w * .5 : pad,
                    bottom: wide ? 56 : 30,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        height: wide ? 110 : 84,
                        width: wide ? w * .4 : w * .7,
                        child: lg != null
                            ? CachedNetworkImage(
                                imageUrl: lg,
                                fit: BoxFit.contain,
                                alignment: Alignment.bottomLeft,
                                errorWidget: (_, __, ___) => _heroTitle(it, wide))
                            : _heroTitle(it, wide),
                      ),
                      const SizedBox(height: 10),
                      Text(meta, style: const TextStyle(fontSize: 13, color: Color(0xB8F5F5F7))),
                      const SizedBox(height: 14),
                      Row(children: [
                        PillButton(it['Type'] == 'Series' ? 'Göz at' : 'Oynat',
                            icon: it['Type'] == 'Series' ? null : Icons.play_arrow_rounded,
                            height: 46,
                            onTap: () => it['Type'] == 'Series' ? openItem(c, it) : openPlayer(c, it)),
                        const SizedBox(width: 10),
                        GlassIcon(isFav ? Icons.check_rounded : Icons.add_rounded,
                            size: 46, tooltip: isFav ? 'Listemden çıkar' : 'Listeme ekle', onTap: () => _fav(it)),
                      ]),
                    ]),
                  ),
                ]),
              );
            },
          ),
        ),
        if (n > 1)
          Positioned(
            right: pad,
            bottom: wide ? 72 : 46,
            child: IgnorePointer(
              child: Row(children: [
                for (var k = 0; k < n; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(left: 5),
                    width: k == page % n ? 18 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                        color: k == page % n ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(3)),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _heroTitle(J it, bool wide) => Align(
        alignment: Alignment.bottomLeft,
        child: Text('${it['Name'] ?? ''}',
            maxLines: 2,
            style: TextStyle(fontSize: wide ? 52 : 36, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1)),
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator.adaptive());
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
              PillButton('Tekrar dene', onTap: retry!, height: 42),
            ],
          ]),
        ),
      );
}
