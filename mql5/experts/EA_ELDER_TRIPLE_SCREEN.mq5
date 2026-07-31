//+------------------------------------------------------------------+
//| EA_ELDER_TRIPLE_SCREEN.mq5                                       |
//| Alexander Elder's Triple Screen trading system                   |
//| + Elder Impulse System filter (EMA13 + MACD histogram)            |
//| + Elder's 2% / 6% money-management rules                          |
//| + ATR-adaptive stop, partial profit-taking, loss-streak cooldown, |
//|   weekly trade cap and CSV trade journal + on-chart dashboard      |
//|                                                                    |
//| Screen 1 (Tide)   - long-term TF, 3 EMAs (9/21/50) stacked set    |
//|                     the ONLY allowed trade direction.              |
//| Screen 2 (Wave)   - intermediate TF, waits for a pullback into    |
//|                     the EMA21/EMA50 zone against the tide (the    |
//|                     "discount"), confirmed by the Impulse filter. |
//| Screen 3 (Ripple) - short TF, fires the entry trigger              |
//|                     (EMA cross / Force Index / pivot breakout).   |
//|                                                                    |
//| NOTE: no rule set guarantees profit. This is engineering for      |
//| robustness (Elder's full published method), not a promise of      |
//| "extreme profitability". Backtest, walk-forward test and demo-    |
//| trade before risking real capital.                                |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"
#property strict
#include <Trade\Trade.mqh>

//==================================================================
// INPUTS
//==================================================================
input group "=== Timeframes (Tide > Wave > Ripple) ==="
input ENUM_TIMEFRAMES InpTideTF   = PERIOD_MN1;  // Tide (trend filter, Screen 1)
input ENUM_TIMEFRAMES InpWaveTF   = PERIOD_W1;   // Wave (pullback + Impulse, Screen 2)
input ENUM_TIMEFRAMES InpRippleTF = PERIOD_D1;   // Ripple (entry trigger, Screen 3)
// Day-trade preset suggestion: Tide=D1, Wave=H4, Ripple=H1 (or D1/H1/M15)

input group "=== EMAs ==="
input int InpEmaFast = 9;   // Fast EMA period
input int InpEmaMid  = 21;  // Mid EMA period (pullback target)
input int InpEmaSlow = 50;  // Slow EMA period

input group "=== Entry trigger (Screen 3) ==="
enum ENUM_TRIGGER { TRIGGER_EMA_CROSS, TRIGGER_FORCE_INDEX, TRIGGER_PIVOT };
input ENUM_TRIGGER InpTrigger    = TRIGGER_EMA_CROSS;
input int          InpForcePeriod = 2; // Force Index smoothing period

input group "=== Wave pullback filter ==="
input int InpWaveLookback = 4; // bars checked for a touch of EMA21/50 on the Wave TF

input group "=== Elder Impulse System filter (Screen 2 confirmation) ==="
input bool InpUseImpulseFilter = true; // block buys on red impulse / sells on green impulse
input int  InpImpulseEmaPeriod = 13;   // Elder's standard impulse EMA period
input int  InpMacdFast   = 12;
input int  InpMacdSlow   = 26;
input int  InpMacdSignal = 9;

input group "=== Volatility filter ==="
input bool   InpUseMinATRFilter = false; // skip entries in dead/choppy markets
input double InpMinATRPercent   = 0.15;  // minimum ATR(ripple) as % of price to allow a trade

input group "=== Risk per trade ==="
input double InpRiskPercent    = 1.0;  // % of balance risked per trade (requested)
input double InpMaxRiskPercent = 2.0;  // Elder's 2% rule - hard ceiling
input double InpRiskReward     = 2.5;  // reward multiple of initial risk (final target)
input int    InpSwingLookback  = 10;   // bars on Ripple TF used for the structural stop level
input int    InpMaxSpreadPts   = 300;  // skip entries if spread exceeds this
input bool   InpOnePositionOnly = true; // only one open position at a time

input group "=== ATR-adaptive stop ==="
input bool   InpUseATRStop    = true; // ATR buffer instead of fixed points
input int    InpATRPeriod     = 14;
input double InpATRBufferMult = 0.5;  // buffer beyond swing low/high = ATR * this
input int    InpStopBufferPts = 50;   // fallback buffer (points) when InpUseATRStop = false

input group "=== Monthly drawdown circuit breaker (Elder's 6% rule) ==="
input bool   InpUseMonthlyStop = true;
input double InpMonthlyMaxLossPercent = 6.0; // halt new entries for rest of month past this DD

input group "=== Daily drawdown circuit breaker (extra safety) ==="
input bool   InpUseDailyStop = false;
input double InpDailyMaxLossPercent = 3.0; // halt new entries for rest of day past this DD

