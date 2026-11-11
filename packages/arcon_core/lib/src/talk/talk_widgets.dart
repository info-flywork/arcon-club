import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme_scope.dart';
import 'talk_controller.dart';
import 'talk_icons.dart';
import 'talk_profile_screen.dart';
import 'talk_theme.dart';

/// Avatar türleri (web sınıfları):
/// - [TalkAvatar.solid]: `.talk-avatar` / `.talk-chan__ico` — açık temada siyah, koyu temada beyaz
/// - [TalkAvatar.hue]: `.talk-msg__avatar` — isimden üretilen renk (hsl hue 52% 42%)
class TalkAvatar extends StatelessWidget {
  const TalkAvatar.solid({super.key, required this.name, this.photoUrl = '', required this.size, this.fontSize = 13.12, this.personIfEmpty = false})
      : seed = null;
  const TalkAvatar.hue({super.key, required this.name, required this.seed, this.photoUrl = '', this.size = 34, this.fontSize = 11.52, this.personIfEmpty = false});

  final String name;
  final Object? seed;
  final String photoUrl;
  final double size;
  final double fontSize;
  /// WhatsApp: foto yoksa harf değil kişi ikonu.
  final bool personIfEmpty;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bg = personIfEmpty
        ? (c.dark ? const Color(0xFF2A3942) : const Color(0xFFDFE5E7))
        : (seed != null ? talkAvatarColor(seed) : c.accent);
    final fg = personIfEmpty ? (c.dark ? const Color(0xFFD1D7DB) : const Color(0xFF8696A0)) : (seed != null ? Colors.white : c.accentContrast);
    Widget fallback() => personIfEmpty
        ? Icon(Icons.person_rounded, size: size * 0.62, color: fg)
        : Text(talkInitials(name),
            style: talkText(fontSize, seed != null ? FontWeight.w800 : FontWeight.w700, fg, letterSpacing: fontSize * 0.02));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: photoUrl.isEmpty ? bg : Colors.transparent, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: photoUrl.isNotEmpty
          ? TalkNetImage(photoUrl, width: size, height: size, fit: BoxFit.cover, decodeWidth: size, placeholder: bg, error: Center(child: fallback()))
          : fallback(),
    );
  }
}

/// Sohbet / avatar görseli: indirme sırasında placeholder, decode ekran pikselinde (tam 12 MP decode yok).
/// İnen dosyalar diskte saklanır: sohbeti yeniden açınca görseller tekrar inmez.
/// [fallbackUrl]: önizleme (thumb) alınamazsa asıl dosya denenir (eski sunucu, GIF vb.).
class TalkNetImage extends StatelessWidget {
  const TalkNetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.decodeWidth,
    this.placeholder = const Color(0xFF111B21),
    this.error,
    this.fallbackUrl,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double? decodeWidth;
  final Color placeholder;
  final Widget? error;
  final String? fallbackUrl;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return ColoredBox(color: placeholder, child: error);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final logical = decodeWidth ?? (width != null && width!.isFinite ? width : null);
    final cacheW = logical != null && logical > 0 ? (logical * dpr).round().clamp(48, 1600) : null;
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheW,
      filterQuality: FilterQuality.low,
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: Duration.zero,
      progressIndicatorBuilder: (ctx, _, p) => ColoredBox(
        color: placeholder,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0x66FFFFFF), value: p.progress),
          ),
        ),
      ),
      errorWidget: (_, _, _) => fallbackUrl != null && fallbackUrl!.isNotEmpty && fallbackUrl != url
          ? TalkNetImage(fallbackUrl!, fit: fit, width: width, height: height, decodeWidth: decodeWidth, placeholder: placeholder, error: error)
          : ColoredBox(color: placeholder, child: error ?? const SizedBox.shrink()),
    );
  }
}

