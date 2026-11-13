import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../auth/session_controller.dart';
import '../../config.dart';
import '../home_screen.dart' show WebModuleIcon;
import '../mono.dart';
import 'club_common.dart';
import '../motion.dart';

/// Tüm modüller: ARCON ürünleri ve kullanıcının AI modülleri, aramalı liste.
/// Liste sunucudan gelir (`/api/v1/modules`), webde açılan modül burada da görünür.
class ClubModules extends StatefulWidget {
  const ClubModules({super.key, required this.session, required this.config});

  final SessionController session;
  final ArconAppConfig config;

  @override
  State<ClubModules> createState() => _ClubModulesState();
}

class _ClubModulesState extends State<ClubModules> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _match(ArconModule m) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return m.title.toLowerCase().contains(q) || m.description.toLowerCase().contains(q);
  }

  void _open(ArconModule m) => clubOpen(context, session: widget.session, config: widget.config, key: m.key);

  @override
  Widget build(BuildContext context) {
    final c = ArconMono.of(context);
    final pad = MediaQuery.paddingOf(context);
    final mods = widget.session.modules;
    final products = mods.where((m) => m.group == 'main' && m.key != 'dashboard' && m.key != 'ai_hub' && _match(m)).toList();
    final ai = mods.where((m) => m.group == 'ai_modules' && _match(m)).toList();

    return RefreshIndicator(
      color: c.ink,
      backgroundColor: c.bg,
      onRefresh: () => widget.session.refreshModules(force: true).catchError((_) {}),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(20, pad.top + 14, 20, 28 + pad.bottom),
        children: [
          Text('Modüller', style: c.text(30, weight: FontWeight.w800, height: 1.15, spacing: -1)),
          const SizedBox(height: 4),
          Text(
            '${mods.where((m) => m.group != 'account' && m.key != 'dashboard').length} modül erişimine açık',
            style: c.text(13, color: c.muted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v.trim()),
            style: c.text(15, weight: FontWeight.w500),
            cursorColor: c.ink,
            keyboardAppearance: c.dark ? Brightness.dark : Brightness.light,
            textInputAction: TextInputAction.search,
            decoration: c.input(
              'Modül ara',
              Icons.search_rounded,
              suffix: AnimatedSwitcher(
                duration: Motion.of(context, Motion.fast),
                transitionBuilder: (w, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: a, child: w),
                ),
                child: _q.isEmpty
                    ? const SizedBox.shrink(key: ValueKey('empty'))
                    : IconButton(
                        key: const ValueKey('clear'),
                        icon: Icon(Icons.close_rounded, size: 18, color: c.muted),
                        onPressed: () => setState(() {
                          _search.clear();
                          _q = '';
                        }),
                      ),
              ),
            ),
          ),
          if (ai.isNotEmpty) ...[
            const SizedBox(height: 24),
            const ClubSectionTitle('AI Modüllerim'),
            const SizedBox(height: 12),
            _group(c, [for (final m in ai) _row(c, m, SizedBox(width: 46, height: 46, child: WebModuleIcon(module: m)))]),
          ],
          if (products.isNotEmpty) ...[
            const SizedBox(height: 24),
            const ClubSectionTitle('ARCON ürünleri'),
            const SizedBox(height: 12),
            _group(c, [for (final m in products) _row(c, m, ClubIconBox(clubFeatureIcon(m.key), size: 40))]),
          ],
          if (products.isEmpty && ai.isEmpty) ...[
            const SizedBox(height: 60),
            Icon(Icons.search_off_rounded, size: 36, color: c.faint),
            const SizedBox(height: 10),
            Text(
              '"$_q" ile eşleşen modül yok',
              textAlign: TextAlign.center,
              style: c.text(14, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _group(ArconMono c, List<Widget> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: c.field,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: c.line),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[if (i > 0) Divider(height: 1, thickness: 1, indent: 70, color: c.line), rows[i]],
      ],
    ),
  );

  Widget _row(ArconMono c, ArconModule m, Widget leading) {
    final desc = m.description.isNotEmpty ? m.description : (clubFeatureFallbackText[m.key] ?? '');
    return InkWell(
      onTap: () => _open(m),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: c.text(14, weight: FontWeight.w700),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: c.text(12, color: c.muted, height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.faint),
          ],
        ),
      ),
    );
  }
}
