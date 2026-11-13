/// Giriş yapan kullanıcı (`/api/v1/me`).
class ArconUser {
  const ArconUser({
    required this.id,
    required this.username,
    required this.email,
    required this.roleId,
    required this.roleName,
    required this.isAdmin,
    required this.isBeta,
    this.accountMenu = const [],
    this.avatarUrl,
  });

  factory ArconUser.fromJson(Map<String, dynamic> j) => ArconUser(
        id: (j['id'] as num).toInt(),
        username: j['username'] as String? ?? '',
        email: j['email'] as String? ?? '',
        roleId: (j['role_id'] as num?)?.toInt() ?? 0,
        roleName: j['role_name'] as String? ?? '',
        isAdmin: j['is_admin'] == true,
        isBeta: j['is_beta'] == true,
        avatarUrl: j['avatar_url'] as String?,
        accountMenu: ((j['account_menu'] as List?) ?? const [])
            .cast<Map>()
            .map((m) => AccountMenuSection.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  final int id;
  final String username;
  final String email;
  final int roleId;
  final String roleName;
  final bool isAdmin;
  final bool isBeta;

  /// Webdeki kullanıcı menüsü (header.php #userMenu), sunucudan yetkiye göre.
  final List<AccountMenuSection> accountMenu;

  /// Profil fotoğrafı (ARCONNECT ile ortak); yoksa null.
  final String? avatarUrl;

  String get initials {
    final s = username.trim();
    return s.isEmpty ? '?' : s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
  }
}

class AccountMenuSection {
  const AccountMenuSection({required this.section, required this.items});
  factory AccountMenuSection.fromJson(Map<String, dynamic> j) => AccountMenuSection(
        section: j['section'] as String? ?? '',
        items: ((j['items'] as List?) ?? const [])
            .cast<Map>()
            .map((i) => AccountMenuItem.fromJson(i.cast<String, dynamic>()))
            .toList(),
      );
  final String section;
  final List<AccountMenuItem> items;
}

class AccountMenuItem {
  const AccountMenuItem({required this.title, required this.path, this.subtitle = '', this.kind = ''});
  factory AccountMenuItem.fromJson(Map<String, dynamic> j) => AccountMenuItem(
        title: j['title'] as String? ?? '',
        path: j['path'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        kind: j['kind'] as String? ?? '',
      );
  final String title;
  final String path;
  final String subtitle;
  final String kind;
}

/// Menüdeki bir modül (`/api/v1/modules`). Liste tamamen sunucudan gelir:
/// webde açılan modül burada kendiliğinden görünür.
class ArconModule {
  const ArconModule({
    required this.key,
    required this.title,
    required this.group,
    required this.icon,
    required this.render,
    required this.path,
    required this.url,
    this.description = '',
    this.iconUrl,
    this.iconSvg,
    this.iconStyle,
    this.tool,
    this.external,
  });

  factory ArconModule.fromJson(Map<String, dynamic> j) => ArconModule(
        key: j['key'] as String,
        title: j['title'] as String? ?? '',
        group: j['group'] as String? ?? 'main',
        icon: j['icon'] as String? ?? '',
        render: j['render'] as String? ?? 'webview',
        path: j['path'] as String? ?? '',
        url: j['url'] as String? ?? '',
        description: j['description'] as String? ?? '',
        iconUrl: j['icon_url'] as String?,
        iconSvg: j['icon_svg'] as String?,
        iconStyle: j['icon_style'] as String?,
        tool: j['tool'] as String?,
        external: j['external'] is Map ? ExternalApp.fromJson((j['external'] as Map).cast<String, dynamic>()) : null,
      );

  final String key;
  final String title;

  /// `main`, `ai_modules` veya `account`.
  final String group;
  final String icon;

  /// `webview` ya da `native`.
  final String render;

  /// Web uygulamasındaki göreli yol, örn. `arcon-todo`.
  final String path;
  final String url;
  final String description;

  /// Webdeki modül kartı ikonu (PNG). Yoksa [iconSvg], o da yoksa webin varsayılan kartı.
  final String? iconUrl;
  final String? iconSvg;

  /// `lucide`: webdeki Modüllerim kartı (siyah kutu, beyaz çizgi ikon).
  final String? iconStyle;

  /// AI modülünün gömülü araç klasörü (`hr-ai`, `lawpath`, `givenchy` …); yerli araç ekranını seçmek için.
  final String? tool;

  /// Doluysa modül ayrı bir mağaza uygulamasıdır (Club'da ARCONNECT): yüklüyse o açılır, değilse mağaza.
  final ExternalApp? external;
}

/// Ayrı mağaza uygulaması bağlantıları — backend'den (`mobile_external_apps`) gelir.
class ExternalApp {
  const ExternalApp({
    this.name = '',
    this.iosScheme = '',
    this.iosStoreUrl = '',
    this.androidScheme = '',
    this.androidPackage = '',
    this.androidStoreUrl = '',
  });

  factory ExternalApp.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] as String? ?? '').trim();
    return ExternalApp(
      name: s('name'),
      iosScheme: s('ios_scheme'),
      iosStoreUrl: s('ios_store_url'),
      androidScheme: s('android_scheme'),
      androidPackage: s('android_package'),
      androidStoreUrl: s('android_store_url'),
    );
  }

  /// Backend henüz göndermezse Club'daki ARCONNECT düğmesi bunu kullanır.
  static const arconnect = ExternalApp(
    name: 'ARCONNECT',
    iosScheme: 'arconnect://',
    iosStoreUrl: 'https://apps.apple.com/app/id6829730899',
    androidScheme: 'arconnect://',
    androidPackage: 'net.arconai.arconnect',
  );

