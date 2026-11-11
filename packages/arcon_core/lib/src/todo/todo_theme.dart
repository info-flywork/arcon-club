import 'package:flutter/material.dart';

import '../talk/talk_theme.dart';
import '../ui/theme.dart';

/// Trello pano görünümü renkleri (açık / koyu).
class TodoColors {
  const TodoColors._({
    required this.listBg,
    required this.cardBg,
    required this.cardBorder,
    required this.ink,
    required this.muted,
    required this.sheetBg,
    required this.field,
    required this.fieldBorder,
    required this.chip,
  });

  final Color listBg,
      cardBg,
      cardBorder,
      ink,
      muted,
      sheetBg,
      field,
      fieldBorder,
      chip;

  static const light = TodoColors._(
    listBg: Color(0xFFF1F2F4),
    cardBg: Colors.white,
    cardBorder: Color(0x1F091E42),
    ink: Color(0xFF172B4D),
    muted: Color(0xFF44546F),
    sheetBg: Color(0xFFF7F8F9),
    field: Colors.white,
    fieldBorder: Color(0xFFDCDFE4),
    chip: Color(0x0F091E42),
  );

  static const dark = TodoColors._(
    listBg: Color(0xFF101204),
    cardBg: Color(0xFF22272B),
    cardBorder: Color(0x00000000),
    ink: Color(0xFFB6C2CF),
    muted: Color(0xFF9FADBC),
    sheetBg: Color(0xFF282E33),
    field: Color(0xFF22272B),
    fieldBorder: Color(0xFF454F59),
    chip: Color(0x14A6C5E2),
  );

  static TodoColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Pano arka planı (Trello varsayılan mavi degrade).
  static const boardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C66E4), Color(0xFF09326C)],
  );

  /// Etiket (departman) rengi — Trello etiket paleti, ada göre sabit.
  static const _labels = [
    Color(0xFF4BCE97),
    Color(0xFFF5CD47),
    Color(0xFFFEA362),
    Color(0xFFF87168),
    Color(0xFF9F8FEF),
    Color(0xFF579DFF),
    Color(0xFF6CC3E0),
    Color(0xFF94C748),
    Color(0xFFE774BB),
  ];
  static Color label(String tag) =>
      _labels[talkAvatarHue(tag) % _labels.length];

  /// Liste başlığı rengi (web To-Do sütun renkleriyle aynı sırada).
  static Color statusAccent(String status) => switch (status) {
    'doing' => const Color(0xFF579DFF),
    'review' => const Color(0xFFFEA362),
    'done' => const Color(0xFF4BCE97),
    _ => const Color(0xFF8C9BAB),
  };
}

const _months = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];
String todoDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String todoIsoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

TextStyle todoText(double size, FontWeight w, Color c, {double? height}) =>
    TextStyle(fontFamily: arconFontFamily, package: 'arcon_core', fontSize: size, fontWeight: w, color: c, height: height);

/// Kişi baş harfli yuvarlak avatar (ARCONNECT ile aynı renk mantığı).
class TodoAvatar extends StatelessWidget {
  const TodoAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.size = 28,
  });
  final String name;
  final Object? seed;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: talkAvatarColor(seed),
      shape: BoxShape.circle,
    ),
    child: Text(
      talkInitials(name),
      style: TextStyle(
        fontFamily: arconFontFamily,
        package: 'arcon_core',
        color: Colors.white,
        fontSize: size * 0.4,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
