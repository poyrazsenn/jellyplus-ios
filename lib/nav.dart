import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'discover.dart';
import 'detail.dart';
import 'library.dart';
import 'player.dart';
import 'theme_music.dart';

/// Kart/vitrin tıklaması: bölümse dizisine, koleksiyonsa içeriğine, değilse detaya git.
Future<void> openItem(BuildContext c, J it) async {
  if (it['Type'] == 'BoxSet') {
    await Navigator.of(c).push(CupertinoPageRoute(builder: (_) => CollectionScreen(id: '${it['Id']}')));
    return;
  }
  final t = it['Type'];
  // Bölüm ya da sezon → dizinin sayfası, ilgili sezon seçili
  if ((t == 'Episode' || t == 'Season') && it['SeriesId'] != null) {
    final s = (t == 'Season' ? it['IndexNumber'] : it['ParentIndexNumber']) as num?;
    await Navigator.of(c).push(MaterialPageRoute(builder: (_) => DetailScreen(id: '${it['SeriesId']}', season: s)));
    return;
  }
  await Navigator.of(c).push(MaterialPageRoute(builder: (_) => DetailScreen(id: '${it['Id']}')));
}

Future<void> openLibrary(BuildContext c, String title, String extra) =>
    Navigator.of(c).push(MaterialPageRoute(builder: (_) => LibraryScreen(title: title, extra: extra)));

Future<void> openPlayer(BuildContext c, J it, {bool restart = false}) async {
  // Dizi/sezon/koleksiyonun kendi dosyası yok → önce sayfasına git
  if (['Series', 'Season', 'BoxSet', 'Folder', 'CollectionFolder'].contains(it['Type'])) {
    await openItem(c, it);
    return;
  }
  ThemeMusic.I.stop(hard: true);
  // Apple TV gibi: oynatıcı yumuşakça büyüyerek açılır, kapanırken küçülerek kaybolur
  await Navigator.of(c, rootNavigator: true).push(PageRouteBuilder(
    opaque: true,
    fullscreenDialog: true,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => PlayerScreen(item: it, restart: restart),
    transitionsBuilder: (_, a, __, child) {
      final t = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: t,
        child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(t), child: child),
      );
    },
  ));
  refreshBus.value++;
}

/// Kabuktaki sekmeyi başka ekrandan değiştirmek için (ör. ana sayfadaki profil düğmesi → Profil).
final tabBus = ValueNotifier<int?>(null);
