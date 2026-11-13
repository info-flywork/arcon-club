import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
List<String> _strs(Object? v) => ((v as List?) ?? const []).map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();

/* ============================== Modeller ============================== */

class AkProgress {
  AkProgress.fromJson(Map<String, dynamic>? j)
      : seen = j?['seen'] == true,
        completed = j?['completed'] == true,
        outdated = j?['outdated'] == true,
        watched = _i(j?['watched']),
        duration = _i(j?['duration']);

  final bool seen;
  final bool completed;

  /// Tamamlanmıştı ama içerik güncellendi; yeniden tamamlanmalı.
  final bool outdated;
  final int watched;
  final int duration;

  double get ratio => completed ? 1 : (duration > 0 ? (watched / duration).clamp(0.0, 1.0) : (seen ? 0.1 : 0));
}

class AkModule {
  AkModule.fromJson(Map<String, dynamic> j)
      : slug = '${j['slug'] ?? ''}',
        name = '${j['name'] ?? ''}',
        tagline = '${j['tagline'] ?? ''}',
        category = '${j['category'] ?? ''}',
        categoryLabel = '${j['category_label'] ?? ''}',
        hasVideo = j['has_video'] == true,
        hasQuiz = j['has_quiz'] == true,
        required = j['required'] == true,
        minutes = _i(j['minutes']),
        coverUrl = j['cover_url'] as String?,
        iconUrl = j['icon_url'] as String?,
        progress = AkProgress.fromJson((j['progress'] as Map?)?.cast<String, dynamic>());

  final String slug;
  final String name;
  final String tagline;
  final String category;
  final String categoryLabel;
  final bool hasVideo;
  final bool hasQuiz;
  final bool required;
  final int minutes;
  final String? coverUrl;
  final String? iconUrl;
  final AkProgress progress;
}

class AkModuleDetail {
  AkModuleDetail.fromJson(Map<String, dynamic> j)
      : module = AkModule.fromJson(j),
        purpose = '${j['purpose'] ?? ''}',
        when = _strs(j['when']),
        steps = _strs(j['steps']),
        tips = _strs(j['tips']),
        videoUrl = j['video_url'] as String?,
        quiz = [
          for (final q in ((j['quiz'] as List?) ?? const []).whereType<Map>()) (q: '${q['q']}', options: _strs(q['options'])),
        ],
        note = (j['note'] as Map?)?.cast<String, dynamic>(),
        communityTips = [
          for (final t in ((j['community_tips'] as List?) ?? const []).whereType<Map>()) (body: '${t['body']}', by: '${t['by'] ?? ''}'),
        ],
        assignment = (j['assignment'] as Map?)?.cast<String, dynamic>(),
        modulePath = '${j['module_path'] ?? ''}',
        webPath = '${j['web_path'] ?? ''}';

  final AkModule module;
  final String purpose;
  final List<String> when;
  final List<String> steps;
  final List<String> tips;
  final String? videoUrl;
  final List<({String q, List<String> options})> quiz;
  final Map<String, dynamic>? note;
  final List<({String body, String by})> communityTips;
  final Map<String, dynamic>? assignment;
  final String modulePath;
  final String webPath;
}

IconData _catIcon(String cat) => switch (cat) {
      'brand' => Icons.sell_outlined,
      'welcome' => Icons.waving_hand_outlined,
      _ => Icons.auto_awesome_outlined,
    };

/* ============================== Ana ekran ============================== */

/// ARCON ACADEMY — webdeki ai-akademi.php: katalog, ilerleme ve sıralama.
class AkademiHomeScreen extends StatefulWidget {
  const AkademiHomeScreen({super.key, required this.session, required this.config, required this.onOpenPath, this.initialTab = 0});

  final SessionController session;
  final ArconAppConfig config;

  /// "Modüle git" gibi uygulama içi yollar (ana kabuk sağlar).
  final void Function(BuildContext context, String path, String title) onOpenPath;

  /// 0 Katalog · 1 İlerleme · 2 Sıralama (profildeki "İlerleme" / "Liderlik" satırları).
  final int initialTab;

  @override
  State<AkademiHomeScreen> createState() => _AkademiHomeScreenState();
}

class _AkademiHomeScreenState extends State<AkademiHomeScreen> {
  late int _tab = widget.initialTab;
  List<AkModule>? _modules;
  List<({String key, String label})> _cats = const [];
  String _cat = 'all';
  int _done = 0;
  int _total = 0;
  Map<String, dynamic> _streak = const {};
  Map<String, dynamic>? _tip;
  String? _error;

