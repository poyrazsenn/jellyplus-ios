import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'version.dart';

typedef J = Map<String, dynamic>;

/// Oynatıcı kapanınca ana sayfa / detay sayfası kendini yenilesin diye.
final refreshBus = ValueNotifier<int>(0);

class ApiError implements Exception {
  final int code;
  ApiError(this.code);
  @override
  String toString() =>
      code == 401 ? 'Kullanıcı adı veya şifre hatalı (401)' : 'Sunucu hatası ($code)';
}

class Account {
  String url, uid, name, token;
  Account({required this.url, required this.uid, required this.name, this.token = ''});
  J toJson() => {'url': url, 'uid': uid, 'name': name, 'token': token};
  static Account fromJson(J j) => Account(
      url: '${j['url'] ?? ''}',
      uid: '${j['uid'] ?? ''}',
      name: '${j['name'] ?? ''}',
      token: '${j['token'] ?? ''}');
}

class Api {
  Api._();
  static final Api I = Api._();

  late SharedPreferences prefs;
  String url = '', uid = '', token = '', name = '', deviceId = '';
  bool admin = false;

  static const defaultServer = 'http://87.76.146.176:8096';

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('dev') ?? '';
    if (deviceId.isEmpty) {
      final r = Random.secure();
      deviceId = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString('dev', deviceId);
    }
    final c = prefs.getString('cur');
    if (c != null) {
      for (final a in accounts) {
        if ('${a.url}|${a.uid}' == c) use(a);
      }
    }
  }

  // ---------- hesaplar / profiller ----------
  List<Account> get accounts {
    try {
      final l = jsonDecode(prefs.getString('acc') ?? '[]') as List;
      return l.map((e) => Account.fromJson(J.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAccounts(List<Account> a) =>
      prefs.setString('acc', jsonEncode(a.map((e) => e.toJson()).toList()));

  void use(Account a) {
    url = a.url;
    uid = a.uid;
    name = a.name;
    token = a.token;
  }

  bool get loggedIn => token.isNotEmpty && uid.isNotEmpty;

  Future<void> upsertCurrent() async {
    final a = accounts;
    final i = a.indexWhere((x) => x.url == url && x.uid == uid);
    final e = Account(url: url, uid: uid, name: name, token: token);
    if (i >= 0) {
      a[i] = e;
    } else {
      a.add(e);
    }
    await saveAccounts(a);
    await prefs.setString('cur', '$url|$uid');
  }

  Future<void> removeAccount(Account x) async {
    final a = accounts..removeWhere((e) => e.url == x.url && e.uid == x.uid);
    await saveAccounts(a);
    if (x.url == url && x.uid == uid) {
      token = '';
      uid = '';
    }
  }

  // ---------- HTTP ----------
  String get _auth =>
      'MediaBrowser Client="Poyraz Player", Device="iPhone", DeviceId="$deviceId", Version="$kVersion"'
      '${token.isNotEmpty ? ', Token="$token"' : ''}';

  Map<String, String> get headers =>
      {'Content-Type': 'application/json', 'Authorization': _auth, 'X-Emby-Authorization': _auth};

  static String normalize(String s) {
    s = s.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    final u = Uri.tryParse(s);
    // Sadece IP yazıldıysa Jellyfin'in varsayılan portunu ekle
    if (u != null &&
        u.scheme == 'http' &&
        !u.hasPort &&
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(u.host)) {
      s = 'http://${u.host}:8096${u.path}';
    }
    return s;
  }

  // Tek, kalıcı bağlantı havuzu: bağlantı kurulamazsa 8 sn'de vazgeçer, boşta kalan bağlantıyı 15 sn'de kapatır.
  static http.Client _newClient() => IOClient(HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 15));
  http.Client _c = _newClient();

  /// Uygulama arka plandan dönünce: kopmuş olabilecek eski bağlantıları bırak.
  void resetConnections() {
    final old = _c;
    _c = _newClient();
    Future.delayed(const Duration(seconds: 30), () {
      try {
        old.close();
      } catch (_) {}
    });
  }

  static bool _transient(Object e) =>
      e is TimeoutException || e is SocketException || e is HttpException || e is http.ClientException || e is HandshakeException;

  Future<dynamic> _send(String m, String p, [Object? body]) async {
    final u = Uri.parse('$url$p');
    late http.Response r;
    // GET bir kez kendiliğinden yeniden denenir (yeni bağlantıyla); POST/DELETE tekrarlanmaz.
    for (var attempt = 0;; attempt++) {
      try {
        if (m == 'GET') {
          r = await _c.get(u, headers: headers).timeout(const Duration(seconds: 15));
        } else if (m == 'POST') {
          r = await _c
              .post(u, headers: headers, body: body == null ? null : jsonEncode(body))
              .timeout(const Duration(seconds: 20));
        } else {
          r = await _c.delete(u, headers: headers).timeout(const Duration(seconds: 20));
        }
        break;
      } catch (e) {
        if (m != 'GET' || attempt >= 1 || !_transient(e)) rethrow;
        resetConnections();
      }
    }
    if (r.statusCode >= 400) throw ApiError(r.statusCode);
    if (r.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> get(String p) => _send('GET', p);
  Future<dynamic> post(String p, [Object? b]) => _send('POST', p, b);
  Future<dynamic> delete(String p) => _send('DELETE', p);

  Future<String> getText(String fullUrl) async {
    final r = await _c.get(Uri.parse(fullUrl), headers: headers).timeout(const Duration(seconds: 15));
    if (r.statusCode >= 400) throw ApiError(r.statusCode);
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// Listeyi ya da {Items:[...]} döndüren uçlar için.
  Future<List<J>> items(String p) async {
    final r = await get(p);
    final List l = r is List ? r : ((r is Map ? r['Items'] : null) as List? ?? const []);
    return l.map((e) => J.from(e as Map)).toList();
  }

  Future<J> item(String id) async => J.from(await get('/Users/$uid/Items/$id') as Map);

  // ---------- oturum ----------
  Future<void> login(String server, String user, String pw) async {
    url = normalize(server);
    token = '';
    final r = await post('/Users/AuthenticateByName', {'Username': user, 'Pw': pw});
    token = '${r['AccessToken']}';
    uid = '${r['User']['Id']}';
    name = '${r['User']['Name'] ?? user}';
    admin = r['User']['Policy']?['IsAdministrator'] == true;
    await upsertCurrent();
  }

  Future<void> loadMe() async {
    final me = await get('/Users/$uid');
    name = '${me['Name'] ?? name}';
    admin = me['Policy']?['IsAdministrator'] == true;
    await upsertCurrent();
    unawaited(pullShared());
  }

  Future<void> logout() async {
    try {
      await post('/Sessions/Logout');
    } catch (_) {}
    final a = accounts;
    for (final x in a) {
      if (x.url == url && x.uid == uid) x.token = '';
    }
    await saveAccounts(a);
    token = '';
  }

  // ---------- tercihler ----------
  String get subLang => prefs.getString('psub') ?? 'tr';
  set subLang(String v) {
    prefs.setString('psub', v);
    sharedChanged();
  }
  bool get autoSkip => prefs.getBool('auto') ?? false;
  set autoSkip(bool v) {
    prefs.setBool('auto', v);
    sharedChanged();
  }
  bool get themeOn => prefs.getBool('theme') ?? true;
  set themeOn(bool v) {
    prefs.setBool('theme', v);
    sharedChanged();
  }
  bool get compat => prefs.getBool('compat') ?? false;
  set compat(bool v) {
    prefs.setBool('compat', v);
    sharedChanged();
  }
  double get subSize => prefs.getDouble('subsize') ?? 1.0;
  set subSize(double v) {
    prefs.setDouble('subsize', v);
    sharedChanged();
  }
  /// 0 beyaz, 1 sarı
  int get subColor => prefs.getInt('subcolor') ?? 0;
  set subColor(int v) {
    prefs.setInt('subcolor', v);
    sharedChanged();
  }
  /// 0 gölge, 1 yarı saydam kutu, 2 siyah kutu
  int get subBg => prefs.getInt('subbg') ?? 0;
  set subBg(int v) {
    prefs.setInt('subbg', v);
    sharedChanged();
  }
  /// 0 alt, 1 biraz yukarı, 2 yukarı
  int get subLift => prefs.getInt('sublift') ?? 0;
  set subLift(int v) {
    prefs.setInt('sublift', v);
    sharedChanged();
  }
  bool get autoNext => prefs.getBool('autonext') ?? true;
  set autoNext(bool v) {
    prefs.setBool('autonext', v);
    sharedChanged();
  }

  // ---------- ortak ayarlar (Jellyfin hesabında saklanır) ----------
  /// Telefonda, iPad'de ve yeni kurulumda aynı gelsin diye Jellyfin'in DisplayPreferences'ına yazılır.
  static const _shared = {
    'psub': 's', 'auto': 'b', 'autonext': 'b', 'theme': 'b', 'compat': 'b',
    'subsize': 'd', 'subcolor': 'i', 'subbg': 'i', 'sublift': 'i',
  };
  static const _dpPath = '/DisplayPreferences/poyraz?client=poyraz';
  Timer? _pushT;
  bool _pulling = false;

  void sharedChanged() {
    if (_pulling || token.isEmpty) return;
    _pushT?.cancel();
    _pushT = Timer(const Duration(seconds: 2), pushShared);
  }

  Future<void> pushShared() async {
    try {
      final d = await get('$_dpPath&userId=$uid');
      final m = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
      final cp = Map<String, dynamic>.from((m['CustomPrefs'] as Map?) ?? const {});
      for (final k in _shared.keys) {
        final v = prefs.get(k);
        if (v != null) cp['p_$k'] = '$v';
      }
      cp['p_at'] = '${DateTime.now().millisecondsSinceEpoch}';
      m
        ..['CustomPrefs'] = cp
        ..['Id'] = m['Id'] ?? 'poyraz'
        ..['Client'] = 'poyraz';
      await post('$_dpPath&userId=$uid', m);
    } catch (_) {}
  }

  /// Girişte: hesaptaki ayarları al. Hesapta hiç yoksa bu cihazdakileri yükle.
  Future<void> pullShared() async {
    try {
      final d = await get('$_dpPath&userId=$uid');
      final cp = (d is Map ? d['CustomPrefs'] as Map? : null) ?? const {};
      if (!cp.keys.any((k) => '$k'.startsWith('p_'))) {
        await pushShared();
        return;
      }
      _pulling = true;
      for (final e in _shared.entries) {
        final v = cp['p_${e.key}'];
        if (v == null) continue;
        final t = '$v';
        switch (e.value) {
          case 's':
            await prefs.setString(e.key, t);
          case 'b':
            await prefs.setBool(e.key, t == 'true');
          case 'd':
            final x = double.tryParse(t);
            if (x != null) await prefs.setDouble(e.key, x);
          case 'i':
            final x = int.tryParse(t);
            if (x != null) await prefs.setInt(e.key, x);
        }
      }
    } catch (_) {
    } finally {
      _pulling = false;
    }
  }

  // ---------- görseller ----------
  String image(String id, String type, {String? tag, int w = 640}) =>
      '$url/Items/$id/Images/$type?maxWidth=$w&quality=90${tag != null ? '&tag=$tag' : ''}';
  String avatar(Account a) => '${a.url}/Users/${a.uid}/Images/Primary?maxWidth=240';
}
