import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  // 'dashboard_group_by_type' is no longer read: Home always groups accounts
  // by type. A value stored by an older version is left in place, unused.
  static const _biometricEnabledKey = 'biometric_enabled';
  static const _showCategoryFilterKey = 'dashboard_show_category_filter';
  static const _themeModeKey = 'theme_mode';
  static const _moneyHiddenKey = 'privacy_money_hidden';
  static const _showZeroHoldingsKey = 'holdings_show_zero_value';

  static PreferencesService? _instance;
  SharedPreferences? _prefs;

  PreferencesService._();

  static PreferencesService get instance {
    _instance ??= PreferencesService._();
    return _instance!;
  }

  /// Drops the cached instance (and its cached [SharedPreferences]) so tests
  /// can re-read values from freshly mocked storage. Test-only.
  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<bool> getBiometricEnabled() async {
    final prefs = await _preferences;
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_biometricEnabledKey, value);
  }

  Future<bool> getShowCategoryFilter() async {
    final prefs = await _preferences;
    return prefs.getBool(_showCategoryFilterKey) ?? false;
  }

  Future<void> setShowCategoryFilter(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_showCategoryFilterKey, value);
  }

  /// Whether money values are masked app-wide ("privacy mode"). Default false.
  Future<bool> getMoneyHidden() async {
    final prefs = await _preferences;
    return prefs.getBool(_moneyHiddenKey) ?? false;
  }

  Future<void> setMoneyHidden(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_moneyHiddenKey, value);
  }

  /// Whether holdings worth zero are listed. Default false (hidden).
  Future<bool> getShowZeroHoldings() async {
    final prefs = await _preferences;
    return prefs.getBool(_showZeroHoldingsKey) ?? false;
  }

  Future<void> setShowZeroHoldings(bool value) async {
    final prefs = await _preferences;
    await prefs.setBool(_showZeroHoldingsKey, value);
  }

  /// Returns 'light', 'dark', or 'system' (default).
  Future<String> getThemeMode() async {
    final prefs = await _preferences;
    return prefs.getString(_themeModeKey) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    final prefs = await _preferences;
    await prefs.setString(_themeModeKey, mode);
  }
}
