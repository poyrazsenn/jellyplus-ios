import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'downloads.dart';
import 'nav.dart';
import 'util.dart';
import 'widgets.dart';

/// Kalite seçtirip indirmeyi kuyruğa ekler.
Future<void> askDownload(BuildContext context, List<J> items, {String? title}) async {
  if (items.isEmpty) return;
  final dl = Downloads.I;
  final orig = dl.sizeOf(items, 'orig'), small = dl.sizeOf(items, 'small');
  final q = await showCupertinoModalPopup<String>(
    context: context,
    builder: (c) {
      Widget opt(String k, String t, String sub) => CupertinoActionSheetAction(
            isDefaultAction: dl.defaultQuality == k,
            onPressed: () => Navigator.pop(c, k),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 12, color: Color(0x99F5F5F7), fontWeight: FontWeight.w400)),
            ]),
          );
      return CupertinoActionSheet(
        title: Text(title ?? (items.length == 1 ? 'İndir' : '${items.length} bölümü indir')),
        message: const Text('İndirme telefon kilitliyken ve uygulama kapalıyken de sürer.'),
        actions: [
          opt('orig', 'Orijinal kalite', '${orig > 0 ? '${fmtBytes(orig)} · ' : ''}Kaldığı yerden devam eder'),
          opt('small', 'Küçük (720p)', '${small > 0 ? 'yaklaşık ${fmtBytes(small)} · ' : ''}Yer kazandırır'),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
      );
    },
  );
  if (q == null) return;
  dl.add(items, q);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(items.length == 1 ? 'İndirme sıraya eklendi.' : '${items.length} bölüm sıraya eklendi.'),
      duration: const Duration(seconds: 2),
    ));
  }
}

/// Detay sayfasındaki indirme düğmesinin simgesi / yazısı.
({IconData icon, String label, double? frac}) dlButton(String id) {
  final d = Downloads.I.of(id);
  if (d == null) return (icon: Icons.download_outlined, label: 'İndir', frac: null);
  switch (d.state) {
    case DlState.done:
      return (icon: Icons.download_done, label: 'İndirildi', frac: null);
    case DlState.running:
      return (icon: Icons.downloading, label: '%${(d.frac * 100).round()}', frac: d.frac);
    case DlState.queued:
      return (icon: Icons.downloading, label: 'Sırada', frac: 0);
    case DlState.paused:
      return (icon: Icons.pause_circle_outline, label: 'Duraklatıldı', frac: null);
    default:
      return (icon: Icons.error_outline, label: 'Hata', frac: null);
  }
}

/// İndirilmiş/inen bir öğeye dokununca: oynat, duraklat, sil…
Future<void> dlActions(BuildContext context, Dl d) async {
  final dl = Downloads.I;
  final a = await showCupertinoModalPopup<String>(
    context: context,
    builder: (c) => CupertinoActionSheet(
      title: Text(d.isEpisode ? '${d.series} · S${d.season} B${d.index}' : d.name),
      message: Text(_status(d)),
      actions: [
        if (d.state == DlState.done)
          CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(c, 'play'), child: const Text('Oynat')),
        if (d.state == DlState.running || d.state == DlState.queued)
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(c, 'pause'), child: const Text('Duraklat')),
        if (d.state == DlState.paused || d.state == DlState.failed)
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(c, 'resume'), child: const Text('Devam et')),
        CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(c, 'del'),
          child: Text(d.state == DlState.done ? 'İndirmeyi sil' : 'İptal et ve sil'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
    ),
  );
  switch (a) {
    case 'play':
      if (context.mounted) await openPlayer(context, d.item);
      break;
    case 'pause':
      dl.pause(d);
      break;
    case 'resume':
      dl.resume(d);
      break;
    case 'del':
      await dl.remove(d);
      break;
  }
}

String _status(Dl d) {
  final q = d.quality == 'small' ? 'Küçük' : 'Orijinal';
  switch (d.state) {
    case DlState.done:
      final run = ((d.item['RunTimeTicks'] as num?) ?? 0);
      final left = run > 0 && d.posTicks > 0 ? ' · ${rt(run - d.posTicks)} kaldı' : '';
      return '${fmtBytes(d.got)} · $q${d.watched ? ' · İzlendi' : left}';
    case DlState.running:
      return d.total > 0
          ? 'İndiriliyor %${(d.frac * 100).round()} · ${fmtBytes(d.got)} / ${d.quality == 'small' ? '~' : ''}${fmtBytes(d.total)}'
          : 'İndiriliyor · ${fmtBytes(d.got)}';
    case DlState.queued:
      return 'Sırada · $q';
    case DlState.paused:
      return 'Duraklatıldı · ${fmtBytes(d.got)}';
    default:
      return d.err.isEmpty ? 'İndirilemedi' : d.err;
  }
}

