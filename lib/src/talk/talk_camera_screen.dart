import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import 'talk_media_composer.dart';
import 'talk_theme.dart';

enum _CamMode { video, photo, note }

class TalkCameraResult {
  const TalkCameraResult.items(this.items) : openGallery = false;
  const TalkCameraResult.gallery() : items = const [], openGallery = true;
  final List<TalkMediaItem> items;
  final bool openGallery;
}

Future<TalkCameraResult?> openTalkCamera(BuildContext context) {
  return Navigator.of(context).push<TalkCameraResult>(
    PageRouteBuilder(opaque: true, transitionDuration: const Duration(milliseconds: 220), pageBuilder: (_, _, _) => const TalkCameraScreen()),
  );
}

class TalkCameraScreen extends StatefulWidget {
  const TalkCameraScreen({super.key});

  @override
  State<TalkCameraScreen> createState() => _TalkCameraScreenState();
}

class _TalkCameraScreenState extends State<TalkCameraScreen> with WidgetsBindingObserver {
  CameraController? _ctl;
  List<CameraDescription> _cams = const [];
  int _camI = 0;
  _CamMode _mode = _CamMode.photo;
  bool _flash = false;
  bool _busy = false;
  bool _recording = false;
  DateTime? _recAt;
  Timer? _tick;
  double _zoom = 1;
  double _minZ = 1;
  double _maxZ = 1;
  int _filter = 0;
  String? _err;
  List<AssetEntity> _strip = const [];

