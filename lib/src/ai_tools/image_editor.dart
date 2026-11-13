import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../ui/mono.dart';
import 'tool_common.dart';

/// Görseli yapay zekâyla değiştirme isteği (görüntüleyicideki araçlardan).
class ImageGenOpts {
  ImageGenOpts({
    required this.prompt,
    required this.imageUrl,
    this.file,
    this.fileName = 'edit.png',
    this.composite = false,
    this.size,
    this.aspect,
    this.transparent = false,
    this.cutout = false,
    this.mask,
  });
  final String prompt;
  final String imageUrl;
  final Uint8List? file;
  final String fileName;
  final bool composite;
  final String? size;
  final String? aspect;
  final bool transparent;
  final bool cutout;
  final Uint8List? mask;
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> loadNetImage(String url) async {
  final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  return _decode(res.bodyBytes);
}

Future<Uint8List> _png(ui.Image img) async => (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

/// Görselin ekranda BoxFit.contain ile çizildiği dikdörtgen.
Rect _containRect(Size box, double w, double h) {
  final s = math.min(box.width / w, box.height / h);
  final dw = w * s, dh = h * s;
  return Rect.fromLTWH((box.width - dw) / 2, (box.height - dh) / 2, dw, dh);
}

/* ======================================================================
 * İşaretle / Yorum / Sil — fırça ve pinler (yapay zekâ ile değiştirme)
 * ==================================================================== */

enum MarkTool { select, comment, erase }

class _Stroke {
  _Stroke(this.size);
  final double size; // görsel pikseli
  final List<Offset> points = []; // görsel pikseli
}

class _Pin {
  _Pin(this.at, this.text);
  final Offset at; // görsel pikseli
  String text;
}

/// Fırçayla işaretle (+ not), numaralı yorum ekle ya da kaldırılacak alanı boya.
/// Sonuç: [ImageGenOpts] — webdeki "İşaretle", "Yorum ekle", "Sil" araçlarıyla aynı istek.
class ImageMarkScreen extends StatefulWidget {
  const ImageMarkScreen({super.key, required this.url, required this.tool});
  final String url;
  final MarkTool tool;

  @override
  State<ImageMarkScreen> createState() => _ImageMarkScreenState();
}

class _ImageMarkScreenState extends State<ImageMarkScreen> {
  ui.Image? _img;
  String? _error;
  final List<_Stroke> _strokes = [];
  final List<_Pin> _pins = [];
  double _brush = 36; // ekran pikseli
  final _note = TextEditingController();
  Rect _shown = Rect.zero;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadNetImage(widget.url).then((i) {
      if (mounted) setState(() => _img = i);
    }).catchError((Object _) {
      if (mounted) setState(() => _error = 'Görsel yüklenemedi.');
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  double get _scale => _img == null || _shown.width == 0 ? 1 : _img!.width / _shown.width;
  Offset _toImg(Offset p) => (p - _shown.topLeft) * _scale;

  String get _title => switch (widget.tool) {
        MarkTool.select => 'İşaretle',
        MarkTool.comment => 'Yorum ekle',
        MarkTool.erase => 'Sil',
      };

  String get _hint => switch (widget.tool) {
        MarkTool.select => 'Değişecek yeri çiz, ne yapılacağını aşağıya yaz.',
        MarkTool.comment => 'Görsele dokun, o noktaya ne yapılacağını yaz.',
        MarkTool.erase => 'Kaldırmak istediğin alanın üzerinden fırçayla geç.',
      };

  bool get _canSend => switch (widget.tool) {
        MarkTool.select => _strokes.isNotEmpty || _note.text.trim().isNotEmpty,
        MarkTool.comment => _pins.any((p) => p.text.trim().isNotEmpty),
        MarkTool.erase => _strokes.isNotEmpty,
      };

  Future<void> _addPin(Offset local) async {
    if (!_shown.contains(local)) return;
    final at = _toImg(local);
    final ctl = TextEditingController();
    final c = ArconMono.of(context);
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${_pins.length + 1}. yorum', style: c.text(17, weight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
              style: c.text(15),
              cursorColor: c.ink,
              decoration: c.input('ör. Bu yazıyı kırmızı yap', null),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            const SizedBox(height: 12),
            c.primaryButton('Ekle', busy: false, onPressed: () => Navigator.of(ctx).pop(ctl.text)),
          ],
        ),
      ),
    );
    ctl.dispose();
    if (text != null && text.trim().isNotEmpty && mounted) setState(() => _pins.add(_Pin(at, text.trim())));
  }

