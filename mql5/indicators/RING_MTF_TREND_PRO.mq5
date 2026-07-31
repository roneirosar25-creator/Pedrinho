//+------------------------------------------------------------------+
//|                                      RING_MTF_TREND_PRO.mq5      |
//|                                         Versão Inteligente        |
//|                    Entradas/Saídas Antecipadas com IA Técnica     |
//+------------------------------------------------------------------+
#property copyright "RoneiRosar23"
#property version   "2.00"
#property description "Sistema Antecipatório Multi-Timeframe com Divergências, Momentum e Confluência"
#property description "Combina WPR, RSI, MACD, ATR e Velocidade do Momento para sinais LEADING."

//--- indicator settings
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   4

//--- Plot 1: Flecha Buy Antecipada (verde claro - sinal early)
#property indicator_type1   DRAW_ARROW
#property indicator_width1  2
#property indicator_color1  0x00FF88
#property indicator_label1  "Buy Early"

//--- Plot 2: Flecha Sell Antecipada (vermelho coral - sinal early)
#property indicator_type2   DRAW_ARROW
#property indicator_width2  2
#property indicator_color2  0xFF4444
#property indicator_label2  "Sell Early"

//--- Plot 3: Flecha Buy Confirmation (azul royal - confirmação)
#property indicator_type3   DRAW_ARROW
#property indicator_width3  1
#property indicator_color3  0x4488FF
#property indicator_label3  "Buy Confirm"

//--- Plot 4: Flecha Sell Confirmation (laranja - confirmação)
#property indicator_type4   DRAW_ARROW
#property indicator_width4  1
#property indicator_color4  0xFF8800
#property indicator_label4  "Sell Confirm"

#define PLOT_MAXIMUM_BARS_BACK 5000
#define OMIT_OLDEST_BARS 50

//--- Buffers
double BuyEarly[];
double SellEarly[];
double BuyConfirm[];
double SellConfirm[];

double myPoint;

//--- Handles globais
int    wpr_handle;
int    rsi_handle;
int    macd_handle;
int    atr_handle;
int    ad_handle;

//--- Buffers de dados
double WPRbuff[];
double RSIbuff[];
double MACDmain[];
double MACDsignal[];
double MACDhist[];
double ATRbuff[];
double ADbuff[];
double LowBuff[];
double HighBuff[];

//--- Input Parameters Base
input int      WPR_Period       = 14;                 // WPR Period
input int      RSI_Period       = 14;                 // RSI Period (divergências)
input int      MACD_Fast        = 12;                 // MACD Fast EMA
input int      MACD_Slow        = 26;                 // MACD Slow EMA
input int      MACD_Signal      = 9;                  // MACD Signal

//--- Limiares WPR
input int      Overbought       = -20;                // WPR Overbought (sell zone)
input int      Oversold         = -80;                // WPR Oversold (buy zone)
input int      NeutralHigh      = -30;                // Zona neutra superior
input int      NeutralLow       = -70;                // Zona neutra inferior

//--- TP/SL
input double   TP_Multiplier    = 1000;               // TP Multiplier (points)
input double   SL_Multiplier    = 100;                // SL Multiplier (points)
input double   ATR_TP_Ratio     = 2.0;                // TP como múltiplo do ATR
input double   ATR_SL_Ratio     = 1.0;                // SL como múltiplo do ATR

//--- Dashboard
input int      RambooShift      = 14;                 // Período de monitorização
input int      DashX            = 500;                // Dashboard X position
input int      DashY            = 200;                // Dashboard Y position
input int      MainBoxX         = 380;                // Box X Offset
input int      MainBoxY         = 113;                // Box Y Offset

//--- Sistema de Pontuação (Signal Score)
input int      MinScoreForEarly  = 60;                // Score mínimo para sinal EARLY (0-100)
input int      MinScoreForEntry  = 80;                // Score mínimo para sinal de ENTRADA

