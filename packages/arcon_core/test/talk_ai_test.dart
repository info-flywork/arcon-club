import 'package:arcon_core/arcon_core.dart';
import 'package:arcon_core/src/ai/engine_client.dart';
import 'package:arcon_core/src/ai/engine_models.dart';
import 'package:arcon_core/src/talk/talk_ai_screen.dart';
import 'package:arcon_core/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeEngine extends EngineClient {
  FakeEngine() : super(arcon: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'arconnect'));
  @override
  Future<List<EngineProvider>> providers() async => const [];
  @override
  Future<(EngineConversation, List<EngineMessage>)> conversation(int id) async => (
        EngineConversation.fromJson({'id': id, 'title': 'Stop-motion'}),
        [
          EngineMessage(id: 1, role: 'user', content: '5 stop-motion film çekme ipucu'),
          EngineMessage(id: 2, role: 'assistant', content: "Stop-motion'da farkı yaratan şey sabır değil, **tutarlılık**. İşte 5 ipucu:\n\n- **Tripodu kilitle**: Kamera en ufak sarsıntıda atlar.\n- **Işığı manuelde sabitle**: Otomatik pozlama titreme yapar.\n- **Küçük hareket, çok kare**: Saniyede 12–15 kare."),
        ]
      );
  @override
  Future<List<EngineConversation>> conversations({int? projectId, bool archived = false}) async => [
        EngineConversation.fromJson({'id': 1, 'title': 'Stop-motion film ipuçları', 'updated_at': DateTime.now().toIso8601String()}),
        EngineConversation.fromJson({'id': 2, 'title': 'Q4 sunum planı', 'updated_at': '2026-10-28T10:00:00'}),
      ];
}

final _api = ArconApi(baseUrl: 'https://x.test/app/', appKey: 'a');

Future<void> _pump(WidgetTester t, Widget w) async {
  await t.pumpWidget(MaterialApp(theme: arconTheme(Brightness.light, mono: true), home: w));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('karşılama: selam, öneri kartları, geçmiş ve gizli sohbet butonları', (t) async {
    await _pump(t, TalkAiScreen(api: _api, name: 'Tuna Avşar', engine: FakeEngine()));
    expect(find.textContaining(', Tuna'), findsOneWidget);
    expect(find.text('Verimli bir toplantı gündemi hazırla'), findsOneWidget);
    expect(find.byTooltip('Sohbet geçmişi'), findsOneWidget);
    expect(find.byTooltip('Gizli sohbet'), findsOneWidget);
  });

  testWidgets('kayıtlı sohbet: uyarı, soru ve cevap balonları', (t) async {
    await _pump(t, TalkAiScreen(api: _api, name: 'Tuna', engine: FakeEngine(), conversationId: 1));
    expect(find.textContaining('yapay zekâ tarafından'), findsOneWidget);
    expect(find.text('5 stop-motion film çekme ipucu'), findsOneWidget);
    expect(find.textContaining('tutarlılık'), findsWidgets);
  });

  testWidgets('gizli sohbet koyu ekran ve uyarı', (t) async {
    await _pump(t, TalkAiScreen(api: _api, name: 'Tuna', engine: FakeEngine(), private: true));
    expect(find.text('Bu sohbeti yalnızca siz görebilirsiniz'), findsOneWidget);
    expect(find.text('Gizli sohbet'), findsOneWidget);
  });

  testWidgets('geçmiş listesi sohbetleri gösterir', (t) async {
    await _pump(t, TalkAiHistoryScreen(engine: FakeEngine()));
    expect(find.text('Q4 sunum planı'), findsOneWidget);
  });
}
