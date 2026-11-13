import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/skeleton.dart';
import '../ai_tools/tool_common.dart' show toolShareBytes, toolToast;
import '../ui/module_webview.dart';
import 'mag_models.dart';

/// Sunucuda MAG ucu yoksa (eski sürüm) modül WebView'de açılır.
bool _serverLacksApi(ArconApiException e) => e.status == 404 || e.status >= 500 || e.code == 'bad_response';

void _openWeb(BuildContext context, SessionController s, ArconAppConfig c, ArconModule m, {bool replace = false}) {
  final route = MaterialPageRoute<void>(
    builder: (_) => ModuleScreen(module: m, session: s, config: c),
  );
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

String magDate(DateTime? d, {bool withYear = true}) {
  if (d == null) return '';
  const months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60 && diff.inMinutes >= 0) return diff.inMinutes <= 1 ? 'az önce' : '${diff.inMinutes} dk önce';
  if (diff.inHours < 24 && diff.inHours >= 0) return '${diff.inHours} sa önce';
  return withYear && d.year != DateTime.now().year ? '${d.day} ${months[d.month - 1]} ${d.year}' : '${d.day} ${months[d.month - 1]}';
}

/* ======================================================================
 * Akış
 * ====================================================================== */

/// ARCON MAG ana ekranı — webdeki arcon-mag.php: kategoriler, kapak hikayesi, haber akışı, arama.
class MagHomeScreen extends StatefulWidget {
  const MagHomeScreen({super.key, required this.session, required this.config, required this.module});

  final SessionController session;
  final ArconAppConfig config;
  final ArconModule module;

  @override
  State<MagHomeScreen> createState() => _MagHomeScreenState();
}

