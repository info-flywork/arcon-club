import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'panel_common.dart';

List<Map<String, dynamic>> _maps(Object? v) => [for (final e in ((v as List?) ?? const []).whereType<Map>()) e.cast<String, dynamic>()];

String _num(Object? v) {
  final s = pi(v).toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// ARCON Güvenlik — Cloudflare'in durdurduğu saldırılar, giriş denemeleri, Gözcü ve olaylar (webdeki guvenlik.php).
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  static const _ranges = [(24, 'Son 24 saat'), (168, 'Son 7 gün'), (720, 'Son 30 gün')];
  static const _sources = [('all', 'Tümü'), ('cloudflare', 'Cloudflare'), ('app', 'Uygulama'), ('watcher', 'Gözcü')];

  Map<String, dynamic>? _d;
  String? _error;
  int _hours = 24;
  String _src = 'all';
  String _ip = '';
  bool _syncing = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall('api/v1/security', query: {'h': '$_hours', 's': _src, if (_ip.isNotEmpty) 'ip': _ip});
      if (mounted) {
        setState(() {
          _d = j;
          _error = null;
        });
      }
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _set(VoidCallback f) {
    setState(() {
      f();
      _d = null;
    });
    _load();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final r = await widget.session.api.webCall('api/v1/security', jsonBody: {'action': 'sync'}, timeout: const Duration(minutes: 2));
      HapticFeedback.mediumImpact();
      if (mounted) pToast(context, ps(r['message']).isEmpty ? 'Kontrol tamamlandı' : ps(r['message']));
      await _load();
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return PanelPage(
      title: 'Güvenlik',
      actions: [
        IconButton(
          tooltip: 'Şimdi kontrol et',
          onPressed: _syncing ? null : _sync,
          icon: _syncing ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink)) : Icon(Icons.refresh_rounded, color: c.ink),
        ),
      ],
      tabs: const ['Özet', 'Olaylar'],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      body: _d == null
          ? (_error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: c.text(14, color: c.muted)))) : const SkeletonList(count: 8, leading: false))
          : RefreshIndicator(color: c.ink, onRefresh: _load, child: _tab == 0 ? _summary(c) : _events(c)),
    );
  }

  Widget _ranges_(ArconMono c) => panelChips<int>(c, [for (final r in _ranges) (r.$1, r.$2)], _hours, (v) => _set(() => _hours = v));

  Widget _pill(ArconMono c, String text, String state) {
    final dot = switch (state) { 'ok' => const Color(0xFF16A34A), 'bad' => const Color(0xFFDC2626), _ => const Color(0xFFF59E0B) };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: c.text(12, weight: FontWeight.w600, color: c.muted))),
      ]),
    );
  }

  Widget _summary(ArconMono c) {
    final d = _d!;
    final st = ((d['status'] as Map?) ?? const {}).cast<String, dynamic>();
    final k = ((d['kpis'] as Map?) ?? const {}).cast<String, dynamic>();
    final w = (d['watcher'] as Map?)?.cast<String, dynamic>();
    final lastRun = DateTime.tryParse(ps(st['last_run']));
    final series = _maps(d['series']);
    final maxV = series.fold<int>(1, (m, s) => [m, pi(s['cf']) + pi(s['lf'])].reduce((a, b) => a > b ? a : b));
    final alerts = _maps(d['alerts']);
    Widget kpi(String label, Object? v, String sub, {bool alert = false}) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(trUpper(label), style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 0.5)),
              const SizedBox(height: 4),
              Text(_num(v), style: c.text(26, weight: FontWeight.w800, color: alert ? const Color(0xFFDC2626) : c.ink)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(11.5, color: c.muted)),
            ]),
          ),
        );
    Widget rank(String title, List<Map<String, dynamic>> rows, {bool ip = false}) => panelCard(
          c,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: c.text(14, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (rows.isEmpty) Text('Veri yok.', style: c.text(13, color: c.muted)),
            for (final r in rows.take(8))
              InkWell(
                onTap: ip
                    ? () => _set(() {
                          _ip = ps(r['ip']);
                          _tab = 1;
                        })
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(
                      child: Text(ip ? ps(r['ip']) : ps(r['label']),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13, color: ip ? c.ink : c.ink).copyWith(fontFamily: ip || title.contains('sayfa') ? 'Menlo' : null)),
                    ),
                    if (ip && ps(r['country']).isNotEmpty) Text('${r['country']} · ', style: c.text(12, color: c.muted)),
                    Text(_num(r['count']), style: c.text(13, weight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
        );
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          _pill(
            c,
            st['cf_on'] == true
                ? (st['cf_last_ok'] != null ? 'Cloudflare: bağlı · son veri ${pDate(ps(st['cf_last_ok']))}' : 'Cloudflare: bağlı, henüz veri çekilmedi')
                : 'Cloudflare: bağlı değil',
            st['cf_on'] == true ? (st['cf_error'] != null ? 'bad' : 'ok') : 'warn',
          ),
          _pill(c, st['mail_on'] == true ? 'E-posta uyarısı: açık' : 'E-posta uyarısı: alıcı tanımlı değil', st['mail_on'] == true ? 'ok' : 'warn'),
          _pill(c, lastRun == null ? 'Otomatik kontrol: hiç çalışmadı' : 'Otomatik kontrol: son ${pDate(ps(st['last_run']))}',
              lastRun != null && DateTime.now().difference(lastRun).inMinutes < 30 ? 'ok' : 'warn'),
          _pill(
            c,
            w == null
                ? 'Gözcü: henüz çalışmadı'
                : (w['stale'] == true
                    ? 'Gözcü: çalışmıyor · son ${pDate(ps(w['received']))}'
                    : 'Gözcü: ${pi(w['open_count']) > 0 ? '${w['open_count']} açık sorun' : 'sorun yok'} · son ${pDate(ps(w['received']))}'),
            w == null ? 'warn' : (w['stale'] == true || pi(w['open_count']) > 0 ? 'bad' : 'ok'),
          ),
          if (st['cf_error'] != null) _pill(c, ps(st['cf_error']), 'bad'),
        ]),
        const SizedBox(height: 14),
        _ranges_(c),
        const SizedBox(height: 10),
        Row(children: [
          kpi('Durdurulan saldırı', k['cf_blocked'], 'Cloudflare engelledi / doğruladı'),
          kpi('Başarısız giriş', k['login_failed'], 'ARCON giriş sayfası'),
        ]),
        Row(children: [
          kpi('Farklı IP', k['unique_ips'], 'olaylarda görülen'),
          kpi('Uyarı', k['alerts'], pi(k['alerts']) > 0 ? 'incelemeniz gereken' : 'her şey sakin', alert: pi(k['alerts']) > 0),
        ]),
        panelSection(c, 'Zaman içinde olaylar'),
        if (series.isEmpty)
          Text('Bu aralıkta olay yok.', style: c.text(13, color: c.muted))
        else ...[
          SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final s in series)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(height: 116 * pi(s['lf']) / maxV, color: const Color(0xFFF59E0B)),
                      Container(height: 116 * pi(s['cf']) / maxV, color: c.ink),
                    ]),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Container(width: 10, height: 10, color: c.ink),
            Text('  Cloudflare   ', style: c.text(11.5, color: c.muted)),
            Container(width: 10, height: 10, color: const Color(0xFFF59E0B)),
            Text('  Başarısız giriş', style: c.text(11.5, color: c.muted)),
          ]),
        ],
        panelSection(c, 'Gözcü'),
        if (w == null)
          Text('Gözcü henüz çalışmadı. Sağ üstten "Şimdi kontrol et"e bas ya da otomatik kontrolü bekle.', style: c.text(13, color: c.muted))
        else ...[
          for (final g in _maps(w['groups']))
            panelCard(
              c,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  panelTag(c, pi(g['bad']) > 0 ? '${g['bad']} sorun' : 'Temiz', strong: pi(g['bad']) > 0),
                  const SizedBox(width: 8),
                  Text(ps(g['label']), style: c.text(14, weight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                if (g['key'] == 'exposed')
                  Text(
                    '${g['count']} dosya denendi (klasör taraması dahil)${pi(g['bad']) > 0 ? ': ${_maps(g['items']).map((i) => i['target']).join(', ')}' : ', hiçbiri indirilemiyor'}',
                    style: c.text(12.5, color: c.muted),
                  )
                else
                  for (final i in _maps(g['items']))
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: ps(i['target']), style: c.text(12, color: i['ok'] == true ? c.ink : const Color(0xFFDC2626)).copyWith(fontFamily: 'Menlo')),
                        TextSpan(text: '  ${i['detail']}', style: c.text(12.5, color: c.muted)),
                      ])),
                    ),
              ]),
            ),
          for (final o in _maps(w['open']))
            panelCard(
              c,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  panelTag(c, 'Açık', strong: true),
                  const SizedBox(width: 8),
                  Expanded(child: Text(ps(o['title']), style: c.text(13.5, weight: FontWeight.w700))),
                ]),
                if (o['since'] != null) Text('${pDate(ps(o['since']))} tarihinden beri', style: c.text(11.5, color: c.muted)),
                const SizedBox(height: 4),
                Text(ps(o['detail']), style: c.text(12.5, color: c.muted)),
              ]),
            ),
        ],
        panelSection(c, 'Son uyarılar'),
        if (alerts.isEmpty) Text('Bu aralıkta uyarı yok.', style: c.text(13, color: c.muted)),
        for (final a in alerts)
          panelCard(
            c,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (a['source'] == 'watcher') ...[panelTag(c, a['resolved'] == true ? 'Düzeldi' : 'Gözcü', strong: a['resolved'] != true), const SizedBox(width: 8)],
                Expanded(child: Text(ps(a['rule']), style: c.text(13.5, weight: FontWeight.w700))),
                Text(pDate(ps(a['at'])), style: c.text(11, color: c.muted)),
              ]),
              if (ps(a['body']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(ps(a['body']), style: c.text(12.5, color: c.muted))),
            ]),
          ),
        panelSection(c, 'En çoklar'),
        rank("En çok görülen IP'ler", _maps(d['top_ips']), ip: true),
        rank('Ülkeler', _maps(d['top_countries'])),
        rank('Olay türleri', _maps(d['top_types'])),
        rank('Hedeflenen sayfalar', _maps(d['top_paths'])),
      ],
    );
  }

  Widget _events(ArconMono c) {
    final ev = _maps(_d!['events']);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        _ranges_(c),
        const SizedBox(height: 8),
        panelChips<String>(c, [for (final s in _sources) (s.$1, s.$2)], _src, (v) => _set(() => _src = v)),
        if (_ip.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            InputChip(
              label: Text('IP: $_ip', style: c.text(12.5, weight: FontWeight.w700)),
              onDeleted: () => _set(() => _ip = ''),
              backgroundColor: c.field,
              side: BorderSide(color: c.line),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        if (ev.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Text(
                _d!['status'] is Map && (_d!['status'] as Map)['cf_on'] != true
                    ? 'Bu aralıkta olay yok. Cloudflare bağlandığında engellenen saldırılar burada görünecek.'
                    : 'Bu aralıkta olay yok.',
                textAlign: TextAlign.center,
                style: c.text(14, color: c.muted),
              ),
            ),
          ),
        for (final e in ev)
          panelCard(
            c,
            onTap: _ip.isEmpty ? () => _set(() => _ip = ps(e['ip'])) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                panelTag(c, ps(e['source_label'])),
                const SizedBox(width: 6),
                panelTag(c, ps(e['action_label']), strong: ['block', 'challenge', 'managed_challenge', 'js_challenge', 'alert'].contains(e['action'])),
                const Spacer(),
                Text(pDate(ps(e['at'])), style: c.text(11, color: c.muted)),
              ]),
              const SizedBox(height: 6),
              Text(ps(e['type']), style: c.text(14, weight: FontWeight.w600)),
              if (ps(e['username']).isNotEmpty) Text('kullanıcı: ${e['username']}', style: c.text(12, color: c.muted)),
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(text: ps(e['ip']), style: c.text(12.5).copyWith(fontFamily: 'Menlo')),
                if (ps(e['country']).isNotEmpty) TextSpan(text: '  ${e['country']}', style: c.text(12, color: c.muted)),
              ])),
              if (ps(e['request']).isNotEmpty)
                Text(ps(e['request']), maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.muted).copyWith(fontFamily: 'Menlo')),
              if (ps(e['ray']).isNotEmpty) Text('Ray: ${e['ray']}', style: c.text(11, color: c.faint)),
            ]),
          ),
      ],
    );
  }
}
