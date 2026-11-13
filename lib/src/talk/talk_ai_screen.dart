import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/ai_widgets.dart';
import '../ai/chat_controller.dart';
import '../ai/engine_client.dart';
import '../ai/engine_models.dart';
import '../api/api_client.dart';
import '../ui/theme.dart';
import 'talk_ai_logo.dart';
import 'talk_icons.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';
import '../ui/skeleton.dart';

/// ARCONNECT'te ARCON AI — WhatsApp'taki Meta AI sohbeti gibi: karşılama + öneri kartları,
/// balonlu sohbet, geçmiş ve gizli sohbet. Webdeki ARCON AI ile aynı hesap ve aynı sohbetler.
class TalkAiScreen extends StatefulWidget {
  const TalkAiScreen({super.key, required this.api, required this.name, this.engine, this.conversationId, this.private = false, this.initialPrompt});

  final ArconApi api;

  /// Karşılamadaki ad ("Günaydın, Tuna")
  final String name;
  final EngineClient? engine;
  final int? conversationId;

  /// Gizli sohbet: koyu ekran, ekrandan çıkınca sohbet silinir
  final bool private;

  /// Sohbetler'deki arama kutusundan gelen soru: açılınca hemen sorulur
  final String? initialPrompt;

  @override
  State<TalkAiScreen> createState() => _TalkAiScreenState();
}

class _TalkAiScreenState extends State<TalkAiScreen> {
  late final EngineClient _engine = widget.engine ?? EngineClient(arcon: widget.api);
  late final ChatController _c = ChatController(engine: _engine, conversationId: widget.conversationId);
  final _input = TextEditingController();
  final _focus = FocusNode();

  static const _suggestions = [
    (CupertinoIcons.mail, 'Profesyonel bir e-posta taslağı yazmama yardım et'),
    (CupertinoIcons.list_bullet, 'Verimli bir toplantı gündemi hazırla'),
    (CupertinoIcons.chart_bar, 'Bir sunum için 5 slaytlık plan çıkar'),
    (CupertinoIcons.chat_bubble_text, 'Bir müşteri şikâyetine kibar bir yanıt yaz'),
    (CupertinoIcons.photo, 'Mars’ta koşan bir astronot görseli oluştur'),
  ];

  static const _privateSuggestions = [
    (CupertinoIcons.heart, 'Bir tartışmadan sonra ne söyleyeceğimi bulmama yardım et'),
    (CupertinoIcons.briefcase, 'Maaş görüşmesine nasıl hazırlanırım?'),
    (CupertinoIcons.money_dollar_circle, 'Bütçe oluşturma konusunda yardıma ihtiyacım var'),
    (CupertinoIcons.bandage, 'Sağlığımla ilgili bir sorum var'),
    (CupertinoIcons.lightbulb, 'Kimsenin haberi olmadan bir sürpriz planlamama yardım et'),
  ];

  @override
  void initState() {
    super.initState();
    _c.load().then((_) {
      final q = widget.initialPrompt;
      if (mounted && q != null && q.trim().isNotEmpty) _send(q);
    });
  }

