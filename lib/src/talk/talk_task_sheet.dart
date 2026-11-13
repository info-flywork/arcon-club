import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// "Görev olarak ekle": başlık (mesaj metniyle dolu gelir), etiketlenecek kişiler, isteğe bağlı teslim tarihi.
/// Etiketlenen her kişiye ARCON TO-DO kartı açılır ve görev grubun Görevler listesinde kişileriyle görünür.
Future<({String title, List<int> assignees, String dueDate})?> showTalkTaskSheet(
  BuildContext context, {
  required String initialTitle,
  required List<TalkUser> people,
  required String Function(String path) fileUrl,
  int? meId,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TaskSheet(initialTitle: initialTitle, people: people, fileUrl: fileUrl, meId: meId),
    );

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({required this.initialTitle, required this.people, required this.fileUrl, this.meId});
  final String initialTitle;
  final List<TalkUser> people;
  final String Function(String path) fileUrl;
  final int? meId;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late final _title = TextEditingController(text: widget.initialTitle.trim().replaceAll(RegExp(r'\s+'), ' '));
  final _picked = <int>{};
  DateTime? _due;
  String _q = '';

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _ready => _title.text.trim().isNotEmpty;

  static String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _label(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Bugün';
    if (day == today.add(const Duration(days: 1))) return 'Yarın';
    const m = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    return '${d.day} ${m[d.month - 1]}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    var pick = _due ?? DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) {
        final c = TalkColors.of(ctx);
        return Container(
          height: 300,
          color: c.dark ? const Color(0xFF1C1C1E) : Colors.white,
          child: SafeArea(
            top: false,
            child: Column(children: [
              Row(children: [
                CupertinoButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                const Spacer(),
                CupertinoButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tamam')),
              ]),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: pick,
                  minimumDate: DateTime(now.year, now.month, now.day),
                  onDateTimeChanged: (d) => pick = d,
                ),
              ),
            ]),
          ),
        );
      },
    );
    if (ok == true && mounted) setState(() => _due = pick);
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bg = c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final card = c.dark ? const Color(0xFF2C2C2E) : Colors.white;
    final q = _q.trim().toLowerCase();
    final people = widget.people.where((u) => q.isEmpty || '${u.displayName} ${u.username}'.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        if (a.id == widget.meId) return -1;
        if (b.id == widget.meId) return 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    Widget chip(String label, bool on, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: on ? c.ink : card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? c.ink : c.rowLine),
            ),
            child: Text(label, style: talkText(14, FontWeight.w500, on ? (c.dark ? Colors.black : Colors.white) : c.ink)),
          ),
        );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Vazgeç', style: talkText(17, FontWeight.w400, c.ink))),
                Expanded(child: Text('Görev olarak ekle', textAlign: TextAlign.center, style: talkText(17, FontWeight.w600, c.ink))),
                TextButton(
                  onPressed: _ready
                      ? () => Navigator.pop(context, (title: _title.text.trim(), assignees: _picked.toList(), dueDate: _due == null ? '' : _iso(_due!)))
                      : null,
                  child: Text('Ekle', style: talkText(17, FontWeight.w600, _ready ? c.ink : c.muted)),
                ),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 6, 16, 16), children: [
                _label2(c, 'Görev'),
                Container(
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                  child: TextField(
                    controller: _title,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 255,
                    onChanged: (_) => setState(() {}),
                    style: talkText(16, FontWeight.w400, c.ink),
                    cursorColor: c.ink,
                    decoration: InputDecoration(
                      counterText: '',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.all(14),
                      hintText: 'Ne yapılacak?',
                      hintStyle: talkText(16, FontWeight.w400, c.muted),
                    ),
                  ),
                ),
                _label2(c, 'Teslim tarihi'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  chip('Yok', _due == null, () => setState(() => _due = null)),
                  chip('Bugün', _due == today, () => setState(() => _due = today)),
                  chip('Yarın', _due == tomorrow, () => setState(() => _due = tomorrow)),
                  chip(_due != null && _due != today && _due != tomorrow ? _label(_due!) : 'Tarih seç…', _due != null && _due != today && _due != tomorrow, _pickDate),
                ]),
                _label2(c, _picked.isEmpty ? 'Kişileri etiketle' : 'Kişileri etiketle · ${_picked.length} kişi'),
                if (widget.people.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CupertinoSearchTextField(placeholder: 'Kişi ara', onChanged: (v) => setState(() => _q = v)),
                  ),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    for (var i = 0; i < people.length; i++)
                      InkWell(
                        onTap: () => setState(() => _picked.contains(people[i].id) ? _picked.remove(people[i].id) : _picked.add(people[i].id)),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                          decoration: BoxDecoration(border: i == people.length - 1 ? null : Border(bottom: BorderSide(color: c.rowLine, width: 0.6))),
                          child: Row(children: [
                            TalkAvatar.solid(name: people[i].displayName, photoUrl: widget.fileUrl(people[i].avatarPath), size: 36, personIfEmpty: true),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(people[i].id == widget.meId ? '${people[i].displayName} (Siz)' : people[i].displayName,
                                  style: talkText(16, FontWeight.w400, c.ink)),
                            ),
                            Icon(
                              _picked.contains(people[i].id) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                              size: 24,
                              color: _picked.contains(people[i].id) ? c.ink : c.muted,
                            ),
                          ]),
                        ),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: Text(
                    "Etiketlenen her kişiye ARCON TO-DO'da görev kartı açılır ve bildirim gider. Kimseyi seçmezsen görev yalnızca grubun Görevler listesine eklenir.",
                    style: talkText(13, FontWeight.w400, c.muted, height: 1.35),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _label2(TalkColors c, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(t, style: talkText(14, FontWeight.w600, c.muted)),
      );
}
