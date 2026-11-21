import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'nav.dart';
import 'seerr.dart';
import 'util.dart';
import 'widgets.dart';

const _muted = Color(0x8CF5F5F7);

/// 3.0 keşif: Top 10, Yakında, Seri sırası
class Discover {
  Discover._();
  static final Discover I = Discover._();
  Api get api => Api.I;

  List<J>? _top;
  DateTime _topAt = DateTime(2000);

  /// Bugün popüler olanlardan sunucunda bulunan ilk 10 (Seerr gerekiyor).
  Future<List<J>> top10() async {
    if (_top != null && DateTime.now().difference(_topAt).inMinutes < 30) return _top!;
    if (!Seerr.I.on) return const [];
    final pages = await Future.wait([1, 2, 3, 4].map((p) => Seerr.I.trending(page: p).catchError((_) => <J>[])));
    final avail = <J>[];
    final seen = <String>{};
    for (final x in pages.expand((l) => l)) {
      final mi = x['mediaInfo'] as Map?;
      final st = (mi?['status'] as num?)?.toInt() ?? 0;
      if (st != 5 && st != 4) continue; // 5: mevcut, 4: kısmen mevcut
      if (!seen.add('${x['mediaType']}${x['id']}')) continue;
      avail.add(x);
      if (avail.length >= 14) break;
    }
    final found = await Future.wait(avail.map(_match));
    final out = <J>[];
    final ids = <String>{};
    for (final j in found) {
      if (j == null || !ids.add('${j['Id']}')) continue;
      out.add(j);
      if (out.length == 10) break;
    }
    _top = out;
    _topAt = DateTime.now();
    return out;
  }

  /// Seerr sonucunu Jellyfin öğesine çevirir: önce kayıtlı Jellyfin kimliği, yoksa ad + yıl.
  Future<J?> _match(J x) async {
    final u = api.uid;
    final jid = (x['mediaInfo'] as Map?)?['jellyfinMediaId'];
    if (jid != null && '$jid'.isNotEmpty) {
      try {
        final l = await api.items('/Users/$u/Items?Ids=$jid&Fields=$kFields');
        if (l.isNotEmpty) return l.first;
      } catch (_) {}
    }
    final title = '${x['title'] ?? x['name'] ?? ''}';
    if (title.isEmpty) return null;
    final year = '${x['releaseDate'] ?? x['firstAirDate'] ?? ''}'.split('-').first;
    final type = x['mediaType'] == 'tv' ? 'Series' : 'Movie';
    try {
      final l = await api.items('/Users/$u/Items?searchTerm=${Uri.encodeQueryComponent(title)}'
          '&IncludeItemTypes=$type&Recursive=true&Limit=6&Fields=$kFields');
      if (l.isEmpty) return null;
      return l.firstWhere((e) => '${e['ProductionYear'] ?? ''}' == year, orElse: () => l.first);
    } catch (_) {
      return null;
    }
  }

  /// Takip ettiğin dizilerin çıkacak bölümleri (Jellyfin'in bildiği tarihler).
  Future<List<J>> upcoming() async {
    final l = await api.items('/Shows/Upcoming?UserId=${api.uid}&Limit=80&Fields=$kFields,PremiereDate'
        '&EnableImageTypes=Primary,Backdrop,Thumb&ImageTypeLimit=1');
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return l.where((e) {
      final d = premiere(e);
      return d != null && !d.isBefore(start);
    }).toList()
      ..sort((a, b) => premiere(a)!.compareTo(premiere(b)!));
  }

  static DateTime? premiere(J e) => DateTime.tryParse('${e['PremiereDate'] ?? ''}')?.toLocal();

  // ---------- seri sırası ----------
  Map<String, String>? _boxOf; // film id → koleksiyon id
  Map<String, J> _boxes = {};
  Future<void>? _indexing;

  Future<void> _index() async {
    final u = api.uid;
    final boxes = await api.items('/Users/$u/Items?IncludeItemTypes=BoxSet&Recursive=true&Limit=500');
    final map = <String, String>{};
    _boxes = {for (final b in boxes) '${b['Id']}': b};
    final ids = boxes.map((b) => '${b['Id']}').toList();
    for (var i = 0; i < ids.length; i += 8) {
      final part = ids.sublist(i, i + 8 > ids.length ? ids.length : i + 8);
      await Future.wait(part.map((bid) async {
        try {
          final kids = await api.items('/Users/$u/Items?ParentId=$bid&Limit=200');
          for (final k in kids) {
            map.putIfAbsent('${k['Id']}', () => bid);
          }
        } catch (_) {}
      }));
    }
    _boxOf = map;
  }