class _MagHomeScreenState extends State<MagHomeScreen> {
  MagFeed? _feed;
  String _cat = 'all';
  String? _tag;
  String _query = '';
  bool _searching = false;
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// [refresh]: aşağı çekerek yenileme — içerik yerinde kalır (iskelet gösterilmez).
  Future<void> _load({bool refresh = false}) async {
    // Bu kategori/arama için önbellekte akış varsa iskelet yerine onu hemen göster
    final cached = refresh ? null : await widget.session.api.cachedMagFeed(category: _cat, query: _query, tag: _tag);
    if (!mounted) return;
    setState(() {
      if (cached != null) _feed = cached;
      _loading = !refresh && cached == null;
      _error = null;
    });
    try {
      final f = await widget.session.api.magFeed(category: _cat, query: _query, tag: _tag, force: refresh);
      if (mounted) setState(() => _feed = f);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_feed == null && _serverLacksApi(e)) {
        _openWeb(context, widget.session, widget.config, widget.module, replace: true);
        return;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setCat(String c) {
    if (c == _cat && _tag == null) return;
    setState(() {
      _cat = c;
      _tag = null;
    });
    _load();
  }

  void _setTag(String? t) {
    setState(() {
      _tag = t;
      _cat = 'all';
    });
    _load();
  }

  Future<void> _open(MagPostSummary p) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MagPostScreen(session: widget.session, config: widget.config, slug: p.slug, module: widget.module),
      ),
    );
    // Okundu işaretini yerelde güncelle (yeniden yüklemeden)
    final f = _feed;
    if (f == null || !mounted) return;
    setState(() {
      _feed = MagFeed(
        category: f.category,
        categories: f.categories,
        cover: f.cover?.id == p.id ? f.cover!.markRead() : f.cover,
        posts: [for (final x in f.posts) x.id == p.id ? x.markRead() : x],
        tags: f.tags,
        unreadCount: (!p.read && f.unreadCount > 0) ? f.unreadCount - 1 : f.unreadCount,
        savedCount: f.savedCount,
        likedCount: f.likedCount,
      );
    });
  }

  void _openList(String view) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MagListScreen(session: widget.session, config: widget.config, view: view, module: widget.module),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final f = _feed;
    final posts = f?.posts ?? const <MagPostSummary>[];
    final cover = f?.cover;
    final rest = cover == null ? posts : posts.where((p) => p.id != cover.id).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Başlık ↔ arama çubuğu ve kategori şeridi yumuşak geçer
              AnimatedSize(
                duration: Motion.of(context, Motion.normal),
                curve: Curves.easeOutCubic,
                child: SwapFade(
                  child: KeyedSubtree(key: ValueKey(_searching), child: _topBar(c, f)),
                ),
              ),
              AnimatedSize(
                duration: Motion.of(context, Motion.normal),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _searching ? 0 : 1,
                  duration: Motion.of(context, Motion.fast),
                  child: _searching ? const SizedBox(width: double.infinity) : _categories(c, f),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: c.ink,
                  backgroundColor: c.bg,
                  onRefresh: () => _load(refresh: true),
                  // iskelet → içerik geçişi
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.normal),
                    child: CustomScrollView(
                      key: ValueKey(_loading),
                      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        if (_tag != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                              child: Row(
                                children: [
                                  Text('#$_tag', style: c.text(18, weight: FontWeight.w800)),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () => _setTag(null),
                                    style: TextButton.styleFrom(foregroundColor: c.muted),
                                    child: Text(
                                      'Temizle',
                                      style: c.text(13, weight: FontWeight.w600, color: c.muted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_loading)
                          const SliverToBoxAdapter(child: _MagFeedSkeleton())
                        else if (_error != null && f == null)
                          SliverFillRemaining(hasScrollBody: false, child: _errorView(c))
                        else ...[
                          if (cover != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                                child: PressScale(
                                  scale: 0.985,
                                  child: _MagCoverCard(post: cover, onTap: () => _open(cover)),
                                ),
                              ),
                            ),
                          if (rest.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Text(
                                  _query.isNotEmpty ? '"$_query" için sonuç yok' : 'Bu kategoride henüz haber yok',
                                  style: c.text(14, color: c.muted),
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                              sliver: SliverList.separated(
                                itemCount: rest.length,
                                separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: c.line),
                                itemBuilder: (context, i) => _MagRow(post: rest[i], onTap: () => _open(rest[i])),
                              ),
                            ),
                          if (!_searching && _tag == null && (f?.tags.isNotEmpty ?? false))
                            SliverToBoxAdapter(child: _tagsCloud(c, f!.tags)),
                          SliverToBoxAdapter(child: SizedBox(height: 28 + MediaQuery.paddingOf(context).bottom)),
                        ],
                      ],
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

  Widget _topBar(ArconMono c, MagFeed? f) {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: c.text(15, weight: FontWeight.w500),
                cursorColor: c.ink,
                keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                decoration: c.input('Haberlerde ara', Icons.search_rounded),
                onSubmitted: (v) {
                  _query = v.trim();
                  _load();
                },
              ),
            ),
            TextButton(
              onPressed: () {
                _search.clear();
                setState(() {
                  _searching = false;
                  _query = '';
                });
                _load();
              },
              style: TextButton.styleFrom(foregroundColor: c.ink),
              child: Text('Vazgeç', style: c.text(14, weight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Geri',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_rounded, color: c.ink),
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'ARCON '),
                TextSpan(
                  text: 'MAG',
                  style: TextStyle(color: c.ink),
                ),
              ],
            ),
            style: c.text(19, weight: FontWeight.w800, spacing: 0.4),
          ),
          if ((f?.unreadCount ?? 0) > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(999)),
              child: Text(
                '${f!.unreadCount} yeni',
                style: c.text(10.5, weight: FontWeight.w700, color: c.bg),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            tooltip: 'Ara',
            onPressed: () => setState(() => _searching = true),
            icon: Icon(Icons.search_rounded, color: c.ink),
          ),
          PopupMenuButton<String>(
            tooltip: 'Listelerim',
            icon: Icon(Icons.bookmarks_outlined, color: c.ink),
            color: c.bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.line),
            ),
            onSelected: _openList,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'saved',
                child: Text('Kaydettiklerim${(f?.savedCount ?? 0) > 0 ? '  (${f!.savedCount})' : ''}', style: c.text(14)),
              ),
              PopupMenuItem(
                value: 'liked',
                child: Text('Beğendiklerim${(f?.likedCount ?? 0) > 0 ? '  (${f!.likedCount})' : ''}', style: c.text(14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _categories(ArconMono c, MagFeed? f) {
    final cats = f?.categories ?? const <MagCategory>[];
    if (cats.isEmpty) return const SizedBox(height: 8);
    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final cat = cats[i];
          final sel = cat.key == _cat && _tag == null;
          return GestureDetector(
            onTap: () => _setCat(cat.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? c.ink : c.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? c.ink : c.line),
              ),
              child: Text(
                trUpper(cat.label),
                style: c.text(11, weight: FontWeight.w700, color: sel ? c.bg : c.ink, spacing: 0.4),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tagsCloud(ArconMono c, List<String> tags) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ETİKETLER',
          style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in tags)
              GestureDetector(
                onTap: () => _setTag(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.field,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.line),
                  ),
                  child: Text('#$t', style: c.text(12, weight: FontWeight.w600)),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _errorView(ArconMono c) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_off_rounded, size: 36, color: c.faint),
        const SizedBox(height: 10),
        Text(
          _error ?? '',
          textAlign: TextAlign.center,
          style: c.text(14, color: c.muted),
        ),
        const SizedBox(height: 16),
        SizedBox(width: 180, child: c.primaryButton('Tekrar dene', busy: false, onPressed: _load)),
        TextButton(
          onPressed: () => _openWeb(context, widget.session, widget.config, widget.module, replace: true),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: Text('Web görünümünde aç', style: c.text(13, color: c.muted)),
        ),
      ],
    ),
  );
}

