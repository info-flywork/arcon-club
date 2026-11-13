import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import 'tool_common.dart';

/// Adaptly markası: veri dosyasındaki mağaza ve barkod sütunları (webdeki *.html ile aynı).
class AdaptlyBrand {
  const AdaptlyBrand(this.id, this.label, this.short, this.dataLabel, this.storeCol, this.barcodeCol, {this.excel = false});
  final String id;
  final String label;
  final String short;
  final String dataLabel;
  final String storeCol;
  final String barcodeCol;

  /// Veri dosyası Excel de olabilir mi (Sephora, Boyner).
  final bool excel;

  static const all = [
    AdaptlyBrand('sevil', 'Sevil', 'SV', 'Data Sevil', 'Mgz', 'Barkod'),
    AdaptlyBrand('beymen', 'Beymen', 'BY', 'Beymen data', 'Mgz', 'Barkod'),
    AdaptlyBrand('sephora', 'Sephora', 'SP', 'Sephora data', 'Store Code', 'EAN Code', excel: true),
    AdaptlyBrand('boyner', 'Boyner', 'BN', 'Boyner data', 'Lokasyon ID', 'Urun ANAEAN', excel: true),
  ];
}

/// Adaptly — webdeki adaptly: marka CRM verisini ürün ve mağaza referanslarıyla birleştirir.
/// Tüm işlem cihazda yapılır (web sürümü de tarayıcıda yapıyor); sunucuya yalnızca işlem logu gider.
class AdaptlyHubScreen extends StatelessWidget {
  const AdaptlyHubScreen({super.key, required this.session, required this.config, required this.title});
  final SessionController session;
  final ArconAppConfig config;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return ToolPage(
      title: title,
      children: [
        const ToolIntro(title: 'Marka seç', text: 'Marka CRM verisini ürün ve mağaza referanslarıyla birleştirip barkod raporu oluştur.'),
        for (final b in AdaptlyBrand.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PressScale(
              child: Material(
                color: c.field,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdaptlyMergeScreen(session: session, brand: b))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(14)),
                          child: Text(b.short, style: c.text(15, weight: FontWeight.w800, color: c.bg)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.label, style: c.text(16, weight: FontWeight.w800)),
                              Text(b.excel ? 'CSV ya da Excel' : 'CSV', style: c.text(12.5, color: c.muted)),
                            ],
                          ),
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
    );
  }
}

typedef _Rows = List<Map<String, String>>;

class AdaptlyMergeScreen extends StatefulWidget {
  const AdaptlyMergeScreen({super.key, required this.session, required this.brand});
  final SessionController session;
  final AdaptlyBrand brand;

  @override
  State<AdaptlyMergeScreen> createState() => _AdaptlyMergeScreenState();
}

class _AdaptlyMergeScreenState extends State<AdaptlyMergeScreen> {
  final _files = <String, PlatformFile?>{'data': null, 'product': null, 'store': null};
  final _urls = <String, TextEditingController>{
    'data': TextEditingController(),
    'product': TextEditingController(),
    'store': TextEditingController(),
  };
  bool _busy = false;
  String? _error;
  _Rows? _result;
  List<String> _headers = const [];
  List<String> _missingStores = const [];
  List<String> _missingProducts = const [];
  double _seconds = 0;

  AdaptlyBrand get _b => widget.brand;

  @override
  void dispose() {
    for (final c in _urls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(String key) async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    final f = files.first;
    final ok = key == 'data' && _b.excel ? RegExp(r'\.(csv|xlsx|xls)$', caseSensitive: false) : RegExp(r'\.csv$', caseSensitive: false);
    if (f.path == null || !ok.hasMatch(f.name)) {
      toolToast(context, key == 'data' && _b.excel ? 'CSV ya da Excel seçin' : 'CSV dosyası seçin');
      return;
    }
    setState(() {
      _files[key] = f;
      _urls[key]!.clear();
      _result = null;
    });
  }

  /* ---------- okuma ---------- */

  static String _cell(Object? v) {
    if (v == null) return '';
    if (v is xl.DoubleCellValue) {
      final d = v.value;
      return d == d.truncateToDouble() && d.abs() < 1e15 ? d.toInt().toString() : d.toString();
    }
    if (v is xl.IntCellValue) return v.value.toString();
    return v.toString();
  }

  static _Rows _parseXlsx(Uint8List bytes) {
    final book = xl.Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) return const [];
    final sheet = book.tables.values.first;
    final rows = sheet.rows;
    if (rows.isEmpty) return const [];
    final head = [for (final h in rows.first) _cell(h?.value).trim()];
    return [
      for (final r in rows.skip(1))
        if (r.any((x) => _cell(x?.value).trim().isNotEmpty))
          {for (var i = 0; i < head.length; i++) if (head[i].isNotEmpty) head[i]: i < r.length ? _cell(r[i]?.value) : ''},
    ];
  }

