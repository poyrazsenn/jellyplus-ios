import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  /// Son durum (ana sayfada açıklama göstermek için): '', seerr, err, none
  String topNote = '';

  /// Bugün popüler olanlardan sunucunda bulunan ilk 10.
  /// Popüler listesi Seerr'den gelir; eşleşme Jellyfin'deki TMDB numarasıyla yapılır,
  /// Seerr'in kendi kütüphane taramasına güvenilmez.
  Future<List<J>> top10() async {
    if (_top != null && _top!.isNotEmpty && DateTime.now().difference(_topAt).inMinutes < 30) return _top!;
    topNote = '';
    if (!Seerr.I.on) {
      topNote = 'seerr';
      return const [];
    }
    final u = api.uid;
    List<List<J>> pages;
    try {
      pages = await Future.wait([1, 2, 3, 4, 5].map((p) => Seerr.I.trending(page: p)));
    } catch (e) {
      topNote = 'err';
      return const [];
    }
    final lib = await api.items('/Users/$u/Items?IncludeItemTypes=Movie,Series&Recursive=true'
        '&Fields=ProviderIds,OriginalTitle,$kFields&EnableImageTypes=Primary,Backdrop,Thumb,Logo&ImageTypeLimit=1');
    final byTmdb = <String, J>{};
    final byName = <String, J>{};
    for (final x in lib) {
      final t = (x['ProviderIds'] as Map?)?['Tmdb'];
      final kind = x['Type'] == 'Series' ? 'tv' : 'movie';
      if (t != null && '$t'.isNotEmpty) byTmdb['$kind$t'] = x;
      byName['$kind|${_norm('${x['Name'] ?? ''}')}|${x['ProductionYear'] ?? ''}'] = x;
      byName.putIfAbsent('$kind|${_norm('${x['OriginalTitle'] ?? ''}')}|${x['ProductionYear'] ?? ''}', () => x);
    }
    final out = <J>[];
    final ids = <String>{};
    for (final r in pages.expand((l) => l)) {
      final kind = '${r['mediaType']}';
      final year = '${r['releaseDate'] ?? r['firstAirDate'] ?? ''}'.split('-').first;
      J? j = byTmdb['$kind${r['id']}'];
      j ??= byName['$kind|${_norm('${r['title'] ?? r['name'] ?? ''}')}|$year'];
      j ??= byName['$kind|${_norm('${r['originalTitle'] ?? r['originalName'] ?? ''}')}|$year'];
      if (j == null || !ids.add('${j['Id']}')) continue;
      out.add(j);
      if (out.length == 10) break;
    }
    if (out.isEmpty) topNote = 'none';
    _top = out;
    _topAt = DateTime.now();
    return out;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9çğıöşü]'), '');

  final Map<String, (DateTime, J?)> _next = {}; // dizi id → (ne zaman alındı, sıradaki bölüm)

  final Map<String, int?> _maze = {}; // dizi id → TVmaze id

  Future<dynamic> _mazeGet(String path) async {
    final r = await http.get(Uri.parse('https://api.tvmaze.com$path')).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// TVmaze: yayın günleri platforma göre doğru (ör. Paramount+ Cuma); anahtar gerekmez.
  Future<List<J>?> _mazeEpisodes(J series) async {
    final sid = '${series['Id']}';
    final pid = (series['ProviderIds'] as Map?) ?? const {};
    if (!_maze.containsKey(sid)) {
      int? id;
      for (final q in [
        if (pid['Imdb'] != null) 'imdb=${pid['Imdb']}',
        if (pid['Tvdb'] != null) 'thetvdb=${pid['Tvdb']}',
      ]) {
        final r = await _mazeGet('/lookup/shows?$q');
        if (r is Map && r['id'] != null) {
          id = (r['id'] as num).toInt();
          break;
        }
      }
      _maze[sid] = id;
    }
    final id = _maze[sid];
    if (id == null) return null;
    final l = await _mazeGet('/shows/$id/episodes');
    return l is List ? l.map((e) => J.from(e as Map)).toList() : null;
  }

  /// Bir dizinin sıradaki bölümü. Tarih TVmaze'den (yoksa Seerr/TMDB'den),
  /// Türkçe ad ve görsel Seerr'den. Sunucunda zaten olan bölümler atlanır.
  Future<J?> nextEpisode(J series) async {
    final sid = '${series['Id']}';
    final c = _next[sid];
    if (c != null && DateTime.now().difference(c.$1).inHours < 6) return c.$2;
    final tmdb = (series['ProviderIds'] as Map?)?['Tmdb'];
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);

    final have = <String>{};
    try {
      final l = await api.items('/Shows/$sid/Episodes?UserId=${api.uid}&IsMissing=false&Fields=');
      for (final e in l) {
        if (e['LocationType'] == 'Virtual') continue;
        have.add('${e['ParentIndexNumber']}x${e['IndexNumber']}');
      }
    } catch (_) {}

    int? sn, en;
    String? when, name, still;
    var ok = false;
    // 1) TVmaze
    try {
      final eps = await _mazeEpisodes(series);
      if (eps != null) {
        ok = true;
        for (final e in eps) {
          final at = DateTime.tryParse('${e['airstamp'] ?? ''}')?.toLocal();
          if (at == null || at.isBefore(start)) continue;
          if (e['number'] == null || have.contains('${e['season']}x${e['number']}')) continue;
          sn = (e['season'] as num?)?.toInt();
          en = (e['number'] as num?)?.toInt();
          when = at.toIso8601String();
          name = '${e['name'] ?? ''}';
          final im = e['image'] as Map?;
          if (im?['original'] != null) still = '${im!['original']}';
          break;
        }
      }
    } catch (_) {}
    // 2) Seerr: TVmaze bulamadıysa tarih, bulduysa Türkçe ad ve görsel
    if (Seerr.I.on && tmdb != null && '$tmdb'.isNotEmpty) {
      try {
        if (!ok) {
          final d = await Seerr.I.tv('$tmdb');
          final n = d?['nextEpisodeToAir'] as Map?;
          if (n != null) {
            ok = true;
            final s0 = (n['seasonNumber'] as num?)?.toInt() ?? 0;
            for (final e in [J.from(n), ...await Seerr.I.season('$tmdb', s0).catchError((_) => <J>[])]) {
              final at = DateTime.tryParse('${e['airDate'] ?? ''}');
              if (at == null || at.isBefore(start)) continue;
              if (have.contains('${e['seasonNumber'] ?? s0}x${e['episodeNumber']}')) continue;
              sn = (e['seasonNumber'] as num?)?.toInt() ?? s0;
              en = (e['episodeNumber'] as num?)?.toInt();
              when = '${e['airDate']}';
              name = '${e['name'] ?? ''}';
              if ('${e['stillPath'] ?? ''}'.isNotEmpty) still = 'https://image.tmdb.org/t/p/w780${e['stillPath']}';
              break;
            }
          }
        } else if (sn != null && en != null) {
          for (final e in await Seerr.I.season('$tmdb', sn)) {
            if ((e['episodeNumber'] as num?)?.toInt() != en) continue;
            if ('${e['name'] ?? ''}'.isNotEmpty) name = '${e['name']}';
            if ('${e['stillPath'] ?? ''}'.isNotEmpty) still = 'https://image.tmdb.org/t/p/w780${e['stillPath']}';
            break;
          }
        }
      } catch (_) {}
    }
    if (!ok) return null; // ikisine de ulaşılamadı: önbelleğe yazma, sonra yeniden dene
    J? out;
    if (when != null && en != null) {
      out = <String, dynamic>{
        'Type': 'Episode',
        'Id': sid,
        'SeriesId': sid,
        'SeriesName': series['Name'],
        'Name': name,
        'ParentIndexNumber': sn,
        'IndexNumber': en,
        'PremiereDate': when,
        'ImageTags': {if ((series['ImageTags'] as Map?)?['Thumb'] != null) 'Thumb': series['ImageTags']['Thumb']},
        'BackdropImageTags': series['BackdropImageTags'] ?? const [],
        'SeriesPrimaryImageTag': (series['ImageTags'] as Map?)?['Primary'],
        if (still != null) '_img': still,
      };
    }
    _next[sid] = (DateTime.now(), out);
    return out;
  }

  /// Kütüphanendeki devam eden dizilerin çıkacak bölümleri.
  /// Tarihler TVmaze'den (yoksa Seerr/TMDB'den) gelir; Jellyfin'in bildiği gelecek bölümler de eklenir.
  Future<List<J>> upcoming() async {
    final u = api.uid;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final r = await Future.wait<List<J>>([
      api
          .items('/Shows/Upcoming?UserId=$u&Limit=80&Fields=$kFields,PremiereDate,LocationType'
              '&EnableImageTypes=Primary,Backdrop,Thumb&ImageTypeLimit=1')
          .catchError((_) => <J>[]),
      api
          .items('/Users/$u/Items?IncludeItemTypes=Series&Recursive=true&SeriesStatus=Continuing'
              '&Fields=ProviderIds,$kFields&EnableImageTypes=Primary,Backdrop,Thumb&ImageTypeLimit=1')
          .catchError((_) => <J>[]),
    ]);
    final fromSeerr = <J>[];
    final shows = r[1];
    for (var i = 0; i < shows.length; i += 8) {
      final part = shows.sublist(i, i + 8 > shows.length ? shows.length : i + 8);
      final got = await Future.wait(part.map(nextEpisode));
      fromSeerr.addAll(got.whereType<J>());
    }
    final seen = <String>{};
    final all = <J>[];
    for (final e in [...r[0].where((e) => e['LocationType'] == 'Virtual' || e['LocationType'] == null), ...fromSeerr]) {
      final d = premiere(e);
      if (d == null || d.isBefore(start)) continue;
      if (!seen.add('${e['SeriesId']}|${e['ParentIndexNumber']}|${e['IndexNumber']}')) continue;
      all.add(e);
    }
    return all..sort((a, b) => premiere(a)!.compareTo(premiere(b)!));
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
    final films = await collectionItems(bid);
    if (films.length < 2) return null;
    return (box: _boxes[bid] ?? <String, dynamic>{'Id': bid, 'Name': 'Seri'}, items: films);
  }

  /// Koleksiyonun içindekiler, çıkış sırasıyla
  Future<List<J>> collectionItems(String bid) async {
    final kids = await api.items('/Users/${api.uid}/Items?ParentId=$bid&Fields=$kFields,PremiereDate'
        '&SortBy=PremiereDate,ProductionYear,SortName&SortOrder=Ascending&Limit=200');
    return kids.where((k) => k['Type'] == 'Movie' || k['Type'] == 'Series').toList();
  }
}

