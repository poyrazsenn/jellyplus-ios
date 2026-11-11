import 'dart:async';

import 'package:video_player/video_player.dart';

import 'api.dart';

/// Detay sayfasında çalan tema müziği (Themerr eklentisinin indirdiği şarkılar).
/// Uygulamada tek bir tane çalar; yeni sayfa açılınca eskisi susar.
class ThemeMusic {
  ThemeMusic._();
  static final ThemeMusic I = ThemeMusic._();

  VideoPlayerController? _c;
  String? owner, songId;
  Timer? _fade;
  static const double volume = .35;

  /// Şarkı varsa true döner (çalmasa bile — kullanıcı kapatmış olabilir).
  Future<bool> start(String ownerId) async {
    final api = Api.I;
    List<J> r;
    try {
      r = await api.items('/Items/$ownerId/ThemeSongs?UserId=${api.uid}&InheritFromParent=true');
    } catch (_) {
      return false;
    }
    if (r.isEmpty) return false;
    if (!api.themeOn) return true;
    final id = '${r.first['Id']}';
    if (songId == id && _c != null) {
      owner = ownerId;
      _fadeTo(volume, 800);
      return true;
    }
    await stop(hard: true);
    owner = ownerId;
    songId = id;
    final c = VideoPlayerController.networkUrl(
      Uri.parse('${api.url}/Audio/$id/stream?static=true&MediaSourceId=$id&ApiKey=${api.token}'),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _c = c;
    try {
      await c.initialize();
    } catch (_) {
      if (_c == c) _c = null;
      c.dispose();
      return true;
    }
    if (_c != c || owner != ownerId) {
      c.dispose();
      return true;
    }
    await c.setLooping(true);
    await c.setVolume(0);
    await c.play();
    _fadeTo(volume, 2000);
    return true;
  }

  void _fadeTo(double to, int ms) {
    _fade?.cancel();
    final c = _c;
    if (c == null) return;
    final from = c.value.volume;
    final t0 = DateTime.now();
    _fade = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final k = (DateTime.now().difference(t0).inMilliseconds / ms).clamp(0.0, 1.0);
      c.setVolume(from + (to - from) * k);
      if (k >= 1) t.cancel();
    });
  }

  /// [ifOwner] verilirse sadece o sayfanın müziğiyse durdurur.
  Future<void> stop({bool hard = false, String? ifOwner}) async {
    if (ifOwner != null && owner != ifOwner) return;
    final c = _c;
    owner = null;
    songId = null;
    _c = null;
    _fade?.cancel();
    if (c == null) return;
    if (hard) {
      await c.dispose();
      return;
    }
    final from = c.value.volume;
    final t0 = DateTime.now();
    Timer.periodic(const Duration(milliseconds: 50), (t) {
      final k = (DateTime.now().difference(t0).inMilliseconds / 700).clamp(0.0, 1.0);
      c.setVolume(from * (1 - k));
      if (k >= 1) {
        t.cancel();
        c.dispose();
      }
    });
  }
}
