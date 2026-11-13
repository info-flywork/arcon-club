import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import 'talk_controller.dart';
import 'talk_events.dart';
import 'talk_models.dart';
import 'talk_pickers.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// WhatsApp iOS "Yeni sohbet": Yeni grup / kişi / toplu mesaj / etkinlik, sık görüşülenler,
/// kişiler (A–Z bölümleri ve sağda harf dizini). Açılan sohbetin id'sini döner.
class TalkNewChatScreen extends StatefulWidget {
  const TalkNewChatScreen({super.key, required this.controller});
  final TalkController controller;

  @override
  State<TalkNewChatScreen> createState() => _TalkNewChatScreenState();
}

class _TalkNewChatScreenState extends State<TalkNewChatScreen> {
  int _busy = 0;

  TalkController get _c => widget.controller;

  Future<void> _openDm(TalkUser u) async {
    if (_busy != 0) return;
    setState(() => _busy = u.id);
    try {
      final ch = await _c.api.openDm(u.id);
      if (ch != null) _c.upsertChannel(ch);
      if (mounted) Navigator.pop(context, ch?.id);
    } on ArconApiException catch (e) {
      if (mounted) {
        talkToast(context, e.message.isEmpty ? 'Sohbet açılamadı' : e.message, error: true);
        setState(() => _busy = 0);
      }
    }
  }

  Future<void> _newGroup() async {
    final id = await showNewGroupSheet(context, _c);
    if (mounted && id != null && id > 0) Navigator.pop(context, id);
  }

  /// Hesaplar şirket yönetiminden açılır; burada ARCONNECT bağlantısı paylaşılır
  Future<void> _newPerson() async {
    final link = _c.api.fileUrl('arconnect');
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(ShareParams(
        text: "ARCONNECT'te benimle yazış: $link",
        subject: 'ARCONNECT daveti',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    } on Exception {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) talkToast(context, 'Davet bağlantısı kopyalandı');
    }
  }