//+------------------------------------------------------------------+
//| Globais auxiliares                                                |
//+------------------------------------------------------------------+
string prefix = "RINGPRO_";
ENUM_TIMEFRAMES periods[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1, PERIOD_W1};
string period_names[] = {"M1","M5","M15","M30","H1","H4","D1","W1"};

string labelBuy  = "RING_TotalBuy";
string labelSell = "RING_TotalSell";
string obj_name  = "RING_InfoBox";

//--- Último sinal para evitar repetição
datetime lastSignalTime = 0;
int      lastSignalDirection = 0; // 1=buy, -1=sell, 0=none

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Configurar buffers
   SetIndexBuffer(0, BuyEarly,    INDICATOR_DATA);
   SetIndexBuffer(1, SellEarly,   INDICATOR_DATA);
   SetIndexBuffer(2, BuyConfirm,  INDICATOR_DATA);
   SetIndexBuffer(3, SellConfirm, INDICATOR_DATA);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   int drawBegin = MathMax(Bars(_Symbol, PERIOD_CURRENT)-PLOT_MAXIMUM_BARS_BACK+1, OMIT_OLDEST_BARS+1);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, drawBegin);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, drawBegin);
   PlotIndexSetInteger(2, PLOT_DRAW_BEGIN, drawBegin);
   PlotIndexSetInteger(3, PLOT_DRAW_BEGIN, drawBegin);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // ▲ verde
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // ▼ vermelho
   PlotIndexSetInteger(2, PLOT_ARROW, 159); // ● azul
   PlotIndexSetInteger(3, PLOT_ARROW, 159); // ● laranja

   myPoint = Point();
   if(Digits() == 5 || Digits() == 3) myPoint *= 10;

   //--- Criar handles
   wpr_handle   = iWPR(_Symbol, PERIOD_CURRENT, WPR_Period);
   rsi_handle   = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   macd_handle  = iMACD(_Symbol, PERIOD_CURRENT, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   atr_handle   = iATR(_Symbol, PERIOD_CURRENT, RambooShift);
   ad_handle    = iAD(_Symbol, PERIOD_CURRENT, VOLUME_TICK);

   if(wpr_handle==INVALID_HANDLE || rsi_handle==INVALID_HANDLE || macd_handle==INVALID_HANDLE || atr_handle==INVALID_HANDLE || ad_handle==INVALID_HANDLE)
   {
      Print("Falha ao criar handles de indicadores. Erro: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Objetos gráficos
   CreateMainLabel("TrendPredictionLabel", "SISTEMA : INICIALIZANDO...", 500, 15, 15, clrWhite);
   CreateMainLabel("ProfitLossLabel", "P/L : ---", 500, 80, 16, clrWhite);
   CreateMainLabel(labelBuy,  "LOT BUY : 0.00", 500, 50, 13, clrMistyRose);
   CreateMainLabel(labelSell, "LOT SELL : 0.00", 500, 65, 13, clrMistyRose);

   //--- Box info
   ObjectDelete(0, obj_name);
   ObjectCreate(0, obj_name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, MainBoxX);
   ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, MainBoxY);
   ObjectSetInteger(0, obj_name, OBJPROP_XSIZE, 650);
   ObjectSetInteger(0, obj_name, OBJPROP_YSIZE, 27);
   ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, 13);
   ObjectSetInteger(0, obj_name, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, obj_name, OBJPROP_READONLY, true);
   ObjectSetInteger(0, obj_name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, obj_name, OBJPROP_ALIGN, ALIGN_CENTER);

   ChartRedraw();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "RING_");
   ObjectsDeleteAll(0, prefix);
   IndicatorRelease(wpr_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(macd_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(ad_handle);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &real_volume[],
                const int &spread[])
{
   if(rates_total < WPR_Period + MACD_Slow + 10) return 0;

   int limit = (prev_calculated < 1) ? rates_total - 1 : rates_total - prev_calculated;
   if(limit < 1) limit = 1;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   //--- Carregar dados dos indicadores
   if(!LoadIndicatorData(rates_total)) return prev_calculated;

   //--- Inicializar buffers
   if(prev_calculated < 1)
   {
      ArrayInitialize(BuyEarly,    EMPTY_VALUE);
      ArrayInitialize(SellEarly,   EMPTY_VALUE);
      ArrayInitialize(BuyConfirm,  EMPTY_VALUE);
      ArrayInitialize(SellConfirm, EMPTY_VALUE);
   }

   ArraySetAsSeries(BuyEarly,    true);
   ArraySetAsSeries(SellEarly,   true);
   ArraySetAsSeries(BuyConfirm,  true);
   ArraySetAsSeries(SellConfirm, true);

   //--- Loop principal de cálculo
   for(int i = limit-1; i >= 0; i--)
   {
      if(i >= MathMin(PLOT_MAXIMUM_BARS_BACK-1, rates_total-1-OMIT_OLDEST_BARS))
         continue;

      //--- Calcular Score de Confluência (0-100)
      int buyScore  = CalculateBuyScore(i);
      int sellScore = CalculateSellScore(i);

      //--- Lógica de Sinais Antecipados (EARLY)
      // Early Buy: score >= MinScoreForEarly + momentum a acelerar (leading)
      if(buyScore >= MinScoreForEarly && buyScore > sellScore + 10)
      {
         // Verificar se é um sinal novo (não repetir na mesma barra)
         if(BuyEarly[i+1] == EMPTY_VALUE || time[i] != time[i+1])
            BuyEarly[i] = low[i] - (myPoint * 10);
      }
      else
         BuyEarly[i] = EMPTY_VALUE;

      // Early Sell
      if(sellScore >= MinScoreForEarly && sellScore > buyScore + 10)
      {
         if(SellEarly[i+1] == EMPTY_VALUE || time[i] != time[i+1])
            SellEarly[i] = high[i] + (myPoint * 10);
      }
      else
         SellEarly[i] = EMPTY_VALUE;

      //--- Lógica de Confirmação (ENTRY)
      if(buyScore >= MinScoreForEntry)
      {
         if(BuyConfirm[i+1] == EMPTY_VALUE || time[i] != time[i+1])
            BuyConfirm[i] = low[i] - (myPoint * 5);
      }
      else
         BuyConfirm[i] = EMPTY_VALUE;

      if(sellScore >= MinScoreForEntry)
      {
         if(SellConfirm[i+1] == EMPTY_VALUE || time[i] != time[i+1])
            SellConfirm[i] = high[i] + (myPoint * 5);
      }
      else
         SellConfirm[i] = EMPTY_VALUE;
   }

   //--- Atualizar objetos gráficos no tick atual
   UpdateGraphicObjects(close, high, low);

   //--- Dashboard MTF
   DrawMTFDashboard();

   return rates_total;
}

//+------------------------------------------------------------------+
//| Carregar dados de todos os indicadores                            |
//+------------------------------------------------------------------+
bool LoadIndicatorData(int total)
{
   if(BarsCalculated(wpr_handle) <= 0)  return false;
   if(BarsCalculated(rsi_handle) <= 0)  return false;
   if(BarsCalculated(macd_handle) <= 0) return false;
   if(BarsCalculated(atr_handle) <= 0)  return false;
   if(BarsCalculated(ad_handle) <= 0)   return false;

   if(CopyBuffer(wpr_handle,  0, 0, total, WPRbuff)    <= 0) return false;
   if(CopyBuffer(rsi_handle,  0, 0, total, RSIbuff)    <= 0) return false;
   if(CopyBuffer(macd_handle, 0, 0, total, MACDmain)   <= 0) return false;
   if(CopyBuffer(macd_handle, 1, 0, total, MACDsignal) <= 0) return false;
   if(CopyBuffer(macd_handle, 2, 0, total, MACDhist)   <= 0) return false;
   if(CopyBuffer(atr_handle,  0, 0, total, ATRbuff)    <= 0) return false;
   if(CopyBuffer(ad_handle,   0, 0, total, ADbuff)     <= 0) return false;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, total, LowBuff)   <= 0) return false;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, total, HighBuff) <= 0) return false;

   ArraySetAsSeries(WPRbuff,    true);
   ArraySetAsSeries(RSIbuff,    true);
   ArraySetAsSeries(MACDmain,   true);
   ArraySetAsSeries(MACDsignal, true);
   ArraySetAsSeries(MACDhist,   true);
   ArraySetAsSeries(ATRbuff,    true);
   ArraySetAsSeries(ADbuff,     true);
   ArraySetAsSeries(LowBuff,    true);
   ArraySetAsSeries(HighBuff,   true);

   return true;
}

