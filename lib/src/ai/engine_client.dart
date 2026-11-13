import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_cache.dart';
import '../api/api_client.dart';
import 'engine_models.dart';

/// ARCON AI motoruna (web'deki ARCON AI modülünün kendisi) doğrudan bağlanan istemci.
///
/// Giriş: ARCON mobil token'ı ile `/api/v1/engine_sso` alınır → motorun `POST /auth/sso`
/// ucuna verilir → motor oturum çerezi (CEDSESSID) saklanır. Çerez düşerse otomatik yenilenir.
class EngineClient {
  EngineClient({required this.arcon, http.Client? client}) : _http = client ?? http.Client();

  final ArconApi arcon;
  final http.Client _http;
  Uri? _api;
  String? _cookie;

  static const _timeout = Duration(seconds: 30);

  bool get isConnected => _api != null && _cookie != null;

  /// Görsel/dosya indirmek için gereken başlık (Image.network headers).
  Map<String, String> get authHeaders => {'Cookie': ?_cookie};

  Uri url(String path, [Map<String, String>? query]) {
    final base = _api!.toString().endsWith('/') ? _api! : Uri.parse('${_api!}/');
    return base.resolve(path).replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  Uri artifactUrl(EngineArtifact a, int conversationId) =>
      url('artifacts/${a.id}', {'conversation_id': '$conversationId'});

  Future<void> connect() async {
    final p = await arcon.engineSso();
    _api = Uri.parse('${p['engine_api']}/');
    final res = await _http
        .post(url('auth/sso'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'uid': p['uid'], 'display_name': p['display_name'], 'sso': p['sso'], 'exp': p['exp']}))
        .timeout(_timeout);
    final cookie = _sessionCookie(res.headers['set-cookie']);
    if (res.statusCode != 200 || cookie == null) {
      throw const ArconApiException('engine_auth', 'ARCON AI oturumu açılamadı. Lütfen tekrar deneyin.');
    }
    _cookie = cookie;
  }

  static String? _sessionCookie(String? header) {
    if (header == null) return null;
    final all = RegExp(r'CEDSESSID=([^;,\s]+)').allMatches(header).toList();
    for (final m in all.reversed) {
      if (m.group(1) != 'deleted' && m.group(1)!.isNotEmpty) return 'CEDSESSID=${m.group(1)}';
    }
    return null;
  }

