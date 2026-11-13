import 'package:arcon_club/arcon_core.dart';
import 'package:flutter/material.dart';

/// ARCON Club — menü ve ekranlar ARCON sunucusundan gelir; webde açılan modül burada da görünür.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ArconApp(
      config: ArconAppConfig(
        appKey: 'club',
        title: 'ARCON CLUB',
        startModuleKey: null,
      ),
    ),
  );
}
