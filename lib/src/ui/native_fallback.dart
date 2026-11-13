import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/session_controller.dart';
import '../config.dart';
import 'module_webview.dart';

/// Sunucuda yerli ekranın ucu yoksa (henüz yüklenmemiş / eski sürüm): 404, 5xx ya da JSON olmayan yanıt.
bool serverLacksApi(ArconApiException e) => e.status == 404 || e.status >= 500 || e.code == 'bad_response';

/// Yerli ekran yerine aynı modülü WebView'de açar ([path] verilirse o sayfayı).
void openWebFallback(
  BuildContext context, {
  required SessionController session,
  required ArconAppConfig config,
  required String title,
  required String path,
  bool replace = true,
}) {
  final m = ArconModule(
    key: 'path:$path',
    title: title,
    group: 'main',
    icon: '',
    render: 'webview',
    path: path,
    url: Uri.parse(config.apiBase).resolve(path).toString(),
  );
  final route = MaterialPageRoute<void>(
    builder: (_) => ModuleScreen(module: m, session: session, config: config),
  );
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}
