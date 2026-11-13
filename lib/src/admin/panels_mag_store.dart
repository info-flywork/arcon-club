import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'panel_common.dart';

/* ============================== MAG yönetimi ============================== */

/// ARCON MAG — haber ekle / düzenle / zamanla / yayınla / sil (webdeki arcon-mag_admin).
class MagAdminScreen extends StatefulWidget {
  const MagAdminScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<MagAdminScreen> createState() => _MagAdminScreenState();
}

class _MagAdminScreenState extends State<MagAdminScreen> {
  List<Map<String, dynamic>>? _posts;
  Map<String, String> _cats = const {};
  String _filter = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(panelApi, query: {'view': 'mag_posts'});
      if (!mounted) return;
      setState(() {
        _posts = [for (final p in ((j['posts'] as List?) ?? const []).whereType<Map>()) p.cast<String, dynamic>()];
        _cats = ((j['categories'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
      });
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open([int? id]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _MagEditor(session: widget.session, id: id, cats: _cats)));
    if (changed == true) {
      _load();
      await widget.session.api.cache.invalidateWhere((k) => k.startsWith('v1:mag'));
    }
  }

  static String statusLabel(String s) => switch (s) {
        'published' => 'Yayında',
        'scheduled' => 'Zamanlandı',
        _ => 'Taslak',
      };

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final list = (_posts ?? const <Map<String, dynamic>>[]).where((p) => _filter == 'all' || p['status'] == _filter).toList();
    int n(String s) => (_posts ?? const []).where((p) => p['status'] == s).length;
    return PanelPage(
      title: 'MAG yönetimi',
      fab: panelFab(c, 'Yeni haber', () => _open()),
      body: _posts == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8, leading: false, thumbnail: true))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + pad.bottom),
                children: [
                  panelChips<String>(c, [
                    ('all', 'Tümü ${_posts!.length}'),
                    ('published', 'Yayında ${n('published')}'),
                    ('scheduled', 'Zamanlı ${n('scheduled')}'),
                    ('draft', 'Taslak ${n('draft')}'),
                  ], _filter, (v) => setState(() => _filter = v)),
                  const SizedBox(height: 12),
                  for (final p in list)
                    panelCard(
                      c,
                      padding: const EdgeInsets.all(10),
                      onTap: () => _open(pi(p['id'])),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: p['cover_url'] == null
                                  ? Container(color: c.ink, child: Icon(Icons.newspaper_outlined, color: c.bg))
                                  : CachedNetworkImage(imageUrl: '${p['cover_url']}', fit: BoxFit.cover, memCacheWidth: 192, errorWidget: (_, _, _) => Container(color: c.line)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ps(p['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w700, height: 1.3)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    panelTag(c, statusLabel(ps(p['status'])), strong: p['status'] == 'published'),
                                    if (p['featured'] == true) panelTag(c, 'Öne çıkan'),
                                    Text('${_cats[ps(p['category'])] ?? p['category']} · ${pDate(ps(p['date']), time: false)} · ${p['views']} okunma',
                                        style: c.text(11, color: c.muted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _MagEditor extends StatefulWidget {
  const _MagEditor({required this.session, required this.id, required this.cats});
  final SessionController session;
  final int? id;
  final Map<String, String> cats;

  @override
  State<_MagEditor> createState() => _MagEditorState();
}

class _MagEditorState extends State<_MagEditor> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _excerpt = TextEditingController();
  final _tags = TextEditingController();
  final _body = TextEditingController();
  final _coverUrl = TextEditingController();
  final _eventLoc = TextEditingController();
  String _cat = 'all';
  bool _isCover = false, _featured = false, _mandatory = false;
  DateTime? _eventAt;
  DateTime? _publishAt;
  String? _coverPath;
  String? _coverPreview;
  String _status = 'draft';
  bool _loading = true;
  String? _busy;
  String? _ai;
  String? _error;

  @override
  void initState() {
    super.initState();
    _author.text = widget.session.user?.username ?? '';
    _load();
  }

  @override
  void dispose() {
    for (final t in [_title, _author, _excerpt, _tags, _body, _coverUrl, _eventLoc]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.id == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final j = await widget.session.api.webCall(panelApi, query: {'view': 'mag_post', 'id': '${widget.id}'});
      final p = (j['post'] as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _title.text = ps(p['title']);
        _author.text = ps(p['author_name']);
        _excerpt.text = ps(p['excerpt']);
        _tags.text = ps(p['tags']);
        _body.text = ps(p['body']);
        final cu = ps(p['cover_url']);
        if (cu.isNotEmpty && !cu.startsWith('uploads/')) _coverUrl.text = cu;
        _coverPreview = p['cover_abs'] as String?;
        _eventLoc.text = ps(p['event_location']);
        _cat = ps(p['category']).isEmpty ? 'all' : ps(p['category']);
        _isCover = pi(p['cover']) == 1;
        _featured = pi(p['featured']) == 1;
        _mandatory = pi(p['mandatory']) == 1;
        _eventAt = DateTime.tryParse(ps(p['event_at']).replaceFirst(' ', 'T'));
        _status = ps(p['status']);
        if (_status == 'scheduled') _publishAt = DateTime.tryParse(ps(p['publish_at']).replaceFirst(' ', 'T'));
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

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: initial ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial ?? now.add(const Duration(hours: 1))));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _aiFix(TextEditingController ctl, String mode) async {
    if (ctl.text.trim().isEmpty || _ai != null) return;
    setState(() => _ai = mode);
    try {
      final r = await widget.session.api.webCall('arcon-mag_ai.php', jsonBody: {'text': ctl.text, 'mode': mode}, timeout: const Duration(minutes: 2));
      final t = ps(r['text']).trim();
      if (t.isNotEmpty && mounted) setState(() => ctl.text = t);
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    } finally {
      if (mounted) setState(() => _ai = null);
    }
  }

  Future<void> _pickCover() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 88);
    if (x != null && mounted) {
      setState(() {
        _coverPath = x.path;
        _coverUrl.clear();
      });
    }
  }

  static const _errors = {
    'title': 'Başlık zorunlu.',
    'body': 'Haber metni zorunlu.',
    'cover_required': 'Kapak görseli zorunlu — dosya seç ya da bağlantı yapıştır.',
    'cover': 'Kapak dosyası geçersiz (jpg/png/webp/gif, ≤8MB).',
    'save': 'Kayıt sırasında hata oluştu.',
  };

  Future<void> _submit(String action) async {
    if (action == 'schedule' && _publishAt == null) {
      final at = await _pickDateTime(DateTime.now().add(const Duration(hours: 1)));
      if (at == null) return;
      setState(() => _publishAt = at);
    }
    if (!mounted) return;
    if (action == 'delete' && !(await pConfirm(context, 'Haber silinsin mi?', 'Bu haber kalıcı olarak silinecek.'))) return;
    setState(() {
      _busy = action;
      _error = null;
    });
    try {
      final r = await widget.session.api.webForm('arcon-mag_save.php', {
        'action': action,
        'id': '${widget.id ?? 0}',
        'title': _title.text.trim(),
        'category': _cat,
        'author_name': _author.text.trim(),
        if (_isCover) 'is_cover': '1',
        if (_featured) 'featured': '1',
        if (_mandatory) 'mandatory': '1',
        'excerpt': _excerpt.text.trim(),
        'tags': _tags.text.trim(),
        'event_at': _eventAt == null ? '' : _fmt(_eventAt!),
        'event_location': _eventLoc.text.trim(),
        'body': _body.text,
        'cover_url': _coverUrl.text.trim(),
        'publish_at': action == 'schedule' && _publishAt != null ? _fmt(_publishAt!) : '',
      }, files: [if (_coverPath != null) ('cover', _coverPath!)]);
      final err = r['err'];
      if (err != null) {
        setState(() => _error = _errors[err] ?? 'Kayıt başarısız ($err).');
        return;
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final m = r['m'];
      pToast(context, switch (m) {
        'published' => r.containsKey('mail') ? 'Yayınlandı · ${r['mail']}/${r['mailtotal']} kişiye e-posta gitti' : 'Haber yayınlandı',
        'scheduled' => 'Haber zamanlandı',
        'draft' => 'Taslak kaydedildi',
        'deleted' => 'Haber silindi',
        _ => 'Kaydedildi',
      });
      Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _aiBtn(ArconMono c, TextEditingController ctl, String mode, String label) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _ai == null ? () => _aiFix(ctl, mode) : null,
          icon: _ai == mode
              ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
              : Icon(Icons.auto_awesome_outlined, size: 16, color: c.ink),
          label: Text(label, style: c.text(12.5, weight: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return PanelPage(
      title: widget.id == null ? 'Yeni haber' : 'Haberi düzenle',
      actions: [if (widget.id != null) IconButton(onPressed: _busy == null ? () => _submit('delete') : null, icon: Icon(Icons.delete_outline_rounded, color: c.danger))],
      body: _loading
          ? const SkeletonArticle()
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
              children: [
                if (widget.id != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [panelTag(c, _MagAdminScreenState.statusLabel(_status), strong: _status == 'published')])),
                panelField(c, _title, 'Haber başlığı…', label: 'Başlık'),
                _aiBtn(c, _title, 'title', 'AI ile düzelt'),
                c.label('Kategori'),
                const SizedBox(height: 6),
                panelChips<String>(c, [for (final e in widget.cats.entries) (e.key, e.value)], _cat, (v) => setState(() => _cat = v)),
                const SizedBox(height: 12),
                panelField(c, _author, 'ör. İK Ekibi', icon: Icons.person_outline_rounded, label: 'Yazar'),
                panelSwitch(c, 'Kapak hikayesi', _isCover, (v) => setState(() => _isCover = v), hint: 'Ana sayfada tam genişlik kapak'),
                panelSwitch(c, 'Öne çıkan', _featured, (v) => setState(() => _featured = v)),
                panelSwitch(c, 'Zorunlu okuma', _mandatory, (v) => setState(() => _mandatory = v), hint: 'Okuyandan onay istenir'),
                const SizedBox(height: 8),
                panelField(c, _excerpt, 'Kısa özet (liste ve mailde görünür)', lines: 2, label: 'Özet'),
                _aiBtn(c, _excerpt, 'excerpt', 'AI ile düzelt'),
                panelField(c, _tags, 'virgülle ayır: ürün, duyuru…', icon: Icons.sell_outlined, label: 'Etiketler'),
                panelSection(c, 'Etkinlik (isteğe bağlı)'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await _pickDateTime(_eventAt);
                          if (d != null) setState(() => _eventAt = d);
                        },
                        style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(46)),
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: Text(_eventAt == null ? 'Etkinlik tarihi seç' : pDate(_eventAt!.toIso8601String()), style: c.text(13.5, weight: FontWeight.w600)),
                      ),
                    ),
                    if (_eventAt != null) IconButton(onPressed: () => setState(() => _eventAt = null), icon: Icon(Icons.close_rounded, color: c.muted)),
                  ],
                ),
                const SizedBox(height: 8),
                panelField(c, _eventLoc, 'ör. Ataşehir Ofis · Toplantı Odası 2', icon: Icons.place_outlined),
                panelSection(c, 'Haber metni'),
                panelField(c, _body, 'Haber metnini yaz ya da ham metni yapıştır…', lines: 10),
                _aiBtn(c, _body, 'body', 'AI ile haber diline çevir'),
                panelSection(c, 'Kapak görseli'),
                if (_coverPath != null || _coverPreview != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _coverPath != null
                            ? Image(image: ResizeImage(FileImage(File(_coverPath!)), width: 900), fit: BoxFit.cover)
                            : CachedNetworkImage(memCacheWidth: 1000, imageUrl: _coverPreview!, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _pickCover,
                  style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(46)),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(_coverPath == null ? 'Galeriden kapak seç' : 'Kapağı değiştir', style: c.text(13.5, weight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                panelField(c, _coverUrl, 'ya da görsel bağlantısı (https://…)', icon: Icons.link_rounded),
                if (_error != null) ...[const SizedBox(height: 6), c.errorBox(_error!)],
                const SizedBox(height: 16),
                c.primaryButton('Yayınla', busy: _busy == 'publish', onPressed: () => _submit('publish')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy == null ? () => _submit('draft') : null,
                        style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(48)),
                        child: Text(_busy == 'draft' ? 'Kaydediliyor…' : 'Taslak kaydet', style: c.text(14, weight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy == null ? () => _submit('schedule') : null,
                        style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(48)),
                        child: Text(
                          _busy == 'schedule' ? 'Zamanlanıyor…' : (_publishAt == null ? 'Zamanla' : 'Zamanla · ${pDate(_publishAt!.toIso8601String())}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: c.text(14, weight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/* ============================== Store yönetimi ============================== */

/// ARCON STORE — mağaza ekle / düzenle / sil, adresten konum bul (webdeki arcon-store_admin).
class StoreAdminScreen extends StatefulWidget {
  const StoreAdminScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<StoreAdminScreen> createState() => _StoreAdminScreenState();
}

class _StoreAdminScreenState extends State<StoreAdminScreen> {
  List<Map<String, dynamic>>? _stores;
  Map<String, String> _retailers = const {};
  Map<String, String> _zones = const {};
  String? _error;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(panelApi, query: {'view': 'store_list'});
      if (!mounted) return;
      setState(() {
        _stores = [for (final s in ((j['stores'] as List?) ?? const []).whereType<Map>()) s.cast<String, dynamic>()];
        _retailers = ((j['retailers'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
        _zones = ((j['zones'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
      });
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open([Map<String, dynamic>? s]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _StoreEditor(session: widget.session, store: s, retailers: _retailers, zones: _zones),
    ));
    if (changed == true) {
      _load();
      await widget.session.api.cache.invalidateWhere((k) => k.startsWith('v1:store'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final q = _q.text.trim().toLowerCase();
    final list = (_stores ?? const <Map<String, dynamic>>[])
        .where((s) => q.isEmpty || [s['store_name'], s['mall'], s['city'], s['district']].any((v) => ps(v).toLowerCase().contains(q)))
        .toList();
    return PanelPage(
      title: 'Store yönetimi',
      fab: panelFab(c, 'Yeni mağaza', () => _open()),
      body: _stores == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8, leading: false))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + pad.bottom),
                children: [
                  TextField(
                    controller: _q,
                    keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                    style: c.text(15),
                    cursorColor: c.ink,
                    decoration: c.input('Mağaza, AVM, şehir ara', Icons.search_rounded),
                  ),
                  const SizedBox(height: 10),
                  Text('${list.length} mağaza', style: c.text(12, weight: FontWeight.w700, color: c.muted)),
                  const SizedBox(height: 8),
                  for (final s in list)
                    panelCard(
                      c,
                      onTap: () => _open(s),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ps(s['store_name']), style: c.text(14.5, weight: FontWeight.w700)),
                                Text([ps(s['retailer_label']), ps(s['mall']), ps(s['city'])].where((e) => e.isNotEmpty).join(' · '), style: c.text(12, color: c.muted)),
                              ],
                            ),
                          ),
                          if (s['is_active'] == false) panelTag(c, 'Pasif'),
                          if (s['lat'] == null) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.location_off_outlined, size: 18, color: c.faint)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _StoreEditor extends StatefulWidget {
  const _StoreEditor({required this.session, required this.store, required this.retailers, required this.zones});
  final SessionController session;
  final Map<String, dynamic>? store;
  final Map<String, String> retailers;
  final Map<String, String> zones;

  @override
  State<_StoreEditor> createState() => _StoreEditorState();
}

class _StoreEditorState extends State<_StoreEditor> {
  late final Map<String, TextEditingController> _f = {
    for (final k in ['store_name', 'mall', 'city', 'district', 'address', 'floor_label', 'phone', 'brands', 'notes', 'source_url', 'floor_source_url', 'lat', 'lng'])
      k: TextEditingController(text: k == 'brands' ? ((widget.store?['brands'] as List?) ?? const []).join(', ') : ps(widget.store?[k])),
  };
  late String _retailer = ps(widget.store?['retailer']).isEmpty ? (widget.retailers.keys.firstOrNull ?? '') : ps(widget.store?['retailer']);
  late String _zone = ps(widget.store?['zone']);
  late bool _carries = widget.store?['carries_arcon'] != false;
  late bool _active = widget.store?['is_active'] != false;
  bool _busy = false;
  bool _geo = false;
  String? _error;

  @override
  void dispose() {
    for (final t in _f.values) {
      t.dispose();
    }
    super.dispose();
  }

  int? get _id => widget.store == null ? null : pi(widget.store!['id']);

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.webCall(panelApi, jsonBody: {
        'action': 'store_save',
        'id': ?_id,
        for (final e in _f.entries) e.key: e.value.text.trim(),
        'retailer': _retailer,
        'zone': _zone,
        'carries_arcon': _carries ? '1' : '',
        'is_active': _active ? '1' : '',
      });
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _geocode() async {
    setState(() => _geo = true);
    try {
      final r = await widget.session.api.webCall(panelApi, jsonBody: {'action': 'store_geocode', 'id': _id}, timeout: const Duration(seconds: 40));
      if (!mounted) return;
      setState(() {
        _f['lat']!.text = ps(r['lat']);
        _f['lng']!.text = ps(r['lng']);
      });
      pToast(context, 'Konum bulundu');
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    } finally {
      if (mounted) setState(() => _geo = false);
    }
  }

  Future<void> _delete() async {
    if (!await pConfirm(context, 'Mağaza silinsin mi?', '${_f['store_name']!.text} kalıcı olarak silinecek.')) return;
    try {
      await widget.session.api.webCall(panelApi, jsonBody: {'action': 'store_delete', 'id': _id});
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return PanelPage(
      title: _id == null ? 'Yeni mağaza' : 'Mağazayı düzenle',
      actions: [if (_id != null) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: c.danger))],
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
        children: [
          c.label('Zincir'),
          const SizedBox(height: 6),
          panelChips<String>(c, [for (final e in widget.retailers.entries) (e.key, e.value)], _retailer, (v) => setState(() => _retailer = v)),
          const SizedBox(height: 12),
          panelField(c, _f['store_name']!, 'ör. Beymen İstinyePark', icon: Icons.storefront_outlined, label: 'Mağaza adı'),
          panelField(c, _f['mall']!, 'AVM', icon: Icons.apartment_outlined),
          Row(
            children: [
              Expanded(child: panelField(c, _f['city']!, 'Şehir', icon: Icons.location_city_outlined)),
              const SizedBox(width: 8),
              Expanded(child: panelField(c, _f['district']!, 'İlçe')),
            ],
          ),
          panelField(c, _f['address']!, 'Adres', lines: 2),
          panelField(c, _f['floor_label']!, 'Kat (ör. Zemin kat, 1. kat)', icon: Icons.layers_outlined),
          if (widget.zones.isNotEmpty) ...[
            c.label('Bölge'),
            const SizedBox(height: 6),
            panelChips<String>(c, [for (final e in widget.zones.entries) (e.key, e.value)], _zone, (v) => setState(() => _zone = v)),
            const SizedBox(height: 12),
          ],
          panelField(c, _f['phone']!, 'Telefon', icon: Icons.call_outlined, type: TextInputType.phone),
          panelField(c, _f['brands']!, 'ARCON markaları (virgülle)', icon: Icons.sell_outlined),
          panelField(c, _f['notes']!, 'Not', lines: 2),
          panelField(c, _f['source_url']!, 'Kaynak bağlantısı', icon: Icons.link_rounded),
          panelField(c, _f['floor_source_url']!, 'Kat bilgisi kaynağı', icon: Icons.link_rounded),
          panelSection(c, 'Konum'),
          Row(
            children: [
              Expanded(child: panelField(c, _f['lat']!, 'Enlem', type: const TextInputType.numberWithOptions(decimal: true, signed: true))),
              const SizedBox(width: 8),
              Expanded(child: panelField(c, _f['lng']!, 'Boylam', type: const TextInputType.numberWithOptions(decimal: true, signed: true))),
            ],
          ),
          if (_id != null)
            OutlinedButton.icon(
              onPressed: _geo ? null : _geocode,
              style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(46)),
              icon: _geo ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)) : const Icon(Icons.my_location_rounded, size: 18),
              label: Text('Adresten konum bul', style: c.text(13.5, weight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          panelSwitch(c, 'ARCON ürünü satıyor', _carries, (v) => setState(() => _carries = v)),
          panelSwitch(c, 'Aktif (listede görünür)', _active, (v) => setState(() => _active = v)),
          if (_error != null) ...[const SizedBox(height: 8), c.errorBox(_error!)],
          const SizedBox(height: 16),
          c.primaryButton('Kaydet', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
