import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/theme_scope.dart';
import 'talk_call_screen.dart';
import 'talk_camera_screen.dart';
import 'talk_calls_screen.dart';
import 'talk_chat_screen.dart';
import '../push/incoming_callkit.dart';
import '../push/push_service.dart';
import 'talk_ai_logo.dart';
import 'talk_ai_screen.dart';
import 'talk_controller.dart';
import 'talk_events.dart';
import 'talk_share_kinds.dart';
import 'talk_info_screen.dart';
import 'talk_icons.dart';
import 'talk_media_composer.dart';
import 'talk_models.dart';
import 'talk_new_chat_screen.dart';
import 'talk_privacy.dart';
import 'talk_profile_screen.dart';
import 'talk_swipe.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';
import '../ui/skeleton.dart';

/// ARCONNECT ana ekranı — WhatsApp iOS düzeni: Aramalar / Sohbetler / Siz; yüzen alt menü.
class TalkHomeScreen extends StatefulWidget {
  const TalkHomeScreen({super.key, required this.session, required this.config, this.appMode = true});

  /// Açık olan ARCONNECT ekranı sayısı (bildirime dokununca yeni ekran açmak gerekir mi).
  static int mounted = 0;

  final SessionController session;
  final ArconAppConfig config;

  /// ARCONNECT uygulamasında geri butonu yok. Club ve People bu uygulamada açılmaz.
  final bool appMode;

  @override
  State<TalkHomeScreen> createState() => _TalkHomeScreenState();
}

class _TalkHomeScreenState extends State<TalkHomeScreen> {
  late final TalkController _c = TalkController(session: widget.session, baseUrl: widget.config.apiBase)..start();

  @visibleForTesting
  TalkController get controllerForTest => _c;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final Set<int> _sel = {};
  /// basılı tutunca ya da "Seç" ile açılan seçim modu
  bool _selecting = false;
  /// 0 Aramalar · 1 Sohbetler · 2 Siz
  int _tab = 1;
  int _callsKey = 0;
  int? _shownCallId;
  bool _openingCall = false;

