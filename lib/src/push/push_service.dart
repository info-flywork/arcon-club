import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../auth/token_store.dart';
import '../config.dart';
import '../talk/talk_api.dart';
import 'incoming_callkit.dart';

/// Ekran kapalıyken WhatsApp benzeri tam ekran gelen arama.
@pragma('vm:entry-point')
Future<void> arconPushBackgroundHandler(RemoteMessage message) async {
  final type = message.data['type'];
  if (type != 'call' && type != 'call_end') return;
  WidgetsFlutterBinding.ensureInitialized();
  // arayan vazgeçti: çalan tam ekran aramayı kapat
  if (type == 'call_end') {
    final id = int.tryParse('${message.data['call_id'] ?? ''}') ?? 0;
    if (id > 0) await ArconCallkit.end(id);
    return;
  }
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  final callId = int.tryParse('${message.data['call_id'] ?? ''}') ?? 0;
  final channelId = int.tryParse('${message.data['channel_id'] ?? ''}') ?? 0;
  if (callId <= 0) return;
  final name = (message.data['caller'] ?? message.data['title'] ?? message.notification?.title ?? 'ARCONNECT').toString();
  // Uygulama kapalıyken bu işleyici bitince Android arka plan motorunu kapatır; o zaman "Reddet"
  // olayını kimse duymaz ve arayan çalmaya devam eder. Arama cevaplanana / reddedilene / süresi
  // dolana kadar beklenir (reddi ArconCallkit.listen sunucuya bildirir).
  final done = Completer<void>();
  final sub = FlutterCallkitIncoming.onEvent.listen((event) {
    if (event is CallEventActionCallAccept ||
        event is CallEventActionCallDecline ||
        event is CallEventActionCallEnded ||
        event is CallEventActionCallTimeout) {
      // reddetme isteğinin gitmesine zaman tanı
      Future<void>.delayed(const Duration(seconds: 4), () {
        if (!done.isCompleted) done.complete();
      });
    }
  });
  await ArconCallkit.showIncoming(
    callId: callId,
    channelId: channelId,
    callerName: name,
    video: message.data['video'] == '1',
  );
  // Bu sırada gelen "call_end" bildirimi kuyrukta bekler (Android bildirimleri sırayla işler):
  // arayan vazgeçerse çalma hemen dursun diye arama durumu sunucudan sorulur.
  final until = DateTime.now().add(const Duration(seconds: 50));
  while (!done.isCompleted && DateTime.now().isBefore(until)) {
    await Future.any([done.future, Future<void>.delayed(const Duration(seconds: 2))]);
    if (done.isCompleted) break;
    if (!await PushService.callStillRinging(callId)) {
      await ArconCallkit.end(callId);
      break;
    }
  }
  await sub.cancel();
}

/// Push bildirimleri (Firebase Cloud Messaging).
///
/// Uygulama ayarında `push: true` olunca (ARCONNECT) ya da `--dart-define=ARCON_PUSH=true` ile açılır.
/// Firebase dosyaları (iOS: GoogleService-Info.plist, Android: google-services.json) yoksa
/// başlatma sessizce başarısız olur ve hiçbir şey yapmaz.
///
/// Uygulama açıkken bildirimi [LocalNotifier] gösterir (açık sohbeti atlar); push yalnızca
/// uygulama arka plandayken / kapalıyken görünür, böylece çift bildirim çıkmaz.
///
/// Bildirime dokununca: `type=talk` → ilgili ARCONNECT sohbeti açılır ([openTalkChannel]).
class PushService {
  PushService._();

  static const bool _forced = bool.fromEnvironment('ARCON_PUSH');
  static bool _enabled = _forced;

  /// Açılması bekleyen ARCONNECT kanalı (bildirime dokunuldu). TalkHomeScreen dinler.
  static final ValueNotifier<int?> openTalkChannel = ValueNotifier<int?>(null);

  /// Bildirimden gelen arama (call_id). TalkHomeScreen dinler.
  static final ValueNotifier<int?> openIncomingCallId = ValueNotifier<int?>(null);
  static bool incomingCallAccepted = false;

  /// Kanal açılması istendiğinde ARCONNECT ekranı açık değilse onu açar (Club'da).
  static void Function(int channelId)? onOpenTalk;

  static bool _started = false;
  static SessionController? _session;
  static TalkApi? _talk;
  static StreamSubscription<String>? _tokenSub;
  static Timer? _apnsRetry;

