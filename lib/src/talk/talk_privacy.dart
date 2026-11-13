import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'talk_controller.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// Kilitli sohbetler için Face ID / parmak izi / telefon şifresi. Doğrulanırsa true.
/// Telefonda ekran kilidi yoksa uyarır ve false döner.
Future<bool> talkUnlock(BuildContext context, {String reason = 'Kilitli sohbetleri açmak için doğrula'}) async {
  final auth = LocalAuthentication();
  try {
    if (!await auth.isDeviceSupported()) {
      if (context.mounted) talkToast(context, 'Sohbet kilidi için telefonda ekran kilidi (Face ID, parmak izi veya şifre) olmalı', error: true);
      return false;
    }
    return await auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
  } on PlatformException catch (e) {
    if (context.mounted) talkToast(context, e.message?.isNotEmpty == true ? e.message! : 'Doğrulanamadı', error: true);
    return false;
  } on LocalAuthException catch (e) {
    // kullanıcı vazgeçtiyse sessiz kal
    if (context.mounted && e.code != LocalAuthExceptionCode.userCanceled && e.code != LocalAuthExceptionCode.systemCanceled) {
      talkToast(context, e.description ?? 'Doğrulanamadı', error: true);
    }
    return false;
  }
}

/// Yeni liste adı sorar; boşsa null
Future<String?> askTalkListName(BuildContext context) async {
  final name = TextEditingController();
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('Yeni liste'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CupertinoTextField(controller: name, placeholder: 'Örn. İş, Aile, Proje', autofocus: true, maxLength: 30),
      ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Oluştur')),
      ],
    ),
  );
  final t = name.text.trim();
  return ok == true && t.isNotEmpty ? t : null;
}

/// WhatsApp "Listeye ekle": mevcut listelerde işaretle / çıkar, yeni liste oluştur
Future<void> showTalkListSheet(BuildContext context, TalkController ctl, int channelId) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: ctl,
        builder: (ctx, _) {
          final c = TalkColors.of(ctx);
          final bg = c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
          final card = c.dark ? const Color(0xFF2C2C2E) : Colors.white;
          final names = ctl.lists.keys.toList()..sort();
          Widget row(Widget lead, String title, VoidCallback onTap, {Widget? trailing}) => InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(children: [
                    lead,
                    const SizedBox(width: 14),
                    Expanded(child: Text(title, style: talkText(17, FontWeight.w400, c.ink))),
                    ?trailing,
                  ]),
                ),
              );
          return Container(
            decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Listeye ekle', textAlign: TextAlign.center, style: talkText(17, FontWeight.w600, c.ink)),
                  const SizedBox(height: 6),
                  Text('Listeler sohbetler ekranında çip olarak görünür.', textAlign: TextAlign.center, style: talkText(13.5, FontWeight.w400, c.muted)),
                  const SizedBox(height: 14),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                    child: Column(children: [
                      for (final n in names)
                        row(
                          Icon(CupertinoIcons.list_bullet, size: 22, color: c.ink),
                          n,
                          () => ctl.toggleInList(n, channelId),
                          trailing: Icon(
                            ctl.lists[n]!.contains(channelId) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            size: 24,
                            color: ctl.lists[n]!.contains(channelId) ? c.ink : c.muted,
                          ),
                        ),
                      row(Icon(CupertinoIcons.add, size: 22, color: c.ink), 'Yeni liste', () async {
                        final n = await askTalkListName(ctx);
                        if (n != null) await ctl.toggleInList(n, channelId);
                      }),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
