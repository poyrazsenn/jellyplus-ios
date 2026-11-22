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
    try {
      final r = await Future.wait<List<J>>([
        safe(api.items('/Users/$u/Items/Resume?Limit=12&MediaTypes=Video&Fields=$kFields')),
        api.items('/Users/$u/Views'),
        safe(api.items('/Users/$u/Items?Filters=IsFavorite&Recursive=true&IncludeItemTypes=Movie,Series&Limit=30&Fields=$kFields')),
        silent && feat.isNotEmpty
            ? Future.value(feat)
            : safe(api.items('/Users/$u/Items?IncludeItemTypes=Movie,Series&Recursive=true&SortBy=Random&Limit=24&ImageTypes=Backdrop&Fields=$kFields')),
        safe(api.items('/Users/$u/Items?IncludeItemTypes=BoxSet&Recursive=true&SortBy=SortName&Limit=30&Fields=$kFields')),
        safe(api.items('/Users/$u/Items?IncludeItemTypes=Movie,Series&Recursive=true&SortBy=DateCreated&SortOrder=Descending&Limit=300&Fields=Studios')),
        safe(api.items('/Studios?userId=$u&Recursive=true&EnableImages=true&EnableImageTypes=Primary,Thumb&Limit=2000')),
      ]);
      final views = r[1]
          .where((v) => !['music', 'books', 'photos', 'playlists', 'livetv', 'boxsets', 'musicvideos'].contains(v['CollectionType']))
          .toList();
      final latest = await Future.wait(views.map((v) => safe(api.items('/Users/$u/Items/Latest?ParentId=${v['Id']}&Limit=16&Fields=$kFields'))));

      // stüdyolar: kütüphanede en çok içeriği olanlar
      final m = <String, _Studio>{};
      for (final x in r[5]) {
        for (final s in (x['Studios'] as List? ?? const [])) {
          final id = '${s['Id']}';
          (m[id] ??= _Studio(id, '${s['Name']}')).n++;
        }
      }
      final tags = {for (final s in r[6]) '${s['Id']}': (s['ImageTags'] as Map?) ?? const {}};
      final st = m.values.where((s) => s.n >= 2).toList()..sort((a, b) => b.n.compareTo(a.n));
      for (final s in st) {
        final t = tags[s.id];
        if (t == null) continue;
        if (t['Primary'] != null) {
          s.img = api.image(s.id, 'Primary', tag: t['Primary'], w: 400);
        } else if (t['Thumb'] != null) {
          s.img = api.image(s.id, 'Thumb', tag: t['Thumb'], w: 400);
        }
      }

      if (!mounted) return;
      setState(() {
        res = r[0];
        libs = views;
        fav = r[2];
        feat = r[3].where((x) => ((x['BackdropImageTags'] as List?) ?? const []).isNotEmpty).take(6).toList();
        cols = r[4];
        lat = latest;
        studios = st.take(10).toList();
        loading = false;
      });
      _discover();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = 'Ana sayfa yüklenemedi.\n$e';
      });
    }
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: loading
          ? const Loading()
          : err.isNotEmpty
              ? ErrorView(err, retry: load)
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Stack(children: [
                        HeroCarousel(feat),
                        Positioned(
                          left: pad + 4,
                          right: pad,
                          top: MediaQuery.paddingOf(context).top + 10,
                          child: Row(children: [
                            const Logo(size: 21),
                            const Spacer(),
                            Semantics(
                              button: true,
                              label: 'Profil',
                              child: Pressable(
                                onTap: () => tabBus.value = 4,
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
                          ]),
                        ),
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
  }
}
