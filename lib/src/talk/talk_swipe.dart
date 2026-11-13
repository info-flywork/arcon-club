import 'package:flutter/material.dart';

import 'talk_theme.dart';

/// Kaydırınca açılan düğme (WhatsApp iOS: "Diğer" / "Arşivle", aramalarda "…" / sil).
class TalkSwipeAction {
  const TalkSwipeAction({required this.icon, required this.color, required this.onTap, this.label, this.tooltip});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// Doluysa simgenin altında yazar (sohbet listesi); boşsa yalnızca simge (aramalar).
  final String? label;
  final String? tooltip;
}

/// Satırı sola kaydırınca sağdan düğmeler çıkar. Aynı anda tek satır açık kalır.
class TalkSwipeActions extends StatefulWidget {
  const TalkSwipeActions({super.key, required this.child, required this.actions, this.enabled = true, this.actionWidth = 80});

  final Widget child;
  final List<TalkSwipeAction> actions;
  final bool enabled;
  final double actionWidth;

  /// Açık olan satır (başkası açılınca kapanır)
  static final ValueNotifier<Object?> _open = ValueNotifier(null);

  @override
  State<TalkSwipeActions> createState() => _TalkSwipeActionsState();
}

class _TalkSwipeActionsState extends State<TalkSwipeActions> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final _id = Object();

  double get _max => widget.actionWidth * widget.actions.length;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    TalkSwipeActions._open.addListener(_onOther);
  }

  @override
  void dispose() {
    TalkSwipeActions._open.removeListener(_onOther);
    if (TalkSwipeActions._open.value == _id) TalkSwipeActions._open.value = null;
    _anim.dispose();
    super.dispose();
  }

  void _onOther() {
    if (TalkSwipeActions._open.value != _id && _anim.value > 0) _anim.animateTo(0, curve: Curves.easeOut);
  }

  void _close() {
    _anim.animateTo(0, curve: Curves.easeOut);
    if (TalkSwipeActions._open.value == _id) TalkSwipeActions._open.value = null;
  }

  void _drag(DragUpdateDetails d) {
    TalkSwipeActions._open.value = _id;
    _anim.value = (_anim.value - d.primaryDelta! / _max).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final open = v < -300 || (v <= 300 && _anim.value > 0.45);
    if (open) {
      _anim.animateTo(1, curve: Curves.easeOut);
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;
    return GestureDetector(
      onHorizontalDragUpdate: _drag,
      onHorizontalDragEnd: _end,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final dx = _max * _anim.value;
          return ClipRect(
            child: Stack(
              children: [
                if (dx > 0)
                  Positioned.fill(
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [for (final a in widget.actions) _button(a, dx / widget.actions.length)]),
                  ),
                Transform.translate(
                  offset: Offset(-dx, 0),
                  child: dx > 0
                      // açıkken satıra dokunmak yalnızca kapatır
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _close,
                          child: AbsorbPointer(child: child),
                        )
                      : child,
                ),
              ],
            ),
          );
        },
        child: widget.child,
      ),
    );
  }

  Widget _button(TalkSwipeAction a, double width) {
    final label = a.label;
    return SizedBox(
      width: width,
      child: Tooltip(
        message: a.tooltip ?? label ?? '',
        child: Material(
          color: a.color,
          child: InkWell(
            onTap: () {
              _close();
              a.onTap();
            },
            child: Opacity(
              // açılıp kapanırken dar alanda yazı sıkışmasın
              opacity: ((width / widget.actionWidth - 0.4) / 0.6).clamp(0.0, 1.0),
              child: OverflowBox(
                maxWidth: widget.actionWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(a.icon, color: Colors.white, size: 24),
                    if (label != null) ...[const SizedBox(height: 4), Text(label, maxLines: 1, style: talkText(14, FontWeight.w500, Colors.white))],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