//+------------------------------------------------------------------+
//| Calcular Score de COMPRA (0-100)                                 |
//+------------------------------------------------------------------+
int CalculateBuyScore(int i)
{
   int score = 0;

   //--- 1. WPR Oversold / Zona de Compra (até 25 pontos)
   if(WPRbuff[i] < Oversold)        score += 25;       // Oversold forte
   else if(WPRbuff[i] < NeutralLow) score += 15;       // Oversold moderado
   else if(WPRbuff[i] < -50)        score += 5;        // Abaixo do midline

   //--- 2. Divergência Bullish WPR vs Preço (até 20 pontos)
   if(i+2 < ArraySize(WPRbuff))
   {
      // Preço fazendo low mais baixo, WPR fazendo low mais alto = divergência bullish
      if(LowBuff[i] < LowBuff[i+1] && LowBuff[i+1] < LowBuff[i+2] &&
         WPRbuff[i] > WPRbuff[i+1] && WPRbuff[i+1] > WPRbuff[i+2])
         score += 20;
      // Mini-divergência (2 barras)
      else if(LowBuff[i] < LowBuff[i+1] && WPRbuff[i] > WPRbuff[i+1])
         score += 10;
   }

   //--- 3. MACD Histograma a acelerar para cima (até 20 pontos)
   if(i+2 < ArraySize(MACDhist))
   {
      // Crescimento do histograma: cada barra maior que a anterior = momentum a acelerar
      if(MACDhist[i] > MACDhist[i+1] && MACDhist[i+1] > MACDhist[i+2])
         score += 20;                          // Aceleração forte
      else if(MACDhist[i] > MACDhist[i+1])
         score += 10;                          // Aceleração moderada
      // Cruzamento MACD para cima (hist negativo -> menos negativo ou positivo)
      if(MACDhist[i] > 0 && MACDhist[i+1] <= 0)
         score += 10;                          // Cruzamento da linha zero
   }

   //--- 4. RSI a sair de oversold ou subindo (até 15 pontos)
   if(RSIbuff[i] < 30) score += 15;            // RSI oversold -> potencial bounce
   else if(RSIbuff[i] < 40) score += 8;

   //--- 5. AD (Accumulation/Distribution) a subir (até 10 pontos)
   if(i+1 < ArraySize(ADbuff))
   {
      if(ADbuff[i] > ADbuff[i+1]) score += 10;
   }

   //--- 6. Velocidade do WPR (momentum) - até 10 pontos extra
   if(i+2 < ArraySize(WPRbuff))
   {
      double vel = WPRbuff[i] - WPRbuff[i+1];
      double velPrev = WPRbuff[i+1] - WPRbuff[i+2];
      if(vel > 0 && vel > velPrev) score += 10; // Velocidade a aumentar na direção bullish
      else if(vel > 0) score += 5;
   }

   return MathMin(score, 100);
}

