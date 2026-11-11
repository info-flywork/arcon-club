import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ARCON AI işareti: parıltı yıldızlı koyu küre ve çevresinde eğik bir yörünge ("arc").
/// Açık temada siyah küre / beyaz yıldız, koyu temada açık küre / siyah yıldız.
class ArconAiLogo extends StatelessWidget {
  const ArconAiLogo({super.key, this.size = 40, this.dark});

  final double size;

  /// Verilmezse temadan alınır.
  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final d = dark ?? Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OrbPainter(dark: d)),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.dark});
  final bool dark;

  /// Kavisli dört köşeli parıltı yıldızı
  static Path _sparkle(Offset c, double r) {
    final k = r * 0.22; // bel inceliği
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
    final c = size.center(Offset.zero);
    final orbR = s * 0.36;
    final orb = Rect.fromCircle(center: c, radius: orbR);
    final ink = dark ? Colors.white : const Color(0xFF0A0A0A);

    // yörünge: kürenin arkasında kalan yarısı soluk
    final orbit = Rect.fromCenter(center: c, width: s * 0.98, height: s * 0.36);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(-0.42)
      ..translate(-c.dx, -c.dy);
    canvas.drawArc(orbit, math.pi, math.pi, false, orbitPaint..color = ink.withValues(alpha: 0.28));
    canvas.restore();

    // küre: tepeden ışık alan degrade
    canvas.drawCircle(
      c,
      orbR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: dark
              ? const [Color(0xFFFFFFFF), Color(0xFFD1D1D6), Color(0xFF9A9AA0)]
              : const [Color(0xFF5A5A5E), Color(0xFF1C1C1E), Color(0xFF000000)],
          stops: const [0, 0.55, 1],
        ).createShader(orb),
    );

    // parıltılar
    final star = dark ? const Color(0xFF0A0A0A) : Colors.white;
    canvas.drawPath(_sparkle(c + Offset(-s * 0.02, s * 0.02), orbR * 0.62), Paint()..color = star);
    canvas.drawPath(_sparkle(c + Offset(orbR * 0.5, -orbR * 0.5), orbR * 0.2), Paint()..color = star.withValues(alpha: 0.85));

    // yörüngenin önden geçen yarısı
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(-0.42)
      ..translate(-c.dx, -c.dy);
    canvas.drawArc(orbit, 0, math.pi, false, orbitPaint..color = ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.dark != dark;
}
