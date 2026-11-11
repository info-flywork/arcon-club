import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import 'talk_controller.dart';
import 'talk_icons.dart';
import 'talk_message.dart';
import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// Kendi profilin. WhatsApp profili: fotoğraf, ad, hakkında, hesap satırı.
class TalkProfileScreen extends StatefulWidget {
  const TalkProfileScreen({super.key, required this.controller});

  final TalkController controller;

  @override
  State<TalkProfileScreen> createState() => _TalkProfileScreenState();
}

class _TalkProfileScreenState extends State<TalkProfileScreen> {
  TalkController get _c => widget.controller;
  bool _busy = false;

  TalkUser? get _me => _c.me;

  Future<void> _save(TalkUser next) async {
    _c.setMe(next);
    if (mounted) setState(() {});
  }

  Future<void> _pickPhoto() async {
    final me = _me;
    if (me == null || _busy) return;
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'camera'), child: const Text('Fotoğraf çek')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'gallery'), child: const Text('Galeriden seç')),
          if (me.avatarPath.isNotEmpty)
            CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Fotoğrafı kaldır')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      setState(() => _busy = true);
      try {
        final next = await _c.api.updateProfile(clearAvatar: true);
        await _save(next);
      } on ArconApiException catch (e) {
        if (mounted) talkToast(context, e.message.isEmpty ? 'Kaldırılamadı' : e.message, error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final x = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 90,
    );
    if (x == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final path = await _c.api.profileAvatar(x.path);
      await _save(me.copyWith(avatarPath: path));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Foto yüklenemedi' : e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({required String title, required String initial, required int max, required String hint, required Future<TalkUser> Function(String) save}) async {
    final ctrl = TextEditingController(text: initial);
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (ctx) {
        final c = TalkColors.of(ctx);
        return Scaffold(
          backgroundColor: c.dark ? c.infoBg : const Color(0xFFF7F8FA),
          appBar: AppBar(
            backgroundColor: c.header,
            foregroundColor: c.ink,
            elevation: 0,
            title: Text(title, style: talkText(17, FontWeight.w700, c.ink)),
            actions: [
              IconButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                icon: TalkIcon(TalkSvg.check, size: 22, color: TalkColors.wa),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: max,
              maxLines: max > 80 ? 4 : 1,
              style: talkText(16, FontWeight.w400, c.ink),
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                fillColor: c.dark ? c.infoCard : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
              ),
            ),
          ),
        );
      },
    ));
    ctrl.dispose();
    if (value == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _save(await save(value.trim()));
      if (mounted) talkToast(context, 'Kaydedildi');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Kaydedilemedi' : e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePassword() async {
    if (_busy) return;
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (ctx) {
        final c = TalkColors.of(ctx);
        String? err;
        var sending = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> submit() async {
              if (sending) return;
              setLocal(() {
                sending = true;
                err = null;
              });
              try {
                await _c.api.changePassword(current: current.text, next: next.text, confirm: confirm.text);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on ArconApiException catch (e) {
                setLocal(() {
                  sending = false;
                  err = e.message.isEmpty ? 'Şifre değiştirilemedi' : e.message;
                });
              }
            }

            InputDecoration deco(String hint) => InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: c.dark ? c.infoCard : Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
                );

            return Scaffold(
              backgroundColor: c.dark ? c.infoBg : const Color(0xFFF7F8FA),
              appBar: AppBar(
                backgroundColor: c.header,
                foregroundColor: c.ink,
                elevation: 0,
                title: Text('Şifre', style: talkText(17, FontWeight.w700, c.ink)),
                actions: [
                  IconButton(
                    onPressed: sending ? null : submit,
                    icon: TalkIcon(TalkSvg.check, size: 22, color: TalkColors.wa),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: current,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    style: talkText(16, FontWeight.w400, c.ink),
                    decoration: deco('Mevcut şifre'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: next,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    style: talkText(16, FontWeight.w400, c.ink),
                    decoration: deco('Yeni şifre (en az 8 karakter)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirm,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => submit(),
                    style: talkText(16, FontWeight.w400, c.ink),
                    decoration: deco('Yeni şifre tekrar'),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 12),
                    Text(err!, style: talkText(14, FontWeight.w500, TalkColors.danger)),
                  ],
                  if (sending)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            );
          },
        );
      },
    ));
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (saved == true && mounted) talkToast(context, 'Şifre güncellendi');
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final me = _me;
    final name = me?.displayName ?? '';
    final about = me?.about ?? '';
    final email = me?.email ?? '';
    final photo = me == null ? '' : _c.api.fileUrl(me.avatarPath);
    return Scaffold(
      backgroundColor: c.dark ? c.infoBg : const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: c.header,
        foregroundColor: c.ink,
        elevation: 0,
        title: Text('Profil', style: talkText(17, FontWeight.w700, c.ink)),
      ),
      body: me == null
          ? Center(child: Text('Profil yüklenemedi', style: talkText(16, FontWeight.w600, c.ink)))
          : ListView(children: [
              const SizedBox(height: 28),
              Center(
                child: SizedBox(
                  width: 168,
                  height: 168,
                  child: Stack(children: [
                    GestureDetector(
                      onTap: photo.isEmpty ? _pickPhoto : () => openTalkImage(context, photo, name),
                      child: TalkAvatar.solid(name: name, photoUrl: photo, size: 160, fontSize: 42),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: GestureDetector(
                        onTap: _busy ? null : _pickPhoto,
                        child: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: TalkColors.wa,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.dark ? c.infoBg : const Color(0xFFF7F8FA), width: 3),
                          ),
                          child: const TalkIcon(TalkSvg.camera, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              _row(
                c,
                label: 'Ad',
                value: name,
                onTap: () => _edit(
                  title: 'Ad',
                  initial: name,
                  max: 80,
                  hint: 'Adın',
                  save: (v) => _c.api.updateProfile(displayName: v),
                ),
              ),
              _row(
                c,
                label: 'Hakkında',
                value: about.isEmpty ? 'Hakkında ekle' : about,
                muted: about.isEmpty,
                onTap: () => _edit(
                  title: 'Hakkında',
                  initial: about,
                  max: 139,
                  hint: 'Hakkında bir şeyler yaz',
                  save: (v) => _c.api.updateProfile(about: v),
                ),
              ),
              if (email.isNotEmpty) _row(c, label: 'E-posta', value: email),
              _row(c, label: 'Şifre', value: 'Değiştir', muted: true, onTap: _changePassword),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ]),
    );
  }

  Widget _row(TalkColors c, {required String label, required String value, bool muted = false, VoidCallback? onTap}) {
    return Material(
      color: c.dark ? c.infoCard : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: talkText(12.5, FontWeight.w600, c.muted)),
                const SizedBox(height: 4),
                Text(value, style: talkText(16, FontWeight.w400, muted ? c.muted : c.ink)),
              ]),
            ),
            if (onTap != null) TalkIcon(TalkSvg.edit, size: 18, color: TalkColors.wa),
          ]),
        ),
      ),
    );
  }
}