//+------------------------------------------------------------------+
//| Calcular Score de VENDA (0-100)                                  |
//+------------------------------------------------------------------+
int CalculateSellScore(int i)
{
   int score = 0;

   //--- 1. WPR Overbought / Zona de Venda (até 25 pontos)
   if(WPRbuff[i] > Overbought)        score += 25;       // Overbought forte
   else if(WPRbuff[i] > NeutralHigh)  score += 15;       // Overbought moderado
   else if(WPRbuff[i] > -50)          score += 5;        // Acima do midline

   //--- 2. Divergência Bearish WPR vs Preço (até 20 pontos)
   if(i+2 < ArraySize(WPRbuff))
   {
      // Preço fazendo high mais alto, WPR fazendo high mais baixo = divergência bearish
      if(HighBuff[i] > HighBuff[i+1] && HighBuff[i+1] > HighBuff[i+2] &&
         WPRbuff[i] < WPRbuff[i+1] && WPRbuff[i+1] < WPRbuff[i+2])
         score += 20;
      // Mini-divergência
      else if(HighBuff[i] > HighBuff[i+1] && WPRbuff[i] < WPRbuff[i+1])
         score += 10;
   }

   //--- 3. MACD Histograma a acelerar para baixo (até 20 pontos)
   if(i+2 < ArraySize(MACDhist))
   {
      if(MACDhist[i] < MACDhist[i+1] && MACDhist[i+1] < MACDhist[i+2])
         score += 20;
      else if(MACDhist[i] < MACDhist[i+1])
         score += 10;
      if(MACDhist[i] < 0 && MACDhist[i+1] >= 0)
         score += 10;
   }

   //--- 4. RSI a sair de overbought ou descendo (até 15 pontos)
   if(RSIbuff[i] > 70) score += 15;
   else if(RSIbuff[i] > 60) score += 8;

   //--- 5. AD a descer (até 10 pontos)
   if(i+1 < ArraySize(ADbuff))
   {
      if(ADbuff[i] < ADbuff[i+1]) score += 10;
   }

   //--- 6. Velocidade do WPR (momentum) - até 10 pontos extra
   if(i+2 < ArraySize(WPRbuff))
   {
      double vel = WPRbuff[i] - WPRbuff[i+1];   // Negativo = descendo
      double velPrev = WPRbuff[i+1] - WPRbuff[i+2];
      if(vel < 0 && vel < velPrev) score += 10; // Velocidade a aumentar na direção bearish
      else if(vel < 0) score += 5;
   }

   return MathMin(score, 100);
}

