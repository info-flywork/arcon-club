import 'package:flutter/widgets.dart';

import 'api/models.dart';
import 'auth/session_controller.dart';

/// Bir modülü yerli (Flutter) ekranla açan kurucu. Backend bir modülü
/// `render: "native"` yaptığında ve burada karşılığı varsa bu ekran açılır;
/// yoksa modül WebView'de açılır (eski uygulama sürümleri bozulmaz).
typedef NativeModuleBuilder = Widget Function(BuildContext context, ArconModule module, SessionController session);

/// Uygulamaya özgü ayarlar. ARCON Club ve ARCONNECT aynı çekirdeği bu ayarla kullanır.
class ArconAppConfig {
  const ArconAppConfig({
    required this.appKey,
    required this.title,
    this.startModuleKey,
    this.apiBase = defaultApiBase,
    this.nativeModules = const {},
    this.push = false,
  });

  /// Backend'deki uygulama anahtarı: `club` veya `arconnect`.
  final String appKey;
  final String title;

  /// Doluysa bu modül ilk sekmede doğrudan açılır (ARCONNECT için `arconnect`).
  final String? startModuleKey;

  /// Web uygulamasının kökü, sonu `/` ile biter. Örn. `https://arconai.net/app/`.
  final String apiBase;

  final Map<String, NativeModuleBuilder> nativeModules;

  /// Uygulama kapalıyken bildirim (Firebase). Firebase dosyaları uygulamaya eklenmemişse
  /// başlatma sessizce başarısız olur, uygulama yerel bildirimlerle devam eder.
  final bool push;

  /// Derlerken değiştirilebilir:
  /// `flutter run --dart-define=ARCON_API_BASE=http://127.0.0.1:8088/`
  static const String defaultApiBase = String.fromEnvironment(
    'ARCON_API_BASE',
    defaultValue: 'https://arconai.net/app/',
  );

  /// ARCONNECT: web bu işareti (ArconConnectApp) görünce üst menüyü gizleyip
  /// Talk uygulama görünümüne geçer (mevcut ARCONNECT WebView uygulamasıyla aynı).
  /// Club: işaret yok → sayfalar webin mobil görünümüyle (üst menü, hamburger) birebir açılır.
  String get userAgentSuffix =>
      appKey == 'arconnect' ? 'ArconConnectApp ArconMobile/$appKey' : 'ArconMobile/$appKey';
}
