import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'home.dart';
import 'library.dart';
import 'search.dart';
import 'theme_music.dart';
import 'util.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.I.init();
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
      title: 'Jelly+',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kBlue, surface: Color(0xFF0E1328)),
        appBarTheme: const AppBarTheme(backgroundColor: kBg, elevation: 0, scrolledUnderElevation: 0),
        useMaterial3: true,
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: busy ? null : go,
                  child: busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('GİRİŞ YAP', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.4, color: Colors.white)),
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

class _ShellState extends State<Shell> {
  int tab = 0;
  final keys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    Api.I.loadMe().catchError((e) {
      if (e is ApiError && e.code == 401 && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => LoginScreen(server: Api.I.url, user: Api.I.name)), (_) => false);
      }
    });
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
          tabNav(3, const SettingsScreen()),
        ]),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(splashColor: Colors.transparent, highlightColor: Colors.transparent),
          child: BottomNavigationBar(
            currentIndex: tab,
            type: BottomNavigationBarType.fixed,
            backgroundColor: kBar,
            selectedItemColor: Colors.white,
            unselectedItemColor: const Color(0xFF8A93AE),
            selectedFontSize: 11,
            unselectedFontSize: 11,
            onTap: (i) {
              if (i == tab) {
                keys[i].currentState?.popUntil((r) => r.isFirst);
              } else {
                ThemeMusic.I.stop();
                setState(() => tab = i);
              }
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Ana sayfa'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Ara'),
              BottomNavigationBarItem(icon: Icon(Icons.add), activeIcon: Icon(Icons.check), label: 'Listem'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profil'),
            ],
          ),
        ),
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
      backgroundColor: const Color(0xFF0E1328),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: kBlue,
            child: Text(api.name.isEmpty ? '?' : api.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
        SwitchListTile(
          secondary: const Icon(Icons.fast_forward_outlined),
          title: const Text('Giriş ve jeneriği otomatik atla'),
          value: api.autoSkip,
          onChanged: (v) => setState(() => api.autoSkip = v),
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
        const Center(child: Text('Jelly+ iOS 1.0', style: TextStyle(color: kMuted, fontSize: 12))),
        const SizedBox(height: 30),
      ]),
    );
  }
}
