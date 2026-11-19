import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'nav.dart';
import 'person.dart';
import 'seerr.dart';
import 'util.dart';
import 'widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final api = Api.I;
  final q = TextEditingController();
  Timer? deb;
  int tok = 0;
  bool busy = false;
  List<String> genres = [];
  List<J> results = [], people = [], seerr = [];

  @override
  void initState() {
    super.initState();
    api
        .items('/Genres?UserId=${api.uid}&IncludeItemTypes=Movie,Series&Recursive=true&SortBy=SortName')
        .then((g) {
      if (mounted) setState(() => genres = g.map((e) => '${e['Name']}').toList());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    deb?.cancel();
    q.dispose();
    super.dispose();
  }

  void onChange(String v) {
    deb?.cancel();
    deb = Timer(const Duration(milliseconds: 350), () => run(v.trim()));
  }

  Future<void> run(String v) async {
    final my = ++tok;
    if (v.isEmpty) {
      setState(() {
        results = [];
        people = [];
        seerr = [];
        busy = false;
      });
      return;
    }
    _seerr(v, my);
    setState(() => busy = true);
    final e = Uri.encodeQueryComponent(v);
    try {
      final r = await Future.wait<List<J>>([
        api.items('/Users/${api.uid}/Items?searchTerm=$e&Recursive=true&IncludeItemTypes=Movie,Series,Episode&Limit=48&Fields=$kFields'),
        api.items('/Persons?searchTerm=$e&Limit=10&UserId=${api.uid}').catchError((_) => <J>[]),
      ]);
      if (my != tok || !mounted) return;
      setState(() {
        results = r[0];
        people = r[1];
        busy = false;
      });
    } catch (_) {
      if (my == tok && mounted) setState(() => busy = false);
    }
  }

  /// Sunucuda olmayanlar: Seerr'de ara (Jellyfin aramasını beklemeden, ayrı)
  Future<void> _seerr(String v, int my) async {
    if (!Seerr.I.on) return;
    try {
      final r = await Seerr.I.search(v);
      if (my != tok || !mounted) return;
      setState(() => seerr = r.where((x) => ((x['mediaInfo'] as Map?)?['status'] as num?) != 5).take(12).toList());
    } catch (_) {
      if (my == tok && mounted) setState(() => seerr = []);
    }
  }

  int _hue(String n) => n.codeUnits.fold(7, (a, c) => (a * 31 + c) % 360);

  static const _muted = Color(0x8CF5F5F7);

  Widget _head(String t, double pad, {String? side}) => Padding(
        padding: EdgeInsets.fromLTRB(pad + 4, 22, pad + 4, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4))),
          if (side != null) Text(side, style: const TextStyle(fontSize: 12, color: _muted)),
        ]),
      );

  String _meta(J x) {
    final t = x['Type'];
    if (t == 'Episode') {
      return '${x['SeriesName'] ?? ''} · S${x['ParentIndexNumber'] ?? '?'} B${x['IndexNumber'] ?? '?'}';
    }
    return [t == 'Series' ? 'Dizi' : 'Film', if (x['ProductionYear'] != null) '${x['ProductionYear']}'].join(' · ');
  }

  Widget _found(BuildContext c, J x, double cw) => SizedBox(
        width: cw,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          WideCard(x, width: cw),
          const SizedBox(height: 7),
          Text('${x['Name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(_meta(x), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _muted)),
        ]),
      );

  Widget _person(BuildContext c, J p) {
    final tag = p['PrimaryImageTag'];
    final n = '${p['Name'] ?? ''}';
    return Pressable(
      onTap: () => Navigator.of(c).push(CupertinoPageRoute(builder: (_) => PersonScreen(id: '${p['Id']}', name: n))),
      child: SizedBox(
        width: 76,
        child: Column(children: [
          ClipOval(
            child: Container(
              width: 64,
              height: 64,
              color: kCard,
              alignment: Alignment.center,
              child: tag != null
                  ? netImg(api.image('${p['Id']}', 'Primary', tag: '$tag', w: 200))
                  : Text(n.isEmpty ? '?' : n[0].toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 6),
          Text(n, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, height: 1.3)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = hPad(context);
    final cols = w > 1000 ? 4 : (w > 700 ? 3 : 2);
    final cw = w > 700 ? cardWidth(context) : w * .43;
    final searching = q.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: kBg,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            const CupertinoSliverNavigationBar(
              largeTitle: Text('Ara', style: TextStyle(color: Color(0xFFF5F5F7))),
              backgroundColor: Color(0xCC0B0B0D),
              border: null,
              automaticallyImplyLeading: false,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.only(left: 12, right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(26),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.search_rounded, size: 20, color: _muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: q,
                        onChanged: (v) {
                          setState(() {});
                          onChange(v);
                        },
                        textInputAction: TextInputAction.search,
                        autocorrect: false,
                        cursorColor: kAccent,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          hintText: 'Film, dizi, oyuncu',
                          hintStyle: TextStyle(color: _muted, fontWeight: FontWeight.w400),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (searching)
                      Semantics(
                        button: true,
                        label: 'Temizle',
                        child: Pressable(
                          onTap: () {
                            q.clear();
                            run('');
                            setState(() {});
                          },
                          child: Container(
                            width: 20,
                            height: 20,
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0x59F5F5F7), shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, size: 14, color: kBg),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            if (!searching) ...[
              if (genres.isNotEmpty) SliverToBoxAdapter(child: _head('Türlere göz at', pad)),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 16 / 9),
                  delegate: SliverChildBuilderDelegate((c, i) {
                    final g = genres[i], h = _hue(g).toDouble();
                    return Pressable(
                      onTap: () => openLibrary(c, g, '&Genres=${Uri.encodeQueryComponent(g)}'),
                      child: Container(
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              HSLColor.fromAHSL(1, h, .32, .30).toColor(),
                              HSLColor.fromAHSL(1, (h + 30) % 360, .30, .10).toColor(),
                            ],
                          ),
                        ),
                        child: Text(g, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    );
                  }, childCount: genres.length),
                ),
              ),
            ] else ...[
              if (busy && results.isEmpty && people.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: CupertinoActivityIndicator(radius: 13))),
              if (!busy && results.isEmpty && people.isEmpty && seerr.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 120),
                    child: Center(child: Text('Sonuç bulunamadı.', style: TextStyle(color: _muted, fontSize: 15))),
                  ),
                ),
              if (results.isNotEmpty) ...[
                SliverToBoxAdapter(child: _head('Sunucunda', pad, side: '${results.length} sonuç')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: cw * 9 / 16 + 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(horizontal: pad),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (c, i) => _found(c, results[i], cw),
                    ),
                  ),
                ),
              ],
              if (people.isNotEmpty) ...[
                SliverToBoxAdapter(child: _head('Kişiler', pad)),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(horizontal: pad),
                      itemCount: people.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (c, i) => _person(c, people[i]),
                    ),
                  ),
                ),
              ],
              if (seerr.isNotEmpty) ...[
                SliverToBoxAdapter(child: _head('Sunucunda yok', pad, side: 'Seerr')),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: pad + 4),
                  sliver: SliverList.builder(
                    itemCount: seerr.length,
                    itemBuilder: (_, i) => SeerrResultTile(seerr[i], key: ValueKey('${seerr[i]['mediaType']}${seerr[i]['id']}')),
                  ),
                ),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 130)),
          ],
        ),
      ),
    );
  }
}