  @override
  void initState() {
    super.initState();
    TalkHomeScreen.mounted++;
    _c.addListener(_onCtl);
    // Bildirime dokunuldu → ilgili sohbeti aç
    PushService.openTalkChannel.addListener(_onPushOpen);
    PushService.openIncomingCallId.addListener(_onPushCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onPushOpen();
      _onPushCall();
      _onIncomingCall();
    });
  }

  void _onCtl() {
    _onIncomingCall();
    _onPushCall();
  }

  void _onIncomingCall() {
    final ring = _c.incomingCall;
    if (ring == null || ring.id == _shownCallId || _openingCall || !mounted) return;
    _presentIncoming(ring, accepted: false);
  }

  void _onPushOpen() {
    final id = PushService.openTalkChannel.value;
    if (id == null || !mounted) return;
    PushService.openTalkChannel.value = null;
    _openById(id);
  }

  void _onPushCall() {
    final want = PushService.openIncomingCallId.value;
    if (want == null || !mounted) return;
    TalkCall? ring;
    for (final c in _c.calls) {
      if (c.id == want) ring = c;
    }
    if (ring == null) {
      unawaited(_c.refresh(silent: true));
      return;
    }
    PushService.openIncomingCallId.value = null;
    final accepted = PushService.incomingCallAccepted;
    PushService.incomingCallAccepted = false;
    _presentIncoming(ring, accepted: accepted);
  }

  void _presentIncoming(TalkCall ring, {required bool accepted}) {
    if (_openingCall && !accepted) return;
    _shownCallId = ring.id;
    final ch = _c.channels.where((c) => c.id == ring.channelId).firstOrNull;
    final callerPhoto = ring.caller?.avatarPath ?? '';
    final photo = _c.api.fileUrl(callerPhoto.isNotEmpty ? callerPhoto : (ch?.photo ?? ''));
    final paused = WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    if (!accepted && paused) {
      unawaited(ArconCallkit.showIncoming(
        callId: ring.id,
        channelId: ring.channelId,
        callerName: ring.callerName.isNotEmpty ? ring.callerName : (ring.caller?.displayName ?? 'ARCONNECT'),
        video: ring.video,
        avatarUrl: photo,
      ));
      return;
    }
    if (_openingCall) return;
    _openingCall = true;
    // iPhone: VoIP ile gelen CallKit penceresi uygulama içi ekranla aynı anda çalmasın
    if (!accepted) ArconCallkit.showingInApp(ring.id, true);
    final open = accepted ? TalkCallScreen.joinLive : TalkCallScreen.incoming;
    open(context, api: _c.api, call: ring, photoUrl: photo).whenComplete(() {
      ArconCallkit.showingInApp(ring.id, false);
      unawaited(ArconCallkit.end(ring.id));
      _openingCall = false;
      _shownCallId = null;
    });
  }

  @override
  void dispose() {
    TalkHomeScreen.mounted--;
    _c.removeListener(_onCtl);
    PushService.openTalkChannel.removeListener(_onPushOpen);
    PushService.openIncomingCallId.removeListener(_onPushCall);
    _c.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _open(TalkChannel ch, {List<TalkMediaItem>? media}) async {
    _c.markRead(ch.id);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TalkChatScreen(controller: _c, channel: ch, config: widget.config, session: widget.session, initialMedia: media),
    ));
    _c.refresh(silent: true);
  }

  Future<void> _openById(int id) async {
    var ch = _c.channels.where((c) => c.id == id).firstOrNull;
    if (ch == null) {
      await _c.refresh(silent: true);
      ch = _c.channels.where((c) => c.id == id).firstOrNull;
    }
    if (ch != null && mounted) _open(ch);
  }

  /// Siyah "+" → Yeni sohbet (Kişi seç)
  Future<void> _newChat() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => TalkNewChatScreen(controller: _c)));
    if (mounted && id != null && id > 0) _openById(id);
  }

  /// Kamera: WhatsApp tarzı çekim → sohbet seç → gönderme ekranı
  Future<void> _camera() async {
    final r = await openTalkCamera(context);
    if (r == null || !mounted) return;
    var items = r.items;
    if (r.openGallery) {
      final xs = await ImagePicker().pickMultipleMedia(maxWidth: 1600, imageQuality: 78);
      items = [for (final x in xs) TalkMediaItem(path: x.path, name: x.name, size: await x.length())];
    }
    if (items.isEmpty || !mounted) return;
    final ch = await Navigator.of(context).push<TalkChannel>(MaterialPageRoute(builder: (_) => TalkChatPickerScreen(controller: _c)));
    if (ch == null || !mounted) return;
    _open(ch, media: items);
  }

  void _openAi() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TalkAiScreen(api: widget.session.api, name: _c.me?.displayName ?? widget.session.user?.username ?? ''),
      ));

  /// Arama kutusundaki soruyu doğrudan ARCON AI'a sor
  void _openAiWith(String q) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TalkAiScreen(api: widget.session.api, name: _c.me?.displayName ?? '', initialPrompt: q),
      ));

  void _toggleSel(int id) => setState(() {
        _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
        _selecting = true;
      });

  void _endSelect() => setState(() {
        _sel.clear();
        _selecting = false;
      });

  Future<void> _deleteSelected() async {
    final list = _c.channels.where((ch) => _sel.contains(ch.id)).toList();
    if (list.isEmpty) return;
    final ok = await talkConfirm(context,
        title: list.length == 1 ? 'Bu sohbet silinsin mi?' : '${list.length} sohbet silinsin mi?',
        message: 'Sohbet listenden kaldırılır. Yeni mesaj gelirse yeniden görünür.',
        ok: 'Sil');
    if (!ok || !mounted) return;
    _endSelect();
    try {
      for (final ch in list) {
        await _c.hideChat(ch);
      }
      if (mounted) talkToast(context, list.length == 1 ? 'Sohbet silindi' : '${list.length} sohbet silindi');
    } on Exception catch (e) {
      if (mounted) talkToast(context, '$e'.replaceFirst('ArconApiException', 'Silinemedi'), error: true);
    }
  }

  /// Seçilenlerin hepsi o durumdaysa geri al, değilse hepsine uygula
  Future<void> _applySelected(Set<int> current, Future<void> Function(int id) toggle) async {
    final ids = _sel.toList();
    final all = ids.every(current.contains);
    _endSelect();
    for (final id in ids) {
      if (current.contains(id) == all) await toggle(id);
    }
  }

  Future<void> _readAll() async {
    for (final ch in _c.channels.where((c) => c.unread > 0).toList()) {
      _c.markRead(ch.id);
      unawaited(_c.api.read(ch.id).catchError((_) {}));
    }
  }

  void _openProfile() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TalkProfileScreen(controller: _c)));

  void _openArchived() {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ArchivedPage(
        controller: _c,
        onOpen: (ch) => _open(ch),
        onUnarchive: (ch) => _c.toggleArchive(ch.id),
      ),
    ));
  }

  /// "Kilitli sohbetler": Face ID / parmak izi ile açılır
  Future<void> _openLocked() async {
    if (!await talkUnlock(context) || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ArchivedPage(
        controller: _c,
        locked: true,
        onOpen: (ch) => _open(ch),
        onUnarchive: (ch) => _c.toggleLock(ch.id),
      ),
    ));
  }

  /// Kilitle / kilidi aç: her iki yönde de doğrulama ister
  Future<void> _toggleLock(TalkChannel ch) async {
    final on = _c.locked.contains(ch.id);
    if (!await talkUnlock(context, reason: on ? 'Sohbetin kilidini açmak için doğrula' : 'Sohbeti kilitlemek için doğrula') || !mounted) return;
    await _c.toggleLock(ch.id);
    if (mounted) talkToast(context, on ? 'Sohbetin kilidi açıldı' : 'Sohbet kilitlendi · Kilitli sohbetler\'de');
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final barBottom = (bottomInset > 0 ? bottomInset - 6 : 10).toDouble();
    return PopScope(
      // Android geri: önce seçimi kapat, sonra Sohbetler sekmesine dön
      canPop: !_selecting && _tab == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _selecting ? _endSelect() : setState(() => _tab = 1);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: _tab == 2 ? c.infoBg : c.rail,
          body: ListenableBuilder(
            listenable: _c,
            builder: (context, _) => Stack(children: [
              Positioned.fill(
                child: IndexedStack(index: _tab, children: [
                  TalkCallsScreen(key: ValueKey(_callsKey), controller: _c, embedded: true, leading: _backToClub(c), onOpenChat: _openById),
                  _chatsTab(c),
                  _meTab(c),
                ]),
              ),
              // WhatsApp'taki Meta AI halkasının yerinde ARCON AI
              if (_tab == 1 && !_selecting)
                Positioned(
                  right: 18,
                  bottom: barBottom + 64 + 14,
                  child: _AiButton(onTap: _openAi),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: barBottom,
                child: _selecting ? _selectBar(c) : _tabBar(c),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ---------- ortak parçalar ----------

  /// iOS 26 WhatsApp: yarı saydam yuvarlak üst butonlar
  /// ARCON Club içinden açıldıysa (appMode: false) Club'a dönüş butonu
  List<Widget> _backToClub(TalkColors c) => widget.appMode || !Navigator.of(context).canPop()
      ? const []
      : [
          _circle(c, Icon(CupertinoIcons.chevron_left, size: 22, color: c.ink), () => Navigator.of(context).maybePop(), tip: 'Geri'),
          const SizedBox(width: 10),
        ];

  Widget _circle(TalkColors c, Widget child, VoidCallback? onTap, {String? tip, bool solid = false}) => Tooltip(
        message: tip ?? '',
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

  Widget _bigTitle(TalkColors c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Text(t, style: talkText(34, FontWeight.w700, c.ink, letterSpacing: -0.6, height: 1.1)),
      );

  Widget _searchField(TalkColors c, String hint, {TextEditingController? controller, ValueChanged<String>? onChanged, FocusNode? focusNode}) {
    return Container(
      height: 42,
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: c.searchBg, borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        Icon(CupertinoIcons.search, size: 21, color: c.muted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onTapOutside: (_) => focusNode?.unfocus(),
            style: talkText(17, FontWeight.w400, c.ink),
            cursorColor: c.ink,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: hint,
              hintStyle: talkText(17, FontWeight.w400, c.muted),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------- Sohbetler ----------

  Widget _chatsTab(TalkColors c) {
    final top = MediaQuery.paddingOf(context).top;
    final list = _c.visible;
    final archived = _c.archivedChannels;
    final q = _c.query.trim();
    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: top + 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _selecting
            ? SizedBox(
                height: 44,
                child: Row(children: [
                  TextButton(onPressed: _endSelect, child: Text('Vazgeç', style: talkText(17, FontWeight.w500, c.ink))),
                  Expanded(
                    child: Text(_sel.isEmpty ? 'Sohbet seç' : '${_sel.length} seçildi',
                        textAlign: TextAlign.center, style: talkText(17, FontWeight.w600, c.ink)),
                  ),
                  const SizedBox(width: 72),
                ]),
              )
            : Row(children: [
                ..._backToClub(c),
                PopupMenuButton<String>(
                  tooltip: 'Diğer',
                  color: c.popBg,
                  offset: const Offset(0, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onSelected: (v) async {
                    switch (v) {
                      case 'select':
                        setState(() => _selecting = true);
                      case 'read':
                        await _readAll();
                    }
                  },
                  itemBuilder: (_) => [
                    for (final (v, t, i) in [
                      ('select', 'Sohbet seç', CupertinoIcons.checkmark_circle),
                      ('read', 'Tümü okundu', CupertinoIcons.text_bubble),
                    ])
                      PopupMenuItem(
                        value: v,
                        child: Row(children: [
                          Icon(i, size: 22, color: c.ink),
                          const SizedBox(width: 14),
                          Text(t, style: talkText(17, FontWeight.w400, c.ink)),
                        ]),
                      ),
                  ],
                  child: IgnorePointer(child: _circle(c, Icon(Icons.more_horiz, size: 24, color: c.ink), () {})),
                ),
                const Spacer(),
                _circle(c, Icon(CupertinoIcons.camera_fill, size: 22, color: c.ink), _camera, tip: 'Kamera'),
                const SizedBox(width: 10),
                _circle(c, Icon(Icons.add, size: 26, color: c.accentContrast), _newChat, tip: 'Yeni sohbet', solid: true),
              ]),
      ),
      _bigTitle(c, 'Sohbetler'),
      _searchField(c, "ARCON AI'a sor veya ara", controller: _search, onChanged: _c.setQuery, focusNode: _searchFocus),
      _filters(c),
      if (q.isNotEmpty) _askAiRow(c, q),
      if (_c.locked.isNotEmpty && q.isEmpty) _lockedRow(c),
      if (archived.isNotEmpty && q.isEmpty) _archivedRow(c, archived),
    ]);

    Widget body;
    if (_c.loading && _c.channels.isEmpty) {
      body = const SliverToBoxAdapter(child: SkeletonList(count: 9, leadingSize: 50, padding: EdgeInsets.symmetric(horizontal: 16)));
    } else if (_c.error != null && _c.channels.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: GestureDetector(
            onTap: _c.refresh,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${_c.error}\nTekrar denemek için dokun', textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
            ),
          ),
        ),
      );
    } else if (list.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(q.isNotEmpty ? 'Sonuç yok' : (_c.filter == TalkFilter.all ? 'Sohbet yok' : 'Bu filtrede sohbet yok'),
              style: talkText(15, FontWeight.w400, c.muted)),
        ),
      );
    } else {
      body = SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => _row(list[i]));
    }

    return RefreshIndicator.adaptive(
      onRefresh: _c.refresh,
      edgeOffset: top,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(child: header),
          body,
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _row(TalkChannel ch, {VoidCallback? onLongPress}) {
    final selecting = _selecting && onLongPress == null;
    final row = _ChanRow(
      channel: ch,
      photoUrl: _c.api.fileUrl(ch.photo),
      typing: _typingLabel(ch),
      draft: _c.draftOf(ch.id),
      muted: _c.muted.contains(ch.id),
      sender: _senderLabel(ch),
      mineLast: ch.lastUserId != 0 && ch.lastUserId == _c.me?.id,
      selecting: selecting,
      selected: _sel.contains(ch.id),
      onTap: () => selecting ? _toggleSel(ch.id) : _open(ch),
      onLongPress: onLongPress ?? () => _toggleSel(ch.id),
    );
    // WhatsApp iOS: sola kaydır → "Diğer" (gri) ve "Arşivle"; arşiv listesinde ve seçimdeyken yok
    return TalkSwipeActions(
      key: ValueKey('swipe-${ch.id}'),
      enabled: onLongPress == null && !_selecting,
      actions: [
        TalkSwipeAction(icon: Icons.more_horiz, label: 'Diğer', color: const Color(0xFF7C7C80), onTap: () => _moreSheet(ch)),
        TalkSwipeAction(icon: CupertinoIcons.archivebox_fill, label: 'Arşivle', color: const Color(0xFF1C1C1E), onTap: () => _archiveOne(ch)),
      ],
      child: row,
    );
  }

  Future<void> _archiveOne(TalkChannel ch) async {
    await _c.toggleArchive(ch.id);
    if (mounted) talkToast(context, 'Sohbet arşivlendi');
  }

  /// "Diğer": sessize al, favori, okundu, bilgi, sil
  Future<void> _moreSheet(TalkChannel ch) async {
    final muted = _c.muted.contains(ch.id);
    final fav = _c.favourites.contains(ch.id);
    final locked = _c.locked.contains(ch.id);
    final c = TalkColors.of(context);
    final ink = c.dark ? const Color(0xFFF2F2F7) : const Color(0xFF111111);
    final card = c.dark ? const Color(0xFF2C2C2E) : Colors.white;
    final photo = _c.api.fileUrl(ch.photo);
    // WhatsApp iOS "Diğer": başlıkta foto + ad + kapat, beyaz kartta işlemler, altta ayrı kırmızı çıkış
    final items = <(String, IconData, String)>[
      ('mute', muted ? CupertinoIcons.bell : CupertinoIcons.bell_slash, muted ? 'Sesi aç' : 'Sessiz'),
      ('info', CupertinoIcons.info_circle, ch.isDm ? 'Kişi bilgisi' : 'Grup bilgisi'),
      ('lock', CupertinoIcons.lock, locked ? 'Kilidi kaldır' : 'Sohbeti kilitle'),
      ('fav', fav ? CupertinoIcons.heart_fill : CupertinoIcons.heart, fav ? "Favoriler'den çıkar" : "Favoriler'e ekle"),
      ('list', CupertinoIcons.person_crop_rectangle, 'Listeye ekle'),
      if (ch.unread > 0) ('read', CupertinoIcons.chat_bubble_text, 'Okundu olarak işaretle'),
      ('clear', CupertinoIcons.xmark_circle, 'Sohbeti temizle'),
    ];
    Widget row((String, IconData, String) it, BuildContext ctx, {bool last = false, Color? color}) => InkWell(
          onTap: () => Navigator.pop(ctx, it.$1),
          child: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Container(
              height: 58,
              decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
              child: Row(children: [
                Icon(it.$2, size: 24, color: color ?? ink),
                const SizedBox(width: 18),
                Expanded(child: Text(it.$3, style: talkText(17.5, FontWeight.w400, color ?? ink))),
              ]),
            ),
          ),
        );
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (ch.isDm || photo.isNotEmpty)
                TalkAvatar.solid(name: ch.name, photoUrl: photo, size: 42, personIfEmpty: true)
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFEBE9FB), shape: BoxShape.circle),
                  child: Icon(CupertinoIcons.person_2_fill, size: 22, color: c.dark ? const Color(0xFFAEAEB2) : const Color(0xFF5B4FD6)),
                ),
              const SizedBox(width: 14),
              Expanded(child: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17.5, FontWeight.w600, ink))),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: card, shape: BoxShape.circle, border: Border.all(color: c.rowLine)),
                  child: Icon(CupertinoIcons.xmark, size: 19, color: ink),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
              child: Column(children: [for (var i = 0; i < items.length; i++) row(items[i], ctx, last: i == items.length - 1)]),
            ),
            const SizedBox(height: 14),
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
              child: row(
                ch.isDm ? ('delete', CupertinoIcons.trash, 'Sohbeti sil') : ('leave', Icons.logout_rounded, 'Gruptan çık'),
                ctx,
                last: true,
                color: TalkColors.dangerSolid,
              ),
            ),
          ]),
        ),
      ),
    );
    if (!mounted || v == null) return;
    switch (v) {
      case 'mute':
        await _c.toggleMute(ch.id);
      case 'fav':
        await _c.toggleFavourite(ch.id);
      case 'list':
        await showTalkListSheet(context, _c, ch.id);
      case 'lock':
        await _toggleLock(ch);
      case 'read':
        _c.markRead(ch.id);
        unawaited(_c.api.read(ch.id).then((_) {}, onError: (_) {}));
      case 'info':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TalkInfoScreen(controller: _c, channel: ch, session: widget.session, config: widget.config),
        ));
      case 'delete':
        _sel
          ..clear()
          ..add(ch.id);
        await _deleteSelected();
      case 'clear':
        if (!await talkConfirm(context, title: 'Sohbeti temizle', message: 'Bu sohbetteki mesajlar yalnızca senin için silinir.', ok: 'Temizle')) return;
        try {
          await _c.api.clearChat(ch.id);
          if (mounted) talkToast(context, 'Sohbet temizlendi');
          unawaited(_c.refresh(silent: true));
        } on ArconApiException catch (e) {
          if (mounted) talkToast(context, e.message.isEmpty ? 'Temizlenemedi' : e.message, error: true);
        }
      case 'leave':
        if (!await talkConfirm(context, title: 'Gruptan çık', message: '${ch.name} grubundan çıkılsın mı?', ok: 'Çık')) return;
        try {
          await _c.api.leaveChannel(ch.id);
          if (mounted) talkToast(context, 'Gruptan çıkıldı');
          unawaited(_c.refresh(silent: true));
        } on ArconApiException catch (e) {
          if (mounted) talkToast(context, e.message.isEmpty ? 'Çıkılamadı' : e.message, error: true);
        }
    }
  }

  /// Grupta son mesajı yazanın adı: "Siz" / "Ali"
  String _senderLabel(TalkChannel ch) {
    if (ch.isDm || ch.lastUserId == 0) return '';
    if (ch.lastUserId == _c.me?.id) return 'Siz';
    for (final u in _c.users) {
      if (u.id == ch.lastUserId) return talkFirstName(u.displayName);
    }
    return '';
  }

  Widget _askAiRow(TalkColors c, String q) => InkWell(
        onTap: () {
          _openAiWith(q);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F4), shape: BoxShape.circle),
              child: const ArconAiLogo(size: 30),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: "ARCON AI'a sor: ", style: talkText(16, FontWeight.w600, c.ink)),
                  TextSpan(text: '“$q”', style: talkText(16, FontWeight.w400, c.muted)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ),
      );

  Widget _archivedRow(TalkColors c, List<TalkChannel> archived) {
    final unread = archived.where((ch) => ch.unread > 0).length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openArchived,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 10, 20, 0),
        child: Row(children: [
          Icon(CupertinoIcons.archivebox, size: 24, color: c.muted),
          const SizedBox(width: 30),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 12, top: 2),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
              child: Row(children: [
                Expanded(child: Text('Arşivlenmiş', style: talkText(17, FontWeight.w600, c.muted))),
                Text(unread > 0 ? '$unread' : '${archived.length}', style: talkText(15, unread > 0 ? FontWeight.w700 : FontWeight.w400, unread > 0 ? c.ink : c.muted)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _lockedRow(TalkColors c) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openLocked,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 10, 20, 0),
          child: Row(children: [
            Icon(CupertinoIcons.lock, size: 24, color: c.muted),
            const SizedBox(width: 30),
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(bottom: 12, top: 2),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
                child: Row(children: [
                  Expanded(child: Text('Kilitli sohbetler', style: talkText(17, FontWeight.w600, c.muted))),
                  Text('${_c.locked.length}', style: talkText(15, FontWeight.w400, c.muted)),
                ]),
              ),
            ),
          ]),
        ),
      );

  /// Filtre çipleri: Tümü / Okunmamış / Favoriler / Gruplar
  Widget _filters(TalkColors c) {
    final unreadChats = _c.channels.where((ch) => ch.unread > 0 && !_c.archived.contains(ch.id)).length;
    Widget chip(String label, TalkFilter? f, {String? list, VoidCallback? onTap, VoidCallback? onLongPress}) {
      final on = list != null ? _c.listFilter == list : (f != null && _c.listFilter == null && _c.filter == f);
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: onTap ?? () => list != null ? _c.setListFilter(on ? null : list) : _c.setFilter(f!),
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: on ? c.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? c.userBtnBorder : c.searchBorder),
            ),
            child: Text(label, style: talkText(15, on ? FontWeight.w600 : FontWeight.w500, on ? c.userBtnInk : c.muted)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
        children: [
          chip('Tümü', TalkFilter.all),
          chip(unreadChats > 0 ? 'Okunmamış $unreadChats' : 'Okunmamış', TalkFilter.unread),
          chip('Favoriler', TalkFilter.favourites),
          chip('Gruplar', TalkFilter.groups),
          // kullanıcının listeleri (basılı tut: listeyi sil)
          for (final n in (_c.lists.keys.toList()..sort())) chip(n, null, list: n, onLongPress: () => _deleteList(n)),
          chip('+', null, onTap: _newList),
        ],
      ),
    );
  }

  Future<void> _newList() async {
    final n = await askTalkListName(context);
    if (n == null || !mounted) return;
    await _c.createList(n);
    _c.setListFilter(n);
    if (mounted) talkToast(context, '"$n" listesi oluşturuldu. Sohbeti sola kaydırıp Diğer › Listeye ekle.');
  }

  Future<void> _deleteList(String n) async {
    final ok = await talkConfirm(context, title: '"$n" listesi silinsin mi?', message: 'Sohbetler silinmez, yalnızca liste kalkar.', ok: 'Sil');
    if (ok) await _c.deleteList(n);
  }

  String _typingLabel(TalkChannel ch) {
    final list = _c.typingOf(ch.id);
    if (list.isEmpty) return '';
    if (list.length == 1) return '${talkFirstName(list.first.displayName)} yazıyor…';
    return 'yazıyor…';
  }

  // ---------- alt menü ----------

  /// iOS 26 WhatsApp: yüzen, buzlu cam kapsül
  Widget _glass(TalkColors c, Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.dark ? const Color(0xD91C1C1E) : const Color(0xE6FFFFFF),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: c.dark ? const Color(0x1FFFFFFF) : const Color(0x14000000)),
            ),
            child: child,
          ),
        ),
      );

  Widget _tabBar(TalkColors c) {
    final unreadChats = _c.channels.where((ch) => ch.unread > 0 && !_c.archived.contains(ch.id)).length;
    final me = _c.me;
    Widget item(int i, String label, Widget icon) {
      final on = _tab == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (i == 0 && _tab != 0) _callsKey++; // sekmeye her gelişte aramaları tazele
            _tab = i;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(color: on ? c.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(30)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              icon,
              const SizedBox(height: 2),
              Text(label, style: talkText(11.5, on ? FontWeight.w700 : FontWeight.w500, c.ink)),
            ]),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      child: _glass(
        c,
        Row(children: [
          item(0, 'Aramalar', Icon(_tab == 0 ? CupertinoIcons.phone_fill : CupertinoIcons.phone, size: 25, color: c.ink)),
          item(
            1,
            'Sohbetler',
            Badge(
              isLabelVisible: unreadChats > 0,
              backgroundColor: c.accent,
              textColor: c.accentContrast,
              label: Text('$unreadChats'),
              child: _tab == 1
                  ? Icon(CupertinoIcons.chat_bubble_2_fill, size: 27, color: c.ink)
                  : TalkIcon(TalkSvg.chats, size: 27, color: c.ink),
            ),
          ),
          item(
            2,
            'Siz',
            Container(
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _tab == 2 ? c.ink : Colors.transparent, width: 1.5)),
              child: TalkAvatar.solid(name: me?.displayName ?? '', photoUrl: _c.api.fileUrl(me?.avatarPath ?? ''), size: 24, personIfEmpty: true),
            ),
          ),
        ]),
      ),
    );
  }

  /// Seçim modunda alt menünün yerine: favori, sessiz, arşivle, sil
  Widget _selectBar(TalkColors c) {
    final any = _sel.isNotEmpty;
    Widget act(IconData i, String label, VoidCallback onTap, {Color? color}) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: any ? onTap : null,
            child: Opacity(
              opacity: any ? 1 : 0.35,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(i, size: 23, color: color ?? c.ink),
                const SizedBox(height: 2),
                Text(label, style: talkText(11.5, FontWeight.w500, color ?? c.ink)),
              ]),
            ),
          ),
        );
    return _glass(
      c,
      Row(children: [
        act(CupertinoIcons.star, 'Favori', () => _applySelected(_c.favourites, _c.toggleFavourite)),
        act(CupertinoIcons.bell_slash, 'Sessiz', () => _applySelected(_c.muted, _c.toggleMute)),
        act(CupertinoIcons.archivebox, 'Arşivle', () => _applySelected(_c.archived, _c.toggleArchive)),
        act(CupertinoIcons.delete, 'Sil', _deleteSelected, color: TalkColors.danger),
      ]),
    );
  }

  // ---------- Siz ----------

  /// Bildirim teşhisi: telefonun Firebase durumu + sunucudan bu hesabın cihazlarına deneme bildirimi.
  Future<void> _pushTest() async {
    talkToast(context, 'Bildirim testi gönderiliyor…');
    await PushService.reRegister();
    final lines = <String>[
      'Bildirim: ${PushService.enabled ? 'açık' : 'KAPALI (uygulama ayarı)'}',
      'Firebase token: ${PushService.lastToken == null ? 'YOK' : '${PushService.lastToken!.substring(0, 10)}…'}',
      if (PushService.lastError.isNotEmpty) 'Telefon hatası: ${PushService.lastError}',
    ];
    try {
      final j = await widget.session.api.pushTest();
      lines
        ..add('')
        ..add('Sunucu bildirimi: ${j['push_enabled'] == true ? 'açık' : 'KAPALI'} · ${j['project'] ?? ''}${j['access_token'] == true ? '' : ' · Google anahtarı alınamadı'}')
        ..add('Kullanıcı: ${j['user_id']}');
      final devs = (j['devices'] as List?) ?? const [];
      if (devs.isEmpty) lines.add('Bu hesaba kayıtlı cihaz YOK');
      for (final d in devs.whereType<Map>()) {
        lines.add('• ${d['platform']} ${d['app']} ${d['version']}${d['this_device'] == true ? ' (bu telefon)' : ''}${d['session_live'] == true ? '' : ' · oturum kapalı'} → ${d['result']}');
      }
    } catch (e) {
      lines
        ..add('')
        ..add('Sunucu: $e');
    }
    if (!mounted) return;
    final text = lines.join('\n');
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Bildirim testi'),
        content: Padding(padding: const EdgeInsets.only(top: 8), child: Text(text, textAlign: TextAlign.left)),
        actions: [
          CupertinoDialogAction(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
            },
            child: const Text('Kopyala'),
          ),
          CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
    );
  }

  Widget _meTab(TalkColors c) {
    final me = _c.me;
    final name = (me?.displayName ?? '').trim().isNotEmpty ? me!.displayName : (widget.session.user?.username ?? '');
    final username = me?.username ?? widget.session.user?.username ?? '';
    final theme = ArconThemeScope.of(context);
    final dark = theme.isDark(context);
    final top = MediaQuery.paddingOf(context).top;
    Widget row(IconData i, String title, {Color? color, VoidCallback? onTap, Widget? trailing, bool last = false}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(children: [
              Icon(i, size: 23, color: color ?? c.ink),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
                  child: Row(children: [
                    Expanded(child: Text(title, style: talkText(17, FontWeight.w400, color ?? c.ink))),
                    trailing ?? Icon(CupertinoIcons.chevron_right, size: 17, color: c.muted),
                  ]),
                ),
              ),
            ]),
          ),
        );
    Widget card(List<Widget> rows) => Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.infoCard, borderRadius: BorderRadius.circular(22)),
          child: Column(children: rows),
        );
    return ListView(padding: EdgeInsets.fromLTRB(0, top + 6, 0, 130), children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          ..._backToClub(c),
          _circle(c, const ArconAiLogo(size: 30), _openAi, tip: 'ARCON AI'),
          const Spacer(),
          _circle(c, Icon(CupertinoIcons.pencil, size: 22, color: c.ink), _openProfile, tip: 'Profili düzenle'),
        ]),
      ),
      const SizedBox(height: 18),
      Center(
        child: GestureDetector(
          onTap: _openProfile,
          child: TalkAvatar.solid(name: name, photoUrl: _c.api.fileUrl(me?.avatarPath ?? ''), size: 104, personIfEmpty: true),
        ),
      ),
      const SizedBox(height: 14),
      Text(name, textAlign: TextAlign.center, style: talkText(28, FontWeight.w700, c.ink, letterSpacing: -0.4)),
      if (username.isNotEmpty) Text('@$username', textAlign: TextAlign.center, style: talkText(17, FontWeight.w400, c.muted)),
      if ((me?.about ?? '').trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
          child: Text(me!.about, textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
        ),
      const SizedBox(height: 26),
      card([
        row(CupertinoIcons.person_crop_circle, 'Profil', onTap: _openProfile),
        row(CupertinoIcons.star, 'Favoriler', onTap: () {
          _c.setFilter(TalkFilter.favourites);
          setState(() => _tab = 1);
        }),
        row(CupertinoIcons.archivebox, 'Arşivlenmiş', onTap: _openArchived,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_c.archived.isNotEmpty) Text('${_c.archived.length}  ', style: talkText(16, FontWeight.w400, c.muted)),
              Icon(CupertinoIcons.chevron_right, size: 17, color: c.muted),
            ])),
        row(CupertinoIcons.sparkles, 'ARCON AI', onTap: _openAi, last: true),
      ]),
      card([
        row(CupertinoIcons.moon, 'Koyu tema',
            onTap: () => theme.toggle(context),
            trailing: CupertinoSwitch(value: dark, activeTrackColor: c.dark ? const Color(0xFF636366) : const Color(0xFF111111), onChanged: (_) => theme.toggle(context))),
        row(CupertinoIcons.bell, 'Bildirim testi', onTap: _pushTest),
        row(CupertinoIcons.bell_slash, 'Sessize alınanlar',
            last: true,
            trailing: Text('${_c.muted.length}', style: talkText(16, FontWeight.w400, c.muted)),
            onTap: () => talkToast(context, _c.muted.isEmpty ? 'Sessize alınmış sohbet yok' : 'Bir sohbete basılı tutup “Sessiz” ile aç/kapat')),
      ]),
      card([
        row(Icons.logout, 'Çıkış yap', color: TalkColors.danger, last: true, trailing: const SizedBox.shrink(), onTap: () async {
          if (await talkConfirm(context, title: 'Çıkış yapılsın mı?', message: 'Bu telefondan oturumun kapanır.', ok: 'Çıkış yap')) {
            widget.session.logout();
          }
        }),
      ]),
    ]);
  }
}