/// Akış yüklenirken: kapak + haber satırları.
class _MagFeedSkeleton extends StatelessWidget {
  const _MagFeedSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Shimmer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 16 / 10, child: SkeletonBox(radius: 20)),
              SizedBox(height: 16),
              SkeletonBox(width: 90, height: 10),
              SizedBox(height: 12),
              SkeletonBox(width: double.infinity, height: 22),
              SizedBox(height: 8),
              FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 22)),
            ],
          ),
        ),
      ),
      const SkeletonList(count: 3, leading: false, thumbnail: true),
    ],
  );
}

/// Kapak görseli (yoksa kategori adıyla düz zemin).
class _MagImage extends StatelessWidget {
  const _MagImage({required this.post, this.radius = 16});
  final MagPostSummary post;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final ph = Container(
      color: c.field,
      alignment: Alignment.center,
      child: Text(
        trUpper(post.categoryLabel),
        style: c.text(10, weight: FontWeight.w700, color: c.faint, spacing: 1),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: post.coverUrl.isEmpty
          ? ph
          : CachedNetworkImage(memCacheWidth: 1080, 
              imageUrl: post.coverUrl,
              fit: BoxFit.cover,
              placeholder: (_, _) => const Shimmer(child: SkeletonBox(radius: 0)),
              errorWidget: (_, _, _) => ph,
            ),
    );
  }
}

class _MagMeta extends StatelessWidget {
  const _MagMeta({required this.post});
  final MagPostSummary post;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final parts = [magDate(post.publishedAt), '${post.readingMinutes} dk okuma'];
    return Text(parts.where((p) => p.isNotEmpty).join(' · '), style: c.text(11.5, color: c.muted));
  }
}

