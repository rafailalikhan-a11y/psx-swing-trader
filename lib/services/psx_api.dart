import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// PSX official public data feed (dps.psx.com.pk) — the same feed that powers
/// the charts on PSX's own website. No API key required.
class PsxApi {
  static const _base = 'https://dps.psx.com.pk';

  static final _client = http.Client();
  static List<String>? _symbolCache;

  /// Fetch all listed symbols.
  static Future<List<String>> fetchSymbols() async {
    if (_symbolCache != null) return _symbolCache!;
    final r = await _client.get(Uri.parse('$_base/symbols')).timeout(const Duration(seconds: 25));
    final List body = jsonDecode(r.body);
    _symbolCache = body
        .where((e) => e is Map && e['isDebt'] != true && e['isETF'] != true)
        .map((e) => e['symbol'].toString())
        .toList();
    return _symbolCache!;
  }

  /// Fetch daily OHLCV candles for a symbol.
  /// Primary: end-of-day history. Fallback: today's intraday ticks.
  static Future<List<Candle>> fetchHistory(String symbol) async {
    // Attempt 1: end-of-day history
    try {
      final r = await _client
          .get(Uri.parse('$_base/timeseries/eod/$symbol'))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body);
      if (body is Map && body['status'] == 1 && body['data'] is List && (body['data'] as List).isNotEmpty) {
        return _parseEod(body['data']);
      }
    } catch (_) {}
    // Attempt 2: intraday ticks (today's session)
    try {
      final r = await _client
          .get(Uri.parse('$_base/timeseries/int/$symbol'))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body);
      if (body is Map && body['status'] == 1 && body['data'] is List && (body['data'] as List).isNotEmpty) {
        return _parseIntraday(body['data']);
      }
    } catch (_) {}
    return [];
  }

  /// EOD format: [timestamp_seconds, close, volume, open]
  static List<Candle> _parseEod(List data) {
    final out = <Candle>[];
    for (final row in data) {
      try {
        if (row is List && row.length >= 3) {
          final ts = row[0] is int ? row[0] : int.parse(row[0].toString());
          final close = double.parse(row[1].toString());
          final vol = double.parse(row[2].toString());
          final open = row.length >= 4 ? double.parse(row[3].toString()) : close;
          out.add(Candle(
            date: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            open: open, high: close > open ? close : open,
            low: close < open ? close : open,
            close: close, volume: vol,
          ));
        }
      } catch (_) {}
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// Intraday format: [timestamp_seconds, price, volume]
  static List<Candle> _parseIntraday(List data) {
    final out = <Candle>[];
    for (final row in data) {
      try {
        if (row is List && row.length >= 3) {
          final ts = row[0] is int ? row[0] : int.parse(row[0].toString());
          final price = double.parse(row[1].toString());
          final vol = double.parse(row[2].toString());
          out.add(Candle(
            date: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            open: price, high: price, low: price, close: price, volume: vol,
          ));
        }
      } catch (_) {}
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }
}
