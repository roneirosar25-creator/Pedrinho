//+------------------------------------------------------------------+
//|                                                EA_CORE.mq5        |
//|                    Engine Base Compartilhada (Refatorado v1.2)    |
//|                                        TRIVIUM369 (c) 2026       |
//+------------------------------------------------------------------+
#property copyright EA_COPYRIGHT
#property version   EA_VERSION
#property description "EA_CORE - Engine Base Compartilhada (Refatorado)"
#property description "Parametros via .mqh | Multi-ativo | Fibonacci"
#property description "Stop Dinamico + Trailing + R:R Adaptativo"
#property description "TRIVIUM369 (c) 2026 - Ronei Rosar + Pedrinho"

//+------------------------------------------------------------------+
//| SECAO 1: PARAMETROS VIA INCLUDE                                  |
//+------------------------------------------------------------------+
#ifndef RISK_PERCENTAGE
   #include <TRIVIUM369\COMMON_PARAMS.mqh>
#endif

//--- Fallback padrao para asset params (usado se compilar direto EA_CORE)
#ifndef ASSET_SYMBOL
   #define ASSET_SYMBOL               "EURUSD"
   #define ASSET_DIRECTION    ORDER_TYPE_SELL
   #define SPREAD_PEAK               0.0002
   #define SPREAD_CLOSING            0.0003
   #define SPREAD_ASIA               0.0005
   #define RSI_THRESHOLD                40
   #define RSI_OVERSOLD                 20
   #define RSI_OVERBOUGHT               80
   #define VOLUME_THRESHOLD            1.0
   #define ATR_MULTIPLIER             0.5
   #define SAFETY_MARGIN             0.0003
   #define STOP_MIN_PIPS               10
   #define STOP_MAX_PIPS               80
   #define LOT_MIN                    0.01
   #define LOT_MAX                    10.0
   #define LOT_STEP                   0.01
   #define NEWS_FILTER           true
   #define H1_BREAKDOWN_CONFIRM  true
   #define M15_CONFIRM           true
   #undef INVERT_LOGIC
#endif

//+------------------------------------------------------------------+
//| SECAO 2: HANDLES DOS INDICADORES                                 |
//+------------------------------------------------------------------+
int h_MA20        = INVALID_HANDLE;
int h_MA50        = INVALID_HANDLE;
int h_MA200       = INVALID_HANDLE;
int h_RSI         = INVALID_HANDLE;
int h_MACD        = INVALID_HANDLE;
int h_Bollinger   = INVALID_HANDLE;
int h_ATR         = INVALID_HANDLE;
int h_Ichimoku    = INVALID_HANDLE;
int h_VolumeMA    = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| SECAO 3: ESTRUTURAS                                              |
//+------------------------------------------------------------------+
struct IndicatorValues
{
   double   rsi;
   double   macd_main;
   double   macd_signal;
   double   macd_hist;
   double   bb_middle;
   double   bb_upper;
   double   bb_lower;
   double   ma20;
   double   ma50;
   double   ma200;
   double   atr;
   long     volume;
   double   volume_ma20;
   bool     divergence_bear;
   bool     divergence_bull;
   bool     ichimoku_bear;
   bool     ichimoku_bull;
};

struct OrderSetup
{
   bool     active;
   ulong    ticket;
   ENUM_ORDER_TYPE type;
   double   entry_price;
   double   stop_loss;
   double   tp1, tp2, tp3;
   double   pct1, pct2, pct3;
   double   lot_size;
   datetime open_time;
   bool     trailing_active;
   double   trailing_stop;
};

struct DailyStats
{
   double   starting_balance;
   double   current_balance;
   double   drawdown_pct;
   int      total_trades;
   int      win_trades;
   int      loss_trades;
   datetime day_start;
};

//+------------------------------------------------------------------+
//| VARIAVEIS GLOBAIS                                                |
//+------------------------------------------------------------------+
OrderSetup g_order;
DailyStats g_stats;
datetime   g_last_bar_time  = 0;
double     g_support_h1     = 0.0;
double     g_support_m15    = 0.0;
double     g_resistance_h1  = 0.0;
double     g_resistance_m15 = 0.0;
bool       g_news_hour      = false;

//+------------------------------------------------------------------+
//| PROTOTIPOS                                                       |
//+------------------------------------------------------------------+
bool   UpdateIndicators(IndicatorValues &ind);
bool   CheckConditions(ENUM_ORDER_TYPE &orderType, IndicatorValues &ind);
double CalculateStop(ENUM_ORDER_TYPE orderType, IndicatorValues &ind);
void   CalculateTargets(double entryPrice, double &t1, double &t2, double &t3, IndicatorValues &ind);
void   CalculateClosePercentages(double entry, double stop, double t1, double t2, double t3, double &pct1, double &pct2, double &pct3);
double MoneyManagement(double stopPips);
void   OpenOrder(ENUM_ORDER_TYPE orderType, IndicatorValues &ind);
void   ManageOrder();
void   ManageTrailing();
bool   CheckDailyDrawdown();
bool   IsNewsHour();
void   UpdateSupportResistance();
void   CheckOpenPositions();
double GetSpreadByHour();
bool   CheckDivergence();
bool   CheckIchimoku();
double GetBid();
double GetAsk();