  Future<void> _broadcast() async {
    final n = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => TalkBroadcastScreen(controller: _c)));
    if (mounted && n != null && n > 0) {
      talkToast(context, '$n kişiye gönderildi');
      Navigator.pop(context);
    }
  }

  /// Etkinlik: ad + zaman → sohbet seç → sohbete etkinlik kartı
  Future<void> _event() async {
    final e = await showTalkEventSheet(context, call: false);
    if (e == null || !mounted) return;
    final ch = await Navigator.of(context).push<TalkChannel>(MaterialPageRoute(builder: (_) => TalkChatPickerScreen(controller: _c, title: 'Etkinliği paylaş')));
    if (ch == null || !mounted) return;
    try {
      await _c.api.sendMessage(channelId: ch.id, body: talkEventBody(e.title, e.at));
      if (mounted) Navigator.pop(context, ch.id);
    } on ArconApiException catch (err) {
      if (mounted) talkToast(context, err.message.isEmpty ? 'Etkinlik gönderilemedi' : err.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => _PeopleList(
        controller: _c,
        title: 'Yeni sohbet',
        busyId: _busy,
        onPick: _openDm,
        showMe: true,
        frequent: true,
        onPickChannel: (ch) => Navigator.pop(context, ch.id),
        actions: [
          (CupertinoIcons.person_2, 'Yeni grup', _newGroup),
          (CupertinoIcons.person_badge_plus, 'Yeni kişi', _newPerson),
          (CupertinoIcons.chat_bubble_text, 'Yeni toplu mesaj', _broadcast),
          (CupertinoIcons.calendar, 'Yeni etkinlik', _event),
        ],
      );
}

/// Kişi seç (arama için): seçilen kişiyi döner.
class TalkUserPickerScreen extends StatelessWidget {
  const TalkUserPickerScreen({super.key, required this.controller, required this.title, this.favouritesOnly = false});
  final TalkController controller;
  final String title;

  /// Yalnızca favorilere eklenmiş birebir sohbetlerdeki kişiler
  final bool favouritesOnly;

  @override
  Widget build(BuildContext context) {
    Set<int>? only;
    if (favouritesOnly) {
      only = {
        for (final ch in controller.channels)
          if (ch.isDm && ch.peer != null && controller.favourites.contains(ch.id)) ch.peer!.id,
      };
    }
    return _PeopleList(
      controller: controller,
      title: title,
      only: only,
      emptyText: favouritesOnly ? 'Favori kişi yok.\nSohbetler listesinde bir sohbeti sola kaydırıp “Diğer” › “Favorilere ekle”yi seç.' : null,
      onPick: (u) => Navigator.pop(context, u),
    );
  }
}

/// WhatsApp "Yeni toplu mesaj": kişileri seç, mesajı yaz; her kişiye ayrı birebir mesaj gider.
/// Gönderilen kişi sayısını döner.
class TalkBroadcastScreen extends StatefulWidget {
  const TalkBroadcastScreen({super.key, required this.controller});
  final TalkController controller;

  @override
  State<TalkBroadcastScreen> createState() => _TalkBroadcastScreenState();
}

class _TalkBroadcastScreenState extends State<TalkBroadcastScreen> {
  final _picked = <int>{};
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (_picked.isEmpty || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    var sent = 0;
    for (final id in _picked.toList()) {
      try {
        final ch = await widget.controller.api.openDm(id);
        if (ch == null) continue;
        widget.controller.upsertChannel(ch);
        await widget.controller.api.sendMessage(channelId: ch.id, body: body);
        sent++;
      } on ArconApiException {
        // gönderilemeyen kişi atlanır; sayı eksik döner
      }
    }
    if (!mounted) return;
    if (sent == 0) {
      setState(() => _sending = false);
      talkToast(context, 'Mesaj gönderilemedi', error: true);
      return;
    }
    Navigator.pop(context, sent);
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ready = _picked.isNotEmpty && _text.text.trim().isNotEmpty && !_sending;
    return _PeopleList(
      controller: widget.controller,
      title: 'Yeni toplu mesaj',
      selected: _picked,
      onPick: (u) => setState(() => _picked.contains(u.id) ? _picked.remove(u.id) : _picked.add(u.id)),
      bottom: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(color: _cardBg(c), border: Border(top: BorderSide(color: c.rowLine, width: 0.6))),
          child: Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: c.searchBg, borderRadius: BorderRadius.circular(20)),
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  style: talkText(16, FontWeight.w400, c.ink),
                  cursorColor: c.ink,
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: _picked.isEmpty ? 'Önce kişi seç' : '${_picked.length} kişiye mesaj',
                    hintStyle: talkText(16, FontWeight.w400, c.muted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Gönder',
              child: GestureDetector(
                onTap: ready ? _send : null,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: ready ? c.accent : c.searchBg, shape: BoxShape.circle),
                  child: _sending
                      ? CupertinoActivityIndicator(color: c.accentContrast)
                      : Icon(CupertinoIcons.arrow_up, size: 20, color: ready ? c.accentContrast : c.muted),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Sohbet seç (kameradan çekilen fotoğrafı / etkinliği göndermek için): seçilen sohbeti döner.
class TalkChatPickerScreen extends StatefulWidget {
  const TalkChatPickerScreen({super.key, required this.controller, this.title = 'Gönder…'});
  final TalkController controller;
  final String title;

  @override
  State<TalkChatPickerScreen> createState() => _TalkChatPickerScreenState();
}

class _TalkChatPickerScreenState extends State<TalkChatPickerScreen> {
  String _q = '';
  int _busy = 0;

  /// Kişi seçildi: sohbeti yoksa birebir sohbet açılır (kendine ilet dahil)
  Future<void> _openUser(TalkUser u) async {
    if (_busy != 0) return;
    setState(() => _busy = u.id);
    try {
      final ch = await widget.controller.api.openDm(u.id);
      if (ch != null) widget.controller.upsertChannel(ch);
      if (mounted) Navigator.pop(context, ch);
    } on ArconApiException catch (e) {
      if (mounted) {
        talkToast(context, e.message.isEmpty ? 'Sohbet açılamadı' : e.message, error: true);
        setState(() => _busy = 0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ctl = widget.controller;
    final q = _q.trim().toLowerCase();
    final me = ctl.me;
    final showMe = me != null && (q.isEmpty || '${me.displayName} ${me.username} siz'.toLowerCase().contains(q));
    final people = ctl.users
        .where((u) => u.id != me?.id && (q.isEmpty || '${u.displayName} ${u.username} ${u.department}'.toLowerCase().contains(q)))
        .toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    final groups = ctl.channels.where((ch) => ch.isGroup && (q.isEmpty || ch.name.toLowerCase().contains(q))).toList();
    Widget? busy(int id) => _busy == id ? CupertinoActivityIndicator(color: c.muted) : null;
    return Scaffold(
      backgroundColor: _groupedBg(c),
      appBar: _sheetBar(context, c, widget.title),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _SearchBox(hint: 'Kişi veya grup ara', onChanged: (v) => setState(() => _q = v)),
        if (showMe)
          _card(c, [
            _Row(
              avatar: TalkAvatar.solid(name: me.displayName, photoUrl: ctl.api.fileUrl(me.avatarPath), size: 40, personIfEmpty: true),
              title: '${me.displayName} (Siz)',
              subtitle: 'Kendinize mesaj gönderin',
              trailing: busy(me.id),
              onTap: () => _openUser(me),
            ),
          ]),
        if (people.isNotEmpty) ...[
          _sectionTitle(c, 'Kişiler'),
          _card(c, [
            for (final u in people)
              _Row(
                avatar: TalkAvatar.solid(name: u.displayName, photoUrl: ctl.api.fileUrl(u.avatarPath), size: 40, personIfEmpty: true),
                title: u.displayName,
                subtitle: u.department.trim().isNotEmpty ? u.department : '@${u.username}',
                trailing: busy(u.id),
                onTap: () => _openUser(u),
              ),
          ]),
        ],
        if (groups.isNotEmpty) ...[
          _sectionTitle(c, 'Gruplar'),
          _card(c, [
            for (final ch in groups)
              _Row(avatar: _chanAvatar(ctl, ch, c), title: ch.name, subtitle: '${ch.memberCount} üye', onTap: () => Navigator.pop(context, ch)),
          ]),
        ],
        if (!showMe && people.isEmpty && groups.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(q.isEmpty ? 'Kişi yok' : 'Sonuç yok', textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
          ),
      ]),
    );
  }
}

// ---------- ortak parçalar ----------

Color _groupedBg(TalkColors c) => c.dark ? Colors.black : const Color(0xFFF2F2F7);
Color _cardBg(TalkColors c) => c.dark ? const Color(0xFF1C1C1E) : Colors.white;

PreferredSizeWidget _sheetBar(BuildContext context, TalkColors c, String title, {String? subtitle}) => AppBar(
      backgroundColor: _groupedBg(c),
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      automaticallyImplyLeading: false,
      centerTitle: true,
      title: Column(children: [
        Text(title, style: talkText(17, FontWeight.w600, c.ink)),
        if (subtitle != null) Text(subtitle, style: talkText(12.5, FontWeight.w400, c.muted)),
      ]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Tooltip(
            message: 'Kapat',
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: _cardBg(c), shape: BoxShape.circle, border: Border.all(color: c.rowLine)),
                child: Icon(Icons.close, size: 20, color: c.ink),
              ),
            ),
          ),
        ),
      ],
    );

Widget _groupAvatar(TalkColors c, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFEBEBEF), shape: BoxShape.circle),
      child: Icon(CupertinoIcons.person_2_fill, size: size * 0.52, color: c.dark ? const Color(0xFFAEAEB2) : const Color(0xFF6E6E73)),
    );

Widget _chanAvatar(TalkController ctl, TalkChannel ch, TalkColors c) => ch.isDm || ch.photo.isNotEmpty
    ? TalkAvatar.solid(name: ch.name, photoUrl: ctl.api.fileUrl(ch.photo), size: 40, personIfEmpty: true)
    : _groupAvatar(c, 40);

/// Beyaz yuvarlak köşeli kart; son satırın alt çizgisi yok
Widget _card(TalkColors c, List<_Row> rows) {
  if (rows.isEmpty) return const SizedBox.shrink();
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: _cardBg(c), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      for (var i = 0; i < rows.length; i++) rows[i].copyWithLast(i == rows.length - 1),
    ]),
  );
}

