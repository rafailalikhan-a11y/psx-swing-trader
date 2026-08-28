import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/storage.dart';
import '../services/csv_importer.dart';
import '../services/psx_api.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  List<Holding> _holdings = [];
  final Map<String, double> _livePrices = {};
  bool _loadingPrices = false;
  final _fmt = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = _mergeAndSort(await Storage.loadHoldings());
    setState(() => _holdings = h);
    if (h.isNotEmpty) _refreshPrices();
  }

  List<Holding> _mergeAndSort(List<Holding> items) {
    final Map<String, Holding> merged = {};
    for (final h in items) {
      final sym = h.symbol.trim().toUpperCase();
      if (sym.isEmpty) continue;
      if (merged.containsKey(sym)) {
        final existing = merged[sym]!;
        final totalShares = existing.shares + h.shares;
        final totalCost = (existing.shares * existing.avgPrice) + (h.shares * h.avgPrice);
        existing.shares = totalShares;
        existing.avgPrice = totalShares > 0 ? totalCost / totalShares : h.avgPrice;
      } else {
        merged[sym] = Holding(symbol: sym, shares: h.shares, avgPrice: h.avgPrice);
      }
    }
    final out = merged.values.toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
    return out;
  }

  Future<void> _refreshPrices() async {
    setState(() => _loadingPrices = true);
    for (final h in _holdings) {
      try {
        final candles = await PsxApi.fetchHistory(h.symbol);
        if (candles.isNotEmpty) _livePrices[h.symbol] = candles.last.close;
      } catch (_) {}
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _loadingPrices = false);
  }

  Future<void> _importCsv() async {
    final imported = await CsvImporter.pickAndParse();
    if (imported == null) return;
    if (imported.isEmpty) {
      _snack('No valid rows found. Use columns: symbol, shares, avg_price');
      return;
    }
    final merged = _mergeAndSort(imported);
    setState(() => _holdings = merged);
    await Storage.saveHoldings(merged);
    _snack('Imported ${merged.length} holdings');
    _refreshPrices();
  }

  Future<void> _addManual() async {
    final symCtrl = TextEditingController();
    final sharesCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Holding'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: symCtrl, decoration: const InputDecoration(labelText: 'Symbol (e.g. HBL)')),
          TextField(controller: sharesCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Shares')),
          TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Avg buy price (Rs)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      final sym = symCtrl.text.trim().toUpperCase();
      final sh = double.tryParse(sharesCtrl.text);
      final pr = double.tryParse(priceCtrl.text);
      if (sym.isNotEmpty && sh != null && pr != null && sh > 0 && pr > 0) {
        final existingIdx = _holdings.indexWhere((h) => h.symbol == sym);
        if (existingIdx != -1) {
          final existing = _holdings[existingIdx];
          final totalShares = existing.shares + sh;
          final totalCost = (existing.shares * existing.avgPrice) + (sh * pr);
          existing.shares = totalShares;
          existing.avgPrice = totalCost / totalShares;
          _snack('$sym updated and averaged into existing holding');
        } else {
          _holdings.add(Holding(symbol: sym, shares: sh, avgPrice: pr));
          _snack('$sym added');
        }
        final merged = _mergeAndSort(_holdings);
        setState(() => _holdings = merged);
        await Storage.saveHoldings(merged);
        _refreshPrices();
      }
    }
  }

  String _compactRs(double value) {
    final sign = value < 0 ? '-' : '';
    final abs = value.abs();
    if (abs >= 1000000) return '$signRs ${(abs / 1000000).toStringAsFixed(2)}M';
    if (abs >= 1000) return '$signRs ${(abs / 1000).toStringAsFixed(1)}K';
    return '$signRs ${_fmt.format(abs)}';
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    double totalCost = 0, totalValue = 0;
    for (final h in _holdings) {
      totalCost += h.shares * h.avgPrice;
      totalValue += h.shares * (_livePrices[h.symbol] ?? h.avgPrice);
    }
    final pnl = totalValue - totalCost;
    final pnlPct = totalCost > 0 ? pnl / totalCost * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Portfolio'),
        actions: [
          if (_loadingPrices)
            const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _holdings.isEmpty ? null : _refreshPrices),
          IconButton(icon: const Icon(Icons.upload_file), tooltip: 'Import CSV', onPressed: _importCsv),
          IconButton(icon: const Icon(Icons.add), onPressed: _addManual),
        ],
      ),
      body: _holdings.isEmpty
          ? _emptyState()
          : Column(children: [
              _summaryCard(totalCost, totalValue, pnl, pnlPct),
              Expanded(
                child: ListView.builder(
                  itemCount: _holdings.length,
                  itemBuilder: (ctx, i) {
                    final h = _holdings[i];
                    final live = _livePrices[h.symbol];
                    final val = h.shares * (live ?? h.avgPrice);
                    final cost = h.shares * h.avgPrice;
                    final pl = val - cost;
                    final plPct = cost > 0 ? pl / cost * 100 : 0.0;
                    final color = pl >= 0 ? Colors.greenAccent : Colors.redAccent;
                    return Dismissible(
                      key: Key(h.symbol + i.toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(color: Colors.red.shade900, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete)),
                      onDismissed: (_) async {
                        setState(() => _holdings.removeAt(i));
                        await Storage.saveHoldings(_holdings);
                      },
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text(h.symbol, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${_fmt.format(h.shares)} shares @ Rs ${_fmt.format(h.avgPrice)}'
                              '${live != null ? '  •  Now Rs ${_fmt.format(live)}' : ''}'),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('Rs ${_fmt.format(val)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${pl >= 0 ? '+' : ''}${plPct.toStringAsFixed(1)}%', style: TextStyle(color: color, fontSize: 12)),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
    );
  }

  Widget _summaryCard(double cost, double value, double pnl, double pnlPct) {
    final color = pnl >= 0 ? Colors.greenAccent : Colors.redAccent;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _stat('Invested', _compactRs(cost), Colors.white70)),
          Expanded(child: _stat('Current', _compactRs(value), Colors.white)),
          Expanded(child: _stat('P&L', '${pnl >= 0 ? '+' : ''}${_compactRs(pnl)}\n(${pnlPct.toStringAsFixed(1)}%)', color)),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) =>
      Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        ),
      ]);

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            const Text('No holdings yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Import a CSV file with columns:\nsymbol, shares, avg_price\n\nExample:\nHBL, 500, 145.50\nLUCK, 100, 890.00',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _importCsv, icon: const Icon(Icons.upload_file), label: const Text('Import CSV')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _addManual, icon: const Icon(Icons.add), label: const Text('Add manually')),
          ]),
        ),
      );
}
