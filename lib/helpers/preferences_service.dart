import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService extends ChangeNotifier {
  static final PreferencesService _instance = PreferencesService._internal();

  factory PreferencesService() => _instance;

  PreferencesService._internal();

  static const String _keyNerdMode = 'nerd_mode_enabled';

  SharedPreferences? _prefs;
  bool _nerdMode = true; // Default to true (Nerd Mode ON)

  bool get isNerdMode => _nerdMode;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _nerdMode = _prefs?.getBool(_keyNerdMode) ?? true;
    notifyListeners();
  }

  Future<void> setNerdMode(bool enabled) async {
    _nerdMode = enabled;
    notifyListeners();
    await _prefs?.setBool(_keyNerdMode, enabled);
  }

  Future<void> toggleNerdMode() async {
    await setNerdMode(!_nerdMode);
  }
}
