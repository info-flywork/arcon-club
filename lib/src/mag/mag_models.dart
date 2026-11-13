/// ARCON MAG verisi (`/api/v1/mag`), webdeki arcon-mag ile aynı kaynak.
library;

int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

class MagCategory {
  const MagCategory({required this.key, required this.label, this.count = 0});
  factory MagCategory.fromJson(Map<String, dynamic> j) =>
      MagCategory(key: j['key'] as String? ?? '', label: j['label'] as String? ?? '', count: _i(j['count']));
  final String key;
  final String label;
  final int count;
}

/// Liste kartındaki haber özeti.
class MagPostSummary {
  const MagPostSummary({
    required this.id,
    required this.slug,
    required this.title,
    this.excerpt = '',
    this.category = '',
    this.categoryLabel = '',
    this.coverUrl = '',
    this.author = '',
    this.publishedAt,
    this.readingMinutes = 1,
    this.views = 0,
    this.featured = false,
    this.mandatory = false,
    this.eventAt,
    this.eventLocation = '',
    this.read = false,
  });

  factory MagPostSummary.fromJson(Map<String, dynamic> j) => MagPostSummary(
    id: _i(j['id']),
    slug: j['slug'] as String? ?? '',
    title: j['title'] as String? ?? '',
    excerpt: j['excerpt'] as String? ?? '',
    category: j['category'] as String? ?? '',
    categoryLabel: j['category_label'] as String? ?? '',
    coverUrl: j['cover_url'] as String? ?? '',
    author: j['author'] as String? ?? '',
    publishedAt: _d(j['published_at']),
    readingMinutes: _i(j['reading_minutes']).clamp(1, 999),
    views: _i(j['views']),
    featured: j['featured'] == true,
    mandatory: j['mandatory'] == true,
    eventAt: _d(j['event_at']),
    eventLocation: j['event_location'] as String? ?? '',
    read: j['read'] == true,
  );

  final int id;
  final String slug;
  final String title;
  final String excerpt;
  final String category;
  final String categoryLabel;
  final String coverUrl;
  final String author;
  final DateTime? publishedAt;
  final int readingMinutes;
  final int views;
  final bool featured;

  /// Herkesin "okudum" demesi gereken duyuru.
  final bool mandatory;
  final DateTime? eventAt;
  final String eventLocation;
  final bool read;

  MagPostSummary markRead() => MagPostSummary(
    id: id,
    slug: slug,
    title: title,
    excerpt: excerpt,
    category: category,
    categoryLabel: categoryLabel,
    coverUrl: coverUrl,
    author: author,
    publishedAt: publishedAt,
    readingMinutes: readingMinutes,
    views: views,
    featured: featured,
    mandatory: mandatory,
    eventAt: eventAt,
    eventLocation: eventLocation,
    read: true,
  );
}

class MagFeed {
  const MagFeed({
    this.category = 'all',
    this.categories = const [],
    this.cover,
    this.posts = const [],
    this.tags = const [],
    this.unreadCount = 0,
    this.savedCount = 0,
    this.likedCount = 0,
  });

  factory MagFeed.fromJson(Map<String, dynamic> j) => MagFeed(
    category: j['category'] as String? ?? 'all',
    categories: ((j['categories'] as List?) ?? const []).cast<Map>().map((m) => MagCategory.fromJson(m.cast<String, dynamic>())).toList(),
    cover: j['cover'] is Map ? MagPostSummary.fromJson((j['cover'] as Map).cast<String, dynamic>()) : null,
    posts: _posts(j['posts']),
    tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
    unreadCount: _i(j['unread_count']),
    savedCount: _i(j['saved_count']),
    likedCount: _i(j['liked_count']),
  );

  final String category;
  final List<MagCategory> categories;
  final MagPostSummary? cover;
  final List<MagPostSummary> posts;
  final List<String> tags;
  final int unreadCount;
  final int savedCount;
  final int likedCount;
}

List<MagPostSummary> _posts(Object? v) =>
    ((v as List?) ?? const []).cast<Map>().map((m) => MagPostSummary.fromJson(m.cast<String, dynamic>())).toList();

List<MagPostSummary> magPostsFromJson(Object? v) => _posts(v);

/// Haber gövdesinin bir parçası: p, h2, h3, quote, li, img.
class MagBlock {
  const MagBlock({required this.type, this.text = '', this.url = ''});
  factory MagBlock.fromJson(Map<String, dynamic> j) =>
      MagBlock(type: j['type'] as String? ?? 'p', text: j['text'] as String? ?? '', url: j['url'] as String? ?? '');
  final String type;
  final String text;
  final String url;
}

class MagReactionType {
  const MagReactionType({required this.key, required this.emoji});
  final String key;
  final String emoji;
}

class MagPost {
  MagPost({
    required this.summary,
    this.blocks = const [],
    this.tags = const [],
    this.likes = 0,
    this.liked = false,
    this.saved = false,
    this.reactionTypes = const [],
    this.reactions = const {},
    this.myReactions = const {},
    this.acked = false,
    this.ackCount = 0,
    this.webPath = '',
    this.related = const [],
  });

  factory MagPost.fromJson(Map<String, dynamic> j) {
    final p = (j['post'] as Map).cast<String, dynamic>();
    return MagPost(
      summary: MagPostSummary.fromJson(p),
      blocks: ((p['blocks'] as List?) ?? const []).cast<Map>().map((m) => MagBlock.fromJson(m.cast<String, dynamic>())).toList(),
      tags: ((p['tags'] as List?) ?? const []).map((e) => '$e').toList(),
      likes: _i(p['likes']),
      liked: p['liked'] == true,
      saved: p['saved'] == true,
      reactionTypes: ((p['reaction_types'] as List?) ?? const [])
          .cast<Map>()
          .map((m) => MagReactionType(key: '${m['key']}', emoji: '${m['emoji']}'))
          .toList(),
      reactions: _counts(p['reactions']),
      myReactions: ((p['my_reactions'] as List?) ?? const []).map((e) => '$e').toSet(),
      acked: p['acked'] == true,
      ackCount: _i(p['ack_count']),
      webPath: p['web_path'] as String? ?? '',
      related: _posts(j['related']),
    );
  }

  final MagPostSummary summary;
  final List<MagBlock> blocks;
  final List<String> tags;
  int likes;
  bool liked;
  bool saved;
  final List<MagReactionType> reactionTypes;
  Map<String, int> reactions;
  Set<String> myReactions;
  bool acked;
  int ackCount;
  final String webPath;
  final List<MagPostSummary> related;
}

Map<String, int> magCounts(Object? v) => _counts(v);

Map<String, int> _counts(Object? v) {
  if (v is! Map) return {};
  return v.map((k, val) => MapEntry('$k', _i(val)));
}
