import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'talk_location_picker.dart';
import 'talk_models.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

// WhatsApp ek menüsünün Konum ve Anket'i. Sunucuda ayrı tablo yok: ikisi de makinece okunur
// mesaj metniyle gider (web düz metin olarak gösterir). Anket oyları mesaj tepkisiyle tutulur
// (kullanıcı başına tek tepki = tek oy).

// ---------- Konum ----------

/// 📍 Konum
/// 41.012300,29.012300
/// Kadıköy, İstanbul
String talkLocationBody(double lat, double lng, String address) =>
    '📍 Konum\n${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}${address.trim().isEmpty ? '' : '\n${address.trim()}'}';

({double lat, double lng, String address})? talkLocationLine(String body) {
  final m = RegExp(r'^📍 Konum\n(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)(?:\n(.+))?$', dotAll: true).firstMatch(body.trim());
  if (m == null) return null;
  return (lat: double.parse(m.group(1)!), lng: double.parse(m.group(2)!), address: (m.group(3) ?? '').trim());
}

/// Şu anki konum → mesaj metni. İzin yoksa / kapalıysa uyarır ve null döner.
Future<String?> talkCurrentLocationBody(BuildContext context) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) talkToast(context, 'Telefonda konum servisi kapalı', error: true);
      return null;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (context.mounted) talkToast(context, 'Konum izni verilmedi. Ayarlar › ARCONNECT › Konum', error: true);
      return null;
    }
    final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    var address = '';
    try {
      final marks = await Geocoding(locale: const Locale('tr', 'TR')).placemarkFromCoordinates(p.latitude, p.longitude);
      if (marks.isNotEmpty) {
        final k = marks.first;
        address = [k.street, k.subLocality, k.locality ?? k.subAdministrativeArea, k.administrativeArea]
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .join(', ');
      }
    } on Exception {
      // adres bulunamazsa yalnızca koordinat gider
    }
    return talkLocationBody(p.latitude, p.longitude, address);
  } on Exception {
    if (context.mounted) talkToast(context, 'Konum alınamadı', error: true);
    return null;
  }
}

Future<void> talkOpenMaps(double lat, double lng) async {
  final apple = Uri.parse('https://maps.apple.com/?q=$lat,$lng&ll=$lat,$lng');
  final google = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
  await launchUrl(Platform.isIOS ? apple : google, mode: LaunchMode.externalApplication);
}

class TalkLocationCardView extends StatelessWidget {
  const TalkLocationCardView({super.key, required this.location, required this.mine, required this.time});

