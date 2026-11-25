import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'discover.dart';
import 'nav.dart';
import 'util.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Studio {
  final String id, name;
  int n = 0;
  String? img;
  _Studio(this.id, this.name);
}

class _HomeScreenState extends State<HomeScreen> {
  final api = Api.I;
  bool loading = true;
  String err = '';
  List<J> res = [], fav = [], feat = [], cols = [], libs = [];
  List<List<J>> lat = [];
  List<J> top = [], soon = [];
  final scrollY = ValueNotifier<double>(0);
  bool slow = false;
  Timer? _slowT;
  List<_Studio> studios = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
    refreshBus.addListener(_silent);
  }

  @override
  void dispose() {
    refreshBus.removeListener(_silent);
    scrollY.dispose();
    _slowT?.cancel();
    super.dispose();
  }

  void _silent() => load(silent: true);

  Future<List<J>> safe(Future<List<J>> f) async {
    try {
      return await f;
    } catch (_) {
      return <J>[];
    }
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        loading = true;
        err = '';
      });
    }
    final u = api.uid;
    _slowT?.cancel();
    if (!silent) {
      _slowT = Timer(const Duration(seconds: 10), () {
        if (mounted && loading) setState(() => slow = true);
      });
    }
    try {
      // 1) Önce ekranı dolduranlar: vitrin, devam et, kütüphaneler, Listem
      final r = await Future.wait<List<J>>([
        safe(api.items('/Users/$u/Items/Resume?Limit=12&MediaTypes=Video&Fields=$kFields')),
        api.items('/Users/$u/Views'),
        safe(api.items('/Users/$u/Items?Filters=IsFavorite&Recursive=true&IncludeItemTypes=Movie,Series&Limit=30&Fields=$kFields')),
        silent && feat.isNotEmpty
            ? Future.value(feat)
            : safe(api.items('/Users/$u/Items?IncludeItemTypes=Movie,Series&Recursive=true&SortBy=Random&Limit=24&ImageTypes=Backdrop&Fields=$kFields')),
      ]);
      final views = r[1]
          .where((v) => !['music', 'books', 'photos', 'playlists', 'livetv', 'boxsets', 'musicvideos'].contains(v['CollectionType']))
          .toList();
      if (!mounted) return;
      _slowT?.cancel();
      setState(() {
        res = r[0];
        libs = views;
        fav = r[2];
        feat = r[3].where((x) => ((x['BackdropImageTags'] as List?) ?? const []).isNotEmpty).take(6).toList();
        loading = false;
        slow = false;
      });
      _discover();
      _rest(views);
    } catch (e) {
      _slowT?.cancel();
      if (!mounted) return;
      if (silent && libs.isNotEmpty) return; // sessiz yenileme başarısız: eldekini göstermeye devam
      setState(() {
        loading = false;
        slow = false;
        err = 'Ana sayfa yüklenemedi.\n$e';
      });
    }
  }

  /// 2) Sonra yavaş olabilenler: yeni eklenenler, koleksiyonlar, stüdyolar. Ana sayfayı bekletmez.
  Future<void> _rest(List<J> views) async {
    final u = api.uid;
    final latF = Future.wait(views.map((v) => safe(api.items('/Users/$u/Items/Latest?ParentId=${v['Id']}&Limit=16&Fields=$kFields'))));
    final colsF = safe(api.items('/Users/$u/Items?IncludeItemTypes=BoxSet&Recursive=true&SortBy=SortName&Limit=30&Fields=$kFields'));
    final stF = safe(api.items('/Users/$u/Items?IncludeItemTypes=Movie,Series&Recursive=true&SortBy=DateCreated&SortOrder=Descending&Limit=300&Fields=Studios'));
    final latest = await latF;
    if (!mounted) return;
    setState(() => lat = latest);
    final c = await colsF;
    if (!mounted) return;
    setState(() => cols = c);
    final recent = await stF;
    // stüdyolar: kütüphanede en çok içeriği olanlar; görselleri sadece bu 10 stüdyo için istenir
    final m = <String, _Studio>{};
    for (final x in recent) {
      for (final s in (x['Studios'] as List? ?? const [])) {
        final id = '${s['Id']}';
        (m[id] ??= _Studio(id, '${s['Name']}')).n++;
      }
    }
    final st = (m.values.where((s) => s.n >= 2).toList()..sort((a, b) => b.n.compareTo(a.n))).take(10).toList();
    if (st.isNotEmpty) {
      final imgs = await safe(api.items('/Users/$u/Items?Ids=${st.map((s) => s.id).join(',')}&EnableImageTypes=Primary,Thumb'));
      final tags = {for (final s in imgs) '${s['Id']}': (s['ImageTags'] as Map?) ?? const {}};
      for (final s in st) {
        final t = tags[s.id];
        if (t == null) continue;
        if (t['Primary'] != null) {
          s.img = api.image(s.id, 'Primary', tag: t['Primary'], w: 400);
        } else if (t['Thumb'] != null) {
          s.img = api.image(s.id, 'Thumb', tag: t['Thumb'], w: 400);
        }
      }
    }
    if (mounted) setState(() => studios = st);
  }

  /// Keşif sıraları ana sayfayı bekletmeden ayrıca gelir.
  Future<void> _discover() async {
    final r = await Future.wait<List<J>>([
      Discover.I.top10().catchError((_) => <J>[]),
      Discover.I.upcoming().catchError((_) => <J>[]),
    ]);
    if (mounted) {
      setState(() {
        top = r[0];
        soon = r[1];
      });
    }
  }

  static IconData _libIcon(Object? t) => t == 'movies'
      ? Icons.movie_outlined
      : t == 'tvshows'
          ? Icons.live_tv_outlined
          : Icons.folder_outlined;

  Widget _pill(String label, IconData? icon, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 17, color: const Color(0xFFF5F5F7)), const SizedBox(width: 7)],
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    final content = loading
          ? (slow
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const CupertinoActivityIndicator(radius: 14),
                      const SizedBox(height: 18),
                      const Text('Sunucu yavaş yanıt veriyor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('Bekleyebilir, yeniden deneyebilir ya da indirdiklerini izleyebilirsin.',
                          textAlign: TextAlign.center, style: TextStyle(color: Color(0x99F5F5F7), height: 1.4)),
                      const SizedBox(height: 18),
                      PillButton('Yeniden dene', onTap: () {
                        api.resetConnections();
                        load();
                      }),
                      const SizedBox(height: 10),
                      Pressable(
                        onTap: () => tabBus.value = 3,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('İndirilenlere git', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  ),
                )
              : const Loading())
          : err.isNotEmpty
              ? ErrorView(err, retry: load)
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.depth == 0) scrollY.value = n.metrics.pixels;
                    return false;
                  },
                  child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Stack(children: [
                        HeroCarousel(feat),
                      ]),
                    ),
                    CupertinoSliverRefreshControl(onRefresh: () => load(silent: true)),
                    // kütüphane kısayolları: cam kapsüller
                    if (libs.isNotEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 56,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(pad, 6, pad, 6),
                            children: [
                              for (final v in libs)
                                _pill('${v['Name']}', _libIcon(v['CollectionType']),
                                    () => openLibrary(context, '${v['Name']}', '&ParentId=${v['Id']}')),
                            ],
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(child: Shelf('İzlemeye devam et', res, resume: true)),
                    SliverToBoxAdapter(child: Top10Shelf(top)),
                    SliverToBoxAdapter(child: UpcomingShelf(soon)),
                    SliverToBoxAdapter(child: Shelf('Listem', fav, more: () => tabBus.value = 2)),
                    for (var i = 0; i < libs.length && i < lat.length; i++)
                      SliverToBoxAdapter(
                          child: Shelf('Yeni: ${libs[i]['Name']}', lat[i],
                              more: () => openLibrary(context, '${libs[i]['Name']}', '&ParentId=${libs[i]['Id']}'))),
                    SliverToBoxAdapter(child: Shelf('Koleksiyonlar', cols)),
                    if (studios.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(pad + 4, 22, pad, 10),
                            child: const Text('Stüdyolar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
                          ),
                          SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.symmetric(horizontal: pad),
                              children: [
                                for (final st in studios)
                                  _pill(st.name, null, () => openLibrary(context, st.name, '&StudioIds=${st.id}')),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 120)),
                  ],
                ),
                );
    final safeTop = MediaQuery.paddingOf(context).top;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(children: [
        Positioned.fill(child: content),
        // Logo ve profil kayan içeriğin dışında: sayfa kayarken/esnerken de dokunuş kaçmaz.
        if (!wideLayout(context) && !loading && err.isEmpty)
          Positioned(
            left: pad + 4,
            right: pad - 3,
            top: safeTop + 7,
            child: Row(children: [
              ValueListenableBuilder<double>(
                valueListenable: scrollY,
                builder: (_, y, child) => Opacity(opacity: (1 - y / 140).clamp(0, 1).toDouble(), child: child),
                child: const IgnorePointer(child: Logo(size: 21)),
              ),
              const Spacer(),
              Semantics(
                button: true,
                label: 'Profil',
                child: Pressable(
                  haptic: true,
                  onTap: () => tabBus.value = 4,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Glass(
                        radius: 19,
                        child: SizedBox(
                          width: 38,
                          height: 38,
                          child: Center(
                            child: Text(api.name.isEmpty ? '?' : api.name[0].toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}
