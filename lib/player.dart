import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'downloads.dart';
import 'main.dart' show allowAppOrientations;
import 'util.dart';
import 'widgets.dart';

class _Seg {
  final String type;
  final Duration a, b;
  bool done = false;
  _Seg(this.type, this.a, this.b);
}

const _lmap = {
  'tr': ['tur', 'tr'],
  'en': ['eng', 'en'],
  'fa': ['per', 'fas', 'fa'],
  'ar': ['ara', 'ar'],
  'de': ['ger', 'deu', 'de'],
  'fr': ['fre', 'fra', 'fr'],
  'es': ['spa', 'es'],
  'it': ['ita', 'it'],
  'pt': ['por', 'pt'],
  'ru': ['rus', 'ru'],
};

class PlayerScreen extends StatefulWidget {
  final J item;
  final bool restart;
  const PlayerScreen({super.key, required this.item, this.restart = false});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

/// Oynatıcı: mpv (media_kit). MKV dahil dosyalar sunucuda dönüştürülmeden doğrudan oynar;
/// altyazı ve ses dosyanın kendi zamanlamasıyla gelir. Sadece resim altyazılar (PGS vb.)
/// için sunucu altyazıyı videoya gömer (HLS).
class _PlayerScreenState extends State<PlayerScreen> {
  final api = Api.I;
  late final Player player = Player(configuration: PlayerConfiguration(bufferSize: 64 * 1024 * 1024));
  late final VideoController vctl = VideoController(player);
  final List<StreamSubscription> subs = [];

  J? it, ms;
  Dl? loc; // indirilmiş dosyadan oynatılıyorsa
  J? tp; // trickplay bilgisi
  String tpW = '';
  Timer? cdT; // sonraki bölüm geri sayımı
  int cd = 0;
  String? cdOff; // geri sayımı iptal edilen bölüm
  // 3.0: bölüm şeridi, görüntü paneli, parlaklık
  bool epsOpen = false, viewOpen = false, tracksOpen = false, night = false, dragBright = false, hud = false, brightTouched = false;
  num? epsSeason;
  double? bright;
  Timer? hudT;
  final eq = <String, double>{'brightness': 0, 'contrast': 0, 'saturation': 0, 'gamma': 0};
  static const _eqNames = {'brightness': 'Parlaklık', 'contrast': 'Kontrast', 'saturation': 'Doygunluk', 'gamma': 'Gama'};
  String sid = '';
  bool transcode = false, burn = false, closed = false, ready = false;
  int? audioIdx, subIdx, defAudio;
  List<_Seg> segs = [];
  List<J> eps = [];
  J? nextEp;
  String err = '';
  bool ui = true, ended = false, showAge = false, dragging = false;
  double dragV = 0;
  Duration pos = Duration.zero, dur = Duration.zero, painted = Duration.zero;
  bool playing = false, buffering = true;
  Timer? hideT, repT, ageT;
  Duration subDelay = Duration.zero; // + geç, − erken
  String? shownCue;
  Offset tapAt = Offset.zero;
  double speed = 1;
  int openTok = 0;

  List<J> get streams =>
      ((ms?['MediaStreams'] as List?) ?? const []).map((e) => J.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    subs.addAll([
      player.stream.position.listen((p) {
        pos = p;
        _onPos();
      }),
      player.stream.duration.listen((d) => dur = d),
      player.stream.playing.listen((p) {
        if (p == playing) return;
        playing = p;
        if (ready) _report('/Progress');
        if (mounted) setState(() {});
        if (p) _armHide();
      }),
      player.stream.buffering.listen((b) {
        if (mounted) setState(() => buffering = b);
      }),
      player.stream.completed.listen((c) {
        if (c && ready && !ended) {
          ended = true;
          _onEnded();
        }
      }),
      player.stream.subtitle.listen((l) {
        final t = l.where((s) => s.trim().isNotEmpty).join('\n').trim();
        final v = t.isEmpty ? null : t;
        if (v != shownCue && mounted) setState(() => shownCue = v);
      }),
      player.stream.error.listen((e) {
        if (!mounted) return;
        if (!ready && err.isEmpty) setState(() => err = 'Video açılamadı.\n\n$e\n\n${_info()}');
      }),
    ]);
    _start(widget.item, restart: widget.restart);
  }

  @override
  void dispose() {
    hideT?.cancel();
    repT?.cancel();
    ageT?.cancel();
    cdT?.cancel();
    hudT?.cancel();
    if (brightTouched) ScreenBrightness().resetScreenBrightness().catchError((_) {});
    for (final s in subs) {
      s.cancel();
    }
    if (!closed) _stopCurrent();
    player.dispose();
    WakelockPlus.disable();
    Downloads.I.cleanupWatched();
    Downloads.I.sync();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    allowAppOrientations();
    super.dispose();
  }

  void _onPos() {
    if (!mounted) return;
    // giriş / jenerik otomatik atla
    final s = _activeSeg();
    if (s != null && api.autoSkip && !s.done && ready) {
      s.done = true;
      player.seek(s.b);
    }
    _checkCountdown(s);
    // ekranı en fazla ~4 kez/sn yenile
    if (dragging) return;
    if ((pos - painted).abs() >= const Duration(milliseconds: 250) || pos < painted) {
      painted = pos;
      setState(() {});
    }
  }

