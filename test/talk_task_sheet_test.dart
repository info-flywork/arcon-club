import 'package:arcon_club/src/talk/talk_models.dart';
import 'package:arcon_club/src/talk/talk_task_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('görev sayfası: başlık mesajdan gelir, etiketlenen kişiler ve tarih döner', (t) async {
    ({String title, List<int> assignees, String dueDate})? res;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => res = await showTalkTaskSheet(
            c,
            initialTitle: 'Raporu   cuma günü\\ngönder',
            people: const [
              TalkUser(id: 1, username: 'sena', displayName: 'Sena'),
              TalkUser(id: 2, username: 'anilcan', displayName: 'Anılcan'),
              TalkUser(id: 3, username: 'emrah', displayName: 'Emrah'),
            ],
            fileUrl: (p) => p,
            meId: 1,
          ),
          child: const Text('aç'),
        ),
      ),
    ));
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
    expect(find.text('Raporu cuma günü\\ngönder'), findsOneWidget);
    expect(find.text('Sena (Siz)'), findsOneWidget);
    await t.tap(find.text('Anılcan'));
    await t.tap(find.text('Emrah'));
    await t.tap(find.text('Yarın'));
    await t.pump();
    expect(find.text('Kişileri etiketle · 2 kişi'), findsOneWidget);
    await t.tap(find.text('Ekle'));
    await t.pumpAndSettle();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(res!.title, 'Raporu cuma günü\\ngönder');
    expect(res!.assignees..sort(), [2, 3]);
    expect(res!.dueDate, '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}');
  });
}
