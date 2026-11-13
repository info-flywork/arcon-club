import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../admin/panel_common.dart';
import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';

/// Kariyer ilanları — listele, yeni ilan aç, düzenle, sil (webdeki "Pozisyonlar").
class KariyerPositionsScreen extends StatefulWidget {
  const KariyerPositionsScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<KariyerPositionsScreen> createState() => _KariyerPositionsScreenState();
}

class _KariyerPositionsScreenState extends State<KariyerPositionsScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.kariyerList(force: true);
      if (!mounted) return;
      setState(() => _items = [for (final p in ((j['positions'] as List?) ?? const []).whereType<Map>()) p.cast<String, dynamic>()]);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open([int? id]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => KariyerPositionEditor(session: widget.session, id: id)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final items = _items ?? const <Map<String, dynamic>>[];
    return PanelPage(
      title: 'İlanlar',
      fab: panelFab(c, 'Yeni ilan', () => _open()),
      body: _items == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 6, leading: false))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + MediaQuery.paddingOf(context).bottom),
                children: [
                  if (items.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Henüz ilan yok.', style: c.text(14, color: c.muted)))),
                  for (final p in items)
                    panelCard(
                      c,
                      onTap: () => _open(pi(p['id'])),
                      child: Row(
                        children: [
                          Icon(Icons.work_outline_rounded, color: p['active'] == false ? c.faint : c.ink),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(ps(p['title']), style: c.text(14.5, weight: FontWeight.w700, color: p['active'] == false ? c.muted : c.ink)),
                          ),
                          if (p['active'] == false) Padding(padding: const EdgeInsets.only(right: 8), child: panelTag(c, 'Pasif')),
                          Text('${pi(p['count'])} başvuru', style: c.text(12, color: c.muted)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class KariyerPositionEditor extends StatefulWidget {
  const KariyerPositionEditor({super.key, required this.session, this.id});
  final SessionController session;
  final int? id;

  @override
  State<KariyerPositionEditor> createState() => _KariyerPositionEditorState();
}

class _KariyerPositionEditorState extends State<KariyerPositionEditor> {
  final _f = {for (final k in ['title', 'slug', 'description', 'description_en', 'duties', 'duties_en', 'sort_order']) k: TextEditingController()};
  final List<(TextEditingController, TextEditingController)> _custom = [];
  final List<TextEditingController> _interview = [];
  Map<String, List<String>> _opts = const {};
  String _department = '', _workModel = 'Hibrit', _exp = '1-2 yıl', _location = 'İstanbul';
  bool _active = true, _aiInterview = false;
  String? _publicUrl;
  bool _loading = true, _busy = false;
  String? _ai;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final t in [..._f.values, ..._interview, for (final (a, b) in _custom) ...[a, b]]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.kariyerPosition(widget.id ?? 0);
      final o = ((j['options'] as Map?) ?? const {}).cast<String, dynamic>();
      final p = (j['position'] as Map?)?.cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _opts = {for (final e in o.entries) e.key: [for (final v in (e.value as List? ?? const [])) '$v']};
        if (p != null) {
          for (final k in _f.keys) {
            _f[k]!.text = ps(p[k]);
          }
          _department = ps(p['department']);
          _workModel = ps(p['work_model']).isEmpty ? _workModel : ps(p['work_model']);
          _exp = ps(p['experience_level']).isEmpty ? _exp : ps(p['experience_level']);
          _location = ps(p['location']).isEmpty ? _location : ps(p['location']);
          _active = p['is_active'] == true;
          _aiInterview = p['ai_interview'] == true;
          _publicUrl = p['public_url'] as String?;
          for (final q in (p['interview_questions_en'] as List? ?? const [])) {
            _interview.add(TextEditingController(text: '$q'));
          }
          for (final q in (p['custom_questions'] as List? ?? const []).whereType<Map>()) {
            _custom.add((TextEditingController(text: ps(q['tr'])), TextEditingController(text: ps(q['en']))));
          }
        } else {
          _department = _opts['departments']?.firstOrNull ?? '';
        }
        _loading = false;
      });
    } on ArconApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _aiText(String key, String action) async {
    final src = action == 'translate' ? _f[key.replaceAll('_en', '')]! : _f[key]!;
    if (src.text.trim().isEmpty || _ai != null) return;
    setState(() => _ai = '$key:$action');
    try {
      final r = await widget.session.api.kariyerPost({'action': action, 'text': src.text});
      final t = ps(r['text']).trim();
      if (t.isNotEmpty && mounted) setState(() => _f[key]!.text = t);
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    } finally {
      if (mounted) setState(() => _ai = null);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.kariyerPost({
        'action': 'position_save',
        'id': ?widget.id,
        for (final e in _f.entries) e.key: e.value.text.trim(),
        'department': _department,
        'work_model': _workModel,
        'experience_level': _exp,
        'location': _location,
        'is_active': _active ? 1 : 0,
        'ai_interview': _aiInterview ? 1 : 0,
        'interview_questions_en': [for (final t in _interview) t.text.trim()],
        'custom_questions': [for (final (tr, _) in _custom) tr.text.trim()],
        'custom_questions_en': [for (final (_, en) in _custom) en.text.trim()],
      });
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await pConfirm(context, 'İlan silinsin mi?', 'İlan kaldırılacak. Başvurusu olan ilanlar silinemeyebilir; bu durumda pasife alın.')) return;
    try {
      await widget.session.api.kariyerPost({'action': 'position_delete', 'id': widget.id});
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    }
  }

  Widget _aiRow(ArconMono c, List<(String, String, String)> btns) => Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          children: [
            for (final (key, action, label) in btns)
              TextButton.icon(
                onPressed: _ai == null ? () => _aiText(key, action) : null,
                icon: _ai == '$key:$action'
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                    : Icon(action == 'translate' ? Icons.translate_rounded : Icons.auto_awesome_outlined, size: 16, color: c.ink),
                label: Text(label, style: c.text(12.5, weight: FontWeight.w700)),
              ),
          ],
        ),
      );

  Widget _chips(ArconMono c, String label, String key, String value, ValueChanged<String> set) {
    final opts = _opts[key] ?? const <String>[];
    if (opts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          c.label(label),
          const SizedBox(height: 6),
          panelChips<String>(c, [for (final o in opts) (o, o == '0' ? 'Deneyimsiz' : o)], value, set),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final needsCity = const ['Ofis', 'Hibrit', 'Esnek'].contains(_workModel);
    return PanelPage(
      title: widget.id == null ? 'Yeni ilan' : 'İlanı düzenle',
      actions: [
        if (_publicUrl != null)
          IconButton(onPressed: () => launchUrl(Uri.parse(_publicUrl!), mode: LaunchMode.externalApplication), icon: Icon(Icons.open_in_new_rounded, color: c.ink)),
        if (widget.id != null) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
      ],
      body: _loading
          ? const SkeletonArticle()
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                panelField(c, _f['title']!, 'ör. Dijital Pazarlama Uzmanı', label: 'Pozisyon adı'),
                panelSwitch(c, 'Yayında', _active, (v) => setState(() => _active = v), hint: 'Kariyer sayfasında görünür, başvuru alır'),
                const SizedBox(height: 8),
                _chips(c, 'Departman', 'departments', _department, (v) => setState(() => _department = v)),
                _chips(c, 'Çalışma modeli', 'work_models', _workModel, (v) => setState(() => _workModel = v)),
                if (needsCity) _chips(c, 'Lokasyon', 'locations', _location, (v) => setState(() => _location = v)),
                _chips(c, 'Deneyim', 'experience_levels', _exp, (v) => setState(() => _exp = v)),
                panelSection(c, 'İş tanımı'),
                panelField(c, _f['description']!, 'İş tanımı (en az 20 karakter; CV analizi bunu kullanır)', lines: 6),
                _aiRow(c, [('description', 'polish', 'AI ile düzenle')]),
                panelField(c, _f['description_en']!, 'İngilizce iş tanımı', lines: 4),
                _aiRow(c, [('description_en', 'translate', 'TR\'den çevir')]),
                panelSection(c, 'Görevler'),
                panelField(c, _f['duties']!, 'Görev ve sorumluluklar (satır satır)', lines: 5),
                panelField(c, _f['duties_en']!, 'İngilizce (boş bırakırsan otomatik çevrilir)', lines: 3),
                panelSection(c, 'Başvuru formu ek soruları'),
                for (var i = 0; i < _custom.length; i++)
                  panelCard(
                    c,
                    padding: const EdgeInsets.fromLTRB(12, 12, 4, 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              panelField(c, _custom[i].$1, 'Soru ${i + 1} (TR)'),
                              panelField(c, _custom[i].$2, 'İngilizce (boşsa AI çevirir)'),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            final (a, b) = _custom.removeAt(i);
                            a.dispose();
                            b.dispose();
                          }),
                          icon: Icon(Icons.close_rounded, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                if (_custom.length < 20)
                  TextButton.icon(
                    onPressed: () => setState(() => _custom.add((TextEditingController(), TextEditingController()))),
                    icon: Icon(Icons.add_rounded, color: c.ink),
                    label: Text('Soru ekle', style: c.text(13.5, weight: FontWeight.w700)),
                  ),
                panelSection(c, 'AI sesli mülakat'),
                panelSwitch(c, 'Başvuruda AI mülakat', _aiInterview, (v) => setState(() => _aiInterview = v), hint: 'Aday başvurudan sonra sesli soruları yanıtlar'),
                if (_aiInterview) ...[
                  for (var i = 0; i < _interview.length; i++)
                    Row(
                      children: [
                        Expanded(child: panelField(c, _interview[i], 'Question ${i + 1} (EN)')),
                        IconButton(
                          onPressed: () => setState(() => _interview.removeAt(i).dispose()),
                          icon: Icon(Icons.close_rounded, color: c.muted),
                        ),
                      ],
                    ),
                  if (_interview.length < 8)
                    TextButton.icon(
                      onPressed: () => setState(() => _interview.add(TextEditingController())),
                      icon: Icon(Icons.add_rounded, color: c.ink),
                      label: Text('Mülakat sorusu ekle', style: c.text(13.5, weight: FontWeight.w700)),
                    ),
                  Text('Boş bırakırsan iş tanımından otomatik sorular üretilir.', style: c.text(11.5, color: c.muted)),
                ],
                panelSection(c, 'Gelişmiş'),
                panelField(c, _f['slug']!, 'İlan adresi (boşsa addan üretilir)', icon: Icons.link_rounded),
                panelField(c, _f['sort_order']!, 'Sıra', icon: Icons.sort_rounded, type: TextInputType.number),
                if (_error != null) ...[const SizedBox(height: 6), c.errorBox(_error!)],
                const SizedBox(height: 16),
                c.primaryButton('Kaydet', busy: _busy, onPressed: _save),
              ],
            ),
    );
  }
}
