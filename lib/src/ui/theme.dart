import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Uygulama yazı tipi (SIL OFL, assets/fonts/Poppins-OFL.txt).
const String arconFontFamily = 'Poppins';

/// ARCON web paneliyle aynı renkler (header.css).
abstract final class ArconColors {
  static const ink = Color(0xFF1A222D);
  static const green = Color(0xFF0B4F3D);
  static const mint = Color(0xFF9DF0D0);
  static const surface = Color(0xFFF8FAFC);
  static const line = Color(0xFFE8EEF5);
  static const muted = Color(0xFF6B7684);
}

/// [mono]: ARCONNECT uygulaması — yeşil yerine siyah tonlar (koyuda beyaz).
ThemeData arconTheme(Brightness brightness, {bool mono = false}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: mono ? const Color(0xFF111111) : ArconColors.green,
    brightness: brightness,
    dynamicSchemeVariant: mono ? DynamicSchemeVariant.monochrome : DynamicSchemeVariant.tonalSpot,
    primary: mono ? (dark ? const Color(0xFFF2F2F2) : const Color(0xFF111111)) : (dark ? ArconColors.mint : ArconColors.green),
    surface: dark ? const Color(0xFF11161D) : ArconColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: arconFontFamily,
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
          fontFamily: arconFontFamily,
        ),
    // Sistem pencereleri / menüleri (onay, dosya seçici) iPhone'daki gibi mavi kalsın
    cupertinoOverrideTheme: const CupertinoThemeData(primaryColor: CupertinoColors.systemBlue),
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: dark ? Colors.white : ArconColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1A222D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? const Color(0xFF26303C) : ArconColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A222D) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: dark ? const Color(0xFF26303C) : ArconColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: arconFontFamily, fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
  );
}

/// Sunucudaki `icon` anahtarı → Material ikon. Bilinmeyen anahtar için genel ikon.
IconData arconModuleIcon(String key) => switch (key) {
      'home' => Icons.space_dashboard_outlined,
      'chat' => Icons.forum_outlined,
      'check' => Icons.checklist_rounded,
      'people' => Icons.groups_outlined,
      'news' => Icons.newspaper_outlined,
      'school' => Icons.school_outlined,
      'search' => Icons.search_rounded,
      'store' => Icons.storefront_outlined,
      'score' => Icons.insights_outlined,
      'idea' => Icons.lightbulb_outline,
      'feedback' => Icons.rate_review_outlined,
      'support' => Icons.support_agent_outlined,
      'person' => Icons.person_outline,
      'ai' => Icons.auto_awesome_outlined,
      _ => Icons.widgets_outlined,
    };

class ArconLogo extends StatelessWidget {
  const ArconLogo({super.key, this.height = 22});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Image.asset(
      dark ? 'assets/arcon_logo_dark.png' : 'assets/arcon_logo.png',
      height: height,
      semanticLabel: 'ARCON',
    );
  }
}
