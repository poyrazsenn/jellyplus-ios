import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'util.dart';

/// Jellyfin kütüphane taraması (yalnızca yönetici). Yeni indirilen dosyalar bilgisayara geçmeden kütüphaneye düşer.
class Scanner extends ChangeNotifier {
  Scanner._();
  static final Scanner I = Scanner._();

  Api get api => Api.I;

  /// null: çalışmıyor; 0–100: tüm kütüphane taraması sürüyor
  double? progress;
  String error = '';
  Timer? _poll;

  bool get running => progress != null;

  Future<void> scanAll() async {
    error = '';
    try {
      await api.post('/Library/Refresh');
      progress = 0;
      notifyListeners();
      _watch();
    } catch (e) {
      error = e is ApiError && (e.code == 401 || e.code == 403) ? 'Bunun için yönetici hesabı gerekiyor.' : 'Tarama başlatılamadı.';
      notifyListeners();
    }
  }

  /// Tek kütüphane (ya da dizi/klasör): sadece onun klasörlerine bakar, daha hızlıdır.
  Future<bool> scanOne(String id) async {
    try {
      await api.post('/Items/$id/Refresh?Recursive=true&MetadataRefreshMode=Default&ImageRefreshMode=Default'
          '&ReplaceAllMetadata=false&ReplaceAllImages=false');
      Timer(const Duration(seconds: 20), () => refreshBus.value++);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ayarlar açıldığında: arka planda (ör. web'den) başlamış bir tarama var mı?
  Future<void> check() async {
    final p = await _taskProgress();
    if (p != null && !running) {
      progress = p;
      notifyListeners();
      _watch();
    }
  }

  void _watch() {
    _poll?.cancel();
    var idle = 0;
    _poll = Timer.periodic(const Duration(seconds: 2), (t) async {
      final p = await _taskProgress();
      if (p == null) {
        // görev bazen birkaç saniye geç başlar
        if (++idle < 3 && (progress ?? 0) == 0) return;
        t.cancel();
        progress = null;
        refreshBus.value++;
      } else {
        idle = 0;
        progress = p;
      }
      notifyListeners();
    });
  }

  Future<double?> _taskProgress() async {
    try {
      final l = (await api.get('/ScheduledTasks?isHidden=false')) as List;
      for (final t in l) {
        if (t is Map && t['Key'] == 'RefreshLibrary') {
          if (t['State'] != 'Running') return null;
          return ((t['CurrentProgressPercentage'] as num?) ?? 0).toDouble();
        }
      }
    } catch (_) {}
    return null;
  }
}

/// Profil sekmesindeki "Kütüphaneyi tara" satırı.
class ScanTile extends StatefulWidget {
  const ScanTile({super.key});
  @override
  State<ScanTile> createState() => _ScanTileState();
}

class _ScanTileState extends State<ScanTile> {
  @override
  void initState() {
    super.initState();
    Scanner.I.check();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Scanner.I,
      builder: (context, _) {
        final s = Scanner.I;
        final p = s.progress;
        return ListTile(
          leading: const Icon(Icons.manage_search),
          title: const Text('Kütüphaneyi tara'),
          subtitle: p != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Taranıyor %${p.round()}', style: const TextStyle(color: kMuted, fontSize: 12)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                        value: p > 0 ? p / 100 : null, minHeight: 3, color: kBlue, backgroundColor: Colors.white12),
                  ]),
                )
              : Text(s.error.isNotEmpty ? s.error : 'Sunucuya yeni eklenen dosyaları bulur',
                  style: TextStyle(color: s.error.isNotEmpty ? const Color(0xFFFF8A8A) : kMuted)),
          trailing: p != null ? null : const Icon(Icons.play_arrow),
          onTap: p != null ? null : s.scanAll,
        );
      },
    );
  }
}
