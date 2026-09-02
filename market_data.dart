import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Reads the pre-computed market data published by the GitHub Actions
/// collector (scraper.py) into this repo and served by GitHub Pages.
///
/// This replaces the slow per-symbol crawling on-device: one fetch of
/// quotes.json gives live prices for the whole market, and one fetch of
/// signals.json gives today's pre-computed swing signals.
///
/// Freshness rule: if the file is older than [maxAgeMinutes], callers
/// should fall back to direct per-symbol fetching (PsxApi) — meaning the
/// collector is down or the market is closed and files weren't refreshed.
class MarketData {
  static const _base =
      'https://rafailaikhan-a11y.github.io/psx-swing-trader/data';
  static const maxAgeMinutes = 35;

  static final _client = http.Client();

  static DateTime? _parseStamp(Map<String, dynamic> body) {
    try {
      return DateTime.parse(body['updated'] as String);
    } catch (_) {
      return null;
    }
  }

  static bool _isFresh(DateTime? stamp) {
    if (stamp == null) return false;
    return DateTime.now().difference(stamp.toLocal()).inMinutes.abs() <= maxAgeMinutes;
  }

  /// Latest quote map: symbol -> {price, prevClose, volume, changePct}.
  /// Returns null if unavailable or stale.
  static Future<Map<String, Map<String, dynamic>>?> fetchQuotes() async {
    try {
      final r = await _client
          .get(Uri.parse('$_base/quotes.json'))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (!_isFresh(_parseStamp(body))) return null;
      final q = body['quotes'] as Map<String, dynamic>;
      return q.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
    } catch (_) {
      return null;
    }
  }

  /// Pre-computed signals, ranked by score. Returns null if stale/unavailable.
  static Future<List<Signal>?> fetchSignals() async {
    try {
      final r = await _client
          .get(Uri.parse('$_base/signals.json'))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (!_isFresh(_parseStamp(body))) return null;
      final List list = body['signals'] ?? [];
      return list.map((e) => Signal.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return null;
    }
  }

  /// Staleness info for display ("Data as of 14:30 PKT").
  static Future<String?> dataTimestamp() async {
    try {
      final r = await _client
          .get(Uri.parse('$_base/quotes.json'))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final stamp = _parseStamp(body);
      if (stamp == null) return null;
      final pkt = stamp.toLocal();
      return '${pkt.hour.toString().padLeft(2, '0')}:${pkt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }
}
