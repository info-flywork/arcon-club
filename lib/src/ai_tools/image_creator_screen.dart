import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';
import 'image_editor.dart';
import 'tool_common.dart';

String _s(Object? v) => v == null ? '' : '$v';

/// Görsel Üretimi — webdeki image-creater: sohbet ederek görsel üret, değiştir; referans görsel ekle.
/// Uç: image-creater/export.php (POST üretim — akışlı yanıt; GET chats / chat / job).
/// Görüntüleyicide: el ile düzenleyici (kırp, ayarlar, yazı & logo, boyutlar) ve yapay zekâ araçları
/// (işaretle, yorum, arka planı kaldır, sil, yeniden boyutlandır).
class ImageCreatorScreen extends StatefulWidget {
  const ImageCreatorScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});
  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  @override
  State<ImageCreatorScreen> createState() => _ImageCreatorScreenState();
}

class _ImageCreatorScreenState extends State<ImageCreatorScreen> {
  static const _path = 'image-creater/export.php';
  static const _sizes = [('auto', 'Otomatik'), ('1024x1024', 'Kare'), ('1024x1536', 'Dikey'), ('1536x1024', 'Yatay')];

  String? _chatId;
  List<Map<String, dynamic>> _turns = [];
  List<Map<String, dynamic>> _chats = [];
  bool _loading = true;
  bool _busy = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  PlatformFile? _ref;
  String _size = 'auto';

