import 'dart:convert';

import 'package:arcon_core/arcon_core.dart';
import 'package:arcon_core/src/talk/talk_controller.dart';
import 'package:arcon_core/src/talk/talk_home_screen.dart';
import 'package:arcon_core/src/ui/theme_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

String _ago(Duration d) => DateTime.now().subtract(d).toString().substring(0, 19);

final _boot = {
  'ok': true,
  'me': {'user_id': 1, 'username': 'sena', 'display_name': 'Sena Yılmaz'},
  'channels': [
    {'id': 3, 'type': 'group', 'name': 'Flywork Rapor Grubu', 'unread': 2, 'last_body': 'toplantı konusu copilot', 'last_at': _ago(const Duration(minutes: 5)), 'last_user_id': 1, 'last_read_all': true},
    {'id': 4, 'type': 'dm', 'name': 'Emrah', 'unread': 0, 'last_body': 'tamamdır teşekkür ederim', 'last_at': _ago(const Duration(days: 1)), 'last_user_id': 1, 'peer': {'id': 2, 'username': 'emrah', 'display_name': 'Emrah'}},
    {'id': 5, 'type': 'dm', 'name': 'Furkan', 'unread': 0, 'last_body': '📞 Cevapsız sesli arama', 'last_at': _ago(const Duration(days: 3)), 'peer': {'id': 3, 'username': 'furkan', 'display_name': 'Furkan'}},
  ],
  'users': [
    {'id': 1, 'username': 'sena', 'display_name': 'Sena Yılmaz'},
    {'id': 2, 'username': 'emrah', 'display_name': 'Emrah', 'about': 'Müsait'},
    {'id': 3, 'username': 'furkan', 'display_name': 'Furkan', 'department': 'Yazılım'},
  ],
};

/// [club]: ARCON Club menüsünden açılmış gibi (altında Club sayfası, appMode: false)
Future<void> pumpHome(WidgetTester t, {bool dark = false, bool club = false}) async {
  SharedPreferences.setMockInitialValues({'arcon-theme': dark ? 'dark' : 'light'});
  final client = MockClient((req) async {
    final a = req.url.queryParameters['action'] ?? req.url.path;
    if (a.contains('bootstrap')) return _json(_boot);
    if (a == 'messages') {
      return _json({
        'ok': true,
        'messages': [
          {'id': 10, 'channel_id': 4, 'user_id': 2, 'display_name': 'Emrah', 'body': 'Selam, rapor hazır mı?', 'created_at': _ago(const Duration(minutes: 30))},
          {'id': 11, 'channel_id': 4, 'user_id': 1, 'display_name': 'Sena Yılmaz', 'body': 'Evet, az önce gönderdim 👍', 'created_at': _ago(const Duration(minutes: 20))},
          {'id': 12, 'channel_id': 4, 'user_id': 2, 'display_name': 'Emrah', 'body': 'tamamdır teşekkür ederim', 'created_at': _ago(const Duration(minutes: 10))},
        ],
        'typing': [],
        'read_upto': _ago(const Duration(minutes: 15)),
        'delivered_upto': _ago(const Duration(minutes: 1)),
      });
    }
    if (a.contains('call_history')) {
      return _json({
        'ok': true,
        'calls': [
          {'id': 91, 'channel_id': 5, 'video': 1, 'outgoing': 0, 'missed': 1, 'created_at': _ago(const Duration(days: 1)), 'name': 'Furkan', 'is_dm': 1},
        ],
      });
    }
    return _json({'ok': false, 'error': {'code': 'x', 'message': 'x'}}, 500);
  });
  final session = SessionController(api: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'arconnect', client: client, token: 'arc_t'), store: MemoryTokenStore());
  final theme = ArconThemeController()..value = dark ? ThemeMode.dark : ThemeMode.light;
  final talk = TalkHomeScreen(
    session: session,
    appMode: !club,
    config: const ArconAppConfig(appKey: 'arconnect', title: 'ARCONNECT', apiBase: 'https://x.test/app/'),
  );
  // TalkApi kendi http.Client'ını kurar: kurulum anında sahte istemciyi verelim
  await http.runWithClient(() => t.pumpWidget(ArconThemeScope(
    controller: theme,
    child: MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      // Club: "/" Club sayfası, üstünde "/talk" (Club menüsünden açılmış gibi)
      initialRoute: club ? '/talk' : '/',
      routes: {
        '/': (_) => club ? const Scaffold(body: Text('Club ana sayfa')) : talk,
        if (club) '/talk': (_) => talk,
      },
    ),
  )), () => client);
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 25));
}

