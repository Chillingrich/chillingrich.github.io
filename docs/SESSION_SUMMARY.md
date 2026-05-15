# ChillingRich Trading System — Session Summary

**Date:** 2026-05-15
**Account:** ICMarketsSC-MT5-2 · 7979470
**Owner:** Chumpol Chaikanarakkul

---

## System Overview

| Layer | Component | Status |
|-------|-----------|--------|
| EA Execution | MT5 on Mac (Wine/MetaQuotes) | ✅ Live |
| Trade Export | ExportTradeHistory.mq5 Script | ✅ Ready |
| Data Pipeline | push_all.sh → GitHub Pages | ✅ Ready |
| Dashboard | chillingrich.github.io/dashboard.html | ✅ v2.0 |

---

## Dashboard v2.0 Features

- Auto-fetch trade history from GitHub on load
- EA breakdown cards (grouped by magic number)
- Main date filter: All / Today / This Week / This Month / Custom
- EA modal: click any card → full stats popup
- Modal date filter: same presets
- Equity curve (collapsible) + session summary
- 12 stats per EA: P&L, Win%, PF, Max DD, Avg Win/Loss, Best/Worst, Pips, Duration, Session

---

## EA Registry (Magic Numbers)

| Magic | EA Name | Color |
|-------|---------|-------|
| 20260201 | MACD_Scalp_v2.3 | Gold |
| 20260202 | MACD_Scalp_BTC | Orange |
| 20240101 | BB_RSI_EA | Green |
| 202473 | HTF_BP | Blue |
| 26040313 | Omo_Engulfing | Purple |
| 26041701 | Omo_EMA_Pullback | Pink |
| 202661 | EMA_Triple_Cross | Teal |
| 20250512 | TwoBar_SR_Zone | Gold |
| 0 | Manual | Gray |

**เพิ่ม EA ใหม่:** แก้ `EA_REGISTRY` ใน dashboard.html บรรทัดเดียว แล้ว push

---

## File Structure (GitHub)

```
chillingrich.github.io/
├── data/
│   └── trades.html          ← MT5 export (auto-updated)
├── strategies/
│   └── twobar-sr-zone/
│       ├── TwoBar_SR_Zone_EA.md
│       └── TwoBar_SR_Zone_EA.mq5
├── dashboard.html            ← Dashboard v2.0
├── GITHUB_PUSH_MANUAL.md
└── README.md
```

---

## Daily Workflow

```
1. MT5 → ลาก ExportTradeHistory script ไปวาง chart
   → popup "Export complete! X trades"
2. double-click UpdateDashboard บน Desktop
   (หรือรัน ~/Documents/push_all.sh ใน Terminal)
3. เปิด chillingrich.github.io/dashboard.html
   → trades โหลดอัตโนมัติ ✅
```

---

## Scripts & Tools

| File | Location | หน้าที่ |
|------|----------|---------|
| push_all.sh | ~/Documents/ | Push ทุกอย่างขึ้น GitHub |
| UpdateDashboard.app | Desktop | Double-click แทน Terminal |
| ExportTradeHistory.mq5 | MQL5/Scripts/ | Export trade history จาก MT5 |
| TwoBar_SR_Zone_EA.mq5 | MQL5/Experts/ | EA หลักตอนนี้ |

---

## MT5 Paths (Mac)

```
MT5 Root:
~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/

MQL5 Files (EA เขียนไฟล์ที่นี่):
.../MQL5/Files/

MQL5 Scripts:
.../MQL5/Scripts/

MQL5 Experts:
.../MQL5/Experts/
```

---

## TwoBar SR Zone EA — Current Status

**Version:** 1.20
**Symbol:** XAUUSD
**Timeframe:** M15
**Magic:** 20250512

### Best Config (locked)
```
ATR_SL_Multiplier  = 1.5
MaxZonesPerSide    = 3
ZoneBodyOverlapPct = 50
NoTradeOnMonday    = true
UseSessionFilter   = false
```

### Backtest Results

| Test | Trades | Win% | PF | Net P/L | Change |
|------|--------|------|-----|---------|--------|
| 001 | ~50 | ~50% | <1 | neg | Baseline |
| 002 | 40 | 65% | 0.70 | -$66.90 | +Monday filter, ZoneMaxSize=0.3 |
| 003 | 27 | 59% | 0.56 | -$80.07 | +SessionFilter (worse) |

**Next:** Test 004 — ATR_SL=1.0, SessionFilter=off

### v1.20 Key Changes
- Multi-zone memory (MaxZonesPerSide sell + buy pools)
- Entry on TICK (wick) not bar close
- Zone NOT removed on order open — stays until close-through only
- Re-entry allowed after order closes
- Separate g_SellZones / g_BuyZones arrays
- Mixed candle pairs skipped

---

## Next Steps

- [ ] Run Test 004: ATR_SL=1.0
- [ ] Dashboard: add symbol filter
- [ ] Dashboard: add EA comparison chart
- [ ] TwoBar: add slope filter after positive RR confirmed
- [ ] Export history from XM accounts (341741465, 302028515)