/// Sağ altta yüzen ARCON AI düğmesi (WhatsApp'taki Meta AI halkası yerine)
class _AiButton extends StatelessWidget {
  const _AiButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    return Tooltip(
      message: 'ARCON AI',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.dark ? const Color(0xFF1C1C1E) : Colors.white,
            border: Border.all(color: c.dark ? const Color(0x26FFFFFF) : const Color(0x0F000000)),
            boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: const ArconAiLogo(size: 40),
        ),
      ),
    );
  }
}

class _ArchivedPage extends StatelessWidget {
  const _ArchivedPage({required this.controller, required this.onOpen, required this.onUnarchive, this.locked = false});

  final TalkController controller;

  /// true: "Kilitli sohbetler" (aynı görünüm, kilit açma işlemi)
  final bool locked;
  final Future<void> Function(TalkChannel ch) onOpen;
  final Future<void> Function(TalkChannel ch) onUnarchive;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = TalkColors.of(context);
        final list = locked ? controller.lockedChannels : controller.archivedChannels;
        return Scaffold(
          backgroundColor: c.rail,
          appBar: AppBar(
            backgroundColor: c.rail,
            foregroundColor: c.ink,
            title: Text(locked ? 'Kilitli sohbetler' : 'Arşivlenmiş', style: talkText(17, FontWeight.w600, c.ink)),
            centerTitle: true,
          ),
          body: list.isEmpty
              ? Center(child: Text(locked ? 'Kilitli sohbet yok' : 'Arşivlenmiş sohbet yok', style: talkText(15, FontWeight.w400, c.muted)))
              : ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                      child: Text(
                          locked
                              ? 'Bu sohbetler yalnızca bu telefonda kilitli ve ana listede görünmez. Kilidi açmak için sohbete basılı tut.'
                              : 'Bu sohbetler arşivde kalır. Çıkarmak için sohbete basılı tut.',
                          textAlign: TextAlign.center, style: talkText(13, FontWeight.w400, c.muted)),
                    ),
                    for (final ch in list)
                      _ChanRow(
                        channel: ch,
                        photoUrl: controller.api.fileUrl(ch.photo),
                        typing: '',
                        draft: controller.draftOf(ch.id),
                        muted: controller.muted.contains(ch.id),
                        sender: _sender(ch),
                        mineLast: ch.lastUserId != 0 && ch.lastUserId == controller.me?.id,
                        selecting: false,
                        selected: false,
                        onTap: () => onOpen(ch),
                        onLongPress: () => _unarchive(context, ch),
                      ),
                  ],
                ),
        );
      },
    );
  }

  String _sender(TalkChannel ch) {
    if (ch.isDm || ch.lastUserId == 0) return '';
    if (ch.lastUserId == controller.me?.id) return 'Siz';
    for (final u in controller.users) {
      if (u.id == ch.lastUserId) return talkFirstName(u.displayName);
    }
    return '';
  }

  Future<void> _unarchive(BuildContext context, TalkChannel ch) async {
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(ch.name),
        actions: [CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, true), child: Text(locked ? 'Kilidi aç' : 'Arşivden çıkar'))],
        cancelButton: CupertinoActionSheetAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (ok == true) await onUnarchive(ch);
  }
}