Widget _sectionTitle(TalkColors c, String t, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 8),
      child: Text(t, style: talkText(15, FontWeight.w600, c.muted)),
    );

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: _cardBg(c), borderRadius: BorderRadius.circular(999), border: Border.all(color: c.rowLine)),
      child: Row(children: [
        Icon(CupertinoIcons.search, size: 20, color: c.ink),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            onChanged: onChanged,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: talkText(17, FontWeight.w400, c.ink),
            cursorColor: c.ink,
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
}

class _Row extends StatelessWidget {
  const _Row({required this.avatar, required this.title, this.subtitle = '', required this.onTap, this.trailing, this.last = false});
  final Widget avatar;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool last;

  _Row copyWithLast(bool last) => _Row(avatar: avatar, title: title, subtitle: subtitle, onTap: onTap, trailing: trailing, last: last);

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.fromLTRB(0, 8, 16, 8),
              decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w400, c.ink)),
                    if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(14, FontWeight.w400, c.muted)),
                  ]),
                ),
                ?trailing,
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Sağdaki harf dizini sırası (Türkçe alfabe)
const _alphabet = ['A', 'B', 'C', 'Ç', 'D', 'E', 'F', 'G', 'H', 'I', 'İ', 'J', 'K', 'L', 'M', 'N', 'O', 'Ö', 'P', 'R', 'S', 'Ş', 'T', 'U', 'Ü', 'V', 'Y', 'Z', '#'];

