import 'package:flutter/material.dart';

import 'api.dart';
import 'util.dart';
import 'widgets.dart';

const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

DateTime? _date(dynamic v) {
  final s = '${v ?? ''}';
  if (s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  // Jellyfin tarihi bilmediğinde 0001 yılı döndürebilir
  return d == null || d.year < 1800 ? null : d;
}

String _trDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

int _age(DateTime from, DateTime to) {
  var a = to.year - from.year;
  if (to.month < from.month || (to.month == from.month && to.day < from.day)) a--;
  return a;
}

/// Oyuncu / yönetmen sayfası: fotoğraf, biyografi, doğum-ölüm, arşivdeki işleri.
class PersonScreen extends StatefulWidget {
  final String id;
  final String name;
  const PersonScreen({super.key, required this.id, this.name = ''});
  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  J? p;
  List<J>? works;
  String err = '';
  bool bioOpen = false;

  Api get api => Api.I;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    setState(() => err = '');
    try {
      final r = await Future.wait([
        api.item(widget.id),
        api.items('/Users/${api.uid}/Items?PersonIds=${widget.id}&Recursive=true'
            '&IncludeItemTypes=Movie,Series&SortBy=PremiereDate,ProductionYear,SortName&SortOrder=Descending&Fields=$kFields'),
      ]);
      if (!mounted) return;
      setState(() {
        p = r[0] as J;
        works = r[1] as List<J>;
      });
    } catch (e) {
      if (mounted) setState(() => err = 'Bilgiler alınamadı.\n$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = p;
    final pad = hPad(context);
    final w = MediaQuery.sizeOf(context).width;
    final cols = w > 1000 ? 4 : (w > 700 ? 3 : 2);
    return Scaffold(
      appBar: AppBar(title: Text(x?['Name'] ?? widget.name, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: err.isNotEmpty
          ? ErrorView(err, retry: load)
          : x == null
              ? const Loading()
              : CustomScrollView(slivers: [
                  SliverToBoxAdapter(child: _head(x, pad)),
                  if ((works ?? const []).isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(pad, 22, pad, 10),
                        child: Text('Arşivindekiler (${works!.length})',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 40),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: 16 / 9),
                      delegate: SliverChildBuilderDelegate(
                        (c, i) => LayoutBuilder(builder: (c, cs) => WideCard(works![i], width: cs.maxWidth)),
                        childCount: works?.length ?? 0,
                      ),
                    ),
                  ),
                ]),
    );
  }

  Widget _head(J x, double pad) {
    final tag = (x['ImageTags'] as Map?)?['Primary'];
    final img = tag != null ? api.image('${x['Id']}', 'Primary', tag: '$tag', w: 400) : null;
    final born = _date(x['PremiereDate']), died = _date(x['EndDate']);
    final place = ((x['ProductionLocations'] as List?) ?? const []).map((e) => '$e').where((e) => e.isNotEmpty).join(', ');
    final bio = '${x['Overview'] ?? ''}'.trim();
    final facts = <List<String>>[
      if (born != null)
        ['Doğum', '${_trDate(born)}${died == null ? ' (${_age(born, DateTime.now())} yaşında)' : ''}'],
      if (died != null) ['Ölüm', '${_trDate(died)}${born != null ? ' (${_age(born, died)} yaşında)' : ''}'],
      if (place.isNotEmpty) ['Doğum yeri', place],
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 120,
              height: 170,
              color: kCard,
              child: img == null ? const Icon(Icons.person, size: 56, color: kMuted) : netImg(img, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x['Name'] ?? ''}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              if (facts.isEmpty)
                const Text('Jellyfin\'de doğum bilgisi yok.', style: TextStyle(color: kMuted, fontSize: 13)),
              for (final f in facts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f[0], style: const TextStyle(color: kMuted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(f[1], style: const TextStyle(fontSize: 14)),
                  ]),
                ),
            ]),
          ),
        ]),
        if (bio.isNotEmpty) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: () => setState(() => bioOpen = !bioOpen),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bio,
                  maxLines: bioOpen ? null : 5,
                  overflow: bioOpen ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFFCFD5EA))),
              const SizedBox(height: 4),
              Text(bioOpen ? 'Daha az' : 'Devamını oku',
                  style: const TextStyle(color: kBlue, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ],
      ]),
    );
  }
}
