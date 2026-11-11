import 'package:flutter/material.dart';

import 'api.dart';
import 'util.dart';
import 'widgets.dart';

/// Kütüphane / koleksiyon / stüdyo / tür / kişi / Listem sayfası — filtre ve sıralamalı ızgara.
class LibraryScreen extends StatefulWidget {
  final String title;
  final String extra; // ör. &ParentId=..., &StudioIds=..., &IsFavorite=true
  final bool root; // sekme kökü (geri düğmesi yok)
  const LibraryScreen({super.key, required this.title, required this.extra, this.root = false});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final api = Api.I;
  final sc = ScrollController();
  static const sorts = {
    'SortName|Ascending': 'Ad (A-Z)',
    'DateCreated|Descending': 'Yeni eklenen',
    'PremiereDate|Descending': 'Yıl (yeni)',
    'CommunityRating|Descending': 'Puan',
  };
  String sort = 'SortName|Ascending', type = '';
  bool unplayed = false, loading = false, first = true;
  List<J> list = [];
  int total = 0, tok = 0;
  String err = '';

  @override
  void initState() {
    super.initState();
    if (widget.extra.contains('IsFavorite')) sort = 'DateCreated|Descending';
    WidgetsBinding.instance.addPostFrameCallback((_) => load(true));
    sc.addListener(() {
      if (sc.position.pixels > sc.position.maxScrollExtent - 600) load(false);
    });
    refreshBus.addListener(_refresh);
  }

  void _refresh() => load(true);

  @override
  void dispose() {
    refreshBus.removeListener(_refresh);
    sc.dispose();
    super.dispose();
  }

  Future<void> load(bool reset) async {
    if (!reset && (loading || list.length >= total)) return;
    final my = ++tok;
    setState(() {
      loading = true;
      if (reset) err = '';
    });
    final s = sort.split('|');
    final start = reset ? 0 : list.length;
    final p = '/Users/${api.uid}/Items?Recursive=true&IncludeItemTypes=${type.isEmpty ? 'Movie,Series' : type}'
        '${widget.extra}&SortBy=${s[0]}&SortOrder=${s[1]}${unplayed ? '&Filters=IsUnplayed' : ''}'
        '&StartIndex=$start&Limit=60&Fields=$kFields&EnableTotalRecordCount=true';
    try {
      final r = await api.get(p);
      if (my != tok || !mounted) return;
      final items = ((r?['Items'] as List?) ?? const []).map((e) => J.from(e as Map)).toList();
      setState(() {
        list = reset ? items : [...list, ...items];
        total = (r?['TotalRecordCount'] as num?)?.toInt() ?? list.length;
        loading = false;
        first = false;
      });
    } catch (e) {
      if (my != tok || !mounted) return;
      setState(() {
        loading = false;
        first = false;
        err = 'Yüklenemedi.\n$e';
      });
    }
  }

  Widget chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: sel, onSelected: (_) => onTap()),
      );

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = hPad(context);
    final cols = w > 1000 ? 4 : (w > 700 ? 3 : 2);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        automaticallyImplyLeading: !widget.root,
      ),
      body: RefreshIndicator(
        onRefresh: () => load(true),
        child: CustomScrollView(controller: sc, physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: pad, vertical: 6), children: [
                PopupMenuButton<String>(
                  initialValue: sort,
                  onSelected: (v) {
                    sort = v;
                    load(true);
                  },
                  itemBuilder: (_) => [for (final e in sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.sort, size: 18),
                      const SizedBox(width: 6),
                      Text(sorts[sort]!),
                    ]),
                  ),
                ),
                chip('Hepsi', type.isEmpty, () {
                  type = '';
                  load(true);
                }),
                chip('Film', type == 'Movie', () {
                  type = 'Movie';
                  load(true);
                }),
                chip('Dizi', type == 'Series', () {
                  type = 'Series';
                  load(true);
                }),
                chip('İzlemediklerim', unplayed, () {
                  unplayed = !unplayed;
                  load(true);
                }),
              ]),
            ),
          ),
          if (!first && err.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
                child: Text(total > 0 ? '$total sonuç' : 'Sonuç yok.', style: const TextStyle(color: kMuted, fontSize: 13)),
              ),
            ),
          if (err.isNotEmpty) SliverFillRemaining(hasScrollBody: false, child: ErrorView(err, retry: () => load(true))),
          if (first) const SliverFillRemaining(hasScrollBody: false, child: Loading()),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 16 / 9),
              delegate: SliverChildBuilderDelegate(
                (c, i) => LayoutBuilder(builder: (c, cs) => WideCard(list[i], width: cs.maxWidth)),
                childCount: list.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: 60, child: loading && !first ? const Loading() : null),
          ),
        ]),
      ),
    );
  }
}
