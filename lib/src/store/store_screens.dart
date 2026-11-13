import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

String _s(Object? v) => v == null ? '' : '$v';

/// ARCON STORE — ARCON ürünlerinin satıldığı mağazalar (webdeki arcon-store.php).
class StoreHomeScreen extends StatefulWidget {
  const StoreHomeScreen({super.key, required this.session, required this.config, this.openStoreId});

  final SessionController session;
  final ArconAppConfig config;
  final int? openStoreId;

  @override
  State<StoreHomeScreen> createState() => _StoreHomeScreenState();
}

class _StoreHomeScreenState extends State<StoreHomeScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  final _q = TextEditingController();
  String _retailer = '';
  String _city = '';
  String _brand = '';
  bool _openedInitial = false;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _start();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final c = await widget.session.api.cachedStores();
    if (c != null && mounted) _apply(c);
    await _load();
  }

  void _apply(Map<String, dynamic> j) {
    setState(() => _data = j);
    final id = widget.openStoreId;
    if (id != null && !_openedInitial) {
      final s = _all.where((e) => e['id'] == id).firstOrNull;
      if (s != null) {
        _openedInitial = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openStore(s));
      }
    }
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.stores(force: force);
      if (mounted) _apply(j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_data == null && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'ARCON STORE', path: 'arcon-store', replace: true);
        return;
      }
      setState(() => _error = e.message);
    }
  }

  List<Map<String, dynamic>> get _all =>
      ((_data?['stores'] as List?) ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  List<Map<String, dynamic>> get _filtered {
    final q = _q.text.trim().toLowerCase();
    final list = _all.where((s) {
      if (_retailer.isNotEmpty && s['retailer'] != _retailer) return false;
      if (_city.isNotEmpty && s['city'] != _city) return false;
      if (_brand.isNotEmpty && !((s['brands'] as List?) ?? const []).any((b) => '$b'.toLowerCase() == _brand.toLowerCase())) return false;
      if (q.isEmpty) return true;
      return [s['store_name'], s['mall'], s['district'], s['city'], s['address'], s['retailer_label']]
          .any((v) => _s(v).toLowerCase().contains(q));
    }).toList();
    // fotoğraflılar önce (webdeki gibi)
    list.sort((a, b) => (b['image_url'] != null ? 1 : 0) - (a['image_url'] != null ? 1 : 0));
    return list;
  }

  void _openStore(Map<String, dynamic> s) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _StoreDetailScreen(store: s)));
  }

  Future<void> _pick(String title, List<String> options, String current, ValueChanged<String> onPick) async {
    final c = ArconMono.of(context);
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.bg,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + MediaQuery.paddingOf(ctx).bottom),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text(title, style: c.text(18, weight: FontWeight.w800))),
            for (final o in ['', ...options])
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                title: Text(o.isEmpty ? 'Tümü' : o, style: c.text(15, weight: o == current ? FontWeight.w800 : FontWeight.w500)),
                trailing: o == current ? Icon(Icons.check_rounded, color: c.ink) : null,
                onTap: () => Navigator.of(ctx).pop(o),
              ),
          ],
        ),
      ),
    );
    if (v != null) setState(() => onPick(v));
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
                    Text('ARCON STORE', style: c.text(19, weight: FontWeight.w800, spacing: 0.4)),
                  ],
                ),
              ),
              Expanded(
                child: SkeletonSwitcher(
                  loading: d == null && _error == null,
                  skeleton: const SkeletonList(count: 6, leading: false, thumbnail: true),
                  child: d == null ? Center(child: Text(_error ?? '', style: c.text(14, color: c.muted))) : _body(c, d, pad),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ArconMono c, Map<String, dynamic> d, EdgeInsets pad) {
    final stats = ((d['stats'] as Map?) ?? const {}).cast<String, dynamic>();
    final retailers = ((d['retailers'] as List?) ?? const []).whereType<Map>().toList();
    final cities = ((d['cities'] as List?) ?? const []).map((e) => '$e').toList();
    final brands = ((d['brands'] as List?) ?? const []).map((e) => '$e').toList();
    final list = _filtered;
    final empty = _all.isEmpty;

    Widget stat(Object? n, String label) => Expanded(
          child: Column(
            children: [
              Text('${n ?? 0}', style: c.text(20, weight: FontWeight.w800, color: c.dark ? c.ink : c.bg)),
              Text(label, textAlign: TextAlign.center, style: c.text(11, color: (c.dark ? c.ink : c.bg).withValues(alpha: 0.65))),
            ],
          ),
        );
    Widget chip(String label, bool on, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.ink : c.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? c.ink : c.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: c.text(12, weight: FontWeight.w700, color: on ? c.bg : c.ink)),
                  if (icon != null) ...[const SizedBox(width: 2), Icon(icon, size: 16, color: on ? c.bg : c.muted)],
                ],
              ),
            ),
          ),
        );

    return RefreshIndicator(
      color: c.ink,
      onRefresh: () => _load(force: true),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
        children: [
          Text('ARCON ürünlerinin satıldığı mağazalar ve AVM içindeki katları.', style: c.text(13.5, color: c.muted, height: 1.45)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            decoration: BoxDecoration(
              color: c.dark ? c.field : c.ink,
              borderRadius: BorderRadius.circular(18),
              border: c.dark ? Border.all(color: c.line) : null,
            ),
            child: Row(children: [stat(stats['stores'], 'mağaza'), stat(stats['malls'], 'AVM'), stat(stats['cities'], 'şehir'), stat(stats['with_floor'], 'kat bilgili')]),
          ),
          if (empty)
            Padding(
              padding: const EdgeInsets.only(top: 50),
              child: Column(
                children: [
                  Icon(Icons.storefront_outlined, size: 44, color: c.faint),
                  const SizedBox(height: 10),
                  Text('Henüz mağaza eklenmedi', style: c.text(15, weight: FontWeight.w700)),
                ],
              ),
            )
          else ...[
            const SizedBox(height: 14),
            TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
              style: c.text(15),
              cursorColor: c.ink,
              decoration: c.input(
                'Mağaza, AVM, ilçe ara…',
                Icons.search_rounded,
                suffix: _q.text.isEmpty ? null : IconButton(onPressed: _q.clear, icon: Icon(Icons.close_rounded, size: 18, color: c.muted)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  chip('Tümü', _retailer.isEmpty, () => setState(() => _retailer = '')),
                  for (final r in retailers) chip('${r['label']}', _retailer == r['key'], () => setState(() => _retailer = _retailer == r['key'] ? '' : '${r['key']}')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  chip(_city.isEmpty ? 'Tüm şehirler' : _city, _city.isNotEmpty, () => _pick('Şehir', cities, _city, (v) => _city = v), icon: Icons.expand_more_rounded),
                  if (brands.isNotEmpty)
                    chip(_brand.isEmpty ? 'Tüm markalar' : _brand, _brand.isNotEmpty, () => _pick('ARCON markası', brands, _brand, (v) => _brand = v), icon: Icons.expand_more_rounded),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text('${list.length} mağaza', style: c.text(12, weight: FontWeight.w700, color: c.muted)),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Center(child: Text('Filtrelere uyan mağaza yok', style: c.text(14, color: c.muted))),
              )
            else
              for (final s in list) ...[_row(c, s), const SizedBox(height: 10)],
          ],
        ],
      ),
    );
  }

  Widget _row(ArconMono c, Map<String, dynamic> s) {
    final img = s['image_url'] as String?;
    final where = [_s(s['mall']), [_s(s['district']), _s(s['city'])].where((e) => e.isNotEmpty).join(', ')].where((e) => e.isNotEmpty).join(' · ');
    return PressScale(
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openStore(s),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: img != null
                        ? CachedNetworkImage(memCacheWidth: 260, imageUrl: img, fit: BoxFit.cover, errorWidget: (_, _, _) => _placeholder(c))
                        : _placeholder(c),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trUpper(_s(s['retailer_label'])), maxLines: 1, style: c.text(9.5, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                      const SizedBox(height: 2),
                      Text(_s(s['store_name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(15, weight: FontWeight.w800)),
                      if (where.isNotEmpty) Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, color: c.muted)),
                      if (_s(s['floor_label']).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
                          child: Text(_s(s['floor_label']), style: c.text(10.5, weight: FontWeight.w700, color: c.muted)),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ArconMono c) => Container(color: c.ink, child: Icon(Icons.storefront_outlined, color: c.bg));
}

/* ============================== Mağaza detayı ============================== */

class _StoreDetailScreen extends StatelessWidget {
  const _StoreDetailScreen({required this.store});

  final Map<String, dynamic> store;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final s = store;
    final img = s['image_url'] as String?;
    final brands = ((s['brands'] as List?) ?? const []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
    final lat = s['lat'] as num?;
    final lng = s['lng'] as num?;
    final phone = _s(s['phone']);
    final pad = MediaQuery.paddingOf(context);
    final mapQuery = lat != null && lng != null
        ? '$lat,$lng'
        : [_s(s['store_name']), _s(s['mall']), _s(s['address']), _s(s['city'])].where((e) => e.isNotEmpty).join(' ');

    Widget kv(IconData icon, String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: c.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trUpper(label), style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                      const SizedBox(height: 2),
                      Text(value, style: c.text(14.5, height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
          );

    return Scaffold(
      backgroundColor: c.bg,
      body: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: img != null ? 280 : 0,
            backgroundColor: c.bg,
            surfaceTintColor: Colors.transparent,
            foregroundColor: img != null ? Colors.white : c.ink,
            systemOverlayStyle: img != null ? SystemUiOverlayStyle.light : (c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark),
            leading: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: CircleAvatar(
                backgroundColor: img != null ? Colors.black38 : Colors.transparent,
                child: Icon(Icons.arrow_back_rounded, color: img != null ? Colors.white : c.ink),
              ),
            ),
            flexibleSpace: img == null
                ? null
                : FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(memCacheWidth: 1200, imageUrl: img, fit: BoxFit.cover, errorWidget: (_, _, _) => ColoredBox(color: c.field)),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Colors.black45, Colors.transparent]),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + pad.bottom),
            sliver: SliverList.list(
              children: [
                if (_s(s['image_credit']).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Fotoğraf: ${s['image_credit']}', style: c.text(11, color: c.faint))),
                Text(trUpper(_s(s['retailer_label'])), style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1.4)),
                const SizedBox(height: 4),
                Text(_s(s['store_name']), style: c.text(26, weight: FontWeight.w800, height: 1.15, spacing: -0.7)),
                if (_s(s['mall']).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_s(s['mall']), style: c.text(15, color: c.muted)),
                ],
                const SizedBox(height: 22),
                kv(Icons.layers_outlined, 'Kat', [_s(s['floor_label']), _s(s['zone'])].where((e) => e.isNotEmpty).join(' · ')),
                kv(Icons.place_outlined, 'Adres', [_s(s['address']), [_s(s['district']), _s(s['city'])].where((e) => e.isNotEmpty).join(' / ')].where((e) => e.isNotEmpty).join('\n')),
                kv(Icons.call_outlined, 'Telefon', phone),
                kv(Icons.notes_rounded, 'Not', _s(s['notes'])),
                if (brands.isNotEmpty) ...[
                  Text(trUpper('ARCON markaları'), style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final b in brands)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
                          child: Text(b, style: c.text(12.5, weight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                const SizedBox(height: 6),
                c.primaryButton('Haritada aç', busy: false, onPressed: () {
                  launchUrl(
                    Uri.https('maps.apple.com', '/', {'q': mapQuery}),
                    mode: LaunchMode.externalApplication,
                  );
                }),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''))),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.line),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: Text('Ara', style: c.text(14.5, weight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