class _MagCoverCard extends StatelessWidget {
  const _MagCoverCard({required this.post, required this.onTap});
  final MagPostSummary post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: _MagImage(post: post, radius: 20),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                trUpper(post.categoryLabel),
                style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1.4),
              ),
              if (!post.read) ...[
                const SizedBox(width: 8),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(post.title, style: c.text(24, weight: FontWeight.w800, height: 1.18, spacing: -0.7)),
          if (post.excerpt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              post.excerpt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: c.text(14, color: c.muted, height: 1.5),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (post.author.isNotEmpty) ...[
                Text(post.author, style: c.text(11.5, weight: FontWeight.w700)),
                Text('  ·  ', style: c.text(11.5, color: c.faint)),
              ],
              Expanded(child: _MagMeta(post: post)),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _MagRow extends StatelessWidget {
  const _MagRow({required this.post, required this.onTap});
  final MagPostSummary post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trUpper(post.categoryLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1.2),
                        ),
                      ),
                      if (post.mandatory) ...[const SizedBox(width: 6), Icon(Icons.campaign_outlined, size: 14, color: c.ink)],
                      if (!post.read) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    post.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: c.text(15.5, weight: post.read ? FontWeight.w600 : FontWeight.w800, height: 1.3, spacing: -0.2),
                  ),
                  const SizedBox(height: 6),
                  _MagMeta(post: post),
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(width: 96, height: 76, child: _MagImage(post: post, radius: 12)),
          ],
        ),
      ),
    );
  }
}

/* ======================================================================
 * Detay
 * ====================================================================== */

/// Haber detayı — webdeki arcon-mag_detay.php: kapak, başlık, gövde, tepkiler, beğeni/kaydet, okudum onayı.
class MagPostScreen extends StatefulWidget {
  const MagPostScreen({super.key, required this.session, required this.config, required this.slug, required this.module});

  final SessionController session;
  final ArconAppConfig config;
  final String slug;
  final ArconModule module;

  @override
  State<MagPostScreen> createState() => _MagPostScreenState();
}

class _MagPostScreenState extends State<MagPostScreen> {
  MagPost? _post;
  String? _error;
  bool _ackBusy = false;

