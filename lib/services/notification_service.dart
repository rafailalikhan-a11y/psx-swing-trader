import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'psx_signals';
  static const _channelName = 'PSX Swing Signals';
  static const _channelDesc = 'New swing-trade signals found during market scans';
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    const channel = AndroidNotificationChannel(
      _channelId, _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _initialized = true;
  }

  /// Ask the user for notification permission (Android 13+). Returns true if granted.
  static Future<bool> requestPermission() async {
    final impl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final granted = await impl?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// Post a summary notification for newly found signals.
  static Future<void> showNewSignals(List<Signal> signals, int scanned) async {
    await init();
    if (signals.isEmpty) return;

    final now = DateTime.now().toUtc().add(const Duration(hours: 5)); // PKT
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');

    final lines = signals.take(3).map((s) {
      final emoji = s.type == SignalType.buy ? '🟢' : '🔴';
      final tag = s.type == SignalType.buy ? 'BUY' : 'SELL';
      return '$emoji ${s.symbol} $tag @ Rs ${s.price.toStringAsFixed(2)} — Vol ${s.volRatio.toStringAsFixed(1)}×, RSI ${s.rsi14.toStringAsFixed(0)}';
    }).join('\n');

    final extra = signals.length > 3 ? '\n+${signals.length - 3} more' : '';
    final title = 'PSX Swing Signals — $hh:$mm';
    final body = '${signals.length} new signal${signals.length > 1 ? 's' : ''} • scanned $scanned symbols\n$lines$extra';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId, _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
    await _plugin.show(now.millisecondsSinceEpoch % 100000, title, body, details);
  }
}
