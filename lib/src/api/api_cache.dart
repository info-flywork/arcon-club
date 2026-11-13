import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Önbellekteki bir yanıt ve kaydedildiği an.
class CacheEntry {
  const CacheEntry(this.json, this.savedAt);
  final Map<String, dynamic> json;
  final DateTime savedAt;

  bool freshFor(Duration maxAge) => DateTime.now().difference(savedAt) < maxAge;
}

/// Proje geneli API önbelleği: bellek + disk (uygulama destek klasörü).
///
/// - **Tazelik süresi:** süresi dolmamış yanıt için sunucuya hiç gidilmez.
/// - **Önce önbellek, sonra tazele:** ekranlar [read] ile eldekini anında çizer, ardından yeniler.
/// - **Çevrimdışı:** ağ yoksa süresi geçmiş olsa da son yanıt kullanılır.
/// - **İstek birleştirme:** aynı anahtar için aynı anda gelen istekler tek isteğe iner ([dedupe]).
///
/// Kayıtlar oturuma (token) göre ayrılır; çıkışta tamamen silinir. Yalnızca GET yanıtları tutulur.
class ApiCache {
  ApiCache({this.maxMemoryEntries = 300});

  final int maxMemoryEntries;
  final _memory = <String, CacheEntry>{};
  final _inflight = <String, Future<Map<String, dynamic>>>{};
  String _scope = 'anon';
  Directory? _dir;

  /// Oturum değişince çağrılır (token özetiyle); farklı hesapların verisi karışmaz.
  void setScope(String? token) {
    final next = (token == null || token.isEmpty) ? 'anon' : _fnv(token);
    if (next == _scope) return;
    _scope = next;
    _memory.clear();
    _dir = null;
  }

  /// Testlerde (platform kanalı yok) ve klasör alınamazsa yalnızca bellek kullanılır.
  static final bool _noDisk = Platform.environment.containsKey('FLUTTER_TEST');
  bool _diskFailed = false;

  Future<Directory?> _folder() async {
    if (_dir != null) return _dir;
    if (_noDisk || _diskFailed) return null;
    try {
      final base = await getApplicationSupportDirectory().timeout(const Duration(seconds: 3));
      final d = Directory('${base.path}/arcon_cache/$_scope');
      if (!d.existsSync()) d.createSync(recursive: true);
      return _dir = d;
    } catch (_) {
      _diskFailed = true;
      return null;
    }
  }

  String _file(Directory d, String key) => '${d.path}/${_fnv(key)}.json';

  /// Eldeki kayıt (bellek, yoksa disk); hiç yoksa null.
  Future<CacheEntry?> read(String key) async {
    final mem = _memory[key];
    if (mem != null) return mem;
    final d = await _folder();
    if (d == null) return null;
    try {
      final f = File(_file(d, key));
      if (!f.existsSync()) return null;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (raw['k'] != key) return null; // özet çakışması
      final e = CacheEntry((raw['j'] as Map).cast<String, dynamic>(), DateTime.fromMillisecondsSinceEpoch((raw['t'] as num).toInt()));
      _remember(key, e);
      return e;
    } catch (_) {
      return null;
    }
  }

  void write(String key, Map<String, dynamic> json) {
    final e = CacheEntry(json, DateTime.now());
    _remember(key, e);
    unawaited(() async {
      final d = await _folder();
      if (d == null) return;
      try {
        await File(_file(d, key)).writeAsString(jsonEncode({'k': key, 't': e.savedAt.millisecondsSinceEpoch, 'j': json}));
      } catch (_) {}
    }());
  }

  void _remember(String key, CacheEntry e) {
    _memory.remove(key);
    _memory[key] = e;
    while (_memory.length > maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// Anahtarı bu önekle başlayan kayıtları siler (ör. bir işlemden sonra liste bayatladıysa).
  Future<void> invalidate(String prefix) => invalidateWhere((k) => k.startsWith(prefix));

  /// Koşula uyan kayıtları siler.
  Future<void> invalidateWhere(bool Function(String key) test) async {
    final keys = _memory.keys.where(test).toList();
    for (final k in keys) {
      _memory.remove(k);
    }
    final d = await _folder();
    if (d == null) return;
    try {
      for (final f in d.listSync().whereType<File>()) {
        // dosya adı özet; anahtarı içinden okuyup karşılaştır (dosyalar küçük)
        try {
          final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          if (test('${raw['k']}')) f.deleteSync();
        } catch (_) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }

  /// Çıkışta: bu cihazdaki tüm oturumların önbelleği.
  Future<void> clear() async {
    _memory.clear();
    _inflight.clear();
    if (_noDisk || _diskFailed) return;
    try {
      final base = await getApplicationSupportDirectory().timeout(const Duration(seconds: 3));
      final d = Directory('${base.path}/arcon_cache');
      if (d.existsSync()) d.deleteSync(recursive: true);
      // önceki hesabın görselleri (avatar, haber kapakları, AI görselleri) cihazda kalmasın
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    _dir = null;
  }

  /// Aynı anahtar için süren istek varsa onu bekler; yoksa [run]'ı başlatır.
  Future<Map<String, dynamic>> dedupe(String key, Future<Map<String, dynamic>> Function() run) {
    final running = _inflight[key];
    if (running != null) return running;
    // Not: geri çağırma bir şey döndürmemeli; silinen kaydı (aynı Future'ı) döndürürse istek kendini bekler.
    final f = run().whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = f;
    return f;
  }

  /// Kalıcı özet (String.hashCode çalıştırmalar arasında sabit değil).
  static String _fnv(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  /// İstek anahtarı: yol + sıralı sorgu.
  static String key(String scope, String path, [Map<String, String>? q]) {
    if (q == null || q.isEmpty) return '$scope:$path';
    final parts = (q.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join('&');
    return '$scope:$path?$parts';
  }
}

/// GET önbellek ilkesi: [maxAge] dolmadıysa ağa gidilmez; [force] her zaman ağ (aşağı çekip yenileme).
/// Ağ hatasında eldeki son yanıt döner ([offline]).
Future<Map<String, dynamic>> cachedFetch({
  required ApiCache cache,
  required String key,
  required Future<Map<String, dynamic>> Function() fetch,
  Duration? maxAge,
  bool force = false,
  bool offline = true,
  bool Function(Object error)? isNetworkError,
}) async {
  CacheEntry? hit;
  if (!force && maxAge != null) {
    hit = await cache.read(key);
    if (hit != null && hit.freshFor(maxAge)) return hit.json;
  }
  try {
    final json = await cache.dedupe(key, fetch);
    cache.write(key, json);
    return json;
  } catch (e) {
    if (offline && (isNetworkError?.call(e) ?? false)) {
      hit ??= await cache.read(key);
      if (hit != null) return hit.json;
    }
    rethrow;
  }
}
