import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../auth/session_controller.dart';
import '../../config.dart';
import '../home_screen.dart' show WebModuleIcon;
import '../mono.dart';
import '../skeleton.dart';
import 'club_common.dart';

/// Yerli ana sayfa — webdeki Dashboard'un (dashboard.php) karşılığı:
/// selamlama, durum kartları, ürün kartları, yönetici özeti ve AI modülleri.
/// `/api/v1/dashboard` yoksa (eski sunucu) ürün kartları modül listesinden kurulur.
class ClubDashboard extends StatefulWidget {
  const ClubDashboard({super.key, required this.session, required this.config, required this.onOpenModules, required this.onOpenProfile});

  final SessionController session;
  final ArconAppConfig config;
  final VoidCallback onOpenModules;
  final VoidCallback onOpenProfile;

  @override
  State<ClubDashboard> createState() => ClubDashboardState();
}

class ClubDashboardState extends State<ClubDashboard> {
  DashboardData? _data;
  bool _loading = true;
  final _notices = PageController(viewportFraction: 0.92);
  int _noticePage = 0;
  Timer? _autoSlide;
  bool _holding = false;

  /// Duyuru kartları 5 saniyede bir sıradakine geçer; sondan sonra başa döner.
  void _restartAutoSlide() {
    _autoSlide?.cancel();
    _autoSlide = Timer.periodic(const Duration(seconds: 5), (_) {
      final n = _data?.notices.length ?? 0;
      if (n < 2 || _holding || !_notices.hasClients || !mounted) return;
      final next = (_noticePage + 1) % n;
      _notices.animateToPage(
        next,
        duration: Duration(milliseconds: next == 0 ? 600 : 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _restartAutoSlide();
    _start();
  }

  /// Önce önbellekteki son ana sayfa (anında), sonra tazelik süresi dolduysa sunucu.
  Future<void> _start() async {
    final cached = await widget.session.api.cachedDashboard();
    if (cached != null && mounted) {
      setState(() {
        _data = cached;
        _loading = false;
      });
    }
    await load();
  }

  @override
  void dispose() {
    _autoSlide?.cancel();
    _notices.dispose();
    super.dispose();
  }

  Future<void> load({bool force = false}) async {
    try {
      final d = await widget.session.api.dashboard(force: force);
      if (mounted) setState(() => _data = d);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([load(force: true), widget.session.refreshModules(force: true).catchError((_) {})]);
  }

  void _open({String? key, String? path, String? title}) {
    if (key == 'ai_hub') {
      widget.onOpenModules();
      return;
    }
    clubOpen(context, session: widget.session, config: widget.config, key: key, path: path, title: title);
  }

  List<DashboardFeature> get _features {
    final fromApi = _data?.features;
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;
    // Sunucuda dashboard ucu yoksa: modül listesindeki ürünler
    return [
      for (final m in widget.session.modules)
        if (m.group == 'main' && m.key != 'dashboard')
          DashboardFeature(key: m.key, name: clubShortName(m.title), description: clubFeatureFallbackText[m.key] ?? m.description),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final user = widget.session.user;
    final ai = widget.session.modules.where((m) => m.group == 'ai_modules').toList();
    final notices = _data?.notices ?? const <DashboardNotice>[];
    final admin = _data?.admin;
    final pad = MediaQuery.paddingOf(context);

    return RefreshIndicator(
      color: c.ink,
      backgroundColor: c.bg,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ArconClubMark(c: c, color: c.ink),
                      const Spacer(),
                      // ARCON SEARCH yetkisi varsa üstte arama
                      if (widget.session.modules.any((m) => m.key == 'search')) ...[
                        Material(
                          color: c.field,
                          shape: CircleBorder(side: BorderSide(color: c.line)),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _open(key: 'search'),
                            child: SizedBox(width: 38, height: 38, child: Icon(Icons.search_rounded, size: 20, color: c.ink)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      GestureDetector(
                        onTap: widget.onOpenProfile,
                        child: ClubAvatar(user: user, size: 38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _greeting(),
                    style: c.text(14, weight: FontWeight.w500, color: c.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.username ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: c.text(24, weight: FontWeight.w800, height: 1.15, spacing: -0.6),
                  ),
                  const SizedBox(height: 4),
                  Text(_today(), style: c.text(12.5, color: c.faint)),
                ],
              ),
            ),
          ),
          if (notices.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 22)),
            SliverToBoxAdapter(child: _noticeCarousel(c, notices)),
          ] else if (_loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                child: const Shimmer(child: SkeletonBox(width: double.infinity, height: 152, radius: 22)),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
            sliver: SliverToBoxAdapter(child: ClubSectionTitle('Ürünler')),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 140),
              delegate: SliverChildBuilderDelegate((context, i) => _featureCard(c, _features[i]), childCount: _features.length),
            ),
          ),
          if (ai.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              sliver: SliverToBoxAdapter(
                child: ClubSectionTitle('AI Modüllerim', action: 'Tümü', onAction: widget.onOpenModules),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: ai.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _aiTile(c, ai[i]),
                ),
              ),
            ),
          ],
          if (admin != null) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              sliver: SliverToBoxAdapter(child: ClubSectionTitle('Yönetim')),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(child: _adminPanel(c, admin)),
            ),
          ],
          SliverToBoxAdapter(child: SizedBox(height: 28 + pad.bottom)),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'İyi geceler,';
    if (h < 12) return 'Günaydın,';
    if (h < 18) return 'İyi günler,';
    return 'İyi akşamlar,';
  }

