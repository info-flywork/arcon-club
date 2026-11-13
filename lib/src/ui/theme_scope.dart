import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web'deki "Tema Değiştir" (localStorage `arcon-theme`) karşılığı: seçim yoksa telefonun teması.
class ArconThemeController extends ValueNotifier<ThemeMode> {
  ArconThemeController() : super(ThemeMode.system) {
    _load();
  }

  static const _key = 'arcon-theme';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    value = switch (p.getString(_key)) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  bool isDark(BuildContext context) =>
      value == ThemeMode.dark || (value == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);

  /// Webdeki tema düğmesinden gelen seçim (uygulama ve web aynı temada kalsın).
  Future<void> setDark(bool dark) async {
    final next = dark ? ThemeMode.dark : ThemeMode.light;
    if (value == next) return;
    value = next;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, dark ? 'dark' : 'light');
  }

  Future<void> toggle(BuildContext context) async {
    value = isDark(context) ? ThemeMode.light : ThemeMode.dark;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, value == ThemeMode.dark ? 'dark' : 'light');
  }
}

class ArconThemeScope extends InheritedNotifier<ArconThemeController> {
  const ArconThemeScope({super.key, required ArconThemeController controller, required super.child})
      : super(notifier: controller);

  static ArconThemeController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArconThemeScope>()!.notifier!;
}
