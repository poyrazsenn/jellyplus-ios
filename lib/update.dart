import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  // alpha < beta < rc < kararlı; aynı etikette sondaki sayı
  int pre(String v) {
    final i = v.indexOf('-');
    if (i < 0) return 1 << 30; // kararlı
    final tail = v.substring(i + 1).toLowerCase();
    final rank = tail.startsWith('rc') ? 3 : tail.startsWith('beta') ? 2 : tail.startsWith('alpha') ? 1 : 0;
    final m = RegExp(r'(\d+)$').firstMatch(tail);
    return rank * 100000 + (m == null ? 0 : int.parse(m.group(1)!));
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

const kRepo = 'poyrazsenn/jellyplus-ios';

/// "v3.0.0-beta.16" → "3.0 beta 16"
String prettyVersion(String v) {
  final t = v.replaceFirst(RegExp(r'^v'), '');
  final core = t.split('-').first.split('.');
  final short = core.length >= 3 && core[2] == '0' ? '${core[0]}.${core[1]}' : core.join('.');
  final pre = t.contains('-') ? t.substring(t.indexOf('-') + 1).replaceAll('.', ' ') : '';
  return pre.isEmpty ? short : '$short $pre';
}

/// Uygulama açılınca (6 saatte bir) ve Profil → Güncellemeleri denetle'den:
/// GitHub'daki sürümlere bakar. Beta kullanıyorsan betaları da gösterir.
Future<void> checkUpdate(BuildContext context, {bool manual = false}) async {
  final api = Api.I;
  final p = api.prefs;
  final now = DateTime.now().millisecondsSinceEpoch;
  if (!manual && now - (p.getInt('updAt') ?? 0) < 6 * 3600 * 1000) return;
  String? tag, ipa, body;
  try {
    final r = await http.get(Uri.parse('https://api.github.com/repos/$kRepo/releases?per_page=20'),
        headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('GitHub ${r.statusCode}');
    final beta = kVersion.contains('-');
    for (final x in (jsonDecode(utf8.decode(r.bodyBytes)) as List).cast<Map>()) {
      if (x['draft'] == true || (!beta && x['prerelease'] == true)) continue;
      final t = '${x['tag_name'] ?? ''}';
      if (t.isEmpty || !t.startsWith('v')) continue; // tema-v… gibi eklenti sürümlerini atla
      if (tag == null || compareVersions(t, tag) > 0) {
        tag = t;
        body = '${x['body'] ?? ''}';
        ipa = ((x['assets'] as List?) ?? const [])
            .cast<Map>()
            .map((a) => '${a['browser_download_url'] ?? ''}')
            .firstWhere((u) => u.endsWith('.ipa'), orElse: () => '${x['html_url'] ?? ''}');
      }
    }
    await p.setInt('updAt', now);
  } catch (_) {
    if (manual && context.mounted) {
      await _say(context, 'Denetlenemedi', 'GitHub\'a ulaşılamadı. İnternet bağlantını kontrol edip tekrar dene.');
    }
    return;
  }
  if (!context.mounted) return;
  if (tag == null || compareVersions(tag, kVersion) <= 0) {
    if (manual) await _say(context, 'Güncelsin', 'Poyraz Player ${prettyVersion(kVersion)} en yeni sürüm.');
    return;
  }
  if (!manual && p.getString('skipver') == tag) return;
  // sadece bu sürümün "Yenilikler" bölümü (önceki betalarınkiler değil)
  var sec = body ?? '';
  final yi = sec.indexOf('**Yenilikler**');
  if (yi >= 0) {
    sec = sec.substring(yi + 14);
    final end = sec.indexOf('\n**');
    if (end >= 0) sec = sec.substring(0, end);
  }
  final news = RegExp(r'^- \*\*(.+?):?\*\*', multiLine: true)
      .allMatches(sec)
      .map((m) => m.group(1)!.replaceAll(RegExp(r':$'), ''))
      .take(4)
      .toList();
  final t = tag;
  final dl = ipa ?? '';
  await showCupertinoDialog(
    context: context,
    builder: (c) => CupertinoAlertDialog(
      title: Text('Poyraz Player ${prettyVersion(t)} hazır'),
      content: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Sende ${prettyVersion(kVersion)} var.'
          '${news.isNotEmpty ? '\n\nYenilikler:\n${news.map((n) => '• $n').join('\n')}' : ''}'
          '\n\nSideStore kullanıyorsan: SideStore → My Apps\'ta güncelle. '
          'Ya da "İndir"e bas, IPA\'yı SideStore\'da + ile veya Sideloadly ile kur. Girişlerin ve indirdiklerin silinmez.',
          textAlign: TextAlign.left,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(c);
            if (dl.isNotEmpty) launchUrl(Uri.parse(dl), mode: LaunchMode.externalApplication);
          },
          child: const Text('İndir'),
        ),
        CupertinoDialogAction(onPressed: () => Navigator.pop(c), child: const Text('Sonra')),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () {
            p.setString('skipver', t);
            Navigator.pop(c);
          },
          child: const Text('Bu sürümü atla'),
        ),
      ],
    ),
  );
}

Future<void> _say(BuildContext context, String title, String msg) => showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
      ),
    );
