import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../talk/talk_home_screen.dart';
import 'account_menu.dart';
import 'club/club_shell.dart';
import 'module_webview.dart';
import 'theme.dart';

/// Ana ekran. Menü tamamen sunucudan gelir (`/api/v1/modules`): webde açılan modül
/// burada kendiliğinden görünür, uygulama güncellemesi gerekmez.
///
/// `startModuleKey` dolu uygulamada (ARCONNECT) ilk sekme o modülün kendisidir.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.config, required this.session});

  final ArconAppConfig config;
  final SessionController session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Uygulama öne gelince menüyü tazele (webde yeni açılan modül görünsün)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.session.refreshModules().catchError((_) {});
    }
  }

  ArconModule? get _startModule {
    final key = widget.config.startModuleKey;
    if (key == null) return null;
    for (final m in widget.session.modules) {
      if (m.key == key) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final start = _startModule;
    // Başlangıç modülü yerli ekransa (ARCONNECT) uygulamanın kendisi o ekrandır — webin uygulama modu gibi.
    if (start != null && start.key == 'arconnect' && start.render == 'native') {
      return TalkHomeScreen(session: widget.session, config: widget.config, appMode: true);
    }
    final menu = _ModuleMenu(config: widget.config, session: widget.session, hideKey: start?.key);
    if (start == null) {
      // ARCON Club: yerli kabuk (Ana sayfa · Modüller · Profil). Modül içleri yerli karşılığı yoksa WebView.
      return ClubShell(session: widget.session, config: widget.config);
    }

    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        SafeArea(
          bottom: false,
          child: ModuleWebView(module: start, session: widget.session, config: widget.config),
        ),
        menu,
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: Icon(arconModuleIcon(start.icon)), label: start.title),
          const NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'Menü'),
        ],
      ),
    );
  }
}

class _ModuleMenu extends StatelessWidget {
  const _ModuleMenu({required this.config, required this.session, this.hideKey});

  final ArconAppConfig config;
  final SessionController session;
  final String? hideKey;

  Future<void> _refresh(BuildContext context) async {
    try {
      await session.refreshModules(force: true);
    } on ArconApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final mods = session.modules.where((m) => m.key != hideKey).toList();
    final main = mods.where((m) => m.group == 'main').toList();
    // Web üst menüsü (ARCON AI, ARCONNECT, PEOPLE …); Dashboard'a webdeki gibi logodan gidilir
    final tools = main.where((m) => m.key != 'dashboard').toList();
    final dashboard = main.where((m) => m.key == 'dashboard').firstOrNull;
    final ai = mods.where((m) => m.group == 'ai_modules').toList();
    void open(ArconModule m) => ModuleScreen.open(context, m, session, config);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: dashboard == null ? null : () => open(dashboard),
          child: const ArconLogo(),
        ),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              // Web üst çubuğundaki kullanıcı düğmesi ve menüsü
              child: AccountButton(session: session, config: config),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (user != null) ...[
              Text('Merhaba, ${user.username}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(config.title, style: const TextStyle(color: ArconColors.muted)),
              const SizedBox(height: 20),
            ],
            if (tools.isNotEmpty) ...[
              _WebToolsBar(modules: tools, onTap: open),
              const SizedBox(height: 24),
            ],
            if (ai.isNotEmpty) ...[
              const _SectionTitle('AI Modüllerim'),
              Card(
                child: Column(children: [
                  for (var i = 0; i < ai.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 56),
                    _ModuleRow(module: ai[i], onTap: () => open(ai[i])),
                  ],
                ]),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }


}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: ArconColors.muted)),
      );
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.module, required this.onTap});
  final ArconModule module;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: module.group == 'ai_modules' ? WebModuleIcon(module: module) : Icon(arconModuleIcon(module.icon)),
        title: Text(module.title),
        subtitle: module.description.isEmpty
            ? null
            : Text(module.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}

/// Webdeki AI modül kartı ikonu (dashboard.php `.dash-mod-card__icon` ile aynı ölçüler):
/// 44×44, köşe 14; PNG varsa açık zemin üzerinde kaplar, yoksa yeşil degrade + beyaz çizgiler.
class WebModuleIcon extends StatelessWidget {
  const WebModuleIcon({super.key, required this.module});
  final ArconModule module;

  static const _linesSvg = '<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="#ffffff">'
      '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h10M4 18h6"/></svg>';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Webdeki Modüllerim kartı (modules.css .mod-icon): 46×46, köşe 12, siyah zemin / beyaz ikon
    if (module.iconStyle == 'lucide' && module.iconSvg != null) {
      return Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFFF4F4F5) : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
        ),
        child: SvgPicture.string(
          module.iconSvg!,
          width: 22,
          height: 22,
          colorFilter: ColorFilter.mode(dark ? const Color(0xFF111111) : Colors.white, BlendMode.srcIn),
        ),
      );
    }
    final radius = BorderRadius.circular(14);
    final hasImg = module.iconUrl != null || module.iconSvg != null;
    if (!hasImg) {
      return Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment(-0.57, -0.82), // 145deg
            end: Alignment(0.57, 0.82),
            colors: [Color(0xFF0F6E56), Color(0xFF0B4F3D)],
          ),
          boxShadow: const [BoxShadow(color: Color(0x420F6E56), blurRadius: 22, offset: Offset(0, 10))],
        ),
        child: SvgPicture.string(_linesSvg, width: 18, height: 18),
      );
    }
    final fg = dark ? Colors.white : const Color(0xFF1A2744);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: dark ? const Color(0xFF1A222D) : const Color(0xFFF4F6FA),
        boxShadow: const [BoxShadow(color: Color(0x1A1A2744), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: module.iconUrl != null
          ? CachedNetworkImage(memCacheWidth: 160, imageUrl: module.iconUrl!, width: 44, height: 44, fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink())
          : SvgPicture.string(module.iconSvg!, width: 18, height: 18,
              colorFilter: ColorFilter.mode(fg, BlendMode.srcIn)),
    );
  }
}

/// Webdeki üst ürün menüsü (header.php `.arcon-tools`): hap düğmeler,
/// "ARCON" + ad (Poppins 700), seçili olmayan beyaz/ince çerçeve.
class _WebToolsBar extends StatelessWidget {
  const _WebToolsBar({required this.modules, required this.onTap});
  final List<ArconModule> modules;
  final void Function(ArconModule) onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: dark ? const Color(0x0AFFFFFF) : const Color(0x0A000000),
          border: Border.all(color: dark ? const Color(0x12FFFFFF) : const Color(0x12000000)),
          borderRadius: BorderRadius.circular(14),
        ),
        // Telefonda hepsi görünsün diye alt satıra kayar (web dar ekranda yatay kaydırır)
        child: Wrap(spacing: 3, runSpacing: 3, children: [
          for (final m in modules) _WebToolPill(module: m, dark: dark, onTap: () => onTap(m)),
        ]),
      ),
    );
  }
}

class _WebToolPill extends StatelessWidget {
  const _WebToolPill({required this.module, required this.dark, required this.onTap});
  final ArconModule module;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? const Color(0xFFF2F2F2) : Colors.black;
    return Material(
      color: dark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: dark ? const Color(0x24FFFFFF) : const Color(0x1F000000)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          // Web 6×9; dokunma alanı için dikeyde biraz daha geniş
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            module.title.toUpperCase(),
            style: TextStyle(fontFamily: arconFontFamily, fontSize: 12,
                fontWeight: FontWeight.w700, color: fg, height: 1.1),
          ),
        ),
      ),
    );
  }
}
