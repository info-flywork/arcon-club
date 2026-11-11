import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Sunucunun döndürdüğü hata (`{"ok":false,"error":{"code","message"}}`) ya da bağlantı hatası.
class ArconApiException implements Exception {
  const ArconApiException(this.code, this.message, {this.status = 0});

  final String code;
  final String message;
  final int status;

  bool get isUnauthorized => status == 401 && code != 'invalid_credentials';

  @override
  String toString() => 'ArconApiException($status $code: $message)';
}

class LoginResult {
  const LoginResult(this.token, this.user);
  final String token;
  final ArconUser user;
}

/// ARCON mobil API v1 istemcisi (`/api/v1/...`). Web ile aynı sunucu ve veritabanı.
class ArconApi {
  ArconApi({required String baseUrl, required this.appKey, http.Client? client, this.token})
      : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = client ?? http.Client();

  final Uri _base;
  final http.Client _http;
  final String appKey;

  /// Giriş sonrası her istekte `Authorization: Bearer` olarak gönderilir.
  String? token;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String endpoint, [Map<String, String>? query]) =>
      _base.resolve('api/v1/$endpoint').replace(queryParameters: query);

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(_timeout);
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw ArconApiException('bad_response', 'Sunucudan beklenmeyen bir yanıt geldi.', status: res.statusCode);
    }
    if (res.statusCode >= 400 || body['ok'] != true) {
      final err = (body['error'] as Map?)?.cast<String, dynamic>() ?? const {};
      throw ArconApiException(
        err['code'] as String? ?? 'error',
        err['message'] as String? ?? 'İşlem tamamlanamadı.',
        status: res.statusCode,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _get(String endpoint, [Map<String, String>? q]) =>
      _send(() => _http.get(_uri(endpoint, q), headers: _headers));

  Future<Map<String, dynamic>> _post(String endpoint, [Map<String, Object?> data = const {}]) =>
      _send(() => _http.post(_uri(endpoint), headers: _headers, body: jsonEncode(data)));

  Future<LoginResult> login(String login, String password, {String deviceName = ''}) async {
    final j = await _post('login', {
      'login': login,
      'password': password,
      'app': appKey,
      'device_name': deviceName,
    });
    return LoginResult(j['token'] as String, ArconUser.fromJson(j['user'] as Map<String, dynamic>));
  }

  Future<void> logout() => _post('logout');

  Future<ArconUser> me() async =>
      ArconUser.fromJson((await _get('me'))['user'] as Map<String, dynamic>);

  Future<List<ArconModule>> modules() async {
    final j = await _get('modules', {'app': appKey});
    return (j['modules'] as List)
        .cast<Map<String, dynamic>>()
        .map(ArconModule.fromJson)
        .toList(growable: false);
  }

  /// WebView'de açılacak tek kullanımlık giriş linki (2 dk geçerli).
  Future<Uri> webSessionUrl(String path) async =>
      Uri.parse((await _post('web_session', {'path': path}))['url'] as String);

  /// ARCON AI motoruna giriş için 5 dakikalık imzalı parametreler.
  Future<Map<String, dynamic>> engineSso() => _post('engine_sso');

  /// Profil fotoğrafı yükle (jpg/png/webp, en fazla 8 MB). Yeni fotoğrafın adresini döner.
  Future<String?> uploadAvatar(String filePath) => _send(() async {
        final req = http.MultipartRequest('POST', _uri('avatar'))
          ..headers.addAll({
            'Accept': 'application/json',
            if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
          })
          ..files.add(await http.MultipartFile.fromPath('avatar', filePath));
        return http.Response.fromStream(await _http.send(req));
      }).then((j) => j['avatar_url'] as String?);

  Future<void> removeAvatar() => _post('avatar', {'remove': true});

  Future<void> registerDevice({required String platform, required String pushToken, String appVersion = ''}) =>
      _post('devices', {'platform': platform, 'push_token': pushToken, 'app_version': appVersion});

  /// Bildirim teşhisi: sunucu bu hesabın cihazlarına deneme bildirimi gönderir, sonuçları döner.
  Future<Map<String, dynamic>> pushTest() => _post('push_test');
}
