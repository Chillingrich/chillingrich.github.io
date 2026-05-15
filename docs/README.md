# ChillingRich (CR)
> *Algorithmic Trading Intelligence Platform — chill \& get rich*

> **Purpose of this document:** Enable any AI assistant (Claude, GPT, Gemini, etc.) to
> understand the full project and continue work immediately without re-explaining context.
> Read this file before making any changes.

---

## 1. Project Overview

A **live trading performance dashboard** for Chumpol Chaikanarakkul (Pom).
Tracks algorithmic trading across multiple MetaTrader 5 EAs in real-time.

**Core flow:**
```
MT5 EA (VPS) → POM_EA_Logger.mqh → MACD_Log.csv
  → Google Drive (symlink/sync) → Apps Script Web App
    → dashboard.html (browser, localhost:8080) — auto-fetch every 30s
```

**Additional data source:**
- ICMarkets trade history export (XLSX) → converted to MACD_Log format CSV
- Loaded manually as "history base" → merged with live CSV in dashboard

---

## 2. Infrastructure

| Component | Details |
|---|---|
| MT5 VPS | MetaTrader VPS, New York NY3, ICMarketsSC-MT5-2 (managed, no remote desktop) |
| Local machine | Mac (Chumpol's MacBook) |
| MT5 client | Runs on Mac, connected to VPS |
| MT5 Files path (Mac) | `/Users/chumpolchaikanarakkul/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/Files/` |
| Google Drive path (Mac) | `/Users/chumpolchaikanarakkul/Library/CloudStorage/GoogleDrive-pomparazzi001@gmail.com/My Drive/MACD_Log.csv` |
| Symlink | MACD_Log.csv in MT5 Files → Google Drive path (auto-sync) |
| Google account | pomparazzi001@gmail.com |
| Dashboard URL | http://localhost:8080/dashboard.html (served via `python3 -m http.server 8080` in ~/Downloads) |

### Google Apps Script (CORS proxy)
- **Script URL:** `https://script.google.com/macros/s/AKfycbzLLs3cxNxg7PqLvgiHZwbcI42PbSDe8DONvnjSZLc-NJHjO4ll2D4JLpW-AZ0ivUwJ/exec`
- **Drive File ID:** `1ObZfThK_I4th3-TYQHCr1vMEe4V90xCD`
- Serves CSV content with CORS headers so browser can fetch it
- Chrome must be logged into pomparazzi001@gmail.com

---

## 3. Active EAs & Magic Numbers

| EA Name (dashboard) | Magic Number | Symbol | Notes |
|---|---|---|---|
| MACD_Scalp_v2.3 | 20260201 | XAUUSD | M15, primary EA |
| MACD_Scalp_BTC | 20260202 | BTCUSD | H1/M15 |
| BB_RSI_EA | 20240101 | any | Bollinger Band + RSI reversal |
| HTF_BP | 202473 | XAUUSD/BTCUSD | HTF trend + LTF breakout pullback |
| Omo_Engulfing | 26040313 | any | v3A39+ |
| Omo_EMA_Pullback | 26041701 | any | v1.07 |
| EMA_Triple_Cross | 202661 | any | v6.2 |
| Omo_Sniper | unknown | any | no source file available |
| Mucho | unknown | any | no source file available |

---

## 4. CSV Format — MACD_Log.csv

**Delimiter:** Tab (`\t`)
**Encoding:** ANSI

### Columns (v2.0 — current)

| Column | Type | Description |
|---|---|---|
| ea_name | string | EA identifier, e.g. "MACD_Scalp_v2.3" or "Manual" |
| magic | int | EA magic number (0 = manual/history import) |
| ticket | int | MT5 position ticket (unique per trade) |
| symbol | string | XAUUSD, BTCUSD, EURUSD, etc. |
| timeframe | string | MT5 timeframe, e.g. "PERIOD_M15", or "HISTORY" for imported |
| open_time | datetime | Format: `YYYY.MM.DD HH:MM` |
| close_time | datetime | Format: `YYYY.MM.DD HH:MM` |
| type | string | "BUY" or "SELL" |
| open_price | float | Entry price |
| close_price | float | Exit price |
| sl | float | Stop loss price at open |
| tp | float | Take profit price at open |
| lot | float | Position size |
| sl_pips | float | SL distance in pips |
| tp_pips | float | TP distance in pips |
| profit_pips | float | Realized profit/loss in pips |
| profit_usd | float | Realized P&L in USD |
| exit_reason | string | SL / TP / TRAIL / BE_THEN_SL / MANUAL / HISTORY |
| be_triggered | string | "true" or "false" |
| trail_triggered | string | "true" or "false" |
| duration_min | int | Trade duration in minutes |
| session | string | Asia / London / Overlap / NewYork / OffHour |
| rr_configured | float | EA's configured R:R ratio |
| rr_actual | float | Actual R:R achieved |
| mfe_usd | float | **[v2.0]** Max Favorable Excursion — peak unrealized profit (USD) |
| mae_usd | float | **[v2.0]** Max Adverse Excursion — worst unrealized drawdown (USD, negative) |
| mfe_pips | float | **[v2.0]** MFE in pips |
| mae_pips | float | **[v2.0]** MAE in pips (negative) |
| mfe_time_min | int | **[v2.0]** Minutes from open until MFE was reached |

### Backward compatibility
- Old trades (v1.0) have empty/0 for mfe_usd through mfe_time_min — dashboard handles this gracefully
- History imports (from ICMarkets XLSX) have magic=0, timeframe="HISTORY", exit_reason="HISTORY"

---

## 5. Logger — POM_EA_Logger.mqh

**Location:** `MQL5/Include/POM_EA_Logger.mqh`

### Usage in EA

```mql5
#include <POM_EA_Logger.mqh>

// Declare MFE/MAE tracking variables per trade
double g_mfeUsd    = 0.0;
double g_maeUsd    = 0.0;
int    g_mfeTimMin = 0;
datetime g_openTime;

// In OnTick() — while position is open:
double unrealPnl = PositionGetDouble(POSITION_PROFIT);
int elapsedMin   = (int)((TimeCurrent() - g_openTime) / 60);

if(unrealPnl > g_mfeUsd) {
   g_mfeUsd    = unrealPnl;
   g_mfeTimMin = elapsedMin;
}
if(unrealPnl < g_maeUsd) {
   g_maeUsd = unrealPnl;
}

// When position closes — call LogTrade():
LogTrade(
   "MACD_Scalp_v2.3", 20260201, ticket,
   POSITION_TYPE_BUY, openTime, closeTime,
   openPrice, closePrice, sl, tp, lot,
   profitUsd, rrConfigured,
   beTriggered, trailTriggered,
   g_mfeUsd, g_maeUsd, g_mfeTimMin   // ← new MFE/MAE params
);

// Reset trackers on new trade open:
g_mfeUsd = g_maeUsd = 0.0;
g_mfeTimMin = 0;
g_openTime = TimeCurrent();
```

### Functions in logger
- `LoggerInit()` — call in `OnInit()`, creates CSV with header if new
- `GetSession(datetime)` — returns session string from GMT time
- `GetExitReason(...)` — infers SL/TP/TRAIL/BE_THEN_SL/MANUAL from close price
- `LogTrade(...)` — appends one row to MACD_Log.csv

---

## 6. Dashboard — dashboard.html

**File:** `~/Downloads/dashboard.html`
**Served via:** `python3 -m http.server 8080` → http://localhost:8080/dashboard.html

### Key JavaScript state variables

```javascript
let allTrades      = [];   // merged result of historyTrades + liveTrades (deduped)
let historyTrades  = [];   // from MACD_Log_history.csv (manual drop)
let liveTrades     = [];   // from Google Drive MACD_Log.csv (auto-fetch)
let filteredTrades = [];   // after EA + date + symbol filters applied

let currentEAFilter  = 'all';    // EA filter tab
let currentPreset    = 'all';    // date preset: all/today/week/month/custom
let currentDateMode  = 'open';   // 'open' or 'close'
let currentSymbol    = 'all';    // symbol dropdown
```

### Dedup logic
Two trades are considered identical (same trade) if:
1. **Primary:** `ticket` number matches (when ticket ≠ 0)
2. **Fallback:** `open_time + symbol + type + lot` all match

Live data wins over history data when duplicate found.

### Magic Number → EA Name mapping (in JS)
```javascript
const EA_MAGIC = {
  20260201: 'MACD_Scalp_v2.3',
  20260202: 'MACD_Scalp_BTC',
  20240101: 'BB_RSI_EA',
  202473:   'HTF_BP',
  26040313: 'Omo_Engulfing',
  26041701: 'Omo_EMA_Pullback',
  202661:   'EMA_Triple_Cross',
};
```

### UI Features
- **Header:** Brand, last-updated status, dedup badge, file name, Load CSV button
- **EA Filter Tabs:** Dynamic — built from data. All / Manual / [each EA]
- **Date Filter Bar:** Presets (All/Today/Week/Month/Custom) + from/to pickers + By Open/Close toggle + Symbol dropdown
- **Stat Cards:** Net P&L, Trades, Win Rate, Profit Factor, Avg RR, Avg Win $, Avg Loss $
- **P&L Breakdown:** Clickable cards per EA — opens modal on click
- **EA Detail Modal:** Full stats + equity curve + trade table for selected EA. Close via ✕, Escape, or backdrop click.
- **Charts:** Equity curve (combined + per-EA lines), Exit reason pie, Session P&L bar, Win rate by session, Pips distribution histogram
- **Session Heatmap:** Asia / London / Overlap / New York
- **Trade Table:** All trades, most recent first

### MFE/MAE — Planned features (not yet built in dashboard)
When enough live trades with MFE/MAE data accumulate, add:
- **Trade Lifecycle chart** — scatter plot: x=duration, y=MFE vs actual close. Shows "left money on table" visually.
- **MFE vs Close analysis** — avg(mfe_usd) vs avg(profit_usd) per EA → how much peak profit is captured
- **Optimal close time** — histogram of mfe_time_min → shows when peak profit typically occurs
- **MAE analysis** — max drawdown per trade → informs SL placement

---

## 7. Data Sources & Files

| File | Description |
|---|---|
| `MACD_Log.csv` | Live log — EA writes here on each close |
| `MACD_Log_history.csv` | History import — 650 trades from ICMarkets XLSX (10 Apr – 6 May 2026) |
| `AllTrade_2026_05_06_ICmarkets.xlsx` | Raw ICMarkets history export |
| `dashboard.html` | The dashboard |
| `POM_EA_Logger.mqh` | MT5 include file for logging |

### History import process
`AllTrade_*.xlsx` → Python pandas script → `MACD_Log_history.csv` (tab-delimited, HISTORY timeframe)
EA classification in history data: based on comment field in ICMarkets transaction history.
Most EA trades lack comments → classified as Manual. Magic number matching is primary method going forward.

---

## 8. Session Times (GMT)

| Session | GMT Hours |
|---|---|
| Asia | 00:00 – 06:59 |
| London | 07:00 – 12:59 |
| Overlap | 13:00 – 16:59 |
| NewYork | 17:00 – 20:59 |
| OffHour | 21:00 – 23:59 |

---

## 9. Known Issues & Pending Work

| # | Issue / Task | Status |
|---|---|---|
| 1 | Omo_Sniper and Mucho magic numbers unknown | ❌ No source files |
| 2 | MFE/MAE tracking — needs to be added to each EA's OnTick() | ⏳ Logger updated, EA code not yet |
| 3 | Dashboard MFE/MAE charts (lifecycle analysis, optimal TP timing) | ⏳ Planned |
| 4 | Symlink MACD_Log.csv → Google Drive on Mac verified but EA on VPS not writing to it yet | ⏳ Waiting for trade close |
| 5 | Duration Analysis tab (bar hold time analysis) | ⏳ Deferred until 20-30 live trades |
| 6 | VPS upgrade from MetaTrader VPS ($39/3mo) to Vultr/AWS Lightsail ($5-12/mo) for full RDP access | ⏳ In ~2 months |

---

## 10. Coding Conventions

- **MQ5:** Follow standard MT5 EA structure. All EAs include `POM_EA_Logger.mqh`. Use `LoggerInit()` in OnInit, `LogTrade()` on position close.
- **Dashboard JS:** Vanilla JS, no frameworks. Chart.js 4.4.1 via CDN. Functions named `renderXxx()`. State in top-level `let` variables.
- **CSV:** Tab-delimited, ANSI. Date format `YYYY.MM.DD HH:MM`. All numeric values use `.` as decimal separator.
- **EA naming:** Use consistent names matching `EA_MAGIC` map in dashboard JS.

---

## 11. Quick Start for New AI

If picking up this project mid-session:

1. Read this file fully
2. The dashboard HTML is at `~/Downloads/dashboard.html` on Pom's Mac
3. The logger MQH is at `MQL5/Include/POM_EA_Logger.mqh` on VPS and Mac
4. Ask Pom what specific task to work on — he will upload relevant files
5. Most common tasks: update dashboard.html (add chart/feature), update POM_EA_Logger.mqh (add field), convert trade history XLSX, fix EA MQL5 code

**Do not:**
- Change the CSV column order (breaks history compatibility)
- Change dedup logic without considering both ticket-based and fallback matching
- Remove the Google Drive Apps Script URL or File ID from dashboard.html

---

## BB_RSI_EA — Optimization Log

### v1.27 Best Settings (Jan–Apr 2026, XAUUSD M5)
*Source: ReportOptimizer-7979470.xml + BB_RSI_Optimized_002_.xml*

| Parameter | Old | New | Impact |
|---|---|---|---|
| `InpBBEntryPeriod` | 10 | **11** | Trades 21→28, DD ลดลง |
| `InpATRMultiplier` | 1.52 | **1.40** | DD 17.1%→12.3% |
| `InpBBExitPeriod` | 18 | 18 | ไม่เปลี่ยน |

**Results:** Sharpe 35.66→39.75 · Net profit +$616→+$735 · Equity DD 17.1%→12.3%

**ATR sweet spot:** 1.30–1.45 (ต่ำกว่า 1.20 ผลแย่ลงชัดเจน)
**BB Entry 11** dominates top 10 ทั้ง Sharpe และ Profit
