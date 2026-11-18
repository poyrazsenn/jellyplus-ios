import 'package:flutter/material.dart';

import 'api.dart';
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = 'Ana sayfa yüklenemedi.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    final tw = cardWidth(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: loading
          ? const Loading()
          : err.isNotEmpty
              ? ErrorView(err, retry: load)
              : RefreshIndicator(
                  onRefresh: () => load(silent: true),
                  child: CustomScrollView(slivers: [
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
                    // kütüphaneler + stüdyolar (Disney/Pixar/Marvel kutuları gibi)
                    if (libs.isNotEmpty || studios.isNotEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: tw * 9 / 16 + 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.fromLTRB(pad, 14, pad, 20),
                            children: [
                              for (final v in libs)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: BrandTile(
                                    title: '${v['Name']}',
                                    icon: v['CollectionType'] == 'movies'
                                        ? Icons.movie_outlined
                                        : v['CollectionType'] == 'tvshows'
                                            ? Icons.tv
                                            : Icons.folder_outlined,
                                    width: tw,
                                    onTap: () => openLibrary(context, '${v['Name']}', '&ParentId=${v['Id']}'),
                                  ),
                                ),
                              for (final s in studios)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: BrandTile(
                                    title: s.name,
                                    image: s.img,
                                    width: tw,
                                    onTap: () => openLibrary(context, s.name, '&StudioIds=${s.id}'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(child: Shelf('İzlemeye devam et', res, resume: true)),
                    SliverToBoxAdapter(child: Shelf('Listem', fav)),
                    for (var i = 0; i < libs.length && i < lat.length; i++)
                      SliverToBoxAdapter(child: Shelf('Yeni eklenenler: ${libs[i]['Name']}', lat[i])),
                    SliverToBoxAdapter(child: Shelf('Koleksiyonlar', cols)),
                    const SliverToBoxAdapter(child: SizedBox(height: 30)),
                  ]),
                ),
    );
  }
}
