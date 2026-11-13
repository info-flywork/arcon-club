import 'dart:async';
import 'dart:convert';

import 'package:arcon_club/arcon_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json', ...headers});

ArconApi _arcon() => ArconApi(
      baseUrl: 'https://arconai.net/app/',
      appKey: 'club',
      token: 'arc_t',
      client: MockClient((req) async => _json({
            'ok': true, 'engine_api': 'https://arconai.net/app/arcon-ai-engine/api',
            'uid': 'arconfs_u2', 'display_name': 'anilcan', 'sso': 'sig', 'exp': 1,
          })),
    );

void main() {
  test('SSO ile bağlanır, CEDSESSID çerezini saklar ve isteklerde gönderir', () async {
    final seen = <http.BaseRequest>[];
    final engine = EngineClient(
      arcon: _arcon(),
      client: MockClient((req) async {
        seen.add(req);
        if (req.url.path.endsWith('/auth/sso')) {
          expect(jsonDecode(req.body)['uid'], 'arconfs_u2');
          return _json({'success': true}, 200, {'set-cookie': 'CEDSESSID=abc123; path=/; HttpOnly'});
        }
        return _json({'success': true, 'conversations': [{'id': 5, 'title': 'Rapor', 'updated_at': '2026-10-20 10:00:00'}]});
      }),
    );
    final list = await engine.conversations();
    expect(seen.first.url.toString(), 'https://arconai.net/app/arcon-ai-engine/api/auth/sso');
    expect(seen.last.headers['Cookie'], 'CEDSESSID=abc123');
    expect(list.single.title, 'Rapor');
  });

  test('motor oturumu düşerse (401) bir kez yeniden bağlanır', () async {
    var ssoCalls = 0;
    var listCalls = 0;
    final engine = EngineClient(
      arcon: _arcon(),
      client: MockClient((req) async {
        if (req.url.path.endsWith('/auth/sso')) {
          ssoCalls++;
          return _json({'success': true}, 200, {'set-cookie': 'CEDSESSID=s$ssoCalls; path=/'});
        }
        listCalls++;
        return listCalls == 1 ? _json({'success': false, 'error': 'Oturum gerekli'}, 401) : _json({'success': true, 'projects': []});
      }),
    );
    expect(await engine.projects(), isEmpty);
    expect(ssoCalls, 2);
  });

  test('parça parça gelen SSE akışı doğru olaylara ayrılır', () async {
    final engine = EngineClient(
      arcon: _arcon(),
      client: MockClient((req) async => _json({'success': true}, 200, {'set-cookie': 'CEDSESSID=x; path=/'})),
    );
    await engine.connect();
    // Gerçek ağ gibi: olaylar parçalara bölünmüş halde gelir
    const raw = 'data: {"type":"meta","conversation_id":9}\n\ndata: {"type":"ping"}\n\ndata: {"type":"tok'
        'en","text":"Mer"}\n\ndata: {"type":"token","text":"haba"}\n\ndata: {"type":"done","content":"Merhaba","sources":[]}\n\n';
    final chunks = [raw.substring(0, 37), raw.substring(37, 90), raw.substring(90)];
    final events = await _collectStream(engine, chunks);
    expect(events.map((e) => e.type), ['meta', 'token', 'token', 'done']);
    expect(events.where((e) => e.type == 'token').map((e) => e.text).join(), 'Merhaba');
  });
}

Future<List<EngineEvent>> _collectStream(EngineClient engine, List<String> chunks) {
  // chat() kendi istemcisini açtığı için akışı http.runWithClient ile sahte istemciye yönlendir
  return http.runWithClient(
    () => engine.chat(conversationId: 9, message: 'selam').toList(),
    () => MockClient.streaming((req, body) async => http.StreamedResponse(
          Stream.fromIterable(chunks.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        )),
  );
}
