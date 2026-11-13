import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/session_controller.dart';
import '../../config.dart';
import '../mono.dart';
import '../skeleton.dart';
import '../theme_scope.dart';
import 'club_common.dart';

/// Yerli profil — webdeki profile.php: fotoğraf, bilgiler, şifre, Academy rozetleri,
/// webdeki kullanıcı menüsü (yetkiye göre), tema ve çıkış.
class ClubProfile extends StatefulWidget {
  const ClubProfile({super.key, required this.session, required this.config});

  final SessionController session;
  final ArconAppConfig config;

  @override
  State<ClubProfile> createState() => ClubProfileState();
}

class ClubProfileState extends State<ClubProfile> {
  AcademySummary? _academy;
  bool _photoBusy = false;

  /// Profil verisi ilk kez gelene kadar Academy kartı yerine iskelet.
  bool _loaded = false;

  SessionController get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final cached = await _s.api.cachedProfile();
    if (cached != null && mounted) {
      setState(() {
        _academy = cached.academy;
        _loaded = true;
      });
    }
    await load();
  }

  Future<void> load({bool force = false}) async {
    try {
      final p = await _s.api.profile(force: force);
      _s.setUser(p.user);
      if (mounted) setState(() => _academy = p.academy);
    } on ArconApiException catch (e) {
      // Sunucuda profil ucu yoksa (eski sürüm) oturumdaki kullanıcıyla devam
      await _s.handleError(e);
    } finally {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _photo() async {
    final user = _s.user;
    if (user == null || _photoBusy) return;
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'camera'), child: const Text('Fotoğraf çek')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'gallery'), child: const Text('Galeriden seç')),
          if (user.avatarUrl != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: const Text('Fotoğrafı kaldır'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (choice == null || !mounted) return;
    XFile? file;
    if (choice != 'remove') {
      file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1200,
      );
      if (file == null || !mounted) return;
    }
    setState(() => _photoBusy = true);
    try {
      if (file == null) {
        await _s.api.removeAvatar();
      } else {
        await _s.api.uploadAvatar(file.path);
      }
      await _s.refreshMe();
      if (mounted) clubToast(context, file == null ? 'Fotoğraf kaldırıldı' : 'Fotoğraf güncellendi');
    } on ArconApiException catch (e) {
      if (mounted) clubToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _editInfo() async {
    final user = _s.user;
    if (user == null) return;
    final ok = await showClubSheet<bool>(
      context,
      title: 'Bilgilerini düzenle',
      builder: (ctx) => _InfoForm(session: _s, user: user),
    );
    if (ok == true && mounted) clubToast(context, 'Profilin güncellendi');
  }

  Future<void> _changePassword() async {
    final ok = await showClubSheet<bool>(
      context,
      title: 'Şifre değiştir',
      builder: (ctx) => _PasswordForm(session: _s),
    );
    if (ok == true && mounted) clubToast(context, 'Şifren değiştirildi');
  }

  Future<void> _logout() async {
    final yes = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text('Bu cihazdaki oturumun kapanır.'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Çıkış yap')),
        ],
      ),
    );
    if (yes == true) await _s.logout();
  }

  void _openPath(AccountMenuItem item) => clubOpen(context, session: _s, config: widget.config, path: item.path, title: item.title);

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final user = _s.user;
    final theme = ArconThemeScope.of(context);
    // Zaten Profil sekmesindeyiz; menüdeki "Profil" satırını gösterme.
    final menu = (user?.accountMenu ?? const <AccountMenuSection>[])
        .map((sec) => AccountMenuSection(
              section: sec.section,
              items: sec.items.where((it) {
                final p = it.path.split('?').first.toLowerCase();
                return p != 'profile' && p != 'profile.php';
              }).toList(),
            ))
        .where((sec) => sec.items.isNotEmpty)
        .toList();

    return RefreshIndicator(
      color: c.ink,
      backgroundColor: c.bg,
      onRefresh: () => load(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 28 + pad.bottom),
        children: [
          Text('Profil', style: c.text(30, weight: FontWeight.w800, height: 1.15, spacing: -1)),
          const SizedBox(height: 18),
          _header(c, user),
          if (!_loaded && (_s.user?.isBeta ?? false)) ...[
            const SizedBox(height: 24),
            const Shimmer(child: SkeletonBox(width: double.infinity, height: 150, radius: 18)),
          ] else if (_academy != null) ...[
            const SizedBox(height: 24),
            const ClubSectionTitle('ARCON Academy'),
            const SizedBox(height: 12),
            _academyCard(c, _academy!),
          ],
          const SizedBox(height: 24),
          const ClubSectionTitle('Ayarlar'),
          const SizedBox(height: 12),
          _group(c, [
            _row(c, Icons.badge_outlined, 'Bilgilerini düzenle', sub: 'Kullanıcı adı ve e-posta', onTap: _editInfo),
            _row(c, Icons.lock_outline_rounded, 'Şifre değiştir', sub: 'En az 8 karakter', onTap: _changePassword),
            _row(
              c,
              c.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              'Koyu tema',
              trailing: CupertinoSwitch(value: theme.isDark(context), activeTrackColor: c.ink, onChanged: (v) => theme.setDark(v)),
            ),
          ]),
          for (final sec in menu) ...[
            const SizedBox(height: 24),
            ClubSectionTitle(sec.section.isEmpty ? 'Diğer' : sec.section),
            const SizedBox(height: 12),
            _group(c, [
              for (final it in sec.items)
                _row(c, _menuIcon(it), it.title, sub: it.subtitle.isEmpty ? null : it.subtitle, onTap: () => _openPath(it)),
            ]),
          ],
          const SizedBox(height: 24),
          _group(c, [_row(c, Icons.logout_rounded, 'Çıkış yap', danger: true, onTap: _logout)]),
          const SizedBox(height: 18),
          Center(
            child: Text(widget.config.title, style: c.text(11.5, color: c.faint)),
          ),
        ],
      ),
    );
  }

  IconData _menuIcon(AccountMenuItem it) {
    final path = it.path.toLowerCase();
    final title = it.title.toLowerCase();
    final kind = it.kind.toLowerCase();
    final p = '$path $title $kind';

    // ARCON MAG
    if (path.contains('view=saved') || title.contains('kaydet')) return Icons.bookmark_outline_rounded;
    if (path.contains('view=liked') || title.contains('beğen')) return Icons.favorite_outline_rounded;
    if (path.contains('mag_admin') || title.contains('mag yönetim')) return Icons.tune_rounded;
    if (kind == 'issue' || path.contains('mag_sayi') || path.contains('arcon-mag')) return Icons.auto_stories_outlined;

    // ARCON ACADEMY
    if (path.contains('view=yol') || title.contains('yol harita')) return Icons.route_outlined;
    if (path.contains('view=ilerleme') || title.contains('ilerleme')) return Icons.trending_up_rounded;
    if (path.contains('view=liderlik') || title.contains('liderlik')) return Icons.emoji_events_outlined;
    if (path.contains('akademi_admin') || title.contains('academy admin')) return Icons.admin_panel_settings_outlined;
    if (p.contains('akademi') || p.contains('academy')) return Icons.school_outlined;

    if (p.contains('helpdesk') || p.contains('destek')) return Icons.support_agent_outlined;
    if (p.contains('user') || p.contains('kullanıcı')) return Icons.group_outlined;
    if (p.contains('role') || p.contains('rol')) return Icons.admin_panel_settings_outlined;
    if (p.contains('log-uyari') || p.contains('log uyarı')) return Icons.notification_important_outlined;
    if (p.contains('log')) return Icons.receipt_long_outlined;
    if (p.contains('guvenlik') || p.contains('güvenlik')) return Icons.security_outlined;
    if (p.contains('modul') || p.contains('module')) return Icons.widgets_outlined;
    if (p.contains('profile') || p.contains('profil')) return Icons.person_outline_rounded;
    return Icons.open_in_new_rounded;
  }

  Widget _header(ArconMono c, ArconUser? user) {
    // Açıkta ters renkli (siyah kart); koyuda diğer kartlar gibi koyu zemin + ince çerçeve
    final bg = c.dark ? c.field : c.ink;
    final fg = c.dark ? c.ink : c.bg;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: c.dark ? Border.all(color: c.line) : null,
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _photo,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClubAvatar(user: user, size: 72, inverted: !c.dark),
                if (_photoBusy)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(color: c.ink.withValues(alpha: 0.5), shape: BoxShape.circle),
                      child: Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: c.bg)),
                      ),
                    ),
                  ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c.bg,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.ink, width: 2),
                    ),
                    child: Icon(Icons.photo_camera_outlined, size: 13, color: c.ink),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.username ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: c.text(20, weight: FontWeight.w800, color: fg, spacing: -0.4),
                ),
                const SizedBox(height: 2),
                Text(
                  user?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: c.text(12.5, color: fg.withValues(alpha: 0.65)),
                ),
                if ((user?.roleName ?? '').isNotEmpty || (user?.isAdmin ?? false)) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if ((user?.roleName ?? '').isNotEmpty) _chip(c, fg, trUpper(clubRoleLabel(user!.roleName))),
                      if ((user?.isAdmin ?? false) && !clubRoleLabel(user!.roleName).contains('Yönetici')) _chip(c, fg, 'YÖNETİCİ'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(ArconMono c, Color fg, String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: fg.withValues(alpha: 0.3)),
    ),
    child: Text(
      t,
      style: c.text(9.5, weight: FontWeight.w700, color: fg, spacing: 0.8),
    ),
  );

  Widget _academyCard(ArconMono c, AcademySummary a) {
    final pct = a.total > 0 ? a.done / a.total : 0.0;
    return ClubCard(
      onTap: () => clubOpen(context, session: _s, config: widget.config, key: 'akademi'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClubIconBox(a.master ? Icons.workspace_premium_outlined : Icons.school_outlined, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a.done} / ${a.total} modül', style: c.text(16, weight: FontWeight.w800)),
                    Text(a.master ? 'Tüm modülleri tamamladın' : 'Tamamlanan eğitimler', style: c.text(12, color: c.muted)),
                  ],
                ),
              ),
              if (a.streak != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${a.streak}', style: c.text(20, weight: FontWeight.w800, height: 1)),
                    Text('hafta seri', style: c.text(10.5, color: c.muted)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: pct, minHeight: 8, color: c.ink, backgroundColor: c.line),
          ),
        ],
      ),
    );
  }

  Widget _group(ArconMono c, List<Widget> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: c.field,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: c.line),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(height: 1, thickness: 1, indent: 58, color: c.line), rows[i]],
      ],
    ),
  );

  Widget _row(ArconMono c, IconData icon, String title, {String? sub, VoidCallback? onTap, Widget? trailing, bool danger = false}) {
    final color = danger ? c.danger : c.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: c.text(14.5, weight: FontWeight.w600, color: color),
                  ),
                  if (sub != null) Text(sub, style: c.text(12, color: c.muted)),
                ],
              ),
            ),
            trailing ?? (onTap != null && !danger ? Icon(Icons.chevron_right_rounded, color: c.faint) : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}

