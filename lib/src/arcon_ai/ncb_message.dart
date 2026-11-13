import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../ai_tools/tool_common.dart' show toolShareBytes, toolToast;
import 'ncb_api.dart';
import 'ncb_icons.dart';
import 'ncb_theme.dart';

String _s(Object? v) => v == null ? '' : '$v';

/// Akış sırasında "Web'de aranıyor…" gibi parıldayan durum yazısı (webdeki .shimmer).
class NcbShimmerText extends StatefulWidget {
  const NcbShimmerText(this.text, {super.key, required this.skin, this.size = 15});
  final String text;
  final NcbSkin skin;
  final double size;

  @override
  State<NcbShimmerText> createState() => _NcbShimmerTextState();
}

class _NcbShimmerTextState extends State<NcbShimmerText> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.skin;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: [k.fg3, k.fg, k.fg3],
          stops: const [0, 0.4, 0.8],
          begin: Alignment(1 - _a.value * 4, 0),
          end: Alignment(3 - _a.value * 4, 0),
        ).createShader(r),
        child: child,
      ),
      child: Text(widget.text, style: k.t(widget.size)),
    );
  }
}

/// Bekleme noktası (webdeki .cursor-dot).
class NcbPulseDot extends StatefulWidget {
  const NcbPulseDot({super.key, required this.color});
  final Color color;
  @override
  State<NcbPulseDot> createState() => _NcbPulseDotState();
}

class _NcbPulseDotState extends State<NcbPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.6).animate(_a),
        child: FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.4).animate(_a),
          child: Container(width: 10, height: 10, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
        ),
      );
}

/* ------------------------------- dosya türü ------------------------------- */

(IconData, Color, String) ncbFileKind(String name, [String kind = '']) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (kind == 'image' || ['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) return (Icons.image_outlined, const Color(0xFF7C3AED), 'Görsel');
  if (kind == 'pdf' || ext == 'pdf') return (Icons.picture_as_pdf_outlined, const Color(0xFFE02E2A), 'PDF');
  if (kind == 'sheet' || ['xlsx', 'xls', 'csv'].contains(ext)) return (Icons.grid_on_rounded, const Color(0xFF10A37F), ext == 'csv' ? 'CSV' : 'Tablo');
  if (kind == 'slides' || ['pptx', 'ppt', 'key'].contains(ext)) return (Icons.slideshow_outlined, const Color(0xFFF97316), 'Sunum');
  if (kind == 'docx' || ['docx', 'doc', 'rtf'].contains(ext)) return (Icons.description_outlined, const Color(0xFF2563EB), 'Belge');
  if (kind == 'archive' || ['zip', 'rar'].contains(ext)) return (Icons.folder_zip_outlined, const Color(0xFF6B7280), 'Arşiv');
  if (kind == 'code' || ['py', 'js', 'ts', 'json', 'html', 'css', 'php', 'dart', 'sql'].contains(ext)) return (Icons.code_rounded, const Color(0xFF0F766E), 'Kod');
  return (Icons.insert_drive_file_outlined, const Color(0xFF6B7280), ext.isEmpty ? 'Dosya' : ext.toUpperCase());
}

Widget ncbFileIcon(String name, [String kind = '', double size = 38]) {
  final (icon, color, _) = ncbFileKind(name, kind);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: Colors.white, size: size * 0.5),
  );
}

Future<void> ncbDownloadAndShare(BuildContext context, NcbApi api, String id, String name) async {
  try {
    final res = await http.get(Uri.parse(api.fileUrl(id, download: true)), headers: api.headers).timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) throw Exception();
    if (context.mounted) await toolShareBytes(context, res.bodyBytes, name.isEmpty ? 'arcon-ai-dosya' : name);
  } catch (_) {
    if (context.mounted) toolToast(context, 'Dosya indirilemedi');
  }
}

/// Görseli tam ekran gösterir; paylaş ve "Düzenle" (sohbete düzenleme isteği).
Future<void> ncbOpenImage(BuildContext context, NcbApi api, String id, String name, {VoidCallback? onEdit}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          actions: [
            if (onEdit != null)
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onEdit();
                },
                child: const Text('Düzenle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            IconButton(onPressed: () => ncbDownloadAndShare(ctx, api, id, name.isEmpty ? 'arcon-ai.png' : name), icon: const Icon(Icons.ios_share_rounded)),
          ],
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: CachedNetworkImage(imageUrl: api.fileUrl(id), httpHeaders: api.headers, fit: BoxFit.contain)),
        ),
      ),
    ));

