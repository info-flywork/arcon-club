import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'talk_api.dart';
import 'talk_icons.dart';
import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// WhatsApp iOS GIF / çıkartma paneli: klavyenin yerine açılır (emoji telefonun klavyesinden seçilir).
/// Üstte arama + GIF · Çıkartma, ortada üç sütunlu akan ızgara, altta kategoriler.
class TalkStickerPanel extends StatefulWidget {
  const TalkStickerPanel({super.key, required this.api, required this.onGif, this.height = 330});

  final TalkApi api;
  final void Function(String url) onGif;
  final double height;

  @override
  State<TalkStickerPanel> createState() => _TalkStickerPanelState();
}

enum _Tab { gif, sticker }

/// Alt çubuk kategorileri: (simge, Giphy araması). `recent` yerelde tutulur, boş arama = trend.
const _cats = <(IconData, String)>[
  (CupertinoIcons.clock, 'recent'),
  (Icons.trending_up_rounded, ''),
  (CupertinoIcons.smiley, 'happy'),
  (CupertinoIcons.heart, 'love'),
  (CupertinoIcons.hand_thumbsup, 'thumbs up'),
  (Icons.sentiment_dissatisfied_outlined, 'sad'),
  (Icons.celebration_outlined, 'celebrate'),
  (Icons.waving_hand_outlined, 'hello'),
];

/// Hazır GIF paketi (Giphy anahtarı gerekmez): (giphy id, genişlik, yükseklik, kategori + Türkçe arama kelimeleri).
/// Sunucuda anahtar yoksa panel bunu gösterir; kategoriler ve arama bu kelimelerle çalışır.
const _pack = <(String, int, int, String)>[
  ('10JhviFuU2gWD6', 152, 200, 'happy gülmek kahkaha komik haha'),
  ('3o7abKhOpu0NwenH3O', 356, 200, 'happy mutlu sevinç süngerbob'),
  ('ZqlvCTNHpqrio', 372, 200, 'happy mutlu minion sevinç'),
  ('l4pTfx2qLszoacZRS', 200, 200, 'happy dans eğlence'),
  ('5VKbvrjxpVJCM', 250, 200, 'happy şaşırmak vay wow'),
  ('3o7TKSjRrfIPjeiVyM', 200, 200, 'happy şok vay wow inanılmaz'),
  ('26BRv0ThflsHCqDrG', 200, 200, 'love kalp sevgi aşk'),
  ('3oEduSbSGpGaRX2Vri', 292, 200, 'love sarılmak kedi sevgi tatlı'),
  ('26gsjCZpPolPr3sBy', 200, 200, 'thumbs up teşekkür sağol thanks'),
  ('7rj2ZgttvgomY', 348, 200, 'thumbs up alkış bravo tebrik'),
  ('1zSz5MVw4zKg0', 182, 200, 'thumbs up evet tamam onay ok'),
  ('3o85xIO33l7RlmLR4I', 268, 200, 'thumbs up ikisi de neden olmasın'),
  ('9Y5BbDSkSTiY8', 286, 200, 'sad üzgün bebek'),
  ('OPU6wzx8JrHna', 242, 200, 'sad üzgün ağlamak patrick'),
  ('d2lcHJTG5Tscg', 358, 200, 'sad ağlamak üzgün'),
  ('l2JehQ2GitHGdVG9y', 265, 200, 'sad üzgün homer'),
  ('l41lFw057lAJQMwg0', 356, 200, 'sad üzgün stres'),
  ('l1J9u3TZfpmeDLkD6', 174, 200, 'sad kızgın sinirli öfke'),
  ('3o6fJ1BM7R2EBRDnxK', 412, 200, 'celebrate tebrikler kutlama congrats'),
  ('26u4cqiYI30juCOGY', 356, 200, 'celebrate konfeti kutlama'),
  ('g9582DNuQppxC', 356, 200, 'celebrate şerefe kutlama tebrik'),
  ('l0MYt5jPR6QX5pnqM', 356, 200, 'celebrate dans kutlama ofis'),
  ('l0HlvtIPzPdt2usKs', 334, 200, 'celebrate dans kutlama'),
  ('3ornk57KwDXf81rjWM', 370, 200, 'hello merhaba selam'),
  ('xT9IgG50Fb7Mi0prBC', 400, 200, 'hello selam el sallamak merhaba'),
  ('111ebonMs90YLu', 268, 200, 'iş çalışmak bilgisayar yazmak'),
  ('3oKIPnAiaMCws8nOsE', 190, 200, 'iş kedi bilgisayar çalışmak'),
  ('13HgwGsXF0aiGY', 356, 200, 'iş yangın acil sorun'),
  ('3oKIPsx2VAYAgEHC12', 356, 200, 'iş yorgun uykulu pazartesi'),
  ('QMHoU66sBXqqLqYvGO', 356, 200, 'iş her şey yolunda sakin yangın'),
  ('26FPy3QZQqGtDcrja', 300, 200, 'iş felaket yangın kaos'),
  ('26xBI73gWquCBBCDe', 326, 200, 'düşünmek kafa karışık hesap'),
  ('3o7btPCcdNniyf0ArS', 358, 200, 'düşünmek kafa karışık anlamadım'),
  ('l3q2K5jinAlChoCLS', 170, 200, 'rahatlamak oh be huzur'),
];

