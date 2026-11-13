import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'talk_controller.dart';
import 'talk_icons.dart';
import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// `#modalGroup` — Yeni grup. Oluşan kanalın id'sini döner.
Future<int?> showNewGroupSheet(BuildContext context, TalkController c) =>
    showDialog<int>(context: context, barrierColor: const Color(0x9E000000), builder: (_) => _PickerSheet(controller: c, group: true));

/// `#modalDm` — Yeni yazışma. Açılan DM kanalının id'sini döner.
Future<int?> showNewDmSheet(BuildContext context, TalkController c) =>
    showDialog<int>(context: context, barrierColor: const Color(0x9E000000), builder: (_) => _PickerSheet(controller: c, group: false));

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.controller, required this.group});
  final TalkController controller;
  final bool group;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String _type = 'group';
  bool _private = false;
  String _q = '';
  final Set<int> _selected = {};
  int _dm = 0;
  bool _busy = false;

  List<TalkUser> get _users {
    final me = widget.controller.me?.id;
    final q = _q.trim().toLowerCase();
    return widget.controller.users
        .where((u) => u.id != me)
        .where((u) => q.isEmpty || '${u.displayName} ${u.username} ${u.department}'.toLowerCase().contains(q))
        .toList();
  }

  // web: grup butonu hep aktif (ad boşsa form uyarır); DM butonu kişi seçilene kadar pasif
  bool get _canSubmit => !_busy && (widget.group || _dm > 0);
  final _nameFocus = FocusNode();

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (widget.group && _name.text.trim().isEmpty) {
      _nameFocus.requestFocus();
      talkToast(context, 'Grup adı gerekli', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final int? id;
      if (widget.group) {
        id = await widget.controller.api.createChannel(
            type: _type, name: _name.text.trim(), description: _desc.text.trim(), isPrivate: _private, memberIds: _selected.toList());
      } else {
        final ch = await widget.controller.api.openDm(_dm);
        if (ch != null) widget.controller.upsertChannel(ch);
        id = ch?.id;
      }
      if (mounted) Navigator.pop(context, id);
    } on ArconApiException catch (e) {
      if (mounted) {
        talkToast(context, e.message.isEmpty ? (widget.group ? 'Grup oluşturulamadı' : 'DM açılamadı') : e.message, error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final infoBg = c.dark ? const Color(0xFF0D1520) : const Color(0xFFF7F8FA);
    InputDecoration field(String hint) => InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.searchBg,
          hintText: hint,
          hintStyle: talkText(14.4, FontWeight.w400, c.muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.ink)),
        );
    Widget label(String t, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t, style: talkText(12.48, FontWeight.w600, c.muted)),
          const SizedBox(height: 6),
          child,
        ]);
    final users = _users;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: SizedBox(
        width: size.width - 24 > 440 ? 440 : size.width - 24,
        height: size.height - 48 > 720 ? 720 : size.height - 48,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: infoBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 60, offset: Offset(0, 24))],
          ),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Row(children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      icon: TalkIcon(TalkSvg.close, size: 20, color: c.ink),
                      tooltip: 'Kapat',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(widget.group ? 'Yeni grup' : 'Yeni yazışma', style: talkText(18.4, FontWeight.w700, c.ink)),
                ]),
              ),
              if (widget.group)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    label('Ad', TextField(controller: _name, focusNode: _nameFocus, maxLength: 120, onChanged: (_) => setState(() {}),
                        style: talkText(14.4, FontWeight.w400, c.ink), decoration: field('örn. Q4 Kampanya').copyWith(counterText: ''))),
                    const SizedBox(height: 10),
                    label(
                      'Tür',
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        dropdownColor: c.popBg,
                        style: talkText(14.4, FontWeight.w400, c.ink),
                        decoration: field(''),
                        items: const [
                          DropdownMenuItem(value: 'group', child: Text('Grup')),
                          DropdownMenuItem(value: 'project', child: Text('Proje')),
                        ],
                        onChanged: (v) => setState(() => _type = v ?? 'group'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    label('Açıklama', TextField(controller: _desc, maxLength: 255,
                        style: talkText(14.4, FontWeight.w400, c.ink), decoration: field('Opsiyonel').copyWith(counterText: ''))),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => setState(() => _private = !_private),
                      child: Row(children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _private,
                            onChanged: (v) => setState(() => _private = v ?? false),
                            activeColor: c.accent,
                            checkColor: c.accentContrast,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Özel grup', style: talkText(12.48, FontWeight.w500, c.ink)),
                      ]),
                    ),
                  ]),
                ),
              // `.talk-picker__search`
              Container(
                margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: c.searchBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.accent, width: 1.5),
                ),
                child: Row(children: [
                  TalkIcon(TalkSvg.search, size: 16, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v),
                      style: talkText(14.4, FontWeight.w400, c.ink),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: widget.group ? 'Üye ara…' : 'İsim veya kullanıcı ara',
                        hintStyle: talkText(14.4, FontWeight.w400, c.muted),
                      ),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: widget.group ? 'Üyeler' : 'Kişiler'),
                  if (widget.group && _selected.isNotEmpty)
                    TextSpan(text: ' (${_selected.length} seçili)', style: talkText(12.48, FontWeight.w600, c.ink)),
                ]), style: talkText(12.48, FontWeight.w700, c.muted, letterSpacing: 0.25)),
              ),
              Expanded(
                child: users.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
                        child: Text('Kişi bulunamadı', textAlign: TextAlign.center, style: talkText(14.4, FontWeight.w400, c.muted)),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(8, 0, 8, widget.group ? 96 : 88),
                        itemCount: users.length,
                        itemBuilder: (_, i) {
                          final u = users[i];
                          final on = widget.group ? _selected.contains(u.id) : _dm == u.id;
                          return _PickerRow(
                            user: u,
                            photoUrl: widget.controller.api.fileUrl(u.avatarPath),
                            selected: on,
                            onTap: () => setState(() {
                              if (widget.group) {
                                on ? _selected.remove(u.id) : _selected.add(u.id);
                              } else {
                                _dm = u.id;
                              }
                            }),
                          );
                        },
                      ),
              ),
            ]),
            // `.talk-picker__fab`
            Positioned(
              right: 18,
              bottom: 18,
              child: Opacity(
                opacity: _canSubmit ? 1 : 0.35,
                child: GestureDetector(
                  onTap: _canSubmit ? _submit : null,
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      boxShadow: _canSubmit ? const [BoxShadow(color: Color(0x47000000), blurRadius: 24, offset: Offset(0, 10))] : null,
                    ),
                    child: _busy
                        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.accentContrast))
                        : TalkIcon(TalkSvg.check, size: 22, color: c.accentContrast),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `.talk-picker__row`: [✓] avatar ad / departman
