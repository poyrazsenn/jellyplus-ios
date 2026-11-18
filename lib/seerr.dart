import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'nav.dart';
import 'util.dart';
import 'widgets.dart';

class SeerrError implements Exception {
  final int code;
  final String msg;
  SeerrError(this.code, this.msg);
  @override
  String toString() => code == 401 || code == 403
      ? 'API anahtarı geçersiz ($code)'
      : (msg.isNotEmpty ? msg : 'Seerr hatası ($code)');
}

/// Jellyseerr / Overseerr (Seerr) API'si. Kimlik: Seerr → Ayarlar → Genel → API Anahtarı.
class Seerr {
  Seerr._();
  static final Seerr I = Seerr._();

  Api get api => Api.I;

  /// Kayıtlı adres yoksa Jellyfin sunucusuyla aynı makinede 5055 portu varsayılır.
  String get url {
    final s = api.prefs.getString('seerr') ?? '';
    if (s.isNotEmpty) return s;
    final u = Uri.tryParse(api.url);
    return u == null || u.host.isEmpty ? '' : '${u.scheme}://${u.host}:5055';
  }

  set url(String v) => api.prefs.setString('seerr', Api.normalize(v).replaceAll(RegExp(r'/api/v1$'), ''));
  String get key => api.prefs.getString('seerrkey') ?? '';
  set key(String v) => api.prefs.setString('seerrkey', v.trim());
  bool get on => key.isNotEmpty && url.isNotEmpty;

  Future<dynamic> _req(String m, String p, [Object? body]) async {
    final u = Uri.parse('$url/api/v1$p');
    final h = {'X-Api-Key': key, 'Accept': 'application/json', 'Content-Type': 'application/json'};
    const t = Duration(seconds: 20);
    final r = m == 'POST'
        ? await http.post(u, headers: h, body: jsonEncode(body ?? {})).timeout(t)
        : await http.get(u, headers: h).timeout(t);
    dynamic j;
    try {
      j = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {}
    if (r.statusCode >= 400) {
      throw SeerrError(r.statusCode, j is Map ? '${j['message'] ?? ''}' : '');
    }
    return j;
  }

  /// Bağlantı ve anahtarı dener; sorun varsa açıklamasını döndürür.
  Future<String?> test() async {
    try {
      await _req('GET', '/request?take=1');
      return null;
    } on SeerrError catch (e) {
      return '$e';
    } catch (e) {
      return 'Seerr\'e ulaşılamadı ($url). Adresi kontrol et.';
    }
  }

  Future<List<J>> search(String q) async {
    final r = await _req('GET', '/search?query=${Uri.encodeComponent(q)}&page=1&language=tr');
    return (((r as Map?)?['results'] as List?) ?? const [])
        .map((e) => J.from(e as Map))
        .where((e) => e['mediaType'] == 'movie' || e['mediaType'] == 'tv')
        .toList();
  }

  Future<void> request(J r) => _req('POST', '/request', {
        'mediaType': r['mediaType'],
        'mediaId': r['id'],
        if (r['mediaType'] == 'tv') 'seasons': 'all',
      });

  /// Son istekler; başlık ve afiş için her birinin TMDB bilgisi de alınır.
  Future<List<J>> requests() async {
    final r = await _req('GET', '/request?take=40&skip=0&sort=added&filter=all');
    final l = (((r as Map?)?['results'] as List?) ?? const []).map((e) => J.from(e as Map)).toList();
    await Future.wait(l.map((x) async {
      final m = (x['media'] as Map?) ?? const {};
      final type = m['mediaType'] ?? x['type'];
      if (m['tmdbId'] == null || type == null) return;
      try {
        final d = await _req('GET', '/$type/${m['tmdbId']}?language=tr') as Map;
        x['_title'] = d['title'] ?? d['name'];
        x['_poster'] = d['posterPath'];
        x['_year'] = '${d['releaseDate'] ?? d['firstAirDate'] ?? ''}'.split('-').first;
      } catch (_) {}
    }));
    return l;
  }

  static String poster(dynamic p, [int w = 185]) => p == null || '$p'.isEmpty ? '' : 'https://image.tmdb.org/t/p/w$w$p';

  /// Medya durumu (+ istek durumu) → kısa Türkçe etiket, renk, indirme yüzdesi.
  static ({String text, Color color, double? frac}) status(Map? media, [int? reqStatus]) {
    final ms = (media?['status'] as num?)?.toInt() ?? 1;
    double? frac;
    final ds = (media?['downloadStatus'] as List?) ?? const [];
    if (ds.isNotEmpty) {
      var size = 0.0, left = 0.0;
      for (final d in ds) {
        size += ((d['size'] as num?) ?? 0).toDouble();
        left += ((d['sizeLeft'] as num?) ?? 0).toDouble();
      }
      if (size > 0) frac = ((size - left) / size).clamp(0, 1).toDouble();
    }
    if (reqStatus == 3) return (text: 'Reddedildi', color: const Color(0xFFFF8A8A), frac: null);
    if (reqStatus == 4) return (text: 'Başarısız', color: const Color(0xFFFF8A8A), frac: null);
    switch (ms) {
      case 5:
        return (text: 'Hazır', color: const Color(0xFF4ADE80), frac: null);
      case 4:
        return (text: 'Kısmen hazır', color: const Color(0xFF4ADE80), frac: frac);
      case 3:
        return (
          text: frac != null ? 'İndiriliyor %${(frac * 100).round()}' : 'İşleniyor',
          color: kBlue,
          frac: frac
        );
      case 2:
        return (text: 'Onay bekliyor', color: const Color(0xFFFBBF24), frac: null);
      default:
        return reqStatus == 2
            ? (text: 'Onaylandı', color: kBlue, frac: null)
            : (text: 'İstenebilir', color: kMuted, frac: null);
    }
  }
}

/// Aramada / listelerde Seerr sonucu satırı: afiş, ad, yıl ve "İste" ya da durum.
class SeerrResultTile extends StatefulWidget {
  final J r;
  const SeerrResultTile(this.r, {super.key});
  @override
  State<SeerrResultTile> createState() => _SeerrResultTileState();
}

class _SeerrResultTileState extends State<SeerrResultTile> {
  bool busy = false;

