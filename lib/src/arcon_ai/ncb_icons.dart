import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Webdeki ARCON AI'nin platform ikonları (new_chatbot/assets/app.js → I.spark, I.cspark, I.whale, ChatGPT çiçeği).
class NcbPlatformIcon extends StatelessWidget {
  const NcbPlatformIcon(this.group, {super.key, this.size = 18, this.color});

  /// ChatGPT · Claude · Gemini · DeepSeek
  final String group;
  final double size;

  /// ChatGPT çiçeğinin rengi (diğerleri kendi renginde).
  final Color? color;

  static const chatgpt = '<svg viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.7"><rect x="9.2" y="2.6" width="5.6" height="12" rx="2.8" transform="rotate(0 12 12)"/><rect x="9.2" y="2.6" width="5.6" height="12" rx="2.8" transform="rotate(60 12 12)"/><rect x="9.2" y="2.6" width="5.6" height="12" rx="2.8" transform="rotate(120 12 12)"/><rect x="9.2" y="2.6" width="5.6" height="12" rx="2.8" transform="rotate(180 12 12)"/><rect x="9.2" y="2.6" width="5.6" height="12" rx="2.8" transform="rotate(240 12 12)"/><rect x="9.2" y="2.6" width="5.6" height="12" rx="2.8" transform="rotate(300 12 12)"/></svg>';
  static const claude = '<svg viewBox="0 0 32 32"><g stroke="#d97757" stroke-width="3.2" stroke-linecap="round"><line x1="16" y1="16" x2="16.00" y2="3.50"/><line x1="16" y1="16" x2="20.75" y2="7.77"/><line x1="16" y1="16" x2="26.83" y2="9.75"/><line x1="16" y1="16" x2="25.50" y2="16.00"/><line x1="16" y1="16" x2="26.83" y2="22.25"/><line x1="16" y1="16" x2="20.75" y2="24.23"/><line x1="16" y1="16" x2="16.00" y2="28.50"/><line x1="16" y1="16" x2="11.25" y2="24.23"/><line x1="16" y1="16" x2="5.17" y2="22.25"/><line x1="16" y1="16" x2="6.50" y2="16.00"/><line x1="16" y1="16" x2="5.17" y2="9.75"/><line x1="16" y1="16" x2="11.25" y2="7.77"/></g></svg>';
  static const gemini = '<svg viewBox="0 0 28 28"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4285f4"/><stop offset=".55" stop-color="#9b72cb"/><stop offset="1" stop-color="#d96570"/></linearGradient></defs><path fill="url(#g)" d="M14 28c0-1.9-.37-3.7-1.1-5.4a13.9 13.9 0 0 0-3-4.5 14 14 0 0 0-4.5-3A13.6 13.6 0 0 0 0 14c1.9 0 3.7-.37 5.4-1.1a14 14 0 0 0 4.5-3 13.9 13.9 0 0 0 3-4.5C13.63 3.7 14 1.9 14 0c0 1.9.36 3.7 1.08 5.4a14 14 0 0 0 3.02 4.5 13.9 13.9 0 0 0 4.5 3c1.7.73 3.5 1.1 5.4 1.1-1.9 0-3.7.37-5.4 1.1a13.9 13.9 0 0 0-4.5 3 14 14 0 0 0-3.02 4.5A13.6 13.6 0 0 0 14 28Z"/></svg>';
  static const deepseek = '<svg viewBox="0 0 32 32"><path fill="#4d6bfe" d="M2.6 17.2C2.6 11.6 7.3 8 13.4 8c4.2 0 7.5 1.7 9.4 4.5l2.8-3.3c.6-.7 1.8-.3 1.8.7v3.5l2.3.6c.9.2 1 1.4.2 1.8l-3.6 1.8C25.7 23 20.6 27 13.6 27 7.9 27 2.6 23.2 2.6 17.2Z"/><circle cx="9.6" cy="15.2" r="1.35" fill="#fff"/><path d="M5.8 20.4c3.4 2.4 9.3 2.8 13.4.8" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" opacity=".9"/></svg>';

  static String? svgOf(String group) => switch (group.toLowerCase()) {
        'chatgpt' => chatgpt,
        'claude' => claude,
        'gemini' => gemini,
        'deepseek' => deepseek,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final svg = svgOf(group);
    if (svg == null) return SizedBox.square(dimension: size);
    final tint = group.toLowerCase() == 'chatgpt' ? (color ?? DefaultTextStyle.of(context).style.color ?? Colors.black) : null;
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}

/// Webdeki menü kutusu (.plat-ic): 28×28 yuvarlatılmış zemin, ortada 18px ikon.
class NcbPlatformBadge extends StatelessWidget {
  const NcbPlatformBadge(this.group, {super.key, required this.bg, required this.fg, this.selected = false, this.ring});
  final String group;
  final Color bg, fg;
  final bool selected;
  final Color? ring;

  @override
  Widget build(BuildContext context) => Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected && ring != null ? [BoxShadow(color: ring!, spreadRadius: 1.5)] : null,
        ),
        child: NcbPlatformIcon(group, color: fg),
      );
}
