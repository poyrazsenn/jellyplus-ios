import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'nav.dart';
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
  }

  @override
  void dispose() {
    refreshBus.removeListener(_soft);
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
    if (err.isNotEmpty) return Scaffold(appBar: AppBar(), body: ErrorView(err, retry: load));
    final x = it;
    if (x == null) return Scaffold(appBar: AppBar(backgroundColor: Colors.transparent), body: const Loading());
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
    ].where((s) => s.isNotEmpty).join(' • ');
    final genres = ((x['Genres'] as List?) ?? const []).take(4).join(', ');
    final ds = descs(x);
    final seasons = eps.map((e) => e['ParentIndexNumber'] as num?).toSet().toList();
    final tabs = [
      if (eps.isNotEmpty) ['eps', 'Bölümler'],
      ['sim', isSeries ? 'Benzer' : 'Önerilenler'],
      if (extras.isNotEmpty) ['ext', 'Ekstralar'],
      ['det', 'Detaylar'],
    ];
    final fav = x['UserData']?['IsFavorite'] == true;
    final seen = x['UserData']?['Played'] == true;
    final heroH = w > 700 ? w * .5 : w * .78;

    String playLabel() {
      if (!res) return isSeries && p['IndexNumber'] != null ? 'OYNAT  S${p['ParentIndexNumber']}:B${p['IndexNumber']}' : 'OYNAT';
      final left = ((p['RunTimeTicks'] as num?) ?? 0) - resTicks;
      return 'DEVAM ET${left > 0 ? '  •  ${rt(left)} kaldı' : ''}';
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
                      colors: [Color(0x66040714), Color(0x00040714), Color(0xCC040714), kBg],
                      stops: [0, .3, .78, 1]),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 6,
                left: 10,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop()),
                ),
              ),
              if (hasTheme)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 6,
                  right: 10,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      tooltip: api.themeOn ? 'Tema müziğini kapat' : 'Tema müziğini aç',
                      icon: Icon(api.themeOn ? Icons.volume_up : Icons.volume_off, color: Colors.white),
                      onPressed: () {
                        setState(() => api.themeOn = !api.themeOn);
                        api.themeOn ? ThemeMusic.I.start(widget.id) : ThemeMusic.I.stop(ifOwner: widget.id);
                      },
                    ),
                  ),
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
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              AgeBadge(x['OfficialRating'], size: 26),
              for (final k in ds) DescIcon(k, size: 26),
              for (final c in chips)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(46), borderRadius: BorderRadius.circular(4)),
                  child: Text(c, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              Text(meta, style: const TextStyle(color: Color(0xFFDFE4F5), fontSize: 13)),
            ]),
            if (genres.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(genres, style: const TextStyle(fontSize: 13))),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF9F9F9),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                onPressed: () async {
                  await openPlayer(context, p);
                },
                icon: const Icon(Icons.play_arrow, size: 28),
                label: Text(playLabel(), style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.4)),
              ),
            ),
            if (res && ((p['RunTimeTicks'] as num?) ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (resTicks / (p['RunTimeTicks'] as num)).clamp(0, 1).toDouble(),
                    minHeight: 3,
                    backgroundColor: Colors.white24,
                    color: const Color(0xFF4DA6FF),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _act(fav ? Icons.check : Icons.add, 'Listem', () => flag('fav', !fav)),
              if (tr != null)
                _act(Icons.movie_creation_outlined, 'Fragman',
                    () => launchUrl(Uri.parse(tr), mode: LaunchMode.externalApplication)),
              if (res) _act(Icons.replay, 'Baştan', () => openPlayer(context, p, restart: true)),
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
            // sekmeler
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24, width: 1.5))),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final t in tabs)
                    GestureDetector(
                      onTap: () => setState(() => tab = t[0]),
                      child: Container(
                        margin: const EdgeInsets.only(right: 26),
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 9),
                        decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: tab == t[0] ? Colors.white : Colors.transparent, width: 3))),
                        child: Text(t[1].toUpperCase(),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                                color: tab == t[0] ? Colors.white : Colors.white60)),
                      ),
                    ),
                ]),
              ),
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

  Widget _act(IconData i, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: Colors.black54, border: Border.all(color: Colors.white, width: 2)),
              child: Icon(i, size: 22),
            ),
            const SizedBox(height: 5),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFFCFD5EA))),
          ]),
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
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  children: [
                    for (final s in seasons)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(s == null || s == 0 ? 'Özel' : '$s. Sezon'),
                          selected: s == season,
                          onSelected: (_) => setState(() => season = s),
                        ),
                      ),
                  ],
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
    return InkWell(
      onTap: () => openPlayer(c, e),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(fit: StackFit.expand, children: [
                Container(color: kCard),
                netImg(img),
                const Center(child: Icon(Icons.play_circle_outline, size: 34, color: Colors.white70)),
                if (pr > 0 && pr < 100)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: FractionallySizedBox(
                        widthFactor: pr / 100, child: Container(height: 3, color: const Color(0xFF4DA6FF))),
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
            Text([rt(e['RunTimeTicks']), if (ud['Played'] == true) 'İzlendi ✓'].where((s) => s.isNotEmpty).join(' • '),
                style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${e['Overview'] ?? ''}',
                maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFFCFD5EA), height: 1.4)),
          ]),
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
      ['Oyuncular', names((p) => p['Type'] == 'Actor', 12)],
      ['Türler', ((x['Genres'] as List?) ?? const []).join(', ')],
      ['Stüdyo', ((x['Studios'] as List?) ?? const []).map((s) => '${s['Name']}').join(', ')],
      ['Yaş sınırı', '${x['OfficialRating'] ?? ''}'],
      ['İçerik işaretleri', descs(x).map((k) => kDesc[k]).join(', ')],
      ['Yayın', '${x['PremiereDate'] ?? ''}'.split('T').first],
      ['Süre', rt(x['RunTimeTicks'])],
    ].where((r) => r[1].isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