//+------------------------------------------------------------------+
//| SECAO 4: OnInit()                                                |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validacao do timeframe
   #ifdef EA_TIMEFRAME
      if(Period() != EA_TIMEFRAME)
      {
         Alert("EA_CORE requer timeframe ", EnumToString(EA_TIMEFRAME),
               ". Atual: ", EnumToString(Period()));
         return(INIT_PARAMETERS_INCORRECT);
      }
   #else
      if(Period() != PERIOD_H1)
      {
         Alert("EA_CORE requer timeframe H1. Atual: ", EnumToString(Period()));
         return(INIT_PARAMETERS_INCORRECT);
      }
   #endif

   //--- Carregar handles dos indicadores
   h_MA20 = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
   h_MA50 = iMA(Symbol(), PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
   h_MA200 = iMA(Symbol(), PERIOD_H4, 200, 0, MODE_SMA, PRICE_CLOSE);

   h_RSI = iRSI(Symbol(), PERIOD_CURRENT, 14, PRICE_CLOSE);
   h_MACD = iMACD(Symbol(), PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
   h_Bollinger = iBands(Symbol(), PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);

   h_ATR = iATR(Symbol(), PERIOD_D1, ATR_PERIOD);
   h_Ichimoku = iIchimoku(Symbol(), PERIOD_CURRENT, 9, 26, 52);

   h_VolumeMA = iMA(Symbol(), PERIOD_CURRENT, 20, 0, MODE_SMA, VOLUME_TICK);

   //--- Validar handles
   if(h_MA20 == INVALID_HANDLE || h_MA50 == INVALID_HANDLE || h_MA200 == INVALID_HANDLE ||
      h_RSI == INVALID_HANDLE || h_MACD == INVALID_HANDLE || h_Bollinger == INVALID_HANDLE ||
      h_ATR == INVALID_HANDLE || h_Ichimoku == INVALID_HANDLE || h_VolumeMA == INVALID_HANDLE)
   {
      Alert("ERRO CRITICO: Falha ao carregar handles de indicadores.");
      return(INIT_FAILED);
   }

   //--- Inicializar estruturas
   g_order.active = false;
   g_order.ticket = 0;
   g_order.trailing_active = false;

   g_stats.starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_stats.current_balance = g_stats.starting_balance;
   g_stats.drawdown_pct = 0;
   g_stats.total_trades = 0;
   g_stats.win_trades = 0;
   g_stats.loss_trades = 0;
   g_stats.day_start = TimeCurrent();

   //--- Verificar se ha posicoes abertas (recovery)
   CheckOpenPositions();

   //--- Log de inicializacao
   Print("==================================================");
   Print("EA_CORE ", EA_VERSION, " - ", ASSET_SYMBOL, " | ", EA_COPYRIGHT);
   #ifdef INVERT_LOGIC
      Print("LOGICA: INVERTIDA (COMPRA)");
   #else
      Print("LOGICA: DIRETA (VENDA)");
   #endif
   Print("Simbolo: ", Symbol(), " | Timeframe: ", EnumToString(Period()));
   Print("Spread: ", (int)(SymbolInfoInteger(Symbol(), SYMBOL_SPREAD)));
   Print("Capital: ", DoubleToString(g_stats.starting_balance, 2));
   Print("Risco: ", RISK_PERCENTAGE, "% | Max DD: ", MAX_DAILY_DRAWDOWN_PCT, "%");
   Print("RSI Threshold: ", RSI_THRESHOLD, " | Min Sinais: ", MIN_SIGNALS);
   Print("==================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| SECAO 5: OnTick()                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Verificar drawdown diario
   if(!CheckDailyDrawdown())
   {
      if(DEBUG_MODE) Print("DRAWDOWN MAXIMO ATINGIDO. Operacoes pausadas.");
      return;
   }

   //--- Verificar hora de noticia
   g_news_hour = IsNewsHour();
   if(g_news_hour && DEBUG_MODE) Print("Horario de noticia - aguardando.");

   //--- Atualizar valores dos indicadores
   IndicatorValues ind;
   if(!UpdateIndicators(ind))
   {
      if(DEBUG_MODE) Print("Erro ao atualizar indicadores.");
      return;
   }

   //--- Verificar se ha posicao ativa
   if(PositionsTotal() == 0)
   {
      g_order.active = false;
      g_order.trailing_active = false;
   }

   //--- Detectar novo candle
   ENUM_TIMEFRAMES tf = PERIOD_H1;
   #ifdef EA_TIMEFRAME
      tf = EA_TIMEFRAME;
   #endif
   datetime current_bar_time = iTime(Symbol(), tf, 0);
   bool new_bar = (current_bar_time != g_last_bar_time);
   if(new_bar)
   {
      g_last_bar_time = current_bar_time;
      if(DEBUG_MODE)
         Print("Novo candle: ", TimeToString(current_bar_time, TIME_DATE|TIME_MINUTES));
   }

   //--- Atualizar suportes/resistencias dinâmicos
   if(new_bar)
      UpdateSupportResistance();

   //--- Se NAO temos posicao aberta e e novo candle
   if(!g_order.active && new_bar)
   {
      ENUM_ORDER_TYPE orderType;
      if(CheckConditions(orderType, ind))
         OpenOrder(orderType, ind);
   }

   //--- Se temos posicao aberta, gerenciar
   if(g_order.active)
      ManageOrder();

   //--- Log periodico (debug)
   if(new_bar && DEBUG_MODE)
   {
      Print("RSI=", DoubleToString(ind.rsi, 1),
            " | MACD=", DoubleToString(ind.macd_hist, 5),
            " | BB_Mid=", DoubleToString(ind.bb_middle, 5),
            " | ATR=", DoubleToString(ind.atr, 5),
            " | Vol=", (int)ind.volume);
   }
}

//+------------------------------------------------------------------+
//| GetBid() / GetAsk()                                              |
//+------------------------------------------------------------------+
double GetBid() { return(SymbolInfoDouble(Symbol(), SYMBOL_BID)); }
double GetAsk() { return(SymbolInfoDouble(Symbol(), SYMBOL_ASK)); }

//+------------------------------------------------------------------+
//| SECAO 6: CheckConditions() - ENTRADA = 4 CONDICOES               |
//+------------------------------------------------------------------+
bool CheckConditions(ENUM_ORDER_TYPE &orderType, IndicatorValues &ind)
{
   //--- Direcao definida pelo ativo (ou invertida)
   #ifdef INVERT_LOGIC
      #ifdef ASSET_DIRECTION
         if(ASSET_DIRECTION == ORDER_TYPE_SELL)
            orderType = ORDER_TYPE_BUY;       // Inverter SELL -> BUY
         else
            orderType = ORDER_TYPE_SELL;      // Inverter BUY -> SELL
      #else
         orderType = ORDER_TYPE_BUY;
      #endif
   #else
      orderType = ASSET_DIRECTION;
   #endif

   //--- Buffers M15/M1 para confirmacao
   double close_m15[3];
   double high_m15_buf[1], low_m15_buf[1];
   long   volume_m15[3];
   long   vol_buffer[20];
   double vol_ma20_m15 = 0;

   if(CopyClose(Symbol(), PERIOD_M15, 0, 3, close_m15) < 3) return false;
   if(CopyHigh(Symbol(), PERIOD_M15, 0, 1, high_m15_buf) < 1) return false;
   if(CopyLow(Symbol(), PERIOD_M15, 0, 1, low_m15_buf) < 1) return false;
   if(CopyTickVolume(Symbol(), PERIOD_M15, 0, 3, volume_m15) < 3) return false;

   //--- Media de volume M15 (20 periodos)
   if(CopyTickVolume(Symbol(), PERIOD_M15, 1, 20, vol_buffer) < 20) return false;
   for(int i = 0; i < 20; i++) vol_ma20_m15 += (double)vol_buffer[i];
   vol_ma20_m15 /= 20.0;

   double support_m15_val = g_support_m15;
   double resistance_m15_val = g_resistance_m15;

   //--- CONDITION 1: BREAKDOWN H1 (ou BREAKUP se INVERTIDO)
   if(g_support_h1 == 0.0 && g_resistance_h1 == 0.0)
   {
      if(DEBUG_MODE) Print("Aguardando definicao de S/R H1...");
      return false;
   }

   double close_h1[3], high_h1_buf[1], low_h1_buf[1];
   if(CopyClose(Symbol(), PERIOD_H1, 0, 3, close_h1) < 3) return false;
   if(CopyHigh(Symbol(), PERIOD_H1, 0, 1, high_h1_buf) < 1) return false;
   if(CopyLow(Symbol(), PERIOD_H1, 0, 1, low_h1_buf) < 1) return false;

   bool breakdown_h1 = false;
   #ifdef INVERT_LOGIC
      //--- INVERTIDO: BreakUP (preco fecha ACIMA da resistencia)
      breakdown_h1 = (close_h1[1] > g_resistance_h1) && (low_h1_buf[0] < g_resistance_h1 + 5 * Point());
      if(!breakdown_h1)
      {
         if(DEBUG_MODE) Print("Cond1 H1 (INV): SEM BREAKUP. Close=", close_h1[1], " Resist=", g_resistance_h1);
         return false;
      }
   #else
      //--- DIRETO: BreakDOWN (preco fecha ABAIXO do suporte)
      breakdown_h1 = (close_h1[1] < g_support_h1) && (high_h1_buf[0] > g_support_h1 - 5 * Point());
      if(!breakdown_h1)
      {
         if(DEBUG_MODE) Print("Cond1 H1: SEM BREAKDOWN. Close=", close_h1[1], " Suporte=", g_support_h1);
         return false;
      }
   #endif

   //--- CONDITION 2: M15 CONFIRMACAO
   bool breakdown_m15 = false;
   bool volume_ok_m15 = ((double)volume_m15[1] > vol_ma20_m15 * VOLUME_THRESHOLD);

   #ifdef INVERT_LOGIC
      breakdown_m15 = (close_m15[1] > resistance_m15_val);
      if(!breakdown_m15)
      {
         if(DEBUG_MODE) Print("Cond2 M15 (INV): SEM BREAKUP M15. Close=", close_m15[1], " Resist=", resistance_m15_val);
         return false;
      }
   #else
      breakdown_m15 = (close_m15[1] < support_m15_val);
      if(!breakdown_m15)
      {
         if(DEBUG_MODE) Print("Cond2 M15: SEM BREAKDOWN M15. Close=", close_m15[1], " Suporte=", support_m15_val);
         return false;
      }
   #endif

   if(!volume_ok_m15)
   {
      if(DEBUG_MODE) Print("Cond2 M15: Volume fraco. Vol=", volume_m15[1], " Media20=", vol_ma20_m15);
      return false;
   }

   //--- CONDITION 3: INDICADORES (minimo MIN_SIGNALS de 5)
   int signals = 0;

   #ifdef INVERT_LOGIC
      //--- INVERTIDO: RSI alto = compra
      if(ind.rsi > RSI_THRESHOLD && ind.rsi < RSI_OVERBOUGHT) signals++;
      if(ind.macd_main > ind.macd_signal) signals++;
      if(ind.bb_middle > 0 && close_h1[1] > ind.bb_middle) signals++;
   #else
      //--- DIRETO: RSI baixo = venda
      if(ind.rsi < RSI_THRESHOLD && ind.rsi > RSI_OVERSOLD) signals++;
      if(ind.macd_main < ind.macd_signal) signals++;
      if(ind.bb_middle > 0 && close_h1[1] < ind.bb_middle) signals++;
   #endif

   if(CheckDivergence()) signals++;
   if(CheckIchimoku()) signals++;

   if(signals < MIN_SIGNALS)
   {
      if(DEBUG_MODE) Print("Cond3 Indicadores: APENAS ", signals, "/", MIN_SIGNALS, " sinais.");
      return false;
   }

   //--- CONDITION 4: VOLUME + HORARIO
   if(ind.volume < (long)ind.volume_ma20)
   {
      if(DEBUG_MODE)
         Print("Cond4 Volume: BAIXO. Vol=", ind.volume, " Media20=", (long)ind.volume_ma20);
      return false;
   }

   if(g_news_hour && NEWS_FILTER)
   {
      if(DEBUG_MODE) Print("Cond4 Horario: Horario de noticia. Aguardando.");
      return false;
   }

   if(DEBUG_MODE)
   {
      string dirStr = (orderType == ORDER_TYPE_SELL) ? "VENDA" : "COMPRA";
      Print("=== SINAL DE ", dirStr, " CONFIRMADO ===");
      Print("H1 Break: OK | M15 Confirm: OK");
      Print("Indicadores: ", signals, "/5 | Volume: OK | Horario: OK");
   }

   return true;
}

//+------------------------------------------------------------------+
//| SECAO 7: CalculateStop() - Stop Loss Dinamico                    |
//+------------------------------------------------------------------+
double CalculateStop(ENUM_ORDER_TYPE orderType, IndicatorValues &ind)
{
   double stop_price = 0.0;
   double entry = (orderType == ORDER_TYPE_SELL) ? GetBid() : GetAsk();

   if(STOP_TYPE == 1)
   {
      //--- Tipo 1: Extremo historico D1
      #ifdef INVERT_LOGIC
         int lowest_idx = iLowest(Symbol(), PERIOD_D1, MODE_LOW, LOOKBACK_CANDLES, 1);
         if(lowest_idx >= 0)
            stop_price = iLow(Symbol(), PERIOD_D1, lowest_idx);
         else
            stop_price = entry - (50 * Point());
      #else
         int highest_idx = iHighest(Symbol(), PERIOD_D1, MODE_HIGH, LOOKBACK_CANDLES, 1);
         if(highest_idx >= 0)
            stop_price = iHigh(Symbol(), PERIOD_D1, highest_idx);
         else
            stop_price = entry + (50 * Point());
      #endif
   }
   else
   {
      //--- Tipo 2: ATR Mix (recomendado)
      #ifdef INVERT_LOGIC
         int lowest_idx = iLowest(Symbol(), PERIOD_D1, MODE_LOW, LOOKBACK_CANDLES, 1);
         double extreme = (lowest_idx >= 0) ? iLow(Symbol(), PERIOD_D1, lowest_idx) : (entry - 50 * Point());
         double spread = GetSpreadByHour();
         double atr_buffer = ind.atr * ATR_MULTIPLIER;
         double safety = SAFETY_MARGIN;
         stop_price = extreme - spread - atr_buffer - safety;
      #else
         int highest_idx = iHighest(Symbol(), PERIOD_D1, MODE_HIGH, LOOKBACK_CANDLES, 1);
         double extreme = (highest_idx >= 0) ? iHigh(Symbol(), PERIOD_D1, highest_idx) : (entry + 50 * Point());
         double spread = GetSpreadByHour();
         double atr_buffer = ind.atr * ATR_MULTIPLIER;
         double safety = SAFETY_MARGIN;
         stop_price = extreme + spread + atr_buffer + safety;
      #endif
   }

   double min_stop = entry + (STOP_MIN_PIPS * Point());
   double max_stop = entry + (STOP_MAX_PIPS * Point());

   #ifdef INVERT_LOGIC
      min_stop = entry - (STOP_MIN_PIPS * Point());
      max_stop = entry - (STOP_MAX_PIPS * Point());
      if(stop_price > min_stop) stop_price = min_stop;
      if(stop_price < max_stop) stop_price = max_stop;
   #else
      if(stop_price < min_stop) stop_price = min_stop;
      if(stop_price > max_stop) stop_price = max_stop;
   #endif

   stop_price = NormalizeDouble(stop_price, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));

   if(DEBUG_MODE)
      Print("Stop calculado: ", stop_price, " (Spread=", DoubleToString(GetSpreadByHour(), 5),
            " ATR=", DoubleToString(ind.atr, 5), ")");

   return stop_price;
}

//+------------------------------------------------------------------+
//| SECAO 8: CalculateTargets() - Alvos Fibonacci                    |
//+------------------------------------------------------------------+
void CalculateTargets(double entryPrice, double &t1, double &t2, double &t3, IndicatorValues &ind)
{
   int highest_idx = iHighest(Symbol(), PERIOD_D1, MODE_HIGH, LOOKBACK_CANDLES, 1);
   int lowest_idx  = iLowest(Symbol(), PERIOD_D1, MODE_LOW, LOOKBACK_CANDLES, 1);

   double highest = (highest_idx >= 0) ? iHigh(Symbol(), PERIOD_D1, highest_idx) : entryPrice + 0.02;
   double lowest  = (lowest_idx >= 0) ? iLow(Symbol(), PERIOD_D1, lowest_idx) : entryPrice - 0.02;

   double fibDistance = MathMax(highest - lowest, 0.005);

   #ifdef INVERT_LOGIC
      //--- INVERTIDO: Targets ACIMA (compra)
      t1 = entryPrice + (fibDistance * FIB_T1 / 1000.0);
      t2 = entryPrice + (fibDistance * FIB_T2 / 1000.0);
      t3 = entryPrice + (fibDistance * FIB_T3 / 1000.0);

      if(t3 > highest + (5 * Point())) t3 = highest + (5 * Point());
      if(t2 > highest + (3 * Point())) t2 = highest + (3 * Point());
   #else
      //--- DIRETO: Targets ABAIXO (venda)
      t1 = entryPrice - (fibDistance * FIB_T1 / 1000.0);
      t2 = entryPrice - (fibDistance * FIB_T2 / 1000.0);
      t3 = entryPrice - (fibDistance * FIB_T3 / 1000.0);

      if(t3 < lowest - (5 * Point())) t3 = lowest - (5 * Point());
      if(t2 < lowest - (3 * Point())) t2 = lowest - (3 * Point());
   #endif

   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   t1 = NormalizeDouble(t1, digits);
   t2 = NormalizeDouble(t2, digits);
   t3 = NormalizeDouble(t3, digits);

   if(DEBUG_MODE)
   {
      Print("Targets Fibonacci:");
      Print("  FibDist=", DoubleToString(fibDistance, 5), " High=", highest, " Low=", lowest);
      Print("  T1(", FIB_T1/10.0, "%)=", t1, " T2(", FIB_T2/10.0, "%)=", t2, " T3(", FIB_T3/10.0, "%)=", t3);
   }
}

//+------------------------------------------------------------------+
//| SECAO 9: CalculateClosePercentages() - R:R Adaptativo            |
//+------------------------------------------------------------------+
void CalculateClosePercentages(double entry, double stop,
                                double t1, double t2, double t3,
                                double &pct1, double &pct2, double &pct3)
{
   double riskValue = MathAbs(entry - stop);
   if(riskValue <= 0) riskValue = 0.001;

   double rr1 = MathAbs(t1 - entry) / riskValue;
   double rr2 = MathAbs(t2 - entry) / riskValue;
   double rr3 = MathAbs(t3 - entry) / riskValue;

   pct1 = (rr1 < 0.5) ? 0.20 : ((rr1 < 1.0) ? 0.30 : 0.40);
   pct2 = (rr2 < 0.5) ? 0.25 : ((rr2 < 1.0) ? 0.35 : 0.45);
   pct3 = (rr3 < 0.5) ? 0.35 : ((rr3 < 1.0) ? 0.40 : 0.50);

   double total = pct1 + pct2 + pct3;
   if(total > 1.0)
   {
      pct1 /= total;
      pct2 /= total;
      pct3 /= total;
   }

   pct1 = NormalizeDouble(pct1, 2);
   pct2 = NormalizeDouble(pct2, 2);
   pct3 = NormalizeDouble(pct3, 2);

   if(DEBUG_MODE)
      Print("R:R | T1=", DoubleToString(rr1, 2), " (", (int)(pct1*100), "%)",
            " T2=", DoubleToString(rr2, 2), " (", (int)(pct2*100), "%)",
            " T3=", DoubleToString(rr3, 2), " (", (int)(pct3*100), "%)");
}

//+------------------------------------------------------------------+
//| SECAO 10: MoneyManagement() - Calculo de Lote por Risco          |
//+------------------------------------------------------------------+
double MoneyManagement(double stopPips)
{
   if(stopPips <= 0) stopPips = 20;

   double capital = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = capital * (RISK_PERCENTAGE / 100.0);

   double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0) tickValue = 1.0;

   double pipValue = tickValue * 10;

   double lots = riskAmount / (stopPips * pipValue);

   lots = MathMax(lots, LOT_MIN);
   lots = MathMin(lots, LOT_MAX);

   double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   if(lotStep > 0)
      lots = MathRound(lots / lotStep) * lotStep;

   lots = NormalizeDouble(lots, 2);

   if(DEBUG_MODE)
      Print("MoneyMgmt: Capital=", DoubleToString(capital, 2),
            " Risco$=", DoubleToString(riskAmount, 2),
            " StopPips=", (int)stopPips,
            " Lote=", DoubleToString(lots, 2));

   return lots;
}