  /// Kapak görseli üst çubuğun arkasından çekilince (çubuk düz zemine döner) true.
  bool _collapsed = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final limit = 300 - kToolbarHeight - MediaQuery.paddingOf(context).top;
      final next = _scroll.offset > limit;
      if (next != _collapsed) setState(() => _collapsed = next);
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    // Daha önce açılmış haber önbellekten anında açılır
    if (_post == null) {
      final cached = await widget.session.api.cachedMagPost(widget.slug);
      if (cached != null && mounted) setState(() => _post = cached);
    }
    try {
      final p = await widget.session.api.magPost(widget.slug);
      if (mounted) setState(() => _post = p);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_serverLacksApi(e) && e.status != 404) {
        _openWeb(context, widget.session, widget.config, _webModule(), replace: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  ArconModule _webModule() {
    final path = _post?.webPath.isNotEmpty == true ? _post!.webPath : 'arcon-mag_detay.php?h=${Uri.encodeComponent(widget.slug)}';
    return ArconModule(
      key: 'path:$path',
      title: widget.module.title,
      group: 'main',
      icon: '',
      render: 'webview',
      path: path,
      url: Uri.parse(widget.config.apiBase).resolve(path).toString(),
    );
  }

  Future<void> _toggle(String action, {String? type}) async {
    final p = _post;
    if (p == null) return;
    HapticFeedback.selectionClick();
    // İyimser güncelleme, sunucu cevabıyla düzeltilir
    setState(() {
      if (action == 'like') {
        p.liked = !p.liked;
        p.likes += p.liked ? 1 : -1;
      } else if (action == 'save') {
        p.saved = !p.saved;
      } else if (action == 'react' && type != null) {
        final on = !p.myReactions.contains(type);
        if (on) {
          p.myReactions = {...p.myReactions, type};
        } else {
          p.myReactions = {...p.myReactions}..remove(type);
        }
        p.reactions = {...p.reactions, type: (p.reactions[type] ?? 0) + (on ? 1 : -1)};
      }
    });
    try {
      final r = await widget.session.api.magAction(action, p.summary.slug, type: type);
      if (!mounted) return;
      setState(() {
        if (action == 'like') {
          p.liked = r['liked'] == true;
          p.likes = (r['likes'] as num?)?.toInt() ?? p.likes;
        } else if (action == 'save') {
          p.saved = r['saved'] == true;
        } else if (action == 'react') {
          p.reactions = magCounts(r['reactions']);
          p.myReactions = ((r['my_reactions'] as List?) ?? const []).map((e) => '$e').toSet();
        }
      });
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        _load();
      }
    }
  }

  Future<void> _ack() async {
    final p = _post;
    if (p == null || p.acked || _ackBusy) return;
    setState(() => _ackBusy = true);
    try {
      final r = await widget.session.api.magAction('ack', p.summary.slug);
      if (mounted) {
        setState(() {
          p.acked = true;
          p.ackCount = (r['ack_count'] as num?)?.toInt() ?? p.ackCount + 1;
        });
      }
    } on ArconApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _ackBusy = false);
    }
  }

  void _share() {
    final p = _post;
    if (p == null) return;
    final url = Uri.parse(widget.config.apiBase).resolve(p.webPath).toString();
    SharePlus.instance.share(ShareParams(text: '${p.summary.title}\n$url'));
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final p = _post;
    final pad = MediaQuery.paddingOf(context);

    if (p == null && _error == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            const SkeletonArticle(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _circleButton(c, Icons.arrow_back_rounded, 'Geri', () => Navigator.of(context).maybePop(), false),
              ),
            ),
          ],
        ),
      );
    }
    if (p == null) {
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(backgroundColor: c.bg, foregroundColor: c.ink, elevation: 0),
        body: Center(
          child: _error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: c.text(14, color: c.muted),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(width: 180, child: c.primaryButton('Tekrar dene', busy: false, onPressed: _load)),
                    ],
                  ),
                ),
        ),
      );
    }

    final s = p.summary;
    final hasCover = s.coverUrl.isNotEmpty;
    // Görsel üstündeyken açık simgeler; çubuk düz zemine dönünce temaya göre
    final overImage = hasCover && !_collapsed;
    final overlay = overImage || c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: c.bg,
        body: CustomScrollView(
          controller: _scroll,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: hasCover ? 300 : 0,
              backgroundColor: c.bg,
              surfaceTintColor: Colors.transparent,
              foregroundColor: c.ink,
              systemOverlayStyle: overlay,
              leading: _circleButton(c, Icons.arrow_back_rounded, 'Geri', () => Navigator.of(context).maybePop(), overImage),
              actions: [
                _circleButton(
                  c,
                  p.saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  p.saved ? 'Kaydedildi' : 'Kaydet',
                  () => _toggle('save'),
                  overImage,
                ),
                const SizedBox(width: 6),
                _circleButton(c, Icons.ios_share_rounded, 'Paylaş', _share, overImage),
                const SizedBox(width: 10),
              ],
              flexibleSpace: hasCover
                  ? FlexibleSpaceBar(
                      collapseMode: CollapseMode.parallax,
                      background: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(memCacheWidth: 1200, imageUrl: s.coverUrl, fit: BoxFit.cover),
                          // durum çubuğu ve düğmeler her görselde okunsun
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment(0, -0.2),
                                colors: [Color(0x99000000), Color(0x00000000)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              sliver: SliverList.list(
                children: [
                  Text(
                    trUpper(s.categoryLabel),
                    style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.6),
                  ),
                  const SizedBox(height: 10),
                  Text(s.title, style: c.text(27, weight: FontWeight.w800, height: 1.18, spacing: -0.8)),
                  if (s.excerpt.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(s.excerpt, style: c.text(16, color: c.muted, height: 1.5)),
                  ],
                  const SizedBox(height: 16),
                  Container(height: 2, width: 44, color: c.ink),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (s.author.isNotEmpty) Text(trUpper(s.author), style: c.text(11, weight: FontWeight.w700, spacing: 1)),
                      if (s.author.isNotEmpty) Text('·', style: c.text(11, color: c.faint)),
                      Text(
                        trUpper(magDate(s.publishedAt)),
                        style: c.text(11, weight: FontWeight.w600, color: c.muted, spacing: 1),
                      ),
                      Text('·', style: c.text(11, color: c.faint)),
                      Text(
                        '${s.readingMinutes} DK',
                        style: c.text(11, weight: FontWeight.w600, color: c.muted, spacing: 1),
                      ),
                      Text('·', style: c.text(11, color: c.faint)),
                      Text(
                        '${s.views} GÖRÜNTÜLENME',
                        style: c.text(11, weight: FontWeight.w600, color: c.muted, spacing: 1),
                      ),
                    ],
                  ),
                  if (s.eventAt != null) ...[const SizedBox(height: 16), _eventCard(c, s)],
                  if (s.mandatory) ...[const SizedBox(height: 16), _ackCard(c, p)],
                  const SizedBox(height: 18),
                  for (final b in p.blocks) _block(c, b),
                  if (p.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in p.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: c.line),
                            ),
                            child: Text(
                              '#$t',
                              style: c.text(12, weight: FontWeight.w600, color: c.muted),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  _actions(c, p),
                  if (p.related.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Text(
                          'İLGİLİ HABERLER',
                          style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Container(height: 1, color: c.line)),
                      ],
                    ),
                    for (var i = 0; i < p.related.length; i++) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: c.line),
                      _MagRow(
                        post: p.related[i],
                        onTap: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => MagPostScreen(
                              session: widget.session,
                              config: widget.config,
                              slug: p.related[i].slug,
                              module: widget.module,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  SizedBox(height: 32 + pad.bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton(ArconMono c, IconData icon, String tip, VoidCallback onTap, bool overImage) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: overImage ? Colors.black.withValues(alpha: 0.35) : c.field,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 20, color: overImage ? Colors.white : c.ink),
        ),
      ),
    );
  }

  Widget _block(ArconMono c, MagBlock b) {
    switch (b.type) {
      case 'h2':
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          child: Text(b.text, style: c.text(21, weight: FontWeight.w800, height: 1.25, spacing: -0.4)),
        );
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(b.text, style: c.text(17.5, weight: FontWeight.w700, height: 1.3)),
        );
      case 'quote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.fromLTRB(16, 4, 0, 4),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: c.ink, width: 3)),
          ),
          child: Text(b.text, style: c.text(18, weight: FontWeight.w600, height: 1.45, spacing: -0.2)),
        );
      case 'li':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 9, right: 12),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                ),
              ),
              Expanded(child: Text(b.text, style: c.text(16, height: 1.65))),
            ],
          ),
        );
      case 'img':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(memCacheWidth: 1080, imageUrl: b.url, fit: BoxFit.cover),
              ),
              if (b.text.isNotEmpty) ...[const SizedBox(height: 6), Text(b.text, style: c.text(12, color: c.muted))],
            ],
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SelectableText(b.text, style: c.text(16, height: 1.7)),
        );
    }
  }

  Widget _eventCard(ArconMono c, MagPostSummary s) {
    final d = s.eventAt!;
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(Icons.event_outlined, color: c.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${magDate(d)} · $time', style: c.text(14, weight: FontWeight.w700)),
                if (s.eventLocation.isNotEmpty) Text(s.eventLocation, style: c.text(12.5, color: c.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ackCard(ArconMono c, MagPost p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.acked ? c.field : c.ink,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.acked ? c.line : c.ink),
      ),
      child: Row(
        children: [
          Icon(p.acked ? Icons.task_alt_rounded : Icons.campaign_outlined, color: p.acked ? c.ink : c.bg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.acked ? 'Okuduğunu onayladın · ${p.ackCount} kişi onayladı' : 'Bu duyuruyu okuduğunu onaylaman bekleniyor.',
              style: c.text(13, weight: FontWeight.w600, color: p.acked ? c.ink : c.bg, height: 1.35),
            ),
          ),
          if (!p.acked) ...[
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _ackBusy ? null : _ack,
              style: FilledButton.styleFrom(
                backgroundColor: c.bg,
                foregroundColor: c.ink,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Okudum', style: c.text(13, weight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(ArconMono c, MagPost p) {
    Widget pill({required Widget child, required bool on, required VoidCallback onTap}) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? c.ink : c.field,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? c.ink : c.line),
        ),
        child: child,
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bu haberi nasıl buldun?', style: c.text(13.5, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pill(
                on: p.liked,
                onTap: () => _toggle('like'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(p.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 17, color: p.liked ? c.bg : c.ink),
                    const SizedBox(width: 6),
                    Text(
                      '${p.likes}',
                      style: c.text(13, weight: FontWeight.w700, color: p.liked ? c.bg : c.ink),
                    ),
                  ],
                ),
              ),
              for (final r in p.reactionTypes)
                pill(
                  on: p.myReactions.contains(r.key),
                  onTap: () => _toggle('react', type: r.key),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Poppins'te emoji yok: sistem emoji yazı tipine düşsün (webdeki 👏 🔥 💡)
                      Text(r.emoji, style: const TextStyle(fontSize: 15, fontFamilyFallback: ['Apple Color Emoji', 'Noto Color Emoji'])),
                      const SizedBox(width: 6),
                      Text(
                        '${p.reactions[r.key] ?? 0}',
                        style: c.text(13, weight: FontWeight.w700, color: p.myReactions.contains(r.key) ? c.bg : c.ink),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ======================================================================
 * Kaydedilen / beğenilen
 * ====================================================================== */

class MagListScreen extends StatefulWidget {
  const MagListScreen({super.key, required this.session, required this.config, required this.view, required this.module});

  final SessionController session;
  final ArconAppConfig config;

  /// `saved` ya da `liked`.
  final String view;
  final ArconModule module;

  @override
  State<MagListScreen> createState() => _MagListScreenState();
}

class _MagListScreenState extends State<MagListScreen> {
  List<MagPostSummary>? _posts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (_posts == null) {
      final cached = await widget.session.api.cachedMagList(widget.view);
      if (cached != null && mounted) setState(() => _posts = cached);
    }
    try {
      final p = await widget.session.api.magList(widget.view, force: force);
      if (mounted) setState(() => _posts = p);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_posts == null && _serverLacksApi(e)) {
        final path = 'arcon-mag?view=${widget.view}';
        _openWeb(
          context,
          widget.session,
          widget.config,
          ArconModule(
            key: 'path:$path',
            title: widget.module.title,
            group: 'main',
            icon: '',
            render: 'webview',
            path: path,
            url: Uri.parse(widget.config.apiBase).resolve(path).toString(),
          ),
          replace: true,
        );
        return;
      }
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final title = widget.view == 'saved' ? 'Kaydettiklerim' : 'Beğendiklerim';
    final posts = _posts;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(title, style: c.text(18, weight: FontWeight.w800)),
      ),
      body: posts == null
          ? (_error == null
                ? const SkeletonList(count: 6, leading: false, thumbnail: true)
                : Center(
                    child: Text(_error!, style: c.text(14, color: c.muted)),
                  ))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: () => _load(force: true),
              child: posts.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Icon(
                          widget.view == 'saved' ? Icons.bookmark_border_rounded : Icons.favorite_border_rounded,
                          size: 36,
                          color: c.faint,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.view == 'saved' ? 'Henüz haber kaydetmedin' : 'Henüz haber beğenmedin',
                          textAlign: TextAlign.center,
                          style: c.text(14, color: c.muted),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: posts.length,
                      separatorBuilder: (_, _) => Divider(height: 1, thickness: 1, color: c.line),
                      itemBuilder: (context, i) => _MagRow(
                        post: posts[i],
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  MagPostScreen(session: widget.session, config: widget.config, slug: posts[i].slug, module: widget.module),
                            ),
                          );
                          _load();
                        },
                      ),
                    ),
            ),
    );
  }
}