  /// `main()` içinde, `runApp` öncesi (yalnızca push açik uygulamalar).
  static void bindBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(arconPushBackgroundHandler);
    ArconCallkit.listen();
  }

  /// Uygulama yeni uyanırken oturum hazır olmadan gelen "reddet"ler oturum açılınca gönderilir.
  static final Set<int> _pendingDeclines = {};

  /// CallKit'te (kilit ekranı) kırmızı düğmeyle kapatılan arama: açık arama ekranı da kapanır.
  static final ValueNotifier<int?> hangupRequested = ValueNotifier<int?>(null);

  static Future<void> declineIncoming(int callId) async {
    hangupRequested.value = callId;
    // uygulama kapalıyken (arka planda uyanmış) oturum yok: kayıtlı oturumla hemen bildir,
    // yoksa arayan taraf çalmaya devam eder
    final talk = _talk ?? await _storedTalk();
    if (talk == null) {
      _pendingDeclines.add(callId);
      return;
    }
    try {
      await talk.callDecline(callId);
    } catch (_) {
      _pendingDeclines.add(callId);
    }
  }

  /// Arka planda: arama sunucuda hâlâ sürüyor mu? Bilinmiyorsa (ağ yok) sürüyor sayılır.
  static Future<bool> callStillRinging(int callId) async {
    final talk = _talk ?? await _storedTalk();
    if (talk == null) return true;
    try {
      final j = await talk.live('').timeout(const Duration(seconds: 6));
      final calls = (j['calls'] as List?) ?? const [];
      return calls.whereType<Map>().any((c) => '${c['id']}' == '$callId' && '${c['status']}' != 'ended');
    } catch (_) {
      return true;
    }
  }

  static const _prefsApp = 'arcon_push_app_key';
  static const _prefsBase = 'arcon_push_api_base';

  /// Arka planda (oturum açılmadan) API: uygulama anahtarı ve adres son açılışta kaydedilir,
  /// oturum belirteci cihazın güvenli deposundan okunur.
  static Future<TalkApi?> _storedTalk() async {
    try {
      final p = await SharedPreferences.getInstance();
      final app = p.getString(_prefsApp) ?? '';
      final base = p.getString(_prefsBase) ?? '';
      if (app.isEmpty || base.isEmpty) return null;
      final token = await SecureTokenStore('arcon_token_$app').read();
      if (token == null || token.isEmpty) return null;
      return TalkApi(arcon: ArconApi(baseUrl: base, appKey: app, token: token), baseUrl: base);
    } catch (_) {
      return null;
    }
  }

  static String _appVersion = '';

  /// iPhone VoIP (PushKit) belirtecini sunucuya kaydeder: kilit ekranında tam ekran arama için.
  static Future<void> registerVoip() async {
    if (!Platform.isIOS) return;
    final s = _session;
    if (s == null || s.user == null) return;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token == null || token.isEmpty) return;
      await s.api.registerDevice(platform: 'ios_voip', pushToken: token, appVersion: _appVersion);
    } catch (e) {
      debugPrint('[push] VoIP kaydı başarısız: $e');
    }
  }

  /// Oturum açıkken çağrılır; izin ister, cihazı sunucuya kaydeder, dokunmaları dinler.
  static Future<void> start(SessionController session, {bool enabled = false, String appVersion = '', String apiBase = ''}) async {
    _enabled = _forced || enabled;
    if (!_enabled) return;
    _session = session;
    _appVersion = appVersion;
    final base = apiBase.isEmpty ? ArconAppConfig.defaultApiBase : apiBase;
    _talk = TalkApi(arcon: session.api, baseUrl: base);
    unawaited(SharedPreferences.getInstance().then((p) async {
      await p.setString(_prefsApp, session.api.appKey);
      await p.setString(_prefsBase, base);
    }).catchError((_) {}));
    for (final id in _pendingDeclines.toList()) {
      _pendingDeclines.remove(id);
      unawaited(declineIncoming(id));
    }
    // kilit ekranında kabul edilip sonra açılan arama: hemen bağlan
    unawaited(ArconCallkit.acceptedCall().then((id) {
      if (id != null) requestOpenCall(id, accepted: true);
    }));
    unawaited(registerVoip());
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        lastError = 'bildirim izni reddedildi';
        return;
      }
      // Uygulama açıkken bildirimi LocalNotifier gösteriyor; iOS push'u ayrıca göstermesin
      await fm.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false);

      await _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((t) => _register(t, appVersion));
      await _takeFcmToken(fm, appVersion);

      ArconCallkit.listen();
      unawaited(ArconCallkit.requestAndroidLockScreen());

      if (!_started) {
        _started = true;
        FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
        final initial = await fm.getInitialMessage();
        if (initial != null) _handleTap(initial);
      }
    } catch (e) {
      lastError = 'başlatılamadı: $e';
      debugPrint('[push] başlatılamadı: $e');
    }
  }

  /// Çıkışta: bu cihaz artık bildirim almasın (sunucudaki token zaten iptal edilir).
  static Future<void> _takeFcmToken(FirebaseMessaging fm, String appVersion) async {
    if (Platform.isIOS) {
      String? apns;
      for (var i = 0; i < 15; i++) {
        apns = await fm.getAPNSToken();
        if (apns != null && apns.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      if (apns == null || apns.isEmpty) {
        _apnsRetry?.cancel();
        _apnsRetry = Timer.periodic(const Duration(seconds: 4), (t) async {
          try {
            final later = await fm.getAPNSToken();
            if (later == null || later.isEmpty) return;
            t.cancel();
            final token = await fm.getToken();
            if (token != null) await _register(token, appVersion);
          } catch (e) {
            debugPrint('[push] FCM token: $e');
          }
        });
        return;
      }
    }
    try {
      final token = await fm.getToken();
      if (token != null) {
        await _register(token, appVersion);
      } else {
        lastError = 'FCM token boş';
      }
    } catch (e) {
      lastError = 'FCM token: $e';
      debugPrint('[push] FCM token: $e');
    }
  }

  static Future<void> stop() async {
    if (!_enabled) return;
    _apnsRetry?.cancel();
    _apnsRetry = null;
    await _tokenSub?.cancel();
    _tokenSub = null;
    try {
      if (Firebase.apps.isNotEmpty) await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  /// "Bildirim testi" için telefon tarafındaki durum: FCM token alındı mı, kayıt / başlatma hatası.
  static String? lastToken;
  static String lastError = '';
  static bool get started => _started;
  static bool get enabled => _enabled;

  static Future<void> _register(String token, String appVersion) async {
    lastToken = token;
    final s = _session;
    if (s == null || s.user == null) {
      lastError = 'oturum yokken token geldi';
      return;
    }
    try {
      await s.api.registerDevice(
        platform: Platform.isIOS ? 'ios' : 'android',
        pushToken: token,
        appVersion: appVersion,
      );
      lastError = '';
    } catch (e) {
      lastError = 'cihaz kaydı: $e';
      debugPrint('[push] cihaz kaydı başarısız: $e');
    }
  }

  /// Token'ı yeniden alıp sunucuya kaydeder (Bildirim testi öncesi).
  static Future<void> reRegister() async {
    if (!_enabled) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final t = await FirebaseMessaging.instance.getToken();
      if (t == null) {
        lastError = 'FCM token alınamadı';
        return;
      }
      await _register(t, _appVersion);
    } catch (e) {
      lastError = 'FCM: $e';
    }
  }

  static void _handleTap(RemoteMessage m) {
    if (m.data['type'] == 'call') {
      final id = int.tryParse('${m.data['call_id'] ?? ''}');
      if (id != null && id > 0) requestOpenCall(id);
      final ch = int.tryParse('${m.data['channel_id'] ?? ''}');
      if (ch != null && ch > 0) requestOpenTalk(ch);
      return;
    }
    if (m.data['type'] == 'talk') {
      final id = int.tryParse('${m.data['channel_id'] ?? ''}');
      if (id != null && id > 0) requestOpenTalk(id);
    }
  }

  static void handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('call:')) {
      final parts = payload.split(':');
      final callId = parts.length > 1 ? int.tryParse(parts[1]) : null;
      final ch = parts.length > 2 ? int.tryParse(parts[2]) : null;
      if (callId != null && callId > 0) requestOpenCall(callId);
      if (ch != null && ch > 0) requestOpenTalk(ch);
      return;
    }
    final id = int.tryParse(payload);
    if (id != null && id > 0) requestOpenTalk(id);
  }

  /// Bildirim dokunması (veya test) → ARCONNECT kanalını aç.
  static void requestOpenTalk(int channelId) {
    openTalkChannel.value = channelId;
    onOpenTalk?.call(channelId);
  }

  static void requestOpenCall(int callId, {bool accepted = false}) {
    incomingCallAccepted = accepted;
    openIncomingCallId.value = callId;
  }
}
