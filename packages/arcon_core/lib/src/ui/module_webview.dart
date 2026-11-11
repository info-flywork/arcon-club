import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../talk/talk_home_screen.dart';
import '../todo/todo_board_screen.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import 'theme_scope.dart';

/// Bir web modülünü uygulama içinde açar. Kullanıcı tekrar şifre girmez:
/// API'den tek kullanımlık giriş linki alınır, WebView normal web oturumuyla açılır.
class ModuleWebView extends StatefulWidget {
  const ModuleWebView({
    super.key,
    required this.module,
    required this.session,
    required this.config,
    this.onHistoryChanged,
    this.onHome,
    this.isHome = false,
  });

  final ArconModule module;
  final SessionController session;
  final ArconAppConfig config;

  /// Her sayfa yüklemesinden sonra: WebView'de geri gidilecek sayfa var mı?
  final ValueChanged<bool>? onHistoryChanged;

  /// Webdeki logo / Dashboard linkine dokunulunca (uygulamanın ana ekranına dön).
  final VoidCallback? onHome;

  /// Ana ekran (Dashboard): başka sayfaya giden linkler yeni ekranda açılır,
  /// böylece iOS'ta kenardan kaydırarak Dashboard'a dönülür.
  final bool isHome;

  @override
  State<ModuleWebView> createState() => ModuleWebViewState();
}