//+------------------------------------------------------------------+
//| Atualizar Objetos Gráficos                                       |
//+------------------------------------------------------------------+
void UpdateGraphicObjects(const double &close[], const double &high[], const double &low[])
{
   //--- Dados atuais
   double wpr_val = WPRbuff[0];
   double rsi_val = RSIbuff[0];
   double atr_val = ATRbuff[0];

   int    last    = 0;

   //--- Score atual
   int buyScore  = CalculateBuyScore(0);
   int sellScore = CalculateSellScore(0);

   //--- Predição de Trend
   string trendText;
   color  trendColor;
   string signalType;
   string tpText  = "";
   string slText  = "";

   if(buyScore >= MinScoreForEntry)
   {
      trendText = StringFormat("SINAL FORTE COMPRA [Score: %d/100]", buyScore);
      trendColor = clrDeepSkyBlue;
      signalType = "BUY";
   }
   else if(sellScore >= MinScoreForEntry)
   {
      trendText = StringFormat("SINAL FORTE VENDA [Score: %d/100]", sellScore);
      trendColor = clrMagenta;
      signalType = "SELL";
   }
   else if(buyScore >= MinScoreForEarly)
   {
      trendText = StringFormat("ANTECIPACAO COMPRA [Score: %d/100]", buyScore);
      trendColor = clrAqua;
      signalType = "BUY_EARLY";
   }
   else if(sellScore >= MinScoreForEarly)
   {
      trendText = StringFormat("ANTECIPACAO VENDA [Score: %d/100]", sellScore);
      trendColor = clrOrange;
      signalType = "SELL_EARLY";
   }
   else
   {
      trendText = StringFormat("NEUTRO [Buy: %d Sell: %d]", buyScore, sellScore);
      trendColor = clrYellow;
      signalType = "NEUTRAL";
   }

   //--- Calcular TP/SL inteligente (baseado em ATR)
   if(StringFind(signalType, "BUY") >= 0)
   {
      double atrTP = atr_val * ATR_TP_Ratio;
      double atrSL = atr_val * ATR_SL_Ratio;
      tpText = StringFormat("TP: %.5f (%.1f ATR)", close[0] + atrTP, ATR_TP_Ratio);
      slText = StringFormat("SL: %.5f (%.1f ATR)", close[0] - atrSL, ATR_SL_Ratio);
   }
   else if(StringFind(signalType, "SELL") >= 0)
   {
      double atrTP = atr_val * ATR_TP_Ratio;
      double atrSL = atr_val * ATR_SL_Ratio;
      tpText = StringFormat("TP: %.5f (%.1f ATR)", close[0] - atrTP, ATR_TP_Ratio);
      slText = StringFormat("SL: %.5f (%.1f ATR)", close[0] + atrSL, ATR_SL_Ratio);
   }

   //--- Atualizar Label Principal
   string info = StringFormat("WPR: %.2f | RSI: %.2f | ATR: %.5f | %s | %s | %s",
                              wpr_val, rsi_val, atr_val, trendText, tpText, slText);
   color infoColor = trendColor;
   ObjectSetString(0, obj_name, OBJPROP_TEXT, info);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, infoColor);

   //--- Trend Prediction Label
   ObjectSetString(0, "TrendPredictionLabel", OBJPROP_TEXT, "TREND: " + trendText);
   ObjectSetInteger(0, "TrendPredictionLabel", OBJPROP_COLOR, trendColor);

   //--- P/L Label
   double totalProfit = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         totalProfit += PositionGetDouble(POSITION_PROFIT);
   }

   string plText;
   color  plColor;
   if(totalProfit >= 0)
   {
      plText  = StringFormat("LUCRO (%s) : $%.2f", _Symbol, totalProfit);
      plColor = clrDeepSkyBlue;
   }
   else
   {
      plText  = StringFormat("PERDA (%s) : $%.2f", _Symbol, MathAbs(totalProfit));
      plColor = clrGold;
   }
   ObjectSetString(0, "ProfitLossLabel", OBJPROP_TEXT, plText);
   ObjectSetInteger(0, "ProfitLossLabel", OBJPROP_COLOR, plColor);

   //--- Lots BUY/SELL
   double totalBuyLots  = 0;
   double totalSellLots = 0;
   string chartSymbol   = Symbol();

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == chartSymbol)
         {
            double lots = PositionGetDouble(POSITION_VOLUME);
            long type   = PositionGetInteger(POSITION_TYPE);
            if(type == POSITION_TYPE_BUY)  totalBuyLots  += lots;
            if(type == POSITION_TYPE_SELL) totalSellLots += lots;
         }
      }
   }

   ObjectSetString(0, labelBuy,  OBJPROP_TEXT, StringFormat("(%s) LOT BUY  : %.2f", chartSymbol, totalBuyLots));
   ObjectSetString(0, labelSell, OBJPROP_TEXT, StringFormat("(%s) LOT SELL : %.2f", chartSymbol, totalSellLots));

   //--- Price Line nos níveis de TP/SL se houver sinal
   ObjectDelete(0, "RING_TP_Line");
   ObjectDelete(0, "RING_SL_Line");
   if(tpText != "")
   {
      double tpPrice = (StringFind(signalType, "BUY") >= 0) ? close[0] + (atr_val * ATR_TP_Ratio) : close[0] - (atr_val * ATR_TP_Ratio);
      ObjectCreate(0, "RING_TP_Line", OBJ_HLINE, 0, 0, tpPrice);
      ObjectSetInteger(0, "RING_TP_Line", OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, "RING_TP_Line", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, "RING_TP_Line", OBJPROP_STYLE, STYLE_DASH);
   }
   if(slText != "")
   {
      double slPrice = (StringFind(signalType, "SELL") >= 0) ? close[0] + (atr_val * ATR_SL_Ratio) : close[0] - (atr_val * ATR_SL_Ratio);
      ObjectCreate(0, "RING_SL_Line", OBJ_HLINE, 0, 0, slPrice);
      ObjectSetInteger(0, "RING_SL_Line", OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, "RING_SL_Line", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, "RING_SL_Line", OBJPROP_STYLE, STYLE_DASH);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Dashboard Multi-Timeframe com Pontuação Inteligente               |
//+------------------------------------------------------------------+
void DrawMTFDashboard()
{
   int x = DashX;
   int y = DashY;
   int row_height = 20;

   CreateLabel(prefix+"header", " MTF MOMENTUM MATRIX [Buy/Sell Score]", x, y, clrWhite, clrDarkSlateGray, 10, 315);
   y += row_height;

   //--- Cabeçalho com colunas
   CreateLabel(prefix+"col1", " TF ", x, y, clrWhite, clrBlack, 9, 35);
   CreateLabel(prefix+"col2", " WPR ", x+38, y, clrWhite, clrBlack, 9, 50);
   CreateLabel(prefix+"col3", " RSI ", x+90, y, clrWhite, clrBlack, 9, 45);
   CreateLabel(prefix+"col4", " SCORE ", x+138, y, clrWhite, clrBlack, 9, 60);
   CreateLabel(prefix+"col5", " SINAL ", x+200, y, clrWhite, clrBlack, 9, 115);
   y += row_height;

   for(int i = 0; i < ArraySize(periods); i++)
   {
      if(periods[i] == PERIOD_CURRENT) continue; // Já mostrado no painel principal

      int score = GetMTFScore(periods[i]);
      string status = "---";
      color  bg = clrGray;

      if(score >= MinScoreForEntry)     { status = "COMPRA";      bg = clrDodgerBlue; }
      else if(score <= -MinScoreForEntry){ status = "VENDA";       bg = clrRed; }
      else if(score >= MinScoreForEarly){ status = "C.EARLY";     bg = clrSteelBlue; }
      else if(score <= -MinScoreForEarly){ status = "V.EARLY";    bg = clrDarkRed; }

      CreateLabel(prefix+"tf_"+period_names[i],  " "+period_names[i]+" ",        x, y, clrWhite, clrBlack, 9, 35);
      CreateLabel(prefix+"wpr_"+period_names[i],  GetMTFWPR(periods[i]),          x+38, y, clrWhite, clrBlack, 9, 50);
      CreateLabel(prefix+"rsi_"+period_names[i],  GetMTFRSI(periods[i]),          x+90, y, clrWhite, clrBlack, 9, 45);
      CreateLabel(prefix+"scr_"+period_names[i],  IntegerToString(score),         x+138, y, clrWhite, clrBlack, 9, 60);
      CreateLabel(prefix+"sig_"+period_names[i],  " "+status+" ",                 x+200, y, clrWhite, bg, 9, 115);

      y += row_height;
   }
}

//+------------------------------------------------------------------+
//| Obter score MTF (positivo=buy, negativo=sell)                    |
//+------------------------------------------------------------------+
int GetMTFScore(ENUM_TIMEFRAMES tf)
{
   double wpr[], rsi[], ad[], atr[];
   int h_wpr = iWPR(_Symbol, tf, WPR_Period);
   int h_rsi = iRSI(_Symbol, tf, RSI_Period, PRICE_CLOSE);
   int h_ad  = iAD(_Symbol, tf, VOLUME_TICK);
   int h_atr = iATR(_Symbol, tf, RambooShift);

   if(h_wpr==INVALID_HANDLE || h_rsi==INVALID_HANDLE || h_ad==INVALID_HANDLE || h_atr==INVALID_HANDLE)
   {
      IndicatorRelease(h_wpr);
      IndicatorRelease(h_rsi);
      IndicatorRelease(h_ad);
      IndicatorRelease(h_atr);
      return 0;
   }

   if(CopyBuffer(h_wpr, 0, 0, 2, wpr) <= 0) { IndicatorRelease(h_wpr); IndicatorRelease(h_rsi); IndicatorRelease(h_ad); IndicatorRelease(h_atr); return 0; }
   if(CopyBuffer(h_rsi, 0, 0, 1, rsi) <= 0) { IndicatorRelease(h_wpr); IndicatorRelease(h_rsi); IndicatorRelease(h_ad); IndicatorRelease(h_atr); return 0; }
   if(CopyBuffer(h_ad,  0, 0, 2, ad)  <= 0)  { IndicatorRelease(h_wpr); IndicatorRelease(h_rsi); IndicatorRelease(h_ad); IndicatorRelease(h_atr); return 0; }
   if(CopyBuffer(h_atr, 0, 0, 1, atr) <= 0)  { IndicatorRelease(h_wpr); IndicatorRelease(h_rsi); IndicatorRelease(h_ad); IndicatorRelease(h_atr); return 0; }

   ArraySetAsSeries(wpr, true);
   ArraySetAsSeries(ad,  true);

   int score = 0;

   //--- Componentes Buy
   if(wpr[0] < Oversold)       score += 25;
   else if(wpr[0] < -50)       score += 10;
   if(rsi[0] < 30)             score += 15;
   else if(rsi[0] < 45)        score += 5;
   if(ad[0] > ad[1])           score += 10;
   if(wpr[0] > wpr[1] && wpr[0] < -50) score += 10; // WPR a subir do fundo

   //--- Componentes Sell
   if(wpr[0] > Overbought)     score -= 25;
   else if(wpr[0] > -50)       score -= 10;
   if(rsi[0] > 70)             score -= 15;
   else if(rsi[0] > 55)        score -= 5;
   if(ad[0] < ad[1])           score -= 10;
   if(wpr[0] < wpr[1] && wpr[0] > -50) score -= 10; // WPR a descer do topo

   IndicatorRelease(h_wpr);
   IndicatorRelease(h_rsi);
   IndicatorRelease(h_ad);
   IndicatorRelease(h_atr);

   return score;
}

//+------------------------------------------------------------------+
//| Obter string formatada do WPR para um timeframe                  |
//+------------------------------------------------------------------+
string GetMTFWPR(ENUM_TIMEFRAMES tf)
{
   int h = iWPR(_Symbol, tf, WPR_Period);
   double buf[];
   if(CopyBuffer(h, 0, 0, 1, buf) <= 0) { IndicatorRelease(h); return "---"; }
   IndicatorRelease(h);
   return StringFormat("%.1f", buf[0]);
}

//+------------------------------------------------------------------+
//| Obter string formatada do RSI para um timeframe                  |
//+------------------------------------------------------------------+
string GetMTFRSI(ENUM_TIMEFRAMES tf)
{
   int h = iRSI(_Symbol, tf, RSI_Period, PRICE_CLOSE);
   double buf[];
   if(CopyBuffer(h, 0, 0, 1, buf) <= 0) { IndicatorRelease(h); return "---"; }
   IndicatorRelease(h);
   return StringFormat("%.1f", buf[0]);
}

//+------------------------------------------------------------------+
//| Funções Auxiliares de Objetos                                    |
//+------------------------------------------------------------------+
void CreateMainLabel(string name, string text, int x, int y, int fontSize, color clr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

void CreateLabel(string n, string t, int x, int y, color text_clr, color bg_clr, int size, int width)
{
   ObjectDelete(0, n);
   ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, 18);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg_clr);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_COLOR, text_clr);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
