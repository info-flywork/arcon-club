import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'tool_common.dart';

const _inlineTags = {'b', 'strong', 'i', 'em', 'u', 'br', 'span', 'small', 'sup', 'sub', 'a', 'mark', 'code', 's'};
const _skipTags = {'script', 'style', 'svg', 'noscript', 'template', 'img', 'video', 'canvas', 'iframe'};

/// Sunumdaki düzenlenebilir yazı öğeleri: yalnızca yazı + satır içi etiket içeren en dış öğeler.
@visibleForTesting
List<dom.Element> deckTextElements(dom.Element slide) {
  final out = <dom.Element>[];
  bool inlineOnly(dom.Element e) => e.children.every((ch) => _inlineTags.contains(ch.localName) && inlineOnly(ch));
  void walk(dom.Element e) {
    if (_skipTags.contains(e.localName)) return;
    if (e.text.trim().isNotEmpty && inlineOnly(e)) {
      out.add(e);
      return;
    }
    for (final ch in e.children) {
      walk(ch);
    }
  }

  for (final ch in slide.children) {
    walk(ch);
  }
  return out;
}

/// Öğenin yazısı (<br> → satır sonu).
@visibleForTesting
String deckReadText(dom.Element e) {
  final b = StringBuffer();
  void walk(dom.Node n) {
    if (n is dom.Text) {
      b.write(n.text.replaceAll(RegExp(r'\s+'), ' '));
    } else if (n is dom.Element) {
      if (n.localName == 'br') {
        b.write('\n');
      } else {
        n.nodes.forEach(walk);
      }
    }
  }

  e.nodes.forEach(walk);
  return b.toString().split('\n').map((l) => l.trim()).join('\n').trim();
}

/// Yazıyı öğeye yazar; satır sonları <br> olur. Biçim yalnızca yazı değiştiyse silinir.
@visibleForTesting
void deckWriteText(dom.Element e, String text) {
  if (deckReadText(e) == text.trim()) return;
  e.nodes.clear();
  final lines = text.trim().split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) e.append(dom.Element.tag('br'));
    e.append(dom.Text(lines[i]));
  }
}

