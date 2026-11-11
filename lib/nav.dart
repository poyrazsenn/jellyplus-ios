import 'package:flutter/material.dart';

import 'api.dart';
import 'detail.dart';
import 'library.dart';
import 'player.dart';

/// Kart/vitrin tıklaması: bölümse dizisine, koleksiyonsa içeriğine, değilse detaya git.
Future<void> openItem(BuildContext c, J it) async {
  if (it['Type'] == 'BoxSet') {
    await openLibrary(c, '${it['Name'] ?? 'Koleksiyon'}', '&ParentId=${it['Id']}');
    return;
  }
  final id = (it['Type'] == 'Episode' && it['SeriesId'] != null) ? it['SeriesId'] : it['Id'];
  await Navigator.of(c).push(MaterialPageRoute(builder: (_) => DetailScreen(id: '$id')));
}

Future<void> openLibrary(BuildContext c, String title, String extra) =>
    Navigator.of(c).push(MaterialPageRoute(builder: (_) => LibraryScreen(title: title, extra: extra)));

Future<void> openPlayer(BuildContext c, J it, {bool restart = false}) async {
  await Navigator.of(c, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true, builder: (_) => PlayerScreen(item: it, restart: restart)));
  refreshBus.value++;
}
