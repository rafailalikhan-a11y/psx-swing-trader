#!/usr/bin/env python3
"""PSX data collector — resilient edition.

Retries with backoff (the PSX feed drops connections under load),
caches the symbol list so a failed /symbols call never kills a run.
"""

import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone, timedelta
from pathlib import Path

BASE = "https://dps.psx.com.pk"
OUT_DIR = Path("data")
PKT = timezone(timedelta(hours=5))
HEADERS = {"User-Agent": "Mozilla/5.0 (PSX-Swing-Trader data collector)"}


def fetch_json(url, timeout=20, retries=4):
    """Retry with exponential backoff: survives RemoteDisconnected bursts."""
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as e:
            if attempt == retries - 1:
                raise
            time.sleep(2 * (attempt + 1))
    return None


def is_market_open():
    now = datetime.now(PKT)
    wd = now.weekday()
    if wd >= 5:
        return False
    mins = now.hour * 60 + now.minute
    if wd == 4:
        return 555 <= mins <= 720
    return 570 <= mins <= 930


def get_symbols():
    cache = OUT_DIR / "symbols_cache.json"
    try:
        data = fetch_json(f"{BASE}/symbols")
        out = []
        for e in data:
            if e.get("isDebt") or e.get("isETF"):
                continue
            sym = e.get("symbol", "")
            if sym and "-" not in sym and len(sym) <= 6:
                out.append(sym)
        if out:
            cache.write_text(json.dumps(sorted(out)))
            return sorted(out)
    except Exception as e:
        print(f"symbols fetch failed ({e}), trying cache…")
    if cache.exists():
        cached = json.loads(cache.read_text())
        print(f"using cached symbol list ({len(cached)} symbols)")
        return cached
    raise RuntimeError("No symbols available and no cache exists")


def fetch_eod(symbol):
    """EOD candles with one retry — improves coverage under rate limiting."""
    for attempt in range(2):
        try:
            body = fetch_json(f"{BASE}/timeseries/eod/{symbol}", retries=2)
            if not (isinstance(body, dict) and body.get("status") == 1):
                return []
            rows = body.get("data") or []
            candles = []
            for row in rows:
                if not isinstance(row, list) or len(row) < 3:
                    continue
                try:
                    candles.append({
                        "t": int(row[0]),
                        "close": float(row[1]),
                        "volume": float(row[2]),
                        "open": float(row[3]) if len(row) >= 4 else float(row[1]),
                    })
                except (ValueError, TypeError):
                    continue
            candles.sort(key=lambda c: c["t"])
            return candles
        except Exception:
            if attempt == 0:
                time.sleep(1.5)
    return []


def sma(values, period):
    if len(values) < period:
        return values[-1] if values else 0.0
    return sum(values[-period:]) / period


def rsi(closes, period=14):
    if len(closes) < period + 1:
        return 50.0
    gain = loss = 0.0
    for i in range(len(closes) - period, len(closes)):
        diff = closes[i] - closes[i - 1]
        if diff >= 0:
            gain += diff
        else:
            loss -= diff
    avg_gain, avg_loss = gain / period, loss / period
    if avg_loss == 0:
        return 100.0
    return 100 - (100 / (1 + avg_gain / avg_loss))


def evaluate(symbol, candles):
    if len(candles) < 22:
        return None
    today = candles[-1]
    closes = [c["close"] for c in candles]
    prior = candles[:-1]
    avg_vol = sum(c["volume"] for c in prior[-20:]) / min(20, len(prior))
    if avg_vol <= 0 or today["volume"] <= 0:
        return None
    vol_ratio = today["volume"] / avg_vol
    if vol_ratio < 2.0:
        return None
    rsi14 = rsi(closes, 14)
    ma20 = sma(closes, 20)
    high20 = max(c["close"] for c in prior[-20:]) if prior else 0
    low20 = min(c["close"] for c in prior[-20:]) if prior else 0
    close = today["close"]

    if 50 <= rsi14 <= 70 and close > ma20 and close >= high20 > 0:
        score = vol_ratio * 40 + (rsi14 - 50) / 20 * 30 + 30
        return {"symbol": symbol, "type": "buy", "price": round(close, 2),
                "volRatio": round(vol_ratio, 2), "rsi14": round(rsi14, 1),
                "score": round(score, 1),
                "reason": f"Volume {vol_ratio:.1f}x avg, breakout above 20-day high "
                          f"(Rs {high20:.2f}), RSI {rsi14:.0f}, price above MA20"}
    if 30 <= rsi14 <= 50 and close < ma20 and close <= low20 and low20 > 0:
        score = vol_ratio * 40 + (50 - rsi14) / 20 * 30 + 30
        return {"symbol": symbol, "type": "sell", "price": round(close, 2),
                "volRatio": round(vol_ratio, 2), "rsi14": round(rsi14, 1),
                "score": round(score, 1),
                "reason": f"Volume {vol_ratio:.1f}x avg, breakdown below 20-day low "
                          f"(Rs {low20:.2f}), RSI {rsi14:.0f}, price below MA20"}
    return None


def main():
    OUT_DIR.mkdir(exist_ok=True)
    now = datetime.now(PKT)
    print(f"[{now:%Y-%m-%d %H:%M PKT}] market open: {is_market_open()}")

    symbols = get_symbols()
    print(f"symbols to scan: {len(symbols)}")

    quotes = {}
    signals = []
    done = 0

    def work(sym):
        candles = fetch_eod(sym)
        if not candles:
            return sym, None, None
        last = candles[-1]
        prev_close = candles[-2]["close"] if len(candles) >= 2 else last["close"]
        quote = {
            "price": round(last["close"], 2),
            "prevClose": round(prev_close, 2),
            "volume": int(last["volume"]),
            "changePct": round((last["close"] - prev_close) / prev_close * 100, 2) if prev_close else 0.0,
        }
        return sym, quote, evaluate(sym, candles)

    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(work, s): s for s in symbols}
        for fut in as_completed(futures):
            sym, quote, sig = fut.result()
            done += 1
            if quote:
                quotes[sym] = quote
            if sig:
                signals.append(sig)
            if done % 100 == 0:
                print(f"progress: {done}/{len(symbols)}")

    signals.sort(key=lambda s: s["score"], reverse=True)
    stamp = now.isoformat()
    (OUT_DIR / "quotes.json").write_text(json.dumps({
        "updated": stamp, "marketOpen": is_market_open(),
        "count": len(quotes), "quotes": quotes}))
    (OUT_DIR / "signals.json").write_text(json.dumps({
        "updated": stamp, "scanned": len(symbols), "signals": signals}))
    print(f"done: {len(quotes)} quotes, {len(signals)} signals")


if __name__ == "__main__":
    main()
