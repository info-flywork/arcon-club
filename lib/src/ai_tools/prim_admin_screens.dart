import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../admin/panel_common.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'tool_common.dart';

/* =====================================================================
 * Prim yönetimi — web panelindeki (prim.fly-work.com) kurallar ve veri kontrolü sayfaları:
 * Prim Kuralları · Satış Satırı Sorunları · Satır Kontrolü · Uniq Kod Farkları ·
 * Excel Karşılaştır · Değişiklik Geçmişi
 * =================================================================== */

List<Map<String, dynamic>> _maps(Object? v) => [for (final e in ((v as List?) ?? const []).whereType<Map>()) e.cast<String, dynamic>()];
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _say(Object? v) {
  final neg = _d(v) < 0;
  final s = _d(v).abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

String _tl(Object? v, {bool decimals = false}) {
  if (v == null) return '—';
  final x = _d(v);
  if (!decimals) return '${_say(x)} TL';
  final parts = x.abs().toStringAsFixed(2).split('.');
  return '${x < 0 ? '-' : ''}${_say(double.parse(parts[0]))},${parts[1]} TL';
}

String _oran(Object? v) {
  final s = _d(v).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}

class PrimApiError implements Exception {
  PrimApiError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// prim.fly-work.com/api istemcisi (web panelinin kullandığı uçlar).
class PrimApi {
  const PrimApi(this.base);
  final String base;

  Future<dynamic> call(String method, String path, {Object? body, Duration timeout = const Duration(seconds: 60)}) async {
    final uri = Uri.parse('$base$path');
    final h = {'Content-Type': 'application/json'};
    final res = await switch (method) {
      'POST' => http.post(uri, headers: h, body: jsonEncode(body ?? {})),
      'PUT' => http.put(uri, headers: h, body: jsonEncode(body ?? {})),
      'DELETE' => http.delete(uri),
      _ => http.get(uri),
    }
        .timeout(timeout);
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw PrimApiError('Prim sunucusu beklenmeyen yanıt verdi (HTTP ${res.statusCode}).');
    }
    if (res.statusCode >= 400 || (j is Map && j['hata'] != null)) {
      throw PrimApiError(j is Map && j['hata'] != null ? '${j['hata']}' : 'İşlem başarısız (HTTP ${res.statusCode}).');
    }
    return j;
  }

  Future<dynamic> get(String path) => call('GET', path);
}

String _err(Object e) => e is PrimApiError ? e.message : 'Prim sistemine ulaşılamadı.';

/* ------------------------------ menü ------------------------------ */

class PrimAdminHubScreen extends StatelessWidget {
  const PrimAdminHubScreen({super.key, required this.api, this.periodId});
  final String api;
  final int? periodId;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final p = PrimApi(api);
    final items = <(IconData, String, String, Widget Function())>[
      (Icons.tune_rounded, 'Prim Kuralları', 'Onaylı kural seti, oranları güncelle', () => PrimRulesScreen(api: p)),
      (Icons.link_off_rounded, 'Satış Satırı Sorunları', 'Eşleşmeyen ürün, mağaza ve uzman satırları', () => PrimIssuesScreen(api: p, periodId: periodId)),
      (Icons.fact_check_outlined, 'Satır Kontrolü', 'Satır satır prim hesabı ve durumları', () => PrimRowsScreen(api: p, periodId: periodId)),
      (Icons.qr_code_2_rounded, 'Uniq Kod Farkları', 'Uniq listesi ↔ Stok Liste ↔ veritabanı', () => PrimUniqScreen(api: p)),
      (Icons.compare_arrows_rounded, 'Excel Karşılaştır', 'Excel prim çalışmasını sistemle kıyasla', () => PrimCompareScreen(api: p, periodId: periodId)),
      (Icons.history_rounded, 'Değişiklik Geçmişi', 'Kim, ne zaman, neyi değiştirdi', () => PrimAuditScreen(api: p)),
    ];
    return PanelPage(
      title: 'Prim yönetimi',
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          for (final (icon, title, sub, build) in items)
            panelCard(
              c,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => build())),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: c.bg, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: c.text(15, weight: FontWeight.w700)),
                    Text(sub, style: c.text(12, color: c.muted)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: c.faint),
              ]),
            ),
        ],
      ),
    );
  }
}

/* ------------------------------ ortak: dönem seçici ------------------------------ */

class _PeriodBar extends StatefulWidget {
  const _PeriodBar({required this.api, required this.value, required this.onChanged});
  final PrimApi api;
  final int? value;
  final ValueChanged<int> onChanged;
  @override
  State<_PeriodBar> createState() => _PeriodBarState();
}

class _PeriodBarState extends State<_PeriodBar> {
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    widget.api.get('/donemler').then((r) {
      final l = _maps(r)..sort((a, b) => (_d(b['yil']) * 100 + _d(b['ay'])).compareTo(_d(a['yil']) * 100 + _d(a['ay'])));
      if (!mounted) return;
      setState(() => _list = l);
      if (widget.value == null && l.isNotEmpty) {
        final pick = l.where((p) => p['durum'] != 'acik').firstOrNull ?? l.first;
        widget.onChanged(pi(pick['id']));
      }
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final l = _list;
    if (l == null) return const SizedBox(height: 40, child: Center(child: CupertinoActivityIndicator()));
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final p in l)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => widget.onChanged(pi(p['id'])),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: pi(p['id']) == widget.value ? c.ink : c.field,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: pi(p['id']) == widget.value ? c.ink : c.line),
                  ),
                  child: Text(ps(p['ad']), style: c.text(12.5, weight: FontWeight.w700, color: pi(p['id']) == widget.value ? c.bg : c.ink)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _stat(ArconMono c, String label, String value, {String? sub, Color? color}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trUpper(label), maxLines: 2, style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 0.4)),
        const SizedBox(height: 4),
        Text(value, style: c.text(19, weight: FontWeight.w800, color: color)),
        if (sub != null) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(11, color: c.muted)),
      ]),
    );

