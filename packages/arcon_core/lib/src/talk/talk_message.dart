import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'talk_api.dart';
import 'talk_icons.dart';
import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// WhatsApp iOS balonu: 18 köşe; kuyruklu balonda alt köşeden dışarı kıvrılan uç (kendi mesajında sağda).
class TalkBubbleShape extends ShapeBorder {
  const TalkBubbleShape({required this.mine, this.tail = true});
  final bool mine;
  final bool tail;

  static const _r = 18.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = math.min(_r, math.min(rect.width, rect.height) / 2);
    if (!tail) return Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
    // kuyruk sağda çizilir, gelen mesajda yatay aynalanır
    final w = rect.width, h = rect.height;
    final p = Path()
      ..moveTo(r, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, h - 14)
      ..cubicTo(w, h - 5, w + 2.5, h - 1, w + 6.5, h - 0.2)
      ..cubicTo(w + 2, h + 0.6, w - 4, h, w - 10, h - 1.2)
      ..cubicTo(w - 13, h, w - 15, h, w - r, h)
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
    final m = mine ? Matrix4.translationValues(rect.left, rect.top, 0) : (Matrix4.translationValues(rect.right, rect.top, 0)..scale(-1.0, 1.0));
    return p.transform(m.storage);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) => other is TalkBubbleShape && other.mine == mine && other.tail == tail;

  @override
  int get hashCode => Object.hash(mine, tail);
}

const talkQuickReact = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏'];

/// Emojiler uygulama yazı tipinde yok: sistem emoji yazı tipine düşsün (iOS / Android).
const talkEmojiFonts = ['Apple Color Emoji', 'Noto Color Emoji'];

/// Tek mesaj balonu (WhatsApp düzeni; grupta başkalarının mesajında avatar + isim).
class TalkMessageView extends StatelessWidget {
  const TalkMessageView({
    super.key,
    required this.message,
    required this.mine,
    required this.api,
    required this.maxWidth,
    required this.onMenu,
    required this.onReact,
    required this.onReplyTap,
    this.onUserTap,
    this.onSwipeReply,
    this.onSelect,
    this.onLongMenu,
    this.onForward,
    this.tick = TalkTick.sent,
    this.editing = false,
    this.onEditSave,
    this.onEditCancel,
    this.group = true,
    this.tail = true,
  });

  final TalkMessage message;
  /// Balon kuyruğu (WhatsApp: art arda mesajların yalnızca sonuncusunda)
  final bool tail;
  /// WhatsApp: birebir sohbette isim ve avatar yok; grupta yalnızca başkalarının mesajında var.
  final bool group;
  final bool mine;
  final TalkApi api;
  final double maxWidth;
  final void Function(Offset globalPos) onMenu;
  final void Function(String emoji) onReact;
  final void Function(int messageId) onReplyTap;
  /// Avatar / isim: kişi bilgisi
  final VoidCallback? onUserTap;
  /// Balonu sağdan sola kaydırınca yanıtla
  final VoidCallback? onSwipeReply;
  /// WhatsApp gibi basılı tutunca çoklu seçim başlar (verilmezse menü açılır)
  final VoidCallback? onSelect;
  /// Basılı tutunca WhatsApp menüsü: balonun ekrandaki yeri ve kopyası (menüde öne çıkar)
  final void Function(Rect rect, Widget preview)? onLongMenu;
  /// Görsel / dosya / videoda balonun yanındaki ilet
  final VoidCallback? onForward;
  /// kendi mesajında WhatsApp tikleri: saat → tek tik → çift gri → çift mavi
  final TalkTick tick;
  final bool editing;
  final void Function(String body)? onEditSave;
  final VoidCallback? onEditCancel;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final m = message;
    final text = m.text;
    final images = m.attachments.where((a) => a.isImage).toList();
    final others = m.attachments.where((a) => !a.isImage).toList();
    final gifs = m.gifs;
    final chips = m.chips;
    final mediaOnly = text.isEmpty && chips.isEmpty && (gifs.isNotEmpty || images.isNotEmpty) && others.isEmpty;
    final gifOnly = gifs.isNotEmpty && text.isEmpty && chips.isEmpty && images.isEmpty && others.isEmpty;
    final ink = mine ? c.bubbleOutInk : c.bubbleInInk;
    final onMedia = gifOnly || (mediaOnly && images.isNotEmpty);
    final bubbleBg = mediaOnly || gifOnly ? Colors.transparent : (mine ? c.bubbleOut : c.bubbleIn);
    Widget avatar = TalkAvatar.hue(name: m.displayName.isEmpty ? m.username : m.displayName, seed: m.userId, photoUrl: api.fileUrl(m.avatarPath));
    if (onUserTap != null) {
      avatar = GestureDetector(onTap: onUserTap, child: avatar);
    }