  static const _filters = <ColorFilter?>[
    null,
    ColorFilter.mode(Color(0x44FF9800), BlendMode.softLight),
    ColorFilter.mode(Color(0x332196F3), BlendMode.overlay),
    ColorFilter.mode(Color(0x33E91E63), BlendMode.softLight),
    ColorFilter.matrix(<double>[0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 1, 0]),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _ctl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctl;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
      _ctl = null;
    } else if (state == AppLifecycleState.resumed) {
      _openCam(_camI);
    }
  }

  Future<void> _boot() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      if (mounted) setState(() => _err = 'Kamera izni gerekli');
      return;
    }
    await Permission.microphone.request();
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        if (mounted) setState(() => _err = 'Kamera bulunamadı');
        return;
      }
      final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      await _openCam(back >= 0 ? back : 0);
    } on Exception catch (e) {
      if (mounted) setState(() => _err = 'Kamera açılamadı: $e');
    }
    _loadStrip();
  }

  Future<void> _openCam(int i) async {
    await _ctl?.dispose();
    _ctl = null;
    if (!mounted) return;
    final next = CameraController(_cams[i], ResolutionPreset.high, enableAudio: true, imageFormatGroup: ImageFormatGroup.jpeg);
    _ctl = next;
    _camI = i;
    try {
      await next.initialize();
      _minZ = await next.getMinZoomLevel();
      _maxZ = await next.getMaxZoomLevel();
      _zoom = 1;
      await next.setFlashMode(FlashMode.off);
      _flash = false;
      if (mounted) setState(() => _err = null);
    } on Exception catch (e) {
      if (mounted) setState(() => _err = 'Kamera açılamadı: $e');
    }
  }

  Future<void> _loadStrip() async {
    try {
      final p = await PhotoManager.requestPermissionExtend();
      if (!p.isAuth && !p.hasAccess) return;
      final albums = await PhotoManager.getAssetPathList(type: RequestType.common, onlyAll: true);
      if (albums.isEmpty) return;
      final list = await albums.first.getAssetListPaged(page: 0, size: 24);
      if (mounted) setState(() => _strip = list);
    } on Exception {
      // galeri şeridi olmasa da kamera çalışır
    }
  }

  Future<void> _toggleFlash() async {
    final c = _ctl;
    if (c == null || !c.value.isInitialized) return;
    try {
      if (_flash) {
        await c.setFlashMode(FlashMode.off);
        setState(() => _flash = false);
      } else {
        try {
          await c.setFlashMode(FlashMode.torch);
        } on Exception {
          await c.setFlashMode(FlashMode.always);
        }
        setState(() => _flash = true);
      }
    } on Exception {
      // cihaz flaşı desteklemiyorsa sessiz
    }
  }

  Future<void> _flip() async {
    if (_cams.length < 2 || _recording) return;
    HapticFeedback.selectionClick();
    await _openCam((_camI + 1) % _cams.length);
  }

  Future<void> _setZoom(double z) async {
    final c = _ctl;
    if (c == null || !c.value.isInitialized) return;
    final v = z.clamp(_minZ, _maxZ);
    await c.setZoomLevel(v);
    setState(() => _zoom = v);
  }

  void _cycleZoom() {
    final next = _zoom < 1.5 ? math.min(2.0, _maxZ) : _minZ;
    _setZoom(next);
  }

  Future<void> _done(TalkCameraResult r) async {
    if (!mounted) return;
    Navigator.of(context).pop(r);
  }

  Future<TalkMediaItem> _item(String path, {required bool video}) async {
    final f = File(path);
    final size = await f.length();
    final name = video ? (_mode == _CamMode.note ? 'goruntulu-not.mp4' : 'video.mp4') : 'foto.jpg';
    return TalkMediaItem(path: path, name: name, size: size);
  }

  Future<void> _shutter() async {
    final c = _ctl;
    if (c == null || !c.value.isInitialized || _busy) return;
    if (_mode == _CamMode.photo) {
      setState(() => _busy = true);
      HapticFeedback.mediumImpact();
      try {
        if (_flash) {
          try {
            await c.setFlashMode(FlashMode.always);
          } on Exception {
            // torch zaten açık
          }
        }
        final x = await c.takePicture();
        await _done(TalkCameraResult.items([await _item(x.path, video: false)]));
      } on Exception {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    if (_recording) {
      setState(() => _busy = true);
      _tick?.cancel();
      try {
        final x = await c.stopVideoRecording();
        _recording = false;
        await _done(TalkCameraResult.items([await _item(x.path, video: true)]));
      } on Exception {
        if (mounted) {
          setState(() {
            _recording = false;
            _busy = false;
          });
        }
      }
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      await c.startVideoRecording();
      _recAt = DateTime.now();
      _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _recording = true);
    } on Exception {
      // kayıt başlamadı
    }
  }

  Future<void> _pickStrip(AssetEntity a) async {
    if (_recording || _busy) return;
    File? f;
    if (a.type == AssetType.image) {
      final bytes = await a.thumbnailDataWithSize(const ThumbnailSize(1600, 1600), quality: 78);
      if (bytes != null && bytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        f = File('${dir.path}/cam-${a.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}-${DateTime.now().millisecondsSinceEpoch}.jpg');
        await f.writeAsBytes(bytes, flush: true);
      }
    }
    f ??= await a.file;
    if (f == null || !mounted) return;
    final video = a.type == AssetType.video;
    await _done(TalkCameraResult.items([TalkMediaItem(path: f.path, name: video ? 'video.mp4' : 'foto.jpg', size: await f.length())]));
  }

  String get _clock {
    if (!_recording || _recAt == null) return '';
    final s = DateTime.now().difference(_recAt!).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctl;
    final ready = c != null && c.value.isInitialized;
    final pad = MediaQuery.paddingOf(context);
    final filter = _filters[_filter % _filters.length];
    Widget preview = const ColoredBox(color: Colors.black);
    if (ready) {
      final size = c.value.previewSize!;
      preview = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: size.height, height: size.width, child: CameraPreview(c)),
        ),
      );
      if (filter != null) {
        preview = ColorFiltered(colorFilter: filter, child: preview);
      }
    }
    if (_mode == _CamMode.note && ready) {
      preview = Stack(
        fit: StackFit.expand,
        children: [
          preview,
          IgnorePointer(child: CustomPaint(painter: _HolePainter())),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          preview,
          if (_err != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_err!, textAlign: TextAlign.center, style: talkText(16, FontWeight.w600, Colors.white)),
              ),
            ),
          Positioned(
            top: pad.top + 6,
            left: 8,
            right: 8,
            child: Row(
              children: [
                _round(CupertinoIcons.xmark, () => Navigator.pop(context)),
                const Spacer(),
                if (_recording)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xFFE11D48), borderRadius: BorderRadius.circular(8)),
                    child: Text(_clock, style: talkText(14, FontWeight.w700, Colors.white)),
                  )
                else ...[
                  _round(CupertinoIcons.circle_lefthalf_fill, () => setState(() => _filter = (_filter + 1) % _filters.length)),
                  const SizedBox(width: 8),
                  _round(
                    _flash ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt_slash_fill,
                    _toggleFlash,
                    bg: _flash ? const Color(0xFFF5C518) : const Color(0x66000000),
                    fg: _flash ? Colors.black : Colors.white,
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(bottom: math.max(pad.bottom, 10)),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC000000), Color(0xF2000000)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_strip.isNotEmpty && !_recording) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(height: 8),
                    // WhatsApp iOS: kenardan kenara büyük kare kutucuklar, aralarında ince boşluk
                    LayoutBuilder(
                      builder: (context, box) {
                        final side = ((box.maxWidth - 3 * 4) / 4.4).clamp(72.0, 120.0);
                        return SizedBox(
                          height: side,
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            scrollDirection: Axis.horizontal,
                            itemCount: _strip.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 3),
                            itemBuilder: (_, i) => _StripThumb(asset: _strip[i], side: side, onTap: () => _pickStrip(_strip[i])),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _galleryBtn(),
                        _iconBtn(CupertinoIcons.sparkles, () => setState(() => _filter = (_filter + 1) % _filters.length)),
                        _shutterBtn(),
                        _zoomBtn(),
                        _iconBtn(CupertinoIcons.camera_rotate_fill, _flip),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _tab('VİDEO', _CamMode.video),
                      const SizedBox(width: 22),
                      _tab('FOTOĞRAF', _CamMode.photo),
                      const SizedBox(width: 22),
                      _tab('GÖRÜNTÜLÜ NOT', _CamMode.note),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String t, _CamMode m) {
    final on = _mode == m && !_recording;
    return GestureDetector(
      onTap: _recording
          ? null
          : () {
              HapticFeedback.selectionClick();
              setState(() => _mode = m);
            },
      child: Text(t, style: talkText(13, FontWeight.w800, on ? Colors.white : const Color(0x99FFFFFF), letterSpacing: 0.4)),
    );
  }

  Widget _round(IconData i, VoidCallback onTap, {Color bg = const Color(0x66000000), Color fg = Colors.white}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(i, size: 20, color: fg),
    ),
  );

  Widget _iconBtn(IconData i, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: SizedBox(width: 44, height: 44, child: Icon(i, size: 26, color: Colors.white)),
  );

  Widget _zoomBtn() {
    final label = _zoom >= 1.8 ? '2×' : '1×';
    return GestureDetector(
      onTap: _cycleZoom,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x66FFFFFF)),
        ),
        child: Text(label, style: talkText(13, FontWeight.w800, Colors.white)),
      ),
    );
  }

  Widget _galleryBtn() {
    // küçük resim gelene kadar simge görünür (simge ayrı tutulur; aksi halde FutureBuilder kendini döndürüp çöker)
    const icon = Icon(CupertinoIcons.photo_on_rectangle, color: Colors.white, size: 22);
    Widget inner = icon;
    if (_strip.isNotEmpty) {
      inner = FutureBuilder<Uint8List?>(
        future: _strip.first.thumbnailDataWithSize(const ThumbnailSize.square(120)),
        builder: (_, s) => s.data == null ? icon : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    return GestureDetector(
      onTap: () => _done(const TalkCameraResult.gallery()),
      child: Container(
        width: 44,
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: inner,
      ),
    );
  }

  Widget _shutterBtn() {
    final rec = _recording;
    final video = _mode != _CamMode.photo;
    return GestureDetector(
      onTap: _shutter,
      child: Container(
        width: 76,
        height: 76,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: rec ? 28 : (video ? 58 : 62),
          height: rec ? 28 : (video ? 58 : 62),
          decoration: BoxDecoration(color: rec || video ? const Color(0xFFE11D48) : Colors.white, borderRadius: BorderRadius.circular(rec ? 6 : 99)),
        ),
      ),
    );
  }
}

class _StripThumb extends StatelessWidget {
  const _StripThumb({required this.asset, required this.side, required this.onTap});
  final AssetEntity asset;
  final double side;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sec = asset.duration;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(const ThumbnailSize.square(300)),
              builder: (_, s) => s.data == null ? const ColoredBox(color: Color(0xFF222222)) : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
            if (sec > 0)
              Positioned(
                left: 4,
                bottom: 4,
                child: Text(
                  '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}',
                  style: talkText(11, FontWeight.w700, Colors.white).copyWith(shadows: const [Shadow(color: Colors.black, blurRadius: 4)]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HolePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) * 0.38;
    final hole = Path()..addOval(Rect.fromCircle(center: Offset(size.width / 2, size.height * 0.42), radius: r));
    final full = Path()..addRect(Offset.zero & size);
    canvas.drawPath(Path.combine(PathOperation.difference, full, hole), Paint()..color = const Color(0x99000000));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
