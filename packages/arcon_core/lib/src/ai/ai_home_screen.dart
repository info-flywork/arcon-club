import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/theme.dart';
import 'ai_chat_screen.dart';
import 'ai_memories_screen.dart';
import 'engine_client.dart';
import 'engine_models.dart';

/// ARCON AI ana ekranı: sohbet geçmişi, projeler, arama, arşiv, hafıza.
/// Webdeki ARCON AI modülünün aynı hesabı ve aynı sohbetleri.
class AiHomeScreen extends StatefulWidget {
  const AiHomeScreen({super.key, required this.session, this.title = 'ARCON AI'});

  final SessionController session;
  final String title;

  @override
  State<AiHomeScreen> createState() => _AiHomeScreenState();
}

class _AiHomeScreenState extends State<AiHomeScreen> {
  late final EngineClient _engine = EngineClient(arcon: widget.session.api);
  List<EngineConversation> _items = const [];
  List<EngineProject> _projects = const [];
  int? _project;
  bool _archived = false;
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _query.isNotEmpty ? _engine.search(_query) : _engine.conversations(projectId: _project, archived: _archived),
        _engine.projects(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<EngineConversation>;
        _projects = results[1] as List<EngineProject>;
      });
    } on ArconApiException catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open({int? id}) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AiChatScreen(engine: _engine, conversationId: id, projectId: _project, onChanged: _load),
      )).then((_) => _load());

  Future<void> _actions(EngineConversation c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700))),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Yeniden adlandır'), onTap: () => Navigator.pop(ctx, 'rename')),
          if (_archived)
            ListTile(leading: const Icon(Icons.unarchive_outlined), title: const Text('Arşivden çıkar'), onTap: () => Navigator.pop(ctx, 'restore'))
          else
            ListTile(leading: const Icon(Icons.archive_outlined), title: const Text('Arşivle'), onTap: () => Navigator.pop(ctx, 'archive')),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: Text('Sil', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'rename':
          final ctrl = TextEditingController(text: c.title);
          final name = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Yeniden adlandır'),
              content: TextField(controller: ctrl, autofocus: true),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Kaydet')),
              ],
            ),
          );
          if (name != null && name.isNotEmpty) await _engine.rename(c.id, name);
        case 'archive':
          await _engine.archive(c.id);
        case 'restore':
          await _engine.restore(c.id);
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sohbet silinsin mi?'),
              content: const Text('Bu sohbet ve içindeki dosyalar kalıcı olarak silinir.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
              ],
            ),
          );
          if (ok == true) await _engine.deleteConversation(c.id);
      }
    } on ArconApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    _load();
  }

  Future<void> _newProject() async {
    final name = TextEditingController();
    final instructions = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yeni proje'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Proje adı')),
          const SizedBox(height: 12),
          TextField(
            controller: instructions,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Talimatlar (isteğe bağlı)', hintText: 'Bu projedeki sohbetlerde AI neye dikkat etsin?'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oluştur')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final p = await _engine.createProject(name.text.trim(), instructions: instructions.text.trim().isEmpty ? null : instructions.text.trim());
      _project = p.id;
      _load();
    } on ArconApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _group(DateTime? d) {
    if (d == null) return 'Daha eski';
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    if (diff < 7) return 'Son 7 gün';
    if (diff < 30) return 'Son 30 gün';
    return 'Daha eski';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<EngineConversation>>{};
    for (final c in _items) {
      groups.putIfAbsent(_query.isNotEmpty ? 'Arama sonuçları' : _group(c.updatedAt), () => []).add(c);
    }
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Sohbetlerde ara…', border: InputBorder.none, enabledBorder: InputBorder.none, filled: false),
                onSubmitted: (q) {
                  _query = q.trim();
                  _load();
                },
              )
            : Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: ArconColors.ink, borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.auto_awesome, size: 17, color: ArconColors.mint),
                ),
                const SizedBox(width: 10),
                Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
        actions: [
          IconButton(
            tooltip: _searching ? 'Aramayı kapat' : 'Ara',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching && _query.isNotEmpty) {
                _query = '';
                _load();
              }
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'archive') {
                setState(() => _archived = !_archived);
                _load();
              } else if (v == 'memory') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiMemoriesScreen(engine: _engine)));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archive', child: Text(_archived ? 'Aktif sohbetler' : 'Arşivlenmiş sohbetler')),
              const PopupMenuItem(value: 'memory', child: Text('Hafıza')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.edit_square),
        label: const Text('Yeni sohbet'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: const Text('Tümü'), selected: _project == null, onSelected: (_) {
                      setState(() => _project = null);
                      _load();
                    }),
                  ),
                  for (final p in _projects)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: const Icon(Icons.folder_outlined, size: 16),
                        label: Text(p.name),
                        selected: _project == p.id,
                        onSelected: (_) {
                          setState(() => _project = p.id);
                          _load();
                        },
                      ),
                    ),
                  ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Proje'), onPressed: _newProject),
                ],
              ),
            ),
            if (_archived)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Text('Arşivlenmiş sohbetler', style: TextStyle(color: ArconColors.muted)),
              ),
            if (_loading)
              const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
                ]),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
                child: Column(children: [
                  const Icon(Icons.forum_outlined, size: 40, color: ArconColors.muted),
                  const SizedBox(height: 12),
                  Text(_query.isNotEmpty ? 'Sonuç bulunamadı' : 'Henüz sohbet yok', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Yeni bir sohbet başlat; webdeki sohbetlerin de burada görünür.',
                      textAlign: TextAlign.center, style: TextStyle(color: ArconColors.muted)),
                ]),
              )
            else
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                  child: Text(g.key.toUpperCase(),
                      style: const TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: ArconColors.muted)),
                ),
                for (final c in g.value)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(icon: const Icon(Icons.more_horiz), onPressed: () => _actions(c)),
                    onTap: () => _open(id: c.id),
                    onLongPress: () => _actions(c),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}
