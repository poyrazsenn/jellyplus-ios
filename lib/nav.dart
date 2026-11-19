import 'package:flutter/material.dart';

import 'api.dart';
import 'detail.dart';
import 'library.dart';
import 'player.dart';
import 'theme_music.dart';

/// Kart/vitrin tıklaması: bölümse dizisine, koleksiyonsa içeriğine, değilse detaya git.
Future<void> openItem(BuildContext c, J it) async {
  if (it['Type'] == 'BoxSet') {
    await openLibrary(c, '${it['Name'] ?? 'Koleksiyon'}', '&ParentId=${it['Id']}');
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
  await Navigator.of(c, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true, builder: (_) => PlayerScreen(item: it, restart: restart)));
  refreshBus.value++;
}

/// Kabuktaki sekmeyi başka ekrandan değiştirmek için (ör. ana sayfadaki profil düğmesi → Profil).
final tabBus = ValueNotifier<int?>(null);
