import 'dart:convert';
import 'dart:io';

import 'package:arcon_club/arcon_core.dart';
import 'package:arcon_club/src/talk/talk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('dosyalı mesaj multipart (boundary başlığıyla) gider ve ilerleme bildirir', () async {
    final tmp = File('${Directory.systemTemp.path}/talk_up_test.txt')..writeAsStringSync('merhaba' * 200);
    late http.BaseRequest seen;
    var body = '';
    final api = TalkApi(arcon: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'arconnect', token: 'arc_t'), baseUrl: 'https://x.test/app/');
    final progress = <double>[];
    final res = await http.runWithClient(
      () => api.sendMessage(channelId: 3, body: 'not', filePaths: [tmp.path], onProgress: progress.add),
      () => MockClient.streaming((req, stream) async {
        seen = req;
        body = utf8.decode(await stream.toBytes(), allowMalformed: true);
        return http.StreamedResponse(Stream.value(utf8.encode('{"ok":true,"message":{"id":9}}')), 200);
      }),
    );
    expect(res['ok'], true);
    expect(seen.headers['content-type'], startsWith('multipart/form-data; boundary='));
    expect(seen.headers['Authorization'], 'Bearer arc_t');
    expect(body, contains('name="files[]"'));
    expect(body, contains('name="channel_id"'));
    expect(progress.last, closeTo(1.0, 0.001));
  });

  test('şifre değişimi mevcut + yeni + tekrar gönderir', () async {
    late http.Request seen;
    final api = TalkApi(
      arcon: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'arconnect', token: 'arc_t'),
      baseUrl: 'https://x.test/app/',
      client: MockClient((req) async {
        seen = req;
        return http.Response('{"ok":true}', 200);
      }),
    );
    await api.changePassword(current: 'eski8chr', next: 'yeni8chr', confirm: 'yeni8chr');
    expect(seen.url.queryParameters['action'], 'profile');
    expect(jsonDecode(seen.body), {
      'current_password': 'eski8chr',
      'new_password': 'yeni8chr',
      'new_password_confirm': 'yeni8chr',
    });
  });
}
