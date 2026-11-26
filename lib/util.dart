import 'package:flutter/material.dart';

import 'api.dart';

// Poyraz Player · A · Cam tasarım sistemi
const kBg = Color(0xFF0B0B0D); // zemin
const kBar = Color(0xF20B0B0D);
const kCard = Color(0xFF1C1C21); // kart / görsel yer tutucu
const kSheet = Color(0xFF1C1C21); // alttan açılan sayfalar
const kBlue = Color(0xFFF5F5F7); // birincil (beyaz düğmeler, ilerleme)
const kInk = Color(0xFF0B0B0D); // beyaz zemin üstündeki yazı
const kAccent = Color(0xFFFFC98F); // sıcak ışık (logo üçgeni, vurgular)
const kMuted = Color(0xFF9C9CA6);
const kGlass = Color(0x9926262C); // buğulu cam dolgusu

/// iPad (ya da geniş pencere): üst sekme kapsülü
bool wideLayout(BuildContext c) => MediaQuery.sizeOf(c).width > 700;

/// Yatay iPad: iki sütunlu detay sayfası
bool isSplit(BuildContext c) => MediaQuery.sizeOf(c).width >= 900;

double hPad(BuildContext c) => MediaQuery.sizeOf(c).width > 700 ? 28 : 16;

/// Bir sırada kaç kart görünsün: telefon ~2.15, iPad ~3.3, geniş ~5.25
double cardWidth(BuildContext c) {
  final w = MediaQuery.sizeOf(c).width;
  final per = w > 1000 ? 5.25 : (w > 700 ? 3.3 : 2.15);
  return (w - 2 * hPad(c) - 12 * per.floor()) / per;
}

String rt(num? ticks) {
  if (ticks == null || ticks == 0) return '';
  final m = (ticks / 6e8).round();
  return m >= 60 ? '${m ~/ 60} sa ${m % 60} dk' : '$m dk';
}

String fmt(Duration d) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, x = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(x)}' : '$m:${two(x)}';
}

Duration ticks(dynamic t) => Duration(microseconds: ((t is num ? t : 0) / 10).round());

// ---------- yaş sınırı ----------
String? ageKey(String? r) {
  final s = (r ?? '').trim().toUpperCase();
  if (s.isEmpty) return null;
  if (RegExp(r'^(G|TV-G|TV-Y|U|ALL|GENEL|0|TR-?GENEL|TR-?ALL)$').hasMatch(s)) return 'all';
  if (RegExp(r'^(TV-Y7|TV-Y7-FV|PG|TV-PG|7\+?|TR-?7\+?|6|8|9|10)$').hasMatch(s)) return '7';
  if (RegExp(r'^(PG-13|TV-14|12A?|12\+?|13\+?|14\+?|15\+?|16\+?|TR-?(13|15)\+?)$').hasMatch(s)) return '13';
  if (RegExp(r'^(R|NC-17|TV-MA|X|18\+?|TR-?18\+?|NR18|ADULT)$').hasMatch(s)) return '18';
  final m = RegExp(r'^\d+').firstMatch(s);
  if (m == null) return null;
  final n = int.parse(m.group(0)!);
  return n <= 0 ? 'all' : (n <= 9 ? '7' : (n <= 17 ? '13' : '18'));
}

/// Apple TV gibi düz yaş etiketi: 13+, Genel
String? ageLabel(String? r) {
  final k = ageKey(r);
  if (k == null) return null;
  return k == 'all' ? 'Genel' : '$k+';
}

const kAgeText = {
  'all': 'Genel izleyici kitlesi',
  '7': '7 yaş ve üzeri',
  '13': '13 yaş ve üzeri',
  '18': '18 yaş ve üzeri'
};

// ---------- içerik işaretleri (web istemcisiyle aynı etiketler: jp-siddet ...) ----------
const kDesc = {
  'siddet': 'Şiddet / Korku',
  'cinsellik': 'Cinsellik',
  'olumsuz': 'Olumsuz örnek olabilecek davranışlar'
};

List<String> descs(J? it) {
  final tags = (it?['Tags'] as List?) ?? const [];
  return tags
      .map((e) => '$e')
      .where((t) => t.startsWith('jp-') && kDesc.containsKey(t.substring(3)))
      .map((t) => t.substring(3))
      .toList();
}

// ---------- görsel seçimi ----------
class WideImg {
  final String url;
  final bool art; // görselin içinde zaten film adı/logosu var
  final bool poster;
  const WideImg(this.url, {this.art = false, this.poster = false});
}

WideImg wideImg(J it) {
  final a = Api.I;
  if ('${it['_img'] ?? ''}'.isNotEmpty) return WideImg('${it['_img']}');
  final t = (it['ImageTags'] as Map?) ?? const {};
  final bdt = (it['BackdropImageTags'] as List?) ?? const [];
  final pbdt = (it['ParentBackdropImageTags'] as List?) ?? const [];
  if (it['Type'] == 'Episode' && t['Primary'] != null) {
    return WideImg(a.image(it['Id'], 'Primary', tag: t['Primary']));
  }
  if (t['Thumb'] != null) return WideImg(a.image(it['Id'], 'Thumb', tag: t['Thumb']), art: true);
  if (it['ParentThumbImageTag'] != null && it['ParentThumbItemId'] != null) {
    return WideImg(a.image(it['ParentThumbItemId'], 'Thumb', tag: it['ParentThumbImageTag']), art: true);
  }
  if (bdt.isNotEmpty) return WideImg(a.image(it['Id'], 'Backdrop', tag: bdt.first));
  if (pbdt.isNotEmpty && it['ParentBackdropItemId'] != null) {
    return WideImg(a.image(it['ParentBackdropItemId'], 'Backdrop', tag: pbdt.first));
  }
  if (t['Primary'] != null) return WideImg(a.image(it['Id'], 'Primary', tag: t['Primary'], w: 500), poster: true);
  if (it['SeriesPrimaryImageTag'] != null && it['SeriesId'] != null) {
    return WideImg(a.image(it['SeriesId'], 'Primary', tag: it['SeriesPrimaryImageTag'], w: 500), poster: true);
  }
  return const WideImg('');
}

String? logoUrl(J it, {int w = 500}) {
  final t = (it['ImageTags'] as Map?) ?? const {};
  if (t['Logo'] != null) return Api.I.image(it['Id'], 'Logo', tag: t['Logo'], w: w);
  if (it['ParentLogoImageTag'] != null && it['ParentLogoItemId'] != null) {
    return Api.I.image(it['ParentLogoItemId'], 'Logo', tag: it['ParentLogoImageTag'], w: w);
  }
  return null;
}

String backdrop(J it, {int w = 1600}) {
  final a = Api.I;
  final bdt = (it['BackdropImageTags'] as List?) ?? const [];
  final pbdt = (it['ParentBackdropImageTags'] as List?) ?? const [];
  final t = (it['ImageTags'] as Map?) ?? const {};
  if (bdt.isNotEmpty) return a.image(it['Id'], 'Backdrop', tag: bdt.first, w: w);
  if (pbdt.isNotEmpty && it['ParentBackdropItemId'] != null) {
    return a.image(it['ParentBackdropItemId'], 'Backdrop', tag: pbdt.first, w: w);
  }
  if (t['Primary'] != null) return a.image(it['Id'], 'Primary', tag: t['Primary'], w: w);
  return '';
}

const kFields = 'Overview,Genres,OfficialRating,Tags';