//+------------------------------------------------------------------+
//| SECAO 11: OpenOrder() - Abrir Ordem Completa                     |
//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE orderType, IndicatorValues &ind)
{
   if(PositionsTotal() >= MAX_POSITIONS)
   {
      if(DEBUG_MODE) Print("Maximo de posicoes atingido (", MAX_POSITIONS, ").");
      return;
   }

   double price = (orderType == ORDER_TYPE_SELL) ? GetBid() : GetAsk();
   double sl, tp1, tp2, tp3;
   double pct1, pct2, pct3;
   double lots;

   sl = CalculateStop(orderType, ind);
   CalculateTargets(price, tp1, tp2, tp3, ind);
   CalculateClosePercentages(price, sl, tp1, tp2, tp3, pct1, pct2, pct3);

   double stopPips = MathAbs(price - sl) / Point();
   lots = MoneyManagement(stopPips);

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = lots;
   request.type = orderType;
   request.price = price;
   request.sl = sl;
   request.tp = tp1;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = ORDER_COMMENT + " v" + EA_VERSION;
   request.type_filling = ORDER_FILLING_FOK;

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         g_order.active = true;
         g_order.ticket = result.order;
         g_order.type = orderType;
         g_order.entry_price = price;
         g_order.stop_loss = sl;
         g_order.tp1 = tp1;
         g_order.tp2 = tp2;
         g_order.tp3 = tp3;
         g_order.pct1 = pct1;
         g_order.pct2 = pct2;
         g_order.pct3 = pct3;
         g_order.lot_size = lots;
         g_order.open_time = TimeCurrent();
         g_order.trailing_active = false;
         g_order.trailing_stop = 0;

         g_stats.total_trades++;

         string dirStr = (orderType == ORDER_TYPE_SELL) ? "VENDA" : "COMPRA";
         Print("==================================================");
         Print("ORDEM ABERTA #", result.order);
         Print("Tipo: ", dirStr, " | Ativo: ", ASSET_SYMBOL);
         Print("Entrada: ", price, " | Stop: ", sl, " | Lote: ", lots);
         Print("T1: ", tp1, " (", (int)(pct1*100), "%) | T2: ", tp2, " (", (int)(pct2*100), "%) | T3: ", tp3, " (", (int)(pct3*100), "%)");
         Print("==================================================");
      }
      else
      {
         Print("Erro ao abrir ordem: ", result.retcode, " | ", result.comment);
      }
   }
   else
   {
      Print("Falha ao enviar ordem. Erro: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| SECAO 12: ManageOrder() - Gerenciar Ordem Aberta                 |
//+------------------------------------------------------------------+
void ManageOrder()
{
   if(!PositionSelectByTicket(g_order.ticket))
   {
      g_order.active = false;
      return;
   }

   double current_price = (g_order.type == ORDER_TYPE_SELL) ? GetBid() : GetAsk();
   double current_sl = PositionGetDouble(POSITION_SL);
   double profit_pips = (g_order.type == ORDER_TYPE_SELL) ?
                        (g_order.entry_price - current_price) / Point() :
                        (current_price - g_order.entry_price) / Point();

   bool hit_t1 = (g_order.type == ORDER_TYPE_SELL) ? (current_price <= g_order.tp1) : (current_price >= g_order.tp1);
   bool hit_t2 = (g_order.type == ORDER_TYPE_SELL) ? (current_price <= g_order.tp2) : (current_price >= g_order.tp2);
   bool hit_t3 = (g_order.type == ORDER_TYPE_SELL) ? (current_price <= g_order.tp3) : (current_price >= g_order.tp3);

   if(hit_t3)
   {
      ClosePosition(g_order.ticket, g_order.lot_size);
      g_order.active = false;
      g_stats.win_trades++;
      if(DEBUG_MODE) Print("T3 ATINGIDO! Posicao fechada. Lucro: ", (int)profit_pips, " pips");
   }
   else if(hit_t2)
   {
      if(DEBUG_MODE) Print("T2 ATINGIDO! Fechando ", (int)(g_order.pct2*100), "%");
      ClosePartial(g_order.ticket, g_order.lot_size * g_order.pct2);

      if(USE_TRAILING && !g_order.trailing_active)
      {
         g_order.trailing_active = true;
         if(DEBUG_MODE) Print("Trailing ativado apos T2.");
      }
   }
   else if(hit_t1)
   {
      if(DEBUG_MODE) Print("T1 ATINGIDO! Fechando ", (int)(g_order.pct1*100), "%");
      ClosePartial(g_order.ticket, g_order.lot_size * g_order.pct1);

      if(current_sl <= 0 || current_sl == g_order.stop_loss)
      {
         double bePrice = (g_order.type == ORDER_TYPE_SELL) ?
                           g_order.entry_price + (BREAK_EVEN_PIPS * Point()) :
                           g_order.entry_price - (BREAK_EVEN_PIPS * Point());
         ModifyStopLoss(g_order.ticket, bePrice);
         if(DEBUG_MODE) Print("Stop movido para break-even +", BREAK_EVEN_PIPS, " pips.");
      }

      if(USE_TRAILING)
         g_order.trailing_active = true;
   }
   else
   {
      if(g_order.trailing_active && USE_TRAILING)
         ManageTrailing();
   }
}

//+------------------------------------------------------------------+
//| SECAO 13: ManageTrailing() - Trailing Stop                       |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   if(!PositionSelectByTicket(g_order.ticket)) return;

   double current_sl = PositionGetDouble(POSITION_SL);
   double current_price = (g_order.type == ORDER_TYPE_SELL) ? GetBid() : GetAsk();

   double trail_distance = TRAILING_PIPS * Point();
   double new_sl = 0;

   if(g_order.type == ORDER_TYPE_SELL)
      new_sl = current_price + trail_distance;
   else
      new_sl = current_price - trail_distance;

   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   new_sl = NormalizeDouble(new_sl, digits);

   bool melhor = (g_order.type == ORDER_TYPE_SELL) ? (new_sl < current_sl) : (new_sl > current_sl);

   if(melhor)
   {
      if(ModifyStopLoss(g_order.ticket, new_sl))
         if(DEBUG_MODE) Print("Trailing atualizado: SL=", new_sl, " (dist=", TRAILING_PIPS, " pips)");
   }
}

//+------------------------------------------------------------------+
//| FUNCOES AUXILIARES                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| UpdateIndicators() - Atualizar todos os indicadores              |
//+------------------------------------------------------------------+
bool UpdateIndicators(IndicatorValues &ind)
{
   double rsi_buf[1];
   if(CopyBuffer(h_RSI, 0, 0, 1, rsi_buf) < 1) return false;
   ind.rsi = rsi_buf[0];

   double macd_main[1], macd_signal[1], macd_hist[1];
   if(CopyBuffer(h_MACD, 0, 0, 1, macd_main) < 1) return false;
   if(CopyBuffer(h_MACD, 1, 0, 1, macd_signal) < 1) return false;
   if(CopyBuffer(h_MACD, 2, 0, 1, macd_hist) < 1) return false;
   ind.macd_main = macd_main[0];
   ind.macd_signal = macd_signal[0];
   ind.macd_hist = macd_hist[0];

   double bb_mid[1], bb_up[1], bb_low[1];
   if(CopyBuffer(h_Bollinger, 0, 0, 1, bb_mid) < 1) return false;
   if(CopyBuffer(h_Bollinger, 1, 0, 1, bb_up) < 1) return false;
   if(CopyBuffer(h_Bollinger, 2, 0, 1, bb_low) < 1) return false;
   ind.bb_middle = bb_mid[0];
   ind.bb_upper = bb_up[0];
   ind.bb_lower = bb_low[0];

   double ma20[1], ma50[1], ma200[1];
   if(CopyBuffer(h_MA20, 0, 0, 1, ma20) < 1) return false;
   if(CopyBuffer(h_MA50, 0, 0, 1, ma50) < 1) return false;
   if(CopyBuffer(h_MA200, 0, 0, 1, ma200) < 1) return false;
   ind.ma20 = ma20[0];
   ind.ma50 = ma50[0];
   ind.ma200 = ma200[0];

   double atr[1];
   if(CopyBuffer(h_ATR, 0, 0, 1, atr) < 1) return false;
   ind.atr = atr[0];

   long vol[1];
   if(CopyTickVolume(Symbol(), PERIOD_CURRENT, 0, 1, vol) < 1) return false;
   ind.volume = vol[0];

   double vol_ma[1];
   if(CopyBuffer(h_VolumeMA, 0, 0, 1, vol_ma) < 1) return false;
   ind.volume_ma20 = vol_ma[0];

   ind.divergence_bear = false;
   ind.divergence_bull = false;
   ind.ichimoku_bear = false;
   ind.ichimoku_bull = false;

   return true;
}

//+------------------------------------------------------------------+
//| CheckDivergence() - Divergencia RSI                              |
//+------------------------------------------------------------------+
bool CheckDivergence()
{
   double close[14];
   double rsi[14];

   if(CopyClose(Symbol(), PERIOD_H1, 0, 14, close) < 14) return false;
   if(CopyBuffer(h_RSI, 0, 0, 14, rsi) < 14) return false;

   #ifdef INVERT_LOGIC
      for(int i = 1; i < 7; i++)
      {
         if(close[i] < close[i+1] && rsi[i] > rsi[i+1])
            return true;
      }
   #else
      for(int i = 1; i < 7; i++)
      {
         if(close[i] > close[i+1] && rsi[i] < rsi[i+1])
            return true;
      }
   #endif

   return false;
}

//+------------------------------------------------------------------+
//| CheckIchimoku() - Preco abaixo/acima da nuvem                   |
//+------------------------------------------------------------------+
bool CheckIchimoku()
{
   double senkouA[1], senkouB[1];
   double close[1];

   if(CopyBuffer(h_Ichimoku, 2, 1, 1, senkouA) < 1) return false;
   if(CopyBuffer(h_Ichimoku, 3, 1, 1, senkouB) < 1) return false;
   if(CopyClose(Symbol(), PERIOD_H1, 1, 1, close) < 1) return false;

   double nuvem_inferior = MathMin(senkouA[0], senkouB[0]);
   double nuvem_superior = MathMax(senkouA[0], senkouB[0]);

   #ifdef INVERT_LOGIC
      if(close[0] > nuvem_superior)
         return true;
   #else
      if(close[0] < nuvem_inferior)
         return true;
   #endif

   return false;
}

//+------------------------------------------------------------------+
//| UpdateSupportResistance() - S/R dinâmicos                        |
//+------------------------------------------------------------------+
void UpdateSupportResistance()
{
   int candles = LOOKBACK_CANDLES;

   double lows_h1[], highs_h1[];
   ArrayResize(lows_h1, candles);
   ArrayResize(highs_h1, candles);

   ENUM_TIMEFRAMES tf = PERIOD_H1;
   #ifdef EA_TIMEFRAME
      tf = EA_TIMEFRAME;
   #endif

   for(int i = 1; i <= candles; i++)
   {
      lows_h1[i-1] = iLow(Symbol(), tf, i);
      highs_h1[i-1] = iHigh(Symbol(), tf, i);
   }

   g_support_h1 = lows_h1[ArrayMinimum(lows_h1)];
   g_resistance_h1 = highs_h1[ArrayMaximum(highs_h1)];

   double lows_m15[], highs_m15[];
   ArrayResize(lows_m15, candles * 4);
   ArrayResize(highs_m15, candles * 4);
   for(int i = 1; i <= candles * 4; i++)
   {
      lows_m15[i-1] = iLow(Symbol(), PERIOD_M15, i);
      highs_m15[i-1] = iHigh(Symbol(), PERIOD_M15, i);
   }

   g_support_m15 = lows_m15[ArrayMinimum(lows_m15)];
   g_resistance_m15 = highs_m15[ArrayMaximum(highs_m15)];

   if(DEBUG_MODE)
      Print("S/R Atualizados: Sup_H1=", g_support_h1,
            " Res_H1=", g_resistance_h1,
            " Sup_M15=", g_support_m15,
            " Res_M15=", g_resistance_m15);
}

//+------------------------------------------------------------------+
//| GetSpreadByHour() - Spread dinamico por horario                  |
//+------------------------------------------------------------------+
double GetSpreadByHour()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;

   if(hour >= 8 && hour <= 17) return SPREAD_PEAK;
   if(hour >= 17 && hour <= 22) return SPREAD_CLOSING;
   return SPREAD_ASIA;
}

