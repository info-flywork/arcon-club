import 'package:arcon_core/arcon_core.dart';
import 'package:arcon_core/src/talk/talk_api.dart';
import 'package:arcon_core/src/talk/talk_gif_panel.dart';
import 'package:arcon_core/src/talk/talk_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TalkApi api(List<Uri> seen, String body) => TalkApi(
        arcon: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'arconnect', token: 'arc_t'),
        baseUrl: 'https://x.test/app/',
        client: MockClient((req) async {
          seen.add(req.url);
          return http.Response(body, 200);
        }),
      );

  test('gifs: arama ve çıkartma sunucuya gider, sonuçlar okunur', () async {
    final seen = <Uri>[];
    final r = await api(seen, '{"ok":true,"configured":true,"items":[{"url":"https://g/1.gif","preview":"https://g/1s.gif","w":200,"h":150}]}')
        .gifs(q: 'happy', stickers: true, offset: 30);
    expect(seen.single.queryParameters, containsPair('action', 'gifs'));
    expect(seen.single.queryParameters, containsPair('kind', 'stickers'));
    expect(seen.single.queryParameters, containsPair('q', 'happy'));
    expect(seen.single.queryParameters, containsPair('offset', '30'));
    expect(r.configured, isTrue);
    expect(r.items.single.preview, 'https://g/1s.gif');
    expect(r.items.single.height, 150);
  });

  testWidgets('anahtar yoksa hazır GIF paketi gelir; çıkartma sekmesi Noto çıkartmalarını gönderir', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final seen = <Uri>[];
    String? sent;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: TalkStickerPanel(api: api(seen, '{"ok":true,"configured":false,"items":[]}'), onGif: (u) => sent = u),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('GIF'), findsOneWidget);
    expect(seen.single.queryParameters, containsPair('kind', 'gifs'));
    expect(find.byType(ClipRRect), findsWidgets);
    await tester.tap(find.byType(ClipRRect).first);
    expect(sent, startsWith('https://media.giphy.com/'));
    await tester.tap(find.byType(TalkIcon).last);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(ClipRRect).first);
    expect(sent, endsWith('/512.webp'));
  });
}
