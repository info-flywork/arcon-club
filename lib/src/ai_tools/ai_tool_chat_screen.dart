import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

/* ============================== Araç tanımları ============================== */

/// Webdeki sohbet tabanlı AI araçları (tool-engine): aynı istek biçimi, farklı alan adları.
class AiChatTool {
  const AiChatTool({
    required this.folder,
    required this.heading,
    required this.intro,
    required this.placeholder,
    required this.icon,
    this.action = 'ask',
    this.textField = 'message',
    this.resultKey = 'report',
    this.labelKey,
    this.sendsHistory = true,
    this.options = const [],
    this.optionField,
    this.suggestions = const [],
  });

  /// Sunucudaki klasör (`hr-ai`) — aynı zamanda geçmiş anahtarı.
  final String folder;
  final String heading;
  final String intro;
  final String placeholder;
  final IconData icon;
  final String action;
  final String textField;
  final String resultKey;

  /// Yanıtta kısa etiket (ör. HealthLingua `category_label`).
  final String? labelKey;
  final bool sendsHistory;

  /// Draftly ton seçimi gibi tek seçimli seçenekler (anahtar, etiket).
  final List<(String, String)> options;
  final String? optionField;
  final List<String> suggestions;

  static const all = <String, AiChatTool>{
    'hr-ai': AiChatTool(
      folder: 'hr-ai',
      heading: 'İK asistanı',
      intro: 'CV yükle ya da pozisyonu anlat; adayı değerlendirip rapor hazırlayayım.',
      placeholder: 'Mesaj yazın veya CV ekleyin…',
      icon: Icons.badge_outlined,
      suggestions: ['Bu CV’yi pazarlama uzmanı pozisyonu için değerlendir', 'Satış temsilcisi için mülakat soruları hazırla'],
    ),
    'lawpath': AiChatTool(
      folder: 'lawpath',
      heading: 'Hukuk asistanı',
      intro: 'Sözleşme ekle ya da sorunu yaz; riskleri ve önerileri çıkarayım.',
      placeholder: 'Mesaj yazın veya sözleşme ekleyin…',
      icon: Icons.gavel_rounded,
      suggestions: ['Bu sözleşmedeki riskli maddeleri listele', 'Gizlilik sözleşmesi taslağı hazırla'],
    ),
    'analytica': AiChatTool(
      folder: 'analytica',
      heading: 'Veri analizi raporu',
      intro: 'Excel, CSV ya da PDF ekle; veriyi yorumlayıp rapora dönüştüreyim.',
      placeholder: 'Bağlam yazın veya veri dosyası ekleyin…',
      icon: Icons.insights_rounded,
      action: 'analyze',
      textField: 'notes',
      sendsHistory: false,
      suggestions: ['Satış verisindeki trendleri özetle'],
    ),
    'customersuccess': AiChatTool(
      folder: 'customersuccess',
      heading: 'Müşteri hizmetleri asistanı',
      intro: 'Müşteri mesajını yapıştır; uygun ve nazik bir yanıt hazırlayayım.',
      placeholder: 'Nasıl yardımcı olabilirim?',
      icon: Icons.support_agent_rounded,
      suggestions: ['Geciken kargo şikâyetine yanıt yaz', 'İade talebine nazik bir cevap hazırla'],
    ),
    'prandbrand': AiChatTool(
      folder: 'prandbrand',
      heading: 'Kampanya stratejisti',
      intro: 'Marka ve dönemi yaz; kampanya fikri, mesaj ve kanal planı çıkarayım.',
      placeholder: 'Marka + dönem yazın (ör. Anneler Günü)…',
      icon: Icons.campaign_outlined,
      suggestions: ['Anneler Günü için parfüm kampanyası', 'Yaz sezonu güneş kremi lansmanı'],
    ),
    'trendmarket': AiChatTool(
      folder: 'trendmarket',
      heading: 'Pazar analizi asistanı',
      intro: 'Dönem, kategori veya marka yaz; pazar trendlerini analiz edeyim.',
      placeholder: 'Dönem / kategori / marka yazın…',
      icon: Icons.trending_up_rounded,
      suggestions: ['2026 cilt bakımı trendleri', 'Erkek parfüm pazarında öne çıkanlar'],
    ),
    'healthlingua': AiChatTool(
      folder: 'healthlingua',
      heading: 'Mevzuata uygun metin',
      intro: 'Ürün ya da reklam metnini yapıştır; sağlık beyanı mevzuatına uygun hâle getireyim.',
      placeholder: 'Dönüştürülecek metni yazın…',
      icon: Icons.health_and_safety_outlined,
      action: 'rewrite',
      textField: 'text',
      resultKey: 'rewritten',
      labelKey: 'category_label',
      sendsHistory: false,
    ),
    'draftly': AiChatTool(
      folder: 'draftly',
      heading: 'E-posta tonunu düzenle',
      intro: 'E-posta metnini yapıştır, tonu seç; seçtiğin tona göre yeniden yazayım.',
      placeholder: 'E-posta metnini buraya yapıştırın…',
      icon: Icons.mark_email_read_outlined,
      action: 'edit',
      textField: 'email',
      resultKey: 'edited',
      labelKey: 'tone_label',
      sendsHistory: false,
      optionField: 'tone',
      options: [
        ('corporate', 'Kurumsal'),
        ('friendly', 'Samimi'),
        ('brand', 'Marka dili'),
        ('informative', 'Bilgilendirme'),
        ('technical', 'Teknik'),
      ],
    ),
  };
}

