import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';

/// Webdeki ARCON AI (`new_chatbot/`) istemcisi — aynı sohbetler, projeler, modeller ve akış.
/// Kimlik: uygulamanın giriş token'ı (Authorization: Bearer); web oturumu gerekmez.
class NcbApi {
  NcbApi(this.api);
  final ArconApi api;

  static const folder = 'new_chatbot/';

  Uri url(String file, [Map<String, String>? q]) => api.webUrl('$folder$file').replace(queryParameters: q);

  Map<String, String> get headers => {
        'Accept': 'application/json',
        if (api.token != null && api.token!.isNotEmpty) 'Authorization': 'Bearer ${api.token}',
      };

  /// Görsel / dosya adresi (yüklenen `u_…` ya da üretilen `f_…`).
  String fileUrl(String id, {bool download = false}) =>
      url('file.php', {'id': id, if (download) 'dl': '1'}).toString();

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> j;
    try {
      j = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw ArconApiException(res.statusCode == 401 ? 'unauthenticated' : 'bad_response', 'ARCON AI yanıt veremedi.', status: res.statusCode);
    }
    if (res.statusCode >= 400 || j['ok'] == false) {
      // new_chatbot hata biçimi: {"ok":false,"error":{"code":"…","message":"…"}}
      final e = j['error'];
      final code = e is Map ? '${e['code'] ?? 'error'}' : '${j['code'] ?? 'error'}';
      final msg = e is Map ? '${e['message'] ?? ''}' : '${e ?? j['message'] ?? ''}';
      throw ArconApiException(code, msg.isEmpty ? 'İşlem yapılamadı.' : msg, status: res.statusCode);
    }
    return j;
  }

  Future<Map<String, dynamic>> get(String action, [Map<String, String> q = const {}]) async =>
      _decode(await http.get(url('api.php', {'action': action, ...q}), headers: headers).timeout(const Duration(seconds: 40)));

  Future<Map<String, dynamic>> post(String action, [Map<String, Object?> body = const {}]) async => _decode(await http
      .post(url('api.php', {'action': action}), headers: {...headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
      .timeout(const Duration(seconds: 60)));

  Future<Map<String, dynamic>> upload(String action, String field, String path, {String? filename, Map<String, String> fields = const {}}) async {
    final req = http.MultipartRequest('POST', url('api.php', {'action': action}))
      ..headers.addAll(headers)
      ..fields.addAll(fields)
      ..files.add(await http.MultipartFile.fromPath(field, path, filename: filename));
    return _decode(await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 3))));
  }

  /// Sohbet akışı (chat.php, SSE). [cancel] tamamlanınca bağlantı kapanır (Durdur).
  Stream<Map<String, dynamic>> chat(Map<String, Object?> body, {Future<void>? cancel}) async* {
    final client = http.Client();
    unawaited(cancel?.then((_) => client.close()));
    try {
      final res = await client.send(http.Request('POST', url('chat.php'))
        ..headers.addAll({...headers, 'Content-Type': 'application/json', 'Accept': 'text/event-stream'})
        ..body = jsonEncode(body));
      if (!(res.headers['content-type'] ?? '').contains('event-stream')) {
        _decode(await http.Response.fromStream(res));
        throw const ArconApiException('bad_response', 'ARCON AI yanıt veremedi.');
      }
      var buf = '';
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        buf += chunk.replaceAll('\r\n', '\n');
        var cut = buf.indexOf('\n\n');
        while (cut >= 0) {
          final block = buf.substring(0, cut);
          buf = buf.substring(cut + 2);
          for (final line in block.split('\n')) {
            if (!line.startsWith('data:')) continue;
            try {
              yield (jsonDecode(line.substring(5).trim()) as Map).cast<String, dynamic>();
            } on FormatException {
              // yarım satır
            }
          }
          cut = buf.indexOf('\n\n');
        }
      }
    } on http.ClientException {
      // Durdur
    } finally {
      client.close();
    }
  }
}

/* ------------------------------ modeller ------------------------------ */

String _s(Object? v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final e in v.whereType<Map>()) e.cast<String, dynamic>()] : const [];

class NcbTier {
  const NcbTier({required this.key, required this.label, required this.hint, required this.engine, required this.skin, required this.group, required this.display});
  factory NcbTier.fromJson(Map<String, dynamic> j) => NcbTier(
        key: _s(j['key']),
        label: _s(j['label']),
        hint: _s(j['hint']),
        engine: _s(j['engine']),
        skin: _s(j['skin']).isEmpty ? 'chatgpt' : _s(j['skin']),
        group: _s(j['group']),
        display: _s(j['display']),
      );
  final String key, label, hint, engine, skin, group, display;
}

class NcbConv {
  NcbConv({required this.id, required this.title, this.projectId, this.pinned = false, this.updatedAt});
  factory NcbConv.fromJson(Map<String, dynamic> j) => NcbConv(
        id: _s(j['id']),
        title: _s(j['title']).isEmpty ? 'Yeni sohbet' : _s(j['title']),
        projectId: j['project_id'] == null || _s(j['project_id']).isEmpty ? null : _s(j['project_id']),
        pinned: j['pinned'] == true,
        updatedAt: DateTime.tryParse(_s(j['updated_at']).replaceFirst(' ', 'T')),
      );
  final String id;
  String title;
  String? projectId;
  bool pinned;
  DateTime? updatedAt;
}

class NcbProject {
  const NcbProject({required this.id, required this.name, this.instructions = '', this.chatCount = 0});
  factory NcbProject.fromJson(Map<String, dynamic> j) =>
      NcbProject(id: _s(j['id']), name: _s(j['name']), instructions: _s(j['instructions']), chatCount: (j['chat_count'] as num?)?.toInt() ?? 0);
  final String id, name, instructions;
  final int chatCount;
}

/// Mesaj — web ile aynı `display` yapısı (text, steps, sources, images, files, actions, connects, thinking …).
class NcbMsg {
  NcbMsg({required this.role, Map<String, dynamic>? display, this.id, this.feedback = 0, this.createdAt}) : d = display ?? {};
  factory NcbMsg.fromJson(Map<String, dynamic> j) => NcbMsg(
        id: (j['id'] as num?)?.toInt(),
        role: _s(j['role']),
        display: (j['display'] as Map?)?.cast<String, dynamic>(),
        feedback: (j['feedback'] as num?)?.toInt() ?? 0,
        createdAt: _s(j['created_at']),
      );

  int? id;
  final String role;
  Map<String, dynamic> d;
  int feedback;
  String? createdAt;

  // canlı akış durumu
  bool streaming = false;
  String status = '';
  bool thinkingLive = false;
  final Map<String, String> imageLoaders = {}; // key → size

  bool get isUser => role == 'user';
  String get text => _s(d['text']);
  set text(String v) => d['text'] = v;
  List<Map<String, dynamic>> list(String k) => _maps(d[k]);
  void add(String k, Map<String, dynamic> v) => d[k] = [...list(k), v];
}
