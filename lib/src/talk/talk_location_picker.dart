import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'talk_share_kinds.dart';
import 'talk_theme.dart';
import 'talk_widgets.dart';

/// Harita döşemeleri (CARTO, OpenStreetMap verisi; anahtar gerekmez). Koyu temada koyu harita.
String talkMapTiles(bool dark) =>
    dark ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png' : 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

TileLayer talkTileLayer(BuildContext context, bool dark) => TileLayer(
      urlTemplate: talkMapTiles(dark),
      retinaMode: RetinaMode.isHighDensity(context),
      userAgentPackageName: 'net.arconai.arconnect',
    );

/// Yakındaki yer / arama sonucu (Photon, OpenStreetMap verisi; anahtar gerekmez)
class TalkPlace {
  const TalkPlace({required this.name, required this.address, required this.lat, required this.lng});
  final String name;
  final String address;
  final double lat;
  final double lng;

  static TalkPlace? fromFeature(Map<String, dynamic> f) {
    final p = (f['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    final coords = ((f['geometry'] as Map?)?['coordinates'] as List?) ?? const [];
    final name = '${p['name'] ?? ''}'.trim();
    if (name.isEmpty || coords.length < 2) return null;
    final street = [p['street'], p['housenumber']].whereType<String>().join(' ').trim();
    final address = [street, p['district'], p['city'] ?? p['county'], p['postcode']]
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != name)
        .toSet()
        .join(', ');
    return TalkPlace(name: name, address: address, lat: (coords[1] as num).toDouble(), lng: (coords[0] as num).toDouble());
  }
}

const _photon = 'https://photon.komoot.io';
const _ua = {'User-Agent': 'ARCONNECT-mobil/1.0'};
// yakındaki yerler listesinde yol, durak gibi kayıtlar çıkmasın
const _placeKeys = {'amenity', 'shop', 'tourism', 'leisure', 'office', 'craft', 'healthcare', 'building', 'historic', 'man_made', 'place'};

Future<List<TalkPlace>> _nearby(LatLng at) async {
  final res = await http
      .get(Uri.parse('$_photon/reverse?lat=${at.latitude}&lon=${at.longitude}&limit=20&radius=0.5&lang=default'), headers: _ua)
      .timeout(const Duration(seconds: 12));
  final feats = ((jsonDecode(res.body) as Map)['features'] as List?) ?? const [];
  return [
    for (final f in feats.whereType<Map>())
      if (_placeKeys.contains('${(f['properties'] as Map?)?['osm_key']}'))
        if (TalkPlace.fromFeature(f.cast<String, dynamic>()) case final TalkPlace p) p,
  ];
}

Future<List<TalkPlace>> _search(String q, LatLng near) async {
  final res = await http
      .get(Uri.parse('$_photon/api/?q=${Uri.encodeQueryComponent(q)}&lat=${near.latitude}&lon=${near.longitude}&limit=15&lang=default'), headers: _ua)
      .timeout(const Duration(seconds: 12));
  final feats = ((jsonDecode(res.body) as Map)['features'] as List?) ?? const [];
  return [
    for (final f in feats.whereType<Map>())
      if (TalkPlace.fromFeature(f.cast<String, dynamic>()) case final TalkPlace p) p,
  ];
}

/// WhatsApp "Konum gönder": harita (kaydırınca ortadaki nokta seçilir, yakındaki yerler güncellenir),
/// mevcut konum, yakındaki yerler ve arama. Seçilen konumun mesaj metnini döner.
Future<String?> showTalkLocationPicker(BuildContext context) async {
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
  } on Exception {
    if (context.mounted) talkToast(context, 'Konum alınamadı', error: true);
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const TalkLocationPickerScreen()));
}

class TalkLocationPickerScreen extends StatefulWidget {
  const TalkLocationPickerScreen({super.key});

  @override
  State<TalkLocationPickerScreen> createState() => _TalkLocationPickerScreenState();
}

