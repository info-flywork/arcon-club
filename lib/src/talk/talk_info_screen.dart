import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import 'talk_call_screen.dart';
import 'talk_chat_screen.dart';
import 'talk_contact_sheet.dart';
import 'talk_controller.dart';
import 'talk_icons.dart';
import 'talk_media_screen.dart';
import 'talk_models.dart';
import 'talk_pickers.dart';
import 'talk_privacy.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';
import '../ui/skeleton.dart';

const _fileSvg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/></svg>';
const _mailSvg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4h16v16H4z"/><path d="M4 7l8 6 8-6"/></svg>';

/// WhatsApp iOS grup / kişi bilgisi: büyük fotoğraf, ad, hızlı düğmeler ve Üyeler / Medya / Ayarlar sekmeleri.
/// Sohbet ekranına dönüş değerleri: 'search' (sohbette ara), 'jump:<mesaj id>', 'left' (gruptan çıkıldı), 'cleared' (sohbet temizlendi).
class TalkInfoScreen extends StatefulWidget {
  const TalkInfoScreen({super.key, required this.controller, required this.channel, required this.session, required this.config, this.sidebar});

  final TalkController controller;
  final TalkChannel channel;
  final SessionController session;
  final ArconAppConfig config;
  final TalkSidebar? sidebar;

  @override
  State<TalkInfoScreen> createState() => _TalkInfoScreenState();
}

class _TalkInfoScreenState extends State<TalkInfoScreen> {
  TalkController get _c => widget.controller;
  late TalkSidebar? _s = widget.sidebar;
  final _scroll = ScrollController();
  final _taskInput = TextEditingController();
  final _memberQuery = TextEditingController();
  String _tab = '';
  bool _descOpen = false;
  bool _searchMembers = false;
  bool _titleInBar = false;
  String _myAvatar = '';

  @override
  void initState() {
    super.initState();
    _apply(_s);
    _scroll.addListener(() {
      final show = _scroll.offset > 230;
      if (show != _titleInBar) setState(() => _titleInBar = show);
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _taskInput.dispose();
    _memberQuery.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _c.api.sidebar(widget.channel.id);
      if (mounted) setState(() => _apply(s));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message, error: true);
    }
  }

  void _apply(TalkSidebar? s) {
    _s = s;
    _myAvatar = _c.me?.avatarPath ?? '';
  }

  bool get _isDm => _s?.isDm ?? widget.channel.isDm;
  bool get _canManage => (_s?.canManage ?? false) && !_isDm;
  bool get _canInvite => (_s?.canInvite ?? false) && !_isDm;
  int get _meId => _c.me?.id ?? 0;
  String get _currentTab => _tab.isNotEmpty ? _tab : (_isDm ? 'media' : 'members');

  TalkUser? get _peer {
    final p = _s?.channel['peer'];
    return p is Map ? TalkUser.fromJson(p.cast<String, dynamic>()) : widget.channel.peer;
  }

  String get _photo {
    final s = _s;
    final own = s?.avatarPath ?? widget.channel.avatarPath;
    return own.isNotEmpty ? own : (_peer?.avatarPath ?? '');
  }

  String get _title => (_s?.name ?? '').isNotEmpty ? _s!.name : widget.channel.name;

  // ---------- işlemler ----------

