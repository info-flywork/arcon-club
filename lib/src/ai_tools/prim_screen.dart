import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/skeleton.dart';
import 'prim_admin_screens.dart';
import 'prim_upload_screen.dart';
import 'tool_common.dart';

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';

const _months = ['', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

/// ₺ biçimi: 12.345,67
String _tl(double v, {bool decimals = false}) {
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals ? 2 : 0).split('.');
  final buf = StringBuffer();
  final digits = fixed[0];
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}$buf${decimals ? ',${fixed[1]}' : ''} ₺';
}

/// Prim Modülü — uzman primleri (prim.fly-work.com): dönem özeti, uzman detayı, Excel,
/// veri yükleme ve hesaplama, kurallar ve veri kontrolü (Prim yönetimi).
class PrimScreen extends StatefulWidget {
  const PrimScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});
  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  static const api = 'https://prim.fly-work.com/api';

  @override
  State<PrimScreen> createState() => _PrimScreenState();
}

class _PrimScreenState extends State<PrimScreen> {
  List<Map<String, dynamic>>? _periods;
  Map<String, dynamic>? _period;
  List<Map<String, dynamic>>? _rows;
  String? _error;
  final _q = TextEditingController();
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _loadPeriods();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<dynamic> _get(String path) async {
    final res = await http.get(Uri.parse('${PrimScreen.api}$path')).timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<void> _loadPeriods() async {
    try {
      final list = [for (final p in (await _get('/donemler') as List).whereType<Map>()) p.cast<String, dynamic>()];
      // en yeni hesaplanmış dönem öne
      list.sort((a, b) => (_n(b['yil']) * 100 + _n(b['ay'])).compareTo(_n(a['yil']) * 100 + _n(a['ay'])));
      final pick = list.where((p) => p['durum'] != 'acik').firstOrNull ?? list.firstOrNull;
      if (!mounted) return;
      setState(() => _periods = list);
      if (pick != null) _selectPeriod(pick);
    } catch (_) {
      if (mounted) setState(() => _error = 'Prim sistemine ulaşılamadı.');
    }
  }

  Future<void> _selectPeriod(Map<String, dynamic> p) async {
    setState(() {
      _period = p;
      _rows = null;
      _error = null;
    });
    try {
      final rows = [for (final r in (await _get('/rapor/ozet/${p['id']}') as List).whereType<Map>()) r.cast<String, dynamic>()];
      if (mounted && _period == p) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Prim raporu alınamadı.');
    }
  }

  String _periodName(Map<String, dynamic> p) => _s(p['ad']).isNotEmpty ? _s(p['ad']) : '${_months[_n(p['ay']).toInt().clamp(0, 12)]} ${_n(p['yil']).toInt()}';

  String _statusLabel(String s) => switch (s) {
        'hesaplandi' => 'Hesaplandı',
        'kapandi' => 'Kapandı',
        _ => 'Açık',
      };

  /// Uzman bazında topla (bir uzman birden çok mağazada olabilir).
  List<({int id, String name, double total, double base, List<Map<String, dynamic>> rows})> get _byExpert {
    final map = <int, List<Map<String, dynamic>>>{};
    for (final r in _rows ?? const <Map<String, dynamic>>[]) {
      map.putIfAbsent(_n(r['uzman_id']).toInt(), () => []).add(r);
    }
    final q = _q.text.trim().toLowerCase();
    final out = [
      for (final e in map.entries)
        (
          id: e.key,
          name: _s(e.value.first['ad_soyad']),
          total: e.value.fold<double>(0, (a, r) => a + _n(r['toplam_prim'])),
          base: e.value.fold<double>(0, (a, r) => a + _n(r['prime_esas_toplam'])),
          rows: e.value,
        ),
    ].where((x) => q.isEmpty || x.name.toLowerCase().contains(q) || x.rows.any((r) => _s(r['prim_magaza']).toLowerCase().contains(q))).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return out;
  }

  Future<void> _export() async {
    final p = _period;
    if (p == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final res = await http.get(Uri.parse('${PrimScreen.api}/rapor/ozet/${p['id']}?format=xlsx')).timeout(const Duration(minutes: 2));
      if (res.statusCode != 200) throw Exception();
      if (mounted) await toolShareBytes(context, res.bodyBytes, 'Prim-Raporu-${_periodName(p).replaceAll(' ', '-')}.xlsx');
    } catch (_) {
      if (mounted) toolToast(context, 'Excel alınamadı');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openUpload() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => PrimUploadScreen(api: PrimScreen.api, periodId: _period == null ? null : _n(_period!['id']).toInt()),
    ));
    if (!mounted) return;
    // dönem durumları değişmiş olabilir; hesap yapıldıysa o döneme geç
    try {
      final list = [for (final p in (await _get('/donemler') as List).whereType<Map>()) p.cast<String, dynamic>()];
      list.sort((a, b) => (_n(b['yil']) * 100 + _n(b['ay'])).compareTo(_n(a['yil']) * 100 + _n(a['ay'])));
      if (!mounted) return;
      setState(() => _periods = list);
      final target = list.where((p) => _n(p['id']).toInt() == (id ?? _n(_period?['id']).toInt())).firstOrNull;
      if (target != null) _selectPeriod(target);
    } catch (_) {}
  }