  @override
  void dispose() {
    // gizli sohbet: ekrandan çıkınca sunucudan da silinir
    final id = _c.conversationId;
    if (widget.private && id != null) unawaited(_engine.deleteConversation(id).then((_) {}, onError: (_) {}));
    _c.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty || !_c.canSend) return;
    if (text == null) _input.clear();
    await _c.send(t);
  }

  Future<void> _attach({String? preset}) async {
    final c = TalkColors.of(context);
    final choice = preset ??
        await showModalBottomSheet<String>(
          context: context,
          backgroundColor: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          showDragHandle: true,
          builder: (ctx) {
            Widget item(String key, IconData icon, String label) => Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(ctx, key),
                    child: Column(children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : Colors.white, shape: BoxShape.circle),
                        child: Icon(icon, size: 28, color: c.ink),
                      ),
                      const SizedBox(height: 8),
                      Text(label, style: talkText(14, FontWeight.w500, c.ink)),
                    ]),
                  ),
                );
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                child: Row(children: [
                  item('gallery', CupertinoIcons.photo_on_rectangle, 'Fotoğraflar'),
                  item('camera', CupertinoIcons.camera, 'Kamera'),
                  item('file', CupertinoIcons.doc, 'Belge'),
                ]),
              ),
            );
          },
        );
    if (choice == null) return;
    if (choice == 'file') {
      for (final f in await FilePicker.pickFiles()) {
        final path = f.path;
        if (path != null) unawaited(_c.attach(path, f.name));
      }
    } else {
      final picker = ImagePicker();
      final shots = choice == 'camera'
          ? [?await picker.pickImage(source: ImageSource.camera, imageQuality: 85)]
          : await picker.pickMultiImage(imageQuality: 85);
      for (final x in shots) {
        unawaited(_c.attach(x.path, x.name, isImage: true));
      }
    }
  }

  Future<void> _pickModel() async {
    if (_c.providers.length < 2) return;
    final c = TalkColors.of(context);
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: c.dark ? const Color(0xFF1C1C1E) : Colors.white,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Model seç', style: talkText(17, FontWeight.w600, c.ink))),
          for (final p in _c.providers)
            ListTile(
              leading: Icon(p.id == _c.provider ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: c.ink),
              title: Text(p.label, style: talkText(16, FontWeight.w500, c.ink)),
              subtitle: Text(p.model, style: talkText(13, FontWeight.w400, c.muted)),
              onTap: () => Navigator.pop(ctx, p.id),
            ),
        ]),
      ),
    );
    if (id != null) _c.selectProvider(id);
  }

  Future<void> _history() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => TalkAiHistoryScreen(engine: _engine)));
    if (id == null || !mounted) return;
    unawaited(Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => TalkAiScreen(api: widget.api, name: widget.name, engine: _engine, conversationId: id > 0 ? id : null),
    )));
  }

  void _openPrivate() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TalkAiScreen(api: widget.api, name: widget.name, engine: _engine, private: true),
      ));

  String get _greeting {
    final h = DateTime.now().hour;
    final hello = h < 5 ? 'İyi geceler' : (h < 12 ? 'Günaydın' : (h < 18 ? 'İyi günler' : 'İyi akşamlar'));
    final first = widget.name.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? hello : '$hello, $first';
  }

  @override
  Widget build(BuildContext context) {
    final screen = ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final c = TalkColors.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: widget.private ? const Color(0xFF0A0A0A) : c.msgBg,
            body: Column(children: [
              Container(color: c.chatHead, height: MediaQuery.paddingOf(context).top),
              _head(c),
              Expanded(
                child: GestureDetector(
                  onTap: () => _focus.unfocus(),
                  child: _body(c),
                ),
              ),
              if (_c.error != null && _c.messages.isEmpty)
                Padding(padding: const EdgeInsets.all(12), child: Text(_c.error!, style: talkText(14, FontWeight.w500, TalkColors.danger))),
              AttachmentStrip(controller: _c),
              _composer(c),
            ]),
          ),
        );
      },
    );
    // gizli sohbet her zaman koyu
    if (!widget.private) return screen;
    return Theme(data: arconTheme(Brightness.dark, mono: true), child: screen);
  }

  // ---------- başlık ----------

  Widget _head(TalkColors c) {
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
    final p = _c.currentProvider;
    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: c.chatHead,
      child: Row(children: [
        circleBtn(Icon(widget.private ? CupertinoIcons.xmark : CupertinoIcons.chevron_left, size: 22, color: c.ink),
            () => Navigator.of(context).maybePop(), widget.private ? 'Gizli sohbeti kapat' : 'Geri'),
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
            onTap: _pickModel,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Flexible(child: Text('ARCON AI', maxLines: 1, style: talkText(17, FontWeight.w600, c.ink, height: 1.25))),
                const SizedBox(width: 4),
                Icon(CupertinoIcons.checkmark_seal_fill, size: 16, color: c.ink),
              ]),
              if (widget.private)
                Text('Gizli sohbet', style: talkText(12.5, FontWeight.w400, c.muted))
              else if (p != null && _c.providers.length > 1)
                Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(12.5, FontWeight.w400, c.muted)),
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
              IconButton(tooltip: 'Sohbet geçmişi', onPressed: _history, icon: Icon(CupertinoIcons.clock, size: 24, color: c.ink)),
              IconButton(tooltip: 'Gizli sohbet', onPressed: _openPrivate, icon: Icon(CupertinoIcons.lock_shield, size: 24, color: c.ink)),
            ]),
          ),
      ]),
    );
  }

  void _howPrivate() => showCupertinoDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Gizli sohbet'),
          content: const Text('Bu sohbet geçmişte görünmez. Ekrandan çıktığında mesajlar sunucudan silinir.'),
          actions: [CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam'))],
        ),
      );

  // ---------- içerik ----------

  Widget _card(TalkColors c, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: c.dark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _c.sending ? null : () => _send(text),
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

  Widget _body(TalkColors c) {
    if (_c.loading) return const SkeletonChat();
    if (_c.messages.isEmpty) return widget.private ? _privateWelcome(c) : _welcome(c);
    final items = _c.messages.reversed.toList();
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: items.length + 1,
      itemBuilder: (_, i) => i == items.length ? _intro(c) : _bubble(c, items[i]),
    );
  }

  Widget _welcome(TalkColors c) => ListView(padding: const EdgeInsets.fromLTRB(20, 48, 20, 24), children: [
        const Center(child: ArconAiLogo(size: 96)),
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
          child: Text('Bugün', style: talkText(13, FontWeight.w600, c.ink)),
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

  Widget _bubble(TalkColors c, EngineMessage m) {
    final w = MediaQuery.sizeOf(context).width;
    if (m.isUser) {
      final t = m.at;
      final time = t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 48),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: m.content));
              talkToast(context, 'Kopyalandı');
            },
            child: Container(
              constraints: BoxConstraints(maxWidth: w * 0.8),
              padding: const EdgeInsets.fromLTRB(14, 9, 10, 7),
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
                if (m.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
                      for (final f in m.attachments)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(fileIcon(f.name, f.mimeType), size: 16, color: c.bubbleOutInk),
                          const SizedBox(width: 4),
                          Flexible(child: Text(f.name, overflow: TextOverflow.ellipsis, style: talkText(13, FontWeight.w500, c.bubbleOutInk))),
                        ]),
                    ]),
                  ),
                Wrap(crossAxisAlignment: WrapCrossAlignment.end, alignment: WrapAlignment.end, spacing: 8, children: [
                  Text(m.content, style: talkText(16.5, FontWeight.w400, c.bubbleOutInk, height: 1.35)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(time, style: talkText(11.5, FontWeight.w400, c.bubbleOutInk.withValues(alpha: 0.6))),
                    const SizedBox(width: 3),
                    TalkIcon(TalkSvg.ticks, width: 16, height: 11, color: c.bubbleOutInk.withValues(alpha: 0.6)),
                  ]),
                ]),
              ]),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: w * 0.94),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(color: c.bubbleIn, borderRadius: BorderRadius.circular(20)),
          child: MessageBubble(message: m, engine: _engine, conversationId: _c.conversationId ?? 0, showHeader: false),
        ),
      ),
    );
  }

  // ---------- yazma alanı ----------

  Widget _composer(TalkColors c) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Container(
      color: c.composerArea,
      padding: EdgeInsets.fromLTRB(6, 8, 10, keyboard ? 8 : bottom + 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Tooltip(
          message: 'Ekle',
          child: GestureDetector(
            onTap: _c.sending ? null : _attach,
            child: SizedBox(width: 44, height: 40, child: Icon(Icons.add, size: 30, color: c.ink)),
          ),
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
            decoration: BoxDecoration(
              color: c.composerBar,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: c.composerBorder, width: 0.6),
            ),
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              style: talkText(16.5, FontWeight.w400, c.ink, height: 1.3),
              cursorColor: c.ink,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.private ? "ARCON AI'a gizli olarak sorun" : null,
                hintStyle: talkText(16.5, FontWeight.w400, c.muted, height: 1.3),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _input,
          builder: (_, v, _) {
            if (_c.sending) return _round(c, CupertinoIcons.stop_fill, 'Durdur', _c.stop);
            if (v.text.trim().isEmpty) {
              return Tooltip(
                message: 'Kamera',
                child: GestureDetector(
                  onTap: () => _attach(preset: 'camera'),
                  child: SizedBox(width: 48, height: 40, child: Icon(CupertinoIcons.camera, size: 26, color: c.ink)),
                ),
              );
            }
            return _round(c, CupertinoIcons.arrow_up, 'Gönder', _c.canSend ? () => _send() : null);
          },
        ),
      ]),
    );
  }

  Widget _round(TalkColors c, IconData icon, String tip, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: onTap == null ? c.muted : c.accent, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: c.accentContrast),
            ),
          ),
        ),
      );
}

