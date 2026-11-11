import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../talk/talk_theme.dart';
import 'todo_api.dart';
import 'todo_board_screen.dart';
import 'todo_models.dart';
import 'todo_theme.dart';

/// Kart detayı (Trello kart penceresi): liste seçimi, tamamlandı dairesi, başlık,
/// üye, etiket, bitiş tarihi, açıklama, yorumlar ve etkinlik.
class TodoCardScreen extends StatefulWidget {
  const TodoCardScreen({
    super.key,
    required this.api,
    required this.boot,
    required this.task,
    required this.session,
  });

  final TodoApi api;
  final TodoBootstrap boot;
  final TodoTask task;
  final SessionController session;

  @override
  State<TodoCardScreen> createState() => _TodoCardScreenState();
}

class _TodoCardScreenState extends State<TodoCardScreen> {
  late TodoTask _t = widget.task;
  List<TodoComment> _comments = [];
  bool _loadingComments = true;
  bool _editingDesc = false;
  bool _editingTitle = false;
  bool _showDetails = true;
  late final _title = TextEditingController(text: _t.title);
  late final _desc = TextEditingController(text: _t.description);
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _comment.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final r = await widget.api.get(_t.id);
      if (!mounted) return;
      setState(() {
        _t = r.task;
        _comments = r.comments;
        _loadingComments = false;
        if (!_editingTitle) _title.text = _t.title;
        if (!_editingDesc) _desc.text = _t.description;
      });
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );

  Future<void> _update(Map<String, Object?> fields) async {
    try {
      final t = await widget.api.update(_t.id, fields);
      if (mounted) setState(() => _t = t..commentCount = _comments.length);
    } on ArconApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _setStatus(String status) async {
    if (status == _t.status) return;
    try {
      await widget.api.move(_t.id, status, 0);
      if (mounted) setState(() => _t.status = status);
    } on ArconApiException catch (e) {
      _toast(e.message);
    }
  }

  String _statusName(String key) => widget.boot.statuses
      .firstWhere((s) => s.key == key, orElse: () => MapEntry(key, key))
      .value;

  Future<void> _pickStatus() async {
    final c = TodoColors.of(context);
    final s = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.sheetBg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Listeye taşı',
                style: todoText(15, FontWeight.w700, c.ink),
              ),
            ),
            for (final st in widget.boot.statuses)
              ListTile(
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: TodoColors.statusAccent(st.key),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  st.value,
                  style: todoText(15, FontWeight.w600, c.ink),
                ),
                trailing: st.key == _t.status
                    ? Icon(Icons.check_rounded, color: c.ink)
                    : null,
                onTap: () => Navigator.pop(ctx, st.key),
              ),
          ],
        ),
      ),
    );
    if (s != null) await _setStatus(s);
  }

  Future<void> _pickMember() async {
    final p = await showModalBottomSheet<TodoPerson>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TodoColors.of(context).sheetBg,
      showDragHandle: true,
      builder: (ctx) =>
          _PeoplePicker(people: widget.boot.people, selected: _t.assigneeId),
    );
    if (p != null) await _update({'assignee_id': p.id});
  }

  Future<void> _pickLabel() async {
    final c = TodoColors.of(context);
    final tags = {
      ...widget.boot.departments,
      if (_t.tag.isNotEmpty) _t.tag,
    }.toList();
    final v = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.sheetBg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'Etiketler',
                style: todoText(15, FontWeight.w700, c.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              for (final tag in tags)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: TodoColors.label(tag),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, tag),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tag,
                                style: todoText(
                                  14,
                                  FontWeight.w600,
                                  const Color(0xFF1D2125),
                                ),
                              ),
                            ),
                            if (tag == _t.tag)
                              const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: Color(0xFF1D2125),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, '\u0000new'),
                child: const Text('Yeni etiket oluştur'),
              ),
            ],
          ),
        ),
      ),
    );
    if (v == null) return;
    if (v == '\u0000new') {
      if (!mounted) return;
      final name = await showTodoTextPrompt(
        context,
        title: 'Yeni etiket',
        hint: 'Etiket adı',
      );
      if (name != null && name.trim().isNotEmpty)
        await _update({'tag': name.trim()});
      return;
    }
    await _update({'tag': v});
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _t.dueDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('tr'),
      helpText: 'Bitiş tarihi',
      cancelText: 'Vazgeç',
      confirmText: 'Kaydet',
    ).catchError((_) => null);
    if (d != null) await _update({'due_date': todoIsoDate(d)});
  }

  Future<void> _pickScope() async {
    await _update({'scope': _t.scope == 'team' ? 'personal' : 'team'});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kart silinsin mi?'),
        content: const Text('Kart ve yorumları kalıcı olarak silinir.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC9372C),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete(_t.id);
      if (mounted) Navigator.of(context).pop();
    } on ArconApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _sendComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.addComment(_t.id, body);
      _comment.clear();
      _commentFocus.unfocus();
      await _fetch();
    } on ArconApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(TodoComment cm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yorum silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteComment(cm.id);
      await _fetch();
    } on ArconApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.sheetBg,
        body: SafeArea(
          child: Column(
            children: [
              _header(c),
              Divider(height: 1, color: c.fieldBorder),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                    children: [
                      _titleRow(c),
                      const SizedBox(height: 18),
                      _meta(c),
                      const SizedBox(height: 26),
                      _section(c, Icons.notes_rounded, 'Açıklama'),
                      const SizedBox(height: 10),
                      _description(c),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: _section(
                              c,
                              Icons.chat_outlined,
                              'Yorumlar ve etkinlik',
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                setState(() => _showDetails = !_showDetails),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.ink,
                              side: BorderSide(color: c.fieldBorder),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: Text(
                              _showDetails
                                  ? 'Detayları gizle'
                                  : 'Detayları göster',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _commentBox(c),
                      const SizedBox(height: 14),
                      if (_showDetails) ..._activity(c),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(TodoColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
    child: Row(
      children: [
        Material(
          color: c.chip,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: _pickStatus,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusName(_t.status),
                    style: todoText(15, FontWeight.w600, c.ink),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded, color: c.ink),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_horiz_rounded, color: c.ink),
          onSelected: (v) {
            if (v == 'delete') _delete();
            if (v == 'scope') _pickScope();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'scope',
              child: Text(
                _t.scope == 'team' ? 'Kişisel karta çevir' : 'Ekip kartı yap',
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text(
                'Kartı sil',
                style: TextStyle(color: Color(0xFFC9372C)),
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.close_rounded, color: c.ink),
        ),
      ],
    ),
  );

  Widget _titleRow(TodoColors c) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 6, right: 12),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _setStatus(_t.isDone ? 'todo' : 'done'),
          child: Icon(
            _t.isDone
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 26,
            color: _t.isDone ? const Color(0xFF4BCE97) : c.muted,
          ),
        ),
      ),
      Expanded(
        child: _editingTitle
            ? TextField(
                controller: _title,
                autofocus: true,
                maxLines: null,
                style: todoText(26, FontWeight.w700, c.ink, height: 1.2),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _saveTitle(),
                onTapOutside: (_) => _saveTitle(),
              )
            : GestureDetector(
                onTap: () => setState(() => _editingTitle = true),
                child: Text(
                  _t.title,
                  style: todoText(26, FontWeight.w700, c.ink, height: 1.2),
                ),
              ),
      ),
    ],
  );

  void _saveTitle() {
    final v = _title.text.trim();
    setState(() => _editingTitle = false);
    if (v.isNotEmpty && v != _t.title) _update({'title': v});
  }

  Widget _meta(TodoColors c) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(s, style: todoText(13, FontWeight.w700, c.muted)),
    );
    Widget plus(VoidCallback onTap) => InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.chip,
          border: Border.all(color: c.fieldBorder),
        ),
        child: Icon(Icons.add_rounded, color: c.ink, size: 20),
      ),
    );
    return Wrap(
      spacing: 28,
      runSpacing: 18,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            label('Üyeler'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_t.assigneeId != null) ...[
                  GestureDetector(
                    onTap: _pickMember,
                    child: TodoAvatar(
                      name: _t.assigneeName,
                      seed: _t.assigneeName,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                plus(_pickMember),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            label('Etiketler'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_t.tag.isNotEmpty) ...[
                  InkWell(
                    onTap: _pickLabel,
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: TodoColors.label(_t.tag),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _t.tag,
                        style: todoText(
                          14,
                          FontWeight.w600,
                          const Color(0xFF1D2125),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                plus(_pickLabel),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            label('Bitiş Tarihi'),
            InkWell(
              onTap: _pickDue,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.field,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.fieldBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t.dueDate == null ? 'Tarih ekle' : todoDate(_t.dueDate!),
                      style: todoText(14.5, FontWeight.w500, c.ink),
                    ),
                    if (_t.isOverdue) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0x33F87168)
                              : const Color(0xFFFFD5D2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'Tarihi geçmiş',
                          style: todoText(
                            12.5,
                            FontWeight.w600,
                            isDark
                                ? const Color(0xFFFD9891)
                                : const Color(0xFFAE2E24),
                          ),
                        ),
                      ),
                    ] else if (_t.isDone && _t.dueDate != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x334BCE97),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'Tamamlandı',
                          style: todoText(
                            12.5,
                            FontWeight.w600,
                            const Color(0xFF4BCE97),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: c.ink,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_t.dueDate != null)
              TextButton(
                onPressed: () => _update({'due_date': ''}),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: Text(
                  'Tarihi kaldır',
                  style: todoText(12.5, FontWeight.w500, c.muted),
                ),
              ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            label('Görünürlük'),
            InkWell(
              onTap: _pickScope,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.chip,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _t.scope == 'team'
                          ? Icons.groups_2_outlined
                          : Icons.lock_outline_rounded,
                      size: 18,
                      color: c.ink,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _t.scope == 'team' ? 'Ekip' : 'Kişisel',
                      style: todoText(14.5, FontWeight.w500, c.ink),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(TodoColors c, IconData icon, String title) => Row(
    children: [
      Icon(icon, color: c.ink, size: 24),
      const SizedBox(width: 12),
      Text(title, style: todoText(16.5, FontWeight.w700, c.ink)),
    ],
  );

  Widget _description(TodoColors c) {
    if (!_editingDesc) {
      final empty = _t.description.trim().isEmpty;
      return Padding(
        padding: const EdgeInsets.only(left: 36),
        child: InkWell(
          onTap: () => setState(() => _editingDesc = true),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: empty ? c.chip : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: empty ? Border.all(color: c.fieldBorder) : null,
            ),
            child: Text(
              empty ? 'Daha ayrıntılı bir açıklama ekleyin…' : _t.description,
              style: todoText(
                14.5,
                FontWeight.w400,
                empty ? c.muted : c.ink,
                height: 1.45,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _desc,
            autofocus: true,
            minLines: 4,
            maxLines: 12,
            style: todoText(14.5, FontWeight.w400, c.ink, height: 1.45),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.field,
              hintText:
                  'Daha ayrıntılı bir açıklama ekleyin… (@kullanıcı ile etiketle)',
              hintStyle: todoText(14.5, FontWeight.w400, c.muted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.fieldBorder),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(
                onPressed: () {
                  setState(() => _editingDesc = false);
                  if (_desc.text.trim() != _t.description.trim())
                    _update({'description': _desc.text});
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0C66E4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('Kaydet'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() {
                  _editingDesc = false;
                  _desc.text = _t.description;
                }),
                child: Text('Vazgeç', style: TextStyle(color: c.ink)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _commentBox(TodoColors c) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: TextField(
          controller: _comment,
          focusNode: _commentFocus,
          minLines: 1,
          maxLines: 6,
          style: todoText(14.5, FontWeight.w400, c.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: c.field,
            hintText: 'Yorum yaz…',
            hintStyle: todoText(14.5, FontWeight.w400, c.muted),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.fieldBorder),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        onPressed: _sending ? null : _sendComment,
        style: IconButton.styleFrom(backgroundColor: const Color(0xFF0C66E4)),
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    ],
  );

  List<Widget> _activity(TodoColors c) {
    if (_loadingComments) {
      return const [
        Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final me = widget.boot.meId;
    final items = <Widget>[
      for (final cm in _comments.reversed)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TodoAvatar(name: cm.name, seed: cm.name, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          cm.name,
                          style: todoText(14.5, FontWeight.w700, c.ink),
                        ),
                        Text(
                          talkMsgTime(cm.createdAt),
                          style:
                              todoText(
                                12.5,
                                FontWeight.w500,
                                const Color(0xFF579DFF),
                              ).copyWith(
                                decoration: TextDecoration.underline,
                                decorationColor: const Color(0xFF579DFF),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onLongPress: cm.userId == me
                          ? () => _deleteComment(cm)
                          : null,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: c.field,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.fieldBorder),
                        ),
                        child: _mentionText(cm.body, c),
                      ),
                    ),
                    if (cm.userId == me)
                      TextButton(
                        onPressed: () => _deleteComment(cm),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 26),
                        ),
                        child: Text(
                          'Sil',
                          style: todoText(12.5, FontWeight.w500, c.muted)
                              .copyWith(
                                decoration: TextDecoration.underline,
                                decorationColor: c.muted,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      // Etkinlik: kartın oluşturulması
      if (_t.createdAt.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TodoAvatar(name: _creatorName(), seed: _creatorName(), size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _creatorName(),
                            style: todoText(14.5, FontWeight.w700, c.ink),
                          ),
                          TextSpan(
                            text:
                                ' bu kartı ${_statusName('todo')} listesine ekledi',
                            style: todoText(14.5, FontWeight.w400, c.ink),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      talkMsgTime(_t.createdAt),
                      style:
                          todoText(
                            12.5,
                            FontWeight.w500,
                            const Color(0xFF579DFF),
                          ).copyWith(
                            decoration: TextDecoration.underline,
                            decorationColor: const Color(0xFF579DFF),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
    if (items.isEmpty) {
      return [
        Text('Henüz yorum yok.', style: todoText(14, FontWeight.w400, c.muted)),
      ];
    }
    return items;
  }

  String _creatorName() {
    for (final p in widget.boot.people) {
      if (p.id == _t.createdBy) return p.name;
    }
    return widget.boot.meId == _t.createdBy ? widget.boot.meName : 'Biri';
  }

  /// @kullanıcı etiketleri hap içinde (web/Trello gibi).
  Widget _mentionText(String body, TodoColors c) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'@[\wçğıöşüÇĞİÖŞÜ.\-]+');
    var last = 0;
    for (final m in re.allMatches(body)) {
      if (m.start > last)
        spans.add(TextSpan(text: body.substring(last, m.start)));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              m.group(0)!,
              style: todoText(14, FontWeight.w500, c.muted),
            ),
          ),
        ),
      );
      last = m.end;
    }
    if (last < body.length) spans.add(TextSpan(text: body.substring(last)));
    return Text.rich(
      TextSpan(
        style: todoText(14.5, FontWeight.w400, c.ink, height: 1.4),
        children: spans,
      ),
    );
  }
}

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.people, required this.selected});
  final List<TodoPerson> people;
  final int? selected;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final q = _q.toLowerCase();
    final list = widget.people
        .where(
          (p) =>
              q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.department.toLowerCase().contains(q),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Text('Üyeler', style: todoText(15, FontWeight.w700, c.ink)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Üyelerde ara',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  filled: true,
                  fillColor: c.field,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: c.fieldBorder),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final p = list[i];
                  return ListTile(
                    leading: TodoAvatar(name: p.name, seed: p.name, size: 34),
                    title: Text(
                      p.name,
                      style: todoText(15, FontWeight.w600, c.ink),
                    ),
                    subtitle: p.department.isEmpty
                        ? null
                        : Text(
                            p.department,
                            style: todoText(12.5, FontWeight.w400, c.muted),
                          ),
                    trailing: p.id == widget.selected
                        ? Icon(Icons.check_rounded, color: c.ink)
                        : null,
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
