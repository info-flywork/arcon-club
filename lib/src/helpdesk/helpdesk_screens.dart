import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

/// Seçilen ek: ad, yerel yol ve boyut.
typedef _Pick = ({String name, String path, int size});

Future<_Pick?> _pickFile() async {
  final files = await FilePicker.pickFiles();
  if (files.isEmpty) return null;
  final f = files.first;
  final path = f.path;
  if (path == null) return null;
  return (name: f.name, path: path, size: f.lengthSync() ?? await f.length() ?? 0);
}

String _s(Object? v) => v == null ? '' : '$v';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

String _ago(String? iso) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'şimdi';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa önce';
  if (d.inDays < 7) return '${d.inDays} gün önce';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

IconData _statusIcon(String s) => switch (s) {
      'closed' => Icons.check_circle_outline_rounded,
      'in_progress' => Icons.autorenew_rounded,
      'waiting' || 'pending' => Icons.hourglass_empty_rounded,
      _ => Icons.radio_button_unchecked_rounded,
    };

Widget _tag(ArconMono c, String label, {bool strong = false, IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? c.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: strong ? c.ink : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: strong ? c.bg : c.muted), const SizedBox(width: 3)],
          Text(label, style: c.text(10.5, weight: FontWeight.w700, color: strong ? c.bg : c.muted)),
        ],
      ),
    );

/* ============================== Liste ============================== */

/// Helpdesk — webdeki helpdesk.php: aktif / yanıtlanan / kapalı talepler ve yeni talep.
class HelpdeskHomeScreen extends StatefulWidget {
  const HelpdeskHomeScreen({super.key, required this.session, required this.config, this.openTicketId});

  final SessionController session;
  final ArconAppConfig config;

  /// Bildirimden / web yolundan gelindiyse doğrudan açılacak talep.
  final int? openTicketId;

  @override
  State<HelpdeskHomeScreen> createState() => _HelpdeskHomeScreenState();
}

