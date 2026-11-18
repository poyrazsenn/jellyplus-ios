import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'api.dart';
import 'downloads.dart';
import 'downloads_screen.dart';
import 'home.dart';
import 'library.dart';
import 'nav.dart';
import 'player.dart' show subtitleText;
import 'scan.dart';
import 'search.dart';
import 'seerr.dart';
import 'theme_music.dart';
import 'update.dart';
import 'util.dart';
import 'version.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await Api.I.init();
  try {
    await Downloads.I.init();
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  final v = WidgetsBinding.instance.platformDispatcher.views.first;
  isTablet = v.physicalSize.shortestSide / v.devicePixelRatio > 600;
  await allowAppOrientations();
  runApp(const JellyPlus());
}

bool isTablet = false;

/// Uygulama telefonda dikey; oynatıcı kendi içinde yatay yapar.
Future<void> allowAppOrientations() => SystemChrome.setPreferredOrientations(
    isTablet ? DeviceOrientation.values : [DeviceOrientation.portraitUp]);

class JellyPlus extends StatelessWidget {
  const JellyPlus({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Api.I;
    final Widget start;
    if (a.accounts.length > 1 || (a.accounts.isNotEmpty && !a.loggedIn)) {
      start = const ProfilesScreen();
    } else if (a.loggedIn) {
      start = const Shell();
    } else {
      start = const LoginScreen();
    }
    return MaterialApp(
      title: 'Poyraz Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kBlue, surface: kSheet),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFFF5F5F7)),
        ),
        useMaterial3: true,
        // iOS hissi: dalga efekti yok, iOS sayfa geçişleri, yuvarlak sayfalar, kapsül düğmeler
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x14FFFFFF),
        canvasColor: kBg,
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        }),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: kSheet,
          modalBackgroundColor: kSheet,
          showDragHandle: true,
          dragHandleColor: Color(0x4DF5F5F7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A2A30),
          contentTextStyle: const TextStyle(color: Color(0xFFF5F5F7), fontSize: 14),
          actionTextColor: kAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(backgroundColor: kBlue, foregroundColor: kInk, shape: const StadiumBorder()),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), shape: const StadiumBorder()),
        ),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Colors.white)),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: Colors.white),
        dividerTheme: const DividerThemeData(color: Color(0x14FFFFFF)),
        listTileTheme: const ListTileThemeData(iconColor: Color(0xCCF5F5F7)),
        chipTheme: const ChipThemeData(shape: StadiumBorder(), side: BorderSide(color: Colors.white24)),
      ),
      home: start,
    );
  }
}

// ======================= Giriş =======================
class LoginScreen extends StatefulWidget {
  final String? server, user;
  const LoginScreen({super.key, this.server, this.user});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final srv = TextEditingController(
      text: widget.server ?? (Api.I.accounts.isNotEmpty ? Api.I.accounts.last.url : Api.defaultServer));
  late final usr = TextEditingController(text: widget.user ?? '');
  final pwd = TextEditingController();
  bool busy = false;
  String err = '';