    final foot = Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
      if (m.expiresAt.isNotEmpty) ...[
        Opacity(opacity: 0.75, child: Text('⏱', style: talkText(11.52, FontWeight.w400, ink, height: 1))),
        const SizedBox(width: 4),
      ],
      if (m.edited) ...[
        Opacity(opacity: 0.65, child: Text('düzenlendi', style: talkText(10.88, FontWeight.w400, ink).copyWith(fontStyle: FontStyle.italic))),
        const SizedBox(width: 4),
      ],
      Opacity(
        opacity: mine ? 0.55 : 1,
        child: Text(talkClock(m.createdAt), style: talkText(10.88, FontWeight.w400, mine ? c.bubbleOutInk : c.time, height: 1)),
      ),
      if (mine) ...[
        const SizedBox(width: 4),
        _TickMark(tick: tick, color: ink),
      ],
    ]);

    final mediaFoot = Row(mainAxisSize: MainAxisSize.min, children: [
      Opacity(
        opacity: 0.95,
        child: Text(talkClock(m.createdAt),
            style: talkText(10.88, FontWeight.w400, Colors.white, height: 1)
                .copyWith(shadows: const [Shadow(color: Color(0x8C000000), blurRadius: 2, offset: Offset(0, 1))])),
      ),
      if (mine) ...[
        const SizedBox(width: 4),
        _TickMark(tick: tick, color: Colors.white, onMedia: true),
      ],
    ]);

    // basılı tutunca menüde balonun anlık görüntüsü öne çıkar (canlı kopya oynatıcı gibi öğelerde bozuluyordu)
    final bubble = Builder(
      builder: (bctx) => RepaintBoundary(child: GestureDetector(
      // dokununca mesajın yanında liste açılır; basılı tutunca WhatsApp menüsü (bağlantı, görsel gibi iç dokunuşlar önceliklidir)
      onTapUp: editing ? null : (d) => onMenu(d.globalPosition),
      onLongPressStart: editing
          ? null
          : (d) async {
              final box = bctx.findRenderObject();
              if (onLongMenu != null && box is RenderRepaintBoundary && box.hasSize) {
                HapticFeedback.mediumImpact();
                final rect = box.localToGlobal(Offset.zero) & box.size;
                Widget preview = SizedBox(width: rect.width, height: rect.height);
                try {
                  final img = await box.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(bctx));
                  preview = RawImage(image: img, width: rect.width, height: rect.height, fit: BoxFit.fill);
                } catch (_) {
                  // görüntü alınamazsa menü yine açılır
                }
                onLongMenu!(rect, preview);
              } else if (onSelect != null) {
                onSelect!();
              } else {
                onMenu(d.globalPosition);
              }
            },
      child: Container(
        padding: gifOnly
            ? EdgeInsets.zero
            : (mediaOnly ? const EdgeInsets.fromLTRB(4, 2, 4, 16) : const EdgeInsets.fromLTRB(12, 8, 12, 6)),
        decoration: ShapeDecoration(
          color: bubbleBg,
          shape: TalkBubbleShape(mine: mine, tail: tail && !mediaOnly && !gifOnly),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (!mine && group)
              Padding(
                padding: const EdgeInsets.only(right: 18),
                child: GestureDetector(
                  onTap: onUserTap,
                  child: Text(m.displayName.isEmpty ? m.username : m.displayName, style: talkText(13.12, FontWeight.w700, c.name, height: 1.5)),
                ),
              ),
            if (m.reply != null) _ReplyQuote(reply: m.reply!, mine: mine, onTap: () => onReplyTap(m.reply!.id)),
            if (images.isNotEmpty || others.isNotEmpty || gifs.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: text.isNotEmpty || chips.isNotEmpty || editing ? 6 : 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (images.length == 1) _SingleImage(api: api, a: images.first, maxWidth: maxWidth - 24),
                  if (images.length > 1) _ImageGrid(api: api, images: images, width: maxWidth - 24),
                  for (final a in others)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: a.isAudio
                          ? TalkVoicePlayer(url: api.fileUrl(a.path), ink: ink)
                          : (a.isVideo ? _VideoTile(api: api, a: a, width: maxWidth - 24) : TalkFileCard(api: api, a: a, mine: mine)),
                    ),
                  for (final g in gifs)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: TalkNetImage(g, fit: BoxFit.cover, decodeWidth: 280, error: const SizedBox(width: 120, height: 80)),
                      ),
                    ),
                ]),
              ),
            if (editing)
              _EditBox(initial: m.body, mine: mine, onSave: onEditSave!, onCancel: onEditCancel!)
            else if (text.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(images.isNotEmpty || others.isNotEmpty || gifs.isNotEmpty ? 8 : 0, 0, mine || m.reply != null ? 16 : 0, 0),
                child: _MentionText(text: text, style: talkText(14.72, FontWeight.w400, ink, height: 1.45), c: c),
              ),
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final ch in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      // `.talk-chip`: var(--talk-chip-bg) / var(--talk-chip-ink) — balon rengi ne olursa olsun aynı
                      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(999)),
                      child: Text(ch, style: talkText(12, FontWeight.w700, c.accentContrast)),
                    ),
                ]),
              ),
            if (m.reactions.where((r) => r.count > 0).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final r in m.reactions.where((r) => r.count > 0))
                    GestureDetector(
                      onTap: () => onReact(r.emoji),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: r.mine
                              ? TalkColors.reactMine.withValues(alpha: 0.15)
                              : (c.dark ? const Color(0x2E000000) : const Color(0xB3FFFFFF)),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: r.mine ? TalkColors.reactMine : c.line),
                        ),
                        child: Text('${r.emoji} ${r.count}', style: talkText(12.48, FontWeight.w400, ink, height: 1.4)),
                      ),
                    ),
                ]),
              ),
            if (!onMedia)
              Padding(padding: const EdgeInsets.only(top: 2), child: Align(alignment: Alignment.centerRight, child: foot)),
          ]),
          if (onMedia)
            Positioned(
              right: 8,
              bottom: gifOnly ? 6 : -10,
              child: DefaultTextStyle.merge(
                style: const TextStyle(shadows: [Shadow(color: Color(0x8C000000), blurRadius: 2, offset: Offset(0, 1))]),
                child: mediaFoot,
              ),
            ),
        ]),
      ),
      )),
    );

    final hasFwdMedia = images.isNotEmpty || gifs.isNotEmpty || others.any((a) => !a.isAudio);
    final showFwd = onForward != null && m.id > 0 && hasFwdMedia;
    Widget fwdBtn() {
      final bg = c.dark ? const Color(0xFF2A3942) : const Color(0xFFECECEC);
      return Tooltip(
        message: 'İlet',
        child: GestureDetector(
          onTap: onForward,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Icon(Icons.shortcut_rounded, size: 18, color: c.dark ? const Color(0xFFD1D7DB) : const Color(0xFF54656F)),
          ),
        ),
      );
    }

    final row = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 80),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!mine && group) ...[avatar, const SizedBox(width: 8)],
            if (mine && showFwd) ...[fwdBtn(), const SizedBox(width: 6)],
            Flexible(child: bubble),
            if (!mine && showFwd) ...[const SizedBox(width: 6), fwdBtn()],
          ],
        ),
      ),
    );
    if (onSwipeReply == null || editing) return row;
    return _SwipeToReply(onReply: onSwipeReply!, child: row);
  }
}

