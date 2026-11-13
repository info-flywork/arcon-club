import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ai_tools/tool_common.dart' show toolToast;
import '../ai/ai_image_generating.dart';
import '../talk/talk_ai_logo.dart';
import '../talk/talk_icons.dart';
import '../talk/talk_swipe.dart';
import '../talk/talk_theme.dart';
import '../talk/talk_widgets.dart';
import '../ui/theme.dart';
import 'ncb_api.dart';
import 'ncb_icons.dart';
import 'ncb_message.dart';
import 'ncb_theme.dart';

String _s(Object? v) => v == null ? '' : '$v';

/// ARCON AI — webdeki ARCON AI'nin (new_chatbot) mobil hâli: aynı sohbetler, projeler, modeller,
/// akış ve model seçimine göre ChatGPT / Gemini / Claude / DeepSeek görünümü.
class ArconAiScreen extends StatefulWidget {
  const ArconAiScreen({super.key, required this.session, this.title = 'ARCON AI', this.private = false});
  final SessionController session;
  final String title;

  /// Gizli sohbet: koyu ekran; ekrandan çıkınca sohbet sunucudan silinir.
  final bool private;

  @override
  State<ArconAiScreen> createState() => _ArconAiScreenState();
}

class _Pending {
  _Pending(this.path, this.name, this.isImage);
  final String path;
  final String name;
  final bool isImage;
  String? id;
  String kind = '';
  bool uploading = true;
}

class _ArconAiScreenState extends State<ArconAiScreen> {
  late final NcbApi _api = NcbApi(widget.session.api);
  final _scaffold = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _rec = AudioRecorder();

