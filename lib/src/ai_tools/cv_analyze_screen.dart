import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
List<String> _strs(Object? v) => ((v as List?) ?? const []).map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();

enum _St { waiting, running, done, failed }

class _Cv {
  _Cv(this.file);
  final PlatformFile file;
  _St state = _St.waiting;
  Map<String, dynamic>? result;
  String? error;

  int? get score => result?['hiring_fit_score'] == null ? null : _i(result!['hiring_fit_score']);
  String get name => _s(result?['candidate_name']).isNotEmpty ? _s(result!['candidate_name']) : file.name;
}

/// CV Analyze — webdeki cv-analyze aracı: iş ilanı + CV'ler → aday raporları ve karşılaştırmalı özet.
/// Her CV ayrı istekte analiz edilir (webdeki gibi), en az iki aday olunca karşılaştırma üretilir.
class CvAnalyzeScreen extends StatefulWidget {
  const CvAnalyzeScreen({super.key, required this.session, required this.config, required this.title, required this.webPath});

  final SessionController session;
  final ArconAppConfig config;
  final String title;
  final String webPath;

  @override
  State<CvAnalyzeScreen> createState() => _CvAnalyzeScreenState();
}

class _CvAnalyzeScreenState extends State<CvAnalyzeScreen> {
  static const _folder = 'cv-analyze';
  static const _ext = ['pdf', 'docx'];

  PlatformFile? _job;
  final List<_Cv> _cvs = [];
  bool _running = false;
  bool _comparing = false;
  Map<String, dynamic>? _compare;
  String? _compareError;
  String? _jobUrl;
  String _sessionId = '';

  bool get _started => _cvs.any((c) => c.state != _St.waiting) || _running;

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  bool _okExt(PlatformFile f) => _ext.contains(f.name.split('.').last.toLowerCase());

