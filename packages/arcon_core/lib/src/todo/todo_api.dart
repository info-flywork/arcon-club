import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import 'todo_models.dart';

/// ARCON To-Do web API'si (`arcon_todo_api?action=…`): web ile aynı uç nokta ve veritabanı,
/// mobilde kimlik çerez yerine Bearer token.
class TodoApi {
  TodoApi({required this.arcon, required String baseUrl, http.Client? client})
    : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _http = client ?? http.Client();

  final ArconApi arcon;
  final Uri base;
  final http.Client _http;

  Map<String, String> get _auth => {
    'Authorization': 'Bearer ${arcon.token ?? ''}',
    'Accept': 'application/json',
  };

  Uri _u(String action, [Map<String, String>? q]) => base
      .resolve('arcon_todo_api')
      .replace(queryParameters: {'action': action, ...?q});

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw ArconApiException(
        'bad_response',
        'Sunucudan beklenmeyen yanıt.',
        status: res.statusCode,
      );
    }
    if (res.statusCode >= 400 || j['ok'] != true) {
      final e = j['error'];
      final msg = e is Map
          ? '${e['message'] ?? 'İşlem başarısız'}'
          : '${e ?? 'İşlem başarısız'}';
      throw ArconApiException(
        e is Map ? '${e['code'] ?? 'error'}' : 'error',
        msg,
        status: res.statusCode,
      );
    }
    return j;
  }

  Future<Map<String, dynamic>> _get(
    String action, [
    Map<String, String>? q,
  ]) async {
    try {
      return _decode(
        await _http
            .get(_u(action, q), headers: _auth)
            .timeout(const Duration(seconds: 20)),
      );
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException(
        'network',
        'Bağlantı yok. Lütfen tekrar deneyin.',
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String action,
    Map<String, Object?> body,
  ) async {
    try {
      return _decode(
        await _http
            .post(
              _u(action),
              headers: {..._auth, 'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 20)),
      );
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException(
        'network',
        'Bağlantı yok. Lütfen tekrar deneyin.',
      );
    }
  }

  static List<TodoTask> _tasks(Object? l) => ((l as List?) ?? const [])
      .cast<Map>()
      .map((t) => TodoTask.fromJson(t.cast<String, dynamic>()))
      .toList();

  Future<TodoBootstrap> bootstrap({String filter = 'all'}) async {
    final j = await _get('bootstrap', {'filter': filter});
    final me = (j['me'] as Map).cast<String, dynamic>();
    final st = (j['statuses'] as Map).cast<String, dynamic>();
    final depts = ((j['departments'] as List?) ?? const [])
        .map((d) => d is Map ? '${d['name'] ?? d['department'] ?? ''}' : '$d')
        .where((d) => d.isNotEmpty)
        .toList();
    return TodoBootstrap(
      meId: (me['id'] as num).toInt(),
      meName: '${me['username'] ?? ''}',
      statuses: [for (final e in st.entries) MapEntry(e.key, '${e.value}')],
      departments: depts,
      tasks: _tasks(j['tasks']),
      people: ((j['people'] as List?) ?? const [])
          .cast<Map>()
          .map((p) => TodoPerson.fromJson(p.cast<String, dynamic>()))
          .toList(),
      channels: ((j['channels'] as List?) ?? const [])
          .cast<Map>()
          .map((c) => TodoChannel.fromJson(c.cast<String, dynamic>()))
          .toList(),
    );
  }

  Future<List<TodoTask>> list({String filter = 'all'}) async =>
      _tasks((await _get('list', {'filter': filter}))['tasks']);

  Future<TodoTask> create(Map<String, Object?> fields) async =>
      TodoTask.fromJson(
        ((await _post('create', fields))['task'] as Map)
            .cast<String, dynamic>(),
      );

  Future<TodoTask> update(int id, Map<String, Object?> fields) async =>
      TodoTask.fromJson(
        ((await _post('update', {'id': id, ...fields}))['task'] as Map)
            .cast<String, dynamic>(),
      );

  Future<void> move(int id, String status, int sortOrder) =>
      _post('move', {'id': id, 'status': status, 'sort_order': sortOrder});

  Future<void> delete(int id) => _post('delete', {'id': id});

  Future<({TodoTask task, List<TodoComment> comments})> get(int id) async {
    final j = await _get('get', {'id': '$id'});
    return (
      task: TodoTask.fromJson((j['task'] as Map).cast<String, dynamic>()),
      comments: ((j['comments'] as List?) ?? const [])
          .cast<Map>()
          .map((c) => TodoComment.fromJson(c.cast<String, dynamic>()))
          .toList(),
    );
  }

  Future<void> addComment(int taskId, String body) =>
      _post('comment_add', {'task_id': taskId, 'body': body});

  Future<void> deleteComment(int id) => _post('comment_delete', {'id': id});
}
