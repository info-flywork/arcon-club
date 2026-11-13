import 'package:flutter/material.dart';

/// Proje geneli hafif geçişler. Süreler kısa, hareket küçük; "hareketi azalt" açıksa anında geçer.
abstract final class Motion {
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 240);

  static Duration of(BuildContext context, Duration d) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

/// İki görünüm arasında kısa solma + birkaç piksellik kayma (ör. başlık ↔ arama çubuğu).
/// Değişen görünüme farklı bir `key` verilmeli.
class SwapFade extends StatelessWidget {
  const SwapFade({super.key, required this.child, this.alignment = Alignment.centerLeft, this.offset = 0.12});

  final Widget child;
  final Alignment alignment;

  /// Dikey kayma (yüksekliğin oranı).
  final double offset;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Motion.of(context, Motion.normal),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(alignment: alignment, children: [...previous, ?current]),
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(begin: Offset(0, offset), end: Offset.zero).animate(anim),
        child: child,
      ),
    ),
    child: child,
  );
}

/// İkon değişimi (ara ↔ kapat): küçük ölçek + solma.
class IconSwap extends StatelessWidget {
  const IconSwap(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: Motion.of(context, Motion.fast),
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(scale: Tween(begin: 0.7, end: 1.0).animate(anim), child: child),
    ),
    child: Icon(icon, key: ValueKey(icon), size: size, color: color),
  );
}

/// Basılınca çok hafif küçülen sarmalayıcı (kartlar için).
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  Offset _start = Offset.zero;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) {
      _start = e.position;
      _set(true);
    },
    // parmak kayarsa (liste kaydırma) küçülme bırakılır
    onPointerMove: (e) {
      if (_down && (e.position - _start).distance > 8) _set(false);
    },
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: Motion.of(context, const Duration(milliseconds: 120)),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}
