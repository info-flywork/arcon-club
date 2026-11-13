import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ARCON AI işareti: parıltı yıldızlı koyu küre ve çevresinde eğik bir yörünge ("arc").
/// Açık temada siyah küre / beyaz yıldız, koyu temada açık küre / siyah yıldız.
///
/// [animated] true ise yörünge yavaş döner, parıltılar hafif nabız yapar
/// (karşılama ekranındaki büyük ikon için).
class ArconAiLogo extends StatelessWidget {
  const ArconAiLogo({super.key, this.size = 40, this.dark, this.animated = false});

  final double size;

  /// Verilmezse temadan alınır.
  final bool? dark;

  final bool animated;

  @override
  Widget build(BuildContext context) {
    final d = dark ?? Theme.of(context).brightness == Brightness.dark;
    if (animated) return _ArconAiLogoAnimated(size: size, dark: d);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OrbPainter(dark: d)),
    );
  }
}

class _ArconAiLogoAnimated extends StatefulWidget {
  const _ArconAiLogoAnimated({required this.size, required this.dark});

  final double size;
  final bool dark;

  @override
  State<_ArconAiLogoAnimated> createState() => _ArconAiLogoAnimatedState();
}

class _ArconAiLogoAnimatedState extends State<_ArconAiLogoAnimated> with SingleTickerProviderStateMixin {
  late final AnimationController _tick = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final t = _tick.value;
        final breathe = 1 + math.sin(t * math.pi * 2) * 0.025;
        final sparkle = 0.75 + 0.25 * (0.5 + 0.5 * math.sin(t * math.pi * 2 * 1.5));
        return Transform.scale(
          scale: breathe,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _OrbPainter(
                dark: widget.dark,
                orbitTurn: t,
                sparkle: sparkle,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.dark, this.orbitTurn = 0, this.sparkle = 1});
  final bool dark;

  /// 0→1 tam tur
  final double orbitTurn;

  /// Parıltı opaklık çarpanı (0.75–1)
  final double sparkle;

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
    if (s <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final orbR = s * 0.36;
    final orb = Rect.fromCircle(center: c, radius: orbR);
    final ink = dark ? Colors.white : const Color(0xFF0A0A0A);
    final tilt = -0.42 + orbitTurn * math.pi * 2;

    // yörünge: kürenin arkasında kalan yarısı soluk
    final orbit = Rect.fromCenter(center: c, width: s * 0.98, height: s * 0.36);
    final backPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round
      ..color = ink.withValues(alpha: 0.28);
    final frontPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round
      ..color = ink;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawArc(orbit, math.pi, math.pi, false, backPaint);
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
          stops: const [0.0, 0.55, 1.0],
        ).createShader(orb),
    );

    // parıltılar
    final star = dark ? const Color(0xFF0A0A0A) : Colors.white;
    final a = sparkle.clamp(0.0, 1.0);
    canvas.drawPath(
      _sparkle(c + Offset(-s * 0.02, s * 0.02), orbR * 0.62),
      Paint()..color = star.withValues(alpha: a),
    );
    canvas.drawPath(
      _sparkle(c + Offset(orbR * 0.5, -orbR * 0.5), orbR * 0.2),
      Paint()..color = star.withValues(alpha: (0.55 + a * 0.45).clamp(0.0, 1.0)),
    );

    // yörüngenin önden geçen yarısı
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawArc(orbit, 0, math.pi, false, frontPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.dark != dark || old.orbitTurn != orbitTurn || old.sparkle != sparkle;
}
