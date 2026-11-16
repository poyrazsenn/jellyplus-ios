import 'dart:async';

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

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = hPad(context);
    final cols = w > 1000 ? 4 : (w > 700 ? 3 : 2);
    final searching = q.text.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Container(
            color: const Color(0xFF4B4E5A),
            padding: EdgeInsets.symmetric(horizontal: pad - 4),
            child: TextField(
              controller: q,
              onChanged: (v) {
                setState(() {});
                onChange(v);
              },
              textInputAction: TextInputAction.search,
              autocorrect: false,
              style: const TextStyle(fontSize: 20),
              decoration: InputDecoration(
                hintText: 'Film, dizi, oyuncu ara',
                hintStyle: const TextStyle(color: Color(0xFFC9CAD1)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
                suffixIcon: searching
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          q.clear();
                          run('');
                          setState(() {});
                        })
                    : const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                if (!searching) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 18, pad, 10),
                      child: const Text('Keşfet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 16 / 9),
                      delegate: SliverChildBuilderDelegate((c, i) {
                        final g = genres[i], h = _hue(g).toDouble();
                        return GestureDetector(
                          onTap: () => openLibrary(c, g, '&Genres=${Uri.encodeQueryComponent(g)}'),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withAlpha(26), width: 2),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  HSLColor.fromAHSL(1, h, .58, .30).toColor(),
                                  HSLColor.fromAHSL(1, (h + 50) % 360, .55, .13).toColor(),
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
                  if (people.isNotEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 54,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
                          children: [
                            for (final p in people)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ActionChip(
                                  avatar: const Icon(Icons.person, size: 18),
                                  label: Text('${p['Name']}'),
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => PersonScreen(id: '${p['Id']}', name: '${p['Name']}'))),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (busy && results.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: Loading()),
                  if (!busy && results.isEmpty && seerr.isEmpty)
                    const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('Sonuç bulunamadı.', style: TextStyle(color: kMuted)))),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 14, pad, 30),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 16 / 9),
                      delegate: SliverChildBuilderDelegate(
                        (c, i) => LayoutBuilder(builder: (c, cs) => WideCard(results[i], width: cs.maxWidth)),
                        childCount: results.length,
                      ),
                    ),
                  ),
                  if (seerr.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(pad, 4, pad, 6),
                        child: const Text('Sunucunda yok — Seerr\'den iste',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 30),
                      sliver: SliverList.builder(
                        itemCount: seerr.length,
                        itemBuilder: (_, i) => SeerrResultTile(seerr[i], key: ValueKey('${seerr[i]['mediaType']}${seerr[i]['id']}')),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