class _HelpdeskHomeScreenState extends State<HelpdeskHomeScreen> {
  static const _tabs = [('active', 'Aktif'), ('answered', 'Yanıtlanan'), ('closed', 'Kapalı')];
  String _tab = 'active';
  final Map<String, List<Map<String, dynamic>>> _lists = {};
  Map<String, dynamic> _counts = const {};
  bool _isAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
    if (widget.openTicketId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTicket(widget.openTicketId!));
    }
  }

  Future<void> _start() async {
    final cached = await widget.session.api.cachedHelpdeskJson('list', params: {'tab': _tab});
    if (cached != null && mounted) _apply(_tab, cached);
    await _load(_tab);
  }

  void _apply(String tab, Map<String, dynamic> j) {
    setState(() {
      _lists[tab] = [for (final t in ((j['tickets'] as List?) ?? const []).whereType<Map>()) t.cast<String, dynamic>()];
      _counts = ((j['counts'] as Map?) ?? const {}).cast<String, dynamic>();
      _isAdmin = j['is_admin'] == true;
      _error = null;
    });
  }

  Future<void> _load(String tab, {bool force = false}) async {
    try {
      final j = await widget.session.api.helpdeskJson('list', params: {'tab': tab}, force: force);
      if (mounted) _apply(tab, j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_lists.isEmpty && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'Helpdesk', path: 'helpdesk', replace: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _switch(String tab) async {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (!_lists.containsKey(tab)) {
      final cached = await widget.session.api.cachedHelpdeskJson('list', params: {'tab': tab});
      if (cached != null && mounted) _apply(tab, cached);
    }
    await _load(tab);
  }

  Future<void> _openTicket(int id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HelpdeskTicketScreen(session: widget.session, config: widget.config, id: id),
    ));
    _lists.removeWhere((k, _) => k != _tab);
    _load(_tab);
  }

  Future<void> _new() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _NewTicketScreen(session: widget.session),
    ));
    if (id == null || !mounted) return;
    _lists.clear();
    setState(() => _tab = 'active');
    _load('active');
    _openTicket(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final list = _lists[_tab];
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _new,
          backgroundColor: c.ink,
          foregroundColor: c.bg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.add_rounded),
          label: Text('Yeni talep', style: c.text(14, weight: FontWeight.w700, color: c.bg)),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Text('Helpdesk', style: c.text(19, weight: FontWeight.w800, spacing: -0.2)),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.line)),
                child: Row(
                  children: [
                    for (final (key, label) in _tabs)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _switch(key),
                          child: AnimatedContainer(
                            duration: Motion.of(context, Motion.fast),
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: _tab == key ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              _counts[key] != null ? '$label ${_i(_counts[key])}' : label,
                              style: c.text(13, weight: FontWeight.w700, color: _tab == key ? c.bg : c.ink),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SkeletonSwitcher(
                  loading: list == null && _error == null,
                  skeleton: const SkeletonList(count: 7, leadingSize: 40),
                  child: list == null
                      ? Center(child: Text(_error ?? '', style: c.text(14, color: c.muted)))
                      : RefreshIndicator(
                          color: c.ink,
                          onRefresh: () => _load(_tab, force: true),
                          child: list.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                  children: [
                                    const SizedBox(height: 90),
                                    Icon(Icons.support_agent_outlined, size: 44, color: c.faint),
                                    const SizedBox(height: 12),
                                    Center(child: Text('Bu sekmede talep yok', style: c.text(15, weight: FontWeight.w700))),
                                    const SizedBox(height: 4),
                                    Center(child: Text('Bir sorun mu var? "Yeni talep" ile bize yaz.', style: c.text(13, color: c.muted))),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                  padding: EdgeInsets.fromLTRB(20, 6, 20, 96 + pad.bottom),
                                  itemCount: list.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                                  itemBuilder: (_, i) => _row(c, list[i]),
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

  Widget _row(ArconMono c, Map<String, dynamic> t) {
    final status = _s(t['status']);
    final closed = status == 'closed';
    final meta = [
      if (_s(t['category']).isNotEmpty) _s(t['category']),
      if (_s(t['project']).isNotEmpty) _s(t['project']),
      if (_isAdmin && _s(t['owner']).isNotEmpty) _s(t['owner']),
    ].join(' · ');
    return PressScale(
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openTicket(_i(t['id'])),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: closed ? Colors.transparent : c.ink,
                    borderRadius: BorderRadius.circular(12),
                    border: closed ? Border.all(color: c.line) : null,
                  ),
                  child: Icon(_statusIcon(status), size: 20, color: closed ? c.muted : c.bg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('#${t['id']}', style: c.text(11.5, weight: FontWeight.w700, color: c.muted)),
                          const Spacer(),
                          Text(_ago(_s(t['updated_at'])), style: c.text(11.5, color: c.faint)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(_s(t['subject']), maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(15, weight: FontWeight.w700, height: 1.3)),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.muted)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _tag(c, _s(t['status_label']), strong: !closed),
                          _tag(c, _s(t['priority_label']), icon: t['priority'] == 'high' || t['priority'] == 'urgent' ? Icons.priority_high_rounded : null),
                          if (_i(t['messages']) > 1) _tag(c, '${_i(t['messages']) - 1} yanıt', icon: Icons.chat_bubble_outline_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ============================== Yeni talep ============================== */

class _NewTicketScreen extends StatefulWidget {
  const _NewTicketScreen({required this.session});

  final SessionController session;

  @override
  State<_NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<_NewTicketScreen> {
  Map<String, dynamic>? _meta;
  final _subject = TextEditingController();
  final _desc = TextEditingController();
  String? _category;
  String _priority = 'medium';
  int? _projectId;
  _Pick? _file;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void dispose() {
    _subject.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final cached = await widget.session.api.cachedHelpdeskJson('meta');
    if (cached != null && mounted) setState(() => _meta = cached);
    try {
      final j = await widget.session.api.helpdeskJson('meta');
      if (mounted) setState(() => _meta = j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted && _meta == null) setState(() => _meta = const {});
    }
  }

  Future<void> _pick() async {
    final f = await _pickFile();
    if (f == null || !mounted) return;
    if (f.size > 10 * 1024 * 1024) {
      setState(() => _error = 'Dosya en fazla 10 MB olabilir.');
      return;
    }
    setState(() {
      _file = f;
      _error = null;
    });
  }

  Future<void> _send() async {
    final subject = _subject.text.trim();
    final desc = _desc.text.trim();
    if (subject.isEmpty || desc.isEmpty) {
      setState(() => _error = 'Konu ve açıklama boş olamaz.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final r = await widget.session.api.helpdeskSend({
        'action': 'create',
        'subject': subject,
        'description': desc,
        'category': ?_category,
        'priority': _priority,
        if (_projectId != null) 'project_id': '$_projectId',
      }, filePath: _file?.path);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(_i(r['id']));
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final m = _meta;
    final cats = ((m?['categories'] as List?) ?? const []).map((e) => '$e').toList();
    final prios = ((m?['priorities'] as List?) ?? const []).whereType<Map>().toList();
    final projects = ((m?['projects'] as List?) ?? const []).whereType<Map>().toList();
    final pad = MediaQuery.paddingOf(context);
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: c.label(t));
    Widget choice(String text, bool sel, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? c.ink : c.field,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? c.ink : c.line),
            ),
            child: Text(text, style: c.text(13, weight: FontWeight.w600, color: sel ? c.bg : c.ink)),
          ),
        );
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.close_rounded, color: c.ink)),
                  Text('Yeni talep', style: c.text(19, weight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(
              child: m == null
                  ? const SkeletonList(count: 5, leading: false)
                  : ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + pad.bottom),
                      children: [
                        Text('Sorunu kısaca anlat; destek ekibi en kısa sürede dönüş yapar.', style: c.text(14, color: c.muted, height: 1.45)),
                        label('Konu'),
                        TextField(
                          controller: _subject,
                          maxLength: 200,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                          style: c.text(15),
                          cursorColor: c.ink,
                          decoration: c.input('Örn. Rapor ekranı açılmıyor', Icons.title_rounded),
                        ),
                        if (cats.isNotEmpty) ...[
                          label('Kategori'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final cat in cats) choice(cat, (_category ?? cats.first) == cat, () => setState(() => _category = cat)),
                            ],
                          ),
                        ],
                        if (prios.isNotEmpty) ...[
                          label('Öncelik'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final p in prios) choice(_s(p['label']), _priority == _s(p['key']), () => setState(() => _priority = _s(p['key']))),
                            ],
                          ),
                        ],
                        if (projects.isNotEmpty) ...[
                          label('Proje (isteğe bağlı)'),
                          DropdownButtonFormField<int?>(
                            initialValue: _projectId,
                            isExpanded: true,
                            dropdownColor: c.bg,
                            style: c.text(15),
                            decoration: c.input('Proje seç', Icons.folder_outlined),
                            items: [
                              DropdownMenuItem<int?>(value: null, child: Text('Proje yok', style: c.text(15, color: c.muted))),
                              for (final p in projects)
                                DropdownMenuItem<int?>(value: _i(p['id']), child: Text(_s(p['name']), overflow: TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setState(() => _projectId = v),
                          ),
                        ],
                        label('Açıklama'),
                        TextField(
                          controller: _desc,
                          minLines: 5,
                          maxLines: 12,
                          maxLength: 5000,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                          style: c.text(15, height: 1.45),
                          cursorColor: c.ink,
                          decoration: c.input('Ne oldu, ne bekliyordun? Adımları yazarsan daha hızlı çözeriz.', null),
                        ),
                        const SizedBox(height: 6),
                        _AttachRow(file: _file, onPick: _pick, onClear: () => setState(() => _file = null)),
                        if (_error != null) ...[const SizedBox(height: 12), c.errorBox(_error!)],
                        const SizedBox(height: 18),
                        c.primaryButton('Talebi gönder', busy: _sending, onPressed: _send),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({required this.file, required this.onPick, required this.onClear});

  final _Pick? file;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final f = file;
    return Material(
      color: c.field,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: f == null ? onPick : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            children: [
              Icon(f == null ? Icons.attach_file_rounded : Icons.insert_drive_file_outlined, size: 20, color: c.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f == null ? 'Dosya ekle (en fazla 10 MB)' : '${f.name} · ${_size(f.size)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: c.text(13.5, weight: FontWeight.w600, color: f == null ? c.muted : c.ink),
                ),
              ),
              if (f != null) IconButton(onPressed: onClear, icon: Icon(Icons.close_rounded, size: 18, color: c.muted)) else const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/* ============================== Talep detayı ============================== */

class HelpdeskTicketScreen extends StatefulWidget {
  const HelpdeskTicketScreen({super.key, required this.session, required this.config, required this.id});

  final SessionController session;
  final ArconAppConfig config;
  final int id;

  @override
  State<HelpdeskTicketScreen> createState() => _HelpdeskTicketScreenState();
}

class _HelpdeskTicketScreenState extends State<HelpdeskTicketScreen> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _statuses = const [];
  String? _error;
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  _Pick? _file;
  String? _status;
  bool _sending = false;
  int? _opening;

  Map<String, String> get _params => {'id': '${widget.id}'};

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cached = await widget.session.api.cachedHelpdeskJson('ticket', params: _params);
    if (cached != null && mounted) _apply(cached);
    await _load();
  }

  void _apply(Map<String, dynamic> j) {
    setState(() {
      _data = j;
      _error = null;
      _status ??= '${(j['ticket'] as Map?)?['status'] ?? 'open'}';
    });
    if (j['is_admin'] == true && _statuses.isEmpty) _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    try {
      final m = await widget.session.api.helpdeskJson('meta');
      if (mounted) setState(() => _statuses = [for (final s in ((m['statuses'] as List?) ?? const []).whereType<Map>()) s.cast<String, dynamic>()]);
    } on ArconApiException catch (_) {}
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.helpdeskJson('ticket', params: _params, force: force);
      if (mounted) _apply(j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_data == null && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'Talep #${widget.id}', path: 'helpdesk_view.php?id=${widget.id}', replace: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _pick() async {
    final f = await _pickFile();
    if (f == null || !mounted) return;
    if (f.size > 10 * 1024 * 1024) {
      _toast('Dosya en fazla 10 MB olabilir.');
      return;
    }
    setState(() => _file = f);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send() async {
    final msg = _reply.text.trim();
    if (msg.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.session.api.helpdeskSend({
        'action': 'reply',
        'id': '${widget.id}',
        'message': msg,
        if (_data?['is_admin'] == true) 'status': ?_status,
      }, filePath: _file?.path);
      _reply.clear();
      setState(() => _file = null);
      FocusManager.instance.primaryFocus?.unfocus();
      await _load(force: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Motion.of(context, Motion.normal), curve: Curves.easeOutCubic);
        }
      });
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openFile(Map<String, dynamic> f) async {
    final id = _i(f['id']);
    if (_opening != null) return;
    setState(() => _opening = id);
    try {
      final r = await widget.session.api.helpdeskFile(id);
      final dir = await getTemporaryDirectory();
      final name = '${r['name'] ?? f['name']}'.replaceAll(RegExp(r'[/\\]'), '_');
      final file = File('${dir.path}/hd_${id}_$name');
      await file.writeAsBytes(base64Decode(_s(r['data'])));
      await OpenFilex.open(file.path);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) _toast(e.message);
    } on Exception {
      if (mounted) _toast('Dosya açılamadı');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final d = _data;
    final t = (d?['ticket'] as Map?)?.cast<String, dynamic>();
    final msgs = ((d?['messages'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final files = ((d?['files'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final isAdmin = d?['is_admin'] == true;
    final closed = t?['status'] == 'closed';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Text('Talep #${widget.id}', style: c.text(17, weight: FontWeight.w800)),
                    const Spacer(),
                    if (t != null) _tag(c, _s(t['status_label']), strong: !closed, icon: _statusIcon(_s(t['status']))),
                  ],
                ),
              ),
              Expanded(
                child: SkeletonSwitcher(
                  loading: t == null && _error == null,
                  skeleton: const SkeletonChat(),
                  child: t == null
                      ? Center(child: Text(_error ?? '', style: c.text(14, color: c.muted)))
                      : RefreshIndicator(
                          color: c.ink,
                          onRefresh: () => _load(force: true),
                          child: ListView(
                            controller: _scroll,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                            children: [
                              Text(_s(t['subject']), style: c.text(22, weight: FontWeight.w800, height: 1.25, spacing: -0.5)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  if (_s(t['category']).isNotEmpty) _tag(c, _s(t['category'])),
                                  _tag(c, _s(t['priority_label'])),
                                  if (_s(t['project']).isNotEmpty) _tag(c, _s(t['project']), icon: Icons.folder_outlined),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                [
                                  if (_s(t['owner']).isNotEmpty) 'Açan: ${t['owner']}',
                                  if (_s(t['assignees']).isNotEmpty) 'Atanan: ${t['assignees']}',
                                  _ago(_s(t['created_at'])),
                                ].join(' · '),
                                style: c.text(12.5, color: c.muted),
                              ),
                              if (files.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                c.label('Ekler'),
                                const SizedBox(height: 8),
                                for (final f in files) _fileRow(c, f),
                              ],
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Text(trUpper('Yazışma'), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
                                  const SizedBox(width: 10),
                                  Expanded(child: Container(height: 1, color: c.line)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              for (final m in msgs) _bubble(c, m),
                            ],
                          ),
                        ),
                ),
              ),
              if (t != null) _composer(c, isAdmin, closed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileRow(ArconMono c, Map<String, dynamic> f) {
    final busy = _opening == _i(f['id']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openFile(f),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.insert_drive_file_outlined, size: 20, color: c.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_s(f['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13.5, weight: FontWeight.w600)),
                      Text('${_size(_i(f['size']))} · ${f['by']}', style: c.text(11.5, color: c.muted)),
                    ],
                  ),
                ),
                busy
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                    : Icon(Icons.download_rounded, size: 20, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(ArconMono c, Map<String, dynamic> m) {
    final mine = m['mine'] == true;
    final staff = m['staff'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mine ? 'Sen' : _s(m['user']), style: c.text(11.5, weight: FontWeight.w700, color: c.muted)),
                if (staff && !mine) ...[const SizedBox(width: 6), _tag(c, 'Destek', strong: true)],
                const SizedBox(width: 6),
                Text(_ago(_s(m['at'])), style: c.text(11, color: c.faint)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: mine ? c.ink : c.field,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: mine ? null : Border.all(color: c.line),
              ),
              child: SelectableText(_s(m['body']), style: c.text(14.5, height: 1.45, color: mine ? c.bg : c.ink)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer(ArconMono c, bool isAdmin, bool closed) {
    return Container(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (closed && !isAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text('Talep kapalı; yazarsan yeniden açılır.', style: c.text(12, color: c.muted)),
            ),
          if (isAdmin && _statuses.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in _statuses) ...[
                    GestureDetector(
                      onTap: () => setState(() => _status = _s(s['key'])),
                      child: AnimatedContainer(
                        duration: Motion.of(context, Motion.fast),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _status == _s(s['key']) ? c.ink : c.field,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: _status == _s(s['key']) ? c.ink : c.line),
                        ),
                        child: Text(_s(s['label']), style: c.text(12, weight: FontWeight.w700, color: _status == _s(s['key']) ? c.bg : c.ink)),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          if (isAdmin && _statuses.isNotEmpty) const SizedBox(height: 8),
          if (_file != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, size: 16, color: c.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${_file!.name} · ${_size(_file!.size)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, color: c.muted))),
                  GestureDetector(onTap: () => setState(() => _file = null), child: Icon(Icons.close_rounded, size: 18, color: c.muted)),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(tooltip: 'Dosya ekle', onPressed: _pick, icon: Icon(Icons.attach_file_rounded, color: c.ink)),
              Expanded(
                child: TextField(
                  controller: _reply,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                  style: c.text(15, height: 1.35),
                  cursorColor: c.ink,
                  decoration: c.input('Yanıt yaz…', null).copyWith(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        isDense: true,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              ListenableBuilder(
                listenable: _reply,
                builder: (_, _) {
                  final can = _reply.text.trim().isNotEmpty && !_sending;
                  return GestureDetector(
                    onTap: can ? _send : null,
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.fast),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: can ? c.ink : c.line, shape: BoxShape.circle),
                      child: _sending
                          ? Padding(padding: const EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: c.bg))
                          : Icon(Icons.arrow_upward_rounded, color: c.bg),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
