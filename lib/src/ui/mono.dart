import 'package:flutter/material.dart';

import 'theme.dart' show arconFontFamily;

/// Türkçe büyük harf: i → İ, ı → I (Dart'ın toUpperCase'i dil bilmez).
String trUpper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Siyah-beyaz palet (koyu temada tersine döner) ve Poppins yazı.
class ArconMono {
  const ArconMono._(this.dark);
  factory ArconMono.of(BuildContext context) => ArconMono._(Theme.of(context).brightness == Brightness.dark);

  final bool dark;

  Color get bg => dark ? const Color(0xFF0A0A0A) : Colors.white;
  Color get ink => dark ? const Color(0xFFF4F4F5) : const Color(0xFF111111);
  Color get muted => dark ? const Color(0xFF9A9AA0) : const Color(0xFF6B6B70);
  Color get faint => dark ? const Color(0xFF5E5E64) : const Color(0xFFA6A6AB);
  Color get line => dark ? const Color(0x24FFFFFF) : const Color(0x1F000000);
  Color get field => dark ? const Color(0xFF161616) : const Color(0xFFF6F6F7);
  Color get danger => dark ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F);

  TextStyle text(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height, double spacing = 0}) => TextStyle(
    fontFamily: arconFontFamily,
    fontSize: size,
    fontWeight: weight,
    color: color ?? ink,
    height: height,
    letterSpacing: spacing,
  );

  OutlineInputBorder _border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: width),
  );

  /// [icon] null ise solda ikon olmaz (çok satırlı metin alanları).
  InputDecoration input(String hint, IconData? icon, {Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: text(15, color: faint),
    filled: true,
    fillColor: field,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: muted),
    suffixIcon: suffix,
    border: _border(line),
    enabledBorder: _border(line),
    focusedBorder: _border(ink, 1.4),
    errorBorder: _border(danger.withValues(alpha: 0.6)),
    focusedErrorBorder: _border(danger, 1.4),
    errorStyle: text(12, weight: FontWeight.w500, color: danger),
  );

  Widget label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(trUpper(t), style: text(11, weight: FontWeight.w700, spacing: 1)),
  );

  Widget errorBox(String message) => Container(
    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
    decoration: BoxDecoration(
      color: field,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: danger.withValues(alpha: 0.45)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 18, color: danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: text(13, weight: FontWeight.w500, height: 1.4)),
        ),
      ],
    ),
  );

  Widget primaryButton(String title, {required bool busy, required VoidCallback onPressed}) => SizedBox(
    height: 54,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: bg,
        disabledBackgroundColor: ink.withValues(alpha: 0.55),
        disabledForegroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: busy
          ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: bg))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: text(15.5, weight: FontWeight.w600, color: bg),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 19, color: bg),
              ],
            ),
    ),
  );

  Widget linkRow(String prefix, String link, VoidCallback onTap) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(prefix, style: text(13.5, color: muted)),
      GestureDetector(
        onTap: onTap,
        child: Text(
          link,
          style: text(
            13.5,
            weight: FontWeight.w700,
          ).copyWith(decoration: TextDecoration.underline, decorationColor: ink, decorationThickness: 1.5),
        ),
      ),
    ],
  );
}

/// "ARCON CLUB" yazısı: logonun şeffaf kenarları kırpılır, CLUB yanına yazılır.
class ArconClubMark extends StatelessWidget {
  const ArconClubMark({super.key, required this.c, required this.color, this.size = 16});
  final ArconMono c;
  final Color color;
  final double size;

  /// ARCON CLUB yazısı (assets/arcon_club_wordmark.png); [size] büyük harf yüksekliği.
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/arcon_club_wordmark.png',
    height: size * 1.15,
    color: color,
    colorBlendMode: BlendMode.srcIn,
    filterQuality: FilterQuality.high,
    semanticLabel: 'ARCON CLUB',
  );
}