  /// Çizimleri görsel boyutunda PNG'ye çevirir.
  Future<Uint8List> _render({required bool mask}) async {
    final img = _img!;
    final rec = ui.PictureRecorder();
    final cv = Canvas(rec);
    final full = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    if (mask) {
      cv.saveLayer(full, Paint());
      cv.drawRect(full, Paint()..color = Colors.white);
    }
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = mask ? Colors.black : const Color(0xFFEF4444)
      ..blendMode = mask ? BlendMode.clear : BlendMode.srcOver;
    for (final s in _strokes) {
      p.strokeWidth = s.size;
      if (s.points.length == 1) {
        cv.drawCircle(s.points.first, s.size / 2, Paint()
          ..color = p.color
          ..blendMode = p.blendMode);
      } else {
        final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
        for (final pt in s.points.skip(1)) {
          path.lineTo(pt.dx, pt.dy);
        }
        cv.drawPath(path, p);
      }
    }
    if (mask) cv.restore();
    if (!mask) {
      final r = math.max(14.0, img.width / 45);
      for (var i = 0; i < _pins.length; i++) {
        final pin = _pins[i];
        cv.drawCircle(pin.at, r, Paint()..color = const Color(0xFF2563EB));
        cv.drawCircle(pin.at, r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r / 6
          ..color = Colors.white);
        final tp = TextPainter(
          text: TextSpan(text: '${i + 1}', style: TextStyle(color: Colors.white, fontSize: r * 1.1, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(cv, pin.at - Offset(tp.width / 2, tp.height / 2));
      }
    }
    final out = await rec.endRecording().toImage(img.width, img.height);
    return _png(out);
  }

  Future<void> _send() async {
    if (!_canSend || _busy) return;
    setState(() => _busy = true);
    try {
      final img = _img!;
      final ImageGenOpts opts;
      switch (widget.tool) {
        case MarkTool.erase:
          opts = ImageGenOpts(
            prompt: 'Fırçayla işaretlediğim bölgeyi kaldır ve çevresiyle uyumlu şekilde doldur. Geri kalan her şey aynı kalsın.',
            imageUrl: widget.url,
            mask: await _render(mask: true),
          );
        case MarkTool.comment:
          final saved = _pins.where((p) => p.text.trim().isNotEmpty).toList();
          final lines = [
            for (var i = 0; i < saved.length; i++)
              '${i + 1}) ${saved[i].text} (soldan %${(saved[i].at.dx / img.width * 100).round()}, üstten %${(saved[i].at.dy / img.height * 100).round()})',
          ];
          opts = ImageGenOpts(
            prompt: 'Görsele numaralı işaretler koydum. Her numaranın olduğu yerde şunu yap:\n${lines.join('\n')}\nBunun dışında hiçbir şeyi değiştirme. Numaralı işaretler sonuçta kalmasın.',
            imageUrl: widget.url,
            file: await _render(mask: false),
            fileName: 'yorumlar.png',
            composite: true,
          );
        case MarkTool.select:
          final note = _note.text.trim();
          opts = ImageGenOpts(
            prompt: note.isNotEmpty ? note : 'Çizdiğim işaretlere, yazılara ve şekillere uyarak görseli düzenle. İşaretlerin kendisi sonuçta kalmasın.',
            imageUrl: widget.url,
            file: await _render(mask: false),
            fileName: 'cizim.png',
            composite: true,
          );
      }
      if (mounted) Navigator.of(context).pop(opts);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        toolToast(context, 'Çizim hazırlanamadı');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final img = _img;
    final drawing = widget.tool != MarkTool.comment;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            onPressed: _strokes.isEmpty && _pins.isEmpty
                ? null
                : () => setState(() {
                      if (drawing && _strokes.isNotEmpty) {
                        _strokes.removeLast();
                      } else if (_pins.isNotEmpty) {
                        _pins.removeLast();
                      }
                    }),
            icon: const Icon(Icons.undo_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: img == null
                ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.white70)) : const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : LayoutBuilder(builder: (ctx, box) {
                    _shown = _containRect(box.biggest, img.width.toDouble(), img.height.toDouble());
                    return GestureDetector(
                      onTapUp: drawing ? null : (d) => _addPin(d.localPosition),
                      onPanStart: !drawing
                          ? null
                          : (d) {
                              if (!_shown.contains(d.localPosition)) return;
                              setState(() => _strokes.add(_Stroke(_brush * _scale)..points.add(_toImg(d.localPosition))));
                            },
                      onPanUpdate: !drawing
                          ? null
                          : (d) {
                              if (_strokes.isEmpty) return;
                              setState(() => _strokes.last.points.add(_toImg(d.localPosition)));
                            },
                      child: CustomPaint(
                        size: box.biggest,
                        painter: _MarkPainter(img: img, shown: _shown, scale: _scale, strokes: _strokes, pins: _pins, erase: widget.tool == MarkTool.erase),
                      ),
                    );
                  }),
          ),
          Container(
            color: c.bg,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + pad.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_hint, style: c.text(12.5, color: c.muted)),
                if (drawing)
                  Row(
                    children: [
                      Icon(Icons.brush_rounded, size: 18, color: c.muted),
                      Expanded(
                        child: Slider(value: _brush, min: 8, max: 96, activeColor: c.ink, inactiveColor: c.line, onChanged: (v) => setState(() => _brush = v)),
                      ),
                    ],
                  ),
                if (widget.tool == MarkTool.select) ...[
                  TextField(
                    controller: _note,
                    onChanged: (_) => setState(() {}),
                    minLines: 1,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
                    style: c.text(15),
                    cursorColor: c.ink,
                    decoration: c.input('Düzenlemeyi açıkla (ör. işaretli şişeyi maviye boya)', null),
                  ),
                  const SizedBox(height: 10),
                ],
                if (widget.tool == MarkTool.comment && _pins.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (var i = 0; i < _pins.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 10, backgroundColor: const Color(0xFF2563EB), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_pins[i].text, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(13.5))),
                          GestureDetector(onTap: () => setState(() => _pins.removeAt(i)), child: Icon(Icons.close_rounded, size: 18, color: c.muted)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
                Opacity(opacity: _canSend ? 1 : 0.4, child: c.primaryButton('Yapay zekâyla uygula', busy: _busy, onPressed: _send)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.img, required this.shown, required this.scale, required this.strokes, required this.pins, required this.erase});
  final ui.Image img;
  final Rect shown;
  final double scale;
  final List<_Stroke> strokes;
  final List<_Pin> pins;
  final bool erase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), shown, Paint()..filterQuality = FilterQuality.medium);
    canvas.save();
    canvas.translate(shown.left, shown.top);
    canvas.scale(1 / scale);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = erase ? Colors.white.withValues(alpha: 0.55) : const Color(0xFFEF4444);
    for (final s in strokes) {
      p.strokeWidth = s.size;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.size / 2, Paint()..color = p.color);
      } else {
        final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
        for (final pt in s.points.skip(1)) {
          path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path, p);
      }
    }
    final r = 14 * scale;
    for (var i = 0; i < pins.length; i++) {
      canvas.drawCircle(pins[i].at, r, Paint()..color = const Color(0xFF2563EB));
      canvas.drawCircle(pins[i].at, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * scale
        ..color = Colors.white);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: TextStyle(color: Colors.white, fontSize: 15 * scale, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pins[i].at - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/* ======================================================================
 * El ile düzenleyici — kırp/oran, ayarlar, yazı & logo, platform boyutları
 * (tamamen cihazda; ek yapay zekâ maliyeti yok)
 * ==================================================================== */

class _Layer {
  _Layer.text({required this.text, required this.fs, required this.y, this.x = 0.5, this.bold = true, this.bg = 'none', this.bgColor = const Color(0xFF0D0D0D), this.shadow = true, this.upper = false, this.color = Colors.white})
      : logo = null,
        w = 0;
  _Layer.logo(this.logo, {this.w = 0.24, this.x = 0.84, this.y = 0.1})
      : text = '',
        fs = 0,
        bold = false,
        bg = 'none',
        bgColor = Colors.transparent,
        shadow = false,
        upper = false,
        color = Colors.white;

  final ui.Image? logo;
  String text;
  double fs; // genişliğe oranla yazı boyu
  double w; // logo genişliği (oran)
  double x, y; // merkez (oran)
  bool bold, shadow, upper;
  String bg; // none | box | band
  Color bgColor;
  Color color;
  String font = 'sans';

  bool get isLogo => logo != null;

  _Layer copy() {
    final l = isLogo
        ? _Layer.logo(logo, w: w, x: x, y: y)
        : _Layer.text(text: text, fs: fs, y: y, x: x, bold: bold, bg: bg, bgColor: bgColor, shadow: shadow, upper: upper, color: color);
    l.font = font;
    return l;
  }
}

class _EdState {
  _EdState();
  double aspect = 0; // 0 = orijinal
  double cx = 0.5, cy = 0.5, zoom = 1;
  double b = 0, c = 0, s = 0;
  bool gray = false;
  List<_Layer> layers = [];

  _EdState copy() => _EdState()
    ..aspect = aspect
    ..cx = cx
    ..cy = cy
    ..zoom = zoom
    ..b = b
    ..c = c
    ..s = s
    ..gray = gray
    ..layers = [for (final l in layers) l.copy()];
}

const _fonts = [('sans', 'Modern', null), ('serif', 'Klasik', 'Georgia'), ('mono', 'Daktilo', 'Courier'), ('display', 'Afiş', 'Impact')];
const _aspects = [(0.0, 'Orijinal'), (1.0, '1:1'), (4 / 5, '4:5'), (9 / 16, '9:16'), (16 / 9, '16:9'), (3 / 2, '3:2'), (4 / 3, '4:3'), (2 / 3, '2:3')];
const _platforms = [
  ('Instagram gönderi', 1080, 1080),
  ('Instagram dikey', 1080, 1350),
  ('Hikâye / Reels', 1080, 1920),
  ('LinkedIn gönderi', 1200, 627),
  ('LinkedIn kapak', 1584, 396),
  ('E-posta başlığı', 600, 200),
  ('Web banner', 1920, 600),
  ('X gönderi', 1600, 900),
];
const _swatches = [Color(0xFFFFFFFF), Color(0xFF0D0D0D), Color(0xFF1F2A44), Color(0xFFE02E2A), Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFF3B82F6)];

/// 5x4 renk matrisi çarpımı (a ∘ b).
List<double> _mul(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var col = 0; col < 5; col++) {
      var v = col == 4 ? a[r * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[r * 5 + k] * b[k * 5 + col];
      }
      out[r * 5 + col] = v;
    }
  }
  return out;
}

