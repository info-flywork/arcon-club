/// ARCONNECT (arcon_talk_api) veri modelleri — alan adları web API ile birebir.
library;

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
bool _b(Object? v) => v == true || v == 1 || v == '1';
List<Map<String, dynamic>> _l(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : const [];

class TalkUser {
  const TalkUser({required this.id, required this.username, required this.displayName, this.department = '', this.avatarPath = '', this.role = 'member', this.about = '', this.email = ''});
  factory TalkUser.fromJson(Map<String, dynamic> j) => TalkUser(
        id: _i(j['id'] ?? j['user_id']),
        username: _s(j['username']),
        displayName: _s(j['display_name']).isEmpty ? _s(j['username']) : _s(j['display_name']),
        department: _s(j['department']),
        avatarPath: _s(j['avatar_path']),
        role: _s(j['role']).isEmpty ? 'member' : _s(j['role']),
        about: _s(j['about']),
        email: _s(j['email']),
      );
  final int id;
  final String username;
  final String displayName;
  final String department;
  final String avatarPath;
  final String role;
  final String about;
  final String email;

  TalkUser copyWith({String? displayName, String? about, String? avatarPath, String? email}) => TalkUser(
        id: id,
        username: username,
        displayName: displayName ?? this.displayName,
        department: department,
        avatarPath: avatarPath ?? this.avatarPath,
        role: role,
        about: about ?? this.about,
        email: email ?? this.email,
      );
  bool get isAdmin => role == 'owner' || role == 'admin';
}

class TalkChannel {
  TalkChannel.fromJson(Map<String, dynamic> j)
      : id = _i(j['id']),
        type = _s(j['type']),
        name = _s(j['name']),
        description = _s(j['description']),
        avatarPath = _s(j['avatar_path']),
        isPrivate = _b(j['is_private']),
        memberRole = _s(j['member_role']),
        unread = _i(j['unread']),
        memberCount = _i(j['member_count']),
        lastBody = _s(j['last_body']),
        lastAt = _s(j['last_at']),
        lastUserId = _i(j['last_user_id']),
        lastReadAll = _b(j['last_read_all']),
        isSelf = _b(j['is_self']),
        peer = j['peer'] is Map ? TalkUser.fromJson((j['peer'] as Map).cast<String, dynamic>()) : null;

  final int id;
  final String type;
  String name;
  String description;
  String avatarPath;
  final bool isPrivate;
  final String memberRole;
  int unread;
  final int memberCount;
  String lastBody;
  String lastAt;
  /// son mesajı atan (liste: "Siz: …" / "Ali: …" ve tik)
  int lastUserId;
  /// diğer herkes son mesajı okudu (mavi tik)
  bool lastReadAll;

  /// WhatsApp "kendine mesaj": tek üyesi kullanıcının kendisi olan DM
  final bool isSelf;
  final TalkUser? peer;

  bool get isDm => type == 'dm';
  bool get isGroup => !isDm;

  /// Liste avatarı: kanal fotoğrafı veya DM'de karşı tarafın fotoğrafı.
  String get photo => avatarPath.isNotEmpty ? avatarPath : (peer?.avatarPath ?? '');

  /// JS `previewText`
  String get preview {
    var body = lastBody
        .replaceAll(RegExp(r'\[\[gif:[^\]]+\]\]', caseSensitive: false), 'GIF')
        .replaceAll(RegExp(r'\[\[chip:[^\]]+\]\]', caseSensitive: false), '')
        .trim();
    if (body.isEmpty) return isDm ? 'Yazışma başlat' : 'Grup oluşturdu';
    if (body.length > 56) body = '${body.substring(0, 54)}…';
    return body;
  }
}

class TalkAttachment {
  TalkAttachment.fromJson(Map<String, dynamic> j)
      : id = _i(j['id']),
        origName = _s(j['orig_name']),
        path = _s(j['path']),
        mime = _s(j['mime']),
        sizeBytes = _i(j['size_bytes']),
        isImage = _b(j['is_image']) || _s(j['mime']).startsWith('image/'),
        isAudio = _audio(j),
        // m4a sunucuda bazen video/mp4 görünür; sesli mesaj video sayılmasın
        isVideo = !_audio(j) && (_b(j['is_video']) || _s(j['mime']).startsWith('video/')),
        createdAt = _s(j['created_at']),
        displayName = _s(j['display_name']);
  final int id;
  final String origName;
  final String path;
  final String mime;
  final int sizeBytes;
  final bool isImage;
  final bool isVideo;
  final bool isAudio;
  final String createdAt;

  static bool _audio(Map<String, dynamic> j) =>
      _s(j['mime']).startsWith('audio/') || RegExp(r'\.(m4a|aac|mp3|ogg|wav)$', caseSensitive: false).hasMatch(_s(j['orig_name']));
  final String displayName;

  /// JS: uzantı, en fazla 4 harf, büyük harf
  String get ext {
    final parts = origName.split('.');
    final e = parts.length > 1 ? parts.last : 'FILE';
    return (e.length > 4 ? e.substring(0, 4) : e).toUpperCase();
  }
}

class TalkReaction {
  const TalkReaction({required this.emoji, required this.count, required this.mine});
  factory TalkReaction.fromJson(Map<String, dynamic> j) =>
      TalkReaction(emoji: _s(j['emoji']), count: _i(j['count']), mine: _b(j['mine']));
  final String emoji;
  final int count;
  final bool mine;
}

class TalkReply {
  const TalkReply({required this.id, required this.userId, required this.displayName, required this.body});
  factory TalkReply.fromJson(Map<String, dynamic> j) =>
      TalkReply(id: _i(j['id']), userId: _i(j['user_id']), displayName: _s(j['display_name']), body: _s(j['body']));
  final int id;
  final int userId;
  final String displayName;
  final String body;
}

class TalkMessage {
  TalkMessage.fromJson(Map<String, dynamic> j)
      : id = _i(j['id']),
        channelId = _i(j['channel_id']),
        userId = _i(j['user_id']),
        username = _s(j['username']),
        displayName = _s(j['display_name']),
        avatarPath = _s(j['avatar_path']),
        body = _s(j['body']),
        createdAt = _s(j['created_at']),
        edited = _b(j['edited']) || _s(j['edited_at']).isNotEmpty,
        expiresAt = _s(j['expires_at']),
        attachments = _l(j['attachments']).map(TalkAttachment.fromJson).toList(),
        reactions = _l(j['reactions']).map(TalkReaction.fromJson).toList(),
        reply = j['reply'] is Map ? TalkReply.fromJson((j['reply'] as Map).cast<String, dynamic>()) : null;

  final int id;
  final int channelId;
  final int userId;
  final String username;
  final String displayName;
  final String avatarPath;
  String body;
  final String createdAt;
  bool edited;
  final String expiresAt;
  final List<TalkAttachment> attachments;
  List<TalkReaction> reactions;
  final TalkReply? reply;

  static final _gifRe = RegExp(r'\[\[gif:(https?://[^\]\s]+)\]\]', caseSensitive: false);

  List<String> get gifs => _gifRe.allMatches(body).map((m) => m.group(1)!).toList();

  /// "Karar Kaydı" / "Toplantı Özeti" etiketleri
  List<String> get chips => [
        if (body.contains('[[chip:karar]]')) 'Karar Kaydı',
        if (body.contains('[[chip:ozet]]')) 'Toplantı Özeti',
      ];

  /// Ekranda gösterilecek düz metin (gif / chip işaretleri çıkarılmış)
  String get text => body
      .replaceAll(_gifRe, '')
      .replaceAll('[[chip:karar]]', '')
      .replaceAll('[[chip:ozet]]', '')
      .trim();
}

/// Grup bilgisi (`sidebar`)
class TalkSidebar {
  TalkSidebar.fromJson(Map<String, dynamic> j)
      : channel = (j['channel'] as Map?)?.cast<String, dynamic>() ?? const {},
        files = _l(j['files']).map(TalkAttachment.fromJson).toList(),
        activity = _l(j['activity']),
        memberCount = _i(j['member_count']),
        admins = _l(j['admins']).map(TalkUser.fromJson).toList(),
        members = _l(j['members']).map(TalkUser.fromJson).toList(),
        people = _l(j['people']).map(TalkUser.fromJson).toList(),
        myRole = _s(j['my_role']),
        canManage = _b(j['can_manage']),
        canInvite = _b(j['can_invite']),
        canSetDisappear = _b(j['can_set_disappear']),
        decisions = _l(j['decisions']).map(TalkDecision.fromJson).toList(),
        tasks = _l(j['tasks']).map(TalkTask.fromJson).toList(),
        disappearPresets = (j['disappear_presets'] is Map)
            ? (j['disappear_presets'] as Map).map((k, v) => MapEntry(_i(k), _s(v)))
            : const {86400: '24 saat', 604800: '7 gün', 7776000: '90 gün', 0: 'Kapalı'};

  final Map<String, dynamic> channel;
  final List<TalkAttachment> files;
  final List<Map<String, dynamic>> activity;
  final int memberCount;
  final List<TalkUser> admins;
  final List<TalkUser> members;
  final List<TalkUser> people;
  final String myRole;
  final bool canManage;
  final bool canInvite;
  final bool canSetDisappear;
  final Map<int, String> disappearPresets;
  /// Kararlar / Görevler (grup bilgi paneli); işlem sonrası yerinde güncellenir
  List<TalkDecision> decisions;
  List<TalkTask> tasks;

  String get name => _s(channel['name']);
  String get description => _s(channel['description']);
  String get avatarPath => _s(channel['avatar_path']);
  bool get isDm => _s(channel['type']) == 'dm';
  int get disappearSec => _i(channel['disappear_after_sec']);

  /// Kısıtlı sohbet: mesajlar başka sohbete iletilemez, sohbet dışa aktarılamaz
  bool get restricted => _b(channel['restricted']);
  String get disappearLabel =>
      _s(channel['disappear_label']).isNotEmpty ? _s(channel['disappear_label']) : (disappearPresets[disappearSec] ?? 'Kapalı');
}

class TalkTyping {
  const TalkTyping(this.userId, this.displayName);
  factory TalkTyping.fromJson(Map<String, dynamic> j) => TalkTyping(_i(j['user_id']), _s(j['display_name']));
  final int userId;
  final String displayName;
}

class TalkRtc {
  const TalkRtc({required this.appId, required this.channel, required this.uid, required this.token});
  factory TalkRtc.fromJson(Map<String, dynamic> j) => TalkRtc(
        appId: _s(j['appId']),
        channel: _s(j['channel']),
        uid: _i(j['uid']),
        token: _s(j['token']),
      );
  final String appId;
  final String channel;
  final int uid;
  final String token;
}

class TalkCallMember {
  const TalkCallMember({required this.userId, required this.state, required this.displayName, this.avatarPath = ''});
  factory TalkCallMember.fromJson(Map<String, dynamic> j) => TalkCallMember(
        userId: _i(j['user_id']),
        state: _s(j['state']),
        displayName: _s(j['display_name']),
        avatarPath: _s(j['avatar_path']),
      );
  final int userId;
  final String state;
  final String displayName;
  final String avatarPath;
}

class TalkCall {
  TalkCall.fromJson(Map<String, dynamic> j)
      : id = _i(j['id']),
        channelId = _i(j['channel_id']),
        title = _s(j['title']),
        video = _b(j['video']),
        createdBy = _i(j['created_by']),
        status = _s(j['status']),
        myState = _s(j['my_state']),
        callerName = _s(j['caller_name']),
        members = _l(j['members']).map(TalkCallMember.fromJson).toList(),
        rtc = j['rtc'] is Map ? TalkRtc.fromJson((j['rtc'] as Map).cast<String, dynamic>()) : null;

  final int id;
  final int channelId;
  final String title;
  final bool video;
  final int createdBy;
  final String status;
  final String myState;
  final String callerName;
  final List<TalkCallMember> members;
  final TalkRtc? rtc;

  bool get ringing => status == 'ringing';
  bool get live => status == 'live';

  TalkCallMember? get caller {
    for (final m in members) {
      if (m.userId == createdBy) return m;
    }
    return null;
  }

  TalkCallMember? otherMember(int myId) {
    for (final m in members) {
      if (m.userId != myId) return m;
    }
    return null;
  }
}

/// "Aramalar" listesindeki tek satır (WhatsApp arama geçmişi).
/// GIF paneli sonucu: `url` gönderilen, `preview` ızgarada gösterilen (daha hafif) adres.
class TalkGif {
  const TalkGif({required this.url, required this.preview, this.width = 200, this.height = 200});
  final String url;
  final String preview;
  final int width;
  final int height;

  factory TalkGif.fromJson(Map<String, dynamic> j) {
    final url = '${j['url'] ?? ''}';
    final preview = '${j['preview'] ?? ''}';
    return TalkGif(
      url: url,
      preview: preview.isEmpty ? url : preview,
      width: int.tryParse('${j['w']}') ?? 200,
      height: int.tryParse('${j['h']}') ?? 200,
    );
  }
}

class TalkCallLog {
  TalkCallLog.fromJson(Map<String, dynamic> j)
      : id = _i(j['id']),
        channelId = _i(j['channel_id']),
        video = _b(j['video']),
        outgoing = _b(j['outgoing']),
        missed = _b(j['missed']),
        live = _b(j['live']),
        duration = _i(j['duration']),
        createdAt = _s(j['created_at']),
        name = _s(j['name']),
        avatarPath = _s(j['avatar_path']),
        isDm = _b(j['is_dm']);

  final int id;
  final int channelId;
  final bool video;
  final bool outgoing;
  final bool missed;
  final bool live;
  final int duration;
  final String createdAt;
  final String name;
  final String avatarPath;
  final bool isDm;
}

/// Sohbete düşen arama satırı ("📞 Sesli arama · 02:13", "📞 Cevapsız sesli arama"). Değilse null.
({bool video, bool missed, String duration})? talkCallLine(String body) {
  final m = RegExp(r'^(📞|🎥) (Cevapsız )?(sesli|görüntülü|Sesli|Görüntülü) arama(?: · ([0-9:]+))?$').firstMatch(body.trim());
  if (m == null) return null;
  return (video: m.group(1) == '🎥', missed: m.group(2) != null, duration: m.group(4) ?? '');
}

/// Grupta karar olarak işaretlenmiş mesaj.
class TalkDecision {
  TalkDecision.fromJson(Map<String, dynamic> j)
      : messageId = _i(j['message_id']),
        text = _s(j['text']),
        markedBy = _s(j['marked_by']),
        userId = _i(j['user_id']),
        createdAt = _s(j['created_at']);

  final int messageId;
  final String text;
  final String markedBy;
  final int userId;
  final String createdAt;
}

/// Grup görevi (bilgi panelindeki "Görevler").
class TalkTask {
  TalkTask.fromJson(Map<String, dynamic> j)
      : id = _i(j['id']),
        title = _s(j['title']),
        messageId = _i(j['message_id']),
        done = _b(j['done']),
        createdBy = _i(j['created_by']),
        createdByName = _s(j['created_by_name']),
        createdAt = _s(j['created_at']),
        assignees = [for (final a in _l(j['assignees'])) (id: _i(a['id']), name: _s(a['name']))];

  final int id;
  final String title;
  final int messageId;

  /// Görevde etiketlenen kişiler (her birine ARCON TO-DO kartı açılır)
  final List<({int id, String name})> assignees;
  final bool done;
  final int createdBy;
  final String createdByName;
  final String createdAt;
}
