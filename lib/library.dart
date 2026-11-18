import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'scan.dart';
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

  Future<void> _sortSheet() async {
    HapticFeedback.selectionClick();
    final v = await showCupertinoModalPopup<String>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: const Text('Sırala'),
        actions: [
          for (final e in sorts.entries)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(c, e.key),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(e.value, style: TextStyle(fontWeight: e.key == sort ? FontWeight.w600 : FontWeight.w400)),
                if (e.key == sort) ...[const SizedBox(width: 8), const Icon(CupertinoIcons.checkmark_alt, size: 18)],
              ]),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
      ),
    );
    if (v != null && v != sort) {
      sort = v;
      load(true);
    }
  }

  Future<void> _scan() async {
    final id = RegExp(r'ParentId=([0-9a-f]+)').firstMatch(widget.extra)!.group(1)!;
    final ok = await Scanner.I.scanOne(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Tarama başladı. Yeni dosyalar birkaç dakika içinde görünür.' : 'Tarama başlatılamadı.')));
    if (ok) {
      Future.delayed(const Duration(seconds: 25), () {
        if (mounted) load(true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = hPad(context);
    final cols = w > 1000 ? 4 : (w > 700 ? 3 : 2);
    final canScan = Api.I.admin && RegExp(r'ParentId=([0-9a-f]+)').hasMatch(widget.extra);
    final seg = type.isEmpty ? 0 : (type == 'Movie' ? 1 : 2);
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        controller: sc,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(widget.title, style: const TextStyle(color: Color(0xFFF5F5F7))),
            backgroundColor: const Color(0xCC0B0B0D),
            border: null,
            automaticallyImplyLeading: !widget.root,
            previousPageTitle: widget.root ? null : 'Geri',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (canScan) ...[
                GlassIcon(Icons.manage_search_rounded, size: 34, tooltip: 'Bu kütüphaneyi tara', onTap: _scan),
                const SizedBox(width: 8),
              ],
              GlassIcon(CupertinoIcons.arrow_up_arrow_down, size: 34, tooltip: 'Sırala: ${sorts[sort]}', onTap: _sortSheet),
            ]),
          ),
          CupertinoSliverRefreshControl(onRefresh: () => load(true)),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, 4, pad, 6),
              child: Row(children: [
                Expanded(
                  child: CupertinoSlidingSegmentedControl<int>(
                    groupValue: seg,
                    backgroundColor: const Color(0x1FFFFFFF),
                    thumbColor: const Color(0xFF636366),
                    children: const {
                      0: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Hepsi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF5F5F7)))),
                      1: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Film', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF5F5F7)))),
                      2: Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Text('Dizi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF5F5F7)))),
                    },
                    onValueChanged: (v) {
                      if (v == null) return;
                      HapticFeedback.selectionClick();
                      type = const ['', 'Movie', 'Series'][v];
                      load(true);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  selected: unplayed,
                  label: 'İzlemediklerim',
                  child: Pressable(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      unplayed = !unplayed;
                      load(true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: unplayed ? kBlue : const Color(0x1FFFFFFF),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(unplayed ? CupertinoIcons.eye_slash_fill : CupertinoIcons.eye_slash,
                            size: 15, color: unplayed ? kInk : const Color(0xFFF5F5F7)),
                        const SizedBox(width: 6),
                        Text('İzlemediklerim',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: unplayed ? kInk : const Color(0xFFF5F5F7))),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (!first && err.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad + 2, 6, pad, 10),
                child: Text(total > 0 ? '$total içerik · ${sorts[sort]}' : 'Sonuç yok.',
                    style: const TextStyle(color: Color(0x8CF5F5F7), fontSize: 13)),
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
            child: SizedBox(height: widget.root ? 130 : 60, child: loading && !first ? const Center(child: CupertinoActivityIndicator()) : null),
          ),
        ],
      ),
    );
  }
}
