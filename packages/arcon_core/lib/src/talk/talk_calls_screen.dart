import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'talk_call_screen.dart';
import 'talk_controller.dart';
import 'talk_events.dart';
import 'talk_models.dart';
import 'talk_plan_screen.dart';
import 'talk_new_chat_screen.dart';
import 'talk_swipe.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// WhatsApp iOS "Aramalar": büyük başlık, arama kutusu, hızlı butonlar ve "En Son" listesi.
class TalkCallsScreen extends StatefulWidget {
  const TalkCallsScreen({super.key, required this.controller, this.embedded = false, this.leading = const [], this.onOpenChat});

  final TalkController controller;

  /// Ana ekranın "Aramalar" sekmesinde: alttaki yüzen menüye yer bırakır.
  final bool embedded;

  /// Başlığın solunda "…" düğmesinden önce (ARCON Club'a geri dönüş)
  final List<Widget> leading;

  /// "…" › Mesaj gönder: arama kaydının sohbetini aç (ana ekran)
  final void Function(int channelId)? onOpenChat;

  @override
  State<TalkCallsScreen> createState() => _TalkCallsScreenState();
}

class _TalkCallsScreenState extends State<TalkCallsScreen> {
  List<TalkCallLog>? _calls;
  String? _error;
  String _q = '';

  /// Silinen arama kayıtları (yalnızca bu telefonda gizlenir)
  Set<int> _hidden = {};

