//+------------------------------------------------------------------+
//|                     POM_EA_Logger.mqh                           |
//|         Shared trade logging for all EAs → MACD_Log.csv        |
//|  Drop in MQL5/Include/ on VPS — auto-syncs to local terminal   |
//|                                                                  |
//|  Version: 2.0                                                   |
//|  Added: MFE/MAE excursion tracking (max profit, max drawdown,   |
//|          time-to-peak) for trade lifecycle analysis             |
//+------------------------------------------------------------------+
#ifndef POM_EA_LOGGER_MQH
#define POM_EA_LOGGER_MQH

#define LOG_FILE "MACD_Log.csv"

//+------------------------------------------------------------------+
//| Call once in OnInit() to write the CSV header if file is new    |
//+------------------------------------------------------------------+
void LoggerInit()
{
   int handle = FileOpen(LOG_FILE, FILE_READ|FILE_CSV);
   if(handle == INVALID_HANDLE)
   {
      handle = FileOpen(LOG_FILE, FILE_WRITE|FILE_CSV|FILE_ANSI);
      if(handle == INVALID_HANDLE)
      {
         Print("EA_Logger: cannot create log file. Error: ", GetLastError());
         return;
      }
      FileWrite(handle,
         "ea_name","magic","ticket","symbol","timeframe",
         "open_time","close_time","type",
         "open_price","close_price","sl","tp","lot",
         "sl_pips","tp_pips","profit_pips","profit_usd",
         "exit_reason","be_triggered","trail_triggered",
         "duration_min","session","rr_configured","rr_actual",
         // ── MFE/MAE fields (v2.0) ──
         "mfe_usd",          // Max Favorable Excursion — highest unrealized profit reached
         "mae_usd",          // Max Adverse Excursion  — worst unrealized drawdown reached
         "mfe_pips",         // MFE in pips
         "mae_pips",         // MAE in pips
         "mfe_time_min"      // Minutes from open until MFE was reached
      );
      FileClose(handle);
      Print("EA_Logger: log file created → ", LOG_FILE);
   }
   else
   {
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Detect GMT session name from a datetime                          |
//+------------------------------------------------------------------+
string GetSession(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int h = dt.hour;
   if(h >= 0  && h < 7)  return "Asia";
   if(h >= 7  && h < 13) return "London";
   if(h >= 13 && h < 17) return "Overlap";
   if(h >= 17 && h < 21) return "NewYork";
   return "OffHour";
}

//+------------------------------------------------------------------+
//| Determine exit reason from close price vs SL/TP                 |
//+------------------------------------------------------------------+
string GetExitReason(double closePrice, double sl, double tp,
                     ENUM_POSITION_TYPE posType, bool beTriggered)
{
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tolerance = point * 3;

   if(posType == POSITION_TYPE_BUY)
   {
      if(MathAbs(closePrice - sl) <= tolerance) return beTriggered ? "BE_THEN_SL" : "SL";
      if(MathAbs(closePrice - tp) <= tolerance) return "TP";
      if(closePrice > sl + tolerance)            return "TRAIL";
   }
   else
   {
      if(MathAbs(closePrice - sl) <= tolerance) return beTriggered ? "BE_THEN_SL" : "SL";
      if(MathAbs(closePrice - tp) <= tolerance) return "TP";
      if(closePrice < sl - tolerance)            return "TRAIL";
   }
   return "MANUAL";
}

//+------------------------------------------------------------------+
//| Main logging function — call when a position closes              |
//|                                                                  |
//| Parameters (original):                                           |
//|   eaName         — e.g. "MACD_Scalp_v2.3"                      |
//|   magic          — EA magic number                               |
//|   ticket         — closed position ticket                        |
//|   posType        — POSITION_TYPE_BUY or POSITION_TYPE_SELL      |
//|   openTime       — position open datetime                        |
//|   closeTime      — position close datetime                       |
//|   openPrice      — entry price                                   |
//|   closePrice     — exit price                                    |
//|   sl             — original stop loss                            |
//|   tp             — original take profit                          |
//|   lot            — position size                                 |
//|   profitUsd      — realized P&L in account currency             |
//|   rrConfigured   — EA's configured RR ratio                     |
//|   beTriggered    — whether breakeven fired during this trade     |
//|   trailTriggered — whether trailing stop fired                   |
//|                                                                  |
//| New MFE/MAE parameters (v2.0):                                   |
//|   mfeUsd         — max unrealized profit during trade (USD)      |
//|                    track with: mfeUsd = MathMax(mfeUsd, unrealizedProfit) |
//|   maeUsd         — max unrealized drawdown during trade (USD)    |
//|                    track with: maeUsd = MathMin(maeUsd, unrealizedProfit) |
//|   mfeTimeMin     — minutes from open until MFE was first reached |
//|                    track with: if(unrealizedProfit >= mfeUsd) mfeTimeMin = elapsedMin |
//|                                                                  |
//| How to track in EA OnTick():                                     |
//|   double unreal = PositionGetDouble(POSITION_PROFIT);            |
//|   if(unreal > g_mfeUsd) { g_mfeUsd = unreal; g_mfeTimeMin = elapsedMin; } |
//|   if(unreal < g_maeUsd)   g_maeUsd = unreal;                    |
//+------------------------------------------------------------------+
void LogTrade(
   string             eaName,
   int                magic,
   ulong              ticket,
   ENUM_POSITION_TYPE posType,
   datetime           openTime,
   datetime           closeTime,
   double             openPrice,
   double             closePrice,
   double             sl,
   double             tp,
   double             lot,
   double             profitUsd,
   double             rrConfigured,
   bool               beTriggered,
   bool               trailTriggered,
   double             mfeUsd     = 0.0,   // optional — default 0 if not tracked
   double             maeUsd     = 0.0,   // optional — default 0 if not tracked
   int                mfeTimeMin = 0      // optional — default 0 if not tracked
)
{
   double pipVal  = _Point * 10;
   string sym     = _Symbol;
   string tf      = EnumToString(PERIOD_CURRENT);

   double slPips = 0, tpPips = 0, profitPips = 0, rrActual = 0;
   double mfePips = 0, maePips = 0;

   if(posType == POSITION_TYPE_BUY)
   {
      slPips     = (openPrice - sl)         / pipVal;
      tpPips     = (tp - openPrice)         / pipVal;
      profitPips = (closePrice - openPrice) / pipVal;
   }
   else
   {
      slPips     = (sl - openPrice)         / pipVal;
      tpPips     = (openPrice - tp)         / pipVal;
      profitPips = (openPrice - closePrice) / pipVal;
   }

   rrActual = (slPips > 0) ? profitPips / slPips : 0;

   // Convert MFE/MAE USD → pips (approximate using lot size)
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal > 0 && tickSz > 0 && lot > 0)
   {
      double usdPerPip = (tickVal / tickSz) * pipVal * lot;
      if(usdPerPip > 0)
      {
         mfePips = mfeUsd / usdPerPip;
         maePips = maeUsd / usdPerPip;   // will be negative
      }
   }

   string exitReason  = GetExitReason(closePrice, sl, tp, posType, beTriggered);
   string session     = GetSession(openTime);
   int    durationMin = (int)((closeTime - openTime) / 60);
   string posTypeStr  = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
   string beStr       = beTriggered    ? "true" : "false";
   string trailStr    = trailTriggered ? "true" : "false";

   int handle = FileOpen(LOG_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI);
   if(handle == INVALID_HANDLE)
   {
      Print("EA_Logger: cannot open log file to write. Error: ", GetLastError());
      return;
   }
   FileSeek(handle, 0, SEEK_END);

   FileWrite(handle,
      eaName,
      IntegerToString(magic),
      IntegerToString((long)ticket),
      sym,
      tf,
      TimeToString(openTime,  TIME_DATE|TIME_MINUTES),
      TimeToString(closeTime, TIME_DATE|TIME_MINUTES),
      posTypeStr,
      DoubleToString(openPrice,  _Digits),
      DoubleToString(closePrice, _Digits),
      DoubleToString(sl,         _Digits),
      DoubleToString(tp,         _Digits),
      DoubleToString(lot,        2),
      DoubleToString(slPips,     1),
      DoubleToString(tpPips,     1),
      DoubleToString(profitPips, 1),
      DoubleToString(profitUsd,  2),
      exitReason,
      beStr,
      trailStr,
      IntegerToString(durationMin),
      session,
      DoubleToString(rrConfigured, 1),
      DoubleToString(rrActual,     2),
      // MFE/MAE
      DoubleToString(mfeUsd,   2),
      DoubleToString(maeUsd,   2),
      DoubleToString(mfePips,  1),
      DoubleToString(maePips,  1),
      IntegerToString(mfeTimeMin)
   );

   FileClose(handle);
   Print("EA_Logger: trade logged — ticket=", ticket, " profit=", profitUsd,
         " MFE=", mfeUsd, " MAE=", maeUsd);
}

#endif
//+------------------------------------------------------------------+
