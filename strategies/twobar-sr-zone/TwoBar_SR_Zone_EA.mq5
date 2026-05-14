//+------------------------------------------------------------------+
//|                                          TwoBar_SR_Zone_EA.mq5   |
//|                                    Two-Bar S/R Zone Strategy EA   |
//|                                                                    |
//|  Concept: Two consecutive candles with overlapping bodies form    |
//|           an S/R zone. Enter when WICK (tick) reaches zone.       |
//|           Zone removed ONLY when price CLOSES through it.         |
//|           Re-entry allowed on same zone after order closes.       |
//|                                                                    |
//|  v1.00 - Initial release                                           |
//|  v1.10 - Fix zone width, sort zones, close-through invalidation   |
//|  v1.20 - Multi-zone memory (MaxZonesPerSide sell + buy stored)    |
//|         - Entry on TICK (wick) not bar open                        |
//|         - Zone NOT removed on order open; stays until close-break  |
//|         - Re-entry: same zone re-triggers after order closes       |
//|         - Separate sell zone / buy zone pools                      |
//|         - Sell zones = bearish two-bar above price (resistance)    |
//|         - Buy  zones = bullish two-bar below price (support)       |
//+------------------------------------------------------------------+
#property copyright "TwoBar SR Zone EA"
#property version   "1.20"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//=== ENUMS ==============================================================

enum ENUM_TREND_METHOD
{
   TREND_EMA         = 0,  // EMA Direction
   TREND_HTF_CANDLE  = 1,  // HTF Candle Direction
   TREND_ATR_SLOPE   = 2   // ATR Slope
};

//=== INPUTS =============================================================

input group "=== EA IDENTITY ==="
input int      MagicNumber         = 20250512;
input string   EA_Comment          = "TwoBar_SR_Zone_M15";

input group "=== ZONE DETECTION ==="
input int      LookbackBars        = 100;
input double   ZoneBodyOverlapPct  = 50.0;   // Min body overlap %
input double   ZoneMaxSizePct      = 0.3;    // Max zone size % of price
input double   RetestTolerancePct  = 0.05;   // Wick tolerance % above/below zone
input bool     RequireRejection    = true;   // Require rejection candle (bar[1])
input int      MaxZonesPerSide     = 3;      // Max sell zones + max buy zones (1-5)

input group "=== TREND FILTER ==="
input bool              UseTrendFilter = true;
input ENUM_TIMEFRAMES   TrendTimeframe = PERIOD_H4;
input ENUM_TREND_METHOD TrendMethod    = TREND_EMA;
input int               EMA_Fast      = 50;
input int               EMA_Slow      = 200;

input group "=== ENTRY ==="
input bool     TradeBuy        = true;
input bool     TradeSell       = true;
input int      MaxOpenTrades   = 1;

input group "=== EXIT ==="
input int      ATR_Period            = 14;
input double   ATR_SL_Multiplier     = 1.5;
input double   ATR_TP1_Multiplier    = 1.0;
input double   ATR_TP2_Multiplier    = 1.5;

input group "=== PARTIAL CLOSE & BREAKEVEN ==="
input bool     UsePartialClose   = true;
input double   PartialClosePct   = 50.0;
input bool     UseBEAfterTP1     = true;

input group "=== TRAILING STOP ==="
input bool     UseTrailingStop   = true;
input double   TrailActivatePct  = 50.0;
input double   TrailStepPct      = 0.05;

input group "=== BOLLINGER BAND EXIT ==="
input bool     UseBBExit         = false;
input int      BB_Period         = 20;
input double   BB_Deviation      = 2.0;

input group "=== RISK MANAGEMENT ==="
input double   RiskPercentPerTrade = 1.0;
input double   MaxSpreadPct        = 0.05;
input double   MaxSL_Pct           = 0.5;

input group "=== MARKET FILTERS ==="
input bool     UseSessionFilter  = false;
input int      SessionStartHour  = 8;
input int      SessionEndHour    = 20;
input bool     NoTradeOnFriday   = true;
input int      FridayStopHour    = 20;
input bool     NoTradeOnMonday   = true;
input int      MondayStartHour   = 4;

