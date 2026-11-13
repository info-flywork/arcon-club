import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../push/local_notifier.dart';
import 'talk_call_screen.dart';
import 'talk_camera_screen.dart';
import 'talk_contact_sheet.dart';
import 'talk_controller.dart';
import 'talk_events.dart';
import 'talk_gif_panel.dart';
import 'talk_location_picker.dart';
import 'talk_share_kinds.dart';
import 'talk_task_sheet.dart';
import 'talk_ai_screen.dart';
import 'talk_icons.dart';
import 'talk_info_screen.dart';
import 'talk_media_composer.dart';
import 'talk_message.dart';
import 'talk_models.dart';
import 'talk_plan_screen.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';
import '../ui/skeleton.dart';

/// Yüklenmekte olan dosya (web: pending entry — ilerleme halkası, İptal, Tekrar).
class _Pending {
  _Pending(this.paths, this.name, this.isImage, this.caption, this.replyTo);
  _Pending.one(String path, String name, bool isImage, String caption, int replyTo)
      : this([path], name, isImage, caption, replyTo);
  final List<String> paths;
  String get path => paths.first;
  final String name;
  final bool isImage;
  final String caption;
  final int replyTo;
  double progress = 0.02;
  bool failed = false;
  Completer<void> cancel = Completer<void>();
}

/// ARCONNECT sohbet ekranı — web `talk-main` (başlık, mesajlar, yazma alanı) telefon görünümü.
class TalkChatScreen extends StatefulWidget {
  const TalkChatScreen({super.key, required this.controller, required this.channel, required this.config, required this.session, this.initialMedia});

  final TalkController controller;
  final TalkChannel channel;
  final ArconAppConfig config;
  final SessionController session;

  /// Ana ekrandaki kameradan gelen fotoğraf: sohbet açılınca gönderme ekranı açılır
  final List<TalkMediaItem>? initialMedia;

  @override
  State<TalkChatScreen> createState() => _TalkChatScreenState();
}

class _TalkChatScreenState extends State<TalkChatScreen> {
  TalkController get _c => widget.controller;
  TalkChannel get _ch => widget.channel;

  final List<TalkMessage> _messages = [];
  final List<_Pending> _pending = [];
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  bool _loading = true;
  int _lastId = 0;
  List<TalkTyping> _typing = const [];
  TalkSidebar? _side;
  TalkMessage? _reply;
  int? _editing;
  int? _highlight;
  String? _pop; // 'emoji' | 'gif' | 'mention'
  String _mentionQ = '';
  Timer? _poll;
  Timer? _typingStop;
  int _typingPingAt = 0;
  int _localSeq = 0;
  bool _farFromBottom = false; // "aşağı in" butonu
  int _unseen = 0; // yukarıdayken gelen mesaj sayısı
  String _readUpto = ''; // diğer üyelerin hepsinin okuduğu an → mavi tik
  String _deliveredUpto = ''; // hepsinin uygulamayı açtığı an → çift gri tik
  /// İnternet yokken yazılanlar: saat simgesiyle bekler, bağlantı gelince sırayla gider (WhatsApp).
  final List<({int localId, String body, int replyTo})> _outbox = [];
  bool _flushing = false;

  /// Basılı tutunca açılan çoklu seçim (WhatsApp): seçili mesaj id'leri
  final Set<int> _selected = {};
  bool _searching = false;
  final _searchCtl = TextEditingController();
  List<int> _hits = const [];
  int _hitIdx = 0;
  final _rec = AudioRecorder();
  bool _recording = false;
  bool _recPaused = false;
  Duration _recHold = Duration.zero;
  DateTime _recMark = DateTime.now();
  Timer? _recTick;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _recAmps = [];

  int get _meId => _c.me?.id ?? 0;