  /// Bu filmin bağlı olduğu koleksiyon ve içindekiler, çıkış sırasına göre.
  Future<({J box, List<J> items})?> seriesOrder(String id) async {
    if (_boxOf == null) {
      _indexing ??= _index().catchError((_) {
        _indexing = null;
      });
      await _indexing;
    }
    final bid = _boxOf?[id];
    if (bid == null) return null;
    final kids = await api.items('/Users/${api.uid}/Items?ParentId=$bid&Fields=$kFields,PremiereDate'
        '&SortBy=PremiereDate,ProductionYear,SortName&SortOrder=Ascending&Limit=200');
    final films = kids.where((k) => k['Type'] == 'Movie' || k['Type'] == 'Series').toList();
    if (films.length < 2) return null;
    return (box: _boxes[bid] ?? <String, dynamic>{'Id': bid, 'Name': 'Seri'}, items: films);
  }
}

// =================== Top 10 ===================
class Top10Shelf extends StatelessWidget {
  final List<J> items;
  const Top10Shelf(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    if (items.length < 3) return const SizedBox.shrink();
    final pad = hPad(context);
    final w = MediaQuery.sizeOf(context).width > 700 ? 150.0 : 122.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 22, pad, 0),
        child: const Text('Bugün Top 10', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 2, pad, 0),
        child: const Text('Dünyada bugün en çok konuşulanlardan arşivinde olanlar', style: TextStyle(fontSize: 12, color: _muted)),
      ),
      SizedBox(
        height: w * 1.5 + 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (c, i) => _TopCard(items[i], i + 1, w),
        ),
      ),
    ]);
  }
}

String? posterUrl(J x, {int w = 400}) {
  final t = (x['ImageTags'] as Map?)?['Primary'];
  if (t != null) return Api.I.image('${x['Id']}', 'Primary', tag: '$t', w: w);
  final st = x['SeriesPrimaryImageTag'];
  if (st != null && x['SeriesId'] != null) return Api.I.image('${x['SeriesId']}', 'Primary', tag: '$st', w: w);
  return null;
}

class _TopCard extends StatelessWidget {
  final J x;
  final int n;
  final double w;
  const _TopCard(this.x, this.n, this.w);

  @override
  Widget build(BuildContext context) {
    final img = posterUrl(x);
    final meta = [x['Type'] == 'Series' ? 'Dizi' : 'Film', ...((x['Genres'] as List?) ?? const []).take(1).map((g) => '$g')].join(' · ');
    return Semantics(
      button: true,
      label: '$n. ${x['Name'] ?? ''}',
      child: Pressable(
        onTap: () => openItem(context, x),
        child: SizedBox(
          width: w,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: w,
              height: w * 1.5,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 8))],
              ),
              child: img == null
                  ? Center(child: Text('${x['Name'] ?? ''}', textAlign: TextAlign.center))
                  : netImg(img),
            ),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: n >= 10 ? 34 : 22,
                child: Text('$n',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1, color: kAccent)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${x['Name'] ?? ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _muted)),
                ]),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// =================== Yakında ===================
const _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

String dayLabel(DateTime d, {bool short = false}) {
  final now = DateTime.now();
  final t = DateTime(now.year, now.month, now.day);
  final x = DateTime(d.year, d.month, d.day);
  final diff = x.difference(t).inDays;
  if (diff == 0) return 'Bugün';
  if (diff == 1) return 'Yarın';
  if (short && diff < 7) return _days[x.weekday - 1];
  return '${_days[x.weekday - 1]}, ${x.day} ${_months[x.month - 1]}';
}

String _epLine(J e) => [
      if (e['ParentIndexNumber'] != null && e['IndexNumber'] != null) 'S${e['ParentIndexNumber']} · B${e['IndexNumber']}',
      if ('${e['Name'] ?? ''}'.isNotEmpty && !'${e['Name']}'.startsWith('Episode') && !'${e['Name']}'.startsWith('Bölüm'))
        '${e['Name']}',
    ].join(' · ');

