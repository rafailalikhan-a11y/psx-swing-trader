import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/storage.dart';
import '../services/psx_api.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});
  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  List<String> _watchlist = [];
  final Map<String, List<Candle>> _data = {};
  bool _loading = false;
  final _fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await Storage.loadWatchlist();
    setState(() => _watchlist = w);
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    for (final sym in _watchlist) {
      try {
        final candles = await PsxApi.fetchHistory(sym);
        if (candles.isNotEmpty) _data[sym] = candles;
      } catch (_) {}
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addSymbol() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add to Watchlist'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Symbol (e.g. MEBL)'), textCapitalization: TextCapitalization.characters),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      final sym = ctrl.text.trim().toUpperCase();
      if (sym.isNotEmpty && !_watchlist.contains(sym)) {
        setState(() => _watchlist.add(sym));
        await Storage.saveWatchlist(_watchlist);
        _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        actions: [
          if (_loading)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(icon: const Icon(Icons.add), onPressed: _addSymbol),
        ],
      ),
      body: ListView.builder(
        itemCount: _watchlist.length,
        itemBuilder: (ctx, i) {
          final sym = _watchlist[i];
          final candles = _data[sym];
          String price = '—', change = '';
          Color changeColor = Colors.white38;
          if (candles != null && candles.length >= 2) {
            final last = candles.last.close;
            final prev = candles[candles.length - 2].close;
            final pct = prev > 0 ? (last - prev) / prev * 100 : 0.0;
            price = 'Rs ${_fmt.format(last)}';
            change = '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%';
            changeColor = pct >= 0 ? Colors.greenAccent : Colors.redAccent;
          }
          return Dismissible(
            key: Key(sym),
            direction: DismissDirection.endToStart,
            background: Container(color: Colors.red.shade900, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete)),
            onDismissed: (_) async {
              setState(() => _watchlist.removeAt(i));
              await Storage.saveWatchlist(_watchlist);
            },
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                title: Text(sym, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: candles != null && candles.isNotEmpty
                    ? Text('Vol ${_fmt.format(candles.last.volume)}', style: const TextStyle(fontSize: 12, color: Colors.white38))
                    : const Text('Loading…', style: TextStyle(fontSize: 12, color: Colors.white38)),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(price, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (change.isNotEmpty) Text(change, style: TextStyle(color: changeColor, fontSize: 12)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
