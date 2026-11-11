import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/api_client.dart';
import '../push/incoming_callkit.dart';
import '../push/push_service.dart';
import 'agora_service.dart';
import 'talk_api.dart';
import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

enum _Phase { outgoing, incoming, active }

/// Sohbetten sesli / görüntülü arama (Veylo DirectCall + Agora).
class TalkCallScreen extends StatefulWidget {
  const TalkCallScreen._({
    required this.api,
    required this.outgoing,
    required this.video,
    required this.title,
    required this.peerName,
    required this.photoUrl,
    this.channelId,
    this.initial,
  });

  final TalkApi api;
  final bool outgoing;
  final bool video;
  final String title;
  final String peerName;
  final String photoUrl;
  final int? channelId;
  final TalkCall? initial;

  static Future<void> start(
    BuildContext context, {
    required TalkApi api,
    required int channelId,
    required bool video,
    required String title,
    required String peerName,
    required String photoUrl,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TalkCallScreen._(
          api: api,
          outgoing: true,
          video: video,
          title: title,
          peerName: peerName,
          photoUrl: photoUrl,
          channelId: channelId,
        ),
      ),
    );
  }

  static Future<void> incoming(BuildContext context, {required TalkApi api, required TalkCall call, required String photoUrl}) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TalkCallScreen._(
          api: api,
          outgoing: false,
          video: call.video,
          title: call.title,
          peerName: call.callerName,
          photoUrl: photoUrl,
          initial: call,
        ),
      ),
    );
  }

  static Future<void> joinLive(BuildContext context, {required TalkApi api, required TalkCall call, required String photoUrl}) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => TalkCallScreen._(
          api: api,
          outgoing: true,
          video: call.video,
          title: call.title,
          peerName: call.callerName,
          photoUrl: photoUrl,
          initial: call,
        ),
      ),
    );
  }

  @override
  State<TalkCallScreen> createState() => _TalkCallScreenState();
}

class _TalkCallScreenState extends State<TalkCallScreen> {
  final _agora = AgoraService.instance;
  late _Phase _phase = widget.outgoing ? _Phase.outgoing : _Phase.incoming;
  TalkCall? _call;
  bool _busy = false;
  bool _closed = false;
  bool _micOn = true;
  bool _speakerOn = false;
  bool _camOn = false;
  DateTime? _startedAt;
  Timer? _clock;
  Timer? _ringTimeout;
  bool _hadRemote = false;
  bool _seenOnServer = false;
  int _seconds = 0;
  late String _peerName = widget.peerName;
  late String _photoUrl = widget.photoUrl;

  @override
  void initState() {
    super.initState();
    _call = widget.initial;
    _camOn = widget.video;
    if (_call != null) _syncPeer(_call!);
    WakelockPlus.enable();
    _agora.remoteUids.addListener(_onRemote);
    _agora.serverCalls.addListener(_onServerCalls);
    PushService.hangupRequested.addListener(_onCallkitHangup);
    if (widget.outgoing) {
      unawaited(_begin());
    }
  }