  Future<void> _pickJob() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    if (!_okExt(files.first) || files.first.path == null) {
      _toast('İş ilanı PDF ya da DOCX olmalı');
      return;
    }
    setState(() => _job = files.first);
  }

  Future<void> _pickCvs() async {
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) return;
    final ok = files.where((f) => _okExt(f) && f.path != null).toList();
    if (ok.length < files.length) _toast('Yalnızca PDF ve DOCX dosyaları eklendi');
    setState(() {
      for (final f in ok) {
        if (_cvs.length < 20 && !_cvs.any((c) => c.file.name == f.name)) _cvs.add(_Cv(f));
      }
    });
  }

  void _reset() {
    setState(() {
      _job = null;
      _cvs.clear();
      _compare = null;
      _compareError = null;
      _jobUrl = null;
    });
  }

  Future<void> _start() async {
    final job = _job;
    if (job == null || _cvs.isEmpty || _running) return;
    _sessionId = 'cv_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 20).toRadixString(36)}';
    setState(() {
      _running = true;
      _compare = null;
      _compareError = null;
    });
    final title = 'İş ilanı: ${job.name}';
    for (var i = 0; i < _cvs.length; i++) {
      final cv = _cvs[i];
      if (cv.state == _St.done) continue;
      setState(() {
        cv.state = _St.running;
        cv.error = null;
      });
      try {
        final r = await widget.session.api.toolPost(
          _folder,
          {
            'action': 'analyze_one',
            'index': '$i',
            'session_id': _sessionId,
            'session_title': title,
            'msg_count': '${i + 1}',
            'job_url': ?_jobUrl,
          },
          namedFiles: {'job_file': job.path!, 'cv_file': cv.file.path!},
        );
        _jobUrl ??= r['job_url'] as String?;
        if (!mounted) return;
        setState(() {
          cv.result = r;
          cv.state = _St.done;
        });
      } on ArconApiException catch (e) {
        if (!mounted) return;
        if (e.code == 'tool_unavailable') {
          openWebFallback(context, session: widget.session, config: widget.config, title: widget.title, path: widget.webPath, replace: true);
          return;
        }
        setState(() {
          cv.state = _St.failed;
          cv.error = e.message;
        });
      }
    }
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _running = false);
    final done = _cvs.where((c) => c.state == _St.done).toList();
    if (done.length >= 2) await _runCompare(done);
  }

  Future<void> _runCompare(List<_Cv> done) async {
    final job = _job;
    if (job == null) return;
    setState(() {
      _comparing = true;
      _compareError = null;
    });
    try {
      final r = await widget.session.api.toolPost(
        _folder,
        {
          'action': 'finalize_compare',
          'session_id': _sessionId,
          'session_title': 'İş ilanı: ${job.name}',
          'msg_count': '${done.length + 1}',
          'summaries': jsonEncode([for (final c in done) c.result?['summary']]),
          'job_url': ?_jobUrl,
        },
        namedFiles: {'job_file': job.path!},
      );
      if (mounted) setState(() => _compare = r);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _compareError = e.message);
    } finally {
      if (mounted) setState(() => _comparing = false);
    }
  }

  Future<void> _open(String? url) async {
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final doneCount = _cvs.where((x) => x.state == _St.done).length;
    final sorted = [..._cvs]..sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(17, weight: FontWeight.w800))),
                    if (_started && !_running && !_comparing)
                      TextButton.icon(
                        onPressed: _reset,
                        icon: Icon(Icons.refresh_rounded, color: c.ink, size: 19),
                        label: Text('Yeni analiz', style: c.text(13.5, weight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
                  children: [
                    if (!_started) ...[
                      Text('CV analizi', style: c.text(26, weight: FontWeight.w800, spacing: -0.7)),
                      const SizedBox(height: 6),
                      Text(
                        'İş ilanını ve aday CV’lerini yükle; her aday için puanlı değerlendirme raporu, birden fazla adayda karşılaştırmalı özet hazırlayayım.',
                        style: c.text(14, color: c.muted, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                    ],
                    _step(
                      c,
                      n: 1,
                      title: 'İş ilanı / görev tanımı',
                      done: _job != null,
                      child: _job == null
                          ? _pickButton(c, Icons.upload_file_rounded, 'İş ilanını seç (PDF / DOCX)', _pickJob)
                          : _fileRow(c, _job!.name, onRemove: _started ? null : () => setState(() => _job = null)),
                    ),
                    const SizedBox(height: 12),
                    _step(
                      c,
                      n: 2,
                      title: _cvs.isEmpty ? 'Aday CV’leri' : 'Aday CV’leri · ${_cvs.length}',
                      done: _cvs.isNotEmpty,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final cv in (_started ? sorted : _cvs)) _cvRow(c, cv),
                          if (!_started) ...[
                            if (_cvs.isNotEmpty) const SizedBox(height: 4),
                            _pickButton(c, Icons.person_add_alt_1_outlined, _cvs.isEmpty ? 'CV seç (birden fazla seçebilirsin)' : 'CV ekle', _pickCvs),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (!_started)
                      Opacity(
                        opacity: _job != null && _cvs.isNotEmpty ? 1 : 0.4,
                        child: c.primaryButton(
                          _cvs.length > 1 ? '${_cvs.length} adayı analiz et' : 'Analizi başlat',
                          busy: false,
                          onPressed: _start,
                        ),
                      )
                    else if (_running)
                      _progress(c, doneCount)
                    else
                      ..._summary(c, doneCount),
                    if (_comparing || _compare != null || _compareError != null) ...[
                      const SizedBox(height: 16),
                      _compareCard(c),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step(ArconMono c, {required int n, required String title, required bool done, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: Motion.of(context, Motion.fast),
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: done ? c.ink : Colors.transparent, shape: BoxShape.circle, border: Border.all(color: done ? c.ink : c.line, width: 1.5)),
                  child: done ? Icon(Icons.check_rounded, size: 15, color: c.bg) : Text('$n', style: c.text(12, weight: FontWeight.w800, color: c.muted)),
                ),
                const SizedBox(width: 10),
                Text(title, style: c.text(15, weight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _pickButton(ArconMono c, IconData icon, String label, VoidCallback onTap) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.bg,
          side: BorderSide(color: c.line),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(icon, size: 19),
        label: Text(label, style: c.text(13.5, weight: FontWeight.w700)),
      );

  Widget _fileRow(ArconMono c, String name, {VoidCallback? onRemove}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
        child: Row(
          children: [
            Icon(Icons.description_outlined, size: 20, color: c.ink),
            const SizedBox(width: 10),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14, weight: FontWeight.w600))),
            if (onRemove != null) IconButton(onPressed: onRemove, icon: Icon(Icons.close_rounded, size: 18, color: c.muted)) else const SizedBox(height: 40),
          ],
        ),
      );

  Widget _cvRow(ArconMono c, _Cv cv) {
    final trailing = switch (cv.state) {
      _St.waiting when !_started => IconButton(onPressed: () => setState(() => _cvs.remove(cv)), icon: Icon(Icons.close_rounded, size: 18, color: c.muted)),
      _St.waiting => Padding(padding: const EdgeInsets.all(12), child: Icon(Icons.schedule_rounded, size: 18, color: c.faint)),
      _St.running => Padding(padding: const EdgeInsets.all(13), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))),
      _St.failed => Padding(padding: const EdgeInsets.all(12), child: Icon(Icons.error_outline_rounded, size: 20, color: c.danger)),
      _St.done => _ScoreBadge(score: cv.score),
    };
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: Row(
        children: [
          Icon(cv.state == _St.done ? Icons.person_outline_rounded : Icons.description_outlined, size: 20, color: c.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cv.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14, weight: FontWeight.w700)),
                if (cv.state == _St.done && _s(cv.result?['recommendation']).isNotEmpty)
                  Text(_s(cv.result!['recommendation']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.muted))
                else if (cv.state == _St.failed)
                  Text(cv.error ?? 'Analiz yapılamadı', maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.danger))
                else if (cv.state == _St.running)
                  Text('Analiz ediliyor…', style: c.text(12, color: c.muted))
                else if (cv.state == _St.done)
                  Text(cv.file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.muted)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
    if (cv.state != _St.done) return row;
    return PressScale(
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _CvReportScreen(cv: cv, onOpen: _open))),
        child: row,
      ),
    );
  }

  Widget _progress(ArconMono c, int done) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _cvs.isEmpty ? 0 : (done + 0.35) / _cvs.length),
              duration: Motion.of(context, Motion.normal),
              builder: (_, v, _) => LinearProgressIndicator(value: v.clamp(0.0, 1.0), minHeight: 6, color: c.ink, backgroundColor: c.line),
            ),
          ),
          const SizedBox(height: 8),
          Text('$done / ${_cvs.length} aday tamamlandı · her CV yaklaşık 1 dakika sürer', style: c.text(12.5, color: c.muted)),
        ],
      );

  List<Widget> _summary(ArconMono c, int done) {
    final failed = _cvs.where((x) => x.state == _St.failed).length;
    return [
      Text(
        failed > 0 ? '$done aday analiz edildi, $failed CV okunamadı.' : '$done aday analiz edildi. Raporu görmek için adaya dokun.',
        style: c.text(13, color: c.muted),
      ),
      if (failed > 0) ...[
        const SizedBox(height: 10),
        _pickButton(c, Icons.refresh_rounded, 'Okunamayanları tekrar dene', _start),
      ],
    ];
  }

  Widget _compareCard(ArconMono c) {
    final r = _compare;
    final cmp = (r?['comparison'] as Map?)?.cast<String, dynamic>() ?? const {};
    final ranking = ((r?['ranking'] as List?) ?? const []).whereType<Map>().toList();
    final concl = (cmp['conclusion'] as Map?)?.cast<String, dynamic>() ?? const {};
    final shortlist = _strs(concl['shortlist']);
    final fg = c.dark ? c.ink : c.bg;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: c.dark ? c.field : c.ink, borderRadius: BorderRadius.circular(20), border: c.dark ? Border.all(color: c.line) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trUpper('Karşılaştırmalı özet'), style: c.text(10.5, weight: FontWeight.w700, color: fg.withValues(alpha: 0.6), spacing: 1.2)),
          const SizedBox(height: 4),
          if (_comparing)
            Row(
              children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                const SizedBox(width: 10),
                Text('Adaylar karşılaştırılıyor…', style: c.text(15, weight: FontWeight.w700, color: fg)),
              ],
            )
          else if (_compareError != null) ...[
            Text(_compareError!, style: c.text(14, color: fg)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _runCompare(_cvs.where((x) => x.state == _St.done).toList()),
              child: Text('Tekrar dene', style: c.text(14, weight: FontWeight.w700, color: fg)),
            ),
          ] else ...[
            Text(_s(r?['position_title']).isEmpty ? 'Aday sıralaması' : _s(r!['position_title']), style: c.text(20, weight: FontWeight.w800, color: fg, spacing: -0.4)),
            const SizedBox(height: 12),
            for (var i = 0; i < ranking.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: i == 0 ? fg : Colors.transparent, shape: BoxShape.circle, border: Border.all(color: fg.withValues(alpha: 0.4))),
                      child: Text('${i + 1}', style: c.text(12, weight: FontWeight.w800, color: i == 0 ? (c.dark ? c.bg : c.ink) : fg)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_s(ranking[i]['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w700, color: fg))),
                    Text('${_i(ranking[i]['score'])}', style: c.text(15, weight: FontWeight.w800, color: fg)),
                  ],
                ),
              ),
            if (shortlist.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Kısa liste: ${shortlist.join(', ')}', style: c.text(13, color: fg.withValues(alpha: 0.8), height: 1.45)),
            ],
            if (_s(concl['closing']).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_s(concl['closing']), style: c.text(13, color: fg.withValues(alpha: 0.75), height: 1.5)),
            ],
            if (r?['report_url'] != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _open(r!['report_url'] as String?),
                style: OutlinedButton.styleFrom(
                  foregroundColor: fg,
                  side: BorderSide(color: fg.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text('Genel özet PDF', style: c.text(14, weight: FontWeight.w700, color: fg)),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});
  final int? score;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: score == null ? 0 : (score! / 100).clamp(0.0, 1.0),
                  strokeWidth: 3.2,
                  color: c.ink,
                  backgroundColor: c.line,
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text(score == null ? '—' : '$score', style: c.text(12.5, weight: FontWeight.w800)),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: c.faint),
      ],
    );
  }
}

