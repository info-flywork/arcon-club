import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ui/mono.dart';

/// Küçük AI araçlarının (Deklarasyon, Teslim Tutanağı, Packing, Adaptly …) ortak parçaları.

/// Baytları geçici dosyaya yazar ve paylaşım menüsünü açar (Dosyalar'a kaydet, Mail, WhatsApp …).
Future<void> toolShareBytes(BuildContext context, Uint8List bytes, String fileName) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/${fileName.replaceAll(RegExp(r'[/\\]'), '_')}');
  await f.writeAsBytes(bytes);
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [XFile(f.path)],
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}

/// Bağlantıdaki dosyayı indirip telefonda açar (Excel, Word, PDF …).
Future<void> toolOpenUrlFile(BuildContext context, String url, {String? fileName}) async {
  try {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('${res.statusCode}');
    final name = fileName ?? Uri.parse(url).pathSegments.lastOrNull ?? 'dosya';
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${Uri.decodeComponent(name).replaceAll(RegExp(r'[/\\]'), '_')}');
    await f.writeAsBytes(res.bodyBytes);
    await OpenFilex.open(f.path);
  } on Exception {
    if (context.mounted) toolToast(context, 'Dosya açılamadı');
  }
}

void toolToast(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

/// Siyah-beyaz araç sayfası iskeleti: geri + başlık + kaydırılabilir içerik.
class ToolPage extends StatelessWidget {
  const ToolPage({super.key, required this.title, required this.children, this.actions = const [], this.bottom});

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: c.ink)),
                    Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(17, weight: FontWeight.w800))),
                    ...actions,
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + (bottom == null ? pad.bottom : 0)),
                  children: children,
                ),
              ),
              ?bottom,
            ],
          ),
        ),
      ),
    );
  }
}

/// Başlık bloğu: büyük başlık + açıklama.
class ToolIntro extends StatelessWidget {
  const ToolIntro({super.key, required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: c.text(26, weight: FontWeight.w800, spacing: -0.7)),
          const SizedBox(height: 6),
          Text(text, style: c.text(14, color: c.muted, height: 1.5)),
        ],
      ),
    );
  }
}

/// Numaralı adım kartı.
class ToolStep extends StatelessWidget {
  const ToolStep({super.key, required this.n, required this.title, required this.done, required this.child});
  final int n;
  final String title;
  final bool done;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.field, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: done ? c.ink : Colors.transparent, shape: BoxShape.circle, border: Border.all(color: done ? c.ink : c.line, width: 1.5)),
                child: done ? Icon(Icons.check_rounded, size: 15, color: c.bg) : Text('$n', style: c.text(12, weight: FontWeight.w800, color: c.muted)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: c.text(15, weight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Dosya seçme düğmesi ya da seçilen dosya satırı.
class ToolFilePick extends StatelessWidget {
  const ToolFilePick({super.key, required this.label, required this.fileName, required this.onPick, this.onClear, this.icon = Icons.upload_file_rounded});
  final String label;
  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    if (fileName == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.bg,
          side: BorderSide(color: c.line),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(icon, size: 19),
        label: Text(label, style: c.text(13.5, weight: FontWeight.w700)),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 20, color: c.ink),
          const SizedBox(width: 10),
          Expanded(child: Text(fileName!, maxLines: 1, overflow: TextOverflow.ellipsis, style: c.text(14, weight: FontWeight.w600))),
          IconButton(onPressed: onClear ?? onPick, icon: Icon(onClear == null ? Icons.swap_horiz_rounded : Icons.close_rounded, size: 18, color: c.muted)),
        ],
      ),
    );
  }
}

/// Seçenek çipleri (tek seçim).
class ToolChoice<T> extends StatelessWidget {
  const ToolChoice({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (v, label) in items)
          GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: v == value ? c.ink : c.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: v == value ? c.ink : c.line),
              ),
              child: Text(label, style: c.text(13, weight: FontWeight.w700, color: v == value ? c.bg : c.ink)),
            ),
          ),
      ],
    );
  }
}

/// Sonuç kartı: siyah zemin, başlık, açıklama, düğmeler.
class ToolResult extends StatelessWidget {
  const ToolResult({super.key, required this.title, this.text, required this.actions});
  final String title;
  final String? text;
  final List<(IconData, String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final fg = c.dark ? c.ink : c.bg;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: c.dark ? c.field : c.ink, borderRadius: BorderRadius.circular(20), border: c.dark ? Border.all(color: c.line) : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: fg, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: c.text(18, weight: FontWeight.w800, color: fg))),
            ],
          ),
          if (text != null) ...[const SizedBox(height: 6), Text(text!, style: c.text(13.5, color: fg.withValues(alpha: 0.75), height: 1.45))],
          const SizedBox(height: 14),
          for (final (icon, label, onTap) in actions)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: fg,
                  side: BorderSide(color: fg.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(icon, size: 18),
                label: Text(label, style: c.text(14, weight: FontWeight.w700, color: fg)),
              ),
            ),
        ],
      ),
    );
  }
}
