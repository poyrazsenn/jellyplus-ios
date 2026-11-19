import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'downloads.dart';
import 'main.dart' show LoginScreen, ProfilesScreen;
import 'nav.dart';
import 'player.dart' show subtitleText;
import 'scan.dart';
import 'seerr.dart';
import 'update.dart';
import 'util.dart';
import 'version.dart';
import 'widgets.dart';

const kSubLangs = {
  'off': 'Kapalı',
  'tr': 'Türkçe',
  'en': 'İngilizce',
  'de': 'Almanca',
  'fr': 'Fransızca',
  'es': 'İspanyolca',
  'it': 'İtalyanca',
  'pt': 'Portekizce',
  'ru': 'Rusça',
  'ar': 'Arapça',
  'fa': 'Farsça',
};

// ---------------- iOS Ayarlar yapı taşları ----------------
const _rowH = 48.0;
const _groupBg = Color(0xFF1C1C21);
const _sep = Color(0x1AFFFFFF);

/// Ayarlar uygulamasındaki gibi renkli kare simge
Widget _tile(IconData i, Color c) => Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
      child: Icon(i, size: 18, color: Colors.white),
    );

Widget _head(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 7),
      child: Text(t, style: const TextStyle(fontSize: 13, color: Color(0x8CF5F5F7), letterSpacing: .3)),
    );

Widget _foot(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(32, 7, 32, 0),
      child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0x73F5F5F7))),
    );

/// Yuvarlak köşeli grup; satırların arasına ince çizgi
Widget _group(List<Widget> rows) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: _groupBg, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Padding(padding: EdgeInsets.only(left: 58), child: Divider(height: .5, thickness: .5, color: _sep)),
          rows[i],
        ],
      ]),
    );

class _Row extends StatefulWidget {
  final Widget? lead;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final Color? color;
  const _Row({this.lead, required this.label, this.value, this.trailing, this.onTap, this.chevron = true, this.color});
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final tap = widget.onTap;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: tap == null ? null : (_) => setState(() => down = true),
      onTapCancel: () => setState(() => down = false),
      onTapUp: (_) => setState(() => down = false),
      onTap: tap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              tap();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        color: down ? const Color(0x14FFFFFF) : Colors.transparent,
        constraints: const BoxConstraints(minHeight: _rowH),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          if (widget.lead != null) ...[widget.lead!, const SizedBox(width: 14)],
          Expanded(
            child: Text(widget.label, style: TextStyle(fontSize: 16, color: widget.color ?? const Color(0xFFF5F5F7))),
          ),
          if (widget.value != null)
            Flexible(
              child: Text(widget.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 16, color: Color(0x8CF5F5F7))),
            ),
          if (widget.trailing != null) widget.trailing!,
          if (widget.chevron && tap != null && widget.trailing == null)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.chevron_right_rounded, size: 17, color: Color(0x59F5F5F7)),
            ),
        ]),
      ),
    );
  }
}

Widget _toggle(Widget lead, String label, bool v, ValueChanged<bool> f) => _Row(
      lead: lead,
      label: label,
      chevron: false,
      trailing: CupertinoSwitch(value: v, activeColor: const Color(0xFF34C759), onChanged: (x) {
        HapticFeedback.selectionClick();
        f(x);
      }),
    );

/// Büyük başlıklı iOS sayfası; kaydırınca başlık küçülüp buğulu çubuğa yerleşir.
class _IosPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool back;
  const _IosPage({required this.title, required this.children, this.trailing, this.back = true});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        body: CustomScrollView(slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(title, style: const TextStyle(color: Color(0xFFF5F5F7))),
            backgroundColor: const Color(0xCC0B0B0D),
            border: null,
            automaticallyImplyLeading: back,
            previousPageTitle: back ? 'Geri' : null,
            trailing: trailing,
          ),
          SliverList.list(children: [...children, const SizedBox(height: 40)]),
        ]),
      );
}

