import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'downloads.dart';
import 'downloads_screen.dart';
import 'nav.dart';
import 'util.dart';
import 'widgets.dart';

/// Önizlenebilir mi? (gerçek Jellyfin öğesi: film, dizi, bölüm)
bool canPreview(J x) =>
    ['Movie', 'Series', 'Episode'].contains(x['Type']) && x['_img'] == null && x['_seerr'] == null && x['Id'] != null;

/// iPhone'daki gibi: karta basılı tutunca kart büyür, arka plan bulanıklaşır, altında eylem menüsü açılır.
Future<void> showPreview(BuildContext context, J x) {
  if (!canPreview(x)) return Future.value();
  return showGeneralDialog(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (c, _, __) => _Preview(x, origin: context),
    transitionBuilder: (c, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween(begin: .9, end: 1.0).animate(t), child: child),
      );
    },
  );
}

class _Preview extends StatelessWidget {
  final J x;
  final BuildContext origin;
  const _Preview(this.x, {required this.origin});

  @override
  Widget build(BuildContext context) {
    final api = Api.I;
    final w = MediaQuery.sizeOf(context).width;
    final cw = (w - 40).clamp(0, 460).toDouble();
    final ud = (x['UserData'] as Map?) ?? const {};
    final fav = ud['IsFavorite'] == true;
    final seen = ud['Played'] == true;
    final pos = (ud['PlaybackPositionTicks'] as num?) ?? 0;
    final playable = x['Type'] != 'Series';
    final dl = Downloads.I.of('${x['Id']}');
    final ep = x['Type'] == 'Episode';
    final title = ep ? '${x['SeriesName'] ?? ''}' : '${x['Name'] ?? ''}';
    final sub = [
      if (ep) 'S${x['ParentIndexNumber'] ?? '?'} · B${x['IndexNumber'] ?? '?'} · ${x['Name'] ?? ''}',
      if (!ep && x['ProductionYear'] != null) '${x['ProductionYear']}',
      if (!ep) x['Type'] == 'Series' ? 'Dizi' : 'Film',
      if (rt(x['RunTimeTicks']).isNotEmpty && !ep) rt(x['RunTimeTicks']),
    ].join(' · ');
    final pr = ((ud['PlayedPercentage'] as num?) ?? 0).toDouble();
    final wi = wideImg(x);

    void close() => Navigator.of(context).pop();
    Future<void> flag(String path, bool on, String msg) async {
      close();
      try {
        on ? await api.post('/Users/${api.uid}/$path/${x['Id']}') : await api.delete('/Users/${api.uid}/$path/${x['Id']}');
        refreshBus.value++;
        if (origin.mounted) ScaffoldMessenger.of(origin).showSnackBar(SnackBar(content: Text(msg)));
      } catch (_) {
        if (origin.mounted) ScaffoldMessenger.of(origin).showSnackBar(const SnackBar(content: Text('Yapılamadı, tekrar dene.')));
      }
    }

    final actions = <(IconData, String, VoidCallback)>[
      if (playable)
        (Icons.play_arrow_rounded, pos > 0 && !seen ? 'Devam et' : 'Oynat', () {
          close();
          openPlayer(origin, x);
        })
      else
        (Icons.tv_rounded, 'Diziyi aç', () {
          close();
          openItem(origin, x);
        }),
      (fav ? Icons.check_rounded : Icons.add_rounded, fav ? 'Listemden çıkar' : 'Listeme ekle',
          () => flag('FavoriteItems', !fav, fav ? 'Listenden çıkarıldı.' : 'Listene eklendi.')),
      if (playable && dl == null)
        (Icons.download_rounded, 'İndir', () {
          close();
          askDownload(origin, [x]);
        }),
      (seen ? Icons.visibility_off_outlined : Icons.visibility_outlined, seen ? 'İzlenmedi olarak işaretle' : 'İzlendi olarak işaretle',
          () => flag('PlayedItems', !seen, seen ? 'İzlenmedi olarak işaretlendi.' : 'İzlendi olarak işaretlendi.')),
      (Icons.info_outline_rounded, 'Ayrıntılar', () {
        close();
        openItem(origin, x);
      }),
    ];

    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: close,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(color: const Color(0x99000000)),
          ),
        ),
      ),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: SizedBox(
            width: cw,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 18))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(fit: StackFit.expand, children: [
                      netImg(wi.url, align: wi.poster ? const Alignment(0, -.5) : Alignment.center),
                      if (pr > 0 && pr < 100)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: FractionallySizedBox(widthFactor: pr / 100, child: Container(height: 3, color: kBlue)),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: Color(0xB3F5F5F7))),
                      ],
                      if ('${x['Overview'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('${x['Overview']}', maxLines: 3, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xD9F5F5F7))),
                      ],
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: cw * .72,
                  child: Glass(
                    radius: 16,
                    color: const Color(0xE62A2A30),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const Divider(height: 1, thickness: .5, color: Color(0x26FFFFFF)),
                        Semantics(
                          button: true,
                          label: actions[i].$2,
                          child: InkResponse(
                            highlightShape: BoxShape.rectangle,
                            containedInkWell: true,
                            splashFactory: NoSplash.splashFactory,
                            highlightColor: const Color(0x1AFFFFFF),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              actions[i].$3();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                              child: Row(children: [
                                Expanded(child: Text(actions[i].$2, style: const TextStyle(fontSize: 16))),
                                Icon(actions[i].$1, size: 20, color: const Color(0xFFF5F5F7)),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
