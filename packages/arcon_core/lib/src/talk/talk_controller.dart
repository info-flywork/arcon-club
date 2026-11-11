import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../auth/session_controller.dart';
import '../push/local_notifier.dart';
import 'agora_service.dart';
import 'talk_api.dart';
import 'talk_live.dart';
import 'talk_models.dart';

enum TalkFilter { all, unread, favourites, groups }

/// Sohbet listesi durumu (web: state.channels, filtreler, favoriler).
class TalkController extends ChangeNotifier {
  TalkController({required this.session, required String baseUrl})
      : api = TalkApi(arcon: session.api, baseUrl: baseUrl);

  final SessionController session;
  final TalkApi api;

  TalkUser? me;
  List<TalkChannel> channels = [];
  List<TalkUser> users = [];
  TalkFilter filter = TalkFilter.all;
  String query = '';
  Set<int> favourites = {};
  bool loading = true;
  String? error;
  Set<int> online = {};
  Map<int, List<TalkTyping>> typingByChannel = {};
  bool live = false;
  List<TalkCall> calls = [];
  Timer? _timer;
  TalkLive? _live;

  /// kanal id → gönderilmemiş yazı (WhatsApp'taki "Taslak")
  Map<int, String> drafts = {};

  /// Sessize alınan sohbetler (yalnızca bu telefonda; bildirim gelmez)
  Set<int> muted = {};

  /// WhatsApp "Arşivlenmiş": ana listede görünmez, üstteki satırdan açılır (yalnızca bu telefonda)
  Set<int> archived = {};

  String get _favKey => 'arcon_talk_favs_${me?.id ?? 0}';
  String get _draftKey => 'arcon_talk_drafts_${me?.id ?? 0}';
  String get _mutedKey => 'arcon_talk_muted_${me?.id ?? 0}';
  String get _archKey => 'arcon_talk_archived_${me?.id ?? 0}';
  String get _lockKey => 'arcon_talk_locked_${me?.id ?? 0}';
  String get _listsKey => 'arcon_talk_lists_${me?.id ?? 0}';

  /// WhatsApp "Sohbeti kilitle": listede görünmez, "Kilitli sohbetler"den Face ID ile açılır (yalnızca bu telefonda)
  Set<int> locked = {};

  /// WhatsApp "Listeye ekle": ad → sohbet id'leri; sohbet listesinde çip olarak görünür (yalnızca bu telefonda)
  Map<String, Set<int>> lists = {};

  /// Seçili liste çipi (doluysa [filter] yerine bu listeye göre süzülür)
  String? listFilter;