//=== STRUCT =============================================================

struct ZoneInfo
{
   double   high;
   double   low;
   bool     isBullish;
   bool     isBearish;
   bool     broken;
   datetime formed;
};

//=== GLOBALS ============================================================

ZoneInfo  g_SellZones[];   // resistance zones above price, sorted highest first
ZoneInfo  g_BuyZones[];    // support zones below price, sorted lowest first
int       g_SellCount = 0;
int       g_BuyCount  = 0;

bool      g_PartialDone[];
ulong     g_Tickets[];
int       g_TicketCount = 0;
int       g_ZoneIDSeq   = 0;

int       g_HandleATR     = INVALID_HANDLE;
int       g_HandleEMAFast = INVALID_HANDLE;
int       g_HandleEMASlow = INVALID_HANDLE;
int       g_HandleBB      = INVALID_HANDLE;

//=== INIT ===============================================================

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   g_HandleATR     = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   g_HandleEMAFast = iMA(_Symbol, TrendTimeframe, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleEMASlow = iMA(_Symbol, TrendTimeframe, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   if(UseBBExit)
      g_HandleBB   = iBands(_Symbol, PERIOD_CURRENT, BB_Period, 0, BB_Deviation, PRICE_CLOSE);

   if(g_HandleATR == INVALID_HANDLE)
   { Print("TwoBar EA v1.20: ATR handle failed"); return INIT_FAILED; }

   Print("TwoBar_SR_Zone_EA v1.20 | Magic=", MagicNumber,
         " | ", _Symbol, " | ", EnumToString(Period()),
         " | MaxZonesPerSide=", MaxZonesPerSide);
   return INIT_SUCCEEDED;
}

//=== DEINIT =============================================================

void OnDeinit(const int reason)
{
   if(g_HandleATR     != INVALID_HANDLE) IndicatorRelease(g_HandleATR);
   if(g_HandleEMAFast != INVALID_HANDLE) IndicatorRelease(g_HandleEMAFast);
   if(g_HandleEMASlow != INVALID_HANDLE) IndicatorRelease(g_HandleEMASlow);
   if(g_HandleBB      != INVALID_HANDLE) IndicatorRelease(g_HandleBB);
}

//=== ON TICK ============================================================

void OnTick()
{
   // Manage existing positions every tick
   ManageOpenTrades();

   // New bar: refresh zone memory + check close-through invalidation
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(curBar != lastBar)
   {
      lastBar = curBar;
      CheckBrokenZones();   // check on newly closed bar[1]
      DetectAndStoreZones();
   }

   // Entry checks every tick
   if(!PassesMarketFilters()) return;
   if(!PassesSpreadFilter())  return;
   if(CountMyTrades() >= MaxOpenTrades) return;

   double atr = GetATR();
   if(atr <= 0) return;

   int trendDir = GetTrendDirection();
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Try sell entries (wick hits resistance zone)
   if(TradeSell)
      TryEnterSell(bid, atr, trendDir);

   // Try buy entries (wick hits support zone)
   if(TradeBuy)
      TryEnterBuy(ask, atr, trendDir);
}

//=== TRY ENTER SELL =====================================================

void TryEnterSell(double bid, double atr, int trendDir)
{
   if(UseTrendFilter && trendDir == 1) return; // bullish trend, skip sell

   double tolAbs = bid * RetestTolerancePct / 100.0;

   for(int i = 0; i < g_SellCount; i++)
   {
      if(g_SellZones[i].broken) continue;

      // Wick reaches zone (bid touches zone area)
      bool wickHit = (bid >= g_SellZones[i].low  - tolAbs &&
                      bid <= g_SellZones[i].high + tolAbs);
      if(!wickHit) continue;

      // Rejection candle on last closed bar
      if(RequireRejection && !HasRejectionCandle(-1)) continue;

      // SL size check
      double slDist = atr * ATR_SL_Multiplier;
      if(MaxSL_Pct > 0 && slDist > bid * MaxSL_Pct / 100.0) continue;

      g_ZoneIDSeq++;
      string cmt = EA_Comment + "_SELL_Z" + IntegerToString(g_ZoneIDSeq);
      OpenSell(atr, cmt, g_SellZones[i]);

      // Zone stays — NOT marked used — can re-trigger after order closes
      break; // one order per tick
   }
}

//=== TRY ENTER BUY ======================================================

void TryEnterBuy(double ask, double atr, int trendDir)
{
   if(UseTrendFilter && trendDir == -1) return; // bearish trend, skip buy

   double tolAbs = ask * RetestTolerancePct / 100.0;

   for(int i = 0; i < g_BuyCount; i++)
   {
      if(g_BuyZones[i].broken) continue;

      // Wick reaches zone
      bool wickHit = (ask >= g_BuyZones[i].low  - tolAbs &&
                      ask <= g_BuyZones[i].high + tolAbs);
      if(!wickHit) continue;

      if(RequireRejection && !HasRejectionCandle(1)) continue;

      double slDist = atr * ATR_SL_Multiplier;
      if(MaxSL_Pct > 0 && slDist > ask * MaxSL_Pct / 100.0) continue;

      g_ZoneIDSeq++;
      string cmt = EA_Comment + "_BUY_Z" + IntegerToString(g_ZoneIDSeq);
      OpenBuy(atr, cmt, g_BuyZones[i]);

      break;
   }
}

//=== DETECT & STORE ZONES ===============================================
// Scan lookback → detect all two-bar zones
// Sell zones = bearish pair ABOVE current price (resistance)
// Buy  zones = bullish pair BELOW current price (support)
// Keep top MaxZonesPerSide of each; preserve broken state from old memory

void DetectAndStoreZones()
{
   double curPrice = iClose(_Symbol, PERIOD_CURRENT, 1);
   int    bars     = MathMin(LookbackBars, iBars(_Symbol, PERIOD_CURRENT) - 2);

   ZoneInfo rawSell[]; int rawSellCnt = 0;
   ZoneInfo rawBuy[];  int rawBuyCnt  = 0;

   for(int i = 1; i < bars; i++)
   {
      double o1 = iOpen (_Symbol, PERIOD_CURRENT, i+1);
      double c1 = iClose(_Symbol, PERIOD_CURRENT, i+1);
      double o2 = iOpen (_Symbol, PERIOD_CURRENT, i);
      double c2 = iClose(_Symbol, PERIOD_CURRENT, i);

      double bH1 = MathMax(o1,c1); double bL1 = MathMin(o1,c1);
      double bH2 = MathMax(o2,c2); double bL2 = MathMin(o2,c2);

      double oHigh = MathMin(bH1, bH2);
      double oLow  = MathMax(bL1, bL2);
      if(oHigh <= oLow) continue;

      double oSize   = oHigh - oLow;
      double minBody = MathMin(bH1-bL1, bH2-bL2);
      if(minBody <= 0) continue;
      if((oSize / minBody) * 100.0 < ZoneBodyOverlapPct) continue;
      if(ZoneMaxSizePct > 0 && oSize > curPrice * ZoneMaxSizePct / 100.0) continue;

      bool b1Bear = (c1 < o1);
      bool b2Bear = (c2 < o2);
      bool isBear = (b1Bear  && b2Bear);
      bool isBull = (!b1Bear && !b2Bear);
      if(!isBear && !isBull) continue;

      double mid = (oHigh + oLow) / 2.0;

      ZoneInfo z;
      z.high      = oHigh;
      z.low       = oLow;
      z.isBullish = isBull;
      z.isBearish = isBear;
      z.broken    = false;
      z.formed    = iTime(_Symbol, PERIOD_CURRENT, i);

      // Resistance: bearish two-bar above price
      if(isBear && mid > curPrice)
      {
         // Carry over broken flag if zone already in memory
         for(int k = 0; k < g_SellCount; k++)
         {
            if(MathAbs(g_SellZones[k].high - z.high) < _Point*10 &&
               MathAbs(g_SellZones[k].low  - z.low)  < _Point*10)
            { z.broken = g_SellZones[k].broken; break; }
         }
         if(!z.broken)
         { ArrayResize(rawSell, rawSellCnt+1); rawSell[rawSellCnt++] = z; }
      }

      // Support: bullish two-bar below price
      if(isBull && mid < curPrice)
      {
         for(int k = 0; k < g_BuyCount; k++)
         {
            if(MathAbs(g_BuyZones[k].high - z.high) < _Point*10 &&
               MathAbs(g_BuyZones[k].low  - z.low)  < _Point*10)
            { z.broken = g_BuyZones[k].broken; break; }
         }
         if(!z.broken)
         { ArrayResize(rawBuy, rawBuyCnt+1); rawBuy[rawBuyCnt++] = z; }
      }
   }

   // Sort sell: highest first
   for(int a = 0; a < rawSellCnt-1; a++)
   for(int b = a+1; b < rawSellCnt; b++)
   {
      if((rawSell[a].high+rawSell[a].low)/2.0 < (rawSell[b].high+rawSell[b].low)/2.0)
      { ZoneInfo tmp = rawSell[a]; rawSell[a] = rawSell[b]; rawSell[b] = tmp; }
   }

   // Sort buy: lowest first
   for(int a = 0; a < rawBuyCnt-1; a++)
   for(int b = a+1; b < rawBuyCnt; b++)
   {
      if((rawBuy[a].high+rawBuy[a].low)/2.0 > (rawBuy[b].high+rawBuy[b].low)/2.0)
      { ZoneInfo tmp = rawBuy[a]; rawBuy[a] = rawBuy[b]; rawBuy[b] = tmp; }
   }

   // Store top N
   g_SellCount = MathMin(rawSellCnt, MaxZonesPerSide);
   ArrayResize(g_SellZones, g_SellCount);
   for(int i = 0; i < g_SellCount; i++) g_SellZones[i] = rawSell[i];

   g_BuyCount  = MathMin(rawBuyCnt,  MaxZonesPerSide);
   ArrayResize(g_BuyZones, g_BuyCount);
   for(int i = 0; i < g_BuyCount; i++) g_BuyZones[i] = rawBuy[i];

   Print("TwoBar v1.20 | SellZones=", g_SellCount, " BuyZones=", g_BuyCount);
   for(int i = 0; i < g_SellCount; i++)
      Print("  SELL[",i,"] ", DoubleToString(g_SellZones[i].low,2),
            "-", DoubleToString(g_SellZones[i].high,2));
   for(int i = 0; i < g_BuyCount; i++)
      Print("  BUY[", i,"] ", DoubleToString(g_BuyZones[i].low,2),
            "-", DoubleToString(g_BuyZones[i].high,2));
}

//=== CHECK BROKEN ZONES =================================================
// Called on new bar using bar[1] close
// Sell zone broken: close > zone.high
// Buy  zone broken: close < zone.low

void CheckBrokenZones()
{
   double cls = iClose(_Symbol, PERIOD_CURRENT, 1);

   for(int i = 0; i < g_SellCount; i++)
   {
      if(g_SellZones[i].broken) continue;
      if(cls > g_SellZones[i].high)
      {
         g_SellZones[i].broken = true;
         Print("TwoBar v1.20 | SELL zone BROKEN close=",
               DoubleToString(cls,2), " zone=",
               DoubleToString(g_SellZones[i].low,2), "-",
               DoubleToString(g_SellZones[i].high,2));
      }
   }

   for(int i = 0; i < g_BuyCount; i++)
   {
      if(g_BuyZones[i].broken) continue;
      if(cls < g_BuyZones[i].low)
      {
         g_BuyZones[i].broken = true;
         Print("TwoBar v1.20 | BUY zone BROKEN close=",
               DoubleToString(cls,2), " zone=",
               DoubleToString(g_BuyZones[i].low,2), "-",
               DoubleToString(g_BuyZones[i].high,2));
      }
   }
}

//=== REJECTION CANDLE ===================================================

bool HasRejectionCandle(int dir)
{
   double o = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double h = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double c = iClose(_Symbol, PERIOD_CURRENT, 1);
   double body  = MathAbs(c - o);
   double upper = h - MathMax(o, c);
   double lower = MathMin(o, c) - l;
   if(body <= 0) return false;
   if(dir ==  1) return (lower > body * 1.5);
   if(dir == -1) return (upper > body * 1.5);
   return false;
}

//=== OPEN BUY / SELL ====================================================

void OpenBuy(double atr, string cmt, ZoneInfo &z)
{
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl   = ask - atr * ATR_SL_Multiplier;
   double tp2  = ask + atr * ATR_TP2_Multiplier;
   double lots = CalcLotSize(MathAbs(ask - sl));
   if(lots <= 0) return;
   if(trade.Buy(lots, _Symbol, ask, sl, tp2, cmt))
   {
      RegisterTicket(trade.ResultOrder());
      Print("TwoBar v1.20 | BUY  | zone=", DoubleToString(z.low,2),
            "-", DoubleToString(z.high,2),
            " sl=", DoubleToString(sl,2), " tp=", DoubleToString(tp2,2));
   }
}

void OpenSell(double atr, string cmt, ZoneInfo &z)
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl   = bid + atr * ATR_SL_Multiplier;
   double tp2  = bid - atr * ATR_TP2_Multiplier;
   double lots = CalcLotSize(MathAbs(sl - bid));
   if(lots <= 0) return;
   if(trade.Sell(lots, _Symbol, bid, sl, tp2, cmt))
   {
      RegisterTicket(trade.ResultOrder());
      Print("TwoBar v1.20 | SELL | zone=", DoubleToString(z.low,2),
            "-", DoubleToString(z.high,2),
            " sl=", DoubleToString(sl,2), " tp=", DoubleToString(tp2,2));
   }
}