  Future<void> _ensure() async {
    if (!isConnected) await connect();
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw ArconApiException('bad_response', 'ARCON AI beklenmeyen bir yanıt verdi.', status: res.statusCode);
    }
    if (res.statusCode >= 400 || body['success'] == false || body['ok'] == false) {
      final e = body['error'];
      final msg = e is Map ? '${e['message'] ?? 'İşlem tamamlanamadı.'}' : '${e ?? 'İşlem tamamlanamadı.'}';
      throw ArconApiException(e is Map ? '${e['code'] ?? 'error'}' : 'error', msg, status: res.statusCode);
    }
    return body;
  }

  /// İstek at; motor oturumu düşmüşse (401) bir kez yeniden bağlanıp tekrar dene.
  Future<Map<String, dynamic>> _call(Future<http.Response> Function() send) async {
    await _ensure();
    try {
      var res = await send().timeout(_timeout);
      if (res.statusCode == 401) {
        await connect();
        res = await send().timeout(_timeout);
      }
      return _decode(res);
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException('network', 'ARCON AI\'ya ulaşılamadı. Bağlantınızı kontrol edin.');
    }
  }

  Map<String, String> get _json => {'Content-Type': 'application/json', 'Accept': 'application/json', ...authHeaders};

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? q]) =>
      _call(() => _http.get(url(path, q), headers: _json));
  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) => _call(() {
        final r = http.Request(method, url(path))..headers.addAll(_json);
        if (body != null) r.body = jsonEncode(body);
        return _http.send(r).then(http.Response.fromStream);
      });

  /// Önbellekli GET (bkz. [cachedFetch]); [maxAge] yoksa her zaman ağ ama yanıt saklanır.
  Future<Map<String, dynamic>> _getCached(String path, [Map<String, String>? q, Duration? maxAge]) => cachedFetch(
        cache: arcon.cache,
        key: ApiCache.key('engine', path, q),
        fetch: () => _get(path, q),
        maxAge: maxAge,
        force: maxAge == null,
        isNetworkError: (e) => e is ArconApiException && e.code == 'network',
      );

  /// Model listesi nadiren değişir: 10 dk önbellekten.
  Future<List<EngineProvider>> providers() async => ((await _getCached('providers', null, const Duration(minutes: 10)))['providers'] as List)
      .cast<Map<String, dynamic>>()
      .map(EngineProvider.fromJson)
      .toList();

  Map<String, String> _convQuery(int? projectId, bool archived) => {
        if (projectId != null) 'project_id': '$projectId',
        if (archived) 'archived': '1',
        'limit': '100',
      };

  static List<EngineConversation> _convs(Map<String, dynamic> j) =>
      (j['conversations'] as List).cast<Map<String, dynamic>>().map(EngineConversation.fromJson).toList();

  Future<List<EngineConversation>> conversations({int? projectId, bool archived = false}) async =>
      _convs(await _getCached('conversations', _convQuery(projectId, archived)));

  /// Son alınan sohbet listesi (ağa gitmez).
  Future<List<EngineConversation>?> cachedConversations({int? projectId, bool archived = false}) async {
    final e = await arcon.cache.read(ApiCache.key('engine', 'conversations', _convQuery(projectId, archived)));
    return e == null ? null : _convs(e.json);
  }

  Future<List<EngineConversation>> search(String q) async {
    final j = await _get('search', {'q': q});
    return ((j['results'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((r) => EngineConversation.fromJson({...r, 'id': r['conversation_id'] ?? r['id'], 'title': r['title']}))
        .toList();
  }

  Future<EngineConversation> createConversation({String title = 'Yeni sohbet', int? projectId}) async =>
      EngineConversation.fromJson(
          (await _send('POST', 'conversations', {'title': title, 'project_id': projectId}))['conversation'] as Map<String, dynamic>);

  Future<(EngineConversation, List<EngineMessage>)> conversation(int id) async {
    final j = await _get('conversations/$id');
    return (
      EngineConversation.fromJson(j['conversation'] as Map<String, dynamic>),
      (j['messages'] as List).cast<Map<String, dynamic>>().map(EngineMessage.fromJson).toList(),
    );
  }

  Future<void> rename(int id, String title) => _send('PATCH', 'conversations/$id', {'title': title});
  Future<void> archive(int id) => _send('POST', 'conversations/$id/archive');
  Future<void> restore(int id) => _send('POST', 'conversations/$id/restore');
  Future<void> deleteConversation(int id) => _send('DELETE', 'conversations/$id');

  /// Projeler 2 dk önbellekten (yeni proje kaydı siler).
  Future<List<EngineProject>> projects() async => ((await _getCached('projects', null, const Duration(minutes: 2)))['projects'] as List)
      .cast<Map<String, dynamic>>()
      .map(EngineProject.fromJson)
      .toList();

  Future<EngineProject> createProject(String name, {String? description, String? instructions}) async {
    final p = EngineProject.fromJson((await _send('POST', 'projects', {
      'name': name,
      'description': description,
      'instructions': instructions,
    }))['project'] as Map<String, dynamic>);
    await arcon.cache.invalidate(ApiCache.key('engine', 'projects'));
    return p;
  }

  Future<List<EngineMemory>> memories() async =>
      ((await _get('memories'))['memories'] as List).cast<Map<String, dynamic>>().map(EngineMemory.fromJson).toList();
  Future<void> addMemory(String content) => _send('POST', 'memories', {'content': content, 'type': 'fact'});
  Future<void> deleteMemory(int id) => _send('DELETE', 'memories/$id');

  Future<EngineFile> upload(String path, String filename) async {
    final j = await _call(() async {
      final req = http.MultipartRequest('POST', url('files'))
        ..headers.addAll(authHeaders)
        ..files.add(await http.MultipartFile.fromPath('file', path, filename: filename));
      return http.Response.fromStream(await _http.send(req));
    });
    return EngineFile.fromJson(j['file'] as Map<String, dynamic>);
  }

  Future<List<int>> download(Uri u) async {
    await _ensure();
    final res = await _http.get(u, headers: authHeaders).timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) {
      throw ArconApiException('download', 'Dosya indirilemedi.', status: res.statusCode);
    }
    return res.bodyBytes;
  }

  /// Mesaj gönderir; cevap parça parça (token) akar. [cancel] tamamlanınca bağlantı kesilir (Durdur).
  Stream<EngineEvent> chat({
    required int conversationId,
    required String message,
    String provider = 'openai',
    List<int> attachmentIds = const [],
    Future<void>? cancel,
  }) async* {
    await _ensure();
    final client = http.Client(); // ayrı istemci: Durdur'da yalnızca bu bağlantı kapanır
    unawaited(cancel?.then((_) => client.close()));
    try {
      Future<http.StreamedResponse> send() => client.send(http.Request('POST', url('chat'))
        ..headers.addAll({..._json, 'Accept': 'text/event-stream'})
        ..body = jsonEncode({
          'conversation_id': conversationId,
          'message': message,
          'provider': provider,
          'attachments': [for (final id in attachmentIds) {'id': id}],
        }));
      var res = await send();
      if (res.statusCode == 401) {
        await res.stream.drain<void>();
        await connect();
        res = await send();
      }
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.contains('event-stream')) {
        _decode(await http.Response.fromStream(res)); // hata mesajını fırlatır
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
              final ev = EngineEvent.fromJson(jsonDecode(line.substring(5).trim()) as Map<String, dynamic>);
              if (ev.type != 'ping') yield ev;
            } on FormatException {
              // yarım satır: yoksay
            }
          }
          cut = buf.indexOf('\n\n');
        }
      }
    } on http.ClientException {
      // Durdur ile kapatıldı
    } finally {
      client.close();
    }
  }
}
