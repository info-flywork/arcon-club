import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

/* ============================== Markalar ============================== */

/// ÜTS marka aracı — webdeki uts-brands/app.js listesiyle aynı.
class UtsBrand {
  const UtsBrand(this.id, this.label, this.folder, this.icon, this.docx, {this.multiFile = false});

  final String id;
  final String label;

  /// Sunucu klasörü (`givenchy`, `sensai-uts` …) — API: `<klasör>/api.php`.
  final String folder;
  final String icon;
  final String docx;
  final bool multiFile;

  static const all = <UtsBrand>[
    UtsBrand('dfb', 'DFB', 'dfb', 'dfb', 'dfb.docx'),
    UtsBrand('dg', 'Dolce & Gabbana', 'dg', 'dg', 'dolce_gabbana.docx'),
    UtsBrand('dior', 'Dior', 'dior', 'dior', 'dior.docx'),
    UtsBrand('givenchy', 'Givenchy', 'givenchy', 'givenchy', 'givenchy.docx'),
    UtsBrand('hermes', 'Hermès', 'hermes', 'hermes', 'hermes.docx'),
    UtsBrand('lp', 'LP', 'lp', 'lp', 'lp.docx', multiFile: true),
    UtsBrand('puig', 'Puig', 'puig', 'puig', 'puig.docx'),
    UtsBrand('sensai', 'Sensai', 'sensai-uts', 'sensai', 'sensai.docx'),
    UtsBrand('sisley', 'Sisley', 'sisley', 'sisley', 'sisley.docx'),
  ];

  static UtsBrand? byFolder(String? f) => f == null ? null : all.where((b) => b.folder == f || b.id == f).firstOrNull;

  String iconPath(bool dark) => 'uts-brands/images/${icon}_${dark ? 'dark' : 'light'}.png';
}

