import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'util.dart';
import 'version.dart';
import 'welcome.dart';
import 'whats_new.g.dart';

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

/// Güncellemeden sonraki ilk açılışta bir kez: büyük sürümde (3.0 gibi) tam ekran hoş geldin turu,
/// küçük sürümlerde sürüm notlarından gelen cam yenilikler sayfası.
Future<void> showWhatsNew(BuildContext context, {bool force = false}) async {
  final p = Api.I.prefs;
  final seen = p.getString('seenver') ?? '';
  if (!force && seen == kVersion) return;
  await p.setString('seenver', kVersion);
  if (!context.mounted) return;
  final major = kVersion.split('.').first;
  final tourDone = p.getBool('tour$major') ?? false;
  if (major == '3' && (!tourDone || force)) {
    await p.setBool('tour$major', true);
    await Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const WelcomeTour()));
    return;
  }
  if (kWhatsNew.isEmpty) return;
  await showSmallWhatsNew(context);
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
  await showCupertinoDialog(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      title: const Text('Yeni sürüm var'),
      content: Text(
        'Poyraz Player $latest çıktı (sende $kVersion).'
        '${'${j['notes'] ?? ''}'.isNotEmpty ? '\n\n${j['notes']}' : ''}'
        '\n\nYeni IPA\'yı Sideloadly ile aynı şekilde kur; girişlerin ve indirdiklerin silinmez.',
      ),
      actions: [
        if (url.isNotEmpty)
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.pop(c);
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: const Text('İndir'),
          ),
        CupertinoDialogAction(onPressed: () => Navigator.pop(c), child: const Text('Sonra')),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () {
            api.prefs.setString('skipver', latest);
            Navigator.pop(c);
          },
          child: const Text('Bu sürümü atla'),
        ),
      ],
    ),
  );
}
