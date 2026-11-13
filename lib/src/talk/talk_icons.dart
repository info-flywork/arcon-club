import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// ARCONNECT web ikonları — arconnect.php / arcon-talk-demo.js içindeki SVG'lerin birebir aynısı.
abstract final class TalkSvg {
  /// ARCON AI işareti (web favicon.svg'deki "A")
  static const arconA = '<svg viewBox="12 9 40 44"><path fill="currentColor" fill-rule="evenodd" d="M32 12 L48 50 H41.2 L37.6 40.2 H26.4 L22.8 50 H16 Z M28.4 34.6 H35.6 L32 24.8 Z"/></svg>';
  static const archive = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="4" width="18" height="5" rx="1.5"/><path d="M5 9v9.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V9"/><path d="M10 13h4"/></svg>';
  static const sticker = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M20.5 12.5V7.5a4 4 0 0 0-4-4h-9a4 4 0 0 0-4 4v9a4 4 0 0 0 4 4h5z"/><path d="M12.5 20.5c0-4.4 3.6-8 8-8"/></svg>';
  static const chats = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M15.5 5.5c-4.1 0-7.5 2.7-7.5 6s3.4 6 7.5 6c.9 0 1.7-.1 2.5-.4l3 1.4-.6-3c1.3-1.1 2.1-2.5 2.1-4 0-3.3-3.4-6-7-6z"/><path d="M8.2 8.6C5 9.3 2.5 11.6 2.5 14.5c0 1.4.6 2.7 1.7 3.7l-.5 2.6 2.7-1.2c.9.3 1.8.4 2.8.4"/></svg>';
  static const search = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>';
  static const plus = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M12 5v14M5 12h14"/></svg>';
  static const back = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M15 18l-6-6 6-6"/></svg>';
  static const panel = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M14 4v16"/><path d="M17 8h2M17 12h2M17 16h2"/></svg>';
  static const attach = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>';
  static const mention = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="4"/><path d="M16 8v5a3 3 0 0 0 6 0v-1a10 10 0 1 0-3.9 7.9"/></svg>';
  static const emoji = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><path d="M8.5 10h.01M15.5 10h.01"/><path d="M8.2 14.2c1.1 1.3 2.5 2 3.8 2s2.7-.7 3.8-2"/></svg>';
  static const send = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M22 2L11 13"/><path d="M22 2l-7 20-4-9-9-4 20-7z"/></svg>';
  static const trash = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/></svg>';
  static const chevron = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 10l5 5 5-5z"/></svg>';
  static const ticks = '<svg viewBox="0 0 16 11"><path fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" d="M1.5 6.2 4.2 9 9.8 2"/><path fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" d="M6.2 9 7.2 10 14.5 2"/></svg>';
  static const tick = '<svg viewBox="0 0 16 11"><path fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" d="M3.5 6.2 6.2 9 11.8 2"/></svg>';
  static const download = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 3v12"/><path d="M7 10l5 5 5-5"/><path d="M5 21h14"/></svg>';
  static const reply = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 14H4V4h11v5"/><path d="M15 19l5-5-5-5"/><path d="M20 14H9"/></svg>';
  static const edit = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>';
  static const close = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M6 6l12 12M18 6L6 18"/></svg>';
  static const check = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4"><path d="M5 12l5 5L20 7"/></svg>';
  static const group = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>';
  static const camera = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h3l2-3h8l2 3h3a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/></svg>';
  static const userAdd = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M19 8v6M22 11h-6"/></svg>';
  static const members = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>';
  static const clock = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>';
  static const pendingClock = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>';
  static const media = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="M21 15l-5-5L5 21"/></svg>';
  static const decisions = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>';
  static const tasks = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M9 3v18"/></svg>';
  static const shield = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="M9 12l2 2 4-4"/></svg>';
  static const user = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>';
  static const x = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 6L6 18M6 6l12 12"/></svg>';
  static const msg = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>';
  static const sun = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v1.6M12 19.6v1.6M4.6 4.6l1.1 1.1M18.3 18.3l1.1 1.1M2.8 12h1.6M19.6 12h1.6M4.6 19.4l1.1-1.1M18.3 5.7l1.1-1.1"/></svg>';
  static const moon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M21 14.5A8.5 8.5 0 1110.5 3a7 7 0 0010.5 11.5z"/></svg>';
}

class TalkIcon extends StatelessWidget {
  const TalkIcon(this.svg, {super.key, this.size = 20, this.width, this.height, required this.color});

  final String svg;
  final double size;
  final double? width;
  final double? height;
  final Color color;

  String get _hex => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final a = (color.a * 255).round();
    final svgColored = svg.replaceAll('currentColor', _hex);
    final pic = SvgPicture.string(svgColored, width: width ?? size, height: height ?? size);
    return a >= 255 ? pic : Opacity(opacity: a / 255, child: pic);
  }
}

/// Gizli sohbet ikonu: konuşma balonu + kilit + yıldız (verilen tasarıma göre).
class TalkPrivateChatIcon extends StatelessWidget {
  const TalkPrivateChatIcon({super.key, this.size = 24, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PrivateChatIconPainter(color: color)),
      );
}

class _PrivateChatIconPainter extends CustomPainter {
  _PrivateChatIconPainter({required this.color});
  final Color color;

  static Path _sparkle(Offset c, double r) {
    final k = r * 0.22;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;

    // Sol: yuvarlak balon + kuyruk
    final bubbleR = Rect.fromCenter(center: Offset(s * 0.36, s * 0.40), width: s * 0.56, height: s * 0.50);
    canvas.drawOval(bubbleR, stroke);
    final tail = Path()
      ..moveTo(s * 0.20, s * 0.58)
      ..lineTo(s * 0.10, s * 0.78)
      ..lineTo(s * 0.32, s * 0.62);
    canvas.drawPath(tail, stroke);

    // Sağ: kilit
    final cx = s * 0.68;
    final bodyTop = s * 0.50;
    final shackle = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, bodyTop), width: s * 0.26, height: s * 0.26),
      math.pi,
      math.pi,
      false,
      shackle,
    );
    canvas.drawLine(Offset(cx - s * 0.13, bodyTop), Offset(cx - s * 0.13, s * 0.56), shackle);
    canvas.drawLine(Offset(cx + s * 0.13, bodyTop), Offset(cx + s * 0.13, s * 0.56), shackle);

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - s * 0.22, s * 0.54, s * 0.44, s * 0.36),
      Radius.circular(s * 0.07),
    );
    final star = _sparkle(Offset(cx, s * 0.72), s * 0.095);
    final bodyPath = Path()
      ..addRRect(body)
      ..addPath(star, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(bodyPath, fill);
  }

  @override
  bool shouldRepaint(_PrivateChatIconPainter old) => old.color != color;
}
