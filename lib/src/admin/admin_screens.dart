import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/skeleton.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
List<int> _ids(Object? v) => ((v as List?) ?? const []).map(_i).where((e) => e > 0).toList();

const _api = 'api/v1/admin';

String _ago(String? iso) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'şimdi';
  if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
  if (d.inHours < 24) return '${d.inHours} sa önce';
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

void _toast(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

Future<bool> _confirm(BuildContext context, String title, String text, {String ok = 'Sil'}) async =>
    await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.of(ctx).pop(true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// Ortak sayfa: geri + başlık + aksiyon + gövde.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.body, this.fab, this.actions = const []});
  final String title;
  final Widget body;
  final Widget? fab;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        floatingActionButton: fab,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(19, weight: FontWeight.w800))),
                    ...actions,
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _fab(ArconMono c, String label, VoidCallback onTap) => FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: c.ink,
      foregroundColor: c.bg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.add_rounded),
      label: Text(label, style: c.text(14, weight: FontWeight.w700, color: c.bg)),
    );

/// Alttan açılan form sayfası.
Future<T?> _sheet<T>(BuildContext context, String title, Widget Function(BuildContext, StateSetter) builder) {
  final c = ArconMono.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.bg,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: c.text(22, weight: FontWeight.w800, spacing: -0.5)),
              const SizedBox(height: 16),
              builder(ctx, set),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _field(ArconMono c, TextEditingController ctl, String hint, IconData icon, {bool obscure = false, TextInputType? type, int lines = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctl,
        obscureText: obscure,
        keyboardType: type,
        minLines: lines,
        maxLines: obscure ? 1 : (lines > 1 ? lines + 6 : 1),
        autocorrect: false,
        keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
        style: c.text(15),
        cursorColor: c.ink,
        decoration: c.input(hint, lines > 1 ? null : icon),
      ),
    );

