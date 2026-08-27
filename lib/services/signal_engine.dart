import '../models/models.dart';
import 'indicators.dart';

/// Swing-trade signal engine for PSX.
///
/// BUY criteria (all must fire, scored):
///  - Volume spike: today volume >= 2x 20-day average
///  - Bullish RSI zone: RSI(14) between 50 and 70 (momentum but not overbought)
///  - Trend confirmation: close > SMA20
///  - Breakout: close breaks above 20-day high
///
/// SELL criteria:
///  - Volume spike: today volume >= 2x 20-day average
///  - Bearish RSI zone: RSI(14) between 30 and 50
///  - Close < SMA20
///  - Breakdown: close breaks below 20-day low
///
/// Score is weighted by volume ratio strength and RSI conviction.
/// Caller keeps only the top 2-3 signals per day.
class SignalEngine {
  static const double volMultiplier = 2.0;
  static const int rsiPeriod = 14;
  static const int maPeriod = 20;
  static const int breakoutPeriod = 20;

  static Signal? evaluate(String symbol, List<Candle> candles) {
    if (candles.length < maPeriod + 2) return null;

    final today = candles.last;
    final closes = candles.map((c) => c.close).toList();

    final avgVol = Indicators.avgVolume(candles, 20);
    if (avgVol <= 0) return null;
    final volRatio = today.volume / avgVol;
    if (volRatio < volMultiplier) return null; // must be a high-volume day

    final rsi14 = Indicators.rsi(closes, rsiPeriod);
    final sma20 = Indicators.sma(closes, maPeriod);
    final high20 = Indicators.highOf(candles, breakoutPeriod);
    final low20 = Indicators.lowOf(candles, breakoutPeriod);

    // BUY
    if (rsi14 >= 50 && rsi14 <= 70 && today.close > sma20 && today.close >= high20 && high20 > 0) {
      final score = (volRatio * 40) + ((rsi14 - 50) / 20 * 30) + 30;
      return Signal(
        symbol: symbol, type: SignalType.buy, price: today.close,
        volRatio: volRatio, rsi14: rsi14,
        reason: 'Volume ${volRatio.toStringAsFixed(1)}x avg, breakout above 20-day high (Rs ${high20.toStringAsFixed(2)}), RSI ${rsi14.toStringAsFixed(0)}, price above MA20',
        score: score,
      );
    }

    // SELL
    if (rsi14 >= 30 && rsi14 <= 50 && today.close < sma20 && today.close <= low20 && low20 > 0) {
      final score = (volRatio * 40) + ((50 - rsi14) / 20 * 30) + 30;
      return Signal(
        symbol: symbol, type: SignalType.sell, price: today.close,
        volRatio: volRatio, rsi14: rsi14,
        reason: 'Volume ${volRatio.toStringAsFixed(1)}x avg, breakdown below 20-day low (Rs ${low20.toStringAsFixed(2)}), RSI ${rsi14.toStringAsFixed(0)}, price below MA20',
        score: score,
      );
    }
    return null;
  }

  /// Keep only top [maxSignals] by score.
  static List<Signal> topSignals(List<Signal> all, {int maxSignals = 3}) {
    all.sort((a, b) => b.score.compareTo(a.score));
    return all.take(maxSignals).toList();
  }
}