  TalkController get _c => widget.controller;
  String get _hiddenKey => 'arcon_talk_hidden_calls_${_c.me?.id ?? 0}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _hide(TalkCallLog l) async {
    setState(() => _hidden.add(l.id));
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_hiddenKey, _hidden.map((e) => '$e').toList());
  }

  /// "…": geri ara, görüntülü ara, sohbete git
  Future<void> _more(TalkCallLog l) async {
    final v = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(l.name),
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'voice'), child: const Text('Sesli ara')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'video'), child: const Text('Görüntülü ara')),
          if (widget.onOpenChat != null)
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, 'chat'), child: const Text('Mesaj gönder')),
          CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Kaydı sil')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'voice':
        await _callBack(l, video: false);
      case 'video':
        await _callBack(l, video: true);
      case 'chat':
        widget.onOpenChat?.call(l.channelId);
      case 'delete':
        await _hide(l);
    }
  }

  /// WhatsApp "Planla": kişi seç → tam ekran planla → sohbete kart
  Future<void> _plan() async {
    final u = await Navigator.of(context).push<TalkUser>(MaterialPageRoute(
      builder: (_) => TalkUserPickerScreen(controller: _c, title: 'Arama planla'),
    ));
    if (u == null || !mounted) return;
    final me = _c.me?.displayName ?? 'Ben';
    final e = await showTalkCallPlanScreen(context, peerName: talkFirstName(u.displayName), organizerName: talkFirstName(me));
    if (e == null || !mounted) return;
    try {
      final ch = await _c.api.openDm(u.id);
      if (ch == null || !mounted) return;
      _c.upsertChannel(ch);
      await _c.api.sendMessage(
        channelId: ch.id,
        body: talkEventBody(
          e.title,
          e.start,
          end: e.end,
          video: e.video,
          approve: e.requireApproval,
          remindMinutes: e.remindMinutes,
          description: e.description,
        ),
        filePaths: [if (e.coverPath != null) e.coverPath!],
      );
      if (mounted) talkToast(context, '${talkFirstName(u.displayName)} ile arama planlandı · ${talkEventWhen(e.start)}');
    } on ArconApiException catch (err) {
      if (mounted) talkToast(context, err.message.isEmpty ? 'Planlanamadı' : err.message, error: true);
    }
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _hidden = (p.getStringList(_hiddenKey) ?? const []).map(int.parse).toSet();
      final list = await _c.api.callHistory();
      if (mounted) setState(() => _calls = list);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message.isEmpty ? 'Aramalar alınamadı' : e.message);
    }
  }

  Future<void> _callBack(TalkCallLog l, {required bool video}) async {
    await TalkCallScreen.start(
      context,
      api: _c.api,
      channelId: l.channelId,
      video: video,
      title: l.name,
      peerName: l.name,
      photoUrl: _c.api.fileUrl(l.avatarPath),
    );
    _load();
  }

  /// Kişi seç → birebir sohbeti aç (yoksa oluştur) → ara
  Future<void> _newCall({required bool video, bool favourites = false}) async {
    final u = await Navigator.of(context).push<TalkUser>(MaterialPageRoute(
      builder: (_) => TalkUserPickerScreen(
        controller: _c,
        title: favourites ? 'Favoriler' : (video ? 'Görüntülü ara' : 'Sesli ara'),
        favouritesOnly: favourites,
      ),
    ));
    if (u == null || !mounted) return;
    try {
      final ch = await _c.api.openDm(u.id);
      if (ch == null || !mounted) return;
      _c.upsertChannel(ch);
      await TalkCallScreen.start(
        context,
        api: _c.api,
        channelId: ch.id,
        video: video,
        title: u.displayName,
        peerName: u.displayName,
        photoUrl: _c.api.fileUrl(u.avatarPath),
      );
      _load();
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message.isEmpty ? 'Arama başlatılamadı' : e.message, error: true);
    }
  }

  /// Bugün saat, son bir haftada "Dün" / gün adı, daha eskide 28.10.2026
  static String _when(String createdAt) {
    final d = talkParseTime(createdAt);
    if (d == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return talkClock(createdAt);
    if (days < 7) return talkDayLabel(d);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final q = _q.trim().toLowerCase();
    final calls = (_calls ?? const <TalkCallLog>[]).where((l) => !_hidden.contains(l.id) && (q.isEmpty || l.name.toLowerCase().contains(q))).toList();

    Widget circle(Widget child, VoidCallback onTap, {bool solid = false, String tip = ''}) => Tooltip(
          message: tip,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: solid ? c.accent : (c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F7F8)),
                shape: BoxShape.circle,
                border: solid ? null : Border.all(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE6E6E8)),
                boxShadow: solid || c.dark ? null : const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: child,
            ),
          ),
        );

    Widget quick(IconData i, String label, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(color: c.searchBg, shape: BoxShape.circle),
                child: Icon(i, size: 25, color: c.ink),
              ),
              const SizedBox(height: 8),
              Text(label, style: talkText(13.5, FontWeight.w400, c.muted)),
            ]),
          ),
        );

    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: top + 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          ...widget.leading,
          PopupMenuButton<String>(
            tooltip: 'Diğer',
            color: c.popBg,
            offset: const Offset(0, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (v) {
              if (v == 'refresh') {
                setState(() => _calls = null);
                _load();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(children: [
                  Expanded(child: Text('Yenile', style: talkText(16, FontWeight.w400, c.ink))),
                  Icon(CupertinoIcons.refresh, size: 20, color: c.ink),
                ]),
              ),
            ],
            child: IgnorePointer(child: circle(Icon(Icons.more_horiz, size: 24, color: c.ink), () {})),
          ),
          const Spacer(),
          circle(Icon(Icons.add, size: 26, color: c.accentContrast), () => _newCall(video: false), solid: true, tip: 'Yeni arama'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Text('Aramalar', style: talkText(34, FontWeight.w700, c.ink, letterSpacing: -0.6, height: 1.1)),
      ),
      Container(
        height: 42,
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 18),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: c.searchBg, borderRadius: BorderRadius.circular(999)),
        child: Row(children: [
          Icon(CupertinoIcons.search, size: 21, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: talkText(17, FontWeight.w400, c.ink),
              cursorColor: c.ink,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Ad veya @kullanıcıadı',
                hintStyle: talkText(17, FontWeight.w400, c.muted),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          quick(CupertinoIcons.phone, 'Ara', () => _newCall(video: false)),
          quick(CupertinoIcons.calendar, 'Planla', _plan),
          quick(CupertinoIcons.video_camera, 'Görüntülü', () => _newCall(video: true)),
          quick(CupertinoIcons.heart, 'Favoriler', () => _newCall(video: false, favourites: true)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 6),
        child: Text('En Son', style: talkText(22, FontWeight.w700, c.ink, letterSpacing: -0.3)),
      ),
    ]);

    Widget body;
    if (_calls == null) {
      body = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: _error == null
                ? CupertinoActivityIndicator(color: c.muted)
                : GestureDetector(
                    onTap: () {
                      setState(() => _error = null);
                      _load();
                    },
                    child: Text('$_error\nTekrar denemek için dokun', textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
                  ),
          ),
        ),
      );
    } else if (calls.isEmpty) {
      body = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(q.isEmpty ? 'Henüz arama yok' : 'Sonuç yok', textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
        ),
      );
    } else {
      body = SliverList.builder(itemCount: calls.length, itemBuilder: (_, i) => _row(c, calls[i]));
    }

    return RefreshIndicator.adaptive(
      onRefresh: _load,
      edgeOffset: top,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: header),
          body,
          SliverToBoxAdapter(child: SizedBox(height: widget.embedded ? 120 : 24)),
        ],
      ),
    );
  }

  Widget _row(TalkColors c, TalkCallLog l) => TalkSwipeActions(
        key: ValueKey('call-${l.id}'),
        actionWidth: 76,
        actions: [
          TalkSwipeAction(icon: Icons.more_horiz, tooltip: 'Diğer', color: const Color(0xFF7C7C80), onTap: () => _more(l)),
          TalkSwipeAction(icon: CupertinoIcons.trash_fill, tooltip: 'Sil', color: TalkColors.dangerSolid, onTap: () => _hide(l)),
        ],
        child: _rowBody(c, l),
      );

  Widget _rowBody(TalkColors c, TalkCallLog l) {
    final red = l.missed && !l.outgoing;
    final kind = l.outgoing ? 'Giden' : (l.missed ? 'Cevapsız' : 'Gelen');
    return InkWell(
      onTap: () => _callBack(l, video: l.video),
      child: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Row(children: [
          TalkAvatar.solid(name: l.name, photoUrl: _c.api.fileUrl(l.avatarPath), size: 42, fontSize: 14, personIfEmpty: true),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 9, 16, 9),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name.isEmpty ? 'Arama' : l.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w400, red ? TalkColors.danger : c.ink)),
                    Row(children: [
                      Icon(l.outgoing ? CupertinoIcons.arrow_up_right : CupertinoIcons.arrow_down_left, size: 13, color: c.muted),
                      const SizedBox(width: 4),
                      Text(kind, style: talkText(14.5, FontWeight.w400, c.muted)),
                    ]),
                  ]),
                ),
                Text(_when(l.createdAt), style: talkText(15, FontWeight.w400, c.muted)),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _callBack(l, video: l.video),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: c.searchBg, shape: BoxShape.circle),
                    child: Icon(l.video ? CupertinoIcons.video_camera : CupertinoIcons.phone, size: 20, color: c.ink),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
