import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'token_store.dart';

enum SessionStatus { loading, signedOut, signedIn }

/// Oturum durumu: açılışta kayıtlı token'ı doğrular, giriş/çıkışı yönetir,
/// sunucu 401 dönerse kullanıcıyı giriş ekranına düşürür.
class SessionController extends ChangeNotifier {
  SessionController({required this.api, required this.store});

  final ArconApi api;
  final TokenStore store;

  SessionStatus _status = SessionStatus.loading;
  ArconUser? _user;
  List<ArconModule> _modules = const [];

  SessionStatus get status => _status;
  ArconUser? get user => _user;
  List<ArconModule> get modules => _modules;

  Future<void> restore() async {
    final saved = await store.read();
    if (saved == null || saved.isEmpty) {
      _set(SessionStatus.signedOut);
      return;
    }
    api.token = saved;
    // Önbellekte son kullanıcı ve modüller varsa uygulama ağı beklemeden açılır,
    // ardından arka planda tazelenir (token iptal edildiyse 401 ile çıkışa düşer).
    final cachedUser = await api.cachedMe();
    final cachedModules = await api.cachedModules();
    if (cachedUser != null && cachedModules != null) {
      _user = cachedUser;
      _modules = cachedModules;
      _set(SessionStatus.signedIn);
      unawaited(_revalidate());
      return;
    }
    try {
      _user = await api.me();
      _modules = await api.modules();
      _set(SessionStatus.signedIn);
    } on ArconApiException catch (e) {
      if (e.isUnauthorized) {
        await _forget();
      } else {
        // Ağ yoksa token'ı silme; kullanıcı tekrar denediğinde devam eder.
        _set(SessionStatus.signedOut);
      }
    }
  }

  Future<void> _revalidate() async {
    try {
      final results = await Future.wait([api.me(force: true), api.modules(force: true)]);
      _user = results[0] as ArconUser;
      _modules = results[1] as List<ArconModule>;
      notifyListeners();
    } on ArconApiException catch (e) {
      await handleError(e); // ağ yoksa önbellekle devam
    }
  }

  Future<void> login(String login, String password, {String deviceName = ''}) async {
    final res = await api.login(login.trim(), password, deviceName: deviceName);
    api.token = res.token;
    await store.write(res.token);
    _user = res.user;
    _modules = await api.modules();
    _set(SessionStatus.signedIn);
  }

  /// Kullanıcı bilgisini (ör. profil fotoğrafı değişince) yeniden çek.
  Future<void> refreshMe() async {
    try {
      _user = await api.me(force: true);
      notifyListeners();
    } on ArconApiException catch (e) {
      await handleError(e);
      rethrow;
    }
  }

  /// Profil güncellenince sunucunun döndürdüğü kullanıcıyı yerleştir.
  void setUser(ArconUser user) {
    _user = user;
    notifyListeners();
  }

  /// [force] yoksa modül listesi tazelik süresi içindeyse sunucuya gidilmez.
  Future<void> refreshModules({bool force = false}) async {
    try {
      _modules = await api.modules(force: force);
      notifyListeners();
    } on ArconApiException catch (e) {
      await handleError(e);
      rethrow;
    }
  }

  /// Herhangi bir istekte oturum düştüyse çağrılır.
  Future<void> handleError(ArconApiException e) async {
    if (e.isUnauthorized) {
      await _forget();
    }
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ArconApiException {
      // Sunucuya ulaşılamasa da cihazdan çıkış yapılır.
    }
    await _forget();
  }

  Future<void> _forget() async {
    api.token = null;
    _user = null;
    _modules = const [];
    await api.cache.clear();
    await store.clear();
    _set(SessionStatus.signedOut);
  }

  void _set(SessionStatus s) {
    _status = s;
    notifyListeners();
  }
}
