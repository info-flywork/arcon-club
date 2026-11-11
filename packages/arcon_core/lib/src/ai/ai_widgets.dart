import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../ui/theme.dart';
import 'chat_controller.dart';
import 'engine_client.dart';
import 'engine_models.dart';

String formatBytes(int b) => b < 1024
    ? '$b B'
    : b < 1048576
        ? '${(b / 1024).toStringAsFixed(0)} KB'
        : '${(b / 1048576).toStringAsFixed(1)} MB';

IconData fileIcon(String name, String mime) {
  final n = name.toLowerCase();
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (n.endsWith('.xlsx') || n.endsWith('.xls') || n.endsWith('.csv')) return Icons.table_chart_outlined;
  if (n.endsWith('.pptx') || n.endsWith('.ppt')) return Icons.slideshow_outlined;
  if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (n.endsWith('.docx') || n.endsWith('.doc')) return Icons.description_outlined;
  return Icons.insert_drive_file_outlined;
}

/// Asistan dosyasını indirip telefonun ilgili uygulamasında açar (Excel, Word, PDF, PowerPoint…).
Future<void> openArtifact(BuildContext context, EngineClient engine, EngineArtifact a, int conversationId) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text('${a.filename} indiriliyor…'), duration: const Duration(seconds: 1)));
  try {
    final bytes = await engine.download(engine.artifactUrl(a, conversationId));
    final dir = await getTemporaryDirectory();
    final safe = a.filename.replaceAll(RegExp(r'[^\w.\- ()ğüşıöçĞÜŞİÖÇ]'), '_');
    final f = File('${dir.path}/$safe');
    await f.writeAsBytes(bytes);
    final r = await OpenFilex.open(f.path);
    if (r.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(content: Text('Dosya açılamadı: ${r.message}')));
    }
  } on ArconApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.engine, required this.conversationId, this.showHeader = true});

  final EngineMessage message;
  final EngineClient engine;
  final int conversationId;

  /// ARCONNECT'teki WhatsApp tarzı balonda "ARCON AI" başlığı gösterilmez
  final bool showHeader;

  @override
  Widget build(BuildContext context) => message.isUser ? _user(context) : _assistant(context);

  Widget _user(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.end, children: [
                for (final f in message.attachments)
                  Chip(
                    avatar: Icon(fileIcon(f.name, f.mimeType), size: 16),
                    label: Text(f.name, overflow: TextOverflow.ellipsis),
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
            ),
          GestureDetector(
            onLongPress: () => _copy(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: SelectableText(message.content, style: const TextStyle(fontSize: 15.5, height: 1.4)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    final theme = Theme.of(context);
    final waiting = message.streaming && message.content.isEmpty;
    return GestureDetector(
      onLongPress: message.content.isEmpty ? null : () => _copy(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showHeader) ...[
        Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: ArconColors.ink, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.auto_awesome, size: 15, color: ArconColors.mint),
          ),
          const SizedBox(width: 8),
          const Text('ARCON AI', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        ],
        if (message.status != null || waiting)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Text(message.status ?? 'Düşünüyor…', style: const TextStyle(color: ArconColors.muted)),
            ]),
          ),
        if (message.content.isNotEmpty)
          MarkdownBody(
            data: message.content,
            selectable: true,
            onTapLink: (_, href, _) {
              final u = href == null ? null : Uri.tryParse(href);
              if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
            },
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyLarge?.copyWith(height: 1.5, fontSize: 15.5),
              code: TextStyle(fontFamily: 'Menlo', fontSize: 13, backgroundColor: theme.colorScheme.surfaceContainerHighest),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              tableBorder: TableBorder.all(color: theme.dividerColor),
              // Geniş tablolar sıkışmasın: sütun içeriğe göre, tablo yatay kaydırılır
              tableColumnWidth: const IntrinsicColumnWidth(),
              tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tableHead: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        if (message.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(message.error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        if (message.artifacts.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final a in message.artifacts) _ArtifactView(artifact: a, engine: engine, conversationId: conversationId),
        ],
        if (message.webImages.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: message.webImages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final img = message.webImages[i];
                return GestureDetector(
                  onTap: img.pageUrl.isEmpty ? null : () => launchUrl(Uri.parse(img.pageUrl), mode: LaunchMode.externalApplication),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(img.imageUrl, width: 150, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(width: 150, color: theme.dividerColor)),
                  ),
                );
              },
            ),
          ),
        ],
        if (message.sources.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (i, s) in message.sources.take(8).indexed)
              ActionChip(
                avatar: CircleAvatar(radius: 9, child: Text('${i + 1}', style: const TextStyle(fontSize: 10))),
                label: Text(s.host, overflow: TextOverflow.ellipsis),
                tooltip: s.title,
                visualDensity: VisualDensity.compact,
                onPressed: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
              ),
          ]),
        ],
      ]),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopyalandı'), duration: Duration(seconds: 1)));
  }
}

class _ArtifactView extends StatelessWidget {
  const _ArtifactView({required this.artifact, required this.engine, required this.conversationId});
  final EngineArtifact artifact;
  final EngineClient engine;
  final int conversationId;

  @override
  Widget build(BuildContext context) {
    final url = engine.artifactUrl(artifact, conversationId).toString();
    if (artifact.isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _ImageViewer(url: url, headers: engine.authHeaders, title: artifact.filename,
                onShare: () => openArtifact(context, engine, artifact, conversationId)),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(url, headers: engine.authHeaders, fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null
                    ? child
                    : const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
                errorBuilder: (_, _, _) => const SizedBox(height: 80, child: Center(child: Text('Görsel yüklenemedi')))),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(fileIcon(artifact.filename, artifact.mimeType), color: Theme.of(context).colorScheme.primary),
          title: Text(artifact.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(formatBytes(artifact.size)),
          trailing: const Icon(Icons.download_rounded),
          onTap: () => openArtifact(context, engine, artifact, conversationId),
        ),
      ),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.headers, required this.title, required this.onShare});
  final String url;
  final Map<String, String> headers;
  final String title;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(title, style: const TextStyle(fontSize: 15)),
          actions: [IconButton(tooltip: 'Aç / Paylaş', icon: const Icon(Icons.ios_share), onPressed: onShare)],
        ),
        body: InteractiveViewer(maxScale: 5, child: Center(child: Image.network(url, headers: headers))),
      );
}

/// Ek çipleri (yükleniyor / hazır / hata).
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.controller});
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.attachments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final a in controller.attachments)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                avatar: a.uploading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(a.error != null ? Icons.error_outline : fileIcon(a.name, a.isImage ? 'image/' : ''), size: 18),
                label: Text(a.error ?? a.name, overflow: TextOverflow.ellipsis),
                onDeleted: () => controller.removeAttachment(a),
              ),
            ),
        ],
      ),
    );
  }
}
