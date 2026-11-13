import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/session_controller.dart';
import '../../config.dart';
import '../mono.dart';
import 'club_dashboard.dart';
import 'club_modules.dart';
import 'club_profile.dart';

/// ARCON Club'ın yerli ana kabuğu: Ana sayfa · Modüller · Profil.
/// Modüllerin içi yerli karşılığı varsa yerli (ARCONNECT, TO-DO), yoksa WebView'de açılır.
class ClubShell extends StatefulWidget {
  const ClubShell({super.key, required this.session, required this.config});

  final SessionController session;
  final ArconAppConfig config;

  @override
  State<ClubShell> createState() => _ClubShellState();
}

class _ClubShellState extends State<ClubShell> {
  int _tab = 0;
  final _dashboard = GlobalKey<ClubDashboardState>();
  // Her sekme oturumu (kullanıcı, modüller) kendisi dinler; kabuk ve menü çubuğu yeniden kurulmaz
  late final List<Widget> _tabs = [
    ListenableBuilder(
      listenable: widget.session,
      builder: (_, _) => ClubDashboard(
        key: _dashboard,
        session: widget.session,
        config: widget.config,
        onOpenModules: () => _go(1),
        onOpenProfile: () => _go(2),
      ),
    ),
    ListenableBuilder(listenable: widget.session, builder: (_, _) => ClubModules(session: widget.session, config: widget.config)),
    ListenableBuilder(listenable: widget.session, builder: (_, _) => ClubProfile(session: widget.session, config: widget.config)),
  ];

  void _go(int i) {
    if (i == _tab) {
      if (i == 0) _dashboard.currentState?.load();
      return;
    }
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            // Sekmeler baştan kurulu durur ve durumunu korur; geçiş anında olur (animasyon/yeniden kurma yok)
            IndexedStack(
              index: _tab,
              sizing: StackFit.expand,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  TickerMode(enabled: i == _tab, child: RepaintBoundary(child: _tabs[i])),
              ],
            ),
            // kaydırınca içerik durum çubuğunun altında okunmasın
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: MediaQuery.paddingOf(context).top,
              child: ColoredBox(color: c.bg),
            ),
          ],
        ),
        bottomNavigationBar: _ClubTabBar(
          index: _tab,
          onTap: _go,
          items: const [
            (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Ana sayfa'),
            (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Modüller'),
            (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
          ],
        ),
      ),
    );
  }
}

class _ClubTabBar extends StatelessWidget {
  const _ClubTabBar({required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    final bottomPad = bottom > 0 ? (bottom - 12).clamp(10.0, bottom) : 0.0;
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(color: i == index ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                        child: Icon(i == index ? items[i].$2 : items[i].$1, size: 21, color: i == index ? c.bg : c.muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].$3,
                        style: c.text(10.5, weight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? c.ink : c.muted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
