import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../api/models.dart';
import '../../auth/session_controller.dart';
import '../../config.dart';
import '../mono.dart';
import '../module_webview.dart';
import '../../admin/admin_screens.dart';
import '../../admin/panel_akademi.dart';
import '../../admin/panels_hub.dart';
import '../../admin/panels_mag_store.dart';
import '../../admin/panels_skor_talk.dart';
import '../../admin/security_screen.dart';
import '../../akademi/akademi_screens.dart';
import '../../feedback/feedback_screen.dart';
import '../../helpdesk/helpdesk_screens.dart';
import '../../kariyer/kariyer_screens.dart';
import '../../skor/skor_screens.dart';
import '../../store/store_screens.dart';
import '../../mag/mag_screens.dart';
import '../../people/people_screen.dart';
import '../../search/search_screen.dart';
import '../motion.dart';

/// Ürün anahtarı → ikon (webdeki dashboard kartlarıyla aynı anlam).
IconData clubFeatureIcon(String key) => switch (key) {
  'ai_hub' || 'arcon_ai' => Icons.auto_awesome_outlined,
  'arconnect' => Icons.forum_outlined,
  'people' => Icons.groups_outlined,
  'todo' => Icons.check_box_outlined,
  'mag' => Icons.newspaper_outlined,
  'akademi' => Icons.school_outlined,
  'idea' => Icons.lightbulb_outline_rounded,
  'feedback' => Icons.rate_review_outlined,
  'skor' => Icons.star_outline_rounded,
  'search' => Icons.search_rounded,
  'helpdesk' => Icons.support_agent_outlined,
  'store' || 'arcon-store' => Icons.storefront_outlined,
  'kariyer' => Icons.badge_outlined,
  'profile' => Icons.person_outline_rounded,
  'dashboard' => Icons.space_dashboard_outlined,
  _ => Icons.widgets_outlined,
};

/// Web menü başlığından "ARCON " önekini ayırır: "ARCON MAG" → "MAG".
String clubShortName(String title) {
  final t = title.trim();
  final up = t.toUpperCase();
  if (up.startsWith('ARCON ')) return t.substring(6).trim();
  // "ARCONNECT" → "NECT" (kartta "ARCON" ayrıca yazılır)
  if (up.startsWith('ARCON') && up.length > 5) return t.substring(5);
  return t;
}

/// Ürün kartları API'den gelmezse (eski sunucu) modül listesinden kurulur.
const Map<String, String> clubFeatureFallbackText = {
  'ai_hub': 'Marka modülleri, chatbot’lar ve iş araçlarını tek panelden aç.',
  'arconnect': 'Kanallar, mesajlar ve dosyalar — ekip içi iletişim tek yerde.',
  'people': 'Kişiler dizini — departman, unvan ve iletişim bilgileri.',
  'todo': 'Bireysel ve ekip görevlerini panoda planla.',
  'mag': 'Ürün duyuruları, başarılar ve kültürümüzden anlar.',
  'akademi': 'Kısa rehberler, eğitim videoları ve quiz’lerle ustalaş.',
  'idea': 'Eklenmesini istediğin özellikleri öner.',
  'feedback': 'Hata, şikayet, övgü veya önerini paylaş.',
  'skor': 'AI-Durum Anketi ile kullanımını puanla.',
  'search': 'Mag, Academy, IDEA ve fazlasında tek aramayla bul.',
};

/// Modülü açar: yerli ekranı varsa o, yoksa WebView. Modül listede yoksa [path] ile WebView açılır.
Future<void> clubOpen(
  BuildContext context, {
  required SessionController session,
  required ArconAppConfig config,
  String? key,
  String? path,
  String? title,
}) async {
  // MAG yolları (bildirim kartı, profil menüsü) yerli ekranlara gider
  // MAG, People, Idea, Feedback, Search yolları (bildirim kartı, profil menüsü, arama sonucu) yerli ekranlara gider
  if (path != null && (_openMagPath(context, session, config, path) || _openNativePath(context, session, config, path))) return;
  ArconModule? m;
  if (key != null) {
    for (final x in session.modules) {
      if (x.key == key) {
        m = x;
        break;
      }
    }
  }
  // Özel yol (ör. okunmamış haberin detayı) modülün kendi sayfasından farklıysa doğrudan o sayfa
  if (path != null && path.isNotEmpty && (m == null || m.path != path)) {
    m = ArconModule(
      key: 'path:$path',
      title: title ?? m?.title ?? '',
      group: 'main',
      icon: '',
      render: 'webview',
      path: path,
      url: Uri.parse(config.apiBase).resolve(path).toString(),
    );
  }
  if (m == null) return;
  await ModuleScreen.open(context, m, session, config);
}