Widget _grid(List<Widget> children) => LayoutBuilder(
      builder: (_, box) {
        final w = (box.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      },
    );

Widget _search(ArconMono c, String hint, ValueChanged<String> onChanged) => TextField(
      onChanged: onChanged,
      keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
      style: c.text(15),
      cursorColor: c.ink,
      decoration: c.input(hint, Icons.search_rounded),
    );

Widget _mono(ArconMono c, String s, {Color? color}) => Text(s.isEmpty ? '—' : s, style: c.text(12.5, color: color).copyWith(fontFamily: 'Menlo'));

/* ------------------------------ Prim Kuralları ------------------------------ */

class PrimRulesScreen extends StatefulWidget {
  const PrimRulesScreen({super.key, required this.api});
  final PrimApi api;
  @override
  State<PrimRulesScreen> createState() => _PrimRulesScreenState();
}

class _PrimRulesScreenState extends State<PrimRulesScreen> {
  static const _types = {'kural': 'Standart kural', 'grup_toplam': 'Grup toplamı', 'bonus': 'Bonus'};
  List<Map<String, dynamic>>? _rules;
  String? _error;
  String _q = '';
  String _type = 'tumu';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('/kurallar');
      if (mounted) setState(() => _rules = _maps(r));
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _edit(Map<String, dynamic> k) async {
    final c = ArconMono.of(context);
    final ctl = TextEditingController(text: _oran(k['prim_oran']));
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Oranı düzenle', style: c.text(18, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(ps(k['kriter_adi']), style: c.text(13, color: c.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            style: c.text(18, weight: FontWeight.w700),
            cursorColor: c.ink,
            decoration: c.input('Oran (%) — 0 ile 10 arası', Icons.percent_rounded),
          ),
          const SizedBox(height: 14),
          c.primaryButton('Kaydet', busy: false, onPressed: () => Navigator.of(ctx).pop(ctl.text)),
        ]),
      ),
    );
    ctl.dispose();
    if (v == null) return;
    final oran = double.tryParse(v.replaceAll(',', '.').trim());
    if (oran == null || oran < 0 || oran > 10) {
      if (mounted) pToast(context, 'Oran 0 ile 10 arasında olmalı.');
      return;
    }
    try {
      await widget.api.call('PUT', '/kural/${k['id']}', body: {'prim_oran': oran});
      HapticFeedback.mediumImpact();
      if (mounted) pToast(context, '${k['kriter_adi']} oranı %${_oran(oran)} olarak güncellendi.');
      await _load();
    } catch (e) {
      if (mounted) pToast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final all = _rules ?? const <Map<String, dynamic>>[];
    final q = _q.trim().toLowerCase();
    final list = all.where((k) {
      if (_type != 'tumu' && k['satir_tipi'] != _type) return false;
      if (q.isEmpty) return true;
      return [k['kanal'], k['bolum_adi'], k['marka_grubu_adi'], k['kriter_adi'], k['kriter_tipi'], k['not_metni']].any((v) => ps(v).toLowerCase().contains(q));
    }).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final k in list) {
      groups.putIfAbsent('${k['kanal']} · ${k['bolum_adi']}${ps(k['marka_grubu_adi']).isEmpty ? '' : ' — ${k['marka_grubu_adi']}'}', () => []).add(k);
    }
    final groupCount = all.map((k) => '${k['kanal']}|${k['bolum_adi']}|${k['marka_grubu_adi'] ?? ''}').toSet().length;
    final types = all.map((k) => ps(k['satir_tipi'])).where((t) => t.isNotEmpty).toSet().toList();
    return PanelPage(
      title: 'Prim Kuralları',
      body: _rules == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8, leading: false))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Row(children: [
                    Expanded(child: _stat(c, 'Toplam kural', '${all.length}')),
                    const SizedBox(width: 8),
                    Expanded(child: _stat(c, 'Kural grubu', '$groupCount')),
                    const SizedBox(width: 8),
                    Expanded(child: _stat(c, 'Bonus', '${all.where((k) => k['satir_tipi'] == 'bonus').length}')),
                  ]),
                  const SizedBox(height: 12),
                  _search(c, 'Kural, kanal, marka veya kriter ara…', (v) => setState(() => _q = v)),
                  const SizedBox(height: 8),
                  panelChips<String>(c, [('tumu', 'Tümü'), for (final t in types) (t, _types[t] ?? t)], _type, (v) => setState(() => _type = v)),
                  const SizedBox(height: 4),
                  Text('${list.length} kural · orana dokunarak düzenle', style: c.text(12, color: c.muted)),
                  const SizedBox(height: 8),
                  if (groups.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Eşleşen kural bulunamadı.', style: c.text(14, color: c.muted)))),
                  for (final e in groups.entries)
                    panelCard(
                      c,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(e.key, style: c.text(14, weight: FontWeight.w800))),
                          panelTag(c, '${e.value.length}'),
                        ]),
                        const SizedBox(height: 6),
                        for (final k in e.value)
                          InkWell(
                            onTap: () => _edit(k),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(ps(k['kriter_adi']), style: c.text(13.5, weight: FontWeight.w600)),
                                    Text(
                                      [ps(k['kriter_tipi']), _types[ps(k['satir_tipi'])] ?? ps(k['satir_tipi']), ps(k['not_metni'])].where((s) => s.isNotEmpty).join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: c.text(11.5, color: c.muted),
                                    ),
                                  ]),
                                ),
                                const SizedBox(width: 8),
                                Text('%${_oran(k['prim_oran'])}', style: c.text(15, weight: FontWeight.w800)),
                                Icon(Icons.edit_outlined, size: 15, color: c.faint),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }
}

/* ------------------------------ Satış Satırı Sorunları ------------------------------ */

class PrimIssuesScreen extends StatefulWidget {
  const PrimIssuesScreen({super.key, required this.api, this.periodId});
  final PrimApi api;
  final int? periodId;
  @override
  State<PrimIssuesScreen> createState() => _PrimIssuesScreenState();
}

class _PrimIssuesScreenState extends State<PrimIssuesScreen> {
  static const _status = {
    'urun_yok': ('Ürün yok', 'Satış satırındaki barkod/referans, sistemdeki ürün listesinde yok.'),
    'magaza_yok': ('Mağaza yok', 'Dosyadaki mağaza adı, sistemdeki standart mağaza adıyla eşleşmedi.'),
    'uzman_yok': ('Uzman yok', 'Dosyadaki uzman adı sistemde kayıtlı değil.'),
    'atama_yok': ('Atama yok', 'Uzman var ama bu dönemde o mağazaya atanmamış (Uzman-Mağaza-Grup).'),
    'urun_cakisma': ('Ürün çakışması', 'Aynı barkod/referans birden fazla ürüne bağlı; hangisi olduğu belli değil.'),
    'kimlik_gecersiz': ('Kimlik geçersiz', 'Barkod veya referans boş/okunaksız.'),
  };