  Map<String, dynamic>? _me;
  String? _error;
  List<NcbTier> _tiers = const [];
  String _tier = 'balanced';
  List<NcbConv> _convs = [];
  String? _currentId;
  String? _projectId; // proje modu (boş sohbet ekranında proje başlığı)
  List<NcbMsg> _messages = [];
  bool _loadingConv = false;
  bool _streaming = false;
  Completer<void>? _cancel;
  final List<_Pending> _pending = [];
  ({String id, String name})? _editImage;
  final bool _dsSearch = true;
  bool _stick = true;
  bool _recording = false;
  bool _transcribing = false;
  DateTime? _recStart;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _stick = _scroll.offset < 140; // ters liste: en alt = 0
    });
    _boot();
  }

  @override
  void dispose() {
    if (widget.private && _currentId != null) {
      unawaited(_api.post('delete', {'id': _currentId}).catchError((Object _) => <String, dynamic>{}));
    }
    _cancel?.complete();
    _rec.dispose();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /* ------------------------------ veri ------------------------------ */

  Future<void> _boot() async {
    try {
      final me = await _api.get('me');
      if (!mounted) return;
      final settings = ((me['settings'] as Map?) ?? const {}).cast<String, dynamic>();
      setState(() {
        _me = me;
        _tiers = [for (final t in ((me['tiers'] as List?) ?? const []).whereType<Map>()) NcbTier.fromJson(t.cast<String, dynamic>())];
        _tier = _s(settings['tier']).isEmpty ? (_tiers.firstOrNull?.key ?? 'balanced') : _s(settings['tier']);
        if (!_tiers.any((t) => t.key == _tier) && _tiers.isNotEmpty) _tier = _tiers.first.key;
      });
      unawaited(_loadSide());
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 401 ? 'ARCON AI oturumu açılamadı. Uygulamadan çıkış yapıp tekrar gir.' : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'ARCON AI\'ye ulaşılamadı.');
    }
  }

  Future<void> _loadSide() async {
    try {
      final r = await _api.get('conversations');
      if (!mounted) return;
      setState(() => _convs = [for (final c in ((r['conversations'] as List?) ?? const []).whereType<Map>()) NcbConv.fromJson(c.cast<String, dynamic>())]);
    } catch (_) {}
  }

  NcbTier? get _tierObj => _tiers.where((t) => t.key == _tier).firstOrNull ?? _tiers.firstOrNull;
  String get _skinName => _tierObj?.skin ?? 'chatgpt';
  String get _userName => _s((_me?['user'] as Map?)?['name']);
  bool get _voice => ((_me?['features'] as Map?)?['voice']) == true;


  void _newChat({String? projectId}) {
    if (_streaming) _stop();
    setState(() {
      _currentId = null;
      _projectId = projectId;
      _messages = [];
      _editImage = null;
    });
    _scaffold.currentState?.closeDrawer();
  }

  Future<void> _openConv(String id) async {
    if (_streaming) _stop();
    _scaffold.currentState?.closeDrawer();
    setState(() {
      _currentId = id;
      _projectId = _convs.where((c) => c.id == id).firstOrNull?.projectId;
      _messages = [];
      _loadingConv = true;
      _editImage = null;
    });
    try {
      final j = await _api.get('conversation', {'id': id});
      if (!mounted || _currentId != id) return;
      setState(() {
        _messages = [for (final m in ((j['messages'] as List?) ?? const []).whereType<Map>()) NcbMsg.fromJson(m.cast<String, dynamic>())];
        _loadingConv = false;
      });
      _toBottom(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingConv = false);
      toolToast(context, e is ArconApiException ? e.message : 'Sohbet açılamadı');
    }
  }

  void _toBottom({bool force = false}) {
    if (!force && !_stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0); // ters liste: en yeni mesaj = 0
    });
  }

  /* ------------------------------ gönderme ------------------------------ */

  bool get _canSend => !_streaming && !_pending.any((p) => p.uploading) && (_input.text.trim().isNotEmpty || _pending.isNotEmpty);

  void _stop() {
    _cancel?.complete();
    _cancel = null;
  }

  Future<void> _send({String mode = 'send', String? text, int? messageId}) async {
    if (_streaming) return;
    final body = <String, Object?>{'conversation_id': _currentId, 'tier': _tier, 'mode': mode};
    if (_skinName == 'deepseek') body['search'] = _dsSearch;
    if (_currentId == null && _projectId != null) body['project_id'] = _projectId;

    if (mode == 'send') {
      final t = (text ?? _input.text).trim();
      if (t.isEmpty && _pending.isEmpty) return;
      body['text'] = t;
      final atts = [for (final p in _pending.where((p) => p.id != null)) {'id': p.id, 'kind': p.kind, 'name': p.name, if (p.isImage) 'local_path': p.path}];
      body['upload_ids'] = [for (final p in _pending.where((p) => p.id != null)) p.id];
      if (_editImage != null) body['edit_image_id'] = _editImage!.id;
      _messages.add(NcbMsg(role: 'user', display: {'text': t, 'attachments': atts}));
      _input.clear();
      _pending.clear();
      _editImage = null;
    } else if (mode == 'regenerate') {
      while (_messages.isNotEmpty && !_messages.last.isUser) {
        _messages.removeLast();
      }
    } else if (mode == 'edit') {
      final i = _messages.indexWhere((m) => m.id == messageId);
      if (i < 0) return;
      body['text'] = text;
      body['message_id'] = messageId;
      _messages = [..._messages.sublist(0, i), NcbMsg(role: 'user', id: messageId, display: {..._messages[i].d, 'text': text})];
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final live = NcbMsg(role: 'assistant')
      ..streaming = true
      ..status = '…';
    setState(() {
      _messages.add(live);
      _streaming = true;
    });
    _stick = true;
    _toBottom(force: true);

    final cancel = Completer<void>();
    _cancel = cancel;
    var gotDone = false;
    try {
      await for (final ev in _api.chat(body, cancel: cancel.future)) {
        if (!mounted) return;
        gotDone = _handle(ev, live) || gotDone;
        setState(() {});
        _toBottom();
      }
    } on ArconApiException catch (e) {
      live.d['error'] = e.message;
    } catch (_) {
      live.d['error'] = 'Bağlantı kesildi. Biraz sonra tekrar dene.';
    }
    if (!mounted) return;
    if (!gotDone && cancel.isCompleted && _s(live.d['error']).isEmpty) live.d['stopped'] = true;
    setState(() {
      live
        ..streaming = false
        ..status = ''
        ..thinkingLive = false
        ..imageLoaders.clear();
      _streaming = false;
    });
    _cancel = null;
    HapticFeedback.lightImpact();
  }

  /// Akış olayı (webdeki handleEvent). `done` gelirse true.
  bool _handle(Map<String, dynamic> ev, NcbMsg live) {
    switch (ev['type']) {
      case 'meta':
        final cid = _s(ev['conversation_id']);
        if (cid.isNotEmpty) {
          if (_currentId == null || ev['is_new'] == true) {
            _currentId = cid;
            if (!_convs.any((c) => c.id == cid)) {
              _convs.insert(0, NcbConv(id: cid, title: _s(ev['title']).isEmpty ? 'Yeni sohbet' : _s(ev['title']), projectId: ev['project_id'] as String?, updatedAt: DateTime.now()));
            }
          }
        }
        final user = _messages.length >= 2 ? _messages[_messages.length - 2] : null;
        if (user != null && user.isUser) {
          if (ev['user_message_id'] != null) user.id = (ev['user_message_id'] as num?)?.toInt();
          final ud = (ev['user_display'] as Map?)?.cast<String, dynamic>();
          if (ud != null) {
            // yerel önizleme kalsın, kimlikler sunucudan
            final local = {for (final a in user.list('attachments')) _s(a['id']): a['local_path']};
            user.d = {
              ...ud,
              'attachments': [for (final a in ((ud['attachments'] as List?) ?? const []).whereType<Map>()) {...a.cast<String, dynamic>(), 'local_path': ?local[_s(a['id'])]}],
            };
          }
        }
      case 'status':
        live.status = _s(ev['label']);
      case 'text':
        live.text = live.text + _s(ev['text']);
        if (live.text.trim().isNotEmpty) live.status = '';
      case 'thinking':
        live.thinkingLive = true;
        live.d['thinking'] = _s(live.d['thinking']) + _s(ev['text']);
        live.status = '';
      case 'thinking_done':
        live.thinkingLive = false;
        live.d['thinking_seconds'] = ev['seconds'];
      case 'step':
        live.add('steps', {'label': ev['label'], 'detail': ev['detail']});
      case 'source':
        live.add('sources', {'url': ev['url'], 'title': ev['title']});
      case 'image_start':
        live.status = '';
        live.imageLoaders[_s(ev['key'])] = _s(ev['size']).isEmpty ? '1024x1024' : _s(ev['size']);
      case 'image_error':
        live.imageLoaders.remove(_s(ev['key']));
      case 'image':
        live.status = '';
        live.imageLoaders.remove(_s(ev['key']));
        live.add('images', Map<String, dynamic>.from(ev)..remove('type'));
      case 'file':
        live.status = '';
        live.add('files', Map<String, dynamic>.from(ev)..remove('type'));
      case 'action':
        live.status = '';
        live.add('actions', Map<String, dynamic>.from(ev)..remove('type'));
      case 'connect':
        live.status = '';
        live.add('connects', Map<String, dynamic>.from(ev)..remove('type'));
      case 'done':
        final disp = (ev['display'] as Map?)?.cast<String, dynamic>();
        if (disp != null) live.d = disp;
        live.id = (ev['message_id'] as num?)?.toInt();
        live.createdAt = _s(ev['created_at']);
        final c = _convs.where((c) => c.id == _currentId).firstOrNull;
        if (c != null) {
          c.updatedAt = DateTime.now();
          _convs
            ..remove(c)
            ..insert(0, c);
        }
        return true;
      case 'title':
        final c = _convs.where((c) => c.id == _s(ev['conversation_id'])).firstOrNull;
        if (c != null) c.title = _s(ev['title']);
      case 'error':
        live.d['error'] = _s(ev['message']).isEmpty ? 'Şu anda cevap üretilemedi.' : _s(ev['message']);
    }
    return false;
  }

  /* ------------------------------ ekler ------------------------------ */

  Future<void> _addFile(String path, String name, bool isImage) async {
    final p = _Pending(path, name, isImage);
    setState(() => _pending.add(p));
    try {
      final r = await _api.upload('upload', 'file', path, filename: name);
      final f = ((r['file'] as Map?) ?? const {}).cast<String, dynamic>();
      p
        ..id = _s(f['id'])
        ..kind = _s(f['kind'])
        ..uploading = false;
    } catch (e) {
      _pending.remove(p);
      if (mounted) toolToast(context, '$name: ${e is ArconApiException ? e.message : 'yüklenemedi'}');
    }
    if (mounted) setState(() {});
  }

  Future<void> _attachMenu(NcbSkin k) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: k.popover,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (key, icon, label) in [
                ('camera', Icons.photo_camera_outlined, 'Kamera'),
                ('photos', Icons.photo_library_outlined, 'Fotoğraflar'),
                ('files', Icons.attach_file_rounded, 'Dosyalar'),
              ])
                ListTile(leading: Icon(icon, color: k.fg), title: Text(label, style: k.t(15)), onTap: () => Navigator.of(ctx).pop(key)),
            ],
          ),
        ),
      ),
    );
    if (v == null) return;
    if (v == 'camera') {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 88);
      if (x != null) unawaited(_addFile(x.path, x.name, true));
    } else if (v == 'photos') {
      for (final x in await ImagePicker().pickMultiImage(maxWidth: 2400, imageQuality: 88, limit: 10)) {
        unawaited(_addFile(x.path, x.name, true));
      }
    } else {
      for (final f in await FilePicker.pickFiles()) {
        if (f.path == null) continue;
        final img = RegExp(r'\.(png|jpe?g|webp|gif|heic)$', caseSensitive: false).hasMatch(f.name);
        unawaited(_addFile(f.path!, f.name, img));
      }
    }
  }

  Future<void> _toggleMic() async {
    if (_recording) {
      final path = await _rec.stop();
      final secs = DateTime.now().difference(_recStart ?? DateTime.now()).inSeconds;
      setState(() {
        _recording = false;
        _transcribing = path != null;
      });
      if (path == null) return;
      try {
        final r = await _api.upload('transcribe', 'audio', path, filename: 'ses.m4a', fields: {'seconds': '${secs < 1 ? 1 : secs}'});
        final t = _s(r['text']).trim();
        if (t.isNotEmpty) {
          _input.text = _input.text.trim().isEmpty ? t : '${_input.text.trim()} $t';
          _input.selection = TextSelection.collapsed(offset: _input.text.length);
        }
      } catch (e) {
        if (mounted) toolToast(context, e is ArconApiException ? e.message : 'Ses yazıya çevrilemedi');
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }
    if (!await _rec.hasPermission()) {
      if (mounted) toolToast(context, 'Mikrofon izni gerekli');
      return;
    }
    final dir = await getTemporaryDirectory();
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: '${dir.path}/ncb_${DateTime.now().millisecondsSinceEpoch}.m4a');
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _recStart = DateTime.now();
    });
  }

  /* ------------------------------ menüler ------------------------------ */

  Future<void> _modelMenu(NcbSkin k) async {
    final groups = <String>[];
    for (final t in _tiers) {
      if (!groups.contains(t.group)) groups.add(t.group);
    }
    final current = _tierObj;
    String? group;
    final picked = await showModalBottomSheet<NcbTier>(
      context: context,
      backgroundColor: k.popover,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: group == null
                  ? [
                      Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 6), child: Text('Platform seç', style: k.t(12, color: k.fg3))),
                      for (final g in groups)
                        ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          tileColor: current?.group == g ? k.hover : null,
                          leading: _platformIcon(g, k, selected: current?.group == g),
                          title: Text(g, style: k.t(15, weight: FontWeight.w500)),
                          subtitle: current?.group == g ? Text(current!.label, style: k.t(12, color: k.fg3)) : null,
                          trailing: Icon(Icons.chevron_right_rounded, color: k.fg3),
                          onTap: () => set(() => group = g),
                        ),
                    ]
                  : [
                      ListTile(
                        leading: Icon(Icons.chevron_left_rounded, color: k.fg),
                        title: Row(children: [_platformIcon(group!, k), const SizedBox(width: 10), Text(group!, style: k.t(15, weight: FontWeight.w600))]),
                        onTap: () => set(() => group = null),
                      ),
                      Divider(height: 1, color: k.line2),
                      for (final t in _tiers.where((t) => t.group == group))
                        ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(t.label, style: k.t(15)),
                          subtitle: Text(t.hint, style: k.t(12, color: k.fg3)),
                          trailing: t.key == _tier ? Icon(Icons.check_rounded, color: k.fg) : null,
                          onTap: () => Navigator.of(ctx).pop(t),
                        ),
                    ],
            ),
          ),
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _tier = picked.key);
    unawaited(_api.post('settings', {'tier': picked.key}).catchError((Object _) => <String, dynamic>{}));
  }

  Widget _platformIcon(String g, NcbSkin k, {bool selected = false}) =>
      NcbPlatformBadge(g, bg: k.hover, fg: k.fg, selected: selected, ring: k.fg3);


  Future<String?> _prompt(NcbSkin k, String title, String initial, {String hint = '', int lines = 1}) async {
    final ctl = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: k.popover,
        title: Text(title, style: k.t(17, weight: FontWeight.w600)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 8,
          style: k.t(15),
          cursorColor: k.fg,
          decoration: InputDecoration(hintText: hint, hintStyle: k.t(15, color: k.fg3)),
          onSubmitted: lines == 1 ? (v) => Navigator.of(ctx).pop(v) : null,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('İptal', style: k.t(14, color: k.fg2))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(ctl.text), child: Text('Kaydet', style: k.t(14, weight: FontWeight.w600))),
        ],
      ),
    );
    ctl.dispose();
    return r;
  }


  /* ------------------------------ arayüz (ARCONNECT görünümü) ------------------------------ */

  static const _suggestions = [
    (CupertinoIcons.mail, 'Profesyonel bir e-posta taslağı yazmama yardım et'),
    (CupertinoIcons.list_bullet, 'Verimli bir toplantı gündemi hazırla'),
    (CupertinoIcons.chart_bar, 'Bir sunum için 5 slaytlık plan çıkar'),
    (CupertinoIcons.chat_bubble_text, 'Bir müşteri şikâyetine kibar bir yanıt yaz'),
    (CupertinoIcons.photo, 'Etkileyici parfüm standı için görsel üret'),
  ];

  static const _privateSuggestions = [
    (CupertinoIcons.heart, 'Bir tartışmadan sonra ne söyleyeceğimi bulmama yardım et'),
    (CupertinoIcons.sun_max, 'Bana uygun olan bir sabah rutini bulmama yardımcı ol'),
    (CupertinoIcons.money_dollar_circle, 'Bütçe oluşturma konusunda yardıma ihtiyacım var'),
    (CupertinoIcons.bandage, 'Sağlığımla ilgili bir sorum var'),
    (CupertinoIcons.lightbulb, 'Kimsenin haberi olmadan bir sürpriz planlamama yardım et'),
  ];

  String get _greeting {
    final h = DateTime.now().hour;
    final hello = h < 5 ? 'İyi geceler' : (h < 12 ? 'Günaydın' : (h < 18 ? 'İyi günler' : 'İyi akşamlar'));
    final first = _userName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? hello : '$hello, $first';
  }

  NcbSkin _skin(TalkColors c) => NcbSkin.talk(
        dark: c.dark,
        ink: c.bubbleInInk,
        muted: c.muted,
        line: c.rowLine,
        bubble: c.bubbleIn,
        pop: c.popBg,
        accent: c.accent,
        accentFg: c.accentContrast,
      );

  Future<void> _history() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => NcbHistoryScreen(api: _api)));
    if (id == null || !mounted) return;
    if (id.isEmpty) {
      _newChat();
    } else {
      unawaited(_openConv(id));
    }
    unawaited(_loadSide());
  }

  void _openPrivate() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ArconAiScreen(session: widget.session, title: widget.title, private: true),
      ));

  void _howPrivate() => showCupertinoDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Gizli sohbet'),
          content: const Text('Bu sohbet geçmişte görünmez. Ekrandan çıktığında mesajlar sunucudan silinir.'),
          actions: [CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final screen = Builder(builder: (context) {
      final c = TalkColors.of(context);
      final k = _skin(c);
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          key: _scaffold,
          backgroundColor: widget.private ? const Color(0xFF0A0A0A) : c.msgBg,
          body: Column(children: [
            Container(color: c.chatHead, height: MediaQuery.paddingOf(context).top),
            _head(c, k),
            Expanded(
              child: GestureDetector(
                onTap: () => _focus.unfocus(),
                child: _body(c, k),
              ),
            ),
            if (_error != null && _me == null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center, style: talkText(14, FontWeight.w500, TalkColors.danger))),
            _attachStrip(c, k),
            _composer(c, k),
          ]),
        ),
      );
    });
    if (!widget.private) return screen;
    return Theme(data: arconTheme(Brightness.dark, mono: true), child: screen);
  }

  // ---------- başlık ----------

  Widget _head(TalkColors c, NcbSkin k) {
    final glass = BoxDecoration(
      color: c.dark ? const Color(0xFF1C1C1E) : Colors.white,
      border: Border.all(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE6E6E8)),
      boxShadow: c.dark ? null : const [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 3))],
    );
    Widget circleBtn(Widget child, VoidCallback onTap, String tip) => Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(width: 44, height: 44, alignment: Alignment.center, decoration: glass.copyWith(shape: BoxShape.circle), child: child),
          ),
        );
    final tier = _tierObj;
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: c.chatHead,
      child: Row(children: [
        circleBtn(Icon(widget.private ? CupertinoIcons.xmark : CupertinoIcons.chevron_left, size: 22, color: c.ink), () => Navigator.of(context).maybePop(),
            widget.private ? 'Gizli sohbeti kapat' : 'Geri'),
        const SizedBox(width: 10),
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.dark ? const Color(0xFF1C1C1E) : Colors.white, shape: BoxShape.circle),
          child: const ArconAiLogo(size: 30),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _tiers.isEmpty ? null : () => _modelMenu(k),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Flexible(child: Text('ARCON AI', maxLines: 1, style: talkText(17, FontWeight.w600, c.ink, height: 1.25))),
                const SizedBox(width: 4),
                Icon(CupertinoIcons.checkmark_seal_fill, size: 16, color: c.ink),
              ]),
              if (tier != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(
                      '${tier.group} · ${tier.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: talkText(12.5, FontWeight.w400, c.muted),
                    ),
                  ),
                  if (_tiers.length > 1) Icon(CupertinoIcons.chevron_down, size: 11, color: c.muted),
                ]),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        if (widget.private)
          PopupMenuButton<String>(
            tooltip: 'Diğer',
            color: c.popBg,
            offset: const Offset(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              if (v == 'end') Navigator.of(context).maybePop();
              if (v == 'how') _howPrivate();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'how', child: Text('Nasıl çalışır?', style: talkText(16, FontWeight.w400, c.ink))),
              PopupMenuItem(value: 'end', child: Text('Gizli sohbeti bitir', style: talkText(16, FontWeight.w400, TalkColors.danger))),
            ],
            child: IgnorePointer(child: circleBtn(Icon(Icons.more_horiz, size: 24, color: c.ink), () {}, 'Diğer')),
          )
        else
          Container(
            height: 44,
            decoration: glass.copyWith(borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Sohbet geçmişi', onPressed: _me == null ? null : _history, icon: Icon(CupertinoIcons.clock, size: 24, color: c.ink)),
              IconButton(tooltip: 'Gizli sohbet', onPressed: _me == null ? null : _openPrivate, icon: TalkPrivateChatIcon(size: 24, color: c.ink)),
            ]),
          ),
      ]),
    );
  }

  // ---------- içerik ----------

  Widget _card(TalkColors c, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: c.dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _streaming || _me == null ? null : () => _send(text: text),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(children: [
                Icon(icon, size: 22, color: c.ink),
                const SizedBox(width: 14),
                Expanded(child: Text(text, style: talkText(16, FontWeight.w400, c.ink, height: 1.3))),
              ]),
            ),
          ),
        ),
      );

  Widget _body(TalkColors c, NcbSkin k) {
    if (_me == null && _error == null) return Center(child: CupertinoActivityIndicator(color: c.muted));
    if (_loadingConv) return Center(child: CupertinoActivityIndicator(color: c.muted));
    if (_messages.isEmpty) return widget.private ? _privateWelcome(c) : _welcome(c);
    final items = _messages.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: items.length + 1,
      itemBuilder: (_, i) => i == items.length ? _intro(c) : _bubble(c, k, items[i]),
    );
  }

  Widget _welcome(TalkColors c) => ListView(padding: const EdgeInsets.fromLTRB(20, 48, 20, 24), children: [
        const Center(child: ArconAiLogo(size: 96, animated: true)),
        const SizedBox(height: 22),
        Text(_greeting, textAlign: TextAlign.center, style: talkText(26, FontWeight.w700, c.ink, letterSpacing: -0.3)),
        const SizedBox(height: 32),
        for (final (icon, text) in _suggestions) _card(c, icon, text),
      ]);

  Widget _privateWelcome(TalkColors c) => ListView(padding: const EdgeInsets.fromLTRB(20, 56, 20, 24), children: [
        Center(
          child: Stack(alignment: Alignment.center, children: [
            Icon(CupertinoIcons.lock_fill, size: 58, color: c.ink),
            Padding(padding: const EdgeInsets.only(top: 16), child: Icon(CupertinoIcons.sparkles, size: 20, color: c.accentContrast)),
          ]),
        ),
        const SizedBox(height: 22),
        Text('Bu sohbeti yalnızca siz görebilirsiniz', textAlign: TextAlign.center, style: talkText(23, FontWeight.w700, c.ink, letterSpacing: -0.3)),
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            onTap: _howPrivate,
            child: Text('Nasıl çalışır?', style: talkText(17, FontWeight.w600, c.ink).copyWith(decoration: TextDecoration.underline)),
          ),
        ),
        const SizedBox(height: 48),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(10)),
            child: Text('Ekrandan çıktığınızda mesajlar silinir.', style: talkText(13.5, FontWeight.w400, c.muted)),
          ),
        ),
        const SizedBox(height: 26),
        for (final (icon, text) in _privateSuggestions) _card(c, icon, text),
      ]);

  /// İlk mesajın üstü: gün ve yapay zekâ uyarısı
  Widget _intro(TalkColors c) => Column(children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: c.dark ? const Color(0xFF1C1C1E) : Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text(_dayLabel(), style: talkText(13, FontWeight.w600, c.ink)),
        ),
        if (!widget.private)
          Container(
            margin: const EdgeInsets.fromLTRB(30, 0, 30, 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFFDFDFC), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Mesajlar yapay zekâ tarafından oluşturulur. Bazı mesajlar yanlış veya eksik olabilir.',
              textAlign: TextAlign.center,
              style: talkText(13.5, FontWeight.w400, c.ink, height: 1.4),
            ),
          ),
      ]);

  DateTime? _msgTime(NcbMsg m) => DateTime.tryParse((m.createdAt ?? '').replaceFirst(' ', 'T'));

  String _dayLabel() {
    final first = _messages.map(_msgTime).whereType<DateTime>().firstOrNull;
    if (first == null) return 'Bugün';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(first.year, first.month, first.day)).inDays;
    if (days <= 0) return 'Bugün';
    if (days == 1) return 'Dün';
    return talkDayLabel(first);
  }

  Widget _bubble(TalkColors c, NcbSkin k, NcbMsg m) {
    final w = MediaQuery.sizeOf(context).width;
    if (m.isUser) {
      final t = _msgTime(m) ?? (m.id == null ? DateTime.now() : null);
      final time = t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final atts = m.list('attachments');
      if (m.text.isEmpty && atts.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 48),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onLongPress: () => _userActions(c, k, m),
            child: Container(
              constraints: BoxConstraints(maxWidth: w * 0.8),
              padding: EdgeInsets.fromLTRB(atts.any((a) => a['kind'] == 'image') ? 4 : 14, atts.any((a) => a['kind'] == 'image') ? 4 : 9, 10, 7),
              decoration: BoxDecoration(
                color: c.bubbleOut,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(5),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                for (final a in atts)
                  if (a['kind'] == 'image')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: () => ncbOpenImage(context, _api, _s(a['id']), _s(a['name'])),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: a['local_path'] != null
                              ? Image.file(File(_s(a['local_path'])), width: w * 0.62, fit: BoxFit.cover, cacheWidth: 900)
                              : CachedNetworkImage(imageUrl: _api.fileUrl(_s(a['id'])), httpHeaders: _api.headers, width: w * 0.62, fit: BoxFit.cover, memCacheWidth: 900),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: () => ncbDownloadAndShare(context, _api, _s(a['id']), _s(a['name'])),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          ncbFileIcon(_s(a['name']), _s(a['kind']), 28),
                          const SizedBox(width: 8),
                          Flexible(child: Text(_s(a['name']), overflow: TextOverflow.ellipsis, style: talkText(14, FontWeight.w500, c.bubbleOutInk))),
                        ]),
                      ),
                    ),
                Padding(
                  padding: EdgeInsets.only(left: atts.any((a) => a['kind'] == 'image') ? 10 : 0),
                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, alignment: WrapAlignment.end, spacing: 8, children: [
                    if (m.text.isNotEmpty) Text(m.text, style: talkText(16.5, FontWeight.w400, c.bubbleOutInk, height: 1.35)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(time, style: talkText(11.5, FontWeight.w400, c.bubbleOutInk.withValues(alpha: 0.6))),
                      const SizedBox(width: 3),
                      TalkIcon(TalkSvg.ticks, width: 16, height: 11, color: c.bubbleOutInk.withValues(alpha: 0.6)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }
    final lastAssistant = _messages.lastWhere((x) => !x.isUser, orElse: () => m);
    final hasContent = m.text.isNotEmpty || m.list('images').isNotEmpty || m.list('files').isNotEmpty || m.list('actions').isNotEmpty ||
        m.list('connects').isNotEmpty || _s(m.d['error']).isNotEmpty || _s(m.d['thinking']).isNotEmpty || m.list('steps').isNotEmpty;
    // Görsel üretilirken ARCONNECT'teki nokta animasyonu (balon dışında, solda)
    final loader = m.imageLoaders.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 10, right: 28, left: 4),
            child: Align(alignment: Alignment.centerLeft, child: AiImageGeneratingCard(size: (w * 0.72).clamp(220.0, 300.0))),
          );
    // Bekleme / araç durumu: balonsuz kısa yazı
    if (!hasContent) {
      if (loader != null) return loader;
      if (!m.streaming) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 48, left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: m.status.isEmpty || m.status == '…'
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: c.bubbleIn, borderRadius: BorderRadius.circular(20)),
                  child: _TypingDots(color: c.muted),
                )
              : NcbShimmerText(m.status, skin: k, size: 14),
        ),
      );
    }
    final bubbleW = w * 0.86;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ?loader,
      Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: bubbleW),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            decoration: BoxDecoration(color: c.bubbleIn, borderRadius: BorderRadius.circular(20)),
            child: NcbAssistantMessage(
              key: ObjectKey(m),
              msg: m,
              skin: k,
              api: _api,
              inBubble: true,
              contentWidth: bubbleW - 32,
              isLast: identical(m, lastAssistant) && !_streaming,
              onRegenerate: () => _send(mode: 'regenerate'),
              onEditImage: (id, name) {
                setState(() => _editImage = (id: id, name: name));
                _focus.requestFocus();
              },
            ),
          ),
        ),
      ),
    ]);
  }

  Future<void> _userActions(TalkColors c, NcbSkin k, NcbMsg m) async {
    final a = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          if (m.text.isNotEmpty) CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'copy'), child: const Text('Kopyala')),
          if (m.id != null && m.text.isNotEmpty && !_streaming) CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'edit'), child: const Text('Düzenle ve yeniden gönder')),
        ],
        cancelButton: CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (!mounted || a == null) return;
    if (a == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) talkToast(context, 'Kopyalandı');
    } else if (a == 'edit') {
      final t = await _prompt(k, 'Mesajı düzenle', m.text, lines: 3);
      if (t != null && t.trim().isNotEmpty) unawaited(_send(mode: 'edit', text: t.trim(), messageId: m.id));
    }
  }

  // ---------- ekler (yazma alanının üstü) ----------

  Widget _attachStrip(TalkColors c, NcbSkin k) {
    if (_pending.isEmpty && _editImage == null) return const SizedBox.shrink();
    return Container(
      color: c.composerArea,
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        children: [
          if (_editImage != null) _editChip(k),
          for (final p in _pending) _pendingChip(k, p),
        ],
      ),
    );
  }

  Widget _editChip(NcbSkin k) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(fit: StackFit.expand, children: [
                  CachedNetworkImage(imageUrl: _api.fileUrl(_editImage!.id), httpHeaders: _api.headers, fit: BoxFit.cover, memCacheWidth: 168),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: const Text('Düzenle', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
                ]),
              ),
            ),
            Positioned(right: -6, top: -6, child: _x(k, () => setState(() => _editImage = null))),
          ],
        ),
      );

  Widget _pendingChip(NcbSkin k, _Pending p) {
    final child = p.isImage
        ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(p.path), width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168))
        : Container(
            height: 56,
            constraints: const BoxConstraints(maxWidth: 210),
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            decoration: BoxDecoration(color: k.bubble, borderRadius: BorderRadius.circular(14), border: Border.all(color: k.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ncbFileIcon(p.name),
              const SizedBox(width: 10),
              Flexible(child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: k.t(13, weight: FontWeight.w500))),
            ]),
          );
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (p.uploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: CupertinoActivityIndicator()),
              ),
            ),
          Positioned(right: -6, top: -6, child: _x(k, () {
            setState(() => _pending.remove(p));
            if (p.id != null) unawaited(_api.post('remove_upload', {'id': p.id}).catchError((Object _) => <String, dynamic>{}));
          })),
        ],
      ),
    );
  }

  Widget _x(NcbSkin k, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: k.fg, shape: BoxShape.circle),
          child: Icon(Icons.close_rounded, size: 13, color: k.bubble),
        ),
      );

  // ---------- yazma alanı (ARCONNECT sohbet düzeni) ----------

  Widget _composerIcon(TalkColors c, IconData icon, String tip, VoidCallback? onTap, {double size = 26}) => Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(width: 44, height: 40, child: Center(child: Icon(icon, size: size, color: onTap == null ? c.muted : c.ink))),
        ),
      );

  Future<void> _camera() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 88);
    if (x != null) unawaited(_addFile(x.path, x.name, true));
  }

  Widget _composer(TalkColors c, NcbSkin k) {
    final bottomPad = MediaQuery.paddingOf(context).bottom * (MediaQuery.viewInsetsOf(context).bottom > 0 ? 0 : 1);
    final empty = _input.text.trim().isEmpty && _pending.isEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 6, 8, 8 + bottomPad),
      color: c.composerArea,
      child: _recording || _transcribing
          ? Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                if (_recording) Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFE11D48), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                  child: _recording
                      ? Text('Dinliyorum… bitince gönder\'e dokun', style: talkText(15, FontWeight.w400, c.muted))
                      : NcbShimmerText('Yazıya çevriliyor…', skin: k),
                ),
                if (_recording)
                  GestureDetector(
                    onTap: _toggleMic,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      child: Icon(Icons.send_rounded, size: 22, color: c.accentContrast),
                    ),
                  ),
              ]),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _composerIcon(c, Icons.add, 'Ekle', _streaming || _me == null ? null : () => _attachMenu(k), size: 30),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                    decoration: BoxDecoration(
                      color: c.composerBar,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: c.composerBorder, width: 0.6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 9, 10, 9),
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        enabled: !_streaming && _me != null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                        style: talkText(16.5, FontWeight.w400, c.ink, height: 1.3),
                        cursorColor: c.ink,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          hintText: _editImage != null ? 'Görselde neyi değiştirelim?' : (widget.private ? "ARCON AI'a gizli olarak sorun" : null),
                          hintMaxLines: 1,
                          hintStyle: talkText(14, FontWeight.w400, c.muted, height: 1.2),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_streaming)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: 'Durdur',
                      child: GestureDetector(
                        onTap: _stop,
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                          child: Icon(CupertinoIcons.stop_fill, size: 18, color: c.accentContrast),
                        ),
                      ),
                    ),
                  )
                else ...[
                  if (empty) _composerIcon(c, CupertinoIcons.camera, 'Kamera', _me == null ? null : _camera),
                  Padding(
                    padding: EdgeInsets.only(left: empty ? 2 : 8),
                    child: Tooltip(
                      message: empty ? 'Sesli mesaj' : 'Gönder',
                      child: GestureDetector(
                        onTap: empty ? (_voice ? _toggleMic : null) : (_canSend ? () => _send() : null),
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
                ],
              ],
            ),
    );
  }
}

