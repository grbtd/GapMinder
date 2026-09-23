import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService extends ChangeNotifier {
  static final PreferencesService _instance = PreferencesService._internal();

  factory PreferencesService() => _instance;

  PreferencesService._internal();

  static const String _keyNerdMode = 'nerd_mode_enabled';
  static const String _keyShowArrivals = 'show_arrivals_enabled';

  SharedPreferences? _prefs;
  bool _nerdMode = true; // Default to true (Nerd Mode ON)
  bool _showArrivals = true; // Default to true (Show Terminating Arrivals)

  bool get isNerdMode => _nerdMode;
  bool get showArrivals => _showArrivals;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _nerdMode = _prefs?.getBool(_keyNerdMode) ?? true;
    _showArrivals = _prefs?.getBool(_keyShowArrivals) ?? true;
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

  Future<void> setShowArrivals(bool enabled) async {
    _showArrivals = enabled;
    notifyListeners();
    await _prefs?.setBool(_keyShowArrivals, enabled);
  }

  Future<void> toggleShowArrivals() async {
    await setShowArrivals(!_showArrivals);
  }
}
