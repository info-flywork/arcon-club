# ARCON Club (mobil)

ARCON panelinin mobil uygulaması (iOS + Android, Flutter). Menü ve modüller ARCON sunucusundan (`https://arconai.net/app/`) gelir; ARCONNECT, ARCON AI ve ARCON TO-DO uygulama içinde, diğer modüller WebView'da açılır.

Bu repo **tek başına çalışır**: uygulamanın ekranlarının çoğu `packages/arcon_core` klasöründeki ortak çekirdektedir ve repoyla birlikte gelir.

## Çalıştırma

```bash
flutter pub get
flutter run
```

- Android APK: `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
- iOS: `ios/Runner.xcworkspace` Xcode'da açılır → Product › Archive → Distribute App › App Store Connect
- Her yeni sürümde `pubspec.yaml` içindeki `version:` satırında `+` sonrasındaki build numarası bir artırılır.

## Klasörler

| Klasör | İçerik |
| --- | --- |
| `lib/main.dart` | Uygulamanın girişi (uygulama anahtarı `club`, başlık) |
| `packages/arcon_core/` | Ortak çekirdek: giriş, modül menüsü, ARCONNECT (sohbet, arama), ARCON AI, bildirimler |
| `android/`, `ios/` | Platform ayarları (paket kimliği `net.arconai.arconClub`) |

## Notlar

- `packages/arcon_core`, ARCONNECT uygulamasıyla ortak kullanılan çekirdeğin bir kopyasıdır (asıl kaynak: `info-flywork/original-arconnect` reposunda `packages/arcon_core`). ARCONNECT tarafında yapılan değişiklikler Club'a otomatik gelmez; gerektiğinde bu klasör o reponun güncel haliyle değiştirilir.
- Android derlemesi için `android/build.gradle.kts` içinde kamera eklentisine `androidx.concurrent:concurrent-futures` eklendi (CameraX 1.5.3 ile gerekli); silinmemeli.
- Sunucu adresi derlerken değiştirilebilir: `flutter run --dart-define=ARCON_API_BASE=http://127.0.0.1:8088/`
