import 'package:arcon_core/arcon_core.dart';
import 'package:arcon_core/src/talk/agora_service.dart';
import 'package:arcon_core/src/talk/talk_api.dart';
import 'package:arcon_core/src/talk/talk_call_screen.dart';
import 'package:arcon_core/src/talk/talk_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final api = TalkApi(arcon: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'arconnect', token: 'arc_t'), baseUrl: 'https://x.test/app/');

  setUp(() {
    // Eklentiler (wakelock, callkit) testte yok: tüm platform çağrılarını sessizce yanıtla
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler('', null);
    for (final ch in ['flutter_callkit_incoming', 'dev.fluttercommunity.plus/wakelock']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    AgoraService.instance.serverCalls.value = const {};
  });

  TalkCall call() => TalkCall.fromJson({
        'id': 7,
        'channel_id': 3,
        'title': 'Sesli arama',
        'video': false,
        'created_by': 2,
        'status': 'ringing',
        'my_state': 'ringing',
        'caller_name': 'Furkan',
        'members': [
          {'user_id': 1, 'state': 'ringing', 'display_name': 'Sena'},
          {'user_id': 2, 'state': 'joined', 'display_name': 'Furkan'},
        ],
      });

  // Ekranı kapat, kapanışta giden sunucu isteğinin zaman aşımı sayacı bitsin
  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  }

  Future<void> openIncoming(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => TalkCallScreen.incoming(c, api: api, call: call(), photoUrl: ''),
            child: const Text('ac'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('ac'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('gelen sesli arama: sayaç yok, isim bir kez, kendi kutun yok', (t) async {
    await openIncoming(t);
    expect(find.text('arıyor…'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
    expect(find.text('Furkan'), findsOneWidget);
    expect(find.text('Sena'), findsNothing);
    expect(find.text('Kabul'), findsOneWidget);
    await finish(t);
  });

  testWidgets('arayan vazgeçince (sunucuda arama bitti) ekran kapanır', (t) async {
    await openIncoming(t);
    AgoraService.instance.serverCalls.value = {7};
    await t.pump();
    expect(find.text('Kabul'), findsOneWidget);
    AgoraService.instance.serverCalls.value = const {};
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Kabul'), findsNothing);
    expect(find.text('Arama bitti'), findsOneWidget);
    await finish(t);
  });

  testWidgets('arama henüz sunucu listesinde görülmediyse boş liste ekranı kapatmaz', (t) async {
    await openIncoming(t);
    AgoraService.instance.serverCalls.value = const {9};
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Kabul'), findsOneWidget);
    await finish(t);
  });
}