@visibleForTesting
List<double>? imageAdjustMatrix(double b, double c, double s, bool gray) {
  if (b == 0 && c == 0 && s == 0 && !gray) return null;
  final id = <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
  var m = id;
  final sat = gray ? 0.0 : 1 + s / 100;
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final sm = <double>[
    lr * (1 - sat) + sat, lg * (1 - sat), lb * (1 - sat), 0, 0,
    lr * (1 - sat), lg * (1 - sat) + sat, lb * (1 - sat), 0, 0,
    lr * (1 - sat), lg * (1 - sat), lb * (1 - sat) + sat, 0, 0,
    0, 0, 0, 1, 0,
  ];
  m = _mul(sm, m);
  final f = (c + 100) / 100;
  final o = 128 * (1 - f) + b * 1.28;
  final cm = <double>[f, 0, 0, 0, o, 0, f, 0, 0, o, 0, 0, f, 0, o, 0, 0, 0, 1, 0];
  return _mul(cm, m);
}

/// Kırpma dikdörtgeni (kaynak pikseli).
Rect _cropRect(_EdState st, double iw, double ih) {
  final r = st.aspect <= 0 ? iw / ih : st.aspect;
  var w = iw, h = iw / r;
  if (h > ih) {
    h = ih;
    w = ih * r;
  }
  w /= st.zoom;
  h /= st.zoom;
  final x = (st.cx * iw - w / 2).clamp(0.0, iw - w);
  final y = (st.cy * ih - h / 2).clamp(0.0, ih - h);
  return Rect.fromLTWH(x, y, w, h);
}

