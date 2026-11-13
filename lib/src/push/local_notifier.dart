import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../auth/session_controller.dart';
import '../talk/talk_api.dart';
import '../talk/talk_models.dart';
import 'push_service.dart';

/// ARCONNECT mesaj bildirimleri — Firebase olmadan, cihazın kendi (yerel) bildirimleriyle.
///
/// Uygulama açıkken sohbet listesini belirli aralıklarla sorar; bir sohbetin okunmamış sayısı
/// artınca bildirim gösterir. Uygulama kapalıyken ya da işletim sistemi onu arka planda
/// askıya aldığında (iOS'ta yaklaşık 30 sn sonra) sorgu duraklar; uygulama yeniden öne gelince
/// arada gelen mesajlar için bildirim gösterilmez, sayaçlar sessizce güncellenir.
///
/// Bildirime dokununca ilgili sohbet açılır ([PushService.requestOpenTalk]).
class LocalNotifier with WidgetsBindingObserver {
  LocalNotifier._();

  static final LocalNotifier _i = LocalNotifier._();
  static const Duration interval = Duration(seconds: 15);

  /// Şu an ekranda açık olan sohbet; onun mesajları için bildirim gösterilmez.
  static int? openChannelId;

  /// Sessize alınmış sohbetler ([TalkController] doldurur); bunlar için bildirim gösterilmez.
  static Set<int> muted = {};

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  TalkApi? _api;
  Timer? _timer;
  bool _busy = false;
  bool _foreground = true;

  /// kanal id → son görülen okunmamış sayısı; null iken ilk sorgu sadece sayaçları doldurur.
  Map<int, int>? _unread;

  static Future<void> start(SessionController session, {required String baseUrl}) => _i._start(session, baseUrl);
  static Future<void> stop() => _i._stop();

  Future<void> _start(SessionController session, String baseUrl) async {
    _stopTimer();
    _api = TalkApi(arcon: session.api, baseUrl: baseUrl);
    _unread = null;
    try {
      await _init();
    } catch (e) {
      debugPrint('[bildirim] başlatılamadı: $e');
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  Future<void> _stop() async {
    _stopTimer();
    WidgetsBinding.instance.removeObserver(this);
    _api = null;
    _unread = null;
    try {
      if (_initialized) await _plugin.cancelAll();
    } catch (_) {}
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _init() async {
    if (_initialized) return;
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
      ),
      onDidReceiveNotificationResponse: (r) => _openFromPayload(r.payload),
    );
    _initialized = true;

    // İzin: iOS sistem penceresi, Android 13+ POST_NOTIFICATIONS
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    // Sunucudan gelen push da bu kanalı kullanır (arcon_push_lib.php: channel_id)
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'arconnect_messages_v2',
      'Mesajlar',
      description: 'ARCONNECT mesaj bildirimleri',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'arconnect_calls',
      'Aramalar',
      description: 'Gelen sesli ve görüntülü aramalar',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    ));

    // Uygulama bir bildirime dokunularak açıldıysa o sohbete git
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _openFromPayload(launch!.notificationResponse?.payload);
    }
  }

  void _openFromPayload(String? payload) {
    PushService.handleNotificationPayload(payload);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg && !_foreground) {
      // Askıdayken gelenler için toplu bildirim göstermeyelim: sayaçları sessizce tazele
      _unread = null;
      _poll();
    }
    _foreground = fg;
  }

  Future<void> _poll() async {
    final api = _api;
    if (api == null || _busy) return;
    _busy = true;
    try {
      // ARCONNECT ekranı son 12 sn'de listeyi aldıysa aynı yanıt kullanılır (çift istek yok)
      final boot = await api.bootstrap(maxAge: const Duration(seconds: 12));
      final prev = _unread;
      final next = <int, int>{};
      for (final ch in boot.channels) {
        next[ch.id] = ch.unread;
        final before = prev == null ? null : (prev[ch.id] ?? 0);
        if (before != null && ch.unread > before && !muted.contains(ch.id) && !(_foreground && openChannelId == ch.id)) {
          await _show(ch, ch.unread - before);
        }
      }
      if (_api == api) _unread = next;
    } catch (e) {
      debugPrint('[bildirim] sohbetler alınamadı: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _show(TalkChannel ch, int added) async {
    final title = ch.isDm ? (ch.peer?.displayName ?? ch.name) : ch.name;
    final text = ch.lastBody.trim();
    final body = text.isNotEmpty ? text : (added > 1 ? '$added yeni mesaj' : 'Yeni mesaj');
    await _plugin.show(
      id: ch.id,
      title: title.isEmpty ? 'ARCONNECT' : title,
      body: body,
      payload: '${ch.id}',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'arconnect_messages_v2',
          'Mesajlar',
          channelDescription: 'ARCONNECT mesaj bildirimleri',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true, presentList: true),
      ),
    );
  }
}