  ArconApi get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    // Yalnızca gönder düğmesi değişince yeniden kur (her tuşta tüm sohbet ekranını kurma)
    var wasEmpty = _input.text.trim().isEmpty;
    _input.addListener(() {
      final empty = _input.text.trim().isEmpty;
      if (empty != wasEmpty) setState(() => wasEmpty = empty);
    });
    _loadChats();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      final j = await _api.webCall(_path, query: {'action': 'chats'});
      if (!mounted) return;
      setState(() {
        _chats = [for (final c in ((j['items'] as List?) ?? const []).whereType<Map>()) c.cast<String, dynamic>()];
        _loading = false;
      });
    } on ArconApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.code == 'tool_unavailable') {
        openWebFallback(context, session: widget.session, config: widget.config, title: widget.title, path: widget.webPath, replace: true);
      }
    }
  }

  Future<void> _openChat(String id) async {
    setState(() {
      _chatId = id;
      _turns = [];
      _loading = true;
    });
    await _reloadChat();
  }

  Future<void> _reloadChat() async {
    final id = _chatId;
    if (id == null) return;
    try {
      final j = await _api.webCall(_path, query: {'action': 'chat', 'id': id});
      if (!mounted || _chatId != id) return;
      setState(() {
        _turns = [for (final t in ((j['turns'] as List?) ?? const []).whereType<Map>()) t.cast<String, dynamic>()];
        _loading = false;
      });
      _scrollToEnd();
      final pending = _turns.where((t) => t['kind'] == 'pending').lastOrNull;
      if (pending != null && !_busy) unawaited(_waitJob(_s(pending['reply'])));
    } on ArconApiException catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bağlantı kesildiyse ya da sohbet sonradan açıldıysa işi bekle.
  Future<void> _waitJob(String jobId) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(jobId)) return;
    setState(() => _busy = true);
    for (var i = 0; i < 100 && mounted; i++) {
      await Future<void>.delayed(const Duration(seconds: 4));
      try {
        final j = await _api.webCall(_path, query: {'action': 'job', 'id': jobId});
        final status = _s((j['job'] as Map?)?['status']);
        if (status == 'done' || status == 'error') break;
      } on ArconApiException catch (_) {
        break;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _reloadChat();
    unawaited(_loadChats());
  }

  void _newChat() {
    if (_busy) return;
    setState(() {
      _chatId = null;
      _turns = [];
      _ref = null;
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.of(context, Motion.normal), curve: Curves.easeOutCubic);
    });
  }

  Future<void> _pickRef() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    final f = files.first;
    if (f.path == null || !RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(f.name)) {
      toolToast(context, 'PNG, JPG ya da WEBP görsel seçin');
      return;
    }
    setState(() => _ref = f);
  }

  Future<void> _send([String? preset, ImageGenOpts? opts]) async {
    final text = (opts?.prompt ?? preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final ref = _ref;
    final history = _turns.where((t) => t['kind'] != 'pending').toList();
    setState(() {
      _busy = true;
      _turns = [..._turns, {'prompt': text, 'kind': 'pending', 'reply': '', 'input_url': '', 'url': '', 'local_ref': opts == null ? ref?.name : null}];
      if (opts == null) {
        _input.clear();
        _ref = null;
      }
    });
    _scrollToEnd();

    String? jobId;
    String? chatId = _chatId;
    String? error;
    try {
      final req = http.MultipartRequest('POST', _api.webUrl(_path))
        ..headers.addAll({'Accept': 'text/event-stream, application/json', if (_api.token != null) 'Authorization': 'Bearer ${_api.token}'})
        ..fields.addAll({
          'prompt': text,
          'stream': '1',
          'history': jsonEncode(history.length > 12 ? history.sublist(history.length - 12) : history),
          'chat_id': ?chatId,
          if (_size != 'auto') 'size': _size,
        });
      if (opts != null) {
        final base = history.lastWhere((t) => _s(t['url']) == opts.imageUrl, orElse: () => const {});
        final ctx = _s(base['image_prompt']).isEmpty ? _s(base['prompt']) : _s(base['image_prompt']);
        req.fields.addAll({
          'mode': 'revise',
          'image_url': opts.imageUrl,
          'force_edit': '1',
          if (ctx.isNotEmpty && opts.file == null) 'context': ctx,
          if (opts.composite) 'composite': '1',
          'size': ?opts.size,
          'aspect': ?opts.aspect,
          if (opts.transparent) 'transparent': '1',
          if (opts.cutout) 'cutout': '1',
        });
        if (opts.file != null) req.files.add(http.MultipartFile.fromBytes('image', opts.file!, filename: opts.fileName));
        if (opts.mask != null) req.files.add(http.MultipartFile.fromBytes('mask', opts.mask!, filename: 'mask.png'));
      } else if (ref?.path != null) {
        req.files.add(await http.MultipartFile.fromPath('image', ref!.path!));
      } else {
        final last = history.lastWhere((t) => _s(t['url']).isNotEmpty, orElse: () => const {});
        if (_s(last['url']).isNotEmpty) {
          req.fields['mode'] = 'auto';
          req.fields['image_url'] = _s(last['url']);
        }
      }
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      if (streamed.statusCode == 401) throw const ArconApiException('tool_unavailable', '');
      // Akış: "data: {...}\n\n" olayları — önce iş/plan, en sonda sonuç
      final body = StringBuffer();
      await for (final chunk in streamed.stream.transform(utf8.decoder).timeout(const Duration(minutes: 6))) {
        body.write(chunk);
        for (final m in RegExp(r'^data: (.+)$', multiLine: true).allMatches(body.toString())) {
          try {
            final ev = jsonDecode(m.group(1)!) as Map<String, dynamic>;
            if (ev['type'] == 'job') {
              jobId = _s(ev['id']);
              if (_s(ev['chat_id']).isNotEmpty) chatId = _s(ev['chat_id']);
            }
            if (ev.containsKey('success')) {
              if (_s(ev['chat_id']).isNotEmpty) chatId = _s(ev['chat_id']);
              if (ev['success'] != true) error = _s(ev['error']).isEmpty ? 'Görsel üretilemedi.' : _s(ev['error']);
            }
          } catch (_) {}
        }
      }
      final raw = body.toString().trim();
      if (raw.startsWith('{')) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        if (_s(j['chat_id']).isNotEmpty) chatId = _s(j['chat_id']);
        if (j['success'] != true) error = _s(j['error']).isEmpty ? 'Görsel üretilemedi.' : _s(j['error']);
      }
    } on ArconApiException catch (e) {
      if (e.code == 'tool_unavailable' && mounted) {
        openWebFallback(context, session: widget.session, config: widget.config, title: widget.title, path: widget.webPath, replace: true);
        return;
      }
    } on Exception {
      // bağlantı kesildi: iş sunucuda sürüyor olabilir
      if (jobId != null && mounted) {
        if (chatId != null) _chatId = chatId;
        unawaited(_waitJob(jobId));
        return;
      }
      error = 'Bağlantı kesildi. Biraz sonra sohbeti yeniden açınca görseli görebilirsin.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) toolToast(context, error);
    if (chatId != null) {
      _chatId = chatId;
      await _reloadChat();
      HapticFeedback.mediumImpact();
    } else {
      setState(() => _turns = _turns.where((t) => t['kind'] != 'pending').toList());
    }
    unawaited(_loadChats());
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
                  Expanded(child: Text('Görsellerim', style: c.text(18, weight: FontWeight.w800))),
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
              Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), child: Text('Henüz görsel yok.', textAlign: TextAlign.center, style: c.text(14, color: c.muted)))
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
          width: 44,
          height: 44,
          child: thumb.isEmpty
              ? Container(color: c.field, child: Icon(Icons.image_outlined, size: 18, color: c.muted))
              : CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover, memCacheWidth: 132, errorWidget: (_, _, _) => Container(color: c.field)),
        ),
      ),
      title: Text(_s(it['title']).isEmpty ? 'Görsel' : _s(it['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w600)),
      onTap: () {
        before?.call();
        _openChat(_s(it['id']));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
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
                      tooltip: 'Yeni görsel',
                      onPressed: _chatId == null || _busy ? null : _newChat,
                      icon: Icon(Icons.edit_square, size: 21, color: _chatId == null || _busy ? c.faint : c.ink),
                    ),
                    IconButton(tooltip: 'Görsellerim', onPressed: _openHistory, icon: Icon(Icons.photo_library_outlined, color: c.ink)),
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
              _composer(c),
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
              child: Icon(Icons.auto_awesome_outlined, color: c.bg, size: 30),
            ),
          ),
          const SizedBox(height: 16),
          Text('Görsel üret', textAlign: TextAlign.center, style: c.text(24, weight: FontWeight.w800, spacing: -0.6)),
          const SizedBox(height: 8),
          Text(
            'Ne istediğini yaz; istersen referans görsel ekle. Sonra “arka planı beyaz yap” gibi yazarak değiştir.',
            textAlign: TextAlign.center,
            style: c.text(14.5, color: c.muted, height: 1.5),
          ),
          const SizedBox(height: 20),
          for (final s in const ['Beyaz zeminde parfüm şişesi, stüdyo ışığı', 'Anneler Günü için Instagram kampanya görseli', 'Mermer masada cilt bakım ürünleri'])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PressScale(
                child: Material(
                  color: c.field,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _send(s),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(s, style: c.text(13.5, weight: FontWeight.w600))),
                          Icon(Icons.north_east_rounded, size: 16, color: c.faint),
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
            Text(trUpper('Son görseller'), style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
            const SizedBox(height: 4),
            for (final it in _chats.take(4)) _chatTile(c, it),
          ],
        ],
      );

  List<Widget> _turn(ArconMono c, Map<String, dynamic> t) {
    final kind = _s(t['kind']);
    final url = _s(t['url']);
    final input = _s(t['input_url']);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (input.isNotEmpty || t['local_ref'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: input.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(imageUrl: input, width: 64, height: 64, fit: BoxFit.cover, memCacheWidth: 192, errorWidget: (_, _, _) => const SizedBox()),
                      )
                    : Text('📎 ${t['local_ref']}', style: c.text(12, color: c.muted)),
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
        padding: const EdgeInsets.only(bottom: 18, right: 32),
        child: kind == 'pending'
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    child: SizedBox(width: 240, height: 240, child: Shimmer(child: SkeletonBox(radius: 0))),
                  ),
                  const SizedBox(height: 8),
                  Text('Görsel hazırlanıyor… 1–2 dakika sürebilir.', style: c.text(12.5, color: c.muted)),
                ],
              )
            : url.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _openViewer(t),
                        child: Hero(
                          tag: url,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              memCacheWidth: 900,
                              placeholder: (_, _) => const SizedBox(width: 240, height: 240, child: Shimmer(child: SkeletonBox(radius: 0))),
                            ),
                          ),
                        ),
                      ),
                      if (_s(t['reply']).isNotEmpty) ...[const SizedBox(height: 8), Text(_s(t['reply']), style: c.text(14, height: 1.45))],
                    ],
                  )
                : Text(_s(t['reply']).isEmpty ? '—' : _s(t['reply']), style: c.text(15, height: 1.5)),
      ),
    ];
  }

  Future<void> _openViewer(Map<String, dynamic> t) async {
    final url = _s(t['url']);
    final base = _s(t['image_prompt']).isEmpty ? _s(t['prompt']) : _s(t['image_prompt']);
    final r = await Navigator.of(context).push<Object>(MaterialPageRoute(
      builder: (_) => _ImageViewer(
        url: url,
        prompt: base,
        busy: _busy,
        logoUrls: [('ARCON lacivert', _api.webUrl('assets/arcon_logo.png').toString()), ('ARCON beyaz', _api.webUrl('assets/arcon_logo_dark.png').toString())],
        onSaveEdit: (png, summary) => _saveEdit(png, summary, url, base),
      ),
    ));
    if (!mounted) return;
    if (r is ImageGenOpts) {
      if (_busy) {
        toolToast(context, 'Görsel üretimi bitince tekrar dene');
      } else {
        unawaited(_send(null, r));
      }
    } else if (r == true) {
      await _reloadChat();
      unawaited(_loadChats());
      HapticFeedback.mediumImpact();
    }
  }

  /// El ile düzenlenen görseli sohbete yeni sürüm olarak kaydeder (webdeki save_edit).
  Future<void> _saveEdit(Uint8List png, String summary, String sourceUrl, String basePrompt) async {
    if (_busy) throw Exception('Görsel üretimi bitince tekrar dene.');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/arcon-edit-${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(png);
    try {
      final j = await _api.webCall(_path,
          fields: {
            'action': 'save_edit',
            'summary': summary,
            'image_prompt': '${basePrompt.isEmpty ? '' : '$basePrompt\n'}[Kullanıcı düzenleyicide elle düzenledi: ${summary.replaceFirst(RegExp(r'^Düzenlendi:\s*'), '')}]',
            'source_url': sourceUrl,
            'chat_id': ?_chatId,
          },
          files: [('image', f.path)],
          timeout: const Duration(minutes: 2));
      if (_s(j['chat_id']).isNotEmpty) _chatId = _s(j['chat_id']);
    } on ArconApiException catch (e) {
      throw Exception(e.message.isEmpty ? 'Kaydedilemedi.' : e.message);
    } finally {
      unawaited(f.delete().catchError((Object _) => f));
    }
  }

  Widget _composer(ArconMono c) {
    final canSend = !_busy && _input.text.trim().isNotEmpty;
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
                for (final (v, label) in _sizes)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _size = v),
                      child: AnimatedContainer(
                        duration: Motion.of(context, Motion.fast),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _size == v ? c.ink : c.field,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: _size == v ? c.ink : c.line),
                        ),
                        child: Text(label, style: c.text(12, weight: FontWeight.w700, color: _size == v ? c.bg : c.ink)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_ref != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, size: 16, color: c.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Referans: ${_ref!.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, color: c.muted))),
                  GestureDetector(onTap: () => setState(() => _ref = null), child: Icon(Icons.close_rounded, size: 18, color: c.muted)),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(tooltip: 'Referans görsel', onPressed: _busy ? null : _pickRef, icon: Icon(Icons.add_photo_alternate_outlined, color: c.ink)),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                  style: c.text(15, height: 1.35),
                  cursorColor: c.ink,
                  decoration: c.input(_turns.isEmpty ? 'Nasıl bir görsel istiyorsun?' : 'Değişiklik iste…', null).copyWith(
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
                  child: _busy
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
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.prompt, required this.busy, required this.logoUrls, required this.onSaveEdit});
  final String url;
  final String prompt;
  final bool busy;
  final List<(String, String)> logoUrls;
  final ImageEditSave onSaveEdit;

  Future<void> _share(BuildContext context) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception();
      final ext = (Uri.parse(url).path.split('.').lastOrNull ?? 'png').toLowerCase();
      if (context.mounted) await toolShareBytes(context, res.bodyBytes, 'arcon-gorsel.${ext.length <= 4 ? ext : 'png'}');
    } catch (_) {
      if (context.mounted) toolToast(context, 'Görsel indirilemedi');
    }
  }

  Future<void> _tool(BuildContext context, String k) async {
    if (busy && k != 'edit') {
      toolToast(context, 'Görsel üretimi bitince tekrar dene');
      return;
    }
    final nav = Navigator.of(context);
    switch (k) {
      case 'edit':
        final saved = await nav.push<bool>(MaterialPageRoute(builder: (_) => ImageManualEditor(url: url, logoUrls: logoUrls, onSave: onSaveEdit)));
        if (saved == true) nav.pop(true);
      case 'select' || 'comment' || 'erase':
        final opts = await nav.push<ImageGenOpts>(MaterialPageRoute(
          builder: (_) => ImageMarkScreen(url: url, tool: switch (k) { 'select' => MarkTool.select, 'comment' => MarkTool.comment, _ => MarkTool.erase }),
        ));
        if (opts != null) nav.pop(opts);
      case 'nobg':
        nav.pop(ImageGenOpts(
          prompt: 'Arka planı tamamen kaldır. Sadece öndeki ana ürünü veya kişiyi bırak; gökyüzü, binalar, bayraklar, süslemeler dahil geri kalan her şey şeffaf olsun. Dama deseni veya yeni bir fon ekleme.',
          imageUrl: url,
          transparent: true,
          cutout: true,
        ));
      case 'resize':
        final c = ArconMono.of(context);
        final pick = await showModalBottomSheet<(String, String, String)>(
          context: context,
          backgroundColor: c.bg,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), child: Text('Yeniden boyutlandır', style: c.text(17, weight: FontWeight.w800))),
                Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Kenarlar sahne uzatılarak doldurulur; hiçbir şey kesilmez.', style: c.text(12.5, color: c.muted))),
                for (final r in imageResizeChoices)
                  ListTile(title: Text(r.$1, style: c.text(15)), trailing: Text(r.$2, style: c.text(13, color: c.muted)), onTap: () => Navigator.of(ctx).pop(r)),
              ],
            ),
          ),
        );
        if (pick != null) {
          nav.pop(ImageGenOpts(
            prompt: 'Bu görseli ${pick.$1.toLowerCase()} ${pick.$2} oranında yeniden çerçevele. Konuyu, yazıları ve logoları olduğu gibi koru. Yeni kenarları sahneyi doğal uzatarak doldur, hiçbir şeyi kesme.',
            imageUrl: url,
            size: pick.$3,
            aspect: pick.$2,
          ));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    const tools = [
      ('edit', 'Düzenle', Icons.crop_rotate_rounded),
      ('select', 'İşaretle', Icons.gesture_rounded),
      ('comment', 'Yorum', Icons.add_comment_outlined),
      ('nobg', 'Arka plan', Icons.layers_clear_outlined),
      ('erase', 'Sil', Icons.auto_fix_normal_outlined),
      ('resize', 'Boyut', Icons.aspect_ratio_rounded),
    ];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [IconButton(tooltip: 'Kaydet / paylaş', onPressed: () => _share(context), icon: const Icon(Icons.ios_share_rounded))],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(child: Hero(tag: url, child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain))),
            ),
          ),
          if (prompt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(prompt, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.4)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              child: Row(
                children: [
                  for (final (k, label, icon) in tools)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _tool(context, k),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Icon(icon, color: Colors.white, size: 22),
                              const SizedBox(height: 3),
                              Text(label, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
