import 'dart:convert';

import 'package:arcon_core/arcon_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user = {'id': 2, 'username': 'anilcan', 'email': '', 'role_id': 1, 'role_name': 'Admin', 'is_admin': true, 'is_beta': true};
const _mods = [
  {'key': 'arconnect', 'title': 'ARCONNECT', 'group': 'main', 'icon': 'chat', 'render': 'webview', 'path': 'arconnect', 'url': ''},
];

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

SessionController _session(MockClient client, MemoryTokenStore store) =>
    SessionController(api: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'club', client: client), store: store);

void main() {
  test('kayıtlı token ile açılışta oturum geri gelir', () async {
    final store = MemoryTokenStore();
    await store.write('arc_saved');
    final s = _session(MockClient((req) async {
      expect(req.headers['Authorization'], 'Bearer arc_saved');
      return req.url.path.endsWith('/me')
          ? _json({'ok': true, 'user': _user})
          : _json({'ok': true, 'modules': _mods});
    }), store);
    await s.restore();
    expect(s.status, SessionStatus.signedIn);
    expect(s.user!.username, 'anilcan');
    expect(s.modules.single.key, 'arconnect');
  });

  test('süresi dolmuş token silinir ve giriş ekranına düşer', () async {
    final store = MemoryTokenStore();
    await store.write('arc_old');
    final s = _session(MockClient((_) async =>
        _json({'ok': false, 'error': {'code': 'unauthorized', 'message': 'x'}}, 401)), store);
    await s.restore();
    expect(s.status, SessionStatus.signedOut);
    expect(await store.read(), isNull);
  });

  test('internet yoksa token silinmez', () async {
    final store = MemoryTokenStore();
    await store.write('arc_keep');
    final s = _session(MockClient((_) async => throw Exception('offline')), store);
    await s.restore();
    expect(s.status, SessionStatus.signedOut);
    expect(await store.read(), 'arc_keep');
  });

  test('giriş token kaydeder, çıkış siler', () async {
    final store = MemoryTokenStore();
    final s = _session(MockClient((req) async => switch (req.url.pathSegments.last) {
          'login' => _json({'ok': true, 'token': 'arc_new', 'expires_at': '', 'user': _user}),
          'modules' => _json({'ok': true, 'modules': _mods}),
          _ => _json({'ok': true}),
        }), store);
    await s.login('anilcan', 'pw');
    expect(s.status, SessionStatus.signedIn);
    expect(await store.read(), 'arc_new');
    await s.logout();
    expect(s.status, SessionStatus.signedOut);
    expect(await store.read(), isNull);
  });
}