  /// Papa.parse(header: true) ile aynı davranış: tırnaklı alanlar, ayraç otomatik (, ; tab).
  static _Rows _parseCsv(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    final firstLine = text.split('\n').first;
    final delim = [';', '\t', ','].reduce((a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b);
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == delim) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    row.add(cell.toString());
    if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
    if (rows.isEmpty) return const [];
    final head = rows.first.map((e) => e.trim()).toList();
    return [
      for (final r in rows.skip(1)) {for (var i = 0; i < head.length; i++) if (head[i].isNotEmpty) head[i]: i < r.length ? r[i] : ''},
    ];
  }

  Future<_Rows> _read(String key) async {
    final f = _files[key];
    Uint8List? bytes;
    String name;
    if (f != null) {
      bytes = await File(f.path!).readAsBytes();
      name = f.name;
    } else {
      final url = _urls[key]!.text.trim();
      if (url.isEmpty) return const [];
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Bağlantıdaki dosya indirilemedi ($url)');
      bytes = res.bodyBytes;
      name = Uri.parse(url).path;
    }
    if (RegExp(r'\.(xlsx|xls)$', caseSensitive: false).hasMatch(name)) return _parseXlsx(bytes);
    return _parseCsv(utf8.decode(bytes, allowMalformed: true));
  }

  bool _has(String key) => _files[key] != null || _urls[key]!.text.trim().isNotEmpty;

  /* ---------- birleştirme ---------- */