  Future<void> ask() async {
    setState(() => busy = true);
    try {
      await Seerr.I.request(widget.r);
      widget.r['mediaInfo'] = {...?(widget.r['mediaInfo'] as Map?), 'status': 2};
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"${widget.r['title'] ?? widget.r['name']}" istendi. Profil → İsteklerim\'den takip edebilirsin.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('İstenemedi: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final mi = r['mediaInfo'] as Map?;
    final st = (mi?['status'] as num?)?.toInt() ?? 1;
    final s = Seerr.status(mi);
    final year = '${r['releaseDate'] ?? r['firstAirDate'] ?? ''}'.split('-').first;
    final img = Seerr.poster(r['posterPath']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 52,
            height: 78,
            color: kCard,
            child: img.isEmpty ? const Icon(Icons.movie_outlined, color: kMuted) : CachedNetworkImage(imageUrl: img, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['title'] ?? r['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text([if (year.isNotEmpty) year, r['mediaType'] == 'tv' ? 'Dizi' : 'Film'].join(' • '),
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        if (st <= 1)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kBlue, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: busy ? null : ask,
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kInk))
                : const Text('İste', style: TextStyle(color: kInk, fontWeight: FontWeight.w700)),
          )
        else
          Text(s.text, style: TextStyle(color: s.color, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }
}

/// Profil → İsteklerim
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<J>? list;
  String err = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final l = await Seerr.I.requests();
      if (mounted) {
        setState(() {
          list = l;
          err = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => err = 'İstekler alınamadı.\n$e');
    }
  }

  /// Hazır olan isteğe dokununca Jellyfin'de bul ve aç.
  Future<void> open(J x) async {
    final t = '${x['_title'] ?? ''}';
    if (t.isEmpty) return;
    final api = Api.I;
    try {
      final r = await api.items(
          '/Users/${api.uid}/Items?searchTerm=${Uri.encodeQueryComponent(t)}&Recursive=true&IncludeItemTypes=Movie,Series&Limit=5&Fields=$kFields');
      if (!mounted) return;
      if (r.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Jellyfin\'de henüz görünmüyor; kütüphane taraması bitince gelir.')));
        return;
      }
      final y = '${x['_year'] ?? ''}';
      final pick = r.firstWhere((e) => '${e['ProductionYear'] ?? ''}' == y, orElse: () => r.first);
      await openItem(context, pick);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = list;
    return Scaffold(
      appBar: AppBar(title: const Text('İsteklerim')),
      body: err.isNotEmpty
          ? ErrorView(err, retry: load)
          : l == null
              ? const Loading()
              : RefreshIndicator(
                  onRefresh: load,
                  child: l.isEmpty
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(40),
                            child: Text('Henüz istek yok. Ara sekmesinde sunucuda olmayan bir film arayınca "İste" çıkar.',
                                textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
                          ),
                        ])
                      : ListView.separated(
                          padding: EdgeInsets.symmetric(horizontal: hPad(context), vertical: 8),
                          itemCount: l.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final x = l[i];
                            final m = x['media'] as Map?;
                            final s = Seerr.status(m, (x['status'] as num?)?.toInt());
                            final img = Seerr.poster(x['_poster']);
                            final type = (m?['mediaType'] ?? x['type']) == 'tv' ? 'Dizi' : 'Film';
                            final when = DateTime.tryParse('${x['createdAt'] ?? ''}')?.toLocal();
                            return InkWell(
                              onTap: () => open(x),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      width: 52,
                                      height: 78,
                                      color: kCard,
                                      child: img.isEmpty ? null : CachedNetworkImage(imageUrl: img, fit: BoxFit.cover),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${x['_title'] ?? 'TMDB ${m?['tmdbId'] ?? ''}'}',
                                          maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 3),
                                      Text(
                                          [
                                            if ('${x['_year'] ?? ''}'.isNotEmpty) '${x['_year']}',
                                            type,
                                            if (when != null) '${when.day}.${when.month}.${when.year} istendi',
                                          ].join(' • '),
                                          style: const TextStyle(color: kMuted, fontSize: 12)),
                                      const SizedBox(height: 6),
                                      Text(s.text, style: TextStyle(color: s.color, fontWeight: FontWeight.w700, fontSize: 13)),
                                      if (s.frac != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: LinearProgressIndicator(
                                              value: s.frac, minHeight: 3, color: kBlue, backgroundColor: Colors.white12),
                                        ),
                                    ]),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

/// Profil → Seerr bağlantısı
class SeerrSettingsScreen extends StatefulWidget {
  const SeerrSettingsScreen({super.key});
  @override
  State<SeerrSettingsScreen> createState() => _SeerrSettingsScreenState();
}

class _SeerrSettingsScreenState extends State<SeerrSettingsScreen> {
  late final u = TextEditingController(text: Seerr.I.url);
  late final k = TextEditingController(text: Seerr.I.key);
  String msg = '';
  bool busy = false, ok = false;