/// Bölüm başlığı: küçük büyük harf + ince çizgi + isteğe bağlı sağ bağlantı.
class ClubSectionTitle extends StatelessWidget {
  const ClubSectionTitle(this.text, {super.key, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return Row(
      children: [
        Text(
          trUpper(text),
          style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: c.line)),
        if (action != null) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!, style: c.text(12, weight: FontWeight.w600)),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, size: 18, color: c.ink),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Siyah kutu + beyaz ikon (koyuda tersine): webdeki modül kartı ikonu.
class ClubIconBox extends StatelessWidget {
  const ClubIconBox(this.icon, {super.key, this.size = 40, this.inverted = false});

  final IconData icon;
  final double size;

  /// Ters renkli kartın içinde kullanılırken.
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final bg = inverted ? c.bg : c.ink;
    final fg = inverted ? c.ink : c.bg;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

/// Profil fotoğrafı ya da baş harfler.
class ClubAvatar extends StatelessWidget {
  const ClubAvatar({super.key, required this.user, this.size = 38, this.inverted = false});

  final ArconUser? user;
  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final bg = inverted ? c.bg : c.ink;
    final fg = inverted ? c.ink : c.bg;
    final url = user?.avatarUrl;
    final initials = Center(
      child: Text(
        user?.initials ?? '?',
        style: c.text(size * 0.36, weight: FontWeight.w700, color: fg, height: 1),
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: url == null
          ? initials
          : CachedNetworkImage(memCacheWidth: 240, imageUrl: url, fit: BoxFit.cover, width: size, height: size, errorWidget: (_, _, _) => initials),
    );
  }
}

/// İnce çerçeveli, hafif dolgulu kart.
class ClubCard extends StatelessWidget {
  const ClubCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.radius = 18});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final card = Material(
      color: c.field,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    // dokunulabilir kart basılınca hafifçe küçülür
    return onTap == null ? card : PressScale(child: card);
  }
}

/// Alttan açılan siyah-beyaz sayfa (profil düzenleme, şifre).
Future<T?> showClubSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ArconMono.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: c.line)),
          ),
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(title, style: c.text(22, weight: FontWeight.w800, spacing: -0.5)),
              const SizedBox(height: 16),
              Flexible(child: SingleChildScrollView(child: builder(ctx))),
            ],
          ),
        ),
      );
    },
  );
}

void clubToast(BuildContext context, String message, {bool error = false}) {
  final c = ArconMono.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? c.danger : c.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: c.text(13.5, weight: FontWeight.w600, color: c.bg),
        ),
      ),
    );
}

/// Sunucudaki rol adı (roles.name, serbest metin) → arayüzde Türkçe ad.
/// Bilinmeyen ad (zaten Türkçe olanlar, ör. "Yeni Üye") olduğu gibi gösterilir.
String clubRoleLabel(String role) {
  final key = role.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), ' ');
  return switch (key) {
    'admin' || 'administrator' => 'Yönetici',
    'super admin' || 'superadmin' => 'Süper Yönetici',
    'user' || 'users' => 'Kullanıcı',
    'member' => 'Üye',
    'new member' => 'Yeni Üye',
    'editor' => 'Editör',
    'moderator' => 'Moderatör',
    'manager' => 'Müdür',
    'viewer' => 'İzleyici',
    'guest' => 'Misafir',
    'developer' || 'dev' => 'Geliştirici',
    'owner' => 'Sahip',
    'support' => 'Destek',
    'advanced' || 'advanced user' => 'İleri Kullanıcı',
    _ => role.trim(),
  };
}