/// Sesli mesaj: oynat/durdur, ilerleme çubuğu ve süre.
class TalkVoicePlayer extends StatefulWidget {
  const TalkVoicePlayer({super.key, required this.url, required this.ink});
  final String url;
  final Color ink;

  @override
  State<TalkVoicePlayer> createState() => _TalkVoicePlayerState();
}

class _TalkVoicePlayerState extends State<TalkVoicePlayer> {
  final _p = AudioPlayer();
  final _subs = <StreamSubscription<Object?>>[];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  Uint8List? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_p.onPlayerStateChanged.listen((s) => setState(() => _state = s)))
      ..add(_p.onPositionChanged.listen((d) => setState(() => _pos = d)))
      ..add(_p.onDurationChanged.listen((d) => setState(() => _dur = d)))
      ..add(_p.onPlayerComplete.listen((_) => setState(() => _pos = Duration.zero)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _p.pause();
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      if (_bytes == null) {
        final r = await http.get(Uri.parse(widget.url));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) return;
        _bytes = r.bodyBytes;
      }
      await _p.setAudioContext(AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      ));
      await _p.play(BytesSource(_bytes!, mimeType: 'audio/mp4'), position: _pos);
    } catch (e) {
      debugPrint('[voice] $e');
    } finally {
      _busy = false;
    }
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    final total = _dur.inMilliseconds;
    return SizedBox(
      width: 230,
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34, color: widget.ink),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: TalkColors.ticks,
              inactiveTrackColor: widget.ink.withValues(alpha: 0.25),
              thumbColor: TalkColors.ticks,
            ),
            child: Slider(
              value: total <= 0 ? 0 : (_pos.inMilliseconds / total).clamp(0.0, 1.0),
              onChanged: total <= 0 ? null : (v) => _p.seek(Duration(milliseconds: (v * total).round())),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(_fmt(playing || _pos > Duration.zero ? _pos : _dur), style: talkText(11.5, FontWeight.w500, widget.ink.withValues(alpha: 0.75))),
      ]),
    );
  }
}

/// Mesajı sağa çekince yanıt ikonu belirir; eşiği geçip bırakınca yanıtlanır.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.onReply, required this.child});
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  static const _max = 80.0;
  static const _trigger = 56.0;
  late final AnimationController _back;
  double _dx = 0;
  double _from = 0;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() {
        if (!mounted) return;
        setState(() => _dx = _from * (1 - Curves.easeOut.transform(_back.value)));
      });
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    _back.stop();
    // balon sağdan sola çekilir (_dx = sola çekilen mesafe)
    final next = (_dx - d.delta.dx).clamp(0.0, _max);
    if (!_armed && next >= _trigger) {
      _armed = true;
      HapticFeedback.lightImpact();
    } else if (_armed && next < _trigger) {
      _armed = false;
    }
    setState(() => _dx = next);
  }

  void _end([DragEndDetails? _]) {
    if (_armed) widget.onReply();
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final p = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(alignment: Alignment.centerRight, children: [
        if (_dx > 0)
          Positioned(
            right: 4,
            child: Opacity(
              opacity: p,
              child: Transform.scale(
                scale: 0.6 + 0.4 * p,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.accentSoft, shape: BoxShape.circle),
                  child: TalkIcon(TalkSvg.reply, size: 16, color: c.ink),
                ),
              ),
            ),
          ),
        Transform.translate(offset: Offset(-_dx, 0), child: widget.child),
      ]),
    );
  }
}