  Future<void> _pickPeriod() async {
    final c = ArconMono.of(context);
    final v = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: c.bg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text('Dönem', style: c.text(18, weight: FontWeight.w800))),
            for (final p in _periods ?? const <Map<String, dynamic>>[])
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: Text(_periodName(p), style: c.text(15, weight: p['id'] == _period?['id'] ? FontWeight.w800 : FontWeight.w500)),
                subtitle: Text(_statusLabel(_s(p['durum'])), style: c.text(12, color: c.muted)),
                trailing: p['id'] == _period?['id'] ? Icon(Icons.check_rounded, color: c.ink) : null,
                onTap: () => Navigator.of(ctx).pop(p),
              ),
          ],
        ),
      ),
    );
    if (v != null) _selectPeriod(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final p = _period;
    final experts = _byExpert;
    final total = experts.fold<double>(0, (a, e) => a + e.total);
    final fg = c.dark ? c.ink : c.bg;
    return ToolPage(
      title: widget.title,
      actions: [
        IconButton(
          tooltip: 'Veri yükleme ve hesaplama',
          onPressed: _openUpload,
          icon: Icon(Icons.upload_file_rounded, color: c.ink),
        ),
        IconButton(
          tooltip: 'Prim yönetimi (kurallar, veri kontrolü)',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PrimAdminHubScreen(api: PrimScreen.api, periodId: _period == null ? null : _n(_period!['id']).toInt()),
          )),
          icon: Icon(Icons.tune_rounded, color: c.ink),
        ),
      ],
      children: [
        if (_periods == null && _error == null) ...[
          const SkeletonBox(height: 140, radius: 20),
          const SizedBox(height: 16),
          const SkeletonList(count: 6, leadingSize: 40),
        ] else if (_periods == null)
          Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: Text(_error!, style: c.text(14, color: c.muted))))
        else ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.dark ? c.field : c.ink, borderRadius: BorderRadius.circular(20), border: c.dark ? Border.all(color: c.line) : null),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _pickPeriod,
                  child: Row(
                    children: [
                      Text(p == null ? 'Dönem seç' : _periodName(p), style: c.text(22, weight: FontWeight.w800, color: fg, spacing: -0.5)),
                      Icon(Icons.expand_more_rounded, color: fg),
                      const Spacer(),
                      if (p != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: fg.withValues(alpha: 0.4))),
                          child: Text(_statusLabel(_s(p['durum'])), style: c.text(11, weight: FontWeight.w700, color: fg)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(_rows == null ? '—' : _tl(total), style: c.text(30, weight: FontWeight.w800, color: fg, spacing: -1)),
                Text('toplam prim · ${experts.length} uzman', style: c.text(12.5, color: fg.withValues(alpha: 0.7))),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _q,
                  keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                  style: c.text(15),
                  cursorColor: c.ink,
                  decoration: c.input('Uzman ya da mağaza ara', Icons.search_rounded),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _rows == null || _rows!.isEmpty ? null : _export,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.ink,
                    side: BorderSide(color: c.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _exporting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)) : const Icon(Icons.grid_on_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 30), child: Center(child: Text(_error!, style: c.text(14, color: c.muted))))
          else if (_rows == null)
            const SkeletonList(count: 6, leadingSize: 40)
          else if (experts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Center(
                child: Text(
                  _rows!.isEmpty ? 'Bu dönem için henüz hesaplama yok.\nVeriler web panelinden yüklenip hesaplanır.' : 'Aramaya uyan uzman yok',
                  textAlign: TextAlign.center,
                  style: c.text(14, color: c.muted, height: 1.5),
                ),
              ),
            )
          else
            for (final e in experts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PressScale(
                  child: Material(
                    color: c.field,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => _PrimExpertScreen(period: p!, periodName: _periodName(p), expertId: e.id, name: e.name, summary: e.rows, get: _get),
                      )),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: c.ink,
                              child: Text(
                                e.name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x[0]).join().toUpperCase(),
                                style: c.text(13, weight: FontWeight.w800, color: c.bg),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w700)),
                                  Text(
                                    e.rows.map((r) => _s(r['prim_magaza'])).toSet().join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: c.text(12, color: c.muted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_tl(e.total), style: c.text(14.5, weight: FontWeight.w800)),
                                Text('ciro ${_tl(e.base)}', style: c.text(11, color: c.muted)),
                              ],
                            ),
                            Icon(Icons.chevron_right_rounded, color: c.faint),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _PrimExpertScreen extends StatefulWidget {
  const _PrimExpertScreen({required this.period, required this.periodName, required this.expertId, required this.name, required this.summary, required this.get});
  final Map<String, dynamic> period;
  final String periodName;
  final int expertId;
  final String name;
  final List<Map<String, dynamic>> summary;
  final Future<dynamic> Function(String) get;

  @override
  State<_PrimExpertScreen> createState() => _PrimExpertScreenState();
}

