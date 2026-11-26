import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'nav.dart';
import 'seerr.dart';
import 'util.dart';
import 'widgets.dart';

const _muted = Color(0x8CF5F5F7);
const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

String _title(J x) => '${x['title'] ?? x['name'] ?? ''}';
String _date(J x) => '${x['releaseDate'] ?? x['firstAirDate'] ?? ''}';
String _year(J x) => _date(x).split('-').first;
int _status(J x) => ((x['mediaInfo'] as Map?)?['status'] as num?)?.toInt() ?? 1;

String _dayMonth(String d) {
  final t = DateTime.tryParse(d);
  return t == null ? '' : '${t.day} ${_months[t.month - 1]}';
}

class _Row {
  final String title, path;
  final bool upcoming;
  List<J> items = [];
  int page = 0, pages = 1;
  bool busy = false;
  _Row(this.title, this.path, {this.upcoming = false});
}

/// Keşfet: Seerr'den (TMDB) trendler, popülerler ve yakında çıkacaklar. Sunucuda olması gerekmez.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final rows = [
    _Row('Bugün trend', '/discover/trending'),
    _Row('Popüler filmler', '/discover/movies'),
    _Row('Popüler diziler', '/discover/tv'),
    _Row('Yakında vizyonda', '/discover/movies/upcoming', upcoming: true),
    _Row('Yakında başlayacak diziler', '/discover/tv/upcoming', upcoming: true),
  ];
  String err = '';
  bool started = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (!Seerr.I.on) {
      setState(() {});
      return;
    }
    for (final r in rows) {
      r.items = [];
      r.page = 0;
      r.pages = 1;
    }
    err = '';
    started = true;
    final ok = await Future.wait(rows.map(more));
    if (mounted && ok.every((x) => !x)) setState(() => err = 'Seerr\'e ulaşılamadı.');
  }

  Future<bool> more(_Row r) async {
    if (r.busy || r.page >= r.pages) return true;
    r.busy = true;
    try {
      final d = await Seerr.I.discover(r.path, page: r.page + 1);
      final seen = r.items.map((e) => '${e['mediaType']}${e['id']}').toSet();
      r.items.addAll(d.items.where((e) => seen.add('${e['mediaType']}${e['id']}')));
      r.page++;
      r.pages = d.pages;
      return true;
    } catch (_) {
      return false;
    } finally {
      r.busy = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    final w = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    if (!Seerr.I.on) {
      return Scaffold(
        backgroundColor: kBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.explore_outlined, size: 56, color: kAccent),
              const SizedBox(height: 16),
              const Text('Keşfet için Seerr gerekiyor', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Trendler, popülerler ve yakında çıkacaklar Seerr üzerinden gelir. Bağlayınca buradan istek de yapabilirsin.',
                  textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.4)),
              const SizedBox(height: 18),
              PillButton('Seerr\'i bağla', onTap: () async {
                await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const SeerrSettingsScreen()));
                reload();
              }),
            ]),
          ),
        ),
      );
    }
    final heroList = rows[0].items.where((e) => '${e['backdropPath'] ?? ''}'.isNotEmpty).toList();
    final hero = heroList.isEmpty ? null : heroList.first;
    final heroH = w > 700 ? w * .42 : min2(w * 1.05, 520);
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: reload),
          SliverToBoxAdapter(
            child: hero == null
                ? SizedBox(
                    height: top + 70,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad + 4, top + 14, pad, 0),
                      child: const Text('Keşfet', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    ),
                  )
                : _Hero(hero, height: heroH, top: top, pad: pad),
          ),
          if (err.isNotEmpty && rows.every((r) => r.items.isEmpty))
            SliverFillRemaining(hasScrollBody: false, child: ErrorView(err, retry: reload))
          else if (started && rows.every((r) => r.items.isEmpty))
            const SliverFillRemaining(hasScrollBody: false, child: Loading())
          else
            for (final r in rows)
              if (r.items.isNotEmpty) SliverToBoxAdapter(child: _RowView(r, onEnd: () => more(r))),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

double min2(double a, double b) => a < b ? a : b;

class _Hero extends StatelessWidget {
  final J x;
  final double height, top, pad;
  const _Hero(this.x, {required this.height, required this.top, required this.pad});