input group "=== Partial profit-taking ==="
input bool   InpUsePartialClose     = true;
input double InpPartialTakeR        = 1.0;  // take partial once profit reaches this many R
input double InpPartialClosePercent = 50;   // % of position closed at that point
input bool   InpMoveToBreakeven     = true; // move stop to breakeven after partial close

input group "=== Trailing stop (runs on the remainder) ==="
input bool   InpUseTrailing = true;
input double InpTrailStartR = 1.5;  // start trailing once profit >= this many R
input double InpTrailStepR  = 0.75; // trail distance, in R

input group "=== Loss-streak cooldown (trading-psychology rule) ==="
input bool InpUseLossCooldown        = true;
input int  InpMaxConsecutiveLosses   = 3;
input int  InpCooldownBarsAfterLosses = 5; // ripple bars to sit out after hitting the streak limit

input group "=== Overtrading guard ==="
input int InpMaxTradesPerWeek = 0; // 0 = unlimited

input group "=== Trade journal ==="
input bool   InpEnableJournal = true;
input string InpJournalFile   = "EA_ELDER_TRIPLE_SCREEN_Journal.csv";

input group "=== Alerts ==="
input bool InpEnableAlerts = true; // terminal Alert() popups on trade events

input group "=== On-chart dashboard ==="
input bool             InpShowDashboard    = true;
input ENUM_BASE_CORNER InpDashboardCorner  = CORNER_LEFT_UPPER;
input int              InpDashboardX       = 12;
input int              InpDashboardY       = 20;
input int              InpDashboardFontSize = 9;

input group "=== Indicadores visiveis no grafico ==="
input bool InpShowChartIndicators = true; // plota EMAs/MACD/Force/Volume/ATR no grafico anexado
input bool InpShowTradeMarkers    = true; // seta de entrada/saida com tooltip (preco, SL, TP, lote, motivo)
input bool InpOpenTideWaveCharts  = true; // abre (ou reaproveita) janelas de grafico para Tide e Wave, com seus proprios indicadores

input group "=== Misc ==="
input ulong  InpMagic        = 20260712;
input string InpTradeComment = "ElderTripleScreen";

//==================================================================
// GLOBALS
//==================================================================
CTrade trade;

int hTideEma9, hTideEma21, hTideEma50;
int hWaveEma21, hWaveEma50, hWaveImpulseEma, hWaveMacd;
int hRippleEma9, hRippleEma21, hRippleForce, hRippleATR;

// visual-only indicators plotted on the attached chart's own timeframe (not used in logic)
int hVisEma9, hVisEma21, hVisEma50, hVisMacd, hVisForce, hVisVolumes, hVisATR;

// auxiliary chart windows opened for Tide/Wave (Ripple = the chart the EA is attached to, chart 0)
long g_chartTide = 0;
long g_chartWave = 0;
int  hTideVisEma9, hTideVisEma21, hTideVisEma50;
int  hWaveVisEma21, hWaveVisEma50, hWaveVisImpulseEma, hWaveVisMacd;

datetime g_lastRippleBarTime = 0;

// per-position risk / partial-close tracking (small arrays, one entry per open position)
ulong  g_posTicket[];
double g_posRisk[];
bool   g_posPartialDone[];

// monthly drawdown circuit breaker
double g_monthStartBalance = 0;
int    g_monthKey = -1;
bool   g_monthlyHalted = false;

// daily drawdown circuit breaker
double g_dayStartBalance = 0;
int    g_dayKey = -1;
bool   g_dailyHalted = false;

// loss-streak cooldown
int g_consecutiveLosses = 0;
int g_cooldownBarsLeft  = 0;

// weekly trade cap
int g_weekKey = -1;
int g_tradesThisWeek = 0;

