import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// Grupta yönetici işlemleri (yalnızca grubu yönetebilen görür; sahibe uygulanmaz)
typedef TalkMemberAdmin = ({bool isAdmin, VoidCallback onToggleAdmin, VoidCallback onRemove});

/// WhatsApp iOS kişi kartı: fotoğraf, ad, Mesaj / Sesli / Görüntülü; grupta Bilgi ve yönetici işlemleri.
Future<void> showTalkContactSheet({
  required BuildContext context,
  required TalkUser user,
  required String photoUrl,
  required VoidCallback onMessage,
  required VoidCallback onVoice,
  required VoidCallback onVideo,
  VoidCallback? onInfo,
  TalkMemberAdmin? admin,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = TalkColors.of(ctx);
      final bg = c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
      final card = c.dark ? const Color(0xFF2C2C2E) : Colors.white;
      void run(VoidCallback action) {
        Navigator.pop(ctx);
        action();
      }

      final sub = [
        if (user.username.isNotEmpty) '@${user.username}',
        if (user.department.isNotEmpty) user.department,
      ];
      final rows = <(IconData, String, VoidCallback, bool)>[
        if (admin != null)
          (
            admin.isAdmin ? CupertinoIcons.person_crop_circle_badge_minus : CupertinoIcons.person_crop_circle_badge_checkmark,
            admin.isAdmin ? 'Yöneticilikten çıkar' : 'Grup yöneticisi yap',
            admin.onToggleAdmin,
            false,
          ),
        if (onInfo != null) (CupertinoIcons.info_circle, 'Bilgi', onInfo, false),
        if (admin != null) (CupertinoIcons.minus_circle, 'Gruptan çıkar', admin.onRemove, true),
      ];

      return Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: 'Kapat',
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: card, shape: BoxShape.circle, border: Border.all(color: c.rowLine)),
                      child: Icon(Icons.close, size: 22, color: c.ink),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -18),
                child: TalkAvatar.solid(name: user.displayName, photoUrl: photoUrl, size: 104, fontSize: 34, personIfEmpty: true),
              ),
              Text(user.displayName, textAlign: TextAlign.center, style: talkText(26, FontWeight.w700, c.ink)),
              for (final s in sub) ...[
                const SizedBox(height: 2),
                Text(s, textAlign: TextAlign.center, style: talkText(15, FontWeight.w400, c.muted)),
              ],
              const SizedBox(height: 18),
              Row(children: [
                _act(c, card, CupertinoIcons.chat_bubble, 'Mesaj', () => run(onMessage)),
                const SizedBox(width: 10),
                _act(c, card, CupertinoIcons.phone, 'Sesli', () => run(onVoice)),
                const SizedBox(width: 10),
                _act(c, card, CupertinoIcons.video_camera, 'Görüntülü', () => run(onVideo)),
              ]),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    for (var i = 0; i < rows.length; i++)
                      InkWell(
                        onTap: () => run(rows[i].$3),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 18),
                          child: Row(children: [
                            Icon(rows[i].$1, size: 24, color: rows[i].$4 ? TalkColors.dangerSolid : c.ink),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Container(
                                height: 54,
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: c.rowLine, width: 0.6)),
                                ),
                                child: Text(rows[i].$2, style: talkText(17, FontWeight.w400, rows[i].$4 ? TalkColors.dangerSolid : c.ink)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
      );
    },
  );
}

Widget _act(TalkColors c, Color bg, IconData icon, String label, VoidCallback onTap) {
  return Expanded(
    child: Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          height: 70,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: c.ink, size: 24),
            const SizedBox(height: 6),
            Text(label, style: talkText(15, FontWeight.w400, c.ink)),
          ]),
        ),
      ),
    ),
  );
}
