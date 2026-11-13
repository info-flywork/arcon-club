import 'package:flutter/cupertino.dart';
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
import 'kariyer_positions.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';

String _date(String? iso, {bool time = false}) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final d = '${two(t.day)}.${two(t.month)}.${t.year}';
  return time ? '$d ${two(t.hour)}:${two(t.minute)}' : d;
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

const _statuses = [('new', 'Yeni'), ('review', 'Değerlendiriliyor'), ('shortlist', 'Görüşme'), ('rejected', 'Reddedildi')];

/// Skor halkası (0–100).
class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, this.size = 44});

  final int? score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: score == null ? 0 : (score! / 100).clamp(0.0, 1.0),
              strokeWidth: size > 60 ? 6 : 3.5,
              color: c.ink,
              backgroundColor: c.line,
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(score == null ? '—' : '$score', style: c.text(size > 60 ? 24 : 13, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/* ============================== Liste ============================== */

/// Kariyer (İK) — webdeki kariyer_admin: başvurular, filtreler, aday detayı.
class KariyerHomeScreen extends StatefulWidget {
  const KariyerHomeScreen({super.key, required this.session, required this.config, this.openAppId});

  final SessionController session;
  final ArconAppConfig config;
  final int? openAppId;

  @override
  State<KariyerHomeScreen> createState() => _KariyerHomeScreenState();
}

class _KariyerHomeScreenState extends State<KariyerHomeScreen> {
  static const _filters = [
    ('all', 'Tümü'),
    ('new', 'Yeni'),
    ('review', 'Değerlendiriliyor'),
    ('shortlist', 'Görüşme'),
    ('rejected', 'Reddedildi'),
    ('general', 'Genel başvuru'),
  ];

  String _filter = 'all';
  int? _position;
  Map<String, dynamic>? _data;
  String? _error;
  final _q = TextEditingController();
  int _seq = 0;
  final Set<int> _sel = {};
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _reload();
    if (widget.openAppId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openApp(widget.openAppId!));
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _reload({bool force = false}) async {
    final seq = ++_seq;
    final pos = _filter == 'general' ? null : _position;
    if (!force) {
      final c = await widget.session.api.cachedKariyerList(filter: _filter, position: pos);
      if (c != null && mounted && seq == _seq) setState(() => _data = c);
    }
    try {
      final j = await widget.session.api.kariyerList(filter: _filter, position: pos, force: force);
      if (mounted && seq == _seq) {
        setState(() {
          _data = j;
          _error = null;
        });
      }
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted || seq != _seq) return;
      if (_data == null && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'Kariyer', path: 'kariyer', replace: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  void _setFilter(String f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _data = null;
    });
    _reload();
  }

  Future<void> _openApp(int id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => KariyerAppScreen(session: widget.session, config: widget.config, id: id),
    ));
    if (mounted) _reload();
  }

  Future<void> _pickPosition() async {
    final c = ArconMono.of(context);
    final positions = ((_data?['positions'] as List?) ?? const []).whereType<Map>().toList();
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: c.bg,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('Pozisyon', style: c.text(18, weight: FontWeight.w800))),
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              title: Text('Tüm pozisyonlar', style: c.text(15, weight: _position == null ? FontWeight.w800 : FontWeight.w500)),
              trailing: _position == null ? Icon(Icons.check_rounded, color: c.ink) : null,
              onTap: () => Navigator.of(ctx).pop(0),
            ),
            for (final p in positions)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: Text(
                  '${p['title']}',
                  style: c.text(15, weight: _position == _i(p['id']) ? FontWeight.w800 : FontWeight.w500, color: p['active'] == false ? c.muted : c.ink),
                ),
                subtitle: p['active'] == false ? Text('Pasif ilan', style: c.text(12, color: c.faint)) : null,
                trailing: Text('${_i(p['count'])}', style: c.text(13, weight: FontWeight.w700, color: c.muted)),
                onTap: () => Navigator.of(ctx).pop(_i(p['id'])),
              ),
          ],
        ),
      ),
    );
    if (v == null) return;
    setState(() {
      _position = v == 0 ? null : v;
      _data = null;
    });
    _reload();
  }

  void _toggle(int id) {
    HapticFeedback.selectionClick();
    setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _bulk(String kind) async {
    final n = _sel.length;
    final (title, text, ok) = switch (kind) {
      'shortlist' => ('$n aday görüşmeye alınsın mı?', 'Adaylara görüşme e-postası gönderilir.', 'Görüşmeye al'),
      'rejected' => ('$n aday reddedilsin mi?', 'Adaylara ret e-postası gönderilir.', 'Reddet'),
      _ => ('$n başvuru silinsin mi?', 'Başvurular ve CV dosyaları kalıcı olarak silinir.', 'Sil'),
    };
    final yes = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDestructiveAction: kind != 'shortlist', onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      final r = await widget.session.api.kariyerPost(
        kind == 'delete' ? {'action': 'bulk_delete', 'ids': _sel.toList()} : {'action': 'bulk_status', 'status': kind, 'ids': _sel.toList()},
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      _toast(kind == 'delete'
          ? '${_i(r['deleted'])} başvuru silindi'
          : '$n aday güncellendi · ${_i(r['sent'])} e-posta gönderildi${_i(r['failed']) > 0 ? ', ${_i(r['failed'])} başarısız' : ''}');
      setState(() => _sel.clear());
      await _reload(force: true);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Widget _bulkBar(ArconMono c, EdgeInsets pad) {
    Widget b(IconData icon, String label, String kind, {bool danger = false}) => Expanded(
          child: TextButton.icon(
            onPressed: _bulkBusy ? null : () => _bulk(kind),
            icon: Icon(icon, size: 18, color: danger ? c.danger : c.bg),
            label: Text(label, style: c.text(12.5, weight: FontWeight.w700, color: danger ? c.danger : c.bg)),
          ),
        );
    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 12 + pad.bottom),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          b(Icons.event_available_outlined, 'Görüşme', 'shortlist'),
          b(Icons.block_rounded, 'Reddet', 'rejected'),
          b(Icons.delete_outline_rounded, 'Sil', 'delete', danger: true),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _items {
    final all = ((_data?['items'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>());
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return all.toList();
    return all.where((a) => [a['name'], a['email'], a['position'], a['city']].any((v) => _s(v).toLowerCase().contains(q))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final counts = ((_data?['counts'] as Map?) ?? const {}).cast<String, dynamic>();
    final positions = ((_data?['positions'] as List?) ?? const []).whereType<Map>().toList();
    final posTitle = _position == null ? 'Tüm pozisyonlar' : '${positions.where((p) => _i(p['id']) == _position).firstOrNull?['title'] ?? 'Pozisyon'}';
    final items = _items;
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        bottomNavigationBar: _sel.isEmpty ? null : _bulkBar(c, pad),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    if (_sel.isNotEmpty) ...[
                      IconButton(onPressed: () => setState(_sel.clear), icon: Icon(Icons.close_rounded, color: c.ink)),
                      Expanded(child: Text('${_sel.length} seçili', style: c.text(19, weight: FontWeight.w800, spacing: -0.2))),
                      TextButton(
                        onPressed: () => setState(() => _sel.addAll(items.map((a) => _i(a['id'])))),
                        child: Text('Tümünü seç', style: c.text(13, weight: FontWeight.w700)),
                      ),
                    ] else ...[
                      IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                      Text('Kariyer', style: c.text(19, weight: FontWeight.w800, spacing: -0.2)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
                        child: Text('İK', style: c.text(10.5, weight: FontWeight.w800, color: c.muted)),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => KariyerPositionsScreen(session: widget.session)));
                          if (mounted) _reload(force: true);
                        },
                        icon: Icon(Icons.work_outline_rounded, size: 18, color: c.ink),
                        label: Text('İlanlar', style: c.text(13.5, weight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                  style: c.text(15),
                  cursorColor: c.ink,
                  decoration: c.input(
                    'Aday, e-posta, pozisyon ara…',
                    Icons.search_rounded,
                    suffix: _q.text.isEmpty ? null : IconButton(onPressed: _q.clear, icon: Icon(Icons.close_rounded, size: 18, color: c.muted)),
                  ),
                ),
              ),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final (key, label) in _filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => _setFilter(key),
                          child: AnimatedContainer(
                            duration: Motion.of(context, Motion.fast),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _filter == key ? c.ink : c.bg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _filter == key ? c.ink : c.line),
                            ),
                            child: Text(
                              counts[key] != null ? '$label ${_i(counts[key])}' : label,
                              style: c.text(12, weight: FontWeight.w700, color: _filter == key ? c.bg : c.ink),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_filter != 'general')
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: positions.isEmpty ? null : _pickPosition,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                        decoration: BoxDecoration(
                          color: _position != null ? c.ink : c.field,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _position != null ? c.ink : c.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.work_outline_rounded, size: 15, color: _position != null ? c.bg : c.muted),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: Text(posTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, weight: FontWeight.w700, color: _position != null ? c.bg : c.ink)),
                            ),
                            Icon(Icons.expand_more_rounded, size: 18, color: _position != null ? c.bg : c.muted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: SkeletonSwitcher(
                  loading: _data == null && _error == null,
                  skeleton: const SkeletonList(count: 8, leadingSize: 44),
                  child: _data == null
                      ? Center(child: Text(_error ?? '', style: c.text(14, color: c.muted)))
                      : RefreshIndicator(
                          color: c.ink,
                          onRefresh: () => _reload(force: true),
                          child: items.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                  children: [
                                    const SizedBox(height: 80),
                                    Icon(Icons.person_search_outlined, size: 44, color: c.faint),
                                    const SizedBox(height: 10),
                                    Center(child: Text(_q.text.isEmpty ? 'Bu filtrede başvuru yok' : 'Aramaya uyan aday yok', style: c.text(15, weight: FontWeight.w700))),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                  padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
                                  itemCount: items.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                                  itemBuilder: (_, i) => _row(c, items[i]),
                                ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ArconMono c, Map<String, dynamic> a) {
    final status = _s(a['status']);
    final meta = [_s(a['position']), _s(a['city'])].where((e) => e.isNotEmpty).join(' · ');
    return PressScale(
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _sel.isEmpty ? _openApp(_i(a['id'])) : _toggle(_i(a['id'])),
          onLongPress: () => _toggle(_i(a['id'])),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: c.ink,
                  child: _sel.contains(_i(a['id']))
                      ? Icon(Icons.check_rounded, color: c.bg)
                      : Text(_initials(_s(a['name'])), style: c.text(14, weight: FontWeight.w800, color: c.bg)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_s(a['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(15, weight: FontWeight.w800)),
                      if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, color: c.muted)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: status == 'shortlist' ? c.ink : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: status == 'shortlist' ? c.ink : c.line),
                            ),
                            child: Text(
                              _s(a['status_label']),
                              style: c.text(10.5, weight: FontWeight.w700, color: status == 'shortlist' ? c.bg : (status == 'rejected' ? c.faint : c.muted)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_date(_s(a['created_at'])), style: c.text(11.5, color: c.faint)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _ScoreRing(score: a['score'] == null ? null : _i(a['score'])),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ============================== Aday detayı ============================== */

class KariyerAppScreen extends StatefulWidget {
  const KariyerAppScreen({super.key, required this.session, required this.config, required this.id});

  final SessionController session;
  final ArconAppConfig config;
  final int id;

  @override
  State<KariyerAppScreen> createState() => _KariyerAppScreenState();
}

class _KariyerAppScreenState extends State<KariyerAppScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  int _tab = 0;
  bool _statusBusy = false;
  bool _analyzing = false;
  final _note = TextEditingController();
  bool _noteBusy = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _app => (_data?['app'] as Map?)?.cast<String, dynamic>();

  Future<void> _start() async {
    final c = await widget.session.api.cachedKariyerApp(widget.id);
    if (c != null && mounted) setState(() => _data = c);
    await _load();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.kariyerApp(widget.id, force: force);
      if (mounted) {
        setState(() {
          _data = j;
          _error = null;
        });
      }
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _changeStatus() async {
    final a = _app;
    if (a == null || _statusBusy) return;
    final c = ArconMono.of(context);
    final picked = await showModalBottomSheet<String>(
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
              Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('Durumu değiştir', style: c.text(18, weight: FontWeight.w800))),
              for (final (key, label) in _statuses)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  title: Text(label, style: c.text(15, weight: a['status'] == key ? FontWeight.w800 : FontWeight.w500)),
                  subtitle: switch (key) {
                    'shortlist' => Text('Adaya görüşme / AI mülakat e-postası gider', style: c.text(12, color: c.muted)),
                    'rejected' => Text('Adaya ret e-postası gider', style: c.text(12, color: c.muted)),
                    _ => null,
                  },
                  trailing: a['status'] == key ? Icon(Icons.check_rounded, color: c.ink) : null,
                  onTap: () => Navigator.of(ctx).pop(key),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == a['status'] || !mounted) return;
    if (picked == 'rejected' || picked == 'shortlist') {
      final label = _statuses.firstWhere((e) => e.$1 == picked).$2;
      final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text('"$label" yapılsın mı?'),
          content: Text(picked == 'rejected'
              ? '${a['name']} adlı adaya ret e-postası gönderilecek.'
              : '${a['name']} adlı adaya görüşme daveti e-postası gönderilecek.'),
          actions: [
            CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
            CupertinoDialogAction(
              isDestructiveAction: picked == 'rejected',
              isDefaultAction: picked == 'shortlist',
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Onayla'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _statusBusy = true);
    try {
      final r = await widget.session.api.kariyerAction('status', widget.id, {'status': picked});
      HapticFeedback.mediumImpact();
      final mail = _s(r['mail']);
      _toast(switch (mail) {
        'sent' => 'Durum güncellendi, adaya e-posta gönderildi',
        'failed' => 'Durum güncellendi ama e-posta gönderilemedi',
        _ => 'Durum güncellendi',
      });
      await _load(force: true);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Future<void> _analyze() async {
    if (_analyzing) return;
    setState(() => _analyzing = true);
    try {
      await widget.session.api.kariyerAction('analyze', widget.id);
      await _load(force: true);
      if (mounted) _toast('AI değerlendirmesi güncellendi');
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _scheduleMeeting() async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(_s(_app?['meeting_at']))?.toLocal();
    final d = await showDatePicker(context: context, initialDate: cur ?? now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 540)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: cur != null ? TimeOfDay.fromDateTime(cur) : const TimeOfDay(hour: 10, minute: 0));
    if (t == null || !mounted) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final raw = '${d.year}-${two(d.month)}-${two(d.day)} ${two(t.hour)}:${two(t.minute)}';
    try {
      final r = await widget.session.api.kariyerAction('meeting', widget.id, {'meeting_at': raw});
      HapticFeedback.mediumImpact();
      await _load(force: true);
      if (mounted) {
        _toast(switch (r['mail']) {
          'sent' => 'Görüşme planlandı · adaya davet gönderildi',
          'failed' => 'Görüşme kaydedildi ama e-posta gönderilemedi',
          _ => 'Görüşme planlandı',
        });
      }
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _deleteApp() async {
    final yes = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Başvuru silinsin mi?'),
        content: const Text('Başvuru ve CV dosyası kalıcı olarak silinir.'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.session.api.kariyerAction('delete', widget.id);
      if (mounted) Navigator.of(context).pop();
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _addNote() async {
    final t = _note.text.trim();
    if (t.isEmpty || _noteBusy) return;
    setState(() => _noteBusy = true);
    try {
      final r = await widget.session.api.kariyerAction('note', widget.id, {'text': t});
      _note.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) {
        setState(() {
          final app = _app;
          if (app != null) app['notes'] = r['notes'];
        });
      }
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _noteBusy = false);
    }
  }

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    final u = Uri.tryParse(url.startsWith('http') || url.contains(':') ? url : 'https://$url');
    if (u != null) await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final a = _app;
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
                    Expanded(child: Text('Başvuru #${widget.id}', style: c.text(17, weight: FontWeight.w800))),
                    if (a != null)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz_rounded, color: c.ink),
                        color: c.bg,
                        onSelected: (v) => v == 'meeting' ? _scheduleMeeting() : _deleteApp(),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'meeting', child: Text('Görüşme planla', style: c.text(14.5))),
                          PopupMenuItem(value: 'delete', child: Text('Başvuruyu sil', style: c.text(14.5, color: c.danger))),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SkeletonSwitcher(
                  loading: a == null && _error == null,
                  skeleton: const SkeletonArticle(),
                  child: a == null
                      ? Center(child: Text(_error ?? '', style: c.text(14, color: c.muted)))
                      : RefreshIndicator(
                          color: c.ink,
                          onRefresh: () => _load(force: true),
                          child: ListView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                            padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
                            children: [
                              _header(c, a),
                              const SizedBox(height: 16),
                              _actions(c, a),
                              const SizedBox(height: 18),
                              _tabs(c),
                              const SizedBox(height: 14),
                              SwapFade(
                                alignment: Alignment.topCenter,
                                offset: 0.02,
                                child: KeyedSubtree(
                                  key: ValueKey(_tab),
                                  child: switch (_tab) {
                                    1 => _formTab(c, a),
                                    2 => _interviewTab(c, a),
                                    3 => _notesTab(c, a),
                                    _ => _analysisTab(c, a),
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ArconMono c, Map<String, dynamic> a) {
    final meta = [_s(a['city']), _s(a['experience'])].where((e) => e.isNotEmpty).join(' · ');
    final status = _s(a['status']);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: c.ink,
          child: Text(_initials(_s(a['name'])), style: c.text(19, weight: FontWeight.w800, color: c.bg)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_s(a['name']), style: c.text(22, weight: FontWeight.w800, height: 1.2, spacing: -0.5)),
              const SizedBox(height: 2),
              Text(_s(a['position']), style: c.text(14, weight: FontWeight.w600, color: c.muted)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: c.faint),
                    const SizedBox(width: 4),
                    Expanded(child: Text(meta, style: c.text(12.5, color: c.muted))),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _changeStatus,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                  decoration: BoxDecoration(
                    color: status == 'shortlist' ? c.ink : c.field,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: status == 'shortlist' ? c.ink : c.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_statusBusy)
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: status == 'shortlist' ? c.bg : c.ink))
                      else
                        Text(_s(a['status_label']), style: c.text(12, weight: FontWeight.w700, color: status == 'shortlist' ? c.bg : c.ink)),
                      Icon(Icons.expand_more_rounded, size: 16, color: status == 'shortlist' ? c.bg : c.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(ArconMono c, Map<String, dynamic> a) {
    Widget btn(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: Opacity(
            opacity: onTap == null ? 0.35 : 1,
            child: Material(
              color: c.field,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(icon, size: 20, color: c.ink),
                      const SizedBox(height: 4),
                      Text(label, style: c.text(11.5, weight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    final phone = _s(a['phone']).replaceAll(RegExp(r'[^0-9+]'), '');
    final email = _s(a['email']);
    final linkedin = _s(a['linkedin_url']);
    final cv = a['cv_url'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            btn(Icons.description_outlined, 'CV', cv == null ? null : () => _open(cv)),
            const SizedBox(width: 8),
            btn(Icons.mail_outline_rounded, 'E-posta', email.isEmpty ? null : () => launchUrl(Uri(scheme: 'mailto', path: email))),
            const SizedBox(width: 8),
            btn(Icons.call_outlined, 'Ara', phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: phone))),
            const SizedBox(width: 8),
            btn(Icons.link_rounded, 'LinkedIn', linkedin.isEmpty ? null : () => _open(linkedin)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          [
            if (email.isNotEmpty) email,
            if (_s(a['phone']).isNotEmpty) _s(a['phone']),
            'Başvuru: ${_date(_s(a['created_at']), time: true)}',
          ].join('  ·  '),
          style: c.text(12, color: c.muted, height: 1.45),
        ),
        if (_s(a['meeting_at']).isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 15, color: c.ink),
              const SizedBox(width: 6),
              Text('Görüşme: ${_date(_s(a['meeting_at']), time: true)}', style: c.text(12.5, weight: FontWeight.w700)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tabs(ArconMono c) {
    final notes = ((_app?['notes'] as List?) ?? const []).length;
    final labels = ['Değerlendirme', 'Form', 'Mülakat', notes > 0 ? 'Notlar $notes' : 'Notlar'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.line)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.fast),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _tab == i ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(labels[i], style: c.text(12, weight: FontWeight.w700, color: _tab == i ? c.bg : c.ink)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _box(ArconMono c, {String? title, required List<Widget> children}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[Text(trUpper(title), style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1)), const SizedBox(height: 6)],
            ...children,
          ],
        ),
      );

  Widget _analysisTab(ArconMono c, Map<String, dynamic> a) {
    final score = a['score'] == null ? null : _i(a['score']);
    final bars = ((a['breakdown'] as List?) ?? const []).whereType<Map>().toList();
    final general = ((a['general_evaluation'] as List?) ?? const []).map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
    final summary = _s(a['summary']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _box(c, children: [
          Row(
            children: [
              _ScoreRing(score: score, size: 76),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (final b in bars)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text('${b['label']}', style: c.text(11.5, weight: FontWeight.w600, color: c.muted))),
                                Text(score == null ? '—' : '${_i(b['value'])}', style: c.text(11.5, weight: FontWeight.w800)),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(value: score == null ? 0 : _i(b['value']) / 100, minHeight: 4, color: c.ink, backgroundColor: c.line),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_s(a['score_label']).isNotEmpty) ...[const SizedBox(height: 10), Text(_s(a['score_label']), style: c.text(13, weight: FontWeight.w700))],
        ]),
        _box(c, title: 'Kısa ön değerlendirme', children: [
          Text(summary.isEmpty ? 'Henüz AI ön değerlendirmesi yok.' : summary, style: c.text(14, height: 1.5, color: summary.isEmpty ? c.muted : c.ink)),
        ]),
        if (general.isNotEmpty)
          _box(c, title: 'Genel değerlendirme', children: [
            for (final p in general) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p, style: c.text(14, height: 1.5))),
          ]),
        if (_s(a['cover_note']).isNotEmpty)
          _box(c, title: 'Adayın notu', children: [Text(_s(a['cover_note']), style: c.text(14, height: 1.5))]),
        const SizedBox(height: 4),
        c.primaryButton(score == null ? 'Analiz et ve puanla' : 'Yeniden analiz et', busy: _analyzing, onPressed: _analyze),
        if (_analyzing) ...[
          const SizedBox(height: 8),
          Text('CV ve form inceleniyor, bu bir dakika kadar sürebilir…', textAlign: TextAlign.center, style: c.text(12, color: c.muted)),
        ],
        if (a['report_url'] != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _open(a['report_url'] as String?),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.ink,
              side: BorderSide(color: c.line),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text('Analiz PDF', style: c.text(14.5, weight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _formTab(ArconMono c, Map<String, dynamic> a) {
    final form = ((a['form'] as List?) ?? const []).whereType<Map>().toList();
    final portfolio = _s(a['portfolio_url']);
    if (form.isEmpty && portfolio.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 30),
        child: Center(child: Text('Detaylı form yanıtı yok', style: c.text(14, color: c.muted))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (portfolio.isNotEmpty)
          _box(c, title: 'Portföy', children: [
            GestureDetector(
              onTap: () => _open(portfolio),
              child: Text(portfolio, style: c.text(14, weight: FontWeight.w600).copyWith(decoration: TextDecoration.underline)),
            ),
          ]),
        for (final f in form) _box(c, title: '${f['label']}', children: [SelectableText('${f['value']}', style: c.text(14, height: 1.5))]),
      ],
    );
  }

  Widget _interviewTab(ArconMono c, Map<String, dynamic> a) {
    final iv = ((_data?['interview'] as List?) ?? const []).whereType<Map>().toList();
    if (iv.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 30),
        child: Column(
          children: [
            Icon(Icons.mic_none_rounded, size: 40, color: c.faint),
            const SizedBox(height: 8),
            Text(
              a['status'] == 'shortlist' ? 'Aday henüz AI mülakatını tamamlamadı' : 'AI mülakat, aday "Görüşme" aşamasına alınınca açılır',
              textAlign: TextAlign.center,
              style: c.text(14, color: c.muted),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < iv.length; i++)
          _box(c, title: 'Soru ${i + 1}', children: [
            Text(_s(iv[i]['question']), style: c.text(14.5, weight: FontWeight.w700, height: 1.4)),
            const SizedBox(height: 8),
            if (_s(iv[i]['transcript']).trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: SelectableText(_s(iv[i]['transcript']), style: c.text(13.5, height: 1.5)),
              )
            else
              Text('Cevap yok', style: c.text(13, color: c.faint)),
            if (iv[i]['audio_url'] != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _open(iv[i]['audio_url'] as String?),
                child: Row(
                  children: [
                    Icon(Icons.play_circle_outline_rounded, size: 20, color: c.ink),
                    const SizedBox(width: 6),
                    Text('Sesli cevabı dinle', style: c.text(13, weight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ]),
      ],
    );
  }

  Widget _notesTab(ArconMono c, Map<String, dynamic> a) {
    final notes = ((a['notes'] as List?) ?? const []).whereType<Map>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 6,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
          style: c.text(14.5, height: 1.45),
          cursorColor: c.ink,
          decoration: c.input('Aday hakkında not ekle (yalnızca İK görür)', null),
        ),
        c.primaryButton('Notu ekle', busy: _noteBusy, onPressed: _addNote),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          Center(child: Text('Henüz not yok', style: c.text(14, color: c.muted)))
        else
          for (final n in notes)
            _box(c, children: [
              Text(_s(n['text']), style: c.text(14, height: 1.5)),
              const SizedBox(height: 6),
              Text('${_s(n['author'])} · ${_date(_s(n['created_at']), time: true)}', style: c.text(11.5, color: c.faint)),
            ]),
      ],
    );
  }
}

