import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
      'MediaBrowser Client="Jelly+ iOS", Device="iPhone", DeviceId="$deviceId", Version="1.0.0"'
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

  Future<dynamic> _send(String m, String p, [Object? body]) async {
    final u = Uri.parse('$url$p');
    const t = Duration(seconds: 25);
    late http.Response r;
    if (m == 'GET') {
      r = await http.get(u, headers: headers).timeout(t);
    } else if (m == 'POST') {
      r = await http
          .post(u, headers: headers, body: body == null ? null : jsonEncode(body))
          .timeout(t);
    } else {
      r = await http.delete(u, headers: headers).timeout(t);
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
    final r = await http.get(Uri.parse(fullUrl), headers: headers).timeout(const Duration(seconds: 25));
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
  set subLang(String v) => prefs.setString('psub', v);
  bool get autoSkip => prefs.getBool('auto') ?? false;
  set autoSkip(bool v) => prefs.setBool('auto', v);
  double get subSize => prefs.getDouble('subsize') ?? 1.0;
  set subSize(double v) => prefs.setDouble('subsize', v);

  // ---------- görseller ----------
  String image(String id, String type, {String? tag, int w = 640}) =>
      '$url/Items/$id/Images/$type?maxWidth=$w&quality=90${tag != null ? '&tag=$tag' : ''}';
  String avatar(Account a) => '${a.url}/Users/${a.uid}/Images/Primary?maxWidth=240';
}
