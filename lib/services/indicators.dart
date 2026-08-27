import '../models/models.dart';

class Indicators {
  static double sma(List<double> values, int period) {
    if (values.length < period) return values.isEmpty ? 0 : values.last;
    final slice = values.sublist(values.length - period);
    return slice.reduce((a, b) => a + b) / period;
  }

  /// Wilder-style RSI.
  static double rsi(List<double> closes, int period) {
    if (closes.length < period + 1) return 50;
    double gain = 0, loss = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      final diff = closes[i] - closes[i - 1];
      if (diff >= 0) gain += diff; else loss -= diff;
    }
    final avgGain = gain / period, avgLoss = loss / period;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  static double avgVolume(List<Candle> candles, int period) {
    if (candles.length < period + 1) {
      return candles.isEmpty ? 0 : candles.last.volume;
    }
    final slice = candles.sublist(candles.length - period - 1, candles.length - 1); // exclude today
    return slice.map((c) => c.volume).reduce((a, b) => a + b) / period;
  }

  static double highOf(List<Candle> candles, int period) {
    if (candles.length < 2) return candles.isEmpty ? 0 : candles.last.high;
    final end = candles.length - 1; // exclude today
    final start = end - period < 0 ? 0 : end - period;
    double h = 0;
    for (int i = start; i < end; i++) { if (candles[i].high > h) h = candles[i].high; }
    return h;
  }

  static double lowOf(List<Candle> candles, int period) {
    if (candles.length < 2) return candles.isEmpty ? 0 : candles.last.low;
    final end = candles.length - 1;
    final start = end - period < 0 ? 0 : end - period;
    double l = double.infinity;
    for (int i = start; i < end; i++) { if (candles[i].low < l) l = candles[i].low; }
    return l == double.infinity ? 0 : l;
  }
}