/// Sunum düzenleyici — webdeki düzenleyicinin mobil karşılığı: sayfa sırası, çoğalt / sil,
/// yazıları düzenle, fotoğraf değiştir, yapay zekâyla sayfa değiştir / ekle, yeni sürüm olarak kaydet.
class DeckEditorScreen extends StatefulWidget {
  const DeckEditorScreen({super.key, required this.session, required this.base, required this.turnId, required this.title});
  final SessionController session;
  final String base; // ör. presentation-creater/
  final int turnId;
  final String title;

  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  dom.Document? _doc;
  String _assetBase = '';
  String? _error;
  int _cur = 0;
  final List<String> _undo = [];
  final List<String> _log = [];
  final Set<int> _textPages = {};
  bool _reordered = false;
  bool _changed = false;
  String? _busy;
  int _gen = 0; // sayfa / içerik değişince alanlar yeniden kurulur

  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.white)
    ..setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) => _showSlide(),
      onNavigationRequest: (r) => r.url.startsWith('about:') || r.url.startsWith('data:') || r.url == _assetBase ? NavigationDecision.navigate : NavigationDecision.prevent,
    ));
  Timer? _previewTimer;

  // aktif sayfanın yazı alanları
  List<(dom.Element, TextEditingController)> _fields = [];

  ArconApi get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _disposeFields();
    super.dispose();
  }

  void _disposeFields() {
    for (final (_, c) in _fields) {
      c.dispose();
    }
    _fields = [];
  }

  Future<void> _load() async {
    try {
      final j = await _api.webCall('${widget.base}chat.php', query: {'action': 'deck_html', 'turn': '${widget.turnId}'}, timeout: const Duration(seconds: 60));
      final doc = html_parser.parse(j['html'] as String? ?? '');
      if (doc.querySelectorAll('.slide').isEmpty) throw const ArconApiException('invalid', 'Bu sunumda sayfa yapısı bulunamadı. Değişikliği sohbetten isteyebilirsin.');
      final url = '${j['url'] ?? ''}';
      _assetBase = j['local'] == true ? _api.webUrl('${widget.base}decks/').toString() : url.replaceFirst(RegExp(r'[^/]*$'), '');
      if (!mounted) return;
      setState(() => _doc = doc);
      _rebuildFields();
      _renderPreview();
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<dom.Element> get _slides => _doc?.querySelectorAll('.slide') ?? const [];

  String _serialize() => '<!DOCTYPE html>\n${_doc!.documentElement!.outerHtml}';

  /// Önizleme: masaüstü genişliğinde çizilir ve küçültülür; dokunma ile sayfa geçişi kapalı.
  void _renderPreview() {
    if (_doc == null) return;
    var html = _serialize().replaceAll(RegExp(r'<meta[^>]+name=["\x27]viewport["\x27][^>]*>', caseSensitive: false), '');
    final inject = '<base href="$_assetBase"><meta name="viewport" content="width=1280">'
        '<style>html,body{pointer-events:none!important}</style>';
    final m = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    html = m == null ? html.replaceFirst('<html', '<html><head>$inject</head><html') : html.replaceRange(m.end, m.end, inject);
    _web.loadHtmlString(html, baseUrl: _assetBase);
  }

  void _showSlide() {
    final k = _cur;
    _web.runJavaScript('try{if(typeof go==="function"){go($k)}else{document.querySelectorAll(".slide").forEach(function(s,j){s.classList.toggle("active",j===$k)})}}catch(e){}');
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 700), _renderPreview);
  }

  void _rebuildFields() {
    _disposeFields();
    final slides = _slides;
    if (slides.isEmpty) return;
    _fields = [for (final e in deckTextElements(slides[_cur])) (e, TextEditingController(text: deckReadText(e)))];
    _gen++;
  }

  void _go(int k) {
    final n = _slides.length;
    if (n == 0) return;
    setState(() {
      _cur = k.clamp(0, n - 1);
      _rebuildFields();
    });
    _showSlide();
  }

  void _snapshot() {
    _undo.add(_serialize());
    if (_undo.length > 30) _undo.removeAt(0);
  }

  void _commit(String? log) {
    if (log != null) _log.add(log);
    setState(() {
      _changed = true;
      _cur = _cur.clamp(0, _slides.length - 1);
      _rebuildFields();
    });
    _renderPreview();
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _doc = html_parser.parse(_undo.removeLast());
      if (_log.isNotEmpty) _log.removeLast();
      _changed = true;
      _cur = _cur.clamp(0, _slides.length - 1);
      _rebuildFields();
    });
    _renderPreview();
  }

  /* ---------------- sayfa işlemleri ---------------- */

  void _move(int dir) {
    final s = _slides;
    final to = _cur + dir;
    if (to < 0 || to >= s.length) return;
    _snapshot();
    final a = s[_cur];
    final b = s[to];
    if (dir < 0) {
      b.parent!.insertBefore(a, b);
    } else {
      a.parent!.insertBefore(b, a);
    }
    _reordered = true;
    _cur = to;
    _commit(null);
  }

  void _duplicate() {
    final s = _slides[_cur];
    _snapshot();
    final copy = s.clone(true)..classes.remove('active');
    s.parent!.insertBefore(copy, s.nextElementSibling);
    _cur++;
    _commit('$_cur. sayfayı çoğalttım');
  }

  Future<void> _delete() async {
    if (_slides.length <= 1) return;
    final ok = await _confirm('${_cur + 1}. sayfa silinsin mi?', 'Kaydetmeden önce geri alabilirsin.', 'Sil', destructive: true);
    if (!ok) return;
    _snapshot();
    _slides[_cur].remove();
    _commit('${_cur + 1}. sayfayı sildim');
  }

  void _textChanged(dom.Element e, String v) {
    deckWriteText(e, v);
    _textPages.add(_cur);
    if (!_changed) setState(() => _changed = true);
    _schedulePreview();
  }

  void _beginTextEdit() {
    // Yazı düzenlemenin ilk harfinde geri alma noktası
    if (_undo.isEmpty || _undo.last != _serialize()) _snapshot();
  }

  /* ---------------- fotoğraflar ---------------- */

  String _resolve(String src) {
    if (src.startsWith('http') || src.startsWith('data:')) return src;
    return Uri.parse(_assetBase).resolve(src).toString();
  }

  Future<String?> _pickAndUpload() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    if (x == null || !mounted) return null;
    setState(() => _busy = 'Fotoğraf yükleniyor…');
    try {
      final r = await _api.webCall('${widget.base}chat.php',
          fields: {'action': 'upload_photo', 'turn': '${widget.turnId}'}, files: [('refs[]', x.path)], timeout: const Duration(minutes: 2));
      return r['url'] as String?;
    } on ArconApiException catch (e) {
      if (mounted) toolToast(context, e.message);
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _replacePhoto(dom.Element img) async {
    final url = await _pickAndUpload();
    if (url == null) return;
    _snapshot();
    img.attributes['src'] = url;
    img.attributes.remove('srcset');
    _commit('${_cur + 1}. sayfada fotoğrafı değiştirdim');
  }

  Future<void> _removePhoto(dom.Element img) async {
    if (!await _confirm('Fotoğraf kaldırılsın mı?', 'Sayfadaki boşluk aynı kalabilir; düzeni yapay zekâyla toparlayabilirsin.', 'Kaldır', destructive: true)) return;
    _snapshot();
    final p = img.parent;
    if (p != null && p.localName == 'figure' && p.querySelectorAll('img').length == 1) {
      p.remove();
    } else {
      img.remove();
    }
    _commit('${_cur + 1}. sayfadan bir fotoğrafı kaldırdım');
  }

  /* ---------------- yapay zekâ ---------------- */

  Future<void> _ai({required bool newPage}) async {
    final c = ArconMono.of(context);
    final ctl = TextEditingController();
    String? photo;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(newPage ? '${_cur + 1}. sayfadan sonra yeni sayfa' : '${_cur + 1}. sayfayı değiştir', style: c.text(18, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(newPage ? 'Yeni sayfada ne olsun? Tasarım sunumla aynı olur.' : 'Sadece bu sayfa değişir, diğerleri aynen kalır.', style: c.text(12.5, color: c.muted)),
              const SizedBox(height: 14),
              TextField(
                controller: ctl,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                style: c.text(15, height: 1.4),
                cursorColor: c.ink,
                decoration: c.input(newPage ? 'ör. 2025 hedeflerini 3 madde ve bir grafikle anlatan sayfa' : 'ör. Başlığı kısalt, maddeleri ikonlu kartlara çevir', null),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final u = await _pickAndUpload();
                      if (u != null) set(() => photo = u);
                    },
                    icon: Icon(photo == null ? Icons.add_photo_alternate_outlined : Icons.check_circle_rounded, color: c.ink, size: 19),
                    label: Text(photo == null ? 'Fotoğraf ekle' : 'Fotoğraf eklendi', style: c.text(13.5, weight: FontWeight.w700)),
                  ),
                  if (photo != null) IconButton(onPressed: () => set(() => photo = null), icon: Icon(Icons.close_rounded, size: 18, color: c.muted)),
                ],
              ),
              const SizedBox(height: 8),
              c.primaryButton(newPage ? 'Sayfayı oluştur' : 'Değiştir', busy: false, onPressed: () {
                if (ctl.text.trim().isNotEmpty || photo != null) Navigator.of(ctx).pop(true);
              }),
            ],
          ),
        ),
      ),
    );
    final instruction = ctl.text.trim();
    ctl.dispose();
    if (go != true || !mounted) return;

    final slides = _slides;
    final sec = slides[_cur];
    final clone = sec.clone(true)..classes.remove('active');
    final css = _doc!.querySelectorAll('style').map((s) => s.text).join('\n');
    setState(() => _busy = newPage ? 'Yeni sayfa hazırlanıyor…' : '${_cur + 1}. sayfa güncelleniyor…');
    try {
      final r = await _api.webCall('${widget.base}chat.php',
          fields: {
            'action': 'edit_slide',
            'turn': '${widget.turnId}',
            'mode': newPage ? 'new' : 'edit',
            'index': '${_cur + 1}',
            'total': '${slides.length}',
            'instruction': instruction,
            'slide_html': clone.outerHtml,
            'css': css.length > 60000 ? css.substring(0, 60000) : css,
            'photo_url': ?photo,
          },
          timeout: const Duration(minutes: 5));
      final frag = html_parser.parseFragment('${r['section'] ?? ''}'.trim());
      final fresh = frag.children.where((e) => e.localName == 'section').firstOrNull;
      if (fresh == null) throw const ArconApiException('invalid', 'Yapay zekâ geçerli bir sayfa döndürmedi. Tekrar dene.');
      if (!fresh.classes.contains('slide')) fresh.classes.add('slide');
      fresh.classes.remove('active');
      if (!mounted) return;
      _snapshot();
      if (newPage) {
        sec.parent!.insertBefore(fresh, sec.nextElementSibling);
        _cur++;
        _commit('${_cur + 1}. sayfayı yapay zekâyla ekledim (${_short(instruction)})');
      } else {
        sec.replaceWith(fresh);
        _commit('${_cur + 1}. sayfayı yapay zekâyla değiştirdim (${_short(instruction)})');
      }
      HapticFeedback.mediumImpact();
    } on ArconApiException catch (e) {
      if (mounted) toolToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _short(String s) => s.isEmpty ? 'fotoğraf' : (s.length > 60 ? '${s.substring(0, 60)}…' : s);

  /* ---------------- kaydet / çık ---------------- */

  String _summary() {
    final parts = <String>[
      if (_textPages.isNotEmpty) '${(_textPages.toList()..sort()).map((k) => k + 1).join(', ')}. sayfada metinleri düzenledim',
      if (_reordered) 'sayfaların sırasını değiştirdim',
      ..._log,
    ];
    return 'Sunumu düzenledim — ${parts.isEmpty ? 'küçük değişiklikler' : parts.join('; ')}.';
  }

  Future<void> _save() async {
    if (_busy != null || !_changed) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = 'Kaydediliyor…');
    try {
      final r = await _api.webCall('${widget.base}chat.php',
          fields: {'action': 'save_deck', 'turn': '${widget.turnId}', 'html': _serialize(), 'summary': _summary()}, timeout: const Duration(minutes: 2));
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop((r['turn'] as Map?)?.cast<String, dynamic>());
    } on ArconApiException catch (e) {
      if (mounted) {
        setState(() => _busy = null);
        toolToast(context, e.message);
      }
    }
  }

  Future<bool> _confirm(String title, String text, String ok, {bool destructive = false}) async =>
      await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
            CupertinoDialogAction(isDestructiveAction: destructive, onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
          ],
        ),
      ) ??
      false;

  Future<void> _exit() async {
    if (_busy != null) return;
    if (!_changed || await _confirm('Değişiklikler silinsin mi?', 'Kaydetmeden çıkarsan yaptığın düzenlemeler kaybolur.', 'Çık', destructive: true)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  /* ---------------- arayüz ---------------- */

  String _slideLabel(dom.Element s) {
    final h = s.querySelector('h1, h2, h3') ?? (deckTextElements(s).firstOrNull);
    final t = h == null ? '' : deckReadText(h).replaceAll('\n', ' ');
    return t.length > 26 ? '${t.substring(0, 26)}…' : t;
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final slides = _slides;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: _exit, icon: Icon(Icons.close_rounded, color: c.ink)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title.isEmpty ? 'Sunum' : widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(16, weight: FontWeight.w800)),
                          Text('düzenleniyor', style: c.text(11.5, color: c.muted)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: _undo.isEmpty || _busy != null ? null : _undoLast, icon: Icon(Icons.undo_rounded, color: _undo.isEmpty ? c.faint : c.ink)),
                    FilledButton(
                      onPressed: _changed && _busy == null ? _save : null,
                      style: FilledButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.bg, disabledBackgroundColor: c.line),
                      child: Text('Kaydet', style: c.text(14, weight: FontWeight.w700, color: _changed ? c.bg : c.faint)),
                    ),
                  ],
                ),
              ),
              if (_doc == null)
                Expanded(
                  child: _error != null
                      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: c.text(14, color: c.muted))))
                      : const Padding(padding: EdgeInsets.all(20), child: Column(children: [SkeletonBox(height: 200, radius: 14), SizedBox(height: 16), SkeletonList(count: 4, leading: false, padding: EdgeInsets.zero)])),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.line)), child: IgnorePointer(child: WebViewWidget(controller: _web))),
                          if (_busy != null)
                            Container(
                              color: Colors.black.withValues(alpha: 0.45),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                  const SizedBox(height: 10),
                                  Text(_busy!, style: c.text(13, weight: FontWeight.w700, color: Colors.white)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: slides.length,
                    itemBuilder: (_, k) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: _busy != null ? null : () => _go(k),
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k == _cur ? c.ink : c.field,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: k == _cur ? c.ink : c.line),
                          ),
                          child: Text(
                            '${k + 1}${_slideLabel(slides[k]).isEmpty ? '' : ' · ${_slideLabel(slides[k])}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: c.text(12, weight: FontWeight.w700, color: k == _cur ? c.bg : c.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _tool(c, Icons.chevron_left_rounded, 'Öne al', _cur > 0 ? () => _move(-1) : null),
                      _tool(c, Icons.chevron_right_rounded, 'Arkaya al', _cur < slides.length - 1 ? () => _move(1) : null),
                      _tool(c, Icons.copy_all_rounded, 'Çoğalt', _duplicate),
                      _tool(c, Icons.delete_outline_rounded, 'Sil', slides.length > 1 ? _delete : null, danger: true),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: ValueKey(_gen),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 24 + pad.bottom),
                    children: [
                      Row(
                        children: [
                          Expanded(child: _aiButton(c, Icons.auto_awesome_outlined, 'Yapay zekâyla değiştir', () => _ai(newPage: false), primary: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _aiButton(c, Icons.add_rounded, 'Yeni sayfa ekle', () => _ai(newPage: true))),
                        ],
                      ),
                      ..._photos(c),
                      if (_fields.isNotEmpty) ...[
                        _section(c, 'Yazılar'),
                        for (final (e, ctl) in _fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TextField(
                              controller: ctl,
                              enabled: _busy == null,
                              minLines: 1,
                              maxLines: 8,
                              onTap: _beginTextEdit,
                              onChanged: (v) => _textChanged(e, v),
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                              style: c.text(const {'h1', 'h2'}.contains(e.localName) ? 16 : 14.5,
                                  weight: const {'h1', 'h2', 'h3', 'strong', 'b'}.contains(e.localName) ? FontWeight.w700 : FontWeight.w400, height: 1.4),
                              cursorColor: c.ink,
                              decoration: c.input('', null),
                            ),
                          ),
                      ] else ...[
                        const SizedBox(height: 18),
                        Text('Bu sayfada düzenlenebilir yazı bulunamadı. Değişikliği yapay zekâyla isteyebilirsin.', style: c.text(13, color: c.muted)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _photos(ArconMono c) {
    final slides = _slides;
    if (slides.isEmpty) return const [];
    final imgs = slides[_cur].querySelectorAll('img').where((i) => (i.attributes['src'] ?? '').isNotEmpty && !(i.classes.any((k) => k.contains('logo')))).toList();
    if (imgs.isEmpty) return const [];
    return [
      _section(c, 'Fotoğraflar'),
      SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final img in imgs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: _busy != null
                      ? null
                      : () async {
                          final v = await showModalBottomSheet<String>(
                            context: context,
                            backgroundColor: c.bg,
                            builder: (ctx) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ListTile(leading: Icon(Icons.photo_library_outlined, color: c.ink), title: Text('Fotoğrafı değiştir', style: c.text(15)), onTap: () => Navigator.of(ctx).pop('replace')),
                                  ListTile(leading: Icon(Icons.delete_outline_rounded, color: c.danger), title: Text('Kaldır', style: c.text(15, color: c.danger)), onTap: () => Navigator.of(ctx).pop('remove')),
                                ],
                              ),
                            ),
                          );
                          if (v == 'replace') _replacePhoto(img);
                          if (v == 'remove') _removePhoto(img);
                        },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 140,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: _resolve(img.attributes['src']!),
                            fit: BoxFit.cover,
                            memCacheWidth: 420,
                            errorWidget: (_, _, _) => Container(color: c.line, child: Icon(Icons.image_not_supported_outlined, color: c.muted)),
                          ),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: CircleAvatar(radius: 13, backgroundColor: Colors.black54, child: const Icon(Icons.edit_rounded, size: 14, color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _section(ArconMono c, String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(trUpper(t), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
      );

  Widget _tool(ArconMono c, IconData icon, String label, VoidCallback? onTap, {bool danger = false}) => Expanded(
        child: Opacity(
          opacity: onTap == null || _busy != null ? 0.35 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _busy != null ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Icon(icon, size: 21, color: danger ? c.danger : c.ink),
                  const SizedBox(height: 2),
                  Text(label, style: c.text(11, weight: FontWeight.w600, color: danger ? c.danger : c.ink)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _aiButton(ArconMono c, IconData icon, String label, VoidCallback onTap, {bool primary = false}) => Material(
        color: primary ? c.ink : c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: primary ? c.ink : c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy != null ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: primary ? c.bg : c.ink),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13, weight: FontWeight.w700, color: primary ? c.bg : c.ink))),
              ],
            ),
          ),
        ),
      );
}