const _muted = Color(0x8CF5F5F7);

Widget _sec(String t, double pad) => Padding(
      padding: EdgeInsets.fromLTRB(pad + 4, 22, pad, 8),
      child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: .5, color: _muted)),
    );

Widget _thumb(String? path, {double w = 112, double h = 63, double r = 10, double prog = 0}) => ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(fit: StackFit.expand, children: [
          Container(color: kCard),
          if (path != null) Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          if (prog > 0)
            Align(
              alignment: Alignment.bottomLeft,
              child: FractionallySizedBox(widthFactor: prog, child: Container(height: 3, color: kBlue)),
            ),
        ]),
      ),
    );

Widget _circle(IconData i, String label, VoidCallback f, {bool white = false}) => Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          f();
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: white ? kBlue : Colors.white.withAlpha(20),
            border: white ? null : Border.all(color: Colors.white.withAlpha(46)),
          ),
          child: Icon(i, size: 18, color: white ? kInk : const Color(0xFFF5F5F7)),
        ),
      ),
    );

/// A · Cam İndirilenler: büyük başlık, depolama kartı, İNDİRİLİYOR / DİZİLER / FİLMLER
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: Downloads.I,
        builder: (context, _) {
          final dl = Downloads.I;
          final active = dl.list.where((d) => d.state != DlState.done).toList()..sort((a, b) => a.added.compareTo(b.added));
          final done = dl.list.where((d) => d.state == DlState.done).toList();
          final movies = done.where((d) => !d.isEpisode).toList()..sort((a, b) => b.added.compareTo(a.added));
          final bySeries = <String, List<Dl>>{};
          for (final d in done.where((d) => d.isEpisode)) {
            (bySeries['${d.item['SeriesId'] ?? d.series}'] ??= []).add(d);
          }
          for (final l in bySeries.values) {
            l.sort((a, b) {
              final s = a.season.compareTo(b.season);
              return s != 0 ? s : a.index.compareTo(b.index);
            });
          }
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              const CupertinoSliverNavigationBar(
                largeTitle: Text('İndirilenler', style: TextStyle(color: Color(0xFFF5F5F7))),
                backgroundColor: Color(0xCC0B0B0D),
                border: null,
                automaticallyImplyLeading: false,
              ),
              if (dl.list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                            color: Colors.white.withAlpha(18), shape: BoxShape.circle, border: Border.all(color: Colors.white.withAlpha(30))),
                        child: const Icon(Icons.arrow_downward_rounded, size: 44, color: Color(0xFFF5F5F7)),
                      ),
                      const SizedBox(height: 18),
                      const Text('Henüz indirilen yok', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text('Bir filmin ya da bölümün sayfasındaki indirme düğmesine bas; internet yokken buradan izlersin.',
                          textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.4)),
                    ]),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 6, pad, 0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withAlpha(20)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${done.length} içerik · ${fmtBytes(dl.usedBytes)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Expanded(child: Text('İzleyince sil', style: TextStyle(fontSize: 15))),
                          CupertinoSwitch(
                            value: dl.autoDelete,
                            activeColor: const Color(0xFF34C759),
                            onChanged: (v) {
                              HapticFeedback.selectionClick();
                              dl.autoDelete = v;
                            },
                          ),
                        ]),
                      ]),
                    ),
                  ),
                ),
                if (active.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _sec('İNDİRİLİYOR', pad)),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    sliver: SliverList.separated(
                      itemCount: active.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (c, i) => _ActiveTile(active[i]),
                    ),
                  ),
                ],
                if (bySeries.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _sec('DİZİLER', pad)),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    sliver: SliverList.separated(
                      itemCount: bySeries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (c, i) {
                        final e = bySeries.entries.elementAt(i);
                        return _SeriesCard(e.key, e.value);
                      },
                    ),
                  ),
                ],
                if (movies.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _sec('FİLMLER', pad)),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    sliver: SliverList.separated(
                      itemCount: movies.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (c, i) => _DoneTile(movies[i]),
                    ),
                  ),
                ],
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          );
        },
      ),
    );
  }
}