/* ============================== Kullanıcılar ============================== */

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<Map<String, dynamic>>? _users;
  List<Map<String, dynamic>> _roles = const [];
  bool _canAdd = false;
  String? _error;
  final _q = TextEditingController();
  int? _roleFilter;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(_api, query: {'view': 'users'});
      if (!mounted) return;
      setState(() {
        _users = [for (final u in ((j['users'] as List?) ?? const []).whereType<Map>()) u.cast<String, dynamic>()];
        _roles = [for (final r in ((j['roles'] as List?) ?? const []).whereType<Map>()) r.cast<String, dynamic>()];
        _canAdd = j['can_add'] == true;
        _error = null;
      });
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.code == 'tool_unavailable' ? 'Yönetim servisi sunucuda henüz yok.' : e.message);
    }
  }

  Future<void> _edit([Map<String, dynamic>? u]) async {
    final c = ArconMono.of(context);
    final name = TextEditingController(text: _s(u?['username']));
    final email = TextEditingController(text: _s(u?['email']));
    final pass = TextEditingController();
    int? role = u == null ? null : _i(u['role_id']);
    var busy = false;
    String? err;
    final saved = await _sheet<bool>(context, u == null ? 'Yeni kullanıcı' : 'Kullanıcıyı düzenle', (ctx, set) {
      Future<void> save() async {
        set(() {
          busy = true;
          err = null;
        });
        try {
          await widget.session.api.webCall(_api, jsonBody: {
            'action': 'user_save',
            'id': ?u?['id'],
            'username': name.text.trim(),
            'email': email.text.trim(),
            if (pass.text.isNotEmpty) 'password': pass.text,
            'role_id': ?role,
          });
          if (ctx.mounted) Navigator.of(ctx).pop(true);
        } on ArconApiException catch (e) {
          set(() {
            err = e.message;
            busy = false;
          });
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(c, name, 'Kullanıcı adı (Ad Soyad)', Icons.person_outline_rounded),
          _field(c, email, 'E-posta', Icons.mail_outline_rounded, type: TextInputType.emailAddress),
          _field(c, pass, u == null ? 'Şifre (en az 6 karakter)' : 'Yeni şifre (boş bırak: değişmez)', Icons.lock_outline_rounded, obscure: true),
          c.label('Rol'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _roles)
                GestureDetector(
                  onTap: u?['is_me'] == true ? null : () => set(() => role = _i(r['id'])),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: role == _i(r['id']) ? c.ink : c.field,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: role == _i(r['id']) ? c.ink : c.line),
                    ),
                    child: Text(_s(r['name']), style: c.text(13, weight: FontWeight.w700, color: role == _i(r['id']) ? c.bg : c.ink)),
                  ),
                ),
            ],
          ),
          if (u == null && role == null) ...[const SizedBox(height: 6), Text('Rol seçmezsen varsayılan yeni üye rolü verilir.', style: c.text(12, color: c.muted))],
          if (err != null) ...[const SizedBox(height: 12), c.errorBox(err!)],
          const SizedBox(height: 16),
          c.primaryButton('Kaydet', busy: busy, onPressed: save),
          if (u != null && u['is_me'] != true) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!await _confirm(ctx, 'Kullanıcı silinsin mi?', '${u['username']} kalıcı olarak silinecek.')) return;
                      try {
                        await widget.session.api.webCall(_api, jsonBody: {'action': 'user_delete', 'id': u['id']});
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } on ArconApiException catch (e) {
                        set(() => err = e.message);
                      }
                    },
              icon: Icon(Icons.delete_outline_rounded, color: c.danger),
              label: Text('Kullanıcıyı sil', style: c.text(14, weight: FontWeight.w700, color: c.danger)),
            ),
          ],
        ],
      );
    });
    name.dispose();
    email.dispose();
    pass.dispose();
    if (saved == true) {
      HapticFeedback.mediumImpact();
      if (mounted) _toast(context, 'Kaydedildi');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final q = _q.text.trim().toLowerCase();
    final list = (_users ?? const <Map<String, dynamic>>[])
        .where((u) => (_roleFilter == null || _i(u['role_id']) == _roleFilter) && (q.isEmpty || '${u['username']} ${u['email']}'.toLowerCase().contains(q)))
        .toList();
    final pad = MediaQuery.paddingOf(context);
    return _Page(
      title: 'Kullanıcılar',
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdminRolesScreen(session: widget.session)));
            _load();
          },
          icon: Icon(Icons.badge_outlined, size: 18, color: c.ink),
          label: Text('Roller', style: c.text(13.5, weight: FontWeight.w700)),
        ),
      ],
      fab: _canAdd ? _fab(c, 'Yeni kullanıcı', () => _edit()) : null,
      body: _users == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 10, leadingSize: 40))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + pad.bottom),
                children: [
                  TextField(
                    controller: _q,
                    keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                    style: c.text(15),
                    cursorColor: c.ink,
                    decoration: c.input('Ad ya da e-posta ara', Icons.search_rounded),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final (id, label) in [(null, 'Tümü ${_users!.length}'), for (final r in _roles) (_i(r['id']), '${r['name']} ${r['user_count']}')])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => setState(() => _roleFilter = id),
                              child: AnimatedContainer(
                                duration: Motion.of(context, Motion.fast),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _roleFilter == id ? c.ink : c.bg,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(color: _roleFilter == id ? c.ink : c.line),
                                ),
                                child: Text(label, style: c.text(12, weight: FontWeight.w700, color: _roleFilter == id ? c.bg : c.ink)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('${list.length} kullanıcı', style: c.text(12, weight: FontWeight.w700, color: c.muted)),
                  const SizedBox(height: 6),
                  for (final u in list)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _edit(u),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: c.ink,
                              child: Text(
                                _s(u['username']).trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x[0]).join().toUpperCase(),
                                style: c.text(13, weight: FontWeight.w800, color: c.bg),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u['is_me'] == true ? '${u['username']} (sen)' : _s(u['username']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14.5, weight: FontWeight.w700)),
                                  Text(_s(u['email']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(12, color: c.muted)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
                              child: Text(_s(u['role_name']).isEmpty ? '—' : _s(u['role_name']), style: c.text(11, weight: FontWeight.w700, color: c.muted)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/* ============================== Roller ============================== */

class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  List<Map<String, dynamic>>? _roles;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(_api, query: {'view': 'roles'});
      if (mounted) setState(() => _roles = [for (final r in ((j['roles'] as List?) ?? const []).whereType<Map>()) r.cast<String, dynamic>()]);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit([Map<String, dynamic>? r]) async {
    final c = ArconMono.of(context);
    final name = TextEditingController(text: _s(r?['name']));
    var busy = false;
    String? err;
    final saved = await _sheet<bool>(context, r == null ? 'Yeni rol' : 'Rolü düzenle', (ctx, set) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(c, name, 'Rol adı (ör. Pazarlama)', Icons.badge_outlined),
          if (err != null) ...[const SizedBox(height: 4), c.errorBox(err!)],
          const SizedBox(height: 12),
          c.primaryButton('Kaydet', busy: busy, onPressed: () async {
            set(() => busy = true);
            try {
              await widget.session.api.webCall(_api, jsonBody: {'action': 'role_save', 'id': ?r?['id'], 'name': name.text.trim()});
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            } on ArconApiException catch (e) {
              set(() {
                err = e.message;
                busy = false;
              });
            }
          }),
        ],
      );
    });
    name.dispose();
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    if (!await _confirm(context, 'Rol silinsin mi?', '“${r['name']}” rolü silinecek.')) return;
    try {
      await widget.session.api.webCall(_api, jsonBody: {'action': 'role_delete', 'id': r['id']});
      _load();
    } on ArconApiException catch (e) {
      if (mounted) _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return _Page(
      title: 'Roller',
      fab: _fab(c, 'Yeni rol', () => _edit()),
      body: _roles == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8, leadingSize: 36))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + pad.bottom),
                children: [
                  for (final r in _roles!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: c.field,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _i(r['id']) == 1 ? null : () => _edit(r),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_s(r['name']), style: c.text(15, weight: FontWeight.w700)),
                                      Text('${r['user_count']} kullanıcı · ID ${r['id']}', style: c.text(12, color: c.muted)),
                                    ],
                                  ),
                                ),
                                if (_i(r['id']) == 1)
                                  Padding(padding: const EdgeInsets.all(12), child: Icon(Icons.lock_outline_rounded, size: 18, color: c.faint))
                                else
                                  IconButton(onPressed: () => _delete(r), icon: Icon(Icons.delete_outline_rounded, color: c.muted)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/* ============================== Modüller ============================== */

class AdminModulesScreen extends StatefulWidget {
  const AdminModulesScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<AdminModulesScreen> createState() => _AdminModulesScreenState();
}

class _AdminModulesScreenState extends State<AdminModulesScreen> {
  List<Map<String, dynamic>>? _mods;
  Map<int, String> _roleNames = const {};
  String? _error;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(_api, query: {'view': 'modules'});
      if (!mounted) return;
      setState(() {
        _mods = [for (final m in ((j['modules'] as List?) ?? const []).whereType<Map>()) m.cast<String, dynamic>()];
        _roleNames = {for (final r in ((j['roles'] as List?) ?? const []).whereType<Map>()) _i(r['id']): _s(r['name'])};
      });
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open([int? id]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _ModuleEditor(session: widget.session, id: id)));
    if (changed == true) {
      _load();
      widget.session.refreshModules(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final q = _q.text.trim().toLowerCase();
    final list = (_mods ?? const <Map<String, dynamic>>[]).where((m) => q.isEmpty || _s(m['name']).toLowerCase().contains(q)).toList();
    return _Page(
      title: 'Modül yönetimi',
      fab: _fab(c, 'Yeni modül', () => _open()),
      body: _mods == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 8, leadingSize: 40))
          : RefreshIndicator(
              color: c.ink,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                padding: EdgeInsets.fromLTRB(20, 4, 20, 96 + pad.bottom),
                children: [
                  TextField(
                    controller: _q,
                    keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                    style: c.text(15),
                    cursorColor: c.ink,
                    decoration: c.input('Modül ara', Icons.search_rounded),
                  ),
                  const SizedBox(height: 12),
                  for (final m in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: c.field,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _open(_i(m['id'])),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(_s(m['name']), style: c.text(15, weight: FontWeight.w800))),
                                    Text('${m['blocks']} blok', style: c.text(11.5, color: c.muted)),
                                  ],
                                ),
                                if (_s(m['description']).isNotEmpty)
                                  Text(_s(m['description']), maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(12.5, color: c.muted, height: 1.4)),
                                const SizedBox(height: 6),
                                Text(
                                  _ids(m['roles']).isEmpty && _ids(m['users']).isEmpty
                                      ? 'Herkes görür'
                                      : [
                                          if (_ids(m['roles']).isNotEmpty) _ids(m['roles']).map((id) => _roleNames[id] ?? '#$id').join(', '),
                                          if (_ids(m['users']).isNotEmpty) '${_ids(m['users']).length} kişi',
                                        ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: c.text(11.5, weight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Erişim seçici: roller (çip) + kişiler (aranabilir liste). Boş = herkes.
class _AccessPicker extends StatelessWidget {
  const _AccessPicker({required this.roles, required this.users, required this.selRoles, required this.selUsers, required this.onChanged});
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> users;
  final Set<int> selRoles;
  final Set<int> selUsers;
  final VoidCallback onChanged;

  Future<void> _pickUsers(BuildContext context) async {
    final c = ArconMono.of(context);
    final q = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.bg,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final s = q.text.trim().toLowerCase();
          final list = users.where((u) => s.isEmpty || _s(u['username']).toLowerCase().contains(s)).toList();
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: q,
                    onChanged: (_) => set(() {}),
                    style: c.text(15),
                    cursorColor: c.ink,
                    decoration: c.input('Kişi ara', Icons.search_rounded),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final u in list)
                        CheckboxListTile(
                          value: selUsers.contains(_i(u['id'])),
                          activeColor: c.ink,
                          title: Text(_s(u['username']), style: c.text(14.5)),
                          onChanged: (v) {
                            set(() => v == true ? selUsers.add(_i(u['id'])) : selUsers.remove(_i(u['id'])));
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    q.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(selRoles.isEmpty && selUsers.isEmpty ? 'Herkes görür' : 'Yalnızca seçilen roller ve kişiler görür', style: c.text(12, color: c.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in roles)
              GestureDetector(
                onTap: () {
                  final id = _i(r['id']);
                  selRoles.contains(id) ? selRoles.remove(id) : selRoles.add(id);
                  onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selRoles.contains(_i(r['id'])) ? c.ink : c.bg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: selRoles.contains(_i(r['id'])) ? c.ink : c.line),
                  ),
                  child: Text(_s(r['name']), style: c.text(12, weight: FontWeight.w700, color: selRoles.contains(_i(r['id'])) ? c.bg : c.ink)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _pickUsers(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.ink,
            side: BorderSide(color: c.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: Text(selUsers.isEmpty ? 'Kişi ekle' : '${selUsers.length} kişi seçili', style: c.text(13, weight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _Block {
  _Block({this.id, String title = '', String content = '', Set<int>? roles, Set<int>? users})
      : title = TextEditingController(text: title),
        content = TextEditingController(text: content),
        roles = roles ?? {},
        users = users ?? {};
  final int? id;
  final TextEditingController title;
  final TextEditingController content;
  final Set<int> roles;
  final Set<int> users;
  bool deleted = false;
  bool open = false;
}

class _ModuleEditor extends StatefulWidget {
  const _ModuleEditor({required this.session, this.id});
  final SessionController session;
  final int? id;

  @override
  State<_ModuleEditor> createState() => _ModuleEditorState();
}

class _ModuleEditorState extends State<_ModuleEditor> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final Set<int> _roles = {};
  final Set<int> _users = {};
  final List<_Block> _blocks = [];
  List<Map<String, dynamic>> _allRoles = const [];
  List<Map<String, dynamic>> _allUsers = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    for (final b in _blocks) {
      b.title.dispose();
      b.content.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final j = await widget.session.api.webCall(_api, query: widget.id == null ? {'view': 'modules'} : {'view': 'module', 'id': '${widget.id}'});
      if (!mounted) return;
      setState(() {
        _allRoles = [for (final r in ((j['roles'] as List?) ?? const []).whereType<Map>()) r.cast<String, dynamic>()];
        _allUsers = [for (final u in ((j['users'] as List?) ?? const []).whereType<Map>()) u.cast<String, dynamic>()];
        final m = (j['module'] as Map?)?.cast<String, dynamic>();
        if (m != null) {
          _name.text = _s(m['name']);
          _desc.text = _s(m['description']);
          _roles.addAll(_ids(m['roles']));
          _users.addAll(_ids(m['users']));
          for (final b in ((j['blocks'] as List?) ?? const []).whereType<Map>()) {
            _blocks.add(_Block(id: _i(b['id']), title: _s(b['title']), content: _s(b['content']), roles: _ids(b['roles']).toSet(), users: _ids(b['users']).toSet()));
          }
        }
        _loading = false;
      });
    } on ArconApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.api.webCall(_api, jsonBody: {
        'action': 'module_save',
        'id': ?widget.id,
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'roles': _roles.toList(),
        'users': _users.toList(),
        'blocks': [
          for (final b in _blocks)
            {'id': ?b.id, 'title': b.title.text, 'content': b.content.text, 'roles': b.roles.toList(), 'users': b.users.toList(), if (b.deleted) 'delete': true},
        ],
      });
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm(context, 'Modül silinsin mi?', '“${_name.text}” ve tüm içerik blokları kalıcı olarak silinecek.')) return;
    try {
      await widget.session.api.webCall(_api, jsonBody: {'action': 'module_delete', 'id': widget.id});
      if (mounted) Navigator.of(context).pop(true);
    } on ArconApiException catch (e) {
      if (mounted) _toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return _Page(
      title: widget.id == null ? 'Yeni modül' : 'Modülü düzenle',
      actions: [if (widget.id != null) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: c.danger))],
      body: _loading
          ? const SkeletonArticle()
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
              children: [
                c.label('Modül adı'),
                const SizedBox(height: 6),
                _field(c, _name, 'Ör. HR - AI', Icons.widgets_outlined),
                c.label('Açıklama'),
                const SizedBox(height: 6),
                _field(c, _desc, 'Modül kartında görünen kısa açıklama', Icons.notes_rounded, lines: 2),
                const SizedBox(height: 4),
                c.label('Kimler görür'),
                const SizedBox(height: 6),
                _AccessPicker(roles: _allRoles, users: _allUsers, selRoles: _roles, selUsers: _users, onChanged: () => setState(() {})),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(child: c.label('İçerik blokları (HTML)')),
                    TextButton.icon(
                      onPressed: () => setState(() => _blocks.add(_Block()..open = true)),
                      icon: Icon(Icons.add_rounded, color: c.ink, size: 18),
                      label: Text('Blok ekle', style: c.text(13, weight: FontWeight.w700)),
                    ),
                  ],
                ),
                for (final b in _blocks.where((b) => !b.deleted))
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          title: Text(b.title.text.isEmpty ? 'Başlıksız blok' : b.title.text, style: c.text(14, weight: FontWeight.w700)),
                          subtitle: Text('${b.content.text.length} karakter', style: c.text(11.5, color: c.muted)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(onPressed: () => setState(() => b.deleted = true), icon: Icon(Icons.delete_outline_rounded, color: c.muted, size: 20)),
                              Icon(b.open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.muted),
                            ],
                          ),
                          onTap: () => setState(() => b.open = !b.open),
                        ),
                        if (b.open)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                  controller: b.title,
                                  onChanged: (_) => setState(() {}),
                                  style: c.text(14.5),
                                  cursorColor: c.ink,
                                  decoration: c.input('Blok başlığı (sekme adı)', null).copyWith(fillColor: c.bg),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: b.content,
                                  minLines: 6,
                                  maxLines: 16,
                                  autocorrect: false,
                                  onChanged: (_) => setState(() {}),
                                  style: const TextStyle(fontFamily: 'Menlo', fontSize: 12.5, height: 1.4),
                                  cursorColor: c.ink,
                                  decoration: c.input('<iframe src="./hr-ai/"></iframe>', null).copyWith(fillColor: c.bg),
                                ),
                                const SizedBox(height: 10),
                                _AccessPicker(roles: _allRoles, users: _allUsers, selRoles: b.roles, selUsers: b.users, onChanged: () => setState(() {})),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (_error != null) ...[const SizedBox(height: 14), c.errorBox(_error!)],
                const SizedBox(height: 20),
                c.primaryButton('Kaydet', busy: _saving, onPressed: _save),
              ],
            ),
    );
  }
}

/* ============================== Loglar ============================== */

class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  String _source = 'system';
  String _module = '';
  List<String> _modules = const [];
  final List<Map<String, dynamic>> _items = [];
  int? _next;
  bool _loading = true;
  bool _more = false;
  String? _error;
  final _q = TextEditingController();
  final _scroll = ScrollController();
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, String> get _query => {
        'view': 'logs',
        'source': _source,
        if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
        if (_source == 'tools' && _module.isNotEmpty) 'module': _module,
      };

  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _next = null;
    });
    try {
      final j = await widget.session.api.webCall(_api, query: _query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items.addAll([for (final x in ((j['items'] as List?) ?? const []).whereType<Map>()) x.cast<String, dynamic>()]);
        _next = j['next_before'] == null ? null : _i(j['next_before']);
        if (_source == 'tools') _modules = ((j['modules'] as List?) ?? const []).map((e) => '$e').toList();
        _loading = false;
      });
    } on ArconApiException catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_more || _next == null || _loading) return;
    final seq = _seq;
    setState(() => _more = true);
    try {
      final j = await widget.session.api.webCall(_api, query: {..._query, 'before': '$_next'});
      if (!mounted || seq != _seq) return;
      setState(() {
        _items.addAll([for (final x in ((j['items'] as List?) ?? const []).whereType<Map>()) x.cast<String, dynamic>()]);
        _next = j['next_before'] == null ? null : _i(j['next_before']);
      });
    } on ArconApiException catch (_) {
    } finally {
      if (mounted) setState(() => _more = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    Widget seg(String key, String label) => Expanded(
          child: GestureDetector(
            onTap: () {
              if (_source == key) return;
              setState(() {
                _source = key;
                _module = '';
              });
              _reload();
            },
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _source == key ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              child: Text(label, style: c.text(13, weight: FontWeight.w700, color: _source == key ? c.bg : c.ink)),
            ),
          ),
        );
    return _Page(
      title: 'Loglar',
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(13), border: Border.all(color: c.line)),
            child: Row(children: [seg('system', 'Sistem'), seg('tools', 'AI araçları')]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
              style: c.text(15),
              cursorColor: c.ink,
              decoration: c.input('Kullanıcı ya da işlem ara (Enter)', Icons.search_rounded),
            ),
          ),
          if (_source == 'tools' && _modules.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                children: [
                  for (final m in ['', ..._modules])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _module = m);
                          _reload();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _module == m ? c.ink : c.bg,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: _module == m ? c.ink : c.line),
                          ),
                          child: Text(m.isEmpty ? 'Tümü' : m, style: c.text(12, weight: FontWeight.w700, color: _module == m ? c.bg : c.ink)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const SkeletonList(count: 10, leading: false)
                : _error != null
                    ? Center(child: Text(_error!, style: c.text(14, color: c.muted)))
                    : RefreshIndicator(
                        color: c.ink,
                        onRefresh: _reload,
                        child: ListView.separated(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                          padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + pad.bottom),
                          itemCount: _items.length + 1,
                          separatorBuilder: (_, _) => Divider(color: c.line, height: 1),
                          itemBuilder: (_, i) {
                            if (i == _items.length) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: _more
                                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.ink))
                                      : Text(_items.isEmpty ? 'Kayıt yok' : (_next == null ? 'Hepsi bu kadar' : ''), style: c.text(12.5, color: c.muted)),
                                ),
                              );
                            }
                            final x = _items[i];
                            final tools = _source == 'tools';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(_s(x['user']).isEmpty ? 'Sistem' : _s(x['user']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13.5, weight: FontWeight.w700)),
                                      ),
                                      Text(_ago(_s(x['at'])), style: c.text(11.5, color: c.faint)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (tools) ...[
                                    Text(
                                      [_s(x['module']), _s(x['action']), if (x['duration_ms'] != null) '${(_i(x['duration_ms']) / 1000).toStringAsFixed(1)} sn'].join(' · '),
                                      style: c.text(11.5, weight: FontWeight.w700, color: c.muted),
                                    ),
                                    if (_s(x['title']).isNotEmpty) Text(_s(x['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13)),
                                    if (_s(x['input']).isNotEmpty) Text('→ ${x['input']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(12.5, color: c.muted, height: 1.35)),
                                    if (_s(x['output']).isNotEmpty) Text('← ${x['output']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(12.5, color: c.muted, height: 1.35)),
                                  ] else ...[
                                    Text(_s(x['action']), style: c.text(13, height: 1.4)),
                                    if (_s(x['page']).isNotEmpty || _s(x['ip']).isNotEmpty)
                                      Text([_s(x['page']), _s(x['ip'])].where((e) => e.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(11.5, color: c.faint)),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