// =================== Top 10 ===================
class Top10Shelf extends StatelessWidget {
  final List<J> items;
  const Top10Shelf(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    if (items.isEmpty) {
      final note = Discover.I.topNote;
      if (note.isEmpty) return const SizedBox.shrink();
      final msg = note == 'seerr'
          ? 'Top 10 listesi Seerr üzerinden gelir. Profil → Seerr\'den bağlayınca burada görünür.'
          : note == 'err'
              ? 'Top 10 için Seerr\'e ulaşılamadı. Profil → Seerr\'den bağlantıyı dene.'
              : 'Bugünün popüler yapımlarından hiçbiri arşivinde yok.';
      return Padding(
        padding: EdgeInsets.fromLTRB(pad, 22, pad, 0),
        child: Pressable(
          onTap: note == 'none' ? null : () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const SeerrSettingsScreen())),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white.withAlpha(13), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.emoji_events_outlined, color: kAccent),
              const SizedBox(width: 12),
              Expanded(child: Text(msg, style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xB8F5F5F7)))),
              if (note != 'none') const Icon(Icons.chevron_right_rounded, color: _muted),
            ]),
          ),
        ),
      );
    }
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
                      'Yakında çıkacak bölüm yok. Kütüphanendeki devam eden dizilerin yeni bölüm tarihi açıklanınca burada görünür.',
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

