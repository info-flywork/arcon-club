import 'package:flutter/material.dart';

/// Proje geneli yükleniyor görünümü: içerik şekli gri kutularla çizilir, üstünden hafif
/// bir parıltı geçer (CircularProgressIndicator yerine). Açık/koyu temaya uyar;
/// cihazda "hareketi azalt" açıksa parıltı durur.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hi = dark ? const Color(0x22FFFFFF) : const Color(0x99FFFFFF);
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 2.6 - 1.3; // soldan sağa
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(t - 0.6, -0.2),
            end: Alignment(t + 0.6, 0.2),
            colors: [hi.withAlpha(0), hi, hi.withAlpha(0)], // saydam beyaz: araya gri karışmasın
            stops: const [0.25, 0.5, 0.75],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

/// Tek iskelet kutusu (Shimmer içinde kullanılır).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 12, this.radius = 8, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  static Color color(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E20) : const Color(0xFFEDEDEF);

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(
      color: color(context),
      borderRadius: circle ? null : BorderRadius.circular(radius),
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
    ),
  );
}

/// Liste satırları: solda daire (avatar/ikon) ya da sağda küçük görsel + iki satır yazı.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 8,
    this.leading = true,
    this.thumbnail = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.leadingSize = 46,
    this.scrollable = false,
  });

  final int count;
  final bool leading;

  /// Sağda haber kartı görseli gibi dikdörtgen.
  final bool thumbnail;
  final EdgeInsetsGeometry padding;
  final double leadingSize;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    Widget row(int i) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (leading) ...[SkeletonBox(height: leadingSize, circle: true), const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: thumbnail ? 70 : null, height: thumbnail ? 9 : 13, radius: 6),
                const SizedBox(height: 9),
                FractionallySizedBox(widthFactor: i.isEven ? 0.92 : 0.7, child: const SkeletonBox(height: 13, radius: 6)),
                if (thumbnail) ...[
                  const SizedBox(height: 7),
                  const FractionallySizedBox(widthFactor: 0.55, child: SkeletonBox(height: 13, radius: 6)),
                  const SizedBox(height: 10),
                  const SkeletonBox(width: 90, height: 9, radius: 6),
                ],
              ],
            ),
          ),
          if (thumbnail) ...[const SizedBox(width: 14), const SkeletonBox(width: 96, height: 76, radius: 12)],
        ],
      ),
    );
    final children = [for (var i = 0; i < count; i++) row(i)];
    final body = Padding(
      padding: padding,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
    return Shimmer(child: _Fit(child: body));
  }
}

/// Kart ızgarası (ana sayfa ürün kartları, AI modülleri).
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({
    super.key,
    this.count = 6,
    this.columns = 2,
    this.height = 140,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final int count;
  final int columns;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rows = (count / columns).ceil();
    return Shimmer(
      child: _Fit(
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: 10),
                      Expanded(child: SkeletonBox(height: height, radius: 18)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Makale / detay sayfası: kapak, kategori, başlık, paragraflar.
class SkeletonArticle extends StatelessWidget {
  const SkeletonArticle({super.key, this.cover = true});
  final bool cover;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover) SkeletonBox(width: double.infinity, height: 300, radius: 0) else SizedBox(height: top + 70),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 90, height: 10),
                  const SizedBox(height: 16),
                  const SkeletonBox(width: double.infinity, height: 24),
                  const SizedBox(height: 10),
                  const FractionallySizedBox(widthFactor: 0.7, child: SkeletonBox(height: 24)),
                  const SizedBox(height: 22),
                  const SkeletonBox(width: 180, height: 10),
                  const SizedBox(height: 28),
                  for (var i = 0; i < 9; i++) ...[
                    FractionallySizedBox(widthFactor: i % 4 == 3 ? 0.6 : 1, child: const SkeletonBox(height: 13, radius: 6)),
                    SizedBox(height: i % 4 == 3 ? 22 : 10),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sohbet balonları (mesajlar yüklenirken).
class SkeletonChat extends StatelessWidget {
  const SkeletonChat({super.key, this.count = 9});
  final int count;

  @override
  Widget build(BuildContext context) {
    const widths = [0.55, 0.4, 0.68, 0.3, 0.5, 0.62, 0.36, 0.48, 0.58];
    return Shimmer(
      child: _Fit(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Align(
                    alignment: i % 3 == 1 ? Alignment.centerRight : Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: widths[i % widths.length],
                      child: SkeletonBox(height: i % 4 == 2 ? 58 : 38, radius: 16),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yatay pano sütunları (To-Do).
class SkeletonBoard extends StatelessWidget {
  const SkeletonBoard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var col = 0; col < 3; col++)
              Container(
                width: 270,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SkeletonBox.color(context).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(width: 110, height: 14),
                    const SizedBox(height: 12),
                    for (var i = 0; i < 4 - col; i++) ...[
                      SkeletonBox(width: double.infinity, height: i.isEven ? 64 : 48, radius: 10),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Yükleme bitince iskeletten içeriğe yumuşak geçiş.
class SkeletonSwitcher extends StatelessWidget {
  const SkeletonSwitcher({super.key, required this.loading, required this.skeleton, required this.child});

  final bool loading;
  final Widget skeleton;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 260),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
    child: loading
        ? KeyedSubtree(key: const ValueKey('skeleton'), child: skeleton)
        : KeyedSubtree(key: const ValueKey('content'), child: child),
  );
}

/// İskelet, verilen alandan büyükse taşma hatası vermeden kırpılır (dar paneller, küçük ekranlar).
class _Fit extends StatelessWidget {
  const _Fit({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), primary: false, child: child),
  );
}