/// `.talk-toast`
void talkToast(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 16,
      right: 16,
      bottom: 28 + MediaQuery.paddingOf(ctx).bottom,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: error ? const Color(0xFF9F1239) : const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 40, offset: Offset(0, 16))],
              ),
              child: Text(message, style: talkText(14.08, FontWeight.w600, Colors.white, height: 1.35)),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 3200), () {
    if (entry.mounted) entry.remove();
  });
}

/// `.talk-modal__card` — başlık, mesaj, alanlar, sağda Vazgeç / ana buton.
class TalkModalCard extends StatelessWidget {
  const TalkModalCard({super.key, required this.title, this.message, this.children = const [], required this.actions});
  final String title;
  final String? message;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.infoCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.popBorder),
            boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 60, offset: Offset(0, 24))],
          ),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: talkText(17.6, FontWeight.w800, c.ink)),
              const SizedBox(height: 4),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: talkText(14.72, FontWeight.w400, c.muted, height: 1.45)),
              ],
              for (final w in children) ...[const SizedBox(height: 12), w],
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 8), actions[i]],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.talk-ghost` (Vazgeç) ve `.talk-send` (ana buton, danger=kırmızı)
class TalkButton extends StatelessWidget {
  const TalkButton.ghost(this.label, {super.key, required this.onPressed}) : primary = false, danger = false;
  const TalkButton.primary(this.label, {super.key, required this.onPressed, this.danger = false}) : primary = true;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bg = !primary ? Colors.transparent : (danger ? TalkColors.dangerSolid : c.accent);
    final fg = !primary ? c.muted : (danger ? Colors.white : c.accentContrast);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(primary ? 999 : 999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(label, style: talkText(14.08, FontWeight.w700, onPressed == null ? fg.withValues(alpha: 0.4) : fg)),
        ),
      ),
    );
  }
}

/// JS `talkConfirm` — `#modalConfirm`
Future<bool> talkConfirm(BuildContext context, {required String title, required String message, String ok = 'Onayla', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x8C000000),
    builder: (ctx) => TalkModalCard(title: title, message: message, actions: [
      TalkButton.ghost('Vazgeç', onPressed: () => Navigator.pop(ctx, false)),
      TalkButton.primary(ok, danger: danger, onPressed: () => Navigator.pop(ctx, true)),
    ]),
  );
  return r == true;
}

/// WhatsApp: sohbet ve bilgi ekranlarında ayrı üst bar yok; yalnızca durum çubuğunun arkası başlık rengiyle boyanır.
PreferredSizeWidget talkStatusBar(BuildContext context) {
  final c = TalkColors.of(context);
  return AppBar(
    toolbarHeight: 0,
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: c.chatHead,
    systemOverlayStyle: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
  );
}

/// Üst bar: web uygulama modundaki `arcon-header` (ARCON + NECT, sağda kullanıcı butonu).
class TalkTopBar extends StatelessWidget implements PreferredSizeWidget {
  const TalkTopBar({super.key, required this.username, required this.onLogout, this.onBack, this.talk});
  final String username;
  final VoidCallback onLogout;
  final VoidCallback? onBack;
  final TalkController? talk;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = c.dark ? const Color(0xFFE8EEF5) : Colors.black;
    // Durum çubuğu (saat/pil) üst barın rengine göre — dosya gönderme ekranından dönünce beyaz kalmasın
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Container(
      height: 52 + MediaQuery.paddingOf(context).top,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, left: onBack == null ? 16 : 4, right: 16),
      decoration: BoxDecoration(color: c.header, border: Border(bottom: BorderSide(color: c.headerBorder))),
      child: Row(children: [
        if (onBack != null)
          IconButton(onPressed: onBack, icon: TalkIcon(TalkSvg.back, size: 22, color: ink), tooltip: 'Geri'),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'ARCON', style: talkText(19.2, FontWeight.w700, ink)),
          TextSpan(text: 'NECT', style: talkText(19.2, FontWeight.w700, ink)),
        ])),
        const Spacer(),
        if (talk == null)
          _UserButton(username: username, onLogout: onLogout)
        else
          ListenableBuilder(
            listenable: talk!,
            builder: (context, _) {
              final shown = (talk!.me?.displayName ?? '').trim().isNotEmpty ? talk!.me!.displayName : username;
              final photo = talk!.api.fileUrl(talk!.me?.avatarPath ?? '');
              return _UserButton(username: shown, photoUrl: photo, onLogout: onLogout, onProfile: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => TalkProfileScreen(controller: talk!)));
              });
            },
          ),
      ]),
      ),
    );
  }
}

