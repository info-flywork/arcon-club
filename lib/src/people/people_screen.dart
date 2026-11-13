import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../push/push_service.dart';
import '../talk/talk_api.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Dizindeki bir kişi (`/api/v1/people`).
class Person {
  Person.fromJson(Map<String, dynamic> j)
    : id = _i(j['id']),
      rosterId = _i(j['roster_id']),
      name = '${j['name'] ?? ''}',
      initials = '${j['initials'] ?? ''}',
      department = '${j['department'] ?? ''}',
      title = '${j['title'] ?? ''}',
      brand = '${j['brand'] ?? ''}',
      email = '${j['email'] ?? ''}',
      phone = '${j['phone'] ?? ''}',
      status = '${j['status'] ?? 'offline'}',
      avatarUrl = j['avatar_url'] as String?,
      isMe = j['is_me'] == true;

  final int id;
  final int rosterId;
  final String name;
  final String initials;
  final String department;
  final String title;
  final String brand;
  final String email;
  final String phone;
  final String status;
  final String? avatarUrl;
  final bool isMe;

  bool get online => status == 'online';

  String get subtitle => [if (title.isNotEmpty) title, if (department.isNotEmpty) department].join(' · ');

  bool matches(String q) {
    if (q.isEmpty) return true;
    final hay = '$name $title $department $brand $email'.toLowerCase();
    return hay.contains(q.toLowerCase());
  }
}

/// ARCON PEOPLE — webdeki arcon-people.php: kişiler dizini, arama, departman süzgeci, kişi kartı.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, required this.session, required this.config, this.openUserId});

  final SessionController session;
  final ArconAppConfig config;

  /// Doluysa liste yüklenince bu kişinin kartı açılır (arama sonucu / profil bağlantısı).
  final int? openUserId;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  List<Person>? _people;
  List<String> _departments = const [];
  bool _canTalk = false;
  String? _dept;
  String _q = '';
  String? _error;
  bool _searching = false;
  bool _openedTarget = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cached = await widget.session.api.cachedPeopleJson();
    if (cached != null && mounted) _apply(cached);
    await _load();
  }

  void _apply(Map<String, dynamic> j) {
    setState(() {
      _people = [for (final p in ((j['people'] as List?) ?? const []).whereType<Map>()) Person.fromJson(p.cast<String, dynamic>())];
      _departments = ((j['departments'] as List?) ?? const []).map((e) => '$e').toList();
      _canTalk = j['can_talk'] == true;
    });
    final target = widget.openUserId;
    if (target != null && !_openedTarget) {
      final p = _people!.where((x) => x.id == target).firstOrNull;
      if (p != null) {
        _openedTarget = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openPerson(p));
      }
    }
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.peopleJson(force: force);
      if (mounted) _apply(j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (_people == null && serverLacksApi(e)) {
        openWebFallback(context, session: widget.session, config: widget.config, title: 'ARCON PEOPLE', path: 'arcon-people');
        return;
      }
      setState(() => _error = e.message);
    }
  }

  List<Person> get _visible => [
    for (final p in _people ?? const <Person>[])
      if ((_dept == null || p.department == _dept) && p.matches(_q)) p,
  ];

  Future<void> _openPerson(Person p) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PersonSheet(person: p, canTalk: _canTalk, onMessage: () => _message(p)),
  );

  /// ARCONNECT'te birebir sohbeti açar (bildirimlerin kullandığı "kanalı aç" yolu).
  Future<void> _message(Person p) async {
    Navigator.of(context).pop();
    try {
      final api = TalkApi(arcon: widget.session.api, baseUrl: widget.config.apiBase);
      final ch = await api.openDm(p.id);
      if (ch != null) PushService.requestOpenTalk(ch.id);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final people = _people;
    final visible = _visible;
    final pad = MediaQuery.paddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AnimatedSize(
                duration: Motion.of(context, Motion.normal),
                curve: Curves.easeOutCubic,
                child: SwapFade(
                  child: KeyedSubtree(key: ValueKey(_searching), child: _topBar(c)),
                ),
              ),
              if (_departments.isNotEmpty) _deptChips(c),
              Expanded(
                child: RefreshIndicator(
                  color: c.ink,
                  backgroundColor: c.bg,
                  onRefresh: () => _load(force: true),
                  child: people == null
                      ? (_error == null
                            ? const SkeletonList(count: 9)
                            : ListView(
                                children: [
                                  const SizedBox(height: 120),
                                  Center(
                                    child: Text(_error!, style: c.text(14, color: c.muted)),
                                  ),
                                ],
                              ))
                      : visible.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 100),
                            Icon(Icons.person_search_outlined, size: 36, color: c.faint),
                            const SizedBox(height: 8),
                            Text(
                              'Eşleşen kişi yok',
                              textAlign: TextAlign.center,
                              style: c.text(14, color: c.muted),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.only(bottom: 24 + pad.bottom),
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final p = visible[i];
                            final letter = p.name.isEmpty ? '#' : trUpper(p.name.characters.first);
                            final prev = i == 0 ? null : visible[i - 1];
                            final newLetter = prev == null || trUpper(prev.name.isEmpty ? '#' : prev.name.characters.first) != letter;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (newLetter && _q.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                                    child: Text(
                                      letter,
                                      style: c.text(12, weight: FontWeight.w800, color: c.muted),
                                    ),
                                  ),
                                _row(c, p),
                              ],
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(ArconMono c) {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v.trim()),
                textInputAction: TextInputAction.search,
                style: c.text(15, weight: FontWeight.w500),
                cursorColor: c.ink,
                keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                decoration: c.input('İsim, unvan, departman, marka', Icons.search_rounded),
              ),
            ),
            TextButton(
              onPressed: () {
                _search.clear();
                setState(() {
                  _searching = false;
                  _q = '';
                });
              },
              style: TextButton.styleFrom(foregroundColor: c.ink),
              child: Text('Vazgeç', style: c.text(14, weight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
    final n = _people?.length;
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
                  text: 'PEOPLE',
                  style: TextStyle(color: c.ink),
                ),
              ],
            ),
            style: c.text(19, weight: FontWeight.w800, spacing: 0.4),
          ),
          if (n != null) ...[const SizedBox(width: 8), Text('$n kişi', style: c.text(12.5, color: c.muted))],
          const Spacer(),
          IconButton(
            tooltip: 'Ara',
            onPressed: () => setState(() => _searching = true),
            icon: Icon(Icons.search_rounded, color: c.ink),
          ),
        ],
      ),
    );
  }

  Widget _deptChips(ArconMono c) {
    Widget chip(String label, String? value) {
      final sel = _dept == value;
      return GestureDetector(
        onTap: () => setState(() => _dept = value),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? c.ink : c.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? c.ink : c.line),
          ),
          child: Text(
            trUpper(label),
            style: c.text(11, weight: FontWeight.w700, color: sel ? c.bg : c.ink, spacing: 0.4),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        children: [
          chip('Tümü', null),
          for (final d in _departments) ...[const SizedBox(width: 6), chip(d, d)],
        ],
      ),
    );
  }

  Widget _row(ArconMono c, Person p) => InkWell(
    onTap: () => _openPerson(p),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Row(
        children: [
          PersonAvatar(person: p, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: c.text(15, weight: FontWeight.w700),
                      ),
                    ),
                    if (p.isMe) ...[const SizedBox(width: 6), Text('(sen)', style: c.text(12, color: c.muted))],
                  ],
                ),
                if (p.subtitle.isNotEmpty)
                  Text(
                    p.subtitle,
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
  );
}

