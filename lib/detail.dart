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
      if (x['Type'] == 'Movie' && order == null) {
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
    final meta = [
      if (x['ProductionYear'] != null) '${x['ProductionYear']}',
      if (isSeries)
        (() {
          final n = eps.map((e) => e['ParentIndexNumber']).toSet().length;
          return n > 0 ? '$n sezon' : '';
        })()
      else
        rt(x['RunTimeTicks']),
      if (x['CommunityRating'] != null) '★ ${(x['CommunityRating'] as num).toStringAsFixed(1)}',
    ].where((s) => s.isNotEmpty).join(' · ');
    final genres = ((x['Genres'] as List?) ?? const []).take(4).join(', ');
    final seasons = eps.map((e) => e['ParentIndexNumber'] as num?).toSet().toList();
    final tabs = [
      if (eps.isNotEmpty) ['eps', 'Bölümler'],
      ['sim', isSeries ? 'Benzer' : 'Önerilenler'],
      if (extras.isNotEmpty) ['ext', 'Ekstralar'],
      ['det', 'Detaylar'],
    ];
    final fav = x['UserData']?['IsFavorite'] == true;
    final seen = x['UserData']?['Played'] == true;
    final heroH = w > 700 ? w * .5 : w * 1.02;

    String playLabel() {
      if (!res) return isSeries && p['IndexNumber'] != null ? 'Oynat · S${p['ParentIndexNumber']} B${p['IndexNumber']}' : 'Oynat';
      final left = ((p['RunTimeTicks'] as num?) ?? 0) - resTicks;
      final ep = isSeries && p['IndexNumber'] != null ? ' · S${p['ParentIndexNumber']} B${p['IndexNumber']}' : '';
      return 'Devam et$ep${left > 0 ? ' · ${rt(left)} kaldı' : ''}';
    }

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroH,
            child: Stack(fit: StackFit.expand, children: [
              netImg(backdrop(x), align: const Alignment(.3, -.4)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x660B0B0D), Color(0x000B0B0D), Color(0xCC0B0B0D), kBg],
                      stops: [0, .3, .78, 1]),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 14,
                child: GlassIcon(Icons.arrow_back_ios_new_rounded,
                    tooltip: 'Geri', onTap: () => Navigator.of(context).maybePop()),
              ),
              if (hasTheme)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  right: 14,
                  child: GlassIcon(api.themeOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      tooltip: api.themeOn ? 'Tema müziğini kapat' : 'Tema müziğini aç', onTap: () {
                    setState(() => api.themeOn = !api.themeOn);
                    api.themeOn ? ThemeMusic.I.start(widget.id) : ThemeMusic.I.stop(ifOwner: widget.id);
                  }),
                ),
              Positioned(
                left: pad,
                right: pad,
                bottom: 4,
                height: heroH * .3,
                child: lg != null
                    ? CachedNetworkImage(
                        imageUrl: lg,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomLeft,
                        errorWidget: (_, __, ___) => _title(x))
                    : _title(x),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
          sliver: SliverList.list(children: [
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(meta, style: const TextStyle(color: Color(0xB8F5F5F7), fontSize: 13)),
              for (final c in [if (ageLabel(x['OfficialRating']) != null) ageLabel(x['OfficialRating'])!, ...chips])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x80F5F5F7), width: 1), borderRadius: BorderRadius.circular(4)),
                  child: Text(c, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xB8F5F5F7))),
                ),
            ]),
            if (genres.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(genres, style: const TextStyle(fontSize: 13))),
            const SizedBox(height: 16),
            PillButton(playLabel(),
                icon: Icons.play_arrow_rounded, height: 52, expand: true, onTap: () => openPlayer(context, p)),
            if (res && ((p['RunTimeTicks'] as num?) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (resTicks / (p['RunTimeTicks'] as num)).clamp(0, 1).toDouble(),
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(children: [
              _act(fav ? Icons.check : Icons.add, 'Listem', () => flag('fav', !fav)),
              if (tr != null)
                _act(Icons.movie_creation_outlined, 'Fragman',
                    () => launchUrl(Uri.parse(tr), mode: LaunchMode.externalApplication)),
              if (res) _act(Icons.replay, 'Baştan', () => openPlayer(context, p, restart: true)),
              if (!isSeries && (x['MediaSources'] as List?)?.isNotEmpty == true) _dlAct(x),
              _act(seen ? Icons.visibility : Icons.visibility_outlined, seen ? 'İzlendi' : 'İzlenmedi',
                  () => flag('seen', !seen)),
            ]),
            if ('${x['Overview'] ?? ''}'.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() => moreText = !moreText),
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('${x['Overview']}',
                      maxLines: moreText ? null : 4,
                      overflow: moreText ? null : TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.5)),
                ),
              ),
            const SizedBox(height: 14),
          ]),
        ),
        if (order != null)
          SliverToBoxAdapter(child: SeriesOrderShelf(box: order!.box, items: order!.items, current: '${x['Id']}')),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverList.list(children: [
            // sekmeler: iOS bölümlü seçici
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white.withAlpha(20), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                for (final t in tabs)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => tab = t[0]);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tab == t[0] ? Colors.white.withAlpha(46) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(t[1],
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: tab == t[0] ? FontWeight.w600 : FontWeight.w500,
                                color: tab == t[0] ? Colors.white : const Color(0xA6F5F5F7))),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
          ]),
        ),
        ..._tabBody(context, x, seasons, pad),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]),
    );
  }

  Widget _title(J x) => Align(
        alignment: Alignment.bottomLeft,
        child: Text('${x['Name'] ?? ''}',
            maxLines: 2,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 14)])),
      );

  Widget _dlAct(J v) {
    final b = dlButton('${v['Id']}');
    final d = Downloads.I.of('${v['Id']}');
    return _act(b.icon, b.label, () => d == null ? askDownload(context, [v]) : dlActions(context, d), frac: b.frac);
  }

  /// A · Cam: cam kare eylem kutusu (Listem, İndir, Fragman…)
  Widget _act(IconData i, String label, VoidCallback onTap, {double? frac}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            button: true,
            label: label,
            child: Pressable(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withAlpha(26)),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Stack(alignment: Alignment.center, children: [
                      Icon(i, size: frac != null ? 14 : 21),
                      if (frac != null)
                        SizedBox.expand(
                            child: CircularProgressIndicator(
                                value: frac == 0 ? null : frac, strokeWidth: 2, color: Colors.white)),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ]),
              ),
            ),
          ),
        ),
      );

  List<Widget> _tabBody(BuildContext context, J x, List<num?> seasons, double pad) {
    final w = MediaQuery.sizeOf(context).width;
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
            : [grid(similar)];
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
      ['Yaş sınırı', '${x['OfficialRating'] ?? ''}'],
      ['İçerik işaretleri', descs(x).map((k) => kDesc[k]).join(', ')],
      ['Yayın', '${x['PremiereDate'] ?? ''}'.split('T').first],
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