//=== MANAGE OPEN TRADES =================================================

void ManageOpenTrades()
{
   double atr = GetATR();
   if(atr <= 0) return;

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;

      double openP  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL  = PositionGetDouble(POSITION_SL);
      double curTP  = PositionGetDouble(POSITION_TP);
      double lots   = PositionGetDouble(POSITION_VOLUME);
      long   pType  = PositionGetInteger(POSITION_TYPE);
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price  = (pType == POSITION_TYPE_BUY) ? bid : ask;
      double slDist = MathAbs(openP - curSL);
      if(slDist <= 0) continue;

      double tp1    = (pType == POSITION_TYPE_BUY)
                      ? openP + slDist * ATR_TP1_Multiplier
                      : openP - slDist * ATR_TP1_Multiplier;
      bool   tp1Hit = (pType == POSITION_TYPE_BUY) ? (price >= tp1) : (price <= tp1);
      int    idx    = FindTicketIdx(ticket);

      // Partial close + BE
      if(UsePartialClose && tp1Hit && !IsPartialDone(idx))
      {
         double cl = NormalizeLots(lots * PartialClosePct / 100.0);
         if(cl > 0 && cl < lots && trade.PositionClosePartial(ticket, cl))
            MarkPartialDone(idx);
         if(UseBEAfterTP1)
         {
            double beSL = (pType == POSITION_TYPE_BUY) ? openP + _Point : openP - _Point;
            if((pType == POSITION_TYPE_BUY  && beSL > curSL) ||
               (pType == POSITION_TYPE_SELL && beSL < curSL))
               trade.PositionModify(ticket, beSL, curTP);
         }
      }

      // Trailing stop
      if(UseTrailingStop)
      {
         double actDist = slDist * TrailActivatePct / 100.0;
         double step    = price  * TrailStepPct     / 100.0;
         if(pType == POSITION_TYPE_BUY && (price - openP) >= actDist)
         {
            double nSL = MathMax(price - slDist, curSL + step);
            if(nSL > curSL) trade.PositionModify(ticket, nSL, curTP);
         }
         if(pType == POSITION_TYPE_SELL && (openP - price) >= actDist)
         {
            double nSL = MathMin(price + slDist, curSL - step);
            if(nSL < curSL) trade.PositionModify(ticket, nSL, curTP);
         }
      }

      // BB middle exit
      if(UseBBExit && g_HandleBB != INVALID_HANDLE)
      {
         double bbM[]; ArraySetAsSeries(bbM, true);
         if(CopyBuffer(g_HandleBB, 1, 0, 2, bbM) >= 1)
         {
            if((pType == POSITION_TYPE_BUY  && bid <= bbM[1]) ||
               (pType == POSITION_TYPE_SELL && ask >= bbM[1]))
               trade.PositionClose(ticket);
         }
      }
   }
}

