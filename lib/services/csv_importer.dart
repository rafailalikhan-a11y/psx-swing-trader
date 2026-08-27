import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';

/// Imports holdings from a CSV file.
/// Expected columns (header row): symbol, shares, avg_price
/// Extra columns are ignored; header names are matched case-insensitively
/// (accepts: symbol/scrip/ticker, shares/qty/quantity, avg_price/price/cost/buy_price).
class CsvImporter {
  static Future<List<Holding>?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.first.bytes;
    if (bytes == null) return null;
    final content = utf8.decode(bytes, allowMalformed: true);
    return parse(content);
  }

  static List<Holding> parse(String content) {
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(content);
    if (rows.isEmpty) return [];

    // Locate header
    int headerIdx = 0;
    final header = rows[0].map((e) => e.toString().trim().toLowerCase()).toList();
    int symCol = _findCol(header, ['symbol', 'scrip', 'ticker', 'stock']);
    int sharesCol = _findCol(header, ['shares', 'qty', 'quantity', 'units']);
    int priceCol = _findCol(header, ['avg_price', 'avg price', 'price', 'cost', 'buy_price', 'buy price', 'rate']);

    if (symCol == -1 || sharesCol == -1 || priceCol == -1) {
      // No recognizable header: assume column order symbol, shares, price
      headerIdx = -1; symCol = 0; sharesCol = 1; priceCol = 2;
    }

    final out = <Holding>[];
    for (int i = headerIdx + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= priceCol) continue;
      final sym = row[symCol].toString().trim().toUpperCase();
      final shares = double.tryParse(row[sharesCol].toString().replaceAll(',', '').trim());
      final price = double.tryParse(row[priceCol].toString().replaceAll(',', '').trim());
      if (sym.isNotEmpty && shares != null && price != null && shares > 0) {
        out.add(Holding(symbol: sym, shares: shares, avgPrice: price));
      }
    }
    return out;
  }

  static int _findCol(List<String> header, List<String> names) {
    for (final n in names) {
      final idx = header.indexOf(n);
      if (idx != -1) return idx;
    }
    return -1;
  }
}