/// İnen / sıradaki / duran / hatalı
class _ActiveTile extends StatelessWidget {
  final Dl d;
  const _ActiveTile(this.d);

  @override
  Widget build(BuildContext context) {
    final dl = Downloads.I;
    final title = d.isEpisode ? '${d.series} · B${d.index}' : d.name;
    final run = d.state == DlState.running || d.state == DlState.queued;
    final failed = d.state == DlState.failed;
    return Pressable(
      onTap: () => dlActions(context, d),
      child: Row(children: [
        _thumb(dl.abs(d.wide)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: d.state == DlState.queued || (d.state == DlState.running && d.total == 0) ? null : d.frac,
                minHeight: 4,
                color: failed ? const Color(0xFFFF6B6B) : kBlue,
                backgroundColor: Colors.white.withAlpha(38),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              d.state == DlState.running ? '${_status(d)} · Kilitliyken de sürer' : _status(d),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: failed ? const Color(0xFFFF8A8A) : _muted),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        run
            ? _circle(Icons.pause_rounded, 'Duraklat', () => dl.pause(d))
            : _circle(Icons.refresh_rounded, 'Devam et', () => dl.resume(d)),
      ]),
    );
  }
}

/// Bitmiş film ya da bölüm satırı
class _DoneTile extends StatelessWidget {
  final Dl d;
  const _DoneTile(this.d);

  @override
  Widget build(BuildContext context) {
    final run = ((d.item['RunTimeTicks'] as num?) ?? 0);
    final prog = run > 0 && !d.watched ? (d.posTicks / run).clamp(0, 1).toDouble() : 0.0;
    final title = d.isEpisode ? '${d.index}. ${d.name}' : d.name;
    return Pressable(
      onTap: () => openPlayer(context, d.item),
      onLongPress: () => dlActions(context, d),
      child: Row(children: [
        _thumb(Downloads.I.abs(d.wide), prog: prog),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(_status(d), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        const SizedBox(width: 10),
        _circle(Icons.play_arrow_rounded, 'Oynat', () => openPlayer(context, d.item), white: true),
      ]),
    );
  }
}

/// DİZİLER: dizi başına tek kart → bölümler sayfası
class _SeriesCard extends StatelessWidget {
  final String sid;
  final List<Dl> eps;
  const _SeriesCard(this.sid, this.eps);

  @override
  Widget build(BuildContext context) {
    final f = eps.first;
    final size = eps.fold<int>(0, (a, d) => a + d.got);
    final poster = eps.map((d) => d.poster).firstWhere((p) => p != null, orElse: () => null);
    return Pressable(
      onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => _SeriesDlPage(sid, f.series))),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withAlpha(13), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          _thumb(Downloads.I.abs(poster), w: 52, h: 78, r: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.series, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${eps.length} bölüm · ${fmtBytes(size)}', style: const TextStyle(fontSize: 12, color: _muted)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ]),
      ),
    );
  }
}

class _SeriesDlPage extends StatelessWidget {
  final String sid, name;
  const _SeriesDlPage(this.sid, this.name);

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    return Scaffold(
      backgroundColor: kBg,
      body: ListenableBuilder(
        listenable: Downloads.I,
        builder: (context, _) {
          final eps = Downloads.I.list
              .where((d) => d.isEpisode && d.state == DlState.done && '${d.item['SeriesId'] ?? d.series}' == sid)
              .toList()
            ..sort((a, b) {
              final s = a.season.compareTo(b.season);
              return s != 0 ? s : a.index.compareTo(b.index);
            });
          final seasons = <num, List<Dl>>{};
          for (final d in eps) {
            (seasons[d.season] ??= []).add(d);
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: Text(name, style: const TextStyle(color: Color(0xFFF5F5F7))),
                previousPageTitle: 'İndirilenler',
                backgroundColor: const Color(0xCC0B0B0D),
                border: null,
              ),
              if (eps.isEmpty)
                const SliverFillRemaining(
                    hasScrollBody: false, child: Center(child: Text('Bu dizinin indirilen bölümü kalmadı.', style: TextStyle(color: _muted)))),
              for (final e in seasons.entries) ...[
                SliverToBoxAdapter(child: _sec(e.key == 0 ? 'ÖZEL' : 'SEZON ${e.key}', pad)),
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  sliver: SliverList.separated(
                    itemCount: e.value.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (c, i) => _DoneTile(e.value[i]),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          );
        },
      ),
    );
  }
}