// ---------------- Profil ----------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final api = Api.I;

  void toRoot(Widget w) => Navigator.of(context, rootNavigator: true)
      .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => w), (_) => false);

  Future<void> push(Widget w) async {
    await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => w));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(api.url)?.host ?? api.url;
    return _IosPage(
      title: 'Profil',
      back: false,
      trailing: GlassIcon(Icons.close_rounded, size: 32, tooltip: 'Kapat', onTap: () => tabBus.value = 0),
      children: [
        const SizedBox(height: 6),
        // profil kartı
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(color: _groupBg, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF34506B), Color(0xFF16222E)]),
              ),
              alignment: Alignment.center,
              child: Text(api.name.isEmpty ? '?' : api.name[0].toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(api.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${api.admin ? 'Yönetici · ' : ''}$host',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0x8CF5F5F7))),
              ]),
            ),
            Pressable(
              onTap: () => toRoot(const ProfilesScreen()),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0x24FFFFFF), borderRadius: BorderRadius.circular(16)),
                child: const Text('Profil değiştir', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),

        _head('OYNATMA'),
        _group([
          _Row(
            lead: _tile(Icons.subtitles_rounded, const Color(0xFF0A84FF)),
            label: 'Altyazı dili',
            value: kSubLangs[api.subLang] ?? api.subLang,
            onTap: () => push(const _SubLangPage()),
          ),
          _Row(
            lead: _tile(Icons.text_fields_rounded, const Color(0xFF5E5CE6)),
            label: 'Altyazı görünümü',
            onTap: () => push(const _SubStylePage()),
          ),
          _toggle(_tile(Icons.fast_forward_rounded, const Color(0xFFFF9F0A)), 'Giriş ve jeneriği atla', api.autoSkip,
              (v) => setState(() => api.autoSkip = v)),
          _toggle(_tile(Icons.skip_next_rounded, const Color(0xFF30B0C7)), 'Sonraki bölümü başlat', api.autoNext,
              (v) => setState(() => api.autoNext = v)),
        ]),
        _foot('Sonraki bölüm, jenerik başlayınca 10 saniyelik geri sayımla kendiliğinden başlar.'),

        _head('İNDİRMELER'),
        _group([
          _toggle(_tile(Icons.cloud_download_rounded, const Color(0xFF34C759)), 'Arka planda indir', Downloads.I.bgOn,
              (v) => setState(() => Downloads.I.bgOn = v)),
          _toggle(_tile(Icons.auto_delete_rounded, const Color(0xFFFF453A)), 'İzleyince sil', Downloads.I.autoDelete,
              (v) => setState(() => Downloads.I.autoDelete = v)),
        ]),
        _foot('Arka planda indirme telefon kilitliyken de sürer. Sorun olursa kapat; o zaman uygulama açıkken iner.'),

        _head('SUNUCU'),
        _group([
          if (api.admin)
            ListenableBuilder(
              listenable: Scanner.I,
              builder: (context, _) {
                final p = Scanner.I.progress;
                return _Row(
                  lead: _tile(Icons.manage_search_rounded, const Color(0xFF64D2FF)),
                  label: 'Kütüphaneyi tara',
                  value: p != null ? '%${p.round()}' : (Scanner.I.error.isNotEmpty ? 'Hata' : null),
                  chevron: false,
                  trailing: p != null
                      ? const Padding(padding: EdgeInsets.only(left: 8), child: CupertinoActivityIndicator(radius: 9))
                      : null,
                  onTap: p != null ? null : Scanner.I.scanAll,
                );
              },
            ),
          _Row(
            lead: _tile(Icons.playlist_add_rounded, const Color(0xFFBF5AF2)),
            label: 'Seerr',
            value: Seerr.I.on ? 'Bağlı' : 'Bağlı değil',
            onTap: () => push(const SeerrSettingsScreen()),
          ),
          if (Seerr.I.on)
            _Row(
              lead: _tile(Icons.playlist_add_check_rounded, const Color(0xFFFF375F)),
              label: 'İsteklerim',
              onTap: () => push(const RequestsScreen()),
            ),
        ]),

        _head('UYGULAMA'),
        _group([
          _Row(
            lead: _tile(Icons.auto_awesome_rounded, const Color(0xFF8E8E93)),
            label: 'Bu sürümdeki yenilikler',
            onTap: () => showWhatsNew(context, force: true),
          ),
        ]),

        const SizedBox(height: 28),
        Center(
          child: Pressable(
            onTap: () async {
              await api.logout();
              toRoot(api.accounts.isNotEmpty ? const ProfilesScreen() : const LoginScreen());
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 26),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0x24FF453A), borderRadius: BorderRadius.circular(22)),
              child: const Text('Çıkış yap', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFFF6961))),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Center(child: PMark(size: 26)),
        const SizedBox(height: 6),
        const Center(child: Text('Poyraz Player $kVersion', style: TextStyle(color: Color(0x66F5F5F7), fontSize: 12))),
      ],
    );
  }
}