  final String name;
  final String iosScheme;
  final String iosStoreUrl;
  final String androidScheme;
  final String androidPackage;
  final String androidStoreUrl;
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Ana sayfa verisi (`/api/v1/dashboard`), webdeki Dashboard ile aynı kaynak.
class DashboardData {
  const DashboardData({this.notices = const [], this.features = const [], this.admin});

  factory DashboardData.fromJson(Map<String, dynamic> j) => DashboardData(
        notices: ((j['notices'] as List?) ?? const [])
            .cast<Map>()
            .map((m) => DashboardNotice.fromJson(m.cast<String, dynamic>()))
            .toList(),
        features: ((j['features'] as List?) ?? const [])
            .cast<Map>()
            .map((m) => DashboardFeature.fromJson(m.cast<String, dynamic>()))
            .toList(),
        admin: j['admin'] is Map ? DashboardAdmin.fromJson((j['admin'] as Map).cast<String, dynamic>()) : null,
      );

  /// Üstteki durum kartları (Mag, Score, Academy, Idea, Feedback).
  final List<DashboardNotice> notices;

  /// Ürün kartları; anahtar `/api/v1/modules` ile aynı.
  final List<DashboardFeature> features;

  /// Yalnızca yöneticide dolu.
  final DashboardAdmin? admin;
}

class DashboardNotice {
  const DashboardNotice({
    required this.key,
    required this.kicker,
    required this.title,
    required this.body,
    required this.cta,
    required this.path,
    required this.moduleKey,
    this.count = 0,
  });

  factory DashboardNotice.fromJson(Map<String, dynamic> j) => DashboardNotice(
        key: j['key'] as String? ?? '',
        kicker: j['kicker'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        cta: j['cta'] as String? ?? '',
        path: j['path'] as String? ?? '',
        moduleKey: j['module_key'] as String? ?? '',
        count: _int(j['count']),
      );

  final String key;
  final String kicker;
  final String title;
  final String body;
  final String cta;

  /// Webde açılacak yol (ör. okunmamış haberin detayı).
  final String path;
  final String moduleKey;
  final int count;
}

class DashboardFeature {
  const DashboardFeature({required this.key, required this.name, required this.description, this.badge = 0});

  factory DashboardFeature.fromJson(Map<String, dynamic> j) => DashboardFeature(
        key: j['key'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String? ?? '',
        badge: _int(j['badge']),
      );

  final String key;

  /// "ARCON" + bu ad (AI, NECT, MAG …).
  final String name;
  final String description;
  final int badge;
}

class DashboardAdmin {
  const DashboardAdmin({
    required this.users,
    required this.activeUsers7d,
    required this.modules,
    required this.roles,
    required this.openTickets,
    this.logs,
    this.logsToday,
    this.activities = const [],
  });

  factory DashboardAdmin.fromJson(Map<String, dynamic> j) => DashboardAdmin(
        users: _int(j['users']),
        activeUsers7d: _int(j['active_users_7d']),
        modules: _int(j['modules']),
        roles: _int(j['roles']),
        openTickets: _int(j['open_tickets']),
        logs: j['logs'] == null ? null : _int(j['logs']),
        logsToday: j['logs_today'] == null ? null : _int(j['logs_today']),
        activities: ((j['activities'] as List?) ?? const [])
            .cast<Map>()
            .map((m) => DashboardActivity.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  final int users;
  final int activeUsers7d;
  final int modules;
  final int roles;
  final int openTickets;
  final int? logs;
  final int? logsToday;
  final List<DashboardActivity> activities;
}

class DashboardActivity {
  const DashboardActivity({required this.module, required this.action, required this.user, this.at});

  factory DashboardActivity.fromJson(Map<String, dynamic> j) => DashboardActivity(
        module: j['module'] as String? ?? '',
        action: j['action'] as String? ?? '',
        user: j['user'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? ''),
      );

  final String module;
  final String action;
  final String user;
  final DateTime? at;
}

/// Profil ekranı (`/api/v1/profile`): kullanıcı + Academy rozet özeti.
class ProfileData {
  const ProfileData({required this.user, this.academy});

  factory ProfileData.fromJson(Map<String, dynamic> j) => ProfileData(
        user: ArconUser.fromJson((j['user'] as Map).cast<String, dynamic>()),
        academy: j['academy'] is Map ? AcademySummary.fromJson((j['academy'] as Map).cast<String, dynamic>()) : null,
      );

  final ArconUser user;
  final AcademySummary? academy;
}

class AcademySummary {
  const AcademySummary({required this.done, required this.total, this.master = false, this.streak, this.badges = const []});

  factory AcademySummary.fromJson(Map<String, dynamic> j) => AcademySummary(
        done: _int(j['done']),
        total: _int(j['total']),
        master: j['master'] == true,
        streak: j['streak'] == null ? null : _int(j['streak']),
        badges: ((j['badges'] as List?) ?? const [])
            .cast<Map>()
            .map((m) => AcademyBadge.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  final int done;
  final int total;
  final bool master;
  final int? streak;
  final List<AcademyBadge> badges;
}

class AcademyBadge {
  const AcademyBadge({required this.label, required this.done, required this.total, this.earned = false});

  factory AcademyBadge.fromJson(Map<String, dynamic> j) => AcademyBadge(
        label: j['label'] as String? ?? '',
        done: _int(j['done']),
        total: _int(j['total']),
        earned: j['earned'] == true,
      );

  final String label;
  final int done;
  final int total;
  final bool earned;
}
