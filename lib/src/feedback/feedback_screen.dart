import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import '../ui/mono.dart';
import '../ui/motion.dart';
import '../ui/native_fallback.dart';
import '../ui/skeleton.dart';

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Gelen bir fikir / geri bildirim (yönetici görür).
class FeedbackItem {
  FeedbackItem.fromJson(Map<String, dynamic> j)
    : id = _i(j['id']),
      body = '${j['body'] ?? ''}',
      name = '${j['name'] ?? ''}',
      department = '${j['department'] ?? ''}',
      contact = '${j['contact'] ?? ''}',
      status = '${j['status'] ?? 'new'}',
      statusLabel = '${j['status_label'] ?? ''}',
      category = '${j['category'] ?? ''}',
      categoryLabel = '${j['category_label'] ?? ''}',
      createdAt = DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal();

  final int id;
  final String body;
  final String name;
  final String department;
  final String contact;
  final String status;
  final String statusLabel;
  final String category;
  final String categoryLabel;
  final DateTime? createdAt;
}

/// ARCON IDEA (`kind: idea`) ve ARCON FEEDBACK (`kind: feedback`) — webdeki arcon-idea.php / arcon-feedback.php:
/// herkes gönderir (anonim olabilir); yönetici "Gelenler" sekmesinde okur, durumunu değiştirir.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, required this.session, required this.config, required this.kind, this.openInbox = false});

  final SessionController session;
  final ArconAppConfig config;

  /// `idea` ya da `feedback`.
  final String kind;

  /// Yöneticiyi doğrudan "Gelenler"e aç (ana sayfadaki bildirim kartından).
  final bool openInbox;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  bool get _idea => widget.kind == 'idea';

  // yetki ve gelenler
  bool _ready = false;
  bool _canManage = false;
  List<({String key, String label})> _categories = const [];
  Map<String, int> _counts = const {};
  List<FeedbackItem>? _items;
  String _filter = 'all';
  String _catFilter = 'all';
  int _tab = 0; // 0: gönder, 1: gelenler

  // form
  final _form = GlobalKey<FormState>();
  final _body = TextEditingController();
  final _name = TextEditingController();
  final _dept = TextEditingController();
  final _contact = TextEditingController();
  String _category = 'suggestion';
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
    _start();
  }

  @override
  void dispose() {
    _body.dispose();
    _name.dispose();
    _dept.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final cached = await widget.session.api.cachedFeedbackJson(widget.kind);
    if (cached != null && mounted) _apply(cached);
    await _load();
  }

  void _apply(Map<String, dynamic> j) {
    setState(() {
      _ready = true;
      _canManage = j['can_manage'] == true;
      _categories = [
        for (final c in ((j['categories'] as List?) ?? const []).whereType<Map>()) (key: '${c['key']}', label: '${c['label']}'),
      ];
      _counts = ((j['counts'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', _i(v)));
      if (j['items'] is List) {
        _items = [for (final r in (j['items'] as List).whereType<Map>()) FeedbackItem.fromJson(r.cast<String, dynamic>())];
      }
      if (widget.openInbox && _canManage && _tab == 0 && !_sent) _tab = 1;
    });
  }

  Future<void> _load({bool force = false}) async {
    try {
      final j = await widget.session.api.feedbackJson(widget.kind, filter: _filter, category: _catFilter, force: force);
      if (mounted) _apply(j);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (!mounted) return;
      if (!_ready && serverLacksApi(e)) {
        openWebFallback(
          context,
          session: widget.session,
          config: widget.config,
          title: _title,
          path: _idea ? 'arcon-idea' : 'arcon-feedback',
        );
        return;
      }
      setState(() {
        _ready = true;
        _error = e.message;
      });
    }
  }

  String get _title => _idea ? 'ARCON IDEA' : 'ARCON FEEDBACK';

  Future<void> _submit() async {
    if (_sending || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.session.api.submitFeedback(
        widget.kind,
        body: _body.text.trim(),
        name: _name.text.trim(),
        department: _dept.text.trim(),
        contact: _contact.text.trim(),
        category: _idea ? null : _category,
      );
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _sent = true);
      if (_canManage) _load(force: true);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reset() {
    _body.clear();
    _name.clear();
    _dept.clear();
    _contact.clear();
    setState(() {
      _sent = false;
      _error = null;
      _category = 'suggestion';
    });
  }

  Future<void> _setStatus(FeedbackItem it, String act) async {
    try {
      await widget.session.api.setFeedbackStatus(widget.kind, it.id, act);
      await _load(force: true);
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Geri',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_rounded, color: c.ink),
                    ),
                    Text(_title, style: c.text(19, weight: FontWeight.w800, spacing: 0.4)),
                  ],
                ),
              ),
              if (_canManage) _tabs(c),
              Expanded(
                child: SwapFade(
                  alignment: Alignment.topCenter,
                  offset: 0.02,
                  child: KeyedSubtree(key: ValueKey(_tab), child: _tab == 0 ? _sendView(c) : _inboxView(c)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs(ArconMono c) {
    final waiting = _counts['new'] ?? 0;
    Widget tab(int i, String label, {int badge = 0}) => Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _tab == i ? c.ink : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: c.text(13, weight: FontWeight.w700, color: _tab == i ? c.bg : c.ink),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: _tab == i ? c.bg : c.ink, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    '$badge',
                    style: c.text(10.5, weight: FontWeight.w700, color: _tab == i ? c.ink : c.bg),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          tab(0, 'Gönder'),
          tab(1, 'Gelenler', badge: waiting),
        ],
      ),
    );
  }

  /* ---------------- Gönder ---------------- */

  Widget _sendView(ArconMono c) {
    final pad = MediaQuery.paddingOf(context);
    if (_sent) {
      return ListView(
        padding: EdgeInsets.fromLTRB(20, 40, 20, 24 + pad.bottom),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(18)),
              child: Icon(Icons.check_rounded, size: 34, color: c.bg),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            _idea ? 'Fikrin bize ulaştı' : 'Geri bildirimin alındı',
            style: c.text(28, weight: FontWeight.w800, height: 1.15, spacing: -0.8),
          ),
          const SizedBox(height: 10),
          Text(
            _idea
                ? 'Paylaştığın için teşekkürler. Fikirlerine önem veriyoruz — değerlendirip gerektiğinde harekete geçeceğiz.'
                : 'Teşekkürler! Ekibimiz geri bildirimini inceleyecek; iletişim bilgisi bıraktıysan gerekirse sana döneceğiz.',
            style: c.text(14.5, color: c.muted, height: 1.55),
          ),
          const SizedBox(height: 28),
          c.primaryButton(_idea ? 'Yeni fikir gönder' : 'Yeni geri bildirim', busy: false, onPressed: _reset),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: Text(
              'Geri dön',
              style: c.text(14, weight: FontWeight.w600, color: c.muted),
            ),
          ),
        ],
      );
    }
    return Form(
      key: _form,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + pad.bottom),
        children: [
          Text(
            _idea ? 'ARCON CLUB için fikrini paylaş' : 'Arcon AI hakkında görüşünü paylaş',
            style: c.text(26, weight: FontWeight.w800, height: 1.15, spacing: -0.8),
          ),
          const SizedBox(height: 8),
          Text(
            _idea
                ? 'Yeni özellik ve geliştirme fikirlerini topluyoruz. İstersen anonim kalabilirsin; en iyi fikirlere sürpriz ödüller var.'
                : 'Hata, şikayet, övgü ya da önerini bırak. İstersen anonim kalabilirsin.',
            style: c.text(14, color: c.muted, height: 1.5),
          ),
          const SizedBox(height: 22),
          if (_error != null) ...[c.errorBox(_error!), const SizedBox(height: 16)],
          if (!_idea) ...[
            c.label('Konu'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cat in (_categories.isEmpty ? _defaultCategories : _categories))
                  GestureDetector(
                    onTap: () => setState(() => _category = cat.key),
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.fast),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: _category == cat.key ? c.ink : c.field,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _category == cat.key ? c.ink : c.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_catIcon(cat.key), size: 16, color: _category == cat.key ? c.bg : c.ink),
                          const SizedBox(width: 6),
                          Text(
                            cat.label,
                            style: c.text(13, weight: FontWeight.w600, color: _category == cat.key ? c.bg : c.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
          ],
          c.label(_idea ? 'Geliştirme fikrin' : 'Geri bildirimin'),
          TextFormField(
            controller: _body,
            minLines: 5,
            maxLines: 10,
            maxLength: 2000,
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            textCapitalization: TextCapitalization.sentences,
            style: c.text(15, height: 1.45),
            cursorColor: c.ink,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                Text('$currentLength / $maxLength', style: c.text(11, color: c.faint)),
            decoration: c.input(_idea ? 'ARCON CLUB’a hangi özellik eklenmeli? Neden?' : 'Ne oldu? Nerede karşılaştın?', null),
            validator: (v) => (v?.trim().length ?? 0) < 5 ? 'Biraz daha açar mısın (en az 5 karakter)?' : null,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'İSTEĞE BAĞLI',
                style: c.text(10.5, weight: FontWeight.w700, color: c.muted, spacing: 1.2),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: c.line)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _optField(c, _dept, 'Departman', Icons.apartment_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _optField(c, _name, 'İsim', Icons.person_outline_rounded)),
            ],
          ),
          const SizedBox(height: 10),
          _optField(c, _contact, _idea ? 'İletişim (ödül için)' : 'İletişim', Icons.alternate_email_rounded),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.visibility_off_outlined, size: 15, color: c.faint),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Boş bırakırsan anonim gönderilir.', style: c.text(12, color: c.faint)),
              ),
            ],
          ),
          const SizedBox(height: 22),
          c.primaryButton(_idea ? 'Fikrimi gönder' : 'Gönder', busy: _sending, onPressed: _submit),
        ],
      ),
    );
  }

  static const _defaultCategories = [
    (key: 'bug', label: 'Hata'),
    (key: 'complaint', label: 'Şikayet'),
    (key: 'praise', label: 'Övgü'),
    (key: 'suggestion', label: 'Öneri'),
  ];

  static IconData _catIcon(String k) => switch (k) {
    'bug' => Icons.bug_report_outlined,
    'complaint' => Icons.sentiment_dissatisfied_outlined,
    'praise' => Icons.favorite_border_rounded,
    _ => Icons.lightbulb_outline_rounded,
  };

  Widget _optField(ArconMono c, TextEditingController ctl, String hint, IconData icon) => TextField(
    controller: ctl,
    keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
    style: c.text(14.5, weight: FontWeight.w500),
    cursorColor: c.ink,
    decoration: c.input(hint, icon),
  );

  /* ---------------- Gelenler (yönetici) ---------------- */

  Widget _inboxView(ArconMono c) {
    final items = _items;
    final pad = MediaQuery.paddingOf(context);
    final doneLabel = _idea ? 'Tamamlandı' : 'Kapatıldı';
    final filters = [
      ('all', 'Tümü', _counts['all'] ?? 0),
      ('new', 'Beklemede', _counts['new'] ?? 0),
      ('read', 'İnceleniyor', _counts['read'] ?? 0),
      ('archived', doneLabel, _counts['archived'] ?? 0),
    ];
    Widget chip(String label, bool sel, VoidCallback onTap, {int? count}) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? c.ink : c.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? c.ink : c.line),
        ),
        child: Text(
          count == null ? label : '$label  $count',
          style: c.text(12, weight: FontWeight.w700, color: sel ? c.bg : c.ink),
        ),
      ),
    );
    return RefreshIndicator(
      color: c.ink,
      backgroundColor: c.bg,
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                children: [
                  for (final f in filters) ...[
                    chip(f.$2, _filter == f.$1, () {
                      setState(() {
                        _filter = f.$1;
                        _items = null;
                      });
                      _load();
                    }, count: f.$3),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          if (!_idea && _categories.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                  children: [
                    for (final cat in [(key: 'all', label: 'Tüm konular'), ..._categories]) ...[
                      chip(cat.label, _catFilter == cat.key, () {
                        setState(() {
                          _catFilter = cat.key;
                          _items = null;
                        });
                        _load();
                      }),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            ),
          if (items == null)
            const SliverToBoxAdapter(child: SkeletonList(count: 6, leading: false))
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_outlined, size: 36, color: c.faint),
                    const SizedBox(height: 8),
                    Text('Bu filtrede kayıt yok', style: c.text(14, color: c.muted)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 24 + pad.bottom),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _itemCard(c, items[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(ArconMono c, FeedbackItem it) {
    final isNew = it.status == 'new';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isNew ? c.ink : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isNew ? c.ink : c.line),
      ),
      child: Text(
        trUpper(it.statusLabel),
        style: c.text(9.5, weight: FontWeight.w700, color: isNew ? c.bg : c.muted, spacing: 0.6),
      ),
    );
  }

  String _who(FeedbackItem it) => [
    if (it.name.isNotEmpty) it.name else 'Anonim',
    if (it.department.isNotEmpty) it.department,
    _date(it.createdAt),
  ].where((s) => s.isNotEmpty).join(' · ');

  static String _date(DateTime? d) {
    if (d == null) return '';
    const m = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Widget _itemCard(ArconMono c, FeedbackItem it) {
    return PressScale(
      child: Material(
        color: c.field,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openItem(it),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (!_idea) ...[
                      Icon(_catIcon(it.category), size: 15, color: c.muted),
                      const SizedBox(width: 5),
                      Text(
                        trUpper(it.categoryLabel),
                        style: c.text(10, weight: FontWeight.w700, color: c.muted, spacing: 1),
                      ),
                      const Spacer(),
                    ] else
                      const Spacer(),
                    _statusChip(c, it),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  it.body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: c.text(14.5, weight: it.status == 'new' ? FontWeight.w600 : FontWeight.w400, height: 1.45),
                ),
                const SizedBox(height: 8),
                Text(_who(it), style: c.text(11.5, color: c.faint)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openItem(FeedbackItem it) async {
    if (it.status == 'new') _setStatus(it, 'read'); // açılan okundu sayılır (webdeki yönetim gibi)
    final c = ArconMono.of(context);
    final act = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (!_idea)
                  Text(
                    trUpper(it.categoryLabel),
                    style: c.text(11, weight: FontWeight.w700, color: c.muted, spacing: 1),
                  ),
                const Spacer(),
                Text(_who(it), style: c.text(11.5, color: c.faint)),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(child: SelectableText(it.body, style: c.text(15.5, height: 1.6))),
            ),
            if (it.contact.isNotEmpty) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: it.contact));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İletişim bilgisi kopyalandı')));
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.field,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.alternate_email_rounded, size: 18, color: c.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(it.contact, style: c.text(14, weight: FontWeight.w600)),
                      ),
                      Icon(Icons.copy_rounded, size: 16, color: c.faint),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, it.status == 'read' ? 'new' : 'read'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.line),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(it.status == 'read' ? 'Beklemeye al' : 'İnceleniyor', style: c.text(13.5, weight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, it.status == 'archived' ? 'read' : 'archive'),
                    style: FilledButton.styleFrom(
                      backgroundColor: c.ink,
                      foregroundColor: c.bg,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      it.status == 'archived' ? 'Yeniden aç' : (_idea ? 'Tamamlandı' : 'Kapat'),
                      style: c.text(13.5, weight: FontWeight.w700, color: c.bg),
                    ),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              style: TextButton.styleFrom(foregroundColor: c.danger),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(
                'Sil',
                style: c.text(13.5, weight: FontWeight.w600, color: c.danger),
              ),
            ),
          ],
        ),
      ),
    );
    if (act == null || !mounted) return;
    if (act == 'delete') {
      final yes = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Kayıt silinsin mi?'),
          content: const Text('Bu işlem geri alınamaz.'),
          actions: [
            CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
          ],
        ),
      );
      if (yes != true) return;
    }
    await _setStatus(it, act);
  }
}