void _paintComposite(Canvas canvas, Size size, ui.Image img, _EdState st, {_Layer? selected}) {
  final src = _cropRect(st, img.width.toDouble(), img.height.toDouble());
  final dst = Offset.zero & size;
  final m = imageAdjustMatrix(st.b, st.c, st.s, st.gray);
  canvas.drawImageRect(img, src, dst, Paint()
    ..filterQuality = FilterQuality.high
    ..colorFilter = m == null ? null : ColorFilter.matrix(m));
  final W = size.width, H = size.height;
  for (final l in st.layers) {
    if (l.isLogo) {
      final lw = l.w * W;
      final lh = lw * l.logo!.height / l.logo!.width;
      final r = Rect.fromCenter(center: Offset(l.x * W, l.y * H), width: lw, height: lh);
      canvas.drawImageRect(l.logo!, Rect.fromLTWH(0, 0, l.logo!.width.toDouble(), l.logo!.height.toDouble()), r, Paint()..filterQuality = FilterQuality.high);
      if (identical(l, selected)) canvas.drawRect(r.inflate(4), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF4078F0));
      continue;
    }
    final family = _fonts.firstWhere((f) => f.$1 == l.font, orElse: () => _fonts.first).$3;
    final style = TextStyle(
      color: l.color,
      fontSize: l.fs * W,
      fontWeight: l.bold ? FontWeight.w800 : FontWeight.w500,
      fontFamily: family,
      height: 1.15,
      shadows: l.shadow ? [Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: l.fs * W * 0.25, offset: Offset(0, l.fs * W * 0.04))] : null,
    );
    final tp = TextPainter(
      text: TextSpan(text: l.upper ? l.text.toUpperCase() : l.text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: W * 0.9);
    final center = Offset(l.x * W, l.y * H);
    final padX = l.fs * W * 0.45, padY = l.fs * W * 0.25;
    Rect box = Rect.fromCenter(center: center, width: tp.width + padX * 2, height: tp.height + padY * 2);
    if (l.bg == 'band') box = Rect.fromLTRB(0, box.top, W, box.bottom);
    if (l.bg != 'none') {
      canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(l.bg == 'band' ? 0 : l.fs * W * 0.25)), Paint()..color = l.bgColor.withValues(alpha: l.bg == 'band' ? 0.78 : 1));
    }
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    if (identical(l, selected)) canvas.drawRect(box.inflate(3), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF4078F0));
  }
}