/// Bu haftanın sayısı — webdeki arcon-mag_sayi: haftalık derleme, önceki/sonraki sayı, PDF.
class MagIssueScreen extends StatefulWidget {
  const MagIssueScreen({super.key, required this.session, required this.config, required this.module, this.week});

  final SessionController session;
  final ArconAppConfig config;
  final ArconModule module;
  final String? week;

  @override
  State<MagIssueScreen> createState() => _MagIssueScreenState();
}

class _MagIssueScreenState extends State<MagIssueScreen> {
  String? _week;
  Map<String, dynamic>? _data;
  List<MagPostSummary> _posts = const [];
  String? _error;
  bool _pdfBusy = false;

  @override
  void initState() {
    super.initState();
    _week = widget.week;
    _load();
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.magIssue(_week, force: force);
      if (!mounted) return;
      setState(() {
        _data = j;
        _posts = magPostsFromJson(j['posts']);
        _error = null;
      });
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_data == null && _serverLacksApi(e)) {
        final path = _week == null ? 'arcon-mag_sayi' : 'arcon-mag_sayi?w=$_week';
        _openWeb(
          context,
          widget.session,
          widget.config,
          ArconModule(
            key: 'path:$path',
            title: widget.module.title,
            group: 'main',
            icon: '',
            render: 'webview',
            path: path,
            url: Uri.parse(widget.config.apiBase).resolve(path).toString(),
          ),
          replace: true,
        );
        return;
      }
      setState(() => _error = e.message);
    }
  }

  void _go(String? week) {
    if (week == null) return;
    setState(() {
      _week = week;
      _data = null;
    });
    _load();
  }

  Future<void> _pdf() async {
    final path = _data?['pdf_path'] as String?;
    if (path == null || _pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final api = widget.session.api;
      final res = await http.get(api.webUrl(path), headers: {if (api.token != null) 'Authorization': 'Bearer ${api.token}'}).timeout(const Duration(minutes: 2));
      if (res.statusCode != 200 || !(res.headers['content-type'] ?? '').contains('pdf')) throw Exception();
      if (mounted) await toolShareBytes(context, res.bodyBytes, 'ArconMag-Sayi-${_data?['number'] ?? ''}.pdf');
    } catch (_) {
      if (mounted) toolToast(context, 'PDF alınamadı');
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  void _open(MagPostSummary p) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MagPostScreen(session: widget.session, config: widget.config, slug: p.slug, module: widget.module),
      ));

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final d = _data;
    Widget navBtn(String label, String? week) => TextButton(
          onPressed: week == null ? null : () => _go(week),
          child: Text(label, style: c.text(13, weight: FontWeight.w700, color: week == null ? c.faint : c.ink)),
        );
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Bu Haftanın Sayısı', style: c.text(18, weight: FontWeight.w800)),
        actions: [
          if (d?['pdf_path'] != null)
            IconButton(
              tooltip: 'PDF indir',
              onPressed: _pdf,
              icon: _pdfBusy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                  : Icon(Icons.picture_as_pdf_outlined, color: c.ink),
            ),
        ],
      ),
      body: d == null
          ? (_error == null ? const _MagFeedSkeleton() : Center(child: Text(_error!, style: c.text(14, color: c.muted))))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: () => _load(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Text('Sayı #${d['number'] ?? 1}', style: c.text(30, weight: FontWeight.w800, spacing: -1)),
                  const SizedBox(height: 2),
                  Text([if ('${d['range'] ?? ''}'.isNotEmpty) d['range'], '${_posts.length} haber'].join(' · '), style: c.text(13, color: c.muted)),
                  Row(
                    children: [
                      Transform.translate(offset: const Offset(-12, 0), child: navBtn('‹ Önceki sayı', d['older'] as String?)),
                      const Spacer(),
                      navBtn('Sonraki sayı ›', d['newer'] as String?),
                    ],
                  ),
                  Divider(height: 1, thickness: 1, color: c.line),
                  const SizedBox(height: 18),
                  if (_posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Center(child: Text('Bu hafta için henüz yayınlanmış haber yok.', style: c.text(14, color: c.muted))),
                    )
                  else ...[
                    _MagCoverCard(post: _posts.first, onTap: () => _open(_posts.first)),
                    for (final p in _posts.skip(1)) ...[
                      Divider(height: 1, thickness: 1, color: c.line),
                      _MagRow(post: p, onTap: () => _open(p)),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
