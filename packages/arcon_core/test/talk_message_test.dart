import 'package:arcon_core/arcon_core.dart';
import 'package:arcon_core/src/talk/talk_api.dart';
import 'package:arcon_core/src/talk/talk_icons.dart';
import 'package:arcon_core/src/talk/talk_message.dart';
import 'package:arcon_core/src/talk/talk_models.dart';
import 'package:arcon_core/src/talk/talk_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final api = TalkApi(arcon: ArconApi(baseUrl: 'https://x.test/app/', appKey: 'arconnect', token: 'arc_t'), baseUrl: 'https://x.test/app/');

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))));

  TalkMessage msg(String body) => TalkMessage.fromJson({
        'id': 5,
        'channel_id': 1,
        'user_id': 2,
        'display_name': 'Tuna',
        'body': body,
        'created_at': '2026-11-02 20:38:00',
      });

  testWidgets('balonu sağdan sola kaydırınca yanıtlanır; az ya da ters kaydırınca yanıtlanmaz', (t) async {
    var replies = 0;
    await t.pumpWidget(host(TalkMessageView(
      message: msg('Klavye kapanmıyor'),
      mine: false,
      api: api,
      maxWidth: 260,
      onMenu: (_) {},
      onReact: (_) {},
      onReplyTap: (_) {},
      onSwipeReply: () => replies++,
    )));
    await t.drag(find.text('Klavye kapanmıyor'), const Offset(-30, 0));
    await t.pumpAndSettle();
    expect(replies, 0);
    // soldan sağa kaydırma yanıtlamaz
    await t.drag(find.text('Klavye kapanmıyor'), const Offset(120, 0));
    await t.pumpAndSettle();
    expect(replies, 0);
    await t.drag(find.text('Klavye kapanmıyor'), const Offset(-120, 0));
    await t.pumpAndSettle();
    expect(replies, 1);
  });

  testWidgets('basılı tutunca WhatsApp menüsü: mesaj öne çıkar, üstte tepkiler, altta liste', (t) async {
    Rect? rect;
    Widget? preview;
    await t.pumpWidget(host(TalkMessageView(
      message: msg('Deneme'),
      mine: true,
      api: api,
      maxWidth: 260,
      onMenu: (_) {},
      onLongMenu: (r, p) {
        rect = r;
        preview = p;
      },
      onReact: (_) {},
      onReplyTap: (_) {},
    )));
    await t.longPress(find.text('Deneme'));
    // balonun anlık görüntüsü gerçek zamanlı alınır
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(rect, isNotNull);
    expect(preview, isA<RawImage>());
    expect(rect!.width, greaterThan(0));

    String? picked;
    final ctx = t.element(find.byType(TalkMessageView));
    showTalkMessageMenu(ctx, mine: true, canCopy: true, canEdit: true, canAskAi: true, rect: rect, preview: preview).then((v) => picked = v);
    await t.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
    for (final s in ['Cevapla', 'İlet', 'Kopyala', 'Düzenle', "ARCON AI'a Sor", 'Sil', 'Daha fazla...']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    await t.tap(find.text('😂'));
    await t.pumpAndSettle();
    expect(picked, 'react:😂');
  });

  testWidgets('balona dokununca menü açılır', (t) async {
    var menus = 0;
    await t.pumpWidget(host(TalkMessageView(
      message: msg('merhaba'),
      mine: true,
      api: api,
      maxWidth: 260,
      onMenu: (_) => menus++,
      onReact: (_) {},
      onReplyTap: (_) {},
    )));
    await t.tap(find.text('merhaba'));
    await t.pumpAndSettle();
    expect(menus, 1);
  });

  test('gün ayracı: bugün, dün, eski tarih', () {
    final now = DateTime.now();
    expect(talkDayLabel(now), 'Bugün');
    expect(talkDayLabel(now.subtract(const Duration(days: 1))), 'Dün');
    expect(talkDayLabel(DateTime(2020, 11, 2)), '2 Kasım 2020');
  });

  test('sesli mesaj eki video sayılmaz', () {
    final a = TalkAttachment.fromJson({'orig_name': 'sesli-mesaj.m4a', 'mime': 'video/mp4', 'is_video': true, 'path': 'x'});
    expect(a.isAudio, true);
    expect(a.isVideo, false);
    final v = TalkAttachment.fromJson({'orig_name': 'klip.mp4', 'mime': 'video/mp4', 'is_video': true, 'path': 'y'});
    expect(v.isAudio, false);
    expect(v.isVideo, true);
  });

  group('WhatsApp tikleri', () {
    Finder icon(String svg) => find.byWidgetPredicate((w) => w is TalkIcon && w.svg == svg);
    Future<void> pumpTick(WidgetTester t, TalkTick tick) => t.pumpWidget(host(TalkMessageView(
          message: msg('selam'),
          mine: true,
          api: api,
          maxWidth: 260,
          onMenu: (_) {},
          onReact: (_) {},
          onReplyTap: (_) {},
          tick: tick,
        )));

    testWidgets('gönderiliyor: saat', (t) async {
      await pumpTick(t, TalkTick.pending);
      expect(icon(TalkSvg.pendingClock), findsOneWidget);
      expect(icon(TalkSvg.ticks), findsNothing);
    });
    testWidgets('sunucuya ulaştı: tek tik', (t) async {
      await pumpTick(t, TalkTick.sent);
      expect(icon(TalkSvg.tick), findsOneWidget);
      expect(icon(TalkSvg.ticks), findsNothing);
    });
    testWidgets('iletildi: çift gri, okundu: çift mavi', (t) async {
      await pumpTick(t, TalkTick.delivered);
      final grey = t.widget<TalkIcon>(icon(TalkSvg.ticks));
      expect(grey.color, isNot(TalkColors.ticks));
      await pumpTick(t, TalkTick.read);
      final blue = t.widget<TalkIcon>(icon(TalkSvg.ticks));
      expect(blue.color, TalkColors.ticks);
    });
  });

  testWidgets('basılı tutunca seçim başlar, menü açılmaz', (t) async {
    var menus = 0, selects = 0;
    await t.pumpWidget(host(TalkMessageView(
      message: msg('seç beni'),
      mine: false,
      api: api,
      maxWidth: 260,
      onMenu: (_) => menus++,
      onSelect: () => selects++,
      onReact: (_) {},
      onReplyTap: (_) {},
    )));
    await t.longPress(find.text('seç beni'));
    await t.pumpAndSettle();
    expect(selects, 1);
    expect(menus, 0);
  });

  test('arama satırları tanınır', () {
    expect(talkCallLine('📞 Cevapsız sesli arama'), (video: false, missed: true, duration: ''));
    expect(talkCallLine('🎥 Görüntülü arama · 02:15'), (video: true, missed: false, duration: '02:15'));
    expect(talkCallLine('📞 Sesli arama · 1:02:03'), (video: false, missed: false, duration: '1:02:03'));
    expect(talkCallLine('sesli arama yaparız'), isNull);
  });

  testWidgets('arama balonu: gelen cevapsız kırmızı, kendi aramam "Cevap yok"', (t) async {
    var taps = 0;
    await t.pumpWidget(host(TalkCallLineView(line: (video: false, missed: true, duration: ''), mine: false, time: '14:03', onTap: () => taps++)));
    expect(find.text('Cevapsız sesli arama'), findsOneWidget);
    expect(find.text('Geri aramak için dokun'), findsOneWidget);
    await t.tap(find.text('Cevapsız sesli arama'));
    expect(taps, 1);
    await t.pumpWidget(host(TalkCallLineView(line: (video: false, missed: true, duration: ''), mine: true, time: '14:03', onTap: () {})));
    expect(find.text('Sesli arama'), findsOneWidget);
    expect(find.text('Cevap yok'), findsOneWidget);
    await t.pumpWidget(host(TalkCallLineView(line: (video: true, missed: false, duration: '02:15'), mine: true, time: '14:03', onTap: () {})));
    expect(find.text('Görüntülü arama'), findsOneWidget);
    expect(find.text('02:15'), findsOneWidget);
  });

  testWidgets('menü: tepki çubuğu + ana liste; ekstra Daha fazla altında', (t) async {
    String? picked;
    Future<void> open(bool? decided, {bool task = true, bool canEdit = false, bool mine = false}) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => picked = await showTalkMessageMenu(
              c,
              mine: mine,
              canCopy: true,
              canEdit: canEdit,
              decided: decided,
              canTask: task,
              canAskAi: true,
              at: const Offset(200, 200),
            ),
            child: const Text('menü'),
          ),
        ),
      ));
      await t.tap(find.text('menü'));
      await t.pumpAndSettle();
    }

    await open(false);
    for (final s in ['Cevapla', 'İlet', 'Kopyala', "ARCON AI'a Sor", 'Daha fazla...']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('Düzenle'), findsNothing);
    expect(find.text('Sil'), findsNothing);
    expect(find.text('Görev olarak ekle'), findsNothing);
    await t.tap(find.text('Daha fazla...'));
    await t.pumpAndSettle();
    expect(find.text('Görev olarak ekle'), findsOneWidget);
    expect(find.text('Karar olarak ekle'), findsOneWidget);
    await t.tap(find.text('Görev olarak ekle'));
    await t.pumpAndSettle();
    expect(picked, 'task');

    await open(true, mine: true, canEdit: true);
    expect(find.text('Düzenle'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);
    await t.tap(find.text('Daha fazla...'));
    await t.pumpAndSettle();
    expect(find.text('Kararı kaldır'), findsOneWidget);

    await open(null, task: false);
    expect(find.text('Daha fazla...'), findsOneWidget);
    await t.tap(find.text('Daha fazla...'));
    await t.pumpAndSettle();
    expect(find.text('Karar olarak ekle'), findsNothing);
    expect(find.text('Görev olarak ekle'), findsNothing);
    expect(find.text('Seç'), findsOneWidget);
  });

  test('düzenle yalnızca 1 dakika içinde', () {
    final now = DateTime(2026, 11, 6, 12, 0, 0);
    expect(talkCanEditMessage('2026-11-06 11:59:20', now: now, text: 'selam'), true);
    expect(talkCanEditMessage('2026-11-06 11:58:00', now: now, text: 'selam'), false);
    expect(talkCanEditMessage('2026-11-06 11:59:50', now: now, text: ''), false);
  });

  test('bilgi paneli kararları ve görevleri okur', () {
    final s = TalkSidebar.fromJson({
      'channel': {'type': 'group', 'name': 'Ekip'},
      'decisions': [
        {'message_id': 17, 'text': 'Q4 bütçesi onaylandı', 'marked_by': 'Sena', 'user_id': 2, 'created_at': '2026-11-04 15:40:25'},
      ],
      'tasks': [
        {'id': 1, 'title': 'Sözleşmeyi gönder', 'message_id': 0, 'done': true, 'created_by': 1},
        {'id': 2, 'title': 'Teklif hazırla', 'message_id': 17, 'done': false, 'created_by': 2},
      ],
    });
    expect(s.decisions.single.messageId, 17);
    expect(s.tasks.where((x) => !x.done).length, 1);
    expect(s.tasks.last.messageId, 17);
  });
}

