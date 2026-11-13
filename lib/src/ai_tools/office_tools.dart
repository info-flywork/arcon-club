
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/native_fallback.dart';
import 'tool_common.dart';

/* ============================== Deklarasyon ============================== */

/// Deklarasyon — webdeki declarations: barkodlardan Sağlık Bakanlığı ÜTS Excel'i (declarations/export_process.php).
class DeclarationScreen extends StatefulWidget {
  const DeclarationScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});
  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  @override
  State<DeclarationScreen> createState() => _DeclarationScreenState();
}

class _DeclarationScreenState extends State<DeclarationScreen> {
  /// Webdeki gibi: 5 boş barkod alanı, "Barkod ekle" ile yenisi.
  final List<TextEditingController> _fields = [];
  final List<FocusNode> _focus = [];
  bool _busy = false;
  String? _url;
  List<String> _missing = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 5; i++) {
      _addField(focus: false);
    }
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  void _addField({bool focus = true, String text = ''}) {
    final c = TextEditingController(text: text)..addListener(() => setState(() {}));
    final f = FocusNode();
    _fields.add(c);
    _focus.add(f);
    if (focus) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => f.requestFocus());
    }
  }

  void _removeField(int i) {
    setState(() {
      _fields.removeAt(i).dispose();
      _focus.removeAt(i).dispose();
    });
  }

  List<String> get _barcodes => _fields.map((c) => c.text.trim()).where((e) => e.isNotEmpty).toSet().toList();

  /// Excel'den kopyalanan barkodları boş alanlara sırayla dağıtır; yetmezse yeni alan açar.
  Future<void> _paste() async {
    final d = await Clipboard.getData('text/plain');
    final codes = (d?.text ?? '').split(RegExp(r'[\s,;]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (codes.isEmpty) return;
    setState(() {
      var i = 0;
      for (final c in _fields) {
        if (i >= codes.length) break;
        if (c.text.trim().isEmpty) c.text = codes[i++];
      }
      while (i < codes.length) {
        _addField(focus: false, text: codes[i++]);
      }
    });
  }

  Future<void> _run() async {
    final codes = _barcodes;
    if (codes.isEmpty || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _url = null;
      _missing = const [];
    });
    try {
      final r = await widget.session.api.webCall('declarations/export_process.php', jsonBody: {'barcodes': codes});
      HapticFeedback.mediumImpact();
      setState(() {
        _url = r['url'] as String?;
        _missing = ((r['missingBarcodes'] as List?) ?? const []).map((e) => '$e').toList();
      });
    } on ArconApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'tool_unavailable') {
        openWebFallback(context, session: widget.session, config: widget.config, title: widget.title, path: widget.webPath, replace: true);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final n = _barcodes.length;
    return ToolPage(
      title: widget.title,
      children: [
        const ToolIntro(
          title: 'Deklarasyon Excel',
          text: 'Etiket onayı sonrası Sağlık Bakanlığı’na iletilecek ÜTS deklarasyon Excel’ini barkodlardan oluşturur.',
        ),
        Row(
          children: [
            Expanded(child: c.label('Barkodlar${n > 0 ? ' · $n' : ''}')),
            TextButton.icon(
              onPressed: _paste,
              icon: Icon(Icons.content_paste_rounded, size: 17, color: c.ink),
              label: Text('Yapıştır', style: c.text(13, weight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < _fields.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _fields[i],
              focusNode: _focus[i],
              keyboardType: TextInputType.number,
              textInputAction: i == _fields.length - 1 ? TextInputAction.done : TextInputAction.next,
              onSubmitted: (_) {
                if (i < _fields.length - 1) _focus[i + 1].requestFocus();
              },
              keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
              style: c.text(15).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              cursorColor: c.ink,
              decoration: c.input('${i + 1}. Barkod', Icons.qr_code_rounded).copyWith(
                    suffixIcon: i >= 5
                        ? IconButton(onPressed: () => _removeField(i), icon: Icon(Icons.close_rounded, size: 18, color: c.muted))
                        : (_fields[i].text.isEmpty ? null : IconButton(onPressed: _fields[i].clear, icon: Icon(Icons.close_rounded, size: 18, color: c.muted))),
                  ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _addField(),
            icon: Icon(Icons.add_rounded, size: 19, color: c.ink),
            label: Text('Barkod ekle', style: c.text(13.5, weight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        Opacity(opacity: n == 0 ? 0.4 : 1, child: c.primaryButton(n > 1 ? '$n barkod için Excel oluştur' : 'Excel oluştur', busy: _busy, onPressed: _run)),
        if (_error != null) ...[const SizedBox(height: 12), c.errorBox(_error!)],
        if (_url != null) ...[
          const SizedBox(height: 14),
          ToolResult(
            title: 'Excel hazır',
            text: _missing.isEmpty ? 'Tüm barkodlar bulundu.' : '${_missing.length} barkod veritabanında bulunamadı: ${_missing.join(', ')}',
            actions: [
              (Icons.open_in_new_rounded, 'Excel’i aç', () => toolOpenUrlFile(context, _url!)),
              (Icons.ios_share_rounded, 'Bağlantıyı paylaş', () => launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication)),
            ],
          ),
        ],
      ],
    );
  }
}

/* ============================== Teslim Tutanağı ve İade Yazısı ============================== */

/// Teslim Tutanağı / İade Yazısı — webdeki deliveryreport: Excel'den toplu Word belgeleri (ZIP).
/// Belge üretimi deliveryreport.fly-work.com servisinde; işlem logu ARCON'a yazılır.
class DeliveryReportScreen extends StatefulWidget {
  const DeliveryReportScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});
  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  @override
  State<DeliveryReportScreen> createState() => _DeliveryReportScreenState();
}

class _DeliveryReportScreenState extends State<DeliveryReportScreen> {
  static const _api = 'https://deliveryreport.fly-work.com';
  static const _template = 'https://deliveryreportarcon.b-cdn.net/ornek/ornek-veri.xlsx';

  String _module = 'iade';
  PlatformFile? _file;
  bool _busy = false;
  bool _converting = false;
  String? _error;
  (Uint8List, String)? _result;

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    final f = files.first;
    if (!RegExp(r'\.(xlsx|xls)$', caseSensitive: false).hasMatch(f.name) || f.path == null) {
      toolToast(context, 'Excel dosyası (.xlsx / .xls) seçin');
      return;
    }
    setState(() {
      _file = f;
      _result = null;
      _error = null;
    });
  }

  Future<http.Response> _post(String endpoint, Map<String, String> fields) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_api$endpoint'))..fields.addAll(fields);
    req.files.add(await http.MultipartFile.fromPath('file', _file!.path!));
    return http.Response.fromStream(await req.send()).timeout(const Duration(minutes: 4));
  }

  String _errorOf(http.Response res, String fallback) {
    try {
      final m = RegExp(r'"(?:error|message)"\s*:\s*"([^"]+)"').firstMatch(res.body);
      if (m != null) return m.group(1)!;
    } catch (_) {}
    if (res.statusCode >= 500) return 'Belge servisine ulaşılamıyor, biraz sonra tekrar dene.';
    return fallback;
  }

  void _log(Map<String, Object?> body) {
    widget.session.api.webCall('deliveryreport/log.php', jsonBody: body).catchError((_) => <String, dynamic>{});
  }

  Future<void> _generate() async {
    if (_file == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    final t0 = DateTime.now();
    try {
      final res = await _post('/api/generate', {'module': _module});
      if (res.statusCode != 200) {
        setState(() => _error = _errorOf(res, 'Belgeler oluşturulamadı. Excel’in şablona uygun olduğundan emin ol.'));
        return;
      }
      final name = _module == 'teslim' ? 'Teslim-Tutanaklari.zip' : 'Iade-Yazilari.zip';
      HapticFeedback.mediumImpact();
      setState(() => _result = (res.bodyBytes, name));
      _log({
        'doc_type': _module,
        'action': 'generate',
        'input_file': _file!.name,
        'output_file': name,
        'duration_ms': DateTime.now().difference(t0).inMilliseconds,
      });
    } on Exception {
      if (mounted) setState(() => _error = 'Belge servisine ulaşılamadı. İnternet bağlantını kontrol et.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convert() async {
    if (_file == null || _converting) return;
    setState(() {
      _converting = true;
      _error = null;
    });
    final t0 = DateTime.now();
    try {
      final res = await _post('/api/convert-excel', const {});
      if (res.statusCode != 200) {
        setState(() => _error = _errorOf(res, 'Excel şablona çevrilemedi.'));
        return;
      }
      final base = _file!.name.replaceAll(RegExp(r'\.(xlsx|xls)$', caseSensitive: false), '');
      final name = '$base-sablon.xlsx';
      _log({'doc_type': 'convert', 'action': 'convert', 'input_file': _file!.name, 'output_file': name, 'duration_ms': DateTime.now().difference(t0).inMilliseconds, 'used_ai': true});
      if (mounted) await toolShareBytes(context, res.bodyBytes, name);
    } on Exception {
      if (mounted) setState(() => _error = 'Dönüştürme servisine ulaşılamadı.');
    } finally {
      if (mounted) setState(() => _converting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final teslim = _module == 'teslim';
    return ToolPage(
      title: widget.title,
      children: [
        const ToolIntro(
          title: 'Teslim tutanağı ve iade yazısı',
          text: 'Excel şablonundaki satırlardan Word belgelerini toplu hazırlar; hepsi tek ZIP dosyasında gelir.',
        ),
        ToolStep(
          n: 1,
          title: 'Belge türü',
          done: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToolChoice<String>(
                items: const [('iade', 'İade yazısı'), ('teslim', 'Teslim tutanağı')],
                value: _module,
                onChanged: (v) => setState(() {
                  _module = v;
                  _result = null;
                }),
              ),
              const SizedBox(height: 10),
              Text(
                teslim
                    ? 'Aynı Takip No’lu satırlar gruplanır; her takip numarası için bir belge oluşturulur.'
                    : 'Yalnızca “İNCELEMEDEN SONRA DURUM” sütunu RED olan satırlar işlenir; her satır ayrı belge olur.',
                style: c.text(12.5, color: c.muted, height: 1.45),
              ),
            ],
          ),
        ),
        ToolStep(
          n: 2,
          title: 'Excel dosyası',
          done: _file != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToolFilePick(label: 'Excel seç (.xlsx)', fileName: _file?.name, onPick: _pick),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => toolOpenUrlFile(context, _template, fileName: 'ornek-veri.xlsx'),
                      icon: Icon(Icons.download_rounded, size: 17, color: c.ink),
                      label: Text('Boş şablonu aç', style: c.text(12.5, weight: FontWeight.w700)),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _file == null || _converting ? null : _convert,
                      icon: _converting
                          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                          : Icon(Icons.auto_fix_high_rounded, size: 17, color: _file == null ? c.faint : c.ink),
                      label: Text('Şablona çevir (AI)', style: c.text(12.5, weight: FontWeight.w700, color: _file == null ? c.faint : c.ink)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Opacity(
          opacity: _file == null ? 0.4 : 1,
          child: c.primaryButton(teslim ? 'Tutanakları oluştur' : 'İade yazılarını oluştur', busy: _busy, onPressed: _generate),
        ),
        if (_error != null) ...[const SizedBox(height: 12), c.errorBox(_error!)],
        if (_result != null) ...[
          const SizedBox(height: 14),
          ToolResult(
            title: 'Belgeler hazır',
            text: '${_result!.$2} · ${(_result!.$1.length / 1024).ceil()} KB',
            actions: [(Icons.ios_share_rounded, 'ZIP’i kaydet / paylaş', () => toolShareBytes(context, _result!.$1, _result!.$2))],
          ),
        ],
      ],
    );
  }
}
