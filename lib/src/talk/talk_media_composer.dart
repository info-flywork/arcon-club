import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'talk_icons.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

class TalkMediaItem {
  TalkMediaItem({required this.path, required this.name, required this.size});
  final String path;
  final String name;
  final int size;
  String get ext {
    final p = name.split('.');
    final e = p.length > 1 ? p.last : 'FILE';
    return (e.length > 4 ? e.substring(0, 4) : e).toUpperCase();
  }

  bool get isImage => const ['PNG', 'JPG', 'JPEG', 'GIF', 'WEBP', 'HEIC'].contains(ext);
  bool get isVideo => const ['MP4', 'MOV', 'WEBM'].contains(ext);
}

class TalkMediaResult {
  const TalkMediaResult(this.items, this.caption);
  final List<TalkMediaItem> items;
  final String caption;
}

/// `#talkMediaComp` — dosya gönderme önizlemesi (koyu tam ekran, açıklama, küçük resimler).
Future<TalkMediaResult?> openTalkMediaComposer(BuildContext context, List<TalkMediaItem> items,
        {required Future<List<TalkMediaItem>> Function() onAddMore}) =>
    Navigator.of(context).push<TalkMediaResult>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MediaComposer(items: items, onAddMore: onAddMore),
    ));

class _MediaComposer extends StatefulWidget {
  const _MediaComposer({required this.items, required this.onAddMore});
  final List<TalkMediaItem> items;
  final Future<List<TalkMediaItem>> Function() onAddMore;

  @override
  State<_MediaComposer> createState() => _MediaComposerState();
}

class _MediaComposerState extends State<_MediaComposer> {
  late final List<TalkMediaItem> _items = [...widget.items];
  final _caption = TextEditingController();
  int _idx = 0;

  static const _bg = Color(0xFF0B141A);
  static const _ink = Color(0xFFE9EDEF);

  /// `#modalMediaDiscard`
  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x8C000000),
      builder: (ctx) => TalkModalCard(title: 'Seçimi iptal et?', message: 'Ekler gönderilmeden silinecek.', actions: [
        TalkButton.ghost('Vazgeç', onPressed: () => Navigator.pop(ctx, false)),
        TalkButton.primary('İptal et', onPressed: () => Navigator.pop(ctx, true)),
      ]),
    );
    if (ok == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cur = _items[_idx.clamp(0, _items.length - 1)];
    final title = _items.length > 1
        ? '${_idx + 1} / ${_items.length}'
        : (cur.isImage ? 'Fotoğraf gönder' : (cur.isVideo ? 'Video gönder' : 'Dosya gönder'));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (did, _) {
        if (!did) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(padding: EdgeInsets.zero, onPressed: _close, icon: const TalkIcon(TalkSvg.x, size: 22, color: _ink), tooltip: 'Kapat'),
                ),
                const SizedBox(width: 12),
                Text(title, style: talkText(16, FontWeight.w600, _ink)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Center(
                  child: cur.isImage
                      ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(File(cur.path), fit: BoxFit.contain))
                      : Container(
                          constraints: const BoxConstraints(minWidth: 220),
                          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
                          decoration: BoxDecoration(color: const Color(0xFF1F2C34), borderRadius: BorderRadius.circular(12)),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 64,
                              height: 64,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: TalkColors.wa, borderRadius: BorderRadius.circular(12)),
                              child: Text(cur.ext, style: talkText(13.6, FontWeight.w800, Colors.white)),
                            ),
                            const SizedBox(height: 10),
                            Text(cur.name, textAlign: TextAlign.center, style: talkText(16, FontWeight.w700, _ink)),
                            const SizedBox(height: 10),
                            Text(talkFmtSize(cur.size), style: talkText(14, FontWeight.w400, _ink)),
                          ]),
                        ),
                ),
              ),
            ),
            Container(
              color: const Color(0xFF111B21),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(color: const Color(0xFF2A3942), borderRadius: BorderRadius.circular(999)),
                      child: TextField(
                        controller: _caption,
                        maxLength: 8000,
                        style: talkText(16, FontWeight.w400, _ink),
                        cursorColor: _ink,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          counterText: '',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: 'Bir mesaj yaz…',
                          hintStyle: talkText(16, FontWeight.w400, const Color(0xFF8696A0)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, TalkMediaResult(_items, _caption.text.trim())),
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: TalkColors.wa, shape: BoxShape.circle),
                      child: const TalkIcon(TalkSvg.send, size: 22, color: Colors.white),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                  for (var i = 0; i < _items.length; i++)
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(clipBehavior: Clip.none, children: [
                        GestureDetector(
                          onTap: () => setState(() => _idx = i),
                          child: Container(
                            width: 52,
                            height: 52,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A3942),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: i == _idx ? TalkColors.wa : Colors.transparent, width: 2),
                            ),
                            child: _items[i].isImage
                                ? Image.file(File(_items[i].path), fit: BoxFit.cover)
                                : Center(child: Text(_items[i].ext, style: talkText(10.4, FontWeight.w800, Colors.white))),
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: GestureDetector(
                            onTap: () {
                              if (_items.length == 1) {
                                _close();
                                return;
                              }
                              setState(() {
                                _items.removeAt(i);
                                if (_idx >= _items.length) _idx = _items.length - 1;
                              });
                            },
                            child: Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFF111111),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 1))],
                              ),
                              child: Text('×', style: talkText(14, FontWeight.w700, Colors.white, height: 1)),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  GestureDetector(
                    onTap: () async {
                      final more = await widget.onAddMore();
                      if (more.isNotEmpty) setState(() => _items.addAll(more.take(12 - _items.length)));
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0x59FFFFFF)),
                      ),
                      child: Text('+', style: talkText(22.4, FontWeight.w400, _ink)),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      ),
    );
  }
}
