import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ChatGPT / DALL·E tarzı "Görsel oluşturuluyor" kartı: nokta ızgarası + yüzde.
class AiImageGeneratingCard extends StatefulWidget {
  const AiImageGeneratingCard({super.key, this.progress, this.size = 280});

  /// Sunucudan gelen ilerleme (0–1). Yoksa kart kendi yumuşak ilerlemesini gösterir.
  final double? progress;
  final double size;

  @override
  State<AiImageGeneratingCard> createState() => _AiImageGeneratingCardState();
}

class _AiImageGeneratingCardState extends State<AiImageGeneratingCard> with TickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();
  late final AnimationController _pct = AnimationController(vsync: this, duration: const Duration(seconds: 28))..forward();

  @override
  void dispose() {
    _wave.dispose();
    _pct.dispose();
    super.dispose();
  }

  double get _shownProgress {
    final server = widget.progress;
    // 0.04 → ~0.92 arası yumuşak eğri; sunucu değeri varsa daha yükseğini al
    final fake = Curves.easeOutCubic.transform(_pct.value.clamp(0.0, 1.0)) * 0.88 + 0.04;
    if (server == null) return fake;
    return math.max(fake, server.clamp(0.0, 0.99));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF1C1C1E) : Colors.white;
    final label = dark ? const Color(0xFF8E8E93) : const Color(0xFF6B7280);
    final ink = dark ? const Color(0xFF5B9FD4) : const Color(0xFF3B82C4);

    return AnimatedBuilder(
      animation: Listenable.merge([_wave, _pct]),
      builder: (context, _) {
        final p = _shownProgress;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Görsel oluşturuluyor', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: label, height: 1.2)),
            const SizedBox(height: 12),
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
                      child: CustomPaint(
                        painter: _DotFieldPainter(t: _wave.value, accent: ink, muted: ink.withValues(alpha: dark ? 0.18 : 0.14)),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.12), blurRadius: 10, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Text(
                        '%${(p * 100).round()}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink, letterSpacing: 0.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DotFieldPainter extends CustomPainter {
  _DotFieldPainter({required this.t, required this.accent, required this.muted});

  final double t;
  final Color accent;
  final Color muted;

  static const _n = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final pad = size.shortestSide * 0.04;
    final usable = size.shortestSide - pad * 2;
    final step = usable / (_n - 1);
    final r = step * 0.22;
    final origin = Offset((size.width - usable) / 2, (size.height - usable) / 2);
    final phase = t * math.pi * 2;

    // İki yumuşak "blob" ChatGPT'deki gibi gezinsin
    final c1 = Offset(
      origin.dx + usable * (0.35 + 0.28 * math.sin(phase)),
      origin.dy + usable * (0.32 + 0.22 * math.cos(phase * 0.85)),
    );
    final c2 = Offset(
      origin.dx + usable * (0.62 + 0.22 * math.cos(phase * 1.1 + 1.2)),
      origin.dy + usable * (0.68 + 0.2 * math.sin(phase * 0.9 + 0.4)),
    );
    final c3 = Offset(
      origin.dx + usable * (0.48 + 0.18 * math.sin(phase * 1.3 + 2.1)),
      origin.dy + usable * (0.5 + 0.16 * math.cos(phase * 1.15 + 0.7)),
    );

    final paint = Paint()..style = PaintingStyle.fill;
    for (var y = 0; y < _n; y++) {
      for (var x = 0; x < _n; x++) {
        final p = Offset(origin.dx + x * step, origin.dy + y * step);
        final d1 = (p - c1).distance / (usable * 0.28);
        final d2 = (p - c2).distance / (usable * 0.26);
        final d3 = (p - c3).distance / (usable * 0.22);
        final w1 = math.exp(-d1 * d1 * 2.2);
        final w2 = math.exp(-d2 * d2 * 2.4);
        final w3 = math.exp(-d3 * d3 * 2.8);
        final w = (w1 * 0.95 + w2 * 0.85 + w3 * 0.55).clamp(0.0, 1.0);
        paint.color = Color.lerp(muted, accent, Curves.easeOut.transform(w))!;
        canvas.drawCircle(p, r * (0.85 + 0.35 * w), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotFieldPainter old) => old.t != t || old.accent != accent || old.muted != muted;
}