  Map<String, dynamic>? _board;

  @override
  void initState() {
    super.initState();
    _start();
    if (_tab == 2) _loadBoard(); // profilden "Liderlik" ile açıldı
  }

  Future<void> _start() async {
    final cached = await widget.session.api.cachedAkademiJson('catalog');
    if (cached != null && mounted) _apply(cached);
    await _load();
  }

  void _apply(Map<String, dynamic> j) {
    setState(() {
      _modules = [for (final m in ((j['modules'] as List?) ?? const []).whereType<Map>()) AkModule.fromJson(m.cast<String, dynamic>())];
      _cats = [for (final c in ((j['categories'] as List?) ?? const []).whereType<Map>()) (key: '${c['key']}', label: '${c['label']}')];
      _done = _i(j['done']);
      _total = _i(j['total']);
      _streak = ((j['streak'] as Map?) ?? const {}).cast<String, dynamic>();
      _tip = (j['tip'] as Map?)?.cast<String, dynamic>();
    });
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.akademiJson('catalog', force: force);
      if (mounted) _apply(j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_modules == null && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'ARCON ACADEMY', path: 'ai-akademi');
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _loadBoard({bool force = false}) async {
    if (_board == null) {
      final c = await widget.session.api.cachedAkademiJson('leaderboard');
      if (c != null && mounted) setState(() => _board = c);
    }
    try {
      final j = await widget.session.api.akademiJson('leaderboard', force: force);
      if (mounted) setState(() => _board = j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
    }
  }

  Future<void> _open(AkModule m) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AkademiModuleScreen(session: widget.session, config: widget.config, slug: m.slug, onOpenPath: widget.onOpenPath),
    ));
    _load(); // ilerleme değişmiş olabilir (önbellek işlemde silindi)
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final streakWeeks = _i(_streak['streak']);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Geri',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                    ),
                    Text.rich(
                      TextSpan(children: [const TextSpan(text: 'ARCON '), TextSpan(text: 'ACADEMY', style: TextStyle(color: c.ink))]),
                      style: c.text(19, weight: FontWeight.w800, spacing: 0.4),
                    ),
                    const Spacer(),
                    if (_modules != null)
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                        decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_fire_department_outlined, size: 16, color: c.ink),
                            const SizedBox(width: 4),
                            Text('$streakWeeks hafta', style: c.text(12, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _segments(c),
              Expanded(
                child: SwapFade(
                  alignment: Alignment.topCenter,
                  offset: 0.02,
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: switch (_tab) {
                      1 => _progressView(c),
                      2 => _boardView(c),
                      _ => _catalogView(c),
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segments(ArconMono c) {
    Widget seg(int i, String label) => Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _tab = i);
              if (i == 2) _loadBoard();
            },
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _tab == i ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: c.text(13, weight: FontWeight.w700, color: _tab == i ? c.bg : c.ink)),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.line)),
      child: Row(children: [seg(0, 'Katalog'), seg(1, 'İlerleme'), seg(2, 'Sıralama')]),
    );
  }

  Widget _hero(ArconMono c) {
    final pct = _total > 0 ? _done / _total : 0.0;
    final goal = _i(_streak['goal']);
    final weekDone = _i(_streak['done']);
    final met = _streak['met'] == true;
    final fg = c.dark ? c.ink : c.bg;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.dark ? c.field : c.ink,
        borderRadius: BorderRadius.circular(20),
        border: c.dark ? Border.all(color: c.line) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$_done / $_total eğitim', style: c.text(24, weight: FontWeight.w800, color: fg, spacing: -0.6)),
          const SizedBox(height: 2),
          Text('tamamlandı', style: c.text(13, color: fg.withValues(alpha: 0.65))),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: pct, minHeight: 8, color: fg, backgroundColor: fg.withValues(alpha: 0.18)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(met ? Icons.check_circle_outline_rounded : Icons.flag_outlined, size: 16, color: fg.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  met ? 'Bu haftanın hedefi tamam ($weekDone/$goal)' : 'Bu hafta $goal modül hedefi · $weekDone tamamlandı',
                  style: c.text(12.5, weight: FontWeight.w600, color: fg.withValues(alpha: 0.8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _catalogView(ArconMono c) {
    final mods = _modules;
    if (mods == null) {
      return _error != null
          ? Center(child: Text(_error!, style: c.text(14, color: c.muted)))
          : const SkeletonList(count: 6, leading: false, thumbnail: true);
    }
    final visible = mods.where((m) => _cat == 'all' || m.category == _cat).toList();
    final pad = MediaQuery.paddingOf(context);
    return RefreshIndicator(
      color: c.ink,
      backgroundColor: c.bg,
      onRefresh: () => _load(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(20, 6, 20, 24 + pad.bottom),
        children: [
          _hero(c),
          if (_tip != null && '${_tip!['body']}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined, size: 20, color: c.ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trUpper('Günün ipucu'), style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                        if ('${_tip!['title']}'.isNotEmpty) Text('${_tip!['title']}', style: c.text(14, weight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('${_tip!['body']}', style: c.text(13, color: c.muted, height: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final cat in _cats) ...[
                  GestureDetector(
                    onTap: () => setState(() => _cat = cat.key),
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.fast),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _cat == cat.key ? c.ink : c.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _cat == cat.key ? c.ink : c.line),
                      ),
                      child: Text(trUpper(cat.label), style: c.text(11, weight: FontWeight.w700, color: _cat == cat.key ? c.bg : c.ink, spacing: 0.4)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(child: Text('Bu kategoride eğitim yok', style: c.text(14, color: c.muted))),
            )
          else
            for (final m in visible) ...[const SizedBox(height: 10), _moduleCard(c, m)],
        ],
      ),
    );
  }

  Widget _chip(ArconMono c, String label, {IconData? icon, bool strong = false}) => Container(
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

  Widget _moduleCard(ArconMono c, AkModule m) {
    final p = m.progress;
    return PressScale(
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(m),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: m.coverUrl != null
                        ? CachedNetworkImage(memCacheWidth: 260, imageUrl: m.coverUrl!, fit: BoxFit.cover, errorWidget: (_, _, _) => _iconBox(c, m))
                        : _iconBox(c, m),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(trUpper(m.categoryLabel), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(9.5, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                          ),
                          if (p.completed)
                            Icon(Icons.check_circle_rounded, size: 18, color: c.ink)
                          else if (p.outdated)
                            Icon(Icons.update_rounded, size: 18, color: c.muted),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(15, weight: FontWeight.w800)),
                      if (m.tagline.isNotEmpty)
                        Text(m.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.muted, height: 1.35)),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _chip(c, m.hasVideo ? 'Video' : 'Rehber', icon: m.hasVideo ? Icons.play_arrow_rounded : Icons.menu_book_outlined),
                          if (m.hasQuiz) _chip(c, 'Quiz', icon: Icons.quiz_outlined),
                          if (m.required) _chip(c, 'Zorunlu', strong: true),
                          _chip(c, '~${m.minutes} dk'),
                        ],
                      ),
                      if (!p.completed && p.ratio > 0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(value: p.ratio, minHeight: 4, color: c.ink, backgroundColor: c.line),
                        ),
                      ],
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

  Widget _iconBox(ArconMono c, AkModule m) => Container(
        color: c.ink,
        alignment: Alignment.center,
        child: m.iconUrl != null
            ? Padding(padding: const EdgeInsets.all(16), child: CachedNetworkImage(memCacheWidth: 300, imageUrl: m.iconUrl!, errorWidget: (_, _, _) => Icon(_catIcon(m.category), color: c.bg)))
            : Icon(_catIcon(m.category), color: c.bg, size: 28),
      );

  Widget _progressView(ArconMono c) {
    final mods = _modules;
    if (mods == null) return const SkeletonList(count: 6, leading: false);
    final inProgress = mods.where((m) => !m.progress.completed && (m.progress.seen || m.progress.outdated)).toList();
    final done = mods.where((m) => m.progress.completed).toList();
    final todo = mods.where((m) => !m.progress.completed && !m.progress.seen && !m.progress.outdated).toList();
    final pad = MediaQuery.paddingOf(context);
    Widget section(String title, List<AkModule> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              Row(
                children: [
                  Text('${trUpper(title)}  ${list.length}', style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
                  const SizedBox(width: 10),
                  Expanded(child: Container(height: 1, color: c.line)),
                ],
              ),
              for (final m in list) ...[const SizedBox(height: 10), _moduleCard(c, m)],
            ],
          );
    return RefreshIndicator(
      color: c.ink,
      onRefresh: () => _load(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(20, 6, 20, 24 + pad.bottom),
        children: [
          _hero(c),
          section('Devam eden', inProgress),
          section('Tamamlanan', done),
          section('Başlanmamış', todo),
        ],
      ),
    );
  }

  Widget _boardView(ArconMono c) {
    final b = _board;
    if (b == null) return const SkeletonList(count: 8, leadingSize: 36);
    final rows = ((b['rows'] as List?) ?? const []).whereType<Map>().toList();
    final me = (b['me'] as Map?);
    final total = _i(b['total']);
    final pad = MediaQuery.paddingOf(context);
    Widget row(Map r, {bool highlight = false}) {
      final rank = _i(r['rank']);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: highlight ? c.ink : c.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: highlight ? c.ink : c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: highlight ? c.bg : (rank <= 3 ? c.ink : Colors.transparent),
                shape: BoxShape.circle,
                border: rank <= 3 || highlight ? null : Border.all(color: c.line),
              ),
              child: Text('$rank', style: c.text(13, weight: FontWeight.w800, color: highlight ? c.ink : (rank <= 3 ? c.bg : c.ink))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                r['is_me'] == true ? '${r['name']} (sen)' : '${r['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: c.text(14.5, weight: FontWeight.w700, color: highlight ? c.bg : c.ink),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${r['completed']}/$total', style: c.text(13.5, weight: FontWeight.w800, color: highlight ? c.bg : c.ink)),
                Text('quiz %${r['quiz_pct']}', style: c.text(11, color: highlight ? c.bg.withValues(alpha: 0.7) : c.muted)),
              ],
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: c.ink,
      onRefresh: () => _loadBoard(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(20, 6, 20, 24 + pad.bottom),
        children: [
          if (me != null) ...[
            Text(trUpper('Senin sıran'), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
            const SizedBox(height: 8),
            row(me, highlight: true),
            const SizedBox(height: 10),
          ],
          Text('${trUpper('Sıralama')}  ${_i(b['count'])} kişi', style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Center(child: Text('Henüz tamamlanan eğitim yok', style: c.text(14, color: c.muted))),
            )
          else
            for (final r in rows) row(r),
        ],
      ),
    );
  }
}

/* ============================== Modül detayı ============================== */

/// Tek eğitim — webdeki ai-akademi_detay.php: video, rehber, quiz, notlarım, pratik görev, tamamla.
class AkademiModuleScreen extends StatefulWidget {
  const AkademiModuleScreen({super.key, required this.session, required this.config, required this.slug, required this.onOpenPath});

  final SessionController session;
  final ArconAppConfig config;
  final String slug;
  final void Function(BuildContext context, String path, String title) onOpenPath;

  @override
  State<AkademiModuleScreen> createState() => _AkademiModuleScreenState();
}

class _AkademiModuleScreenState extends State<AkademiModuleScreen> {
  AkModuleDetail? _d;
  String? _error;
  VideoPlayerController? _video;
  bool _videoReady = false;
  int _lastSentWatched = 0;
  bool _completed = false;
  bool _busy = false;

  final _note = TextEditingController();
  bool _noteAsTip = false;
  bool _noteSaving = false;
  String? _noteStatus;
  final _task = TextEditingController();
  bool _taskSending = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sendWatched(); // çıkarken izlenen süre
    _video?.removeListener(_onVideo);
    _video?.dispose();
    _note.dispose();
    _task.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cached = await widget.session.api.cachedAkademiJson('module', slug: widget.slug);
    if (cached != null && mounted) _apply(cached);
    try {
      final j = await widget.session.api.akademiJson('module', slug: widget.slug);
      if (mounted) _apply(j);
      // açıldı = görüldü
      unawaited(widget.session.api.akademiAction('progress', widget.slug, {'seen': true}).catchError((_) => <String, dynamic>{}));
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_d == null && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'ARCON ACADEMY', path: 'ai-akademi_detay.php?m=${widget.slug}');
        return;
      }
      setState(() => _error = e.message);
    }
  }

  void _apply(Map<String, dynamic> j) {
    final d = AkModuleDetail.fromJson((j['module'] as Map).cast<String, dynamic>());
    final first = _d == null;
    setState(() {
      _d = d;
      _completed = d.module.progress.completed;
      if (first) {
        _note.text = '${d.note?['body'] ?? ''}';
        _noteAsTip = d.note?['as_tip'] == true;
        _noteStatus = d.note == null ? null : '${d.note?['status']}';
      }
    });
    if (first && d.videoUrl != null) _initVideo(d.videoUrl!);
  }

  Future<void> _initVideo(String url) async {
    final v = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = v;
    try {
      await v.initialize();
      v.addListener(_onVideo);
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {
      if (mounted) setState(() => _videoReady = false);
    }
  }

  void _onVideo() {
    final v = _video;
    if (v == null || !mounted) return;
    final pos = v.value.position.inSeconds;
    final dur = v.value.duration.inSeconds;
    // her 15 sn'de bir izlenen süre; video bitince (quiz yoksa) tamamlandı
    if (pos - _lastSentWatched >= 15) _sendWatched();
    if (dur > 0 && pos >= dur - 1 && !v.value.isPlaying && !_completed && !(_d?.module.hasQuiz ?? true)) {
      _setCompleted(true);
    }
    setState(() {});
  }

  void _sendWatched() {
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    final pos = v.value.position.inSeconds;
    if (pos <= _lastSentWatched) return;
    _lastSentWatched = pos;
    widget.session.api
        .akademiAction('progress', widget.slug, {'watched': pos, 'duration': v.value.duration.inSeconds})
        .catchError((_) => <String, dynamic>{});
  }

  Future<void> _setCompleted(bool v) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _completed = v;
    });
    try {
      await widget.session.api.akademiAction('progress', widget.slug, {'completed': v});
      if (v) HapticFeedback.mediumImpact();
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) {
        setState(() => _completed = !v);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveNote() async {
    if (_noteSaving || _note.text.trim().isEmpty) return;
    setState(() => _noteSaving = true);
    try {
      final r = await widget.session.api.akademiAction('note', widget.slug, {'body': _note.text.trim(), 'as_tip': _noteAsTip});
      if (mounted) {
        setState(() => _noteStatus = '${r['status']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_noteAsTip ? 'Notun kaydedildi, ipucu önerin onaya gönderildi' : 'Notun kaydedildi')),
        );
      }
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _noteSaving = false);
    }
  }

  Future<void> _sendTask() async {
    if (_taskSending) return;
    final t = _task.text.trim();
    if (t.length < 20) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Görevi biraz daha anlat (en az 20 karakter)')));
      return;
    }
    setState(() => _taskSending = true);
    try {
      await widget.session.api.akademiAction('assignment', widget.slug, {'body': t});
      final j = await widget.session.api.akademiJson('module', slug: widget.slug, force: true);
      if (mounted) {
        _task.clear();
        _apply(j);
      }
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _taskSending = false);
    }
  }

  Future<void> _startQuiz() async {
    final d = _d;
    if (d == null) return;
    final passed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _QuizScreen(session: widget.session, slug: widget.slug, title: d.module.name, quiz: d.quiz),
    ));
    if (passed == true && mounted) setState(() => _completed = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final d = _d;
    if (d == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            _error == null ? const SkeletonArticle() : Center(child: Text(_error!, style: c.text(14, color: c.muted))),
            SafeArea(
              child: IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
            ),
          ],
        ),
      );
    }
    final m = d.module;
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
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
                    Expanded(
                      child: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(17, weight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
                  children: [
                    if (d.videoUrl != null) _videoBox(c) else _noVideo(c, m),
                    const SizedBox(height: 18),
                    Text(trUpper(m.categoryLabel), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4)),
                    const SizedBox(height: 6),
                    Text(m.name, style: c.text(26, weight: FontWeight.w800, height: 1.15, spacing: -0.7)),
                    if (m.tagline.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(m.tagline, style: c.text(14.5, color: c.muted, height: 1.5)),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _pill(c, Icons.schedule_rounded, '~${m.minutes} dk'),
                        if (m.hasQuiz) _pill(c, Icons.quiz_outlined, '${d.quiz.length} soruluk quiz'),
                        if (m.required) _pill(c, Icons.priority_high_rounded, 'Zorunlu', strong: true),
                        if (_completed) _pill(c, Icons.check_rounded, 'Tamamlandı', strong: true),
                      ],
                    ),
                    if (d.when.isNotEmpty) _section(c, 'Öğrenecekleriniz', [for (final w in d.when) _bullet(c, w)]),
                    _section(c, 'Nasıl kullanılır?', [
                      for (var i = 0; i < d.steps.length; i++) _step(c, i + 1, d.steps[i]),
                      if (d.steps.isEmpty) Text('Modülü aç, rehberdeki adımları izle ve sonucu kaydet.', style: c.text(14.5, color: c.muted)),
                    ]),
                    if (d.purpose.isNotEmpty) _section(c, 'Açıklama', [Text(d.purpose, style: c.text(15, height: 1.6))]),
                    if (d.tips.isNotEmpty) _section(c, 'İpuçları', [for (final t in d.tips) _bullet(c, t, icon: Icons.lightbulb_outline_rounded)]),
                    if (m.hasQuiz && d.quiz.isNotEmpty) _quizCard(c, d),
                    _noteCard(c, d),
                    _taskCard(c, d),
                    const SizedBox(height: 22),
                    if (!m.hasQuiz)
                      c.primaryButton(
                        _completed ? 'Tamamlandı · geri al' : 'Tamamlandı olarak işaretle',
                        busy: _busy,
                        onPressed: () => _setCompleted(!_completed),
                      ),
                    if (d.modulePath.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => widget.onOpenPath(context, d.modulePath, m.name),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink,
                          side: BorderSide(color: c.line),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text('Modüle git', style: c.text(14.5, weight: FontWeight.w700)),
                      ),
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

  Widget _videoBox(ArconMono c) {
    final v = _video;
    final ready = _videoReady && v != null;
    final playing = ready && v.value.isPlaying;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: ready ? v.value.aspectRatio : 16 / 9,
        child: !ready
            ? const Shimmer(child: SkeletonBox(radius: 0))
            : Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.black, child: VideoPlayer(v)),
                  GestureDetector(
                    onTap: () => playing ? v.pause() : v.play(),
                    child: AnimatedOpacity(
                      opacity: playing ? 0 : 1,
                      duration: Motion.of(context, Motion.fast),
                      child: Container(
                        color: Colors.black26,
                        alignment: Alignment.center,
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 14, 6, 4),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
                      ),
                      child: Row(
                        children: [
                          Text(_fmt(v.value.position), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()])),
                          const SizedBox(width: 8),
                          Expanded(
                            child: VideoProgressIndicator(
                              v,
                              allowScrubbing: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white38, backgroundColor: Colors.white12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(_fmt(v.value.duration), style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                          PopupMenuButton<double>(
                            tooltip: 'Hız',
                            icon: Text('${v.value.playbackSpeed}x', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                            onSelected: v.setPlaybackSpeed,
                            itemBuilder: (_) => [for (final s in const [0.75, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: s, child: Text('${s}x'))],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _noVideo(ArconMono c, AkModule m) => Container(
        height: 120,
        decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, color: c.muted),
            const SizedBox(width: 10),
            Text(m.hasVideo ? 'Video yakında' : 'Bu eğitim rehber olarak hazırlandı', style: c.text(13.5, color: c.muted)),
          ],
        ),
      );

  Widget _pill(ArconMono c, IconData icon, String label, {bool strong = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: strong ? c.ink : c.field,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: strong ? c.ink : c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: strong ? c.bg : c.ink),
            const SizedBox(width: 5),
            Text(label, style: c.text(12, weight: FontWeight.w600, color: strong ? c.bg : c.ink)),
          ],
        ),
      );

  Widget _section(ArconMono c, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: c.text(18, weight: FontWeight.w800, spacing: -0.3)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );

  Widget _bullet(ArconMono c, String t, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: icon == null ? 8 : 2, right: 10),
              child: icon == null
                  ? Container(width: 5, height: 5, decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle))
                  : Icon(icon, size: 17, color: c.muted),
            ),
            Expanded(child: Text(t, style: c.text(14.5, height: 1.55))),
          ],
        ),
      );

  Widget _step(ArconMono c, int n, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
              child: Text('$n', style: c.text(12, weight: FontWeight.w800, color: c.bg)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(t, style: c.text(14.5, height: 1.5)))),
          ],
        ),
      );

  Widget _card(ArconMono c, {required IconData icon, required String title, String? sub, required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(top: 22),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: c.ink),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: c.text(15.5, weight: FontWeight.w800))),
              ],
            ),
            if (sub != null) ...[const SizedBox(height: 4), Text(sub, style: c.text(12.5, color: c.muted, height: 1.4))],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _quizCard(ArconMono c, AkModuleDetail d) => _card(
        c,
        icon: Icons.quiz_outlined,
        title: 'Quiz',
        sub: _completed
            ? 'Quizi geçtin; istersen tekrar çözebilirsin.'
            : '${d.quiz.length} soru · geçmek için en az ${(d.quiz.length * 0.6).ceil()} doğru. Geçince eğitim tamamlanır.',
        children: [c.primaryButton(_completed ? 'Tekrar çöz' : 'Quize başla', busy: false, onPressed: _startQuiz)],
      );

  Widget _noteCard(ArconMono c, AkModuleDetail d) => _card(
        c,
        icon: Icons.sticky_note_2_outlined,
        title: 'Notlarım',
        sub: _noteStatus == 'pending'
            ? 'İpucu önerin onay bekliyor.'
            : _noteStatus == 'approved'
                ? 'İpucun onaylandı ve herkese görünüyor.'
                : 'Yalnızca sen görürsün; istersen ipucu olarak öner.',
        children: [
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 8,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            style: c.text(14.5, height: 1.45),
            cursorColor: c.ink,
            decoration: c.input('Bu eğitimle ilgili notun…', null).copyWith(fillColor: c.bg),
          ),
          Row(
            children: [
              Switch.adaptive(value: _noteAsTip, activeTrackColor: c.ink, onChanged: (v) => setState(() => _noteAsTip = v)),
              const SizedBox(width: 6),
              Expanded(child: Text('İpucu olarak öner (onaydan sonra herkes görür)', style: c.text(12.5, color: c.muted))),
            ],
          ),
          const SizedBox(height: 6),
          c.primaryButton('Notu kaydet', busy: _noteSaving, onPressed: _saveNote),
          if (d.communityTips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(trUpper('Topluluk ipuçları'), style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
            for (final t in d.communityTips)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.body, style: c.text(13.5, height: 1.45)),
                      if (t.by.isNotEmpty) ...[const SizedBox(height: 4), Text('— ${t.by}', style: c.text(11.5, color: c.faint))],
                    ],
                  ),
                ),
              ),
          ],
        ],
      );

  Widget _taskCard(ArconMono c, AkModuleDetail d) {
    final a = d.assignment;
    final status = '${a?['status'] ?? ''}';
    final label = switch (status) {
      'approved' => 'Onaylandı',
      'rejected' => 'Tekrar dene',
      'pending' => 'İncelemede',
      _ => '',
    };
    return _card(
      c,
      icon: Icons.assignment_outlined,
      title: 'Pratik görev',
      sub: 'Öğrendiğini gerçek bir işte dene ve ne yaptığını kısaca anlat. Onaylanan görev sertifika seviyeni yükseltir.',
      children: [
        if (a != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(trUpper('Son gönderim'), style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                    const Spacer(),
                    if (label.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'approved' ? c.ink : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: status == 'approved' ? c.ink : c.line),
                        ),
                        child: Text(trUpper(label), style: c.text(9.5, weight: FontWeight.w700, color: status == 'approved' ? c.bg : c.muted)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${a['body']}', maxLines: 5, overflow: TextOverflow.ellipsis, style: c.text(13.5, height: 1.45)),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (status != 'pending' && status != 'approved') ...[
          TextField(
            controller: _task,
            minLines: 3,
            maxLines: 8,
            maxLength: 3000,
            textCapitalization: TextCapitalization.sentences,
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            style: c.text(14.5, height: 1.45),
            cursorColor: c.ink,
            decoration: c.input('Ne yaptın, sonuç ne oldu? (en az 20 karakter)', null).copyWith(fillColor: c.bg),
          ),
          const SizedBox(height: 6),
          c.primaryButton('Görevi gönder', busy: _taskSending, onPressed: _sendTask),
        ],
      ],
    );
  }
}