Rect _layerRect(_Layer l, Size size) {
  final W = size.width, H = size.height;
  if (l.isLogo) {
    final lw = l.w * W;
    return Rect.fromCenter(center: Offset(l.x * W, l.y * H), width: lw, height: lw * l.logo!.height / l.logo!.width);
  }
  final tp = TextPainter(
    text: TextSpan(text: l.upper ? l.text.toUpperCase() : l.text, style: TextStyle(fontSize: l.fs * W, fontWeight: FontWeight.w800, height: 1.15)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: W * 0.9);
  return Rect.fromCenter(center: Offset(l.x * W, l.y * H), width: tp.width + l.fs * W, height: tp.height + l.fs * W * 0.5);
}

/// Kaydedilen görselin bilgisi: sohbete eklenir.
typedef ImageEditSave = Future<void> Function(Uint8List png, String summary);

class ImageManualEditor extends StatefulWidget {
  const ImageManualEditor({super.key, required this.url, required this.logoUrls, required this.onSave});
  final String url;
  final List<(String, String)> logoUrls; // (ad, url)
  final ImageEditSave onSave;

  @override
  State<ImageManualEditor> createState() => _ImageManualEditorState();
}

class _ImageManualEditorState extends State<ImageManualEditor> {
  ui.Image? _img;
  String? _error;
  _EdState _st = _EdState();
  final List<_EdState> _undo = [];
  int _tab = 0;
  _Layer? _sel;
  (String, int, int)? _platform;
  bool _busy = false;
  final _textCtl = TextEditingController();
  // jest başlangıcı
  double _z0 = 1;
  Offset _c0 = Offset.zero;

  @override
  void initState() {
    super.initState();
    loadNetImage(widget.url).then((i) {
      if (mounted) setState(() => _img = i);
    }).catchError((Object _) {
      if (mounted) setState(() => _error = 'Görsel yüklenemedi.');
    });
  }

  @override
  void dispose() {
    _textCtl.dispose();
    super.dispose();
  }

  void _snap() {
    _undo.add(_st.copy());
    if (_undo.length > 40) _undo.removeAt(0);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _st = _undo.removeLast();
      _sel = null;
    });
  }

  bool get _dirty => _undo.isNotEmpty;

  double get _outAspect {
    final img = _img!;
    final r = _cropRect(_st, img.width.toDouble(), img.height.toDouble());
    return r.width / r.height;
  }

  void _select(_Layer? l) {
    setState(() {
      _sel = l;
      if (l != null && !l.isLogo) _textCtl.text = l.text;
    });
  }

  void _addText(String k) {
    _snap();
    final l = switch (k) {
      'title' => _Layer.text(text: 'Başlığını yaz', fs: 0.09, y: 0.14),
      'body' => _Layer.text(text: 'Kısa açıklama metni', fs: 0.045, y: 0.8, bold: false),
      'price' => _Layer.text(text: '₺1.299', fs: 0.075, x: 0.8, y: 0.84, bg: 'box', bgColor: const Color(0xFFE02E2A), shadow: false),
      _ => _Layer.text(text: '%30 indirim · Sadece bu hafta', fs: 0.048, y: 0.9, bg: 'band', shadow: false, upper: true),
    };
    setState(() => _st.layers.add(l));
    _select(l);
  }

  Future<void> _addLogo(String url) async {
    try {
      final img = await loadNetImage(url);
      if (!mounted) return;
      _snap();
      final l = _Layer.logo(img);
      setState(() => _st.layers.add(l));
      _select(l);
    } catch (_) {
      if (mounted) toolToast(context, 'Logo yüklenemedi');
    }
  }

  Future<void> _addOwnLogo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (x == null) return;
    final img = await _decode(await x.readAsBytes());
    if (!mounted) return;
    _snap();
    final l = _Layer.logo(img);
    setState(() => _st.layers.add(l));
    _select(l);
  }

  String _summary() {
    final st = _st;
    final parts = <String>[
      if (st.aspect > 0) 'kırpıldı (${_aspects.firstWhere((a) => a.$1 == st.aspect, orElse: () => (0, '')).$2})' else if (st.zoom > 1.01) 'kırpıldı',
      if (st.b != 0) 'parlaklık ${st.b > 0 ? '+' : ''}${st.b.round()}',
      if (st.c != 0) 'kontrast ${st.c > 0 ? '+' : ''}${st.c.round()}',
      if (st.s != 0 && !st.gray) 'doygunluk ${st.s > 0 ? '+' : ''}${st.s.round()}',
      if (st.gray) 'siyah-beyaz',
      for (final l in st.layers) l.isLogo ? 'logo eklendi' : '"${l.text}" yazısı eklendi',
    ];
    return parts.isEmpty ? 'Görsel düzenlendi' : 'Düzenlendi: ${parts.join(', ')}';
  }

  /// Son hâli istenen boyutta çizer (platform boyutunda kenarlar kırpılır).
  Future<Uint8List> _export({int? w, int? h}) async {
    final img = _img!;
    final crop = _cropRect(_st, img.width.toDouble(), img.height.toDouble());
    var ow = (w ?? crop.width.round()).toDouble(), oh = (h ?? crop.height.round()).toDouble();
    final cap = 4096 / math.max(ow, oh);
    if (cap < 1) {
      ow *= cap;
      oh *= cap;
    }
    var st = _st;
    if (w != null && h != null && ((w / h) - crop.width / crop.height).abs() > 0.01) {
      st = _st.copy()..aspect = w / h;
    }
    final rec = ui.PictureRecorder();
    _paintComposite(Canvas(rec), Size(ow, oh), img, st);
    final out = await rec.endRecording().toImage(ow.round(), oh.round());
    return _png(out);
  }

  Future<void> _save() async {
    if (_busy || !_dirty) return;
    setState(() => _busy = true);
    try {
      await widget.onSave(await _export(), _summary());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toolToast(context, e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Kaydedilemedi');
      }
    }
  }

  Future<void> _sharePlatform() async {
    final p = _platform;
    if (p == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _export(w: p.$2, h: p.$3);
      if (mounted) await toolShareBytes(context, bytes, 'arcon-gorsel-${p.$2}x${p.$3}.png');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Değişiklikler silinsin mi?'),
            content: const Text('Kaydetmeden çıkarsan düzenlemeler kaybolur.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
              TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Çık')),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final img = _img;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        if (await _confirmExit() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          backgroundColor: c.bg,
          foregroundColor: c.ink,
          elevation: 0,
          title: Text('Düzenle', style: c.text(17, weight: FontWeight.w800)),
          actions: [
            IconButton(onPressed: _undo.isEmpty ? null : _undoLast, icon: Icon(Icons.undo_rounded, color: _undo.isEmpty ? c.faint : c.ink)),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton(
                onPressed: _dirty && !_busy ? _save : null,
                style: FilledButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.bg, disabledBackgroundColor: c.line),
                child: _busy && _tab != 3
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.bg))
                    : Text('Sohbete kaydet', style: c.text(13.5, weight: FontWeight.w700, color: _dirty ? c.bg : c.faint)),
              ),
            ),
          ],
        ),
        body: img == null
            ? Center(child: _error != null ? Text(_error!, style: c.text(14, color: c.muted)) : CircularProgressIndicator(color: c.ink, strokeWidth: 2))
            : Column(
                children: [
                  Expanded(
                    child: Container(
                      color: c.dark ? Colors.black : const Color(0xFFEDEDED),
                      padding: const EdgeInsets.all(12),
                      alignment: Alignment.center,
                      child: AspectRatio(
                        aspectRatio: _outAspect,
                        child: LayoutBuilder(builder: (ctx, box) {
                          final size = box.biggest;
                          return GestureDetector(
                            onTapUp: (d) {
                              final hit = _st.layers.reversed.where((l) => _layerRect(l, size).inflate(8).contains(d.localPosition)).firstOrNull;
                              _select(hit);
                            },
                            onScaleStart: (d) {
                              _z0 = _st.zoom;
                              _c0 = Offset(_st.cx, _st.cy);
                              final hit = _st.layers.reversed.where((l) => _layerRect(l, size).inflate(8).contains(d.localFocalPoint)).firstOrNull;
                              if (hit != null && hit != _sel) _select(hit);
                              _snap();
                            },
                            onScaleUpdate: (d) {
                              setState(() {
                                final sel = _sel;
                                if (sel != null && _tab == 2) {
                                  sel.x = (sel.x + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0);
                                  sel.y = (sel.y + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0);
                                  if (d.scale != 1) {
                                    if (sel.isLogo) {
                                      sel.w = (sel.w * (1 + (d.scale - 1) * 0.08)).clamp(0.05, 0.9);
                                    } else {
                                      sel.fs = (sel.fs * (1 + (d.scale - 1) * 0.08)).clamp(0.02, 0.25);
                                    }
                                  }
                                } else if (_tab == 0) {
                                  _st.zoom = (_z0 * d.scale).clamp(1.0, 4.0);
                                  final crop = _cropRect(_st, img.width.toDouble(), img.height.toDouble());
                                  final k = crop.width / size.width;
                                  _st.cx = (_st.cx - d.focalPointDelta.dx * k / img.width).clamp(0.0, 1.0);
                                  _st.cy = (_st.cy - d.focalPointDelta.dy * k / img.height).clamp(0.0, 1.0);
                                }
                              });
                            },
                            onScaleEnd: (_) {
                              // hareket yoksa geri alma noktası gereksiz
                              if (_undo.isNotEmpty && _st.zoom == _z0 && Offset(_st.cx, _st.cy) == _c0 && _sel == null) _undo.removeLast();
                            },
                            child: CustomPaint(size: size, painter: _EdPainter(img, _st, _sel, _tab == 2)),
                          );
                        }),
                      ),
                    ),
                  ),
                  _tabs(c),
                  SizedBox(
                    height: 210 + pad.bottom,
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + pad.bottom),
                      children: switch (_tab) {
                        0 => _cropPane(c),
                        1 => _adjustPane(c),
                        2 => _textPane(c),
                        _ => _sizePane(c),
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _tabs(ArconMono c) => Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line), bottom: BorderSide(color: c.line))),
        child: Row(
          children: [
            for (final (i, label, icon) in [(0, 'Kırp', Icons.crop_rounded), (1, 'Ayarlar', Icons.tune_rounded), (2, 'Yazı & Logo', Icons.text_fields_rounded), (3, 'Boyutlar', Icons.aspect_ratio_rounded)])
              Expanded(
                child: InkWell(
                  onTap: () => setState(() {
                    _tab = i;
                    if (i != 2) _sel = null;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Column(
                      children: [
                        Icon(icon, size: 20, color: _tab == i ? c.ink : c.faint),
                        const SizedBox(height: 2),
                        Text(label, style: c.text(11, weight: FontWeight.w700, color: _tab == i ? c.ink : c.faint)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _chip(ArconMono c, String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(color: on ? c.ink : c.bg, borderRadius: BorderRadius.circular(9), border: Border.all(color: on ? c.ink : c.line)),
          child: Text(label, style: c.text(12.5, weight: FontWeight.w700, color: on ? c.bg : c.ink)),
        ),
      );

  Widget _wrap(List<Widget> ch) => Wrap(spacing: 6, runSpacing: 6, children: ch);

  List<Widget> _cropPane(ArconMono c) => [
        Text('Oran seç; görseli iki parmakla yakınlaştırıp kaydırarak çerçevele.', style: c.text(12, color: c.muted)),
        const SizedBox(height: 10),
        _wrap([
          for (final (r, label) in _aspects)
            _chip(c, label, _st.aspect == r, () {
              _snap();
              setState(() {
                _st.aspect = r;
                _st.zoom = 1;
                _st.cx = _st.cy = 0.5;
              });
            }),
        ]),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              _snap();
              setState(() {
                _st.aspect = 0;
                _st.zoom = 1;
                _st.cx = _st.cy = 0.5;
              });
            },
            child: Text('Kırpmayı sıfırla', style: c.text(13, weight: FontWeight.w700)),
          ),
        ),
      ];

  Widget _slider(ArconMono c, String label, double v, ValueChanged<double> set) => Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: c.text(13, weight: FontWeight.w600))),
          Expanded(
            child: Slider(
              value: v,
              min: -100,
              max: 100,
              activeColor: c.ink,
              inactiveColor: c.line,
              onChangeStart: (_) => _snap(),
              onChanged: (x) => setState(() => set(x)),
            ),
          ),
          SizedBox(width: 36, child: Text('${v > 0 ? '+' : ''}${v.round()}', textAlign: TextAlign.right, style: c.text(12, color: c.muted))),
        ],
      );

  List<Widget> _adjustPane(ArconMono c) => [
        _wrap([
          for (final (label, b, ct, s, g) in [
            ('Doğal', 0.0, 0.0, 0.0, false),
            ('Canlı', 5.0, 15.0, 30.0, false),
            ('Sıcak', 8.0, 5.0, 15.0, false),
            ('Yumuşak', 10.0, -15.0, -10.0, false),
            ('Siyah-beyaz', 0.0, 10.0, 0.0, true),
          ])
            _chip(c, label, _st.b == b && _st.c == ct && _st.s == s && _st.gray == g, () {
              _snap();
              setState(() {
                _st
                  ..b = b
                  ..c = ct
                  ..s = s
                  ..gray = g;
              });
            }),
        ]),
        const SizedBox(height: 6),
        _slider(c, 'Parlaklık', _st.b, (v) => _st.b = v),
        _slider(c, 'Kontrast', _st.c, (v) => _st.c = v),
        _slider(c, 'Doygunluk', _st.s, (v) => _st.s = v),
      ];

  List<Widget> _textPane(ArconMono c) {
    final sel = _sel;
    return [
      _wrap([
        _chip(c, '+ Başlık', false, () => _addText('title')),
        _chip(c, '+ Metin', false, () => _addText('body')),
        _chip(c, '+ Fiyat etiketi', false, () => _addText('price')),
        _chip(c, '+ Kampanya bandı', false, () => _addText('band')),
        for (final (name, url) in widget.logoUrls) _chip(c, '+ $name', false, () => _addLogo(url)),
        _chip(c, '+ Kendi logon', false, _addOwnLogo),
      ]),
      if (sel == null)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text('Bir katmana dokunarak seç; sürükleyerek taşı, iki parmakla büyüt.', style: c.text(12, color: c.muted)))
      else ...[
        const SizedBox(height: 12),
        if (!sel.isLogo) ...[
          TextField(
            controller: _textCtl,
            onTap: _snap,
            onChanged: (v) => setState(() => sel.text = v),
            minLines: 1,
            maxLines: 3,
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            style: c.text(15),
            cursorColor: c.ink,
            decoration: c.input('Yazı', null),
          ),
          const SizedBox(height: 8),
          _wrap([
            for (final (k, n, _) in _fonts) _chip(c, n, sel.font == k, () => setState(() => sel.font = k)),
            _chip(c, 'Kalın', sel.bold, () => setState(() => sel.bold = !sel.bold)),
            _chip(c, 'BÜYÜK HARF', sel.upper, () => setState(() => sel.upper = !sel.upper)),
            _chip(c, 'Gölge', sel.shadow, () => setState(() => sel.shadow = !sel.shadow)),
          ]),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Renk', style: c.text(12.5, weight: FontWeight.w600)),
              const SizedBox(width: 8),
              for (final col in _swatches)
                GestureDetector(
                  onTap: () => setState(() => sel.color = col),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: sel.color == col ? c.ink : c.line, width: sel.color == col ? 2.5 : 1)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _wrap([
            for (final (k, n) in [('none', 'Zeminsiz'), ('box', 'Kutu'), ('band', 'Bant')]) _chip(c, n, sel.bg == k, () => setState(() => sel.bg = k)),
            for (final col in _swatches.skip(1).take(4))
              GestureDetector(
                onTap: () => setState(() {
                  sel.bgColor = col;
                  if (sel.bg == 'none') sel.bg = 'box';
                }),
                child: Container(width: 30, height: 30, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(8), border: Border.all(color: sel.bgColor == col ? c.ink : c.line, width: sel.bgColor == col ? 2.5 : 1))),
              ),
          ]),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              _snap();
              setState(() {
                _st.layers.remove(sel);
                _sel = null;
              });
            },
            icon: Icon(Icons.delete_outline_rounded, color: c.danger),
            label: Text('Katmanı sil', style: c.text(13, weight: FontWeight.w700, color: c.danger)),
          ),
        ),
      ],
    ];
  }

  List<Widget> _sizePane(ArconMono c) => [
        Text('Platform boyutunu seç; görsel o ölçüde kırpılıp paylaşılır.', style: c.text(12, color: c.muted)),
        const SizedBox(height: 10),
        _wrap([
          for (final p in _platforms)
            _chip(c, '${p.$1} · ${p.$2}×${p.$3}', _platform == p, () {
              _snap();
              setState(() {
                _platform = p;
                _st.aspect = p.$2 / p.$3;
                _st.zoom = 1;
              });
            }),
        ]),
        const SizedBox(height: 12),
        Opacity(
          opacity: _platform == null ? 0.4 : 1,
          child: c.primaryButton(_platform == null ? 'Boyut seç' : '${_platform!.$2}×${_platform!.$3} indir / paylaş', busy: _busy && _tab == 3, onPressed: _sharePlatform),
        ),
      ];
}

class _EdPainter extends CustomPainter {
  _EdPainter(this.img, this.st, this.sel, this.showSel);
  final ui.Image img;
  final _EdState st;
  final _Layer? sel;
  final bool showSel;

  @override
  void paint(Canvas canvas, Size size) => _paintComposite(canvas, size, img, st, selected: showSel ? sel : null);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Görüntüleyicideki "Yeniden boyutlandır" seçenekleri (webdeki ile aynı).
const imageResizeChoices = [
  ('Kare', '1:1', '1024x1024'),
  ('Dikey', '3:4', '1024x1536'),
  ('Hikaye', '9:16', '1024x1536'),
  ('Yatay', '4:3', '1536x1024'),
  ('Geniş ekran', '16:9', '1536x1024'),
];