/// @Ad Soyad → `.talk-mention`; bağlantılar tıklanınca tarayıcıda açılır.
class _MentionText extends StatefulWidget {
  const _MentionText({required this.text, required this.style, required this.c});
  final String text;
  final TextStyle style;
  final TalkColors c;

  @override
  State<_MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<_MentionText> {
  static final _re = RegExp(r'(https?://[^\s<>"]+|www\.[^\s<>"]+)|@([A-Za-zÇĞİÖŞÜçğıöşü0-9_]+(?:\s+[A-Za-zÇĞİÖŞÜçğıöşü0-9_]+)?)');
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  void _open(String raw) {
    // cümle sonundaki noktalama bağlantıya dahil değil
    final link = raw.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
    final uri = Uri.tryParse(link.startsWith('http') ? link : 'https://$link');
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final text = widget.text;
    final style = widget.style;
    final c = widget.c;
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _re.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      final url = m.group(1);
      if (url != null) {
        final tap = TapGestureRecognizer()..onTap = () => _open(url);
        _taps.add(tap);
        spans.add(TextSpan(
          text: url,
          recognizer: tap,
          style: TextStyle(color: c.dark ? const Color(0xFF53BDEB) : const Color(0xFF027EB5), decoration: TextDecoration.underline),
        ));
      } else {
        spans.add(TextSpan(
          text: m.group(0)!,
          style: style.copyWith(fontWeight: FontWeight.w600, color: style.color),
        ));
      }
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// `.talk-reply-quote`
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.reply, required this.mine, required this.onTap});
  final TalkReply reply;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = mine ? c.bubbleOutInk : c.bubbleInInk;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: mine ? const Color(0x1A000000) : (c.dark ? const Color(0x1F000000) : const Color(0x0F000000)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: mine ? const Color(0x8CFFFFFF) : TalkColors.ticks),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(reply.displayName.isEmpty ? 'Mesaj' : reply.displayName,
                      style: talkText(12.48, FontWeight.w600, mine ? const Color(0xEBFFFFFF) : TalkColors.ticks)),
                  const SizedBox(height: 1),
                  Opacity(
                    opacity: 0.85,
                    child: Text(reply.body.isEmpty ? 'Mesaj' : reply.body,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(12.48, FontWeight.w400, ink)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `.talk-msg-edit`
class _EditBox extends StatefulWidget {
  const _EditBox({required this.initial, required this.mine, required this.onSave, required this.onCancel});
  final String initial;
  final bool mine;
  final void Function(String) onSave;
  final VoidCallback onCancel;

  @override
  State<_EditBox> createState() => _EditBoxState();
}

class _EditBoxState extends State<_EditBox> {
  late final _t = TextEditingController(text: widget.initial);
  final _f = FocusNode();

  @override
  void initState() {
    super.initState();
    // web: ta.focus() + imleç sona
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _f.requestFocus();
      _t.selection = TextSelection.collapsed(offset: _t.text.length);
    });
  }

  @override
  void dispose() {
    _f.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        TextField(
          controller: _t,
          focusNode: _f,
          minLines: 2,
          maxLines: 6,
          maxLength: 8000,
          style: talkText(14.72, FontWeight.w400, c.dark ? Colors.white : const Color(0xFF111111)),
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            filled: true,
            fillColor: c.dark ? const Color(0x2E000000) : const Color(0xD9FFFFFF),
            contentPadding: const EdgeInsets.all(8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.dark ? const Color(0x33FFFFFF) : const Color(0x1F000000))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.dark ? const Color(0x33FFFFFF) : const Color(0x1F000000))),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _pill('İptal', const Color(0x33808080), widget.mine ? c.bubbleOutInk : c.bubbleInInk, widget.onCancel),
          const SizedBox(width: 8),
          _pill('Kaydet', c.dark ? const Color(0xFFE8EEFC) : Colors.white, const Color(0xFF111111), () => widget.onSave(_t.text)),
        ]),
      ]),
    );
  }

  Widget _pill(String t, Color bg, Color fg, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(t, style: talkText(13.12, FontWeight.w700, fg)),
        ),
      );
}

class _SingleImage extends StatelessWidget {
  const _SingleImage({required this.api, required this.a, required this.maxWidth});
  final TalkApi api;
  final TalkAttachment a;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final url = api.fileUrl(a.path);
    return GestureDetector(
      onTap: () => openTalkImage(context, url, a.origName),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth > 420 ? 420 : maxWidth, maxHeight: MediaQuery.sizeOf(context).height * 0.72),
          child: Container(
            color: const Color(0xFF0B141A),
            child: TalkNetImage(api.thumbUrl(a.path, width: 960), fallbackUrl: url, fit: BoxFit.contain, decodeWidth: maxWidth > 420 ? 420 : maxWidth, error: const SizedBox(width: 160, height: 120)),
          ),
        ),
      ),
    );
  }
}

