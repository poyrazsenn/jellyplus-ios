import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'api.dart';
import 'downloads.dart';
import 'downloads_screen.dart';
import 'explore.dart';
import 'home.dart';
import 'library.dart';
import 'nav.dart';
import 'player.dart' show subtitleText;
import 'scan.dart';
import 'search.dart';
import 'settings.dart';
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
        colorScheme: const ColorScheme.dark(primary: kBlue, onPrimary: kInk, secondary: kBlue, onSecondary: kInk, secondaryContainer: kBlue, onSecondaryContainer: kInk, surface: kSheet),
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
          backgroundColor: const Color(0xF22C2C32),
          contentTextStyle: const TextStyle(color: Color(0xFFF5F5F7), fontSize: 14),
          actionTextColor: kAccent,
          shape: const StadiumBorder(),
          insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
          elevation: 0,
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
        chipTheme: const ChipThemeData(shape: StadiumBorder(), side: BorderSide(color: Colors.white24), showCheckmark: false, selectedColor: kBlue, secondaryLabelStyle: TextStyle(color: kInk, fontWeight: FontWeight.w600)),
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

  @override
  Widget build(BuildContext context) {
    final canBack = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        Container(
          height: 420,
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(.6, -1), radius: 1.1, colors: [Color(0x40FFD6AA), Color(0x00FFD6AA)]),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Center(child: PMark(size: 72)),
                  const SizedBox(height: 18),
                  const Text('Poyraz Player', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.8)),
                  const SizedBox(height: 6),
                  const Text('Jellyfin sunucuna giriş yap', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Color(0x99F5F5F7))),
                  const SizedBox(height: 30),
                  IosField(srv, 'Sunucu adresi', keyboardType: TextInputType.url, action: TextInputAction.next),
                  const SizedBox(height: 10),
                  IosField(usr, 'Kullanıcı adı', action: TextInputAction.next),
                  const SizedBox(height: 10),
                  IosField(pwd, 'Şifre', obscure: true, action: TextInputAction.go, onSubmitted: (_) => go()),
                  if (err.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 14), child: Text(err, style: const TextStyle(color: Color(0xFFFF8A8A)))),
                  const SizedBox(height: 22),
                  PillButton('Giriş yap', height: 54, expand: true, busy: busy, onTap: go),
                ]),
              ),
            ),
          ),
        ),
        if (canBack)
          Positioned(
            left: 14,
            top: MediaQuery.paddingOf(context).top + 8,
            child: GlassIcon(Icons.arrow_back_ios_new_rounded, tooltip: 'Geri', onTap: () => Navigator.of(context).maybePop()),
          ),
      ]),
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
  static const colors = [Color(0xFF3E5C77), Color(0xFF6B5A48), Color(0xFF2E4B3C), Color(0xFF4A3F6B), Color(0xFF5B3A2E), Color(0xFF3A3F57)];

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
      backgroundColor: kBg,
      body: Container(
        decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(.5, -1.1), radius: 1.2, colors: [Color(0x38FFD6AA), Color(0x000B0B0D)])),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Text(edit ? 'Profilleri düzenle' : 'Kim izliyor?',
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.8)),
                const SizedBox(height: 32),
                Wrap(spacing: 22, runSpacing: 22, alignment: WrapAlignment.center, children: [
                  for (var i = 0; i < acc.length; i++)
                    Pressable(
                      haptic: true,
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
                          Text(acc[i].name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, color: Color(0xB8F5F5F7))),
                        ]),
                      ),
                    ),
                  Pressable(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: SizedBox(
                      width: size + 10,
                      child: Column(children: [
                        CircleAvatar(
                            radius: size / 2,
                            backgroundColor: Colors.white.withAlpha(20),
                            child: Icon(Icons.add, size: size * .4, color: Colors.white)),
                        const SizedBox(height: 10),
                        const Text('Profil ekle', style: TextStyle(fontSize: 15, color: Color(0xB8F5F5F7))),
                      ]),
                    ),
                  ),
                ]),
                const SizedBox(height: 34),
                Pressable(
                  onTap: () => setState(() => edit = !edit),
                  child: Glass(
                    radius: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                    child: Text(edit ? 'Bitti' : 'Profilleri düzenle', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
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
  final keys = List.generate(6, (_) => GlobalKey<NavigatorState>());
  // Sekmelerin ekrandaki sırası → IndexedStack içindeki yeri (Keşfet 5'te)
  static const order = [0, 5, 1, 2, 3];
  bool offline = false;
  DateTime? _pausedAt;
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
      [Icons.explore_outlined, Icons.explore_rounded, 'Keşfet'],
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
                      selected: tab == order[i],
                      label: items[i][2] as String,
                      child: Pressable(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _goTab(order[i]);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 54,
                          height: 44,
                          decoration: BoxDecoration(
                            color: tab == order[i] ? Colors.white.withAlpha(42) : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon((tab == order[i] ? items[i][1] : items[i][0]) as IconData,
                              size: 25, color: tab == order[i] ? Colors.white : const Color(0x99F5F5F7)),
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

  /// iPad: üstte logo, ortada cam sekme kapsülü, sağda profil.
  Widget _topBar(BuildContext context) {
    const labels = ['Ana sayfa', 'Keşfet', 'Ara', 'Listem', 'İndirilenler'];
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 8, 36, 0),
        child: SizedBox(
          height: 50,
          child: Stack(alignment: Alignment.center, children: [
            Row(children: [
              const Logo(size: 20),
              const Spacer(),
              Semantics(
                button: true,
                selected: tab == 4,
                label: 'Profil',
                child: Pressable(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _goTab(4);
                  },
                  child: Glass(
                    radius: 20,
                    color: tab == 4 ? const Color(0x52FFFFFF) : kGlass,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Text(Api.I.name.isEmpty ? '?' : Api.I.name[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
            Glass(
              radius: 26,
              color: const Color(0xB326262C),
              padding: const EdgeInsets.all(5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < labels.length; i++)
                  Semantics(
                    button: true,
                    selected: tab == order[i],
                    label: labels[i],
                    child: Pressable(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _goTab(order[i]);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tab == order[i] ? Colors.white.withAlpha(46) : Colors.transparent,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Text(labels[i],
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: tab == order[i] ? FontWeight.w600 : FontWeight.w500,
                                color: tab == order[i] ? const Color(0xFFF5F5F7) : const Color(0xB3F5F5F7))),
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
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
    if (s == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (s == AppLifecycleState.resumed) {
      // 30 sn'den uzun arka planda kaldıysa eski bağlantılar ölmüş olabilir
      if (_pausedAt != null && DateTime.now().difference(_pausedAt!).inSeconds > 30) Api.I.resetConnections();
      _pausedAt = null;
      _online();
    }
  }

  Widget tabNav(int i, Widget root) => Navigator(
        key: keys[i],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
      );

  @override
  Widget build(BuildContext context) {
    final tablet = wideLayout(context);
    final mq = MediaQuery.of(context);
    // Görünmeyen sekmelerde animasyonlar ve zamanlayıcılar durur (pil)
    Widget t(int i, Widget w) => TickerMode(enabled: tab == i, child: tabNav(i, w));
    final stack = IndexedStack(index: tab, children: [
      t(0, const HomeScreen()),
      t(1, const SearchScreen()),
      t(2, const LibraryScreen(title: 'Listem', extra: '&IsFavorite=true', root: true)),
      t(3, const DownloadsScreen()),
      t(4, const SettingsScreen()),
      t(5, const ExploreScreen()),
    ]);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        keys[tab].currentState?.maybePop();
      },
      child: Scaffold(
        body: tablet
            ? Stack(children: [
                // sayfalar, üst çubuğun altından başlasın diye üst boşluk büyütülür
                MediaQuery(
                  data: mq.copyWith(
                    padding: mq.padding.copyWith(top: mq.padding.top + 60),
                    viewPadding: mq.viewPadding.copyWith(top: mq.viewPadding.top + 60),
                  ),
                  child: stack,
                ),
                Positioned(left: 0, right: 0, top: 0, child: _topBar(context)),
              ])
            : stack,
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
          if (!tablet) _glassBar(context) else SizedBox(height: mq.padding.bottom),
        ]),
      ),
    );
  }
}

