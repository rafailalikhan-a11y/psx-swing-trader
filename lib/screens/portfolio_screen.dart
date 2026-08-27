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
    final h = await Storage.loadHoldings();
    setState(() => _holdings = h);
    if (h.isNotEmpty) _refreshPrices();
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
    setState(() => _holdings = imported);
    await Storage.saveHoldings(imported);
    _snack('Imported ${imported.length} holdings');
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
      if (sym.isNotEmpty && sh != null && pr != null) {
        setState(() => _holdings.add(Holding(symbol: sym, shares: sh, avgPrice: pr)));
        await Storage.saveHoldings(_holdings);
        _refreshPrices();
      }
    }
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
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _stat('Invested', 'Rs ${_fmt.format(cost)}', Colors.white70),
          _stat('Current', 'Rs ${_fmt.format(value)}', Colors.white),
          _stat('P&L', '${pnl >= 0 ? '+' : ''}${_fmt.format(pnl)} (${pnlPct.toStringAsFixed(1)}%)', color),
        ]),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) =>
      Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
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
