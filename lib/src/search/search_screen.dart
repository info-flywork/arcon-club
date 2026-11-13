import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

class SearchHit {
  SearchHit.fromJson(Map<String, dynamic> j)
    : cat = '${j['cat'] ?? ''}',
      title = '${j['title'] ?? ''}',
      blurb = '${j['blurb'] ?? ''}',
      tags = ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
      path = '${j['path'] ?? ''}';

  final String cat;
  final String title;
  final String blurb;
  final List<String> tags;

  /// Uygulama içi göreli yol (MAG / People yerli ekranla açılır).
  final String path;
}

/// ARCON SEARCH — webdeki arcon-search ile aynı motor: Mag, Academy, kişiler, modüller, IDEA…
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.session, required this.config, required this.onOpenPath});

  final SessionController session;
  final ArconAppConfig config;

  /// Sonuca dokununca (yerli ekran varsa o, yoksa WebView). Ana kabuk sağlar.
  final void Function(BuildContext context, String path, String title) onOpenPath;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _recentKey = 'arcon-search-recent';
  final _q = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _cat = 'all';
  List<({String key, String label})> _cats = const [
    (key: 'all', label: 'Tümü'),
    (key: 'magazine', label: 'Mag'),
    (key: 'people', label: 'Kişiler'),
    (key: 'modules', label: 'Modüller'),
    (key: 'events', label: 'Etkinlikler'),
    (key: 'topics', label: 'Konular'),
  ];
  List<SearchHit>? _hits;
  bool _loading = false;
  String? _error;
  List<String> _recent = const [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _recent = p.getStringList(_recentKey) ?? const []);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _hits = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(v.trim()));
  }

  Future<void> _run(String q, {bool remember = false}) async {
    if (q.isEmpty) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (remember) _remember(q);
    try {
      final j = await widget.session.api.searchJson(q, cat: _cat);
      if (!mounted || seq != _seq) return; // eski arama sonucu gelirse at
      setState(() {
        _hits = [for (final r in ((j['results'] as List?) ?? const []).whereType<Map>()) SearchHit.fromJson(r.cast<String, dynamic>())];
        final cats = ((j['categories'] as List?) ?? const []).whereType<Map>().toList();
        if (cats.isNotEmpty) _cats = [for (final c in cats) (key: '${c['key']}', label: '${c['label']}')];
      });
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted || seq != _seq) return;
      if (_hits == null && serverLacksApi(e)) {
        openWebFallback(
          context,
          session: widget.session,
          config: widget.config,
          title: 'ARCON SEARCH',
          path: 'arcon-search-demo?q=${Uri.encodeQueryComponent(q)}',
        );
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _remember(String q) async {
    final next = [q, ..._recent.where((r) => r.toLowerCase() != q.toLowerCase())].take(8).toList();
    setState(() => _recent = next);
    try {
      (await SharedPreferences.getInstance()).setStringList(_recentKey, next);
    } catch (_) {}
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = const []);
    try {
      (await SharedPreferences.getInstance()).remove(_recentKey);
    } catch (_) {}
  }

  void _pick(String q) {
    _q.text = q;
    _q.selection = TextSelection.collapsed(offset: q.length);
    _run(q, remember: true);
  }

  void _open(SearchHit h) {
    _remember(_q.text.trim());
    widget.onOpenPath(context, h.path, h.title);
  }

  static IconData _icon(String cat) => switch (cat) {
    'magazine' => Icons.newspaper_outlined,
    'people' => Icons.person_outline_rounded,
    'modules' => Icons.widgets_outlined,
    'events' => Icons.event_outlined,
    'topics' => Icons.tag_rounded,
    'locations' => Icons.place_outlined,
    _ => Icons.search_rounded,
  };

  String _catLabel(String key) => _cats.where((c) => c.key == key).firstOrNull?.label ?? key;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final q = _q.text.trim();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Geri',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _q,
                        focusNode: _focus,
                        autofocus: true,
                        onChanged: _onChanged,
                        onSubmitted: (v) => _run(v.trim(), remember: true),
                        textInputAction: TextInputAction.search,
                        style: c.text(15, weight: FontWeight.w500),
                        cursorColor: c.ink,
                        keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                        decoration: c.input(
                          'Mag, Academy, kişi, modül ara',
                          Icons.search_rounded,
                          suffix: AnimatedSwitcher(
                            duration: Motion.of(context, Motion.fast),
                            child: q.isEmpty
                                ? const SizedBox.shrink(key: ValueKey('e'))
                                : IconButton(
                                    key: const ValueKey('x'),
                                    icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                                    onPressed: () {
                                      _q.clear();
                                      setState(() => _hits = null);
                                      _focus.requestFocus();
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                  children: [
                    for (final cat in _cats) ...[
                      GestureDetector(
                        onTap: () {
                          setState(() => _cat = cat.key);
                          if (q.length >= 2) _run(q);
                        },
                        child: AnimatedContainer(
                          duration: Motion.of(context, Motion.fast),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _cat == cat.key ? c.ink : c.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _cat == cat.key ? c.ink : c.line),
                          ),
                          child: Text(
                            trUpper(cat.label),
                            style: c.text(11, weight: FontWeight.w700, color: _cat == cat.key ? c.bg : c.ink, spacing: 0.4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.line),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.normal),
                  child: KeyedSubtree(key: ValueKey('${_hits == null}-$_loading-${_hits?.length}'), child: _body(c, q, pad.bottom)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ArconMono c, String q, double bottom) {
    if (_loading && (_hits == null || _hits!.isEmpty)) {
      return const SkeletonList(count: 7, leadingSize: 40);
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: c.text(14, color: c.muted)),
      );
    }
    final hits = _hits;
    if (hits == null) {
      // boş durum: son aramalar + öneriler
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + bottom),
        children: [
          if (_recent.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'SON ARAMALAR',
                  style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _clearRecent,
                  child: Text(
                    'Temizle',
                    style: c.text(12, weight: FontWeight.w600, color: c.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final r in _recent)
              InkWell(
                onTap: () => _pick(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 19, color: c.faint),
                      const SizedBox(width: 12),
                      Expanded(child: Text(r, style: c.text(14.5))),
                      Icon(Icons.north_west_rounded, size: 16, color: c.faint),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 22),
          ],
          Text(
            'ÖNERİLER',
            style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in const ['Kaydettiklerim', 'Takvim', 'Akademi', 'ÜTS', 'Packing', 'Dior', 'Kutlamalar'])
                GestureDetector(
                  onTap: () => _pick(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.field,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line),
                    ),
                    child: Text(s, style: c.text(13, weight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ],
      );
    }
    if (hits.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 90),
          Icon(Icons.search_off_rounded, size: 36, color: c.faint),
          const SizedBox(height: 8),
          Text(
            '"$q" için sonuç yok',
            textAlign: TextAlign.center,
            style: c.text(14, color: c.muted),
          ),
        ],
      );
    }
    // kategoriye göre grupla (sıra korunur: en iyi eşleşme önce)
    final groups = <String, List<SearchHit>>{};
    for (final h in hits) {
      groups.putIfAbsent(h.cat, () => []).add(h);
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottom),
      children: [
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(
              '${trUpper(_catLabel(g.key))}  ${g.value.length}',
              style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4),
            ),
          ),
          for (final h in g.value)
            InkWell(
              onTap: () => _open(h),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(12)),
                      child: Icon(_icon(h.cat), size: 20, color: c.bg),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: c.text(14.5, weight: FontWeight.w700, height: 1.3),
                          ),
                          if (h.blurb.isNotEmpty)
                            Text(
                              h.blurb,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: c.text(12.5, color: c.muted),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.faint),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