class _TalkLocationPickerScreenState extends State<TalkLocationPickerScreen> {
  final _map = MapController();
  final _q = TextEditingController();
  Position? _me;
  LatLng? _center;
  bool _moved = false;
  bool _big = false;
  bool _searching = false;
  bool _loading = true;
  List<TalkPlace> _places = const [];
  List<TalkPlace> _results = const [];
  String _centerAddress = '';
  Timer? _debounce;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _loading = true);
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      if (!mounted) return;
      final at = LatLng(p.latitude, p.longitude);
      setState(() {
        _me = p;
        _center = at;
        _moved = false;
      });
      try {
        _map.move(at, 17);
      } catch (_) {
        // harita henüz çizilmediyse ilk konumla açılır
      }
      await _loadPlaces(at);
    } on Exception {
      if (!mounted) return;
      setState(() => _loading = false);
      talkToast(context, 'Konum alınamadı', error: true);
    }
  }

  Future<void> _loadPlaces(LatLng at) async {
    final req = ++_req;
    setState(() => _loading = true);
    var places = const <TalkPlace>[];
    try {
      places = await _nearby(at);
    } catch (_) {
      // yer servisi yanıt vermezse yalnızca konum gönderilebilir
    }
    if (!mounted || req != _req) return;
    setState(() {
      _places = places;
      _loading = false;
      // kaydırılan noktanın adresi: en yakın kaydın sokağı / semti
      _centerAddress = places.isEmpty ? '' : places.first.address;
    });
  }

  void _onMoved(MapCamera cam, bool gesture) {
    if (!gesture) return;
    _center = cam.center;
    if (!_moved) setState(() => _moved = true);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _loadPlaces(cam.center));
  }

  void _recenter() {
    final p = _me;
    if (p == null) {
      _locate();
      return;
    }
    final at = LatLng(p.latitude, p.longitude);
    _map.move(at, 17);
    setState(() {
      _center = at;
      _moved = false;
    });
    _loadPlaces(at);
  }

  void _runSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final near = _center ?? const LatLng(41.0082, 28.9784);
      try {
        final r = await _search(q.trim(), near);
        if (mounted) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      }
    });
  }

  void _send(double lat, double lng, String address) => Navigator.pop(context, talkLocationBody(lat, lng, address));

  void _sendPlace(TalkPlace p) => _send(p.lat, p.lng, p.address.isEmpty ? p.name : '${p.name}\n${p.address}');

  @override
  Widget build(BuildContext context) {
    final c = TalkColors.of(context);
    final ink = c.dark ? const Color(0xFFF2F2F7) : const Color(0xFF111111);
    final bg = c.dark ? const Color(0xFF0B141A) : Colors.white;
    final size = MediaQuery.sizeOf(context);
    final me = _me;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => _searching ? setState(() => _searching = false) : Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: _searching
            ? TextField(
                controller: _q,
                autofocus: true,
                onChanged: _runSearch,
                style: talkText(17, FontWeight.w400, ink),
                cursorColor: ink,
                decoration: InputDecoration(
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Yer ara…',
                  hintStyle: talkText(17, FontWeight.w400, c.muted),
                ),
              )
            : Text('Konum gönder', style: talkText(20, FontWeight.w600, ink)),
        actions: [
          if (!_searching) IconButton(tooltip: 'Ara', icon: const Icon(CupertinoIcons.search), onPressed: () => setState(() => _searching = true)),
          if (_searching && _q.text.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              icon: const Icon(CupertinoIcons.xmark_circle_fill),
              onPressed: () => setState(() {
                _q.clear();
                _results = const [];
              }),
            ),
          if (!_searching) IconButton(tooltip: 'Yenile', icon: const Icon(CupertinoIcons.refresh), onPressed: _locate),
        ],
      ),
      body: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: _searching ? 0 : (_big ? size.height * 0.62 : size.height * 0.36),
          child: center == null
              ? Container(color: c.dark ? const Color(0xFF1C1C1E) : const Color(0xFFEDEDED), alignment: Alignment.center, child: const CupertinoActivityIndicator())
              : Stack(children: [
                  FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: center!,
                      initialZoom: 17,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                      onPositionChanged: _onMoved,
                    ),
                    children: [
                      talkTileLayer(context, c.dark),
                      if (me != null)
                        MarkerLayer(markers: [
                          Marker(
                            point: LatLng(me.latitude, me.longitude),
                            width: 22,
                            height: 22,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2F80ED),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6)],
                              ),
                            ),
                          ),
                        ]),
                    ],
                  ),
                  // haritayı kaydırınca seçilen nokta ortadaki iğne
                  if (_moved)
                    const IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 34),
                          child: Icon(CupertinoIcons.map_pin, size: 40, color: Color(0xFFE11D48)),
                        ),
                      ),
                    ),
                  Positioned(left: 14, top: 14, child: _roundBtn(c, _big ? CupertinoIcons.fullscreen_exit : CupertinoIcons.fullscreen, 'Büyüt', () => setState(() => _big = !_big))),
                  Positioned(right: 14, top: 14, child: _roundBtn(c, CupertinoIcons.scope, 'Konumuma git', _recenter)),
                  Positioned(
                    right: 6,
                    bottom: 4,
                    child: Text('© OpenStreetMap © CARTO', style: talkText(9.5, FontWeight.w400, c.dark ? const Color(0xAAFFFFFF) : const Color(0x99000000))),
                  ),
                ]),
        ),
        Expanded(child: _searching ? _searchList(c, ink) : _list(c, ink)),
      ]),
    );
  }

  LatLng? get center => _center;

  Widget _roundBtn(TalkColors c, IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.dark ? const Color(0xFF2C2C2E) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Icon(icon, size: 22, color: c.dark ? Colors.white : const Color(0xFF111111)),
          ),
        ),
      );

  Widget _row(TalkColors c, Color ink, {required Widget icon, required String title, String subtitle = '', required VoidCallback onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(children: [
            icon,
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(17, FontWeight.w500, ink)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: talkText(14.5, FontWeight.w400, c.muted)),
                ],
              ]),
            ),
          ]),
        ),
      );

  Widget _pinIcon(TalkColors c) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: c.dark ? const Color(0xFF2C2C2E) : const Color(0xFFF0F0F2), shape: BoxShape.circle),
        child: Icon(CupertinoIcons.location, size: 22, color: c.dark ? Colors.white : const Color(0xFF111111)),
      );

  Widget _list(TalkColors c, Color ink) {
    final me = _me;
    final at = _center;
    return ListView(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
        child: Text('Yakındaki yerler', style: talkText(15, FontWeight.w500, c.muted)),
      ),
      if (at != null)
        _row(
          c,
          ink,
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.accent, width: 2)),
            child: Center(child: Container(width: 20, height: 20, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle))),
          ),
          title: _moved ? 'Bu konumu gönder' : 'Mevcut konumunu gönder',
          subtitle: _moved ? _centerAddress : (me == null ? '' : '${me.accuracy.round()} metre hassasiyetle'),
          onTap: () => _send(at.latitude, at.longitude, _centerAddress),
        ),
      if (_loading && _places.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CupertinoActivityIndicator()))
      else
        for (final p in _places) _row(c, ink, icon: _pinIcon(c), title: p.name, subtitle: p.address, onTap: () => _sendPlace(p)),
    ]);
  }

  Widget _searchList(TalkColors c, Color ink) {
    if (_q.text.trim().length < 2) {
      return Center(child: Text('Bir yer adı yaz', style: talkText(15, FontWeight.w400, c.muted)));
    }
    if (_results.isEmpty) {
      return Center(child: Text('Sonuç yok', style: talkText(15, FontWeight.w400, c.muted)));
    }
    return ListView(children: [for (final p in _results) _row(c, ink, icon: _pinIcon(c), title: p.name, subtitle: p.address, onTap: () => _sendPlace(p))]);
  }
}
