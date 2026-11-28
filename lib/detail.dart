import 'dart:math' show min;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'discover.dart';
import 'downloads.dart';
import 'downloads_screen.dart';
import 'nav.dart';
import 'person.dart';
import 'theme_music.dart';
import 'util.dart';
import 'widgets.dart';

class DetailScreen extends StatefulWidget {
  final String id;
  final num? season; // açılışta seçili olacak sezon
  const DetailScreen({super.key, required this.id, this.season});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final api = Api.I;
  J? it;
  J? pit; // oynatılacak öğe (dizide devam edilecek bölüm)
  List<J> eps = [], similar = [], extras = [];
  ({J box, List<J> items})? order;
  J? nextEp;
  num? season;
  String tab = '';
  String err = '';
  bool moreText = false;
  bool hasTheme = false, themeTried = false;

  @override
  void initState() {
    super.initState();
    load();
    refreshBus.addListener(_soft);
    Downloads.I.addListener(_dl);
  }

  void _dl() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    refreshBus.removeListener(_soft);
    Downloads.I.removeListener(_dl);
    ThemeMusic.I.stop(ifOwner: widget.id);
    super.dispose();
  }

  void _soft() => load();

  Future<List<J>> safe(Future<List<J>> f) async {
    try {
      return await f;
    } catch (_) {
      return <J>[];
    }
  }

  Future<void> load() async {
    final u = api.uid, id = widget.id;
    try {
      final x = await api.item(id);
      final r = await Future.wait<List<J>>([
        x['Type'] == 'Series'
            ? safe(api.items('/Shows/$id/Episodes?UserId=$u&Fields=Overview'))
            : Future.value(<J>[]),
        safe(api.items('/Items/$id/Similar?UserId=$u&Limit=18&Fields=$kFields')),
        safe(api.items('/Users/$u/Items/$id/LocalTrailers')),
        safe(api.items('/Users/$u/Items/$id/SpecialFeatures')),
      ]);
      final e = r[0];
      J p = x;
      if (e.isNotEmpty) {
        bool played(J v) => v['UserData']?['Played'] == true;
        num pos(J v) => (v['UserData']?['PlaybackPositionTicks'] as num?) ?? 0;
        p = e.firstWhere((v) => pos(v) > 0 && !played(v),
            orElse: () => e.firstWhere((v) => !played(v), orElse: () => e.first));
      }
      if (!mounted) return;
      setState(() {
        it = x;
        eps = e;
        pit = p;
        similar = r[1];
        extras = [...r[2], ...r[3]];
        season ??= widget.season ?? (p['ParentIndexNumber'] as num?) ?? (e.isNotEmpty ? e.first['ParentIndexNumber'] as num? : null);
        if (tab.isEmpty) tab = e.isNotEmpty ? 'eps' : 'sim';
        err = '';
      });
      if (x['Type'] == 'Series' && nextEp == null) {
        Discover.I.nextEpisode(x).then((n) {
          if (mounted && n != null) setState(() => nextEp = n);
        }).catchError((_) {});
      }
      if ((x['Type'] == 'Movie' || x['Type'] == 'Series') && order == null) {
        Discover.I.seriesOrder(id).then((o) {
          if (mounted && o != null) setState(() => order = o);
        }).catchError((_) {});
      }
      if (!themeTried) {
        themeTried = true;
        ThemeMusic.I.start(widget.id).then((has) {
          if (mounted) setState(() => hasTheme = has);
        });
      }
    } catch (e) {
      if (mounted) setState(() => err = 'Yüklenemedi.\n$e');
    }
  }

  Future<void> flag(String kind, bool on) async {
    final x = it!;
    final path = kind == 'fav' ? '/Users/${api.uid}/FavoriteItems/${x['Id']}' : '/Users/${api.uid}/PlayedItems/${x['Id']}';
    final key = kind == 'fav' ? 'IsFavorite' : 'Played';
    setState(() => (x['UserData'] ??= <String, dynamic>{})[key] = on);
    try {
      on ? await api.post(path) : await api.delete(path);
      if (kind == 'seen') load();
      refreshBus.value++;
    } catch (_) {
      if (mounted) setState(() => x['UserData'][key] = !on);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bare(Widget body) => Scaffold(
          backgroundColor: kBg,
          body: Stack(children: [
            Positioned.fill(child: body),
            Positioned(
              left: 14,
              top: MediaQuery.paddingOf(context).top + 8,
              child: GlassIcon(Icons.arrow_back_ios_new_rounded, tooltip: 'Geri', onTap: () => Navigator.of(context).maybePop()),
            ),
          ]),
        );
    if (err.isNotEmpty) return bare(ErrorView(err, retry: load));
    final x = it;
    if (x == null) return bare(const Loading());
    final w = MediaQuery.sizeOf(context).width;
    final pad = hPad(context);
    final p = pit ?? x;
    final ud = (p['UserData'] as Map?) ?? const {};
    final resTicks = (ud['PlaybackPositionTicks'] as num?) ?? 0;
    final res = resTicks > 0 && ud['Played'] != true;
    final isSeries = x['Type'] == 'Series';
    final lg = logoUrl(x, w: 800);
    final tr = ((x['RemoteTrailers'] as List?) ?? const []).isNotEmpty ? '${x['RemoteTrailers'][0]['Url']}' : null;

    // kalite etiketleri
    final sts = ((x['MediaSources'] as List?)?.isNotEmpty == true)
        ? ((x['MediaSources'][0]['MediaStreams'] as List?) ?? const [])
        : const [];
    final vs = sts.cast<Map>().where((s) => s['Type'] == 'Video').toList();
    final width = vs.isNotEmpty ? ((vs.first['Width'] as num?) ?? 0) : 0;
    var ch = 0;
    for (final s in sts.cast<Map>()) {
      if (s['Type'] == 'Audio' && ((s['Channels'] as num?) ?? 0) > ch) ch = (s['Channels'] as num).toInt();
    }
    final chips = [
      if (width >= 3500) '4K UHD' else if (width >= 1200) 'HD',
      if (vs.isNotEmpty && vs.first['VideoRange'] == 'HDR') 'HDR',
      if (sts.cast<Map>().any((s) => s['Type'] == 'Subtitle')) 'CC',
      if (ch >= 8) '7.1' else if (ch >= 6) '5.1',
    ];
    final seasons = eps.map((e) => e['ParentIndexNumber'] as num?).toSet().toList();
    final tabs = [
      if (eps.isNotEmpty) ['eps', 'Bölümler'],
      if (order != null) ['col', 'Koleksiyon'],
      ['sim', 'Benzerleri'],
      if (extras.isNotEmpty) ['ext', 'Ekstralar'],
      ['det', 'Detaylar'],
    ];
    if (!tabs.any((t) => t[0] == tab)) tab = tabs.first[0];
    final fav = x['UserData']?['IsFavorite'] == true;
    final seen = x['UserData']?['Played'] == true;
    final top = MediaQuery.paddingOf(context).top;
    final epOf = isSeries && p['IndexNumber'] != null ? 'S${p['ParentIndexNumber']}:B${p['IndexNumber']}' : '';
    final runT = ((p['RunTimeTicks'] as num?) ?? 0);
    final people = ((x['People'] as List?) ?? const []).cast<Map>();
    final actors = people.where((q) => q['Type'] == 'Actor').take(3).map((q) => '${q['Name']}').toList();
    final directors = people.where((q) => q['Type'] == 'Director').take(2).map((q) => '${q['Name']}').toList();
    final overview = isSeries && '${p['Overview'] ?? ''}'.isNotEmpty && p != x ? '${p['Overview']}' : '${x['Overview'] ?? ''}';
    final canDl = isSeries ? p != x && p['Type'] == 'Episode' : (x['MediaSources'] as List?)?.isNotEmpty == true;
    final age = ageLabel(x['OfficialRating']);

    Widget badge(String t, {bool fill = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: fill ? Colors.white.withAlpha(46) : null,
            border: fill ? null : Border.all(color: const Color(0x80F5F5F7), width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xE6F5F5F7))),
        );

    Widget dlPill() {
      final b = dlButton('${p['Id']}');
      final d = Downloads.I.of('${p['Id']}');
      final done = d?.state == DlState.done;
      final what = epOf.isNotEmpty ? ' $epOf' : '';
      final text = b.frac != null
          ? 'İndiriliyor$what${b.frac! > 0 ? ' · %${(b.frac! * 100).round()}' : ''}'
          : done
              ? 'İndirildi$what'
              : 'İndir$what';
      return Semantics(
        button: true,
        label: text,
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            d == null ? askDownload(context, [p]) : dlActions(context, d);
          },
          child: Container(
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(24)),
            child: Stack(children: [
              if (b.frac != null && b.frac! > 0)
                FractionallySizedBox(
                  widthFactor: b.frac!,
                  child: Container(decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(24))),
                ),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(done ? Icons.check_rounded : Icons.download_rounded, size: 22, color: const Color(0xFFF5F5F7)),
                  const SizedBox(width: 8),
                  Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    final metaW = Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (x['ProductionYear'] != null) Text('${x['ProductionYear']}', style: const TextStyle(fontSize: 14, color: Color(0xD9F5F5F7))),
        if (age != null) badge(age, fill: true),
        if (isSeries)
          (() {
            final n = eps.map((e) => e['ParentIndexNumber']).where((v) => v != 0 && v != null).toSet().length;
            return n > 0 ? Text('$n Sezon', style: const TextStyle(fontSize: 14, color: Color(0xD9F5F5F7))) : const SizedBox.shrink();
          })()
        else if (rt(x['RunTimeTicks']).isNotEmpty)
          Text(rt(x['RunTimeTicks']), style: const TextStyle(fontSize: 14, color: Color(0xD9F5F5F7))),
        for (final c in chips) badge(c),
        if (x['CommunityRating'] != null)
          Text('★ ${(x['CommunityRating'] as num).toStringAsFixed(1)}', style: const TextStyle(fontSize: 13, color: Color(0xD9F5F5F7))),
      ]);
    final playW = PillButton(res ? 'Devam et' : 'Oynat', icon: Icons.play_arrow_rounded, height: 48, expand: true, onTap: () => openPlayer(context, p));
    final epW = <Widget>[
      if (epOf.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('$epOf ${p['IndexNumber']}. Bölüm: ${p['Name'] ?? ''}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ],
      if (res && runT > 0) ...[
        SizedBox(height: epOf.isNotEmpty ? 8 : 14),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (resTicks / runT).clamp(0, 1).toDouble(),
                minHeight: 4,
                backgroundColor: Colors.white.withAlpha(51),
                color: kBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('${rt(runT - resTicks)} kaldı', style: const TextStyle(fontSize: 12, color: Color(0x99F5F5F7))),
        ]),
      ],
    ];
    final textW = <Widget>[
      if (overview.isNotEmpty)
        GestureDetector(
          onTap: () => setState(() => moreText = !moreText),
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(overview,
                maxLines: moreText ? null : 4,
                overflow: moreText ? null : TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, height: 1.45)),
          ),
        ),
    ];
    final peopleW = <Widget>[
      if (actors.isNotEmpty)
        GestureDetector(
          onTap: () => setState(() => tab = 'det'),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Oyuncular: ${actors.join(', ')}'),
                const TextSpan(text: ' … daha fazla', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xCCF5F5F7))),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0x8CF5F5F7)),
            ),
          ),
        ),
      if (directors.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Yönetmen: ${directors.join(', ')}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0x8CF5F5F7))),
        ),
    ];
    final actionsW = Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _act(fav ? Icons.check_rounded : Icons.add_rounded, 'Listem', () => flag('fav', !fav)),
        _act(seen ? Icons.visibility_rounded : Icons.visibility_outlined, seen ? 'İzlendi' : 'İzlenmedi', () => flag('seen', !seen)),
        if (tr != null) _act(Icons.movie_creation_outlined, 'Fragman', () => launchUrl(Uri.parse(tr), mode: LaunchMode.externalApplication)),
        if (res) _act(Icons.replay_rounded, 'Baştan', () => openPlayer(context, p, restart: true)),
        if (isSeries && season != null)
          _act(Icons.download_for_offline_outlined, season == 0 ? 'Özeller' : 'Sezon $season', () {
            final todo = eps.where((e) => e['ParentIndexNumber'] == season && Downloads.I.of('${e['Id']}') == null).toList();
            if (todo.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu sezonun bölümleri zaten indirildi ya da sırada.')));
              return;
            }
            askDownload(context, todo, title: '${todo.length} bölümü indir');
          }),
      ]);
    final info = <Widget>[
      metaW,
      const SizedBox(height: 16),
      playW,
      if (canDl) ...[const SizedBox(height: 10), dlPill()],
      ...epW,
      ...textW,
      ...peopleW,
      if (nextEp != null) NextEpisodeRow(nextEp!),
      const SizedBox(height: 18),
      actionsW,
      const SizedBox(height: 10),
    ];

    // Sekmeler: altı çizili yazılar, seçilinin üstünde ince çizgi
    final tabBar = SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          for (final t in tabs)
            Semantics(
              button: true,
              selected: tab == t[0],
              label: t[1],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => tab = t[0]);
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: IntrinsicWidth(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 3,
                        decoration: BoxDecoration(
                          color: tab == t[0] ? kBlue : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(t[1],
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: tab == t[0] ? const Color(0xFFF5F5F7) : const Color(0x73F5F5F7))),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    Widget titleW({double size = 30}) => lg != null
        ? Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: size * 2,
              width: w > 700 ? 360 : w * .7,
              child: CachedNetworkImage(
                  imageUrl: lg,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  errorWidget: (_, __, ___) => Text('${x['Name'] ?? ''}',
                      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -.8))),
            ),
          )
        : Text('${x['Name'] ?? ''}', style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: -.8, height: 1.1));

    Widget themeBtn() => GlassIcon(api.themeOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            size: 36, tooltip: api.themeOn ? 'Tema müziğini kapat' : 'Tema müziğini aç', onTap: () {
          setState(() => api.themeOn = !api.themeOn);
          api.themeOn ? ThemeMusic.I.start(widget.id) : ThemeMusic.I.stop(ifOwner: widget.id);
        });

    // iPad: tam ekran. Üstte boydan boya görsel, altında iki sütun bilgi, sonra sekmeler bütün genişlikte.
    if (wideLayout(context)) {
      final h = MediaQuery.sizeOf(context).height;
      final heroH = min(h * .6, w * .56);
      const side = 48.0;
      return Scaffold(
        backgroundColor: kBg,
        body: Stack(children: [
          CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: heroH,
                child: Stack(fit: StackFit.expand, children: [
                  netImg(backdrop(x, w: 1920), align: const Alignment(.2, -.5)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x800B0B0D), Color(0x000B0B0D), Color(0x000B0B0D), kBg],
                        stops: [0, .25, .55, 1],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0x990B0B0D), Color(0x000B0B0D)],
                        stops: [0, .6],
                      ),
                    ),
                  ),
                  if (res && runT > 0)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        widthFactor: (resTicks / runT).clamp(0, 1).toDouble(),
                        child: Container(height: 3, color: kBlue),
                      ),
                    ),
                  Positioned(left: side, right: side, bottom: 22, child: titleW(size: 44)),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(side, 6, side, 0),
              sliver: SliverList.list(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 3,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      metaW,
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: playW),
                        if (canDl) ...[const SizedBox(width: 12), Expanded(child: dlPill())],
                      ]),
                      ...epW,
                      ...textW,
                    ]),
                  ),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 2,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ...peopleW,
                      if (nextEp != null) NextEpisodeRow(nextEp!),
                      const SizedBox(height: 22),
                      actionsW,
                    ]),
                  ),
                ]),
                const SizedBox(height: 28),
                tabBar,
                const SizedBox(height: 10),
              ]),
            ),
            ..._tabBody(context, x, seasons, side, area: w),
            const SliverToBoxAdapter(child: SizedBox(height: 60)),
          ]),
          Positioned(
            top: top + 8,
            left: 28,
            child: GlassIcon(Icons.arrow_back_ios_new_rounded, size: 44, tooltip: 'Geri', onTap: () => Navigator.of(context).maybePop()),
          ),
          if (hasTheme) Positioned(top: top + 8, right: 28, child: themeBtn()),
        ]),
      );
    }

    final imgH = w > 700 ? w * .5 : w * 9 / 16;
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: top + imgH,
            child: Stack(children: [
              Positioned(
                left: 0,
                right: 0,
                top: top,
                height: imgH,
                child: Stack(fit: StackFit.expand, children: [
                  netImg(backdrop(x), align: const Alignment(.3, -.4)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0x00000000), Color(0x990B0B0D)],
                          stops: [0, .7, 1]),
                    ),
                  ),
                  if (res && runT > 0)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        widthFactor: (resTicks / runT).clamp(0, 1).toDouble(),
                        child: Container(height: 3, color: kBlue),
                      ),
                    ),
                ]),
              ),
              Positioned(
                top: top + 10,
                left: 14,
                child: GlassIcon(Icons.arrow_back_ios_new_rounded, tooltip: 'Geri', onTap: () => Navigator.of(context).maybePop()),
              ),
              if (hasTheme) Positioned(right: 12, top: top + imgH - 48, child: themeBtn()),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
          sliver: SliverList.list(children: [
            titleW(),
            const SizedBox(height: 10),
            ...info,
            tabBar,
            const SizedBox(height: 10),
          ]),
        ),
        ..._tabBody(context, x, seasons, pad),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]),
    );
  }

  /// Simge + altında yazı (Listem, İzlendi, Fragman, Sezonu indir…)
  Widget _act(IconData i, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 78,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 28, color: const Color(0xFFF5F5F7)),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  List<Widget> _tabBody(BuildContext context, J x, List<num?> seasons, double pad, {double? area}) {
    final w = area ?? MediaQuery.sizeOf(context).width;
    final cols = w > 1000 ? 4 : (w > 700 ? 3 : 2);
    SliverPadding grid(List<J> list, {bool play = false}) => SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 16 / 9),
            delegate: SliverChildBuilderDelegate(
              (c, i) => LayoutBuilder(
                builder: (c, cs) => WideCard(list[i],
                    width: cs.maxWidth, text: play, onTap: play ? () => openPlayer(context, list[i]) : null),
              ),
              childCount: list.length,
            ),
          ),
        );

    switch (tab) {
      case 'eps':
        final list = eps.where((e) => e['ParentIndexNumber'] == season).toList();
        return [
          if (seasons.length > 1)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(pad, 6, pad, 6),
                  children: [
                    for (final s in seasons)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Pressable(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => season = s);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: s == season ? kBlue : const Color(0x1FFFFFFF),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(s == null || s == 0 ? 'Özel' : 'Sezon $s',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: s == season ? kInk : const Color(0xFFF5F5F7))),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 6, pad, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Pressable(
                  onTap: () {
                    final todo = list.where((e) => Downloads.I.of('${e['Id']}') == null).toList();
                    if (todo.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bu sezonun bölümleri zaten indirildi ya da sırada.')));
                      return;
                    }
                    askDownload(context, todo, title: '${todo.length} bölümü indir');
                  },
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(17)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.arrow_downward_rounded, size: 16, color: Color(0xFFF5F5F7)),
                      const SizedBox(width: 6),
                      Text(season == null || season == 0 ? 'Özel bölümleri indir' : 'Sezon $season\'i indir',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
            sliver: SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (c, i) => _episode(c, list[i]),
            ),
          ),
        ];
      case 'sim':
        return similar.isEmpty
            ? [const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(20), child: Text('Öneri yok.', style: TextStyle(color: kMuted))))]
            : [SliverToBoxAdapter(child: SizedBox(height: 6)), posterGrid(similar, pad, w)];
      case 'col':
        final o = order;
        if (o == null) return [];
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 12),
              child: Pressable(
                onTap: () => openItem(context, o.box),
                child: Row(children: [
                  Expanded(
                    child: Text('${o.box['Name'] ?? ''} · ${o.items.length} yapım · çıkış sırasıyla',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0x99F5F5F7))),
                  ),
                  const Text('Tümü', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ]),
              ),
            ),
          ),
          posterGrid(o.items, pad, w, numbered: true, current: '${x['Id']}'),
        ];
      case 'ext':
        return [grid(extras, play: true)];
      default:
        return [SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(horizontal: pad), child: _details(x)))];
    }
  }

  Widget _episode(BuildContext c, J e) {
    final ud = (e['UserData'] as Map?) ?? const {};
    final pr = ((ud['PlayedPercentage'] as num?) ?? 0).toDouble();
    final img = ((e['ImageTags'] as Map?)?['Primary']) != null
        ? api.image(e['Id'], 'Primary', tag: e['ImageTags']['Primary'], w: 400)
        : backdrop(e, w: 400);
    return Pressable(
      onTap: () => openPlayer(c, e),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: kCard),
                netImg(img),
                if (pr > 0 && pr < 100)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: pr / 100, color: kBlue, backgroundColor: const Color(0x40FFFFFF)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['IndexNumber'] ?? ''}. ${e['Name'] ?? ''}',
                maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 3),
            Text([rt(e['RunTimeTicks']), if (ud['Played'] == true) 'İzlendi ✓'].where((s) => s.isNotEmpty).join(' · '),
                style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${e['Overview'] ?? ''}',
                maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0x99F5F5F7), height: 1.4)),
          ]),
        ),
        _epDl(c, e),
      ]),
    );
  }

  Widget _epDl(BuildContext c, J e) {
    final d = Downloads.I.of('${e['Id']}');
    final b = dlButton('${e['Id']}');
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(alignment: Alignment.center, children: [
        if (b.frac != null)
          SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(value: b.frac == 0 ? null : b.frac, strokeWidth: 2, color: kBlue)),
        Semantics(
          button: true,
          label: b.label,
          child: Pressable(
            onTap: () => d == null ? askDownload(c, [e]) : dlActions(c, d),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                  b.frac != null
                      ? Icons.stop_rounded
                      : d?.state == DlState.done
                          ? Icons.check_circle_rounded
                          : Icons.arrow_circle_down_rounded,
                  size: b.frac != null ? 14 : 24,
                  color: d?.state == DlState.done ? kBlue : const Color(0xB3F5F5F7)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _details(J x) {
    final people = ((x['People'] as List?) ?? const []).cast<Map>();
    String names(bool Function(Map) f, [int n = 10]) => people.where(f).take(n).map((p) => '${p['Name']}').join(', ');
    final rows = <List<String>>[
      ['Yönetmen', names((p) => p['Type'] == 'Director')],
      ['Senaryo', names((p) => p['Type'] == 'Writer')],
      ['Türler', ((x['Genres'] as List?) ?? const []).join(', ')],
      ['Stüdyo', ((x['Studios'] as List?) ?? const []).map((s) => '${s['Name']}').join(', ')],
      ['Yaş sınırı', ageText(x['OfficialRating'])],
      ['İçerik işaretleri', descs(x).map((k) => kDesc[k]).join(', ')],
      ['Yayın', trDate(x['PremiereDate'])],
      ['Süre', rt(x['RunTimeTicks'])],
    ].where((r) => r[1].isNotEmpty).toList();
    final cast = people.where((p) => p['Type'] == 'Actor' || p['Type'] == 'Director').take(24).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (cast.isNotEmpty) ...[
        const Text('Oyuncular ve ekip', style: TextStyle(color: kMuted, fontSize: 12)),
        const SizedBox(height: 8),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (c, i) {
              final p = cast[i];
              final tag = p['PrimaryImageTag'];
              return Pressable(
                onTap: () => Navigator.of(c).push(
                    MaterialPageRoute(builder: (_) => PersonScreen(id: '${p['Id']}', name: '${p['Name']}'))),
                child: SizedBox(
                  width: 76,
                  child: Column(children: [
                    ClipOval(
                      child: Container(
                        width: 64,
                        height: 64,
                        color: kCard,
                        child: tag == null
                            ? const Icon(Icons.person, color: kMuted)
                            : netImg(Api.I.image('${p['Id']}', 'Primary', tag: '$tag', w: 160)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('${p['Name']}',
                        maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    Text(p['Type'] == 'Director' ? 'Yönetmen' : '${p['Role'] ?? ''}',
                        maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: kMuted)),
                  ]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (((x['Taglines'] as List?) ?? const []).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text('"${x['Taglines'][0]}"', style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFFCFD5EA))),
        ),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r[0], style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 2),
            Text(r[1], style: const TextStyle(fontSize: 14)),
          ]),
        ),
    ]);
  }
}
