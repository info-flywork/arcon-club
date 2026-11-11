import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ui/theme.dart';
import 'ai_widgets.dart';
import 'chat_controller.dart';
import 'engine_client.dart';

/// ARCON AI sohbet ekranı: akışlı cevap, model seçimi, dosya/fotoğraf ekleme, durdurma.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key, required this.engine, this.conversationId, this.projectId, this.onChanged});

  final EngineClient engine;
  final int? conversationId;
  final int? projectId;

  /// Sohbet oluştu / başlığı değişti → listeyi tazele.
  final VoidCallback? onChanged;

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  late final ChatController _c =
      ChatController(engine: widget.engine, conversationId: widget.conversationId, projectId: widget.projectId);
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    ('Bir e-posta taslağı yaz', Icons.mail_outline),
    ('Bu dosyayı özetle', Icons.summarize_outlined),
    ('Satış verisini analiz et', Icons.insights_outlined),
    ('Sunum hazırla', Icons.slideshow_outlined),
    ('Web\'de araştır', Icons.travel_explore),
    ('Görsel oluştur', Icons.image_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  @override
  void dispose() {
    _c.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final t = text ?? _input.text;
    if (t.trim().isEmpty) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    final isNew = _c.conversationId == null;
    await _c.send(t);
    if (isNew || _c.messages.length <= 2) widget.onChanged?.call();
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Fotoğraf çek'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Galeriden seç'), onTap: () => Navigator.pop(ctx, 'gallery')),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('Dosya seç'),
            subtitle: const Text('PDF, Excel, Word, PowerPoint, CSV…'),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'file') {
      for (final f in await FilePicker.pickFiles()) {
        final path = f.path;
        if (path != null) _c.attach(path, f.name);
      }
    } else {
      final picker = ImagePicker();
      final shots = choice == 'camera'
          ? [?await picker.pickImage(source: ImageSource.camera, imageQuality: 85)]
          : await picker.pickMultiImage(imageQuality: 85);
      for (final x in shots) {
        _c.attach(x.path, x.name, isImage: true);
      }
    }
  }

  Future<void> _pickModel() async {
    if (_c.providers.length < 2) return;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Model seç', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final p in _c.providers)
            ListTile(
              leading: Icon(p.id == _c.provider ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(p.label),
              subtitle: Text(p.model),
              onTap: () => Navigator.pop(ctx, p.id),
            ),
        ]),
      ),
    );
    if (id != null) _c.selectProvider(id);
  }

  Future<void> _rename() async {
    if (_c.conversationId == null) return;
    final ctrl = TextEditingController(text: _c.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sohbeti yeniden adlandır'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Kaydet')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.engine.rename(_c.conversationId!, name);
    setState(() => _c.title = name);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final p = _c.currentProvider;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
              if (p != null)
                GestureDetector(
                  onTap: _pickModel,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(p.label, style: const TextStyle(fontSize: 12.5, color: ArconColors.muted)),
                    if (_c.providers.length > 1) const Icon(Icons.expand_more, size: 16, color: ArconColors.muted),
                  ]),
                ),
            ]),
            actions: [
              if (_c.conversationId != null)
                IconButton(tooltip: 'Yeniden adlandır', icon: const Icon(Icons.edit_outlined), onPressed: _rename),
            ],
          ),
          body: SafeArea(
            child: Column(children: [
              Expanded(child: _body()),
              if (_c.error != null && _c.messages.isEmpty)
                Padding(padding: const EdgeInsets.all(12), child: Text(_c.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              AttachmentStrip(controller: _c),
              _composer(context),
            ]),
          ),
        );
      },
    );
  }

  Widget _body() {
    if (_c.loading) return const Center(child: CircularProgressIndicator());
    if (_c.messages.isEmpty) {
      return ListView(padding: const EdgeInsets.fromLTRB(20, 40, 20, 20), children: [
        const Icon(Icons.auto_awesome, size: 36, color: ArconColors.green),
        const SizedBox(height: 14),
        const Text('Bugün neye yardım edeyim?', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Soru sor, dosya yükle, analiz ya da sunum iste.', textAlign: TextAlign.center, style: TextStyle(color: ArconColors.muted)),
        const SizedBox(height: 24),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final (s, icon) in _suggestions)
            ActionChip(avatar: Icon(icon, size: 18), label: Text(s), onPressed: () {
              _input.text = '$s: ';
              _input.selection = TextSelection.collapsed(offset: _input.text.length);
            }),
        ]),
      ]);
    }
    final items = _c.messages.reversed.toList();
    return ListView.separated(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (_, i) => MessageBubble(message: items[i], engine: widget.engine, conversationId: _c.conversationId ?? 0),
    );
  }

  Widget _composer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(tooltip: 'Ekle', icon: const Icon(Icons.add_circle_outline), onPressed: _c.sending ? null : _attach),
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'ARCON AI\'ya sor…',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _c.sending
              ? IconButton.filled(tooltip: 'Durdur', icon: const Icon(Icons.stop_rounded), onPressed: _c.stop)
              : ListenableBuilder(
                  listenable: _input,
                  builder: (_, _) => IconButton.filled(
                    tooltip: 'Gönder',
                    style: IconButton.styleFrom(backgroundColor: scheme.primary),
                    icon: const Icon(Icons.arrow_upward_rounded),
                    onPressed: _input.text.trim().isEmpty || !_c.canSend ? null : _send,
                  ),
                ),
        ),
      ]),
    );
  }
}