/// ÜTS — marka seçimi (webdeki uts-brands hub'ı).
class UtsBrandHubScreen extends StatelessWidget {
  const UtsBrandHubScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});

  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(19, weight: FontWeight.w800))),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
                  children: [
                    Text('Marka seç', style: c.text(24, weight: FontWeight.w800, spacing: -0.6)),
                    const SizedBox(height: 6),
                    Text('Ambalaj PDF’ini yükle; ÜTS bilgilerini çıkarıp markanın Word şablonunu hazırlayayım.', style: c.text(14, color: c.muted, height: 1.5)),
                    const SizedBox(height: 18),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.9,
                      children: [
                        for (final b in UtsBrand.all)
                          PressScale(
                            child: Material(
                              color: c.bg,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                  builder: (_) => UtsChatScreen(session: session, config: config, brand: b, webPath: '${b.folder}/index.html'),
                                )),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      UtsBrandLogo(session: session, brand: b, size: 68),
                                      const SizedBox(height: 10),
                                      Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: c.text(12.5, weight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UtsBrandLogo extends StatelessWidget {
  const UtsBrandLogo({super.key, required this.session, required this.brand, required this.size});

  final SessionController session;
  final UtsBrand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Text(brand.label.substring(0, 2).toUpperCase(), style: c.text(size * 0.32, weight: FontWeight.w800, color: c.bg)),
    );
    // Yeni ikonlar kare ve zeminli (açık: beyaz, koyu: siyah) — uygulama ikonu gibi yuvarlak köşeli tam kare
    final radius = size * 0.24;
    return Container(
      width: size,
      height: size,
      // Logo zeminiyle aynı renk: kare olmayan görseller (Hermès) kırpılmadan ortalanır
      decoration: BoxDecoration(color: c.dark ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(radius), border: Border.all(color: c.line)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: session.api.webUrl(brand.iconPath(c.dark)).toString(),
          fit: BoxFit.contain,
          // ~1 MB'lık PNG'ler: belleğe ekran boyutunda çöz
          memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
          placeholder: (_, _) => const Shimmer(child: SkeletonBox(radius: 0)),
          errorWidget: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

/* ============================== Sohbet ============================== */

class _UMsg {
  _UMsg({required this.bot, required this.text, this.url, this.file = false, this.at, this.error = false, this.localName});

  factory _UMsg.fromRow(Map<String, dynamic> r) {
    Map<String, dynamic> d = const {};
    try {
      final raw = r['message'];
      d = raw is Map ? raw.cast<String, dynamic>() : (jsonDecode('$raw') as Map).cast<String, dynamic>();
    } catch (_) {
      d = {'message': '${r['message'] ?? ''}'};
    }
    return _UMsg(
      bot: r['message_sender'] == 'bot',
      text: '${d['message'] ?? ''}',
      url: d['url'] as String?,
      file: d['contentFile'] == true,
      at: DateTime.tryParse('${r['sentDate'] ?? ''}'.replaceFirst(' ', 'T')),
      error: d['errorType'] != null,
    );
  }

  final bool bot;
  final String text;
  final String? url;
  final bool file;
  final DateTime? at;
  final bool error;
  final String? localName;
}

/// ÜTS marka sohbeti — ambalaj PDF'i yükle, Word (DOCX) çıktısını al; düzeltmeleri yazarak iste.
class UtsChatScreen extends StatefulWidget {
  const UtsChatScreen({super.key, required this.session, required this.config, required this.brand, required this.webPath});

  final SessionController session;
  final ArconAppConfig config;
  final UtsBrand brand;
  final String webPath;

  @override
  State<UtsChatScreen> createState() => _UtsChatScreenState();
}

class _UtsChatScreenState extends State<UtsChatScreen> {
  int? _conversationId;
  List<_UMsg> _msgs = [];
  List<Map<String, dynamic>> _conversations = [];
  bool _loadingConv = true;
  bool _loadingMsgs = false;
  bool _busy = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<PlatformFile> _files = [];
  Timer? _poll;

  UtsBrand get _b => widget.brand;

  @override
  void initState() {
    super.initState();
    // Yalnızca gönder düğmesi değişince yeniden kur (her tuşta tüm sohbet ekranını kurma)
    var wasEmpty = _input.text.trim().isEmpty;
    _input.addListener(() {
      final empty = _input.text.trim().isEmpty;
      if (empty != wasEmpty) setState(() => wasEmpty = empty);
    });
    _loadConversations();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  void _fallback() =>
      openWebFallback(context, session: widget.session, config: widget.config, title: 'ÜTS · ${_b.label}', path: widget.webPath, replace: true);

  Future<void> _loadConversations() async {
    try {
      final j = await widget.session.api.utsGet(_b.folder, {'action': 'get_conversations'});
      if (!mounted) return;
      setState(() {
        _conversations = [for (final c in ((j['conversations'] as List?) ?? const []).whereType<Map>()) c.cast<String, dynamic>()];
        _loadingConv = false;
      });
    } on ArconApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingConv = false);
      if (e.code == 'tool_unavailable') _fallback();
    }
  }

  Future<void> _openConversation(int id) async {
    _poll?.cancel();
    setState(() {
      _conversationId = id;
      _msgs = [];
      _loadingMsgs = true;
    });
    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    final id = _conversationId;
    if (id == null) return;
    try {
      final j = await widget.session.api.utsGet(_b.folder, {'action': 'get_messages', 'conversation_id': '$id'});
      if (!mounted || id != _conversationId) return;
      setState(() {
        _msgs = [for (final r in ((j['messages'] as List?) ?? const []).whereType<Map>()) _UMsg.fromRow(r.cast<String, dynamic>())];
        _loadingMsgs = false;
      });
      _scrollToEnd();
    } on ArconApiException catch (e) {
      if (mounted) {
        setState(() => _loadingMsgs = false);
        _toast(e.message);
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.of(context, Motion.normal), curve: Curves.easeOutCubic);
      }
    });
  }

  void _newChat() {
    if (_busy) return;
    _poll?.cancel();
    setState(() {
      _conversationId = null;
      _msgs = [];
      _files.clear();
    });
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    final pdfs = files.where((f) => f.name.toLowerCase().endsWith('.pdf')).toList();
    if (pdfs.isEmpty) {
      _toast('Sadece PDF dosyaları yüklenebilir');
      return;
    }
    setState(() {
      if (!_b.multiFile) _files.clear();
      _files.addAll(_b.multiFile ? pdfs : pdfs.take(1));
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_busy || (text.isEmpty && _files.isEmpty)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final files = List<PlatformFile>.of(_files);
    final botCountBefore = _msgs.where((m) => m.bot).length;
    setState(() {
      _msgs = [..._msgs, _UMsg(bot: false, text: text, file: files.isNotEmpty, localName: files.map((f) => f.name).join(', '), at: DateTime.now())];
      _files.clear();
      _input.clear();
      _busy = true;
    });
    _scrollToEnd();
    try {
      final r = await widget.session.api.utsSend(
        _b.folder,
        {'message': text, if (_conversationId != null) 'conversation_id': '$_conversationId'},
        files: [for (final f in files) if (f.path != null) f.path!],
        multiFile: _b.multiFile,
      );
      final id = int.tryParse('${r['conversation_id']}');
      if (id != null) _conversationId = id;
      if (r['is_new_conversation'] == true) unawaited(_loadConversations());
      await _loadMessages();
      if (_msgs.where((m) => m.bot).length <= botCountBefore) _startPolling(botCountBefore);
      HapticFeedback.lightImpact();
    } on ArconApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'tool_unavailable') {
        _fallback();
        return;
      }
      if (e.code == 'timeout' && _conversationId != null) {
        _toast(e.message);
        _startPolling(botCountBefore);
      } else {
        setState(() => _msgs = [..._msgs, _UMsg(bot: true, text: e.message, error: true)]);
      }
    } finally {
      if (mounted && _poll == null) setState(() => _busy = false);
    }
  }

  /// Sonuç henüz yazılmadıysa (uzun analiz) birkaç dakika boyunca yeni bot mesajını bekle.
  void _startPolling(int botCountBefore) {
    var tries = 0;
    _poll?.cancel();
    setState(() => _busy = true);
    _poll = Timer.periodic(const Duration(seconds: 5), (t) async {
      tries++;
      await _loadMessages();
      final done = _msgs.where((m) => m.bot).length > botCountBefore;
      if (done || tries >= 60 || !mounted) {
        t.cancel();
        _poll = null;
        if (mounted) setState(() => _busy = false);
      }
    });
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
                  Expanded(child: Text('Geçmiş · ${_b.label}', style: c.text(18, weight: FontWeight.w800))),
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
            if (_conversations.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Text('Henüz sohbet yok.', textAlign: TextAlign.center, style: c.text(14, color: c.muted)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + MediaQuery.paddingOf(ctx).bottom),
                  children: [for (final cv in _conversations) _convTile(c, cv, () => Navigator.of(ctx).pop())],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _convTile(ArconMono c, Map<String, dynamic> cv, [VoidCallback? before]) {
    final id = int.tryParse('${cv['id']}') ?? 0;
    final title = '${cv['title'] ?? ''}'.trim();
    final at = DateTime.tryParse('${cv['createdDate'] ?? ''}'.replaceFirst(' ', 'T'));
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: _conversationId == id,
      selectedTileColor: c.field,
      leading: Icon(Icons.description_outlined, color: c.muted, size: 20),
      title: Text(title.isEmpty ? 'Sohbet #$id' : title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w600)),
      subtitle: at == null ? null : Text(_fmtDate(at), style: c.text(12, color: c.muted)),
      onTap: () {
        before?.call();
        _openConversation(id);
      },
    );
  }

  static String _fmtDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
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
                    UtsBrandLogo(session: widget.session, brand: _b, size: 28),
                    const SizedBox(width: 10),
                    Expanded(child: Text('ÜTS · ${_b.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(17, weight: FontWeight.w800))),
                    IconButton(
                      tooltip: 'Yeni sohbet',
                      onPressed: _conversationId == null ? null : _newChat,
                      icon: Icon(Icons.edit_square, size: 21, color: _conversationId == null ? c.faint : c.ink),
                    ),
                    IconButton(tooltip: 'Geçmiş', onPressed: _openHistory, icon: Icon(Icons.history_rounded, color: c.ink)),
                  ],
                ),
              ),
              Expanded(
                child: SwapFade(
                  child: KeyedSubtree(
                    key: ValueKey(_conversationId ?? (_msgs.isEmpty ? 'empty' : 'new')),
                    child: _msgs.isEmpty && _conversationId == null
                        ? _empty(c)
                        : _loadingMsgs
                            ? const SkeletonChat()
                            : ListView(
                                controller: _scroll,
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                children: [
                                  for (final m in _msgs) _bubble(c, m),
                                  if (_busy) _working(c),
                                ],
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
          Center(child: UtsBrandLogo(session: widget.session, brand: _b, size: 84)),
          const SizedBox(height: 16),
          Text('${_b.label} ÜTS', textAlign: TextAlign.center, style: c.text(24, weight: FontWeight.w800, spacing: -0.6)),
          const SizedBox(height: 8),
          Text(
            _b.multiFile
                ? 'Ambalaj PDF’lerini yükle; ÜTS bilgilerini çıkarıp ${_b.docx} dosyasını hazırlayayım. Sonra düzeltmeleri yazarak isteyebilirsin.'
                : 'Ambalaj PDF’ini yükle; ÜTS bilgilerini çıkarıp ${_b.docx} dosyasını hazırlayayım. Sonra düzeltmeleri yazarak isteyebilirsin.',
            textAlign: TextAlign.center,
            style: c.text(14.5, color: c.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          c.primaryButton(_b.multiFile ? 'PDF’leri seç' : 'PDF seç', busy: false, onPressed: _pick),
          if (_loadingConv) ...[
            const SizedBox(height: 24),
            const SkeletonList(count: 2, leading: false),
          ] else if (_conversations.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(trUpper('Son sohbetler'), style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
            const SizedBox(height: 4),
            for (final cv in _conversations.take(4)) _convTile(c, cv),
          ],
        ],
      );

  Widget _working(ArconMono c) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 12),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)),
            const SizedBox(width: 10),
            Expanded(child: Text('PDF inceleniyor, ÜTS belgesi hazırlanıyor… Bu birkaç dakika sürebilir.', style: c.text(13, color: c.muted))),
          ],
        ),
      );

  Widget _bubble(ArconMono c, _UMsg m) {
    final docName = m.url == null ? null : Uri.tryParse(m.url!)?.pathSegments.lastOrNull;
    if (!m.bot) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14, left: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (m.file)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _fileCard(c, Icons.picture_as_pdf_outlined, m.localName ?? (docName != null ? Uri.decodeComponent(docName) : 'PDF'), m.url),
              ),
            if (m.text.isNotEmpty)
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
                child: SelectableText(m.text, style: c.text(15, height: 1.45, color: c.bg)),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, right: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UtsBrandLogo(session: widget.session, brand: _b, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.error)
                  Text(m.text.isEmpty ? 'Analiz tamamlanamadı, tekrar dener misin?' : m.text, style: c.text(14.5, color: c.danger, height: 1.45))
                else if (m.text.isNotEmpty)
                  SelectableText(m.text, style: c.text(15, height: 1.5)),
                if (m.url != null && m.file) ...[
                  const SizedBox(height: 8),
                  _fileCard(c, Icons.description_outlined, _b.docx, m.url, primary: true),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileCard(ArconMono c, IconData icon, String name, String? url, {bool primary = false}) => Material(
        color: primary ? c.ink : c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: primary ? c.ink : c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: primary ? c.bg : c.ink),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13.5, weight: FontWeight.w700, color: primary ? c.bg : c.ink)),
                ),
                if (url != null) ...[
                  const SizedBox(width: 8),
                  Icon(primary ? Icons.download_rounded : Icons.open_in_new_rounded, size: 17, color: primary ? c.bg : c.muted),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _composer(ArconMono c) {
    final canSend = !_busy && (_input.text.trim().isNotEmpty || _files.isNotEmpty);
    return Container(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                          Icon(Icons.picture_as_pdf_outlined, size: 15, color: c.muted),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
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
              IconButton(tooltip: 'PDF ekle', onPressed: _busy ? null : _pick, icon: Icon(Icons.attach_file_rounded, color: c.ink)),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                  style: c.text(15, height: 1.35),
                  cursorColor: c.ink,
                  decoration: c.input(_conversationId == null ? 'PDF ekle veya not yaz…' : 'Düzeltme yaz (ör. hacmi 100 ml yap)…', null).copyWith(
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
