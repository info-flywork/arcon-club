import 'dart:async';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'push_service.dart';

/// WhatsApp benzeri kilit ekranı gelen arama (Android tam ekran / iOS CallKit).
class ArconCallkit {
  ArconCallkit._();

  static bool _listening = false;
  /// Kendi kapattığımız CallKit aramaları: "bitti" olayı aramayı reddetmesin.
  static final Set<int> _selfEnded = {};
  /// Uygulama açıkken uygulama içi gelen arama ekranı gösterilen aramalar (CallKit ayrıca çalmasın).
  static final Set<int> _inApp = {};

  static String uuidFor(int callId) {
    final hex = callId.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-a000-$hex';
  }

  static int _idFromExtra(CallKitParams params) {
    final extra = params.extra ?? const <String, dynamic>{};
    return int.tryParse('${extra['call_id'] ?? ''}') ?? _idFromUuid(params.id);
  }

  static int _idFromUuid(String id) {
    final hex = id.split('-').last;
    return int.tryParse(hex, radix: 16) ?? 0;
  }

  static void listen() {
    if (_listening) return;
    _listening = true;
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      switch (event) {
        case CallEventActionDidUpdateDevicePushTokenVoip():
          unawaited(PushService.registerVoip());
        case CallEventActionCallIncoming(:final callKitParams):
          // uygulama önündeyken aynı arama zaten ekranda: CallKit penceresini sessizce kapat
          final callId = _idFromExtra(callKitParams);
          if (_inApp.contains(callId)) unawaited(end(callId));
        case CallEventActionCallAccept(:final callKitParams):
          final callId = _idFromExtra(callKitParams);
          if (callId > 0) PushService.requestOpenCall(callId, accepted: true);
        case CallEventActionCallDecline(:final callKitParams):
          final callId = _idFromExtra(callKitParams);
          if (callId > 0) unawaited(PushService.declineIncoming(callId));
        case CallEventActionCallEnded(:final callKitParams):
          final callId = _idFromExtra(callKitParams);
          if (_selfEnded.remove(callId)) break;
          if (callId > 0) unawaited(PushService.declineIncoming(callId));
        case CallEventActionCallTimeout(:final id):
          final callId = _idFromUuid(id);
          if (callId > 0) unawaited(PushService.declineIncoming(callId));
        default:
          break;
      }
    });
  }

  static Future<void> showIncoming({
    required int callId,
    required int channelId,
    required String callerName,
    required bool video,
    String avatarUrl = '',
  }) async {
    listen();
    final name = callerName.trim().isEmpty ? 'ARCONNECT' : callerName.trim();
    await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: uuidFor(callId),
      nameCaller: name,
      appName: 'ARCONNECT',
      avatar: avatarUrl.isEmpty ? null : avatarUrl,
      handle: video ? 'Görüntülü arama' : 'Sesli arama',
      type: video ? 1 : 0,
      duration: 45000,
      extra: <String, dynamic>{'call_id': '$callId', 'channel_id': '$channelId'},
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Cevapsız arama',
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0B141A',
        actionColor: '#22C55E',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Aramalar',
        missedCallNotificationChannelName: 'Cevapsız arama',
        isShowFullLockedScreen: true,
        isFullScreen: true,
        isImportant: true,
        textAccept: 'Kabul',
        textDecline: 'Reddet',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        ringtonePath: 'system_ringtone_default',
      ),
    ));
  }

  /// Uygulama içi gelen arama ekranı açık: VoIP ile gelen CallKit penceresi ayrıca çalmasın.
  static void showingInApp(int callId, bool on) => on ? _inApp.add(callId) : _inApp.remove(callId);

  /// Kilit ekranında kabul edilmiş (uygulama sonra açılmış) arama varsa id'si.
  static Future<int?> acceptedCall() async {
    try {
      for (final c in await FlutterCallkitIncoming.activeCalls()) {
        if (c.isAccepted) {
          final id = _idFromExtra(c);
          if (id > 0) return id;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Görüşme bağlandı: kilit ekranındaki CallKit "bağlanıyor"dan süreye geçer.
  static Future<void> connected(int callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(uuidFor(callId));
    } catch (_) {}
  }

  static Future<void> end(int callId) async {
    _selfEnded.add(callId);
    try {
      await FlutterCallkitIncoming.endCall(uuidFor(callId));
    } catch (_) {}
  }

  static Future<void> requestAndroidLockScreen() async {
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Bildirim izni',
        'rationaleMessagePermission': 'Gelen aramalar ve mesajlar için bildirim gerekir.',
        'postNotificationMessageRequired': 'Ayarlardan bildirim iznini aç.',
      });
      final can = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (can != true) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (_) {}
  }
}