/// `.talk-img-grid--n2/n3/n4` (+N kaplaması)
class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.api, required this.images, required this.width});
  final TalkApi api;
  final List<TalkAttachment> images;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = width > 420 ? 420.0 : width;
    final shown = images.take(4).toList();
    final extra = images.length > 4 ? images.length - 4 : 0;
    Widget cell(int i, {double? aspect}) {
      final a = shown[i];
      final url = api.fileUrl(a.path);
      final img = Stack(fit: StackFit.expand, children: [
        TalkNetImage(api.thumbUrl(a.path), fallbackUrl: url, fit: BoxFit.cover, decodeWidth: w / 2),
        if (extra > 0 && i == 3)
          Container(
            color: const Color(0x8C0B141A),
            alignment: Alignment.center,
            child: Text('+$extra', style: talkText(25.6, FontWeight.w700, Colors.white)),
          ),
      ]);
      return GestureDetector(
        onTap: () => openTalkGallery(context, [for (final x in images) (api.fileUrl(x.path), x.origName)], initial: i),
        child: AspectRatio(aspectRatio: aspect ?? 1, child: Container(color: const Color(0xFF111B21), child: img)),
      );
    }

    const gap = 3.0;
    final rows = <Widget>[];
    if (shown.length == 3) {
      rows.add(cell(0, aspect: 16 / 10));
      rows.add(const SizedBox(height: gap));
      rows.add(Row(children: [Expanded(child: cell(1)), const SizedBox(width: gap), Expanded(child: cell(2))]));
    } else {
      for (var i = 0; i < shown.length; i += 2) {
        if (i > 0) rows.add(const SizedBox(height: gap));
        rows.add(Row(children: [
          Expanded(child: cell(i)),
          const SizedBox(width: gap),
          Expanded(child: i + 1 < shown.length ? cell(i + 1) : const SizedBox()),
        ]));
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(width: w, color: const Color(0x40000000), child: Column(children: rows)),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.api, required this.a, required this.width});
  final TalkApi api;
  final TalkAttachment a;
  final double width;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => launchUrl(Uri.parse(api.fileUrl(a.path)), mode: LaunchMode.externalApplication),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: width > 420 ? 420 : width,
            height: 180,
            color: const Color(0xFF0B141A),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 48),
              const SizedBox(height: 6),
              Text(a.origName, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(12, FontWeight.w600, Colors.white70)),
            ]),
          ),
        ),
      );
}

/// `.talk-file` — uzantı rozeti, ad, boyut, indirme ikonu
class TalkFileCard extends StatelessWidget {
  const TalkFileCard({super.key, required this.api, required this.a, this.mine = false});
  final TalkApi api;
  final TalkAttachment a;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    // arcon-talk-demo.css: .talk-file / html:not(.dark) .talk-msg.is-mine .talk-file / html.dark .talk-msg.is-mine .talk-file
    final (Color bg, Color border, Color ink, Color sub, Color icoBg, Color icoInk) = switch ((c.dark, mine)) {
      (false, true) => (const Color(0x14FFFFFF), const Color(0x29FFFFFF), Colors.white, const Color(0xB3FFFFFF), Colors.white, const Color(0xFF111111)),
      (true, true) => (const Color(0x0F000000), const Color(0x1A000000), const Color(0xFF111111), c.muted, const Color(0xFF111111), Colors.white),
      (false, false) => (const Color(0xFFFAFAFA), c.line, c.bubbleInInk, c.muted, c.accent, c.accentContrast),
      (true, false) => (const Color(0x2E000000), const Color(0x14FFFFFF), c.bubbleInInk, c.muted, c.accent, c.accentContrast),
    };
    final dl = mine && !c.dark ? const Color(0xB3FFFFFF) : const Color(0xFF8696A0);
    return GestureDetector(
      onTap: () => openTalkFile(context, api.fileUrl(a.path), a.origName),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: icoBg, borderRadius: BorderRadius.circular(10)),
            child: Text(a.ext, style: talkText(10.88, FontWeight.w800, icoInk)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.origName, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(14.08, FontWeight.w700, ink)),
              const SizedBox(height: 2),
              Text(talkFmtSize(a.sizeBytes), style: talkText(11.84, FontWeight.w400, sub)),
            ]),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 36, height: 36, child: Center(child: TalkIcon(TalkSvg.download, size: 16, color: dl))),
        ]),
      ),
    );
  }
}

void openTalkImage(BuildContext context, String url, String name) => openTalkGallery(context, [(url, name)]);

/// Tam ekran görsel: çoklu fotoğrafta sağa sola kaydırılır, üstte "2 / 5".
void openTalkGallery(BuildContext context, List<(String, String)> images, {int initial = 0}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _TalkGallery(images: images, initial: initial)));

class _TalkGallery extends StatefulWidget {
  const _TalkGallery({required this.images, required this.initial});
  final List<(String, String)> images;
  final int initial;

  @override
  State<_TalkGallery> createState() => _TalkGalleryState();
}

