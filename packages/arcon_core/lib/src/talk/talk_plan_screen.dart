import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'talk_theme.dart';

class TalkCallPlan {
  const TalkCallPlan({
    required this.title,
    required this.start,
    required this.end,
    required this.video,
    required this.requireApproval,
    required this.remindMinutes,
    this.description = '',
    this.coverPath,
  });

  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
  final bool video;
  final bool requireApproval;
  final int remindMinutes;
  final String? coverPath;
}

/// WhatsApp iOS "Arama planla" tam ekran.
Future<TalkCallPlan?> showTalkCallPlanScreen(
  BuildContext context, {
  required String peerName,
  required String organizerName,
  String? title,
}) {
  return Navigator.of(context).push<TalkCallPlan>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => TalkPlanCallScreen(peerName: peerName, organizerName: organizerName, title: title),
  ));
}

class TalkPlanCallScreen extends StatefulWidget {
  const TalkPlanCallScreen({super.key, required this.peerName, required this.organizerName, this.title});
  final String peerName;
  final String organizerName;
  /// Verilmezse "X kişisinin araması" (grupta grup adıyla başlık verilir)
  final String? title;

  @override
  State<TalkPlanCallScreen> createState() => _TalkPlanCallScreenState();
}

class _TalkPlanCallScreenState extends State<TalkPlanCallScreen> {
  late final _title = TextEditingController(text: widget.title ?? '${widget.peerName} kişisinin araması');
  final _desc = TextEditingController();
  late DateTime _start = _nextSlot();
  late DateTime _end = _start.add(const Duration(minutes: 30));
  var _video = true;
  var _approve = false;
  var _remind = 15;
  String? _cover;

  static const _months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

  static DateTime _nextSlot() {
    final n = DateTime.now().add(const Duration(minutes: 30));
    return DateTime(n.year, n.month, n.day, n.hour, n.minute < 30 ? 30 : 0).add(Duration(hours: n.minute < 30 ? 0 : 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  String _d(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';
  String _h(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickWhen({required bool start, required bool date}) async {
    var v = start ? _start : _end;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: TalkColors.of(context).dark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 280,
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tamam')),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: date ? CupertinoDatePickerMode.date : CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  minuteInterval: 5,
                  initialDateTime: DateTime(v.year, v.month, v.day, v.hour, (v.minute ~/ 5) * 5),
                  minimumDate: date ? DateTime.now().subtract(const Duration(days: 1)) : null,
                  onDateTimeChanged: (d) => v = date
                      ? DateTime(d.year, d.month, d.day, v.hour, v.minute)
                      : DateTime(v.year, v.month, v.day, d.hour, d.minute),
                ),
              ),
            ]),
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    setState(() {
      if (start) {
        final dur = _end.difference(_start);
        _start = v;
        _end = _start.add(dur.isNegative || dur.inMinutes < 5 ? const Duration(minutes: 30) : dur);
      } else {
        _end = v.isAfter(_start) ? v : _start.add(const Duration(minutes: 30));
      }
    });
  }

  Future<void> _coverPick() async {
    final src = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('Fotoğraf çek')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text('Galeriden seç')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, imageQuality: 85);
    if (x != null && mounted) setState(() => _cover = x.path);
  }

