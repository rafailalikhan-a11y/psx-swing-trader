import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Free unofficial PSX data layer.
/// Primary: psxterminal.com (PSX Terminal API). Fallback: dps.psx.com.pk chart data.
class PsxApi {
  static const _base = 'https://psxterminal.com/api';
  static const _psxCharts = 'https://dps.psx.com.pk/charts';

  static final _client = http.Client();
  static List<String>? _symbolCache;

  /// Fetch all listed symbols.
  static Future<List<String>> fetchSymbols() async {
    if (_symbolCache != null) return _symbolCache!;
    final r = await _client.get(Uri.parse('$_base/symbols')).timeout(const Duration(seconds: 25));
    final body = jsonDecode(r.body);
    final List data = body['data'];
    _symbolCache = data.map((e) => e.toString()).toList();
    return _symbolCache!;
  }

  /// Fetch ~120 days of daily OHLCV candles for a symbol.
  /// Tries psxterminal klines first, falls back to PSX public chart endpoint.
  static Future<List<Candle>> fetchHistory(String symbol) async {
    // Attempt 1: psxterminal klines
    try {
      final r = await _client
          .get(Uri.parse('$_base/klines/$symbol/1d'))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body);
      if (body['success'] == true && body['data'] is List && (body['data'] as List).isNotEmpty) {
        return _parseKlines(body['data']);
      }
    } catch (_) {}
    // Attempt 2: PSX chart endpoint (timeseries)
    try {
      final r = await _client
          .get(Uri.parse('$_psxCharts/timeseries/eod/$symbol'))
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(r.body);
      if (body is List && body.isNotEmpty) return _parsePsxTimeseries(body);
      if (body is Map && body['data'] is List) return _parsePsxTimeseries(body['data']);
    } catch (_) {}
    return [];
  }

  static List<Candle> _parseKlines(List data) {
    final out = <Candle>[];
    for (final k in data) {
      try {
        // klines format: [timestamp, open, high, low, close, volume]
        if (k is List && k.length >= 6) {
          out.add(Candle(
            date: DateTime.fromMillisecondsSinceEpoch((k[0] is int ? k[0] : int.parse(k[0].toString())) * (k[0] < 10000000000 ? 1000 : 1)),
            open: double.parse(k[1].toString()),
            high: double.parse(k[2].toString()),
            low: double.parse(k[3].toString()),
            close: double.parse(k[4].toString()),
            volume: double.parse(k[5].toString()),
          ));
        }
      } catch (_) {}
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static List<Candle> _parsePsxTimeseries(List data) {
    final out = <Candle>[];
    for (final row in data) {
      try {
        if (row is List && row.length >= 3) {
          final ts = row[0] is int ? row[0] : int.parse(row[0].toString());
          final price = double.parse(row[1].toString());
          final vol = row.length >= 3 ? double.parse(row[2].toString()) : 0.0;
          out.add(Candle(
            date: DateTime.fromMillisecondsSinceEpoch(ts * (ts < 10000000000 ? 1000 : 1)),
            open: price, high: price, low: price, close: price, volume: vol,
          ));
        }
      } catch (_) {}
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }
}