/// ARCON AI sohbet geçmişi: ara, aç, yeniden adlandır, sil. Seçilen sohbetin id'sini döner (0 = yeni sohbet).
class TalkAiHistoryScreen extends StatefulWidget {
  const TalkAiHistoryScreen({super.key, required this.engine});
  final EngineClient engine;

  @override
  State<TalkAiHistoryScreen> createState() => _TalkAiHistoryScreenState();
}

class _TalkAiHistoryScreenState extends State<TalkAiHistoryScreen> {
  List<EngineConversation>? _items;
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
      final list = _q.trim().isEmpty ? await widget.engine.conversations() : await widget.engine.search(_q.trim());
      if (mounted) setState(() => _items = list);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _actions(EngineConversation conv) async {
    final a = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(conv.title),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'rename'), child: const Text('Yeniden adlandır')),
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Sil')),
        ],
        cancelButton: CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (!mounted || a == null) return;
    try {
      if (a == 'delete') {
        await widget.engine.deleteConversation(conv.id);
      } else {
        final ctrl = TextEditingController(text: conv.title);
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
        await widget.engine.rename(conv.id, name);
      }
      await _load();
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message, error: true);
    }
  }

  String _when(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(l.year, l.month, l.day)).inDays;
    String two(int n) => n.toString().padLeft(2, '0');
    if (days == 0) return '${two(l.hour)}:${two(l.minute)}';
    if (days < 7) return talkDayLabel(l);
    return '${two(l.day)}.${two(l.month)}.${l.year}';
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
          IconButton(tooltip: 'Yeni sohbet', onPressed: () => Navigator.pop(context, 0), icon: Icon(CupertinoIcons.square_pencil, color: c.ink)),
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
                          return InkWell(
                            onTap: () => Navigator.pop(context, conv.id),
                            onLongPress: () => _actions(conv),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 20),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
                                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
                                child: Row(children: [
                                  Icon(CupertinoIcons.chat_bubble, size: 20, color: c.muted),
                                  const SizedBox(width: 14),
                                  Expanded(child: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(16.5, FontWeight.w500, c.ink))),
                                  const SizedBox(width: 8),
                                  Text(_when(conv.updatedAt), style: talkText(14, FontWeight.w400, c.muted)),
                                ]),
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