class _InfoForm extends StatefulWidget {
  const _InfoForm({required this.session, required this.user});
  final SessionController session;
  final ArconUser user;

  @override
  State<_InfoForm> createState() => _InfoFormState();
}

class _InfoFormState extends State<_InfoForm> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.user.username);
  late final _email = TextEditingController(text: widget.user.email);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final u = await widget.session.api.updateProfile(username: _username.text.trim(), email: _email.text.trim());
      widget.session.setUser(u);
      if (mounted) Navigator.pop(context, true);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[c.errorBox(_error!), const SizedBox(height: 14)],
          c.label('Kullanıcı adı'),
          TextFormField(
            controller: _username,
            autocorrect: false,
            style: c.text(15, weight: FontWeight.w500),
            cursorColor: c.ink,
            decoration: c.input('Kullanıcı adı', Icons.person_outline_rounded),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.length < 3 || t.length > 30) return 'Kullanıcı adı 3–30 karakter olmalı';
              return null;
            },
          ),
          const SizedBox(height: 14),
          c.label('E-posta'),
          TextFormField(
            controller: _email,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            style: c.text(15, weight: FontWeight.w500),
            cursorColor: c.ink,
            decoration: c.input('E-posta', Icons.mail_outline_rounded),
            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Geçerli bir e-posta girin',
          ),
          const SizedBox(height: 20),
          c.primaryButton('Kaydet', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.session});
  final SessionController session;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.changePassword(current: _current.text, next: _next.text, confirm: _confirm.text);
      if (mounted) Navigator.pop(context, true);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    Widget field(TextEditingController ctl, String label, String hint, String? Function(String?) validator, {List<String>? hints}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            c.label(label),
            TextFormField(
              controller: ctl,
              obscureText: _obscure,
              autofillHints: hints,
              style: c.text(15, weight: FontWeight.w500),
              cursorColor: c.ink,
              decoration: c.input(hint, Icons.lock_outline_rounded),
              validator: validator,
            ),
            const SizedBox(height: 14),
          ],
        );
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[c.errorBox(_error!), const SizedBox(height: 14)],
          field(
            _current,
            'Mevcut şifre',
            '••••••••',
            (v) => (v ?? '').isEmpty ? 'Mevcut şifreni gir' : null,
            hints: const [AutofillHints.password],
          ),
          field(
            _next,
            'Yeni şifre',
            'En az 8 karakter',
            (v) => (v ?? '').length < 8 ? 'Yeni şifre en az 8 karakter olmalı' : null,
            hints: const [AutofillHints.newPassword],
          ),
          field(_confirm, 'Yeni şifre tekrar', 'Yeni şifreni tekrar yaz', (v) => v != _next.text ? 'Şifreler aynı değil' : null),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _obscure = !_obscure),
              style: TextButton.styleFrom(foregroundColor: c.muted),
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
              label: Text(_obscure ? 'Şifreleri göster' : 'Şifreleri gizle', style: c.text(13, color: c.muted)),
            ),
          ),
          const SizedBox(height: 8),
          c.primaryButton('Şifreyi değiştir', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
