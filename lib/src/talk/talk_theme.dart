import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// ARCONNECT renkleri — WhatsApp iOS düzeni; yeşil yerine siyah tonlar (açık/koyu).
@immutable
class TalkColors {
  const TalkColors._({
    required this.dark,
    required this.header,
    required this.headerBorder,
    required this.rail,
    required this.railTop,
    required this.searchBg,
    required this.searchBorder,
    required this.ink,
    required this.muted,
    required this.line,
    required this.rowLine,
    required this.accent,
    required this.accentContrast,
    required this.accentSoft,
    required this.chatHead,
    required this.msgBg,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.bubbleInInk,
    required this.bubbleOutInk,
    required this.name,
    required this.time,
    required this.composerArea,
    required this.composerBar,
    required this.composerBorder,
    required this.barBtn,
    required this.mentionBg,
    required this.mentionInk,
    required this.popBg,
    required this.popBorder,
    required this.infoBg,
    required this.infoCard,
    required this.unreadPreview,
    required this.userBtnBg,
    required this.userBtnInk,
    required this.userBtnBorder,
  });

  final bool dark;
  final Color header, headerBorder, rail, railTop, searchBg, searchBorder, ink, muted, line, rowLine;
  final Color accent, accentContrast, accentSoft, chatHead, msgBg, bubbleIn, bubbleOut, bubbleInInk, bubbleOutInk;
  final Color name, time, composerArea, composerBar, composerBorder, barBtn, mentionBg, mentionInk;
  final Color popBg, popBorder, infoBg, infoCard, unreadPreview, userBtnBg, userBtnInk, userBtnBorder;

  static const ticks = Color(0xFF53BDEB);
  static const danger = Color(0xFFEF4444);
  static const dangerSolid = Color(0xFFE11D48);
  static const wa = Color(0xFF111111); // eskiden WhatsApp yeşili; ARCONNECT'te siyah
  static const infoGreen = Color(0xFF0F6E56);
  static const infoGreenText = Color(0xFF0B6B5A);
  static const reactMine = Color(0xFF636366);

  // WhatsApp iOS düzeni, yeşil yerine siyah tonlar — açık tema
  static const light = TalkColors._(
    dark: false,
    header: Color(0xFFFFFFFF),
    headerBorder: Color(0x00000000),
    rail: Color(0xFFFFFFFF),
    railTop: Color(0xFFFFFFFF),
    searchBg: Color(0xFFF0F0F1),
    searchBorder: Color(0xFFD1D1D6),
    ink: Color(0xFF000000),
    muted: Color(0xFF8A8A8E),
    line: Color(0xFFE3E3E6),
    rowLine: Color(0xFFE3E3E6),
    accent: Color(0xFF111111),
    accentContrast: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFEDEDEF),
    chatHead: Color(0xFFF7F7F8),
    msgBg: Color(0xFFEFEDEA),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFF1C1C1E),
    bubbleInInk: Color(0xFF000000),
    bubbleOutInk: Color(0xFFFFFFFF),
    name: Color(0xFF3A3A3C),
    time: Color(0xFF8A8A8E),
    composerArea: Color(0xFFF7F7F8),
    composerBar: Color(0xFFFFFFFF),
    composerBorder: Color(0xFFD1D1D6),
    barBtn: Color(0xFF111111),
    mentionBg: Color(0xFFEDEDEF),
    mentionInk: Color(0xFF007AFF),
    popBg: Color(0xFFFFFFFF),
    popBorder: Color(0xFFE3E3E6),
    infoBg: Color(0xFFF2F2F7),
    infoCard: Color(0xFFFFFFFF),
    unreadPreview: Color(0xFF3A3A3C),
    userBtnBg: Color(0xFFEDEDEF),
    userBtnInk: Color(0xFF111111),
    userBtnBorder: Color(0xFFB9B9BE),
  );

  // WhatsApp iOS düzeni, siyah tonlar — koyu tema
  static const darkTheme = TalkColors._(
    dark: true,
    header: Color(0xFF000000),
    headerBorder: Color(0x00000000),
    rail: Color(0xFF000000),
    railTop: Color(0xFF000000),
    searchBg: Color(0xFF1C1C1E),
    searchBorder: Color(0xFF3A3A3C),
    ink: Color(0xFFFFFFFF),
    muted: Color(0xFF8E8E93),
    line: Color(0xFF2C2C2E),
    rowLine: Color(0xFF2C2C2E),
    accent: Color(0xFFF2F2F2),
    accentContrast: Color(0xFF000000),
    accentSoft: Color(0xFF2C2C2E),
    chatHead: Color(0xFF111112),
    msgBg: Color(0xFF0B0B0C),
    bubbleIn: Color(0xFF1C1C1E),
    bubbleOut: Color(0xFF3A3A3C),
    bubbleInInk: Color(0xFFFFFFFF),
    bubbleOutInk: Color(0xFFFFFFFF),
    name: Color(0xFFD1D1D6),
    time: Color(0xFF8E8E93),
    composerArea: Color(0xFF111112),
    composerBar: Color(0xFF1C1C1E),
    composerBorder: Color(0xFF3A3A3C),
    barBtn: Color(0xFFF2F2F2),
    mentionBg: Color(0xFF2C2C2E),
    mentionInk: Color(0xFF64D2FF),
    popBg: Color(0xFF1C1C1E),
    popBorder: Color(0xFF3A3A3C),
    infoBg: Color(0xFF000000),
    infoCard: Color(0xFF1C1C1E),
    unreadPreview: Color(0xFFD1D1D6),
    userBtnBg: Color(0xFF2C2C2E),
    userBtnInk: Color(0xFFFFFFFF),
    userBtnBorder: Color(0xFF636366),
  );

  static TalkColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTheme : light;
}

