import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Webdeki ARCON AI görünümleri (assets/app.css): model seçimine göre ChatGPT, Gemini, Claude, DeepSeek.
/// Renkler CSS değişkenleriyle birebir aynıdır.
class NcbSkin {
  const NcbSkin({
    required this.name,
    required this.bg,
    required this.sidebar,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.line,
    required this.line2,
    required this.hover,
    required this.active,
    required this.bubble,
    required this.composer,
    required this.composerBorder,
    required this.composerShadow,
    required this.codeBg,
    required this.codeHead,
    required this.popover,
    required this.accent,
    required this.accentFg,
    required this.link,
    this.activeFg,
    this.danger = const Color(0xFFE02E2A),
    this.dark = false,
  });

  final String name;
  final Color bg, sidebar, fg, fg2, fg3, line, line2, hover, active, bubble, composer, codeBg, codeHead, popover, accent, accentFg, link, danger;
  final Color? composerBorder;
  final bool composerShadow;
  final Color? activeFg;
  final bool dark;

  bool get gemini => name == 'gemini';
  bool get claude => name == 'claude';
  bool get deepseek => name == 'deepseek';

  /// Gövde yazı tipi: Gemini → Google Sans benzeri sistem, Claude başlıkları serif.
  String? get serif => claude ? 'Georgia' : null;