class _TalkGalleryState extends State<_TalkGallery> {
  late int _i = widget.initial.clamp(0, widget.images.length - 1);
  late final _pages = PageController(initialPage: _i);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.images[_i];
    final many = widget.images.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(many ? '${_i + 1} / ${widget.images.length}' : cur.$2, style: talkText(15, FontWeight.w600, Colors.white)),
        actions: [IconButton(icon: const TalkIcon(TalkSvg.download, size: 20, color: Colors.white), onPressed: () => openTalkFile(context, cur.$1, cur.$2))],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (_, i) => InteractiveViewer(maxScale: 5, child: Center(child: TalkNetImage(widget.images[i].$1, fit: BoxFit.contain, placeholder: Colors.black))),
      ),
    );
  }
}

/// Dosyayı indirip telefonun ilgili uygulamasında aç (web: `download` linki).
Future<void> openTalkFile(BuildContext context, String url, String name) async {
  try {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('${res.statusCode}');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${name.replaceAll(RegExp(r'[/\\]'), '_')}');
    await f.writeAsBytes(res.bodyBytes);
    await OpenFilex.open(f.path);
  } on Exception {
    if (context.mounted) talkToast(context, 'Dosya açılamadı', error: true);
  }
}

/// Mesaj menüsü — WhatsApp: bulanık arka plan, üstte hızlı tepkiler, yanda işlem listesi.
/// [decided]: grupta Kararlar/Görevler menüsü (null: gösterme; true: zaten karar).
Future<String?> showTalkMessageMenu(
  BuildContext context, {
  required bool mine,
  required bool canCopy,
  bool canForward = true,
  bool canEdit = false,
  bool? decided,
  Offset? at,
  bool canTask = false,
  bool canAskAi = false,
  Rect? rect,
  Widget? preview,
}) {
  final main = <(String, IconData, String, bool)>[
    ('reply', CupertinoIcons.reply, 'Cevapla', false),
    if (canForward) ('forward', CupertinoIcons.arrowshape_turn_up_right, 'İlet', false),
    if (canCopy) ('copy', CupertinoIcons.doc_on_doc, 'Kopyala', false),
    if (canEdit) ('edit', CupertinoIcons.pencil, 'Düzenle', false),
    if (canAskAi) ('ask-ai', CupertinoIcons.sparkles, "ARCON AI'a Sor", false),
    if (mine) ('delete', CupertinoIcons.trash, 'Sil', true),
  ];
  final extra = <(String, IconData, String, bool)>[
    if (canTask) ('task', CupertinoIcons.checkmark_square, 'Görev olarak ekle', false),
    if (decided != null) ('decision', CupertinoIcons.flag, decided ? 'Kararı kaldır' : 'Karar olarak ekle', false),
    if (mine) ('info', CupertinoIcons.info_circle, 'Bilgi', false),
    ('select', CupertinoIcons.checkmark_circle, 'Seç', false),
  ];
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => rect != null && preview != null
        ? _TalkLongMenu(mine: mine, rect: rect, preview: preview, main: main, extra: extra)
        : _TalkMsgMenu(
            mine: mine,
            at: at,
            main: main,
            extra: extra,
          ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child),
    ),
  );
}

class _TalkMsgMenu extends StatefulWidget {
  const _TalkMsgMenu({required this.mine, required this.main, required this.extra, this.at});
  final bool mine;
  final Offset? at;
  final List<(String, IconData, String, bool)> main;
  final List<(String, IconData, String, bool)> extra;

  @override
  State<_TalkMsgMenu> createState() => _TalkMsgMenuState();
}

