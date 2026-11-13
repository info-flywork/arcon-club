/// ARCON AI motoru (arcon-ai-engine) veri modelleri.
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _str(Object? v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

class EngineConversation {
  const EngineConversation({required this.id, required this.title, this.projectId, this.updatedAt, this.archived = false});

  factory EngineConversation.fromJson(Map<String, dynamic> j) => EngineConversation(
        id: _int(j['id']),
        title: _str(j['title']).isEmpty ? 'Yeni sohbet' : _str(j['title']),
        projectId: j['project_id'] == null ? null : _int(j['project_id']),
        updatedAt: DateTime.tryParse(_str(j['updated_at']).replaceFirst(' ', 'T')),
        archived: j['archived'] == true,
      );

  final int id;
  final String title;
  final int? projectId;
  final DateTime? updatedAt;
  final bool archived;
}

class EngineProject {
  const EngineProject({required this.id, required this.name, this.description = ''});
  factory EngineProject.fromJson(Map<String, dynamic> j) =>
      EngineProject(id: _int(j['id']), name: _str(j['name']), description: _str(j['description']));
  final int id;
  final String name;
  final String description;
}

class EngineProvider {
  const EngineProvider({required this.id, required this.label, required this.model, required this.configured});
  factory EngineProvider.fromJson(Map<String, dynamic> j) => EngineProvider(
        id: _str(j['id']),
        label: _str(j['label']),
        model: _str(j['model']),
        configured: j['configured'] == true,
      );
  final String id;
  final String label;
  final String model;
  final bool configured;
}

/// Kullanıcının yüklediği dosya (`POST /files`).
class EngineFile {
  const EngineFile({required this.id, required this.name, required this.mimeType, required this.size});
  factory EngineFile.fromJson(Map<String, dynamic> j) => EngineFile(
        id: _int(j['id']),
        name: _str(j['original_name']).isNotEmpty ? _str(j['original_name']) : _str(j['filename']),
        mimeType: _str(j['mime_type']),
        size: _int(j['size']),
      );
  final int id;
  final String name;
  final String mimeType;
  final int size;
  bool get isImage => mimeType.startsWith('image/');
}

/// Asistanın ürettiği dosya: görsel, Excel, Word, PowerPoint, PDF, grafik…
class EngineArtifact {
  const EngineArtifact({required this.id, required this.filename, required this.mimeType, required this.type, required this.size});
  factory EngineArtifact.fromJson(Map<String, dynamic> j) => EngineArtifact(
        id: _int(j['artifact_id'] ?? j['id']),
        filename: _str(j['filename']),
        mimeType: _str(j['mime_type']),
        type: _str(j['type']),
        size: _int(j['size']),
      );
  final int id;
  final String filename;
  final String mimeType;
  final String type;
  final int size;
  bool get isImage => mimeType.startsWith('image/');
}

class EngineSource {
  const EngineSource({required this.title, required this.url, this.snippet = ''});
  factory EngineSource.fromJson(Map<String, dynamic> j) =>
      EngineSource(title: _str(j['title']).isEmpty ? _str(j['url']) : _str(j['title']), url: _str(j['url']), snippet: _str(j['snippet']));
  final String title;
  final String url;
  final String snippet;
  String get host => Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;
}

/// Web görsel araması sonucu (dış bağlantılı görsel kartı).
class EngineWebImage {
  const EngineWebImage({required this.imageUrl, this.title = '', this.pageUrl = ''});
  factory EngineWebImage.fromJson(Map<String, dynamic> j) => EngineWebImage(
        imageUrl: _str(j['image_url'] ?? j['thumbnail_url'] ?? j['url']),
        title: _str(j['title']),
        pageUrl: _str(j['source_url'] ?? j['page_url']),
      );
  final String imageUrl;
  final String title;
  final String pageUrl;
}

class EngineMessage {
  EngineMessage({
    required this.id,
    required this.role,
    required this.content,
    this.attachments = const [],
    this.sources = const [],
    this.webImages = const [],
    this.artifacts = const [],
  });

  factory EngineMessage.fromJson(Map<String, dynamic> j) {
    final meta = (j['meta'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return EngineMessage(
      id: _int(j['id']),
      role: _str(j['role']),
      content: _str(j['content']),
    )
      ..at = DateTime.tryParse(_str(j['created_at']).replaceFirst(' ', 'T'))
      ..applyMeta(meta);
  }

  final int id;
  final String role;
  String content;
  List<EngineFile> attachments;
  List<EngineSource> sources;
  List<EngineWebImage> webImages;
  List<EngineArtifact> artifacts;

  /// Gönderilme anı (yeni mesajda şimdi)
  DateTime? at = DateTime.now();

  /// Akış sırasında gösterilen araç durumu (ör. "Web'de aranıyor…").
  String? status;
  bool streaming = false;
  String? error;

  bool get isUser => role == 'user';

  void applyMeta(Map<String, dynamic> meta) {
    attachments = _maps(meta['attachments']).map(EngineFile.fromJson).toList();
    sources = _maps(meta['sources']).map(EngineSource.fromJson).where((s) => s.url.isNotEmpty).toList();
    webImages = _maps(meta['images']).map(EngineWebImage.fromJson).where((i) => i.imageUrl.isNotEmpty).toList();
    artifacts = _maps(meta['artifacts']).map(EngineArtifact.fromJson).where((a) => a.id > 0).toList();
  }
}

class EngineMemory {
  const EngineMemory({required this.id, required this.content, this.type = ''});
  factory EngineMemory.fromJson(Map<String, dynamic> j) =>
      EngineMemory(id: _int(j['id']), content: _str(j['content']), type: _str(j['type'] ?? j['memory_type']));
  final int id;
  final String content;
  final String type;
}

/// Sohbet akışındaki tek olay (SSE `data:` satırı).
class EngineEvent {
  const EngineEvent(this.type, this.data);
  factory EngineEvent.fromJson(Map<String, dynamic> j) => EngineEvent(_str(j['type']), j);
  final String type;
  final Map<String, dynamic> data;
  String get text => _str(data['text'] ?? data['delta']);
  String get capability => _str(data['capability']);
  String get label => _str(data['label']);
}
