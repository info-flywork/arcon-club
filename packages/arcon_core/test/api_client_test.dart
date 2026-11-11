import 'dart:convert';

import 'package:arcon_core/arcon_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user = {
  'id': 7, 'username': 'ayse', 'email': 'ayse@arcon.test', 'role_id': 2,
  'role_name': 'User', 'is_admin': false, 'is_beta': false,
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  test('login gönderir, token ve kullanıcıyı döner', () async {
    late http.Request seen;
    final api = ArconApi(
      baseUrl: 'https://arconai.net/app/',
      appKey: 'arconnect',
      client: MockClient((req) async {
        seen = req;
        return _json({'ok': true, 'token': 'arc_x', 'expires_at': '2027-01-01', 'user': _user});
      }),
    );
    final r = await api.login('ayse', 'sifre', deviceName: 'ios');
    expect(seen.url.toString(), 'https://arconai.net/app/api/v1/login');
    expect(jsonDecode(seen.body), {'login': 'ayse', 'password': 'sifre', 'app': 'arconnect', 'device_name': 'ios'});
    expect(r.token, 'arc_x');
    expect(r.user.username, 'ayse');
    expect(r.user.initials, 'AY');
  });

  test('token Bearer başlığıyla gider ve modüller app ile istenir', () async {
    late http.Request seen;
    final api = ArconApi(
      baseUrl: 'https://arconai.net/app',
      appKey: 'club',
      token: 'arc_tok',
      client: MockClient((req) async {
        seen = req;
        return _json({'ok': true, 'modules': [
          {'key': 'todo', 'title': 'To-Do', 'group': 'main', 'icon': 'check', 'render': 'webview',
           'path': 'arcon-todo', 'url': 'https://arconai.net/app/arcon-todo'},
        ]});
      }),
    );
    final mods = await api.modules();
    expect(seen.headers['Authorization'], 'Bearer arc_tok');
    expect(seen.url.toString(), 'https://arconai.net/app/api/v1/modules?app=club');
    expect(mods.single.key, 'todo');
    expect(mods.single.render, 'webview');
  });

  test('sunucu hatası ArconApiException olur; 401 oturum düşmesidir', () async {
    final api = ArconApi(
      baseUrl: 'https://arconai.net/app/',
      appKey: 'club',
      client: MockClient((_) async =>
          _json({'ok': false, 'error': {'code': 'unauthorized', 'message': 'Oturum geçersiz'}}, 401)),
    );
    await expectLater(
      api.me(),
      throwsA(isA<ArconApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)),
    );
  });

  test('yanlış şifre oturum düşmesi sayılmaz', () async {
    final api = ArconApi(
      baseUrl: 'https://arconai.net/app/',
      appKey: 'club',
      client: MockClient((_) async =>
          _json({'ok': false, 'error': {'code': 'invalid_credentials', 'message': 'Yanlış'}}, 401)),
    );
    await expectLater(
      api.login('a', 'b'),
      throwsA(isA<ArconApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', false)),
    );
  });

  test('JSON olmayan yanıt anlaşılır hata verir', () async {
    final api = ArconApi(
      baseUrl: 'https://arconai.net/app/',
      appKey: 'club',
      client: MockClient((_) async => http.Response('<html>', 500)),
    );
    await expectLater(api.me(), throwsA(isA<ArconApiException>().having((e) => e.code, 'code', 'bad_response')));
  });
}