/* ============================== Aday raporu ============================== */

class _CvReportScreen extends StatelessWidget {
  const _CvReportScreen({required this.cv, required this.onOpen});

  final _Cv cv;
  final Future<void> Function(String?) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final r = cv.result ?? const {};
    final a = (r['analysis'] as Map?)?.cast<String, dynamic>() ?? const {};
    final hiring = (a['hiring_fit'] as Map?)?.cast<String, dynamic>() ?? const {};
    final swot = (a['swot'] as Map?)?.cast<String, dynamic>() ?? const {};
    final gap = (a['gap_analysis'] as Map?)?.cast<String, dynamic>() ?? const {};
    final fin = (a['final_recommendation'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pad = MediaQuery.paddingOf(context);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Text(title, style: c.text(18, weight: FontWeight.w800, spacing: -0.3)), const SizedBox(height: 10), ...children],
          ),
        );
    Widget box(Widget child) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: child,
        );
    Widget bullets(List<String> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 8),
                      child: Container(width: 4, height: 4, decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle)),
                    ),
                    Expanded(child: Text(t, style: c.text(13.5, height: 1.45))),
                  ],
                ),
              ),
          ],
        );

    final score = cv.score;
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
                  IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                  Expanded(child: Text('Aday raporu', style: c.text(17, weight: FontWeight.w800))),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 28 + pad.bottom),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cv.name, style: c.text(24, weight: FontWeight.w800, height: 1.2, spacing: -0.6)),
                            if (_s(fin['label']).isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('${_s(fin['stars'])}  ${_s(fin['label'])}'.trim(), style: c.text(14, weight: FontWeight.w700, color: c.muted)),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: score == null ? 0 : score / 100,
                                strokeWidth: 6,
                                color: c.ink,
                                backgroundColor: c.line,
                                strokeCap: StrokeCap.round,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(score == null ? '—' : '$score', style: c.text(22, weight: FontWeight.w800)),
                                if (_s(hiring['score_label']).isNotEmpty)
                                  Text(_s(hiring['score_label']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(8.5, weight: FontWeight.w700, color: c.muted)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (r['report_url'] != null)
                    c.primaryButton('PDF raporu aç', busy: false, onPressed: () => onOpen(r['report_url'] as String?)),
                  for (final p in _strs(fin['summary'])) Padding(padding: const EdgeInsets.only(top: 14), child: Text(p, style: c.text(14.5, height: 1.55))),
                  if (((hiring['criteria'] as List?) ?? const []).isNotEmpty)
                    section('İşe uygunluk', [
                      for (final k in (hiring['criteria'] as List).whereType<Map>())
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(_s(k['name']), style: c.text(13, weight: FontWeight.w600))),
                                  Text('%${_i(k['match_percent'])}', style: c.text(13, weight: FontWeight.w800)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(value: _i(k['match_percent']) / 100, minHeight: 5, color: c.ink, backgroundColor: c.line),
                              ),
                            ],
                          ),
                        ),
                    ]),
                  if (_strs(a['general_evaluation']).isNotEmpty)
                    section('Genel değerlendirme', [for (final p in _strs(a['general_evaluation'])) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(p, style: c.text(14, height: 1.55)))]),
                  if (swot.isNotEmpty)
                    section('SWOT', [
                      for (final (key, label) in const [('strengths', 'Güçlü yönler'), ('weaknesses', 'Zayıf yönler'), ('opportunities', 'Fırsatlar'), ('threats', 'Tehditler')])
                        if (_strs(swot[key]).isNotEmpty)
                          box(Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(trUpper(label), style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                              const SizedBox(height: 8),
                              bullets(_strs(swot[key])),
                            ],
                          )),
                    ]),
                  if (((gap['rows'] as List?) ?? const []).isNotEmpty)
                    section('Beklenti karşılama${_s(gap['overall_gap_level']).isEmpty ? '' : ' · açık seviyesi ${_s(gap['overall_gap_level'])}'}', [
                      for (final g in (gap['rows'] as List).whereType<Map>())
                        box(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(_s(g['expectation']), style: c.text(13.5, weight: FontWeight.w700, height: 1.35))),
                                const SizedBox(width: 8),
                                _Tag(text: _s(g['gap']), strong: _s(g['gap']) == 'Karşılıyor'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(_s(g['candidate_status']), style: c.text(13, color: c.muted, height: 1.45)),
                          ],
                        )),
                    ]),
                  if (((a['competency'] as List?) ?? const []).isNotEmpty)
                    section('Yetkinlikler', [
                      for (final k in (a['competency'] as List).whereType<Map>())
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(_s(k['name']), style: c.text(13.5))),
                              Text(_s(k['level']), style: c.text(14, color: c.ink)),
                            ],
                          ),
                        ),
                    ]),
                  if (((a['risk_analysis'] as List?) ?? const []).isNotEmpty)
                    section('Riskler', [
                      for (final k in (a['risk_analysis'] as List).whereType<Map>())
                        box(Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(_s(k['area']), style: c.text(13.5, weight: FontWeight.w700))),
                                _Tag(text: _s(k['level'])),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(_s(k['assessment']), style: c.text(13, color: c.muted, height: 1.45)),
                          ],
                        )),
                    ]),
                  if (_strs(a['interview_focus']).isNotEmpty) section('Mülakatta sorulacaklar', [bullets(_strs(a['interview_focus']))]),
                  if (r['cv_url'] != null) ...[
                    const SizedBox(height: 22),
                    OutlinedButton.icon(
                      onPressed: () => onOpen(r['cv_url'] as String?),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.ink,
                        side: BorderSide(color: c.line),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: Text('Adayın CV’si', style: c.text(14, weight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? c.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: strong ? c.ink : c.line),
      ),
      child: Text(text, style: c.text(10.5, weight: FontWeight.w700, color: strong ? c.bg : c.muted)),
    );
  }
}