String _letterOf(String name) {
  final t = name.trim();
  if (t.isEmpty) return '#';
  final ch = t.substring(0, 1);
  final up = switch (ch) { 'i' => 'İ', 'ı' => 'I', _ => ch.toUpperCase() };
  return _alphabet.contains(up) ? up : '#';
}

int _alphaIndex(String l) {
  final i = _alphabet.indexOf(l);
  return i < 0 ? _alphabet.length : i;
}

class _PeopleList extends StatefulWidget {
  const _PeopleList({
    required this.controller,
    required this.title,
    required this.onPick,
    this.actions = const [],
    this.only,
    this.busyId = 0,
    this.emptyText,
    this.showMe = false,
    this.frequent = false,
    this.onPickChannel,
    this.selected,
    this.bottom,
  });
  final TalkController controller;
  final String title;
  final void Function(TalkUser u) onPick;
  final List<(IconData, String, VoidCallback)> actions;
  final Set<int>? only;
  final int busyId;
  final String? emptyText;

  /// WhatsApp gibi kişilerin başında "Ad (Siz) · Kendinize mesaj gönderin"
  final bool showMe;

  /// "Sık görüşülenler": son yazışılan sohbetler
  final bool frequent;
  final void Function(TalkChannel ch)? onPickChannel;

  /// Çoklu seçim (toplu mesaj): doluysa satırlarda seçim dairesi
  final Set<int>? selected;
  final Widget? bottom;