  late int? _pid = widget.periodId;
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _stores = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.get('/magazalar').then((r) {
      if (mounted) setState(() => _stores = _maps(r));
    }).catchError((Object _) {});
    if (_pid != null) _load();
  }

  Future<void> _load() async {
    final id = _pid;
    if (id == null) return;
    try {
      final r = await widget.api.get('/eslesmeyen/$id');
      if (mounted && id == _pid) {
        setState(() {
          _d = (r as Map).cast<String, dynamic>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _remap() async {
    setState(() => _busy = true);
    try {
      await widget.api.call('POST', '/donemler/$_pid/urunleri-yeniden-esle', timeout: const Duration(minutes: 3));
      if (mounted) pToast(context, 'Açık dönem ürünleri yeniden eşlendi.');
      await _load();
    } catch (e) {
      if (mounted) pToast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _alias(String raw) async {
    final c = ArconMono.of(context);
    var q = '';
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final list = _stores.where((m) => q.isEmpty || ps(m['prim_magaza']).toLowerCase().contains(q.toLowerCase()) || ps(m['bayi']).toLowerCase().contains(q.toLowerCase())).toList();
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.8,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Standart mağaza seç', style: c.text(17, weight: FontWeight.w800)),
                Text('Dosyadaki ad: $raw', style: c.text(12.5, color: c.muted)),
                const SizedBox(height: 10),
                _search(c, 'Mağaza ara', (v) => set(() => q = v)),
                Expanded(
                  child: ListView(children: [
                    for (final m in list)
                      ListTile(
                        title: Text(ps(m['prim_magaza']), style: c.text(14.5)),
                        subtitle: Text(ps(m['bayi']), style: c.text(12, color: c.muted)),
                        onTap: () => Navigator.of(ctx).pop(pi(m['id'])),
                      ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (id == null) return;
    try {
      await widget.api.call('POST', '/magaza-alias', body: {'alias': raw, 'magaza_id': id, 'kaynak': 'zeops'});
      if (mounted) pToast(context, 'Mağaza eşlemesi kaydedildi. Dönemi yeniden eşleyin.');
    } catch (e) {
      if (mounted) pToast(context, _err(e));
    }
  }

  Future<void> _link(Map<String, dynamic> row, {int? conflictId, String? conflictType}) async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _LinkProductScreen(api: widget.api, periodId: _pid!, row: row, conflictId: conflictId, conflictType: conflictType),
    ));
    if (done == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final d = _d;
    final cards = [
      for (final o in _maps(d?['ozet'])) {'kaynak': 'Zeops', ...o},
      for (final o in _maps(d?['selloutOzet'])) {'kaynak': 'Sell-out', ...o},
    ];
    Widget productRows(String title, String sub, List<Map<String, dynamic>> rows, String source) => rows.isEmpty
        ? const SizedBox.shrink()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            panelSection(c, title),
            Text(sub, style: c.text(12, color: c.muted)),
            const SizedBox(height: 8),
            for (final u in rows)
              panelCard(
                c,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    panelTag(c, _status[ps(u['eslesme_durum'])]?.$1 ?? ps(u['eslesme_durum']), strong: true),
                    const Spacer(),
                    Text('${_say(u['adet'])} adet', style: c.text(12.5, weight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  Text(ps(u['etiket']).isEmpty ? '—' : ps(u['etiket']), style: c.text(13.5, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(children: [Text('Barkod  ', style: c.text(11.5, color: c.muted)), _mono(c, ps(u['barkod']))]),
                  Row(children: [Text('Referans  ', style: c.text(11.5, color: c.muted)), _mono(c, ps(u['kod']))]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _link({...u, 'kaynak': source}),
                      icon: Icon(Icons.link_rounded, size: 18, color: c.ink),
                      label: Text('Ürüne bağla', style: c.text(13, weight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
          ]);
    return PanelPage(
      title: 'Satış Satırı Sorunları',
      actions: [
        if (_pid != null)
          IconButton(
            tooltip: 'Dönemi yeniden eşle',
            onPressed: _busy ? null : _remap,
            icon: _busy ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)) : Icon(Icons.sync_rounded, color: c.ink),
          ),
      ],
      body: Column(children: [
        _PeriodBar(
          api: widget.api,
          value: _pid,
          onChanged: (v) {
            setState(() {
              _pid = v;
              _d = null;
            });
            _load();
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: d == null
              ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 6, leading: false))
              : RefreshIndicator(
                  color: c.ink,
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
                    children: [
                      Text(
                        'Zeops ve Sell-out dosyalarındaki satış satırları ürün–mağaza–uzman kayıtlarıyla eşleştirilir. Eşleşmeyen satırlar prim hesabına girmez.',
                        style: c.text(12.5, color: c.muted, height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      if (cards.isEmpty)
                        panelCard(c, child: Text('Bu dönemde satış satırı sorunu yok — hepsi eşleşmiş.', style: c.text(13.5, weight: FontWeight.w600)))
                      else
                        _grid([
                          for (final o in cards)
                            _stat(c, '${o['kaynak']} · ${_status[ps(o['eslesme_durum'])]?.$1 ?? o['eslesme_durum']}', _say(o['sayi']),
                                sub: _status[ps(o['eslesme_durum'])]?.$2),
                        ]),
                      productRows('Zeops’ta ürün bulunamayan', 'Zeops Ham Data: barkod/referans sistem ürününe bağlanamadı.', _maps(d['urunler']), 'zeops'),
                      productRows('Sell-out’ta ürün bulunamayan', 'Sell-out Data: Arcon barkod/referans sistem ürününe bağlanamadı.', _maps(d['selloutUrunler']), 'sellout'),
                      if (_maps(d['cakismalar']).isNotEmpty) ...[
                        panelSection(c, 'Kimlik çakışmaları'),
                        for (final k in _maps(d['cakismalar']))
                          panelCard(
                            c,
                            onTap: () => _link({'deger_ham': k['deger_ham']}, conflictId: pi(k['id']), conflictType: ps(k['tip'])),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${k['tip']} · ${ps(k['deger_ham']).isEmpty ? k['deger_normalize'] : k['deger_ham']}', style: c.text(13.5, weight: FontWeight.w600)),
                                  Text('Kaynak: ${k['kaynak']}', style: c.text(11.5, color: c.muted)),
                                ]),
                              ),
                              Text('Çöz', style: c.text(13, weight: FontWeight.w700)),
                            ]),
                          ),
                      ],
                      if (_maps(d['magazalar']).isNotEmpty) ...[
                        panelSection(c, 'Mağaza adı eşleşmeyenler'),
                        Text('Dosyadaki yazımı standart mağazaya bağla.', style: c.text(12, color: c.muted)),
                        const SizedBox(height: 8),
                        for (final m in _maps(d['magazalar']))
                          panelCard(
                            c,
                            onTap: () => _alias(ps(m['magaza_ham'])),
                            child: Row(children: [
                              Expanded(child: Text(ps(m['magaza_ham']), style: c.text(13.5, weight: FontWeight.w600))),
                              Text('${m['satir']} satır  ', style: c.text(12, color: c.muted)),
                              Icon(Icons.chevron_right_rounded, color: c.faint),
                            ]),
                          ),
                      ],
                      if (_maps(d['uzmanlar']).isNotEmpty) ...[
                        panelSection(c, 'Uzman / atama sorunları'),
                        Text('Çözüm: bu dönem için Uzman-Mağaza-Grup dosyasını Veri yükleme ekranından yeniden yükle.', style: c.text(12, color: c.muted)),
                        const SizedBox(height: 8),
                        for (final u in _maps(d['uzmanlar']))
                          panelCard(
                            c,
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(ps(u['uzman_ham']), style: c.text(13.5, weight: FontWeight.w600)),
                                  Text(ps(u['magaza_ham']), style: c.text(12, color: c.muted)),
                                ]),
                              ),
                              Text('${u['satir']} satır', style: c.text(12, color: c.muted)),
                            ]),
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ]),
    );
  }
}

class _LinkProductScreen extends StatefulWidget {
  const _LinkProductScreen({required this.api, required this.periodId, required this.row, this.conflictId, this.conflictType});
  final PrimApi api;
  final int periodId;
  final Map<String, dynamic> row;
  final int? conflictId;
  final String? conflictType;
  @override
  State<_LinkProductScreen> createState() => _LinkProductScreenState();
}

class _LinkProductScreenState extends State<_LinkProductScreen> {
  List<Map<String, dynamic>> _results = const [];
  int? _sel;
  Timer? _t;
  bool _busy = false;
  final _uniq = TextEditingController();
  final _brand = TextEditingController();
  late final _name = TextEditingController(text: ps(widget.row['etiket']));

  @override
  void dispose() {
    _t?.cancel();
    _uniq.dispose();
    _brand.dispose();
    _name.dispose();
    super.dispose();
  }

  void _searchChanged(String q) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 2) {
        setState(() => _results = const []);
        return;
      }
      try {
        final r = await widget.api.get('/urunler?q=${Uri.encodeQueryComponent(q.trim())}');
        if (mounted) setState(() => _results = _maps(r));
      } catch (_) {}
    });
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    setState(() => _busy = true);
    try {
      await f();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      pToast(context, ok);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) pToast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bind(String type) {
    final r = widget.row;
    if (widget.conflictId != null) {
      return _run(() => widget.api.call('POST', '/urun-cakismalari/${widget.conflictId}/coz', body: {'urun_id': _sel, 'donem_id': widget.periodId}),
          'Çakışma çözüldü ve dönem yeniden eşlendi.');
    }
    final value = type == 'barkod' ? ps(r['barkod']) : ps(r['kod']);
    return _run(
      () => widget.api.call('POST', '/urunler/$_sel/kimlik', body: {'tip': type, 'deger': value, 'donem_id': widget.periodId, 'kaynak': ps(r['kaynak']).isEmpty ? 'manuel' : r['kaynak']}),
      'Kimlik bağlandı ve açık dönem yeniden eşlendi.',
    );
  }

  Future<void> _create() {
    final r = widget.row;
    final src = ps(r['kaynak']).isEmpty ? 'manuel' : ps(r['kaynak']);
    return _run(
      () => widget.api.call('POST', '/urunler', body: {
        'uniq_kod': _uniq.text.trim(),
        'marka': _brand.text.trim(),
        'urun_adi': _name.text.trim().isEmpty ? ps(r['etiket']) : _name.text.trim(),
        'identifiers': [
          if (ps(r['barkod']).isNotEmpty) {'tip': 'barkod', 'deger': r['barkod'], 'kaynak': src},
          if (ps(r['kod']).isNotEmpty) {'tip': 'referans', 'deger': r['kod'], 'kaynak': src},
        ],
        'donem_id': widget.periodId,
      }),
      'Yeni ürün oluşturuldu ve dönem yeniden eşlendi.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final r = widget.row;
    final conflict = widget.conflictId != null;
    return PanelPage(
      title: conflict ? 'Çakışmayı çöz' : 'Ürüne bağla',
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          panelCard(
            c,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ps(r['etiket']).isNotEmpty ? ps(r['etiket']) : ps(r['deger_ham']), style: c.text(14, weight: FontWeight.w700)),
              if (!conflict) ...[
                const SizedBox(height: 4),
                Row(children: [Text('Barkod  ', style: c.text(12, color: c.muted)), _mono(c, ps(r['barkod']))]),
                Row(children: [Text('Referans  ', style: c.text(12, color: c.muted)), _mono(c, ps(r['kod']))]),
                const SizedBox(height: 6),
                Text('Mevcut bir ürüne bağlarsan bu barkod/referans o ürünün kimliği olur; sonraki yüklemelerde otomatik eşleşir.', style: c.text(12, color: c.muted)),
              ],
            ]),
          ),
          panelSection(c, 'Mevcut ürünü seç'),
          _search(c, 'Ad, UNIQ, barkod veya referansla ara', _searchChanged),
          const SizedBox(height: 6),
          for (final u in _results.take(30))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_sel == pi(u['id']) ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: c.ink),
              title: Text(ps(u['urun_adi']), style: c.text(13.5, weight: FontWeight.w600)),
              subtitle: Text('${u['uniq_kod']} · ${u['marka']}', style: c.text(12, color: c.muted)),
              onTap: () => setState(() => _sel = pi(u['id'])),
            ),
          const SizedBox(height: 8),
          if (conflict)
            Opacity(opacity: _sel == null ? 0.4 : 1, child: c.primaryButton('Çakışmayı bu ürüne çöz', busy: _busy, onPressed: () => _sel == null ? null : _bind(widget.conflictType ?? 'barkod')))
          else
            Row(children: [
              Expanded(
                child: Opacity(
                  opacity: _sel == null || ps(r['barkod']).isEmpty ? 0.4 : 1,
                  child: c.primaryButton('Barkodu bağla', busy: _busy, onPressed: () {
                    if (_sel != null && ps(r['barkod']).isNotEmpty) _bind('barkod');
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _sel == null || ps(r['kod']).isEmpty || _busy ? null : () => _bind('referans'),
                  style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(52)),
                  child: Text('Referansı bağla', style: c.text(14, weight: FontWeight.w700)),
                ),
              ),
            ]),
          if (!conflict) ...[
            panelSection(c, 'Yeni ürün oluştur'),
            panelField(c, _uniq, 'UNIQ kod (zorunlu)', icon: Icons.qr_code_rounded),
            panelField(c, _brand, 'Marka (zorunlu)', icon: Icons.sell_outlined),
            panelField(c, _name, 'Ürün adı', icon: Icons.inventory_2_outlined),
            OutlinedButton(
              onPressed: _busy ? null : () {
                if (_uniq.text.trim().isEmpty || _brand.text.trim().isEmpty) {
                  pToast(context, 'UNIQ kod ve marka zorunlu');
                } else {
                  _create();
                }
              },
              style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(50)),
              child: Text('Oluştur ve bağla', style: c.text(14, weight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

/* ------------------------------ Satır Kontrolü (mutabakat) ------------------------------ */

class PrimRowsScreen extends StatefulWidget {
  const PrimRowsScreen({super.key, required this.api, this.periodId});
  final PrimApi api;
  final int? periodId;
  @override
  State<PrimRowsScreen> createState() => _PrimRowsScreenState();
}

class _PrimRowsScreenState extends State<PrimRowsScreen> {
  late int? _pid = widget.periodId;
  Map<String, dynamic>? _d;
  String? _error;
  String _status = '';
  int? _expert;
  int? _store;
  String? _brand;
  String _q = '';
  Timer? _t;
  bool _exporting = false;
  List<Map<String, dynamic>> _experts = const [], _stores = const [];
  List<String> _brands = const [];

  @override
  void initState() {
    super.initState();
    Future.wait([widget.api.get('/uzmanlar'), widget.api.get('/magazalar'), widget.api.get('/markalar')]).then((r) {
      if (!mounted) return;
      setState(() {
        _experts = _maps(r[0]);
        _stores = _maps(r[1]);
        _brands = [for (final b in (r[2] as List? ?? const [])) '$b'];
      });
    }).catchError((Object _) {});
    if (_pid != null) _load();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _pid;
    if (id == null) return;
    final q = {
      if (_expert != null) 'uzman': '$_expert',
      if (_store != null) 'magaza': '$_store',
      'marka': ?_brand,
      if (_status.isNotEmpty) 'durum': _status,
      if (_q.trim().isNotEmpty) 'q': _q.trim(),
    };
    try {
      final r = await widget.api.get('/mutabakat/$id${q.isEmpty ? '' : '?${Uri(queryParameters: q).query}'}');
      if (mounted && id == _pid) {
        setState(() {
          _d = (r as Map).cast<String, dynamic>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  void _reload() {
    setState(() => _d = null);
    _load();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('${widget.api.base}/mutabakat/$_pid/export')).timeout(const Duration(minutes: 2));
      if (res.statusCode != 200) throw Exception();
      if (mounted) await toolShareBytes(context, res.bodyBytes, 'Satir-Kontrolu-$_pid.xlsx');
    } catch (_) {
      if (mounted) toolToast(context, 'Excel alınamadı');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  (String, bool) _rowStatus(String a) {
    if (a.isEmpty) return ('—', false);
    if (a == 'Ok') return ('Ok', false);
    if (a.startsWith('Kısmi')) return ('Kısmi Ok', false);
    if (a.startsWith('Mükerrer')) return ('Mükerrer Giriş', true);
    if (a.startsWith('Sell-out')) return ('Sell-out kaydı yok', true);
    return (a, false);
  }

  Future<T?> _pick<T>(String title, List<(T, String)> items) {
    final c = ArconMono.of(context);
    var q = '';
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.75,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: c.text(17, weight: FontWeight.w800)),
              const SizedBox(height: 10),
              _search(c, 'Ara', (v) => set(() => q = v)),
              Expanded(
                child: ListView(children: [
                  for (final (v, l) in items.where((i) => q.isEmpty || i.$2.toLowerCase().contains(q.toLowerCase())))
                    ListTile(title: Text(l, style: c.text(14.5)), onTap: () => Navigator.of(ctx).pop(v)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(ArconMono c, String label, bool on, VoidCallback onTap, VoidCallback? onClear) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 7, 8, 7),
          decoration: BoxDecoration(color: on ? c.ink : c.bg, borderRadius: BorderRadius.circular(9), border: Border.all(color: on ? c.ink : c.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, weight: FontWeight.w700, color: on ? c.bg : c.ink))),
            const SizedBox(width: 2),
            if (on && onClear != null)
              GestureDetector(onTap: onClear, child: Icon(Icons.close_rounded, size: 16, color: c.bg))
            else
              Icon(Icons.expand_more_rounded, size: 16, color: on ? c.bg : c.muted),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final d = _d;
    final ozet = ((d?['ozet'] as Map?) ?? const {}).cast<String, dynamic>();
    final rows = _maps(d?['satirlar']);
    final sel = _maps(d?['secilenOzet']);
    final expertName = _experts.where((e) => pi(e['id']) == _expert).map((e) => ps(e['ad_soyad'])).firstOrNull;
    final storeName = _stores.where((e) => pi(e['id']) == _store).map((e) => ps(e['prim_magaza'])).firstOrNull;
    return PanelPage(
      title: 'Satır Kontrolü',
      actions: [
        if (_pid != null)
          IconButton(
            tooltip: 'Excel indir',
            onPressed: _exporting ? null : _export,
            icon: _exporting ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)) : Icon(Icons.grid_on_rounded, color: c.ink),
          ),
      ],
      body: Column(children: [
        _PeriodBar(
          api: widget.api,
          value: _pid,
          onChanged: (v) {
            _pid = v;
            _reload();
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            color: c.ink,
            onRefresh: _load,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (ozet.isNotEmpty)
                  _grid([
                    _stat(c, 'Toplam satır', _say(ozet['toplam']), sub: 'Prime esas ${_tl(ozet['toplam_esas'])}'),
                    _stat(c, 'Ok', _say(ozet['ok_'])),
                    _stat(c, 'Kısmi Ok', _say(ozet['kismi'])),
                    _stat(c, 'Mükerrer / Sell-out yok', '${_say(ozet['mukerrer'])} / ${_say(ozet['sellout_yok'])}', color: const Color(0xFFDC2626)),
                  ]),
                const SizedBox(height: 12),
                _search(c, 'Ürün, UNIQ, uzman veya mağaza ara', (v) {
                  _q = v;
                  _t?.cancel();
                  _t = Timer(const Duration(milliseconds: 450), _load);
                }),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _filterChip(c, const {'': 'Tüm durumlar', 'ok': 'Ok', 'kismi': 'Kısmi Ok', 'mukerrer': 'Mükerrer', 'sellout_yok': 'Sell-out yok'}[_status] ?? 'Durum', _status.isNotEmpty, () async {
                    final v = await _pick<String>('Durum', const [('', 'Tüm durumlar'), ('ok', 'Ok'), ('kismi', 'Kısmi Ok'), ('mukerrer', 'Mükerrer Giriş'), ('sellout_yok', 'Sell-out kaydı yok')]);
                    if (v != null) {
                      _status = v;
                      _reload();
                    }
                  }, () {
                    _status = '';
                    _reload();
                  }),
                  _filterChip(c, expertName ?? 'Tüm uzmanlar', _expert != null, () async {
                    final v = await _pick<int>('Uzman', [for (final e in _experts) (pi(e['id']), ps(e['ad_soyad']))]);
                    if (v != null) {
                      _expert = v;
                      _reload();
                    }
                  }, () {
                    _expert = null;
                    _reload();
                  }),
                  _filterChip(c, storeName ?? 'Tüm mağazalar', _store != null, () async {
                    final v = await _pick<int>('Mağaza', [for (final e in _stores) (pi(e['id']), ps(e['prim_magaza']))]);
                    if (v != null) {
                      _store = v;
                      _reload();
                    }
                  }, () {
                    _store = null;
                    _reload();
                  }),
                  _filterChip(c, _brand ?? 'Tüm markalar', _brand != null, () async {
                    final v = await _pick<String>('Marka', [for (final b in _brands) (b, b)]);
                    if (v != null) {
                      _brand = v;
                      _reload();
                    }
                  }, () {
                    _brand = null;
                    _reload();
                  }),
                ]),
                if (sel.isNotEmpty) ...[
                  panelSection(c, '${sel.first['ad_soyad']} — hesaplanan prim'),
                  for (final s in sel)
                    panelCard(
                      c,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(ps(s['prim_magaza']), style: c.text(13.5, weight: FontWeight.w700))),
                          Text(_tl(s['toplam_prim']), style: c.text(15, weight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          'Prime esas ${_tl(s['prime_esas_toplam'])} · %${_oran(s['toplam_oran'])}\n'
                          'Satış ${_tl(s['satis_prim'])} · Hedef ${_tl(s['hedef_prim'])} · Sıralama ${_tl(s['siralama_prim'])} · Bonus ${_tl(s['bonus_prim'])} · Ek ${_tl(s['ek_prim'])}',
                          style: c.text(11.5, color: c.muted, height: 1.4),
                        ),
                      ]),
                    ),
                ],
                panelSection(c, d == null ? 'Satırlar' : '${rows.length} satır${rows.length >= 5000 ? ' (ilk 5000)' : ''}'),
                if (d == null)
                  (_error != null ? Text(_error!, style: c.text(13, color: c.muted)) : const SkeletonList(count: 5, leading: false, padding: EdgeInsets.zero))
                else if (rows.isEmpty)
                  Text('Bu filtrelerle satır yok.', style: c.text(13, color: c.muted))
                else
                  for (final r in rows.take(300))
                    panelCard(
                      c,
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          panelTag(c, _rowStatus(ps(r['aciklama'])).$1, strong: _rowStatus(ps(r['aciklama'])).$2),
                          const Spacer(),
                          Text(_tl(r['satir_prim_tl'], decimals: true), style: c.text(13.5, weight: FontWeight.w800)),
                        ]),
                        const SizedBox(height: 6),
                        Text(ps(r['uniq_ad']).isEmpty ? ps(r['etiket']) : ps(r['uniq_ad']), style: c.text(13.5, weight: FontWeight.w600)),
                        Text('${r['marka'] ?? ''} · ${r['uniq_kod'] ?? ''}', style: c.text(11.5, color: c.muted)),
                        const SizedBox(height: 4),
                        Text('${r['uzman'] ?? '—'} · ${r['sellout_magaza'] ?? r['beyan_magaza'] ?? '—'}', style: c.text(12, color: c.muted)),
                        const SizedBox(height: 4),
                        Text(
                          'Beyan ${_say(r['beyan_adet'])} · Prim adedi ${_say(r['prim_adet'])} · Birim ${_tl(r['birim_ciro'], decimals: true)} · Esas ${_tl(r['prime_esas_tutar'], decimals: true)}',
                          style: c.text(11.5, color: c.muted),
                        ),
                        if (ps(r['aciklama']).length > 12) Text(ps(r['aciklama']), style: c.text(11, color: c.faint)),
                      ]),
                    ),
                if (rows.length > 300) Padding(padding: const EdgeInsets.only(top: 6), child: Text('İlk 300 satır gösteriliyor; tamamı için filtrele ya da Excel indir.', style: c.text(12, color: c.muted))),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/* ------------------------------ Uniq Kod Farkları ------------------------------ */

class PrimUniqScreen extends StatefulWidget {
  const PrimUniqScreen({super.key, required this.api});
  final PrimApi api;
  @override
  State<PrimUniqScreen> createState() => _PrimUniqScreenState();
}

class _PrimUniqScreenState extends State<PrimUniqScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  int _tab = 0;
  String _dbTab = 'farkli';
  String _sheetTab = 'cakisma';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.call('GET', '/uniq-farklar', timeout: const Duration(minutes: 2));
      if (mounted) setState(() => _d = (r as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  bool _match(Map<String, dynamic> s, List<String> keys) {
    final q = _q.trim().toUpperCase();
    if (q.isEmpty) return true;
    return keys.map((k) => ps(s[k])).join(' ').toUpperCase().contains(q);
  }

  Widget _kv(ArconMono c, String k, Object? v, {bool bad = false}) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: c.text(11.5, color: c.muted))),
          Expanded(child: _mono(c, ps(v), color: bad ? const Color(0xFFDC2626) : null)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final d = _d;
    return PanelPage(
      title: 'Uniq Kod Farkları',
      tabs: const ['Stok ↔ Veritabanı', 'Uniq ↔ Stok'],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      body: d == null
          ? (_error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: c.text(14, color: c.muted)))) : const SkeletonList(count: 6, leading: false))
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
              children: _tab == 0 ? _dbView(c, d) : _sheetView(c, d),
            ),
    );
  }

  List<Widget> _dbView(ArconMono c, Map<String, dynamic> d) {
    final sd = ((d['stok_db'] as Map?) ?? const {}).cast<String, dynamic>();
    final o = ((sd['ozet'] as Map?) ?? const {}).cast<String, dynamic>();
    final lists = {'farkli': ('Stok beklenen ≠ DB', _maps(sd['farkli'])), 'db_yok': ('DB’de ürün yok', _maps(sd['db_yok'])), 'tam': ('Tam eşleşme', _maps(sd['tam']))};
    final rows = lists[_dbTab]!.$2.where((s) => _match(s, ['marka', 'stok_adi', 'barkod', 'stok_kodu', 'stok_uniq', 'beklenen_uniq', 'db_uniq_kod'])).toList();
    return [
      Text('Her Stok Liste satırı için beklenen UNIQ (Stok UNIQ KOD, yoksa STOK KODU) veritabanındaki ürünün UNIQ koduyla karşılaştırılır.', style: c.text(12.5, color: c.muted, height: 1.4)),
      const SizedBox(height: 10),
      _grid([
        _stat(c, 'Tam eşleşme', _say(o['tam'])),
        _stat(c, 'Farklı', _say(o['farkli']), color: const Color(0xFFDC2626)),
        _stat(c, 'DB’de yok', _say(o['db_yok']), color: const Color(0xFFDC2626)),
        _stat(c, 'Uyum', '%${o['yuzde_tam'] ?? 0}', sub: '${_say(o['karsilastirilan'])} satır'),
      ]),
      const SizedBox(height: 12),
      panelChips<String>(c, [for (final e in lists.entries) (e.key, '${e.value.$1} (${e.value.$2.length})')], _dbTab, (v) => setState(() => _dbTab = v)),
      const SizedBox(height: 10),
      _search(c, 'Barkod, stok kodu, uniq…', (v) => setState(() => _q = v)),
      const SizedBox(height: 10),
      if (rows.isEmpty) Text('Bu grupta kayıt yok.', style: c.text(13, color: c.muted)),
      for (final s in rows.take(200))
        panelCard(
          c,
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ps(s['stok_adi']).isEmpty ? '—' : ps(s['stok_adi']), style: c.text(13.5, weight: FontWeight.w600)),
            Text(ps(s['marka']), style: c.text(11.5, color: c.muted)),
            const SizedBox(height: 4),
            _kv(c, 'Barkod', s['barkod']),
            _kv(c, 'Stok kodu', s['stok_kodu']),
            _kv(c, 'Stok UNIQ', s['stok_uniq']),
            _kv(c, 'Beklenen UNIQ', s['beklenen_uniq']),
            _kv(c, 'DB UNIQ', s['db_uniq_kod'], bad: _dbTab != 'tam'),
          ]),
        ),
      if (rows.length > 200) Text('İlk 200 kayıt gösteriliyor; aramayla daralt.', style: c.text(12, color: c.muted)),
    ];
  }

  List<Widget> _sheetView(ArconMono c, Map<String, dynamic> d) {
    final o = ((d['ozet'] as Map?) ?? const {}).cast<String, dynamic>();
    final lists = {
      'cakisma': ('UNIQ farklı', _maps(d['cakisma'])),
      'uniq_sheet_bos': ('Uniq’te boş, Stok’ta var', _maps(d['uniq_sheet_bos'])),
      'stok_uniq_bos': ('Uniq’te var, Stok’ta boş', _maps(d['stok_uniq_bos'])),
    };
    final rows = lists[_sheetTab]!.$2.where((s) => _match(s, ['marka', 'urun_adi', 'barkod', 'stok_kodu', 'uniq_sheet_uniq', 'stok_uniq', 'db_uniq_kod'])).toList();
    final src = ((d['kaynak'] as Map?) ?? const {}).cast<String, dynamic>();
    return [
      Text(ps(src['aciklama']), style: c.text(12.5, color: c.muted, height: 1.4)),
      if (ps(src['uniq_dosya']).isNotEmpty) Text('Dosyalar: ${src['uniq_dosya']} · ${src['stok_dosya']}', style: c.text(11.5, color: c.faint)),
      const SizedBox(height: 10),
      _grid([
        _stat(c, 'Uniq ürün satırı', _say(o['uniq_urun_satir'])),
        _stat(c, 'Stok satırı', _say(o['stok_satir'])),
        _stat(c, 'Aynı', _say(o['ayni'])),
        _stat(c, 'Çakışma', _say(o['cakisma']), color: const Color(0xFFDC2626)),
      ]),
      const SizedBox(height: 12),
      panelChips<String>(c, [for (final e in lists.entries) (e.key, '${e.value.$1} (${e.value.$2.length})')], _sheetTab, (v) => setState(() => _sheetTab = v)),
      const SizedBox(height: 10),
      _search(c, 'Marka, ürün, barkod, uniq…', (v) => setState(() => _q = v)),
      const SizedBox(height: 10),
      if (rows.isEmpty) Text('Bu grupta kayıt yok.', style: c.text(13, color: c.muted)),
      for (final s in rows.take(200))
        panelCard(
          c,
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ps(s['urun_adi']).isEmpty ? ps(s['stok_adi']) : ps(s['urun_adi']), style: c.text(13.5, weight: FontWeight.w600)),
            Text('${s['marka'] ?? ''} · eşleşme: ${s['eslesme']}', style: c.text(11.5, color: c.muted)),
            const SizedBox(height: 4),
            _kv(c, 'Barkod/anahtar', s['barkod'] ?? s['anahtar']),
            _kv(c, 'Stok kodu', s['stok_kodu']),
            _kv(c, 'Uniq sheet UNIQ', s['uniq_sheet_uniq'], bad: _sheetTab == 'cakisma'),
            _kv(c, 'Stok Liste UNIQ', s['stok_uniq'], bad: _sheetTab == 'cakisma'),
            if (s.containsKey('db_uniq_kod')) _kv(c, 'DB’deki UNIQ', s['db_uniq_kod']),
          ]),
        ),
      if (rows.length > 200) Text('İlk 200 kayıt gösteriliyor; aramayla daralt.', style: c.text(12, color: c.muted)),
    ];
  }
}