class UpcomingShelf extends StatelessWidget {
  final List<J> items;
  const UpcomingShelf(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final pad = hPad(context);
    final sw = MediaQuery.sizeOf(context).width;
    final cw = sw > 700 ? cardWidth(context) : sw * .56;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 22, pad, 2),
        child: Pressable(
          onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => UpcomingScreen(initial: items))),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Yakında', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
            Icon(Icons.chevron_right_rounded, size: 24, color: Color(0x99F5F5F7)),
          ]),
        ),
      ),
      SizedBox(
        height: cw * 9 / 16 + 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 10, pad, 18),
          itemCount: items.length > 12 ? 12 : items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (c, i) {
            final e = items[i];
            final d = Discover.premiere(e)!;
            return SizedBox(
              width: cw,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stack(children: [
                  WideCard(e, width: cw, text: true),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Glass(
                      radius: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(dayLabel(d, short: true), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('${e['SeriesName'] ?? e['Name'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_epLine(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

/// Tam sayfa takvim: günlere göre gruplu
class UpcomingScreen extends StatefulWidget {
  final List<J>? initial;
  const UpcomingScreen({super.key, this.initial});
  @override
  State<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends State<UpcomingScreen> {
  late List<J>? list = widget.initial;
  String err = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final l = await Discover.I.upcoming();
      if (mounted) setState(() => list = l);
    } catch (e) {
      if (mounted && list == null) setState(() => err = 'Takvim alınamadı.\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    final l = list;
    final groups = <String, List<J>>{};
    for (final e in l ?? const <J>[]) {
      (groups[dayLabel(Discover.premiere(e)!)] ??= []).add(e);
    }
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          iosNav('Yakında', back: 'Ana sayfa'),
          CupertinoSliverRefreshControl(onRefresh: load),
          if (err.isNotEmpty)
            SliverFillRemaining(hasScrollBody: false, child: ErrorView(err, retry: load))
          else if (l == null)
            const SliverFillRemaining(hasScrollBody: false, child: Loading())
          else if (l.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(40, 0, 40, 120),
                child: Center(
                  child: Text(
                      'Yakında çıkacak bölüm yok. Jellyfin, takip ettiğin dizilerin yayın tarihi belli olan bölümlerini burada gösterir.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, height: 1.4)),
                ),
              ),
            )
          else
            for (final g in groups.entries) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad + 4, 20, pad, 8),
                  child: Text(g.key.toUpperCase(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .5, color: _muted)),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverList.separated(
                  itemCount: g.value.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (c, i) {
                    final e = g.value[i];
                    return Pressable(
                      onTap: () => openItem(c, e),
                      child: Row(children: [
                        WideCard(e, width: 112, text: true, onTap: () => openItem(c, e)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${e['SeriesName'] ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(_epLine(e), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

// =================== Seri sırası (detay sayfası) ===================
class SeriesOrderShelf extends StatelessWidget {
  final J box;
  final List<J> items;
  final String current;
  const SeriesOrderShelf({super.key, required this.box, required this.items, required this.current});

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    final cw = MediaQuery.sizeOf(context).width > 700 ? 220.0 : 168.0;
    final at = items.indexWhere((e) => '${e['Id']}' == current);
    final ctl = ScrollController(initialScrollOffset: at > 1 ? (at - 1) * (cw + 12) : 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 6, pad, 0),
        child: Pressable(
          onTap: () => openItem(context, box),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Seri sırası', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
            const Icon(Icons.chevron_right_rounded, size: 24, color: Color(0x99F5F5F7)),
          ]),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 2, pad, 0),
        child: Text('${box['Name'] ?? ''} · ${items.length} yapım · çıkış sırasıyla',
            style: const TextStyle(fontSize: 12, color: _muted)),
      ),
      SizedBox(
        height: cw * 9 / 16 + 62,
        child: ListView.separated(
          controller: ctl,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (c, i) {
            final e = items[i];
            final me = '${e['Id']}' == current;
            final seen = e['UserData']?['Played'] == true;
            return SizedBox(
              width: cw,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stack(children: [
                  Opacity(
                    opacity: me ? 1 : .92,
                    child: WideCard(e, width: cw, onTap: me ? () {} : () => openItem(c, e)),
                  ),
                  if (me)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14), border: Border.all(color: kBlue, width: 2)),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: me ? kBlue : const Color(0xB3000000), borderRadius: BorderRadius.circular(12)),
                      child: Text(me ? '${i + 1} · Bu film' : '${i + 1}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: me ? kInk : Colors.white)),
                    ),
                  ),
                  if (seen)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: Icon(Icons.check_circle_rounded, size: 22, color: Colors.white),
                    ),
                ]),
                const SizedBox(height: 7),
                Text('${e['Name'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${e['ProductionYear'] ?? ''}', style: const TextStyle(fontSize: 11, color: _muted)),
              ]),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
    ]);
  }
}
