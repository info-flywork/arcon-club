import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
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
          theme: arconTheme(Brightness.light, mono: widget.config.appKey == 'arconnect'),
          darkTheme: arconTheme(Brightness.dark, mono: widget.config.appKey == 'arconnect'),
          themeMode: mode,
          // Tarih seçici vb. sistem metinleri Türkçe
          locale: const Locale('tr'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ListenableBuilder(
            listenable: _session,
            builder: (context, _) => switch (_session.status) {
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

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: ArconLogo(height: 28)));
}