  TextStyle t(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height, double spacing = 0, String? family}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? fg, height: height, letterSpacing: spacing, fontFamily: family);

  /// ARCONNECT (Talk) renkleriyle: ARCON AI ekranı WhatsApp görünümünde.
  factory NcbSkin.talk({required bool dark, required Color ink, required Color muted, required Color line, required Color bubble, required Color pop, required Color accent, required Color accentFg}) => NcbSkin(
        name: 'talk',
        dark: dark,
        bg: bubble,
        sidebar: bubble,
        fg: ink,
        fg2: muted,
        fg3: muted.withValues(alpha: 0.75),
        line: line,
        line2: line.withValues(alpha: 0.5),
        hover: ink.withValues(alpha: 0.06),
        active: ink.withValues(alpha: 0.1),
        bubble: bubble,
        composer: bubble,
        composerBorder: line,
        composerShadow: false,
        codeBg: ink.withValues(alpha: 0.05),
        codeHead: ink.withValues(alpha: 0.08),
        popover: pop,
        accent: accent,
        accentFg: accentFg,
        link: dark ? const Color(0xFF7AB7FF) : const Color(0xFF2964AA),
      );

  static NcbSkin of(String skin, bool dark) => switch (skin) {
        'gemini' => dark ? _geminiDark : _gemini,
        'claude' => dark ? _claudeDark : _claude,
        'deepseek' => dark ? _deepseekDark : _deepseek,
        _ => dark ? _chatgptDark : _chatgpt,
      };

  static const _chatgpt = NcbSkin(
    name: 'chatgpt',
    bg: Color(0xFFFFFFFF), sidebar: Color(0xFFF9F9F9), fg: Color(0xFF0D0D0D), fg2: Color(0xFF5D5D5D), fg3: Color(0xFF8F8F8F),
    line: Color(0x1A000000), line2: Color(0x0F000000), hover: Color(0x0D000000), active: Color(0x14000000),
    bubble: Color(0xFFF4F4F4), composer: Color(0xFFFFFFFF), composerBorder: Color(0x26000000), composerShadow: true,
    codeBg: Color(0xFFF9F9F9), codeHead: Color(0xFFF3F3F3), popover: Color(0xFFFFFFFF),
    accent: Color(0xFF0D0D0D), accentFg: Color(0xFFFFFFFF), link: Color(0xFF2964AA),
  );
  static const _chatgptDark = NcbSkin(
    name: 'chatgpt', dark: true,
    bg: Color(0xFF212121), sidebar: Color(0xFF181818), fg: Color(0xFFECECEC), fg2: Color(0xFFB4B4B4), fg3: Color(0xFF8F8F8F),
    line: Color(0x1FFFFFFF), line2: Color(0x12FFFFFF), hover: Color(0x0FFFFFFF), active: Color(0x1AFFFFFF),
    bubble: Color(0xFF303030), composer: Color(0xFF303030), composerBorder: Color(0x0FFFFFFF), composerShadow: false,
    codeBg: Color(0xFF171717), codeHead: Color(0xFF2A2A2A), popover: Color(0xFF353535),
    accent: Color(0xFFFFFFFF), accentFg: Color(0xFF0D0D0D), link: Color(0xFF7AB7FF),
  );
  static const _gemini = NcbSkin(
    name: 'gemini',
    bg: Color(0xFFFFFFFF), sidebar: Color(0xFFF0F4F9), fg: Color(0xFF1F1F1F), fg2: Color(0xFF444746), fg3: Color(0xFF747775),
    line: Color(0xFFE0E3E7), line2: Color(0xFFECEFF3), hover: Color(0x14444746), active: Color(0xFFD3E3FD),
    bubble: Color(0xFFE9EEF6), composer: Color(0xFFF0F4F9), composerBorder: null, composerShadow: false,
    codeBg: Color(0xFFF0F4F9), codeHead: Color(0xFFE9EEF6), popover: Color(0xFFFFFFFF),
    accent: Color(0xFF0B57D0), accentFg: Color(0xFFFFFFFF), link: Color(0xFF0B57D0), activeFg: Color(0xFF041E49),
  );
  static const _geminiDark = NcbSkin(
    name: 'gemini', dark: true,
    bg: Color(0xFF131314), sidebar: Color(0xFF1E1F20), fg: Color(0xFFE3E3E3), fg2: Color(0xFFC4C7C5), fg3: Color(0xFF8E918F),
    line: Color(0xFF3C4043), line2: Color(0xFF2D2F31), hover: Color(0x14E3E3E3), active: Color(0xFF1F3760),
    bubble: Color(0xFF333537), composer: Color(0xFF1E1F20), composerBorder: null, composerShadow: false,
    codeBg: Color(0xFF1E1F20), codeHead: Color(0xFF282A2C), popover: Color(0xFF282A2C),
    accent: Color(0xFFA8C7FA), accentFg: Color(0xFF062E6F), link: Color(0xFFA8C7FA), activeFg: Color(0xFFD3E3FD),
  );
  static const _claude = NcbSkin(
    name: 'claude',
    bg: Color(0xFFFAF9F5), sidebar: Color(0xFFF3F1EA), fg: Color(0xFF141413), fg2: Color(0xFF5E5D59), fg3: Color(0xFF8A8880),
    line: Color(0x241F1E1D), line2: Color(0x121F1E1D), hover: Color(0x0D1F1E1D), active: Color(0x171F1E1D),
    bubble: Color(0xFFF0EEE6), composer: Color(0xFFFFFFFF), composerBorder: Color(0x2E1F1E1D), composerShadow: true,
    codeBg: Color(0xFFF5F4EE), codeHead: Color(0xFFEFEDE5), popover: Color(0xFFFFFFFF),
    accent: Color(0xFFC6613F), accentFg: Color(0xFFFFFFFF), link: Color(0xFFC6613F),
  );
  static const _claudeDark = NcbSkin(
    name: 'claude', dark: true,
    bg: Color(0xFF262624), sidebar: Color(0xFF1F1E1D), fg: Color(0xFFFAF9F5), fg2: Color(0xFFC2C0B6), fg3: Color(0xFF9C9A92),
    line: Color(0x26DEDCD1), line2: Color(0x14DEDCD1), hover: Color(0x0FDEDCD1), active: Color(0x1CDEDCD1),
    bubble: Color(0xFF141413), composer: Color(0xFF30302E), composerBorder: Color(0x2EDEDCD1), composerShadow: false,
    codeBg: Color(0xFF1F1E1D), codeHead: Color(0xFF2A2928), popover: Color(0xFF30302E),
    accent: Color(0xFFC6613F), accentFg: Color(0xFFFFFFFF), link: Color(0xFFE3A68C),
  );
  static const _deepseek = NcbSkin(
    name: 'deepseek',
    bg: Color(0xFFFFFFFF), sidebar: Color(0xFFF9FBFF), fg: Color(0xFF262626), fg2: Color(0xFF525252), fg3: Color(0xFF8B8B8B),
    line: Color(0x1A000000), line2: Color(0x0F000000), hover: Color(0x0A000000), active: Color(0xFFDBEAFE),
    bubble: Color(0xFFEFF6FF), composer: Color(0xFFF3F4F6), composerBorder: null, composerShadow: false,
    codeBg: Color(0xFFFAFAFA), codeHead: Color(0xFFF3F4F6), popover: Color(0xFFFFFFFF),
    accent: Color(0xFF4D6BFE), accentFg: Color(0xFFFFFFFF), link: Color(0xFF4D6BFE), activeFg: Color(0xFF4D6BFE),
  );
  static const _deepseekDark = NcbSkin(
    name: 'deepseek', dark: true,
    bg: Color(0xFF292A2D), sidebar: Color(0xFF212327), fg: Color(0xFFF8FAFF), fg2: Color(0xFFC9CDD4), fg3: Color(0xFF8B8F97),
    line: Color(0x1FFFFFFF), line2: Color(0x12FFFFFF), hover: Color(0x0FFFFFFF), active: Color(0xFF414158),
    bubble: Color(0xFF414158), composer: Color(0xFF404045), composerBorder: null, composerShadow: false,
    codeBg: Color(0xFF1F2023), codeHead: Color(0xFF2C2D31), popover: Color(0xFF35363A),
    accent: Color(0xFF4D6BFE), accentFg: Color(0xFFFFFFFF), link: Color(0xFF8EA2FF), activeFg: Color(0xFFF8FAFF),
  );
}

/// Claude kıvılcımı (webdeki I.cspark) — turuncu yıldız.
class NcbClaudeSpark extends StatelessWidget {
  const NcbClaudeSpark({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _SparkPainter());
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = const Color(0xFFD97757)
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final len = size.width * (i.isEven ? 0.48 : 0.36);
      canvas.drawLine(c, c + Offset(math.sin(a) * len, -math.cos(a) * len), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
