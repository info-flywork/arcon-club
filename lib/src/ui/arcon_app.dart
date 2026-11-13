import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../auth/token_store.dart';
import '../config.dart';
import '../push/local_notifier.dart';
import '../push/push_service.dart';
import '../talk/talk_home_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'theme.dart';
import 'theme_scope.dart';

/// Uygulamanın kökü. Oturum durumuna göre giriş ekranı ya da ana ekran gösterir.
class ArconApp extends StatefulWidget {
  const ArconApp({super.key, required this.config, this.session});

  final ArconAppConfig config;

  /// Testlerde sahte oturum vermek için; normalde null.
  final SessionController? session;

  @override
  State<ArconApp> createState() => _ArconAppState();
}

class _ArconAppState extends State<ArconApp> {
  final _theme = ArconThemeController();
  final _nav = GlobalKey<NavigatorState>();
  SessionStatus? _lastStatus;

  late final SessionController _session =
      widget.session ??
      SessionController(
        api: ArconApi(
          baseUrl: widget.config.apiBase,
          appKey: widget.config.appKey,
        ),
        store: SecureTokenStore('arcon_token_${widget.config.appKey}'),
      );

  /// Splash en az bu kadar görünür (oturum daha önce hazır olsa bile).
  static const _minSplash = Duration(milliseconds: 1500);
  bool _splashMinDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(_minSplash, () {
      if (mounted) setState(() => _splashMinDone = true);
    });
    if (widget.session == null) {
      _session.restore();
    }
    _session.addListener(_onSession);
    PushService.onOpenTalk = _openTalkFromPush;
  }

  /// Çıkış (uygulamadan, webdeki "Çıkış Yap"tan veya oturum süresi dolunca):
  /// üstte açık modül ekranlarını kapat, giriş ekranı görünsün.
  void _onSession() {
    final s = _session.status;
    if (s == SessionStatus.signedOut && _lastStatus == SessionStatus.signedIn) {
      _nav.currentState?.popUntil((r) => r.isFirst);
      PushService.stop();
      LocalNotifier.stop();
    }
    if (s == SessionStatus.signedIn && _lastStatus != SessionStatus.signedIn) {
      PushService.start(_session, enabled: widget.config.push, apiBase: widget.config.apiBase);
      LocalNotifier.start(_session, baseUrl: widget.config.apiBase);
      // Debug: bildirim dokunmasını taklit et (--dart-define=ARCON_TEST_OPEN_TALK=<kanal id>)
      const testCh = int.fromEnvironment('ARCON_TEST_OPEN_TALK');
      if (kDebugMode && testCh > 0) {
        Future.delayed(const Duration(seconds: 2), () => PushService.requestOpenTalk(testCh));
      }
    }
    _lastStatus = s;
  }

  /// Bildirime dokunuldu, ARCONNECT ekranı açık değil (Club) → ARCONNECT'i aç; sohbeti o açar.
  void _openTalkFromPush(int channelId) {
    if (TalkHomeScreen.mounted > 0) return; // açık ekran kendisi açar
    final nav = _nav.currentState;
    if (nav == null || _session.status != SessionStatus.signedIn) return;
    nav.push(MaterialPageRoute(
      builder: (_) => TalkHomeScreen(session: _session, config: widget.config, appMode: false),
    ));
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ArconThemeScope(
      controller: _theme,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _theme,
        builder: (context, mode, _) => MaterialApp(
          navigatorKey: _nav,
          title: widget.config.title,
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: mode,
          // Tema geçişi anında olsun: varsayılan 200 ms'lik ara renk animasyonu her karede
          // tüm uygulamayı yeniden kurar, koyu temaya geçerken takılmaya yol açıyordu.
          themeAnimationDuration: Duration.zero,
          // Tarih seçici vb. sistem metinleri Türkçe
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ListenableBuilder(
            listenable: _session,
            builder: (context, _) => switch (_session.status) {
              _ when !_splashMinDone => const _Splash(),
              SessionStatus.loading => const _Splash(),
              SessionStatus.signedOut => LoginScreen(
                config: widget.config,
                session: _session,
              ),
              SessionStatus.signedIn => HomeScreen(
                config: widget.config,
                session: _session,
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Açılış: sistem açılış ekranıyla birebir aynı yerde başlar (zıplama yok), sonra
/// yazı hafifçe nefes alır ve altında ince bir yükleme çizgisi belirir.
// Temalar bir kez kurulur (her tema değişiminde yeniden oluşturulmaz)
final ThemeData _lightTheme = arconTheme(Brightness.light, mono: true);
final ThemeData _darkTheme = arconTheme(Brightness.dark, mono: true);

class _Splash extends StatefulWidget {
  const _Splash();

  static const bg = Color(0xFF050608);

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  bool _showBar = false;

  @override
  void initState() {
    super.initState();
    // Oturum hemen açılırsa çizgi hiç görünmesin
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showBar = true);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _Splash.bg,
        body: Stack(
          alignment: Alignment.center,
          children: [
            // Üstten hafif ışık (giriş ekranındaki gibi)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.9),
                    radius: 1.1,
                    colors: [const Color(0xFF3A4352).withValues(alpha: 0.35), _Splash.bg.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _a,
              builder: (_, child) => Opacity(
                opacity: reduce ? 1 : 0.82 + 0.18 * Curves.easeInOut.transform(_a.value),
                child: child,
              ),
              child: Image.asset('assets/splash_mark.png', width: 120, semanticLabel: 'ARCON CLUB'),
            ),
            Align(
              alignment: const Alignment(0, 0.22),
              child: AnimatedOpacity(
                opacity: _showBar ? 1 : 0,
                duration: const Duration(milliseconds: 400),
                child: SizedBox(
                  width: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(minHeight: 2, color: Colors.white, backgroundColor: Color(0x1FFFFFFF)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