/// `arcon-mag…` yollarını yerli MAG ekranlarıyla açar; tanınmayan yol için false.
bool _openMagPath(BuildContext context, SessionController session, ArconAppConfig config, String path) {
  final uri = Uri.tryParse(path);
  if (uri == null) return false;
  final page = uri.path.replaceAll('.php', '');
  if (page != 'arcon-mag' && page != 'arcon-mag_detay' && page != 'arcon-mag_sayi') return false;
  final module =
      session.modules.where((m) => m.key == 'mag').firstOrNull ??
      ArconModule(
        key: 'mag',
        title: 'ARCON MAG',
        group: 'main',
        icon: 'news',
        render: 'webview',
        path: 'arcon-mag',
        url: Uri.parse(config.apiBase).resolve('arcon-mag').toString(),
      );
  final slug = uri.queryParameters['h'];
  final view = uri.queryParameters['view'];
  final Widget screen;
  if (page == 'arcon-mag_sayi') {
    screen = MagIssueScreen(session: session, config: config, module: module, week: uri.queryParameters['w']);
  } else if (page == 'arcon-mag_detay' && slug != null && slug.isNotEmpty) {
    screen = MagPostScreen(session: session, config: config, slug: slug, module: module);
  } else if (view == 'saved' || view == 'liked') {
    screen = MagListScreen(session: session, config: config, view: view!, module: module);
  } else if (page == 'arcon-mag' && uri.queryParameters.isEmpty) {
    screen = MagHomeScreen(session: session, config: config, module: module);
  } else {
    return false;
  }
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  return true;
}

/// People / Idea / Feedback / Search sayfalarının web yollarını yerli ekranlarla açar.
bool _openNativePath(BuildContext context, SessionController session, ArconAppConfig config, String path) {
  final uri = Uri.tryParse(path);
  if (uri == null) return false;
  final page = uri.path.replaceAll('.php', '').replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'^app/'), '');
  void open(BuildContext ctx, String p, String t) => clubOpen(ctx, session: session, config: config, path: p, title: t);
  final Widget? screen = switch (page) {
    'arcon-people' || 'arcon-people-demo' => PeopleScreen(session: session, config: config),
    'arcon-people_profil' => PeopleScreen(session: session, config: config, openUserId: int.tryParse(uri.queryParameters['id'] ?? '')),
    'arcon-idea' => FeedbackScreen(session: session, config: config, kind: 'idea'),
    'arcon-idea_admin' => FeedbackScreen(session: session, config: config, kind: 'idea', openInbox: true),
    'arcon-feedback' => FeedbackScreen(session: session, config: config, kind: 'feedback'),
    'arcon-feedback_admin' => FeedbackScreen(session: session, config: config, kind: 'feedback', openInbox: true),
    'arcon-search-demo' || 'arcon-search' => SearchScreen(
      session: session,
      config: config,
      onOpenPath: (ctx, p, t) => clubOpen(ctx, session: session, config: config, path: p, title: t),
    ),
    'ai-akademi' => AkademiHomeScreen(
      session: session,
      config: config,
      onOpenPath: open,
      initialTab: switch (uri.queryParameters['view']) { 'ilerleme' => 1, 'liderlik' || 'siralama' => 2, _ => 0 },
    ),
    'ai-akademi_detay' when (uri.queryParameters['m'] ?? '').isNotEmpty =>
      AkademiModuleScreen(session: session, config: config, slug: uri.queryParameters['m']!, onOpenPath: open),
    'helpdesk' => HelpdeskHomeScreen(session: session, config: config),
    'helpdesk_view' || 'helpdesk_reply' when int.tryParse(uri.queryParameters['id'] ?? '') != null =>
      HelpdeskTicketScreen(session: session, config: config, id: int.parse(uri.queryParameters['id']!)),
    // Yönetim (ana sayfadaki admin kartları)
    'users' || 'user_add' || 'user_edit' => AdminUsersScreen(session: session),
    'roles' => AdminRolesScreen(session: session),
    'logs' || 'log-uyarilari' => AdminLogsScreen(session: session),
    'admin-modules' || 'module_add' || 'module_edit' => AdminModulesScreen(session: session),
    'panels' => PanelsHubScreen(session: session),
    'guvenlik' => SecurityScreen(session: session),
    'arcon-mag_admin' || 'arcon-mag_edit' => MagAdminScreen(session: session),
    'arcon-store_admin' => StoreAdminScreen(session: session),
    'arcon-skor_admin' => SkorAdminScreen(session: session),
    'arconnect_admin' || 'arcon-talk_admin' => TalkAdminScreen(session: session),
    'akademi_admin' || 'ai-akademi_admin' => AkademiAdminScreen(session: session),
    'arcon-skor' => SkorHomeScreen(session: session, config: config),
    'arcon-store' => StoreHomeScreen(session: session, config: config, openStoreId: int.tryParse(uri.queryParameters['s'] ?? '')),
    'kariyer' || 'kariyer_admin' || 'kariyer/basvurular' =>
      KariyerHomeScreen(session: session, config: config, openAppId: int.tryParse(uri.queryParameters['id'] ?? '')),
    _ => null,
  };
  if (screen == null) return false;
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  return true;
}
