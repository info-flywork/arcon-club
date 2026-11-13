import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import 'talk_controller.dart';
import 'talk_message.dart';
import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';
import '../ui/skeleton.dart';

/// WhatsApp iOS "Medya, bağlantı ve belgeler": üstte Medya / Bağlantılar / Belgeler, sağda "Seç";
/// medya galeri ızgarası, altta "N Fotoğraf, M Video".
class TalkMediaScreen extends StatefulWidget {
  const TalkMediaScreen({super.key, required this.controller, required this.channelId, required this.files, this.restricted = false});

  final TalkController controller;
  final int channelId;
  final List<TalkAttachment> files;

  /// Kısıtlı sohbet: seçip paylaşma kapalı
  final bool restricted;

  @override
  State<TalkMediaScreen> createState() => _TalkMediaScreenState();
}

/// Sohbetteki bağlantı: adres, gönderen, zaman
typedef _Link = ({String url, String who, String at});

class _TalkMediaScreenState extends State<TalkMediaScreen> {
  int _tab = 0;
  bool _selecting = false;
  final _picked = <int>{};
  List<_Link>? _links;

  TalkController get _c => widget.controller;
  List<TalkAttachment> get _media => widget.files.where((f) => f.isImage || f.isVideo).toList();
  List<TalkAttachment> get _docs => widget.files.where((f) => !f.isImage && !f.isVideo).toList();

  /// Bağlantılar mesajlardan çıkarılır (son mesajlar)
  Future<void> _loadLinks() async {
    if (_links != null) return;
    try {
      final r = await _c.api.messages(widget.channelId);
      final re = RegExp(r'https?://[^\s<>"\]]+');
      final out = <_Link>[];
      for (final m in r.messages.reversed) {
        for (final u in re.allMatches(m.body)) {
          out.add((url: u.group(0)!.replaceAll(RegExp(r'[).,;!?]+$'), ''), who: m.displayName.isEmpty ? m.username : m.displayName, at: m.createdAt));
        }
      }
      if (mounted) setState(() => _links = out);
    } on ArconApiException {
      if (mounted) setState(() => _links = const []);
    }
  }

  void _setTab(int i) {
    setState(() {
      _tab = i;
      _picked.clear();
      _selecting = false;
    });
    if (i == 1) _loadLinks();
  }

  Future<void> _sharePicked() async {
    final all = [..._media, ..._docs].where((f) => _picked.contains(f.id)).toList();
    if (all.isEmpty) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: all.map((f) => '${f.origName}: ${_c.api.fileUrl(f.path)}').join('\n'),
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
    if (mounted) setState(() => _picked.clear());
  }

  void _open(TalkAttachment f) {
    if (_selecting) {
      setState(() => _picked.contains(f.id) ? _picked.remove(f.id) : _picked.add(f.id));
      return;
    }
    final url = _c.api.fileUrl(f.path);
    f.isImage ? openTalkImage(context, url, f.origName) : openTalkFile(context, url, f.origName);
  }

