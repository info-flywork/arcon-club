import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../mag/mag_models.dart';
import 'api_cache.dart';
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
  ArconApi({required String baseUrl, required this.appKey, http.Client? client, String? token, ApiCache? cache})
      : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = client ?? http.Client(),
        cache = cache ?? ApiCache() {
    this.token = token;
  }

  final Uri _base;

  /// Web uygulamasındaki göreli yolun tam adresi (görseller vb.).
  Uri webUrl(String path) => _base.resolve(path);
  final http.Client _http;
  final String appKey;

  /// Proje geneli GET önbelleği (ARCONNECT, To-Do ve AI istemcileri de bunu kullanır).
  final ApiCache cache;

  String? _token;

  /// Giriş sonrası her istekte `Authorization: Bearer` olarak gönderilir.
  /// Değişince önbellek de o oturuma geçer (hesaplar karışmaz).
  String? get token => _token;
  set token(String? t) {
    _token = t;
    cache.setScope(t);
  }

  /// Uç bazında tazelik süreleri: bu süre dolmadan aynı istek sunucuya gitmez.
  static const ttlUser = Duration(minutes: 5);
  static const ttlModules = Duration(minutes: 5);
  static const ttlDashboard = Duration(seconds: 60);
  static const ttlProfile = Duration(minutes: 5);
  static const ttlMagFeed = Duration(minutes: 2);
  static const ttlMagPost = Duration(minutes: 10);

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

  /// GET. [maxAge] verilirse önbellek ilkesi uygulanır (bkz. [cachedFetch]); [force] her zaman ağ.
  Future<Map<String, dynamic>> _get(String endpoint, [Map<String, String>? q, Duration? maxAge, bool force = false]) {
    Future<Map<String, dynamic>> net() => _send(() => _http.get(_uri(endpoint, q), headers: _headers));
    if (maxAge == null) return net();
    return cachedFetch(
      cache: cache,
      key: ApiCache.key('v1', endpoint, q),
      fetch: net,
      maxAge: maxAge,
      force: force,
      isNetworkError: (e) => e is ArconApiException && e.code == 'network',
    );
  }

  /// Önbellekteki son yanıt (ağa gitmez); ekranın anında çizmesi için.
  Future<Map<String, dynamic>?> _peek(String endpoint, [Map<String, String>? q]) async =>
      (await cache.read(ApiCache.key('v1', endpoint, q)))?.json;

  Map<String, String> _magFeedQuery(String category, String? query, String? tag) => {
        'view': 'feed',
        'cat': category,
        if (query != null && query.isNotEmpty) 'q': query,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      };

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

  /// Yeni hesap; webdeki kayıtla aynı kurallar ve hesap yönetici onayıyla açılır.
  /// Mobil API'de kayıt ucu olmadığı için webin `register` formuna gönderilir ve sonuç
  /// mesajı sayfadaki uyarı kutusundan okunur. Başarıda sunucunun mesajını döner.
  Future<String> register({required String username, required String email, required String password}) async {
    http.Response res;
    try {
      res = await _http
          .post(
            _base.resolve('register'),
            headers: const {'Accept': 'text/html'},
            body: {'username': username, 'email': email, 'password': password},
          )
          .timeout(_timeout);
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    final html = utf8.decode(res.bodyBytes, allowMalformed: true);
    final m = RegExp(r'class="alert (is-success|is-error)">\s*([\s\S]*?)\s*</div>').firstMatch(html);
    if (m == null) {
      throw ArconApiException('bad_response', 'Kayıt tamamlanamadı. Lütfen daha sonra tekrar deneyin.',
          status: res.statusCode);
    }
    final msg = m
        .group(2)!
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    if (m.group(1) == 'is-success') return msg;
    throw ArconApiException('register_failed', msg, status: res.statusCode);
  }

  Future<void> logout() => _post('logout');

  static ArconUser _user(Map<String, dynamic> j) => ArconUser.fromJson(j['user'] as Map<String, dynamic>);
  static List<ArconModule> _modules(Map<String, dynamic> j) =>
      (j['modules'] as List).cast<Map<String, dynamic>>().map(ArconModule.fromJson).toList(growable: false);

  Future<ArconUser> me({bool force = false}) async => _user(await _get('me', null, ttlUser, force));

  Future<List<ArconModule>> modules({bool force = false}) async => _modules(await _get('modules', {'app': appKey}, ttlModules, force));

  /// Önbellekteki kullanıcı ve modüller (açılışta oturumu ağı beklemeden kurmak için).
  Future<ArconUser?> cachedMe() async {
    final j = await _peek('me');
    return j == null ? null : _user(j);
  }

  Future<List<ArconModule>?> cachedModules() async {
    final j = await _peek('modules', {'app': appKey});
    return j == null ? null : _modules(j);
  }

  /// Ana sayfa verisi (webdeki Dashboard ile aynı).
  Future<DashboardData> dashboard({bool force = false}) async =>
      DashboardData.fromJson(await _get('dashboard', null, ttlDashboard, force));

  Future<DashboardData?> cachedDashboard() async {
    final j = await _peek('dashboard');
    return j == null ? null : DashboardData.fromJson(j);
  }

  /// ARCON MAG akışı: kategori, arama (q) ya da etiket (tag) ile.
  Future<MagFeed> magFeed({String category = 'all', String? query, String? tag, bool force = false}) async =>
      MagFeed.fromJson(await _get('mag', _magFeedQuery(category, query, tag), ttlMagFeed, force));

  Future<MagFeed?> cachedMagFeed({String category = 'all', String? query, String? tag}) async {
    final j = await _peek('mag', _magFeedQuery(category, query, tag));
    return j == null ? null : MagFeed.fromJson(j);
  }

  /// Haber detayı. Sunucu açılışta okundu işaretler; bu yüzden ilk açılış her zaman ağdan,
  /// sonraki açılışlar [ttlMagPost] boyunca önbellekten (beğeni vb. işlemler kaydı siler).
  Future<MagPost> magPost(String slug, {bool force = false}) async {
    final key = {'view': 'post', 'slug': slug};
    final known = await _peek('mag', key);
    final j = await _get('mag', key, ttlMagPost, force || known == null);
    if (known == null || force) {
      // okundu bilgisi değişti: akış ve ana sayfa sayaçları bayatladı
      unawaited(_invalidateMagFeeds());
      unawaited(cache.invalidate(ApiCache.key('v1', 'dashboard')));
    }
    return MagPost.fromJson(j);
  }

  Future<void> _invalidateMagFeeds() => cache.invalidateWhere((k) => k.startsWith('v1:mag?') && k.contains('view=feed'));

  Future<MagPost?> cachedMagPost(String slug) async {
    final j = await _peek('mag', {'view': 'post', 'slug': slug});
    return j == null ? null : MagPost.fromJson(j);
  }

  /// `saved` ya da `liked`.
  Future<List<MagPostSummary>> magList(String view, {bool force = false}) async =>
      magPostsFromJson((await _get('mag', {'view': view}, ttlMagFeed, force))['posts']);

  /// Haftalık sayı (`week` boşsa en güncel): number, range, newer, older, pdf_path, posts.
  Future<Map<String, dynamic>> magIssue(String? week, {bool force = false}) =>
      _get('mag', {'view': 'issue', 'w': ?week}, ttlMagFeed, force);

  Future<List<MagPostSummary>?> cachedMagList(String view) async {
    final j = await _peek('mag', {'view': view});
    return j == null ? null : magPostsFromJson(j['posts']);
  }

  /// like / save / ack / react (type ile). İlgili önbellek kayıtları silinir.
  Future<Map<String, dynamic>> magAction(String action, String slug, {String? type}) async {
    final r = await _post('mag', {'action': action, 'slug': slug, 'type': ?type});
    await cache.invalidate(ApiCache.key('v1', 'mag', {'slug': slug, 'view': 'post'}));
    if (action == 'save' || action == 'like') {
      await cache.invalidate(ApiCache.key('v1', 'mag', {'view': 'saved'}));
      await cache.invalidate(ApiCache.key('v1', 'mag', {'view': 'liked'}));
      await _invalidateMagFeeds();
    }
    return r;
  }

  /* ---------- People / Search / Idea / Feedback (ham JSON; modeller ekran dosyalarında) ---------- */

  static const ttlPeople = Duration(minutes: 10);
  static const ttlSearch = Duration(minutes: 2);
  static const ttlFeedbackInbox = Duration(seconds: 30);

  /// Kişiler dizini (tamamı tek istekte; süzme uygulamada).
  Future<Map<String, dynamic>> peopleJson({bool force = false}) => _get('people', null, ttlPeople, force);
  Future<Map<String, dynamic>?> cachedPeopleJson() => _peek('people');

  /// Webdeki arama motoru; aynı arama 2 dk önbellekten.
  Future<Map<String, dynamic>> searchJson(String q, {String cat = 'all'}) =>
      _get('search', {'q': q, 'cat': cat, 'limit': '40'}, ttlSearch);

  /// IDEA / FEEDBACK: yetki bilgisi, yöneticiye sayaçlar ve gelenler.
  Future<Map<String, dynamic>> feedbackJson(String kind, {String filter = 'all', String category = 'all', bool force = false}) =>
      _get('feedback', {'kind': kind, 'filter': filter, if (kind == 'feedback') 'category': category}, ttlFeedbackInbox, force);
  Future<Map<String, dynamic>?> cachedFeedbackJson(String kind, {String filter = 'all', String category = 'all'}) =>
      _peek('feedback', {'kind': kind, 'filter': filter, if (kind == 'feedback') 'category': category});

  Future<void> submitFeedback(String kind, {required String body, String name = '', String department = '', String contact = '', String? category}) async {
    await _post('feedback', {
      'kind': kind,
      'action': 'submit',
      'body': body,
      'name': name,
      'department': department,
      'contact': contact,
      'category': ?category,
    });
    await _feedbackChanged(kind);
  }

  /// Yönetici: read / new / archive / delete.
  Future<void> setFeedbackStatus(String kind, int id, String act) async {
    await _post('feedback', {'kind': kind, 'action': 'status', 'id': id, 'act': act});
    await _feedbackChanged(kind);
  }

  Future<void> _feedbackChanged(String kind) async {
    await cache.invalidateWhere((k) => k.startsWith('v1:feedback?') && k.contains('kind=$kind'));
    await cache.invalidate(ApiCache.key('v1', 'dashboard')); // ana sayfadaki "okunmamış fikir" sayaçları
  }

  /* ---------- Academy ---------- */

  static const ttlAkademiCatalog = Duration(minutes: 2);
  static const ttlAkademiModule = Duration(minutes: 10);
  static const ttlAkademiBoard = Duration(minutes: 5);

  Map<String, String> _akQuery(String view, String? slug) => {'view': view, 'slug': ?slug};

  Duration _akTtl(String view) => switch (view) {
        'module' => ttlAkademiModule,
        'leaderboard' => ttlAkademiBoard,
        _ => ttlAkademiCatalog,
      };

  /// `catalog`, `module` (slug ile) ya da `leaderboard`.
  Future<Map<String, dynamic>> akademiJson(String view, {String? slug, bool force = false}) =>
      _get('akademi', _akQuery(view, slug), _akTtl(view), force);
  Future<Map<String, dynamic>?> cachedAkademiJson(String view, {String? slug}) => _peek('akademi', _akQuery(view, slug));

  /// progress / quiz / note / assignment. İlerleme değişince katalog, sıralama, profil ve ana sayfa kayıtları silinir.
  Future<Map<String, dynamic>> akademiAction(String action, String slug, [Map<String, Object?> data = const {}]) async {
    final r = await _post('akademi', {'action': action, 'slug': slug, ...data});
    await cache.invalidateWhere((k) => k.startsWith('v1:akademi?') && (!k.contains('view=module') || k.contains('slug=$slug')));
    if (action == 'progress' || action == 'quiz') {
      await cache.invalidate(ApiCache.key('v1', 'profile'));
      await cache.invalidate(ApiCache.key('v1', 'dashboard'));
    }
    return r;
  }

  /* ---------- ARCON SCORE ---------- */

  Future<Map<String, dynamic>> skor({bool force = false}) => _get('skor', null, const Duration(minutes: 2), force);
  Future<Map<String, dynamic>?> cachedSkor() => _peek('skor');

  /// Bir grubun puanlarını kaydeder (soru id → 1..5).
  Future<Map<String, dynamic>> skorSubmit(int round, String group, Map<int, int> scores) async {
    final r = await _post('skor', {
      'round': round,
      'group': group,
      'scores': {for (final e in scores.entries) '${e.key}': e.value},
    });
    await cache.invalidate(ApiCache.key('v1', 'skor'));
    return r;
  }

  /* ---------- ARCON STORE ---------- */

  Future<Map<String, dynamic>> stores({bool force = false}) => _get('store', null, const Duration(minutes: 30), force);
  Future<Map<String, dynamic>?> cachedStores() => _peek('store');

  /* ---------- Kariyer (İK) ---------- */

  Map<String, String> _kariyerListQ(String filter, int? position) => {
        'view': 'list',
        'f': filter,
        if (position != null) 'position': '$position',
      };
  Future<Map<String, dynamic>> kariyerList({String filter = 'all', int? position, bool force = false}) =>
      _get('kariyer', _kariyerListQ(filter, position), const Duration(seconds: 45), force);
  Future<Map<String, dynamic>?> cachedKariyerList({String filter = 'all', int? position}) =>
      _peek('kariyer', _kariyerListQ(filter, position));
  Future<Map<String, dynamic>> kariyerApp(int id, {bool force = false}) =>
      _get('kariyer', {'view': 'app', 'id': '$id'}, const Duration(seconds: 30), force);
  Future<Map<String, dynamic>?> cachedKariyerApp(int id) => _peek('kariyer', {'view': 'app', 'id': '$id'});

  /// status / note / analyze — liste ve aday kayıtları önbellekten silinir.
  Future<Map<String, dynamic>> kariyerAction(String action, int id, [Map<String, Object?> data = const {}]) async {
    final r = await _post('kariyer', {'action': action, 'id': id, ...data});
    await cache.invalidateWhere((k) => k.startsWith('v1:kariyer?'));
    return r;
  }

  /// Toplu işlem, ilan kaydı, görüşme vb. — kimliksiz Kariyer işlemleri.
  Future<Map<String, dynamic>> kariyerPost(Map<String, Object?> body) async {
    final r = await _post('kariyer', body);
    await cache.invalidateWhere((k) => k.startsWith('v1:kariyer?'));
    return r;
  }

  Future<Map<String, dynamic>> kariyerPosition(int id) => _get('kariyer', {'view': 'position', 'id': '$id'});

  /* ---------- AI araçları (hr-ai, lawpath … /<klasör>/api.php) ---------- */

  /// Gömülü AI aracına istek (webdeki araçla aynı uç; oturum yerine Bearer token).
  /// Yanıt biçimi `{success, ...}`; hata `{success:false, error:"..."}`.
  /// [namedFiles]: alan adı → dosya yolu (CV Analyze: `job_file`, `cv_file`).
  Future<Map<String, dynamic>> toolPost(
    String folder,
    Map<String, String> fields, {
    List<String> files = const [],
    Map<String, String> namedFiles = const {},
  }) async {
    http.Response res;
    try {
      final req = http.MultipartRequest('POST', _base.resolve('$folder/api.php'))
        ..headers.addAll({
          'Accept': 'application/json',
          if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
        })
        ..fields.addAll(fields);
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath('files[]', f));
      }
      for (final e in namedFiles.entries) {
        req.files.add(await http.MultipartFile.fromPath(e.key, e.value));
      }
      res = await http.Response.fromStream(await _http.send(req)).timeout(const Duration(minutes: 4));
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    return _toolBody(res);
  }

  /// Webdeki bir yönetim formuna POST (Bearer token'la). Form işlem sonrası yönlendirir; yönlendirme
  /// takip edilmez, hedef adresin sorgu parametreleri döner (ör. `m=published`, `err=title`).
  Future<Map<String, String>> webForm(String path, Map<String, String> fields, {List<(String, String)> files = const [], Map<String, List<String>> lists = const {}}) async {
    final req = http.MultipartRequest('POST', _base.resolve(path))
      ..followRedirects = false
      ..headers.addAll({if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token'})
      ..fields.addAll(fields);
    // PHP dizi alanları (roles[] gibi): MultipartRequest aynı adı tekrarlayamadığı için dosyasız parça olarak eklenir
    for (final e in lists.entries) {
      for (final v in e.value) {
        req.files.add(http.MultipartFile.fromString(e.key, v));
      }
    }
    for (final (field, p) in files) {
      req.files.add(await http.MultipartFile.fromPath(field, p));
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req)).timeout(const Duration(minutes: 2));
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    if (res.statusCode == 401) throw const ArconApiException('tool_unavailable', 'Oturum doğrulanamadı.');
    final loc = res.headers['location'];
    if (res.statusCode >= 300 && res.statusCode < 400 && loc != null) {
      final u = Uri.parse(loc);
      return {...u.queryParameters, '_path': u.path};
    }
    if (res.statusCode >= 400) throw ArconApiException('tool_error', 'İşlem tamamlanamadı (HTTP ${res.statusCode}).');
    return {'_status': '${res.statusCode}'};
  }

  /// Web uygulamasındaki bir PHP ucuna Bearer token'la istek (`{ok}` ya da `{success}` yanıtı).
  /// [files]: (alan adı, yerel yol) — aynı alan birden çok kez verilebilir (`refs[]`).
  Future<Map<String, dynamic>> webCall(
    String path, {
    Map<String, String>? query,
    Map<String, String>? fields,
    List<(String, String)> files = const [],
    Object? jsonBody,
    Duration? timeout,
  }) async {
    final uri = _base.resolve(path).replace(queryParameters: query);
    http.Response res;
    try {
      if (jsonBody != null) {
        res = await _http.post(uri, headers: _headers, body: jsonEncode(jsonBody)).timeout(timeout ?? const Duration(minutes: 2));
      } else if (fields == null && files.isEmpty) {
        res = await _http.get(uri, headers: _headers).timeout(timeout ?? _timeout);
      } else {
        final req = http.MultipartRequest('POST', uri)
          ..headers.addAll({
            'Accept': 'application/json',
            if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
          })
          ..fields.addAll(fields ?? const {});
        for (final (field, p) in files) {
          req.files.add(await http.MultipartFile.fromPath(field, p));
        }
        res = await http.Response.fromStream(await _http.send(req)).timeout(timeout ?? const Duration(minutes: 2));
      }
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw const ArconApiException('tool_unavailable', 'Bu araç uygulamada henüz açılamıyor.');
    }
    if (res.statusCode == 401) throw const ArconApiException('tool_unavailable', 'Bu araç uygulamada henüz açılamıyor.');
    if (body['ok'] == true || body['success'] == true) return body;
    final e = body['error'];
    throw ArconApiException('tool_error', e is String && e.isNotEmpty ? e : (e is Map ? '${e['message'] ?? 'İşlem tamamlanamadı.'}' : 'İşlem tamamlanamadı.'));
  }

  /// ÜTS marka aracı (givenchy/api.php …): GET işlemleri (konuşmalar, mesajlar, son bot mesajı).
  Future<Map<String, dynamic>> utsGet(String folder, Map<String, String> query) async {
    try {
      final res = await _http.get(_base.resolve('$folder/api.php').replace(queryParameters: query), headers: _headers).timeout(_timeout);
      return _toolBody(res);
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
  }

  /// ÜTS mesajı (PDF + metin). Sunucu analizi bu istek içinde yapar; birkaç dakika sürebilir.
  /// [multiFile]: LP gibi çoklu PDF alan markalar `files[]`, diğerleri `file` bekler.
  Future<Map<String, dynamic>> utsSend(String folder, Map<String, String> fields, {List<String> files = const [], bool multiFile = false}) async {
    http.Response res;
    try {
      final req = http.MultipartRequest('POST', _base.resolve('$folder/api.php'))
        ..headers.addAll({
          'Accept': 'application/json',
          if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
        })
        ..fields.addAll({'action': 'send_message', ...fields});
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath(multiFile ? 'files[]' : 'file', f));
        if (!multiFile) break;
      }
      res = await http.Response.fromStream(await _http.send(req)).timeout(const Duration(minutes: 6));
    } on TimeoutException {
      throw const ArconApiException('timeout', 'Analiz uzun sürüyor; sonuç hazır olunca sohbette görünecek.');
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı. İnternet bağlantınızı kontrol edin.');
    }
    return _toolBody(res);
  }

  /// Araç sohbet geçmişi (webdeki tool_module_history.php ile ortak; hesap bazlı).
  Future<Map<String, dynamic>> toolHistoryLoad(String module) async {
    try {
      final res = await _http
          .get(_base.resolve('tool_module_history.php').replace(queryParameters: {'action': 'load', 'module_key': module}), headers: _headers)
          .timeout(_timeout);
      return _toolBody(res);
    } on ArconApiException {
      rethrow;
    } on Exception {
      throw const ArconApiException('network', 'Sunucuya ulaşılamadı.');
    }
  }

  Future<void> toolHistorySave(String module, List<Map<String, dynamic>> sessions, String? activeId) async {
    try {
      await _http
          .post(
            _base.resolve('tool_module_history.php'),
            headers: _headers,
            body: jsonEncode({'action': 'save', 'module_key': module, 'sessions': sessions.take(40).toList(), 'activeId': activeId}),
          )
          .timeout(_timeout);
    } on Exception {
      // geçmiş kaydı başarısız olsa da sohbet sürer
    }
  }

  Map<String, dynamic> _toolBody(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      // Oturum kontrolü eski sunucuda HTML/yönlendirme döner → güncelleme bekleniyor
      throw ArconApiException('tool_unavailable', 'Bu araç uygulamada henüz açılamıyor.', status: res.statusCode >= 500 ? res.statusCode : 0);
    }
    if (res.statusCode == 401) {
      // Araç kapısı token'ı tanımıyorsa (sunucu güncellenmemiş) oturumu kapatma; WebView'e düş
      throw const ArconApiException('tool_unavailable', 'Bu araç uygulamada henüz açılamıyor.');
    }
    if (res.statusCode >= 400 || body['success'] != true) {
      final e = body['error'];
      throw ArconApiException('tool_error', e is String && e.isNotEmpty ? e : 'İşlem tamamlanamadı.');
    }
    return body;
  }

  /* ---------- Helpdesk ---------- */

  Future<Map<String, dynamic>> helpdeskJson(String view, {Map<String, String> params = const {}, bool force = false}) => _get(
        'helpdesk',
        {'view': view, ...params},
        switch (view) {
          'meta' => const Duration(minutes: 10),
          'ticket' => const Duration(seconds: 15),
          _ => const Duration(seconds: 30),
        },
        force,
      );
  Future<Map<String, dynamic>?> cachedHelpdeskJson(String view, {Map<String, String> params = const {}}) =>
      _peek('helpdesk', {'view': view, ...params});

  /// Ek dosya (base64) — önbelleğe alınmaz.
  Future<Map<String, dynamic>> helpdeskFile(int id) => _get('helpdesk', {'view': 'file', 'id': '$id'});

  /// Yeni talep ya da yanıt (isteğe bağlı tek dosya). Liste ve talep kayıtları silinir.
  Future<Map<String, dynamic>> helpdeskSend(Map<String, String> fields, {String? filePath}) async {
    final r = await _send(() async {
      final req = http.MultipartRequest('POST', _uri('helpdesk'))
        ..headers.addAll({
          'Accept': 'application/json',
          if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
        })
        ..fields.addAll(fields);
      if (filePath != null) req.files.add(await http.MultipartFile.fromPath('attachment', filePath));
      return http.Response.fromStream(await _http.send(req));
    });
    await cache.invalidateWhere((k) => k.startsWith('v1:helpdesk?') && !k.contains('view=meta'));
    await cache.invalidate(ApiCache.key('v1', 'dashboard'));
    return r;
  }

  /// Profil + Academy rozet özeti.
  Future<ProfileData> profile({bool force = false}) async => ProfileData.fromJson(await _get('profile', null, ttlProfile, force));

  Future<ProfileData?> cachedProfile() async {
    final j = await _peek('profile');
    return j == null ? null : ProfileData.fromJson(j);
  }

  /// Kullanıcı bilgisi değişince (profil, fotoğraf) kullanıcıyı tutan kayıtlar silinir.
  Future<void> _userChanged() async {
    await cache.invalidate(ApiCache.key('v1', 'me'));
    await cache.invalidate(ApiCache.key('v1', 'profile'));
  }

  /// Kullanıcı adı / e-posta güncelle; güncel kullanıcıyı döner.
  Future<ArconUser> updateProfile({required String username, required String email}) async {
    final u = ArconUser.fromJson((await _post('profile', {'username': username, 'email': email}))['user'] as Map<String, dynamic>);
    await _userChanged();
    return u;
  }

  /// Webdeki profil kuralı: mevcut şifre + yeni şifre (en az 8) + tekrar.
  Future<void> changePassword({required String current, required String next, required String confirm}) =>
      _post('profile', {'current_password': current, 'new_password': next, 'new_password_confirm': confirm});

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
      }).then((j) async {
        await _userChanged();
        return j['avatar_url'] as String?;
      });

  Future<void> removeAvatar() async {
    await _post('avatar', {'remove': true});
    await _userChanged();
  }

  Future<void> registerDevice({required String platform, required String pushToken, String appVersion = ''}) =>
      _post('devices', {'platform': platform, 'push_token': pushToken, 'app_version': appVersion});

  /// Bildirim teşhisi: sunucu bu hesabın cihazlarına deneme bildirimi gönderir, sonuçları döner.
  Future<Map<String, dynamic>> pushTest() => _post('push_test');
}
