import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'tool_common.dart';

double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
String _say(Object? v) {
  final s = _n(v).round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Webdeki "Veri Yükleme" ile aynı altı dosya; `ready` dashboard alanına bakar.
const _files = [
  (tip: 'uzman-magaza', title: 'Uzman · Mağaza · Grup', sub: 'Uzman ve mağaza eşleşmeleri', key: 'atama', logs: ['uzman-magaza', 'uzman_magaza']),
  (tip: 'sellout', title: 'Sell-out', sub: 'Resmî bayi satış verisi', key: 'sellout', logs: ['sellout']),
  (tip: 'zeops', title: 'Zeops', sub: 'Uzman satış beyanları', key: 'beyan', logs: ['zeops']),
  (tip: 'hedef', title: 'Ciro Hedefleri', sub: 'Mağaza ve marka hedefleri', key: 'hedef', logs: ['hedef']),
  (tip: 'siralama', title: 'Marka Sıralamaları', sub: 'Aylık marka sıralamaları', key: 'siralama', logs: ['siralama']),
  (tip: 'stok', title: 'Stok Listesi', sub: 'Ürün master tamamlama', key: 'stok', logs: ['stok', 'uniq_kod']),
];

class _PrimError implements Exception {
  _PrimError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Prim — dönem verisi yükleme ve prim hesaplama (prim.fly-work.com/yukle).
class PrimUploadScreen extends StatefulWidget {
  const PrimUploadScreen({super.key, required this.api, this.periodId});
  final String api;
  final int? periodId;

  @override
  State<PrimUploadScreen> createState() => _PrimUploadScreenState();
}

class _PrimUploadScreenState extends State<PrimUploadScreen> {
  List<Map<String, dynamic>>? _periods;
  int? _pid;
  Map<String, dynamic>? _dash;
  List<Map<String, dynamic>> _logs = const [];
  final Map<String, String> _fileErr = {};
  String? _busy; // dosya tipi ya da 'hesap'
  String? _status;
  bool _statusErr = false;
  String? _error;
  bool _calculated = false;
  final _note = TextEditingController();
  Timer? _noteTimer;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  @override
  void dispose() {
    _noteTimer?.cancel();
    _note.dispose();
    super.dispose();
  }

  Future<dynamic> _req(String method, String path, {Object? body, Duration timeout = const Duration(seconds: 40)}) async {
    final uri = Uri.parse('${widget.api}$path');
    final headers = {'Content-Type': 'application/json'};
    final res = await switch (method) {
      'POST' => http.post(uri, headers: headers, body: jsonEncode(body ?? {})),
      'PUT' => http.put(uri, headers: headers, body: jsonEncode(body ?? {})),
      'DELETE' => http.delete(uri),
      _ => http.get(uri),
    }
        .timeout(timeout);
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw _PrimError(res.statusCode >= 500 ? 'Prim sunucusu yanıt vermedi (HTTP ${res.statusCode}).' : 'Beklenmeyen yanıt.');
    }
    if (res.statusCode >= 400 || (j is Map && j['hata'] != null)) throw _PrimError(_s(j is Map ? j['hata'] : null).isEmpty ? 'HTTP ${res.statusCode}' : _s(j['hata']));
    return j;
  }

  Map<String, dynamic>? get _period => _periods?.where((p) => _n(p['id']).toInt() == _pid).firstOrNull;

  Future<void> _loadPeriods() async {
    try {
      final list = [for (final p in (await _req('GET', '/donemler') as List).whereType<Map>()) p.cast<String, dynamic>()];
      list.sort((a, b) => (_n(b['yil']) * 100 + _n(b['ay'])).compareTo(_n(a['yil']) * 100 + _n(a['ay'])));
      final now = DateTime.now();
      final pick = widget.periodId ??
          _n((list.where((p) => _n(p['yil']) == now.year && _n(p['ay']) == now.month).firstOrNull ?? list.firstOrNull)?['id']).toInt();
      if (!mounted) return;
      setState(() => _periods = list);
      if (pick > 0) _select(pick);
    } catch (e) {
      if (mounted) setState(() => _error = e is _PrimError ? e.message : 'Prim sistemine ulaşılamadı.');
    }
  }

  Future<void> _select(int id) async {
    setState(() {
      _pid = id;
      _dash = null;
      _logs = const [];
      _fileErr.clear();
      _status = null;
      _calculated = false;
      _note.text = _s(_period?['ozel_talimat']);
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final id = _pid;
    if (id == null) return;
    try {
      final r = await Future.wait([_req('GET', '/dashboard/$id'), _req('GET', '/import-log/$id')]);
      if (!mounted || id != _pid) return;
      setState(() {
        _dash = (r[0] as Map).cast<String, dynamic>();
        _logs = [for (final l in (r[1] as List).whereType<Map>()) l.cast<String, dynamic>()];
      });
    } catch (e) {
      if (mounted) _setStatus(e.toString(), err: true);
    }
  }

  void _setStatus(String m, {bool err = false}) => setState(() {
        _status = m;
        _statusErr = err;
      });

  bool _ready(({String tip, String title, String sub, String key, List<String> logs}) f) =>
      _n((_dash?[f.key] as Map?)?['satir']) > 0 || _logs.any((l) => f.logs.contains(l['tip']));

  bool get _locked => _period?['durum'] == 'kapandi';

  /// Arka plan işini bitene kadar izler.
  Future<Map<String, dynamic>> _wait(String jobId, String label) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < const Duration(minutes: 20)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) throw _PrimError('İptal');
      final Map<String, dynamic> job;
      try {
        job = ((await _req('GET', '/import-job/$jobId')) as Map).cast<String, dynamic>();
      } on _PrimError {
        // sunucu yeniden başlamış olabilir: durumdan kontrol et
        await _refresh();
        return const {'not': 'İşlem sunucuda tamamlanmış görünüyor.'};
      }
      if (job['durum'] == 'bitti') return ((job['sonuc'] as Map?) ?? const {}).cast<String, dynamic>();
      if (job['durum'] == 'hata') throw _PrimError(_s(job['hata']).isEmpty ? 'İşlem başarısız.' : _s(job['hata']));
      final p = (job['ilerleme'] as Map?)?.cast<String, dynamic>();
      if (p != null && mounted) {
        final asama = switch (_s(p['asama'])) { 'esleme' => 'eşleme', 'hesap' => 'hesap', final a => a };
        final t = _n(p['toplam']);
        _setStatus(t > 1 ? '$label işleniyor… ${asama.isEmpty ? '' : '$asama '}${_say(p['yapilan'])} / ${_say(t)}' : '$label işleniyor…${asama.isEmpty ? '' : ' ($asama)'}');
      }
    }
    throw _PrimError('İşlem çok uzun sürdü. Biraz sonra sayfayı yenileyip kontrol edin.');
  }

  Future<void> _upload(({String tip, String title, String sub, String key, List<String> logs}) f) async {
    if (_busy != null || _pid == null || _locked) return;
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'xls', 'csv']);
    if (!mounted || files.isEmpty || files.first.path == null) return;
    final pf = files.first;
    setState(() {
      _busy = f.tip;
      _fileErr.remove(f.tip);
    });
    _setStatus('${f.title} gönderiliyor…');
    try {
      final req = http.MultipartRequest('POST', Uri.parse('${widget.api}/import/${f.tip}/$_pid'))
        ..files.add(await http.MultipartFile.fromPath('dosya', pf.path!, filename: pf.name));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 5)));
      Map<String, dynamic> j;
      try {
        j = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
      } catch (_) {
        throw _PrimError('Sunucu beklenmeyen yanıt döndü (HTTP ${res.statusCode}).');
      }
      if (res.statusCode >= 400 || j['hata'] != null) throw _PrimError(_s(j['hata']).isEmpty ? 'Dosya yüklenemedi.' : _s(j['hata']));
      if (j['jobId'] != null) await _wait(_s(j['jobId']), f.title);
      await _refresh();
      HapticFeedback.mediumImpact();
      if (mounted) _setStatus('${f.title} yüklendi.');
    } catch (e) {
      await _refresh();
      if (!mounted) return;
      if (_ready(f)) {
        _setStatus('${f.title} yüklendi (yanıt gecikti, işlem tamamlanmış).');
      } else {
        final m = e is _PrimError ? e.message : 'Yükleme başarısız. Bağlantını kontrol edip tekrar dene.';
        setState(() => _fileErr[f.tip] = m);
        _setStatus(m, err: true);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _noteChanged(String _) {
    _noteTimer?.cancel();
    _noteTimer = Timer(const Duration(milliseconds: 900), _saveNote);
  }

  Future<void> _saveNote() async {
    _noteTimer?.cancel();
    final id = _pid;
    if (id == null) return;
    try {
      await _req('PUT', '/donemler/$id/ozel-talimat', body: {'metin': _note.text});
      final p = _period;
      if (p != null) p['ozel_talimat'] = _note.text;
    } catch (_) {}
  }

  Future<void> _calculate() async {
    if (_busy != null || _pid == null) return;
    setState(() => _busy = 'hesap');
    _setStatus('Prim hesaplanıyor…');
    try {
      await _saveNote();
      final j = ((await _req('POST', '/hesapla/$_pid', timeout: const Duration(minutes: 2))) as Map).cast<String, dynamic>();
      final r = j['jobId'] != null ? await _wait(_s(j['jobId']), 'Prim hesabı') : j;
      final p = _period;
      if (p != null) p['durum'] = 'hesaplandi';
      await _refresh();
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      final extra = r['ozelTalimatVar'] == true
          ? ' Özel talimat hesaba dahil edildi.'
          : (_n(r['ozelDurumUygulanan']) > 0 ? ' Özel durum: ${_say(r['ozelDurumUygulanan'])} etki uygulandı.' : '');
      setState(() => _calculated = true);
      _setStatus(r.containsKey('toplamPrim')
          ? '${_say(r['uzmanMagazaSayisi'])} uzman-mağaza için ${_say(r['toplamPrim'])} TL prim hesaplandı.$extra'
          : 'Prim hesabı tamamlandı.');
    } catch (e) {
      if (mounted) _setStatus(e is _PrimError ? e.message : 'Hesaplama başarısız.', err: true);
    } finally {
      if (mounted) setState(() => _busy = null);
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

  Future<void> _menu(String v) async {
    final id = _pid;
    if (id == null || _busy != null) return;
    try {
      if (v == 'lock' || v == 'unlock') {
        final lock = v == 'lock';
        if (!await _confirm(lock ? 'Dönem kapatılsın mı?' : 'Dönem açılsın mı?', lock ? 'Kapalı dönemde dosya yüklenemez, hesap yapılamaz.' : 'Dönem yeniden düzenlenebilir olur.', lock ? 'Kapat' : 'Aç')) return;
        await _req('PUT', '/donemler/$id/durum', body: {'durum': lock ? 'kapandi' : (_n(_dash?['prim']?['kayit']) > 0 ? 'hesaplandi' : 'acik')});
        await _loadPeriodsKeep();
        if (mounted) toolToast(context, lock ? 'Dönem kapatıldı' : 'Dönem açıldı');
      } else if (v == 'clear') {
        if (!await _confirm('Dönem verileri silinsin mi?', '${_s(_period?['ad'])} dönemine yüklenen tüm dosyalar ve prim sonuçları silinir. Stok master kalır.', 'Temizle', destructive: true)) return;
        final r = await _req('DELETE', '/donemler/$id/temizle', timeout: const Duration(minutes: 3));
        await _loadPeriodsKeep();
        if (mounted) toolToast(context, _s(r is Map ? r['mesaj'] : null).isEmpty ? 'Dönem temizlendi' : _s(r['mesaj']));
      }
    } catch (e) {
      if (mounted) toolToast(context, e is _PrimError ? e.message : 'İşlem başarısız');
    }
  }

  Future<void> _loadPeriodsKeep() async {
    final list = [for (final p in (await _req('GET', '/donemler') as List).whereType<Map>()) p.cast<String, dynamic>()];
    list.sort((a, b) => (_n(b['yil']) * 100 + _n(b['ay'])).compareTo(_n(a['yil']) * 100 + _n(a['ay'])));
    if (!mounted) return;
    setState(() => _periods = list);
    await _refresh();
  }

  String _statusLabel(String s) => switch (s) { 'hesaplandi' => 'Hesaplandı', 'kapandi' => 'Kapalı', _ => 'Açık' };

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final p = _period;
    final readyCount = _files.where(_ready).length;
    final allReady = _dash != null && readyCount == _files.length;
    final unmatched = _n((_dash?['beyan'] as Map?)?['eslesmeyen']) + _n((_dash?['sellout'] as Map?)?['eslesmeyen']);
    return PopScope(
      canPop: _busy == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) toolToast(context, 'İşlem sürüyor, bitmesini bekle');
        if (didPop) _saveNote();
      },
      child: ToolPage(
        title: 'Veri yükleme · Hesaplama',
        actions: [
          if (p != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, color: c.ink),
              color: c.bg,
              onSelected: _menu,
              itemBuilder: (_) => [
                PopupMenuItem(value: _locked ? 'unlock' : 'lock', child: Text(_locked ? 'Dönemi aç' : 'Dönemi kapat', style: c.text(14.5))),
                if (!_locked) PopupMenuItem(value: 'clear', child: Text('Dönem verilerini temizle', style: c.text(14.5, color: c.danger))),
              ],
            ),
        ],
        children: [
          if (_periods == null && _error == null)
            const SkeletonList(count: 6, leading: false)
          else if (_periods == null)
            Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: Text(_error!, style: c.text(14, color: c.muted))))
          else ...[
            SizedBox(
              height: 58,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final d in _periods!)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: _busy != null ? null : () => _select(_n(d['id']).toInt()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _n(d['id']).toInt() == _pid ? c.ink : c.field,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _n(d['id']).toInt() == _pid ? c.ink : c.line),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_s(d['ad']), style: c.text(13, weight: FontWeight.w700, color: _n(d['id']).toInt() == _pid ? c.bg : c.ink)),
                              Text(_statusLabel(_s(d['durum'])), style: c.text(10.5, color: _n(d['id']).toInt() == _pid ? c.bg.withValues(alpha: 0.7) : c.muted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (p != null) ...[
              Row(
                children: [
                  Text('${p['ad']}', style: c.text(20, weight: FontWeight.w800, spacing: -0.3)),
                  const Spacer(),
                  Text(_dash == null ? '' : '$readyCount/${_files.length} dosya yüklü', style: c.text(12.5, weight: FontWeight.w700, color: c.muted)),
                ],
              ),
              if (_locked) ...[
                const SizedBox(height: 8),
                Text('Bu dönem kapalı. Yükleme ve hesap için ••• menüsünden dönemi aç.', style: c.text(12.5, color: c.muted)),
              ],
              const SizedBox(height: 10),
              if (_dash == null)
                const SkeletonList(count: 6, leading: true, padding: EdgeInsets.zero)
              else
                for (final f in _files) _fileCard(c, f),
              if (_dash != null && unmatched > 0)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                  child: Row(
                    children: [
                      Icon(Icons.link_off_rounded, size: 18, color: c.ink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${_say(unmatched)} satır eşleşmedi. Eşleşmeyenleri web panelindeki "Eşleşmeyenler" ekranından düzeltebilirsin.',
                            style: c.text(12.5, height: 1.4)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              c.label('Özel durum talimatı'),
              const SizedBox(height: 6),
              TextField(
                controller: _note,
                onChanged: _noteChanged,
                enabled: !_locked,
                minLines: 2,
                maxLines: 6,
                keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                style: c.text(14.5, height: 1.4),
                cursorColor: c.ink,
                decoration: c.input('ör. Ahmet Y. bu ay Beymen Zorlu\'da da çalıştı, satışları ona yazılsın…', null),
              ),
              const SizedBox(height: 4),
              Text('Hesaplamada AI bu talimatı dikkate alır. Otomatik kaydedilir.', style: c.text(11.5, color: c.muted)),
              if (_status != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusErr ? c.danger.withValues(alpha: 0.08) : c.field,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _statusErr ? c.danger.withValues(alpha: 0.4) : c.line),
                  ),
                  child: Row(
                    children: [
                      if (_busy != null)
                        Padding(padding: const EdgeInsets.only(right: 10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))),
                      Expanded(child: Text(_status!, style: c.text(13, height: 1.4, color: _statusErr ? c.danger : c.ink))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Opacity(
                opacity: allReady && !_locked ? 1 : 0.4,
                child: c.primaryButton(
                  _n((_dash?['prim'] as Map?)?['kayit']) > 0 ? 'Primleri yeniden hesapla' : 'Primleri hesapla',
                  busy: _busy == 'hesap',
                  onPressed: () {
                    if (!allReady) {
                      toolToast(context, 'Önce altı dosyanın hepsini yükle');
                    } else if (!_locked) {
                      _calculate();
                    }
                  },
                ),
              ),
              if (_calculated) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(_pid),
                  style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(48)),
                  child: Text('Raporu gör', style: c.text(14, weight: FontWeight.w700)),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _fileCard(ArconMono c, ({String tip, String title, String sub, String key, List<String> logs}) f) {
    final ready = _ready(f);
    final busy = _busy == f.tip;
    final count = _n((_dash?[f.key] as Map?)?['satir']);
    final log = _logs.where((l) => f.logs.contains(l['tip'])).firstOrNull;
    final err = _fileErr[f.tip];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: err != null ? c.danger.withValues(alpha: 0.5) : c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy != null || _locked ? null : () => _upload(f),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: ready ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(10), border: Border.all(color: ready ? c.ink : c.line)),
                  child: busy
                      ? Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                      : Icon(ready ? Icons.check_rounded : Icons.upload_file_rounded, size: 19, color: ready ? c.bg : c.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.title, style: c.text(14.5, weight: FontWeight.w700)),
                      Text(
                        err ?? (log != null ? _s(log['dosya_adi']) : (count > 0 ? '${_say(count)} satır' : f.sub)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: c.text(12, color: err != null ? c.danger : c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(busy ? 'Yükleniyor' : (ready ? 'Yenile' : 'Dosya seç'), style: c.text(12.5, weight: FontWeight.w700, color: _locked ? c.faint : c.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