/* ------------------------------- kullanıcı ------------------------------- */

class NcbUserMessage extends StatelessWidget {
  const NcbUserMessage({super.key, required this.msg, required this.skin, required this.api, required this.onEdit});
  final NcbMsg msg;
  final NcbSkin skin;
  final NcbApi api;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final k = skin;
    final atts = msg.list('attachments');
    final w = MediaQuery.sizeOf(context).width;
    if (msg.text.isEmpty && atts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (atts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in atts)
                    if (a['kind'] == 'image')
                      GestureDetector(
                        onTap: () => ncbOpenImage(context, api, _s(a['id']), _s(a['name'])),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: a['local_path'] != null
                              ? Image.file(File(_s(a['local_path'])), width: 180, height: 200, fit: BoxFit.cover, cacheWidth: 540)
                              : CachedNetworkImage(imageUrl: api.fileUrl(_s(a['id'])), httpHeaders: api.headers, width: 180, height: 200, fit: BoxFit.cover, memCacheWidth: 540),
                        ),
                      )
                    else
                      _FileChip(api: api, skin: k, id: _s(a['id']), name: _s(a['name']), kind: _s(a['kind'])),
                ],
              ),
            ),
          if (msg.text.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxWidth: w * 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(color: k.bubble, borderRadius: BorderRadius.circular(k.gemini ? 24 : 18)),
              child: SelectableText(msg.text, style: k.t(16, height: 1.5)),
            ),
          if (msg.text.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Act(icon: Icons.copy_rounded, skin: k, tip: 'Kopyala', onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.text));
                  toolToast(context, 'Kopyalandı');
                }),
                if (onEdit != null && msg.id != null) _Act(icon: Icons.edit_outlined, skin: k, tip: 'Düzenle', onTap: onEdit!),
              ],
            ),
        ],
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.api, required this.skin, required this.id, required this.name, required this.kind});
  final NcbApi api;
  final NcbSkin skin;
  final String id, name, kind;

  @override
  Widget build(BuildContext context) {
    final k = skin;
    final (_, _, label) = ncbFileKind(name, kind);
    return GestureDetector(
      onTap: id.isEmpty ? null : () => ncbDownloadAndShare(context, api, id, name),
      child: Container(
        height: 56,
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(color: k.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: k.line)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ncbFileIcon(name, kind),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: k.t(13, weight: FontWeight.w500)),
                  Text(label, style: k.t(13, color: k.fg3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Act extends StatelessWidget {
  const _Act({required this.icon, required this.skin, required this.onTap, this.tip, this.on = false});
  final IconData icon;
  final NcbSkin skin;
  final VoidCallback onTap;
  final String? tip;
  final bool on;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: Icon(icon, color: on ? skin.fg : skin.fg2),
      );
}

/* ------------------------------- asistan ------------------------------- */

class NcbAssistantMessage extends StatefulWidget {
  const NcbAssistantMessage({
    super.key,
    required this.msg,
    required this.skin,
    required this.api,
    required this.isLast,
    required this.onRegenerate,
    required this.onEditImage,
    this.contentWidth,
    this.inBubble = false,
  });

  /// Balon içinde (ARCONNECT görünümü): avatar yok, görsel genişliği balona göre, yükleme kartı dışarıda.
  final double? contentWidth;
  final bool inBubble;
  final NcbMsg msg;
  final NcbSkin skin;
  final NcbApi api;
  final bool isLast;
  final VoidCallback onRegenerate;
  final void Function(String id, String name) onEditImage;

  @override
  State<NcbAssistantMessage> createState() => _NcbAssistantMessageState();
}

class _NcbAssistantMessageState extends State<NcbAssistantMessage> {
  bool _stepsOpen = false;
  bool? _thinkOpen;

  NcbMsg get m => widget.msg;
  NcbSkin get k => widget.skin;

  Future<void> _feedback(int v) async {
    final next = m.feedback == v ? 0 : v;
    setState(() => m.feedback = next);
    try {
      await widget.api.post('feedback', {'message_id': m.id, 'value': next});
      if (next != 0 && mounted) toolToast(context, 'Geri bildirimin için teşekkürler');
    } catch (_) {}
  }

  MarkdownStyleSheet _md() {
    final base = k.t(16, height: 1.75);
    return MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 4),
      a: base.copyWith(color: k.link),
      strong: base.copyWith(fontWeight: FontWeight.w600),
      em: base.copyWith(fontStyle: FontStyle.italic),
      h1: k.t(25, weight: FontWeight.w600, height: 1.35),
      h2: k.t(21, weight: FontWeight.w600, height: 1.35),
      h3: k.t(18, weight: FontWeight.w600, height: 1.35),
      h4: k.t(16, weight: FontWeight.w600, height: 1.35),
      h1Padding: const EdgeInsets.only(top: 14, bottom: 4),
      h2Padding: const EdgeInsets.only(top: 14, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 12, bottom: 2),
      listBullet: base,
      listIndent: 22,
      blockSpacing: 12,
      blockquote: base.copyWith(color: k.fg2),
      blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: k.line, width: 3))),
      blockquotePadding: const EdgeInsets.only(left: 14),
      code: TextStyle(fontFamily: 'Menlo', fontSize: 14, color: k.fg, backgroundColor: k.hover),
      codeblockDecoration: BoxDecoration(color: k.codeBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: k.line2)),
      codeblockPadding: const EdgeInsets.all(16),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: k.line))),
      tableHead: k.t(14, weight: FontWeight.w600),
      tableBody: k.t(14, height: 1.5),
      tableHeadAlign: TextAlign.left,
      tableBorder: TableBorder.all(color: k.line, borderRadius: BorderRadius.circular(12)),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      tableCellsDecoration: BoxDecoration(color: k.bg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = m.d;
    final steps = m.list('steps');
    final images = m.list('images');
    final files = m.list('files');
    final sources = <Map<String, dynamic>>[];
    final hosts = <String>{};
    for (final s in m.list('sources')) {
      var host = Uri.tryParse(_s(s['url']))?.host.replaceFirst(RegExp(r'^www\.'), '') ?? _s(s['url']);
      if (host.endsWith('vertexaisearch.cloud.google.com') && _s(s['title']).isNotEmpty) host = _s(s['title']).replaceFirst(RegExp(r'^www\.'), '');
      if (hosts.add(host)) sources.add({...s, '_host': host});
    }
    final thinking = _s(d['thinking']);
    final showAvatar = !widget.inBubble && (k.gemini || k.deepseek);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinking.isNotEmpty) _think(thinking, _s(d['thinking_seconds'])),
        if (m.status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: m.status == '…' ? NcbPulseDot(color: k.fg) : NcbShimmerText(m.status, skin: k),
          ),
        if (steps.isNotEmpty) _steps(steps),
        if (images.isNotEmpty || (!widget.inBubble && m.imageLoaders.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (!widget.inBubble)
                  for (final e in m.imageLoaders.entries) _ImageLoader(size: e.value),
                for (final img in images) _genImage(img),
              ],
            ),
          ),
        if (m.text.isNotEmpty)
          MarkdownBody(
            data: m.text,
            selectable: !m.streaming,
            styleSheet: _md(),
            onTapLink: (_, href, _) {
              final u = href == null ? null : Uri.tryParse(href);
              if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
            },
          ),
        for (final c in m.list('connects')) _ConnectCard(api: widget.api, skin: k, c: c),
        for (final a in m.list('actions')) _ActionCard(api: widget.api, skin: k, a: a),
        if (files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 12),
            child: Wrap(spacing: 10, runSpacing: 10, children: [for (final f in files) _fileCard(f)]),
          ),
        if (sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in sources)
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(_s(s['url'])), mode: LaunchMode.externalApplication),
                    child: Container(
                      height: 28,
                      constraints: const BoxConstraints(maxWidth: 240),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(color: k.hover, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.public_rounded, size: 13, color: k.fg2),
                          const SizedBox(width: 6),
                          Flexible(child: Text(_s(s['_host']), maxLines: 1, overflow: TextOverflow.ellipsis, style: k.t(12, color: k.fg2))),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (d['stopped'] == true) _notice('Cevap durduruldu.'),
        if (d['truncated'] == true) _notice('Cevap uzunluk sınırına ulaştı. "Devam et" yazarak sürdürebilirsin.'),
        if (_s(d['error']).isNotEmpty) _notice(_s(d['error']), err: true, retry: widget.isLast),
        if (!m.streaming && (m.text.isNotEmpty || images.isNotEmpty || files.isNotEmpty)) _actions(),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: widget.inBubble ? 0 : 22),
      child: showAvatar
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: k.gemini
                      ? const NcbPlatformIcon('Gemini', size: 24)
                      : Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: k.line)),
                          alignment: Alignment.center,
                          child: const NcbPlatformIcon('DeepSeek', size: 18),
                        ),
                ),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }

  Widget _think(String text, String seconds) {
    final live = m.thinkingLive;
    final open = _thinkOpen ?? live;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _thinkOpen = !open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology_outlined, size: 17, color: k.fg2),
                const SizedBox(width: 6),
                live ? NcbShimmerText('Düşünüyor…', skin: k, size: 14) : Text(seconds.isEmpty || seconds == '0' ? 'Düşündü' : 'Düşündü ($seconds sn)', style: k.t(14, color: k.fg2)),
                Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: k.fg2),
              ],
            ),
          ),
          if (open)
            Container(
              margin: const EdgeInsets.only(top: 8, left: 4),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: k.line, width: 2))),
              child: Text(text, style: k.t(14, color: k.fg2, height: 1.6)),
            ),
        ],
      ),
    );
  }

  Widget _steps(List<Map<String, dynamic>> steps) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _stepsOpen = !_stepsOpen),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(steps.length == 1 ? _s(steps.first['label']) : '${steps.length} adım tamamlandı', style: k.t(14, color: k.fg2)),
                  Icon(_stepsOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: k.fg2),
                ],
              ),
            ),
            if (_stepsOpen)
              Container(
                margin: const EdgeInsets.only(top: 8, left: 4),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: k.line, width: 2))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final s in steps)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: _s(s['label']), style: k.t(14, weight: FontWeight.w500, color: k.fg2)),
                            if (_s(s['detail']).isNotEmpty) TextSpan(text: '  ${_s(s['detail'])}', style: k.t(14, color: k.fg3)),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _genImage(Map<String, dynamic> img) {
    final id = _s(img['id']);
    final wide = ((img['width'] as num?) ?? 0) > ((img['height'] as num?) ?? 0);
    final w = widget.contentWidth ?? (MediaQuery.sizeOf(context).width - 40 - (k.gemini || k.deepseek ? 40 : 0));
    return GestureDetector(
      onTap: () => ncbOpenImage(context, widget.api, id, _s(img['name']), onEdit: () => widget.onEditImage(id, _s(img['name']))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Container(
              color: k.hover,
              width: wide ? w : w * 0.86,
              child: CachedNetworkImage(
                imageUrl: widget.api.fileUrl(id),
                httpHeaders: widget.api.headers,
                fit: BoxFit.fitWidth,
                fadeInDuration: const Duration(milliseconds: 600),
                placeholder: (_, _) => AspectRatio(aspectRatio: wide ? 3 / 2 : 1, child: Container(color: k.hover)),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: GestureDetector(
                onTap: () => widget.onEditImage(id, _s(img['name'])),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(999)),
                  child: const Text('Düzenle', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: GestureDetector(
                onTap: () => ncbDownloadAndShare(context, widget.api, id, _s(img['name']).isEmpty ? 'arcon-ai.png' : _s(img['name'])),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                  child: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCard(Map<String, dynamic> f) {
    final name = _s(f['name']);
    final (_, _, label) = ncbFileKind(name, _s(f['kind']));
    return GestureDetector(
      onTap: () => ncbDownloadAndShare(context, widget.api, _s(f['id']), name),
      child: Container(
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(color: k.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: k.line)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ncbFileIcon(name, _s(f['kind']), 40),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: k.t(14, weight: FontWeight.w500)),
                  Text(label, style: k.t(13, color: k.fg3)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.download_rounded, size: 20, color: k.fg2),
          ],
        ),
      ),
    );
  }

  Widget _notice(String text, {bool err = false, bool retry = false}) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: err ? k.danger.withValues(alpha: 0.08) : k.hover, borderRadius: BorderRadius.circular(12)),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: k.t(14, color: err ? k.danger : k.fg2)),
          if (retry)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: widget.onRegenerate,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text('Tekrar dene', style: k.t(14, color: err ? k.danger : k.fg2).copyWith(decoration: TextDecoration.underline)),
                ),
              ),
            ),
        ])),
      );

  Widget _actions() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            _Act(icon: Icons.copy_rounded, skin: k, tip: 'Kopyala', onTap: () {
              Clipboard.setData(ClipboardData(text: m.text));
              toolToast(context, 'Kopyalandı');
            }),
            if (m.id != null) ...[
              _Act(icon: m.feedback == 1 ? Icons.thumb_up : Icons.thumb_up_outlined, on: m.feedback == 1, skin: k, tip: 'İyi cevap', onTap: () => _feedback(1)),
              _Act(icon: m.feedback == -1 ? Icons.thumb_down : Icons.thumb_down_outlined, on: m.feedback == -1, skin: k, tip: 'Kötü cevap', onTap: () => _feedback(-1)),
            ],
            if (widget.isLast) _Act(icon: Icons.refresh_rounded, skin: k, tip: 'Yeniden üret', onTap: widget.onRegenerate),
            if (k.claude && widget.isLast) ...[const Spacer(), const NcbPlatformIcon('Claude', size: 22)],
          ],
        ),
      );
}