/// Dizi sayfası: "Yeni bölüm · Cuma, 27 Kasım"
class NextEpisodeRow extends StatelessWidget {
  final J ep;
  const NextEpisodeRow(this.ep, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = Discover.premiere(ep)!;
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
        .inDays;
    final when = dayLabel(d);
    final left = days >= 2 ? '$days gün sonra' : '';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: kAccent.withAlpha(36), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.calendar_month_outlined, size: 20, color: kAccent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Yeni bölüm · $when', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text([_epLine(ep), if (left.isNotEmpty) left].where((x) => x.isNotEmpty).join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
      ]),
    );
  }
}

// =================== Poster ızgarası (Koleksiyon / Benzerleri) ===================
class PosterTile extends StatelessWidget {
  final J x;
  final int? n;
  final bool current;
  const PosterTile(this.x, {super.key, this.n, this.current = false});

  @override
  Widget build(BuildContext context) {
    final img = posterUrl(x);
    final seen = x['UserData']?['Played'] == true;
    return Semantics(
      button: true,
      label: '${n != null ? '$n. ' : ''}${x['Name'] ?? ''}${current ? ', şu an açık' : ''}',
      child: Pressable(
        onTap: current ? null : () => openItem(context, x),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(10),
            border: current ? Border.all(color: kBlue, width: 2) : null,
          ),
          child: Stack(fit: StackFit.expand, children: [
            if (img != null)
              netImg(img)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${x['Name'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            if (n != null)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  height: 22,
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: current ? kBlue : const Color(0xB3000000), borderRadius: BorderRadius.circular(11)),
                  child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: current ? kInk : Colors.white)),
                ),
              ),
            if (seen)
              const Positioned(right: 6, top: 6, child: Icon(Icons.check_circle_rounded, size: 20, color: Colors.white)),
            if (((x['UserData']?['PlayedPercentage'] as num?) ?? 0) > 0 && !seen)
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      value: (x['UserData']['PlayedPercentage'] as num) / 100, color: kBlue, backgroundColor: const Color(0x40FFFFFF)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

int posterCols(double w) => w > 1000 ? 6 : (w > 700 ? 5 : 3);

SliverPadding posterGrid(List<J> list, double pad, double w, {bool numbered = false, String? current}) => SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: pad),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: posterCols(w), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2 / 3),
        delegate: SliverChildBuilderDelegate(
          (c, i) => PosterTile(list[i], n: numbered ? i + 1 : null, current: '${list[i]['Id']}' == current),
          childCount: list.length,
        ),
      ),
    );