  final ({double lat, double lng, String address}) location;
  final bool mine;
  final String time;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = mine ? c.bubbleOutInk : c.bubbleInInk;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => talkOpenMaps(location.lat, location.lng),
        child: Container(
          width: 260,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: mine ? c.bubbleOut : c.bubbleIn, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // küçük harita (dokunulmaz; karta dokununca Haritalar açılır)
            SizedBox(
              height: 130,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(location.lat, location.lng),
                    initialZoom: 15.5,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    talkTileLayer(context, c.dark),
                    MarkerLayer(markers: [
                      Marker(
                        point: LatLng(location.lat, location.lng),
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(CupertinoIcons.map_pin, size: 40, color: Color(0xFFE11D48)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Konum', style: talkText(15, FontWeight.w600, ink)),
                Text(
                  location.address.isNotEmpty ? location.address : '${location.lat.toStringAsFixed(5)}, ${location.lng.toStringAsFixed(5)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: talkText(13, FontWeight.w400, ink.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text('Haritada aç', style: talkText(14, FontWeight.w600, ink)),
                  const Spacer(),
                  Text(time, style: talkText(10.88, FontWeight.w400, ink.withValues(alpha: 0.55), height: 1)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- Anket ----------

/// Seçenek oy simgeleri (tepki olarak gönderilir)
const talkPollEmojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣'];

/// 📊 Soru
/// 1. Seçenek
/// 2. Seçenek
String talkPollBody(String question, List<String> options) =>
    '📊 ${question.trim()}\n${[for (var i = 0; i < options.length; i++) '${i + 1}. ${options[i].trim()}'].join('\n')}';

({String question, List<String> options})? talkPollLine(String body) {
  final lines = body.trim().split('\n');
  if (lines.length < 3 || !lines.first.startsWith('📊 ')) return null;
  final opts = <String>[];
  for (var i = 1; i < lines.length; i++) {
    final m = RegExp(r'^(\d+)\. (.+)$').firstMatch(lines[i].trim());
    if (m == null || int.parse(m.group(1)!) != i) return null;
    opts.add(m.group(2)!);
  }
  if (opts.length < 2 || opts.length > talkPollEmojis.length) return null;
  return (question: lines.first.substring(3).trim(), options: opts);
}

class TalkPollCardView extends StatelessWidget {
  const TalkPollCardView({super.key, required this.poll, required this.reactions, required this.mine, required this.time, required this.onVote});

  final ({String question, List<String> options}) poll;
  final List<TalkReaction> reactions;
  final bool mine;
  final String time;
  final void Function(String emoji) onVote;

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = mine ? c.bubbleOutInk : c.bubbleInInk;
    int votes(int i) => reactions.where((r) => r.emoji == talkPollEmojis[i]).fold(0, (a, r) => a + r.count);
    bool chosen(int i) => reactions.any((r) => r.emoji == talkPollEmojis[i] && r.mine);
    final total = [for (var i = 0; i < poll.options.length; i++) votes(i)].fold(0, (a, b) => a + b);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(color: mine ? c.bubbleOut : c.bubbleIn, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(poll.question, style: talkText(16, FontWeight.w700, ink)),
          const SizedBox(height: 2),
          Text('Bir seçenek seçin', style: talkText(12.5, FontWeight.w400, ink.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          for (var i = 0; i < poll.options.length; i++)
            InkWell(
              onTap: () => onVote(talkPollEmojis[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Icon(chosen(i) ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, size: 22, color: ink.withValues(alpha: chosen(i) ? 1 : 0.55)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(poll.options[i], style: talkText(15, FontWeight.w500, ink))),
                        Text('${votes(i)}', style: talkText(14, FontWeight.w600, ink.withValues(alpha: 0.7))),
                      ]),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : votes(i) / total,
                          minHeight: 5,
                          color: ink,
                          backgroundColor: ink.withValues(alpha: 0.12),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 4),
          Row(children: [
            Text(total == 0 ? 'Henüz oy yok' : '$total oy', style: talkText(12.5, FontWeight.w500, ink.withValues(alpha: 0.65))),
            const Spacer(),
            Text(time, style: talkText(10.88, FontWeight.w400, ink.withValues(alpha: 0.55), height: 1)),
          ]),
        ]),
      ),
    );
  }
}

/// Anket oluştur: soru + 2–8 seçenek. Mesaj metnini döner.
Future<String?> showTalkPollSheet(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PollSheet(),
    );

class _PollSheet extends StatefulWidget {
  const _PollSheet();

  @override
  State<_PollSheet> createState() => _PollSheetState();
}

class _PollSheetState extends State<_PollSheet> {
  final _q = TextEditingController();
  final _opts = [TextEditingController(), TextEditingController()];

  @override
  void dispose() {
    _q.dispose();
    for (final o in _opts) {
      o.dispose();
    }
    super.dispose();
  }

  List<String> get _filled => _opts.map((o) => o.text.trim()).where((t) => t.isNotEmpty).toList();
  bool get _ready => _q.text.trim().isNotEmpty && _filled.length >= 2;

  void _changed() {
    // son seçenek dolunca yenisi açılır (WhatsApp gibi)
    if (_opts.last.text.trim().isNotEmpty && _opts.length < talkPollEmojis.length) _opts.add(TextEditingController());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final bg = c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final card = c.dark ? const Color(0xFF2C2C2E) : Colors.white;
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: talkText(16, FontWeight.w400, c.muted),
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text('Vazgeç', style: talkText(17, FontWeight.w400, c.ink))),
                Expanded(child: Text('Anket oluştur', textAlign: TextAlign.center, style: talkText(17, FontWeight.w600, c.ink))),
                TextButton(
                  onPressed: _ready ? () => Navigator.pop(context, talkPollBody(_q.text, _filled)) : null,
                  child: Text('Gönder', style: talkText(17, FontWeight.w600, _ready ? c.ink : c.muted)),
                ),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 6), child: Text('Soru', style: talkText(14, FontWeight.w600, c.muted))),
                Container(
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                  child: TextField(controller: _q, autofocus: true, onChanged: (_) => setState(() {}), style: talkText(16, FontWeight.w400, c.ink), cursorColor: c.ink, decoration: deco('Soru sor')),
                ),
                Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 6), child: Text('Seçenekler', style: talkText(14, FontWeight.w600, c.muted))),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    for (var i = 0; i < _opts.length; i++) ...[
                      TextField(controller: _opts[i], onChanged: (_) => _changed(), style: talkText(16, FontWeight.w400, c.ink), cursorColor: c.ink, decoration: deco('Seçenek ${i + 1}')),
                      if (i < _opts.length - 1) Divider(height: 0.6, thickness: 0.6, indent: 14, color: c.rowLine),
                    ],
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: Text('Herkes tek seçenek işaretleyebilir. En fazla ${talkPollEmojis.length} seçenek.', style: talkText(13, FontWeight.w400, c.muted)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- Galeri ızgarası ----------

/// Ek menüsünün altında galerideki son fotoğraflar. Dokununca seçilir (çoklu); sıra numarası görünür.
class TalkGalleryGrid extends StatefulWidget {
  const TalkGalleryGrid({super.key, required this.onChanged, this.max = 12});

  final ValueChanged<List<File>> onChanged;
  final int max;

  @override
  State<TalkGalleryGrid> createState() => _TalkGalleryGridState();
}

class _TalkGalleryGridState extends State<TalkGalleryGrid> {
  List<AssetEntity>? _assets;
  bool _denied = false;
  final _order = <String>[];
  final _files = <String, File>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final paths = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
      final list = paths.isEmpty ? <AssetEntity>[] : await paths.first.getAssetListPaged(page: 0, size: 90);
      if (mounted) setState(() => _assets = list);
    } on Exception {
      if (mounted) setState(() => _assets = const []);
    }
  }

  void _emit() => widget.onChanged([for (final id in _order) if (_files[id] != null) _files[id]!]);

  Future<void> _toggle(AssetEntity a) async {
    final id = a.id;
    if (_order.contains(id)) {
      setState(() {
        _order.remove(id);
        _files.remove(id);
      });
      _emit();
      return;
    }
    if (_order.length >= widget.max) return;
    File? f;
    if (a.type == AssetType.image) {
      final bytes = await a.thumbnailDataWithSize(const ThumbnailSize(1600, 1600), quality: 78);
      if (bytes != null && bytes.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        // iOS kimliği "…/L0/001" gibi eğik çizgi içerir: dosya adında alt klasör sanılmasın
        f = File('${dir.path}/talk-${a.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}-${DateTime.now().millisecondsSinceEpoch}.jpg');
        await f.writeAsBytes(bytes, flush: true);
      }
    }
    f ??= await a.file;
    if (f == null || !mounted) return;
    setState(() {
      _order.add(id);
      _files[id] = f!;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    if (_denied) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: PhotoManager.openSetting,
          child: Text('Son fotoğrafları görmek için galeri izni ver › Ayarlar', textAlign: TextAlign.center, style: talkText(14, FontWeight.w500, c.muted)),
        ),
      );
    }
    final list = _assets;
    if (list == null) return Center(child: CupertinoActivityIndicator(color: c.muted));
    if (list.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final a = list[i];
        final n = _order.indexOf(a.id);
        return _Thumb(asset: a, index: n < 0 ? null : n + 1, onTap: () => _toggle(a));
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.asset, required this.onTap, this.index});
  final AssetEntity asset;
  final VoidCallback onTap;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final on = index != null;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(fit: StackFit.expand, children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize.square(300)),
            builder: (_, s) => s.data == null ? const ColoredBox(color: Color(0x14000000)) : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          if (on) const ColoredBox(color: Color(0x33000000)),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? TalkColors.wa : const Color(0x66000000),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: on ? Text('$index', style: talkText(12, FontWeight.w700, Colors.white, height: 1)) : null,
            ),
          ),
        ]),
      ),
    );
  }
}