class _PickerRow extends StatelessWidget {
  const _PickerRow({required this.user, required this.photoUrl, required this.selected, required this.onTap});
  final TalkUser user;
  final String photoUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    return Material(
      color: selected ? c.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: selected ? c.accent : c.muted, width: 1.5),
              ),
              child: selected ? Text('✓', style: talkText(11.52, FontWeight.w800, c.accentContrast)) : null,
            ),
            const SizedBox(width: 14),
            TalkAvatar.solid(name: user.displayName, photoUrl: photoUrl, size: 48, fontSize: 12.48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(15.2, FontWeight.w700, c.ink)),
                const SizedBox(height: 2),
                Text(user.department.isNotEmpty ? user.department : (user.username.isNotEmpty ? user.username : '—'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(12.8, FontWeight.w400, c.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `#modalInvite` — Gruba üye ekle (+ davet linki)
Future<TalkSidebar?> showInviteModal(BuildContext context, TalkController c, int channelId, List<int> existing) =>
    showDialog<TalkSidebar>(context: context, barrierColor: const Color(0x8C000000), builder: (_) => _InviteModal(c, channelId, existing));

class _InviteModal extends StatefulWidget {
  const _InviteModal(this.c, this.channelId, this.existing);
  final TalkController c;
  final int channelId;
  final List<int> existing;

  @override
  State<_InviteModal> createState() => _InviteModalState();
}

class _InviteModalState extends State<_InviteModal> {
  final Set<int> _ids = {};
  String _role = 'member';
  String _link = '';

  @override
  void initState() {
    super.initState();
    widget.c.api.inviteLink(widget.channelId).then((u) {
      if (mounted) setState(() => _link = u);
    }).catchError((Object e) {
      if (mounted) talkToast(context, e is ArconApiException ? e.message : 'Davet linki alınamadı', error: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final users = widget.c.users.where((u) => u.id != widget.c.me?.id && !widget.existing.contains(u.id)).toList();
    final fieldBg = c.rail;
    return TalkModalCard(
      title: 'Gruba üye ekle',
      children: [
        Text('Kullanıcılar', style: talkText(12.8, FontWeight.w600, c.muted)),
        Container(
          height: 200,
          decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.popBorder)),
          child: ListView(children: [
            for (final u in users)
              InkWell(
                onTap: () => setState(() => _ids.contains(u.id) ? _ids.remove(u.id) : _ids.add(u.id)),
                child: Container(
                  color: _ids.contains(u.id) ? c.accentSoft : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(u.displayName, style: talkText(14.4, FontWeight.w400, c.ink)),
                ),
              ),
          ]),
        ),
        Text('Rol', style: talkText(12.8, FontWeight.w600, c.muted)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.popBorder)),
          child: DropdownButton<String>(
            value: _role,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: c.popBg,
            style: talkText(14.4, FontWeight.w400, c.ink),
            items: const [DropdownMenuItem(value: 'member', child: Text('Üye')), DropdownMenuItem(value: 'admin', child: Text('Admin'))],
            onChanged: (v) => setState(() => _role = v ?? 'member'),
          ),
        ),
        // `.talk-invite-link`
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.popBorder))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Veya davet linki gönder', style: talkText(13.12, FontWeight.w700, c.ink)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.dark ? const Color(0xFF111111) : const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.popBorder),
                  ),
                  child: Text(_link.isEmpty ? 'Link oluşturulacak…' : _link,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(12.48, FontWeight.w400, _link.isEmpty ? c.muted : Colors.white)),
                ),
              ),
              const SizedBox(width: 8),
              _Mini('Kopyala', onTap: () {
                if (_link.isEmpty) {
                  talkToast(context, 'Önce link oluşsun', error: true);
                  return;
                }
                Clipboard.setData(ClipboardData(text: _link));
                talkToast(context, 'Davet linki kopyalandı');
              }),
            ]),
            const SizedBox(height: 6),
            Text('Linke tıklayan kişi (ARCONNECT erişimi varsa) doğrudan gruba katılır.',
                style: talkText(11.52, FontWeight.w400, c.muted, height: 1.35)),
          ]),
        ),
      ],
      actions: [
        TalkButton.ghost('Vazgeç', onPressed: () => Navigator.pop(context)),
        TalkButton.primary('Davet et', onPressed: () async {
          try {
            final s = await widget.c.api.invite(widget.channelId, _ids.toList(), _role);
            if (context.mounted) {
              talkToast(context, 'Üyeler eklendi');
              Navigator.pop(context, s);
            }
          } on ArconApiException catch (e) {
            if (context.mounted) talkToast(context, e.message.isEmpty ? 'Davet başarısız' : e.message, error: true);
          }
        }),
      ],
    );
  }
}