  @override
  void dispose() {
    u.dispose();
    k.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      msg = '';
    });
    Seerr.I.url = u.text;
    Seerr.I.key = k.text;
    final e = await Seerr.I.test();
    if (!mounted) return;
    setState(() {
      busy = false;
      ok = e == null;
      msg = e ?? 'Bağlandı. Artık aramada "İste" düğmesi çıkar.';
    });
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String l, [String? h]) => InputDecoration(
          labelText: l,
          hintText: h,
          filled: true,
          fillColor: Colors.white.withAlpha(20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Seerr bağlantısı')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'Seerr\'de Ayarlar → Genel sayfasındaki "API Anahtarı"nı kopyalayıp buraya yapıştır. '
            'Anahtar sadece bu telefonda saklanır.',
            style: TextStyle(color: kMuted, height: 1.4)),
        const SizedBox(height: 18),
        TextField(controller: u, decoration: deco('Seerr adresi', 'http://sunucu:5055'), keyboardType: TextInputType.url, autocorrect: false),
        const SizedBox(height: 12),
        TextField(controller: k, decoration: deco('API anahtarı'), autocorrect: false, obscureText: true),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : save,
          style: FilledButton.styleFrom(backgroundColor: kBlue, padding: const EdgeInsets.symmetric(vertical: 14)),
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kInk))
              : const Text('Kaydet ve dene', style: TextStyle(color: kInk, fontWeight: FontWeight.w700)),
        ),
        if (msg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(msg, style: TextStyle(color: ok ? const Color(0xFF4ADE80) : const Color(0xFFFF8A8A))),
          ),
      ]),
    );
  }
}
