import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  static const String _prefsKeyPrefix = 'app_theme_mode_user_';

  ThemeMode _themeMode = ThemeMode.light;
  String? _activeUid;

  ThemeMode get themeMode => _themeMode;

  Future<void> syncForUser(String? uid) async {
    if (_activeUid == uid) {
      return;
    }
    _activeUid = uid;

    final resolvedMode = await _resolveModeForActiveUser();
    if (_themeMode == resolvedMode) {
      return;
    }
    _themeMode = resolvedMode;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();

    if (_activeUid == null || _activeUid!.trim().isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForUid(_activeUid!), _serializeMode(mode));
  }

  Future<ThemeMode> _resolveModeForActiveUser() async {
    if (_activeUid == null || _activeUid!.trim().isEmpty) {
      return ThemeMode.light;
    }
    final prefs = await SharedPreferences.getInstance();
    final persistedMode = prefs.getString(_keyForUid(_activeUid!));
    return _parseMode(persistedMode);
  }

  String _keyForUid(String uid) {
    return '$_prefsKeyPrefix${uid.trim()}';
  }

  ThemeMode _parseMode(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  String _serializeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
      default:
        return 'light';
    }
  }
}