void main() {
  testWidgets('ana ekran WhatsApp iOS düzeninde: büyük başlık, çipler, yüzen menü', (t) async {
    await pumpHome(t);
    expect(find.text('Sohbetler'), findsNWidgets(2)); // büyük başlık + alt menü
    for (final s in ['Tümü', 'Okunmamış 1', 'Favoriler', 'Gruplar', 'Aramalar', 'Siz']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.text("ARCON AI'a sor veya ara"), findsOneWidget);
    expect(find.byTooltip('ARCON AI'), findsOneWidget);
    expect(find.text('Flywork Rapor Grubu'), findsOneWidget);
    expect(find.textContaining('Cevapsız sesli arama'), findsOneWidget);
    expect(find.textContaining('Siz: '), findsOneWidget); // grupta son mesaj benim
    await close(t);
  });

  testWidgets("ARCON Club içinden açılınca Geri butonu Club'a döner; ARCONNECT uygulamasında yok", (t) async {
    await pumpHome(t);
    expect(find.byTooltip('Geri'), findsNothing);
    await close(t);

    await pumpHome(t, club: true);
    expect(find.byTooltip('Geri'), findsOneWidget);
    await t.tap(find.byTooltip('Geri'));
    await t.pumpAndSettle();
    expect(find.text('Club ana sayfa'), findsOneWidget);
    await close(t);
  });

  testWidgets('aramada Vazgeç yok; dışarı basınca klavye kapanır', (t) async {
    await pumpHome(t);
    await t.tap(find.text("ARCON AI'a sor veya ara"));
    await t.pump();
    await t.enterText(find.byType(TextField).first, 'flyw');
    await t.pump();
    expect(find.text('Vazgeç'), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    expect(t.testTextInput.isVisible, isFalse);
    await close(t);
  });

  testWidgets('basılı tutunca seçim açılır; alt menü işlemlere döner', (t) async {
    await pumpHome(t);
    await t.longPress(find.text('Emrah'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('1 seçildi'), findsOneWidget);
    for (final s in ['Favori', 'Sessiz', 'Arşivle', 'Sil']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    await t.tap(find.text('Arşivle'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Emrah'), findsNothing); // arşive gitti
    expect(find.text('Arşivlenmiş'), findsOneWidget);
    // seçim kapanınca + yine çalışır
    await t.tap(find.byTooltip('Yeni sohbet'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Yeni sohbet'), findsOneWidget);
    await close(t);
  });

  testWidgets('Arşivlenmiş satırı arşiv listesini açar', (t) async {
    await pumpHome(t);
    await t.longPress(find.text('Emrah'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Arşivle'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('Arşivlenmiş'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Bu sohbetler arşivde kalır. Çıkarmak için sohbete basılı tut.'), findsOneWidget);
    expect(find.text('Emrah'), findsOneWidget);
    await close(t);
  });

  testWidgets('siyah + Yeni sohbet ekranını açar', (t) async {
    await pumpHome(t);
    await t.tap(find.byTooltip('Yeni sohbet'));
    await t.pumpAndSettle();
    expect(find.text('Yeni sohbet'), findsOneWidget);
    // WhatsApp iOS: topluluk hariç işlemler, sık görüşülenler, harf bölümleri
    for (final s in ['Yeni grup', 'Yeni kişi', 'Yeni toplu mesaj', 'Yeni etkinlik', 'Sık görüşülenler', "ARCONNECT'teki kişiler"]) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    // harf bölümü başlığı + sağdaki dizin
    expect(find.text('E'), findsNWidgets(2));
    expect(find.text('F'), findsNWidgets(2));
    expect(find.text('Yeni topluluk'), findsNothing);
    expect(find.text('Müsait'), findsOneWidget);
    expect(find.text('Sena Yılmaz (Siz)'), findsOneWidget);
    expect(find.text('Kendinize mesaj gönderin'), findsOneWidget);
    await close(t);
  });

  testWidgets('… menüsünde yalnızca Sohbet seç ve Tümü okundu var', (t) async {
    await pumpHome(t);
    await t.tap(find.byTooltip('Diğer').first);
    await t.pumpAndSettle();
    expect(find.text('Sohbet seç'), findsOneWidget);
    expect(find.text('Tümü okundu'), findsOneWidget);
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
    await t.tap(find.text('Tümü okundu'));
    await t.pumpAndSettle();
    expect(find.text('Okunmamış 1'), findsNothing); // okunmamış sayacı sıfırlandı
    await close(t);
  });

  testWidgets('sola kaydırınca Diğer ve Arşivle çıkar; Arşivle sohbeti arşive alır', (t) async {
    await pumpHome(t);
    await t.drag(find.text('Emrah'), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(find.text('Diğer'), findsOneWidget);
    expect(find.text('Arşivle'), findsOneWidget);
    await t.tap(find.text('Arşivle'));
    await t.pumpAndSettle();
    expect(find.text('Emrah'), findsNothing);
    expect(find.text('Arşivlenmiş'), findsOneWidget);
    await close(t);
  });

  testWidgets('Diğer: WhatsApp sayfası (başlık + işlemler + ayrı kırmızı satır)', (t) async {
    await pumpHome(t);
    await t.drag(find.text('Emrah'), const Offset(-300, 0));
    await t.pumpAndSettle();
    await t.tap(find.text('Diğer'));
    await t.pumpAndSettle();
    for (final s in ['Sessiz', 'Kişi bilgisi', 'Sohbeti kilitle', "Favoriler'e ekle", 'Listeye ekle', 'Sohbeti temizle', 'Sohbeti sil']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    await t.tap(find.byIcon(CupertinoIcons.xmark));
    await t.pumpAndSettle();
    expect(find.text('Sohbeti temizle'), findsNothing);
    await close(t);
  });

  testWidgets('aramayı sola kaydırınca … ve sil çıkar; sil kaydı listeden kaldırır', (t) async {
    await pumpHome(t);
    await t.tap(find.text('Aramalar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Cevapsız'), findsOneWidget);
    await t.drag(find.text('Cevapsız'), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(find.byTooltip('Sil'), findsOneWidget);
    await t.tap(find.byTooltip('Sil'));
    await t.pumpAndSettle();
    expect(find.text('Cevapsız'), findsNothing);
    expect(find.text('Henüz arama yok'), findsOneWidget);
    await close(t);
  });

  testWidgets('özel liste çipi listeyi süzer; kilitli sohbet listede görünmez', (t) async {
    await pumpHome(t);
    final state = t.state(find.byType(TalkHomeScreen)) as dynamic;
    final ctl = state.controllerForTest as TalkController;
    await ctl.toggleInList('İş', 4); // Emrah
    await t.pump();
    expect(find.text('İş'), findsOneWidget);
    await t.tap(find.text('İş'));
    await t.pump();
    expect(find.text('Emrah'), findsOneWidget);
    expect(find.text('Flywork Rapor Grubu'), findsNothing);
    await t.tap(find.text('Tümü'));
    await ctl.toggleLock(4);
    await t.pump();
    expect(find.text('Emrah'), findsNothing);
    expect(find.text('Kilitli sohbetler'), findsOneWidget);
    await close(t);
  });

  testWidgets('Aramalar ve Siz sekmeleri', (t) async {
    await pumpHome(t);
    await t.tap(find.text('Aramalar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('En Son'), findsOneWidget);
    for (final s in ['Ara', 'Planla', 'Görüntülü', 'Favoriler']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    await t.tap(find.text('Siz'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Sena Yılmaz'), findsOneWidget);
    expect(find.text('@sena'), findsOneWidget);
    expect(find.text('Arşivlenmiş'), findsOneWidget);
    await close(t);
  });
}
