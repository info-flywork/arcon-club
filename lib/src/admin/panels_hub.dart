import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../ui/mono.dart';
import '../ui/skeleton.dart';
import 'panel_akademi.dart';
import 'panel_common.dart';
import 'panels_mag_store.dart';
import 'panels_skor_talk.dart';

/// Modül yönetim panellerinin listesi — yalnızca yetkili olunanlar gösterilir.
class PanelsHubScreen extends StatefulWidget {
  const PanelsHubScreen({super.key, required this.session});
  final SessionController session;

  @override
  State<PanelsHubScreen> createState() => _PanelsHubScreenState();
}

class _PanelsHubScreenState extends State<PanelsHubScreen> {
  Map<String, dynamic>? _caps;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.api.webCall(panelApi, query: {'view': 'caps'}).then((j) {
      if (mounted) setState(() => _caps = ((j['caps'] as Map?) ?? const {}).cast<String, dynamic>());
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is ArconApiException ? e.message : '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final s = widget.session;
    final items = <(String, String, String, IconData, Widget Function())>[
      ('mag', 'ARCON MAG', 'Haber ekle, zamanla, yayınla', Icons.newspaper_outlined, () => MagAdminScreen(session: s)),
      ('akademi', 'Akademi', 'Rapor, onaylar, sertifikalar, eğitimler', Icons.school_outlined, () => AkademiAdminScreen(session: s)),
      ('skor', 'SCORE', 'Anket dönemleri, analiz, sorular', Icons.insights_outlined, () => SkorAdminScreen(session: s)),
      ('store', 'ARCON STORE', 'Mağaza listesi ve konumlar', Icons.storefront_outlined, () => StoreAdminScreen(session: s)),
      ('talk', 'ARCONNECT', 'Kanal ve mesaj moderasyonu', Icons.forum_outlined, () => TalkAdminScreen(session: s)),
    ];
    final visible = items.where((e) => _caps?[e.$1] == true).toList();
    return PanelPage(
      title: 'Modül yönetimi',
      body: _caps == null
          ? (_error != null ? Center(child: Text(_error!, style: c.text(14, color: c.muted))) : const SkeletonList(count: 5))
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (visible.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Text('Yönetebileceğin bir modül yok.', style: c.text(14, color: c.muted)))),
                for (final (_, title, sub, icon, build) in visible)
                  panelCard(
                    c,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => build())),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(12)),
                          child: Icon(icon, color: c.bg, size: 21),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: c.text(15, weight: FontWeight.w700)),
                              Text(sub, style: c.text(12, color: c.muted)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.faint),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