/// Çıkartmalar: Google Noto animasyonlu emojileri (ücretsiz). Izgarada küçük PNG, gönderilen animasyonlu WebP.
const _stickers = <(String, String)>[
  ('1f602', 'happy gülmek kahkaha'),
  ('1f923', 'happy kahkaha komik'),
  ('1f600', 'happy mutlu gülümseme'),
  ('1f60e', 'happy havalı'),
  ('1f60d', 'love aşk kalp göz'),
  ('1f970', 'love sevgi'),
  ('1f618', 'love öpücük'),
  ('2764_fe0f', 'love kalp'),
  ('1f44d', 'thumbs up tamam evet onay'),
  ('1f44f', 'thumbs up alkış bravo'),
  ('1f64f', 'thumbs up teşekkür rica lütfen'),
  ('2705', 'thumbs up tamam onay'),
  ('1f4af', 'thumbs up süper yüz'),
  ('1f622', 'sad üzgün'),
  ('1f62d', 'sad ağlamak'),
  ('1f621', 'sad kızgın sinirli'),
  ('1f973', 'celebrate parti kutlama'),
  ('1f389', 'celebrate konfeti kutlama'),
  ('1f525', 'celebrate ateş süper harika'),
  ('1f44b', 'hello merhaba selam el'),
  ('1f914', 'düşünmek hmm'),
  ('1f631', 'şok korku wow'),
  ('1f92f', 'şok wow inanılmaz'),
  ('1f634', 'uyku yorgun'),
];

List<TalkGif> _stickersFor(String query) {
  final q = query.toLowerCase().trim();
  const base = 'https://fonts.gstatic.com/s/e/notoemoji/latest';
  return [
    for (final e in _stickers)
      if (q.isEmpty || e.$2.contains(q) || e.$2.split(' ').any((w) => w.startsWith(q)))
        TalkGif(url: '$base/${e.$1}/512.webp', preview: '$base/${e.$1}/128.png', width: 128, height: 128),
  ];
}

List<TalkGif> _packFor(String query) {
  final q = query.toLowerCase().trim();
  return [
    for (final g in _pack)
      if (q.isEmpty || g.$4.contains(q) || g.$4.split(' ').any((w) => w.startsWith(q)))
        TalkGif(url: 'https://media.giphy.com/media/${g.$1}/200.gif', preview: 'https://media.giphy.com/media/${g.$1}/200.gif', width: g.$2, height: g.$3),
  ];
}

class _TalkStickerPanelState extends State<TalkStickerPanel> {
  String get _recentKey => _tab == _Tab.sticker ? 'arcon_talk_recent_stickers' : 'arcon_talk_recent_gifs';