// ---------------- Altyazı dili ----------------
class _SubLangPage extends StatefulWidget {
  const _SubLangPage();
  @override
  State<_SubLangPage> createState() => _SubLangPageState();
}

class _SubLangPageState extends State<_SubLangPage> {
  @override
  Widget build(BuildContext context) {
    final api = Api.I;
    return _IosPage(title: 'Altyazı dili', children: [
      const SizedBox(height: 6),
      _group([
        for (final e in kSubLangs.entries)
          _Row(
            label: e.value,
            chevron: false,
            trailing: e.key == api.subLang ? const Icon(Icons.check_rounded, size: 20, color: kAccent) : null,
            onTap: () => setState(() => api.subLang = e.key),
          ),
      ]),
      _foot('Oynatıcı bu dildeki altyazıyı kendiliğinden açar. Yoksa altyazı kapalı başlar.'),
    ]);
  }
}

// ---------------- Altyazı görünümü ----------------
class _SubStylePage extends StatefulWidget {
  const _SubStylePage();
  @override
  State<_SubStylePage> createState() => _SubStylePageState();
}

class _SubStylePageState extends State<_SubStylePage> {
  Widget _seg(List<String> opts, int cur, ValueChanged<int> f) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<int>(
            groupValue: cur,
            backgroundColor: const Color(0x1FFFFFFF),
            thumbColor: const Color(0xFF636366),
            children: {
              for (var i = 0; i < opts.length; i++)
                i: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(opts[i], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFF5F5F7))),
                ),
            },
            onValueChanged: (v) {
              if (v == null) return;
              HapticFeedback.selectionClick();
              setState(() => f(v));
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final api = Api.I;
    return _IosPage(title: 'Altyazı görünümü', children: [
      const SizedBox(height: 6),
      // önizleme
      Container(
        height: 150,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment(0, [0.78, 0.3, -0.18][api.subLift.clamp(0, 2)]),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D2B38), Color(0xFF3A4C5E), Color(0xFF6B5A48), Color(0xFF2A2018)],
          ),
        ),
        child: subtitleText('Altyazı böyle görünecek', scale: .8),
      ),
      _head('BOYUT'),
      _group([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            const Text('A', style: TextStyle(fontSize: 13, color: Color(0xB3F5F5F7))),
            Expanded(
              child: CupertinoSlider(
                value: api.subSize.clamp(.7, 1.8),
                min: .7,
                max: 1.8,
                divisions: 11,
                activeColor: const Color(0xFFF5F5F7),
                onChanged: (v) => setState(() => api.subSize = v),
              ),
            ),
            const Text('A', style: TextStyle(fontSize: 22, color: Color(0xB3F5F5F7))),
          ]),
        ),
      ]),
      _head('RENK'),
      _group([_seg(const ['Beyaz', 'Sarı'], api.subColor, (v) => api.subColor = v)]),
      _head('ARKA PLAN'),
      _group([_seg(const ['Gölge', 'Yarı saydam', 'Siyah kutu'], api.subBg, (v) => api.subBg = v)]),
      _head('KONUM'),
      _group([_seg(const ['Alt', 'Biraz yukarı', 'Yukarı'], api.subLift, (v) => api.subLift = v)]),
      _foot('Ayarlar bir sonraki oynatmada değil, hemen geçerli olur.'),
    ]);
  }
}