//=== FILTERS ============================================================

bool PassesMarketFilters()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int dow = dt.day_of_week, h = dt.hour;
   if(NoTradeOnFriday && dow == 5 && h >= FridayStopHour)    return false;
   if(NoTradeOnMonday && dow == 1 && h <  MondayStartHour)   return false;
   if(UseSessionFilter && (h < SessionStartHour || h >= SessionEndHour)) return false;
   return true;
}

bool PassesSpreadFilter()
{
   if(MaxSpreadPct <= 0) return true;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return ((ask - bid) <= ask * MaxSpreadPct / 100.0);
}

//=== TREND DIRECTION ====================================================

int GetTrendDirection()
{
   if(!UseTrendFilter) return 0;
   double b1[], b2[];
   ArraySetAsSeries(b1, true); ArraySetAsSeries(b2, true);

   if(TrendMethod == TREND_EMA)
   {
      if(CopyBuffer(g_HandleEMAFast, 0, 0, 3, b1) < 1) return 0;
      if(CopyBuffer(g_HandleEMASlow, 0, 0, 3, b2) < 1) return 0;
      return (b1[1] > b2[1]) ? 1 : (b1[1] < b2[1]) ? -1 : 0;
   }
   if(TrendMethod == TREND_HTF_CANDLE)
   {
      double o = iOpen(_Symbol, TrendTimeframe, 1);
      double c = iClose(_Symbol, TrendTimeframe, 1);
      return (c > o) ? 1 : (c < o) ? -1 : 0;
   }
   if(TrendMethod == TREND_ATR_SLOPE)
   {
      double c1 = iClose(_Symbol, TrendTimeframe, 1);
      double c3 = iClose(_Symbol, TrendTimeframe, 3);
      return (c1 > c3) ? 1 : (c1 < c3) ? -1 : 0;
   }
   return 0;
}

