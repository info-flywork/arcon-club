import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';
import 'tool_common.dart';

String _s(Object? v) => v == null ? '' : '$v';

/// Video Size — webdeki video-creater: videoyu yükle, yeni oranı seç, AI kadrajı yeniden üretsin.
/// Uçlar: video-creater/api.php (upload → create → status, list).
class VideoSizeScreen extends StatefulWidget {
  const VideoSizeScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});
  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  @override
  State<VideoSizeScreen> createState() => _VideoSizeScreenState();
}

class _VideoSizeScreenState extends State<VideoSizeScreen> {
  static const _api = 'video-creater/api.php';
  static const _aspects = [('9:16', 'Dikey 9:16'), ('1:1', 'Kare 1:1'), ('16:9', 'Yatay 16:9'), ('21:9', 'Sinema 21:9')];

  PlatformFile? _file;
  double _seconds = 0;
  bool _uploading = false;
  Map<String, dynamic>? _uploaded;
  String _aspect = '9:16';
  final _note = TextEditingController();
  bool _creating = false;
  String? _error;
  List<Map<String, dynamic>>? _jobs;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _note.dispose();
    super.dispose();
  }

  ArconApi get _apiC => widget.session.api;

  String _abs(String u) => u.startsWith('http') ? u : _apiC.webUrl('video-creater/').resolve(u).toString();

  Future<void> _loadJobs() async {
    try {
      final j = await _apiC.webCall(_api, query: {'action': 'list'});
      if (!mounted) return;
      setState(() => _jobs = [for (final x in ((j['jobs'] as List?) ?? const []).whereType<Map>()) x.cast<String, dynamic>()]);
      _schedulePoll();
    } on ArconApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'tool_unavailable') {
        openWebFallback(context, session: widget.session, config: widget.config, title: widget.title, path: widget.webPath, replace: true);
        return;
      }
      setState(() => _jobs = const []);
    }
  }

  bool _running(Map<String, dynamic> j) => !['success', 'fail'].contains(_s(j['status']));

  void _schedulePoll() {
    _poll?.cancel();
    final running = (_jobs ?? const []).where(_running).toList();
    if (running.isEmpty) return;
    _poll = Timer(const Duration(seconds: 6), () async {
      for (final j in running) {
        try {
          final r = await _apiC.webCall(_api, query: {'action': 'status', 'id': '${j['id']}'});
          final nj = (r['job'] as Map?)?.cast<String, dynamic>();
          if (nj != null && mounted) {
            setState(() => _jobs = [for (final x in _jobs!) x['id'] == nj['id'] ? nj : x]);
            if (nj['status'] == 'success') HapticFeedback.mediumImpact();
          }
        } on ArconApiException catch (_) {}
      }
      if (mounted) _schedulePoll();
    });
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    final f = files.first;
    if (f.path == null || !RegExp(r'\.(mp4|mov|webm|m4v)$', caseSensitive: false).hasMatch(f.name)) {
      toolToast(context, 'MP4, MOV ya da WEBM video seçin');
      return;
    }
    // süre: 2–30 sn
    double secs = 0;
    final v = VideoPlayerController.file(File(f.path!));
    try {
      await v.initialize();
      secs = v.value.duration.inMilliseconds / 1000;
    } catch (_) {
    } finally {
      await v.dispose();
    }
    if (secs > 0 && (secs < 2 || secs > 30.5)) {
      if (mounted) toolToast(context, 'Video 2–30 saniye arasında olmalı (seçilen: ${secs.toStringAsFixed(0)} sn)');
      return;
    }
    setState(() {
      _file = f;
      _seconds = secs;
      _uploaded = null;
      _error = null;
      _uploading = true;
    });
    try {
      final r = await _apiC.webCall(_api, query: {'action': 'upload'}, fields: const {}, files: [('file', f.path!)], timeout: const Duration(minutes: 5));
      if (mounted) setState(() => _uploaded = r);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _create() async {
    final up = _uploaded;
    if (up == null || _creating) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _creating = true;
      _error = null;
    });
    final seconds = (_seconds > 0 ? _seconds.round() : 5).clamp(3, 30);
    final extra = _note.text.trim();
    final prompt = 'Bu videoyu $_aspect boyuta getir. Ön plandaki tüm öğeleri değiştirmeden eksiksiz koru ve kenarlarını temiz, pürüzsüz tut. '
        'Kadrajı $_aspect oranında düzenle.${extra.isEmpty ? '' : ' $extra'}';
    try {
      await _apiC.webCall(_api, query: {'action': 'create'}, jsonBody: {
        'prompt': prompt,
        'aspect_ratio': _aspect,
        'duration': seconds,
        'source_seconds': _seconds,
        'source_file': _s(up['local']),
        'keep_original_sound': true,
        'video_urls': [up['url']],
      });
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      toolToast(context, 'Video hazırlanıyor; birkaç dakika sürebilir.');
      setState(() {
        _file = null;
        _uploaded = null;
        _note.clear();
      });
      await _loadJobs();
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final jobs = _jobs;
    return ToolPage(
      title: widget.title,
      children: [
        const ToolIntro(title: 'Video boyutlandır', text: 'Videonu yükle, yeni oranı seç; yapay zekâ kadrajı ön plandaki öğeleri koruyarak yeniden oluştursun.'),
        ToolStep(
          n: 1,
          title: 'Video (2–30 sn)',
          done: _uploaded != null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToolFilePick(label: 'Video seç', fileName: _file?.name, onPick: _pick, icon: Icons.video_library_outlined),
              if (_uploading) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)),
                    const SizedBox(width: 8),
                    Text('Yükleniyor…', style: c.text(12.5, color: c.muted)),
                  ],
                ),
              ] else if (_uploaded != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Yüklendi${_seconds > 0 ? ' · ${_seconds.toStringAsFixed(1)} sn' : ''}', style: c.text(12.5, color: c.muted)),
                ),
            ],
          ),
        ),
        ToolStep(
          n: 2,
          title: 'Yeni oran',
          done: true,
          child: ToolChoice<String>(items: _aspects, value: _aspect, onChanged: (v) => setState(() => _aspect = v)),
        ),
        ToolStep(
          n: 3,
          title: 'Ek not (isteğe bağlı)',
          done: _note.text.isNotEmpty,
          child: TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            style: c.text(14.5, height: 1.4),
            cursorColor: c.ink,
            decoration: c.input('Ör. ürünü ortala, arka planı beyaz yap', null).copyWith(fillColor: c.bg),
          ),
        ),
        Opacity(opacity: _uploaded == null ? 0.4 : 1, child: c.primaryButton('Videoyu düzelt', busy: _creating, onPressed: _create)),
        if (_error != null) ...[const SizedBox(height: 12), c.errorBox(_error!)],
        const SizedBox(height: 24),
        Row(
          children: [
            Text(trUpper('Videolarım'), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: c.line)),
          ],
        ),
        const SizedBox(height: 10),
        if (jobs == null)
          const SkeletonList(count: 3, leading: false, thumbnail: true)
        else if (jobs.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Henüz video yok', style: c.text(14, color: c.muted))))
        else
          for (final j in jobs) _jobRow(c, j),
      ],
    );
  }

  Widget _jobRow(ArconMono c, Map<String, dynamic> j) {
    final status = _s(j['status']);
    final ok = status == 'success' && _s(j['result_url']).isNotEmpty;
    final ratio = _s((j['params'] as Map?)?['aspect_ratio']);
    final label = switch (status) {
      'success' => 'Hazır',
      'fail' => _s(j['fail_msg']).isEmpty ? 'Başarısız' : _s(j['fail_msg']),
      'generating' => 'Üretiliyor${j['progress'] != null ? ' · %${j['progress']}' : ''}',
      'queuing' => 'Sırada',
      _ => 'Bekliyor',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: ok ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _VideoPlayerPage(url: _abs(_s(j['result_url'])), title: ratio.isEmpty ? 'Video' : 'Video · $ratio'))) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: ok ? c.ink : c.bg, borderRadius: BorderRadius.circular(12), border: ok ? null : Border.all(color: c.line)),
                  child: _running(j)
                      ? Padding(padding: const EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                      : Icon(ok ? Icons.play_arrow_rounded : Icons.error_outline_rounded, color: ok ? c.bg : c.danger),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ratio.isEmpty ? 'Video' : '$ratio · ${j['duration']} sn', style: c.text(14, weight: FontWeight.w700)),
                      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(12, color: status == 'fail' ? c.danger : c.muted)),
                    ],
                  ),
                ),
                if (ok) Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPlayerPage extends StatefulWidget {
  const _VideoPlayerPage({required this.url, required this.title});
  final String url;
  final String title;

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late final VideoPlayerController _v = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _v.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _v
        ..setLooping(true)
        ..play();
    });
    _v.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Kaydet / paylaş',
            onPressed: () => toolOpenUrlFile(context, widget.url, fileName: 'video.mp4'),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: Center(
        child: !_ready
            ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            : GestureDetector(
                onTap: () => _v.value.isPlaying ? _v.pause() : _v.play(),
                child: AspectRatio(aspectRatio: _v.value.aspectRatio, child: VideoPlayer(_v)),
              ),
      ),
    );
  }
}