  @override
  void initState() {
    super.initState();
    LocalNotifier.openChannelId = _ch.id; // açık sohbetin mesajları için bildirim gösterme
    _c.addListener(_onLive);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
    final draft = _c.draftOf(_ch.id);
    if (draft.isNotEmpty) {
      _input.value = TextEditingValue(text: draft, selection: TextSelection.collapsed(offset: draft.length));
    }
    _input.addListener(_onInput);
    _focus.addListener(_onFocus);
    _scroll.addListener(_onScroll);
    final media = widget.initialMedia;
    if (media != null && media.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sendPicked(media);
      });
    }
  }

  /// Liste ters (reverse): 0 = en alt. Yukarı çıkınca "aşağı in" butonu görünür.
  void _onScroll() {
    final far = _scroll.hasClients && _scroll.offset > 320;
    if (far != _farFromBottom || (!far && _unseen > 0)) {
      setState(() {
        _farFromBottom = far;
        if (!far) _unseen = 0;
      });
    }
  }

  @override
  void dispose() {
    if (LocalNotifier.openChannelId == _ch.id) LocalNotifier.openChannelId = null;
    _c.removeListener(_onLive);
    _poll?.cancel();
    _typingStop?.cancel();
    if (_typingPingAt > 0) _c.api.typing(_ch.id, false).catchError((_) {});
    _c.setDraft(_ch.id, _input.text);
    _recTick?.cancel();
    _ampSub?.cancel();
    _rec.dispose();
    _input.dispose();
    _searchCtl.dispose();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _c.api.messages(_ch.id);
      _messages
        ..clear()
        ..addAll(r.messages);
      _lastId = _messages.isEmpty ? 0 : _messages.map((m) => m.id).reduce((a, b) => a > b ? a : b);
      _typing = r.typing;
      _readUpto = r.readUpto;
      _deliveredUpto = r.deliveredUpto;
      _c.markRead(_ch.id);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) talkToast(context, e.message.isEmpty ? 'Mesaj açılamadı' : e.message, error: true);
    }
    if (mounted) setState(() => _loading = false);
    _refreshSidebar();
  }

  Future<void> _refreshSidebar() async {
    try {
      final s = await _c.api.sidebar(_ch.id);
      if (mounted) setState(() => _side = s);
    } on ArconApiException {
      // sessiz
    }
  }

  /// web `poll`: 2 sn'de bir yeni mesajlar + yazıyor bilgisi; süresi dolan mesajları kaldır.
  Future<void> _pollOnce() async {
    if (_loading) return;
    final now = DateTime.now();
    _messages.removeWhere((m) => m.expiresAt.isNotEmpty && (talkParseTime(m.expiresAt)?.isBefore(now) ?? false));
    try {
      final r = await _c.api.messages(_ch.id, afterId: _lastId);
      if (!mounted) return;
      if (r.messages.isNotEmpty) {
        _append(r.messages);
        _refreshSidebar();
        // sohbet açıkken gelenler okunmuş sayılır (karşı taraf mavi tik görsün)
        if (r.messages.any((m) => m.userId != _meId) && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          _c.api.read(_ch.id).catchError((_) {});
        }
      }
      if (r.readUpto != _readUpto || r.deliveredUpto != _deliveredUpto) {
        setState(() {
          _readUpto = r.readUpto;
          _deliveredUpto = r.deliveredUpto;
        });
      }
      unawaited(_flushOutbox());
      if (!_c.live) setState(() => _typing = r.typing);
    } on ArconApiException {
      // web: poll hataları yok sayılır
    }
  }

  void _append(List<TalkMessage> list) {
    for (final m in list) {
      if (_messages.any((x) => x.id == m.id)) continue;
      if (m.userId == _meId) {
        final ghost = _messages.indexWhere((x) => x.id < 0 && x.body == m.body);
        if (ghost >= 0) _messages.removeAt(ghost);
      }
      _messages.add(m);
      if (m.id > _lastId) _lastId = m.id;
      if (_farFromBottom && m.userId != _meId) _unseen++;
    }
    if (list.isNotEmpty) _c.updateLast(_ch.id, list.last.body, list.last.createdAt, userId: list.last.userId);
    setState(() {});
  }

  void _onLive() {
    if (!mounted || !_c.live) return;
    setState(() => _typing = _c.typingOf(_ch.id));
  }

  void _onFocus() {
    if (!_focus.hasFocus) return;
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  void _openComposerKeyboard() {
    if (_pop != null && _pop != 'mention') setState(() => _pop = null);
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  // ---------- yazıyor ----------
  void _onInput() {
    final t = _input.text;
    // @bahsetme: imleçten önceki son "@kelime"
    final sel = _input.selection.baseOffset < 0 ? t.length : _input.selection.baseOffset;
    final before = t.substring(0, sel.clamp(0, t.length));
    final m = RegExp(r'@([A-Za-zÇĞİÖŞÜçğıöşü0-9_]*)$').firstMatch(before);
    if (m != null) {
      setState(() {
        _pop = 'mention';
        _mentionQ = m.group(1) ?? '';
      });
    } else if (_pop == 'mention') {
      setState(() => _pop = null);
    }
    if (t.trim().isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(milliseconds: 2800), () {
      _typingPingAt = 0;
      _c.api.typing(_ch.id, false).catchError((_) {});
    });
    if (now - _typingPingAt < 1800) return;
    _typingPingAt = now;
    _c.api.typing(_ch.id, true).catchError((_) {});
  }

  String get _sub {
    final names = _typing.where((t) => t.userId != _meId).map((t) => talkFirstName(t.displayName)).toList();
    if (names.length == 1) return '${names[0]} yazıyor…';
    if (names.length == 2) return '${names[0]} ve ${names[1]} yazıyor…';
    if (names.length > 2) return 'Birkaç kişi yazıyor…';
    if (_ch.isSelf) return 'Kendinize mesaj gönderin';
    if (_peerOnline) return 'çevrimiçi';
    var base = _ch.isDm
        ? 'kişi bilgisi için dokun'
        : '${_ch.memberCount > 0 ? _ch.memberCount : '—'} üye${_ch.type == 'department' && !_ch.isPrivate ? ' · Resmî grup' : ''}';
    final s = _side;
    if (s != null && s.disappearSec > 0) base = '$base · Süreli: ${s.disappearLabel}';
    return base;
  }

  bool get _isTyping => _typing.any((t) => t.userId != _meId);

  bool get _peerOnline => _ch.isDm && _ch.peer != null && _c.online.contains(_ch.peer!.id);

  // ---------- gönderme ----------
  String _stampNow() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}:${two(n.second)}';
  }

  Future<void> _send([String? override]) async {
    final body = (override ?? _input.text).trim();
    if (body.isEmpty) return;
    final replyTo = _reply?.id ?? 0;
    final reply = _reply;
    final me = _c.me;
    final localId = --_localSeq;
    final local = TalkMessage.fromJson({
      'id': localId,
      'channel_id': _ch.id,
      'user_id': _meId,
      'username': me?.username ?? '',
      'display_name': me?.displayName ?? '',
      'avatar_path': me?.avatarPath ?? '',
      'body': body,
      'created_at': _stampNow(),
      if (reply != null)
        'reply': {
          'id': reply.id,
          'user_id': reply.userId,
          'display_name': reply.displayName,
          'body': reply.body,
        },
    });
    if (override == null) _input.clear();
    setState(() {
      _reply = null;
      _pop = null;
      _messages.add(local);
    });
    _scrollToBottom();
    _c.updateLast(_ch.id, body, local.createdAt, userId: _meId);
    _typingStop?.cancel();
    _typingPingAt = 0;
    _outbox.add((localId: localId, body: body, replyTo: replyTo));
    await _flushOutbox();
  }

  /// Bekleyenleri sırayla gönderir; bağlantı yoksa saat simgesiyle kalır, sonraki denemede gider.
  Future<void> _flushOutbox() async {
    if (_flushing || _outbox.isEmpty) return;
    _flushing = true;
    try {
      while (_outbox.isNotEmpty && mounted) {
        final o = _outbox.first;
        // yanıt kaybolup gerçek mesaj yoklamayla geldiyse yer tutucu zaten kalktı: tekrar gönderme
        if (!_messages.any((m) => m.id == o.localId)) {
          _outbox.removeAt(0);
          continue;
        }
        try {
          final j = await _c.api.sendMessage(channelId: _ch.id, body: o.body, replyTo: o.replyTo);
          _outbox.remove(o);
          if (!mounted) return;
          setState(() => _messages.removeWhere((m) => m.id == o.localId));
          if (j['message'] is Map) _append([TalkMessage.fromJson((j['message'] as Map).cast<String, dynamic>())]);
          _scrollToBottom();
        } on ArconApiException catch (e) {
          if (e.code == 'network') return; // internet yok: saat simgesiyle bekle
          _outbox.remove(o);
          if (!mounted) return;
          setState(() => _messages.removeWhere((m) => m.id == o.localId));
          talkToast(context, e.message.isEmpty ? 'Gönderilemedi' : e.message, error: true);
          if (_input.text.isEmpty) _input.text = o.body;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  TalkTick _tickFor(TalkMessage m) {
    if (m.id < 0) return TalkTick.pending;
    if (_readUpto.isNotEmpty && m.createdAt.compareTo(_readUpto) <= 0) return TalkTick.read;
    if (_deliveredUpto.isNotEmpty && m.createdAt.compareTo(_deliveredUpto) <= 0) return TalkTick.delivered;
    return TalkTick.sent;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  /// Web'deki `<input type="file" multiple>` telefonda bu üç seçeneği gösterir.
  Future<List<TalkMediaItem>> _pickFiles([String? preset]) async {
    var choice = preset ?? await showCupertinoModalPopup<String>(
      context: context,
      // iPhone'da Safari'nin dosya menüsü sistem mavisiyle görünür
      builder: (ctx) => CupertinoTheme(
        data: const CupertinoThemeData(primaryColor: CupertinoColors.systemBlue),
        child: CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'library'), child: const Text('Fotoğraf Arşivi')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'camera'), child: const Text('Fotoğraf veya Video Çek')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'files'), child: const Text('Dosya Seç')),
        ],
        cancelButton: CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
      ),
    );
    if (choice == null) return const [];
    if (choice == 'camera') {
      final r = await openTalkCamera(context);
      if (r == null || !mounted) return const [];
      if (!r.openGallery) return r.items;
      choice = 'library';
    }
    final out = <TalkMediaItem>[];
    if (choice == 'files') {
      for (final f in await FilePicker.pickFiles()) {
        final p = f.path;
        if (p != null) out.add(TalkMediaItem(path: p, name: f.name, size: await f.length() ?? 0));
      }
    } else {
      for (final x in await ImagePicker().pickMultipleMedia(maxWidth: 1600, imageQuality: 78)) {
        out.add(TalkMediaItem(path: x.path, name: x.name, size: await x.length()));
      }
    }
    return out;
  }

  /// WhatsApp iOS ek menüsü: Fotoğraflar, Kamera, Konum, Kişi, Belge, Anket, Etkinlik; altta galeri (çoklu seçim + açıklama).
  Future<void> _attach() async {
    setState(() => _pop = null);
    _focus.unfocus();
    final c = TalkColors.of(context);
    final caption = TextEditingController();
    var picked = <File>[];
    Object? choice;
    try {
      choice = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        backgroundColor: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: true,
        builder: (ctx) {
          Widget item(String key, IconData icon, Color color, String label) => Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(ctx, key),
                  child: Column(children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : Colors.white, shape: BoxShape.circle),
                      child: Icon(icon, size: 23, color: color),
                    ),
                    const SizedBox(height: 6),
                    Text(label, style: talkText(12.5, FontWeight.w500, c.ink)),
                  ]),
                ),
              );
          return StatefulBuilder(
            builder: (ctx, setSheet) {
              final inset = MediaQuery.viewInsetsOf(ctx).bottom;
              return Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * 0.72,
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          item('library', CupertinoIcons.photo_fill_on_rectangle_fill, const Color(0xFF2F80ED), 'Fotoğraflar'),
                          item('camera', CupertinoIcons.camera_fill, c.ink, 'Kamera'),
                          item('location', CupertinoIcons.location_solid, c.ink, 'Konum'),
                          item('contact', CupertinoIcons.person_crop_circle_fill, c.muted, 'Kişi'),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          item('files', CupertinoIcons.doc_fill, const Color(0xFF2F80ED), 'Belge'),
                          item('poll', CupertinoIcons.chart_bar_alt_fill, const Color(0xFFF5A623), 'Anket'),
                          item('event', CupertinoIcons.calendar, const Color(0xFFE11D48), 'Etkinlik'),
                          const Expanded(child: SizedBox()),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TalkGalleryGrid(
                          onChanged: (files) => setSheet(() => picked = files),
                        ),
                      ),
                      if (picked.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                          child: Row(children: [
                            Expanded(
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: c.dark ? const Color(0xFF2C2C2E) : Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: TextField(
                                  controller: caption,
                                  style: talkText(16, FontWeight.w400, c.ink),
                                  cursorColor: c.ink,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => Navigator.pop(ctx, 'gallery-send'),
                                  decoration: InputDecoration(
                                    isCollapsed: true,
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    hintText: 'Açıklama ekle',
                                    hintStyle: talkText(16, FontWeight.w400, c.muted),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => Navigator.pop(ctx, 'gallery-send'),
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: TalkColors.wa, shape: BoxShape.circle),
                                child: Stack(alignment: Alignment.center, children: [
                                  const Icon(Icons.send_rounded, size: 20, color: Colors.white),
                                  if (picked.length > 1)
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                        child: Text('${picked.length}', style: talkText(9, FontWeight.w800, TalkColors.wa, height: 1)),
                                      ),
                                    ),
                                ]),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      // sheet kapandıktan sonra controller'ı bir frame sonra bırak
    }
    if (choice == null || !mounted) {
      caption.dispose();
      return;
    }
    if (choice == 'gallery-send') {
      final items = [
        for (final f in picked) TalkMediaItem(path: f.path, name: f.uri.pathSegments.isEmpty ? 'foto.jpg' : f.uri.pathSegments.last, size: await f.length()),
      ];
      final text = caption.text.trim();
      caption.dispose();
      await _sendPicked(items, caption: text, compose: false);
      return;
    }
    caption.dispose();
    if (choice is! String) return;
    switch (choice) {
      case 'contact':
        return _shareContact();
      case 'location':
        final body = await showTalkLocationPicker(context);
        if (body != null && mounted) await _send(body);
        return;
      case 'poll':
        final body = await showTalkPollSheet(context);
        if (body != null && mounted) await _send(body);
        return;
      case 'event':
        final e = await showTalkEventSheet(context, call: false);
        if (e != null && mounted) await _send(talkEventBody(e.title, e.at));
        return;
    }
    final files = await _pickFiles(choice);
    if (files.isEmpty || !mounted) return;
    await _sendPicked(files);
  }

  /// Anket oyu: kullanıcı başına tek tepki (aynı seçenek = oyu geri al, başka seçenek = oyu değiştir)
  Future<void> _vote(TalkMessage m, String emoji) async {
    final had = m.reactions.any((r) => r.emoji == emoji && r.mine);
    final list = [
      for (final r in m.reactions)
        if (r.mine) TalkReaction(emoji: r.emoji, count: r.count - 1, mine: false) else r,
    ];
    if (!had) {
      final i = list.indexWhere((r) => r.emoji == emoji);
      if (i >= 0) {
        list[i] = TalkReaction(emoji: emoji, count: list[i].count + 1, mine: true);
      } else {
        list.add(TalkReaction(emoji: emoji, count: 1, mine: true));
      }
    }
    final before = m.reactions;
    setState(() => m.reactions = list.where((r) => r.count > 0).toList());
    try {
      await _c.api.react(m.id, emoji);
    } on ArconApiException catch (e) {
      if (!mounted) return;
      setState(() => m.reactions = before);
      talkToast(context, e.message.isEmpty ? 'Oy verilemedi' : e.message, error: true);
    }
  }

  /// Kişi kartı: seçilen kişinin adı ve kullanıcı adı mesaj olarak gider
  Future<void> _shareContact() async {
    final me = _meId;
    final people = _c.users.where((u) => u.id != me).toList()..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final c = TalkColors.of(context);
    final u = await showModalBottomSheet<TalkUser>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.rail,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text('Kişi paylaş', textAlign: TextAlign.center, style: talkText(17, FontWeight.w600, c.ink)),
          ),
          for (final p in people)
            ListTile(
              leading: TalkAvatar.solid(name: p.displayName, photoUrl: _c.api.fileUrl(p.avatarPath), size: 40, personIfEmpty: true),
              title: Text(p.displayName, style: talkText(16, FontWeight.w500, c.ink)),
              subtitle: Text('@${p.username}', style: talkText(13.5, FontWeight.w400, c.muted)),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    );
    if (u == null || !mounted) return;
    final dept = u.department.trim().isEmpty ? '' : ' · ${u.department.trim()}';
    await _send('👤 ${u.displayName} (@${u.username})$dept');
  }

  Future<void> _sendPicked(List<TalkMediaItem> picked, {String caption = '', bool compose = true}) async {
    if (picked.isEmpty || !mounted) return;
    final items = <TalkMediaItem>[];
    for (final it in picked) {
      if (it.size > 64 * 1024 * 1024) {
        talkToast(context, 'Dosya 64 MB’dan büyük olamaz: ${it.name}', error: true);
        continue;
      }
      items.add(it);
    }
    if (items.length > 12) {
      talkToast(context, 'En fazla 12 dosya gönderebilirsin', error: true);
      items.removeRange(12, items.length);
    }
    if (items.isEmpty || !mounted) return;
    var text = caption;
    var sendItems = items;
    if (compose) {
      final res = await openTalkMediaComposer(context, items, onAddMore: _pickFiles);
      if (res == null || res.items.isEmpty) return;
      sendItems = res.items;
      text = res.caption;
    }
    final replyTo = _reply?.id ?? 0;
    setState(() => _reply = null);
    final images = sendItems.every((it) => it.isImage);
    final p = _Pending(
      [for (final it in sendItems) it.path],
      sendItems.first.name,
      images,
      text,
      replyTo,
    );
    setState(() => _pending.add(p));
    _upload(p);
    _scrollToBottom();
  }

  Future<void> _upload(_Pending p) async {
    setState(() {
      p
        ..failed = false
        ..progress = 0.02
        ..cancel = Completer<void>();
    });
    try {
      final j = await _c.api.sendMessage(
        channelId: _ch.id,
        body: p.caption,
        replyTo: p.replyTo,
        filePaths: p.paths,
        onProgress: (v) {
          if (mounted) setState(() => p.progress = (v * 0.95).clamp(0.02, 0.95));
        },
        cancel: p.cancel.future,
      );
      if (!mounted) return;
      setState(() => _pending.remove(p));
      if (j['message'] is Map) _append([TalkMessage.fromJson((j['message'] as Map).cast<String, dynamic>())]);
    } on ArconApiException catch (e) {
      if (!mounted) return;
      if (p.cancel.isCompleted) {
        setState(() => _pending.remove(p));
      } else {
        setState(() => p.failed = true);
        talkToast(context, e.message.isEmpty ? 'Gönderilemedi' : e.message, error: true);
      }
    }
  }

  // ---------- mesaj menüsü ----------
  Future<void> _menu(TalkMessage m, Offset at, {Rect? rect, Widget? preview}) async {
    final mine = m.userId == _meId;
    _focus.unfocus();
    final act = await showTalkMessageMenu(
      context,
      mine: mine,
      at: at,
      canCopy: m.text.trim().isNotEmpty,
      canForward: m.id > 0,
      canEdit: mine && talkCanEditMessage(m.createdAt, text: m.text),
      canTask: m.id > 0,
      canAskAi: m.text.trim().isNotEmpty,
      decided: _ch.isGroup && m.id > 0 ? (_side?.decisions.any((d) => d.messageId == m.id) ?? false) : null,
      rect: rect,
      preview: preview,
    );
    if (act == null || !mounted) return;
    if (act.startsWith('react:')) return _react(m, act.substring(6));
    switch (act) {
      case 'react-more':
        final e = await showTalkEmojiPicker(context);
        if (e != null) _react(m, e);
      case 'reply':
        _startReply(m);
      case 'info':
        _showInfo(m);
      case 'forward':
        _forward([m]);
      case 'decision':
        await _board(() => _c.api.toggleDecision(m.id), done: (r) => r.decisions.any((d) => d.messageId == m.id) ? 'Karar olarak işaretlendi' : 'Karar kaldırıldı');
      case 'task':
        await _addTask(m);
      case 'ask-ai':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TalkAiScreen(api: widget.session.api, name: _c.me?.displayName ?? '', initialPrompt: m.text.trim()),
        ));
      case 'select':
        _toggleSelect(m);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
        if (mounted) talkToast(context, 'Mesaj kopyalandı');
      case 'edit':
        _focus.unfocus();
        setState(() => _editing = m.id);
      case 'delete':
        await _delete([m]);
    }
  }

  /// "Görev olarak ekle": başlık, etiketlenecek kişiler (her birine ARCON TO-DO kartı), teslim tarihi
  Future<void> _addTask(TalkMessage m) async {
    var people = _side?.people ?? const <TalkUser>[];
    if (people.isEmpty) {
      final me = _c.me;
      people = [?me, if (_ch.peer != null && _ch.peer!.id != me?.id) _ch.peer!];
    }
    final r = await showTalkTaskSheet(context, initialTitle: m.text, people: people, fileUrl: _c.api.fileUrl, meId: _meId);
    if (r == null || !mounted) return;
    await _board(
      () => _c.api.addTask(_ch.id, r.title, messageId: m.id, assigneeIds: r.assignees, dueDate: r.dueDate),
      done: (_) => r.assignees.isEmpty ? 'Görevlere eklendi' : "Görev eklendi · ${r.assignees.length} kişiye ARCON TO-DO'da atandı",
    );
  }

  /// Kararlar / Görevler işlemi: paneli günceller, kısa bilgi gösterir.
  Future<void> _board(
    Future<({List<TalkDecision> decisions, List<TalkTask> tasks})> Function() call, {
    required String Function(({List<TalkDecision> decisions, List<TalkTask> tasks}) r) done,
  }) async {
    try {
      final r = await call();
      if (!mounted) return;
      final s = _side;
      if (s != null) {
        setState(() {
          s.decisions = r.decisions;
          s.tasks = r.tasks;
        });
      }
      talkToast(context, done(r));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'İşlem başarısız' : e.message, error: true);
    }
  }

  Future<void> _delete(List<TalkMessage> list) async {
    // web: window.confirm(...) — telefonda sistemin kendi onay kutusu
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(list.length == 1 ? 'Bu mesajı silmek istiyor musun?' : '${list.length} mesajı silmek istiyor musun?'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Tamam')),
        ],
      ),
    );
    if (ok != true) return;
    for (final m in list) {
      try {
        await _c.api.deleteMessage(m.id);
        if (mounted) setState(() => _messages.removeWhere((x) => x.id == m.id));
      } on ArconApiException catch (e) {
        if (mounted) talkToast(context, e.message.isEmpty ? 'Silinemedi' : e.message, error: true);
        return;
      }
    }
  }

  // ---------- çoklu seçim ----------
  List<TalkMessage> get _selectedMessages => [
    for (final m in _messages)
      if (_selected.contains(m.id)) m,
  ];

  void _toggleSelect(TalkMessage m) {
    if (m.id <= 0) return;
    _focus.unfocus();
    setState(() => _selected.contains(m.id) ? _selected.remove(m.id) : _selected.add(m.id));
  }

  Future<void> _copySelected() async {
    final list = _selectedMessages;
    final text = list.length == 1
        ? list.first.text
        : list.map((m) => '[${talkClock(m.createdAt)}] ${m.displayName.isEmpty ? m.username : m.displayName}: ${m.text}').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(_selected.clear);
    talkToast(context, list.length == 1 ? 'Mesaj kopyalandı' : '${list.length} mesaj kopyalandı');
  }

  Widget _selectHead(TalkColors c) {
    final list = _selectedMessages;
    final allMine = list.isNotEmpty && list.every((m) => m.userId == _meId);
    final one = list.length == 1 ? list.first : null;
    Widget act(IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, color: c.ink),
    );
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      decoration: BoxDecoration(
        color: c.chatHead,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Seçimi kapat',
            onPressed: () => setState(_selected.clear),
            icon: Icon(Icons.close, color: c.ink),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text('${list.length}', style: talkText(18, FontWeight.w700, c.ink))),
          if (one != null)
            act(Icons.reply, 'Yanıtla', () {
              setState(_selected.clear);
              _startReply(one);
            }),
          if (list.any((m) => m.text.trim().isNotEmpty)) act(Icons.copy_outlined, 'Kopyala', _copySelected),
          act(Icons.shortcut, 'İlet', () {
            final l = _selectedMessages;
            setState(_selected.clear);
            _forward(l);
          }),
          if (allMine)
            act(Icons.delete_outline, 'Sil', () {
              final l = _selectedMessages;
              setState(_selected.clear);
              _delete(l);
            }),
          if (one != null && allMine)
            act(Icons.info_outline, 'Bilgi', () {
              setState(_selected.clear);
              _showInfo(one);
            }),
        ],
      ),
    );
  }

  /// WhatsApp "Bilgi": kim okudu, kim henüz okumadı
  Future<void> _showInfo(TalkMessage m) async {
    final c = TalkColors.of(context);
    final future = _c.api.messageInfo(m.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.dark ? const Color(0xFF1F2C34) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: FutureBuilder(
          future: future,
          builder: (ctx, snap) {
            Widget head(String t) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Text(t, style: talkText(13.5, FontWeight.w700, TalkColors.ticks)),
                );
            Widget person(TalkUser u, String sub) => ListTile(
                  leading: TalkAvatar.solid(name: u.displayName, photoUrl: _c.api.fileUrl(u.avatarPath), size: 36, fontSize: 12),
                  title: Text(u.displayName, style: talkText(15, FontWeight.w600, c.ink)),
                  subtitle: sub.isEmpty ? null : Text(sub, style: talkText(12.5, FontWeight.w400, c.muted)),
                );
            final body = <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text('Mesaj bilgisi', style: talkText(17, FontWeight.w700, c.ink)),
              ),
            ];
            if (snap.hasError) {
              body.add(Padding(padding: const EdgeInsets.all(20), child: Text('Bilgi alınamadı', style: talkText(14, FontWeight.w400, c.muted))));
            } else if (!snap.hasData) {
              body.add(const SkeletonList(count: 3, padding: EdgeInsets.symmetric(horizontal: 16)));
            } else {
              final d = snap.data!;
              body.add(head('Okudu'));
              if (d.read.isEmpty) body.add(Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text('Henüz kimse okumadı', style: talkText(13.5, FontWeight.w400, c.muted))));
              for (final (u, at) in d.read) {
                final t = talkParseTime(at);
                body.add(person(u, t == null ? '' : '${talkDayLabel(t)} ${talkClock(at)}'));
              }
              if (d.unread.isNotEmpty) {
                body.add(head('Henüz okumadı'));
                for (final u in d.unread) {
                  body.add(person(u, ''));
                }
              }
            }
            return SafeArea(top: false, child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: body));
          },
        ),
      ),
    );
  }

  /// Mesajı başka sohbetlere / kişilere ilet (sohbeti olmayan kişiler ve kendine dahil).
  Future<void> _forward(List<TalkMessage> list) async {
    final c = TalkColors.of(context);
    final picked = <String>{};
    var q = '';
    final me = _c.me;
    final people = [..._c.users]..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final groups = _c.channels.where((ch) => ch.isGroup).toList();
    bool hit(String hay) => q.isEmpty || hay.toLowerCase().contains(q);
    final targets = await showModalBottomSheet<({List<int> channels, List<int> users})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.dark ? const Color(0xFF1F2C34) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final meHit = me != null && hit('${me.displayName} ${me.username} siz kendime');
          final shownPeople = people.where((u) => u.id != me?.id && hit('${u.displayName} ${u.username} ${u.department}')).toList();
          final shownGroups = groups.where((ch) => hit(ch.name)).toList();
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(children: [
                    Expanded(child: Text('İletilecek kişi veya grup', style: talkText(17, FontWeight.w700, c.ink))),
                    TextButton(
                      onPressed: picked.isEmpty ? null : () {
                        Navigator.pop(ctx, (
                          channels: [
                            for (final k in picked)
                              if (k.startsWith('c:')) int.tryParse(k.substring(2)) ?? 0
                          ].where((id) => id > 0).toList(),
                          users: [
                            for (final k in picked)
                              if (k.startsWith('u:')) int.tryParse(k.substring(2)) ?? 0
                          ].where((id) => id > 0).toList(),
                        ));
                      },
                      child: Text(picked.isEmpty ? 'Gönder' : 'Gönder (${picked.length})', style: talkText(14.5, FontWeight.w700, picked.isEmpty ? c.muted : TalkColors.wa)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    onChanged: (v) => setSheet(() => q = v.trim()),
                    style: talkText(16, FontWeight.w400, c.ink),
                    cursorColor: c.ink,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.searchBg,
                      hintText: 'Kişi veya grup ara',
                      hintStyle: talkText(16, FontWeight.w400, c.muted),
                      prefixIcon: Icon(Icons.search, size: 20, color: c.muted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    if (meHit && me != null)
                      CheckboxListTile(
                        value: picked.contains('u:${me.id}'),
                        activeColor: TalkColors.wa,
                        onChanged: (v) => setSheet(() => v == true ? picked.add('u:${me.id}') : picked.remove('u:${me.id}')),
                        secondary: TalkAvatar.solid(name: me.displayName, photoUrl: _c.api.fileUrl(me.avatarPath), size: 36, fontSize: 12, personIfEmpty: true),
                        title: Text('${me.displayName} (Siz)', maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(15, FontWeight.w600, c.ink)),
                        subtitle: Text('Kendinize mesaj gönderin', style: talkText(13, FontWeight.w400, c.muted)),
                      ),
                    if (shownPeople.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                        child: Text('Kişiler', style: talkText(13, FontWeight.w700, c.muted)),
                      ),
                    for (final u in shownPeople)
                      CheckboxListTile(
                        value: picked.contains('u:${u.id}'),
                        activeColor: TalkColors.wa,
                        onChanged: (v) => setSheet(() => v == true ? picked.add('u:${u.id}') : picked.remove('u:${u.id}')),
                        secondary: TalkAvatar.solid(name: u.displayName, photoUrl: _c.api.fileUrl(u.avatarPath), size: 36, fontSize: 12, personIfEmpty: true),
                        title: Text(u.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(15, FontWeight.w600, c.ink)),
                        subtitle: Text(
                          u.department.trim().isNotEmpty ? u.department : '@${u.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: talkText(13, FontWeight.w400, c.muted),
                        ),
                      ),
                    if (shownGroups.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                        child: Text('Gruplar', style: talkText(13, FontWeight.w700, c.muted)),
                      ),
                    for (final ch in shownGroups)
                      CheckboxListTile(
                        value: picked.contains('c:${ch.id}'),
                        activeColor: TalkColors.wa,
                        onChanged: (v) => setSheet(() => v == true ? picked.add('c:${ch.id}') : picked.remove('c:${ch.id}')),
                        secondary: TalkAvatar.solid(name: ch.name, photoUrl: _c.api.fileUrl(ch.photo), size: 36, fontSize: 12),
                        title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(15, FontWeight.w600, c.ink)),
                        subtitle: Text('${ch.memberCount} üye', style: talkText(13, FontWeight.w400, c.muted)),
                      ),
                    if (!meHit && shownPeople.isEmpty && shownGroups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(q.isEmpty ? 'Kişi yok' : 'Sonuç yok', textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
                      ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (targets == null || (targets.channels.isEmpty && targets.users.isEmpty) || !mounted) return;
    try {
      var n = 0;
      for (final m in list) {
        n = await _c.api.forward(m.id, channelIds: targets.channels, userIds: targets.users);
      }
      if (mounted) {
        talkToast(context, list.length > 1 ? '${list.length} mesaj iletildi' : (n == 1 ? 'Mesaj iletildi' : '$n sohbete iletildi'));
      }
      _c.refresh(silent: true);
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'İletilemedi' : e.message, error: true);
    }
  }

  // ---------- sesli mesaj (WhatsApp: çöp · süre+dalga · duraklat · gönder) ----------
  Duration get _recElapsed => _recHold + (_recPaused ? Duration.zero : DateTime.now().difference(_recMark));

  Future<void> _startRec() async {
    if (!await _rec.hasPermission()) {
      if (mounted) talkToast(context, 'Sesli mesaj için mikrofon izni gerekli', error: true);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/sesli-mesaj-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: path);
    HapticFeedback.mediumImpact();
    _focus.unfocus();
    await _ampSub?.cancel();
    _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((a) {
      if (!mounted || _recPaused) return;
      final v = ((a.current + 50) / 50).clamp(0.08, 1.0);
      setState(() {
        _recAmps.add(v);
        if (_recAmps.length > 80) _recAmps.removeAt(0);
      });
    });
    setState(() {
      _recording = true;
      _recPaused = false;
      _recHold = Duration.zero;
      _recMark = DateTime.now();
      _recAmps
        ..clear()
        ..addAll(List.filled(12, 0.15));
      _pop = null;
    });
    _recTick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted && !_recPaused) setState(() {});
    });
  }

  Future<void> _toggleRecPause() async {
    if (_recPaused) {
      await _rec.resume();
      if (!mounted) return;
      setState(() {
        _recPaused = false;
        _recMark = DateTime.now();
      });
      return;
    }
    await _rec.pause();
    if (!mounted) return;
    setState(() {
      _recHold += DateTime.now().difference(_recMark);
      _recPaused = true;
    });
  }

  Future<void> _stopRec({required bool send}) async {
    _recTick?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    final ms = _recElapsed.inMilliseconds;
    final path = await _rec.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recPaused = false;
      _recAmps.clear();
    });
    if (path == null) return;
    if (!send || ms < 1000) {
      try {
        File(path).deleteSync();
      } on FileSystemException {
        // geçici dosya zaten yoksa sorun değil
      }
      if (send) talkToast(context, 'Sesli mesaj çok kısa');
      return;
    }
    final p = _Pending.one(path, 'sesli-mesaj.m4a', false, '', _reply?.id ?? 0);
    setState(() {
      _reply = null;
      _pending.add(p);
    });
    _upload(p);
    _scrollToBottom();
  }

  Widget _recRound(Color bg, Widget child, VoidCallback onTap, {double size = 44}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: child,
        ),
      );

  /// WhatsApp iOS kayıt alanı: üstte süre + dalga, altta çöp · duraklat/devam · gönder (yeşil yerine bizim ton).
  Widget _recordingBar(TalkColors c) {
    final secs = _recElapsed.inSeconds;
    final clock = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final wave = c.dark ? const Color(0xFFAEAEB2) : const Color(0xFF6B6B70);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Row(children: [
          SizedBox(width: 64, child: Text(clock, style: talkText(19, FontWeight.w500, c.ink, height: 1))),
          Expanded(
            child: SizedBox(
              height: 30,
              child: CustomPaint(
                painter: _WavePainter(List<double>.from(_recAmps), wave, paused: _recPaused),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
        child: Row(children: [
          Tooltip(
            message: 'Sil',
            child: _recRound(
              c.dark ? const Color(0xFF3A1D24) : const Color(0xFFFDE4EA),
              const Icon(CupertinoIcons.delete, size: 23, color: Color(0xFFE11D48)),
              () => _stopRec(send: false),
              size: 46,
            ),
          ),
          Expanded(
            child: Center(
              child: Tooltip(
                message: _recPaused ? 'Devam et' : 'Duraklat',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleRecPause,
                  child: SizedBox(
                    width: 56,
                    height: 46,
                    child: _recPaused
                        ? const Icon(CupertinoIcons.mic_fill, size: 26, color: Color(0xFFE11D48))
                        : Icon(CupertinoIcons.pause_fill, size: 28, color: c.ink),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Gönder',
            child: _recRound(c.accent, Icon(Icons.send_rounded, size: 22, color: c.accentContrast), () => _stopRec(send: true), size: 46),
          ),
        ]),
      ),
    ]);
  }

  // ---------- sohbette arama ----------
  void _runSearch(String q) {
    final needle = q.trim().toLowerCase();
    final hits = needle.isEmpty ? <int>[] : [for (final m in _messages.reversed) if (m.id > 0 && m.text.toLowerCase().contains(needle)) m.id];
    setState(() {
      _hits = hits;
      _hitIdx = 0;
    });
    if (hits.isNotEmpty) _jumpTo(hits.first);
  }

  void _stepHit(int dir) {
    if (_hits.isEmpty) return;
    setState(() => _hitIdx = (_hitIdx + dir) % _hits.length);
    if (_hitIdx < 0) _hitIdx += _hits.length;
    _jumpTo(_hits[_hitIdx]);
  }

  void _closeSearch() {
    _searchCtl.clear();
    setState(() {
      _searching = false;
      _hits = const [];
    });
  }

  void _startReply(TalkMessage m) {
    setState(() {
      _reply = m;
      _editing = null;
    });
    _focus.requestFocus();
  }

  Future<void> _react(TalkMessage m, String emoji) async {
    try {
      await _c.api.react(m.id, emoji);
      // web: sunucudan güncel tepki listesi gelene kadar yerelde çevir
      final list = [...m.reactions];
      final i = list.indexWhere((r) => r.emoji == emoji);
      if (i >= 0) {
        final r = list[i];
        list[i] = TalkReaction(emoji: emoji, count: r.mine ? r.count - 1 : r.count + 1, mine: !r.mine);
      } else {
        list.add(TalkReaction(emoji: emoji, count: 1, mine: true));
      }
      setState(() => m.reactions = list.where((r) => r.count > 0).toList());
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Tepki eklenemedi' : e.message, error: true);
    }
  }

  Future<void> _saveEdit(TalkMessage m, String body) async {
    if (body.trim().isEmpty) {
      talkToast(context, 'Mesaj boş olamaz', error: true);
      return;
    }
    try {
      await _c.api.editMessage(m.id, body.trim());
      setState(() {
        m
          ..body = body.trim()
          ..edited = true;
        _editing = null;
      });
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Düzenlenemedi' : e.message, error: true);
    }
  }

  void _jumpTo(int id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, alignment: 0.4, duration: const Duration(milliseconds: 250));
    setState(() => _highlight = id);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  /// Başlıktaki arama menüsü (WhatsApp iOS): sesli / görüntülü, kişi seç, bağlantı gönder, planla.
  Future<void> _callMenu(Rect anchor) async {
    final c = TalkColors.of(context);
    final ink = c.dark ? const Color(0xFFF2F2F7) : const Color(0xFF111111);
    final items = <(String, IconData, String)?>[
      ('voice', CupertinoIcons.phone, 'Sesli arama'),
      ('video', CupertinoIcons.video_camera, 'Görüntülü arama'),
      null,
      if (_ch.isGroup) ('pick', CupertinoIcons.checkmark_circle, 'Kişi seç'),
      ('link', CupertinoIcons.link, 'Arama bağlantısı gönder'),
      ('plan', CupertinoIcons.calendar, 'Arama planla'),
    ];
    final act = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, _) {
        final w = math.min(290.0, MediaQuery.sizeOf(ctx).width - 24);
        return Stack(children: [
          Positioned.fill(child: GestureDetector(onTap: () => Navigator.pop(ctx), child: const ColoredBox(color: Colors.transparent))),
          Positioned(
            top: anchor.top,
            right: math.max(12.0, MediaQuery.sizeOf(ctx).width - anchor.right),
            width: w,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Material(
                  color: c.dark ? const Color(0xE62C2C2E) : const Color(0xE6F6F6F9),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(height: 8),
                    for (final it in items)
                      if (it == null)
                        Divider(height: 17, thickness: 0.6, indent: 22, endIndent: 22, color: c.dark ? const Color(0x33FFFFFF) : const Color(0x1F000000))
                      else
                        InkWell(
                          onTap: () => Navigator.pop(ctx, it.$1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                            child: Row(children: [
                              Icon(it.$2, size: 23, color: ink),
                              const SizedBox(width: 18),
                              Expanded(child: Text(it.$3, style: talkText(17.5, FontWeight.w400, ink))),
                            ]),
                          ),
                        ),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
            ),
          ),
        ]);
      },
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(alignment: Alignment.topRight, scale: Tween(begin: 0.9, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child),
      ),
    );
    if (act == null || !mounted) return;
    switch (act) {
      case 'voice':
        return _startCall(video: false);
      case 'video':
        return _startCall(video: true);
      case 'pick':
        return _pickCallPerson();
      case 'link':
        // sohbete bir saat geçerli arama kartı: dokunan aramaya katılır
        await _send(talkEventBody('Sesli arama', DateTime.now(), video: false));
      case 'plan':
        await _planCall();
    }
  }

  /// WhatsApp "Arama planla" tam ekranı: sohbete etkinlik kartı (kapak fotoğrafı varsa ekiyle)
  Future<void> _planCall() async {
    final me = talkFirstName(_c.me?.displayName ?? 'Ben');
    final peer = _ch.isDm ? talkFirstName(_ch.peer?.displayName ?? _ch.name) : _ch.name;
    final e = await showTalkCallPlanScreen(context, peerName: peer, organizerName: me, title: _ch.isDm ? null : '${_ch.name} araması');
    if (e == null || !mounted) return;
    final body = talkEventBody(e.title, e.start, end: e.end, video: e.video, approve: e.requireApproval, remindMinutes: e.remindMinutes, description: e.description);
    if (e.coverPath == null) {
      await _send(body);
      return;
    }
    try {
      final j = await _c.api.sendMessage(channelId: _ch.id, body: body, filePaths: [e.coverPath!]);
      if (!mounted) return;
      if (j['message'] is Map) _append([TalkMessage.fromJson((j['message'] as Map).cast<String, dynamic>())]);
      _scrollToBottom();
    } on ArconApiException catch (err) {
      if (mounted) talkToast(context, err.message.isEmpty ? 'Planlanamadı' : err.message, error: true);
    }
  }

  /// WhatsApp "Kişi seç": grup başlığı, yuvarlak seçimli üye listesi, altta Sesli / Görüntülü (seçince etkin).
  /// Arama birebir yapıldığı için tek kişi seçilir.
  Future<void> _pickCallPerson() async {
    final people = (_side?.people ?? const <TalkUser>[]).where((u) => u.id != _meId).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    if (people.isEmpty) {
      talkToast(context, 'Grupta aranacak kişi yok');
      return;
    }
    final c = TalkColors.of(context);
    final ink = c.dark ? const Color(0xFFF2F2F7) : const Color(0xFF111111);
    final card = c.dark ? const Color(0xFF2C2C2E) : Colors.white;
    final photo = _c.api.fileUrl(_ch.photo);
    TalkUser? picked;
    final pick = await showModalBottomSheet<(TalkUser, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget row(Widget leading, Widget title, Widget trailing, {VoidCallback? onTap, bool last = false}) => InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(children: [
                    leading,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Container(
                        height: 64,
                        padding: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
                        child: Row(children: [Expanded(child: title), trailing]),
                      ),
                    ),
                  ]),
                ),
              );
          Widget button(IconData icon, String label, bool video) {
            final on = picked != null;
            return Expanded(
              child: GestureDetector(
                onTap: on ? () => Navigator.pop(ctx, (picked!, video)) : null,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: on ? c.accent : (c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EE)),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, size: 20, color: on ? c.accentContrast : c.muted),
                    const SizedBox(width: 8),
                    Text(label, style: talkText(17, FontWeight.w600, on ? c.accentContrast : c.muted)),
                  ]),
                ),
              ),
            );
          }

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
                    child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                      row(
                        photo.isNotEmpty
                            ? TalkAvatar.solid(name: _ch.name, photoUrl: photo, size: 44)
                            : Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: c.dark ? const Color(0xFF3A3A3C) : const Color(0xFFEBE9FB), shape: BoxShape.circle),
                                child: Icon(CupertinoIcons.person_2_fill, size: 22, color: c.dark ? const Color(0xFFAEAEB2) : const Color(0xFF5B4FD6)),
                              ),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(_ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w500, ink)),
                          Text('Kişi seç', style: talkText(13.5, FontWeight.w400, c.muted)),
                        ]),
                        Icon(CupertinoIcons.chevron_down, size: 18, color: c.muted),
                      ),
                      for (var i = 0; i < people.length; i++)
                        row(
                          TalkAvatar.solid(name: people[i].displayName, photoUrl: _c.api.fileUrl(people[i].avatarPath), size: 44, personIfEmpty: true),
                          Text(people[i].displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w400, ink)),
                          Icon(
                            picked?.id == people[i].id ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            size: 26,
                            color: picked?.id == people[i].id ? c.accent : c.muted.withValues(alpha: 0.7),
                          ),
                          onTap: () => setSheet(() => picked = picked?.id == people[i].id ? null : people[i]),
                          last: i == people.length - 1,
                        ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(children: [
                    button(CupertinoIcons.phone_fill, 'Sesli', false),
                    const SizedBox(width: 12),
                    button(CupertinoIcons.video_camera_solid, 'Görüntülü', true),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (pick != null && mounted) await _contactCall(pick.$1, video: pick.$2);
  }

  Future<void> _startCall({required bool video}) async {
    final existing = _c.liveCallOn(_ch.id);
    if (existing != null) {
      await TalkCallScreen.joinLive(
        context,
        api: _c.api,
        call: existing,
        photoUrl: _c.api.fileUrl(_ch.photo),
      );
      return;
    }
    await TalkCallScreen.start(
      context,
      api: _c.api,
      channelId: _ch.id,
      video: video,
      title: _ch.name,
      peerName: _ch.isDm ? (_ch.peer?.displayName ?? _ch.name) : _ch.name,
      photoUrl: _c.api.fileUrl(_ch.photo),
    );
  }

  void _openInfo() async {
    final res = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => TalkInfoScreen(controller: _c, channel: _ch, sidebar: _side, session: widget.session, config: widget.config),
    ));
    if (!mounted) return;
    // gruptan çıkıldı: sohbet listesine dön
    if (res == 'left') {
      Navigator.of(context).pop();
      return;
    }
    // Kararlar / Görevler'den bir mesaja dokunuldu
    if (res != null && res.startsWith('jump:')) _jumpTo(int.tryParse(res.substring(5)) ?? 0);
    // bilgi ekranındaki "Sohbette ara"
    if (res == 'search') setState(() => _searching = true);
    // "Sohbeti temizle": eski mesajlar sunucudan artık gelmez, listeyi baştan yükle
    if (res == 'cleared') {
      await _load();
      if (mounted) setState(() {});
    }
    _refreshSidebar();
  }

  TalkUser _userFromMessage(TalkMessage m) {
    for (final u in _c.users) {
      if (u.id == m.userId) return u;
    }
    for (final u in _side?.people ?? const <TalkUser>[]) {
      if (u.id == m.userId) return u;
    }
    return TalkUser(id: m.userId, username: m.username, displayName: m.displayName.isEmpty ? m.username : m.displayName, avatarPath: m.avatarPath);
  }

  Future<void> _openContact(TalkUser user) async {
    if (user.id == _c.me?.id) return;
    // grupta: üyenin rolü ve benim yönetme yetkim (sahibe işlem yok)
    final side = _side;
    final role = side?.people.where((p) => p.id == user.id).firstOrNull?.role ?? '';
    final manage = _ch.isGroup && (side?.canManage ?? false) && role.isNotEmpty && role != 'owner';
    await showTalkContactSheet(
      context: context,
      user: user,
      photoUrl: _c.api.fileUrl(user.avatarPath),
      onMessage: () => unawaited(_contactMessage(user)),
      onVoice: () => unawaited(_contactCall(user, video: false)),
      onVideo: () => unawaited(_contactCall(user, video: true)),
      onInfo: _ch.isGroup ? () => unawaited(_contactInfo(user)) : null,
      admin: manage
          ? (
              isAdmin: role == 'admin',
              onToggleAdmin: () => unawaited(_memberRole(user, admin: role != 'admin')),
              onRemove: () => unawaited(_memberRemove(user)),
            )
          : null,
    );
  }

  /// Üyenin kişi bilgisi (birebir sohbetin bilgi ekranı)
  Future<void> _contactInfo(TalkUser user) async {
    try {
      final ch = await _c.api.openDm(user.id);
      if (ch == null || !mounted) return;
      _c.upsertChannel(ch);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TalkInfoScreen(controller: _c, channel: ch, session: widget.session, config: widget.config),
      ));
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Bilgi açılamadı' : e.message, error: true);
    }
  }

  Future<void> _memberRole(TalkUser user, {required bool admin}) async {
    try {
      final ns = await _c.api.setRole(_ch.id, user.id, admin ? 'admin' : 'member');
      if (!mounted) return;
      setState(() => _side = ns);
      talkToast(context, admin ? '${talkFirstName(user.displayName)} artık grup yöneticisi' : '${talkFirstName(user.displayName)} yöneticilikten çıkarıldı');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'İşlem başarısız' : e.message, error: true);
    }
  }

  Future<void> _memberRemove(TalkUser user) async {
    final ok = await talkConfirm(context, title: 'Gruptan çıkar', message: '${user.displayName} gruptan çıkarılsın mı?', ok: 'Çıkar');
    if (!ok || !mounted) return;
    try {
      final ns = await _c.api.removeMember(_ch.id, user.id);
      if (!mounted) return;
      setState(() => _side = ns);
      talkToast(context, '${talkFirstName(user.displayName)} gruptan çıkarıldı');
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Çıkarılamadı' : e.message, error: true);
    }
  }

  Future<void> _contactMessage(TalkUser user) async {
    if (_ch.isDm && _ch.peer?.id == user.id) return;
    try {
      final ch = await _c.api.openDm(user.id);
      if (ch == null || !mounted) return;
      _c.upsertChannel(ch);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TalkChatScreen(controller: _c, channel: ch, config: widget.config, session: widget.session),
        ),
      );
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Sohbet açılamadı' : e.message, error: true);
    }
  }

  Future<void> _contactCall(TalkUser user, {required bool video}) async {
    try {
      TalkChannel? ch = (_ch.isDm && _ch.peer?.id == user.id) ? _ch : await _c.api.openDm(user.id);
      if (ch == null || !mounted) return;
      _c.upsertChannel(ch);
      await TalkCallScreen.start(
        context,
        api: _c.api,
        channelId: ch.id,
        video: video,
        title: user.displayName,
        peerName: user.displayName,
        photoUrl: _c.api.fileUrl(user.avatarPath),
      );
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Arama başlatılamadı' : e.message, error: true);
    }
  }

  // ---------- arayüz ----------
  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    // Android geri tuşu önce seçimi kapatır (WhatsApp)
    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
      backgroundColor: c.msgBg,
      resizeToAvoidBottomInset: true,
      appBar: talkStatusBar(context),
      body: Column(children: [
        _head(c),
        Expanded(
          child: GestureDetector(
            // WhatsApp gibi: mesajlara dokununca klavye ve açık pencereler kapanır
            onTap: () {
              _focus.unfocus();
              setState(() => _pop = null);
            },
            child: Stack(children: [
              Positioned.fill(child: _background(c)),
              _list(c),
              if (_c.liveCallOn(_ch.id) != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 8,
                  child: Material(
                    color: TalkColors.wa,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _startCall(video: _c.liveCallOn(_ch.id)?.video ?? false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Text(
                          'Devam eden arama — katıl',
                          textAlign: TextAlign.center,
                          style: talkText(14, FontWeight.w700, Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_farFromBottom) Positioned(right: 14, bottom: 14, child: _toBottomButton(c)),
            ]),
          ),
        ),
        _composer(c),
      ]),
    ),
    );
  }

  Widget _head(TalkColors c) => _selected.isNotEmpty ? _selectHead(c) : (_searching ? _searchHead(c) : _mainHead(c));

  Widget _searchHead(TalkColors c) => Container(
        height: 64,
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(color: c.chatHead, border: Border(bottom: BorderSide(color: c.line))),
        child: Row(children: [
          IconButton(onPressed: _closeSearch, icon: TalkIcon(TalkSvg.back, size: 22, color: c.ink)),
          Expanded(
            child: TextField(
              controller: _searchCtl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _runSearch,
              onSubmitted: (_) => _stepHit(1),
              style: talkText(15.5, FontWeight.w400, c.ink),
              cursorColor: c.ink,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                hintText: 'Sohbette ara…',
                hintStyle: talkText(15.5, FontWeight.w400, c.muted),
              ),
            ),
          ),
          if (_searchCtl.text.trim().isNotEmpty)
            Text(_hits.isEmpty ? '0' : '${_hitIdx + 1}/${_hits.length}', style: talkText(13, FontWeight.w600, c.muted)),
          IconButton(onPressed: _hits.isEmpty ? null : () => _stepHit(1), icon: Icon(Icons.keyboard_arrow_up, color: c.ink)),
          IconButton(onPressed: _hits.isEmpty ? null : () => _stepHit(-1), icon: Icon(Icons.keyboard_arrow_down, color: c.ink)),
        ]),
      );

  /// WhatsApp iOS başlığı: yuvarlak geri, fotoğraf + ad, sağda görüntülü/sesli arama kapsülü
  Widget _mainHead(TalkColors c) {
    final glass = BoxDecoration(
      color: c.dark ? const Color(0xFF1C1C1E) : Colors.white,
      border: Border.all(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE6E6E8)),
      boxShadow: c.dark ? null : const [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 3))],
    );
    void openPeer() {
      if (_ch.isDm && _ch.peer != null) {
        unawaited(_openContact(_ch.peer!));
      } else {
        _openInfo();
      }
    }

    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: c.chatHead,
      child: Row(children: [
        Tooltip(
          message: 'Sohbet listesine dön',
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 44,
              height: 44,
              decoration: glass.copyWith(shape: BoxShape.circle),
              child: Icon(CupertinoIcons.chevron_left, size: 24, color: c.ink),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openInfo,
            onLongPress: openPeer,
            child: Row(children: [
              _ch.isDm || _ch.photo.isNotEmpty
                  ? TalkAvatar.solid(name: _ch.name, photoUrl: _c.api.fileUrl(_ch.photo), size: 40, personIfEmpty: true)
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFEBEBEF), shape: BoxShape.circle),
                      child: Icon(CupertinoIcons.person_2_fill, size: 22, color: c.dark ? const Color(0xFFAEAEB2) : const Color(0xFF6E6E73)),
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w600, c.ink, height: 1.25)),
                  if (_isTyping || _peerOnline || !_ch.isDm || _ch.isSelf)
                    Text(_sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: talkText(12.5, FontWeight.w400, c.muted, height: 1.3).copyWith(fontStyle: _isTyping ? FontStyle.italic : FontStyle.normal)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // kendinle sohbette arama yok
        if (!_ch.isSelf)
          Container(
            height: 44,
            decoration: glass.copyWith(borderRadius: BorderRadius.circular(22)),
            // WhatsApp iOS: tek kamera düğmesi; dokununca arama seçenekleri
            child: Builder(
              builder: (bctx) => Tooltip(
                message: 'Ara',
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    final box = bctx.findRenderObject() as RenderBox;
                    _callMenu(box.localToGlobal(Offset.zero) & box.size);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.video_camera, size: 30, color: c.ink),
                      const SizedBox(width: 2),
                      Icon(CupertinoIcons.chevron_down, size: 13, color: c.ink),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  /// `.talk-messages` arka planı: iki hafif radyal gölge
  Widget _background(TalkColors c) => DecoratedBox(
        decoration: BoxDecoration(color: c.msgBg),
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -0.8),
                  radius: 0.9,
                  colors: [c.dark ? const Color(0x08FFFFFF) : const Color(0x08000000), const Color(0x00000000)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.6, 0.8),
                  radius: 0.95,
                  colors: [c.dark ? const Color(0x06FFFFFF) : const Color(0x06000000), const Color(0x00000000)],
                ),
              ),
            ),
          ),
        ]),
      );

  Widget _list(TalkColors c) {
    if (_loading) {
      return Center(child: Text('Yükleniyor…', style: talkText(16, FontWeight.w700, c.ink)));
    }
    if (_messages.isEmpty && _pending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Henüz mesaj yok\n', style: talkText(16.8, FontWeight.w700, c.ink, height: 1.6)),
                const TextSpan(text: 'İlk mesajı sen yaz veya dosya paylaş.'),
              ]),
              textAlign: TextAlign.center,
              style: talkText(16, FontWeight.w400, c.muted),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final contentW = box.maxWidth - 45;
      final maxBubble = contentW * 0.82 - 42;
      final children = <Widget>[];
      DateTime? lastDay;
      for (var mi = 0; mi < _messages.length; mi++) {
        final m = _messages[mi];
        // WhatsApp: kuyruk yalnızca aynı kişinin art arda mesajlarının sonuncusunda
        final next = mi + 1 < _messages.length ? _messages[mi + 1] : null;
        final d = talkParseTime(m.createdAt);
        final nd = next == null ? null : talkParseTime(next.createdAt);
        final tail = next == null || next.userId != m.userId || d == null || nd == null || d.day != nd.day || d.month != nd.month || d.year != nd.year;
        if (d != null) {
          final day = DateTime(d.year, d.month, d.day);
          if (lastDay == null || day != lastDay) {
            children.add(_dayChip(c, talkDayLabel(d)));
            lastDay = day;
          }
        }
        final key = _keys.putIfAbsent(m.id, GlobalKey.new);
        final picked = _selected.contains(m.id);
        final callLine = m.attachments.isEmpty ? talkCallLine(m.body) : null;
        final event = callLine == null ? talkEventLine(m.body) : null;
        final place = m.attachments.isEmpty && callLine == null && event == null ? talkLocationLine(m.body) : null;
        final poll = m.attachments.isEmpty && callLine == null && event == null && place == null ? talkPollLine(m.body) : null;
        final view = callLine != null
            // WhatsApp gibi arama balonu; dokununca geri arar
            ? TalkCallLineView(line: callLine, mine: m.userId == _meId, time: talkClock(m.createdAt), onTap: () => _startCall(video: callLine.video))
            : event != null
                // etkinlik / planlı arama kartı
                ? TalkEventCardView(
                    event: event,
                    mine: m.userId == _meId,
                    time: talkClock(m.createdAt),
                    onCall: (v) => _startCall(video: v),
                    coverUrl: () {
                      for (final a in m.attachments) {
                        if (a.isImage) return _c.api.fileUrl(a.path);
                      }
                      return null;
                    }(),
                  )
                : place != null
                    ? TalkLocationCardView(location: place, mine: m.userId == _meId, time: talkClock(m.createdAt))
                    : poll != null && m.id > 0
                        ? TalkPollCardView(poll: poll, reactions: m.reactions, mine: m.userId == _meId, time: talkClock(m.createdAt), onVote: (e) => _vote(m, e))
                        : TalkMessageView(
          message: m,
          mine: m.userId == _meId,
          group: _ch.isGroup,
          api: _c.api,
          maxWidth: maxBubble,
          tail: tail,
          onMenu: (at) => _menu(m, at),
          onSelect: m.id > 0 ? () => _toggleSelect(m) : null,
          // seçim modunda basılı tutmak seçer, değilse WhatsApp menüsü
          onLongMenu: m.id > 0 && _selected.isEmpty ? (r, p) => _menu(m, r.center, rect: r, preview: p) : null,
          onReact: (e) => _react(m, e),
          onReplyTap: _jumpTo,
          onSwipeReply: m.id > 0 ? () => _startReply(m) : null,
          onForward: m.id > 0 ? () => _forward([m]) : null,
          tick: _tickFor(m),
          editing: _editing == m.id,
          onEditSave: (b) => _saveEdit(m, b),
          onEditCancel: () => setState(() => _editing = null),
          onUserTap: m.userId == _meId ? null : () => _openContact(_userFromMessage(m)),
        );
        children.add(AnimatedContainer(
          key: key,
          duration: const Duration(milliseconds: 300),
          color: picked ? TalkColors.wa.withValues(alpha: 0.22) : (_highlight == m.id ? c.accentSoft : Colors.transparent),
          // seçim açıkken dokunuş mesajı seçer / bırakır (menü açılmaz)
          child: _selected.isEmpty
              ? view
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleSelect(m),
                  child: AbsorbPointer(child: view),
                ),
        ));
        children.add(const SizedBox(height: 8));
      }
      for (final p in _pending) {
        children.add(_PendingView(p: p, maxWidth: maxBubble, me: _c.me, photoUrl: _c.api.fileUrl(_c.me?.avatarPath ?? ''), onCancel: () => p.cancel.complete(), onRetry: () => _upload(p)));
        children.add(const SizedBox(height: 8));
      }
      return SingleChildScrollView(
        controller: _scroll,
        reverse: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(22.5, 18, 22.5, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
    });
  }

  /// WhatsApp'taki gün ayracı ("Bugün", "Dün", "2 Kasım")
  Widget _dayChip(TalkColors c, String label) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: c.chatHead, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.line)),
            child: Text(label, style: talkText(12.2, FontWeight.w600, c.muted, height: 1.3)),
          ),
        ),
      );

  /// En alta inme butonu; yukarıdayken gelen mesaj sayısını gösterir.
  Widget _toBottomButton(TalkColors c) => GestureDetector(
        onTap: () {
          setState(() => _unseen = 0);
          _scrollToBottom();
        },
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.composerBar,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: RotatedBox(quarterTurns: 3, child: TalkIcon(TalkSvg.back, size: 20, color: c.ink)),
          ),
          if (_unseen > 0)
            Positioned(
              top: -6,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: const BoxConstraints(minWidth: 20),
                decoration: BoxDecoration(color: TalkColors.wa, borderRadius: BorderRadius.circular(999)),
                child: Text('$_unseen', textAlign: TextAlign.center, style: talkText(11, FontWeight.w700, Colors.white, height: 1.3)),
              ),
            ),
        ]),
      );

  /// Mesaj yazma alanı (WhatsApp düzeni)
  Widget _composer(TalkColors c) {
    final panel = _pop == 'emoji' || _pop == 'gif';
    final bar = Container(
      padding: EdgeInsets.fromLTRB(8, 6, 8, 8 + MediaQuery.paddingOf(context).bottom * (MediaQuery.viewInsetsOf(context).bottom > 0 || panel ? 0 : 1)),
      color: c.composerArea,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_pop == 'mention') _mentionPop(c),
        if (_reply != null) _replyBar(c),
        // Anahtar şart: üstüne açılan pencere de Container; anahtarsız olunca yazı kutusu
        // yeniden kurulup odağı (klavyeyi) kaybediyordu.
        // WhatsApp iOS: "+" · yazı kutusu (içinde çıkartma/emoji) · kamera · siyah mikrofon / gönder
        Row(
          key: const ValueKey('talk-composer-bar'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _recording
              ? [Expanded(child: _recordingBar(c))]
              : [
                  _composerIcon(c, Icons.add, 'Ekle', _attach, size: 30),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 40),
                      padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                      decoration: BoxDecoration(
                        color: c.composerBar,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: c.composerBorder, width: 0.6),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _openComposerKeyboard,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 8000,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              textCapitalization: TextCapitalization.sentences,
                              style: talkText(16.5, FontWeight.w400, c.ink, height: 1.3),
                              cursorColor: c.ink,
                              onTap: _openComposerKeyboard,
                              decoration: const InputDecoration(
                                isCollapsed: true,
                                filled: false,
                                counterText: '',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        // çıkartma simgesi: klavyenin yerine emoji / GIF / çıkartma paneli; açıkken klavye simgesi
                        if (panel)
                          Tooltip(
                            message: 'Klavye',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() => _pop = null);
                                _openComposerKeyboard();
                              },
                              child: SizedBox(width: 38, height: 40, child: Center(child: Icon(CupertinoIcons.keyboard, size: 23, color: c.ink))),
                            ),
                          )
                        else
                          _barBtn(TalkSvg.sticker, 'Emoji ve GIF', () {
                            _focus.unfocus();
                            setState(() => _pop = 'gif');
                          }),
                      ]),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, v, _) {
                      final empty = v.text.trim().isEmpty;
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        if (empty) _composerIcon(c, CupertinoIcons.camera, 'Kamera', () async => _sendPicked(await _pickFiles('camera')), size: 26),
                        Padding(
                          padding: EdgeInsets.only(left: empty ? 2 : 8),
                          child: Tooltip(
                            message: empty ? 'Sesli mesaj' : 'Gönder',
                            child: GestureDetector(
                              onTap: empty ? _startRec : () => _send(),
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                                child: empty
                                    ? Icon(CupertinoIcons.mic_fill, size: 21, color: c.accentContrast)
                                    : Icon(CupertinoIcons.arrow_up, size: 22, color: c.accentContrast),
                              ),
                            ),
                          ),
                        ),
                      ]);
                    },
                  ),
                ],
        ),
      ]),
    );
    if (!panel) return bar;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      bar,
      TalkStickerPanel(
        api: _c.api,
        onGif: (url) {
          setState(() => _pop = null);
          _send('[[gif:$url]]');
        },
      ),
    ]);
  }

  Widget _composerIcon(TalkColors c, IconData icon, String tip, VoidCallback onTap, {double size = 26}) => Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(width: 44, height: 40, child: Center(child: Icon(icon, size: size, color: c.ink))),
        ),
      );

  Widget _barBtn(String svg, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(width: 38, height: 40, child: Center(child: TalkIcon(svg, size: 22, color: TalkColors.of(context).ink))),
        ),
      );

  /// `.talk-reply-bar`
  Widget _replyBar(TalkColors c) {
    final r = _reply!;
    final name = r.userId == _meId ? 'Sen' : (r.displayName.isEmpty ? 'Mesaj' : r.displayName);
    final text = r.text.isNotEmpty ? r.text : (r.attachments.isNotEmpty ? r.attachments.first.origName : (r.gifs.isNotEmpty ? 'GIF' : 'Mesaj'));
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0x1F7F7F7F),
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: TalkColors.ticks, width: 3)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: talkText(12.8, FontWeight.w600, TalkColors.ticks)),
            const SizedBox(height: 2),
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(12.8, FontWeight.w400, c.muted)),
          ]),
        ),
        GestureDetector(
          onTap: () => setState(() => _reply = null),
          child: SizedBox(width: 28, height: 28, child: Center(child: Text('×', style: talkText(20, FontWeight.w400, c.muted, height: 1)))),
        ),
      ]),
    );
  }

  /// Yazılmakta olan "@kelime"yi seçilen adla değiştirir; klavye açık kalır.
  void _insertMention(String name) {
    final t = _input.text;
    final sel = _input.selection.baseOffset < 0 ? t.length : _input.selection.baseOffset.clamp(0, t.length);
    final before = t.substring(0, sel).replaceFirst(RegExp(r'@([A-Za-zÇĞİÖŞÜçğıöşü0-9_]*)$'), '@$name ');
    _input.value = TextEditingValue(text: before + t.substring(sel), selection: TextSelection.collapsed(offset: before.length));
    setState(() => _pop = null);
    _focus.requestFocus();
  }

  /// `.talk-pop--mention`
  Widget _mentionPop(TalkColors c) {
    final q = _mentionQ.toLowerCase();
    final pool = (_side?.people ?? const <TalkUser>[])
        .where((u) => u.id != _meId)
        .where((u) => q.isEmpty || u.displayName.toLowerCase().contains(q) || u.username.toLowerCase().contains(q))
        .take(8)
        .toList();
    final everyone = !_ch.isDm && 'herkes'.startsWith(q);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 6),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: c.railTop,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.popBorder),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: pool.isEmpty && !everyone
          ? Padding(padding: const EdgeInsets.all(10), child: Text('Kullanıcı yok', style: talkText(13.6, FontWeight.w400, const Color(0xFF6B7280))))
          : ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(6),
              children: [
                if (everyone)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _insertMention('herkes'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                          child: Text('@', style: talkText(14, FontWeight.w800, c.ink, height: 1)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text('herkes', style: talkText(16, FontWeight.w600, c.ink))),
                        Text('Gruptaki herkes', style: talkText(12.48, FontWeight.w400, c.muted)),
                      ]),
                    ),
                  ),
                for (final u in pool)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _insertMention(u.displayName),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        TalkAvatar.solid(name: u.displayName, photoUrl: _c.api.fileUrl(u.avatarPath), size: 28, fontSize: 10.4),
                        const SizedBox(width: 10),
                        Expanded(child: Text(u.displayName, style: talkText(16, FontWeight.w400, c.ink))),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Gönderilmekte olan dosya — kendi balonunda ilerleme halkası (×) veya "Tekrar".
