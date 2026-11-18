import 'dart:io';

import 'package:flutter/material.dart';

import 'api.dart';
import 'downloads.dart';
import 'nav.dart';
import 'util.dart';

/// Kalite seçtirip indirmeyi kuyruğa ekler.
Future<void> askDownload(BuildContext context, List<J> items, {String? title}) async {
  if (items.isEmpty) return;
  final dl = Downloads.I;
  final orig = dl.sizeOf(items, 'orig'), small = dl.sizeOf(items, 'small');
  final q = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: kSheet,
    builder: (c) {
      Widget opt(String k, IconData i, String t, String sub) => ListTile(
            leading: Icon(i),
            title: Text(t),
            subtitle: Text(sub, style: const TextStyle(color: kMuted, fontSize: 12)),
            trailing: dl.defaultQuality == k ? const Icon(Icons.check, color: kBlue) : null,
            onTap: () => Navigator.pop(c, k),
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title ?? (items.length == 1 ? 'İndir' : '${items.length} bölümü indir'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          opt('orig', Icons.high_quality_outlined, 'Orijinal kalite',
              '${orig > 0 ? '${fmtBytes(orig)} • ' : ''}Sunucuyu yormaz, kaldığı yerden devam eder'),
          opt('small', Icons.sd_outlined, 'Küçük (720p)',
              '${small > 0 ? 'yaklaşık ${fmtBytes(small)} • ' : ''}Sunucu bir kez küçültür, yer kazandırır'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text('İndirme telefon kilitliyken ve uygulama kapalıyken de sürer.',
                style: TextStyle(color: kMuted, fontSize: 11)),
          ),
        ]),
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
  final a = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: kSheet,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(d.isEpisode ? '${d.series} • S${d.season}:B${d.index}' : d.name,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(_status(d), style: const TextStyle(color: kMuted, fontSize: 12)),
        ),
        if (d.state == DlState.done)
          ListTile(leading: const Icon(Icons.play_arrow), title: const Text('Oynat'), onTap: () => Navigator.pop(c, 'play')),
        if (d.state == DlState.running || d.state == DlState.queued)
          ListTile(leading: const Icon(Icons.pause), title: const Text('Duraklat'), onTap: () => Navigator.pop(c, 'pause')),
        if (d.state == DlState.paused || d.state == DlState.failed)
          ListTile(leading: const Icon(Icons.refresh), title: const Text('Devam et'), onTap: () => Navigator.pop(c, 'resume')),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Color(0xFFFF8A8A)),
          title: Text(d.state == DlState.done ? 'İndirmeyi sil' : 'İptal et ve sil',
              style: const TextStyle(color: Color(0xFFFF8A8A))),
          onTap: () => Navigator.pop(c, 'del'),
        ),
      ]),
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
      final left = run > 0 && d.posTicks > 0 ? ' • ${rt(run - d.posTicks)} kaldı' : '';
      return '${fmtBytes(d.got)} • $q${d.watched ? ' • İzlendi' : left}';
    case DlState.running:
      return d.total > 0
          ? 'İndiriliyor %${(d.frac * 100).round()} • ${fmtBytes(d.got)} / ${d.quality == 'small' ? '~' : ''}${fmtBytes(d.total)}'
          : 'İndiriliyor • ${fmtBytes(d.got)}';
    case DlState.queued:
      return 'Sırada • $q';
    case DlState.paused:
      return 'Duraklatıldı • ${fmtBytes(d.got)}';
    default:
      return d.err.isEmpty ? 'İndirilemedi' : d.err;
  }
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = hPad(context);
    return Scaffold(
      appBar: AppBar(title: const Text('İndirilenler')),
      body: ListenableBuilder(
        listenable: Downloads.I,
        builder: (context, _) {
          final dl = Downloads.I;
          final movies = dl.list.where((d) => !d.isEpisode).toList()..sort((a, b) => b.added.compareTo(a.added));
          final bySeries = <String, List<Dl>>{};
          for (final d in dl.list.where((d) => d.isEpisode)) {
            (bySeries['${d.item['SeriesId'] ?? d.series}'] ??= []).add(d);
          }
          for (final l in bySeries.values) {
            l.sort((a, b) {
              final s = a.season.compareTo(b.season);
              return s != 0 ? s : a.index.compareTo(b.index);
            });
          }
          if (dl.list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.download_for_offline_outlined, size: 64, color: kMuted),
                  SizedBox(height: 14),
                  Text('Henüz indirilen yok', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text('Bir film ya da bölümün sayfasındaki indirme düğmesine bas; internet yokken buradan izlersin.',
                      textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                ]),
              ),
            );
          }
          return ListView(padding: EdgeInsets.fromLTRB(pad, 4, pad, 30), children: [
            Row(children: [
              Expanded(
                child: Text('${dl.list.where((d) => d.state == DlState.done).length} içerik • ${fmtBytes(dl.usedBytes)}',
                    style: const TextStyle(color: kMuted, fontSize: 13)),
              ),
              const Text('İzleyince sil', style: TextStyle(fontSize: 13)),
              Switch.adaptive(value: dl.autoDelete, onChanged: (v) => dl.autoDelete = v),
            ]),
            if (movies.isNotEmpty) _head('Filmler'),
            for (final d in movies) _DlTile(d),
            for (final e in bySeries.entries) ...[
              _head(e.value.first.series),
              for (final d in e.value) _DlTile(d),
            ],
          ]);
        },
      ),
    );
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}

class _DlTile extends StatelessWidget {
  final Dl d;
  const _DlTile(this.d);

  @override
  Widget build(BuildContext context) {
    final dl = Downloads.I;
    final img = dl.abs(d.wide);
    final title = d.isEpisode ? 'B${d.index} • ${d.name}' : d.name;
    final run = ((d.item['RunTimeTicks'] as num?) ?? 0);
    final watchedFrac = run > 0 ? (d.posTicks / run).clamp(0, 1).toDouble() : 0.0;
    Widget trailing;
    switch (d.state) {
      case DlState.done:
        trailing = IconButton(icon: const Icon(Icons.play_circle_fill, size: 34), onPressed: () => openPlayer(context, d.item));
        break;
      case DlState.running:
      case DlState.queued:
        trailing = SizedBox(
          width: 40,
          height: 40,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(
                value: d.state == DlState.queued || d.total == 0 ? null : d.frac, strokeWidth: 2.5, color: kBlue),
            IconButton(icon: const Icon(Icons.pause, size: 18), onPressed: () => dl.pause(d)),
          ]),
        );
        break;
      default:
        trailing = IconButton(icon: const Icon(Icons.refresh), onPressed: () => dl.resume(d));
    }
    return InkWell(
      onTap: () => d.state == DlState.done ? openPlayer(context, d.item) : dlActions(context, d),
      onLongPress: () => dlActions(context, d),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
            width: 128,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(fit: StackFit.expand, children: [
                  Container(color: kCard),
                  if (img != null)
                    Image.file(File(img), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  if (d.state == DlState.done && watchedFrac > 0 && !d.watched)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                          widthFactor: watchedFrac, child: Container(height: 3, color: const Color(0xFF4DA6FF))),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(_status(d),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: d.state == DlState.failed ? const Color(0xFFFF8A8A) : kMuted, fontSize: 12)),
              if (d.state == DlState.running && d.total > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(value: d.frac, minHeight: 3, color: kBlue, backgroundColor: Colors.white12),
                ),
            ]),
          ),
          trailing,
        ]),
      ),
    );
  }
}