  Future<void> start() async {
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      refresh(silent: true);
      api.presence().catchError((_) {});
    });
    api.presence().catchError((_) {});
    _live = TalkLive(api, _applyLive, onDown: () {
      if (!live) return;
      live = false;
      notifyListeners();
    });
    unawaited(_live!.start());
  }

  void _applyLive(Set<int> ids, Map<int, List<TalkTyping>> typing, List<TalkCall> nextCalls) {
    online = ids;
    typingByChannel = typing;
    calls = nextCalls;
    AgoraService.instance.serverCalls.value = {for (final c in nextCalls) c.id};
    live = true;
    notifyListeners();
  }

  TalkCall? get incomingCall {
    final uid = me?.id ?? 0;
    for (final c in calls) {
      if (c.ringing && c.createdBy != uid && c.myState == 'ringing') return c;
    }
    return null;
  }

  TalkCall? liveCallOn(int channelId) {
    for (final c in calls) {
      if (c.channelId == channelId && (c.ringing || c.live)) return c;
    }
    return null;
  }

  List<TalkTyping> typingOf(int channelId) => typingByChannel[channelId] ?? const [];

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      error = null;
      notifyListeners();
    }
    try {
      final b = await api.bootstrap();
      final firstLoad = me == null;
      me = b.me;
      channels = b.channels;
      users = b.users;
      if (firstLoad) {
        final p = await SharedPreferences.getInstance();
        favourites = (p.getStringList(_favKey) ?? const []).map(int.parse).toSet();
        muted = (p.getStringList(_mutedKey) ?? const []).map(int.parse).toSet();
        archived = (p.getStringList(_archKey) ?? const []).map(int.parse).toSet();
        locked = (p.getStringList(_lockKey) ?? const []).map(int.parse).toSet();
        try {
          final raw = jsonDecode(p.getString(_listsKey) ?? '{}') as Map<String, dynamic>;
          lists = {
            for (final e in raw.entries) e.key: {for (final v in (e.value as List)) (v as num).toInt()},
          };
        } catch (_) {
          lists = {};
        }
        LocalNotifier.muted = {...muted};
        try {
          final raw = jsonDecode(p.getString(_draftKey) ?? '{}') as Map<String, dynamic>;
          drafts = {for (final e in raw.entries) int.parse(e.key): '${e.value}'};
        } catch (_) {
          drafts = {};
        }
      }
      error = null;
    } on ArconApiException catch (e) {
      await session.handleError(e);
      if (!silent) error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// JS `splitChannels` + filtre + arama
  List<TalkChannel> get visible {
    final q = query.trim().toLowerCase();
    return channels.where((c) {
      // kilitli sohbetler hiçbir zaman ana listede (aramada da) görünmez
      if (locked.contains(c.id)) return false;
      // arşivdekiler yalnızca aramada görünür
      if (archived.contains(c.id) && q.isEmpty) return false;
      final list = listFilter;
      if (list != null) {
        if (!(lists[list]?.contains(c.id) ?? false)) return false;
      } else {
        switch (filter) {
          case TalkFilter.unread:
            if (c.unread <= 0) return false;
          case TalkFilter.favourites:
            if (!favourites.contains(c.id)) return false;
          case TalkFilter.groups:
            if (c.isDm) return false;
          case TalkFilter.all:
            break;
        }
      }
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q);
    }).toList();
  }

  void setFilter(TalkFilter f) {
    filter = f;
    listFilter = null;
    notifyListeners();
  }

  void setListFilter(String? name) {
    listFilter = name;
    filter = TalkFilter.all;
    notifyListeners();
  }

  List<TalkChannel> get lockedChannels => channels.where((c) => locked.contains(c.id)).toList();

  Future<void> toggleLock(int id) async {
    locked.contains(id) ? locked.remove(id) : locked.add(id);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_lockKey, locked.map((e) => '$e').toList());
  }

  Future<void> _saveLists() async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_listsKey, jsonEncode({for (final e in lists.entries) e.key: e.value.toList()}));
  }

  /// Sohbeti listeye ekle / listeden çıkar; liste yoksa oluşturulur
  Future<void> toggleInList(String name, int channelId) async {
    final set = lists.putIfAbsent(name, () => <int>{});
    set.contains(channelId) ? set.remove(channelId) : set.add(channelId);
    await _saveLists();
  }

  Future<void> createList(String name) async {
    lists.putIfAbsent(name, () => <int>{});
    await _saveLists();
  }

  Future<void> deleteList(String name) async {
    lists.remove(name);
    if (listFilter == name) listFilter = null;
    await _saveLists();
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  Future<void> toggleFavourite(int id) async {
    favourites.contains(id) ? favourites.remove(id) : favourites.add(id);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_favKey, favourites.map((e) => '$e').toList());
  }

  Future<void> toggleMute(int id) async {
    muted.contains(id) ? muted.remove(id) : muted.add(id);
    LocalNotifier.muted = {...muted};
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_mutedKey, muted.map((e) => '$e').toList());
  }

  List<TalkChannel> get archivedChannels => channels.where((c) => archived.contains(c.id)).toList();

  Future<void> toggleArchive(int id) async {
    archived.contains(id) ? archived.remove(id) : archived.add(id);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_archKey, archived.map((e) => '$e').toList());
  }

  String draftOf(int channelId) => drafts[channelId] ?? '';

  /// Sohbetten çıkarken çağrılır; boş yazı taslağı siler.
  Future<void> setDraft(int channelId, String text) async {
    final t = text.trim().isEmpty ? '' : text;
    if (draftOf(channelId) == t) return;
    t.isEmpty ? drafts.remove(channelId) : drafts[channelId] = t;
    // sohbet ekranı kapanırken (ağaç kilitliyken) listeyi hemen yeniden çizdirmeyelim
    scheduleMicrotask(notifyListeners);
    final p = await SharedPreferences.getInstance();
    await p.setString(_draftKey, jsonEncode({for (final e in drafts.entries) '${e.key}': e.value}));
  }

  Future<void> hideChat(TalkChannel c) async {
    await api.hideChat(c.id);
    channels.removeWhere((x) => x.id == c.id);
    notifyListeners();
  }

  /// WhatsApp "Gruptan çık": üyelikten çıkar, listeden kaldır.
  Future<void> leaveChannel(TalkChannel c) async {
    await api.leaveChannel(c.id);
    channels.removeWhere((x) => x.id == c.id);
    notifyListeners();
  }

  void setMe(TalkUser user) {
    me = user;
    notifyListeners();
  }

  void upsertChannel(TalkChannel ch) {
    final i = channels.indexWhere((c) => c.id == ch.id);
    if (i >= 0) {
      channels[i] = ch;
    } else {
      channels.insert(0, ch);
    }
    notifyListeners();
  }

  void markRead(int id) {
    for (final c in channels) {
      if (c.id == id) c.unread = 0;
    }
    notifyListeners();
  }

  void updateLast(int channelId, String body, String at, {int? userId}) {
    for (final c in channels) {
      if (c.id == channelId) {
        if (userId != null && (c.lastAt != at || c.lastUserId != userId)) c.lastReadAll = false;
        c
          ..lastBody = body
          ..lastAt = at;
        if (userId != null) c.lastUserId = userId;
      }
    }
    channels.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    notifyListeners();
  }

  @override
  void dispose() {
    _live?.stop();
    _timer?.cancel();
    super.dispose();
  }
}
