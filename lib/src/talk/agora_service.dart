import 'dart:io';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'talk_models.dart';

/// Veylo'daki AgoraService'in ARCONNECT kopyası: tek motor, tek kanal.
class AgoraService {
  AgoraService._();
  static final AgoraService instance = AgoraService._();

  RtcEngine? _engine;
  String? _appId;
  String? _channel;

  final ValueNotifier<Set<int>> remoteUids = ValueNotifier(const {});
  final ValueNotifier<Set<int>> remoteVideo = ValueNotifier(const {});
  final ValueNotifier<Set<int>> remoteMuted = ValueNotifier(const {});
  final ValueNotifier<bool> sawRemoteVideoState = ValueNotifier(false);
  /// Sunucuda hâlâ süren (çalan/canlı) arama id'leri; canlı akıştan güncellenir.
  final ValueNotifier<Set<int>> serverCalls = ValueNotifier(const {});
  int localUid = 0;
  /// Son kanala girme hatası (ekranda kodla göstermek için).
  String lastError = '';
  RtcEngine? get engine => _engine;
  String? get channel => _channel;
  bool get inChannel => _channel != null;

  Future<bool> requestMic() async {
    if (Platform.isIOS) return AudioRecorder().hasPermission();
    final s = await Permission.microphone.request();
    return s.isGranted || s.isLimited;
  }

  Future<bool> requestCamera() async {
    final s = await Permission.camera.request();
    return s.isGranted || s.isLimited;
  }

  Future<bool> _ensureEngine(String appId) async {
    if (_engine != null && _appId == appId) return true;
    await _disposeEngine();
    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(appId: appId, channelProfile: ChannelProfileType.channelProfileCommunication));
    engine.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (_, uid, _) => remoteUids.value = {...remoteUids.value, uid},
      onUserOffline: (_, uid, _) {
        remoteUids.value = {...remoteUids.value}..remove(uid);
        remoteVideo.value = {...remoteVideo.value}..remove(uid);
        remoteMuted.value = {...remoteMuted.value}..remove(uid);
      },
      onUserMuteAudio: (_, uid, muted) {
        final next = {...remoteMuted.value};
        muted ? next.add(uid) : next.remove(uid);
        remoteMuted.value = next;
      },
      onRemoteVideoStateChanged: (_, uid, state, _, _) {
        sawRemoteVideoState.value = true;
        final on = state == RemoteVideoState.remoteVideoStateDecoding || state == RemoteVideoState.remoteVideoStateStarting;
        final next = {...remoteVideo.value};
        on ? next.add(uid) : next.remove(uid);
        remoteVideo.value = next;
      },
      onError: (err, msg) => debugPrint('Agora hata: $err $msg'),
    ));
    await engine.enableAudio();
    _engine = engine;
    _appId = appId;
    return true;
  }

  Future<bool> join(TalkRtc rtc, {required bool micOn, required bool video}) async {
    if (micOn && !await requestMic()) micOn = false;
    try {
      await _ensureEngine(rtc.appId);
      if (_channel == rtc.channel) {
        localUid = rtc.uid;
        await _engine?.muteLocalAudioStream(!micOn);
        return true;
      }
      if (_channel != null) await leave();
      localUid = rtc.uid;
      final engine = _engine!;
      lastError = '';
      // Hoparlör ayarı Android'de kanala girmeden hata verebiliyor; aramayı düşürmesin.
      await _soft(() => engine.setDefaultAudioRouteToSpeakerphone(false));
      if (video) {
        final cam = await requestCamera();
        await engine.enableVideo();
        await _soft(() => engine.enableLocalVideo(cam));
        if (cam) await _soft(() => engine.startPreview());
      }
      await engine.joinChannel(
        token: rtc.token,
        channelId: rtc.channel,
        uid: rtc.uid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: video,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
      _channel = rtc.channel;
      await _soft(() => engine.muteLocalAudioStream(!micOn));
      await _soft(() => engine.setEnableSpeakerphone(false));
      return true;
    } catch (e) {
      debugPrint('Agora kanala girilemedi: $e');
      lastError = e is AgoraRtcException ? 'kod ${e.code}' : e.toString();
      return false;
    }
  }

  Future<void> _soft(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('Agora: $e');
    }
  }

  bool _ringback = false;

  /// Arayan taraf karşı açana kadar "dıt dıt" çalma sesi: yalnızca yerelde, aramanın ses yolundan (kulaklık).
  Future<void> startRingback() async {
    final engine = _engine;
    if (engine == null) return;
    _ringback = true;
    await _soft(() async {
      final path = await engine.getAssetAbsolutePath('assets/ringback.wav');
      if (path == null || !_ringback) return;
      await engine.startAudioMixing(filePath: path, loopback: true, cycle: -1);
    });
  }

  Future<void> stopRingback() async {
    if (!_ringback) return;
    _ringback = false;
    await _soft(() async => _engine?.stopAudioMixing());
  }

  Future<void> setMic(bool on) async {
    if (on && !await requestMic()) return;
    await _engine?.muteLocalAudioStream(!on);
  }

  Future<void> setSpeaker(bool on) async {
    if (_channel == null) return;
    await _engine?.setEnableSpeakerphone(on);
  }

  Future<void> setCamera(bool on) async {
    final engine = _engine;
    if (engine == null) return;
    if (on && !await requestCamera()) return;
    if (on) {
      await engine.enableVideo();
      await engine.enableLocalVideo(true);
      await engine.muteLocalVideoStream(false);
      await engine.startPreview();
      await engine.updateChannelMediaOptions(const ChannelMediaOptions(publishCameraTrack: true));
    } else {
      await engine.muteLocalVideoStream(true);
      await engine.enableLocalVideo(false);
      await engine.stopPreview();
      await engine.updateChannelMediaOptions(const ChannelMediaOptions(publishCameraTrack: false));
    }
  }

  Future<void> switchCamera() async => _engine?.switchCamera();

  Future<void> leave() async {
    final engine = _engine;
    _channel = null;
    remoteUids.value = const {};
    remoteVideo.value = const {};
    remoteMuted.value = const {};
    sawRemoteVideoState.value = false;
    if (engine == null) return;
    await stopRingback();
    try {
      await engine.stopPreview();
      await engine.disableVideo();
      await engine.leaveChannel();
    } catch (e) {
      debugPrint('Agora çıkış: $e');
    }
  }

  Future<void> _disposeEngine() async {
    final engine = _engine;
    _engine = null;
    _appId = null;
    if (engine == null) return;
    await engine.leaveChannel();
    await engine.release();
  }
}
