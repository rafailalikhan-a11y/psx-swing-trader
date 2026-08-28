import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/storage.dart';
import '../services/psx_api.dart';
import '../services/signal_engine.dart';

class SignalsScreen extends StatefulWidget {
  const SignalsScreen({super.key});
  @override
  State<SignalsScreen> createState() => _SignalsScreenState();
}

class _SignalsScreenState extends State<SignalsScreen> {
  bool _scanning = false;
  String _status = '';
  List<Signal> _signals = [];
  int _scanned = 0, _total = 0;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _signals = [];
      _scanned = 0;
      _status = 'Loading portfolio + watchlist…';
    });

    // Current design: scan watchlist symbols + portfolio symbols.
    // Whole-market scanning is a later enhancement because each symbol currently
    // requires a separate network call and would be too slow on-device.
    final watch = await Storage.loadWatchlist();
    final holdings = (await Storage.loadHoldings()).map((h) => h.symbol).toList();
    final symbols = {...watch.map((e) => e.toUpperCase()), ...holdings.map((e) => e.toUpperCase())}.toList()..sort();

    setState(() {
      _total = symbols.length;
      _status = 'Fetching signal data from portfolio + watchlist…';
    });

    final found = <Signal>[];
    for (final sym in symbols) {
      try {
        final candles = await PsxApi.fetchHistory(sym);
        final sig = SignalEngine.evaluate(sym, candles);
        if (sig != null) found.add(sig);
      } catch (_) {}
      if (mounted) setState(() => _scanned++);
    }

    final top = SignalEngine.topSignals(found, maxSignals: 3);
    setState(() {
      _signals = top;
      _scanning = false;
      _status = top.isEmpty
          ? 'No high-volume swing signals today across ${symbols.length} portfolio/watchlist symbols.'
          : 'Top ${top.length} signal(s) today • scanned ${symbols.length} portfolio/watchlist symbols';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Swing Signals')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _criteriaCard(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt),
              label: Text(_scanning ? 'Scanning $_scanned/$_total…' : 'Scan Market for Signals'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
          const SizedBox(height: 12),
          if (_status.isNotEmpty)
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 12),
          Expanded(
            child: _signals.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    itemCount: _signals.length,
                    itemBuilder: (ctx, i) => _signalCard(_signals[i], i + 1),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _criteriaCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Swing criteria (2–3 trades/day max)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _rule(Icons.show_chart, 'BUY', Colors.greenAccent,
                'Volume ≥ 2× 20-day avg + RSI 50–70 + price above MA20 + breakout above 20-day high'),
            const SizedBox(height: 6),
            _rule(Icons.trending_down, 'SELL', Colors.redAccent,
                'Volume ≥ 2× 20-day avg + RSI 30–50 + price below MA20 + breakdown below 20-day low'),
            const SizedBox(height: 8),
            const Text('Current scope: scans your portfolio + watchlist symbols only.', style: TextStyle(fontSize: 11, color: Colors.white54)),
          ]),
        ),
      );

  Widget _rule(IconData icon, String label, Color color, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(style: const TextStyle(fontSize: 12, color: Colors.white70), children: [
              TextSpan(text: '$label: ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              TextSpan(text: text),
            ]),
          ),
        ),
      ]);

  Widget _signalCard(Signal s, int rank) {
    final isBuy = s.type == SignalType.buy;
    final color = isBuy ? Colors.greenAccent : Colors.redAccent;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withOpacity(0.4))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 14, backgroundColor: color.withOpacity(0.15), child: Text('$rank', style: TextStyle(color: color, fontWeight: FontWeight.bold))),
            const SizedBox(width: 10),
            Text(s.symbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(isBuy ? 'BUY' : 'SELL', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _chip('Price', 'Rs ${s.price.toStringAsFixed(2)}'),
            _chip('Volume', '${s.volRatio.toStringAsFixed(1)}× avg'),
            _chip('RSI(14)', s.rsi14.toStringAsFixed(0)),
          ]),
          const SizedBox(height: 8),
          Text(s.reason, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ]),
      ),
    );
  }

  Widget _chip(String label, String value) => Expanded(
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
}
