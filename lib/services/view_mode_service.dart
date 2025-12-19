import 'package:shared_preferences/shared_preferences.dart';

class ViewModeService {
  static const _kGrid = 'vinyl_view_grid';

  static Future<bool> isGridEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kGrid) ?? false; // default: lista
  }

  static Future<void> setGridEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGrid, value);
  }
}

