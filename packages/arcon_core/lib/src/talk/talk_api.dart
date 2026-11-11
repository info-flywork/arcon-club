import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import 'talk_models.dart';

/// ARCONNECT web API'si (`arcon_talk_api?action=…`). Web ile aynı uç nokta, aynı veritabanı;
/// mobilde kimlik çerez yerine Bearer token.
class TalkApi {
  TalkApi({required this.arcon, required String baseUrl, http.Client? client})
      : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = client ?? http.Client();

  final ArconApi arcon;
  final Uri base;
  final http.Client _http;

  /// Göreli dosya yolunu (uploads/…) tam adrese çevir.
  String fileUrl(String path) => path.isEmpty || path.startsWith('http') ? path : base.resolve(path).toString();

  /// Sohbet görselinin küçük önizlemesi (sunucu ilk istekte üretir ve saklar). GIF ve dış adresler olduğu gibi.
  String thumbUrl(String path, {int width = 480}) {
    if (!RegExp(r'^uploads/arcon-talk/\d+/[A-Za-z0-9_-]+\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(path)) return fileUrl(path);
    return base.resolve('arcon_talk_thumb').replace(queryParameters: {'p': path, 'w': '$width'}).toString();
  }

  Map<String, String> get _auth => {'Authorization': 'Bearer ${arcon.token ?? ''}', 'Accept': 'application/json'};

  Uri _u(String action, [Map<String, String>? q]) =>
      base.resolve('arcon_talk_api').replace(queryParameters: {'action': action, ...?q});

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw ArconApiException('bad_response', 'Sunucudan beklenmeyen yanıt.', status: res.statusCode);
    }
    if (res.statusCode >= 400 || j['ok'] != true) {
      final e = j['error'];
      final msg = e is Map ? '${e['message'] ?? 'İşlem başarısız'}' : '${e ?? 'İşlem başarısız'}';
      throw ArconApiException(e is Map ? '${e['code'] ?? 'error'}' : 'error', msg, status: res.statusCode);
    }
    return j;
  }

  Future<Map<String, dynamic>> _get(String action, [Map<String, String>? q]) async {
    try {
      return _decode(await _http.get(_u(action, q), headers: _auth).timeout(const Duration(seconds: 20)));
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException('network', 'Bağlantı yok. Tekrar deneniyor…');
    }
  }

  Future<Map<String, dynamic>> _post(String action, Map<String, Object?> body) async {
    try {
      return _decode(await _http
          .post(_u(action), headers: {..._auth, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20)));
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException('network', 'Bağlantı yok. Tekrar deneniyor…');
    }
  }

  Future<({TalkUser me, List<TalkChannel> channels, List<TalkUser> users})> bootstrap() async {
    final j = await _get('bootstrap');
    final me = (j['me'] as Map).cast<String, dynamic>();
    return (
      me: TalkUser.fromJson({...me, 'id': me['user_id']}),
      channels: (j['channels'] as List).cast<Map>().map((c) => TalkChannel.fromJson(c.cast<String, dynamic>())).toList(),
      users: (j['users'] as List).cast<Map>().map((u) => TalkUser.fromJson(u.cast<String, dynamic>())).toList(),
    );
  }

  /// [readUpto]: diğer üyelerin hepsinin okuduğu an (mavi tik); kimse okumadıysa boş.
  /// [deliveredUpto]: hepsinin uygulamayı açtığı an (çift gri tik).
  Future<({List<TalkMessage> messages, List<TalkTyping> typing, String readUpto, String deliveredUpto})> messages(int channelId, {int afterId = 0}) async {
    final j = await _get('messages', {'channel_id': '$channelId', 'after_id': '$afterId'});
    return (
      messages: (j['messages'] as List).cast<Map>().map((m) => TalkMessage.fromJson(m.cast<String, dynamic>())).toList(),
      typing: ((j['typing'] as List?) ?? const []).cast<Map>().map((t) => TalkTyping.fromJson(t.cast<String, dynamic>())).toList(),
      readUpto: '${j['read_upto'] ?? ''}',
      deliveredUpto: '${j['delivered_upto'] ?? ''}',
    );
  }