class _TalkMsgMenuState extends State<_TalkMsgMenu> {
  var _more = false;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    const width = 268.0;
    const rowH = 46.0;
    final rows = [...widget.main, if (_more) ...widget.extra];
    final moreRow = !_more && widget.extra.isNotEmpty;
    final height = (rows.length + (moreRow ? 1 : 0)) * rowH + 56;
    final p = widget.at ?? Offset(size.width / 2, size.height / 2);
    var top = p.dy + 8;
    if (top + height > size.height - pad.bottom - 12) top = p.dy - height - 8;
    top = top.clamp(pad.top + 12, (size.height - pad.bottom - height - 12).clamp(pad.top + 12, size.height)).toDouble();
    final left = widget.mine ? null : 16.0;
    final right = widget.mine ? 16.0 : null;
    final ink = c.dark ? const Color(0xFFF2F2F7) : const Color(0xFF111111);
    final card = c.dark ? const Color(0xF22C2C2E) : const Color(0xF7F4F4F8);
    Widget row((String, IconData, String, bool) it, {VoidCallback? onTap}) {
      final (act, icon, label, danger) = it;
      return InkWell(
        onTap: onTap ?? () => Navigator.pop(context, act),
        child: SizedBox(
          height: rowH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(icon, size: 20, color: danger ? TalkColors.dangerSolid : ink),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: talkText(16.5, FontWeight.w400, danger ? TalkColors.dangerSolid : ink))),
            ]),
          ),
        ),
      );
    }

    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: ColoredBox(color: c.dark ? const Color(0x66000000) : const Color(0x33000000)),
          ),
        ),
      ),
      Positioned(
        left: left,
        right: right,
        top: top,
        child: Column(crossAxisAlignment: widget.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Material(
            color: card,
            elevation: 10,
            shadowColor: const Color(0x33000000),
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 4, 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final e in talkQuickReact)
                  InkWell(
                    onTap: () => Navigator.pop(context, 'react:$e'),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Text(e, style: const TextStyle(fontSize: 21, fontFamilyFallback: talkEmojiFonts))),
                  ),
                InkWell(
                  onTap: () => Navigator.pop(context, 'react-more'),
                  child: Container(
                    width: 26,
                    height: 26,
                    margin: const EdgeInsets.only(left: 2, right: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.dark ? const Color(0x33FFFFFF) : const Color(0x14000000),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(CupertinoIcons.add, size: 15, color: ink),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: width,
            child: Material(
            color: card,
            elevation: 12,
            shadowColor: const Color(0x40000000),
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 4),
              for (final it in rows) row(it),
              if (moreRow) ...[
                Divider(height: 1, thickness: 0.5, color: c.dark ? const Color(0x33FFFFFF) : const Color(0x1A000000)),
                row(('more', CupertinoIcons.ellipsis_circle, 'Daha fazla...', false), onTap: () => setState(() => _more = true)),
              ],
              const SizedBox(height: 4),
            ]),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// Basılı tutunca (WhatsApp iOS): arka plan bulanık, basılan mesaj öne çıkar; üstünde büyük tepki çubuğu,
/// altında işlem listesi. Ekrana sığmazsa üçü birlikte kaydırılır.
class _TalkLongMenu extends StatefulWidget {
  const _TalkLongMenu({required this.mine, required this.rect, required this.preview, required this.main, required this.extra});
  final bool mine;
  final Rect rect;
  final Widget preview;
  final List<(String, IconData, String, bool)> main;
  final List<(String, IconData, String, bool)> extra;

  @override
  State<_TalkLongMenu> createState() => _TalkLongMenuState();
}

class _TalkLongMenuState extends State<_TalkLongMenu> {
  var _more = false;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    const barH = 62.0;
    const rowH = 56.0;
    const gap = 10.0;
    final menuW = math.min(300.0, size.width - 32);
    final rows = [...widget.main, if (_more) ...widget.extra];
    final moreRow = !_more && widget.extra.isNotEmpty;
    final menuH = rows.length * rowH + (moreRow ? rowH + 1 : 0) + 12;
    final ink = c.dark ? const Color(0xFFF2F2F7) : const Color(0xFF111111);
    final card = c.dark ? const Color(0xF22C2C2E) : const Color(0xF2F6F6F9);

    // mesaj çok uzunsa kopyası kısaltılır; grup ekrana sığacak şekilde yukarı/aşağı kayar
    final avail = size.height - pad.top - pad.bottom - 24;
    final msgH = math.min(widget.rect.height, math.max(80.0, avail - barH - menuH - gap * 2));
    final total = barH + gap + msgH + gap + menuH;
    final minTop = pad.top + 12;
    final maxTop = math.max(minTop, size.height - pad.bottom - 12 - total);
    final top = (widget.rect.top - barH - gap).clamp(minTop, maxTop).toDouble();
    final msgTop = top + barH + gap;
    final menuTop = msgTop + msgH + gap;

    final side = widget.mine ? size.width - widget.rect.right : widget.rect.left;
    final edge = math.max(12.0, side);

    Widget row((String, IconData, String, bool) it, {VoidCallback? onTap}) {
      final (act, icon, label, danger) = it;
      final color = danger ? TalkColors.dangerSolid : ink;
      return InkWell(
        onTap: onTap ?? () => Navigator.pop(context, act),
        child: SizedBox(
          height: rowH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(children: [
              Icon(icon, size: 23, color: color),
              const SizedBox(width: 18),
              Expanded(child: Text(label, style: talkText(18, FontWeight.w400, color))),
            ]),
          ),
        ),
      );
    }

    // Material: metin stili ve emoji yazı tipi doğru gelsin
    return Material(type: MaterialType.transparency, child: Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: ColoredBox(color: c.dark ? const Color(0x59000000) : const Color(0x1F000000)),
          ),
        ),
      ),
      // tepki çubuğu
      Positioned(
        top: top,
        left: widget.mine ? null : edge,
        right: widget.mine ? edge : null,
        child: Container(
          height: barH,
          constraints: BoxConstraints(maxWidth: size.width - 24),
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 20, offset: Offset(0, 6))],
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final e in talkQuickReact)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, 'react:$e'),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(e, style: const TextStyle(fontSize: 30, height: 1.1, fontFamilyFallback: talkEmojiFonts))),
              ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => Navigator.pop(context, 'react-more'),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.dark ? const Color(0x33FFFFFF) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.dark ? const Color(0x22FFFFFF) : const Color(0x14000000)),
                ),
                child: Icon(CupertinoIcons.add, size: 22, color: ink),
              ),
            ),
          ])),
        ),
      ),
      // basılan mesaj (dokunulmaz kopya)
      Positioned(
        top: msgTop,
        left: widget.rect.left,
        width: widget.rect.width,
        height: msgH,
        child: IgnorePointer(
          child: ClipRect(
            child: OverflowBox(alignment: Alignment.topLeft, maxHeight: widget.rect.height, child: SizedBox(width: widget.rect.width, child: widget.preview)),
          ),
        ),
      ),
      // işlem listesi
      Positioned(
        top: menuTop,
        left: widget.mine ? null : edge,
        right: widget.mine ? edge : null,
        width: menuW,
        child: Material(
          color: card,
          elevation: 14,
          shadowColor: const Color(0x40000000),
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 6),
            for (final it in rows) row(it),
            if (moreRow) ...[
              Divider(height: 1, thickness: 0.6, indent: 22, endIndent: 22, color: c.dark ? const Color(0x33FFFFFF) : const Color(0x1F000000)),
              row(('more', CupertinoIcons.ellipsis_circle, 'Daha fazla...', false), onTap: () => setState(() => _more = true)),
            ],
            const SizedBox(height: 6),
          ]),
        ),
      ),
    ]));
  }
}