  Future<void> _merge() async {
    if (_busy || !_has('data')) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    final t0 = DateTime.now();
    try {
      final parts = await Future.wait([_read('data'), _read('product'), _read('store')]);
      final data = parts[0], products = parts[1], stores = parts[2];
      final productMap = {for (final p in products) (p['BARKOD 1'] ?? '').trim(): p};
      final storeMap = {for (final s in stores) (s['SEVKİYAT MAĞAZA KODU'] ?? '').trim(): s};
      final missingMgz = <String>{
        for (final d in data)
          if ((d[_b.storeCol] ?? '').trim().isNotEmpty && !storeMap.containsKey((d[_b.storeCol] ?? '').trim())) (d[_b.storeCol] ?? '').trim(),
      }.toList();
      final missingProducts = <String>{
        for (final d in data)
          if ((d[_b.barcodeCol] ?? '').trim().isNotEmpty && !productMap.containsKey((d[_b.barcodeCol] ?? '').trim())) (d[_b.barcodeCol] ?? '').trim(),
      }.toList();
      for (final mgz in missingMgz) {
        storeMap[mgz] = {
          'CARİ KOD': 'YOK',
          'CARİ ADI': 'Bilinmeyen Mağaza',
          'SEVKİYAT MAĞAZA KODU': mgz,
          'MAĞAZA KODU': 'YOK',
          'MAĞAZA ADI': '$mgz Mağazası',
          'BÖLGE': 'Tanımsız',
          'ŞEHİR': 'Tanımsız',
        };
      }
      final merged = [
        for (final row in data)
          {
            ...row,
            ...?productMap[(row[_b.barcodeCol] ?? '').trim()],
            ...?storeMap[(row[_b.storeCol] ?? '').trim()],
          },
      ];
      final headers = <String>[];
      for (final r in merged) {
        for (final k in r.keys) {
          if (!headers.contains(k)) headers.add(k);
        }
      }
      final secs = DateTime.now().difference(t0).inMilliseconds / 1000;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = merged;
        _headers = headers;
        _missingStores = missingMgz;
        _missingProducts = missingProducts;
        _seconds = secs;
      });
      _log('merge', '${merged.length} satır birleştirildi', {
        'brand': _b.label,
        'row_count': merged.length,
        'missing_stores': missingMgz.length,
        'missing_products': missingProducts.length,
      }, (secs * 1000).round());
    } catch (e) {
      if (mounted) setState(() => _error = 'Dosyalar okunamadı: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _log(String action, String output, Map<String, Object?> meta, [int? ms]) {
    widget.session.api.webCall('tool_module_log.php', jsonBody: {
      'module_key': 'adaptly',
      'session_id': 'adaptly-app-${DateTime.now().millisecondsSinceEpoch}',
      'action': action,
      'msg_count': 1,
      'title': 'Adaptly · ${_b.label}',
      'input_preview': '${_b.label} CRM birleştirme',
      'output_preview': output,
      'duration_ms': ?ms,
      'meta': meta,
    }).catchError((_) => <String, dynamic>{});
  }

  Future<void> _exportExcel() async {
    final rows = _result;
    if (rows == null || rows.isEmpty) return;
    final book = xl.Excel.createExcel();
    final sheetName = book.getDefaultSheet() ?? 'Sheet1';
    book.rename(sheetName, 'Rapor');
    final sheet = book['Rapor'];
    sheet.appendRow([for (final h in _headers) xl.TextCellValue(h)]);
    for (final r in rows) {
      sheet.appendRow([for (final h in _headers) xl.TextCellValue(r[h] ?? '')]);
    }
    final bytes = book.encode();
    if (bytes == null) return;
    _log('export_xlsx', '${rows.length} satır Excel', {'brand': _b.label, 'row_count': rows.length, 'format': 'xlsx'});
    if (mounted) await toolShareBytes(context, Uint8List.fromList(bytes), '${_b.label}-Birlesik-Rapor.xlsx');
  }

  Future<void> _exportCsv() async {
    final rows = _result;
    if (rows == null || rows.isEmpty) return;
    String q(String v) => v.contains(RegExp('[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
    final csv = StringBuffer()..writeln(_headers.map(q).join(','));
    for (final r in rows) {
      csv.writeln(_headers.map((h) => q(r[h] ?? '')).join(','));
    }
    _log('export_csv', '${rows.length} satır CSV', {'brand': _b.label, 'row_count': rows.length, 'format': 'csv'});
    await toolShareBytes(context, Uint8List.fromList(utf8.encode('﻿$csv')), '${_b.label}-Birlesik-Rapor.csv');
  }

  /* ---------- arayüz ---------- */

  Widget _source(ArconMono c, int n, String key, String title, String hint) => ToolStep(
        n: n,
        title: title,
        done: _has(key),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ToolFilePick(
              label: hint,
              fileName: _files[key]?.name,
              onPick: () => _pick(key),
              onClear: _files[key] == null ? null : () => setState(() => _files[key] = null),
            ),
            if (_files[key] == null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _urls[key],
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.url,
                autocorrect: false,
                keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                style: c.text(13.5),
                cursorColor: c.ink,
                decoration: c.input('ya da CSV bağlantısı (https://…)', Icons.link_rounded).copyWith(fillColor: c.bg),
              ),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final r = _result;
    return ToolPage(
      title: 'Adaptly · ${_b.label}',
      children: [
        ToolIntro(title: _b.label, text: 'Data, ürün ve mağaza dosyalarını birleştirip barkod raporu oluştur. İşlem telefonunda yapılır.'),
        _source(c, 1, 'data', '${_b.dataLabel} — ${_b.excel ? 'CSV / Excel' : 'CSV'}', _b.excel ? 'Dosya seç (CSV / Excel)' : 'CSV seç'),
        _source(c, 2, 'product', 'Ürün referansı — CSV', 'CSV seç'),
        _source(c, 3, 'store', 'Mağaza referansı — CSV', 'CSV seç'),
        Opacity(opacity: _has('data') ? 1 : 0.4, child: c.primaryButton('Verileri birleştir', busy: _busy, onPressed: _merge)),
        if (_error != null) ...[const SizedBox(height: 12), c.errorBox(_error!)],
        if (r != null) ...[
          const SizedBox(height: 14),
          ToolResult(
            title: '${r.length} satır birleştirildi',
            text: [
              '${_seconds.toStringAsFixed(2)} sn',
              if (_missingStores.isNotEmpty) '${_missingStores.length} mağaza eşleşmedi',
              if (_missingProducts.isNotEmpty) '${_missingProducts.length} ürün barkodu eşleşmedi',
            ].join(' · '),
            actions: [
              (Icons.grid_on_rounded, 'Excel olarak kaydet', _exportExcel),
              (Icons.description_outlined, 'CSV olarak kaydet', _exportCsv),
            ],
          ),
          if (_missingStores.isNotEmpty || _missingProducts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_missingStores.isNotEmpty) ...[
                    Text(trUpper('Tanımsız mağazalar'), style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                    const SizedBox(height: 4),
                    SelectableText(_missingStores.join(', '), style: c.text(12.5, height: 1.45)),
                    const SizedBox(height: 10),
                  ],
                  if (_missingProducts.isNotEmpty) ...[
                    Text(trUpper('Tanımsız ürün barkodları'), style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                    const SizedBox(height: 4),
                    SelectableText(_missingProducts.take(200).join(', '), style: c.text(12.5, height: 1.45)),
                  ],
                ],
              ),
            ),
          ],
          if (r.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Önizleme · ilk ${r.length < 30 ? r.length : 30} satır', style: c.text(12, weight: FontWeight.w700, color: c.muted)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 38,
                    dataRowMinHeight: 34,
                    dataRowMaxHeight: 40,
                    columnSpacing: 18,
                    headingTextStyle: c.text(11.5, weight: FontWeight.w800),
                    dataTextStyle: c.text(12),
                    headingRowColor: WidgetStatePropertyAll(c.field),
                    columns: [for (final h in _headers) DataColumn(label: Text(h))],
                    rows: [
                      for (final row in r.take(30)) DataRow(cells: [for (final h in _headers) DataCell(Text(row[h] ?? ''))]),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Test için: CSV ayrıştırıcı (Papa.parse header:true eşdeğeri).
@visibleForTesting
List<Map<String, String>> adaptlyParseCsv(String text) => _AdaptlyMergeScreenState._parseCsv(text);
