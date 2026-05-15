# TwoBar_SR_Zone_EA — Strategy & Parameter Reference

**Version:** 1.20
**File:** `TwoBar_SR_Zone_EA.mq5`
**Default Timeframe:** M15
**Suitable Symbols:** XAUUSD, Crypto, FX Pairs
**Last Updated:** 2026-05-15

---

## 1. Concept & Strategy Overview

### Core Idea
Detect two consecutive candles whose **open/close bodies overlap** to form a Support or Resistance zone. Enter when price **wick (tick)** reaches the zone. Zone is invalidated **only when price closes through it** — a wick-only break keeps the zone active for re-entry.

### Why Two-Bar Zone?
- Two candles opening and closing near the same price level = **consensus area**
- When price returns to this zone, it tends to react quickly (bounce or reject)
- Decision-making is fast and objective — no subjective interpretation needed
- More actionable than SMC for intraday and short-term trading

### Trade Philosophy
- **Short-duration trades** — bounce/reaction strategy, not trend-riding
- **Multi-zone memory** — store up to N sell zones and N buy zones simultaneously
- **Wick entry** — enter on tick the moment price reaches the zone, not waiting for bar close
- **Zone persists** — opening an order does NOT remove the zone; zone stays active for re-entry
- **Close-only invalidation** — zone removed only when a bar closes through it
- **Re-entry** — same zone can trigger again after previous order closes (MaxOpenTrades guards against overlap)

---

## 2. Zone Detection Logic

### Overlap Area (v1.10+)
```
Zone high = Min(bodyHigh1, bodyHigh2)   ← top of overlap only
Zone low  = Max(bodyLow1,  bodyLow2)    ← bottom of overlap only
```
Zone is exactly the price range where both candles agree — not the full span.

### Zone Classification
| Zone Type | Formed By | Acts As | Entry Direction |
|-----------|-----------|---------|----------------|
| Bearish Zone | 2 consecutive bearish candles | Resistance | SELL on retest |
| Bullish Zone | 2 consecutive bullish candles | Support | BUY on retest |
| Mixed Zone | 1 bull + 1 bear | Skipped | Not used |

Mixed (one bull + one bear) zones are **ignored** — only pure bearish or pure bullish pairs qualify.

---

## 3. Multi-Zone Memory — v1.20 New

### Two Separate Pools
```
g_SellZones[]  ← resistance zones (bearish two-bar ABOVE current price)
                  sorted: highest zone first
                  max size: MaxZonesPerSide

g_BuyZones[]   ← support zones (bullish two-bar BELOW current price)
                  sorted: lowest zone first
                  max size: MaxZonesPerSide
```

### Zone Selection Priority
- **Sell zones**: highest midpoint first → price hits strongest resistance first
- **Buy zones**: lowest midpoint first → price hits strongest support first

### Zone Memory Lifecycle
```
New bar → Rescan lookback → Rebuild both pools
        → Carry over broken=true from previous bar if same zone still detected
        → Check bar[1] close → mark broken if close-through

Per tick → Check if bid/ask reaches any zone in pool
         → If yes and no order open → enter
         → Zone stays in pool (NOT removed on order open)

Zone removed → only when broken=true (close-through confirmed)
```

### Re-entry Flow
```
Wick hits Sell Zone A → SELL order opened
Order hits TP → order closed → MaxOpenTrades = 0
Price rallies back to Zone A → wick hits again → SELL opened again ✅
(Zone A still in memory, still not broken by close)
```

---

## 4. Entry Logic (v1.20)

```
Every TICK:
  1. ManageOpenTrades()
  2. If new bar → CheckBrokenZones() → DetectAndStoreZones()
  3. PassesMarketFilters() + PassesSpreadFilter()
  4. CountMyTrades() >= MaxOpenTrades → skip
  5. GetATR() → skip if 0
  6. GetTrendDirection()
  7. For each zone in g_SellZones[] (highest first):
       - skip if broken
       - bid within zone ± RetestTolerancePct% → wick hit
       - trend allows sell
       - RequireRejection → check bar[1] rejection
       - MaxSL_Pct check
       → OpenSell() → break (one order per tick)
  8. For each zone in g_BuyZones[] (lowest first):
       - same logic → OpenBuy()
```

### Order Comment Format
```
TwoBar_SR_Zone_[TF]_[DIR]_Z[#]
Example: TwoBar_SR_Zone_M15_SELL_Z7
```

---

## 5. Zone Invalidation (v1.20)

Called on every **new bar** using bar[1] close:

| Zone Type | Broken When |
|-----------|-------------|
| Sell (resistance) | `close[1] > zone.high` |
| Buy (support) | `close[1] < zone.low` |

**Wick-only break does NOT invalidate zone.**
```
Example: Sell Zone at 4720-4725
  Bar close at 4724 (inside zone)  → NOT broken ✅
  Bar close at 4726 (above zone)   → BROKEN ❌ → removed from pool
```

---

## 6. Exit Logic

### Tiered Exit System
```
Entry Price
    │
    ├─── TP1 (ATR × ATR_TP1_Multiplier)
    │        → Close PartialClosePct% of position (default 50%)
    │        → Move SL to Breakeven + 1 point (if UseBEAfterTP1=true)
    │
    └─── TP2 (ATR × ATR_TP2_Multiplier)
             → Close remaining position
             OR trail via Trailing Stop
             OR close at BB Middle Line (if UseBBExit=true)
```

### Exit Priority
1. SL hit → full close
2. TP1 hit → partial close + move to BE
3. BB Middle Line cross (if enabled)
4. Trailing Stop (activates after profit >= TrailActivatePct% of SL distance)
5. TP2 hit → close remainder

---

## 7. Input Parameters

### EA Identity
| Parameter | Default | Description |
|-----------|---------|-------------|
| MagicNumber | 20250512 | Unique identifier per EA instance |
| EA_Comment | TwoBar_SR_Zone_M15 | Order comment prefix |

### Zone Detection
| Parameter | Default | Description |
|-----------|---------|-------------|
| LookbackBars | 100 | Bars scanned per detection cycle |
| ZoneBodyOverlapPct | 50.0 | Min body overlap % to qualify zone |
| ZoneMaxSizePct | 0.3 | Max zone size as % of price |
| RetestTolerancePct | 0.05 | Wick entry tolerance % above/below zone |
| RequireRejection | true | Require rejection candle on bar[1] |
| **MaxZonesPerSide** | **3** | **v1.20 — Max sell + max buy zones stored (1-5)** |

### Trend Filter
| Parameter | Default | Description |
|-----------|---------|-------------|
| UseTrendFilter | true | Enable HTF trend filter |
| TrendTimeframe | H4 | Higher timeframe |
| TrendMethod | TREND_EMA | EMA / HTF Candle / ATR Slope |
| EMA_Fast | 50 | Fast EMA period |
| EMA_Slow | 200 | Slow EMA period |

### Entry
| Parameter | Default | Description |
|-----------|---------|-------------|
| TradeBuy | true | Allow buy orders |
| TradeSell | true | Allow sell orders |
| MaxOpenTrades | 1 | Max simultaneous open trades |

### Exit
| Parameter | Default | Description |
|-----------|---------|-------------|
| ATR_Period | 14 | ATR calculation period |
| ATR_SL_Multiplier | 1.5 | SL = ATR × this |
| ATR_TP1_Multiplier | 1.0 | TP1 = ATR × this (1R) |
| ATR_TP2_Multiplier | 1.5 | TP2 = ATR × this (1.5R) |

### Partial Close & Breakeven
| Parameter | Default | Description |
|-----------|---------|-------------|
| UsePartialClose | true | Close partial lot at TP1 |
| PartialClosePct | 50.0 | % of position to close at TP1 |
| UseBEAfterTP1 | true | Move SL to breakeven after TP1 |

### Trailing Stop
| Parameter | Default | Description |
|-----------|---------|-------------|
| UseTrailingStop | true | Enable ATR-based trailing stop |
| TrailActivatePct | 50.0 | Activate when profit >= X% of SL distance |
| TrailStepPct | 0.05 | Trail step % of price |

### Bollinger Band Exit
| Parameter | Default | Description |
|-----------|---------|-------------|
| UseBBExit | false | Close remaining at BB Middle Line |
| BB_Period | 20 | BB period |
| BB_Deviation | 2.0 | BB deviation |

### Risk Management
| Parameter | Default | Description |
|-----------|---------|-------------|
| RiskPercentPerTrade | 1.0 | Risk % of account balance per trade |
| MaxSpreadPct | 0.05 | Max allowed spread as % of price |
| MaxSL_Pct | 0.5 | Max SL as % of price (safety cap) |

### Market Filters
| Parameter | Default | Description |
|-----------|---------|-------------|
| UseSessionFilter | false | Restrict to session hours |
| SessionStartHour | 8 | Session open (server time) |
| SessionEndHour | 20 | Session close (server time) |
| NoTradeOnFriday | true | Block new trades on Friday |
| FridayStopHour | 20 | Stop Friday trades after this hour |
| NoTradeOnMonday | true | Block Monday gap risk |
| MondayStartHour | 4 | Allow Monday trades after this hour |

