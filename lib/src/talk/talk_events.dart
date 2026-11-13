import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'talk_theme.dart';
import 'talk_widgets.dart';

/// WhatsApp "Etkinlik" / "Arama planla": sohbete düşen mesaj.
///   📅 Proje toplantısı
///   06.11.2026 15:00
/// İsteğe bağlı satırlar: end:… / call:voice|video / approve:1 / remind:15 / boş satır + açıklama
const _callTitles = {'Sesli arama planlandı': false, 'Görüntülü arama planlandı': true};

String talkFmtEventStamp(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(at.day)}.${two(at.month)}.${at.year} ${two(at.hour)}:${two(at.minute)}';
}

DateTime? talkParseEventStamp(String s) {
  final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4}) (\d{2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!));
}

String talkEventBody(
  String title,
  DateTime at, {
  DateTime? end,
  bool? video,
  bool approve = false,
  int remindMinutes = 0,
  String description = '',
}) {
  final b = StringBuffer('📅 ${title.trim()}\n${talkFmtEventStamp(at)}');
  if (end != null) b.write('\nend:${talkFmtEventStamp(end)}');
  if (video != null) b.write('\ncall:${video ? 'video' : 'voice'}');
  if (approve) b.write('\napprove:1');
  if (remindMinutes > 0) b.write('\nremind:$remindMinutes');
  final d = description.trim();
  if (d.isNotEmpty) b.write('\n\n$d');
  return b.toString();
}

String talkCallPlanTitle({required bool video}) => video ? 'Görüntülü arama planlandı' : 'Sesli arama planlandı';

typedef TalkEvent = ({String title, DateTime at, DateTime? end, bool? callVideo, bool approve, int remindMinutes, String description});

/// Mesaj bir etkinlikse alanları; değilse null.
TalkEvent? talkEventLine(String body) {
  final raw = body.trim();
  if (!raw.startsWith('📅 ')) return null;
  final parts = raw.split('\n');
  if (parts.length < 2) return null;
  final at = talkParseEventStamp(parts[1]);
  if (at == null) return null;
  final title = parts[0].substring(2).trim();
  DateTime? end;
  bool? callVideo = _callTitles[title];
  var approve = false;
  var remind = 0;
  final descLines = <String>[];
  var inDesc = false;
  for (var i = 2; i < parts.length; i++) {
    final line = parts[i];
    if (inDesc) {
      descLines.add(line);
      continue;
    }
    if (line.trim().isEmpty) {
      inDesc = true;
      continue;
    }
    if (line.startsWith('end:')) {
      end = talkParseEventStamp(line.substring(4));
    } else if (line.startsWith('call:')) {
      callVideo = line.substring(5).trim() == 'video';
    } else if (line.startsWith('approve:')) {
      approve = line.substring(8).trim() == '1';
    } else if (line.startsWith('remind:')) {
      remind = int.tryParse(line.substring(7).trim()) ?? 0;
    } else {
      inDesc = true;
      descLines.add(line);
    }
  }
  return (
    title: title,
    at: at,
    end: end,
    callVideo: callVideo,
    approve: approve,
    remindMinutes: remind,
    description: descLines.join('\n').trim(),
  );
}

const _months = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

/// "6 Kasım Perşembe · 15:00"
String talkEventWhen(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.day} ${_months[at.month - 1]} ${_days[at.weekday - 1]} · ${two(at.hour)}:${two(at.minute)}';
}

/// Sohbetteki etkinlik kartı. Planlı aramada "Ara" düğmesi aramayı başlatır.
class TalkEventCardView extends StatelessWidget {
  const TalkEventCardView({super.key, required this.event, required this.mine, required this.time, this.onCall, this.coverUrl});