class _PendingView extends StatelessWidget {
  const _PendingView({required this.p, required this.maxWidth, required this.me, required this.photoUrl, required this.onCancel, required this.onRetry});
  final _Pending p;
  final double maxWidth;
  final TalkUser? me;
  final String photoUrl;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    Widget ring() => GestureDetector(
          onTap: onCancel,
          child: Container(
            width: 36,
            height: 36,
            decoration: p.isImage ? const BoxDecoration(color: Color(0x8C0B141A), shape: BoxShape.circle) : null,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: p.progress, strokeWidth: 3, color: p.isImage ? Colors.white : c.bubbleOutInk, backgroundColor: const Color(0x40FFFFFF)),
              Text('×', style: talkText(16, FontWeight.w700, p.isImage ? Colors.white : c.bubbleOutInk, height: 1)),
            ]),
          ),
        );
    Widget retry() => GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: TalkColors.wa, borderRadius: BorderRadius.circular(999)),
            child: Text('Tekrar', style: talkText(12, FontWeight.w700, Colors.white)),
          ),
        );
    Widget photoGrid() {
      final w = maxWidth - 24 > 280 ? 280.0 : maxWidth - 24;
      final shown = p.paths.take(4).toList();
      final extra = p.paths.length > 4 ? p.paths.length - 4 : 0;
      Widget cell(int i) => Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                Image.file(File(shown[i]), fit: BoxFit.cover),
                if (extra > 0 && i == 3)
                  Container(color: const Color(0x8C0B141A), alignment: Alignment.center, child: Text('+$extra', style: talkText(22, FontWeight.w700, Colors.white))),
              ]),
            ),
          );
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: w,
          child: shown.length == 1
              ? Opacity(opacity: 0.85, child: Image.file(File(shown.first), fit: BoxFit.cover))
              : Column(children: [
                  for (var r = 0; r < shown.length; r += 2) ...[
                    if (r > 0) const SizedBox(height: 3),
                    Row(children: [
                      cell(r),
                      const SizedBox(width: 3),
                      if (r + 1 < shown.length) cell(r + 1) else const Expanded(child: SizedBox()),
                    ]),
                  ],
                ]),
        ),
      );
    }

    final body = p.isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(alignment: Alignment.center, children: [
              photoGrid(),
              p.failed ? retry() : ring(),
            ]),
          )
        : Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x24000000),
              borderRadius: BorderRadius.circular(10),
              border: p.failed ? Border.all(color: const Color(0x59EF4444)) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              p.failed ? retry() : ring(),
              const SizedBox(width: 10),
              Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(14.08, FontWeight.w700, c.bubbleOutInk))),
            ]),
          );
    return Align(
      alignment: Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            decoration: ShapeDecoration(color: c.bubbleOut, shape: const TalkBubbleShape(mine: true)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              body,
              if (p.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(p.caption, style: talkText(14.72, FontWeight.w400, c.bubbleOutInk, height: 1.45)),
                ),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Opacity(opacity: 0.55, child: Text(talkClock(DateTime.now().toString()), style: talkText(10.88, FontWeight.w400, c.bubbleOutInk))),
                const SizedBox(width: 4),
                Opacity(opacity: 0.55, child: TalkIcon(TalkSvg.pendingClock, size: 12, color: c.bubbleOutInk)),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        TalkAvatar.hue(name: me?.displayName ?? '?', seed: me?.id, photoUrl: photoUrl),
      ]),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.amps, this.color, {required this.paused});
  final List<double> amps;
  final Color color;
  final bool paused;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    // WhatsApp: sessiz yerler nokta, ses çubuk; en yeni ses sağda, solu noktalarla dolar
    final paint = Paint()
      ..color = color.withValues(alpha: paused ? 0.45 : 1)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6;
    const gap = 4.6;
    final n = (size.width / gap).floor().clamp(8, 80);
    final start = amps.length > n ? amps.length - n : 0;
    final slice = amps.sublist(start);
    final pad = n - slice.length;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final x = i * gap + 1.3;
      final t = i < pad ? 0.0 : slice[i - pad];
      if (t <= 0.16) {
        canvas.drawCircle(Offset(x, mid), 1.2, paint);
      } else {
        final h = (t * size.height).clamp(4.0, size.height);
        canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.amps != amps || old.paused != paused || old.color != color;
}
