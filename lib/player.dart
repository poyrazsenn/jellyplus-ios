import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'main.dart' show allowAppOrientations;
import 'util.dart';
import 'widgets.dart';

class _Seg {
  final String type;
  final Duration a, b;
  bool done = false;
  _Seg(this.type, this.a, this.b);
}

class _Cue {
  final Duration a, b;
  final String t;
  _Cue(this.a, this.b, this.t);
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

List<_Cue> _parseVtt(String s) {
  final out = <_Cue>[];
  final lines = s.replaceAll('\r', '').split('\n');
  final re = RegExp(r'((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})');
  Duration t(String x) {
    final p = x.replaceAll(',', '.').split(':');
    final sec = double.parse(p.last);
    final m = int.parse(p[p.length - 2]);
    final h = p.length > 2 ? int.parse(p[0]) : 0;
    return Duration(milliseconds: ((h * 3600 + m * 60 + sec) * 1000).round());
  }

  for (var i = 0; i < lines.length; i++) {
    final m = re.firstMatch(lines[i]);
    if (m == null) continue;
    final buf = <String>[];
    var j = i + 1;
    while (j < lines.length && lines[j].trim().isNotEmpty) {
      buf.add(lines[j]);
      j++;
    }
    final txt = buf
        .join('\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\{\\[^}]*\}'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .trim();
    if (txt.isNotEmpty) out.add(_Cue(t(m.group(1)!), t(m.group(2)!), txt));
    i = j;
  }
  out.sort((a, b) => a.a.compareTo(b.a));
  return out;
}

class PlayerScreen extends StatefulWidget {
  final J item;
  final bool restart;
  const PlayerScreen({super.key, required this.item, this.restart = false});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final api = Api.I;
  VideoPlayerController? vc;
  J? it, ms, series;
  String sid = '';
  bool transcode = false, forceHls = false, burn = false, opening = false, closed = false;
  int? audioIdx, subIdx, defAudio;
  List<_Cue> cues = [];
  List<_Seg> segs = [];
  List<J> eps = [];
  J? nextEp;
  String err = '';
  bool ui = true, ended = false, showAge = false, dragging = false;
  double dragV = 0;
  Duration pos = Duration.zero, dur = Duration.zero;
  bool playing = false, buffering = true;
  Timer? hideT, repT, ageT, subT;
  Duration subDelay = Duration.zero; // + geç, − erken
  DateTime posAt = DateTime.now();
  String? shownCue;
  Offset tapAt = Offset.zero;
  double speed = 1;
  int hlsTry = 0; // 0: fMP4 + 6 kanal, 1: klasik TS + stereo AAC (web istemcisinin ayarı)
  bool compat = Api.I.compat; // uyumlu mod: videoyu sunucu H.264'e çevirir
  Timer? vidT;

  List<J> get streams =>
      ((ms?['MediaStreams'] as List?) ?? const []).map((e) => J.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
    // Altyazıyı oynatıcının 0,5 sn'lik konum güncellemesini beklemeden, 100 ms'de bir eşle
    subT = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final t = _cueAt(_subPos);
      if (t != shownCue) setState(() => shownCue = t);
    });
    _start(widget.item, restart: widget.restart);
  }

  @override
  void dispose() {
    hideT?.cancel();
    repT?.cancel();
    ageT?.cancel();
    vidT?.cancel();
    subT?.cancel();
    if (!closed) _stopCurrent();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    allowAppOrientations();
    super.dispose();
  }

