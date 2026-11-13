import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'panel_common.dart';

List<Map<String, dynamic>> _maps(Object? v) => [for (final e in ((v as List?) ?? const []).whereType<Map>()) e.cast<String, dynamic>()];

String _score(Object? v) => v == null ? '—' : pd(v).toStringAsFixed(2);

/* ============================== SCORE yönetimi ============================== */

/// ARCON SCORE — dönem analizi, anket gönderimi ve soru yönetimi (webdeki arcon-skor_admin).
class SkorAdminScreen extends StatefulWidget {
  const SkorAdminScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<SkorAdminScreen> createState() => _SkorAdminScreenState();
}

class _SkorAdminScreenState extends State<SkorAdminScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  int _tab = 0;
  int? _round;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(panelApi, query: {'view': 'skor', 'r': ?_round?.toString()});
      if (mounted) {
        setState(() {
          _d = j;
          _round = pi(j['round_id']);
          _error = null;
        });
      }
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _act(Map<String, Object?> body, String ok) async {
    setState(() => _busy = true);
    try {
      final r = await widget.session.api.webCall(panelApi, jsonBody: body, timeout: const Duration(minutes: 3));
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final mail = r['mail'];
      pToast(context, mail is Map ? '$ok · ${mail['sent'] ?? mail['ok'] ?? ''} e-posta' : ok);
      await _load();
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _question([Map<String, dynamic>? q]) async {
    final groups = ((_d?['groups'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    final body = TextEditingController(text: ps(q?['body']));
    final order = TextEditingController(text: q == null ? '' : '${q['sort_order']}');
    var group = ps(q?['group_key']).isEmpty ? (groups.keys.firstOrNull ?? 'usage') : ps(q?['group_key']);
    var active = q?['is_active'] != false;
    final c = ArconMono.of(context);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(q == null ? 'Yeni soru' : 'Soruyu düzenle', style: c.text(18, weight: FontWeight.w800)),
              const SizedBox(height: 14),
              panelField(c, body, 'Soru metni (1–5 puanlanır)', lines: 3),
              panelChips<String>(c, [for (final e in groups.entries) (e.key, e.value)], group, (v) => set(() => group = v)),
              const SizedBox(height: 10),
              if (q != null) ...[
                panelField(c, order, 'Sıra', icon: Icons.sort_rounded, type: TextInputType.number),
                panelSwitch(c, 'Aktif', active, (v) => set(() => active = v)),
              ],
              const SizedBox(height: 10),
              c.primaryButton('Kaydet', busy: false, onPressed: () => Navigator.of(ctx).pop(true)),
            ],
          ),
        ),
      ),
    );
    if (ok == true && body.text.trim().isNotEmpty) {
      await _act({
        'action': q == null ? 'skor_q_add' : 'skor_q_update',
        'question_id': ?q?['id'],
        'body': body.text.trim(),
        'group_key': group,
        'sort_order': pi(order.text),
        'is_active': active,
      }, 'Soru kaydedildi');
    }
    body.dispose();
    order.dispose();
  }

  Future<void> _newRound() async {
    final now = DateTime.now();
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (!await pConfirm(context, 'Anket gönderilsin mi?', '$key dönemi için anket oluşturulup tüm kullanıcılara e-posta ile gönderilecek.', ok: 'Gönder', destructive: false)) return;
    await _act({'action': 'skor_create_send', 'period_key': key}, 'Anket gönderildi');
  }

  Widget _analysis(ArconMono c) {
    final rounds = _maps(_d!['rounds']);
    final stats = _maps(_d!['stats']);
    final sum = (_d!['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    final resp = _maps(_d!['respondents']);
    final trend = _maps(_d!['trend']);
    final maxAvg = 5.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        if (rounds.isNotEmpty)
          panelChips<int>(c, [for (final r in rounds.take(8)) (pi(r['id']), ps(r['period_label']))], _round ?? 0, (v) {
            setState(() => _round = v);
            _load();
          }),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final (label, value) in [
              ('Ortalama', _score(sum['avg'])),
              ('Katılım', '${resp.length}'),
              ('Soru', '${sum['answered_questions'] ?? stats.length}'),
            ])
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value, style: c.text(22, weight: FontWeight.w800)),
                      Text(label, style: c.text(11.5, color: c.muted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (trend.length > 1) ...[
          panelSection(c, 'Trend'),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final t in trend)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(pd(t['avg']).toStringAsFixed(1), style: c.text(9.5, color: c.muted)),
                          const SizedBox(height: 2),
                          Container(height: 60 * (pd(t['avg']) / maxAvg).clamp(0.04, 1.0), decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 2),
                          Text(ps(t['period_key']).length >= 7 ? ps(t['period_key']).substring(5) : ps(t['period_key']), style: c.text(9.5, color: c.muted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        panelSection(c, 'Soru bazında'),
        if (stats.isEmpty) Text('Bu dönem için henüz yanıt yok.', style: c.text(13, color: c.muted)),
        for (final s in stats)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(ps(s['body']), style: c.text(13.5, height: 1.35))),
                    const SizedBox(width: 10),
                    Text(_score(s['avg']), style: c.text(14, weight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(value: (pd(s['avg']) / 5).clamp(0, 1), minHeight: 6, backgroundColor: c.line, color: c.ink),
                ),
                Text('${s['n']} yanıt', style: c.text(11, color: c.muted)),
              ],
            ),
          ),
        if (resp.isNotEmpty) ...[
          panelSection(c, 'Katılımcılar'),
          for (final r in resp)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(ps(r['name']), style: c.text(14, weight: FontWeight.w600))),
                  Text('${_score(r['avg'])} · ${pDate(ps(r['at']), time: false)}', style: c.text(12, color: c.muted)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _rounds(ArconMono c) {
    final rounds = _maps(_d!['rounds']);
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        c.primaryButton('Bu ay için anket gönder', busy: _busy, onPressed: _newRound),
        const SizedBox(height: 14),
        for (final r in rounds)
          panelCard(
            c,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(ps(r['period_label']), style: c.text(15, weight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        panelTag(c, r['status'] == 'active' ? 'Aktif' : 'Kapalı', strong: r['status'] == 'active'),
                      ]),
                      const SizedBox(height: 2),
                      Text('${r['responses']}/${r['invites']} yanıt · ort. ${_score(r['avg'])}', style: c.text(12, color: c.muted)),
                    ],
                  ),
                ),
                if (r['status'] == 'active')
                  TextButton(
                    onPressed: _busy ? null : () => _act({'action': 'skor_resend', 'round_id': pi(r['id'])}, 'Hatırlatma gönderildi'),
                    child: Text('Hatırlat', style: c.text(13, weight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _questions(ArconMono c) {
    final qs = _maps(_d!['questions']);
    final groups = ((_d?['groups'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + MediaQuery.paddingOf(context).bottom),
      children: [
        for (final q in qs)
          panelCard(
            c,
            onTap: () => _question(q),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ps(q['body']), style: c.text(13.5, height: 1.35, color: q['is_active'] == true ? c.ink : c.faint)),
                      const SizedBox(height: 3),
                      Text('#${q['sort_order']} · ${groups[ps(q['group_key'])] ?? q['group_key']}', style: c.text(11, color: c.muted)),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: q['is_active'] == true,
                  activeTrackColor: c.ink,
                  onChanged: _busy ? null : (v) => _act({'action': 'skor_q_toggle', 'question_id': pi(q['id']), 'is_active': v}, v ? 'Soru açıldı' : 'Soru kapatıldı'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return PanelPage(
      title: 'SCORE yönetimi',
      tabs: const ['Analiz', 'Dönemler', 'Sorular'],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      fab: _tab == 2 && _d != null ? panelFab(c, 'Yeni soru', () => _question()) : null,
      body: _d == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 7, leading: false))
          : RefreshIndicator(color: c.ink, onRefresh: _load, child: [_analysis, _rounds, _questions][_tab](c)),
    );
  }
}

/* ============================== ARCONNECT yönetimi ============================== */

/// ARCONNECT — kanal / mesaj moderasyonu ve kaybolan mesaj ayarları (webdeki arconnect_admin).
class TalkAdminScreen extends StatefulWidget {
  const TalkAdminScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<TalkAdminScreen> createState() => _TalkAdminScreenState();
}

class _TalkAdminScreenState extends State<TalkAdminScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  int _tab = 0;
  int _channel = 0;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(panelApi, query: {
        'view': 'talk',
        if (_channel > 0) 'c': '$_channel',
        if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
      });
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

  Future<void> _act(Map<String, Object?> body, String ok) async {
    try {
      final r = await widget.session.api.webCall(panelApi, jsonBody: body);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      pToast(context, r['purged'] != null ? '$ok · ${r['purged']} mesaj' : ok);
      await _load();
    } on ArconApiException catch (e) {
      if (mounted) pToast(context, e.message);
    }
  }

  String _disappearLabel(int sec) {
    for (final p in _maps(_d?['presets'])) {
      if (pi(p['seconds']) == sec) return ps(p['label']);
    }
    return sec <= 0 ? 'Kapalı' : '$sec sn';
  }

  Future<void> _channelSheet(Map<String, dynamic> ch) async {
    final c = ArconMono.of(context);
    final presets = _maps(_d?['presets']);
    final pick = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ps(ch['name']).isEmpty ? 'Kanal #${ch['id']}' : ps(ch['name']), style: c.text(18, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${ch['members']} üye · ${ch['messages']} mesaj', style: c.text(12.5, color: c.muted)),
              panelSection(c, 'Kaybolan mesajlar'),
              panelChips<int>(c, [for (final p in presets) (pi(p['seconds']), ps(p['label']))], pi(ch['disappear']), (v) => Navigator.of(ctx).pop(v)),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ctx).pop('messages'),
                style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(46)),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: Text('Mesajlarını gör', style: c.text(14, weight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(ctx).pop('delete'),
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                label: Text('Kanalı sil', style: c.text(14, weight: FontWeight.w700, color: c.danger)),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || pick == null) return;
    if (pick is int) {
      await _act({'action': 'talk_set_disappear', 'channel_id': pi(ch['id']), 'seconds': pick}, 'Ayar kaydedildi');
    } else if (pick == 'messages') {
      setState(() {
        _channel = pi(ch['id']);
        _tab = 1;
      });
      _load();
    } else if (pick == 'delete') {
      if (await pConfirm(context, 'Kanal silinsin mi?', 'Kanal ve tüm mesajları kalıcı olarak silinecek.')) {
        await _act({'action': 'talk_delete_channel', 'channel_id': pi(ch['id'])}, 'Kanal silindi');
      }
    }
  }

  Future<void> _messageSheet(Map<String, dynamic> m) async {
    final c = ArconMono.of(context);
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m['deleted'] != true)
              ListTile(leading: Icon(Icons.hide_source_rounded, color: c.ink), title: Text('Mesajı sil (herkesten)', style: c.text(15)), onTap: () => Navigator.of(ctx).pop('delete')),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: c.danger),
              title: Text('Kalıcı olarak temizle', style: c.text(15, color: c.danger)),
              onTap: () => Navigator.of(ctx).pop('purge'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    if (pick == 'delete') {
      await _act({'action': 'talk_delete_message', 'message_id': pi(m['id'])}, 'Mesaj silindi');
    } else if (await pConfirm(context, 'Kalıcı silinsin mi?', 'Mesaj veritabanından tamamen silinecek.')) {
      await _act({'action': 'talk_purge_message', 'message_id': pi(m['id'])}, 'Mesaj temizlendi');
    }
  }

  Widget _channels(ArconMono c) {
    final chs = _maps(_d!['channels']);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        OutlinedButton.icon(
          onPressed: () => _act({'action': 'talk_purge_expired'}, 'Süresi dolanlar temizlendi'),
          style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line), minimumSize: const Size.fromHeight(44)),
          icon: const Icon(Icons.timer_off_outlined, size: 18),
          label: Text('Süresi dolan mesajları temizle', style: c.text(13.5, weight: FontWeight.w700)),
        ),
        const SizedBox(height: 12),
        for (final ch in chs)
          panelCard(
            c,
            onTap: () => _channelSheet(ch),
            child: Row(
              children: [
                Icon(ch['type'] == 'dm' ? Icons.person_outline_rounded : (ch['private'] == true ? Icons.lock_outline_rounded : Icons.tag_rounded), size: 20, color: c.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ps(ch['name']).isEmpty ? 'Kanal #${ch['id']}' : ps(ch['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w700)),
                      Text('${ch['members']} üye · ${ch['messages']} mesaj${pi(ch['deleted']) > 0 ? ' · ${ch['deleted']} silinmiş' : ''}', style: c.text(12, color: c.muted)),
                    ],
                  ),
                ),
                if (pi(ch['disappear']) > 0) panelTag(c, _disappearLabel(pi(ch['disappear']))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _messages(ArconMono c) {
    final msgs = _maps(_d!['messages']);
    final chs = _maps(_d!['channels']);
    final chName = chs.where((e) => pi(e['id']) == _channel).map((e) => ps(e['name'])).firstOrNull;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
      children: [
        TextField(
          controller: _q,
          onSubmitted: (_) => _load(),
          textInputAction: TextInputAction.search,
          keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
          style: c.text(15),
          cursorColor: c.ink,
          decoration: c.input('Mesajlarda ara', Icons.search_rounded),
        ),
        if (_channel > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            InputChip(
              label: Text(chName?.isNotEmpty == true ? chName! : 'Kanal #$_channel', style: c.text(12.5, weight: FontWeight.w700)),
              onDeleted: () {
                setState(() => _channel = 0);
                _load();
              },
              backgroundColor: c.field,
              side: BorderSide(color: c.line),
            ),
          ]),
        ],
        const SizedBox(height: 10),
        if (msgs.isEmpty) Padding(padding: const EdgeInsets.only(top: 30), child: Center(child: Text('Mesaj yok.', style: c.text(14, color: c.muted)))),
        for (final m in msgs)
          panelCard(
            c,
            onTap: () => _messageSheet(m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${m['user']} · ${m['channel']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12.5, weight: FontWeight.w700))),
                    Text(pDate(ps(m['at'])), style: c.text(11, color: c.muted)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  ps(m['body']),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: c.text(13.5, height: 1.35, color: m['deleted'] == true ? c.faint : c.ink).copyWith(decoration: m['deleted'] == true ? TextDecoration.lineThrough : null),
                ),
                if (m['deleted'] == true || m['expires_at'] != null) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, children: [
                    if (m['deleted'] == true) panelTag(c, 'Silinmiş'),
                    if (m['expires_at'] != null) panelTag(c, 'Kaybolur · ${pDate(ps(m['expires_at']))}'),
                  ]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return PanelPage(
      title: 'ARCONNECT yönetimi',
      tabs: const ['Kanallar', 'Mesajlar'],
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      body: _d == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8))
          : RefreshIndicator(color: c.ink, onRefresh: _load, child: _tab == 0 ? _channels(c) : _messages(c)),
    );
  }
}