---

## 8. Lot Sizing Formula

```
Risk Amount  = Account Balance × RiskPercentPerTrade / 100
SL Distance  = |Entry Price − SL Price|
SL in Ticks  = SL Distance / Tick Size
Lot Size     = Risk Amount / (SL in Ticks × Tick Value)
```

Works on any symbol (XAUUSD, BTCUSD, EURUSD, etc.) using the symbol's own tick size and tick value.

---

## 9. Optimization Roadmap

### Phase 1 — Baseline Logic (no filters)
Confirm strategy has positive edge before adding any filter:

| Priority | Parameter | Range | Step |
|----------|-----------|-------|------|
| 1 | ATR_SL_Multiplier | 0.5 – 2.0 | 0.25 |
| 2 | ATR_TP2_Multiplier | 1.0 – 3.0 | 0.25 |
| 3 | ZoneBodyOverlapPct | 30 – 80 | 10 |
| 4 | ZoneMaxSizePct | 0.1 – 0.5 | 0.1 |
| 5 | MaxZonesPerSide | 1 – 5 | 1 |

### Phase 2 — Filter Testing (one at a time)
| Toggle | Options |
|--------|---------|
| UseTrendFilter | on vs off |
| RequireRejection | on vs off |
| UseSessionFilter | on vs off |
| UseBBExit | on vs off |
| NoTradeOnMonday/Friday | on vs off |

### Phase 3 — Multi-Symbol
Apply locked settings to BTCUSD, ETHUSD, EURUSD. Adjust only `MaxSpreadPct` per symbol.

---

## 10. Backtest Checklist

- [ ] Symbol: XAUUSD
- [ ] Timeframe: M15
- [ ] Model: Every Tick (real ticks)
- [ ] Period: Minimum 6 months
- [ ] Session filter: OFF for baseline
- [ ] Upload HTML + screenshots after each run

---

## 11. Known Limitations

- Zone overlap uses body only (open/close), not wicks — intentional
- Mixed zones (1 bull + 1 bear) are skipped entirely in v1.20
- Entry fires on first qualifying zone per tick — subsequent zones skipped until next tick
- Partial close tracking resets on EA restart (backtest compatible)
- RequireRejection checks bar[1] — useful on bar open only; may miss intra-bar wicks
- BB Middle Exit: test separately; avoid combining with Trailing Stop until validated

---

## 12. Backtest Results Summary

| Test | Version | Settings Change | Trades | Win% | PF | Net P/L | Notes |
|------|---------|----------------|--------|------|-----|---------|-------|
| 001 | v1.00 | Baseline | ~50 | ~50% | <1 | -$xx | Zone too wide, Monday gap issue |
| 002 | v1.10 | NoTradeOnMonday=true, ZoneMaxSizePct=0.3 | 40 | 65% | 0.70 | -$66.90 | WR improved, RR still poor |
| 003 | v1.10 | +UseSessionFilter=true (8-20) | 27 | 59% | 0.56 | -$80.07 | Session filter cut good trades |

**Key Finding:** Session filter not helpful at this stage. Core problem is RR (Avg Win $6 vs Avg Loss $16). Fix SL size first.

---

## 13. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.00 | 2025-05-14 | Initial release |
| 1.10 | 2025-05-14 | Zone = overlap area only; zone priority sorting; close-through invalidation; NoTradeOnMonday default true; ZoneMaxSizePct 0.8→0.3 |
| 1.20 | 2026-05-15 | Multi-zone memory (MaxZonesPerSide sell + buy pools); entry on TICK (wick) not bar open; zone NOT removed on order open — stays until close-through; re-entry allowed after order closes; separate g_SellZones / g_BuyZones arrays; mixed candle pairs skipped |

---

## 14. Related EAs (Same Account)

| EA | Strategy | Best TF | Symbol |
|----|----------|---------|--------|
| DWR_BB | Double Wick Rejection + BB | H1 | XAUUSD |
| ORB_EA | Opening Range Breakout | H1 | XAUUSD |
| BB_RSI_EA | BB + RSI Reversal | H1 | XAUUSD |
| HTF_LTF_EA | HTF Trend + LTF Breakout | H1/M15 | XAUUSD |
| **TwoBar_SR_Zone_EA** | **Two-Bar S/R Zone Retest** | **M15** | **XAUUSD / Crypto** |