  // =================== akış ===================
  String _newSid() {
    final r = Random();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<void> _start(J base, {bool restart = false}) async {
    await _stopCurrent();
    if (!mounted) return;
    setState(() {
      err = '';
      ended = false;
      segs = [];
      cues = [];
      nextEp = null;
      buffering = true;
      pos = Duration.zero;
      dur = Duration.zero;
      forceHls = false;
      burn = false;
      hlsTry = 0;
    });
    J full;
    try {
      full = await api.item('${base['Id']}');
    } catch (_) {
      full = base;
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
    defAudio = (ms!['DefaultAudioStreamIndex'] as num?)?.toInt() ?? (aud.isNotEmpty ? (aud.first['Index'] as num).toInt() : null);
    audioIdx = defAudio;
    subIdx = _autoSub();
    final startAt = restart
        ? Duration.zero
        : ticks((full['UserData'] as Map?)?['PlaybackPositionTicks'] ?? 0);
    await _open(startAt);
    _loadSubs();
    _loadSegments();
    _loadEpisodes();
    // Netflix/Disney+ tarzı yaş kartı
    ageT?.cancel();
    setState(() => showAge = true);
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

  /// Dolby Vision iPhone oynatıcısında siyah/yanlış renkli görüntü verebiliyor
  bool get _dovi {
    final v = _video;
    final r = '${v?['VideoRangeType'] ?? ''} ${v?['VideoDoViTitle'] ?? ''}'.toUpperCase();
    return r.contains('DOVI') || r.contains('DOLBY VISION');
  }

  bool _canDirect() {
    final m = ms!;
    final cont = '${m['Container'] ?? ''}'.toLowerCase().split(',');
    final v = _video;
    final a = streams.where((s) => s['Index'] == audioIdx).toList();
    final vcod = '${v?['Codec'] ?? ''}'.toLowerCase();
    final tag = '${v?['CodecTag'] ?? ''}'.toLowerCase();
    final ac = a.isNotEmpty ? '${a.first['Codec']}'.toLowerCase() : 'aac';
    // HEVC sadece "hvc1" etiketliyse doğrudan oynar; "hev1" iPhone'da siyah ekran verir
    final videoOk = vcod == 'h264' || (['hevc', 'h265'].contains(vcod) && tag == 'hvc1' && !_dovi);
    return cont.any((c) => ['mp4', 'm4v', 'mov'].contains(c)) &&
        videoOk &&
        ['aac', 'ac3', 'eac3', 'mp3', 'alac', 'flac'].contains(ac);
  }

  Future<void> _open(Duration startAt) async {
    if (opening) return;
    opening = true;
    final id = '${it!['Id']}', msId = '${ms!['Id']}';
    transcode = compat || forceHls || burn || audioIdx != defAudio || !_canDirect();
    final vcodecs = (compat || _dovi) ? 'h264' : 'h264,hevc';
    final q = 'MediaSourceId=$msId&DeviceId=${api.deviceId}&ApiKey=${api.token}&PlaySessionId=$sid';
    final prof = hlsTry == 0
        ? 'VideoCodec=$vcodecs&AudioCodec=aac,ac3,eac3&TranscodingMaxAudioChannels=6&SegmentContainer=mp4'
            '&MaxStreamingBitrate=40000000&VideoBitrate=40000000&AudioBitrate=384000'
        : 'VideoCodec=h264&AudioCodec=aac&TranscodingMaxAudioChannels=2&SegmentContainer=ts'
            '&MaxStreamingBitrate=20000000&VideoBitrate=20000000&AudioBitrate=192000';
    final url = transcode
        ? '${api.url}/Videos/$id/master.m3u8?$q&$prof&MinSegments=1&BreakOnNonKeyFrames=True'
            '${audioIdx != null ? '&AudioStreamIndex=$audioIdx' : ''}'
            '${burn && subIdx != null ? '&SubtitleStreamIndex=$subIdx&SubtitleMethod=Encode' : ''}'
        : '${api.url}/Videos/$id/stream.mp4?static=true&$q';
    final old = vc;
    final c = VideoPlayerController.networkUrl(Uri.parse(url),
        formatHint: transcode ? VideoFormat.hls : null,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
    vc = c;
    if (mounted) setState(() => buffering = true);
    old?.removeListener(_tick);
    old?.dispose();
    try {
      await c.initialize();
    } catch (e) {
      opening = false;
      if (vc != c) return;
      if (!transcode) {
        forceHls = true; // doğrudan oynatma olmadı → sunucu dönüştürsün
        return _open(startAt);
      }
      if (hlsTry == 0) {
        hlsTry = 1; // klasik ayarlarla bir kez daha dene
        _killEncoding();
        sid = _newSid();
        return _open(startAt);
      }
      final why = await _probe(url);
      if (mounted) {
        setState(() => err = 'Video açılamadı.\n\n$why\n\nOynatıcı hatası: ${e is PlatformException ? (e.message ?? e.code) : e}\n\n${_info()}');
      }
      return;
    }
    opening = false;
    if (!mounted || vc != c) return;
    c.addListener(_tick);
    if (startAt > const Duration(seconds: 1)) await c.seekTo(startAt);
    await c.setPlaybackSpeed(speed);
    await c.play();
    _report('');
    _watchVideo(c);
    repT?.cancel();
    repT = Timer.periodic(const Duration(seconds: 10), (_) => _report('/Progress'));
    _armHide();
  }

  void _killEncoding() {
    api.delete('/Videos/ActiveEncodings?DeviceId=${api.deviceId}&PlaySessionId=$sid').catchError((_) {});
  }

  /// Sunucunun akış adresine verdiği cevabı oku (hatanın nedenini göstermek için)
  Future<String> _probe(String url) async {
    try {
      final t = await api.getText(url);
      return t.contains('#EXTM3U') ? 'Sunucu akışı oluşturdu ama iPhone oynatamadı.' : 'Sunucu beklenmeyen cevap verdi.';
    } catch (e) {
      if (e is ApiError) {
        if (e.code == 401 || e.code == 403) return 'Sunucu dönüştürmeye izin vermiyor ($e). Jellyfin kullanıcı ayarlarında "dönüştürme gerektiren oynatmaya izin ver" açık mı?';
        return 'Sunucu dönüştürmeyi başlatamadı ($e). Jellyfin → Pano → Günlükler bölümündeki en yeni FFmpeg.Transcode günlüğü nedenini gösterir.';
      }
      return 'Sunucuya ulaşılamadı: $e';
    }
  }

  /// Ses/altyazı ilerliyor ama görüntü gelmiyorsa uyumlu moda geç
  void _watchVideo(VideoPlayerController c) {
    vidT?.cancel();
    if (compat || _video == null) return;
    vidT = Timer(const Duration(seconds: 6), () {
      if (!mounted || vc != c || compat) return;
      final v = c.value;
      if (v.isInitialized && v.position > const Duration(seconds: 2) && (v.size.width < 2 || v.size.height < 2)) {
        compat = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Görüntü gelmedi, uyumlu moda (H.264) geçiliyor…'), duration: Duration(seconds: 3)));
        _reopen();
      }
    });
  }

  String _info() {
    final v = _video, m = ms;
    final src = [
      '${m?['Container'] ?? '?'}'.toUpperCase(),
      '${v?['Codec'] ?? '?'}'.toUpperCase() + (v?['CodecTag'] != null ? ' (${v!['CodecTag']})' : ''),
      if (v?['Width'] != null) '${v?['Width']}×${v?['Height']}',
      if (v?['VideoRangeType'] != null) '${v!['VideoRangeType']}',
    ].join(' • ');
    final s = vc?.value.size ?? Size.zero;
    return 'Kaynak: $src\nOynatma: ${transcode ? 'Sunucu dönüştürüyor (HLS${compat || _dovi ? ', H.264' : ''})' : 'Doğrudan oynatma'}'
        '\nOynatıcıdaki görüntü: ${s.width.round()}×${s.height.round()}';
  }

  Future<void> _report(String kind) async {
    final c = vc, i = it;
    if (c == null || i == null || !c.value.isInitialized) return;
    final body = <String, dynamic>{
      'ItemId': i['Id'],
      'MediaSourceId': ms?['Id'],
      'PlaySessionId': sid,
      'PositionTicks': c.value.position.inMicroseconds * 10,
      'IsPaused': !c.value.isPlaying,
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
    final c = vc;
    if (c == null) return;
    await _report('/Stopped');
    if (transcode) {
      api.delete('/Videos/ActiveEncodings?DeviceId=${api.deviceId}&PlaySessionId=$sid').catchError((_) {});
    }
    c.removeListener(_tick);
    vc = null;
    await c.dispose();
  }

  /// Aynı içerikte ses/altyazı değişince akışı kaldığı yerden yeniden aç
  Future<void> _reopen() async {
    final at = vc?.value.position ?? pos;
    await _report('/Stopped');
    if (transcode) {
      api.delete('/Videos/ActiveEncodings?DeviceId=${api.deviceId}&PlaySessionId=$sid').catchError((_) {});
    }
    sid = _newSid();
    await _open(at);
  }

  void _tick() {
    final c = vc;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError && err.isEmpty && !opening) {
      if (!transcode) {
        forceHls = true;
        _open(v.position);
        return;
      }
      if (hlsTry == 0) {
        hlsTry = 1;
        _killEncoding();
        sid = _newSid();
        _open(v.position);
        return;
      }
      setState(() => err = 'Oynatma hatası: ${v.errorDescription ?? ''}\n\n${_info()}');
      return;
    }
    final was = playing;
    if (v.position != pos) posAt = DateTime.now();
    pos = v.position;
    dur = v.duration;
    playing = v.isPlaying;
    buffering = v.isBuffering && !playing;
    if (was != playing) _report('/Progress');
    // giriş / jenerik
    final s = _activeSeg();
    if (s != null && api.autoSkip && !s.done) {
      s.done = true;
      c.seekTo(s.b);
    }
    // bitti mi
    if (!ended && dur > Duration.zero && pos >= dur - const Duration(milliseconds: 800) && !playing) {
      ended = true;
      _onEnded();
    }
    setState(() {});
  }

  _Seg? _activeSeg() {
    for (final s in segs) {
      if (pos >= s.a && pos < s.b - const Duration(seconds: 1)) return s;
    }
    return null;
  }

  /// Son bilinen konum + o andan beri geçen süre (oynarken)
  Duration get _subPos {
    var p = pos;
    if (playing) {
      final e = DateTime.now().difference(posAt);
      if (e < const Duration(seconds: 2)) p += e * speed;
    }
    return p - subDelay;
  }

  String? _cueAt(Duration pos) {
    if (cues.isEmpty || subIdx == null || burn) return null;
    // ikili arama
    var lo = 0, hi = cues.length - 1, f = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cues[mid].a <= pos) {
        f = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final out = <String>[];
    for (var k = f; k >= 0 && k > f - 4; k--) {
      if (cues[k].a <= pos && pos < cues[k].b) out.insert(0, cues[k].t);
    }
    return out.isEmpty ? null : out.join('\n');
  }

  // =================== altyazı ===================
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

  Future<void> _loadSubs() async {
    final id = it?['Id'], idx = subIdx;
    if (id == null || idx == null || burn) {
      setState(() => cues = []);
      return;
    }
    try {
      final txt = await api.getText(
          '${api.url}/Videos/$id/${ms!['Id']}/Subtitles/$idx/0/Stream.vtt');
      if (!mounted || it?['Id'] != id || subIdx != idx) return;
      setState(() => cues = _parseVtt(txt));
    } catch (_) {
      if (mounted) setState(() => cues = []);
    }
  }

  Future<void> _selectSub(int? idx) async {
    final s = idx == null ? null : streams.firstWhere((x) => x['Index'] == idx, orElse: () => <String, dynamic>{});
    final needBurn = s != null && s.isNotEmpty && s['IsTextSubtitleStream'] != true;
    final wasBurn = burn;
    setState(() {
      subIdx = idx;
      burn = needBurn;
      cues = [];
    });
    if (needBurn || wasBurn) {
      await _reopen(); // resim tabanlı altyazı (PGS vb.) → sunucu videoya gömer
    }
    _loadSubs();
  }

  Future<void> _selectAudio(int idx) async {
    if (idx == audioIdx) return;
    setState(() => audioIdx = idx);
    await _reopen();
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
    } catch (_) {}
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
      if (mounted && playing && !dragging) setState(() => ui = false);
    });
  }

  void _showUI() {
    setState(() => ui = true);
    _armHide();
  }

  void _togglePlay() {
    final c = vc;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
    _showUI();
  }

  void _seekBy(int s) {
    final c = vc;
    if (c == null) return;
    var t = c.value.position + Duration(seconds: s);
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur;
    c.seekTo(t);
    _showUI();
  }

  Future<void> _tracksSheet() async {
    hideT?.cancel();
    final auds = streams.where((s) => s['Type'] == 'Audio').toList();
    final subs = streams.where((s) => s['Type'] == 'Subtitle').toList();
    String lbl(J s) => '${s['DisplayTitle'] ?? s['Language'] ?? 'Parça ${s['Index']}'}';
    Widget head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(t, style: const TextStyle(color: kMuted, fontSize: 12, letterSpacing: 1.4)));
    Widget opt(String t, bool sel, VoidCallback f, {String? sub}) => ListTile(
          dense: true,
          title: Text(t),
          subtitle: sub != null ? Text(sub, style: const TextStyle(color: kMuted, fontSize: 11)) : null,
          trailing: sel ? const Icon(Icons.check, color: kBlue) : null,
          onTap: f,
        );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF20B1024),
      constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.sizeOf(context).height * .9),
      builder: (c) => SafeArea(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ListView(children: [
              head('SES'),
              for (final a in auds)
                opt(lbl(a), a['Index'] == audioIdx, () {
                  Navigator.pop(c);
                  _selectAudio((a['Index'] as num).toInt());
                }),
              head('HIZ'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(spacing: 6, children: [
                  for (final s in [.75, 1.0, 1.25, 1.5, 2.0])
                    ChoiceChip(
                      label: Text('${s}x'),
                      selected: speed == s,
                      onSelected: (_) {
                        speed = s;
                        vc?.setPlaybackSpeed(s);
                        Navigator.pop(c);
                      },
                    ),
                ]),
              ),
            ]),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: ListView(children: [
              head('ALTYAZI'),
              opt('Kapalı', subIdx == null, () {
                Navigator.pop(c);
                _selectSub(null);
              }),
              for (final s in subs)
                opt(lbl(s), s['Index'] == subIdx, () {
                  Navigator.pop(c);
                  _selectSub((s['Index'] as num).toInt());
                }, sub: s['IsTextSubtitleStream'] == true ? null : 'Resim altyazı — sunucu videoya gömer'),
              StatefulBuilder(builder: (c2, set2) {
                final ms = subDelay.inMilliseconds;
                final lab = ms == 0 ? '0 sn' : '${ms > 0 ? '+' : ''}${(ms / 1000).toStringAsFixed(2)} sn';
                void adj(int d) => set2(() => subDelay += Duration(milliseconds: d));
                return ListTile(
                  dense: true,
                  title: const Text('Altyazı zamanlaması'),
                  subtitle: Text('$lab   (+ geç, − erken gösterir)', style: const TextStyle(color: kMuted, fontSize: 11)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => adj(-250)),
                    IconButton(icon: const Icon(Icons.restart_alt), onPressed: () => set2(() => subDelay = Duration.zero)),
                    IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => adj(250)),
                  ]),
                );
              }),
              ListTile(
                dense: true,
                leading: const Icon(Icons.download_outlined),
                title: const Text('Altyazı ara ve indir'),
                subtitle: const Text('Subtitle Downloader eklentisi', style: TextStyle(color: kMuted, fontSize: 11)),
                onTap: () {
                  Navigator.pop(c);
                  _subSearch();
                },
              ),
              head('GÖRÜNTÜ'),
              SwitchListTile(
                dense: true,
                title: const Text('Uyumlu mod (H.264)'),
                subtitle: const Text('Görüntü gelmiyorsa aç. Sunucu videoyu dönüştürür.',
                    style: TextStyle(color: kMuted, fontSize: 11)),
                value: compat,
                onChanged: (v) {
                  Navigator.pop(c);
                  compat = v;
                  api.compat = v;
                  _reopen();
                },
              ),
              ListTile(
                dense: true,
                title: const Text('Akış bilgisi'),
                subtitle: Text(_info(), style: const TextStyle(color: kMuted, fontSize: 11)),
              ),
              head('OTOMATİK ATLA'),
              SwitchListTile(
                dense: true,
                title: const Text('Giriş ve jeneriği otomatik atla'),
                value: api.autoSkip,
                onChanged: (v) {
                  api.autoSkip = v;
                  Navigator.pop(c);
                },
              ),
            ]),
          ),
        ]),
      ),
    );
    _armHide();
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
      backgroundColor: const Color(0xF20B1024),
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
        const muted = TextStyle(color: kMuted, fontSize: 12);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.viewInsetsOf(c).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Text('Altyazı ara', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                DropdownButton<String>(
                  value: lang,
                  dropdownColor: const Color(0xFF151B3A),
                  underline: const SizedBox.shrink(),
                  items: [for (final e in _langs.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) {
                    if (v == null) return;
                    lang = v;
                    search();
                  },
                ),
              ]),
              const SizedBox(height: 6),
              TextField(
                controller: q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                  hintText: 'Başlık (boş bırak: otomatik bulur)',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: search),
                ),
              ),
              if (msg.isNotEmpty) Padding(padding: const EdgeInsets.all(14), child: Text(msg, style: muted)),
              Expanded(
                child: ListView.builder(
                  itemCount: res.length,
                  itemBuilder: (_, i) {
                    final x = res[i];
                    final tags = <String?>[
                      x['IsHashMatch'] == true
                          ? '⭐ Tam senkron'
                          : (x['IsReleaseMatch'] == true ? '🎯 Sürüm eşleşti' : null),
                      '${x['Provider'] ?? ''}',
                      '${x['LanguageName'] ?? x['Language'] ?? ''}',
                      if (x['HearingImpaired'] == true) 'İşitme engelli',
                      if (x['DownloadCount'] != null) '${x['DownloadCount']} indirme',
                    ].whereType<String>().where((s) => s.isNotEmpty).join(' • ');
                    return ListTile(
                      dense: true,
                      enabled: loadingId == null,
                      title: Text('${x['ReleaseName'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(loadingId == '${x['Id']}' ? 'İndiriliyor…' : tags, style: muted),
                      onTap: () => download(x),
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

  Future<void> _episodesSheet() async {
    hideT?.cancel();
    final cur = it;
    final season = cur?['ParentIndexNumber'];
    final list = eps.where((e) => e['ParentIndexNumber'] == season).toList();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF20B1024),
      constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.sizeOf(context).height * .9),
      builder: (c) => SafeArea(
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final e = list[i];
            final now = e['Id'] == cur?['Id'];
            final tag = (e['ImageTags'] as Map?)?['Primary'];
            return ListTile(
              selected: now,
              selectedTileColor: Colors.white10,
              leading: SizedBox(
                width: 96,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                        color: kCard,
                        child: tag != null ? netImg(api.image(e['Id'], 'Primary', tag: tag, w: 300)) : null),
                  ),
                ),
              ),
              title: Text('${e['IndexNumber'] ?? ''}. ${e['Name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(rt(e['RunTimeTicks']), style: const TextStyle(color: kMuted)),
              onTap: () {
                Navigator.pop(c);
                if (!now) _start(e);
              },
            );
          },
        ),
      ),
    );
    _armHide();
  }

  // =================== çizim ===================
  @override
  Widget build(BuildContext context) {
    final c = vc;
    final i = it;
    final seg = _activeSeg();
    final nearEnd = dur > Duration.zero && dur - pos < const Duration(seconds: 40);
    final showNext = nextEp != null && (nearEnd || seg?.type == 'Outro');
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
        onTap: () => ui ? setState(() => ui = false) : _showUI(),
        onDoubleTapDown: (d) => tapAt = d.localPosition,
        onDoubleTap: () => _seekBy(tapAt.dx < MediaQuery.sizeOf(context).width / 2 ? -10 : 10),
        child: Stack(children: [
          // video
          Center(
            child: c != null && c.value.isInitialized
                ? AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))
                : const SizedBox.shrink(),
          ),
          // altyazı
          if (cue != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              left: 48,
              right: 48,
              bottom: ui ? 110 : 30,
              child: Text(
                cue,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21 * api.subSize,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.25,
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black),
                    Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1)),
                    Shadow(blurRadius: 2, color: Colors.black, offset: Offset(-1, -1)),
                  ],
                ),
              ),
            ),
          if (buffering && err.isEmpty) const Center(child: CircularProgressIndicator(color: Colors.white)),
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
          // kontroller
          IgnorePointer(
            ignoring: !ui,
            child: AnimatedOpacity(
              opacity: ui ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
                    stops: [0, .25, .65, 1],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Column(children: [
                      Row(children: [
                        IconButton(icon: const Icon(Icons.close, size: 28), onPressed: _close),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            if (sub.isNotEmpty)
                              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFCFD5EA), fontSize: 13)),
                          ]),
                        ),
                        if (eps.length > 1) IconButton(icon: const Icon(Icons.video_library_outlined), tooltip: 'Bölümler', onPressed: _episodesSheet),
                        IconButton(icon: const Icon(Icons.subtitles_outlined), tooltip: 'Ses ve altyazı', onPressed: _tracksSheet),
                      ]),
                      const Spacer(),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton(iconSize: 40, icon: const Icon(Icons.replay_10), onPressed: () => _seekBy(-10)),
                        const SizedBox(width: 40),
                        IconButton(
                            iconSize: 64,
                            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            onPressed: _togglePlay),
                        const SizedBox(width: 40),
                        IconButton(iconSize: 40, icon: const Icon(Icons.forward_10), onPressed: () => _seekBy(10)),
                      ]),
                      const Spacer(),
                      Row(children: [
                        SizedBox(width: 62, child: Text(fmt(dragging ? Duration(milliseconds: (dragV * 1000).round()) : pos), style: const TextStyle(fontSize: 13))),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              overlayShape: SliderComponentShape.noOverlay,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            ),
                            child: Slider(
                              value: curV.clamp(0, maxV).toDouble(),
                              max: maxV,
                              onChangeStart: (v) {
                                hideT?.cancel();
                                setState(() {
                                  dragging = true;
                                  dragV = v;
                                });
                              },
                              onChanged: (v) => setState(() => dragV = v),
                              onChangeEnd: (v) {
                                vc?.seekTo(Duration(milliseconds: (v * 1000).round()));
                                setState(() => dragging = false);
                                _armHide();
                              },
                            ),
                          ),
                        ),
                        SizedBox(
                            width: 70,
                            child: Text('-${fmt(dur - pos)}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
          // giriş atla / sonraki bölüm
          Positioned(
            right: 40,
            bottom: ui ? 96 : 34,
            child: Row(children: [
              if (seg != null && !(showNext && seg.type == 'Outro'))
                _pill(seg.type == 'Intro' ? 'Girişi atla' : 'Jeneriği atla', () => vc?.seekTo(seg.b)),
              if (showNext) ...[
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
                FilledButton(onPressed: _close, child: const Text('Kapat')),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _pill(String t, VoidCallback f, {bool primary = false}) => Material(
        color: primary ? const Color(0xFFF9F9F9) : const Color(0xB3000000),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: primary ? Colors.transparent : Colors.white70, width: 1.5)),
        child: InkWell(
          onTap: f,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(t,
                style: TextStyle(
                    fontWeight: FontWeight.w700, letterSpacing: .6, color: primary ? Colors.black : Colors.white)),
          ),
        ),
      );

  Widget _ageCard(J i) {
    final k = ageKey(i['OfficialRating']);
    final ds = descs(i);
    final g = ((i['Genres'] as List?) ?? const []).take(3).join(', ');
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
      decoration: const BoxDecoration(
        color: Color(0xA6000000),
        border: Border(left: BorderSide(color: Colors.white, width: 4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (k != null) Padding(padding: const EdgeInsets.only(right: 8), child: AgeBadge(i['OfficialRating'], size: 38)),
        for (final d in ds) Padding(padding: const EdgeInsets.only(right: 8), child: DescIcon(d, size: 38)),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(k != null ? kAgeText[k]! : '${i['OfficialRating'] ?? 'İçerik uyarısı'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            if (ds.isNotEmpty)
              Text(ds.map((d) => kDesc[d]).join(' • '), style: const TextStyle(color: Color(0xFFCFD5EA), fontSize: 12)),
            if (g.isNotEmpty) Text(g, style: const TextStyle(color: Color(0xFFCFD5EA), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
