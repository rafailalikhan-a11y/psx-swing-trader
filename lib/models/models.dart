class Candle {
  final DateTime date;
  final double open, high, low, close, volume;
  Candle({required this.date, required this.open, required this.high,
      required this.low, required this.close, required this.volume});
}

class Holding {
  String symbol;
  double shares;
  double avgPrice;
  Holding({required this.symbol, required this.shares, required this.avgPrice});
  Map<String, dynamic> toJson() => {'symbol': symbol, 'shares': shares, 'avgPrice': avgPrice};
  factory Holding.fromJson(Map<String, dynamic> j) =>
      Holding(symbol: j['symbol'], shares: (j['shares'] as num).toDouble(), avgPrice: (j['avgPrice'] as num).toDouble());
}

class Quote {
  final String symbol;
  final double price, changePct, volume;
  Quote({required this.symbol, required this.price, required this.changePct, required this.volume});
}

enum SignalType { buy, sell }

class Signal {
  final String symbol;
  final SignalType type;
  final double price;
  final double volRatio;      // volume vs 20-day average
  final double rsi14;
  final String reason;
  final double score;
  Signal({required this.symbol, required this.type, required this.price,
      required this.volRatio, required this.rsi14, required this.reason, required this.score});

  /// Unique identity for "is this a new signal" comparisons.
  String get key => '$symbol-${type.name}';

  Map<String, dynamic> toJson() => {
    'symbol': symbol, 'type': type.name, 'price': price, 'volRatio': volRatio,
    'rsi14': rsi14, 'reason': reason, 'score': score,
  };
  factory Signal.fromJson(Map<String, dynamic> j) => Signal(
    symbol: j['symbol'],
    type: j['type'] == 'sell' ? SignalType.sell : SignalType.buy,
    price: (j['price'] as num).toDouble(),
    volRatio: (j['volRatio'] as num).toDouble(),
    rsi14: (j['rsi14'] as num).toDouble(),
    reason: j['reason'] ?? '',
    score: (j['score'] as num).toDouble(),
  );
}
