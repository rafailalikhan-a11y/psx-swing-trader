import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class Storage {
  static const _holdingsKey = 'holdings_v1';
  static const _watchlistKey = 'watchlist_v1';

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
}