/* ============================== Model ============================== */

class _Msg {
  _Msg({required this.role, required this.text, this.files = const [], this.pending = false});

  factory _Msg.fromJson(Map<String, dynamic> j) => _Msg(
        role: '${j['role'] ?? 'assistant'}',
        text: '${j['text'] ?? ''}',
        files: ((j['files'] as List?) ?? const []).map((e) => '$e').toList(),
      );

  final String role; // user | assistant | error
  String text;
  final List<String> files;
  String? label;
  bool pending;

  Map<String, dynamic> toJson() => {'role': role, 'text': text, 'files': files};
}

class _Session {
  _Session({required this.id, required this.title, required this.updatedAt, required this.messages});

  factory _Session.fromJson(Map<String, dynamic> j) => _Session(
        id: '${j['id']}',
        title: '${j['title'] ?? 'Sohbet'}',
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        messages: [for (final m in ((j['messages'] as List?) ?? const []).whereType<Map>()) _Msg.fromJson(m.cast<String, dynamic>())],
      );

  final String id;
  String title;
  int updatedAt;
  final List<_Msg> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt,
        'messages': [for (final m in messages.where((m) => !m.pending)) m.toJson()],
      };
}

class _Attachment {
  const _Attachment(this.path, this.name, {this.audio = false});
  final String path;
  final String name;
  final bool audio;
}

String _newId() {
  final r = math.Random();
  return 's_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';
}

/* ============================== Ekran ============================== */

/// Webdeki sohbet tabanlı AI aracının (HR-AI, LawPath, Analytica …) yerli karşılığı.
/// Aynı sunucu ucunu (`/<klasör>/api.php`) ve aynı hesap bazlı geçmişi kullanır.
class AiToolChatScreen extends StatefulWidget {
  const AiToolChatScreen({super.key, required this.session, required this.config, required this.tool, required this.title, required this.webPath});

  final SessionController session;
  final ArconAppConfig config;
  final AiChatTool tool;
  final String title;

  /// Araç uygulamada açılamazsa (sunucu güncellenmemiş) WebView'de açılacak yol.
  final String webPath;

  @override
  State<AiToolChatScreen> createState() => _AiToolChatScreenState();
}

class _AiToolChatScreenState extends State<AiToolChatScreen> {
  final List<_Session> _sessions = [];
  _Session? _current;
  bool _loadingHistory = true;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Attachment> _attachments = [];
  bool _busy = false;
  late String? _option = widget.tool.options.isEmpty ? null : widget.tool.options.first.$1;

  final _rec = AudioRecorder();
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTimer;

  AiChatTool get _t => widget.tool;

