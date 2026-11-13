import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import 'tool_common.dart';
import 'uts_screens.dart';

/// Packing markası — webdeki tools/packing/app.js ile aynı: PDF paket listesi → marka servisinde dönüştürme.
class PackingBrand {
  const PackingBrand(this.id, this.label, this.api, this.prefer, this.downloadLabel);
  final String id;
  final String label;
  final String api;
  final List<String> prefer;
  final String downloadLabel;

  static const all = [
    PackingBrand('dior', 'Dior', 'https://packaging.fly-work.com/api/convert', ['json_url', 'csv_url', 'xlsx_url'], 'Sonucu aç'),
    PackingBrand('givenchy', 'Givenchy', 'https://givenchy.fly-work.com/api/convert', ['json_url', 'csv_url', 'xlsx_url'], 'Sonucu aç'),
    PackingBrand('hermes', 'Hermès', 'https://hermes.fly-work.com/api/convert', ['xlsx_url'], 'Excel’i aç'),
    PackingBrand('puig', 'Puig', 'https://puigpackage.fly-work.com/api/convert', ['xlsx_url', 'json_url', 'csv_url'], 'Sonucu aç'),
    PackingBrand('dg', 'Dolce&Gabbana', 'https://dgpackage.fly-work.com/api/convert', ['xlsx_url', 'json_url', 'csv_url'], 'Sonucu aç'),
    PackingBrand('sisley', 'Sisley', 'https://sisleypacking.fly-work.com/api/convert', ['xlsx_url', 'json_url', 'csv_url'], 'Sonucu aç'),
  ];

  UtsBrand get logo => UtsBrand.all.firstWhere((b) => b.id == id);
}

/// Packing Modülleri — marka seçimi.
class PackingHubScreen extends StatelessWidget {
  const PackingHubScreen({super.key, required this.session, required this.config, required this.title});
  final SessionController session;
  final ArconAppConfig config;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return ToolPage(
      title: title,
      children: [
        const ToolIntro(title: 'Marka seç', text: 'PDF paket listesini yükle; markanın formatında çeki listesine dönüştürülsün.'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.9,
          children: [
            for (final b in PackingBrand.all)
              PressScale(
                child: Material(
                  color: c.bg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PackingScreen(session: session, brand: b))),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          UtsBrandLogo(session: session, brand: b.logo, size: 68),
                          const SizedBox(height: 10),
                          Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class PackingScreen extends StatefulWidget {
  const PackingScreen({super.key, required this.session, required this.brand});
  final SessionController session;
  final PackingBrand brand;

  @override
  State<PackingScreen> createState() => _PackingScreenState();
}

class _PackingScreenState extends State<PackingScreen> {
  PlatformFile? _file;
  bool _busy = false;
  String? _error;
  String? _resultUrl;
  String? _resultName;

  PackingBrand get _b => widget.brand;

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    final f = files.first;
    if (f.path == null || !f.name.toLowerCase().endsWith('.pdf')) {
      toolToast(context, 'PDF dosyası seçin');
      return;
    }
    setState(() {
      _file = f;
      _resultUrl = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final f = _file;
    if (f == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _resultUrl = null;
    });
    final t0 = DateTime.now();
    // Girdi PDF'i ARCON'a arşivlenir (log için; başarısız olsa da devam)
    String? inputUrl;
    try {
      final up = await widget.session.api.webCall('tools/packing_upload.php', fields: const {}, files: [('file', f.path!)]);
      inputUrl = up['url'] as String?;
    } catch (_) {}
    try {
      final req = http.MultipartRequest('POST', Uri.parse(_b.api));
      req.files.add(await http.MultipartFile.fromPath('file', f.path!));
      final res = await http.Response.fromStream(await req.send()).timeout(const Duration(minutes: 5));
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {}
      if (data == null) {
        setState(() => _error = switch (res.statusCode) {
              504 => 'İşlem zaman aşımına uğradı.',
              413 => 'Dosya boyutu çok büyük.',
              _ => 'Sunucu hatası: ${res.statusCode}.',
            });
        return;
      }
      if (res.statusCode >= 400 || data['success'] != true) {
        setState(() => _error = '${data!['error'] ?? 'Dönüştürme başarısız oldu.'}');
        return;
      }
      String? url;
      for (final k in [..._b.prefer, 'json_url', 'csv_url', 'xlsx_url']) {
        if ((data[k] ?? '').toString().isNotEmpty) {
          url = '${data[k]}';
          break;
        }
      }
      HapticFeedback.mediumImpact();
      setState(() {
        _resultUrl = url;
        _resultName = data!['file_name'] as String?;
      });
      widget.session.api.webCall('tools/packing_log.php', jsonBody: {
        'brand': _b.id,
        'input_file': f.name,
        'input_file_url': inputUrl,
        'output_url': url,
        'duration_ms': DateTime.now().difference(t0).inMilliseconds,
      }).catchError((_) => <String, dynamic>{});
    } on Exception {
      if (mounted) setState(() => _error = 'Dönüştürme servisine ulaşılamadı.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return ToolPage(
      title: '${_b.label} — Paket listesi',
      children: [
        Center(child: UtsBrandLogo(session: widget.session, brand: _b.logo, size: 84)),
        const SizedBox(height: 14),
        ToolIntro(title: '${_b.label} çeki listesi', text: 'PDF paket listeni yükle; ${_b.label} için otomatik olarak dönüştürülsün.'),
        ToolStep(n: 1, title: 'PDF paket listesi', done: _file != null, child: ToolFilePick(label: 'PDF seç', fileName: _file?.name, onPick: _pick)),
        Opacity(opacity: _file == null ? 0.4 : 1, child: c.primaryButton('Dönüştür', busy: _busy, onPressed: _run)),
        if (_busy) ...[
          const SizedBox(height: 10),
          Text('PDF işleniyor; büyük dosyalarda birkaç dakika sürebilir.', textAlign: TextAlign.center, style: c.text(12.5, color: c.muted)),
        ],
        if (_error != null) ...[const SizedBox(height: 12), c.errorBox(_error!)],
        if (_resultUrl != null) ...[
          const SizedBox(height: 14),
          ToolResult(
            title: 'Dönüştürme tamamlandı',
            text: _resultName,
            actions: [
              (Icons.open_in_new_rounded, _b.downloadLabel, () => toolOpenUrlFile(context, _resultUrl!, fileName: _resultName)),
              (Icons.ios_share_rounded, 'Bağlantıyı tarayıcıda aç', () => launchUrl(Uri.parse(_resultUrl!), mode: LaunchMode.externalApplication)),
            ],
          ),
        ],
      ],
    );
  }
}