  void _syncPeer(TalkCall call) {
    if (widget.outgoing) {
      final others = [for (final m in call.members) if (m.userId != call.createdBy) m];
      if (others.length == 1) {
        if (others.first.displayName.isNotEmpty) _peerName = others.first.displayName;
        if (others.first.avatarPath.isNotEmpty) _photoUrl = widget.api.fileUrl(others.first.avatarPath);
      }
    } else {
      final caller = call.caller;
      if (call.callerName.isNotEmpty) _peerName = call.callerName;
      if (caller != null) {
        if (caller.displayName.isNotEmpty) _peerName = caller.displayName;
        if (caller.avatarPath.isNotEmpty) _photoUrl = widget.api.fileUrl(caller.avatarPath);
      }
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _ringTimeout?.cancel();
    _agora.remoteUids.removeListener(_onRemote);
    _agora.serverCalls.removeListener(_onServerCalls);
    PushService.hangupRequested.removeListener(_onCallkitHangup);
    WakelockPlus.disable();
    unawaited(_agora.leave());
    final id = _call?.id;
    if (id != null) unawaited(ArconCallkit.end(id));
    if (id != null && !_closed) {
      unawaited(_quiet(widget.api.callHangup(id)));
    }
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() => _busy = true);
    try {
      TalkCall call;
      if (_call != null) {
        call = await widget.api.callJoin(_call!.id);
      } else {
        call = await widget.api.callStart(channelId: widget.channelId ?? 0, video: widget.video, title: widget.title);
      }
      final rtc = call.rtc;
      if (rtc == null) {
        if (mounted) talkToast(context, 'Agora kanalı alınamadı', error: true);
        _pop();
        return;
      }
      final ok = await _agora.join(rtc, micOn: true, video: widget.video);
      if (!ok) {
        if (mounted) talkToast(context, 'Arama bağlanamadı (${_agora.lastError})', error: true);
        await widget.api.callHangup(call.id);
        _pop();
        return;
      }
      if (!mounted) return;
      setState(() {
        _call = call;
        _busy = false;
        _camOn = widget.video;
        _syncPeer(call);
      });
      if (_agora.remoteUids.value.isEmpty) unawaited(_agora.startRingback());
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (!mounted || _startedAt != null || _closed) return;
        talkToast(context, 'Cevap yok');
        _hangup();
      });
      _onRemote();
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message, error: true);
      _pop();
    }
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final call = await widget.api.callJoin(_call!.id);
      final rtc = call.rtc;
      if (rtc == null) {
        if (mounted) talkToast(context, 'Agora kanalı alınamadı', error: true);
        _pop();
        return;
      }
      final ok = await _agora.join(rtc, micOn: true, video: call.video);
      if (!ok) {
        if (mounted) talkToast(context, 'Arama bağlanamadı (${_agora.lastError})', error: true);
        _pop();
        return;
      }
      if (!mounted) return;
      setState(() {
        _call = call;
        _busy = false;
        _phase = _Phase.outgoing;
        _camOn = call.video;
        _syncPeer(call);
      });
      _onRemote();
    } on ArconApiException catch (e) {
      if (mounted) talkToast(context, e.message, error: true);
      _pop();
    }
  }

  /// Karşı taraf kanala girince sayaç başlar; birebir aramada çıkınca arama biter.
  void _onRemote() {
    if (!mounted || _closed || _agora.channel == null) return;
    final n = _agora.remoteUids.value.length;
    if (n > 0) {
      _hadRemote = true;
      if (_startedAt == null) _markActive();
    } else if (_hadRemote && (_call?.members.length ?? 2) <= 2) {
      _hangup();
    }
  }

  /// Karşı taraf reddetti / kapattı: arama sunucuda bitince ekran da kapanır.
  void _onServerCalls() {
    final id = _call?.id;
    if (id == null || _closed || !mounted) return;
    if (_agora.serverCalls.value.contains(id)) {
      _seenOnServer = true;
      return;
    }
    if (!_seenOnServer) return;
    talkToast(context, _startedAt == null && widget.outgoing ? 'Arama reddedildi' : 'Arama bitti');
    _hangup();
  }

  void _onCallkitHangup() {
    final id = PushService.hangupRequested.value;
    if (id == null || id != _call?.id || _closed) return;
    PushService.hangupRequested.value = null;
    _hangup();
  }

  void _markActive() {
    _ringTimeout?.cancel();
    final id = _call?.id;
    if (id != null) unawaited(ArconCallkit.connected(id));
    unawaited(_agora.stopRingback());
    setState(() {
      _phase = _Phase.active;
      _startedAt = DateTime.now();
      _seconds = 0;
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startedAt == null || !mounted) return;
      setState(() => _seconds = DateTime.now().difference(_startedAt!).inSeconds);
    });
  }

  Future<void> _decline() async {
    final id = _call?.id;
    _pop();
    if (id != null) await _quiet(widget.api.callDecline(id));
  }

  Future<void> _hangup() async {
    if (_closed) return;
    final id = _call?.id;
    // WhatsApp gibi ekran hemen kapansın; kanaldan çıkış ve sunucu kaydı arkada sürsün
    _pop();
    _closed = true;
    await _agora.leave();
    if (id != null) await _quiet(widget.api.callHangup(id));
  }

  /// Kapatma/reddetme isteği ağ hatasında sessizce düşsün.
  static Future<void> _quiet(Future<void> f) async {
    try {
      await f;
    } catch (_) {}
  }

  void _pop() {
    if (!mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  String get _clockText {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final name = _peerName.isEmpty ? widget.title : _peerName;
    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: _videoOrAvatar(name)),
          Positioned(left: 0, right: 0, top: 24, child: _top(name)),
          Positioned(left: 0, right: 0, bottom: 28, child: _controls()),
        ]),
      ),
    );
  }

  Widget _videoOrAvatar(String name) {
    final engine = _agora.engine;
    final ch = _agora.channel;
    if (engine != null && ch != null) {
      return AnimatedBuilder(
        animation: Listenable.merge([_agora.remoteUids, _agora.remoteVideo, _agora.remoteMuted, _agora.sawRemoteVideoState]),
        builder: (_, _) {
          final uids = _agora.remoteUids.value.toList();
          final isVideoCall = widget.video || _camOn || (_call?.video ?? false);
          final myCam = _camOn && isVideoCall;
          // WhatsApp gibi: çalarken görüntülüde kendi kameran tam ekran, sesli aramada karşı tarafın fotoğrafı.
          if (uids.isEmpty) {
            return myCam
                ? AgoraVideoView(controller: VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0)))
                : _personStage(name: name, photoUrl: _photoUrl, micOn: true, large: true);
          }
          return Stack(fit: StackFit.expand, children: [
            if (uids.length == 1)
              _remoteStage(engine, ch, uids.first, isVideoCall, large: true)
            else
              _remoteGrid(engine, ch, uids, isVideoCall),
            // Kendi küçük kutun yalnızca kameran açıkken
            if (myCam)
              Positioned(
                right: 16,
                top: 88,
                width: 110,
                height: 148,
                child: _localPip(engine, isVideoCall),
              ),
          ]);
        },
      );
    }
    return _personStage(name: name, photoUrl: _photoUrl, micOn: true, large: true);
  }

  TalkCallMember? _memberFor(int uid) {
    for (final m in _call?.members ?? const <TalkCallMember>[]) {
      if (m.userId == uid) return m;
    }
    return null;
  }

  Widget _remoteGrid(RtcEngine engine, String ch, List<int> uids, bool isVideoCall) {
    final cols = uids.length <= 2 ? 1 : 2;
    return GridView.count(
      crossAxisCount: cols,
      physics: const NeverScrollableScrollPhysics(),
      children: [for (final uid in uids) _remoteStage(engine, ch, uid, isVideoCall, large: false)],
    );
  }

  Widget _remoteStage(RtcEngine engine, String ch, int uid, bool isVideoCall, {required bool large}) {
    final cam = _agora.remoteVideo.value.contains(uid) || (isVideoCall && !_agora.sawRemoteVideoState.value);
    final m = _memberFor(uid);
    final name = (m?.displayName.isNotEmpty ?? false) ? m!.displayName : _peerName;
    final photo = (m != null && m.avatarPath.isNotEmpty) ? widget.api.fileUrl(m.avatarPath) : _photoUrl;
    final micOn = !_agora.remoteMuted.value.contains(uid);
    Widget? video;
    if (cam) {
      video = AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: engine,
          canvas: VideoCanvas(uid: uid),
          connection: RtcConnection(channelId: ch),
        ),
      );
    }
    return _personStage(name: name, photoUrl: photo, micOn: micOn, large: large, video: video);
  }

  Widget _localPip(RtcEngine engine, bool isVideoCall) {
    final me = _memberFor(_agora.localUid);
    final name = me?.displayName.isNotEmpty == true ? me!.displayName : 'Sen';
    final photo = (me != null && me.avatarPath.isNotEmpty) ? widget.api.fileUrl(me.avatarPath) : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: _personStage(
        name: name,
        photoUrl: photo,
        micOn: _micOn,
        large: false,
        video: (_camOn && isVideoCall)
            ? AgoraVideoView(controller: VideoViewController(rtcEngine: engine, canvas: const VideoCanvas(uid: 0)))
            : null,
      ),
    );
  }

  Widget _personStage({
    required String name,
    required String photoUrl,
    required bool micOn,
    required bool large,
    Widget? video,
  }) {
    final avatarSize = large ? 140.0 : 52.0;
    return Stack(fit: StackFit.expand, children: [
      if (video != null)
        video
      else
        ColoredBox(
          color: const Color(0xFF0B141A),
          child: Center(
            child: TalkAvatar.solid(name: name, photoUrl: photoUrl, size: avatarSize, fontSize: large ? 36 : 16, personIfEmpty: true),
          ),
        ),
      if (large && !micOn)
        const Positioned(
          left: 0,
          right: 0,
          top: 150,
          child: Center(child: Icon(Icons.mic_off, color: Color(0xFFE11D48), size: 22)),
        ),
      if (!large) Positioned(
        left: large ? 16 : 6,
        right: large ? 16 : 6,
        bottom: large ? 16 : 6,
        child: Row(children: [
          Container(
            width: large ? 28 : 22,
            height: large ? 28 : 22,
            decoration: BoxDecoration(color: micOn ? const Color(0xCC1F6B4A) : const Color(0xCC9F1239), shape: BoxShape.circle),
            child: Icon(micOn ? Icons.mic : Icons.mic_off, color: Colors.white, size: large ? 16 : 13),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: talkText(large ? 14 : 11, FontWeight.w600, Colors.white).copyWith(shadows: const [Shadow(color: Colors.black54, blurRadius: 6)]),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _top(String name) {
    final sub = switch (_phase) {
      _Phase.incoming => 'arıyor…',
      _Phase.outgoing => _call == null ? 'Aranıyor…' : (widget.outgoing ? 'Çalıyor…' : 'Bağlanıyor…'),
      _Phase.active => _clockText,
    };
    return Column(children: [
      Text(name, textAlign: TextAlign.center, style: talkText(18, FontWeight.w700, Colors.white)),
      const SizedBox(height: 6),
      Text(sub, style: talkText(14, FontWeight.w400, const Color(0xFFB0B8BF))),
    ]);
  }

  Widget _controls() {
    if (_phase == _Phase.incoming) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _round(Icons.call_end, const Color(0xFFE11D48), _decline, 'Reddet', size: 72),
          _round(Icons.call, const Color(0xFF22C55E), _busy ? null : _accept, 'Kabul', size: 72),
        ]),
      );
    }
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _round(_micOn ? Icons.mic : Icons.mic_off, _micOn ? const Color(0xFF3A4A54) : const Color(0xFF1F2C34), () async {
        setState(() => _micOn = !_micOn);
        await _agora.setMic(_micOn);
      }, _micOn ? 'Mikrofon' : 'Kapalı'),
      _round(Icons.volume_up, _speakerOn ? const Color(0xFF3A4A54) : const Color(0xFF1F2C34), () async {
        setState(() => _speakerOn = !_speakerOn);
        await _agora.setSpeaker(_speakerOn);
      }, 'Hoparlör'),
      _round(_camOn ? Icons.videocam : Icons.videocam_off, _camOn ? const Color(0xFF3A4A54) : const Color(0xFF1F2C34), () async {
        final next = !_camOn;
        await _agora.setCamera(next);
        if (mounted) setState(() => _camOn = next);
      }, 'Kamera'),
      _round(Icons.cameraswitch, const Color(0xFF3A4A54), _camOn ? () => _agora.switchCamera() : null, 'Çevir'),
      _round(Icons.call_end, const Color(0xFFE11D48), _hangup, 'Bitir'),
    ]);
  }

  Widget _round(IconData icon, Color color, VoidCallback? onTap, String label, {double size = 58}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Opacity(opacity: onTap == null ? 0.35 : 1, child: Icon(icon, color: Colors.white, size: size * 0.42)),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: talkText(13, FontWeight.w500, const Color(0xFFB0B8BF))),
    ]);
  }
}
