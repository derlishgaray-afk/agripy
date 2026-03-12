import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController extends ChangeNotifier {
  static const String _prefsKeyPrefix = 'app_theme_mode_user_';
  static const String _prefsGuestKey = 'app_theme_mode_guest';

  ThemeMode _themeMode = ThemeMode.light;
  String? _activeUid;
  bool _hasSyncedActiveUid = false;

  ThemeMode get themeMode => _themeMode;

  Future<void> syncForUser(String? uid) async {
    final normalizedUid = _normalizeUid(uid);
    if (_hasSyncedActiveUid && _activeUid == normalizedUid) {
      return;
    }
    _activeUid = normalizedUid;
    _hasSyncedActiveUid = true;

    final resolvedMode = await _resolveModeForActiveUser();
    if (_themeMode == resolvedMode) {
      return;
    }
    _themeMode = resolvedMode;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }

    final prefs = await SharedPreferences.getInstance();
    final activeUid = _activeUid;
    if (activeUid != null && activeUid.isNotEmpty) {
      await prefs.setString(_keyForUid(activeUid), _serializeMode(mode));
      return;
    }
    await prefs.setString(_prefsGuestKey, _serializeMode(mode));
  }

  Future<ThemeMode> _resolveModeForActiveUser() async {
    final prefs = await SharedPreferences.getInstance();
    final activeUid = _activeUid;
    if (activeUid == null || activeUid.isEmpty) {
      return _parseMode(prefs.getString(_prefsGuestKey));
    }
    final userMode = prefs.getString(_keyForUid(activeUid));
    return _parseMode(userMode);
  }

  String _keyForUid(String uid) {
    return '$_prefsKeyPrefix${uid.trim()}';
  }

  String? _normalizeUid(String? uid) {
    final value = uid?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
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