  @override
  Widget build(BuildContext context) {
    final st = _status(x);
    final meta = [
      x['mediaType'] == 'tv' ? 'Dizi' : 'Film',
      if (_year(x).isNotEmpty) _year(x),
      if (((x['voteAverage'] as num?) ?? 0) > 0) '★ ${(x['voteAverage'] as num).toStringAsFixed(1)}',
    ].join(' · ');
    return SizedBox(
      height: height,
      child: Stack(fit: StackFit.expand, children: [
        netImg(Seerr.poster(x['backdropPath'], 1280), align: const Alignment(.2, -.4)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x990B0B0D), Color(0x000B0B0D), Color(0x000B0B0D), kBg],
              stops: [0, .28, .5, 1],
            ),
          ),
        ),
        Positioned(
          left: pad + 4,
          top: top + 14,
          child: const Text('Keşfet', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
        ),
        Positioned(
          left: pad + 4,
          right: pad + 4,
          bottom: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('BUGÜN EN ÇOK KONUŞULAN',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: kAccent)),
            const SizedBox(height: 6),
            Text(_title(x),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.05)),
            const SizedBox(height: 6),
            Text(meta, style: const TextStyle(fontSize: 14, color: Color(0xCCF5F5F7))),
            const SizedBox(height: 14),
            Row(children: [
              PillButton(st >= 4 ? 'Ayrıntılar' : (st >= 2 ? 'İstendi' : 'Ayrıntılar ve iste'),
                  icon: st >= 4 ? Icons.check_rounded : Icons.info_outline_rounded,
                  onTap: () => openSeerr(context, x)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _RowView extends StatelessWidget {
  final _Row r;
  final VoidCallback onEnd;
  const _RowView(this.r, {required this.onEnd});

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    final cw = MediaQuery.sizeOf(context).width > 700 ? 150.0 : 118.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 22, pad, 0),
        child: Text(r.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
      ),
      SizedBox(
        height: cw * 1.5 + 58,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) onEnd();
            return false;
          },
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 4),
            itemCount: r.items.length + (r.page < r.pages ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (c, i) => i >= r.items.length
                ? SizedBox(width: 40, child: Center(child: r.busy ? const CupertinoActivityIndicator() : null))
                : SeerrPoster(r.items[i], width: cw, upcoming: r.upcoming),
          ),
        ),
      ),
    ]);
  }
}

/// Seerr afişi: sunucunda olanlarda ✓, istenmişlerde saat işareti
class SeerrPoster extends StatelessWidget {
  final J x;
  final double width;
  final bool upcoming;
  const SeerrPoster(this.x, {super.key, required this.width, this.upcoming = false});

  @override
  Widget build(BuildContext context) {
    final st = _status(x);
    final img = Seerr.poster(x['posterPath'], 342);
    final sub = upcoming && _dayMonth(_date(x)).isNotEmpty ? _dayMonth(_date(x)) : [x['mediaType'] == 'tv' ? 'Dizi' : 'Film', if (_year(x).isNotEmpty) _year(x)].join(' · ');
    return Semantics(
      button: true,
      label: '${_title(x)}${st >= 4 ? ', sunucunda var' : st >= 2 ? ', istendi' : ''}',
      child: Pressable(
        onTap: () => openSeerr(context, x),
        child: SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: width,
              height: width * 1.5,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6))],
              ),
              child: Stack(fit: StackFit.expand, children: [
                if (img.isNotEmpty)
                  netImg(img)
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_title(x), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                if (st >= 2)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: st >= 4 ? const Color(0xFF34C759) : const Color(0xE6000000),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(st >= 4 ? Icons.check_rounded : Icons.schedule_rounded, size: 15, color: Colors.white),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 7),
            Text(_title(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: upcoming ? kAccent : _muted)),
          ]),
        ),
      ),
    );
  }
}

Future<void> openSeerr(BuildContext c, J x) =>
    Navigator.of(c).push(CupertinoPageRoute(builder: (_) => SeerrDetailScreen(type: '${x['mediaType']}', id: '${x['id']}', seed: x)));

/// Seerr'deki bir yapımın sayfası: bilgiler, oyuncular ve İste / Oynat
class SeerrDetailScreen extends StatefulWidget {
  final String type, id;
  final J? seed;
  const SeerrDetailScreen({super.key, required this.type, required this.id, this.seed});
  @override
  State<SeerrDetailScreen> createState() => _SeerrDetailScreenState();
}

class _SeerrDetailScreenState extends State<SeerrDetailScreen> {
  J? x;
  String err = '';
  bool busy = false, more = false;

  @override
  void initState() {
    super.initState();
    x = widget.seed;
    load();
  }

  Future<void> load() async {
    try {
      final d = await Seerr.I.details(widget.type, widget.id);
      d['mediaType'] = widget.type;
      if (mounted) setState(() => x = d);
    } catch (e) {
      if (mounted && x == null) setState(() => err = 'Ayrıntılar alınamadı.\n$e');
    }
  }

