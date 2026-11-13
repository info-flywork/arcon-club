import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';
import 'deck_editor.dart';

String _s(Object? v) => v == null ? '' : '$v';

const _base = 'presentation-creater/';
const _imgExt = ['png', 'jpg', 'jpeg', 'webp', 'gif'];

/// Sunum Oluşturucu — webdeki presentation-creater: sohbet ederek sunum iste, değiştir, aç.
/// Planlama `chat.php`, üretim `api.php` iş sistemi (process + status) ile yapılır; sunumun kendisi HTML'dir.
class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});

  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  String? _chatId;
  List<Map<String, dynamic>> _turns = [];
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  bool _sending = false;
  int? _watching;
  String _phase = '';
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<PlatformFile> _files = [];

  // seçenekler
  int _pages = 0; // 0 = otomatik
  String _lang = '';
  bool _arcon = false;

  @override
  void initState() {
    super.initState();
    // Yalnızca gönder düğmesi değişince yeniden kur (her tuşta tüm sohbet ekranını kurma)
    var wasEmpty = _input.text.trim().isEmpty;
    _input.addListener(() {
      final empty = _input.text.trim().isEmpty;
      if (empty != wasEmpty) setState(() => wasEmpty = empty);
    });
    _start();
  }

  @override
  void dispose() {
    _watching = null;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ArconApi get _api => widget.session.api;

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  void _fallback() =>
      openWebFallback(context, session: widget.session, config: widget.config, title: widget.title, path: widget.webPath, replace: true);

  Future<void> _start() async {
    try {
      final j = await _api.webCall('${_base}chat.php', query: {'action': 'chats'});
      if (!mounted) return;
      setState(() {
        _chats = [for (final c in ((j['items'] as List?) ?? const []).whereType<Map>()) c.cast<String, dynamic>()];
        _loading = false;
      });
    } on ArconApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.code == 'tool_unavailable') _fallback();
    }
  }

  Future<void> _openChat(String id) async {
    setState(() {
      _chatId = id;
      _turns = [];
      _loading = true;
    });
    try {
      final j = await _api.webCall('${_base}chat.php', query: {'action': 'chat', 'id': id});
      if (!mounted || _chatId != id) return;
      setState(() {
        _turns = [for (final t in ((j['turns'] as List?) ?? const []).whereType<Map>()) t.cast<String, dynamic>()];
        _loading = false;
      });
      _scrollToEnd();
      final pending = _turns.where((t) => t['status'] == 'pending' && _s(t['job']).isNotEmpty).lastOrNull;
      if (pending != null) unawaited(_watch(pending));
    } on ArconApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _toast(e.message);
      }
    }
  }

  void _newChat() {
    if (_sending || _watching != null) return;
    setState(() {
      _chatId = null;
      _turns = [];
      _files.clear();
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.of(context, Motion.normal), curve: Curves.easeOutCubic);
    });
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    setState(() {
      for (final f in files) {
        if (f.path != null && _files.length < 6) _files.add(f);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (_sending || _watching != null || (text.isEmpty && _files.isEmpty)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final files = List<PlatformFile>.of(_files);
    setState(() {
      _sending = true;
      _turns = [..._turns, {'id': -1, 'prompt': text, 'status': 'sending', 'kind': '', 'refs': const []}];
      _files.clear();
      _input.clear();
    });
    _scrollToEnd();
    try {
      final j = await _api.webCall(
        '${_base}chat.php',
        fields: {
          'action': 'send',
          'prompt': text,
          'chat_id': ?_chatId,
          if (_pages > 0) 'opt_pages': '$_pages',
          if (_lang.isNotEmpty) 'opt_lang': _lang,
          if (_arcon) 'opt_design': 'arcon',
        },
        files: [
          for (final f in files)
            (_imgExt.contains(f.name.split('.').last.toLowerCase()) ? 'refs[]' : 'docs[]', f.path!),
        ],
        timeout: const Duration(minutes: 3),
      );
      final turn = (j['turn'] as Map?)?.cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _chatId = _s(j['chat_id']).isEmpty ? _chatId : _s(j['chat_id']);
        _turns = [..._turns.where((t) => t['id'] != -1), ?turn];
      });
      if (j['new_chat'] == true) unawaited(_start());
      _scrollToEnd();
      if (turn != null && turn['status'] == 'pending' && _s(turn['job']).isNotEmpty) unawaited(_watch(turn));
    } on ArconApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'tool_unavailable') {
        _fallback();
        return;
      }
      setState(() => _turns = [..._turns.where((t) => t['id'] != -1), {'id': -2, 'prompt': text, 'status': 'error', 'error': e.message, 'kind': ''}]);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Sunum işini başlat ve bitene kadar izle (webdeki watchTurn).
  Future<void> _watch(Map<String, dynamic> turn) async {
    final id = turn['id'] as int?;
    final job = _s(turn['job']);
    if (id == null || job.isEmpty) return;
    final chat = _chatId;
    setState(() {
      _watching = id;
      _phase = 'Sunum hazırlanıyor…';
    });
    unawaited(_api.webCall('${_base}api.php', query: {'action': 'process', 'job': job}, fields: const {}).catchError((_) => <String, dynamic>{}));
    final started = DateTime.now();
    while (mounted && _watching == id && chat == _chatId) {
      await Future<void>.delayed(const Duration(seconds: 4));
      if (!mounted || _watching != id) return;
      try {
        final st = await _api.webCall('${_base}api.php', query: {'action': 'status', 'job': job});
        final status = _s(st['status']);
        if (status == 'done') break;
        final phase = _s(st['phase']);
        if (mounted) setState(() => _phase = _phaseLabel(phase));
      } on ArconApiException catch (e) {
        if (e.code == 'tool_error') break; // iş hata ile bitti
      }
      if (DateTime.now().difference(started).inMinutes >= 20) break;
    }
    if (!mounted || chat != _chatId) return;
    try {
      final j = await _api.webCall('${_base}chat.php', query: {'action': 'turn', 'id': '$id'});
      final t = (j['turn'] as Map?)?.cast<String, dynamic>();
      if (t != null && mounted) {
        setState(() => _turns = [for (final x in _turns) x['id'] == id ? t : x]);
        if (t['status'] == 'done') HapticFeedback.mediumImpact();
      }
    } on ArconApiException catch (_) {}
    if (mounted) {
      setState(() => _watching = null);
      _scrollToEnd();
      unawaited(_start());
    }
  }

  static String _phaseLabel(String p) => switch (p) {
        'queued' || 'pending' => 'Sırada bekliyor…',
        'planning' || 'outline' => 'İçerik planlanıyor…',
        'writing' || 'html' || 'generating' || 'running' => 'Sayfalar tasarlanıyor…',
        'images' || 'media' => 'Görseller hazırlanıyor…',
        'saving' || 'publish' => 'Sunum kaydediliyor…',
        _ => 'Sunum hazırlanıyor…',
      };

  String _abs(String u) => u.startsWith('http') ? u : _api.webUrl('$_base${u.replaceFirst(RegExp(r'^\./'), '')}').toString();

  void _openDeck(Map<String, dynamic> deck) {
    final url = _abs(_s(deck['url']));
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _DeckViewer(url: url, title: _s(deck['title']))));
  }

  List<Map<String, dynamic>> get _deckTurns => _turns.where((t) => t['status'] == 'done' && t['deck'] is Map && _s(t['id']) != '' && (t['id'] as num) > 0).toList();

  void _appendTurn(Map<String, dynamic>? turn) {
    if (turn == null || !mounted) return;
    setState(() => _turns = [..._turns, turn]);
    _scrollToEnd();
  }

  Future<void> _editDeck(Map<String, dynamic> t, Map<String, dynamic> deck) async {
    if (_sending || _watching != null) {
      _toast('Sunum hazırlanırken düzenleme yapılamaz');
      return;
    }
    final turn = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => DeckEditorScreen(session: widget.session, base: _base, turnId: (t['id'] as num).toInt(), title: _s(deck['title'])),
    ));
    _appendTurn(turn);
    if (turn != null && mounted) _toast('Yeni sürüm kaydedildi');
  }

  Future<void> _restore(Map<String, dynamic> t, int no) async {
    if (_sending || _watching != null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('$no. sürüme dönülsün mü?'),
        content: const Text('Bu sürüm sohbetin sonuna güncel sürüm olarak eklenir. Diğer sürümler silinmez.'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Bu sürüme dön')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _api.webCall('${_base}chat.php', fields: {'action': 'restore_version', 'turn': '${t['id']}', 'version': '$no'});
      _appendTurn((r['turn'] as Map?)?.cast<String, dynamic>());
    } on ArconApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _openHistory() async {
    final c = ArconMono.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bg,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Sunumlarım', style: c.text(18, weight: FontWeight.w800))),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _newChat();
                    },
                    icon: Icon(Icons.add_rounded, color: c.ink),
                    label: Text('Yeni', style: c.text(14, weight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            if (_chats.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Text('Henüz sunum yok.', textAlign: TextAlign.center, style: c.text(14, color: c.muted)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + MediaQuery.paddingOf(ctx).bottom),
                  children: [for (final it in _chats) _chatTile(c, it, () => Navigator.of(ctx).pop())],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chatTile(ArconMono c, Map<String, dynamic> it, [VoidCallback? before]) {
    final thumb = _s(it['thumb']);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: _chatId == _s(it['id']),
      selectedTileColor: c.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 36,
          child: thumb.isEmpty
              ? Container(color: c.field, child: Icon(Icons.slideshow_rounded, size: 18, color: c.muted))
              : CachedNetworkImage(memCacheWidth: 160, imageUrl: _abs(thumb), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: c.field)),
        ),
      ),
      title: Text(_s(it['title']).isEmpty ? 'Sunum' : _s(it['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w600)),
      onTap: () {
        before?.call();
        _openChat(_s(it['id']));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final busy = _sending || _watching != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(17, weight: FontWeight.w800))),
                    IconButton(
                      tooltip: 'Yeni sunum',
                      onPressed: _chatId == null || busy ? null : _newChat,
                      icon: Icon(Icons.edit_square, size: 21, color: _chatId == null || busy ? c.faint : c.ink),
                    ),
                    IconButton(tooltip: 'Sunumlarım', onPressed: _openHistory, icon: Icon(Icons.history_rounded, color: c.ink)),
                  ],
                ),
              ),
              Expanded(
                child: SwapFade(
                  child: KeyedSubtree(
                    key: ValueKey(_chatId ?? (_turns.isEmpty ? 'empty' : 'new')),
                    child: _chatId == null && _turns.isEmpty
                        ? _empty(c)
                        : _loading
                            ? const SkeletonChat()
                            : ListView(
                                controller: _scroll,
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                children: [for (final t in _turns) ..._turn(c, t)],
                              ),
                  ),
                ),
              ),
              _composer(c, busy),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(ArconMono c) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.slideshow_rounded, color: c.bg, size: 30),
            ),
          ),
          const SizedBox(height: 16),
          Text('Sunum oluştur', textAlign: TextAlign.center, style: c.text(24, weight: FontWeight.w800, spacing: -0.6)),
          const SizedBox(height: 8),
          Text(
            'Konuyu yaz ya da belge/görsel ekle; sayfa sayfa tasarlanmış bir sunum hazırlayayım. Sonra “3. sayfayı kısalt” gibi yazarak değiştirebilirsin.',
            textAlign: TextAlign.center,
            style: c.text(14.5, color: c.muted, height: 1.5),
          ),
          const SizedBox(height: 20),
          for (final s in const ['2026 pazarlama planı için 8 sayfalık sunum', 'Yeni çalışanlar için şirket tanıtım sunumu', 'Ekteki rapordan yönetim kurulu özeti'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PressScale(
                child: Material(
                  color: c.field,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => s.startsWith('Ekteki') ? _pick() : _send(s),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(s, style: c.text(13.5, weight: FontWeight.w600))),
                          Icon(s.startsWith('Ekteki') ? Icons.attach_file_rounded : Icons.north_east_rounded, size: 16, color: c.faint),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_loading) ...[
            const SizedBox(height: 20),
            const SkeletonList(count: 2, leading: false),
          ] else if (_chats.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(trUpper('Son sunumlar'), style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
            const SizedBox(height: 4),
            for (final it in _chats.take(4)) _chatTile(c, it),
          ],
        ],
      );

  List<Widget> _turn(ArconMono c, Map<String, dynamic> t) {
    final refs = ((t['refs'] as List?) ?? const []).map((e) => '$e').toList();
    final status = _s(t['status']);
    final deck = (t['deck'] as Map?)?.cast<String, dynamic>();
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (refs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in refs.take(6))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: CachedNetworkImage(memCacheWidth: 200, imageUrl: _abs(r), fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: c.field)),
                        ),
                      ),
                  ],
                ),
              ),
            if (_s(t['prompt']).isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: c.ink,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(5),
                  ),
                ),
                child: SelectableText(_s(t['prompt']), style: c.text(15, height: 1.45, color: c.bg)),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.slideshow_rounded, size: 16, color: c.bg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: switch (status) {
                'sending' => _waiting(c, 'İsteğin anlaşılıyor…'),
                'pending' => _waiting(c, _watching == t['id'] ? _phase : 'Sunum hazırlanıyor…'),
                'error' => Text(_s(t['error']).isEmpty ? 'Sunum hazırlanamadı.' : _s(t['error']), style: c.text(14, color: c.danger, height: 1.45)),
                _ when deck != null => _deckCard(c, deck, t),
                _ => Text(_s(t['reply']).isEmpty ? (_s(t['error']).isEmpty ? '—' : _s(t['error'])) : _s(t['reply']), style: c.text(15, height: 1.5)),
              },
            ),
          ],
        ),
      ),
    ];
  }

  Widget _waiting(ArconMono c, String label) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)),
            const SizedBox(width: 10),
            Expanded(child: Text('$label Birkaç dakika sürebilir.', style: c.text(13.5, color: c.muted))),
          ],
        ),
      );

  Widget _deckCard(ArconMono c, Map<String, dynamic> deck, Map<String, dynamic> t) {
    final thumb = _s(deck['thumb']);
    final pages = deck['pages'];
    final versions = _deckTurns;
    final no = versions.indexWhere((v) => v['id'] == t['id']) + 1;
    final isLast = no == versions.length;
    return PressScale(
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDeck(deck),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: thumb.isEmpty
                    ? Container(color: c.ink, child: Icon(Icons.slideshow_rounded, size: 40, color: c.bg))
                    : CachedNetworkImage(memCacheWidth: 1080, 
                        imageUrl: _abs(thumb),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const Shimmer(child: SkeletonBox(radius: 0)),
                        errorWidget: (_, _, _) => Container(color: c.ink, child: Icon(Icons.slideshow_rounded, size: 40, color: c.bg)),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_s(deck['title']).isEmpty ? 'Sunum' : _s(deck['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(15, weight: FontWeight.w800)),
                          Text(
                            [
                              if (versions.length > 1) 'Sürüm $no${isLast ? ' · güncel' : ''}',
                              if (t['kind'] == 'revise') 'Güncellendi',
                              if (t['kind'] == 'edit') 'Düzenlendi',
                              if (pages != null) '$pages sayfa',
                            ].join(' · '),
                            style: c.text(12, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    if (!isLast && no > 0)
                      IconButton(
                        tooltip: 'Bu sürüme dön',
                        onPressed: () => _restore(t, no),
                        icon: Icon(Icons.history_rounded, color: c.ink),
                      ),
                    if (no > 0)
                      IconButton(
                        tooltip: 'Düzenle',
                        onPressed: () => _editDeck(t, deck),
                        icon: Icon(Icons.edit_outlined, color: c.ink),
                      ),
                    Icon(Icons.play_circle_outline_rounded, color: c.ink),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(ArconMono c, bool busy) {
    final canSend = !busy && (_input.text.trim().isNotEmpty || _files.isNotEmpty);
    Widget opt(String label, bool on, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.ink : c.field,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: on ? c.ink : c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 14, color: on ? c.bg : c.muted), const SizedBox(width: 4)],
                  Text(label, style: c.text(12, weight: FontWeight.w700, color: on ? c.bg : c.ink)),
                ],
              ),
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                opt(_pages == 0 ? 'Sayfa: otomatik' : '$_pages sayfa', _pages > 0, () async {
                  final v = await _choose<int>('Sayfa sayısı', [(0, 'Otomatik'), for (final n in const [4, 6, 8, 10, 12, 16]) (n, '$n sayfa')], _pages);
                  if (v != null) setState(() => _pages = v);
                }, icon: Icons.layers_outlined),
                opt(_lang.isEmpty ? 'Dil: otomatik' : _lang.toUpperCase(), _lang.isNotEmpty, () async {
                  final v = await _choose<String>('Dil', const [('', 'Otomatik'), ('tr', 'Türkçe'), ('en', 'İngilizce'), ('de', 'Almanca'), ('fr', 'Fransızca')], _lang);
                  if (v != null) setState(() => _lang = v);
                }, icon: Icons.translate_rounded),
                opt('ARCON şablonu', _arcon, () => setState(() => _arcon = !_arcon), icon: Icons.palette_outlined),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in _files)
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_imgExt.contains(f.name.split('.').last.toLowerCase()) ? Icons.image_outlined : Icons.description_outlined, size: 15, color: c.muted),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, weight: FontWeight.w600)),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _files.remove(f)),
                            child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 16, color: c.muted)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(tooltip: 'Belge / görsel ekle', onPressed: busy ? null : _pick, icon: Icon(Icons.attach_file_rounded, color: c.ink)),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                  style: c.text(15, height: 1.35),
                  cursorColor: c.ink,
                  decoration: c.input(_turns.isEmpty ? 'Ne hakkında sunum istiyorsun?' : 'Değişiklik iste ya da yeni sunum yaz…', null).copyWith(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        isDense: true,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: canSend ? _send : null,
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.fast),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: canSend ? c.ink : c.line, shape: BoxShape.circle),
                  child: busy
                      ? Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: c.bg))
                      : Icon(Icons.arrow_upward_rounded, color: c.bg),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<T?> _choose<T>(String title, List<(T, String)> items, T current) {
    final c = ArconMono.of(context);
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: c.bg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text(title, style: c.text(18, weight: FontWeight.w800))),
              for (final (v, label) in items)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  title: Text(label, style: c.text(15, weight: v == current ? FontWeight.w800 : FontWeight.w500)),
                  trailing: v == current ? Icon(Icons.check_rounded, color: c.ink) : null,
                  onTap: () => Navigator.of(ctx).pop(v),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ============================== Sunum görüntüleyici ============================== */

/// Üretilen sunum (HTML). Yatay çevirince tam ekran izlenir; paylaş/tarayıcıda aç.
class _DeckViewer extends StatefulWidget {
  const _DeckViewer({required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<_DeckViewer> createState() => _DeckViewerState();
}

class _DeckViewerState extends State<_DeckViewer> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
      if (mounted) setState(() => _ready = true);
    }))
    ..loadRequest(Uri.parse(widget.url));
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !landscape,
          bottom: !landscape,
          child: Stack(
            children: [
              Column(
                children: [
                  if (!landscape)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      child: Row(
                        children: [
                          IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                          Expanded(
                            child: Text(widget.title.isEmpty ? 'Sunum' : widget.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            tooltip: 'Tarayıcıda aç (PDF olarak kaydet)',
                            onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
                            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: WebViewWidget(controller: _web)),
                  if (!landscape)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text('Tam ekran için telefonu yan çevir', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                ],
              ),
              if (!_ready) const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
              if (landscape)
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const CircleAvatar(backgroundColor: Colors.black45, child: Icon(Icons.close_rounded, color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