/// Görsel üretilirken: açık gri kart, nokta ızgarası hissi ve tahmini yüzde (webdeki .img-loader).
class _ImageLoader extends StatefulWidget {
  const _ImageLoader({required this.size});
  final String size;
  @override
  State<_ImageLoader> createState() => _ImageLoaderState();
}

class _ImageLoaderState extends State<_ImageLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  final _start = DateTime.now();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.size.split('x');
    final w = double.tryParse(parts.first) ?? 1024, h = double.tryParse(parts.length > 1 ? parts[1] : '') ?? 1024;
    final maxW = MediaQuery.sizeOf(context).width - 40;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: w > h ? maxW : maxW * 0.86,
        child: AspectRatio(
          aspectRatio: w / h,
          child: AnimatedBuilder(
            animation: _a,
            builder: (_, _) {
              final secs = DateTime.now().difference(_start).inMilliseconds / 1000;
              final pct = (95 * (1 - 1 / (1 + secs / 18))).clamp(1, 95).round();
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _DotsPainter(_a.value)),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
                      child: Text('%$pct', style: const TextStyle(fontSize: 13, color: Color(0xFF374151), fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF3F4F6));
    const gap = 14.0;
    final p = Paint();
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        final wave = 0.5 + 0.5 * (((x + y) / 120 - t * 6.283).remainder(6.283) - 3.14).abs() / 3.14;
        p.color = Color.lerp(const Color(0xFFDDE3EC), const Color(0xFF60A5FA), 1 - wave)!;
        canvas.drawCircle(Offset(x, y), 1.6 + (1 - wave) * 1.2, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.t != t;
}

/* ------------------------------- dış servis kartları ------------------------------- */

const _argLabels = <String, String?>{
  'recipient_email': 'Alıcı', 'to': 'Alıcı', 'extra_recipients': 'Diğer alıcılar', 'cc': 'Bilgi', 'bcc': 'Gizli', 'subject': 'Konu', 'body': 'İçerik', 'message_body': 'İçerik',
  'summary': 'Başlık', 'start_datetime': 'Başlangıç', 'end_datetime': 'Bitiş', 'start_date': 'Başlangıç', 'end_date': 'Bitiş', 'event_duration_hour': 'Süre (saat)', 'event_duration_minutes': 'Süre (dakika)',
  'attendees': 'Katılımcılar', 'location': 'Yer', 'description': 'Açıklama', 'recurrence': 'Tekrar', 'create_meeting_room': 'Meet bağlantısı', 'event_id': 'Etkinlik',
  'name': 'Ad', 'file_name': 'Dosya adı', 'text_content': 'İçerik', 'mime_type': 'Tür', 'file_id': 'Dosya', 'parent_id': 'Klasör', 'add_parents': 'Yeni klasör', 'remove_parents': 'Eski klasör',
  'title': 'Başlık', 'folder_name': 'Klasör', 'folder_id': 'Klasör', 'spreadsheet_id': 'Tablo', 'spreadsheetId': 'Tablo', 'range': 'Aralık', 'values': 'Değerler',
  'is_html': null, 'user_id': null, 'thread_id': null, 'attachment': null, 'include_signature': null, 'from_email': null, 'calendar_id': null, 'calendarId': null, 'timezone': null,
  'send_updates': null, 'eventType': null, 'visibility': null, 'transparency': null, 'supportsAllDrives': null, 'supports_all_drives': null, 'fields': null,
  'valueInputOption': null, 'value_input_option': null, 'majorDimension': null, 'major_dimension': null, 'insertDataOption': null, 'includeValuesInResponse': null,
  'include_values_in_response': null, 'responseValueRenderOption': null, 'response_value_render_option': null, 'responseDateTimeRenderOption': null,
  'response_datetime_render_option': null, 'auto_expand_sheet': null, 'exclude_organizer': null, 'guestsCanModify': null, 'guestsCanInviteOthers': null, 'guestsCanSeeOtherGuests': null,
};

String _showArg(Object? v) {
  if (v is List) {
    final rows = v.map((x) => x is List ? x.join(' | ') : (x is Map ? _s(x['email'] ?? jsonEncode(x)) : _s(x)));
    return rows.join(v.isNotEmpty && v.first is List ? '\n' : ', ');
  }
  if (v is Map) return jsonEncode(v);
  if (v is bool) return v ? 'Evet' : 'Hayır';
  return _s(v);
}

class _ActionCard extends StatefulWidget {
  const _ActionCard({required this.api, required this.skin, required this.a});
  final NcbApi api;
  final NcbSkin skin;
  final Map<String, dynamic> a;
  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  late String _status = _s(widget.a['status']).isEmpty ? 'pending' : _s(widget.a['status']);
  String? _error;
  bool _busy = false;

  Future<void> _decide(String decision) async {
    setState(() {
      _busy = true;
      if (decision == 'approve') _status = 'running';
    });
    try {
      final r = await widget.api.post('action_decide', {'id': widget.a['id'], 'decision': decision});
      widget.a['status'] = r['status'];
      setState(() {
        _status = _s(r['status']);
        _error = r['error'] as String?;
      });
    } catch (e) {
      if (mounted) toolToast(context, e is Exception ? '$e' : 'İşlem yapılamadı');
      setState(() => _status = 'pending');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.skin;
    final args = ((widget.a['args'] as Map?) ?? const {}).cast<String, dynamic>();
    const states = {'done': 'Yapıldı ✓', 'rejected': 'Vazgeçildi', 'failed': 'Yapılamadı', 'running': 'Yapılıyor…'};
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: k.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: k.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_s(widget.a['service'])} · ${_s(widget.a['title'])}', style: k.t(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final e in args.entries)
            if (_argLabels[e.key] != null || !_argLabels.containsKey(e.key))
              if (!(e.value == null || e.value == '' || (e.value is List && (e.value as List).isEmpty)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 96, child: Text(_argLabels[e.key] ?? e.key, style: k.t(14, color: k.fg3))),
                      Expanded(child: Text(_showArg(e.value), maxLines: 12, overflow: TextOverflow.ellipsis, style: k.t(14))),
                    ],
                  ),
                ),
          const SizedBox(height: 8),
          if (_status == 'pending')
            Row(
              children: [
                _pill(k, 'Onayla', primary: true, onTap: _busy ? null : () => _decide('approve')),
                const SizedBox(width: 8),
                _pill(k, 'Vazgeç', onTap: _busy ? null : () => _decide('reject')),
              ],
            )
          else
            Wrap(
              spacing: 8,
              children: [
                Text(states[_status] ?? _status, style: k.t(14, weight: FontWeight.w500, color: _status == 'done' ? const Color(0xFF10A37F) : (_status == 'failed' ? k.danger : k.fg2))),
                if (_error != null) Text(_error!, style: k.t(14, color: k.danger)),
              ],
            ),
        ],
      ),
    );
  }
}

Widget _pill(NcbSkin k, String label, {bool primary = false, VoidCallback? onTap}) => GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: primary ? k.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: primary ? k.accent : k.line),
          ),
          child: Text(label, style: k.t(14, color: primary ? k.accentFg : k.fg)),
        ),
      ),
    );

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.api, required this.skin, required this.c});
  final NcbApi api;
  final NcbSkin skin;
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final k = skin;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: k.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: k.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_s(c['service'])} hesabın bağlı değil', style: k.t(14, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Bağladıktan sonra isteğini tekrar yazman yeterli.', style: k.t(14, color: k.fg2)),
          const SizedBox(height: 10),
          _pill(k, '${_s(c['service'])} hesabını bağla', primary: true, onTap: () async {
            try {
              final r = await api.post('connect_link', {'toolkit': c['toolkit']});
              await launchUrl(Uri.parse(_s(r['url'])), mode: LaunchMode.externalApplication);
            } catch (e) {
              if (context.mounted) toolToast(context, 'Bağlantı açılamadı');
            }
          }),
        ],
      ),
    );
  }
}
