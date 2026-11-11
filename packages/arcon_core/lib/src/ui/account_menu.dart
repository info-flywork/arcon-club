import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api/models.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import 'module_webview.dart';
import 'theme.dart';
import 'theme_scope.dart';

/// Web üst çubuğundaki kullanıcı düğmesi (header.php `.arcon-user__btn`): 38×38, köşe 11.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, required this.session, required this.config});
  final SessionController session;
  final ArconAppConfig config;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    if (user == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Builder(
      builder: (btnCtx) => Material(
        color: dark ? const Color(0xFF1A222D) : const Color(0xFFF0F0F0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(
            color: dark ? const Color(0x24FFFFFF) : const Color(0xFFD8D8D8),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () =>
              showAccountMenu(btnCtx, session: session, config: config),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: Text(
                user.initials,
                style: TextStyle(
                  fontFamily: arconFontFamily,
                  package: 'arcon_core',
                  fontSize: 11.52,
                  fontWeight: FontWeight.w700,
                  color: dark
                      ? const Color(0xFFE8EEF5)
                      : const Color(0xFF111111),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Web kullanıcı menüsü (`#userMenu`): düğmenin altında, sağa hizalı 228px kart.
Future<void> showAccountMenu(
  BuildContext anchor, {
  required SessionController session,
  required ArconAppConfig config,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final screen = MediaQuery.sizeOf(anchor);
  final origin =
      box?.localToGlobal(Offset.zero) ?? Offset(screen.width - 54, 60);
  final size = box?.size ?? const Size(38, 38);
  final top = origin.dy + size.height + 10; // web: 10px boşluk
  final right = (screen.width - (origin.dx + size.width)).clamp(
    8.0,
    screen.width,
  );
  final theme = ArconThemeScope.of(anchor);
  final nav = Navigator.of(anchor);

  return showGeneralDialog<void>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Menüyü kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) => Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          child: _AccountMenuCard(
            session: session,
            theme: theme,
            maxHeight: screen.height - top - 24,
            onOpen: (item) {
              Navigator.of(ctx).pop();
              final m = ArconModule(
                key: 'account:${item.path}',
                title: item.title,
                group: 'account',
                icon: '',
                render: 'webview',
                path: item.path,
                url: Uri.parse(config.apiBase).resolve(item.path).toString(),
              );
              ModuleScreen.open(nav.context, m, session, config);
            },
            onLogout: () {
              Navigator.of(ctx).pop();
              session.logout();
            },
          ),
        ),
      ],
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, -0.02),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    ),
  );
}

class _AccountMenuCard extends StatelessWidget {
  const _AccountMenuCard({
    required this.session,
    required this.theme,
    required this.maxHeight,
    required this.onOpen,
    required this.onLogout,
  });

  final SessionController session;
  final ArconThemeController theme;
  final double maxHeight;
  final ValueChanged<AccountMenuItem> onOpen;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final user = session.user!;
    final ink = dark
        ? const Color(0xFFB7C0CC)
        : const Color(0xFF3D4A63); // --ink-soft
    final muted = dark ? const Color(0xFF8B98A8) : const Color(0xFF6B7280);
    final rows = <Widget>[];
    for (final sec in user.accountMenu) {
      for (final it in sec.items) {
        rows.add(
          it.kind == 'issue'
              ? _row(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.title.toUpperCase(),
                        style: _mont(13.12, FontWeight.w700, ink, ls: 0.52),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        it.subtitle.toUpperCase(),
                        style: _mont(
                          11.52,
                          FontWeight.w600,
                          muted.withValues(alpha: 0.9),
                          ls: 1.15,
                        ),
                      ),
                    ],
                  ),
                  dark: dark,
                  onTap: () => onOpen(it),
                )
              : _row(
                  child: Text(
                    it.title,
                    style: _mont(13.76, FontWeight.w400, ink),
                  ),
                  dark: dark,
                  onTap: () => onOpen(it),
                ),
        );
      }
    }

    // Gölge kartın altında (üstte olursa kartı griye boyar)
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 50,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Material(
        color: dark ? const Color(0xFF161D27) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: dark ? const Color(0x14FFFFFF) : const Color(0x14000000),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: 228,
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF1A222D)
                        : const Color(0xFFF8FAFC),
                    border: Border(
                      bottom: BorderSide(
                        color: dark
                            ? const Color(0x14FFFFFF)
                            : const Color(0xFFD7DDE8),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.username,
                        style: _mont(
                          14.4,
                          FontWeight.w600,
                          dark ? const Color(0xFFE8EEF5) : Colors.black,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hesap',
                        style: _mont(11.52, FontWeight.w400, muted),
                      ),
                    ],
                  ),
                ),
                ...rows,
                _row(
                  dark: dark,
                  onTap: () => theme.toggle(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dark ? 'Koyu tema' : 'Açık tema',
                          style: _mont(13.76, FontWeight.w400, ink),
                        ),
                      ),
                      _ThemeSwitch(dark: dark),
                    ],
                  ),
                ),
                _row(
                  dark: dark,
                  danger: true,
                  onTap: onLogout,
                  child: Text(
                    'Çıkış Yap',
                    style: _mont(
                      13.76,
                      FontWeight.w400,
                      dark ? const Color(0xFFB7C0CC) : const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static TextStyle _mont(double size, FontWeight w, Color c, {double? ls}) =>
      TextStyle(
        fontFamily: arconFontFamily,
        package: 'arcon_core',
        fontSize: size,
        fontWeight: w,
        color: c,
        letterSpacing: ls,
      );

  Widget _row({
    required Widget child,
    required bool dark,
    required VoidCallback onTap,
    bool danger = false,
  }) => InkWell(
    onTap: onTap,
    // web :hover rengi dokunma geri bildirimi olarak
    highlightColor: danger
        ? const Color(0xFFFEF2F2)
        : (dark ? const Color(0x0DFFFFFF) : const Color(0xFFF4F6F9)),
    splashColor: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: child,
    ),
  );
}

/// Web `.arcon-theme-switch`: 44×24, düğme 18px; koyu temada yeşil ve sağda.
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({required this.dark});
  final bool dark;

  static const _sun =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.2">'
      '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v1.6M12 19.6v1.6M4.6 4.6l1.1 1.1M18.3 18.3l1.1 1.1M2.8 12h1.6M19.6 12h1.6M4.6 19.4l1.1-1.1M18.3 5.7l1.1-1.1"/></svg>';
  static const _moon =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="2.2">'
      '<path d="M21 14.5A8.5 8.5 0 1110.5 3a7 7 0 0010.5 11.5z"/></svg>';

  @override
  Widget build(BuildContext context) {
    final icoColor = dark ? const Color(0xFF0B4F3D) : const Color(0xFF8A6524);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 44,
      height: 24,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0F6E56) : const Color(0xFFCFD6E0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark ? const Color(0x4D59DFB7) : const Color(0x1A000000),
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.all(2),
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: SvgPicture.string(
            dark ? _moon : _sun,
            width: 11,
            height: 11,
            colorFilter: ColorFilter.mode(icoColor, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
