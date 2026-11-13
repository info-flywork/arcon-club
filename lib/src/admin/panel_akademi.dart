import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'panel_common.dart';

List<Map<String, dynamic>> _maps(Object? v) => [for (final e in ((v as List?) ?? const []).whereType<Map>()) e.cast<String, dynamic>()];

const _certLabels = {'ai': 'AI', 'ops': 'Operasyon', 'hr': 'İK', 'vis': 'Görsel', 'data': 'Veri', 'master': 'Master'};

/// ARCON Akademi yönetimi — rapor, moderasyon, sertifikalar, eğitimler (webdeki akademi_admin).
class AkademiAdminScreen extends StatefulWidget {
  const AkademiAdminScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<AkademiAdminScreen> createState() => _AkademiAdminScreenState();
}

class _AkademiAdminScreenState extends State<AkademiAdminScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  int _tab = 0;
  String _cat = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(panelApi, query: {'view': 'akademi', 'cat': _cat});
      if (mounted) {
        setState(() {
          _d = j;
          _error = null;
        });
      }
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _act(Map<String, Object?> body, String ok) async {
    try {
      await widget.session.api.webCall(panelApi, jsonBody: body);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      pToast(context, ok);
      await _load();
      await widget.session.api.cache.invalidate('v1:akademi');
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    }
  }

  Widget _report(ArconMono c) {
    final cats = _maps(_d!['categories']);
    final users = _maps(_d!['users']);
    final mods = _maps(_d!['modules']);
    final hard = _maps(_d!['hard_questions']);
    final total = pi(_d!['module_count']).clamp(1, 1 << 30);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (cats.isNotEmpty)
          panelChips<String>(c, [for (final k in cats) (ps(k['key']), ps(k['label']))], _cat, (v) {
            setState(() => _cat = v);
            _load();
          }),
        panelSection(c, 'Kullanıcı ilerlemesi · $total modül'),
        if (users.isEmpty) Text('Henüz ilerleme yok.', style: c.text(13, color: c.muted)),
        for (final u in users)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(ps(u['name']), style: c.text(14, weight: FontWeight.w600))),
                    Text('${u['completed']}/$total tamam · ${u['seen']} görüldü', style: c.text(11.5, color: c.muted)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: (pi(u['completed']) / total).clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: c.line, color: c.ink),
                ),
              ],
            ),
          ),
        if (mods.isNotEmpty) ...[
          panelSection(c, 'Modüller'),
          for (final m in mods)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text(ps(m['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13.5))),
                  Text('${m['completed']} tamam · ${m['seen']} görüldü', style: c.text(11.5, color: c.muted)),
                ],
              ),
            ),
        ],
        if (hard.isNotEmpty) ...[
          panelSection(c, 'En çok yanlış yapılan sorular'),
          for (final h in hard)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text('${h['module']} · Soru ${pi(h['index']) + 1}', style: c.text(13.5))),
                  Text('${h['wrong']} yanlış / ${pi(h['wrong']) + pi(h['correct'])}', style: c.text(11.5, color: c.muted)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _moderation(ArconMono c) {
    final items = _maps(_d!['pending']);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (items.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Onay bekleyen içerik yok.', style: c.text(14, color: c.muted)))),
        for (final it in items)
          panelCard(
            c,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    panelTag(c, it['kind'] == 'tip' ? 'İpucu' : 'Ödev', strong: true),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${it['user']} · ${it['module']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, weight: FontWeight.w700))),
                  ],
                ),
                const SizedBox(height: 8),
                Text(ps(it['body']), style: c.text(13.5, height: 1.4)),
                const SizedBox(height: 6),
                Text(pDate(ps(it['at'])), style: c.text(11, color: c.muted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _act({'action': 'ak_moderate', 'id': pi(it['id']), 'kind': it['kind'], 'decision': 'reject'}, 'Reddedildi'),
                        style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.line)),
                        child: Text('Reddet', style: c.text(13.5, weight: FontWeight.w700, color: c.danger)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _act({'action': 'ak_moderate', 'id': pi(it['id']), 'kind': it['kind'], 'decision': 'approve'}, 'Onaylandı'),
                        style: FilledButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.bg),
                        child: Text('Onayla', style: c.text(13.5, weight: FontWeight.w700, color: c.bg)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _certs(ArconMono c) {
    final certs = _maps(_d!['certificates']);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (certs.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Henüz sertifika yok.', style: c.text(14, color: c.muted)))),
        for (final ct in certs)
          panelCard(
            c,
            child: Row(
              children: [
                Icon(Icons.workspace_premium_outlined, color: ct['revoked'] == true ? c.faint : c.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${ct['name']} · ${_certLabels[ct['scope']] ?? ct['scope']}', style: c.text(14, weight: FontWeight.w700, color: ct['revoked'] == true ? c.faint : c.ink)),
                      Text('${ct['code']} · ${pDate(ps(ct['issued_at']), time: false)}', style: c.text(11.5, color: c.muted)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final revoke = ct['revoked'] != true;
                    if (revoke && !await pConfirm(context, 'Sertifika iptal edilsin mi?', '${ct['name']} kullanıcısının sertifikası geçersiz sayılacak.', ok: 'İptal et')) return;
                    await _act({'action': 'ak_cert', 'user_id': pi(ct['user_id']), 'scope': ct['scope'], 'decision': revoke ? 'revoke' : 'restore'}, revoke ? 'Sertifika iptal edildi' : 'Sertifika geri verildi');
                  },
                  child: Text(ct['revoked'] == true ? 'Geri ver' : 'İptal et', style: c.text(13, weight: FontWeight.w700, color: ct['revoked'] == true ? c.ink : c.danger)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _videos(ArconMono c) {
    final vids = _maps(_d!['videos']);
    final cats = {for (final k in _maps(_d!['categories'])) ps(k['key']): ps(k['label'])};
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (vids.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Eklenmiş eğitim yok.', style: c.text(14, color: c.muted)))),
        for (final v in vids)
          panelCard(
            c,
            onTap: () => _openQuiz(v),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ps(v['name']), style: c.text(14.5, weight: FontWeight.w700, color: v['active'] == true ? c.ink : c.faint)),
                      Text([cats[ps(v['category'])] ?? ps(v['category']), ps(v['tagline'])].where((e) => e.isNotEmpty).join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.muted)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: v['active'] == true,
                  activeTrackColor: c.ink,
                  onChanged: (on) => _act({'action': 'ak_edu_toggle', 'slug': v['slug'], 'on': on}, on ? 'Yayına alındı' : 'Yayından kaldırıldı'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _openQuiz(Map<String, dynamic> v) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _AkQuizScreen(session: widget.session, video: v)));
    if (changed == true) _load();
  }

  Future<void> _newEdu() async {
    final cats = [for (final k in _maps(_d!['categories'])) if (ps(k['key']) != 'all') (ps(k['key']), ps(k['label']))];
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _AkEduEditor(session: widget.session, categories: cats)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pending = _maps(_d?['pending']).length;
    return PanelPage(
      title: 'Akademi yönetimi',
      tabs: ['Rapor', pending > 0 ? 'Onay ($pending)' : 'Onay', 'Sertifika', 'Eğitimler'],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      fab: _tab == 3 && _d != null ? panelFab(c, 'Yeni eğitim', _newEdu) : null,
      body: _d == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8, leading: false))
          : RefreshIndicator(color: c.ink, onRefresh: _load, child: [_report, _moderation, _certs, _videos][_tab](c)),
    );
  }
}

/* ---------------- Quiz düzenleme ---------------- */

class _AkQuizScreen extends StatefulWidget {
  const _AkQuizScreen({required this.session, required this.video});
  final SessionController session;
  final Map<String, dynamic> video;

  @override
  State<_AkQuizScreen> createState() => _AkQuizScreenState();
}

class _AkQuizScreenState extends State<_AkQuizScreen> {
  List<Map<String, dynamic>>? _rows;
  bool _changed = false;

  String get _slug => ps(widget.video['slug']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(panelApi, query: {'view': 'akademi_quiz', 'slug': _slug});
      if (mounted) setState(() => _rows = _maps(j['rows']));
    } on ArconApiException catch (e) {
      if (mounted) {
        setState(() => _rows = const []);
        pToast(context, e.message);
      }
    }
  }

  Future<void> _post(Map<String, Object?> body, String ok) async {
    try {
      await widget.session.api.webCall(panelApi, jsonBody: body);
      _changed = true;
      if (!mounted) return;
      pToast(context, ok);
      await _load();
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    }
  }

  Future<void> _add() async {
    final c = ArconMono.of(context);
    final text = TextEditingController();
    final expl = TextEditingController();
    final opts = List.generate(4, (_) => TextEditingController());
    var correct = 0;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Yeni soru', style: c.text(18, weight: FontWeight.w800)),
                const SizedBox(height: 14),
                panelField(c, text, 'Soru', lines: 2),
                for (var i = 0; i < opts.length; i++)
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => set(() => correct = i),
                        icon: Icon(correct == i ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: correct == i ? c.ink : c.faint),
                      ),
                      Expanded(child: panelField(c, opts[i], 'Şık ${String.fromCharCode(65 + i)}${i < 2 ? '' : ' (isteğe bağlı)'}')),
                    ],
                  ),
                Text('Doğru şıkkı soldan işaretle.', style: c.text(11.5, color: c.muted)),
                const SizedBox(height: 10),
                panelField(c, expl, 'Açıklama (isteğe bağlı)', lines: 2),
                c.primaryButton('Ekle', busy: false, onPressed: () => Navigator.of(ctx).pop(true)),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) {
      await _post({
        'action': 'ak_quiz_add',
        'slug': _slug,
        'text': text.text.trim(),
        'options': [for (final o in opts) o.text.trim()],
        'correct': correct,
        'explanation': expl.text.trim(),
      }, 'Soru eklendi');
    }
    for (final t in [text, expl, ...opts]) {
      t.dispose();
    }
  }

  Future<void> _deleteEdu() async {
    if (!await pConfirm(context, 'Eğitim silinsin mi?', '${widget.video['name']} ve soruları kalıcı olarak silinecek.')) return;
    try {
      await widget.session.api.webCall(panelApi, jsonBody: {'action': 'ak_edu_delete', 'slug': _slug});
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: PanelPage(
        title: ps(widget.video['name']),
        actions: [IconButton(onPressed: _deleteEdu, icon: Icon(Icons.delete_outline_rounded, color: c.danger))],
        fab: panelFab(c, 'Soru ekle', _add),
        body: _rows == null
            ? const SkeletonList(count: 5, leading: false)
            : ListView(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + MediaQuery.paddingOf(context).bottom),
                children: [
                  if (_rows!.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Bu eğitimin sınav sorusu yok.', style: c.text(14, color: c.muted)))),
                  for (final r in _rows!)
                    panelCard(
                      c,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Text('${pi(r['index']) + 1}. ${r['text']}', style: c.text(14, weight: FontWeight.w700, height: 1.35))),
                              GestureDetector(
                                onTap: () async {
                                  if (await pConfirm(context, 'Soru silinsin mi?', ps(r['text']))) {
                                    await _post({'action': 'ak_quiz_delete', 'slug': _slug, 'index': pi(r['index'])}, 'Soru silindi');
                                  }
                                },
                                child: Padding(padding: const EdgeInsets.only(left: 8), child: Icon(Icons.close_rounded, size: 20, color: c.muted)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          for (var i = 0; i < (r['options'] as List? ?? const []).length; i++)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Row(
                                children: [
                                  Icon(i == pi(r['correct']) ? Icons.check_circle_rounded : Icons.circle_outlined, size: 16, color: i == pi(r['correct']) ? c.ink : c.faint),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('${(r['options'] as List)[i]}', style: c.text(13))),
                                ],
                              ),
                            ),
                          if (ps(r['explanation']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ps(r['explanation']), style: c.text(12, color: c.muted))),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/* ---------------- Yeni eğitim ---------------- */

class _AkEduEditor extends StatefulWidget {
  const _AkEduEditor({required this.session, required this.categories});
  final SessionController session;
  final List<(String, String)> categories;

  @override
  State<_AkEduEditor> createState() => _AkEduEditorState();
}

class _AkEduEditorState extends State<_AkEduEditor> {
  final _f = {
    for (final k in ['module_name', 'module_slug', 'video_title', 'video_url', 'tagline', 'purpose', 'when_text', 'steps_text', 'tips_text', 'est_minutes']) k: TextEditingController(),
  };
  late String _cat = widget.categories.firstOrNull?.$1 ?? 'ai';
  bool _required = false;
  bool _active = true;
  PlatformFile? _video;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _f['est_minutes']!.text = '8';
  }

  @override
  void dispose() {
    for (final t in _f.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final files = await FilePicker.pickFiles(type: FileType.video);
    if (files.isNotEmpty && files.first.path != null && mounted) setState(() => _video = files.first);
  }

  Future<void> _save() async {
    if (_f['module_name']!.text.trim().isEmpty) {
      setState(() => _error = 'Eğitim adı zorunlu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.webCall(
        panelApi,
        fields: {
          'action': 'ak_edu_save',
          for (final e in _f.entries) e.key: e.value.text.trim(),
          'category': _cat,
          'is_required': _required ? '1' : '0',
          'is_active': _active ? '1' : '0',
        },
        files: [if (_video?.path != null) ('video_file', _video!.path!)],
        timeout: const Duration(minutes: 10),
      );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return PanelPage(
      title: 'Yeni eğitim',
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          panelField(c, _f['module_name']!, 'ör. Draftly ile e-posta yazımı', label: 'Eğitim adı'),
          panelField(c, _f['module_slug']!, 'Modül anahtarı (isteğe bağlı, ör. draftly)', icon: Icons.tag_rounded),
          c.label('Kategori'),
          const SizedBox(height: 6),
          panelChips<String>(c, widget.categories, _cat, (v) => setState(() => _cat = v)),
          const SizedBox(height: 12),
          panelField(c, _f['tagline']!, 'Kısa açıklama', icon: Icons.short_text_rounded),
          panelField(c, _f['est_minutes']!, 'Süre (dk)', icon: Icons.timer_outlined, type: TextInputType.number),
          panelSection(c, 'Video'),
          panelField(c, _f['video_title']!, 'Video başlığı', icon: Icons.title_rounded),
          panelField(c, _f['video_url']!, 'Video bağlantısı (YouTube / mp4)', icon: Icons.link_rounded),
          OutlinedButton.icon(
            onPressed: _pickVideo,
            style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.video_file_outlined, size: 18),
            label: Text(_video == null ? 'ya da video dosyası yükle' : _video!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13.5, weight: FontWeight.w600)),
          ),
          panelSection(c, 'İçerik'),
          panelField(c, _f['purpose']!, 'Ne işe yarar?', lines: 2),
          panelField(c, _f['when_text']!, 'Ne zaman kullanılır? (satır satır)', lines: 3),
          panelField(c, _f['steps_text']!, 'Adımlar (satır satır)', lines: 3),
          panelField(c, _f['tips_text']!, 'İpuçları (satır satır)', lines: 3),
          panelSwitch(c, 'Zorunlu eğitim', _required, (v) => setState(() => _required = v)),
          panelSwitch(c, 'Yayında', _active, (v) => setState(() => _active = v)),
          Text('Sınav sorularını kaydettikten sonra eğitimin içinden ekleyebilirsin.', style: c.text(12, color: c.muted)),
          if (_error != null) ...[const SizedBox(height: 10), c.errorBox(_error!)],
          const SizedBox(height: 16),
          c.primaryButton(_busy && _video != null ? 'Video yükleniyor…' : 'Kaydet', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
