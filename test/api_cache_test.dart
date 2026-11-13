import 'dart:async';

import 'package:arcon_club/arcon_core.dart';
import 'package:arcon_club/src/api/api_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // disk yok (path_provider) → yalnızca bellek

  bool isNet(Object e) => e is ArconApiException && e.code == 'network';

  test('tazelik süresi içinde ikinci istek ağa gitmez', () async {
    final cache = ApiCache();
    var calls = 0;
    Future<Map<String, dynamic>> fetch() async {
      calls++;
      return {'ok': true, 'n': calls};
    }

    final a = await cachedFetch(cache: cache, key: 'k', fetch: fetch, maxAge: const Duration(minutes: 1), isNetworkError: isNet);
    final b = await cachedFetch(cache: cache, key: 'k', fetch: fetch, maxAge: const Duration(minutes: 1), isNetworkError: isNet);
    expect(calls, 1);
    expect(b['n'], a['n']);

    // force her zaman ağ
    await cachedFetch(cache: cache, key: 'k', fetch: fetch, maxAge: const Duration(minutes: 1), force: true, isNetworkError: isNet);
    expect(calls, 2);
  });

  test('ağ yoksa son yanıt döner, başka hata yeniden fırlatılır', () async {
    final cache = ApiCache()..write('k', {'ok': true, 'v': 'eski'});
    final r = await cachedFetch(
      cache: cache,
      key: 'k',
      fetch: () async => throw const ArconApiException('network', 'yok'),
      force: true,
      isNetworkError: isNet,
    );
    expect(r['v'], 'eski');

    expect(
      () => cachedFetch(
        cache: cache,
        key: 'k',
        fetch: () async => throw const ArconApiException('forbidden', 'yasak', status: 403),
        force: true,
        isNetworkError: isNet,
      ),
      throwsA(isA<ArconApiException>()),
    );
  });

  test('aynı anda gelen istekler tek isteğe iner', () async {
    final cache = ApiCache();
    var calls = 0;
    final gate = Completer<void>();
    Future<Map<String, dynamic>> fetch() async {
      calls++;
      await gate.future;
      return {'ok': true};
    }

    final f1 = cachedFetch(cache: cache, key: 'k', fetch: fetch, force: true, isNetworkError: isNet);
    final f2 = cachedFetch(cache: cache, key: 'k', fetch: fetch, force: true, isNetworkError: isNet);
    gate.complete();
    await Future.wait([f1, f2]);
    expect(calls, 1);
  });

  test('invalidate ve oturum değişimi kayıtları siler', () async {
    final cache = ApiCache()
      ..setScope('token-a')
      ..write('v1:mag?cat=all&view=feed', {'ok': true})
      ..write('v1:mag?slug=x&view=post', {'ok': true});
    await cache.invalidateWhere((k) => k.contains('view=feed'));
    expect(await cache.read('v1:mag?cat=all&view=feed'), isNull);
    expect(await cache.read('v1:mag?slug=x&view=post'), isNotNull);

    cache.setScope('token-b');
    expect(await cache.read('v1:mag?slug=x&view=post'), isNull);
  });

  test('anahtar sorgu sırasından bağımsız', () {
    expect(ApiCache.key('v1', 'mag', {'view': 'feed', 'cat': 'ai'}), ApiCache.key('v1', 'mag', {'cat': 'ai', 'view': 'feed'}));
  });
}