  _Tab _tab = _Tab.gif;
  int _cat = 1;
  bool _searching = false;
  String _q = '';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<TalkGif> _items = const [];
  bool _loading = false;
  bool _more = true;
  bool _configured = true;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load(append: true);
    });
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _query => _searching && _q.trim().isNotEmpty ? _q.trim() : _cats[_cat].$2;
  bool get _recent => _query == 'recent';

  Future<List<TalkGif>> _readRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_recentKey);
      if (raw == null) return const [];
      return [for (final g in (jsonDecode(raw) as List).whereType<Map>()) TalkGif.fromJson(g.cast<String, dynamic>())];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _remember(TalkGif g) async {
    try {
      final list = [g, ...(await _readRecent()).where((x) => x.url != g.url)].take(36).toList();
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _recentKey,
        jsonEncode([
          for (final x in list) {'url': x.url, 'preview': x.preview, 'w': x.width, 'h': x.height},
        ]),
      );
    } catch (_) {}
  }

  Future<void> _load({bool append = false}) async {
    if (append && (_loading || !_more || _recent)) return;
    final req = ++_req;
    setState(() {
      _loading = true;
      if (!append) {
        _items = const [];
        _more = true;
      }
    });
    List<TalkGif> next;
    var configured = _configured;
    var more = false;
    if (_recent) {
      next = await _readRecent();
    } else if (_tab == _Tab.sticker) {
      next = append ? const [] : _stickersFor(_query);
    } else {
      try {
        // sunucuda anahtar yoksa bir kez öğrenilir, sonra hep hazır paket kullanılır
        if (!_configured) throw const FormatException('paket');
        final r = await widget.api.gifs(q: _query, offset: append ? _items.length : 0);
        configured = r.configured;
        next = r.items;
        more = r.items.length >= 30;
        if (!configured) throw const FormatException('paket');
      } catch (_) {
        next = append ? const [] : _packFor(_query);
        more = false;
      }
    }
    if (!mounted || req != _req) return;
    setState(() {
      _items = append ? [..._items, ...next] : next;
      _more = more;
      _configured = configured;
      _loading = false;
    });
  }

  void _pick(TalkGif g) {
    _remember(g);
    widget.onGif(g.url);
  }

  void _setTab(_Tab t) {
    if (_tab == t) return;
    setState(() => _tab = t);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  void _setCat(int i) {
    setState(() {
      _cat = i;
      _searching = false;
      _q = '';
      _search.clear();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bg = c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final seg = c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE3E3E8);
    final segOn = c.dark ? const Color(0xFF48484A) : Colors.white;
    Widget segItem(_Tab t, Widget child) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setTab(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _tab == t ? segOn : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: _tab == t && !c.dark ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 4, offset: Offset(0, 1))] : null,
          ),
          child: child,
        ),
      ),
    );
    return Container(
      height: widget.height + MediaQuery.paddingOf(context).bottom,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7, bottom: 6),
            width: 38,
            height: 5,
            decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: _searching
                ? Row(
                    children: [
                      Expanded(
                        child: CupertinoSearchTextField(
                          controller: _search,
                          autofocus: true,
                          placeholder: _tab == _Tab.sticker ? 'Çıkartma ara' : 'GIF ara',
                          style: talkText(15, FontWeight.w400, c.ink),
                          onChanged: (v) {
                            _q = v;
                            _debounce?.cancel();
                            _debounce = Timer(const Duration(milliseconds: 350), _load);
                          },
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.only(left: 10),
                        onPressed: () => _setCat(_cat),
                        child: Text('Vazgeç', style: talkText(15, FontWeight.w400, c.ink)),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          tooltip: 'Ara',
                          onPressed: () => setState(() => _searching = true),
                          icon: Icon(CupertinoIcons.search, size: 22, color: c.muted),
                        ),
                      ),
                      // WhatsApp: ortada kısa GIF | çıkartma anahtarı
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 200,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(color: seg, borderRadius: BorderRadius.circular(999)),
                            child: Row(
                              children: [
                                segItem(
                                  _Tab.gif,
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: c.ink, width: 1.6),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text('GIF', style: talkText(10.5, FontWeight.w900, c.ink, height: 1.1)),
                                  ),
                                ),
                                segItem(_Tab.sticker, TalkIcon(TalkSvg.sticker, size: 21, color: c.ink)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
          ),
          Expanded(child: _grid(c)),
          if (!_searching)
            Container(
              padding: EdgeInsets.fromLTRB(6, 4, 6, 4 + MediaQuery.paddingOf(context).bottom),
              child: Row(
                children: [
                  for (var i = 0; i < _cats.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _setCat(i),
                        child: Container(
                          height: 38,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(color: _cat == i ? seg : Colors.transparent, shape: BoxShape.circle),
                          child: Icon(_cats[i].$1, size: 22, color: _cat == i ? c.ink : c.muted),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  /// Üç sütunlu akan ızgara (yükseklik oranları korunur), sona yaklaşınca devamı yüklenir.
  Widget _grid(TalkColors c) {
    if (_items.isEmpty) {
      return Center(
        child: _loading
            ? const CupertinoActivityIndicator()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _recent
                      ? (_tab == _Tab.sticker ? 'Son gönderdiğin çıkartmalar burada görünür' : 'Son gönderdiğin GIF’ler burada görünür')
                      : 'Sonuç bulunamadı',
                  textAlign: TextAlign.center,
                  style: talkText(14, FontWeight.w400, c.muted),
                ),
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 4.0;
        final colW = (box.maxWidth - 12 - gap * 2) / 3;
        final cols = [<TalkGif>[], <TalkGif>[], <TalkGif>[]];
        final heights = [0.0, 0.0, 0.0];
        for (final g in _items) {
          final h = colW * (g.height <= 0 || g.width <= 0 ? 1 : (g.height / g.width).clamp(0.5, 1.8));
          var k = 0;
          for (var i = 1; i < 3; i++) {
            if (heights[i] < heights[k]) k = i;
          }
          cols[k].add(g);
          heights[k] += h + gap;
        }
        final placeholder = c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
        return SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var k = 0; k < 3; k++) ...[
                    if (k > 0) const SizedBox(width: gap),
                    SizedBox(
                      width: colW,
                      child: Column(
                        children: [
                          for (final g in cols[k])
                            Padding(
                              padding: const EdgeInsets.only(bottom: gap),
                              child: GestureDetector(
                                onTap: () => _pick(g),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: colW,
                                    height: colW * (g.height <= 0 || g.width <= 0 ? 1 : (g.height / g.width).clamp(0.5, 1.8)),
                                    child: Padding(
                                      padding: EdgeInsets.all(_tab == _Tab.sticker ? 12 : 0),
                                      child: TalkNetImage(
                                        g.preview,
                                        fit: _tab == _Tab.sticker ? BoxFit.contain : BoxFit.cover,
                                        placeholder: _tab == _Tab.sticker ? Colors.transparent : placeholder,
                                        error: Container(color: placeholder),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (_loading) const Padding(padding: EdgeInsets.all(10), child: CupertinoActivityIndicator()),
            ],
          ),
        );
      },
    );
  }
}