/* ------------------------------ Excel Karşılaştır ------------------------------ */

class PrimCompareScreen extends StatefulWidget {
  const PrimCompareScreen({super.key, required this.api, this.periodId});
  final PrimApi api;
  final int? periodId;
  @override
  State<PrimCompareScreen> createState() => _PrimCompareScreenState();
}

class _PrimCompareScreenState extends State<PrimCompareScreen> {
  static const _reasons = {
    'eslesir': ('EŞLEŞİYOR', Color(0xFF1F7A1F)),
    'sistem_fazla': ('SİSTEM FAZLA', Color(0xFFB57200)),
    'excel_fazla': ('EXCEL FAZLA', Color(0xFFB57200)),
    'sadece_sistem': ('SADECE SİSTEMDE', Color(0xFF0066CC)),
    'sadece_excel': ("SADECE EXCEL'DE", Color(0xFFCC0000)),
    'atama_yok': ('ATAMA YOK', Color(0xFFCC0000)),
    'master_yok': ("MASTER'DA YOK", Color(0xFFCC0000)),
  };

  late int? _pid = widget.periodId;
  PlatformFile? _file;
  bool _busy = false;
  Map<String, dynamic>? _r;
  String? _error;
  String _q = '';
  bool _onlyDiff = true;

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'xlsm', 'csv']);
    if (f.isNotEmpty && f.first.path != null) setState(() => _file = f.first);
  }

  Future<void> _run() async {
    if (_pid == null || _file?.path == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _r = null;
    });
    try {
      final req = http.MultipartRequest('POST', Uri.parse('${widget.api.base}/karsilastir/$_pid'))
        ..files.add(await http.MultipartFile.fromPath('dosya', _file!.path!, filename: _file!.name));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 3)));
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode >= 400 || (j is Map && j['hata'] != null)) throw PrimApiError(j is Map ? '${j['hata'] ?? 'Karşılaştırılamadı'}' : 'Karşılaştırılamadı');
      if (mounted) setState(() => _r = (j as Map).cast<String, dynamic>());
    } catch (e) {
      if (mounted) setState(() => _error = e is PrimApiError ? e.message : 'Dosya karşılaştırılamadı.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final r = _r;
    final o = ((r?['ozet'] as Map?) ?? const {}).cast<String, dynamic>();
    final rows = _maps(r?['satirlar']).where((x) {
      if (_onlyDiff && x['sebep_kod'] == 'eslesir') return false;
      final q = _q.toLowerCase();
      return q.isEmpty || ps(x['uzman_ad']).toLowerCase().contains(q) || ps(x['magaza_ad']).toLowerCase().contains(q);
    }).toList();
    return PanelPage(
      title: 'Excel Karşılaştır',
      body: Column(children: [
        _PeriodBar(api: widget.api, value: _pid, onChanged: (v) => setState(() => _pid = v)),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              Text(
                'Excel’in Prim Çalışma çıktısını (Uzman × Mağaza × Prime Esas içeren CSV/XLSX) yükle; sistem her uzman × mağaza için kendi hesabıyla karşılaştırır ve farkın nedenini gösterir.',
                style: c.text(12.5, color: c.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickFile,
                style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(_file == null ? 'Dosya seç (.xlsx, .xlsm, .csv)' : _file!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13.5, weight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: _file == null || _pid == null ? 0.4 : 1,
                child: c.primaryButton(_busy ? 'Karşılaştırılıyor…' : 'Karşılaştır', busy: _busy, onPressed: _run),
              ),
              if (_error != null) ...[const SizedBox(height: 10), c.errorBox(_error!)],
              if (r != null) ...[
                const SizedBox(height: 14),
                _grid([
                  _stat(c, 'Excel prime esas', _tl(o['toplam_excel']), sub: '${_say(o['excel_satir'])} uzman × mağaza'),
                  _stat(c, 'Sistem prime esas', _tl(o['toplam_sistem']), sub: '${_say(o['sistem_satir'])} satır'),
                  _stat(c, 'Fark (Sistem − Excel)', '${_d(o['fark']) >= 0 ? '+' : ''}${_tl(o['fark'])}',
                      sub: '${o['birlesik_satir']} birleşik satır', color: _d(o['fark']) >= 0 ? const Color(0xFF1F7A1F) : const Color(0xFFCC0000)),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in (((o['sebep_kirilim'] as Map?) ?? const {}).entries))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: (_reasons[e.key]?.$2 ?? Colors.grey).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text('${_reasons[e.key]?.$1 ?? e.key}: ${e.value}', style: c.text(11.5, weight: FontWeight.w700, color: _reasons[e.key]?.$2 ?? c.muted)),
                    ),
                ]),
                const SizedBox(height: 10),
                _search(c, 'Uzman veya mağaza ara', (v) => setState(() => _q = v)),
                panelSwitch(c, 'Sadece farklı olanları göster', _onlyDiff, (v) => setState(() => _onlyDiff = v)),
                Text('${rows.length} satır gösteriliyor · toplam ${_maps(r['satirlar']).length}', style: c.text(12, color: c.muted)),
                const SizedBox(height: 8),
                for (final x in rows.take(300))
                  panelCard(
                    c,
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: (_reasons[x['sebep_kod']]?.$2 ?? Colors.grey).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                          child: Text(_reasons[x['sebep_kod']]?.$1 ?? ps(x['sebep_kod']), style: c.text(10.5, weight: FontWeight.w800, color: _reasons[x['sebep_kod']]?.$2 ?? c.muted)),
                        ),
                        const Spacer(),
                        Text('${_d(x['fark']) >= 0 ? '+' : ''}${_tl(x['fark'], decimals: true)}',
                            style: c.text(13.5, weight: FontWeight.w800, color: _d(x['fark']) >= 0 ? const Color(0xFF1F7A1F) : const Color(0xFFCC0000))),
                      ]),
                      const SizedBox(height: 6),
                      Text(ps(x['uzman_ad']), style: c.text(13.5, weight: FontWeight.w700)),
                      Text('${x['magaza_ad'] ?? ''}${ps(x['bayi']).isEmpty ? '' : ' · ${x['bayi']}'}', style: c.text(12, color: c.muted)),
                      const SizedBox(height: 4),
                      Text('Excel ${_tl(x['excel_esas'], decimals: true)} · Sistem ${_tl(x['sistem_esas'], decimals: true)}', style: c.text(12, color: c.muted)),
                      if (ps(x['sebep']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(ps(x['sebep']), style: c.text(11.5, color: c.faint))),
                    ]),
                  ),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/* ------------------------------ Değişiklik Geçmişi ------------------------------ */

class PrimAuditScreen extends StatefulWidget {
  const PrimAuditScreen({super.key, required this.api});
  final PrimApi api;
  @override
  State<PrimAuditScreen> createState() => _PrimAuditScreenState();
}

class _PrimAuditScreenState extends State<PrimAuditScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  final Set<int> _open = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('/audit');
      if (mounted) setState(() => _rows = _maps(r));
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Map<String, dynamic>? _detail(Map<String, dynamic> k) {
    final d = k['detay'];
    if (d is Map) return d.cast<String, dynamic>();
    if (d is String) {
      try {
        return (jsonDecode(d) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  /// Webdeki ozetle(): kaydı okunur cümleye çevirir.
  String _summary(Map<String, dynamic> k) {
    final d = _detail(k);
    if (d == null) return '—';
    final t = ps(k['tablo']), op = ps(k['islem']);
    Map<String, dynamic> m(Object? v) => (v as Map?)?.cast<String, dynamic>() ?? const {};
    if (t == 'donem' && op == 'hesap') {
      return '${d['donem'] ?? 'Dönem #${k['kayit_id']}'}: ${_say(d['uzmanMagazaSayisi'])} uzman-mağaza, ${_say(d['satirSayisi'])} satır, toplam prim ${_tl(d['toplamPrim'])}';
    }
    if (t == 'donem' && op == 'kilit') {
      const tr = {'acik': 'açıldı', 'kapandi': 'kapatıldı', 'hesaplandi': 'hesaplandı'};
      return '${d['donem'] ?? 'Dönem'} ${tr[d['yeni_durum']] ?? d['yeni_durum'] ?? d['durum'] ?? ''}';
    }
    if (t == 'uzman_atama' && op == 'silme') {
      final s = m(d['silinen']);
      return s.isEmpty ? 'Atama silindi' : '${s['uzman'] ?? '?'} × ${s['magaza'] ?? '?'} — ${s['marka_grubu_adi'] ?? s['bolum_adi'] ?? '?'} ataması silindi';
    }
    if (t == 'uzman_atama' && op == 'ekleme') {
      return 'Yeni atama · ${d['uzman'] ?? '?'} × ${d['magaza'] ?? '?'} — ${d['marka_grubu_adi'] ?? d['bolum_adi'] ?? '?'}${d['donem'] != null ? ' · ${d['donem']}' : ''}';
    }
    if (t == 'uzman_atama' && op == 'guncelleme') {
      final a = m(d['atama']);
      final ns = m(d['yeni'])['bolum_adi'];
      if (a.isEmpty) return 'Atama güncellendi';
      return ns != null ? '${a['uzman']} × ${a['magaza']} atamasının senaryosu → $ns' : '${a['uzman']} × ${a['magaza']} ataması güncellendi';
    }
    if ((t == 'magaza' || t == 'uzman') && op == 'guncelleme') {
      final y = m(d['yeni']);
      final parts = <String>[
        if (y['aktif'] != null) (y['aktif'] == true || y['aktif'] == 1) ? 'aktifleştirildi' : 'pasifleştirildi',
        if (y['prim_magaza'] != null) 'ad → "${y['prim_magaza']}"',
        if (y['ad_soyad'] != null) 'ad → "${y['ad_soyad']}"',
        if (y['sehir'] != null) 'şehir → "${y['sehir']}"',
      ];
      return '${d[t] ?? (t == 'magaza' ? 'Mağaza' : 'Uzman')}: ${parts.isEmpty ? 'güncellendi' : parts.join(', ')}';
    }
    if (t == 'magaza' && op == 'ekleme') return 'Yeni mağaza: ${d['prim_magaza']} (${d['bayi']})';
    if (t == 'uzman' && op == 'ekleme') return 'Yeni uzman: ${d['ad_soyad']}';
    if (t == 'prim_kural' && op == 'guncelleme') {
      final e = m(d['eski']), y = m(d['yeni']);
      if (e['prim_oran'] != null && y['prim_oran'] != null) {
        return 'Kural oranı: %${e['prim_oran']} → %${y['prim_oran']}${e['kriter_adi'] != null ? ' (${e['kriter_adi']})' : ''}';
      }
      return 'Kural güncellendi';
    }
    if (t == 'urun' && op == 'guncelleme') return 'Ürün #${k['kayit_id']} güncellendi';
    if (t == 'magaza_alias' && op == 'ekleme') return 'Mağaza eşlemesi: "${d['alias']}" → ${d['magaza'] ?? 'mağaza #${d['magaza_id']}'}';
    final raw = jsonEncode(d);
    return raw.length > 120 ? raw.substring(0, 120) : raw;
  }

  Future<void> _export(int periodId) async {
    try {
      final res = await http.get(Uri.parse('${widget.api.base}/mutabakat/$periodId/export')).timeout(const Duration(minutes: 2));
      if (res.statusCode != 200) throw Exception();
      if (mounted) await toolShareBytes(context, res.bodyBytes, 'Prim-Hesap-$periodId.xlsx');
    } catch (_) {
      if (mounted) toolToast(context, 'Excel alınamadı');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final rows = _rows;
    return PanelPage(
      title: 'Değişiklik Geçmişi',
      body: rows == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8, leading: false))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Text('Master veri, kural, atama ve dönem işlemlerinin izi — son 100 kayıt.', style: c.text(12.5, color: c.muted)),
                  const SizedBox(height: 10),
                  for (final k in rows)
                    panelCard(
                      c,
                      onTap: () => setState(() => _open.contains(pi(k['id'])) ? _open.remove(pi(k['id'])) : _open.add(pi(k['id']))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          panelTag(c, ps(k['islem']), strong: k['islem'] == 'silme'),
                          const SizedBox(width: 6),
                          Text(ps(k['tablo']), style: c.text(11.5, color: c.muted)),
                          const Spacer(),
                          Text(pDate(ps(k['created_at'])), style: c.text(11, color: c.muted)),
                        ]),
                        const SizedBox(height: 6),
                        Text(_summary(k), style: c.text(13.5, height: 1.35)),
                        if (k['tablo'] == 'donem' && k['islem'] == 'hesap' && k['kayit_id'] != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _export(pi(k['kayit_id'])),
                              icon: Icon(Icons.grid_on_rounded, size: 16, color: c.ink),
                              label: Text('Excel indir', style: c.text(12.5, weight: FontWeight.w700)),
                            ),
                          ),
                        if (_open.contains(pi(k['id'])))
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
                            child: SelectableText(const JsonEncoder.withIndent('  ').convert(_detail(k) ?? k['detay']), style: c.text(11).copyWith(fontFamily: 'Menlo')),
                          ),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }
}