  String _today() {
    const days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
    const months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
    final d = DateTime.now();
    return '${d.day} ${months[d.month - 1]} ${d.year}, ${days[d.weekday - 1]}';
  }

  Widget _noticeCarousel(ArconMono c, List<DashboardNotice> notices) {
    return Column(
      children: [
        SizedBox(
          height: 152,
          child: Listener(
            // basılı tutarken / kaydırırken otomatik geçiş beklesin
            onPointerDown: (_) => _holding = true,
            onPointerUp: (_) {
              _holding = false;
              _restartAutoSlide();
            },
            onPointerCancel: (_) => _holding = false,
            child: PageView.builder(
              controller: _notices,
              padEnds: false,
              itemCount: notices.length,
              onPageChanged: (i) => setState(() => _noticePage = i),
              itemBuilder: (context, i) => Padding(
                padding: EdgeInsets.only(left: i == 0 ? 20 : 5, right: i == notices.length - 1 ? 20 : 5),
                child: _noticeCard(c, notices[i], inverted: i == 0),
              ),
            ),
          ),
        ),
        if (notices.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < notices.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _noticePage ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: i == _noticePage ? c.ink : c.line, borderRadius: BorderRadius.circular(3)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _noticeCard(ArconMono c, DashboardNotice n, {required bool inverted}) {
    final bg = inverted ? c.ink : c.field;
    final fg = inverted ? c.bg : c.ink;
    final soft = fg.withValues(alpha: 0.6);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: inverted ? BorderSide.none : BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(key: n.moduleKey, path: n.path, title: n.kicker),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(clubFeatureIcon(n.moduleKey), size: 16, color: soft),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trUpper(n.kicker),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: c.text(10, weight: FontWeight.w700, color: soft, spacing: 1),
                    ),
                  ),
                  if (n.count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        '${n.count}',
                        style: c.text(10.5, weight: FontWeight.w700, color: bg),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                n.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: c.text(17, weight: FontWeight.w700, color: fg, height: 1.25, spacing: -0.3),
              ),
              const SizedBox(height: 4),
              Text(
                n.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: c.text(12.5, color: soft, height: 1.4),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    n.cta,
                    style: c.text(12.5, weight: FontWeight.w700, color: fg),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: fg),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureCard(ArconMono c, DashboardFeature f) {
    return ClubCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      onTap: () => _open(key: f.key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClubIconBox(clubFeatureIcon(f.key), size: 36),
              const Spacer(),
              if (f.badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    '${f.badge}',
                    style: c.text(10.5, weight: FontWeight.w700, color: c.bg),
                  ),
                )
              else
                Icon(Icons.arrow_outward_rounded, size: 16, color: c.faint),
            ],
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                // ARCONNECT tek kelime: ARCON ve NECT aynı renkte
                TextSpan(
                  text: f.key == 'arconnect' ? 'ARCON' : 'ARCON ',
                  style: f.key == 'arconnect' ? null : TextStyle(color: c.muted),
                ),
                TextSpan(text: trUpper(f.name)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: c.text(13, weight: FontWeight.w800, spacing: 0.4),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              f.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: c.text(11.5, color: c.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiTile(ArconMono c, ArconModule m) {
    return SizedBox(
      width: 96,
      child: ClubCard(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
        onTap: () => _open(key: m.key),
        child: Column(
          children: [
            WebModuleIcon(module: m),
            const SizedBox(height: 8),
            Text(
              m.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: c.text(11, weight: FontWeight.w600, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminPanel(ArconMono c, DashboardAdmin a) {
    final activePct = a.users > 0 ? (a.activeUsers7d / a.users).clamp(0.0, 1.0) : 0.0;
    Widget stat(String label, String value, String hint, String path) => Expanded(
      child: ClubCard(
        padding: const EdgeInsets.all(14),
        onTap: () => _open(path: path, title: label),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trUpper(label),
              style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1),
            ),
            const SizedBox(height: 6),
            Text(value, style: c.text(24, weight: FontWeight.w800, height: 1.1, spacing: -0.5)),
            const SizedBox(height: 2),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: c.text(11, color: c.faint),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            stat('Kullanıcılar', _n(a.users), '7 günde aktif: ${_n(a.activeUsers7d)}', 'users.php'),
            const SizedBox(width: 10),
            stat('Modüller', _n(a.modules), 'Roller: ${_n(a.roles)}', 'admin-modules'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            stat('Destek', _n(a.openTickets), 'Açık talep', 'helpdesk'),
            const SizedBox(width: 10),
            if (a.logs != null)
              stat('Loglar', _n(a.logs!), 'Bugün: ${_n(a.logsToday ?? 0)}', 'logs.php')
            else
              stat('Roller', _n(a.roles), 'Yetki tanımları', 'roles.php'),
          ],
        ),
        const SizedBox(height: 10),
        ClubCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: () => _open(path: 'panels', title: 'Modül yönetimi'),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: c.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Modül panelleri', style: c.text(14, weight: FontWeight.w700)),
              ),
              Text('MAG · Akademi · SCORE · Store · ARCONNECT', style: c.text(10.5, color: c.faint)),
              Icon(Icons.chevron_right_rounded, color: c.faint),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ClubCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Aktif kullanıcılar (7 gün)', style: c.text(12.5, weight: FontWeight.w600)),
                  const Spacer(),
                  Text('${_n(a.activeUsers7d)} / ${_n(a.users)}', style: c.text(12.5, weight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(value: activePct, minHeight: 8, color: c.ink, backgroundColor: c.line),
              ),
              if (a.activities.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'SON AKTİVİTELER',
                  style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1),
                ),
                for (final act in a.activities) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              act.action,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: c.text(12.5, weight: FontWeight.w600, height: 1.3),
                            ),
                            Text(
                              [if (act.module.isNotEmpty && act.module != '—') act.module, if (act.user.isNotEmpty && act.user != '-') act.user].join(' · '),
                              style: c.text(11, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                      Text(_ago(act.at), style: c.text(11, color: c.faint)),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _n(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'az önce';
    if (d.inHours < 1) return '${d.inMinutes} dk';
    if (d.inDays < 1) return '${d.inHours} sa';
    if (d.inDays < 7) return '${d.inDays} gün';
    return '${t.day}.${t.month}.${t.year}';
  }
}