  Future<void> go() async {
    setState(() {
      busy = true;
      err = '';
    });
    try {
      await Api.I.login(srv.text, usr.text.trim(), pwd.text);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
    } catch (e) {
      setState(() => err = e is ApiError ? '$e' : 'Sunucuya ulaşılamadı. Adresi kontrol et.\n($e)');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  InputDecoration deco(String l) => InputDecoration(
        labelText: l,
        filled: true,
        fillColor: Colors.white.withAlpha(20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final canBack = Navigator.of(context).canPop();
    return Scaffold(
      appBar: canBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Center(child: Logo(size: 44)),
                const SizedBox(height: 32),
                TextField(controller: srv, decoration: deco('Sunucu adresi'), keyboardType: TextInputType.url, autocorrect: false),
                const SizedBox(height: 12),
                TextField(controller: usr, decoration: deco('Kullanıcı adı'), autocorrect: false, textCapitalization: TextCapitalization.none),
                const SizedBox(height: 12),
                TextField(controller: pwd, decoration: deco('Şifre'), obscureText: true, onSubmitted: (_) => go()),
                if (err.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 14), child: Text(err, style: const TextStyle(color: Color(0xFFFF8A8A)))),
                const SizedBox(height: 22),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const StadiumBorder()),
                  onPressed: busy ? null : go,
                  child: busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kInk))
                      : const Text('Giriş yap', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kInk)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= Profiller =======================
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool edit = false;
  static const colors = [Color(0xFF0063E5), Color(0xFFE5484D), Color(0xFF30A46C), Color(0xFFD98E04), Color(0xFF8E4EC6), Color(0xFF12A594)];

  Future<void> pick(Account a) async {
    final api = Api.I;
    if (edit) {
      await api.removeAccount(a);
      if (api.accounts.isEmpty && mounted) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
        return;
      }
      setState(() {});
      return;
    }
    if (a.token.isEmpty) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoginScreen(server: a.url, user: a.name)));
      return;
    }
    api.use(a);
    try {
      await api.loadMe();
    } catch (e) {
      if (e is ApiError && e.code == 401 && mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoginScreen(server: a.url, user: a.name)));
        return;
      }
      // ağ hatası: yine de devam et, ana sayfa hata gösterir
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final acc = Api.I.accounts;
    final size = MediaQuery.sizeOf(context).width > 700 ? 120.0 : 92.0;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment.topCenter, radius: 1.3, colors: [Color(0xFF1B2A5C), kBg])),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(edit ? 'Profilleri düzenle' : 'Kim izliyor?',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                const SizedBox(height: 32),
                Wrap(spacing: 22, runSpacing: 22, alignment: WrapAlignment.center, children: [
                  for (var i = 0; i < acc.length; i++)
                    GestureDetector(
                      onTap: () => pick(acc[i]),
                      child: SizedBox(
                        width: size + 10,
                        child: Column(children: [
                          Stack(children: [
                            CircleAvatar(
                              radius: size / 2,
                              backgroundColor: colors[i % colors.length],
                              child: ClipOval(
                                child: SizedBox.expand(
                                  child: Stack(fit: StackFit.expand, children: [
                                    Center(
                                        child: Text(acc[i].name.isEmpty ? '?' : acc[i].name[0].toUpperCase(),
                                            style: TextStyle(fontSize: size * .42, fontWeight: FontWeight.w700, color: Colors.white))),
                                    CachedNetworkImage(
                                        imageUrl: Api.I.avatar(acc[i]),
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => const SizedBox.shrink()),
                                  ]),
                                ),
                              ),
                            ),
                            if (edit)
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
                                  child: const Icon(Icons.close, size: 34),
                                ),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          Text(acc[i].name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Color(0xFFCFD5EA))),
                        ]),
                      ),
                    ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: SizedBox(
                      width: size + 10,
                      child: Column(children: [
                        CircleAvatar(
                            radius: size / 2,
                            backgroundColor: Colors.white.withAlpha(20),
                            child: Icon(Icons.add, size: size * .4, color: Colors.white)),
                        const SizedBox(height: 10),
                        const Text('Profil ekle', style: TextStyle(fontSize: 15, color: Color(0xFFCFD5EA))),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 34),
                OutlinedButton(
                  onPressed: () => setState(() => edit = !edit),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                  child: Text(edit ? 'Bitti' : 'Profilleri düzenle'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= Ana çerçeve (sekmeler) =======================
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 0;
  static const dlTab = 3;
  final keys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  bool offline = false;
  StreamSubscription<List<ConnectivityResult>>? _net;

  static bool _isOff(List<ConnectivityResult> r) => r.isEmpty || r.every((x) => x == ConnectivityResult.none);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tabBus.addListener(_onTabBus);
    // Netflix gibi: internet kesildiği an İndirilenler'e geç
    Connectivity().checkConnectivity().then((r) {
      if (_isOff(r)) _goOffline();
    }).catchError((_) {});
    _net = Connectivity().onConnectivityChanged.listen((r) {
      _isOff(r) ? _goOffline() : _goOnline();
    }, onError: (_) {});
    Api.I.loadMe().then((_) {
      _online();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showWhatsNew(context);
        if (mounted) await checkUpdate(context);
      });
    }).catchError((e) {
      if (!mounted) return;
      if (e is ApiError && e.code == 401) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => LoginScreen(server: Api.I.url, user: Api.I.name)), (_) => false);
      } else if (e is! ApiError && Downloads.I.hasDone) {
        // sunucuya ulaşılamıyor: indirilenlerle devam
        setState(() => tab = dlTab);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sunucuya ulaşılamadı. İndirdiklerini izleyebilirsin.'), duration: Duration(seconds: 4)));
      }
    });
  }

  void _goTab(int i) {
    if (i == tab) {
      keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      ThemeMusic.I.stop();
      setState(() => tab = i);
    }
  }

  void _onTabBus() {
    final t = tabBus.value;
    if (t == null) return;
    tabBus.value = null;
    _goTab(t);
  }

  /// A · Cam: ekranın altında havada duran buğulu cam şerit. Profil sağ üstteki düğmeden açılır.
  Widget _glassBar(BuildContext context) {
    const items = [
      [Icons.home_outlined, Icons.home_rounded, 'Ana sayfa'],
      [Icons.search_rounded, Icons.search_rounded, 'Ara'],
      [Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Listem'],
      [Icons.download_outlined, Icons.download_rounded, 'İndirilenler'],
    ];
    final wide = MediaQuery.sizeOf(context).width > 700;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 460 : 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Glass(
              radius: 32,
              color: const Color(0xC726262C),
              child: SizedBox(
                height: 62,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  for (var i = 0; i < items.length; i++)
                    Semantics(
                      button: true,
                      selected: tab == i,
                      label: items[i][2] as String,
                      child: Pressable(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _goTab(i);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 58,
                          height: 44,
                          decoration: BoxDecoration(
                            color: tab == i ? Colors.white.withAlpha(42) : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon((tab == i ? items[i][1] : items[i][0]) as IconData,
                              size: 25, color: tab == i ? Colors.white : const Color(0x99F5F5F7)),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tabBus.removeListener(_onTabBus);
    _net?.cancel();
    super.dispose();
  }

  void _goOffline() {
    if (!mounted || offline) return;
    ThemeMusic.I.stop(hard: true);
    setState(() {
      offline = true;
      tab = dlTab;
    });
    keys[dlTab].currentState?.popUntil((r) => r.isFirst);
  }

  void _goOnline() {
    if (!mounted || !offline) return;
    setState(() => offline = false);
    _online();
    refreshBus.value++;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('İnternet geri geldi.'),
      duration: const Duration(seconds: 4),
      action: tab == 0 ? null : SnackBarAction(label: 'Ana sayfa', onPressed: () => setState(() => tab = 0)),
    ));
  }

  /// Sunucuya ulaşılınca: bekleyen çevrimdışı ilerlemeyi yaz, yarım indirmeleri sürdür.
  void _online() {
    Downloads.I.sync();
    Downloads.I.retryFailed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _online();
  }

  Widget tabNav(int i, Widget root) => Navigator(
        key: keys[i],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        keys[tab].currentState?.maybePop();
      },
      child: Scaffold(
        body: IndexedStack(index: tab, children: [
          tabNav(0, const HomeScreen()),
          tabNav(1, const SearchScreen()),
          tabNav(2, const LibraryScreen(title: 'Listem', extra: '&IsFavorite=true', root: true)),
          tabNav(3, const DownloadsScreen()),
          tabNav(4, const SettingsScreen()),
        ]),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: offline
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                    decoration: BoxDecoration(color: const Color(0xFF26262C), borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(children: [
                      const Icon(Icons.cloud_off, size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            Downloads.I.hasDone ? 'Çevrimdışısın. İndirdiklerini izleyebilirsin.' : 'Çevrimdışısın. İnternet yokken indirdiklerin burada olur.',
                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
          _glassBar(context),
        ]),
      ),
    );
  }
}

// ======================= Profil / Ayarlar =======================
const kSubLangs = {
  'off': 'Kapalı',
  'tr': 'Türkçe',
  'en': 'English',
  'de': 'Almanca',
  'fr': 'Fransızca',
  'es': 'İspanyolca',
  'it': 'İtalyanca',
  'pt': 'Portekizce',
  'ru': 'Rusça',
  'ar': 'Arapça',
  'fa': 'Farsça',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final api = Api.I;

  void toRoot(Widget w) => Navigator.of(context, rootNavigator: true)
      .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => w), (_) => false);

  Future<void> chooseLang() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kSheet,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Otomatik altyazı dili', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          for (final e in kSubLangs.entries)
            ListTile(
              title: Text(e.value),
              trailing: e.key == api.subLang ? const Icon(Icons.check, color: kBlue) : null,
              onTap: () => Navigator.pop(c, e.key),
            ),
        ]),
      ),
    );
    if (v != null) setState(() => api.subLang = v);
  }

  Widget _head(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(t, style: const TextStyle(color: kMuted, fontSize: 12, letterSpacing: 1.4)),
      );

  Widget _choice(String label, List<String> opts, int cur, void Function(int) set) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(children: [
          SizedBox(width: 78, child: Text(label)),
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (var i = 0; i < opts.length; i++)
                ChoiceChip(
                  label: Text(opts[i], style: const TextStyle(fontSize: 12)),
                  selected: cur == i,
                  onSelected: (_) => setState(() => set(i)),
                ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GlassIcon(Icons.close_rounded, size: 34, tooltip: 'Kapat', onTap: () => tabBus.value = 0),
          ),
        ],
      ),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: kBlue,
            child: Text(api.name.isEmpty ? '?' : api.name[0].toUpperCase(),
                style: const TextStyle(color: kInk, fontWeight: FontWeight.w700)),
          ),
          title: Text(api.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(api.url, style: const TextStyle(color: kMuted)),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.switch_account),
          title: const Text('Profil değiştir'),
          onTap: () => toRoot(const ProfilesScreen()),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text('OYNATMA', style: TextStyle(color: kMuted, fontSize: 12, letterSpacing: 1.4)),
        ),
        ListTile(
          leading: const Icon(Icons.subtitles_outlined),
          title: const Text('Otomatik altyazı dili'),
          subtitle: Text(kSubLangs[api.subLang] ?? api.subLang, style: const TextStyle(color: kMuted)),
          onTap: chooseLang,
        ),
        ListTile(
          leading: const Icon(Icons.format_size),
          title: const Text('Altyazı boyutu'),
          subtitle: Slider(
            value: api.subSize.clamp(.7, 1.8),
            min: .7,
            max: 1.8,
            divisions: 11,
            label: '${(api.subSize * 100).round()}%',
            onChanged: (v) => setState(() => api.subSize = v),
          ),
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.fast_forward_outlined),
          title: const Text('Giriş ve jeneriği otomatik atla'),
          value: api.autoSkip,
          onChanged: (v) => setState(() => api.autoSkip = v),
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.skip_next_outlined),
          title: const Text('Sonraki bölümü otomatik başlat'),
          subtitle: const Text('Jenerikte 10 saniyelik geri sayım', style: TextStyle(color: kMuted)),
          value: api.autoNext,
          onChanged: (v) => setState(() => api.autoNext = v),
        ),
        _head('ALTYAZI GÖRÜNÜMÜ'),
        Container(
          height: 90,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          alignment: Alignment(0, [0.75, 0.25, -0.25][api.subLift.clamp(0, 2)]),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(colors: [Color(0xFF2A3B5C), Color(0xFF6B7C93), Color(0xFF34404F)]),
          ),
          child: subtitleText('Altyazı böyle görünecek', scale: .75),
        ),
        _choice('Renk', ['Beyaz', 'Sarı'], api.subColor, (v) => api.subColor = v),
        _choice('Arka plan', ['Gölge', 'Yarı saydam', 'Siyah kutu'], api.subBg, (v) => api.subBg = v),
        _choice('Konum', ['Alt', 'Biraz yukarı', 'Yukarı'], api.subLift, (v) => api.subLift = v),
        if (api.admin) ...[
          _head('SUNUCU'),
          const ScanTile(),
        ],
        _head('İNDİRMELER'),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.auto_delete_outlined),
          title: const Text('İzleyince sil'),
          subtitle: const Text('İzlenen indirmeler oynatıcı kapanınca silinir', style: TextStyle(color: kMuted)),
          value: Downloads.I.autoDelete,
          onChanged: (v) => setState(() => Downloads.I.autoDelete = v),
        ),
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.cloud_download_outlined),
          title: const Text('Arka planda indir'),
          subtitle: const Text('Telefon kilitliyken ve uygulama kapalıyken de sürer. Sorun olursa kapat; 2.0\'daki gibi uygulama açıkken iner.',
              style: TextStyle(color: kMuted)),
          value: Downloads.I.bgOn,
          onChanged: (v) => setState(() => Downloads.I.bgOn = v),
        ),
        _head('İSTEKLER (SEERR)'),
        if (Seerr.I.on)
          ListTile(
            leading: const Icon(Icons.playlist_add_check),
            title: const Text('İsteklerim'),
            subtitle: const Text('Bekliyor / indiriliyor / hazır', style: TextStyle(color: kMuted)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RequestsScreen())),
          ),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('Seerr bağlantısı'),
          subtitle: Text(Seerr.I.on ? Seerr.I.url : 'Bağlı değil', style: const TextStyle(color: kMuted)),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeerrSettingsScreen()));
            if (mounted) setState(() {});
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.new_releases_outlined),
          title: const Text('Bu sürümdeki yenilikler'),
          onTap: () => showWhatsNew(context, force: true),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Color(0xFFFF8A8A)),
          title: const Text('Çıkış yap', style: TextStyle(color: Color(0xFFFF8A8A))),
          onTap: () async {
            await api.logout();
            toRoot(api.accounts.isNotEmpty ? const ProfilesScreen() : const LoginScreen());
          },
        ),
        const SizedBox(height: 20),
        const Center(child: Text('Poyraz Player $kVersion', style: TextStyle(color: kMuted, fontSize: 12))),
        const SizedBox(height: 30),
      ]),
    );
  }
}