/* ============================== Quiz ============================== */

class _QuizScreen extends StatefulWidget {
  const _QuizScreen({required this.session, required this.slug, required this.title, required this.quiz});

  final SessionController session;
  final String slug;
  final String title;
  final List<({String q, List<String> options})> quiz;

  @override
  State<_QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<_QuizScreen> {
  late final List<int?> _answers = List<int?>.filled(widget.quiz.length, null);
  int _index = 0;
  bool _sending = false;
  Map<String, dynamic>? _result;

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      final r = await widget.session.api.akademiAction('quiz', widget.slug, {'answers': _answers});
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _result = r);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(_result?['passed'] == true),
                    icon: Icon(Icons.close_rounded, color: c.ink),
                  ),
                  Expanded(child: Text('${widget.title} · Quiz', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(16, weight: FontWeight.w800))),
                  if (_result == null) Text('${_index + 1}/${widget.quiz.length}', style: c.text(13, weight: FontWeight.w700, color: c.muted)),
                ],
              ),
            ),
            if (_result == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (_index + 1) / widget.quiz.length),
                    duration: Motion.of(context, Motion.normal),
                    builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 5, color: c.ink, backgroundColor: c.line),
                  ),
                ),
              ),
            Expanded(
              child: SwapFade(
                alignment: Alignment.topCenter,
                offset: 0.03,
                child: KeyedSubtree(
                  key: ValueKey(_result == null ? _index : -1),
                  child: _result == null ? _question(c) : _resultView(c),
                ),
              ),
            ),
            if (_result == null)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + pad.bottom * 0),
                child: Row(
                  children: [
                    if (_index > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: OutlinedButton(
                          onPressed: () => setState(() => _index--),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.ink,
                            side: BorderSide(color: c.line),
                            minimumSize: const Size(54, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    Expanded(
                      child: Opacity(
                        opacity: _answers[_index] == null ? 0.4 : 1,
                        child: c.primaryButton(
                          _index == widget.quiz.length - 1 ? 'Gönder' : 'Sonraki',
                          busy: _sending,
                          onPressed: () {
                            if (_answers[_index] == null) return;
                            if (_index < widget.quiz.length - 1) {
                              setState(() => _index++);
                            } else {
                              _submit();
                            }
                          },
                        ),
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

  Widget _question(ArconMono c) {
    final q = widget.quiz[_index];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      children: [
        Text(q.q, style: c.text(21, weight: FontWeight.w800, height: 1.3, spacing: -0.4)),
        const SizedBox(height: 20),
        for (var i = 0; i < q.options.length; i++) ...[
          GestureDetector(
            onTap: () => setState(() => _answers[_index] = i),
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _answers[_index] == i ? c.ink : c.field,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _answers[_index] == i ? c.ink : c.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _answers[_index] == i ? c.bg : c.line, width: 1.5),
                    ),
                    child: Text(String.fromCharCode(65 + i), style: c.text(12, weight: FontWeight.w800, color: _answers[_index] == i ? c.bg : c.muted)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(q.options[i], style: c.text(14.5, weight: FontWeight.w600, color: _answers[_index] == i ? c.bg : c.ink, height: 1.4))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _resultView(ArconMono c) {
    final r = _result!;
    final passed = r['passed'] == true;
    final results = ((r['results'] as List?) ?? const []).whereType<Map>().toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: passed ? c.ink : c.field, borderRadius: BorderRadius.circular(18), border: passed ? null : Border.all(color: c.line)),
            child: Icon(passed ? Icons.emoji_events_outlined : Icons.refresh_rounded, size: 32, color: passed ? c.bg : c.ink),
          ),
        ),
        const SizedBox(height: 18),
        Text(passed ? 'Tebrikler, geçtin!' : 'Az kaldı', style: c.text(28, weight: FontWeight.w800, spacing: -0.8)),
        const SizedBox(height: 6),
        Text(
          '${r['correct']} / ${r['total']} doğru · geçme sınırı ${r['pass']}.${passed ? ' Eğitim tamamlandı olarak işaretlendi.' : ' Tekrar deneyebilirsin.'}',
          style: c.text(14.5, color: c.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        for (var i = 0; i < results.length && i < widget.quiz.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(results[i]['correct'] == true ? Icons.check_circle_rounded : Icons.cancel_outlined, size: 20, color: results[i]['correct'] == true ? c.ink : c.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(widget.quiz[i].q, style: c.text(14, weight: FontWeight.w700, height: 1.35))),
                  ],
                ),
                if (results[i]['correct'] != true) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Doğru cevap: ${widget.quiz[i].options.elementAtOrNull(_i(results[i]['correct_index'])) ?? '-'}',
                    style: c.text(13, weight: FontWeight.w600),
                  ),
                  if ('${results[i]['explanation'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('${results[i]['explanation']}', style: c.text(12.5, color: c.muted, height: 1.45)),
                  ],
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        c.primaryButton(passed ? 'Eğitime dön' : 'Tekrar dene', busy: false, onPressed: () {
          if (passed) {
            Navigator.of(context).pop(true);
          } else {
            setState(() {
              _result = null;
              _index = 0;
              _answers.fillRange(0, _answers.length, null);
            });
          }
        }),
      ],
    );
  }
}