  /// Grup adı ve açıklaması (yalnızca yönetebilen)
  Future<void> _editGroup() async {
    final s = _s;
    if (s == null || !_canManage) return;
    final name = TextEditingController(text: s.name);
    final desc = TextEditingController(text: s.description);
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Grubu düzenle'),
        content: Column(children: [
          const SizedBox(height: 10),
          CupertinoTextField(controller: name, placeholder: 'Grup adı', maxLength: 120),
          const SizedBox(height: 8),
          CupertinoTextField(controller: desc, placeholder: 'Grup açıklaması', maxLines: 4, minLines: 2, maxLength: 255),
        ]),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final ns = await _c.api.updateChannel(widget.channel.id, name: name.text.trim(), description: desc.text.trim());
      setState(() => _apply(ns));
      widget.channel.name = ns.name;
      if (mounted) talkToast(context, 'Kaydedildi');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Kaydedilemedi' : e.message, error: true);
    }
  }

  Future<void> _pickChannelAvatar() async {
    if (!_canManage) return;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    try {
      final s = await _c.api.updateChannel(widget.channel.id, avatarPath: x.path);
      setState(() => _apply(s));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Foto yüklenemedi' : e.message, error: true);
    }
  }

  Future<void> _pickMyAvatar() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    try {
      final p = await _c.api.profileAvatar(x.path);
      setState(() => _myAvatar = p);
      if (mounted) talkToast(context, 'Profil fotoğrafı güncellendi');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Foto yüklenemedi' : e.message, error: true);
    }
  }

  Future<void> _disappear() async {
    final s = _s;
    if (s == null) return;
    if (!s.canSetDisappear) {
      talkToast(context, s.disappearSec > 0
          ? 'Süreli mesaj açık: ${s.disappearLabel}. Değiştirmek için grup yöneticisi olmalısın.'
          : 'Süreli mesajı yalnızca grup yöneticisi (birebir sohbette iki taraf) ayarlayabilir.');
      return;
    }
    final sec = await showDisappearModal(context, s.disappearSec);
    if (sec == null) return;
    try {
      final ns = await _c.api.setDisappear(widget.channel.id, sec);
      setState(() => _apply(ns));
      if (mounted) talkToast(context, sec > 0 ? 'Süreli mesaj: ${ns.disappearLabel}' : 'Süreli mesaj kapatıldı');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Ayarlanamadı' : e.message, error: true);
    }
  }

  Future<void> _invite() async {
    if (!_canInvite) {
      talkToast(context, 'Üye ekleme yetkin yok', error: true);
      return;
    }
    final ns = await showInviteModal(context, _c, widget.channel.id, [for (final p in _s?.people ?? const <TalkUser>[]) p.id]);
    if (ns != null) setState(() => _apply(ns));
  }

  /// Grupta / birebirde arama (grupta önce sesli mi görüntülü mü sorulur)
  Future<void> _call({bool? video}) async {
    var v = video;
    if (v == null) {
      final pick = await showCupertinoModalPopup<bool>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Sesli arama')),
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, true), child: const Text('Görüntülü arama')),
          ],
          cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        ),
      );
      if (pick == null) return;
      v = pick;
    }
    if (!mounted) return;
    await TalkCallScreen.start(
      context,
      api: _c.api,
      channelId: widget.channel.id,
      video: v,
      title: _title,
      peerName: _isDm ? (_peer?.displayName ?? _title) : _title,
      photoUrl: _c.api.fileUrl(_photo),
    );
  }

  /// Paylaş: grupta davet bağlantısı (yetkiliyse), değilse grup / kişi adı
  Future<void> _share() async {
    final box = context.findRenderObject() as RenderBox?;
    var text = _isDm ? "${_peer?.displayName ?? _title} · ARCONNECT'te @${_peer?.username ?? ''}" : "ARCONNECT grubu: $_title";
    if (_canInvite) {
      try {
        final url = await _c.api.inviteLink(widget.channel.id);
        if (url.isNotEmpty) text = "ARCONNECT'te \"$_title\" grubuna katıl: $url";
      } on ArconApiException {
        // bağlantı alınamazsa grup adı paylaşılır
      }
    }
    await SharePlus.instance.share(ShareParams(
      text: text,
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
  }

  /// Sohbeti dışa aktar: son mesajlar düz metin olarak paylaşılır
  Future<void> _export() async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      final r = await _c.api.messages(widget.channel.id);
      String two(int n) => n.toString().padLeft(2, '0');
      final lines = [
        for (final m in r.messages)
          if (m.body.trim().isNotEmpty || m.attachments.isNotEmpty)
            () {
              final d = talkParseTime(m.createdAt);
              final at = d == null ? '' : '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
              final files = m.attachments.map((a) => '<${a.origName}>').join(' ');
              return '[$at] ${m.displayName.isEmpty ? m.username : m.displayName}: ${m.body.trim()} $files'.trim();
            }(),
      ];
      if (lines.isEmpty) {
        if (mounted) talkToast(context, 'Dışa aktarılacak mesaj yok');
        return;
      }
      await SharePlus.instance.share(ShareParams(
        text: 'ARCONNECT · $_title\n\n${lines.join('\n')}',
        subject: '$_title sohbeti',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Dışa aktarılamadı' : e.message, error: true);
    }
  }

  /// Benzer bir grup: aynı üyelerle yeni grup
  Future<void> _similarGroup() async {
    final s = _s;
    if (s == null) return;
    final name = TextEditingController(text: '${s.name} 2');
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Benzer bir grup oluşturun'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(children: [
            Text('${s.people.length} üyeyle yeni grup', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            CupertinoTextField(controller: name, placeholder: 'Grup adı', maxLength: 120),
          ]),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Oluştur')),
        ],
      ),
    );
    if (ok != true || !mounted || name.text.trim().length < 2) return;
    try {
      final id = await _c.api.createChannel(
        type: 'group',
        name: name.text.trim(),
        memberIds: [for (final p in s.people) if (p.id != _meId) p.id],
      );
      await _c.refresh();
      final ch = _c.channels.where((x) => x.id == id).firstOrNull;
      if (ch == null || !mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => TalkChatScreen(controller: _c, channel: ch, config: widget.config, session: widget.session),
      ));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Grup oluşturulamadı' : e.message, error: true);
    }
  }

  /// Sohbeti kilitle: yalnızca bu telefonda; her iki yönde de Face ID / parmak izi ister
  Future<void> _toggleLock() async {
    final id = widget.channel.id;
    final on = _c.locked.contains(id);
    if (!await talkUnlock(context, reason: on ? 'Sohbetin kilidini açmak için doğrula' : 'Sohbeti kilitlemek için doğrula') || !mounted) return;
    await _c.toggleLock(id);
    if (mounted) talkToast(context, on ? 'Sohbetin kilidi açıldı' : 'Sohbet kilitlendi · Sohbetler › Kilitli sohbetler');
  }

  /// Kısıtlı sohbet: açıklama + (yöneticiyse) aç/kapat
  Future<void> _restrictedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final c = TalkColors.of(ctx);
        final on = _s?.restricted ?? false;
        return Container(
          decoration: BoxDecoration(color: _bg(c), borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(CupertinoIcons.shield_lefthalf_fill, size: 40, color: c.ink),
                const SizedBox(height: 10),
                Text('Kısıtlı sohbet', textAlign: TextAlign.center, style: talkText(20, FontWeight.w700, c.ink)),
                const SizedBox(height: 8),
                Text(
                  'Açıkken bu sohbetteki mesajlar başka sohbetlere iletilemez ve sohbet dışa aktarılamaz. Ayar sohbetteki herkes için geçerlidir.',
                  textAlign: TextAlign.center,
                  style: talkText(15, FontWeight.w400, c.muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: _cardBg(c), borderRadius: BorderRadius.circular(16)),
                  child: _row(
                    c,
                    title: 'Kısıtlı sohbet',
                    subtitle: _canManage ? null : 'Yalnızca grup yöneticileri değiştirebilir',
                    trailing: CupertinoSwitch(
                      value: on,
                      activeTrackColor: c.ink,
                      onChanged: !_canManage
                          ? null
                          : (v) async {
                              try {
                                final ns = await _c.api.setRestricted(widget.channel.id, v);
                                if (!mounted) return;
                                setState(() => _apply(ns));
                                setSheet(() {});
                              } on ArconApiException catch (e) {
                                if (mounted) talkToast(context, e.message.isEmpty ? 'Ayarlanamadı' : e.message, error: true);
                              }
                            },
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  /// Şifreleme: gerçekte ne olduğunu anlatır (uçtan uca değil)
  Future<void> _encryptionSheet() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final c = TalkColors.of(ctx);
          return Container(
            decoration: BoxDecoration(color: _bg(c), borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(CupertinoIcons.lock_fill, size: 40, color: c.ink),
                  const SizedBox(height: 10),
                  Text('Şifreleme', style: talkText(20, FontWeight.w700, c.ink)),
                  const SizedBox(height: 10),
                  Text(
                    'Mesajlar, dosyalar ve aramalar telefonun ile ARCON sunucuları arasında şifreli bağlantı (HTTPS) üzerinden iletilir. '
                    'Mesajlar şirketin ARCON sunucusunda saklanır; uçtan uca şifreli değildir.',
                    textAlign: TextAlign.center,
                    style: talkText(15, FontWeight.w400, c.muted, height: 1.45),
                  ),
                ]),
              ),
            ),
          );
        },
      );

  /// Sohbeti temizle: eski mesajlar yalnızca senden gizlenir
  Future<void> _clearChat() async {
    final ok = await talkConfirm(context,
        title: 'Sohbet temizlensin mi?', message: 'Bu sohbetteki mesajlar yalnızca senin için silinir. Diğer üyelerde kalır.', ok: 'Temizle');
    if (!ok || !mounted) return;
    try {
      await _c.api.clearChat(widget.channel.id);
      if (!mounted) return;
      talkToast(context, 'Sohbet temizlendi');
      Navigator.of(context).pop('cleared');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Temizlenemedi' : e.message, error: true);
    }
  }

  /// Şikayet et: sebep seçilir, ARCON platform yöneticisine (Anılcan) birebir mesajla bildirilir
  Future<void> _report() async {
    const adminId = 2;
    if (_meId == adminId) {
      talkToast(context, 'Şikayetler zaten sana geliyor');
      return;
    }
    final kind = _isDm ? 'Kişiyi' : 'Grubu';
    final reason = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('$kind şikayet et'),
        message: const Text('Şikayet ARCON yöneticisine iletilir. Kimse sohbetten çıkarılmaz.'),
        actions: [
          for (final r in const ['Uygunsuz içerik', 'Taciz veya hakaret', 'Spam', 'Gizli bilgi paylaşımı', 'Diğer'])
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, r), child: Text(r)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (reason == null || !mounted) return;
    try {
      final dm = await _c.api.openDm(adminId);
      if (dm == null) throw const ArconApiException('report', '');
      _c.upsertChannel(dm);
      await _c.api.sendMessage(
        channelId: dm.id,
        body: '⚠️ Şikayet · ${_isDm ? 'Kişi' : 'Grup'}: $_title (#${widget.channel.id})\nSebep: $reason',
      );
      if (mounted) talkToast(context, 'Şikayetin iletildi');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Şikayet gönderilemedi' : e.message, error: true);
    }
  }

  /// Sohbeti sil: listeden kaldırır (yeni mesaj gelince geri gelir)
  Future<void> _deleteChat() async {
    final ok = await talkConfirm(context,
        title: 'Bu sohbet silinsin mi?', message: 'Sohbet listenden kaldırılır. Yeni mesaj gelirse yeniden görünür.', ok: 'Sil');
    if (!ok || !mounted) return;
    try {
      await _c.hideChat(widget.channel);
      if (mounted) Navigator.of(context).pop('left');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Silinemedi' : e.message, error: true);
    }
  }

  Future<void> _leave() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('"${widget.channel.name}" grubundan çıkılsın mı?'),
        content: const Text('Bu gruptan artık mesaj almayacaksın.'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Çık')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _c.leaveChannel(widget.channel);
      if (!mounted) return;
      talkToast(context, 'Gruptan çıktın');
      Navigator.of(context).pop('left');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Gruptan çıkılamadı' : e.message, error: true);
    }
  }

  /// "…": sohbette ara, sessize al, arşivle, grubu düzenle, profil fotoğrafım
  Future<void> _more() async {
    final id = widget.channel.id;
    final v = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'search'), child: const Text('Sohbette ara')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'mute'), child: Text(_c.muted.contains(id) ? 'Bildirimleri aç' : 'Sessize al')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'archive'), child: Text(_c.archived.contains(id) ? 'Arşivden çıkar' : 'Sohbeti arşivle')),
          if (_canManage) CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'edit'), child: const Text('Grubu düzenle')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'photo'), child: const Text('Profil fotoğrafımı değiştir')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'search':
        Navigator.pop(context, 'search');
      case 'mute':
        await _c.toggleMute(id);
      case 'archive':
        await _c.toggleArchive(id);
      case 'edit':
        await _editGroup();
      case 'photo':
        await _pickMyAvatar();
    }
    if (mounted) setState(() {});
  }

  // ---------- üyeler ----------

  Future<void> _openMember(TalkUser p) async {
    final manage = _canManage && p.id != _meId && p.role != 'owner';
    await showTalkContactSheet(
      context: context,
      user: p,
      photoUrl: _c.api.fileUrl(p.avatarPath),
      onMessage: () => _memberOp('dm', p),
      onVoice: () => _callMember(p, video: false),
      onVideo: () => _callMember(p, video: true),
      onInfo: () => _memberInfo(p),
      admin: manage
          ? (
              isAdmin: p.role == 'admin',
              onToggleAdmin: () => _memberOp(p.role == 'admin' ? 'demote' : 'promote', p),
              onRemove: () => _memberOp('remove', p),
            )
          : null,
    );
  }

  /// Üyenin kişi bilgisi (birebir sohbetin bilgi ekranı)
  Future<void> _memberInfo(TalkUser u) async {
    try {
      final ch = await _c.api.openDm(u.id);
      if (ch == null || !mounted) return;
      _c.upsertChannel(ch);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TalkInfoScreen(controller: _c, channel: ch, session: widget.session, config: widget.config),
      ));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Bilgi açılamadı' : e.message, error: true);
    }
  }

  Future<void> _callMember(TalkUser u, {required bool video}) async {
    try {
      final ch = await _c.api.openDm(u.id);
      if (ch == null || !mounted) return;
      _c.upsertChannel(ch);
      await TalkCallScreen.start(
        context,
        api: _c.api,
        channelId: ch.id,
        video: video,
        title: u.displayName,
        peerName: u.displayName,
        photoUrl: _c.api.fileUrl(u.avatarPath),
      );
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Arama başlatılamadı' : e.message, error: true);
    }
  }

  Future<void> _memberOp(String act, TalkUser u) async {
    try {
      if (act == 'dm') {
        final ch = await _c.api.openDm(u.id);
        if (ch != null) _c.upsertChannel(ch);
        if (ch != null && mounted) {
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => TalkChatScreen(controller: _c, channel: ch, config: widget.config, session: widget.session),
          ));
        }
        return;
      }
      TalkSidebar ns;
      if (act == 'remove') {
        if (!await talkConfirm(context, title: 'Gruptan çıkar', message: '${u.displayName} gruptan çıkarılsın mı?', ok: 'Çıkar')) return;
        ns = await _c.api.removeMember(widget.channel.id, u.id);
        if (mounted) talkToast(context, '${talkFirstName(u.displayName)} gruptan çıkarıldı');
      } else if (act == 'promote') {
        ns = await _c.api.setRole(widget.channel.id, u.id, 'admin');
        if (mounted) talkToast(context, '${talkFirstName(u.displayName)} artık grup yöneticisi');
      } else {
        ns = await _c.api.setRole(widget.channel.id, u.id, 'member');
        if (mounted) talkToast(context, '${talkFirstName(u.displayName)} yöneticilikten çıkarıldı');
      }
      setState(() => _apply(ns));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'İşlem başarısız' : e.message, error: true);
    }
  }

  // ---------- görünüm ----------

  Color _bg(TalkColors c) => c.dark ? Colors.black : const Color(0xFFF2F2F7);
  Color _cardBg(TalkColors c) => c.dark ? const Color(0xFF1C1C1E) : Colors.white;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final s = _s;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: _bg(c),
      body: Stack(children: [
        ListenableBuilder(
          listenable: _c,
          builder: (context, _) => ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(0, top + 58, 0, MediaQuery.paddingOf(context).bottom + 30),
            children: [
              _hero(c, s),
              _quickActions(c),
              if (s == null)
                const Padding(padding: EdgeInsets.only(top: 16), child: SkeletonList(count: 4, padding: EdgeInsets.symmetric(horizontal: 16)))
              else ...[
                _tabs(c),
                ...switch (_currentTab) {
                  'members' => _membersTab(c, s),
                  'media' => _mediaTab(c, s),
                  _ => _settingsTab(c, s),
                },
              ],
            ],
          ),
        ),
        _topBar(c, top),
      ]),
    );
  }

  /// Üstte geri ve "…"; aşağı kayınca ortada ad
  Widget _topBar(TalkColors c, double top) {
    Widget circle(Widget child, VoidCallback onTap, String tip, {double width = 44}) => Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: width,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _cardBg(c),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE6E6E8)),
                boxShadow: c.dark ? null : const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: child,
            ),
          ),
        );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.fromLTRB(16, top + 4, 16, 8),
      color: _titleInBar ? _bg(c).withValues(alpha: 0.96) : Colors.transparent,
      child: Row(children: [
        circle(Icon(CupertinoIcons.chevron_left, size: 22, color: c.ink), () => Navigator.pop(context), 'Geri'),
        Expanded(
          child: AnimatedOpacity(
            opacity: _titleInBar ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Text(_title, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w600, c.ink)),
          ),
        ),
        circle(Icon(Icons.more_horiz, size: 24, color: c.ink), _more, 'Diğer', width: 60),
      ]),
    );
  }

  Widget _hero(TalkColors c, TalkSidebar? s) {
    final total = s == null ? widget.channel.memberCount : ((s.channel['member_count'] as num?)?.toInt() ?? s.people.length);
    final sub = _isDm
        ? (_peer?.username.isNotEmpty ?? false ? '@${_peer!.username}' : 'Birebir sohbet')
        : 'Grup · ${total > 0 ? total : s?.people.length ?? 0} üye';
    final desc = _isDm ? (_peer?.about ?? '') : (s?.description ?? widget.channel.description);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      child: Column(children: [
        GestureDetector(
          onTap: _canManage ? _pickChannelAvatar : null,
          child: _isDm || _photo.isNotEmpty
              ? TalkAvatar.solid(name: _title, photoUrl: _c.api.fileUrl(_photo), size: 150, fontSize: 46, personIfEmpty: true)
              : Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA), shape: BoxShape.circle),
                  child: Icon(CupertinoIcons.person_2_fill, size: 72, color: c.dark ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93)),
                ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _canManage ? _editGroup : null,
          child: Text(_title, textAlign: TextAlign.center, style: talkText(28, FontWeight.w700, c.ink, letterSpacing: -0.5, height: 1.15)),
        ),
        const SizedBox(height: 4),
        Text(sub, textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
        if (desc.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _descOpen = !_descOpen),
            child: Column(children: [
              Text(
                desc.trim(),
                textAlign: TextAlign.center,
                maxLines: _descOpen ? null : 2,
                overflow: _descOpen ? null : TextOverflow.ellipsis,
                style: talkText(15, FontWeight.w400, c.dark ? const Color(0xFFD1D1D6) : const Color(0xFF3A3A3C), height: 1.4),
              ),
              if (!_descOpen && desc.trim().length > 70)
                Text('Devamını okuyun', style: talkText(15, FontWeight.w600, c.ink, height: 1.4)),
            ]),
          ),
        ] else if (_canManage) ...[
          const SizedBox(height: 8),
          GestureDetector(onTap: _editGroup, child: Text('Grup açıklaması ekle', style: talkText(15, FontWeight.w500, c.muted))),
        ],
      ]),
    );
  }

  /// Ara / Paylaş / Ara (QR, Durum yok)
  Widget _quickActions(TalkColors c) {
    Widget btn(Widget icon, String label, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(children: [
              Container(
                width: 62,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _cardBg(c),
                  borderRadius: BorderRadius.circular(27),
                  border: Border.all(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE6E6E8)),
                ),
                child: icon,
              ),
              const SizedBox(height: 8),
              Text(label, style: talkText(14, FontWeight.w400, c.ink)),
            ]),
          ),
        );
    final ink = c.ink;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 22),
      child: Row(children: [
        if (_isDm) ...[
          btn(Icon(CupertinoIcons.phone, size: 24, color: ink), 'Sesli', () => _call(video: false)),
          btn(Icon(CupertinoIcons.video_camera, size: 28, color: ink), 'Görüntülü', () => _call(video: true)),
        ] else
          btn(
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.video_camera, size: 28, color: ink),
              Icon(CupertinoIcons.chevron_down, size: 12, color: ink),
            ]),
            'Ara',
            _call,
          ),
        btn(Icon(CupertinoIcons.share, size: 24, color: ink), 'Paylaş', _share),
        btn(Icon(CupertinoIcons.search, size: 24, color: ink), 'Ara', () => Navigator.pop(context, 'search')),
      ]),
    );
  }

  Widget _tabs(TalkColors c) {
    final tabs = [if (!_isDm) ('members', 'Üyeler'), ('media', 'Medya'), ('settings', 'Ayarlar')];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final (k, l) in tabs)
          GestureDetector(
            onTap: () => setState(() => _tab = k),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: _currentTab == k ? _cardBg(c) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _currentTab == k ? (c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE6E6E8)) : Colors.transparent),
              ),
              child: Text(l, style: talkText(16, _currentTab == k ? FontWeight.w600 : FontWeight.w500, _currentTab == k ? c.ink : c.muted)),
            ),
          ),
      ]),
    );
  }

  /// Beyaz yuvarlak kart (satırlar arası çizgi)
  Widget _group(TalkColors c, List<Widget> rows, {double indent = 64}) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: _cardBg(c), borderRadius: BorderRadius.circular(22)),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1) Padding(padding: EdgeInsets.only(left: indent), child: Divider(height: 0.6, thickness: 0.6, color: c.rowLine)),
          ],
        ]),
      );

  /// Simgeli satır (Ayarlar)
  Widget _row(TalkColors c, {IconData? icon, required String title, String? subtitle, String? value, Widget? trailing, VoidCallback? onTap, Color? color, bool chevron = true}) {
    final ink = color ?? c.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(icon == null ? 20 : 18, 13, 16, 13),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 24, color: ink), const SizedBox(width: 22)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: talkText(17, FontWeight.w400, ink)),
              if (subtitle != null) Text(subtitle, style: talkText(13.5, FontWeight.w400, c.muted, height: 1.3)),
            ]),
          ),
          if (value != null) Text(value, style: talkText(16, FontWeight.w400, c.muted)),
          ?trailing,
          if (chevron && trailing == null && onTap != null) ...[const SizedBox(width: 6), Icon(CupertinoIcons.chevron_right, size: 16, color: c.muted)],
        ]),
      ),
    );
  }

  List<Widget> _membersTab(TalkColors c, TalkSidebar s) {
    final q = _memberQuery.text.trim().toLowerCase();
    int rank(TalkUser p) => p.id == _meId ? 0 : (p.role == 'owner' ? 1 : (p.role == 'admin' ? 2 : 3));
    final people = s.people.where((p) => q.isEmpty || '${p.displayName} ${p.username} ${p.department}'.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    String roleLabel(TalkUser p) => p.isAdmin ? 'Yönetici' : '';

    Widget person(TalkUser p) {
      final me = p.id == _meId;
      final sub = p.department.trim().isNotEmpty ? p.department.trim() : p.about.trim();
      return InkWell(
        onTap: me ? null : () => _openMember(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Row(children: [
            TalkAvatar.solid(name: p.displayName, photoUrl: _c.api.fileUrl(p.avatarPath), size: 40, personIfEmpty: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me ? 'Siz' : p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w400, c.ink)),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(13.5, FontWeight.w400, c.muted)),
              ]),
            ),
            if (roleLabel(p).isNotEmpty) Text(roleLabel(p), style: talkText(15, FontWeight.w400, c.muted)),
            if (!me) ...[const SizedBox(width: 6), Icon(CupertinoIcons.chevron_right, size: 16, color: c.muted)],
          ]),
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 20, 8),
        child: Row(children: [
          Expanded(child: Text('${s.people.length} üye', style: talkText(17, FontWeight.w600, c.muted))),
          Tooltip(
            message: 'Üye ara',
            child: GestureDetector(
              onTap: () => setState(() {
                _searchMembers = !_searchMembers;
                if (!_searchMembers) _memberQuery.clear();
              }),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA), shape: BoxShape.circle),
                child: Icon(_searchMembers ? CupertinoIcons.xmark : CupertinoIcons.search, size: 18, color: c.ink),
              ),
            ),
          ),
        ]),
      ),
      if (_searchMembers)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: CupertinoSearchTextField(
            controller: _memberQuery,
            autofocus: true,
            placeholder: 'Üye ara',
            onChanged: (_) => setState(() {}),
          ),
        ),
      _group(c, [
        if (_canInvite && q.isEmpty)
          InkWell(
            onTap: _invite,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7), shape: BoxShape.circle),
                  child: Icon(CupertinoIcons.add, size: 22, color: c.ink),
                ),
                const SizedBox(width: 12),
                Text('Üye ekle', style: talkText(17, FontWeight.w400, c.ink)),
              ]),
            ),
          ),
        for (final p in people) person(p),
        if (q.isEmpty) _row(c, icon: CupertinoIcons.list_bullet, title: 'Üye değişikliklerini görüntüle', onTap: () => _activitySheet(s)),
      ]),
      _boardCard(c, TalkSvg.decisions, 'Kararlar', _decisions(c, s)),
      _boardCard(c, TalkSvg.tasks, 'Görevler', _tasks(c, s)),
      _footer(c, s),
    ];
  }

  void _openMedia(TalkSidebar s) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TalkMediaScreen(controller: _c, channelId: widget.channel.id, files: s.files, restricted: s.restricted),
      ));

  /// Medya: galeri önizlemesi (4 sütun) ve "Medya, bağlantı ve belgeler" satırı
  List<Widget> _mediaTab(TalkColors c, TalkSidebar s) {
    final media = s.files.where((f) => f.isImage || f.isVideo).take(8).toList();
    return [
      _group(c, [
        _row(c, icon: CupertinoIcons.photo_on_rectangle, title: 'Medya, bağlantı ve belgeler', value: '${s.files.length}', onTap: () => _openMedia(s)),
        if (media.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              // padding verilmezse ızgara ekranın güvenli alan boşluğunu (çentik/alt çubuk) ekler
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              children: [
                for (final f in media)
                  GestureDetector(
                    onTap: () => _openMedia(s),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: f.isImage
                          ? TalkNetImage(_c.api.thumbUrl(f.path, width: 240), fallbackUrl: _c.api.fileUrl(f.path), fit: BoxFit.cover, decodeWidth: 140, placeholder: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA))
                          : const ColoredBox(color: Color(0xFF1C1C1E), child: Center(child: Icon(CupertinoIcons.play_fill, color: Colors.white70))),
                    ),
                  ),
              ],
            ),
          )
        else
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: Text('Henüz fotoğraf veya video yok', style: talkText(14, FontWeight.w400, c.muted))),
      ]),
      _footer(c, s),
    ];
  }

  List<Widget> _settingsTab(TalkColors c, TalkSidebar s) {
    final id = widget.channel.id;
    final muted = _c.muted.contains(id);
    final fav = _c.favourites.contains(id);
    final inLists = _c.lists.entries.where((e) => e.value.contains(id)).map((e) => e.key).toList();
    return [
      _group(c, [
        _row(c, icon: CupertinoIcons.timer, title: 'Süreli mesajlar', value: s.disappearLabel, onTap: _disappear),
        _row(
          c,
          icon: CupertinoIcons.lock_shield,
          title: 'Sohbeti kilitle',
          subtitle: 'Bu sohbeti bu cihazda kilitleyin ve gizleyin.',
          trailing: CupertinoSwitch(value: _c.locked.contains(id), activeTrackColor: c.ink, onChanged: (_) => _toggleLock()),
        ),
        _row(c, icon: CupertinoIcons.shield_lefthalf_fill, title: 'Kısıtlı sohbet', value: s.restricted ? 'Açık' : 'Kapalı', onTap: _restrictedSheet),
        _row(c, icon: CupertinoIcons.lock, title: 'Şifreleme', subtitle: 'Mesajlar şifreli bağlantıyla iletilir. Daha fazla bilgi', onTap: _encryptionSheet),
        _row(
          c,
          icon: muted ? CupertinoIcons.bell_slash : CupertinoIcons.bell,
          title: 'Bildirimler',
          subtitle: muted ? 'Bu sohbet sessizde' : null,
          trailing: CupertinoSwitch(value: !muted, activeTrackColor: c.ink, onChanged: (_) => _c.toggleMute(id)),
        ),
        _row(
          c,
          icon: CupertinoIcons.person_crop_circle,
          title: 'Profil fotoğrafım',
          subtitle: 'Fotoğraf ekle veya değiştir',
          trailing: TalkAvatar.solid(name: _c.me?.displayName ?? '', photoUrl: _c.api.fileUrl(_myAvatar), size: 34, personIfEmpty: true),
          onTap: _pickMyAvatar,
        ),
      ]),
      if (!_isDm)
        _group(c, [
          _row(c, icon: CupertinoIcons.person_2, title: 'Benzer bir grup oluşturun', subtitle: 'Ekleyebileceğiniz veya çıkarabileceğiniz aynı üyelerle başlayın.', onTap: _similarGroup),
          if (_canManage) _row(c, icon: CupertinoIcons.pencil, title: 'Grubu düzenle', subtitle: 'Grup adı, açıklama ve fotoğraf', onTap: _editGroup),
        ]),
      _group(c, [
        _row(c, title: fav ? "Favoriler'den çıkar" : "Favoriler'e ekle", color: c.ink, chevron: false, onTap: () => _c.toggleFavourite(id)),
        _row(c, title: 'Listeye ekle', subtitle: inLists.isEmpty ? null : inLists.join(', '), color: c.ink, chevron: false, onTap: () => showTalkListSheet(context, _c, id)),
        _row(c, title: _c.archived.contains(id) ? 'Arşivden çıkar' : 'Sohbeti arşivle', color: c.ink, chevron: false, onTap: () => _c.toggleArchive(id)),
        // kısıtlı sohbette dışa aktarma yok
        if (!s.restricted) _row(c, title: 'Sohbeti dışa aktar', color: c.ink, chevron: false, onTap: _export),
        _row(c, title: 'Sohbeti temizle', color: TalkColors.dangerSolid, chevron: false, onTap: _clearChat),
      ], indent: 20),
      _group(c, [
        if (s.channel['type'] == 'group') _row(c, title: 'Gruptan çık', color: TalkColors.dangerSolid, chevron: false, onTap: _leave),
        _row(c, title: 'Sohbeti sil', color: TalkColors.dangerSolid, chevron: false, onTap: _deleteChat),
        _row(c, title: _isDm ? 'Kişiyi şikayet et' : 'Grubu şikayet et', color: TalkColors.dangerSolid, chevron: false, onTap: _report),
      ], indent: 20),
      _footer(c, s),
    ];
  }

  /// "Oluşturan: Anıl / Oluşturulma zamanı: 30 Eyl 2025"
  Widget _footer(TalkColors c, TalkSidebar s) {
    if (_isDm) return const SizedBox.shrink();
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    final by = '${s.channel['created_by_name'] ?? ''}';
    final d = talkParseTime('${s.channel['created_at'] ?? ''}');
    if (by.isEmpty && d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (by.isNotEmpty) Text('Oluşturan: $by', style: talkText(14, FontWeight.w400, c.muted)),
        if (d != null) Text('Oluşturulma zamanı: ${d.day} ${months[d.month - 1]} ${d.year}', style: talkText(14, FontWeight.w400, c.muted)),
      ]),
    );
  }

  Future<void> _activitySheet(TalkSidebar s) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final c = TalkColors.of(ctx);
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
            decoration: BoxDecoration(color: _bg(c), borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
            child: SafeArea(
              top: false,
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 18, 16, 16), children: [
                Text('Üye değişiklikleri ve etkinlik', style: talkText(17, FontWeight.w600, c.ink)),
                const SizedBox(height: 14),
                _activity(c, s),
              ]),
            ),
          );
        },
      );

  // ---------- Kararlar / Görevler ----------

  Future<void> _board(Future<({List<TalkDecision> decisions, List<TalkTask> tasks})> Function() call) async {
    try {
      final r = await call();
      final s = _s;
      if (!mounted || s == null) return;
      setState(() {
        s.decisions = r.decisions;
        s.tasks = r.tasks;
      });
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'İşlem başarısız' : e.message, error: true);
    }
  }

  static String _shortDate(String at) {
    final d = talkParseTime(at);
    return d == null ? '' : talkDayLabel(d);
  }

  Widget _boardCard(TalkColors c, String svg, String title, Widget body) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: _cardBg(c), borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFF111111), borderRadius: BorderRadius.circular(10)),
              child: TalkIcon(svg, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(title, style: talkText(17, FontWeight.w600, c.ink)),
          ]),
          const SizedBox(height: 10),
          body,
        ]),
      );

  Widget _decisions(TalkColors c, TalkSidebar s) {
    if (s.decisions.isEmpty) {
      return Text('Henüz karar yok. Bir mesaja basılı tutup "Karar olarak işaretle" diyebilirsin.', style: talkText(14, FontWeight.w400, c.muted));
    }
    return Column(children: [
      for (final d in s.decisions)
        InkWell(
          // dokununca sohbette o mesaja gider
          onTap: () => Navigator.of(context).pop('jump:${d.messageId}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: talkText(14.5, FontWeight.w600, c.ink)),
                  Text('${d.markedBy} · ${_shortDate(d.createdAt)}', style: talkText(12.5, FontWeight.w400, c.muted)),
                ]),
              ),
              if (d.userId == _meId || s.canManage)
                IconButton(
                  tooltip: 'Kararı kaldır',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: c.muted),
                  onPressed: () => _board(() => _c.api.toggleDecision(d.messageId)),
                ),
            ]),
          ),
        ),
    ]);
  }

  Widget _tasks(TalkColors c, TalkSidebar s) {
    final total = s.tasks.length;
    final open = s.tasks.where((t) => !t.done).length;
    Future<void> add() async {
      final title = _taskInput.text.trim();
      if (title.isEmpty) return;
      _taskInput.clear();
      await _board(() => _c.api.addTask(widget.channel.id, title));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(total == 0 ? 'Görev yok' : (open == 0 ? 'Tüm görevler tamamlandı' : '$open açık görev'), style: talkText(15, FontWeight.w500, c.ink)),
      if (total > 0) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (total - open) / total,
            minHeight: 8,
            color: c.dark ? Colors.white : const Color(0xFF111111),
            backgroundColor: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE8E8E8),
          ),
        ),
        const SizedBox(height: 6),
        for (final t in s.tasks)
          InkWell(
            onTap: () => _board(() => _c.api.toggleTask(t.id)),
            onLongPress: (t.createdBy == _meId || s.canManage) ? () => _confirmDeleteTask(t) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Checkbox(
                  value: t.done,
                  activeColor: TalkColors.wa,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => _board(() => _c.api.toggleTask(t.id)),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: talkText(14.5, FontWeight.w400, t.done ? c.muted : c.ink).copyWith(decoration: t.done ? TextDecoration.lineThrough : null),
                    ),
                    // etiketlenen kişiler (ARCON TO-DO'da her birine kart açıldı)
                    if (t.assignees.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Icon(CupertinoIcons.person_2, size: 14, color: c.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              t.assignees.map((a) => a.id == _meId ? 'Siz' : a.name).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: talkText(12.5, FontWeight.w500, c.muted),
                            ),
                          ),
                        ]),
                      ),
                  ]),
                ),
                if (t.messageId > 0)
                  IconButton(
                    tooltip: 'Mesaja git',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.chat_bubble_outline, size: 16, color: c.muted),
                    onPressed: () => Navigator.of(context).pop('jump:${t.messageId}'),
                  ),
              ]),
            ),
          ),
      ],
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _taskInput,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => add(),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: talkText(15, FontWeight.w400, c.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Görev ekle',
              hintStyle: talkText(15, FontWeight.w400, c.muted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.line)),
            ),
          ),
        ),
        IconButton(tooltip: 'Ekle', onPressed: add, icon: const Icon(Icons.add_circle, color: TalkColors.wa)),
      ]),
    ]);
  }

  Future<void> _confirmDeleteTask(TalkTask t) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text('"${t.title}" görevi silinsin mi?'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) await _board(() => _c.api.deleteTask(t.id));
  }

  Widget _activity(TalkColors c, TalkSidebar s) {
    if (s.activity.isEmpty) return Text('Henüz değişiklik yok', style: talkText(14, FontWeight.w400, c.muted));
    String icon(String label) {
      final t = label.toLowerCase();
      if (RegExp(r'dosya|yükle|upload|file').hasMatch(t)) return _fileSvg;
      if (RegExp(r'karar|onay|decision').hasMatch(t)) return TalkSvg.decisions;
      if (RegExp(r'mail|e-?posta|email').hasMatch(t)) return _mailSvg;
      return TalkSvg.user;
    }

    return Column(children: [
      for (final a in s.activity)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
              child: TalkIcon(icon('${a['label'] ?? ''}'), size: 13, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${a['label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ('${a['preview'] ?? ''}'.trim().isNotEmpty)
                    TextSpan(
                        text: ' · ${'${a['preview']}'.replaceAll(RegExp(r'\[\[chip:[^\]]+\]\]'), '').replaceAll(RegExp(r'\[\[gif:[^\]]+\]\]'), '[GIF]').trim()}'),
                ]),
                style: talkText(14, FontWeight.w400, c.ink),
              ),
            ),
            Text(_clock('${a['created_at'] ?? ''}'), style: talkText(12, FontWeight.w400, c.muted)),
          ]),
        ),
    ]);
  }

  String _clock(String iso) {
    final d = talkParseTime(iso);
    return d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