  @override
  void initState() {
    super.initState();
    // Yalnızca gönder düğmesi değişince yeniden kur (her tuşta tüm sohbet ekranını kurma)
    var wasEmpty = _input.text.trim().isEmpty;
    _input.addListener(() {
      final empty = _input.text.trim().isEmpty;
      if (empty != wasEmpty) setState(() => wasEmpty = empty);
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _rec.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final j = await widget.session.api.toolHistoryLoad(_t.folder);
      final list = [for (final s in ((j['sessions'] as List?) ?? const []).whereType<Map>()) _Session.fromJson(s.cast<String, dynamic>())]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(list);
        _loadingHistory = false;
      });
    } on ArconApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      if (e.code == 'tool_unavailable') _fallback();
    }
  }

  void _fallback() {
    openWebFallback(context, session: widget.session, config: widget.config, title: widget.title, path: widget.webPath, replace: true);
  }

  void _saveHistory() {
    final cur = _current;
    if (cur != null && !_sessions.contains(cur)) _sessions.insert(0, cur);
    _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    widget.session.api.toolHistorySave(_t.folder, [for (final s in _sessions) s.toJson()], cur?.id);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.of(context, Motion.normal), curve: Curves.easeOutCubic);
      }
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  /* ---------- Ekler ---------- */

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    if (!mounted) return;
    setState(() {
      for (final f in files) {
        final p = f.path;
        if (p != null && _attachments.length < 6) _attachments.add(_Attachment(p, f.name));
      }
    });
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      _recTimer?.cancel();
      final path = await _rec.stop();
      setState(() => _recording = false);
      if (path != null && (DateTime.now().difference(_recStart ?? DateTime.now()).inMilliseconds > 700)) {
        setState(() => _attachments.add(_Attachment(path, 'Ses kaydı.m4a', audio: true)));
      }
      return;
    }
    if (!await _rec.hasPermission()) {
      _toast('Mikrofon izni gerekli');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/tool_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: path);
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _recStart = DateTime.now();
    });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /* ---------- Gönder ---------- */

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (_busy || (text.isEmpty && _attachments.isEmpty)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final atts = List<_Attachment>.of(_attachments);
    final cur = _current ??= _Session(id: _newId(), title: 'Sohbet', updatedAt: 0, messages: []);
    final prior = cur.messages.where((m) => m.role != 'error' && !m.pending).toList();
    if (cur.messages.isEmpty) {
      final base = text.isNotEmpty ? text : atts.first.name;
      cur.title = base.length > 60 ? '${base.substring(0, 57)}…' : base;
    }
    final assistant = _Msg(role: 'assistant', text: '', pending: true);
    setState(() {
      cur.messages.add(_Msg(role: 'user', text: text, files: [for (final a in atts) a.name]));
      cur.messages.add(assistant);
      cur.updatedAt = DateTime.now().millisecondsSinceEpoch;
      _attachments.clear();
      _input.clear();
      _busy = true;
    });
    _scrollToEnd();
    try {
      final r = await widget.session.api.toolPost(
        _t.folder,
        {
          'action': _t.action,
          _t.textField: text,
          'session_id': cur.id,
          'session_title': cur.title,
          'msg_count': '${prior.length}',
          'user_name': widget.session.user?.username ?? '',
          if (_t.optionField != null && _option != null) _t.optionField!: _option!,
          if (_t.sendsHistory)
            'history': _historyJson([
              for (final m in prior)
                {'role': m.role, 'content': [if (m.text.isNotEmpty) m.text, if (m.files.isNotEmpty) 'Dosyalar: ${m.files.join(', ')}'].join('\n\n')},
            ]),
        },
        files: [for (final a in atts) a.path],
      );
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(() {
        assistant
          ..text = '${r[_t.resultKey] ?? ''}'.trim()
          ..label = _t.labelKey == null ? null : (r[_t.labelKey] as String?)
          ..pending = false;
        if (assistant.text.isEmpty) assistant.text = 'Yanıt alınamadı.';
        cur.updatedAt = DateTime.now().millisecondsSinceEpoch;
      });
      _saveHistory();
    } on ArconApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'tool_unavailable') {
        _fallback();
        return;
      }
      setState(() {
        cur.messages.remove(assistant);
        cur.messages.add(_Msg(role: 'error', text: e.message));
      });
    } finally {
      for (final a in atts.where((a) => a.audio)) {
        unawaited(File(a.path).delete().catchError((_) => File(a.path)));
      }
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  static String _historyJson(List<Map<String, String>> h) {
    final trimmed = h.length > 16 ? h.sublist(h.length - 16) : h;
    return jsonEncode([
      for (final m in trimmed) {'role': m['role'], 'content': (m['content'] ?? '').length > 8000 ? m['content']!.substring(0, 8000) : m['content']},
    ]);
  }

  /* ---------- Geçmiş ---------- */

  void _newChat() {
    if (_busy) return;
    setState(() {
      _current = null;
      _attachments.clear();
    });
  }

  Future<void> _openHistory() async {
    final c = ArconMono.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bg,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('Geçmiş sohbetler', style: c.text(18, weight: FontWeight.w800))),
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
              if (_sessions.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  child: Text('Henüz sohbet yok.', textAlign: TextAlign.center, style: c.text(14, color: c.muted)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + MediaQuery.paddingOf(ctx).bottom),
                    children: [
                      for (final s in _sessions)
                        Dismissible(
                          key: ValueKey(s.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                          ),
                          onDismissed: (_) {
                            setState(() {
                              _sessions.remove(s);
                              if (_current?.id == s.id) _current = null;
                            });
                            setSheet(() {});
                            widget.session.api.toolHistorySave(_t.folder, [for (final x in _sessions) x.toJson()], _current?.id);
                          },
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            selected: _current?.id == s.id,
                            selectedTileColor: c.field,
                            leading: Icon(Icons.chat_bubble_outline_rounded, color: c.muted, size: 20),
                            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w600)),
                            subtitle: Text(
                              s.messages.lastWhere((m) => m.role == 'assistant', orElse: () => _Msg(role: 'x', text: '')).text.replaceAll(RegExp(r'[#*_`>\n]+'), ' ').trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: c.text(12, color: c.muted),
                            ),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              setState(() => _current = s);
                              _scrollToEnd();
                            },
                          ),
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

  /* ---------- Arayüz ---------- */

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final msgs = _current?.messages ?? const <_Msg>[];
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
                    IconButton(tooltip: 'Yeni sohbet', onPressed: _current == null ? null : _newChat, icon: Icon(Icons.edit_square, color: _current == null ? c.faint : c.ink, size: 21)),
                    IconButton(tooltip: 'Geçmiş', onPressed: _openHistory, icon: Icon(Icons.history_rounded, color: c.ink)),
                  ],
                ),
              ),
              Expanded(
                child: SwapFade(
                  child: KeyedSubtree(
                    key: ValueKey(_current?.id ?? 'empty'),
                    child: msgs.isEmpty
                        ? _empty(c)
                        : ListView.builder(
                            controller: _scroll,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: msgs.length,
                            itemBuilder: (_, i) => _bubble(c, msgs[i]),
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(20)),
              child: Icon(_t.icon, color: c.bg, size: 30),
            ),
          ),
          const SizedBox(height: 18),
          Text(_t.heading, textAlign: TextAlign.center, style: c.text(24, weight: FontWeight.w800, spacing: -0.6)),
          const SizedBox(height: 8),
          Text(_t.intro, textAlign: TextAlign.center, style: c.text(14.5, color: c.muted, height: 1.5)),
          if (_t.suggestions.isNotEmpty) ...[
            const SizedBox(height: 24),
            for (final s in _t.suggestions)
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
          ],
          if (_loadingHistory) ...[
            const SizedBox(height: 24),
            const SkeletonList(count: 2, leading: false),
          ] else if (_sessions.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(trUpper('Son sohbetler'), style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
            const SizedBox(height: 6),
            for (final s in _sessions.take(3))
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(Icons.chat_bubble_outline_rounded, size: 19, color: c.muted),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14, weight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
                onTap: () {
                  setState(() => _current = s);
                  _scrollToEnd();
                },
              ),
          ],
        ],
      );

  Widget _bubble(ArconMono c, _Msg m) {
    if (m.role == 'user') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14, left: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (m.files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final f in m.files) _fileChip(c, f)],
                ),
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
    if (m.role == 'error') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.danger.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(m.text, style: c.text(13.5, color: c.danger))),
            ],
          ),
        ),
      );
    }
    // asistan
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(9)),
            child: Icon(_t.icon, size: 16, color: c.bg),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: m.pending
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        const _Dots(),
                        const SizedBox(width: 10),
                        Text('Hazırlanıyor…', style: c.text(13, color: c.muted)),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.label != null && m.label!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
                            child: Text(m.label!, style: c.text(11, weight: FontWeight.w700, color: c.muted)),
                          ),
                        ),
                      MarkdownBody(
                        data: m.text,
                        selectable: true,
                        onTapLink: (_, href, _) {
                          final u = href == null ? null : Uri.tryParse(href);
                          if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
                        },
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                          p: c.text(15, height: 1.55),
                          h1: c.text(20, weight: FontWeight.w800),
                          h2: c.text(17.5, weight: FontWeight.w800),
                          h3: c.text(16, weight: FontWeight.w700),
                          listBullet: c.text(15),
                          strong: c.text(15, weight: FontWeight.w700),
                          blockquoteDecoration: BoxDecoration(
                            color: c.field,
                            border: Border(left: BorderSide(color: c.ink, width: 3)),
                          ),
                          code: TextStyle(fontFamily: 'Menlo', fontSize: 13, color: c.ink, backgroundColor: c.field),
                          codeblockDecoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(10)),
                          tableBorder: TableBorder.all(color: c.line),
                          tableColumnWidth: const IntrinsicColumnWidth(),
                          tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          tableHead: c.text(13.5, weight: FontWeight.w700),
                          tableBody: c.text(13.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _miniAction(c, Icons.copy_rounded, 'Kopyala', () {
                            Clipboard.setData(ClipboardData(text: m.text));
                            _toast('Kopyalandı');
                          }),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction(ArconMono c, IconData icon, String label, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: c.muted),
              const SizedBox(width: 4),
              Text(label, style: c.text(12, weight: FontWeight.w600, color: c.muted)),
            ],
          ),
        ),
      );

  Widget _fileChip(ArconMono c, String name, {VoidCallback? onRemove, bool audio = false}) => Container(
        padding: EdgeInsets.fromLTRB(10, 6, onRemove == null ? 10 : 4, 6),
        decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(audio ? Icons.graphic_eq_rounded : Icons.insert_drive_file_outlined, size: 15, color: c.muted),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, weight: FontWeight.w600)),
            ),
            if (onRemove != null)
              GestureDetector(onTap: onRemove, child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 16, color: c.muted))),
          ],
        ),
      );

  Widget _composer(ArconMono c) {
    final canSend = !_busy && (_input.text.trim().isNotEmpty || _attachments.isNotEmpty);
    final secs = _recording ? DateTime.now().difference(_recStart ?? DateTime.now()).inSeconds : 0;
    return Container(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_t.options.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final (key, label) in _t.options)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _option = key),
                        child: AnimatedContainer(
                          duration: Motion.of(context, Motion.fast),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _option == key ? c.ink : c.field,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: _option == key ? c.ink : c.line),
                          ),
                          child: Text(label, style: c.text(12, weight: FontWeight.w700, color: _option == key ? c.bg : c.ink)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_t.options.isNotEmpty) const SizedBox(height: 8),
          if (_attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in _attachments) _fileChip(c, a.name, audio: a.audio, onRemove: () => setState(() => _attachments.remove(a))),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(tooltip: 'Dosya ekle', onPressed: _busy || _recording ? null : _pickFiles, icon: Icon(Icons.attach_file_rounded, color: c.ink)),
              Expanded(
                child: _recording
                    ? Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                        child: Row(
                          children: [
                            Icon(Icons.fiber_manual_record_rounded, size: 12, color: c.danger),
                            const SizedBox(width: 8),
                            Text('Kaydediliyor  ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}', style: c.text(14, weight: FontWeight.w600)),
                          ],
                        ),
                      )
                    : TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                        style: c.text(15, height: 1.35),
                        cursorColor: c.ink,
                        decoration: c.input(_t.placeholder, null).copyWith(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              isDense: true,
                            ),
                      ),
              ),
              const SizedBox(width: 6),
              if (!canSend && !_busy)
                GestureDetector(
                  onTap: _toggleRecord,
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.fast),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: _recording ? c.danger : c.field, shape: BoxShape.circle, border: _recording ? null : Border.all(color: c.line)),
                    child: Icon(_recording ? Icons.stop_rounded : Icons.mic_none_rounded, color: _recording ? Colors.white : c.ink),
                  ),
                )
              else
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

/// Yanıt beklenirken üç nokta.
class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: 0.25 + 0.75 * (0.5 + 0.5 * math.sin((_c.value * 2 * math.pi) - i * 0.9)).clamp(0.0, 1.0),
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle)),
              ),
            ),
        ],
      ),
    );
  }
}