TextStyle talkText(double size, FontWeight weight, Color color, {double? height, double? letterSpacing}) => TextStyle(
      fontFamily: arconFontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

TextStyle dmSans(double size, double weight, Color color) => TextStyle(
      fontFamily: arconFontFamily,
      fontSize: size,
      fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
      color: color,
    );

/// JS `avatarHue`: ((h << 5) - h) + charCode, int32 taşmasıyla aynı sonuç.
int talkAvatarHue(Object? seed) {
  final s = '${seed ?? 'x'}'.isEmpty ? 'x' : '${seed ?? 'x'}';
  num h = 0;
  for (final c in s.codeUnits) {
    final shifted = (h.toInt().toSigned(32) << 5).toSigned(32);
    h = shifted - h + c;
  }
  return h.abs().toInt() % 360;
}

/// `hsl(var(--av-hue) 52% 42%)`
Color talkAvatarColor(Object? seed) => HSLColor.fromAHSL(1, talkAvatarHue(seed).toDouble(), 0.52, 0.42).toColor();

/// JS `initials`: iki kelime → baş harfler; tek kelime → ilk iki harf (tr-TR büyük harf).
String talkInitials(String? name) {
  final parts = (name ?? '?').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String up(String s) => s.isEmpty ? '?' : s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
  String first(String s) => s.characters.isEmpty ? '?' : s.characters.first;
  if (parts.length == 1) {
    final ch = parts[0].characters.toList();
    return up(ch.take(2).join());
  }
  return up(first(parts.first) + first(parts.last));
}

const _trMonths = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

DateTime? talkParseTime(String? s) => s == null || s.isEmpty ? null : DateTime.tryParse(s.replaceFirst(' ', 'T'));

/// WhatsApp gibi: kendi metin mesajı yalnızca kısa süre düzenlenebilir.
const talkEditWindow = Duration(minutes: 1);

bool talkCanEditMessage(String createdAt, {DateTime? now, String text = 'x'}) {
  if (text.trim().isEmpty) return false;
  final t = talkParseTime(createdAt);
  if (t == null) return false;
  return (now ?? DateTime.now()).difference(t) <= talkEditWindow;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Mesaj saati: "20 Eki 05:58"
String talkMsgTime(String? iso) {
  final d = talkParseTime(iso);
  if (d == null) return iso ?? '';
  return '${_two(d.day)} ${_trMonths[d.month - 1]} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Balon saati: "20:38" (gün, mesajların arasındaki ayraçta yazar)
String talkClock(String? iso) {
  final d = talkParseTime(iso);
  if (d == null) return iso ?? '';
  return '${_two(d.hour)}:${_two(d.minute)}';
}

const _trDays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const _trMonthsLong = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

/// Gün ayracı: "Bugün", "Dün", son bir haftada gün adı, daha eskide "2 Kasım 2026"
String talkDayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Bugün';
  if (diff == 1) return 'Dün';
  if (diff > 1 && diff < 7) return _trDays[d.weekday - 1];
  return '${d.day} ${_trMonthsLong[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

/// Liste saati: bugün "10:49", dün "Dün", önce "12 Eyl"
String talkListTime(String? iso) {
  final d = talkParseTime(iso);
  if (d == null) return '';
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '${_two(d.hour)}:${_two(d.minute)}';
  final y = now.subtract(const Duration(days: 1));
  if (d.year == y.year && d.month == y.month && d.day == y.day) return 'Dün';
  return '${d.day} ${_trMonths[d.month - 1]}';
}

/// JS `firstName`
String talkFirstName(String? name) {
  final s = (name ?? '').trim();
  return s.isEmpty ? 'Biri' : s.split(RegExp(r'\s+')).first;
}

String talkFmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1048576).toStringAsFixed(1)} MB';
}
