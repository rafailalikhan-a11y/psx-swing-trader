import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class Storage {
  static const _holdingsKey = 'holdings_v1';
  static const _watchlistKey = 'watchlist_v1';
  static const _settingsKey = 'settings_v1';
  static const _lastSignalKeysKey = 'last_signal_keys_v1';

  static Future<List<Holding>> loadHoldings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_holdingsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Holding.fromJson(e)).toList();
  }

  static Future<void> saveHoldings(List<Holding> h) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_holdingsKey, jsonEncode(h.map((e) => e.toJson()).toList()));
  }

  static Future<List<String>> loadWatchlist() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_watchlistKey) ??
        ['HBL', 'LUCK', 'ENGRO', 'OGDC', 'PPL', 'MCB', 'UBL', 'FFC', 'PSO', 'TRG'];
  }

  static Future<void> saveWatchlist(List<String> w) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_watchlistKey, w);
  }

  // ---- Settings ----

  static Future<Map<String, dynamic>> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_settingsKey);
    if (raw == null) {
      return {'bgScanEnabled': false, 'scanIntervalMin': 15};
    }
    return Map<String, dynamic>.from(jsonDecode(raw));
  }

  static Future<void> saveSettings(Map<String, dynamic> s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_settingsKey, jsonEncode(s));
  }

  // ---- Last notified signal keys (for "only notify on new" behavior) ----

  static Future<Set<String>> loadLastSignalKeys() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_lastSignalKeysKey) ?? []).toSet();
  }

  static Future<void> saveLastSignalKeys(Set<String> keys) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_lastSignalKeysKey, keys.toList());
  }
}