  // =================== akış ===================
  String _newSid() {
    final r = Random();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<void> _start(J base, {bool restart = false}) async {
    await _stopCurrent();
    if (!mounted) return;
    cdT?.cancel();
    cdT = null;
    setState(() {
      tp = null;
      err = '';
      ended = false;
      segs = [];
      nextEp = null;
      buffering = true;
      pos = Duration.zero;
      dur = Duration.zero;
      burn = false;
      shownCue = null;
    });
    J full;
    final id0 = '${base['Id']}';
    loc = Downloads.I.doneFor(id0);
    if (loc != null) {
      // indirilmiş dosya: sunucuya hiç gitmeden oynar; internet varsa sadece kaldığın yeri sor
      full = Downloads.I.localItem(loc!);
      try {
        final srv = await api.item(id0).timeout(const Duration(seconds: 4));
        if (srv['UserData'] != null) full['UserData'] = srv['UserData'];
      } catch (_) {}
    } else {
      try {
        full = await api.item(id0);
      } catch (_) {
        full = base;
      }
    }
    if (!mounted) return;
    final sources = (full['MediaSources'] as List?) ?? const [];
    if (sources.isEmpty) {
      setState(() => err = 'Bu içerik oynatılamıyor (medya kaynağı yok).');
      return;
    }
    it = full;
    ms = J.from(sources.first as Map);
    sid = _newSid();
    final aud = streams.where((s) => s['Type'] == 'Audio').toList();
    defAudio = (ms!['DefaultAudioStreamIndex'] as num?)?.toInt() ??
        (aud.isNotEmpty ? (aud.first['Index'] as num).toInt() : null);
    audioIdx = defAudio;
    subIdx = _autoSub();
    final startAt = restart ? Duration.zero : ticks((full['UserData'] as Map?)?['PlaybackPositionTicks'] ?? 0);
    _setupTrickplay();
    await _open(startAt);
    _loadSegments();
    _loadEpisodes();
    // Netflix/Disney+ tarzı yaş kartı
    ageT?.cancel();
    if (mounted) setState(() => showAge = true);
    ageT = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => showAge = false);
    });
  }

  J? get _video {
    for (final s in streams) {
      if (s['Type'] == 'Video') return s;
    }
    return null;
  }

  Future<void> _open(Duration startAt) async {
    final tok = ++openTok;
    final id = '${it!['Id']}', msId = '${ms!['Id']}';
    transcode = burn && loc == null;
    final q = 'MediaSourceId=$msId&DeviceId=${api.deviceId}&ApiKey=${api.token}&PlaySessionId=$sid';
    final url = transcode
        ? '${api.url}/Videos/$id/master.m3u8?$q&VideoCodec=h264&AudioCodec=aac&TranscodingMaxAudioChannels=2'
            '&SegmentContainer=ts&MinSegments=1&BreakOnNonKeyFrames=True&MaxStreamingBitrate=20000000'
            '${audioIdx != null ? '&AudioStreamIndex=$audioIdx' : ''}'
            '${subIdx != null ? '&SubtitleStreamIndex=$subIdx&SubtitleMethod=Encode' : ''}'
        : loc != null
            ? Downloads.I.path(loc!)
            : '${api.url}/Videos/$id/stream?static=true&$q';
    ready = false;
    if (mounted) setState(() => buffering = true);
    try {
      await player.open(Media(url), play: false);
    } catch (e) {
      if (mounted && tok == openTok) setState(() => err = 'Video açılamadı.\n\n$e\n\n${_info()}');
      return;
    }
    // süre gelene kadar bekle (dosya açıldı demektir)
    if (player.state.duration <= Duration.zero) {
      try {
        await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 30));
      } catch (_) {}
    }
    if (!mounted || tok != openTok) return;
    if (player.state.duration <= Duration.zero && err.isEmpty) {
      setState(() => err = 'Video açılamadı (sunucudan cevap gelmedi).\n\n${_info()}');
      return;
    }
    // parça listesi gelsin
    if (player.state.tracks.audio.length <= 2) {
      try {
        await player.stream.tracks.firstWhere((t) => t.audio.length > 2).timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    if (!mounted || tok != openTok) return;
    if (startAt > const Duration(seconds: 1)) await player.seek(startAt);
    if (!transcode) await _applyAudio();
    await _applySub();
    await _applyDelay();
    await player.setRate(speed);
    await player.play();
    ready = true;
    _report('');
    repT?.cancel();
    repT = Timer.periodic(const Duration(seconds: 10), (_) => _report('/Progress'));
    _armHide();
  }

  // ---- Jellyfin akış sırası → mpv parça sırası (aynı dosya, aynı sıra) ----
  List<J> _embedded(String type) =>
      streams.where((s) => s['Type'] == type && s['IsExternal'] != true).toList();

  Future<void> _applyAudio() async {
    final k = _embedded('Audio').indexWhere((s) => s['Index'] == audioIdx);
    final real = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (k >= 0 && k < real.length) await player.setAudioTrack(real[k]);
  }

  Future<void> _applySub() async {
    if (burn || subIdx == null) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      if (mounted) setState(() => shownCue = null);
      return;
    }
    final s = streams.firstWhere((x) => x['Index'] == subIdx, orElse: () => <String, dynamic>{});
    if (s.isEmpty) return;
    if (s['IsExternal'] == true) {
      // yan dosya altyazı: indirildiyse telefondan, yoksa sunucudan
      await player.setSubtitleTrack(SubtitleTrack.uri(
        loc != null
            ? Downloads.I.subPath(loc!, subIdx!)
            : '${api.url}/Videos/${it!['Id']}/${ms!['Id']}/Subtitles/$subIdx/0/Stream.srt?ApiKey=${api.token}',
        title: '${s['DisplayTitle'] ?? s['Title'] ?? 'Altyazı'}',
        language: '${s['Language'] ?? ''}',
      ));
    } else {
      final k = _embedded('Subtitle').indexWhere((x) => x['Index'] == subIdx);
      final real = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
      if (k >= 0 && k < real.length) await player.setSubtitleTrack(real[k]);
    }
  }

  Future<void> _applyDelay() async {
    try {
      await (player.platform as dynamic).setProperty('sub-delay', (subDelay.inMilliseconds / 1000).toStringAsFixed(3));
    } catch (_) {}
  }

  String _info() {
    final v = _video, m = ms;
    final a = streams.where((s) => s['Index'] == audioIdx).toList();
    final src = [
      '${m?['Container'] ?? '?'}'.toUpperCase(),
      '${v?['Codec'] ?? '?'}'.toUpperCase(),
      if (v?['Width'] != null) '${v?['Width']}×${v?['Height']}',
      if (v?['VideoRangeType'] != null) '${v?['VideoRangeType']}',
      if (a.isNotEmpty) 'Ses: ${'${a.first['Codec'] ?? ''}'.toUpperCase()} ${a.first['Channels'] ?? ''}ch',
    ].join(' • ');
    final how = loc != null
        ? 'İndirilen dosya (${loc!.quality == 'small' ? 'küçük kopya' : 'orijinal'}, internet gerekmez)'
        : transcode
            ? 'Sunucu resim altyazıyı videoya gömüyor (HLS)'
            : 'Doğrudan oynatma (mpv, sunucuda dönüştürme yok)';
    return 'Kaynak: $src\nOynatma: $how'
        '\nGörüntü: ${player.state.width ?? 0}×${player.state.height ?? 0}';
  }

  Future<void> _report(String kind) async {
    final i = it;
    if (i == null || !ready) return;
    if (loc != null) Downloads.I.progress('${i['Id']}', player.state.position.inMicroseconds * 10);
    final body = <String, dynamic>{
      'ItemId': i['Id'],
      'MediaSourceId': ms?['Id'],
      'PlaySessionId': sid,
      'PositionTicks': player.state.position.inMicroseconds * 10,
      'IsPaused': !player.state.playing,
      'CanSeek': true,
      'PlayMethod': transcode ? 'Transcode' : 'DirectPlay',
      if (audioIdx != null) 'AudioStreamIndex': audioIdx,
      if (subIdx != null) 'SubtitleStreamIndex': subIdx,
    };
    try {
      await api.post('/Sessions/Playing$kind', body);
    } catch (_) {}
  }

  Future<void> _stopCurrent() async {
    repT?.cancel();
    if (it == null) return;
    await _report('/Stopped');
    if (transcode) {
      api.delete('/Videos/ActiveEncodings?DeviceId=${api.deviceId}&PlaySessionId=$sid').catchError((_) {});
    }
    ready = false;
    try {
      await player.stop();
    } catch (_) {}
  }

  /// Sunucu tarafı gömme açılıp kapanınca akışı kaldığı yerden yeniden aç
  Future<void> _reopen() async {
    final at = player.state.position;
    await _report('/Stopped');
    if (transcode) {
      api.delete('/Videos/ActiveEncodings?DeviceId=${api.deviceId}&PlaySessionId=$sid').catchError((_) {});
    }
    sid = _newSid();
    await _open(at);
  }

  _Seg? _activeSeg() {
    for (final s in segs) {
      if (pos >= s.a && pos < s.b - const Duration(seconds: 1)) return s;
    }
    return null;
  }

  // =================== altyazı / ses seçimi ===================
  int? _autoSub() {
    final codes = _lmap[api.subLang];
    if (codes == null) return null;
    final a = streams.where((s) => s['Index'] == audioIdx).toList();
    if (a.isNotEmpty && codes.contains('${a.first['Language']}'.toLowerCase())) return null;
    final c = streams
        .where((s) =>
            s['Type'] == 'Subtitle' &&
            s['IsTextSubtitleStream'] == true &&
            codes.contains('${s['Language']}'.toLowerCase()) &&
            s['IsForced'] != true)
        .toList();
    if (c.isEmpty) return null;
    final sdh = RegExp(r'sdh|hearing|\bhi\b', caseSensitive: false);
    final pick = c.firstWhere((s) => s['IsDefault'] == true,
        orElse: () => c.firstWhere((s) => !sdh.hasMatch('${s['DisplayTitle'] ?? s['Title'] ?? ''}'),
            orElse: () => c.first));
    return (pick['Index'] as num).toInt();
  }

  Future<void> _selectSub(int? idx) async {
    final s = idx == null ? null : streams.firstWhere((x) => x['Index'] == idx, orElse: () => <String, dynamic>{});
    final needBurn = s != null && s.isNotEmpty && s['IsTextSubtitleStream'] != true;
    final wasBurn = burn;
    setState(() {
      subIdx = idx;
      burn = needBurn;
    });
    if (needBurn || wasBurn) {
      await _reopen(); // resim altyazı (PGS vb.) → sunucu videoya gömer; ya da gömmeden çık
    } else {
      await _applySub();
    }
    _report('/Progress');
  }

  Future<void> _selectAudio(int idx) async {
    if (idx == audioIdx) return;
    setState(() => audioIdx = idx);
    if (transcode) {
      await _reopen();
    } else {
      await _applyAudio(); // mpv'de anında değişir
    }
    _report('/Progress');
  }

  // =================== giriş/jenerik, bölümler ===================
  Future<void> _loadSegments() async {
    final id = '${it!['Id']}';
    var s = <_Seg>[];
    try {
      final r = await api.get('/MediaSegments/$id');
      s = ((r?['Items'] as List?) ?? const [])
          .map((x) => J.from(x as Map))
          .where((x) => x['Type'] == 'Intro' || x['Type'] == 'Outro')
          .map((x) => _Seg('${x['Type']}', ticks(x['StartTicks']), ticks(x['EndTicks'])))
          .toList();
    } catch (_) {}
    if (s.isEmpty) {
      try {
        final r = await api.get('/Episode/$id/IntroTimestamps/v1');
        if (r?['Valid'] == true) {
          s = [
            _Seg('Intro', Duration(milliseconds: ((r['IntroStart'] as num) * 1000).round()),
                Duration(milliseconds: ((r['IntroEnd'] as num) * 1000).round()))
          ];
        }
      } catch (_) {}
    }
    if (mounted && '${it?['Id']}' == id) setState(() => segs = s);
  }

  Future<void> _loadEpisodes() async {
    final i = it!;
    if (i['Type'] != 'Episode' || i['SeriesId'] == null) return;
    try {
      final a = await api.items('/Shows/${i['SeriesId']}/Episodes?UserId=${api.uid}&Fields=Overview');
      final k = a.indexWhere((e) => e['Id'] == i['Id']);
      if (mounted && it?['Id'] == i['Id']) {
        setState(() {
          eps = a;
          nextEp = (k >= 0 && k + 1 < a.length) ? a[k + 1] : null;
        });
      }
    } catch (_) {
      // çevrimdışı: sıradaki indirilmiş bölüm
      final n = Downloads.I.nextDownloaded(i);
      if (mounted && it?['Id'] == i['Id']) setState(() => nextEp = n);
    }
  }

  // =================== sahne önizlemesi (Jellyfin trickplay) ===================
  void _setupTrickplay() {
    tp = null;
    if (loc != null) return;
    final m = it?['Trickplay'];
    if (m is! Map || m.isEmpty) return;
    final byMs = (m['${ms?['Id']}'] ?? m.values.first);
    if (byMs is! Map || byMs.isEmpty) return;
    // ~320 piksele en yakın genişlik
    String best = '';
    var diff = 1 << 30;
    for (final k in byMs.keys) {
      final w = int.tryParse('$k') ?? 0;
      if (w > 0 && (w - 320).abs() < diff) {
        diff = (w - 320).abs();
        best = '$k';
      }
    }
    if (best.isEmpty || byMs[best] is! Map) return;
    tp = J.from(byMs[best] as Map);
    tpW = best;
  }

  Widget _thumb(double secs) {
    final t = tp!;
    int n(String k, int d) => (t[k] as num?)?.toInt() ?? d;
    final interval = max(1, n('Interval', 10000)), tw = max(1, n('TileWidth', 10)), th = max(1, n('TileHeight', 10));
    final cnt = max(1, n('ThumbnailCount', 1));
    final w = n('Width', 320).toDouble(), h = max(1, n('Height', 180)).toDouble();
    final k = ((secs * 1000) ~/ interval).clamp(0, cnt - 1);
    final per = tw * th, tile = k ~/ per, col = (k % per) % tw, row = (k % per) ~/ tw;
    const dw = 176.0;
    final sc = dw / w, dh = h * sc;
    final url = '${api.url}/Videos/${it!['Id']}/Trickplay/$tpW/$tile.jpg?MediaSourceId=${ms!['Id']}&ApiKey=${api.token}';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: dw + 4,
        height: dh + 4,
        decoration: BoxDecoration(
            color: Colors.black, border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(-col * w * sc, -row * h * sc),
              child: SizedBox(
                width: tw * w * sc,
                height: th * h * sc,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topLeft,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(fmt(Duration(milliseconds: (secs * 1000).round())),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, shadows: [Shadow(blurRadius: 4)])),
    ]);
  }

  // =================== sonraki bölüm geri sayımı ===================
  void _checkCountdown(_Seg? seg) {
    final n = nextEp, i = it;
    if (n == null || i == null || !ready || dur <= Duration.zero) return;
    final left = dur - pos;
    final want = seg?.type == 'Outro' || left < const Duration(seconds: 15);
    if (!want) {
      if (cdT != null) {
        cdT!.cancel();
        cdT = null;
      }
      return;
    }
    if (cdT != null || !api.autoNext || cdOff == '${i['Id']}' || !playing) return;
    cd = min(10, max(1, left.inSeconds));
    cdT = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (!playing) return;
      if (--cd <= 0) {
        t.cancel();
        cdT = null;
        final nx = nextEp;
        if (nx != null) _start(nx, restart: true);
        return;
      }
      setState(() {});
    });
  }

  void _cancelCountdown() {
    cdT?.cancel();
    cdT = null;
    cdOff = '${it?['Id']}';
    setState(() {});
  }

  void _onEnded() {
    if (nextEp != null) {
      _start(nextEp!, restart: true);
    } else {
      _close();
    }
  }

  Future<void> _close() async {
    if (closed) return;
    closed = true;
    await _stopCurrent();
    if (mounted) Navigator.of(context).pop();
  }

  // =================== kontroller ===================
  void _armHide() {
    hideT?.cancel();
    hideT = Timer(const Duration(seconds: 4), () {
      if (mounted && playing && !dragging && !tracksOpen) setState(() => ui = false);
    });
  }

  void _showUI() {
    setState(() => ui = true);
    _armHide();
  }

  void _togglePlay() {
    player.playOrPause();
    _showUI();
  }

  void _seekBy(int s) {
    var t = player.state.position + Duration(seconds: s);
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur;
    player.seek(t);
    _showUI();
  }

  void _toggleTracks() {
    setState(() {
      tracksOpen = !tracksOpen;
      viewOpen = false;
      ui = true;
    });
    if (tracksOpen) {
      hideT?.cancel();
    } else {
      _armHide();
    }
  }

  void _setNight(bool v) {
    night = v;
    try {
      (player.platform as dynamic).setProperty('af', v ? 'lavfi=[dynaudnorm=f=200:g=11:p=0.9]' : '');
    } catch (_) {}
    setState(() {});
  }

  static const _speeds = [.75, 1.0, 1.25, 1.5, 2.0];
  static String _num(double v) => (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v').replaceAll('.', ',');

  /// A · Cam: kapsülün altında açılan iki sütunlu cam menü (Ses | Altyazı)
  Widget _tracksPanel() {
    final auds = streams.where((s) => s['Type'] == 'Audio').toList();
    final subs = streams.where((s) => s['Type'] == 'Subtitle').toList();
    String lbl(J s) => '${s['DisplayTitle'] ?? s['Language'] ?? 'Parça ${s['Index']}'}';
    const head = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: Color(0x80F5F5F7));
    const div = Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, thickness: 1, color: Color(0x14FFFFFF)));
    Widget h(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: Text(t, style: head));
    Widget row(Widget left, {Widget? right, VoidCallback? onTap}) => Pressable(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.transparent,
            child: Row(children: [Expanded(child: left), if (right != null) right]),
          ),
        );
    Widget opt(String t, bool sel, VoidCallback f, {String? sub}) => row(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 11, color: Color(0x80F5F5F7))),
          ]),
          right: sel ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFFF5F5F7)) : null,
          onTap: f,
        );
    Widget val(String t) => Text(t, style: const TextStyle(fontSize: 14, color: Color(0x8CF5F5F7)));
    Widget step(IconData i, String l, VoidCallback f) => Semantics(
          button: true,
          label: l,
          child: Pressable(
            onTap: () {
              HapticFeedback.selectionClick();
              f();
            },
            child: Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(color: Colors.white.withAlpha(30), shape: BoxShape.circle),
              child: Icon(i, size: 16, color: const Color(0xFFF5F5F7)),
            ),
          ),
        );
    final ms = subDelay.inMilliseconds;
    final delay = ms == 0 ? '0 sn' : '${ms > 0 ? '+' : '−'}${_num((ms.abs() / 1000))} sn';
    void adj(int d) {
      setState(() => subDelay += Duration(milliseconds: d));
      _applyDelay();
    }

    final scr = MediaQuery.sizeOf(context);
    final w = min(440.0, scr.width - 32);
    return Positioned(
      right: scr.width > 700 ? 52 : 16,
      top: MediaQuery.paddingOf(context).top + 74,
      width: w,
      child: GestureDetector(
        onTap: () {},
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: scr.height - MediaQuery.paddingOf(context).top - 90),
          child: Container(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(22)),
              boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 20))],
            ),
            child: Glass(
              radius: 22,
              color: const Color(0xDB202026),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        h('SES'),
                        for (final a in auds)
                          opt(lbl(a), a['Index'] == audioIdx, () {
                            setState(() => tracksOpen = false);
                            _armHide();
                            _selectAudio((a['Index'] as num).toInt());
                          }),
                        if (auds.isEmpty) row(val('Tek ses parçası')),
                        div,
                        row(const Text('Hız', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            right: val('${_num(speed)}×'), onTap: () {
                          final k = _speeds.indexOf(speed);
                          speed = _speeds[(k + 1) % _speeds.length];
                          player.setRate(speed);
                          setState(() {});
                        }),
                        row(const Text('Gece modu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            right: SizedBox(
                              height: 28,
                              child: FittedBox(
                                child: CupertinoSwitch(value: night, activeColor: const Color(0xFF34C759), onChanged: _setNight),
                              ),
                            )),
                        row(const Text('Giriş/jenerik atla', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            right: SizedBox(
                              height: 28,
                              child: FittedBox(
                                child: CupertinoSwitch(
                                    value: api.autoSkip,
                                    activeColor: const Color(0xFF34C759),
                                    onChanged: (v) => setState(() => api.autoSkip = v)),
                              ),
                            )),
                        const SizedBox(height: 8),
                      ]),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(border: Border(left: BorderSide(color: Color(0x14FFFFFF)))),
                      child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        h('ALTYAZI'),
                        opt('Kapalı', subIdx == null, () {
                          setState(() => tracksOpen = false);
                          _armHide();
                          _selectSub(null);
                        }),
                        for (final x in subs)
                          opt(lbl(x), x['Index'] == subIdx, () {
                            setState(() => tracksOpen = false);
                            _armHide();
                            _selectSub((x['Index'] as num).toInt());
                          }, sub: x['IsTextSubtitleStream'] == true ? null : 'Resim altyazı'),
                        div,
                        row(const Text('Zamanlama', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            right: Row(mainAxisSize: MainAxisSize.min, children: [
                              val(delay),
                              step(Icons.remove_rounded, 'Altyazıyı erken göster', () => adj(-250)),
                              step(Icons.add_rounded, 'Altyazıyı geç göster', () => adj(250)),
                            ]),
                            onTap: ms == 0
                                ? null
                                : () {
                                    setState(() => subDelay = Duration.zero);
                                    _applyDelay();
                                  }),
                        row(
                          const Row(children: [
                            Icon(Icons.search_rounded, size: 17, color: kAccent),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text('Altyazı ara ve indir',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kAccent)),
                            ),
                          ]),
                          onTap: () {
                            setState(() => tracksOpen = false);
                            _subSearch();
                          },
                        ),
                        const SizedBox(height: 8),
                      ]),
                    ),
                    ),
                  ),
                ]),
            ),
          ),
        ),
      ),
    );
  }

  static const _langs = {
    'tr': 'Türkçe', 'en': 'English', 'fa': 'Farsça', 'ar': 'Arapça', 'de': 'Almanca', 'fr': 'Fransızca',
    'es': 'İspanyolca', 'it': 'İtalyanca', 'pt': 'Portekizce', 'ru': 'Rusça', 'all': 'Tüm diller',
  };

  /// Subtitle Downloader eklentisi (web istemcisiyle aynı uçlar)
  Future<void> _subSearch() async {
    hideT?.cancel();
    final id = '${it?['Id']}';
    var lang = _langs.containsKey(api.subLang) ? api.subLang : 'tr';
    final q = TextEditingController();
    var res = <J>[];
    var msg = 'Aranıyor…';
    var started = false;
    String? loadingId;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF2202026),
      constraints: BoxConstraints(maxWidth: 760, maxHeight: MediaQuery.sizeOf(context).height * .92),
      builder: (c) => StatefulBuilder(builder: (c, set) {
        Future<void> search() async {
          set(() {
            msg = 'Aranıyor…';
            res = [];
          });
          try {
            final r = await api.get(
                '/SubtitleDownloader/Search?itemId=$id&language=$lang&query=${Uri.encodeQueryComponent(q.text.trim())}');
            final l = ((r?['results'] as List?) ?? const []).map((e) => J.from(e as Map)).toList();
            int b(dynamic x) => x == true ? 1 : 0;
            l.sort((x, y) {
              final h = b(y['IsHashMatch']) - b(x['IsHashMatch']);
              return h != 0 ? h : b(y['IsReleaseMatch']) - b(x['IsReleaseMatch']);
            });
            if (!c.mounted) return;
            set(() {
              res = l.take(50).toList();
              msg = l.isEmpty ? 'Bu dil için sonuç yok. Başka bir dil ya da başlık dene.' : '';
            });
          } catch (e) {
            if (!c.mounted) return;
            set(() => msg = e is ApiError && e.code == 404
                ? 'Subtitle Downloader eklentisi sunucuda bulunamadı. Eklentiyi kurup sunucuyu yeniden başlat.'
                : 'Altyazı aranamadı ($e).');
          }
        }

        Future<void> download(J x) async {
          set(() => loadingId = '${x['Id']}');
          try {
            final r = await api.post('/SubtitleDownloader/Download', {
              'ItemId': id,
              'SubtitleId': x['Id'],
              'Provider': x['Provider'],
              'Format': x['Format'] ?? 'srt',
              'Language': x['Language'] ?? lang,
              'DownloadUrl': x['DownloadUrl'],
              'FileId': x['FileId'],
            });
            if (r?['Success'] != true) throw Exception(r?['Message'] ?? 'indirilemedi');
            // yeni altyazı akışını görmek için öğeyi tazele (oynatmayı kesmeden)
            final full = await api.item(id);
            final srcs = (full['MediaSources'] as List?) ?? const [];
            if (mounted && srcs.isNotEmpty) {
              setState(() {
                it = full;
                ms = J.from(srcs.first as Map);
              });
            }
            if (c.mounted) Navigator.pop(c);
            final idx = (r['StreamIndex'] as num?)?.toInt();
            if (idx != null) await _selectSub(idx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Altyazı indirildi ve açıldı.'), duration: Duration(seconds: 2)));
            }
          } catch (e) {
            if (c.mounted) {
              set(() {
                loadingId = null;
                msg = 'İndirilemedi: $e';
              });
            }
          }
        }

        if (!started) {
          started = true;
          Future.microtask(search);
        }
        const muted = TextStyle(color: Color(0x8CF5F5F7), fontSize: 12);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.viewInsetsOf(c).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Altyazı ara', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -.5)),
              const SizedBox(height: 12),
              CupertinoSearchTextField(
                controller: q,
                placeholder: 'Başlık (boş bırak: otomatik bulur)',
                style: const TextStyle(color: Color(0xFFF5F5F7)),
                backgroundColor: Colors.white.withAlpha(26),
                onSubmitted: (_) => search(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final e in _langs.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Pressable(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          lang = e.key;
                          search();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: lang == e.key ? kBlue : Colors.white.withAlpha(31),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Text(e.value,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: lang == e.key ? kInk : const Color(0xFFF5F5F7))),
                        ),
                      ),
                    ),
                ]),
              ),
              if (msg == 'Aranıyor…')
                const Padding(padding: EdgeInsets.all(24), child: CupertinoActivityIndicator())
              else if (msg.isNotEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text(msg, style: muted)),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  itemCount: res.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0x14FFFFFF)),
                  itemBuilder: (_, i) {
                    final x = res[i];
                    final tags = <String?>[
                      x['IsHashMatch'] == true ? 'Tam senkron' : (x['IsReleaseMatch'] == true ? 'Sürüm eşleşti' : null),
                      '${x['Provider'] ?? ''}',
                      '${x['LanguageName'] ?? x['Language'] ?? ''}',
                      if (x['HearingImpaired'] == true) 'İşitme engelli',
                      if (x['DownloadCount'] != null) '${x['DownloadCount']} indirme',
                    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
                    final me = loadingId == '${x['Id']}';
                    return Pressable(
                      onTap: loadingId == null ? () => download(x) : null,
                      child: Container(
                        color: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${x['ReleaseName'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 3),
                              Text(tags,
                                  style: x['IsHashMatch'] == true
                                      ? const TextStyle(color: kAccent, fontSize: 12)
                                      : muted),
                            ]),
                          ),
                          const SizedBox(width: 10),
                          me
                              ? const CupertinoActivityIndicator()
                              : const Icon(Icons.arrow_circle_down_rounded, size: 24, color: Color(0xB3F5F5F7)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      }),
    );
    q.dispose();
    _armHide();
  }

  // =================== çizim ===================
  @override
  Widget build(BuildContext context) {
    final i = it;
    final seg = _activeSeg();
    final nearEnd = dur > Duration.zero && dur - pos < const Duration(seconds: 40);
    final showNext = nextEp != null && (nearEnd || seg?.type == 'Outro' || cdT != null);
    final title = i == null
        ? '${widget.item['Name'] ?? ''}'
        : (i['Type'] == 'Episode' ? '${i['SeriesName'] ?? ''}' : '${i['Name'] ?? ''}');
    final sub = i != null && i['Type'] == 'Episode'
        ? 'S${i['ParentIndexNumber'] ?? '?'}:B${i['IndexNumber'] ?? '?'}  ${i['Name'] ?? ''}'
        : '';
    final cue = shownCue;
    final maxV = max(1.0, dur.inMilliseconds / 1000.0);
    final curV = dragging ? dragV : min(maxV, pos.inMilliseconds / 1000.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (viewOpen) return setState(() => viewOpen = false);
          if (tracksOpen) {
            setState(() => tracksOpen = false);
            return _armHide();
          }
          ui ? setState(() => ui = false) : _showUI();
        },
        // solda yukarı/aşağı kaydır: ekran parlaklığı
        onVerticalDragStart: (d) async {
          if (d.localPosition.dx > MediaQuery.sizeOf(context).width / 2) return;
          dragBright = true;
          await _ensureBright();
          if (mounted) setState(() => hud = true);
        },
        onVerticalDragUpdate: (d) {
          if (!dragBright || bright == null) return;
          _setBright(bright! - d.delta.dy / (MediaQuery.sizeOf(context).height * .7));
          setState(() {});
        },
        onVerticalDragEnd: (_) {
          dragBright = false;
          hudT?.cancel();
          hudT = Timer(const Duration(milliseconds: 900), () {
            if (mounted) setState(() => hud = false);
          });
        },
        onDoubleTapDown: (d) => tapAt = d.localPosition,
        onDoubleTap: () => _seekBy(tapAt.dx < MediaQuery.sizeOf(context).width / 2 ? -10 : 10),
        child: Stack(children: [
          // video
          Positioned.fill(
            child: Video(
              controller: vctl,
              controls: NoVideoControls,
              fill: Colors.black,
              subtitleViewConfiguration: SubtitleViewConfiguration(visible: false),
            ),
          ),
          // altyazı
          if (cue != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              left: 48,
              right: 48,
              bottom: (ui ? 110 : 30) + const [0.0, 50.0, 100.0][api.subLift.clamp(0, 2)],
              child: Center(child: subtitleText(cue)),
            ),
          if (buffering && err.isEmpty) const Center(child: CircularProgressIndicator.adaptive()),
          // yaş kartı
          if (i != null)
            Positioned(
              left: 40,
              top: 76,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showAge && (ageKey(i['OfficialRating']) != null || descs(i).isNotEmpty) ? 1 : 0,
                  duration: const Duration(milliseconds: 600),
                  child: _ageCard(i),
                ),
              ),
            ),
          // kontroller (A · Cam)
          IgnorePointer(
            ignoring: !ui,
            child: AnimatedOpacity(
              opacity: ui ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0x99000000),
                      const Color(0x33000000),
                      const Color(0x33000000),
                      epsOpen ? const Color(0xEB000000) : const Color(0xB3000000),
                    ],
                    stops: const [0, .3, .55, 1],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(children: [
                      Row(children: [
                        GlassIcon(Icons.close_rounded, tooltip: 'Kapat', onTap: _close),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            if (sub.isNotEmpty)
                              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xB3F5F5F7), fontSize: 12)),
                          ]),
                        ),
                        Glass(
                          radius: 24,
                          padding: const EdgeInsets.all(4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (epsOpen)
                              _capBtn(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, playing ? 'Duraklat' : 'Oynat', _togglePlay),
                            _capBtn('sun', 'Görüntü', _openView, on: viewOpen),
                            _capBtn('cc', 'Ses ve altyazı', _toggleTracks, on: tracksOpen),
                            if (eps.length > 1) _capBtn('eps', 'Bölümler', _toggleEps, on: epsOpen),
                          ]),
                        ),
                      ]),
                      Expanded(
                        child: epsOpen
                            ? const SizedBox()
                            : Center(
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  _seekBtn(-10),
                                  const SizedBox(width: 52),
                                  Semantics(
                                    button: true,
                                    label: playing ? 'Duraklat' : 'Oynat',
                                    child: Pressable(
                                      haptic: true,
                                      onTap: _togglePlay,
                                      child: Glass(
                                        radius: 42,
                                        color: const Color(0x7326262C),
                                        child: SizedBox(
                                          width: 84,
                                          height: 84,
                                          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 44, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 52),
                                  _seekBtn(10),
                                ]),
                              ),
                      ),
                      _scrubber(maxV, curV),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (c, a) => SizeTransition(
                          sizeFactor: a,
                          axisAlignment: -1,
                          child: FadeTransition(opacity: a, child: c),
                        ),
                        child: epsOpen ? KeyedSubtree(key: const ValueKey('eps'), child: _epsStrip()) : const SizedBox(width: double.infinity),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          // parlaklık göstergesi (solda kaydırınca)
          Positioned(
            left: 40,
            top: 0,
            bottom: 0,
            child: Center(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: hud ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Glass(
                    radius: 26,
                    child: SizedBox(
                      width: 52,
                      height: 190,
                      child: Stack(children: [
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: (bright ?? .5).clamp(0.0, 1.0),
                            widthFactor: 1,
                            child: Container(color: const Color(0xE6F5F5F7)),
                          ),
                        ),
                        const Align(
                          alignment: Alignment(0, .82),
                          child: Icon(Icons.wb_sunny_rounded, size: 22, color: Color(0xFF6B6B73)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _pop(viewOpen, _viewPanel()),
          _pop(tracksOpen && ui, _tracksPanel()),
          // giriş atla / sonraki bölüm
          Positioned(
            right: 40,
            bottom: ui ? 96 : 34,
            child: Row(children: [
              if (seg != null && !(showNext && seg.type == 'Outro'))
                _pill(seg.type == 'Intro' ? 'Girişi atla' : 'Jeneriği atla', () => player.seek(seg.b)),
              if (showNext && cdT != null) ...[
                const SizedBox(width: 10),
                _pill('İzlemeye devam', _cancelCountdown),
                const SizedBox(width: 10),
                _pill('Sonraki bölüm  $cd', () => _start(nextEp!, restart: true), primary: true),
              ] else if (showNext) ...[
                const SizedBox(width: 10),
                _pill('Sonraki bölüm  ›', () => _start(nextEp!, restart: true), primary: true),
              ],
            ]),
          ),
          if (err.isNotEmpty)
            Container(
              color: Colors.black87,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: SingleChildScrollView(child: SelectableText(err, textAlign: TextAlign.center))),
                const SizedBox(height: 18),
                PillButton('Kapat', onTap: _close),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _pill(String t, VoidCallback f, {bool primary = false}) => Pressable(
        haptic: true,
        onTap: f,
        child: primary
            ? Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(21)),
                child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kInk)),
              )
            : Glass(
                radius: 21,
                color: const Color(0x9926262C),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white)),
                ),
              ),
      );

  // =================== 3.0 oynatıcı parçaları ===================
  Widget _capBtn(Object i, String label, VoidCallback f, {bool on = false}) => Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            f();
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: on ? kBlue : Colors.transparent, borderRadius: BorderRadius.circular(19)),
            child: i is IconData
                ? Icon(i, size: 20, color: on ? kInk : Colors.white)
                : CustomPaint(painter: _CapIcon(i as String, on ? kInk : Colors.white)),
          ),
        ),
      );

  /// iOS menüleri gibi: sağ üstten büyüyerek açılır, küçülerek kapanır.
  Widget _pop(bool open, Widget panel) {
    final p = panel as Positioned;
    return Positioned(
      left: p.left,
      top: p.top,
      right: p.right,
      bottom: p.bottom,
      width: p.width,
      height: p.height,
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: Duration(milliseconds: open ? 180 : 140),
          child: AnimatedScale(
            scale: open ? 1 : .9,
            alignment: Alignment.topRight,
            duration: Duration(milliseconds: open ? 280 : 160),
            curve: open ? Curves.easeOutBack : Curves.easeInCubic,
            child: ExcludeSemantics(excluding: !open, child: p.child),
          ),
        ),
      ),
    );
  }

  Widget _seekBtn(int s) => Semantics(
        button: true,
        label: s < 0 ? '10 saniye geri' : '10 saniye ileri',
        child: Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            _seekBy(s);
          },
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(s < 0 ? Icons.replay_10_rounded : Icons.forward_10_rounded, size: 42, color: Colors.white),
          ),
        ),
      );

  Widget _scrubber(double maxV, double curV) => LayoutBuilder(
        builder: (context, cs) => Stack(clipBehavior: Clip.none, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: dragging ? 8 : 4,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: dragging ? 9 : 5),
              ),
              child: Slider(
                value: curV.clamp(0, maxV).toDouble(),
                max: maxV,
                onChangeStart: (v) {
                  hideT?.cancel();
                  HapticFeedback.selectionClick();
                  setState(() {
                    dragging = true;
                    dragV = v;
                  });
                },
                onChanged: (v) => setState(() => dragV = v),
                onChangeEnd: (v) {
                  player.seek(Duration(milliseconds: (v * 1000).round()));
                  setState(() => dragging = false);
                  _armHide();
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(fmt(dragging ? Duration(milliseconds: (dragV * 1000).round()) : pos),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xCCF5F5F7))),
              Text('-${fmt(dur - pos)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xCCF5F5F7))),
            ]),
          ]),
          if (dragging && tp != null)
            Positioned(
              bottom: 40,
              left: ((dragV / maxV).clamp(0.0, 1.0) * (cs.maxWidth - 24) + 12 - 90).clamp(0.0, max(0.0, cs.maxWidth - 180)),
              child: IgnorePointer(child: _thumb(dragV)),
            ),
        ]),
      );

  void _toggleEps() {
    hideT?.cancel();
    setState(() {
      epsOpen = !epsOpen;
      epsSeason = null;
    });
    if (!epsOpen) _armHide();
  }

  Widget _epsStrip() {
    final seasons = eps.map((e) => e['ParentIndexNumber'] as num?).toSet().toList();
    final s = epsSeason ?? (it?['ParentIndexNumber'] as num?);
    final list = eps.where((e) => e['ParentIndexNumber'] == s).toList();
    return SizedBox(
      height: 196,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final x in seasons)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Pressable(
                  onTap: () => setState(() => epsSeason = x),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: x == s ? kBlue : Colors.white.withAlpha(26),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(x == null || x == 0 ? 'Özel' : '$x. Sezon',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: x == s ? kInk : Colors.white)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, k) {
              final e = list[k];
              final now = e['Id'] == it?['Id'];
              final ud = (e['UserData'] as Map?) ?? const {};
              final seen = ud['Played'] == true;
              final run = (e['RunTimeTicks'] as num?) ?? 0;
              final pt = (ud['PlaybackPositionTicks'] as num?) ?? 0;
              final frac = now
                  ? (dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0)
                  : (seen ? 1.0 : (run > 0 ? pt / run : 0.0));
              final tag = (e['ImageTags'] as Map?)?['Primary'];
              return Pressable(
                onTap: () {
                  if (now) return;
                  setState(() => epsOpen = false);
                  _start(e, restart: seen);
                },
                child: SizedBox(
                  width: 176,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 176,
                      height: 99,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: now ? Colors.white : Colors.white12, width: now ? 2 : 1),
                      ),
                      child: Stack(fit: StackFit.expand, children: [
                        if (tag != null) netImg(api.image('${e['Id']}', 'Primary', tag: '$tag', w: 360)),
                        if (now)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(10)),
                              child: const Text('Oynatılıyor', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kInk)),
                            ),
                          ),
                        if (seen && !now)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(color: const Color(0xBF26262C), borderRadius: BorderRadius.circular(11)),
                              child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: FractionallySizedBox(
                            widthFactor: frac.clamp(0.0, 1.0).toDouble(),
                            child: Container(height: 3, color: Colors.white),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    Text('${e['IndexNumber'] ?? ''}. ${e['Name'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(rt(e['RunTimeTicks']), style: const TextStyle(fontSize: 11, color: Color(0x8CF5F5F7))),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _ensureBright() async {
    if (bright != null) return;
    try {
      bright = await ScreenBrightness().current;
    } catch (_) {
      bright = .5;
    }
  }

  Future<void> _setBright(double v) async {
    bright = v.clamp(0.0, 1.0);
    brightTouched = true;
    try {
      await ScreenBrightness().setScreenBrightness(bright!);
    } catch (_) {}
  }

  void _eq(String k, double v) {
    eq[k] = v;
    try {
      (player.platform as dynamic).setProperty(k, '${v.round()}');
    } catch (_) {}
  }

  Future<void> _openView() async {
    hideT?.cancel();
    await _ensureBright();
    if (!mounted) return;
    setState(() {
      viewOpen = true;
      ui = false;
    });
  }

  Future<void> _resetView() async {
    for (final k in eq.keys.toList()) {
      _eq(k, 0);
    }
    if (brightTouched) {
      try {
        await ScreenBrightness().resetScreenBrightness();
      } catch (_) {}
      brightTouched = false;
      bright = null;
      await _ensureBright();
    }
    if (mounted) setState(() {});
  }

  Widget _viewSlider(String label, String value, double v, double lo, double hi, ValueChanged<double> f) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(value, style: const TextStyle(fontSize: 13, color: Color(0x99F5F5F7))),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(value: v.clamp(lo, hi), min: lo, max: hi, onChanged: f),
          ),
        ]),
      );

  Widget _viewPanel() {
    String sign(double v) => v > 0 ? '+${v.round()}' : '${v.round()}';
    return Positioned(
      right: 16,
      top: 12,
      bottom: 12,
      width: 320,
      child: SafeArea(
        left: false,
        child: GestureDetector(
          onTap: () {},
          child: Glass(
            radius: 26,
            color: const Color(0xD920202A),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: ListView(padding: EdgeInsets.zero, children: [
              Row(children: [
                const Expanded(child: Text('Görüntü', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                Pressable(
                  onTap: _resetView,
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(15)),
                    child: const Text('Sıfırla', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              const Text('EKRAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: Color(0x80F5F5F7))),
              const SizedBox(height: 6),
              _viewSlider('Ekran parlaklığı', '%${((bright ?? .5) * 100).round()}', bright ?? .5, 0, 1, (v) {
                _setBright(v);
                setState(() {});
              }),
              const SizedBox(height: 4),
              const Text('VİDEO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: Color(0x80F5F5F7))),
              const SizedBox(height: 6),
              for (final k in eq.keys)
                _viewSlider(_eqNames[k]!, sign(eq[k]!), eq[k]!, -50, 50, (v) {
                  _eq(k, v);
                  setState(() {});
                }),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _ageCard(J i) {
    final a = ageLabel(i['OfficialRating']);
    final ds = descs(i);
    final line = [if (a != null) a, ...ds.map((d) => kDesc[d]!)].join(' · ');
    return Glass(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Text(line, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

/// Ayarlardaki altyazı görünümüyle (boyut, renk, arka plan) altyazı satırı. Ayarlar ekranındaki önizleme de bunu kullanır.
Widget subtitleText(String text, {double scale = 1}) {
  final api = Api.I;
  final bg = api.subBg;
  final t = Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 21 * api.subSize * scale,
      fontWeight: FontWeight.w600,
      color: api.subColor == 1 ? const Color(0xFFFFE14D) : Colors.white,
      height: 1.25,
      shadows: bg == 0
          ? const [
              Shadow(blurRadius: 4, color: Colors.black),
              Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1)),
              Shadow(blurRadius: 2, color: Colors.black, offset: Offset(-1, -1)),
            ]
          : null,
    ),
  );
  if (bg == 0) return t;
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 4 * scale),
    decoration: BoxDecoration(
      color: bg == 1 ? const Color(0x99000000) : Colors.black,
      borderRadius: BorderRadius.circular(4),
    ),
    child: t,
  );
}

/// Tasarımdaki çizgisel simgeler (24'lük ızgara): Görüntü, Ses ve altyazı, Bölümler
class _CapIcon extends CustomPainter {
  final String kind;
  final Color color;
  const _CapIcon(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = (kind == 'sun' ? 19 : 20) / 24;
    canvas.translate((size.width - 24 * k) / 2, (size.height - 24 * k) / 2);
    canvas.scale(k);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double a, double b, double c, double d) => canvas.drawLine(Offset(a, b), Offset(c, d), pen);
    switch (kind) {
      case 'sun':
        canvas.drawCircle(const Offset(12, 12), 4, pen);
        line(12, 2, 12, 4);
        line(12, 20, 12, 22);
        line(2, 12, 4, 12);
        line(20, 12, 22, 12);
        line(4.9, 4.9, 6.3, 6.3);
        line(17.7, 17.7, 19.1, 19.1);
        line(4.9, 19.1, 6.3, 17.7);
        line(17.7, 6.3, 19.1, 4.9);
      case 'cc':
        canvas.drawRRect(RRect.fromLTRBR(3, 5, 21, 19, const Radius.circular(3)), pen);
        line(7, 13, 11, 13);
        line(13, 13, 17, 13);
        line(7, 16, 17, 16);
      case 'eps':
        canvas.drawRRect(RRect.fromLTRBR(3, 6, 16, 18, const Radius.circular(2)), pen);
        line(19, 8, 19, 16);
        line(22, 9.5, 22, 14.5);
    }
  }

  @override
  bool shouldRepaint(_CapIcon o) => o.kind != kind || o.color != color;
}