class ModuleWebViewState extends State<ModuleWebView> with AutomaticKeepAliveClientMixin {
  late final WebViewController _controller;
  late final Uri _appBase = Uri.parse(widget.config.apiBase);
  int _progress = 0;
  String? _error;
  int _reauthTries = 0;
  bool _loadedOnce = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Webdeki "Açık/Koyu tema" düğmesi → uygulamanın teması
      // Profil sayfasındaki fotoğraf kutusu → telefonun fotoğraf seçicisi (yalnızca uygulamada)
      ..addJavaScriptChannel('ArconProfilePhoto', onMessageReceived: (_) => _pickProfilePhoto())
      ..addJavaScriptChannel('ArconTheme', onMessageReceived: (m) {
        if (mounted) ArconThemeScope.of(context).setDark(m.message == 'dark');
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => mounted ? setState(() => _progress = p) : null,
        onPageFinished: (_) async {
          _reauthTries = 0;
          _loadedOnce = true;
          _injectAppStyles();
          _injectProfilePhoto();
          final cb = widget.onHistoryChanged;
          if (cb != null) cb(await _controller.canGoBack());
        },
        onNavigationRequest: _onNavigation,
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (mounted) setState(() => _error = 'Sayfa yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.');
          }
        },
      ));
    _start();
  }

  Future<void> _start() async {
    final ua = await _controller.getUserAgent();
    await _controller.setUserAgent('${ua ?? ''} ${widget.config.userAgentSuffix}'.trim());
    await _open(widget.module.path);
  }

  Future<void> _open(String path) async {
    if (mounted) setState(() => _error = null);
    try {
      final url = await widget.session.api.webSessionUrl(path);
      await _controller.loadRequest(url);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> reload() => _open(widget.module.path);

  /// Sunucudaki uygulamaya özel stilleri ekle (assets/mobile-app.css). Web sayfaları bu dosyayı
  /// yüklemez; görünüm ayarı sunucudan güncellenir, mağaza güncellemesi gerekmez.
  void _injectAppStyles() {
    final href = Uri.parse(widget.config.apiBase).resolve('assets/mobile-app.css').toString();
    final want = mounted && ArconThemeScope.of(context).isDark(context) ? 'dark' : 'light';
    _controller.runJavaScript('''
(function(){
  var d=document; if(!d||!d.documentElement) return;
  var root=d.documentElement;
  root.classList.add('arcon-mobile-app');
  if(!d.getElementById('arcon-mobile-app-css')){
    var l=d.createElement('link'); l.id='arcon-mobile-app-css'; l.rel='stylesheet';
    l.href=${jsonEncode(href)}+'?v='+Math.floor(Date.now()/600000);
    (d.head||d.documentElement).appendChild(l);
  }
  // Tema: uygulamayla aynı; webdeki tema düğmesi uygulamaya bildirir
  var want=${jsonEncode(want)}, btn=d.getElementById('themeToggle');
  if(btn && !btn.__arconHooked){
    btn.__arconHooked=1;
    btn.addEventListener('click',function(){setTimeout(function(){
      try{ArconTheme.postMessage(root.classList.contains('dark')?'dark':'light');}catch(e){}
    },0);});
  }
  if((want==='dark')!==root.classList.contains('dark')){
    if(btn){ btn.__arconSilent=1; btn.click(); }
    else { root.classList.toggle('dark', want==='dark'); try{localStorage.setItem('arcon-theme',want);}catch(e){} }
  }
})();''').catchError((_) {});
  }

  /// Profil sayfası (profile): baş harf kutusunu fotoğrafla göster, dokununca fotoğraf seç.
  void _injectProfilePhoto() {
    final url = widget.session.user?.avatarUrl;
    _controller.runJavaScript('''
(function(){
  var a=document.querySelector('.prof-aside__avatar'); if(!a) return;
  var url=${jsonEncode(url)};
  a.classList.add('arcon-app-avatar');
  a.setAttribute('role','button'); a.setAttribute('aria-label','Profil fotoğrafını değiştir');
  if(url){ a.style.backgroundImage='url("'+url+'")'; a.classList.add('has-photo'); }
  else { a.style.backgroundImage=''; a.classList.remove('has-photo'); }
  if(!a.querySelector('.arcon-app-avatar__badge')){
    var b=document.createElement('span'); b.className='arcon-app-avatar__badge'; b.setAttribute('aria-hidden','true');
    b.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 4h-5L7.5 6.5H5A2 2 0 0 0 3 8.5v9A2 2 0 0 0 5 19.5h14a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2h-2.5z"/><circle cx="12" cy="13" r="3.5"/></svg>';
    a.appendChild(b);
  }
  if(!a.__arconHooked){
    a.__arconHooked=1;
    a.addEventListener('click',function(){ try{ArconProfilePhoto.postMessage('pick');}catch(e){} });
    var h=document.createElement('small'); h.className='arcon-app-avatar__hint';
    h.textContent='Fotoğrafı değiştirmek için dokun';
    a.insertAdjacentElement('afterend',h);
  }
})();''').catchError((_) {});
  }

  Future<void> _pickProfilePhoto() async {
    if (!mounted) return;
    final hasPhoto = widget.session.user?.avatarUrl != null;
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Profil fotoğrafı'),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'gallery'), child: const Text('Fotoğraf Arşivi')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'camera'), child: const Text('Fotoğraf Çek')),
          if (hasPhoto)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Fotoğrafı Kaldır'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'remove') {
        await widget.session.api.removeAvatar();
      } else {
        final x = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85,
        );
        if (x == null) return;
        await widget.session.api.uploadAvatar(x.path);
      }
      await widget.session.refreshMe();
      _injectProfilePhoto();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(choice == 'remove' ? 'Profil fotoğrafı kaldırıldı.' : 'Profil fotoğrafı güncellendi.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Fotoğrafa erişilemedi. Ayarlardan izin verip tekrar dene.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  /// Geri tuşu: önce WebView geçmişinde geri git.
  Future<bool> goBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return true;
    }
    return false;
  }

  ArconModule? _nativeModuleFor(Uri u) {
    final segs = u.pathSegments.where((p) => p.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    var first = segs.last;
    if (first.endsWith('.php')) first = first.substring(0, first.length - 4);
    for (final m in widget.session.modules) {
      if (m.render != 'native' || m.key == widget.module.key) continue;
      if (ModuleScreen.nativeBuilder(m, widget.config) == null) continue;
      final p = m.path.split('?').first.split('/').where((x) => x.isNotEmpty).lastOrNull;
      if (p != null && p == first) return m;
    }
    return null;
  }

  bool _isLoginPage(Uri u) {
    final base = _appBase.path.endsWith('/') ? _appBase.path : '${_appBase.path}/';
    return u.path == base || u.path == '${base}index' || u.path == '${base}index.php';
  }

  NavigationDecision _onNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;

    // Site dışı linkler, mailto/tel → telefonun kendi uygulaması
    final external = !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host != _appBase.host;
    if (external) {
      if (req.isMainFrame) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate; // gömülü iframe (ör. video) sayfanın içinde kalsın
    }

    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (last == 'logout' || last == 'logout.php') {
      widget.session.logout();
      return NavigationDecision.prevent;
    }
    // Uygulamada yerli ekranı olan modül (ARCONNECT, To-Do) linki → yerli ekranı aç
    if (req.isMainFrame && _loadedOnce) {
      final native = _nativeModuleFor(uri);
      if (native != null) {
        ModuleScreen.open(context, native, widget.session, widget.config);
        return NavigationDecision.prevent;
      }
    }
    // Ana ekrandan başka sayfaya → üstte yeni ekran (geri kaydırma ile Dashboard'a dönülür)
    if (widget.isHome && req.isMainFrame && _loadedOnce && !_isLoginPage(uri)) {
      final here = widget.module.path.split('?').first;
      final target = last.endsWith('.php') ? last.substring(0, last.length - 4) : last;
      if (target.isNotEmpty && target != here && target != 'mobile_open') {
        final base = _appBase.path.endsWith('/') ? _appBase.path : '${_appBase.path}/';
        var rel = uri.path.startsWith(base) ? uri.path.substring(base.length) : uri.path.replaceFirst('/', '');
        if (rel.endsWith('.php')) rel = rel.substring(0, rel.length - 4);
        if (uri.hasQuery) rel = '$rel?${uri.query}';
        ModuleScreen.open(
          context,
          ArconModule(key: 'link:$rel', title: '', group: 'link', icon: '', render: 'webview', path: rel, url: uri.toString()),
          widget.session,
          widget.config,
        );
        return NavigationDecision.prevent;
      }
    }
    // Webdeki logo / Dashboard → uygulamanın ana ekranı (Dashboard modülünün kendisi hariç)
    final isDashboard = last == 'dashboard' || last == 'dashboard.php';
    if (req.isMainFrame && isDashboard && _loadedOnce && widget.onHome != null
        && widget.module.path.split('?').first != 'dashboard') {
      widget.onHome!();
      return NavigationDecision.prevent;
    }
    // Web oturumu düştüyse (giriş sayfasına yönlendirildi) şifre sormadan yeniden bağlan
    if (req.isMainFrame && _isLoginPage(uri) && _reauthTries < 1) {
      _reauthTries++;
      _open(widget.module.path);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: reload, child: const Text('Tekrar dene')),
          ]),
        ),
      );
    }
    return Stack(children: [
      WebViewWidget(controller: _controller),
      if (_progress < 100) LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100, minHeight: 2),
    ]);
  }
}

