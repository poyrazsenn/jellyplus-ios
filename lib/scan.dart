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