//=== LOT SIZE ===========================================================

double CalcLotSize(double slDist)
{
   if(slDist <= 0) return 0;
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercentPerTrade / 100.0;
   double tv   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0 || tv <= 0) return 0;
   return NormalizeLots(risk / ((slDist / ts) * tv));
}

double NormalizeLots(double lots)
{
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathMax(mn, MathMin(mx, MathFloor(lots / st) * st));
}

//=== ATR ================================================================

double GetATR()
{
   double buf[]; ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_HandleATR, 0, 1, 1, buf) < 1) return 0;
   return buf[0];
}

//=== TICKET MANAGEMENT ==================================================

void RegisterTicket(ulong t)
{
   ArrayResize(g_Tickets,     g_TicketCount+1);
   ArrayResize(g_PartialDone, g_TicketCount+1);
   g_Tickets[g_TicketCount]     = t;
   g_PartialDone[g_TicketCount] = false;
   g_TicketCount++;
}

int FindTicketIdx(ulong t)
{
   for(int i = 0; i < g_TicketCount; i++) if(g_Tickets[i] == t) return i;
   return -1;
}

bool IsPartialDone(int idx)  { return (idx >= 0 && idx < g_TicketCount) ? g_PartialDone[idx] : false; }
void MarkPartialDone(int idx){ if(idx >= 0 && idx < g_TicketCount) g_PartialDone[idx] = true; }

//=== TRADE COUNT ========================================================

int CountMyTrades()
{
   int n = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong t = PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)     continue;
      n++;
   }
   return n;
}
//+------------------------------------------------------------------+