  /// Mesaj bilgisi: okuyanlar (okuma zamanıyla) ve henüz okumayanlar.
  Future<({List<(TalkUser, String)> read, List<TalkUser> unread})> messageInfo(int messageId) async {
    final j = await _get('message_info', {'message_id': '$messageId'});
    List<Map<String, dynamic>> rows(String k) => ((j[k] as List?) ?? const []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    return (
      read: [for (final r in rows('read')) (TalkUser.fromJson(r), '${r['read_at'] ?? ''}')],
      unread: [for (final r in rows('unread')) TalkUser.fromJson(r)],
    );
  }

  Future<int> forward(int messageId, {List<int> channelIds = const [], List<int> userIds = const []}) async =>
      ((await _post('forward', {
        'message_id': messageId,
        'channel_ids': channelIds,
        'user_ids': userIds,
      }))['sent'] as num?)?.toInt() ?? 0;

  Future<TalkSidebar> sidebar(int channelId) async => TalkSidebar.fromJson(await _get('sidebar', {'channel_id': '$channelId'}));

  Future<void> typing(int channelId, bool on) async => _post('typing', {'channel_id': channelId, 'typing': on ? 1 : 0});

  Future<TalkCall> callStart({required int channelId, required bool video, String title = ''}) async {
    final j = await _post('call_start', {'channel_id': channelId, 'video': video, 'title': title});
    return TalkCall.fromJson((j['call'] as Map).cast<String, dynamic>());
  }

  Future<TalkCall> callJoin(int callId) async {
    final j = await _post('call_join', {'call_id': callId});
    return TalkCall.fromJson((j['call'] as Map).cast<String, dynamic>());
  }

  // ---------- Kararlar / Görevler ----------
  ({List<TalkDecision> decisions, List<TalkTask> tasks}) _board(Map<String, dynamic> j) => (
        decisions: ((j['decisions'] as List?) ?? const []).cast<Map>().map((d) => TalkDecision.fromJson(d.cast<String, dynamic>())).toList(),
        tasks: ((j['tasks'] as List?) ?? const []).cast<Map>().map((t) => TalkTask.fromJson(t.cast<String, dynamic>())).toList(),
      );

  Future<({List<TalkDecision> decisions, List<TalkTask> tasks})> toggleDecision(int messageId) async =>
      _board(await _post('decision_toggle', {'message_id': messageId}));

  /// [assigneeIds]: etiketlenen kişiler (her birine ARCON TO-DO kartı açılır); [dueDate] YYYY-MM-DD
  Future<({List<TalkDecision> decisions, List<TalkTask> tasks})> addTask(int channelId, String title,
          {int messageId = 0, List<int> assigneeIds = const [], String dueDate = ''}) async =>
      _board(await _post('task_add', {
        'channel_id': channelId,
        'title': title,
        'message_id': messageId,
        if (assigneeIds.isNotEmpty) 'assignee_ids': assigneeIds,
        if (dueDate.isNotEmpty) 'due_date': dueDate,
      }));

  Future<({List<TalkDecision> decisions, List<TalkTask> tasks})> toggleTask(int taskId) async =>
      _board(await _post('task_toggle', {'task_id': taskId}));

  Future<({List<TalkDecision> decisions, List<TalkTask> tasks})> deleteTask(int taskId) async =>
      _board(await _post('task_delete', {'task_id': taskId}));

  /// GIF / çıkartma araması (sunucu Giphy'ye sorar). `configured` false ise sunucuda anahtar yok.
  Future<({bool configured, List<TalkGif> items})> gifs({String q = '', bool stickers = false, int offset = 0}) async {
    final j = await _get('gifs', {'q': q, 'kind': stickers ? 'stickers' : 'gifs', 'offset': '$offset'});
    return (
      configured: j['configured'] != false,
      items: ((j['items'] as List?) ?? const []).whereType<Map>().map((g) => TalkGif.fromJson(g.cast<String, dynamic>())).toList(),
    );
  }

  Future<List<TalkCallLog>> callHistory() async {
    final j = await _get('call_history');
    return ((j['calls'] as List?) ?? const []).cast<Map>().map((c) => TalkCallLog.fromJson(c.cast<String, dynamic>())).toList();
  }

  Future<void> callDecline(int callId) async => _post('call_decline', {'call_id': callId});
  Future<void> callHangup(int callId) async => _post('call_hangup', {'call_id': callId});

  Future<void> presence() async => _post('presence', const {});

  /// Açık hat: `rev` aynıysa sunucu değişene kadar bekler, sonra çevrimiçi + yazıyor döner.
  Future<Map<String, dynamic>> live(String rev) => _get('live', {'rev': rev});
  Future<void> read(int channelId) async => _post('read', {'channel_id': channelId});
  Future<void> deleteMessage(int id) async => _post('delete_message', {'message_id': id});
  Future<void> editMessage(int id, String body) async => _post('edit_message', {'message_id': id, 'body': body});
  Future<void> react(int id, String emoji) async => _post('react', {'message_id': id, 'emoji': emoji});
  Future<void> hideChat(int channelId) async => _post('hide_chat', {'channel_id': channelId});
  Future<void> leaveChannel(int channelId) async => _post('leave_channel', {'channel_id': channelId});
  Future<TalkSidebar> setDisappear(int channelId, int sec) async =>
      TalkSidebar.fromJson(await _post('set_disappear', {'channel_id': channelId, 'disappear_after_sec': sec}));
  Future<TalkSidebar> invite(int channelId, List<int> userIds, String role) async =>
      TalkSidebar.fromJson(await _post('invite', {'channel_id': channelId, 'user_ids': userIds, 'role': role}));
  /// Sohbeti temizle: önceki mesajlar yalnızca bu kullanıcıdan gizlenir
  Future<void> clearChat(int channelId) async => _post('clear_chat', {'channel_id': channelId});

  /// Kısıtlı sohbet (yalnızca grup yöneticisi): mesajlar iletilemez / dışa aktarılamaz
  Future<TalkSidebar> setRestricted(int channelId, bool on) async =>
      TalkSidebar.fromJson(await _post('set_restricted', {'channel_id': channelId, 'restricted': on}));
  Future<String> inviteLink(int channelId) async => '${(await _post('invite_link', {'channel_id': channelId}))['url'] ?? ''}';
  Future<TalkSidebar> removeMember(int channelId, int userId) async =>
      TalkSidebar.fromJson(await _post('remove_member', {'channel_id': channelId, 'user_id': userId}));
  Future<TalkSidebar> setRole(int channelId, int userId, String role) async =>
      TalkSidebar.fromJson(await _post('set_role', {'channel_id': channelId, 'user_id': userId, 'role': role}));
  Future<int> createChannel({required String type, required String name, String description = '', bool isPrivate = false, required List<int> memberIds}) async {
    final j = await _post('channel', {'type': type, 'name': name, 'description': description, 'is_private': isPrivate, 'member_ids': memberIds});
    return ((j['channel'] as Map?)?['id'] as num?)?.toInt() ?? (j['channel_id'] as num?)?.toInt() ?? 0;
  }

  Future<TalkChannel?> openDm(int userId) async {
    final j = await _post('dm', {'user_id': userId});
    final raw = j['channel'];
    if (raw is! Map) return null;
    final ch = TalkChannel.fromJson(raw.cast<String, dynamic>());
    return ch.id > 0 ? ch : null;
  }

  Future<TalkSidebar> updateChannel(int channelId, {String? name, String? description, String? avatarPath}) async {
    final req = http.MultipartRequest('POST', _u('channel_update'))
      ..headers.addAll(_auth)
      ..fields['channel_id'] = '$channelId';
    if (name != null) req.fields['name'] = name;
    if (description != null) req.fields['description'] = description;
    if (avatarPath != null) req.files.add(await http.MultipartFile.fromPath('avatar', avatarPath));
    return TalkSidebar.fromJson(_decode(await http.Response.fromStream(await _http.send(req))));
  }

  /// Web profiliyle aynı: mevcut şifre + yeni şifre (en az 8) + tekrar.
  Future<void> changePassword({required String current, required String next, required String confirm}) async {
    await _post('profile', {
      'current_password': current,
      'new_password': next,
      'new_password_confirm': confirm,
    });
  }

  Future<TalkUser> updateProfile({String? displayName, String? about, bool clearAvatar = false}) async {
    final j = await _post('profile', {
      if (displayName != null) 'display_name': displayName,
      if (about != null) 'about': about,
      if (clearAvatar) 'clear_avatar': 1,
    });
    final me = (j['me'] as Map).cast<String, dynamic>();
    return TalkUser.fromJson({...me, 'id': me['user_id']});
  }

  Future<String> profileAvatar(String path) async {
    final req = http.MultipartRequest('POST', _u('profile_avatar'))
      ..headers.addAll(_auth)
      ..files.add(await http.MultipartFile.fromPath('avatar', path));
    final j = _decode(await http.Response.fromStream(await _http.send(req)));
    return '${j['avatar_path'] ?? (j['me'] as Map?)?['avatar_path'] ?? ''}';
  }

  /// Mesaj gönder (metin + isteğe bağlı dosyalar). [onProgress] 0..1 yükleme ilerlemesi;
  /// [cancel] tamamlanırsa yükleme iptal edilir.
  Future<Map<String, dynamic>> sendMessage({
    required int channelId,
    required String body,
    int replyTo = 0,
    List<String> filePaths = const [],
    void Function(double)? onProgress,
    Future<void>? cancel,
  }) async {
    if (filePaths.isEmpty) {
      return _post('message', {'channel_id': channelId, 'body': body, if (replyTo > 0) 'reply_to': replyTo});
    }
    final mp = http.MultipartRequest('POST', _u('message'))
      ..fields['channel_id'] = '$channelId'
      ..fields['body'] = body
      ..fields['had_file'] = '1';
    if (replyTo > 0) mp.fields['reply_to'] = '$replyTo';
    for (final p in filePaths) {
      mp.files.add(await http.MultipartFile.fromPath('files[]', p));
    }
    // Multipart gövdesini sayarak gönder → yükleme yüzdesi
    final total = mp.contentLength;
    var sent = 0;
    final client = http.Client();
    unawaited(cancel?.then((_) => client.close()));
    // finalize() content-type (boundary) başlığını ekler — başlıkları ondan SONRA kopyala
    final payload = mp.finalize();
    final req = http.StreamedRequest('POST', mp.url)
      ..headers.addAll({..._auth, ...mp.headers})
      ..contentLength = total;
    payload.listen(
      (chunk) {
        sent += chunk.length;
        onProgress?.call(total > 0 ? sent / total : 0);
        req.sink.add(chunk);
      },
      onDone: req.sink.close,
      onError: req.sink.addError,
      cancelOnError: true,
    );
    try {
      return _decode(await http.Response.fromStream(await client.send(req)));
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException('upload', 'Yükleme tamamlanamadı.');
    } finally {
      client.close();
    }
  }
}