/// "Yazıyor" üç nokta.
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: 0.35 + 0.65 * (1 - ((_a.value * 3 - i) % 3 / 3 - 0.0).clamp(0.0, 1.0)),
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
              ),
            ),
        ]),
      );
}

/// ARCON AI sohbet geçmişi (ARCONNECT'teki gibi): ara, aç, yeniden adlandır, sil.
/// Seçilen sohbetin kimliğini döner ('' = yeni sohbet).
class NcbHistoryScreen extends StatefulWidget {
  const NcbHistoryScreen({super.key, required this.api});
  final NcbApi api;

  @override
  State<NcbHistoryScreen> createState() => _NcbHistoryScreenState();
}

class _NcbHistoryScreenState extends State<NcbHistoryScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _q = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = _q.trim().isEmpty ? await widget.api.get('conversations') : await widget.api.get('search', {'q': _q.trim()});
      final list = (r[_q.trim().isEmpty ? 'conversations' : 'results'] as List? ?? const []).whereType<Map>();
      if (mounted) setState(() => _items = [for (final x in list) x.cast<String, dynamic>()]);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Sohbetler yüklenemedi.');
    }
  }

  Future<void> _delete(Map<String, dynamic> conv) async {
    final prev = List<Map<String, dynamic>>.from(_items ?? const []);
    setState(() => _items = [...prev]..remove(conv));
    try {
      await widget.api.post('delete', {'id': conv['id']});
    } on ArconApiException catch (e) {
      if (mounted) {
        setState(() => _items = prev);
        talkToast(context, e.message, error: true);
      }
    }
  }

  Future<void> _actions(Map<String, dynamic> conv) async {
    final pinned = conv['pinned'] == true;
    final a = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(_s(conv['title'])),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'pin'), child: Text(pinned ? 'Sabitlemeyi kaldır' : 'Sabitle')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'rename'), child: const Text('Yeniden adlandır')),
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Sil')),
        ],
        cancelButton: CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (!mounted || a == null) return;
    try {
      if (a == 'delete') {
        await _delete(conv);
        return;
      }
      if (a == 'pin') {
        await widget.api.post('pin', {'id': conv['id'], 'pinned': !pinned});
        await _load();
        return;
      }
      final ctrl = TextEditingController(text: _s(conv['title']));
      final name = await showCupertinoDialog<String>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Yeniden adlandır'),
          content: Padding(padding: const EdgeInsets.only(top: 10), child: CupertinoTextField(controller: ctrl, autofocus: true)),
          actions: [
            CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Kaydet')),
          ],
        ),
      );
      if (name == null || name.isEmpty) return;
      await widget.api.post('rename', {'id': conv['id'], 'title': name});
      await _load();
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message, error: true);
    }
  }

  String _when(String? iso) {
    final d = DateTime.tryParse((iso ?? '').replaceFirst(' ', 'T'));
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    String two(int n) => n.toString().padLeft(2, '0');
    if (days == 0) return '${two(d.hour)}:${two(d.minute)}';
    if (days < 7) return talkDayLabel(d);
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final items = _items;
    return Scaffold(
      backgroundColor: c.rail,
      appBar: AppBar(
        backgroundColor: c.rail,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text('Sohbet geçmişi', style: talkText(17, FontWeight.w600, c.ink)),
        actions: [
          IconButton(tooltip: 'Yeni sohbet', onPressed: () => Navigator.pop(context, ''), icon: Icon(CupertinoIcons.square_pencil, color: c.ink)),
        ],
      ),
      body: Column(children: [
        Container(
          height: 40,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: c.searchBg, borderRadius: BorderRadius.circular(999)),
          child: Row(children: [
            Icon(CupertinoIcons.search, size: 20, color: c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (v) {
                  _q = v;
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _load);
                },
                style: talkText(17, FontWeight.w400, c.ink),
                cursorColor: c.ink,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Sohbetlerde ara',
                  hintStyle: talkText(17, FontWeight.w400, c.muted),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: items == null
              ? Center(
                  child: _error == null
                      ? CupertinoActivityIndicator(color: c.muted)
                      : Text(_error!, textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
                )
              : items.isEmpty
                  ? Center(child: Text(_q.isEmpty ? 'Henüz sohbet yok' : 'Sonuç yok', style: talkText(15, FontWeight.w400, c.muted)))
                  : RefreshIndicator.adaptive(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final conv = items[i];
                          return TalkSwipeActions(
                            key: ValueKey('ai-hist-${conv['id']}'),
                            actionWidth: 88,
                            actions: [
                              TalkSwipeAction(icon: CupertinoIcons.trash_fill, label: 'Sil', color: const Color(0xFFE11D48), onTap: () => _delete(conv)),
                            ],
                            child: InkWell(
                              onTap: () => Navigator.pop(context, _s(conv['id'])),
                              onLongPress: () => _actions(conv),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 20),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
                                  decoration: BoxDecoration(color: c.rail, border: Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
                                  child: Row(children: [
                                    Icon(conv['pinned'] == true ? CupertinoIcons.pin_fill : CupertinoIcons.chat_bubble, size: 20, color: c.muted),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(_s(conv['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(16.5, FontWeight.w500, c.ink)),
                                        if (_s(conv['snippet']).isNotEmpty)
                                          Text(_s(conv['snippet']), maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(13.5, FontWeight.w400, c.muted)),
                                      ]),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(_when(_s(conv['updated_at'])), style: talkText(14, FontWeight.w400, c.muted)),
                                  ]),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
