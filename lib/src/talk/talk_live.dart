import 'dart:async';

import 'talk_api.dart';
import 'talk_models.dart';

/// Yazıyor ve çevrimiçi için açık tutulan hat. Durum değişince sunucu hemen döner.
class TalkLive {
  TalkLive(this.api, this.onData, {this.onDown});

  final TalkApi api;
  final void Function(Set<int> online, Map<int, List<TalkTyping>> typing, List<TalkCall> calls) onData;
  final void Function()? onDown;
  bool _stop = false;

  Future<void> start() async {
    var rev = '';
    while (!_stop) {
      try {
        final j = await api.live(rev);
        if (_stop) return;
        final next = '${j['rev'] ?? ''}';
        final changed = next != rev;
        rev = next;
        if (!changed) continue;
        final online = ((j['online'] as List?) ?? const [])
            .map((e) => int.tryParse('$e') ?? 0)
            .where((e) => e > 0)
            .toSet();
        final typing = <int, List<TalkTyping>>{};
        for (final row in (j['typing'] as List?) ?? const []) {
          if (row is! Map) continue;
          final m = row.cast<String, dynamic>();
          final cid = int.tryParse('${m['channel_id']}') ?? 0;
          if (cid <= 0) continue;
          (typing[cid] ??= []).add(TalkTyping.fromJson(m));
        }
        final calls = ((j['calls'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => TalkCall.fromJson(e.cast<String, dynamic>()))
            .toList();
        onData(online, typing, calls);
      } catch (_) {
        if (_stop) return;
        onDown?.call();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  void stop() => _stop = true;
}