/// Emoji seçici (`emoji-picker-element` karşılığı) — seçilen emojiyi döner.
Future<String?> showTalkEmojiPicker(BuildContext context) {
  final c = TalkColors.of(context);
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: c.dark ? const Color(0xFF1F2C34) : Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    builder: (ctx) => SizedBox(
      height: 340,
      child: EmojiPicker(
        onEmojiSelected: (_, e) => Navigator.pop(ctx, e.emoji),
        config: talkEmojiConfig(c),
      ),
    ),
  );
}

Config talkEmojiConfig(TalkColors c) => Config(
      emojiViewConfig: EmojiViewConfig(
        backgroundColor: c.dark ? const Color(0xFF1F2C34) : Colors.white,
        emojiSizeMax: 24,
        columns: 8,
      ),
      categoryViewConfig: CategoryViewConfig(
        backgroundColor: c.dark ? const Color(0xFF1F2C34) : Colors.white,
        indicatorColor: TalkColors.wa,
        iconColorSelected: TalkColors.wa,
        iconColor: c.dark ? const Color(0xFF8696A0) : const Color(0xFF667781),
      ),
      bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
      searchViewConfig: SearchViewConfig(backgroundColor: c.dark ? const Color(0xFF1F2C34) : Colors.white),
    );

/// Kendi mesajının durumu (WhatsApp): gönderiliyor, sunucuya ulaştı, karşıya iletildi, okundu, gönderilemedi.
enum TalkTick { pending, sent, delivered, read, failed }

class _TickMark extends StatelessWidget {
  const _TickMark({required this.tick, required this.color, this.onMedia = false});

  final TalkTick tick;
  final Color color;
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final dim = onMedia ? 0.95 : 0.6;
    return switch (tick) {
      TalkTick.pending => Opacity(opacity: dim, child: TalkIcon(TalkSvg.pendingClock, size: 12, color: color)),
      TalkTick.sent => Opacity(opacity: dim, child: TalkIcon(TalkSvg.tick, width: 16, height: 11, color: color)),
      TalkTick.delivered => Opacity(opacity: dim, child: TalkIcon(TalkSvg.ticks, width: 16, height: 11, color: color)),
      TalkTick.read => Opacity(opacity: 0.95, child: TalkIcon(TalkSvg.ticks, width: 16, height: 11, color: TalkColors.ticks)),
      TalkTick.failed => const Icon(Icons.error_outline, size: 14, color: Color(0xFFEF4444)),
    };
  }
}

/// Sohbetteki arama satırı (WhatsApp): simge, "Sesli arama" / "Cevapsız sesli arama", süre, saat.
class TalkCallLineView extends StatelessWidget {
  const TalkCallLineView({super.key, required this.line, required this.mine, required this.time, required this.onTap});

  final ({bool video, bool missed, String duration}) line;
  final bool mine;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = mine ? c.bubbleOutInk : c.bubbleInInk;
    final kind = line.video ? 'Görüntülü arama' : 'Sesli arama';
    final title = line.missed ? (mine ? kind : 'Cevapsız ${kind.toLowerCase()}') : kind;
    final sub = line.missed ? (mine ? 'Cevap yok' : 'Geri aramak için dokun') : line.duration;
    final red = line.missed && !mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 8),
          decoration: BoxDecoration(color: mine ? c.bubbleOut : c.bubbleIn, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: ink.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(
                line.missed ? (line.video ? Icons.missed_video_call : Icons.phone_missed) : (line.video ? Icons.videocam : Icons.call),
                size: 19,
                color: red ? const Color(0xFFE11D48) : ink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: talkText(14.5, FontWeight.w600, red ? const Color(0xFFE11D48) : ink)),
                if (sub.isNotEmpty) Text(sub, style: talkText(12.5, FontWeight.w400, ink.withValues(alpha: 0.65))),
              ]),
            ),
            const SizedBox(width: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(time, style: talkText(10.88, FontWeight.w400, ink.withValues(alpha: 0.55), height: 1)),
            ),
          ]),
        ),
      ),
    );
  }
}
