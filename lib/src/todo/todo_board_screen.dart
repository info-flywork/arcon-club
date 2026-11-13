import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import 'todo_api.dart';
import 'todo_card_screen.dart';
import 'todo_models.dart';
import 'todo_theme.dart';
import '../ui/skeleton.dart';
import '../ui/motion.dart';

/// ARCON To-Do — Trello tarzı pano. Veri web To-Do ile aynı (`arcon_todo_api`).
class TodoBoardScreen extends StatefulWidget {
  const TodoBoardScreen({
    super.key,
    required this.session,
    required this.config,
    this.title = 'ARCON To-Do',
  });

  final SessionController session;
  final ArconAppConfig config;
  final String title;

  @override
  State<TodoBoardScreen> createState() => _TodoBoardScreenState();
}

const _filters = [
  ('all', 'Tüm Görevler'),
  ('assigned', 'Bana Atananlar'),
  ('created', 'Oluşturduklarım'),
  ('team', 'Ekip Görevleri'),
];

class _TodoBoardScreenState extends State<TodoBoardScreen> {
  late final TodoApi _api = TodoApi(
    arcon: widget.session.api,
    baseUrl: widget.config.apiBase,
  );
  final _pages = PageController(viewportFraction: 0.86);

  TodoBootstrap? _boot;
  List<TodoTask> _tasks = [];
  String _filter = 'all';
  String? _error;
  bool _loading = true;
  int _page = 0;
  String _query = '';
  bool _searching = false;
  Timer? _edgeTimer;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    _edgeTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_boot == null) {
      // son pano önbellekten anında
      final cached = await _api.cachedBootstrap(filter: _filter);
      if (cached != null && mounted && _boot == null) {
        setState(() {
          _boot = cached;
          _tasks = cached.tasks;
        });
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = _boot == null;
      _error = null;
    });
    try {
      final b = await _api.bootstrap(filter: _filter);
      if (!mounted) return;
      setState(() {
        _boot = b;
        _tasks = b.tasks;
        _loading = false;
      });
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    try {
      final t = await _api.list(filter: _filter);
      if (mounted) setState(() => _tasks = t);
    } on ArconApiException catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
  }

  List<TodoTask> _column(String status) {
    final q = _query.trim().toLowerCase();
    final list =
        _tasks.where((t) => t.status == status).where((t) {
          if (q.isEmpty) return true;
          return t.title.toLowerCase().contains(q) ||
              t.description.toLowerCase().contains(q) ||
              t.tag.toLowerCase().contains(q) ||
              t.assigneeName.toLowerCase().contains(q);
        }).toList()..sort(
          (a, b) => a.sortOrder != b.sortOrder
              ? a.sortOrder.compareTo(b.sortOrder)
              : a.id.compareTo(b.id),
        );
    return list;
  }

  /// Kartı listeye taşı; [before] verilirse onun önüne, yoksa sona.
  Future<void> _move(TodoTask t, String status, {TodoTask? before}) async {
    if (before?.id == t.id) return;
    final col = _column(status).where((x) => x.id != t.id).toList();
    final idx = before == null
        ? col.length
        : col.indexWhere((x) => x.id == before.id);
    col.insert(idx < 0 ? col.length : idx, t);
    final prevStatus = t.status;
    setState(() {
      t.status = status;
      for (var i = 0; i < col.length; i++) {
        col[i].sortOrder = i + 1;
      }
    });
    HapticFeedback.selectionClick();
    try {
      // Web ile aynı: taşınan kart yeni sırasıyla; aynı listedeki diğerleri de sıralı kalsın
      for (var i = 0; i < col.length; i++) {
        if (col[i].id == t.id || col[i].status == status) {
          await _api.move(col[i].id, status, i + 1);
        }
      }
    } on ArconApiException catch (e) {
      setState(() => t.status = prevStatus);
      _toast(e.message);
      unawaited(_reload());
    }
  }

  Future<void> _quickAdd(String status, String title) async {
    try {
      final t = await _api.create({'title': title, 'status': status});
      if (mounted) setState(() => _tasks.add(t));
    } on ArconApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _openCard(TodoTask t) async {
    final boot = _boot;
    if (boot == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TodoCardScreen(
          api: _api,
          boot: boot,
          task: t,
          session: widget.session,
        ),
      ),
    );
    if (mounted) unawaited(_reload());
  }

  Future<void> _newCard() async {
    final boot = _boot;
    if (boot == null) return;
    final status = boot.statuses[_page.clamp(0, boot.statuses.length - 1)].key;
    final title = await showTodoTextPrompt(
      context,
      title: 'Yeni kart',
      hint: 'Bu kart için bir başlık girin…',
    );
    if (title != null && title.trim().isNotEmpty)
      await _quickAdd(status, title.trim());
  }

  void _chooseFilter() {
    final c = TodoColors.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.sheetBg,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in _filters)
              ListTile(
                title: Text(f.$2, style: todoText(15, FontWeight.w600, c.ink)),
                trailing: _filter == f.$1
                    ? Icon(Icons.check_rounded, color: c.ink)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _filter = f.$1);
                  _reload();
                },
              ),
          ],
        ),
      ),
    );
  }

  // Sürüklerken ekran kenarına gelince yan listeye geç
  void _onDragUpdate(DragUpdateDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    final dir = d.globalPosition.dx < 36
        ? -1
        : (d.globalPosition.dx > w - 36 ? 1 : 0);
    if (dir == 0) {
      _edgeTimer?.cancel();
      _edgeTimer = null;
      return;
    }
    _edgeTimer ??= Timer(const Duration(milliseconds: 450), () {
      _edgeTimer = null;
      final n = (_boot?.statuses.length ?? 1) - 1;
      final next = (_page + dir).clamp(0, n);
      if (next != _page) {
        _pages.animateToPage(
          next,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final boot = _boot;
    final filterName = _filters.firstWhere((f) => f.$1 == _filter).$2;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF09326C),
        body: Container(
          decoration: const BoxDecoration(gradient: TodoColors.boardGradient),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  title: widget.title,
                  subtitle: filterName,
                  searching: _searching,
                  onBack: () => Navigator.of(context).maybePop(),
                  onTitle: _chooseFilter,
                  onSearch: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _query = '';
                  }),
                  onQuery: (q) => setState(() => _query = q),
                  onAdd: boot == null ? null : _newCard,
                ),
                Expanded(child: _body(boot)),
                if (boot != null)
                  _PageDots(
                    count: boot.statuses.length,
                    index: _page,
                    onTap: (i) {
                      _pages.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOut,
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(TodoBootstrap? boot) {
    if (_loading) return const SkeletonBoard();
    if (_error != null || boot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Pano yüklenemedi.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: _load, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      notificationPredicate: (n) => n.depth == 1,
      child: PageView.builder(
        controller: _pages,
        padEnds: false,
        itemCount: boot.statuses.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (ctx, i) {
          final s = boot.statuses[i];
          return Padding(
            padding: EdgeInsets.fromLTRB(i == 0 ? 12 : 6, 8, 6, 8),
            // Trello gibi: liste içeriği kadar uzar
            child: Align(
              alignment: Alignment.topCenter,
              child: _TodoList(
                status: s.key,
                title: s.value,
                tasks: _column(s.key),
                dragging: _dragging,
                onOpen: _openCard,
                onMove: _move,
                onAdd: (title) => _quickAdd(s.key, title),
                onDragStart: () => setState(() => _dragging = true),
                onDragEnd: () {
                  _edgeTimer?.cancel();
                  _edgeTimer = null;
                  setState(() => _dragging = false);
                },
                onDragUpdate: _onDragUpdate,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.searching,
    required this.onBack,
    required this.onTitle,
    required this.onSearch,
    required this.onQuery,
    required this.onAdd,
  });

  final String title, subtitle;
  final bool searching;
  final VoidCallback onBack, onTitle, onSearch;
  final ValueChanged<String> onQuery;
  final VoidCallback? onAdd;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    return Container(
      color: const Color(0x3D000000),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: white,
              size: 20,
            ),
          ),
          Expanded(
            child: SwapFade(
              child: widget.searching
                ? TextField(
                    key: const ValueKey('search'),
                    controller: _q,
                    autofocus: true,
                    onChanged: widget.onQuery,
                    style: const TextStyle(color: white, fontSize: 16),
                    cursorColor: white,
                    decoration: const InputDecoration(
                      hintText: 'Kartlarda ara…',
                      hintStyle: TextStyle(color: Color(0xB3FFFFFF)),
                      border: InputBorder.none,
                    ),
                  )
                : InkWell(
                    key: const ValueKey('title'),
                    onTap: widget.onTitle,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.subtitle,
                                style: const TextStyle(
                                  color: Color(0xCCFFFFFF),
                                  fontSize: 12.5,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xCCFFFFFF),
                                size: 18,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
          IconButton(
            onPressed: widget.onSearch,
            icon: IconSwap(
              widget.searching ? Icons.close_rounded : Icons.search_rounded,
              color: white,
            ),
          ),
          if (widget.onAdd != null)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: FilledButton(
                onPressed: widget.onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF579DFF),
                  foregroundColor: const Color(0xFF1D2125),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  'Oluştur',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.index,
    required this.onTap,
  });
  final int count, index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == index ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == index ? Colors.white : const Color(0x80FFFFFF),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Tek liste (sütun): başlık, kartlar, "Kart ekle".
class _TodoList extends StatefulWidget {
  const _TodoList({
    required this.status,
    required this.title,
    required this.tasks,
    required this.dragging,
    required this.onOpen,
    required this.onMove,
    required this.onAdd,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDragUpdate,
  });

  final String status, title;
  final List<TodoTask> tasks;
  final bool dragging;
  final ValueChanged<TodoTask> onOpen;
  final Future<void> Function(TodoTask, String, {TodoTask? before}) onMove;
  final Future<void> Function(String) onAdd;
  final VoidCallback onDragStart, onDragEnd;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  @override
  State<_TodoList> createState() => _TodoListState();
}

class _TodoListState extends State<_TodoList> {
  bool _adding = false;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty) {
      setState(() => _adding = false);
      return;
    }
    _ctrl.clear();
    await widget.onAdd(t);
    _focus.requestFocus(); // Trello gibi: art arda kart eklenebilir
  }

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.listBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: TodoColors.statusAccent(widget.status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: todoText(15, FontWeight.w700, c.ink),
                  ),
                ),
                Text(
                  '${widget.tasks.length}',
                  style: todoText(13.5, FontWeight.w600, c.muted),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _adding = true),
                  icon: Icon(Icons.more_horiz_rounded, color: c.muted),
                  tooltip: 'Kart ekle',
                ),
              ],
            ),
          ),
          Flexible(
            child: DragTarget<TodoTask>(
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (d) => widget.onMove(d.data, widget.status),
              builder: (ctx, cand, _) => AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: cand.isNotEmpty
                      ? const Color(0x22579DFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                  children: [
                    for (final t in widget.tasks) _draggable(t),
                    if (widget.tasks.isEmpty && widget.dragging)
                      Container(
                        height: 64,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: c.muted.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    if (_adding) _addBox(c),
                  ],
                ),
              ),
            ),
          ),
          if (!_adding)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: TextButton.icon(
                onPressed: () => setState(() => _adding = true),
                style: TextButton.styleFrom(
                  foregroundColor: c.muted,
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(
                  'Kart ekle',
                  style: todoText(14.5, FontWeight.w600, c.muted),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _addBox(TodoColors c) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40091E42),
                blurRadius: 1,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            maxLines: null,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: todoText(14.5, FontWeight.w500, c.ink),
            decoration: InputDecoration(
              hintText: 'Bu kart için bir başlık girin…',
              hintStyle: todoText(14.5, FontWeight.w400, c.muted),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0C66E4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text('Kart ekle'),
            ),
            IconButton(
              onPressed: () {
                _ctrl.clear();
                setState(() => _adding = false);
              },
              icon: Icon(Icons.close_rounded, color: c.ink),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _draggable(TodoTask t) {
    final card = TodoCardTile(task: t, onTap: () => widget.onOpen(t));
    return DragTarget<TodoTask>(
      onWillAcceptWithDetails: (d) => d.data.id != t.id,
      onAcceptWithDetails: (d) =>
          widget.onMove(d.data, widget.status, before: t),
      builder: (ctx, cand, _) => Column(
        children: [
          if (cand.isNotEmpty)
            Container(
              height: 48,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0x33579DFF),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          LongPressDraggable<TodoTask>(
            data: t,
            onDragStarted: () {
              HapticFeedback.mediumImpact();
              widget.onDragStart();
            },
            onDragEnd: (_) => widget.onDragEnd(),
            onDraggableCanceled: (_, _) => widget.onDragEnd(),
            onDragUpdate: widget.onDragUpdate,
            feedback: Material(
              color: Colors.transparent,
              child: Transform.rotate(
                angle: 0.05,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.78,
                  child: card,
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: card),
            child: card,
          ),
        ],
      ),
    );
  }
}

/// Pano kartı: etiket çubuğu, başlık, rozetler (tarih, açıklama, yorum), atanan kişi.
class TodoCardTile extends StatelessWidget {
  const TodoCardTile({super.key, required this.task, required this.onTap});
  final TodoTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final t = task;
    final badges = <Widget>[
      if (t.dueDate != null) TodoDueChip(task: t, compact: true),
      if (t.scope == 'team')
        Icon(Icons.groups_2_outlined, size: 16, color: c.muted),
      if (t.description.trim().isNotEmpty)
        Icon(Icons.notes_rounded, size: 16, color: c.muted),
      if (t.commentCount > 0)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 15, color: c.muted),
            const SizedBox(width: 4),
            Text(
              '${t.commentCount}',
              style: todoText(12.5, FontWeight.w500, c.muted),
            ),
          ],
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        // Gölge kartın altında; kart zemini Material'da (yoksa gölge kartın üstüne biner)
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: dark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x40091E42),
                    blurRadius: 1,
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        child: Material(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t.tag.isNotEmpty) ...[
                    Container(
                      height: 8,
                      width: 40,
                      decoration: BoxDecoration(
                        color: TodoColors.label(t.tag),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t.isDone) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Color(0xFF4BCE97),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          t.title,
                          style:
                              todoText(
                                14.5,
                                FontWeight.w500,
                                c.ink,
                                height: 1.3,
                              ).copyWith(
                                decoration: t.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: c.muted,
                              ),
                        ),
                      ),
                    ],
                  ),
                  if (badges.isNotEmpty || t.assigneeId != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: badges,
                          ),
                        ),
                        if (t.assigneeId != null)
                          TodoAvatar(
                            name: t.assigneeName,
                            seed: t.assigneeName,
                            size: 26,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bitiş tarihi rozeti: geçmiş → kırmızı, yaklaşan → sarı, tamamlandı → yeşil.
class TodoDueChip extends StatelessWidget {
  const TodoDueChip({super.key, required this.task, this.compact = false});
  final TodoTask task;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = TodoColors.of(context);
    final d = task.dueDate!;
    final (Color bg, Color fg) = task.isDone
        ? (const Color(0xFF4BCE97), const Color(0xFF1D2125))
        : task.isOverdue
        ? (const Color(0xFFF87168), const Color(0xFF1D2125))
        : task.isDueSoon
        ? (const Color(0xFFF5CD47), const Color(0xFF1D2125))
        : (c.chip, c.muted);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            task.isDone ? Icons.check_box_outlined : Icons.schedule_rounded,
            size: compact ? 14 : 16,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            todoDate(d),
            style: todoText(compact ? 12.5 : 14, FontWeight.w500, fg),
          ),
        ],
      ),
    );
  }
}

/// Tek satırlık metin sorusu (yeni kart başlığı, etiket adı).
Future<String?> showTodoTextPrompt(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Kaydet'),
        ),
      ],
    ),
  );
}
