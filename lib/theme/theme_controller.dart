//
//  theme_controller.dart
//
//  Drives the app-wide appearance (跟随系统 / 浅色 / 深色) and the bottom tab-bar
//  style (经典 / 系统). The chosen mode is persisted in SharedPreferences and
//  applied at the app root via MaterialApp.themeMode. All color tokens in
//  AppColors are adaptive, so flipping the scheme re-resolves every surface.
//

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

enum AppearanceMode {
  system('跟随系统', Icons.contrast),
  light('浅色', Icons.light_mode),
  dark('深色', Icons.dark_mode);

  const AppearanceMode(this.label, this.icon);
  final String label;
  final IconData icon;

  ThemeMode get themeMode => switch (this) {
    AppearanceMode.system => ThemeMode.system,
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
  };
}

/// Classic flat bar (default) or the system tab bar.
enum TabBarStyle {
  classic('经典', Icons.view_week),
  system('系统', Icons.auto_awesome);

  const TabBarStyle(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) {
    _mode = AppearanceMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_modeKey),
      orElse: () => AppearanceMode.system,
    );
    _tabBarStyle = TabBarStyle.values.firstWhere(
      (s) => s.name == _prefs.getString(_tabKey),
      orElse: () => TabBarStyle.classic, // flat bar by default
    );
    _brandColor = Color(
      _prefs.getInt(_brandKey) ?? (0xFF000000 | AppTheme.defaultBrand),
    );
    _fontScale = _prefs.getDouble(_fontKey) ?? 1.0;
    AppTheme.applyBrand(_brandColor); // before the first MaterialApp build
  }

  static const _modeKey = 'appearanceMode';
  static const _tabKey = 'tabBarStyle';
  static const _brandKey = 'brandColor';
  static const _fontKey = 'fontScale';

  /// Selectable text-scale steps for the 字体大小 control (小 / 标准 / 大 / 超大).
  /// Capped at 1.3 so fixed-height chrome doesn't overflow badly.
  static const List<double> fontScaleSteps = [0.85, 1.0, 1.15, 1.3];

  final SharedPreferences _prefs;
  late AppearanceMode _mode;
  late TabBarStyle _tabBarStyle;
  late Color _brandColor;
  late double _fontScale;

  AppearanceMode get mode => _mode;
  TabBarStyle get tabBarStyle => _tabBarStyle;
  ThemeMode get themeMode => _mode.themeMode;
  Color get brandColor => _brandColor;

  /// App-wide text scale factor, applied at the root via MediaQuery.textScaler.
  double get fontScale => _fontScale;

  set mode(AppearanceMode value) {
    _mode = value;
    _prefs.setString(_modeKey, value.name);
    notifyListeners();
  }

  set tabBarStyle(TabBarStyle value) {
    _tabBarStyle = value;
    _prefs.setString(_tabKey, value.name);
    notifyListeners();
  }

  /// The app's accent / brand color. Persisted and applied app-wide.
  set brandColor(Color value) {
    _brandColor = value;
    _prefs.setInt(_brandKey, value.toARGB32());
    AppTheme.applyBrand(value);
    notifyListeners();
  }

  set fontScale(double value) {
    _fontScale = value;
    _prefs.setDouble(_fontKey, value);
    notifyListeners();
  }
}