/// `.talk-mini`
class _Mini extends StatelessWidget {
  const _Mini(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
          child: Text(label, style: talkText(12.48, FontWeight.w700, Colors.white)),
        ),
      );
}

/// `#modalDisappear` — Süreli mesajlar
Future<int?> showDisappearModal(BuildContext context, int current) => showDialog<int>(
      context: context,
      barrierColor: const Color(0x8C000000),
      builder: (ctx) {
        var sel = current;
        return StatefulBuilder(builder: (ctx, setS) {
          final c = TalkColors.of(ctx);
          return TalkModalCard(
            title: 'Süreli mesajlar',
            message: 'Bu sohbetteki yeni mesajlar seçilen süre sonunda herkesten silinir.',
            children: [
              Text('Mesaj zamanlayıcısı', style: talkText(12.8, FontWeight.w600, c.muted)),
              RadioGroup<int>(
                groupValue: sel,
                onChanged: (x) => setS(() => sel = x ?? 0),
                child: Column(children: [
                  for (final (v, l) in const [(86400, '24 saat'), (604800, '7 gün'), (7776000, '90 gün'), (0, 'Kapalı')])
                    InkWell(
                      onTap: () => setS(() => sel = v),
                      child: Row(children: [
                        Radio<int>(value: v, activeColor: c.ink, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        Text(l, style: talkText(14.4, FontWeight.w500, c.ink)),
                      ]),
                    ),
                ]),
              ),
            ],
            actions: [
              TalkButton.ghost('Vazgeç', onPressed: () => Navigator.pop(ctx)),
              TalkButton.primary('Kaydet', onPressed: () => Navigator.pop(ctx, sel)),
            ],
          );
        });
      },
    );
