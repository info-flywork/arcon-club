import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'engine_client.dart';
import 'engine_models.dart';

/// Yüklenmekte olan / hazır ek.
class PendingAttachment {
  PendingAttachment(this.name, {this.isImage = false, this.localPath});
  final String name;
  final bool isImage;
  final String? localPath;
  EngineFile? file;
  String? error;
  bool get uploading => file == null && error == null;
}

/// Tek bir sohbetin durumu: mesajlar, akan cevap, ekler, model seçimi.
class ChatController extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  ChatController({required this.engine, int? conversationId, this.projectId}) : _conversationId = conversationId;

  final EngineClient engine;
  final int? projectId;
  int? _conversationId;
  String title = 'Yeni sohbet';
  final List<EngineMessage> messages = [];
  final List<PendingAttachment> attachments = [];
  List<EngineProvider> providers = const [];
  String provider = 'openai';
  bool loading = false;
  bool sending = false;
  String? error;
  Completer<void>? _cancel;

  int? get conversationId => _conversationId;
  bool get canSend => !sending && !attachments.any((a) => a.uploading);

  EngineProvider? get currentProvider {
    for (final p in providers) {
      if (p.id == provider) return p;
    }
    return null;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      providers = (await engine.providers()).where((p) => p.configured).toList();
      if (providers.isNotEmpty && !providers.any((p) => p.id == provider)) provider = providers.first.id;
      if (_conversationId != null) {
        final (conv, msgs) = await engine.conversation(_conversationId!);
        title = conv.title;
        messages
          ..clear()
          ..addAll(msgs);
      }
    } on ArconApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void selectProvider(String id) {
    provider = id;
    notifyListeners();
  }

  Future<void> attach(String path, String name, {bool isImage = false}) async {
    final a = PendingAttachment(name, isImage: isImage, localPath: path);
    attachments.add(a);
    notifyListeners();
    try {
      a.file = await engine.upload(path, name);
    } on ArconApiException catch (e) {
      a.error = e.message;
    }
    notifyListeners();
  }

  void removeAttachment(PendingAttachment a) {
    attachments.remove(a);
    notifyListeners();
  }

  void stop() => _cancel?.complete();

  static String statusLabel(String capability, String label) {
    if (label.isNotEmpty) return label;
    return switch (capability) {
      'web_search' => 'Web\'de aranıyor…',
      'web_page_read' => 'Sayfa okunuyor…',
      'image_generation' => 'Görsel oluşturuluyor…',
      'image_search' => 'Görseller aranıyor…',
      'artifact_creation' => 'Dosya hazırlanıyor…',
      'data_analysis' => 'Veri analiz ediliyor…',
      'code_execution' => 'Hesaplanıyor…',
      'document_read' || 'file_analysis' => 'Belge okunuyor…',
      'company_knowledge' => 'Şirket bilgisi aranıyor…',
      _ => 'Çalışıyor…',
    };
  }

  Future<void> send(String text) async {
    text = text.trim();
    if (text.isEmpty || !canSend) return;
    final ready = attachments.where((a) => a.file != null).map((a) => a.file!).toList();
    attachments.clear();
    error = null;
    final user = EngineMessage(id: 0, role: 'user', content: text, attachments: ready);
    final bot = EngineMessage(id: 0, role: 'assistant', content: '')
      ..streaming = true
      ..status = 'Düşünüyor…';
    messages.addAll([user, bot]);
    sending = true;
    _cancel = Completer<void>();
    notifyListeners();

    try {
      _conversationId ??= (await engine.createConversation(projectId: projectId)).id;
      await for (final ev in engine.chat(
        conversationId: _conversationId!,
        message: text,
        provider: provider,
        attachmentIds: [for (final f in ready) f.id],
        cancel: _cancel!.future,
      )) {
        switch (ev.type) {
          case 'meta':
            final id = ev.data['conversation_id'];
            if (id is num && id > 0) _conversationId = id.toInt();
          case 'progress' || 'tool_start':
            if (ev.capability != 'image_search') bot.status = statusLabel(ev.capability, ev.label);
          case 'tool_result':
            bot.status = ev.data['status'] == 'ok' ? null : 'Bir adım tamamlanamadı';
          case 'token':
            bot.status = null;
            bot.content += ev.text;
          case 'done':
            final content = '${ev.data['content'] ?? ''}';
            if (content.isNotEmpty) bot.content = content;
            bot.applyMeta(ev.data);
            final conv = ev.data['conversation'];
            if (conv is Map && conv['title'] != null) title = '${conv['title']}';
          case 'error':
            bot.error = '${ev.data['error'] ?? 'Cevap üretilemedi.'}';
        }
        notifyListeners();
      }
      if (_cancel!.isCompleted && bot.content.isEmpty) bot.content = '_Durduruldu._';
    } on ArconApiException catch (e) {
      bot.error = e.message;
    } finally {
      bot
        ..streaming = false
        ..status = null;
      sending = false;
      _cancel = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_cancel != null && !_cancel!.isCompleted) _cancel!.complete();
    super.dispose();
  }
}
