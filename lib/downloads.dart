import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'util.dart';

enum DlState { queued, running, paused, done, failed }

/// İndirilmiş (ya da indirilmekte olan) tek bir film/bölüm.
class Dl {
  final String id;
  J item; // Jellyfin öğesi; indirme başlayınca MediaSources dahil tam hâli
  String quality; // 'orig' | 'small'
  DlState state;
  int got, total; // bayt (total 0 = bilinmiyor)
  String file; // indirme klasörüne göre göreli yol
  Map<String, String> subs; // altyazı akış index → göreli dosya
  String? poster, wide; // göreli resim yolları
  String err;
  int added;
  int? audio; // küçük kopyada seçilen ses akışı

  Dl(this.id, this.item, this.quality,
      {this.state = DlState.queued,
      this.got = 0,
      this.total = 0,
      this.file = '',
      Map<String, String>? subs,
      this.poster,
      this.wide,
      this.err = '',
      int? added,
      this.audio})
      : subs = subs ?? {},
        added = added ?? DateTime.now().millisecondsSinceEpoch;

  bool get isEpisode => item['Type'] == 'Episode';
  String get name => '${item['Name'] ?? ''}';
  String get series => '${item['SeriesName'] ?? ''}';
  num get season => (item['ParentIndexNumber'] as num?) ?? 0;
  num get index => (item['IndexNumber'] as num?) ?? 0;
  double get frac => total > 0 ? (got / total).clamp(0, 1).toDouble() : 0;
  num get posTicks => (item['UserData'] as Map?)?['PlaybackPositionTicks'] as num? ?? 0;
  bool get watched => (item['UserData'] as Map?)?['Played'] == true;

  J toJson() => {
        'id': id,
        'item': item,
        'q': quality,
        's': state.index,
        'got': got,
        'total': total,
        'file': file,
        'subs': subs,
        'poster': poster,
        'wide': wide,
        'err': err,
        'added': added,
        'audio': audio,
      };