//+------------------------------------------------------------------+
//| IsNewsHour() - Horarios de noticias (NFP/CPI/FOMC)              |
//+------------------------------------------------------------------+
bool IsNewsHour()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   int minute = dt.min;

   if(hour == 12 && minute >= 30) return true;
   if(hour == 13 && minute <= 30) return true;
   if(hour == 18 && minute >= 30) return true;
   if(hour == 19 && minute <= 30) return true;

   return false;
}

//+------------------------------------------------------------------+
//| CheckDailyDrawdown() - Monitorar drawdown diario                 |
//+------------------------------------------------------------------+
bool CheckDailyDrawdown()
{
   MqlDateTime current_time;
   TimeCurrent(current_time);

   MqlDateTime day_start_struct;
   TimeToStruct(g_stats.day_start, day_start_struct);

   if(current_time.day != day_start_struct.day)
   {
      g_stats.day_start = TimeCurrent();
      g_stats.starting_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_stats.drawdown_pct = 0;
      if(DEBUG_MODE) Print("Novo dia: reset drawdown. Balance=", g_stats.starting_balance);
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(g_stats.starting_balance > 0)
      g_stats.drawdown_pct = (1.0 - equity / g_stats.starting_balance) * 100.0;

   if(g_stats.drawdown_pct >= MAX_DAILY_DRAWDOWN_PCT)
   {
      if(PositionsTotal() > 0)
         Alert("DRAWDOWN CRITICO: ", DoubleToString(g_stats.drawdown_pct, 1), "%");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| CheckOpenPositions() - Recuperar posicoes abertas                |
//+------------------------------------------------------------------+
void CheckOpenPositions()
{
   int total = PositionsTotal();
   if(total == 0) return;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == Symbol())
         {
            g_order.active = true;
            g_order.ticket = ticket;
            g_order.type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
            g_order.entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
            g_order.stop_loss = PositionGetDouble(POSITION_SL);
            g_order.lot_size = PositionGetDouble(POSITION_VOLUME);
            g_order.open_time = (datetime)PositionGetInteger(POSITION_TIME);

            Print("Posicao recuperada: #", ticket, " | ",
                  (g_order.type == ORDER_TYPE_SELL ? "VENDA" : "COMPRA"),
                  " | Entrada: ", g_order.entry_price,
                  " | Lote: ", g_order.lot_size);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ClosePosition() - Fechar posicao                                 |
//+------------------------------------------------------------------+
bool ClosePosition(ulong ticket, double volume)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("Erro: Posicao #", ticket, " nao encontrada.");
      return false;
   }

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.volume = volume;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = "Close " + ORDER_COMMENT;

   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
   request.type = (type == ORDER_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (type == ORDER_TYPE_BUY) ? GetBid() : GetAsk();

   if(!OrderSend(request, result))
   {
      Print("Erro ao fechar posicao #", ticket, ". Erro: ", GetLastError());
      return false;
   }

   if(result.retcode == TRADE_RETCODE_DONE)
   {
      Print("Posicao #", ticket, " fechada.");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| ClosePartial() - Fechar parte da posicao                         |
//+------------------------------------------------------------------+
bool ClosePartial(ulong ticket, double volume)
{
   if(!PositionSelectByTicket(ticket))
   {
      Print("Erro: Posicao #", ticket, " nao encontrada.");
      return false;
   }

   double current_volume = PositionGetDouble(POSITION_VOLUME);
   if(volume >= current_volume)
      volume = current_volume;

   return ClosePosition(ticket, volume);
}

//+------------------------------------------------------------------+
//| ModifyStopLoss() - Modificar Stop Loss                           |
//+------------------------------------------------------------------+
bool ModifyStopLoss(ulong ticket, double new_sl)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_SLTP;
   request.symbol = PositionGetString(POSITION_SYMBOL);
   request.sl = new_sl;
   request.tp = PositionGetDouble(POSITION_TP);
   request.magic = MAGIC_NUMBER;
   request.comment = "ModSL " + ORDER_COMMENT;

   if(!OrderSend(request, result))
   {
      if(DEBUG_MODE) Print("Erro ao modificar SL: ", GetLastError());
      return false;
   }

   return (result.retcode == TRADE_RETCODE_DONE);
}

//+------------------------------------------------------------------+
//| OnDeinit()                                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_MA20     != INVALID_HANDLE) IndicatorRelease(h_MA20);
   if(h_MA50     != INVALID_HANDLE) IndicatorRelease(h_MA50);
   if(h_MA200    != INVALID_HANDLE) IndicatorRelease(h_MA200);
   if(h_RSI      != INVALID_HANDLE) IndicatorRelease(h_RSI);
   if(h_MACD     != INVALID_HANDLE) IndicatorRelease(h_MACD);
   if(h_Bollinger != INVALID_HANDLE) IndicatorRelease(h_Bollinger);
   if(h_ATR      != INVALID_HANDLE) IndicatorRelease(h_ATR);
   if(h_Ichimoku != INVALID_HANDLE) IndicatorRelease(h_Ichimoku);
   if(h_VolumeMA != INVALID_HANDLE) IndicatorRelease(h_VolumeMA);

   Print("EA_CORE ", EA_VERSION, " deinitialized. Reason: ", reason);
}
//+------------------------------------------------------------------+