  Future<void> ask() async {
    final v = x;
    if (v == null) return;
    setState(() => busy = true);
    HapticFeedback.mediumImpact();
    try {
      await Seerr.I.request(<String, dynamic>{'mediaType': widget.type, 'id': int.tryParse(widget.id) ?? widget.id});
      if (!mounted) return;
      setState(() => v['mediaInfo'] = {...((v['mediaInfo'] as Map?) ?? const {}), 'status': 2});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_title(v)} istendi.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e is SeerrError ? e.toString() : 'İstek gönderilemedi.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Sunucundaki kopyayı aç: önce Seerr'in bildiği Jellyfin kimliği, yoksa ad + yıl
  Future<void> play() async {
    final v = x!;
    final api = Api.I;
    setState(() => busy = true);
    try {
      J? it;
      final jid = '${(v['mediaInfo'] as Map?)?['jellyfinMediaId'] ?? ''}';
      if (jid.isNotEmpty) {
        try {
          it = await api.item(jid);
        } catch (_) {}
      }
      if (it == null) {
        final l = await api.items('/Users/${api.uid}/Items?searchTerm=${Uri.encodeQueryComponent(_title(v))}'
            '&Recursive=true&IncludeItemTypes=${widget.type == 'tv' ? 'Series' : 'Movie'}&Limit=6&Fields=$kFields');
        if (l.isNotEmpty) it = l.firstWhere((e) => '${e['ProductionYear'] ?? ''}' == _year(v), orElse: () => l.first);
      }
      if (!mounted) return;
      if (it == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Jellyfin\'de henüz görünmüyor; kütüphane taraması bitince gelir.')));
        return;
      }
      await openItem(context, it);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    final pad = w > 700 ? 48.0 : hPad(context);
    final v = x;
    Widget back() => Positioned(
          left: 14,
          top: top + 8,
          child: GlassIcon(Icons.arrow_back_ios_new_rounded, tooltip: 'Geri', onTap: () => Navigator.of(context).maybePop()),
        );
    if (v == null) {
      return Scaffold(
        backgroundColor: kBg,
        body: Stack(children: [Positioned.fill(child: err.isNotEmpty ? ErrorView(err, retry: load) : const Loading()), back()]),
      );
    }
    final st = Seerr.status(v['mediaInfo'] as Map?);
    final code = _status(v);
    final run = (v['runtime'] as num?) ?? (((v['episodeRunTime'] as List?) ?? const []).isNotEmpty ? v['episodeRunTime'][0] as num : null);
    final genres = ((v['genres'] as List?) ?? const []).map((g) => '${g['name']}').take(3).toList();
    final meta = [
      widget.type == 'tv' ? 'Dizi' : 'Film',
      if (_year(v).isNotEmpty) _year(v),
      if (widget.type == 'tv' && v['numberOfSeasons'] != null) '${v['numberOfSeasons']} Sezon',
      if (widget.type != 'tv' && run != null && run > 0) '${run ~/ 60 > 0 ? '${run ~/ 60} sa ' : ''}${run % 60} dk',
      if (((v['voteAverage'] as num?) ?? 0) > 0) '★ ${(v['voteAverage'] as num).toStringAsFixed(1)}',
    ].join(' · ');
    final when = DateTime.tryParse(_date(v));
    final future = when != null && when.isAfter(DateTime.now());
    final cast = (((v['credits'] as Map?)?['cast'] as List?) ?? const []).cast<Map>().take(15).toList();
    final imgH = w > 700 ? w * .45 : w * 9 / 16;

    Widget action() {
      if (code >= 4) return PillButton('Oynat', icon: Icons.play_arrow_rounded, height: 50, expand: true, busy: busy, onTap: play);
      if (code >= 2) {
        return Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(25)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.schedule_rounded, size: 20),
            const SizedBox(width: 8),
            Text('İstendi · ${st.text}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        );
      }
      return PillButton('İste', icon: Icons.add_rounded, height: 50, expand: true, busy: busy, onTap: ask);
    }

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: top + imgH,
              child: Stack(fit: StackFit.expand, children: [
                netImg(Seerr.poster(v['backdropPath'], 1280), align: const Alignment(.2, -.4)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x800B0B0D), Color(0x000B0B0D), kBg],
                      stops: [0, .4, 1],
                    ),
                  ),
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
            sliver: SliverList.list(children: [
              Text(_title(v), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.8, height: 1.1)),
              const SizedBox(height: 8),
              Text(meta, style: const TextStyle(fontSize: 14, color: Color(0xD9F5F5F7))),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(genres.join(', '), style: const TextStyle(fontSize: 13, color: _muted)),
              ],
              if (future) ...[
                const SizedBox(height: 10),
                Text('Çıkış: ${when.day} ${_months[when.month - 1]} ${when.year}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kAccent)),
              ],
              const SizedBox(height: 18),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: action()),
              if (code < 2)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Sunucunda yok. İstersen Seerr indirir ve hazır olunca kütüphanende görünür.',
                      style: TextStyle(fontSize: 12, color: _muted)),
                ),
              if ('${v['tagline'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('"${v['tagline']}"', style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: Color(0xCCF5F5F7))),
              ],
              if ('${v['overview'] ?? ''}'.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => more = !more),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('${v['overview']}',
                        maxLines: more ? null : 5,
                        overflow: more ? null : TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, height: 1.5)),
                  ),
                ),
              if (cast.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('Oyuncular', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
              ],
            ]),
          ),
          if (cast.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                  itemCount: cast.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final p = cast[i];
                    final img = Seerr.poster(p['profilePath'], 185);
                    return SizedBox(
                      width: 76,
                      child: Column(children: [
                        ClipOval(
                          child: Container(
                            width: 64,
                            height: 64,
                            color: kCard,
                            child: img.isEmpty ? const Icon(Icons.person_rounded, color: kMuted) : netImg(img),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('${p['name'] ?? ''}',
                            maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.3)),
                      ]),
                    );
                  },
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ]),
        back(),
      ]),
    );
  }
}