  static String _date(String at) {
    final d = talkParseTime(at);
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  static String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final bg = c.dark ? Colors.black : Colors.white;
    final body = switch (_tab) {
      0 => _mediaGrid(c, top, bottom),
      1 => _linksList(c, top, bottom),
      _ => _docsList(c, top, bottom),
    };
    return Scaffold(
      backgroundColor: bg,
      body: Stack(fit: StackFit.expand, children: [
        body,
        Positioned(top: 0, left: 0, right: 0, child: _topBar(c, top)),
        if (_selecting && _picked.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom + 12,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: c.ink, foregroundColor: c.dark ? Colors.black : Colors.white, minimumSize: const Size.fromHeight(50)),
              onPressed: _sharePicked,
              icon: const Icon(CupertinoIcons.share),
              label: Text('${_picked.length} öğeyi paylaş', style: talkText(16, FontWeight.w600, c.dark ? Colors.black : Colors.white)),
            ),
          ),
      ]),
    );
  }

  /// Buzlu üst çubuk: geri, sekmeler, Seç
  Widget _topBar(TalkColors c, double top) {
    final glass = c.dark ? const Color(0xE61C1C1E) : const Color(0xE6FFFFFF);
    final border = c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE6E6E8);
    final canSelect = _tab != 1 && !widget.restricted;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, top + 6, 12, 0),
      child: Row(children: [
        Tooltip(
          message: 'Geri',
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: glass, shape: BoxShape.circle, border: Border.all(color: border)),
              child: Icon(CupertinoIcons.chevron_left, size: 22, color: c.ink),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 46,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: glass, borderRadius: BorderRadius.circular(23), border: Border.all(color: border)),
            child: Row(children: [
              for (final (i, l) in const [(0, 'Medya'), (1, 'Bağlantılar'), (2, 'Belgeler')])
                Expanded(
                  child: GestureDetector(
                    onTap: () => _setTab(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tab == i ? (c.dark ? const Color(0xFF3A3A3C) : const Color(0xFFEDEDF0)) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(14.5, _tab == i ? FontWeight.w600 : FontWeight.w500, c.ink)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: canSelect ? () => setState(() {
                _selecting = !_selecting;
                _picked.clear();
              }) : null,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: glass, borderRadius: BorderRadius.circular(23), border: Border.all(color: border)),
            child: Text(_selecting ? 'Vazgeç' : 'Seç', style: talkText(15, FontWeight.w600, canSelect ? c.ink : c.muted)),
          ),
        ),
      ]),
    );
  }

  Widget _empty(TalkColors c, String t) => Center(child: Text(t, style: talkText(15, FontWeight.w400, c.muted)));

  Widget _mediaGrid(TalkColors c, double top, double bottom) {
    final media = _media;
    if (media.isEmpty) return _empty(c, 'Bu sohbette fotoğraf veya video yok');
    final photos = media.where((f) => f.isImage).length;
    final videos = media.length - photos;
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: EdgeInsets.only(top: top + 62),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 2, crossAxisSpacing: 2),
          itemCount: media.length,
          itemBuilder: (_, i) {
            final f = media[i];
            final on = _picked.contains(f.id);
            return GestureDetector(
              onTap: () => _open(f),
              child: Stack(fit: StackFit.expand, children: [
                if (f.isImage)
                  TalkNetImage(_c.api.thumbUrl(f.path, width: 240), fallbackUrl: _c.api.fileUrl(f.path), fit: BoxFit.cover, decodeWidth: 120, placeholder: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA))
                else
                  const ColoredBox(color: Color(0xFF1C1C1E), child: Center(child: Icon(CupertinoIcons.play_fill, color: Colors.white70, size: 28))),
                if (f.isVideo)
                  const Positioned(left: 6, bottom: 5, child: Icon(CupertinoIcons.videocam_fill, color: Colors.white, size: 18)),
                if (_selecting)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: on ? c.ink : const Color(0x55000000),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: on ? Icon(Icons.check, size: 15, color: c.dark ? Colors.black : Colors.white) : null,
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, bottom + 80),
          child: Text(
            [if (photos > 0) '$photos Fotoğraf', if (videos > 0) '$videos Video'].join(', '),
            textAlign: TextAlign.center,
            style: talkText(16, FontWeight.w500, c.ink),
          ),
        ),
      ),
    ]);
  }

  Widget _linksList(TalkColors c, double top, double bottom) {
    final links = _links;
    if (links == null) return Padding(padding: EdgeInsets.only(top: top), child: const SkeletonList(count: 6, padding: EdgeInsets.symmetric(horizontal: 16)));
    if (links.isEmpty) return _empty(c, 'Bu sohbette bağlantı yok');
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(0, top + 66, 0, bottom + 24),
      itemCount: links.length,
      separatorBuilder: (_, _) => Divider(height: 0.6, thickness: 0.6, indent: 76, color: c.rowLine),
      itemBuilder: (_, i) {
        final l = links[i];
        final host = Uri.tryParse(l.url)?.host.replaceFirst('www.', '') ?? l.url;
        return InkWell(
          onTap: () => launchUrl(Uri.parse(l.url), mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(10)),
                child: Icon(CupertinoIcons.link, size: 22, color: c.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(15.5, FontWeight.w600, c.ink)),
                  Text(l.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(13, FontWeight.w400, c.muted)),
                  Text('${l.who} · ${_date(l.at)}', style: talkText(12, FontWeight.w400, c.muted)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _docsList(TalkColors c, double top, double bottom) {
    final docs = _docs;
    if (docs.isEmpty) return _empty(c, 'Bu sohbette belge yok');
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(0, top + 66, 0, bottom + 80),
      itemCount: docs.length,
      separatorBuilder: (_, _) => Divider(height: 0.6, thickness: 0.6, indent: 76, color: c.rowLine),
      itemBuilder: (_, i) {
        final f = docs[i];
        final ext = f.origName.contains('.') ? f.origName.split('.').last.toUpperCase() : 'DOSYA';
        final on = _picked.contains(f.id);
        return InkWell(
          onTap: () => _open(f),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFF111111), borderRadius: BorderRadius.circular(10)),
                child: Text(ext.length > 4 ? ext.substring(0, 4) : ext, style: talkText(12, FontWeight.w700, Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.origName, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(15.5, FontWeight.w500, c.ink)),
                  Text('${_size(f.sizeBytes)} · ${_date(f.createdAt)}', style: talkText(12.5, FontWeight.w400, c.muted)),
                ]),
              ),
              if (_selecting) Icon(on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 24, color: on ? c.ink : c.muted),
            ]),
          ),
        );
      },
    );
  }
}
