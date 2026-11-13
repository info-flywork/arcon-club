import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/theme.dart';
import 'engine_client.dart';
import 'engine_models.dart';
import '../ui/skeleton.dart';

/// ARCON AI'nın kullanıcı hakkında hatırladıkları (webdeki "Hafıza").
class AiMemoriesScreen extends StatefulWidget {
  const AiMemoriesScreen({super.key, required this.engine});
  final EngineClient engine;

  @override
  State<AiMemoriesScreen> createState() => _AiMemoriesScreenState();
}

class _AiMemoriesScreenState extends State<AiMemoriesScreen> {
  List<EngineMemory>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await widget.engine.memories();
      if (mounted) setState(() => _items = m);
    } on ArconApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hatırlanacak bilgi'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Ör. Raporları her zaman Türkçe ve madde madde istiyorum.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    try {
      await widget.engine.addMemory(text);
      _load();
    } on ArconApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(EngineMemory m) async {
    try {
      await widget.engine.deleteMemory(m.id);
      _load();
    } on ArconApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Hafıza')),
      floatingActionButton: FloatingActionButton(onPressed: _add, tooltip: 'Ekle', child: const Icon(Icons.add)),
      body: _error != null
          ? Center(child: Text(_error!))
          : items == null
              ? const SkeletonList(count: 7, leading: false, padding: EdgeInsets.symmetric(horizontal: 16))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('ARCON AI sohbetlerde bunları hatırlar. İstemediğini sil.', style: TextStyle(color: ArconColors.muted)),
                  ),
                  if (items.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('Henüz kayıtlı bilgi yok.'))),
                  for (final m in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(m.content),
                        trailing: IconButton(tooltip: 'Sil', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(m)),
                      ),
                    ),
                ]),
    );
  }
}