/// Modülü tam ekran açan sayfa (webin kendi mobil başlığıyla).
class ModuleScreen extends StatefulWidget {
  const ModuleScreen({super.key, required this.module, required this.session, required this.config});

  final ArconModule module;
  final SessionController session;
  final ArconAppConfig config;

  /// Modül `native` işaretliyse ve uygulamada karşılığı varsa yerli ekranı, yoksa WebView'i açar.
  static Future<void> open(BuildContext context, ArconModule m, SessionController s, ArconAppConfig c) {
    final native = m.render == 'native' ? nativeBuilder(m, c) : null;
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => native != null ? native(ctx, m, s) : ModuleScreen(module: m, session: s, config: c),
    ));
  }

  static NativeModuleBuilder? nativeBuilder(ArconModule m, ArconAppConfig c) =>
      c.nativeModules[m.key] ?? builtInNativeModules(c)[m.key];

  /// Çekirdekte hazır gelen yerli ekranlar (modül anahtarı → ekran).
  static Map<String, NativeModuleBuilder> builtInNativeModules(ArconAppConfig c) => {
        // Club içinden açılınca geri butonlu; ARCONNECT uygulamasında ana ekran (HomeScreen) olarak açılır
        'arconnect': (ctx, m, s) => TalkHomeScreen(session: s, config: c, appMode: false),
        // Trello tarzı pano; veri web To-Do ile aynı (arcon_todo_api)
        'todo': (ctx, m, s) => TodoBoardScreen(session: s, config: c, title: m.title),
      };

  @override
  State<ModuleScreen> createState() => _ModuleScreenState();
}

class _ModuleScreenState extends State<ModuleScreen> {
  final _web = GlobalKey<ModuleWebViewState>();
  bool _webCanGoBack = false;

  @override
  Widget build(BuildContext context) {
    // Üst başlık webin kendi mobil başlığıdır (logo + menü); yerli başlık çubuğu yok.
    // Geri: iOS'ta kenardan kaydırma / Android geri tuşu (önce web geçmişi), logo → ana ekran.
    return PopScope(
      canPop: !_webCanGoBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final handled = await _web.currentState?.goBack() ?? false;
        if (!handled && context.mounted) Navigator.of(context).pop();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          // Web üst çubuğuyla aynı zemin (koyu tema: html.dark .arcon-header)
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF121820) : Colors.white,
          body: SafeArea(
            child: ModuleWebView(
              key: _web,
              module: widget.module,
              session: widget.session,
              config: widget.config,
              onHistoryChanged: (v) {
                if (mounted && v != _webCanGoBack) setState(() => _webCanGoBack = v);
              },
              onHome: () {
                if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
        ),
      ),
    );
  }
}
