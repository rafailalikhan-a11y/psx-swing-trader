import 'package:flutter/material.dart';
import '../services/storage.dart';
import '../services/background_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bgScan = false;
  int _interval = 15;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Storage.loadSettings();
    setState(() {
      _bgScan = s['bgScanEnabled'] == true;
      _interval = (s['scanIntervalMin'] as num?)?.toInt() ?? 15;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await Storage.saveSettings({'bgScanEnabled': _bgScan, 'scanIntervalMin': _interval});
  }

  Future<void> _toggleBgScan(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Notification permission denied — enable it in system Settings to get signal alerts.'),
        ));
        return;
      }
      await BackgroundService.enable(intervalMin: _interval);
    } else {
      await BackgroundService.disable();
    }
    setState(() => _bgScan = value);
    await _save();
  }

  Future<void> _setInterval(int min) async {
    setState(() => _interval = min);
    await _save();
    if (_bgScan) await BackgroundService.enable(intervalMin: min);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: SwitchListTile(
                  title: const Text('Background signal scanning'),
                  subtitle: const Text('Scans the whole PSX market during trading hours and notifies you only when NEW signals appear'),
                  value: _bgScan,
                  onChanged: _toggleBgScan,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Scan interval', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('How often the market is scanned during trading hours',
                        style: TextStyle(fontSize: 12, color: Colors.white54)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      for (final m in [15, 30, 60])
                        ChoiceChip(
                          label: Text('$m min'),
                          selected: _interval == m,
                          onSelected: (_) => _setInterval(m),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    const Text('Note: Android may batch 15-minute jobs slightly to save battery — this is normal.',
                        style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PSX trading hours (PKT)', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Mon–Thu:  9:30 AM – 3:30 PM', style: TextStyle(color: Colors.white70)),
                    Text('Friday:  9:15 AM – 12:00 PM', style: TextStyle(color: Colors.white70)),
                    Text('Sat–Sun:  market closed (no scans)', style: TextStyle(color: Colors.white70)),
                    SizedBox(height: 8),
                    Text('Scans never run outside these hours. Notifications fire only when new signals appear.',
                        style: TextStyle(fontSize: 12, color: Colors.white54)),
                  ]),
                ),
              ),
            ]),
    );
  }
}