string g_dashName = "ElderTS_Dashboard";

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);

   hTideEma9  = iMA(_Symbol, InpTideTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hTideEma21 = iMA(_Symbol, InpTideTF, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE);
   hTideEma50 = iMA(_Symbol, InpTideTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   hWaveEma21 = iMA(_Symbol, InpWaveTF, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE);
   hWaveEma50 = iMA(_Symbol, InpWaveTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hWaveImpulseEma = iMA(_Symbol, InpWaveTF, InpImpulseEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hWaveMacd  = iMACD(_Symbol, InpWaveTF, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);

   hRippleEma9  = iMA(_Symbol, InpRippleTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hRippleEma21 = iMA(_Symbol, InpRippleTF, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE);
   hRippleForce = iForce(_Symbol, InpRippleTF, InpForcePeriod, MODE_SMA, VOLUME_TICK);
   hRippleATR   = iATR(_Symbol, InpRippleTF, InpATRPeriod);

   if(hTideEma9==INVALID_HANDLE || hTideEma21==INVALID_HANDLE || hTideEma50==INVALID_HANDLE ||
      hWaveEma21==INVALID_HANDLE || hWaveEma50==INVALID_HANDLE || hWaveImpulseEma==INVALID_HANDLE ||
      hWaveMacd==INVALID_HANDLE || hRippleEma9==INVALID_HANDLE || hRippleEma21==INVALID_HANDLE ||
      hRippleForce==INVALID_HANDLE || hRippleATR==INVALID_HANDLE)
     {
      Print("ElderTripleScreen: failed to create one or more indicator handles");
      return(INIT_FAILED);
     }

   ResetMonthlyGuard();
   ResetDailyGuard();
   ResetWeeklyGuard();

   if(InpEnableJournal)
      JournalEnsureHeader();

   if(InpShowChartIndicators)
      SetupChartIndicators();

   if(InpOpenTideWaveCharts)
      SetupTideWaveCharts();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
// Open (or reuse) separate chart windows for Tide and Wave timeframes,
// each with the moving averages/oscillators used on that screen of the
// Triple Screen method. Ripple is the chart the EA is already attached to
// (chart 0), already covered by SetupChartIndicators().
//+------------------------------------------------------------------+
void SetupTideWaveCharts()
  {
   g_chartTide = ChartOpen(_Symbol, InpTideTF);
   g_chartWave = ChartOpen(_Symbol, InpWaveTF);

   if(g_chartTide > 0)
     {
      hTideVisEma9  = iMA(_Symbol, InpTideTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
      hTideVisEma21 = iMA(_Symbol, InpTideTF, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE);
      hTideVisEma50 = iMA(_Symbol, InpTideTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
      if(hTideVisEma9!=INVALID_HANDLE)  ChartIndicatorAdd(g_chartTide, 0, hTideVisEma9);
      if(hTideVisEma21!=INVALID_HANDLE) ChartIndicatorAdd(g_chartTide, 0, hTideVisEma21);
      if(hTideVisEma50!=INVALID_HANDLE) ChartIndicatorAdd(g_chartTide, 0, hTideVisEma50);
      ChartSetString(g_chartTide, CHART_COMMENT, "MARE (Screen 1) - "+EnumToString(InpTideTF)+" - define a direcao permitida (compra/venda)");
      ChartRedraw(g_chartTide);
     }

   if(g_chartWave > 0)
     {
      hWaveVisEma21 = iMA(_Symbol, InpWaveTF, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE);
      hWaveVisEma50 = iMA(_Symbol, InpWaveTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
      hWaveVisImpulseEma = iMA(_Symbol, InpWaveTF, InpImpulseEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      hWaveVisMacd = iMACD(_Symbol, InpWaveTF, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
      if(hWaveVisEma21!=INVALID_HANDLE)      ChartIndicatorAdd(g_chartWave, 0, hWaveVisEma21);
      if(hWaveVisEma50!=INVALID_HANDLE)      ChartIndicatorAdd(g_chartWave, 0, hWaveVisEma50);
      if(hWaveVisImpulseEma!=INVALID_HANDLE) ChartIndicatorAdd(g_chartWave, 0, hWaveVisImpulseEma);
      if(hWaveVisMacd!=INVALID_HANDLE)       ChartIndicatorAdd(g_chartWave, 1, hWaveVisMacd);
      ChartSetString(g_chartWave, CHART_COMMENT, "ONDA (Screen 2) - "+EnumToString(InpWaveTF)+" - zona de desconto + filtro Impulse System");
      ChartRedraw(g_chartWave);
     }
  }

//+------------------------------------------------------------------+
// Plot trend/oscillator/volume indicators on the chart the EA is attached to
// (visual reference only - trading logic always uses the Tide/Wave/Ripple
// handles above, on their own configured timeframes).
//+------------------------------------------------------------------+
void SetupChartIndicators()
  {
   hVisEma9  = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hVisEma21 = iMA(_Symbol, PERIOD_CURRENT, InpEmaMid,  0, MODE_EMA, PRICE_CLOSE);
   hVisEma50 = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hVisMacd    = iMACD(_Symbol, PERIOD_CURRENT, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
   hVisForce   = iForce(_Symbol, PERIOD_CURRENT, InpForcePeriod, MODE_SMA, VOLUME_TICK);
   hVisVolumes = iVolumes(_Symbol, PERIOD_CURRENT, VOLUME_TICK);
   hVisATR     = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);

   if(hVisEma9!=INVALID_HANDLE)  ChartIndicatorAdd(0, 0, hVisEma9);
   if(hVisEma21!=INVALID_HANDLE) ChartIndicatorAdd(0, 0, hVisEma21);
   if(hVisEma50!=INVALID_HANDLE) ChartIndicatorAdd(0, 0, hVisEma50);
   if(hVisMacd!=INVALID_HANDLE)    ChartIndicatorAdd(0, 1, hVisMacd);
   if(hVisForce!=INVALID_HANDLE)   ChartIndicatorAdd(0, 2, hVisForce);
   if(hVisVolumes!=INVALID_HANDLE) ChartIndicatorAdd(0, 3, hVisVolumes);
   if(hVisATR!=INVALID_HANDLE)     ChartIndicatorAdd(0, 4, hVisATR);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_dashName);
   if(g_chartWave > 0) ObjectsDeleteAll(g_chartWave, g_dashName);
   if(g_chartTide > 0) ObjectsDeleteAll(g_chartTide, g_dashName);
  }

//+------------------------------------------------------------------+
// Utility: keys for month/day/week rollover
//+------------------------------------------------------------------+
int MonthKey(datetime t)  { MqlDateTime s; TimeToStruct(t, s); return s.year*12 + s.mon; }
int DayKey(datetime t)    { MqlDateTime s; TimeToStruct(t, s); return s.year*1000 + s.day_of_year; }
int WeekKey(datetime t)
  {
   MqlDateTime s; TimeToStruct(t, s);
   int dow = s.day_of_week==0 ? 7 : s.day_of_week; // ISO-ish: Mon=1..Sun=7
   datetime mondayStart = t - (dow-1)*86400;
   MqlDateTime m; TimeToStruct(mondayStart, m);
   return m.year*1000 + m.day_of_year;
  }

void ResetMonthlyGuard()
  {
   g_monthKey = MonthKey(TimeCurrent());
   g_monthStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_monthlyHalted = false;
  }
void ResetDailyGuard()
  {
   g_dayKey = DayKey(TimeCurrent());
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyHalted = false;
  }
void ResetWeeklyGuard()
  {
   g_weekKey = WeekKey(TimeCurrent());
   g_tradesThisWeek = 0;
  }

void UpdateDrawdownGuards()
  {
   datetime now = TimeCurrent();
   if(MonthKey(now) != g_monthKey)
      ResetMonthlyGuard();
   if(DayKey(now) != g_dayKey)
      ResetDailyGuard();
   if(WeekKey(now) != g_weekKey)
      ResetWeeklyGuard();

   double bal = AccountInfoDouble(ACCOUNT_BALANCE) + AccountInfoDouble(ACCOUNT_CREDIT)*0; // balance only, ignore floating equity swings
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(InpUseMonthlyStop && g_monthStartBalance > 0)
     {
      double ddPct = (g_monthStartBalance - eq) / g_monthStartBalance * 100.0;
      if(ddPct >= InpMonthlyMaxLossPercent && !g_monthlyHalted)
        {
         g_monthlyHalted = true;
         NotifyEvent(StringFormat("6%% mensal atingido (DD %.2f%%) — novas entradas bloqueadas até o próximo mês.", ddPct));
        }
     }
   if(InpUseDailyStop && g_dayStartBalance > 0)
     {
      double ddPct = (g_dayStartBalance - eq) / g_dayStartBalance * 100.0;
      if(ddPct >= InpDailyMaxLossPercent && !g_dailyHalted)
        {
         g_dailyHalted = true;
         NotifyEvent(StringFormat("Stop diário atingido (DD %.2f%%) — novas entradas bloqueadas até amanhã.", ddPct));
        }
     }
  }

bool TradingHalted()
  {
   if(g_monthlyHalted) return(true);
   if(g_dailyHalted) return(true);
   if(InpUseLossCooldown && g_cooldownBarsLeft > 0) return(true);
   if(InpMaxTradesPerWeek > 0 && g_tradesThisWeek >= InpMaxTradesPerWeek) return(true);
   return(false);
  }

//+------------------------------------------------------------------+
void NotifyEvent(string msg)
  {
   Print("ElderTripleScreen: ", msg);
   if(InpEnableAlerts)
      Alert("ElderTripleScreen: ", msg);
  }

//+------------------------------------------------------------------+
// Screen 1 - Tide: returns +1 (allow buy), -1 (allow sell), 0 (no trade allowed)
//+------------------------------------------------------------------+
int TideDirection()
  {
   double e9[2], e21[2], e50[2];
   if(CopyBuffer(hTideEma9, 0, 0, 2, e9)<2 || CopyBuffer(hTideEma21, 0, 0, 2, e21)<2 || CopyBuffer(hTideEma50, 0, 0, 2, e50)<2)
      return(0);

   bool stackedUp   = e9[1] > e21[1] && e21[1] > e50[1] && e9[1] > e9[0];
   bool stackedDown = e9[1] < e21[1] && e21[1] < e50[1] && e9[1] < e9[0];

   if(stackedUp) return(1);
   if(stackedDown) return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
// Screen 2 - Wave: pullback into EMA21/50 zone against the tide direction
//+------------------------------------------------------------------+
bool WavePullbackOk(int tideDir)
  {
   double e21[], e50[], close[], low[], high[];
   int n = InpWaveLookback+1;
   ArrayResize(e21,n); ArrayResize(e50,n); ArrayResize(close,n); ArrayResize(low,n); ArrayResize(high,n);
   if(CopyBuffer(hWaveEma21,0,0,n,e21)<n || CopyBuffer(hWaveEma50,0,0,n,e50)<n) return(false);
   if(CopyClose(_Symbol, InpWaveTF, 0, n, close)<n) return(false);
   if(CopyLow(_Symbol, InpWaveTF, 0, n, low)<n) return(false);
   if(CopyHigh(_Symbol, InpWaveTF, 0, n, high)<n) return(false);

   bool touched = false;
   for(int i=0;i<n;i++)
     {
      if(tideDir>0)
        {
         // buy setup: wave should have dipped down into the EMA21/50 zone (discount), not broken far below EMA50
         if(low[i] <= e21[i] && low[i] >= e50[i]*0.985)
            touched = true;
        }
      else if(tideDir<0)
        {
         if(high[i] >= e21[i] && high[i] <= e50[i]*1.015)
            touched = true;
        }
     }
   return(touched);
  }

//+------------------------------------------------------------------+
// Screen 2b - Elder Impulse System: +1 green, -1 red, 0 blue/neutral
//+------------------------------------------------------------------+
int ImpulseState()
  {
   double ema[2], macdHist[2], macdMain[2], macdSignal[2];
   if(CopyBuffer(hWaveImpulseEma,0,0,2,ema)<2) return(0);
   if(CopyBuffer(hWaveMacd,MAIN_LINE,0,2,macdMain)<2) return(0);
   if(CopyBuffer(hWaveMacd,SIGNAL_LINE,0,2,macdSignal)<2) return(0);

   double hist0 = macdMain[0]-macdSignal[0];
   double hist1 = macdMain[1]-macdSignal[1];

   bool emaUp   = ema[1] > ema[0];
   bool emaDown = ema[1] < ema[0];
   bool histUp   = hist1 > hist0;
   bool histDown = hist1 < hist0;

   if(emaUp && histUp) return(1);
   if(emaDown && histDown) return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
// Screen 3 - Ripple trigger: +1 buy trigger, -1 sell trigger, 0 none
//+------------------------------------------------------------------+
int RippleTrigger(int tideDir)
  {
   if(InpTrigger==TRIGGER_EMA_CROSS)
     {
      double e9[2], e21[2];
      if(CopyBuffer(hRippleEma9,0,0,2,e9)<2 || CopyBuffer(hRippleEma21,0,0,2,e21)<2) return(0);
      bool crossUp   = e9[0] <= e21[0] && e9[1] > e21[1];
      bool crossDown = e9[0] >= e21[0] && e9[1] < e21[1];
      if(tideDir>0 && crossUp) return(1);
      if(tideDir<0 && crossDown) return(-1);
      return(0);
     }
   if(InpTrigger==TRIGGER_FORCE_INDEX)
     {
      double f[2];
      if(CopyBuffer(hRippleForce,0,0,2,f)<2) return(0);
      bool crossUp   = f[0] <= 0 && f[1] > 0;
      bool crossDown = f[0] >= 0 && f[1] < 0;
      if(tideDir>0 && crossUp) return(1);
      if(tideDir<0 && crossDown) return(-1);
      return(0);
     }
   // TRIGGER_PIVOT: simple 3-bar swing pivot breakout
   double high[4], low[4], close[4];
   if(CopyHigh(_Symbol, InpRippleTF, 0, 4, high)<4) return(0);
   if(CopyLow(_Symbol, InpRippleTF, 0, 4, low)<4) return(0);
   if(CopyClose(_Symbol, InpRippleTF, 0, 4, close)<4) return(0);

   bool pivotLow  = low[2] < low[1] && low[2] < low[3] && close[0] > high[2];
   bool pivotHigh = high[2] > high[1] && high[2] > high[3] && close[0] < low[2];

   if(tideDir>0 && pivotLow) return(1);
   if(tideDir<0 && pivotHigh) return(-1);
   return(0);
  }

//+------------------------------------------------------------------+
bool VolatilityOk()
  {
   if(!InpUseMinATRFilter) return(true);
   double atr[1];
   if(CopyBuffer(hRippleATR,0,0,1,atr)<1) return(true);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price<=0) return(true);
   double atrPct = atr[0]/price*100.0;
   return(atrPct >= InpMinATRPercent);
  }

bool SpreadOk()
  {
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return(spread <= InpMaxSpreadPts);
  }

//+------------------------------------------------------------------+
// Sizing & stop calculation
//+------------------------------------------------------------------+
double CalcStopDistance(bool isBuy, double &swingLevel)
  {
   double low[], high[];
   int n = InpSwingLookback;
   ArrayResize(low,n); ArrayResize(high,n);
   if(CopyLow(_Symbol, InpRippleTF, 1, n, low)<n) return(-1);
   if(CopyHigh(_Symbol, InpRippleTF, 1, n, high)<n) return(-1);

   double buffer;
   if(InpUseATRStop)
     {
      double atr[1];
      if(CopyBuffer(hRippleATR,0,0,1,atr)<1) return(-1);
      buffer = atr[0]*InpATRBufferMult;
     }
   else
      buffer = InpStopBufferPts * _Point;

   if(isBuy)
     {
      double lowest = low[ArrayMinimum(low)];
      swingLevel = lowest - buffer;
     }
   else
     {
      double highest = high[ArrayMaximum(high)];
      swingLevel = highest + buffer;
     }
   return(0);
  }

double CalcLotFromRisk(double riskPct, double entry, double stopLevel)
  {
   double slPoints = MathAbs(entry-stopLevel) / _Point;
   if(slPoints<=0) return(0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0 || tickSize<=0) return(0);

   double valuePerPoint = tickValue * (_Point/tickSize);
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct/100.0;
   double lot = riskMoney / (slPoints*valuePerPoint);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot/step)*step;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return(lot);
  }

//+------------------------------------------------------------------+
bool HasOpenPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==(long)InpMagic)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void TryEnter()
  {
   if(InpOnePositionOnly && HasOpenPosition()) return;
   if(TradingHalted()) return;
   if(!SpreadOk()) return;
   if(!VolatilityOk()) return;

   int tideDir = TideDirection();
   if(tideDir==0) return;

   if(!WavePullbackOk(tideDir)) return;

   if(InpUseImpulseFilter)
     {
      int impulse = ImpulseState();
      if(tideDir>0 && impulse<0) return; // red impulse blocks buys
      if(tideDir<0 && impulse>0) return; // green impulse blocks sells
     }

   int trigger = RippleTrigger(tideDir);
   if(trigger==0) return;
   if((tideDir>0 && trigger<0) || (tideDir<0 && trigger>0)) return; // trigger must agree with tide

   bool isBuy = tideDir>0;
   double entry = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double stopLevel;
   if(CalcStopDistance(isBuy, stopLevel) < 0) return;

   double riskPct = MathMin(InpRiskPercent, InpMaxRiskPercent);
   double lot = CalcLotFromRisk(riskPct, entry, stopLevel);
   if(lot<=0) return;

   double riskDist = MathAbs(entry-stopLevel);
   double target = isBuy ? entry + riskDist*InpRiskReward : entry - riskDist*InpRiskReward;

   bool ok;
   if(isBuy)
      ok = trade.Buy(lot, _Symbol, entry, stopLevel, target, InpTradeComment);
   else
      ok = trade.Sell(lot, _Symbol, entry, stopLevel, target, InpTradeComment);

   if(ok)
     {
      ulong ticket = trade.ResultOrder();
      RegisterPosition(ticket, riskDist);
      g_tradesThisWeek++;
      NotifyEvent(StringFormat("%s %s lot=%.2f entry=%.5f SL=%.5f TP=%.5f (risco %.2f%%)",
                  isBuy?"COMPRA":"VENDA", _Symbol, lot, entry, stopLevel, target, riskPct));
      JournalWrite("OPEN", ticket, isBuy?"BUY":"SELL", lot, entry, stopLevel, target, 0);

      if(InpShowTradeMarkers)
        {
         string tooltip = StringFormat(
            "%s #%I64u\nEntrada: %.5f | SL: %.5f | TP: %.5f\nLote: %.2f | Risco: %.2f%%\nMare=%s Onda=OK Impulso=%s Gatilho=%s",
            isBuy?"COMPRA":"VENDA", ticket, entry, stopLevel, target, lot, riskPct,
            isBuy?"alta":"baixa", ImpulseState()>0?"verde":(ImpulseState()<0?"vermelho":"azul"),
            EnumToString(InpTrigger));
         DrawTradeMarkerAllScreens("entry_"+IntegerToString((long)ticket), TimeCurrent(), entry, isBuy, true, tooltip);
        }
     }
  }

//+------------------------------------------------------------------+
void RegisterPosition(ulong ticket, double riskDist)
  {
   int n = ArraySize(g_posTicket);
   ArrayResize(g_posTicket, n+1);
   ArrayResize(g_posRisk, n+1);
   ArrayResize(g_posPartialDone, n+1);
   g_posTicket[n] = ticket;
   g_posRisk[n] = riskDist;
   g_posPartialDone[n] = false;
  }

int FindPosSlot(ulong ticket)
  {
   for(int i=0;i<ArraySize(g_posTicket);i++)
      if(g_posTicket[i]==ticket) return(i);
   return(-1);
  }

void RemovePosSlot(int idx)
  {
   int last = ArraySize(g_posTicket)-1;
   if(idx<0 || idx>last) return;
   g_posTicket[idx] = g_posTicket[last];
   g_posRisk[idx] = g_posRisk[last];
   g_posPartialDone[idx] = g_posPartialDone[last];
   ArrayResize(g_posTicket, last);
   ArrayResize(g_posRisk, last);
   ArrayResize(g_posPartialDone, last);
  }

//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=(long)InpMagic) continue;

      int slot = FindPosSlot(ticket);
      if(slot<0) { RegisterPosition(ticket, 0); slot = FindPosSlot(ticket); }
      double riskDist = g_posRisk[slot];
      if(riskDist<=0) continue;

      bool isBuy = PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double price = isBuy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double profitDist = isBuy ? (price-entry) : (entry-price);
      double rMultiple = profitDist/riskDist;

      // partial close at InpPartialTakeR
      if(InpUsePartialClose && !g_posPartialDone[slot] && rMultiple >= InpPartialTakeR)
        {
         double vol = PositionGetDouble(POSITION_VOLUME);
         double closeVol = NormalizeVolume(vol*InpPartialClosePercent/100.0);
         if(closeVol>0 && closeVol<vol)
           {
            if(trade.PositionClosePartial(ticket, closeVol))
              {
               g_posPartialDone[slot] = true;
               JournalWrite("PARTIAL", ticket, isBuy?"BUY":"SELL", closeVol, price, sl, 0, 0);
               if(InpMoveToBreakeven)
                 {
                  double be = entry; // pure breakeven; spread/commission absorbed by remaining R cushion
                  double tp = PositionGetDouble(POSITION_TP);
                  trade.PositionModify(ticket, be, tp);
                 }
              }
           }
        }

      // trailing stop on remainder
      if(InpUseTrailing && rMultiple >= InpTrailStartR)
        {
         double trailDist = riskDist*InpTrailStepR;
         double newSl = isBuy ? price-trailDist : price+trailDist;
         bool improve = isBuy ? (newSl>sl) : (newSl<sl || sl==0);
         if(improve)
            trade.PositionModify(ticket, newSl, PositionGetDouble(POSITION_TP));
        }
     }
  }

double NormalizeVolume(double vol)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   vol = MathFloor(vol/step)*step;
   if(vol<minLot) return(0);
   return(vol);
  }

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY) return;

   double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   ulong posId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   JournalWrite("CLOSE", posId, "", HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
                HistoryDealGetDouble(trans.deal, DEAL_PRICE), 0, 0, dealProfit);

   if(InpShowTradeMarkers)
     {
      bool wasBuy = HistoryDealGetInteger(trans.deal, DEAL_TYPE)==DEAL_TYPE_SELL; // closing deal opposite to position direction
      double exitPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      string tooltip = StringFormat("Saida posicao #%I64u\nPreco: %.5f | Resultado: %.2f", posId, exitPrice, dealProfit);
      DrawTradeMarkerAllScreens("exit_"+IntegerToString((long)posId)+"_"+IntegerToString((long)trans.deal), TimeCurrent(), exitPrice, wasBuy, false, tooltip);
     }

   if(dealProfit < 0)
     {
      g_consecutiveLosses++;
      if(InpUseLossCooldown && g_consecutiveLosses >= InpMaxConsecutiveLosses)
        {
         g_cooldownBarsLeft = InpCooldownBarsAfterLosses;
         NotifyEvent(StringFormat("%d perdas seguidas — cooldown de %d barras (Ripple) ativado.",
                     g_consecutiveLosses, InpCooldownBarsAfterLosses));
         g_consecutiveLosses = 0;
        }
     }
   else if(dealProfit > 0)
      g_consecutiveLosses = 0;

   // position fully closed -> drop tracking slot
   for(int i=0;i<ArraySize(g_posTicket);i++)
     {
      if(!PositionSelectByTicket(g_posTicket[i]))
        {
         RemovePosSlot(i);
         break;
        }
     }
  }

//+------------------------------------------------------------------+
bool IsNewRippleBar()
  {
   datetime t[1];
   if(CopyTime(_Symbol, InpRippleTF, 0, 1, t) < 1) return(false);
   if(t[0] != g_lastRippleBarTime)
     {
      g_lastRippleBarTime = t[0];
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDrawdownGuards();
   ManageOpenPositions();

   bool newBar = IsNewRippleBar();
   if(newBar && g_cooldownBarsLeft>0)
      g_cooldownBarsLeft--;

   if(newBar)
      TryEnter();

   if(InpShowDashboard)
      DrawDashboard();
  }

//+------------------------------------------------------------------+
// Trade journal (CSV)
//+------------------------------------------------------------------+
void JournalEnsureHeader()
  {
   if(FileIsExist(InpJournalFile)) return;
   int h = FileOpen(InpJournalFile, FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(h==INVALID_HANDLE) return;
   FileWrite(h, "time","event","ticket","side","volume","price","sl","tp","profit");
   FileClose(h);
  }

void JournalWrite(string event, ulong ticket, string side, double volume, double price, double sl, double tp, double profit)
  {
   if(!InpEnableJournal) return;
   int h = FileOpen(InpJournalFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), event, (long)ticket, side, volume, price, sl, tp, profit);
   FileClose(h);
  }

//+------------------------------------------------------------------+
// On-chart dashboard
//+------------------------------------------------------------------+
void DrawTradeMarker(long chartId, string name, datetime t, double price, bool isBuy, bool isEntry, string tooltip)
  {
   string obj = g_dashName+"_mk_"+name;
   ENUM_OBJECT type = isEntry ? (isBuy?OBJ_ARROW_BUY:OBJ_ARROW_SELL) : OBJ_ARROW_CHECK;
   if(ObjectFind(chartId, obj) < 0)
      ObjectCreate(chartId, obj, type, 0, t, price);
   ObjectSetInteger(chartId, obj, OBJPROP_COLOR, isEntry ? (isBuy?clrLime:clrRed) : clrYellow);
   ObjectSetInteger(chartId, obj, OBJPROP_WIDTH, 2);
   ObjectSetString(chartId, obj, OBJPROP_TOOLTIP, tooltip);
   ObjectSetInteger(chartId, obj, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ChartRedraw(chartId);
  }

// draws the same entry/exit marker on the Ripple (current), Wave and Tide chart
// windows at once, so all three screens show the exact same point in time/price.
void DrawTradeMarkerAllScreens(string name, datetime t, double price, bool isBuy, bool isEntry, string tooltip)
  {
   DrawTradeMarker(0, name, t, price, isBuy, isEntry, tooltip);
   if(g_chartWave > 0)
      DrawTradeMarker(g_chartWave, name, t, price, isBuy, isEntry, tooltip);
   if(g_chartTide > 0)
      DrawTradeMarker(g_chartTide, name, t, price, isBuy, isEntry, tooltip);
  }

void DashLabel(string name, int y, string text, color clr)
  {
   string obj = g_dashName+"_"+name;
   if(ObjectFind(0, obj) < 0)
     {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, obj, OBJPROP_CORNER, InpDashboardCorner);
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, InpDashboardX);
      ObjectSetString(0, obj, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, InpDashboardFontSize);
     }
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, InpDashboardY + y*(InpDashboardFontSize+6));
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
  }

void DrawDashboard()
  {
   int tideDir = TideDirection();
   string tideTxt = tideDir>0 ? "ALTA" : (tideDir<0 ? "BAIXA" : "SEM ALINHAMENTO");
   color tideClr  = tideDir>0 ? clrLime : (tideDir<0 ? clrRed : clrGray);

   bool waveOk = tideDir!=0 && WavePullbackOk(tideDir);
   int impulse = ImpulseState();
   string impTxt = impulse>0 ? "VERDE" : (impulse<0 ? "VERMELHO" : "AZUL");
   color impClr  = impulse>0 ? clrLime : (impulse<0 ? clrRed : clrDodgerBlue);

   int trig = tideDir!=0 ? RippleTrigger(tideDir) : 0;
   string trigTxt = trig!=0 ? "GATILHO ATIVO" : "aguardando";

   DashLabel("title", 0, "=== ELDER TRIPLE SCREEN ===", clrWhite);
   DashLabel("tide",  1, "Mare ("+EnumToString(InpTideTF)+"): "+tideTxt, tideClr);
   DashLabel("wave",  2, "Onda ("+EnumToString(InpWaveTF)+"): "+(waveOk?"desconto OK":"fora da zona"), waveOk?clrLime:clrGray);
   DashLabel("imp",   3, "Impulso: "+impTxt, impClr);
   DashLabel("trig",  4, "Marola ("+EnumToString(InpRippleTF)+"): "+trigTxt, trig!=0?clrLime:clrGray);
   DashLabel("halt",  5, "Status: "+(TradingHalted()?"BLOQUEADO":"liberado"), TradingHalted()?clrOrange:clrLime);
   DashLabel("week",  6, StringFormat("Trades na semana: %d%s", g_tradesThisWeek, InpMaxTradesPerWeek>0?"/"+IntegerToString(InpMaxTradesPerWeek):""), clrSilver);
  }
//+------------------------------------------------------------------+
