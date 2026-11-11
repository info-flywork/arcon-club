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
      _user = await api.me();
      notifyListeners();
    } on ArconApiException catch (e) {
      await handleError(e);
      rethrow;
    }
  }

  Future<void> refreshModules() async {
    try {
      _modules = await api.modules();
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
    await store.clear();
    _set(SessionStatus.signedOut);
  }

  void _set(SessionStatus s) {
    _status = s;
    notifyListeners();
  }
}