/// WhatsApp iOS sohbet satırı: avatar, ad + saat, iki satır önizleme (tik / "Siz:"), sessiz ve okunmamış rozeti
class _ChanRow extends StatelessWidget {
  const _ChanRow({
    required this.channel,
    required this.photoUrl,
    required this.typing,
    required this.draft,
    required this.muted,
    required this.sender,
    required this.mineLast,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final TalkChannel channel;
  final String photoUrl;
  final String typing;
  final String draft;
  final bool muted;
  final String sender;
  final bool mineLast;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final unread = channel.unread > 0;
    final call = talkCallLine(channel.lastBody);
    final event = call == null ? talkEventLine(channel.lastBody) : null;
    final preview = call != null
        ? channel.lastBody.replaceFirst(RegExp(r'^(📞|🎥)\s*'), '')
        : event != null
            ? '${event.title} · ${talkEventWhen(event.at)}'
            : talkLocationLine(channel.lastBody) != null
                ? 'Konum'
                : talkPollLine(channel.lastBody) != null
                    ? 'Anket: ${talkPollLine(channel.lastBody)!.question}'
                    : channel.preview;
    final previewStyle = talkText(15, FontWeight.w400, c.muted, height: 1.33);

    final InlineSpan lead;
    if (typing.isNotEmpty) {
      lead = TextSpan(text: typing, style: previewStyle.copyWith(color: c.ink, fontStyle: FontStyle.italic));
    } else if (draft.trim().isNotEmpty) {
      lead = TextSpan(children: [
        TextSpan(text: 'Taslak: ', style: previewStyle.copyWith(color: TalkColors.danger)),
        TextSpan(text: draft.trim().replaceAll('\n', ' ')),
      ]);
    } else {
      lead = TextSpan(children: [
        if (sender.isNotEmpty) TextSpan(text: '$sender: ', style: previewStyle.copyWith(color: c.unreadPreview)),
        // kendi son mesajında WhatsApp tiki: herkes okuduysa mavi
        if (mineLast && call == null)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TalkIcon(TalkSvg.ticks, width: 18, height: 12, color: channel.lastReadAll ? TalkColors.ticks : c.muted),
            ),
          ),
        if (call != null)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(call.video ? CupertinoIcons.video_camera_solid : CupertinoIcons.phone_fill,
                  size: 16, color: call.missed && !mineLast ? TalkColors.danger : c.muted),
            ),
          ),
        TextSpan(text: preview.replaceAll('\n', ' ')),
      ]);
    }

    return Material(
      color: selected ? c.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              child: selecting
                  ? Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                          size: 24, color: selected ? c.accent : c.muted),
                    )
                  : const SizedBox.shrink(),
            ),
            _avatar(c),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 11, 16, 11),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w600, c.ink, height: 1.3)),
                    ),
                    const SizedBox(width: 8),
                    Text(talkListTime(channel.lastAt), style: talkText(14.5, unread ? FontWeight.w600 : FontWeight.w400, unread ? c.ink : c.muted)),
                  ]),
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text.rich(lead, maxLines: 2, overflow: TextOverflow.ellipsis, style: previewStyle)),
                    if (muted) ...[
                      const SizedBox(width: 6),
                      Padding(padding: const EdgeInsets.only(top: 2), child: Icon(CupertinoIcons.bell_slash_fill, size: 15, color: c.muted)),
                    ],
                    if (unread) ...[
                      const SizedBox(width: 6),
                      Container(
                        margin: const EdgeInsets.only(top: 1),
                        constraints: const BoxConstraints(minWidth: 21),
                        height: 21,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: muted ? c.muted : c.accent, borderRadius: BorderRadius.circular(999)),
                        child: Text(channel.unread > 99 ? '99+' : '${channel.unread}', style: talkText(12.5, FontWeight.w600, c.accentContrast)),
                      ),
                    ],
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Foto yoksa: kişide gri insan, grupta açık mor zeminli grup ikonu (WhatsApp iOS)
  Widget _avatar(TalkColors c) {
    if (channel.isDm || photoUrl.isNotEmpty) {
      return TalkAvatar.solid(name: channel.name, photoUrl: photoUrl, size: 56, personIfEmpty: true);
    }
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFEBEBEF), shape: BoxShape.circle),
      child: Icon(CupertinoIcons.person_2_fill, size: 30, color: c.dark ? const Color(0xFFAEAEB2) : const Color(0xFF6E6E73)),
    );
  }
}