  final TalkEvent event;
  final bool mine;
  final String time;
  final void Function(bool video)? onCall;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = mine ? c.bubbleOutInk : c.bubbleInInk;
    final past = event.at.isBefore(DateTime.now().subtract(const Duration(hours: 1)));
    final video = event.callVideo;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(minWidth: 230, maxWidth: 280),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: BoxDecoration(color: mine ? c.bubbleOut : c.bubbleIn, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (coverUrl != null && coverUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TalkNetImage(coverUrl!, height: 110, fit: BoxFit.cover, decodeWidth: 280, error: const SizedBox.shrink()),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: ink.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Icon(video == null ? CupertinoIcons.calendar : (video ? CupertinoIcons.video_camera : CupertinoIcons.phone), size: 21, color: ink),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: talkText(15, FontWeight.w600, ink)),
                      Text(
                        event.end == null
                            ? talkEventWhen(event.at)
                            : '${talkEventWhen(event.at)} – ${event.end!.hour.toString().padLeft(2, '0')}:${event.end!.minute.toString().padLeft(2, '0')}',
                        style: talkText(13, FontWeight.w400, ink.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (event.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(event.description, maxLines: 4, overflow: TextOverflow.ellipsis, style: talkText(13.5, FontWeight.w400, ink.withValues(alpha: 0.8))),
              ),
            if (video != null && onCall != null && !past) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => onCall!(video),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: ink.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
                  child: Text(event.approve ? 'Katılmayı iste' : (video ? 'Görüntülü katıl' : 'Ara'), style: talkText(14, FontWeight.w600, ink)),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(time, style: talkText(10.88, FontWeight.w400, ink.withValues(alpha: 0.55), height: 1)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etkinlik / planlı arama oluşturma: başlık (etkinlikte), tarih-saat ve (aramada) sesli/görüntülü.
/// Seçilenleri döner; vazgeçilirse null.
Future<({String title, DateTime at, bool video})?> showTalkEventSheet(BuildContext context, {required bool call}) {
  return showModalBottomSheet<({String title, DateTime at, bool video})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EventSheet(call: call),
  );
}

class _EventSheet extends StatefulWidget {
  const _EventSheet({required this.call});
  final bool call;

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  final _title = TextEditingController();
  late DateTime _at = _nextSlot();
  bool _video = false;

  /// Bir sonraki yarım saat
  static DateTime _nextSlot() {
    final n = DateTime.now().add(const Duration(minutes: 30));
    return DateTime(n.year, n.month, n.day, n.hour, n.minute < 30 ? 30 : 0).add(Duration(hours: n.minute < 30 ? 0 : 1));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _done() {
    final t = _title.text.trim();
    if (!widget.call && t.isEmpty) return;
    Navigator.pop(context, (title: widget.call ? talkCallPlanTitle(video: _video) : t, at: _at, video: _video));
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bg = c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final card = c.dark ? const Color(0xFF2C2C2E) : Colors.white;
    final canSave = widget.call || _title.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Vazgeç', style: talkText(17, FontWeight.w400, c.ink)),
                    ),
                    Expanded(
                      child: Text(widget.call ? 'Arama planla' : 'Yeni etkinlik', textAlign: TextAlign.center, style: talkText(17, FontWeight.w600, c.ink)),
                    ),
                    TextButton(
                      onPressed: canSave ? _done : null,
                      child: Text(widget.call ? 'Planla' : 'Oluştur', style: talkText(17, FontWeight.w600, canSave ? c.ink : c.muted)),
                    ),
                  ],
                ),
              ),
              if (!widget.call)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                  child: TextField(
                    controller: _title,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: talkText(17, FontWeight.w400, c.ink),
                    cursorColor: c.ink,
                    decoration: InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Etkinlik adı',
                      hintStyle: talkText(17, FontWeight.w400, c.muted),
                    ),
                  ),
                ),
              if (widget.call)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: CupertinoSlidingSegmentedControl<bool>(
                    groupValue: _video,
                    onValueChanged: (v) => setState(() => _video = v ?? false),
                    children: {
                      false: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('Sesli', style: talkText(15, FontWeight.w500, c.ink)),
                      ),
                      true: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('Görüntülü', style: talkText(15, FontWeight.w500, c.ink)),
                      ),
                    },
                  ),
                ),
              Container(
                height: 216,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                child: CupertinoTheme(
                  data: CupertinoThemeData(brightness: c.dark ? Brightness.dark : Brightness.light),
                  child: CupertinoDatePicker(
                    initialDateTime: _at,
                    minimumDate: DateTime.now().subtract(const Duration(minutes: 1)),
                    minuteInterval: 5,
                    use24hFormat: true,
                    onDateTimeChanged: (d) => _at = d,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