  Future<void> _pickType() async {
    final v = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Sesli arama')),
          CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, true), child: const Text('Görüntülü arama')),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (v != null) setState(() => _video = v);
  }

  Future<void> _pickRemind() async {
    const opts = {0: 'Yok', 5: '5 dakika önce', 15: '15 dakika önce', 30: '30 dakika önce', 60: '1 saat önce'};
    final v = await showCupertinoModalPopup<int>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          for (final e in opts.entries)
            CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      ),
    );
    if (v != null) setState(() => _remind = v);
  }

  void _save() {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    Navigator.pop(
      context,
      TalkCallPlan(
        title: t,
        description: _desc.text.trim(),
        start: _start,
        end: _end,
        video: _video,
        requireApproval: _approve,
        remindMinutes: _remind,
        coverPath: _cover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bg = c.dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final card = c.dark ? const Color(0xFF1C1C1E) : Colors.white;
    final chip = c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE8E8ED);
    Widget pill(String text, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: chip, borderRadius: BorderRadius.circular(8)),
            child: Text(text, style: talkText(16, FontWeight.w500, c.ink)),
          ),
        );
    Widget cardBox({required List<Widget> children, EdgeInsets pad = const EdgeInsets.symmetric(horizontal: 16)}) => Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          padding: pad,
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
          child: Column(children: children),
        );
    Widget line(String left, Widget right) => SizedBox(
          height: 48,
          child: Row(children: [
            Text(left, style: talkText(17, FontWeight.w400, c.ink)),
            const Spacer(),
            right,
          ]),
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(CupertinoIcons.xmark, size: 22, color: c.ink),
                ),
                Expanded(child: Text('Arama planla', textAlign: TextAlign.center, style: talkText(17, FontWeight.w600, c.ink))),
                GestureDetector(
                  onTap: _title.text.trim().isEmpty ? null : _save,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: _title.text.trim().isEmpty ? c.muted.withValues(alpha: 0.35) : c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Planla', style: talkText(16, FontWeight.w700, _title.text.trim().isEmpty ? Colors.white : c.accentContrast)),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
                const SizedBox(height: 8),
                Center(
                  child: GestureDetector(
                    onTap: _coverPick,
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      backgroundImage: _cover == null ? null : FileImage(File(_cover!)),
                      child: _cover == null ? Icon(CupertinoIcons.camera_fill, size: 26, color: c.muted) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                cardBox(
                  pad: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  children: [
                    TextField(
                      controller: _title,
                      onChanged: (_) => setState(() {}),
                      style: talkText(22, FontWeight.w700, c.ink),
                      cursorColor: c.ink,
                      decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _desc,
                      maxLines: 2,
                      style: talkText(16, FontWeight.w400, c.ink),
                      cursorColor: c.ink,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: 'Açıklama ekle (isteğe bağlı)',
                        hintStyle: talkText(16, FontWeight.w400, c.muted),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
                cardBox(children: [
                  line('Başlangıç', Row(children: [
                    pill(_d(_start), () => _pickWhen(start: true, date: true)),
                    const SizedBox(width: 8),
                    pill(_h(_start), () => _pickWhen(start: true, date: false)),
                  ])),
                  Divider(height: 1, color: c.rowLine),
                  line('Bitiş', Row(children: [
                    pill(_d(_end), () => _pickWhen(start: false, date: true)),
                    const SizedBox(width: 8),
                    pill(_h(_end), () => _pickWhen(start: false, date: false)),
                  ])),
                ]),
                cardBox(children: [
                  GestureDetector(
                    onTap: _pickType,
                    behavior: HitTestBehavior.opaque,
                    child: line(
                      'Arama türü',
                      Row(children: [
                        Text(_video ? 'Görüntülü arama' : 'Sesli arama', style: talkText(16, FontWeight.w400, c.muted)),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.chevron_up_chevron_down, size: 14, color: c.muted),
                      ]),
                    ),
                  ),
                  Divider(height: 1, color: c.rowLine),
                  SizedBox(
                    height: 48,
                    child: Row(children: [
                      Expanded(child: Text('Katılmak için onay gereksin', style: talkText(17, FontWeight.w400, c.ink))),
                      CupertinoSwitch(value: _approve, activeTrackColor: c.accent, onChanged: (v) => setState(() => _approve = v)),
                    ]),
                  ),
                ]),
                cardBox(children: [
                  GestureDetector(
                    onTap: _pickRemind,
                    behavior: HitTestBehavior.opaque,
                    child: line(
                      'Hatırlatma',
                      Row(children: [
                        Text(
                          {0: 'Yok', 5: '5 dakika önce', 15: '15 dakika önce', 30: '30 dakika önce', 60: '1 saat önce'}[_remind] ?? '15 dakika önce',
                          style: talkText(16, FontWeight.w400, c.muted),
                        ),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.chevron_up_chevron_down, size: 14, color: c.muted),
                      ]),
                    ),
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 14),
                  child: Text('Konuklar etkinlik zamanında da bildirim alır.', style: talkText(13, FontWeight.w400, c.muted)),
                ),
                cardBox(children: [
                  line('Organizatör', Text(widget.organizerName, style: talkText(16, FontWeight.w400, c.muted))),
                ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 18),
                  child: Text("ARCONNECT'teki adınız. Ayarlar'da düzenleyin.", style: talkText(13, FontWeight.w400, c.muted)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 8),
                  child: Text.rich(
                    TextSpan(style: talkText(13, FontWeight.w400, c.muted), children: [
                      const TextSpan(text: 'Planlama detayları konuklar tarafından görülebilir. '),
                      TextSpan(text: 'Daha fazla bilgi', style: talkText(13, FontWeight.w600, c.ink)),
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
