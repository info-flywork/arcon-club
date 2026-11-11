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
}
