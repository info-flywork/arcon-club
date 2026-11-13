import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';

/// Ayrı mağaza uygulamasını açar: önce URL şemasıyla (yüklüyse uygulama açılır),
/// olmazsa mağaza sayfasına gider. İkisi de yapılamazsa `false` döner
/// (çağıran modülü uygulamanın içinde açar).
Future<bool> openExternalApp(ExternalApp app) async {
  if (kIsWeb) return false;
  final ios = Platform.isIOS;
  final scheme = ios ? app.iosScheme : app.androidScheme;
  final store = ios ? app.iosStoreUrl : app.androidStoreUrl;

  final appUri = Uri.tryParse(scheme);
  if (scheme.isNotEmpty && appUri != null && appUri.hasScheme) {
    try {
      if (await launchUrl(appUri, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {
      // uygulama yüklü değil → mağaza
    }
  }

  final storeUri = Uri.tryParse(store);
  if (store.isNotEmpty && storeUri != null && storeUri.hasScheme) {
    // Android: Play uygulaması varsa doğrudan onda aç
    if (!ios && app.androidPackage.isNotEmpty) {
      try {
        if (await launchUrl(Uri.parse('market://details?id=${app.androidPackage}'), mode: LaunchMode.externalApplication)) return true;
      } catch (_) {}
    }
    try {
      return await launchUrl(storeUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  return false;
}