  @override
  State<_PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends State<_PeopleList> {
  String _q = '';
  final _sections = <String, GlobalKey>{};

  void _jump(String letter) {
    // dokunulan harfte kimse yoksa sonraki ilk bölüm
    final keys = _sections.keys.toList()..sort((a, b) => _alphaIndex(a).compareTo(_alphaIndex(b)));
    final target = keys.where((k) => _alphaIndex(k) >= _alphaIndex(letter)).firstOrNull ?? keys.lastOrNull;
    final ctx = target == null ? null : _sections[target]?.currentContext;
    if (ctx != null) {
      HapticFeedback.selectionClick();
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 120));
    }
  }

  Widget _check(TalkColors c, bool on) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: on ? c.accent : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: on ? c.accent : c.muted, width: 1.5),
        ),
        child: on ? Icon(Icons.check, size: 16, color: c.accentContrast) : null,
      );

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ctl = widget.controller;
    final meUser = ctl.me;
    final me = meUser?.id;
    final q = _q.trim().toLowerCase();
    final showMe =
        widget.showMe && meUser != null && (q.isEmpty || '${meUser.displayName} ${meUser.username} siz'.toLowerCase().contains(q));
    final people = ctl.users
        .where((u) => u.id != me && (widget.only == null || widget.only!.contains(u.id)))
        .where((u) => q.isEmpty || '${u.displayName} ${u.username} ${u.department}'.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final l = _alphaIndex(_letterOf(a.displayName)).compareTo(_alphaIndex(_letterOf(b.displayName)));
        return l != 0 ? l : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    final frequent = widget.frequent && q.isEmpty
        ? (ctl.channels.where((ch) => !ctl.archived.contains(ch.id) && ch.lastAt.isNotEmpty && !ch.isSelf).toList()
              ..sort((a, b) => b.lastAt.compareTo(a.lastAt)))
            .take(5)
            .toList()
        : const <TalkChannel>[];
    final sel = widget.selected;

    _Row personRow(TalkUser u) => _Row(
          avatar: TalkAvatar.solid(name: u.displayName, photoUrl: ctl.api.fileUrl(u.avatarPath), size: 40, personIfEmpty: true),
          title: u.displayName,
          subtitle: u.about.trim().isNotEmpty ? u.about.trim() : (u.department.trim().isNotEmpty ? u.department.trim() : '@${u.username}'),
          trailing: sel != null ? _check(c, sel.contains(u.id)) : (widget.busyId == u.id ? CupertinoActivityIndicator(color: c.muted) : null),
          onTap: () => widget.onPick(u),
        );

    // harf bölümleri
    final groups = <String, List<TalkUser>>{};
    for (final u in people) {
      groups.putIfAbsent(_letterOf(u.displayName), () => []).add(u);
    }
    for (final k in groups.keys) {
      _sections.putIfAbsent(k, () => GlobalKey(debugLabel: 'harf-$k'));
    }
    _sections.removeWhere((k, _) => !groups.containsKey(k));

    final list = SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SearchBox(hint: 'Ad veya @kullanıcıadı', onChanged: (v) => setState(() => _q = v)),
        if (q.isEmpty && widget.actions.isNotEmpty)
          _card(c, [
            for (final (icon, label, onTap) in widget.actions)
              _Row(avatar: SizedBox(width: 40, child: Icon(icon, size: 26, color: c.ink)), title: label, onTap: onTap),
          ]),
        if (frequent.isNotEmpty) ...[
          _sectionTitle(c, 'Sık görüşülenler'),
          _card(c, [
            for (final ch in frequent) _Row(avatar: _chanAvatar(ctl, ch, c), title: ch.name, onTap: () => widget.onPickChannel?.call(ch)),
          ]),
        ],
        if (showMe) ...[
          _sectionTitle(c, "ARCONNECT'teki kişiler"),
          _card(c, [
            _Row(
              avatar: TalkAvatar.solid(name: meUser.displayName, photoUrl: ctl.api.fileUrl(meUser.avatarPath), size: 40, personIfEmpty: true),
              title: '${meUser.displayName} (Siz)',
              subtitle: 'Kendinize mesaj gönderin',
              trailing: widget.busyId == meUser.id ? CupertinoActivityIndicator(color: c.muted) : null,
              onTap: () => widget.onPick(meUser),
            ),
          ]),
        ],
        for (final e in groups.entries) ...[
          _sectionTitle(c, e.key, key: _sections[e.key]),
          _card(c, [for (final u in e.value) personRow(u)]),
        ],
        if (people.isEmpty && !showMe)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(widget.emptyText ?? (q.isEmpty ? 'Kişi yok' : 'Sonuç yok'), textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
          ),
      ]),
    );

    return Scaffold(
      backgroundColor: _groupedBg(c),
      appBar: _sheetBar(context, c, widget.title, subtitle: sel != null && sel.isNotEmpty ? '${sel.length} seçildi' : null),
      bottomNavigationBar: widget.bottom,
      body: Stack(children: [
        list,
        if (groups.length > 1 && q.isEmpty)
          Positioned(
            right: 0,
            top: 60,
            bottom: 20,
            child: _IndexBar(onLetter: _jump),
          ),
      ]),
    );
  }
}

/// Sağdaki A–Z dizini: dokun veya parmağını kaydır
class _IndexBar extends StatelessWidget {
  const _IndexBar({required this.onLetter});
  final ValueChanged<String> onLetter;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      void at(double dy) {
        final i = (dy / h * _alphabet.length).floor().clamp(0, _alphabet.length - 1);
        onLetter(_alphabet[i]);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => at(d.localPosition.dy),
        onVerticalDragUpdate: (d) => at(d.localPosition.dy),
        child: SizedBox(
          width: 22,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final l in _alphabet) Flexible(child: Text(l, style: talkText(11, FontWeight.w600, c.ink, height: 1.25))),
          ]),
        ),
      );
    });
  }
}