// =================== Koleksiyon sayfası ===================
class CollectionScreen extends StatefulWidget {
  final String id;
  const CollectionScreen({super.key, required this.id});
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  J? box;
  List<J>? items;
  String err = '';

  @override
  void initState() {
    super.initState();
    load();
    refreshBus.addListener(load);
  }

  @override
  void dispose() {
    refreshBus.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait<dynamic>([Api.I.item(widget.id), Discover.I.collectionItems(widget.id)]);
      if (mounted) {
        setState(() {
          box = r[0] as J;
          items = r[1] as List<J>;
          err = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => err = 'Koleksiyon yüklenemedi.\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    final pad = hPad(context);
    final b = box, l = items;
    Widget back() => Positioned(
          left: 14,
          top: top + 8,
          child: GlassIcon(Icons.arrow_back_ios_new_rounded, tooltip: 'Geri', onTap: () => Navigator.of(context).maybePop()),
        );
    if (err.isNotEmpty || b == null || l == null) {
      return Scaffold(
        backgroundColor: kBg,
        body: Stack(children: [
          Positioned.fill(child: err.isNotEmpty ? ErrorView(err, retry: load) : const Loading()),
          back(),
        ]),
      );
    }
    bool played(J v) => v['UserData']?['Played'] == true;
    num pos(J v) => (v['UserData']?['PlaybackPositionTicks'] as num?) ?? 0;
    final seen = l.where(played).length;
    final next = l.firstWhere((v) => pos(v) > 0 && !played(v), orElse: () => l.firstWhere((v) => !played(v), orElse: () => l.first));
    final idx = l.indexOf(next) + 1;
    final label = pos(next) > 0 && !played(next)
        ? 'Devam et · $idx. ${next['Name'] ?? ''}'
        : seen == 0
            ? 'Sırayla izle'
            : seen == l.length
                ? 'Baştan izle'
                : 'Sıradaki · $idx. ${next['Name'] ?? ''}';
    final heroH = w > 700 ? w * .42 : w * 9 / 16 + top;
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: heroH,
              child: Stack(fit: StackFit.expand, children: [
                netImg(backdrop(b), align: const Alignment(.3, -.4)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x660B0B0D), Color(0x000B0B0D), kBg],
                        stops: [0, .45, 1]),
                  ),
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
            sliver: SliverList.list(children: [
              Text('${b['Name'] ?? ''}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.8, height: 1.1)),
              const SizedBox(height: 6),
              Text('Koleksiyon · ${l.length} yapım · ${seen == 0 ? 'hiçbiri izlenmedi' : '$seen\'i izlendi'}',
                  style: const TextStyle(fontSize: 13, color: Color(0xB8F5F5F7))),
              if (seen > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                      value: seen / l.length, minHeight: 4, color: kBlue, backgroundColor: Colors.white.withAlpha(38)),
                ),
              ],
              const SizedBox(height: 16),
              PillButton(label, icon: Icons.play_arrow_rounded, height: 50, expand: true, onTap: () {
                if (next['Type'] == 'Series') {
                  openItem(context, next);
                } else {
                  openPlayer(context, next, restart: seen == l.length);
                }
              }),
              if ('${b['Overview'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('${b['Overview']}', style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xD9F5F5F7))),
              ],
              const SizedBox(height: 22),
              const Text('Çıkış sırasıyla', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
              const SizedBox(height: 12),
            ]),
          ),
          posterGrid(l, pad, w, numbered: true),
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ]),
        back(),
      ]),
    );
  }
}
