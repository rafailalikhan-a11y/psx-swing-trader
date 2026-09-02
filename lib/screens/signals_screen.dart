import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/storage.dart';
import '../services/psx_api.dart';
import '../services/market_data.dart';
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

  /// Primary path: load the pre-computed signals published by the data
  /// collector (fast, one fetch). Fallback: on-device scan of
  /// portfolio + watchlist when the published data is stale/unavailable.
  Future<void> _loadSignals() async {
    setState(() {
      _scanning = true;
      _signals = [];
      _status = 'Loading latest market scan…';
    });

    final published = await MarketData.fetchSignals();
    if (published != null) {
      final stamp = await MarketData.dataTimestamp();
      setState(() {
        _signals = published;
        _scanning = false;
        _status = published.isEmpty
            ? 'No qualifying swing signals in the latest whole-market scan${stamp != null ? ' (data $stamp PKT)' : ''}.'
            : '${published.length} qualifying signal(s) from whole-market scan${stamp != null ? ' • data $stamp PKT' : ''}';
      });
      return;
    }

    // Fallback: quick on-device scan of portfolio + watchlist.
    await _scanQuick(fromFallback: true);
  }

  /// Quick on-device scan: portfolio + watchlist only.
  Future<void> _scanQuick({bool fromFallback = false}) async {
    final watch = await Storage.loadWatchlist();
    final holdings = (await Storage.loadHoldings()).map((h) => h.symbol).toList();
    final symbols = {...watch.map((e) => e.toUpperCase()), ...holdings.map((e) => e.toUpperCase())}.toList()..sort();
    await _runScan(symbols, fromFallback
        ? 'portfolio + watchlist (live scan — published data unavailable)'
        : 'portfolio + watchlist');
  }

  Future<void> _runScan(List<String> symbols, String scope) async {
    setState(() {
      _scanning = true;
      _signals = [];
      _scanned = 0;
      _total = symbols.length;
      _status = 'Scanning $scope…';
    });

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
      if (!mounted) return;
      setState(() => _scanned = min(i + batchSize, symbols.length));
    }

    found.sort((a, b) => b.score.compareTo(a.score));
    if (!mounted) return;
    setState(() {
      _signals = found;
      _scanning = false;
      _status = found.isEmpty
          ? 'No qualifying swing signals today. Scanned ${symbols.length} symbols ($scope).'
          : '${found.length} qualifying signal(s) • scanned ${symbols.length} symbols ($scope)';
    });
  }

  Future<void> _addToWatchlist(String symbol) async {
    final watch = await Storage.loadWatchlist();
    if (!watch.contains(symbol)) {
      watch.add(symbol);
      watch.sort();
      await Storage.saveWatchlist(watch);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$symbol added to watchlist')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$symbol is already in your watchlist')),
      );
    }
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
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _scanning ? null : _scanQuick,
                icon: const Icon(Icons.flash_on, size: 18),
                label: const Text('Quick Scan', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _scanning ? null : _loadSignals,
                icon: _scanning
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.radar),
                label: Text(_scanning
                    ? (_total > 0 ? 'Scanning $_scanned/$_total' : 'Loading…')
                    : 'Whole-Market Signals'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (_scanning && _total > 0)
            LinearProgressIndicator(value: _scanned / _total),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
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
            const Text('Swing criteria', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _rule(Icons.show_chart, 'BUY', Colors.greenAccent,
                'Volume ≥ 2× 20-day avg + RSI 50–70 + price above MA20 + breakout above 20-day high'),
            const SizedBox(height: 6),
            _rule(Icons.trending_down, 'SELL', Colors.redAccent,
                'Volume ≥ 2× 20-day avg + RSI 30–50 + price below MA20 + breakdown below 20-day low'),
            const SizedBox(height: 8),
            const Text('Whole-market results come from the automated scanner (refreshed every 15 min during trading hours). Top 3 picks are starred.',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
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
    final isTopPick = rank <= 3;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isTopPick ? color.withOpacity(0.7) : color.withOpacity(0.25), width: isTopPick ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: isTopPick ? color.withOpacity(0.2) : Colors.white10,
              child: Text('$rank', style: TextStyle(color: isTopPick ? color : Colors.white54, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Text(s.symbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (isTopPick) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star, size: 16, color: Colors.amber),
            ],
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _addToWatchlist(s.symbol),
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('Add to Watchlist'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70, padding: EdgeInsets.zero),
            ),
          ),
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
