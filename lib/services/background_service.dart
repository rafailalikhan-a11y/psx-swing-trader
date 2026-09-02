import 'dart:math';
import 'package:workmanager/workmanager.dart';
import '../models/models.dart';
import 'psx_api.dart';
import 'market_data.dart';
import 'signal_engine.dart';
import 'storage.dart';
import 'notification_service.dart';

/// Background market scanner.
///
/// Runs via Workmanager every 15 minutes (Android's minimum periodic interval).
/// Each run checks whether Pakistan Standard Time (UTC+5) is inside PSX trading
/// hours — Mon–Thu 09:30–15:30, Fri 09:15–12:00, weekends off — and silently
/// returns outside those hours, so no battery/data is wasted.
///
/// Primary path: read the collector's pre-computed signals.json (one small
/// fetch — the heavy whole-market scanning happens server-side via GitHub
/// Actions). Fallback: if published data is stale/unavailable, do a light
/// on-device scan of portfolio + watchlist symbols.
class BackgroundService {
  static const taskName = 'psxSignalScan';

  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> enable({int intervalMin = 15}) async {
    await init();
    await Workmanager().registerPeriodicTask(
      taskName, taskName,
      frequency: Duration(minutes: intervalMin < 15 ? 15 : intervalMin),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static Future<void> disable() async {
    await Workmanager().cancelByUniqueName(taskName);
  }
}

/// True when PKT (UTC+5) is inside PSX regular trading hours.
bool _isMarketOpen() {
  final pkt = DateTime.now().toUtc().add(const Duration(hours: 5));
  final wd = pkt.weekday; // 1=Mon ... 7=Sun
  if (wd > 5) return false;
  final mins = pkt.hour * 60 + pkt.minute;
  if (wd == 5) {
    return mins >= 555 && mins <= 720; // Fri 09:15–12:00
  }
  return mins >= 570 && mins <= 930; // Mon–Thu 09:30–15:30
}

/// Fallback on-device scan of portfolio + watchlist symbols only.
Future<List<Signal>> _quickScan() async {
  final watch = await Storage.loadWatchlist();
  final holdings = (await Storage.loadHoldings()).map((h) => h.symbol).toList();
  final symbols = {...watch.map((e) => e.toUpperCase()), ...holdings.map((e) => e.toUpperCase())}.toList();

  final found = <Signal>[];
  const batchSize = 10;
  for (var i = 0; i < symbols.length; i += batchSize) {
    final batch = symbols.sublist(i, min(i + batchSize, symbols.length));
    await Future.wait(batch.map((sym) async {
      try {
        final candles = await PsxApi.fetchHistory(sym);
        final sig = SignalEngine.evaluate(sym, candles);
        if (sig != null) found.add(sig);
      } catch (_) {}
    }));
  }
  found.sort((a, b) => b.score.compareTo(a.score));
  return found;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (!_isMarketOpen()) return true;

      await NotificationService.init();

      // Primary: pre-computed whole-market signals from the collector.
      List<Signal>? found = await MarketData.fetchSignals();
      var scanned = 0;

      // Fallback: light on-device scan of portfolio + watchlist.
      if (found == null) {
        found = await _quickScan();
      }

      final lastKeys = await Storage.loadLastSignalKeys();
      final newSignals = found.where((s) => !lastKeys.contains(s.key)).toList();

      if (newSignals.isNotEmpty) {
        await NotificationService.showNewSignals(newSignals, scanned > 0 ? scanned : found.length);
        await Storage.saveLastSignalKeys(found.map((s) => s.key).toSet());
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}