/// Fotoğraf ya da baş harfler + çevrim içi noktası.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.person, this.size = 44});
  final Person person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final initials = Center(
      child: Text(
        person.initials,
        style: c.text(size * 0.34, weight: FontWeight.w700, color: c.bg, height: 1),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
            child: person.avatarUrl == null
                ? initials
                : CachedNetworkImage(memCacheWidth: 240, imageUrl: person.avatarUrl!, fit: BoxFit.cover, errorWidget: (_, _, _) => initials),
          ),
          if (person.online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonSheet extends StatelessWidget {
  const _PersonSheet({required this.person, required this.canTalk, required this.onMessage});

  final Person person;
  final bool canTalk;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final p = person;
    Widget action(IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: PressScale(
          child: Material(
            color: c.field,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: c.line),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(icon, size: 22, color: c.ink),
                    const SizedBox(height: 6),
                    Text(label, style: c.text(12, weight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Widget info(IconData icon, String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : InkWell(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label kopyalandı')));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: c.muted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trUpper(label),
                          style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1),
                        ),
                        const SizedBox(height: 2),
                        Text(value, style: c.text(14.5, weight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, 18 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Center(child: PersonAvatar(person: p, size: 88)),
          const SizedBox(height: 14),
          Text(
            p.name,
            textAlign: TextAlign.center,
            style: c.text(22, weight: FontWeight.w800, spacing: -0.4),
          ),
          if (p.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              p.subtitle,
              textAlign: TextAlign.center,
              style: c.text(13.5, color: c.muted),
            ),
          ],
          if (p.online) ...[
            const SizedBox(height: 6),
            Text(
              'Çevrim içi',
              textAlign: TextAlign.center,
              style: c.text(12, weight: FontWeight.w600, color: const Color(0xFF16A34A)),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              action(
                Icons.call_outlined,
                'Ara',
                p.phone.isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: p.phone.replaceAll(' ', ''))),
              ),
              const SizedBox(width: 8),
              action(Icons.mail_outline_rounded, 'E-posta', p.email.isEmpty ? null : () => launchUrl(Uri(scheme: 'mailto', path: p.email))),
              const SizedBox(width: 8),
              action(Icons.chat_bubble_outline_rounded, 'Mesaj', (canTalk && p.id > 0 && !p.isMe) ? onMessage : null),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: c.field,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                info(Icons.badge_outlined, 'Unvan', p.title),
                info(Icons.apartment_rounded, 'Departman', p.department),
                info(Icons.sell_outlined, 'Marka', p.brand),
                info(Icons.mail_outline_rounded, 'E-posta', p.email),
                info(Icons.call_outlined, 'Telefon', p.phone),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bilgiyi kopyalamak için basılı tut',
            textAlign: TextAlign.center,
            style: c.text(11.5, color: c.faint),
          ),
        ],
      ),
    );
  }
}
