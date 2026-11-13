import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// ARCON SCORE — AI-Durum Anketi (webdeki arcon-skor.php): gruplar → gruptaki soruları 1–5 yıldızla puanla.
class SkorHomeScreen extends StatefulWidget {
  const SkorHomeScreen({super.key, required this.session, required this.config});

  final SessionController session;
  final ArconAppConfig config;

  @override
  State<SkorHomeScreen> createState() => _SkorHomeScreenState();
}

class _SkorHomeScreenState extends State<SkorHomeScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final c = await widget.session.api.cachedSkor();
    if (c != null && mounted) setState(() => _data = c);
    await _load();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.skor(force: force);
      if (mounted) setState(() => _data = j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_data == null && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'ARCON SCORE', path: 'arcon-skor', replace: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _openGroup(Map<String, dynamic> g) async {
    final round = (_data?['round'] as Map?)?['id'];
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _SkorGroupScreen(session: widget.session, round: _i(round), group: g),
    ));
    if (saved == true) {
      await _load(force: true);
      if (!mounted) return;
      final d = _data;
      final done = d != null && _i(d['total']) > 0 && _i(d['answered']) >= _i(d['total']);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done ? 'Teşekkürler, tüm başlıkları puanladın.' : 'Grup kaydedildi; diğer gruplara devam edebilirsin.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final d = _data;
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
                    Text('ARCON SCORE', style: c.text(19, weight: FontWeight.w800, spacing: 0.4)),
                  ],
                ),
              ),
              Expanded(
                child: SkeletonSwitcher(
                  loading: d == null && _error == null,
                  skeleton: const SkeletonList(count: 5, leading: false, thumbnail: true),
                  child: d == null
                      ? Center(child: Text(_error ?? '', style: c.text(14, color: c.muted)))
                      : RefreshIndicator(
                          color: c.ink,
                          onRefresh: () => _load(force: true),
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                            padding: EdgeInsets.fromLTRB(20, 6, 20, 24 + pad.bottom),
                            children: d['round'] == null ? _empty(c, d) : _hub(c, d),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _empty(ArconMono c, Map<String, dynamic> d) => [
        const SizedBox(height: 70),
        Icon(Icons.star_outline_rounded, size: 46, color: c.faint),
        const SizedBox(height: 12),
        Center(child: Text('Şu an açık bir anket yok', style: c.text(16, weight: FontWeight.w700))),
        const SizedBox(height: 4),
        Center(child: Text('Yeni dönem başladığında burada görünür.', style: c.text(13, color: c.muted))),
        ..._history(c, d),
      ];

  List<Widget> _hub(ArconMono c, Map<String, dynamic> d) {
    final round = (d['round'] as Map).cast<String, dynamic>();
    final answered = _i(d['answered']);
    final total = _i(d['total']);
    final groups = ((d['groups'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final fg = c.dark ? c.ink : c.bg;
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.dark ? c.field : c.ink,
          borderRadius: BorderRadius.circular(20),
          border: c.dark ? Border.all(color: c.line) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trUpper('AI-Durum Anketi'), style: c.text(10.5, weight: FontWeight.w700, color: fg.withValues(alpha: 0.6), spacing: 1.2)),
            const SizedBox(height: 4),
            Text('${round['period_label']}', style: c.text(24, weight: FontWeight.w800, color: fg, spacing: -0.6)),
            const SizedBox(height: 6),
            Text(
              'Bir gruba gir, gruptaki tüm soruları 1–5 arası puanla. $answered/$total tamamlandı.',
              style: c.text(13, color: fg.withValues(alpha: 0.75), height: 1.45),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: total > 0 ? answered / total : 0),
                duration: Motion.of(context, Motion.normal),
                builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 8, color: fg, backgroundColor: fg.withValues(alpha: 0.18)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (groups.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 30),
          child: Center(child: Text('Bu dönemde henüz soru yok', style: c.text(14, color: c.muted))),
        )
      else
        for (final g in groups) ...[_groupTile(c, g), const SizedBox(height: 10)],
      ..._history(c, d),
      const SizedBox(height: 16),
      Text('Daha iyi bir AI deneyimi için geri bildirimin çok değerli.', textAlign: TextAlign.center, style: c.text(12.5, color: c.faint)),
    ];
  }

  Widget _groupTile(ArconMono c, Map<String, dynamic> g) {
    final total = _i(g['total']);
    final done = _i(g['answered']);
    final complete = total > 0 && done >= total;
    return PressScale(
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openGroup(g),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: complete ? c.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: complete ? null : Border.all(color: c.line),
                  ),
                  child: Icon(complete ? Icons.check_rounded : Icons.star_outline_rounded, color: complete ? c.bg : c.ink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trUpper('Grup'), style: c.text(9.5, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                      const SizedBox(height: 2),
                      Text('${g['label']}', style: c.text(15.5, weight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(value: total > 0 ? done / total : 0, minHeight: 4, color: c.ink, backgroundColor: c.line),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('$done/$total soru', style: c.text(12, weight: FontWeight.w600, color: c.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _history(ArconMono c, Map<String, dynamic> d) {
    final h = ((d['history'] as List?) ?? const []).whereType<Map>().toList();
    if (h.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      Row(
        children: [
          Text(trUpper('Geçmiş puanların'), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.2)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: c.line)),
        ],
      ),
      const SizedBox(height: 8),
      for (final r in h)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(child: Text('${r['period_label']}', style: c.text(14.5, weight: FontWeight.w600))),
              Text((r['avg'] as num? ?? 0).toStringAsFixed(2), style: c.text(15, weight: FontWeight.w800)),
              const SizedBox(width: 4),
              Icon(Icons.star_rounded, size: 18, color: c.ink),
            ],
          ),
        ),
    ];
  }
}

/* ============================== Grup formu ============================== */

class _SkorGroupScreen extends StatefulWidget {
  const _SkorGroupScreen({required this.session, required this.round, required this.group});

  final SessionController session;
  final int round;
  final Map<String, dynamic> group;

  @override
  State<_SkorGroupScreen> createState() => _SkorGroupScreenState();
}

class _SkorGroupScreenState extends State<_SkorGroupScreen> {
  late final List<Map<String, dynamic>> _qs =
      ((widget.group['questions'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  late final Map<int, int> _scores = {
    for (final q in _qs)
      if (q['score'] != null) _i(q['id']): _i(q['score']),
  };
  late final bool _wasComplete = _qs.isNotEmpty && _scores.length >= _qs.length;
  bool _saving = false;

  Future<void> _save() async {
    if (_scores.length < _qs.length) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_qs.length - _scores.length} soru puanlanmadı')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.session.api.skorSubmit(widget.round, '${widget.group['key']}', _scores);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final done = _scores.length;
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
                  Expanded(
                    child: Text('${widget.group['label']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(17, weight: FontWeight.w800)),
                  ),
                  Text('$done/${_qs.length}', style: c.text(13, weight: FontWeight.w700, color: c.muted)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: _qs.isEmpty ? 0 : done / _qs.length),
                  duration: Motion.of(context, Motion.normal),
                  builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 5, color: c.ink, backgroundColor: c.line),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                itemCount: _qs.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Text('1 = Çok düşük · 5 = Çok yüksek', style: c.text(12.5, color: c.muted));
                  }
                  return _question(c, i, _qs[i - 1]);
                },
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 10 + pad.bottom),
              decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
              child: Opacity(
                opacity: done < _qs.length ? 0.5 : 1,
                child: c.primaryButton(_wasComplete ? 'Güncelle' : 'Kaydet', busy: _saving, onPressed: _save),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _question(ArconMono c, int n, Map<String, dynamic> q) {
    final id = _i(q['id']);
    final score = _scores[id] ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: score > 0 ? c.ink.withValues(alpha: 0.35) : c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n.toString().padLeft(2, '0'), style: c.text(12, weight: FontWeight.w800, color: c.faint)),
              const SizedBox(width: 10),
              Expanded(child: Text('${q['body']}', style: c.text(14.5, weight: FontWeight.w600, height: 1.4))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var s = 1; s <= 5; s++)
                Semantics(
                  button: true,
                  selected: score == s,
                  label: '$s yıldız',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _scores[id] = s);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: AnimatedScale(
                        scale: score == s ? 1.15 : 1,
                        duration: Motion.of(context, Motion.fast),
                        child: Icon(
                          s <= score ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 38,
                          color: s <= score ? c.ink : c.faint,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Text('Çok düşük', style: c.text(11, color: c.faint)),
              const Spacer(),
              Text('Çok yüksek', style: c.text(11, color: c.faint)),
            ],
          ),
        ],
      ),
    );
  }
}