class _UserButton extends StatelessWidget {
  const _UserButton({required this.username, required this.onLogout, this.onProfile, this.photoUrl = ''});
  final String username;
  final VoidCallback onLogout;
  final VoidCallback? onProfile;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = c.dark ? const Color(0xFFE8EEF5) : Colors.black;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (onProfile != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: GestureDetector(
            onTap: onProfile,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(username, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: dmSans(13.5, 650, ink)),
            ),
          ),
        ),
      GestureDetector(
        onTap: () => _menu(context),
        child: Container(
          width: 38,
          height: 38,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.userBtnBg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: c.userBtnBorder),
          ),
          child: photoUrl.isEmpty
              ? Text(talkInitials(username), style: dmSans(11.52, 700, c.userBtnInk).copyWith(letterSpacing: 0.23))
              : TalkNetImage(
                  photoUrl,
                  width: 38,
                  height: 38,
                  decodeWidth: 38,
                  placeholder: c.userBtnBg,
                  error: Center(child: Text(talkInitials(username), style: dmSans(11.52, 700, c.userBtnInk).copyWith(letterSpacing: 0.23))),
                ),
        ),
      ),
    ]);
  }

  /// `#userMenu`: ad + "Hesap", Tema Değiştir anahtarı, Çıkış Yap
  void _menu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero);
    final theme = ArconThemeScope.of(context);
    showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        final c = TalkColors.of(ctx);
        final dark = theme.isDark(ctx);
        final ink = c.dark ? const Color(0xFFE8EEF5) : Colors.black;
        final itemInk = c.dark ? const Color(0xFFB7C0CC) : const Color(0xFF3D4A63);
        return Stack(children: [
          Positioned(
            top: pos.dy + box.size.height + 8,
            right: 16,
            width: 228,
            child: Material(
              color: c.dark ? const Color(0xFF161D27) : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.dark ? const Color(0x14FFFFFF) : const Color(0x14000000)),
              ),
              shadowColor: const Color(0x14000000),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.dark ? const Color(0xFF1A222D) : const Color(0xFFF8FAFC),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: GestureDetector(
                    onTap: onProfile == null
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            onProfile!();
                          },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(username, style: dmSans(14.4, 650, ink)),
                      Text(onProfile == null ? 'Hesap' : 'Profil', style: dmSans(11.52, 400, const Color(0xFF6B7280))),
                    ]),
                  ),
                ),
                Divider(height: 1, color: c.dark ? const Color(0x14FFFFFF) : const Color(0x14000000)),
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    theme.toggle(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(children: [
                      Expanded(child: Text(dark ? 'Koyu tema' : 'Açık tema', style: dmSans(13.76, 400, itemInk))),
                      _ThemeSwitch(dark: dark),
                    ]),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    onLogout();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Text('Çıkış Yap', style: dmSans(13.76, 400, const Color(0xFF991B1B))),
                  ),
                ),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

/// `.arcon-theme-switch` (44×24, beyaz düğme, güneş/ay ikonu)
class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({required this.dark});
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          // açık: #cfd6e0 · koyu modda kapalı: #3a4658 · açıkken accent #0f6e56
          color: dark ? const Color(0xFF0F6E56) : const Color(0xFFCFD6E0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: dark ? const Color(0x4D59DFB7) : const Color(0x1A000000)),
        ),
        alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
          child: TalkIcon(dark ? TalkSvg.moon : TalkSvg.sun, size: 12, color: dark ? const Color(0xFF0B4F3D) : const Color(0xFF8A6524)),
        ),
      );
}
