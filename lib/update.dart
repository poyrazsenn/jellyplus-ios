import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'util.dart';
import 'version.dart';

/// "1.2.3-beta.4" → karşılaştırılabilir parçalar. Ön sürüm, aynı numaralı kararlı sürümden eskidir.
int compareVersions(String a, String b) {
  List<int> nums(String v) {
    final core = v.trim().replaceFirst(RegExp(r'^v'), '').split('-').first;
    final p = core.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    while (p.length < 3) {
      p.add(0);
    }
    return p;
  }

  int pre(String v) {
    final i = v.indexOf('-');
    if (i < 0) return 1 << 30; // kararlı
    final m = RegExp(r'(\d+)$').firstMatch(v.substring(i));
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  final x = nums(a), y = nums(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i].compareTo(y[i]);
  }
  return pre(a).compareTo(pre(b));
}

const _icons = {
  'download_for_offline': Icons.download_for_offline_outlined,
  'playlist_add': Icons.playlist_add,
  'view_carousel': Icons.view_carousel_outlined,
  'skip_next': Icons.skip_next_outlined,
  'subtitles': Icons.subtitles_outlined,
};

/// Güncellemeden sonraki ilk açılışta bir kez "Yenilikler".
Future<void> showWhatsNew(BuildContext context, {bool force = false}) async {
  final p = Api.I.prefs;
  if (!force && p.getString('seenver') == kVersion) return;
  await p.setString('seenver', kVersion);
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF0E1328),
      title: Text('Jelly+ $kVersion yenilikleri'),
      content: SizedBox(
        width: 420,
        child: ListView(shrinkWrap: true, children: [
          for (final w in kWhatsNew)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_icons[w[0]] ?? Icons.star_outline, color: kBlue),
              title: Text(w[1], style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(w[2], style: const TextStyle(color: kMuted, fontSize: 12)),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
    ),
  );
}

/// Sunucudaki web klasörüne konan jellyplus-version.json'a bakar:
/// {"ios": "2.0.0", "notes": "…", "url": "https://…"}
Future<void> checkUpdate(BuildContext context) async {
  final api = Api.I;
  J j;
  try {
    j = J.from(jsonDecode(await api.getText('${api.url}/web/jellyplus-version.json')) as Map);
  } catch (_) {
    return; // dosya yok ya da çevrimdışı: sessiz geç
  }
  final latest = '${j['ios'] ?? ''}';
  if (latest.isEmpty || compareVersions(latest, kVersion) <= 0) return;
  if (api.prefs.getString('skipver') == latest) return;
  if (!context.mounted) return;
  final url = '${j['url'] ?? ''}';
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF0E1328),
      title: const Text('Yeni sürüm var'),
      content: Text(
        'Jelly+ $latest çıktı (sende $kVersion).'
        '${'${j['notes'] ?? ''}'.isNotEmpty ? '\n\n${j['notes']}' : ''}'
        '\n\nYeni IPA\'yı Sideloadly ile aynı şekilde kurman yeterli; girişlerin ve indirdiklerin silinmez.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            api.prefs.setString('skipver', latest);
            Navigator.pop(c);
          },
          child: const Text('Bu sürümü atla'),
        ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Sonra')),
        if (url.isNotEmpty)
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: const Text('İndir'),
          ),
      ],
    ),
  );
}