class _PrimExpertScreenState extends State<_PrimExpertScreen> {
  List<Map<String, dynamic>>? _lines;

  @override
  void initState() {
    super.initState();
    widget.get('/rapor/detay/${widget.period['id']}/${widget.expertId}').then((j) {
      if (!mounted) return;
      setState(() => _lines = [for (final r in (((j as Map)['satirlar'] as List?) ?? const []).whereType<Map>()) r.cast<String, dynamic>()]);
    }).catchError((_) {
      if (mounted) setState(() => _lines = const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    Widget kv(String k, double v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(k, style: c.text(13.5, color: strong ? c.ink : c.muted, weight: strong ? FontWeight.w800 : FontWeight.w500))),
              Text(_tl(v, decimals: true), style: c.text(13.5, weight: strong ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        );
    return ToolPage(
      title: widget.name,
      children: [
        Text(widget.periodName, style: c.text(13, color: c.muted)),
        const SizedBox(height: 10),
        for (final s in widget.summary)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_s(s['prim_magaza']), style: c.text(15, weight: FontWeight.w800)),
                Text([_s(s['bolum_adi']), _s(s['marka_grubu_adi']), _s(s['bayi'])].where((e) => e.isNotEmpty).join(' · '), style: c.text(12, color: c.muted)),
                const SizedBox(height: 8),
                kv('Prime esas ciro', _n(s['prime_esas_toplam'])),
                kv('Satış primi (%${_n(s['satis_prim_oran']).toStringAsFixed(2)})', _n(s['satis_prim'])),
                kv('Hedef primi', _n(s['hedef_prim'])),
                kv('Sıralama primi', _n(s['siralama_prim'])),
                kv('Bonus', _n(s['bonus_prim'])),
                if (_n(s['ek_prim']) != 0) kv('Ek prim', _n(s['ek_prim'])),
                if (_n(s['devreden_prim']) != 0) kv('Devreden', _n(s['devreden_prim'])),
                Divider(color: c.line, height: 16),
                kv('Toplam prim · efektif %${_n(s['toplam_oran']).toStringAsFixed(2)}', _n(s['toplam_prim']), strong: true),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(trUpper('Satış satırları'), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
        const SizedBox(height: 8),
        if (_lines == null)
          const SkeletonList(count: 5, leading: false)
        else if (_lines!.isEmpty)
          Text('Satır bulunamadı.', style: c.text(13.5, color: c.muted))
        else
          for (final l in _lines!)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_s(l['urun_adi']).isEmpty ? (_s(l['aciklama']).isEmpty ? 'Ürün' : _s(l['aciklama'])) : _s(l['urun_adi']),
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(13, weight: FontWeight.w600)),
                        Text(
                          [_s(l['marka']), '${_n(l['prim_adet']).toInt()}/${_n(l['beyan_adet']).toInt()} adet', if (_s(l['aciklama']).isNotEmpty && _s(l['urun_adi']).isNotEmpty) _s(l['aciklama'])]
                              .where((e) => e.isNotEmpty)
                              .join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: c.text(11.5, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_tl(_n(l['prime_esas_tutar'])), style: c.text(13, weight: FontWeight.w700)),
                ],
              ),
            ),
      ],
    );
  }
}