  static Dl fromJson(J j) => Dl(
        '${j['id']}',
        J.from(j['item'] as Map),
        '${j['q'] ?? 'orig'}',
        state: DlState.values[(j['s'] as num?)?.toInt() ?? 0],
        got: (j['got'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        file: '${j['file'] ?? ''}',
        subs: ((j['subs'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
        poster: j['poster'] as String?,
        wide: j['wide'] as String?,
        err: '${j['err'] ?? ''}',
        added: (j['added'] as num?)?.toInt(),
        audio: (j['audio'] as num?)?.toInt(),
      );
}

class _Cancelled implements Exception {}

/// İndirme kuyruğu. Aynı anda tek dosya iner; uygulama arka plana geçip iOS indirmeyi
/// keserse, uygulama tekrar açılınca kaldığı bayttan devam eder (orijinal kalite).
class Downloads extends ChangeNotifier {
  Downloads._();
  static final Downloads I = Downloads._();

  /// Küçük kopya: 720p H.264 ~2.5 Mbps + AAC stereo
  static const smallVideoBps = 2500000, smallAudioBps = 160000;

  late Directory root;
  final List<Dl> list = [];
  bool _running = false, _ready = false;
  http.Client? _client;
  Dl? _cur;

  Api get api => Api.I;

  Future<void> init() async {
    // Application Support: kullanıcıya görünmez, iOS kendiliğinden silmez.
    final base = await getApplicationSupportDirectory();
    root = Directory('${base.path}/downloads');
    await root.create(recursive: true);
    try {
      final l = jsonDecode(api.prefs.getString('dl') ?? '[]') as List;
      list
        ..clear()
        ..addAll(l.map((e) => Dl.fromJson(J.from(e as Map))));
    } catch (_) {}
    for (final d in list) {
      if (d.state == DlState.running) d.state = DlState.queued;
      if (d.state == DlState.done && !File(path(d)).existsSync()) {
        d.state = DlState.failed;
        d.err = 'Dosya bulunamadı';
      }
    }
    _ready = true;
    await _save();
  }

  Future<void> _save() async {
    await api.prefs.setString('dl', jsonEncode(list.map((d) => d.toJson()).toList()));
  }

  // ---------- sorgular ----------
  String path(Dl d) => '${root.path}/${d.file}';
  String? abs(String? rel) => rel == null ? null : '${root.path}/$rel';
  String subPath(Dl d, int idx) => '${root.path}/${d.subs['$idx']}';

  Dl? of(String id) {
    for (final d in list) {
      if (d.id == id) return d;
    }
    return null;
  }

  Dl? doneFor(String id) {
    final d = of(id);
    return d != null && d.state == DlState.done ? d : null;
  }

  bool get hasDone => list.any((d) => d.state == DlState.done);
  int get usedBytes => list.fold(0, (a, d) => a + d.got);

  bool get autoDelete => api.prefs.getBool('dlauto') ?? false;
  set autoDelete(bool v) {
    api.prefs.setBool('dlauto', v);
    notifyListeners();
  }

  String get defaultQuality => api.prefs.getString('dlq') ?? 'orig';

  /// Çevrimdışı oynatıcı için: aynı dizide sıradaki indirilmiş bölüm.
  J? nextDownloaded(J it) {
    if (it['Type'] != 'Episode') return null;
    final eps = list
        .where((d) => d.state == DlState.done && d.isEpisode && d.item['SeriesId'] == it['SeriesId'])
        .toList()
      ..sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.index.compareTo(b.index);
      });
    final k = eps.indexWhere((d) => d.id == it['Id']);
    return k >= 0 && k + 1 < eps.length ? eps[k + 1].item : null;
  }

  /// İndirilmiş dosyayı oynatmak için öğenin kopyası: akış listesi dosyanın gerçek içeriğine göre.
  J localItem(Dl d) {
    final it = J.from(jsonDecode(jsonEncode(d.item)) as Map);
    final srcs = (it['MediaSources'] as List?) ?? const [];
    if (srcs.isEmpty) return it;
    final ms = J.from(srcs.first as Map);
    var st = ((ms['MediaStreams'] as List?) ?? const []).map((e) => J.from(e as Map)).toList();
    bool have(J s) => d.subs.containsKey('${s['Index']}');
    if (d.quality == 'small') {
      st = st
          .where((s) =>
              s['Type'] == 'Video' ||
              (s['Type'] == 'Audio' && (d.audio == null || s['Index'] == d.audio)) ||
              (s['Type'] == 'Subtitle' && have(s)))
          .toList();
      // küçük kopyada altyazılar dosyanın içinde değil, yanında
      for (final s in st) {
        if (s['Type'] == 'Subtitle') s['IsExternal'] = true;
      }
      if (d.audio != null) ms['DefaultAudioStreamIndex'] = d.audio;
    } else {
      // dış altyazılar sadece indirildiyse; resim altyazılar çevrimdışı gömülemez
      st = st
          .where((s) =>
              s['Type'] != 'Subtitle' ||
              (s['IsExternal'] == true ? have(s) : s['IsTextSubtitleStream'] == true))
          .toList();
    }
    ms['MediaStreams'] = st;
    it['MediaSources'] = [ms];
    return it;
  }

  // ---------- kuyruk ----------
  /// [items] film ya da bölümler (MediaSources olmasa da olur; indirme başlarken tam hâli alınır).
  void add(List<J> items, String quality) {
    api.prefs.setString('dlq', quality);
    for (final it in items) {
      final id = '${it['Id']}';
      final old = of(id);
      if (old != null) {
        if (old.state == DlState.failed || old.state == DlState.paused) {
          old.state = DlState.queued;
          old.err = '';
        }
        continue;
      }
      list.add(Dl(id, it, quality));
    }
    _save();
    notifyListeners();
    kick();
  }

  void kick() {
    if (!_ready || _running) return;
    _loop();
  }

  Future<void> _loop() async {
    _running = true;
    try {
      while (true) {
        Dl? next;
        for (final d in list) {
          if (d.state == DlState.queued) {
            next = d;
            break;
          }
        }
        if (next == null) break;
        final ok = await _run(next);
        if (!ok) break; // ağ yok: sonra tekrar denenir
      }
    } finally {
      _running = false;
    }
  }

  void pause(Dl d) {
    if (d.state == DlState.queued || d.state == DlState.running) {
      d.state = DlState.paused;
      if (_cur == d) _client?.close();
      _save();
      notifyListeners();
    }
  }

  void resume(Dl d) {
    if (d.state == DlState.paused || d.state == DlState.failed) {
      d.state = DlState.queued;
      d.err = '';
      _save();
      notifyListeners();
      kick();
    }
  }

  /// Ağ geldi / uygulama öne geldi: duraklatılmamış yarım indirmeleri sürdür.
  void retryFailed() {
    for (final d in list) {
      if (d.state == DlState.failed && d.err.startsWith('Bağlantı')) {
        d.state = DlState.queued;
        d.err = '';
      }
    }
    notifyListeners();
    kick();
  }

  Future<void> remove(Dl d) async {
    list.remove(d);
    if (_cur == d) _client?.close();
    await _save();
    notifyListeners();
    try {
      await Directory('${root.path}/${d.id}').delete(recursive: true);
    } catch (_) {}
  }

  int _estimate(J it) {
    final secs = ((it['RunTimeTicks'] as num?) ?? 0) / 1e7;
    return (secs * (smallVideoBps + smallAudioBps) / 8).round();
  }

  /// İndirmeden önce kullanıcıya gösterilecek tahmini boyut.
  int sizeOf(List<J> items, String q) {
    var s = 0;
    for (final it in items) {
      if (q == 'small') {
        s += _estimate(it);
      } else {
        final srcs = (it['MediaSources'] as List?) ?? const [];
        final sz = srcs.isNotEmpty ? (srcs.first['Size'] as num?) : null;
        s += sz?.toInt() ?? 0;
      }
    }
    return s;
  }

  Future<void> _fetch(String url, File f) async {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode >= 400) throw ApiError(r.statusCode);
    await f.writeAsBytes(r.bodyBytes, flush: true);
  }

  /// true: devam edilebilir; false: ağ yok, kuyruk dursun.
  Future<bool> _run(Dl d) async {
    _cur = d;
    d.state = DlState.running;
    d.err = '';
    notifyListeners();
    final dir = Directory('${root.path}/${d.id}');
    try {
      await dir.create(recursive: true);
      // tam öğe (MediaSources, Trickplay vb.)
      if (((d.item['MediaSources'] as List?) ?? const []).isEmpty || d.item['_full'] != true) {
        final full = await api.item(d.id);
        full['_full'] = true;
        d.item = full;
      }
      final srcs = (d.item['MediaSources'] as List?) ?? const [];
      if (srcs.isEmpty) throw Exception('Bu içerik indirilemiyor (medya kaynağı yok)');
      final ms = J.from(srcs.first as Map);
      final msId = '${ms['Id']}';
      final streams = ((ms['MediaStreams'] as List?) ?? const []).map((e) => J.from(e as Map)).toList();
      final small = d.quality == 'small';
      d.audio ??= (ms['DefaultAudioStreamIndex'] as num?)?.toInt();

      // resimler
      final w = wideImg(d.item).url;
      if (d.wide == null && w.isNotEmpty) {
        try {
          await _fetch('$w&ApiKey=${api.token}', File('${dir.path}/wide.jpg'));
          d.wide = '${d.id}/wide.jpg';
        } catch (_) {}
      }
      if (d.poster == null) {
        final t = (d.item['ImageTags'] as Map?)?['Primary'];
        final sid = d.item['SeriesId'], st = d.item['SeriesPrimaryImageTag'];
        final p = d.isEpisode && sid != null && st != null
            ? api.image('$sid', 'Primary', tag: '$st', w: 400)
            : (t != null ? api.image(d.id, 'Primary', tag: '$t', w: 400) : null);
        if (p != null) {
          try {
            await _fetch('$p&ApiKey=${api.token}', File('${dir.path}/poster.jpg'));
            d.poster = '${d.id}/poster.jpg';
          } catch (_) {}
        }
      }
      // altyazılar: orijinalde dosyanın içindekiler zaten var, dıştakiler ayrıca iner;
      // küçük kopyada tüm yazı altyazılar ayrı .srt olarak iner.
      for (final s in streams) {
        if (s['Type'] != 'Subtitle' || s['IsTextSubtitleStream'] != true) continue;
        if (!small && s['IsExternal'] != true) continue;
        final idx = (s['Index'] as num).toInt();
        if (d.subs.containsKey('$idx')) continue;
        try {
          await _fetch('${api.url}/Videos/${d.id}/$msId/Subtitles/$idx/0/Stream.srt?ApiKey=${api.token}',
              File('${dir.path}/sub_$idx.srt'));
          d.subs['$idx'] = '${d.id}/sub_$idx.srt';
        } catch (_) {}
      }
      await _save();

      // video
      final ext = small ? 'mkv' : _ext(ms);
      d.file = '${d.id}/video.$ext';
      final f = File(path(d));
      final url = small
          ? '${api.url}/Videos/${d.id}/stream.mkv?MediaSourceId=$msId&ApiKey=${api.token}'
              '&DeviceId=${api.deviceId}&PlaySessionId=dl${d.id}'
              '&VideoCodec=h264&AudioCodec=aac&VideoBitrate=$smallVideoBps&AudioBitrate=$smallAudioBps'
              '&MaxWidth=1280&MaxHeight=720&MaxAudioChannels=2&TranscodingMaxAudioChannels=2'
              '${d.audio != null ? '&AudioStreamIndex=${d.audio}' : ''}'
          : '${api.url}/Videos/${d.id}/stream?static=true&MediaSourceId=$msId&ApiKey=${api.token}';
      var start = 0;
      if (await f.exists()) {
        if (small) {
          await f.delete(); // dönüştürülen akış kaldığı yerden sürdürülemez
        } else {
          start = await f.length();
        }
      }
      final req = http.Request('GET', Uri.parse(url));
      if (start > 0) req.headers['Range'] = 'bytes=$start-';
      final c = http.Client();
      _client = c;
      final r = await c.send(req);
      if (r.statusCode >= 400) throw ApiError(r.statusCode);
      if (start > 0 && r.statusCode != 206) start = 0;
      final len = r.contentLength ?? 0;
      d.got = start;
      d.total = len > 0 ? start + len : (small ? _estimate(d.item) : ((ms['Size'] as num?)?.toInt() ?? 0));
      final sink = f.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
      var last = DateTime.now();
      try {
        await for (final chunk in r.stream) {
          if (d.state != DlState.running || !list.contains(d)) throw _Cancelled();
          sink.add(chunk);
          d.got += chunk.length;
          final now = DateTime.now();
          if (now.difference(last).inMilliseconds > 700) {
            last = now;
            notifyListeners();
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        c.close();
        _client = null;
      }
      if (d.state != DlState.running || !list.contains(d)) throw _Cancelled();
      if (len > 0 && d.got < start + len) throw const SocketException('eksik');
      d.total = d.got;
      d.state = DlState.done;
      await _save();
      notifyListeners();
      return true;
    } on _Cancelled {
      await _save();
      notifyListeners();
      return true;
    } catch (e) {
      if (!list.contains(d) || d.state == DlState.paused) {
        notifyListeners();
        return true;
      }
      final net = e is SocketException || e is TimeoutException || e is http.ClientException;
      d.state = DlState.failed;
      d.err = net ? 'Bağlantı kesildi; uygulama açıkken kendiliğinden devam eder' : '$e';
      await _save();
      notifyListeners();
      return !net;
    } finally {
      _cur = null;
    }
  }

  String _ext(J ms) {
    final p = '${ms['Path'] ?? ''}';
    final dot = p.lastIndexOf('.');
    if (dot > 0 && p.length - dot <= 5) return p.substring(dot + 1).toLowerCase();
    final c = '${ms['Container'] ?? 'mkv'}'.split(',').first.trim();
    return c.isEmpty ? 'mkv' : c;
  }

  // ---------- çevrimdışı ilerleme ----------
  Map<String, dynamic> get _pending {
    try {
      return J.from(jsonDecode(api.prefs.getString('dlpend') ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  /// İndirilmiş dosya izlenirken kaldığın yer: hem yerelde saklanır hem eşitleme kuyruğuna girer.
  void progress(String id, int posTicks) {
    final d = of(id);
    final run = ((d?.item['RunTimeTicks'] as num?) ?? 0).toInt();
    final played = run > 0 && posTicks >= run * .9;
    if (d != null) {
      final ud = J.from((d.item['UserData'] as Map?) ?? const {});
      ud['PlaybackPositionTicks'] = played ? 0 : posTicks;
      if (played) ud['Played'] = true;
      d.item['UserData'] = ud;
    }
    final p = _pending;
    p[id] = {'t': played ? 0 : posTicks, 'p': played, 'at': DateTime.now().toUtc().toIso8601String()};
    api.prefs.setString('dlpend', jsonEncode(p));
    _save();
  }

  /// Oynatıcı kapanınca: "izleyince sil" açıksa izlenmiş dosyaları kaldır.
  Future<void> cleanupWatched() async {
    if (!autoDelete) return;
    for (final d in list.where((d) => d.state == DlState.done && d.watched).toList()) {
      await remove(d);
    }
  }

  bool _syncing = false;

  /// Bekleyen çevrimdışı ilerlemeleri Jellyfin'e yaz. Sunucuda daha yeni bir izleme varsa ona dokunmaz.
  Future<void> sync() async {
    if (_syncing || !api.loggedIn) return;
    _syncing = true;
    try {
      final p = _pending;
      for (final id in p.keys.toList()) {
        final e = J.from(p[id] as Map);
        try {
          final cur = await api.item(id);
          final last = DateTime.tryParse('${(cur['UserData'] as Map?)?['LastPlayedDate'] ?? ''}');
          final mine = DateTime.tryParse('${e['at']}');
          final newer = last != null && mine != null && last.isAfter(mine);
          if (!newer) {
            final body = {
              'PlaybackPositionTicks': e['t'],
              'Played': e['p'] == true || (cur['UserData'] as Map?)?['Played'] == true,
              'LastPlayedDate': e['at'],
            };
            try {
              await api.post('/UserItems/$id/UserData?userId=${api.uid}', body);
            } on ApiError catch (x) {
              if (x.code != 404 && x.code != 405) rethrow;
              await api.post('/Sessions/Playing/Stopped', {'ItemId': id, 'PositionTicks': e['t']});
              if (e['p'] == true) await api.post('/Users/${api.uid}/PlayedItems/$id');
            }
          }
          p.remove(id);
          await api.prefs.setString('dlpend', jsonEncode(p));
        } on ApiError catch (x) {
          if (x.code == 404) {
            p.remove(id); // öğe sunucudan silinmiş
            await api.prefs.setString('dlpend', jsonEncode(p));
          } else {
            break;
          }
        } catch (_) {
          break; // çevrimdışı
        }
      }
      if (p.isEmpty) refreshBus.value++;
    } finally {
      _syncing = false;
    }
  }
}

String fmtBytes(num b) {
  if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(b >= 1e10 ? 0 : 1)} GB';
  if (b >= 1e6) return '${(b / 1e6).round()} MB';
  if (b >= 1e3) return '${(b / 1e3).round()} KB';
  return '$b B';
}
