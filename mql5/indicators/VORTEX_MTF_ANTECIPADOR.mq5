//+------------------------------------------------------------------+
//|                                              VORTEX_MTF_ANTECIPADOR.mq5
//|                                                   by Goose AI + Trivium369
//|  Estratégia: WPR + Divergências + ATR + RSI + MTF Alignment
//|  Objetivo: Antecipar entradas/saídas antes do preço confirmar
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

// --- SETAS DE SINAL ---
#property indicator_type1   DRAW_ARROW
#property indicator_width1  2
#property indicator_color1  0x00FFAA   // Verde-água para COMPRA
#property indicator_label1  "BUY_ANTECIPADO"

#property indicator_type2   DRAW_ARROW
#property indicator_width2  2
#property indicator_color2  0xFF5500   // Laranja para VENDA
#property indicator_label2  "SELL_ANTECIPADO"

// Buffers 3 e 4 são INDICATOR_CALCULATIONS (setados via SetIndexBuffer)

#define PLOT_MAXIMUM_BARS_BACK 3000
#define OMIT_OLDEST_BARS 60

//+------------------------------------------------------------------+
//--- INPUT PARAMETERS
//+------------------------------------------------------------------+

//--- WPR Principal
input int      Inp_WPR_Period        = 14;          // WPR Period
input double   Inp_WPR_OB_Level      = -20.0;       // WPR Overbought Level
input double   Inp_WPR_OS_Level      = -80.0;       // WPR Oversold Level
input double   Inp_WPR_Pivot         = -50.0;       // WPR Pivot / Neutro

//--- Confirmação RSI
input int      Inp_RSI_Period        = 7;           // RSI Period (confirmação)
input double   Inp_RSI_OB_Level      = 70.0;        // RSI Overbought
input double   Inp_RSI_OS_Level      = 30.0;        // RSI Oversold

//--- ATR para Volatilidade
input int      Inp_ATR_Period        = 14;          // ATR Period
input double   Inp_ATR_Breakout_Factor = 1.5;       // ATR Breakout Factor

//--- Divergência
input int      Inp_Divergence_Bars   = 20;          // Barras p/ detectar divergência

//--- Filtro MTF (timeframes maiores confirmam tendência)
input bool     Inp_Use_MTF_Filter    = true;        // Usar filtro MTF?
input ENUM_TIMEFRAMES Inp_MTF_Trend  = PERIOD_H1;   // Timeframe para tendência
input ENUM_TIMEFRAMES Inp_MTF_Entry  = PERIOD_M15;  // Timeframe para entrada

//--- Gestão de Risco (TP/SL dinâmico)
input double   Inp_ATR_TP_Multiplier = 2.0;         // TP = ATR * Multiplicador
input double   Inp_ATR_SL_Multiplier = 1.2;         // SL = ATR * Multiplicador

//--- Dashboard
input int      Inp_Dash_X            = 10;          // Dashboard X position
input int      Inp_Dash_Y            = 15;          // Dashboard Y position
input int      Inp_Font_Size         = 11;          // Dashboard Font Size

//+------------------------------------------------------------------+
//--- GLOBAIS
//+------------------------------------------------------------------+
string prefix = "VORTEX_";
string objTrendLabel = "VORTEX_TrendLabel";
string objPLLabel    = "VORTEX_PL_Label";
string objInfoBox    = "VORTEX_InfoBox";
string objDashPrefix = "VORTEX_DASH_";

//--- Handles
int    hWPR          = INVALID_HANDLE;
int    hWPR_Trend    = INVALID_HANDLE;
int    hRSI          = INVALID_HANDLE;
int    hATR          = INVALID_HANDLE;
int    hWPR_Entry    = INVALID_HANDLE;

//--- Buffers do indicador (setas)
double B1_BUY[];
double B2_SELL[];

//--- Buffers internos
double wpr_buf[];
double wpr_trend_buf[];
double rsi_buf[];
double atr_buf[];
double wpr_entry_buf[];

double high_buf[],
       low_buf[],
       close_buf[],
       open_buf[];

datetime last_bar_time = 0;
double   myPoint       = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Configurar buffers de saída
   SetIndexBuffer(0, B1_BUY,  INDICATOR_DATA);
   SetIndexBuffer(1, B2_SELL, INDICATOR_DATA);
   SetIndexBuffer(2, wpr_buf, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, rsi_buf, INDICATOR_CALCULATIONS);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, OMIT_OLDEST_BARS + Inp_WPR_Period);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, OMIT_OLDEST_BARS + Inp_WPR_Period);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // ▲ seta para cima
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // ▼ seta para baixo

   //--- Calcular myPoint para símbolos com 5 dígitos
   myPoint = Point();
   if(Digits() == 5 || Digits() == 3)
      myPoint *= 10;

   //--- Criar handles dos indicadores
   hWPR = iWPR(_Symbol, PERIOD_CURRENT, Inp_WPR_Period);
   if(hWPR == INVALID_HANDLE)
   {
      Print("Erro ao criar WPR handle: ", GetLastError());
      return INIT_FAILED;
   }

   hRSI = iRSI(_Symbol, PERIOD_CURRENT, Inp_RSI_Period, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE)
   {
      Print("Erro ao criar RSI handle: ", GetLastError());
      return INIT_FAILED;
   }

   hATR = iATR(_Symbol, PERIOD_CURRENT, Inp_ATR_Period);
   if(hATR == INVALID_HANDLE)
   {
      Print("Erro ao criar ATR handle: ", GetLastError());
      return INIT_FAILED;
   }

   //--- Handles MTF
   if(Inp_Use_MTF_Filter)
   {
      hWPR_Trend = iWPR(_Symbol, Inp_MTF_Trend, Inp_WPR_Period);
      if(hWPR_Trend == INVALID_HANDLE)
      {
         Print("Erro ao criar WPR_Trend handle: ", GetLastError());
         return INIT_FAILED;
      }

      hWPR_Entry = iWPR(_Symbol, Inp_MTF_Entry, Inp_WPR_Period);
      if(hWPR_Entry == INVALID_HANDLE)
      {
         Print("Erro ao criar WPR_Entry handle: ", GetLastError());
         return INIT_FAILED;
      }
   }

   //--- Criar objetos gráficos
   CreateObjects();

   last_bar_time = 0;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Libertar handles
   if(hWPR != INVALID_HANDLE)       IndicatorRelease(hWPR);
   if(hRSI != INVALID_HANDLE)       IndicatorRelease(hRSI);
   if(hATR != INVALID_HANDLE)       IndicatorRelease(hATR);
   if(hWPR_Trend != INVALID_HANDLE) IndicatorRelease(hWPR_Trend);
   if(hWPR_Entry != INVALID_HANDLE) IndicatorRelease(hWPR_Entry);

   //--- Apagar objetos
   ObjectsDeleteAllByPrefix(prefix);
   ObjectDelete(0, objTrendLabel);
   ObjectDelete(0, objPLLabel);
   ObjectDelete(0, objInfoBox);

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
   if(rates_total < Inp_WPR_Period + OMIT_OLDEST_BARS)
      return rates_total;

   //--- Configurar séries
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(B1_BUY, true);
   ArraySetAsSeries(B2_SELL, true);

   //--- Limpar buffers de saída
   if(prev_calculated < 1)
   {
      ArrayInitialize(B1_BUY,  EMPTY_VALUE);
      ArrayInitialize(B2_SELL, EMPTY_VALUE);
   }

   //--- Calcular limite para iteração
   int limit = (prev_calculated < 1) ? rates_total - 1 : rates_total - prev_calculated + 1;
   if(limit > rates_total - OMIT_OLDEST_BARS)
      limit = rates_total - OMIT_OLDEST_BARS;
   if(limit < 1) limit = 1;

   //--- Copiar dados dos indicadores
   if(!CopyIndicatorBuffers(rates_total))
      return rates_total;

   //--- Copiar preços
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, rates_total, high_buf) <= 0) return rates_total;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, rates_total, low_buf) <= 0) return rates_total;
   if(CopyClose(_Symbol, PERIOD_CURRENT, 0, rates_total, close_buf) <= 0) return rates_total;
   if(CopyOpen(_Symbol, PERIOD_CURRENT, 0, rates_total, open_buf) <= 0) return rates_total;

   ArraySetAsSeries(high_buf, true);
   ArraySetAsSeries(low_buf, true);
   ArraySetAsSeries(close_buf, true);
   ArraySetAsSeries(open_buf, true);
   ArraySetAsSeries(wpr_buf, true);
   ArraySetAsSeries(rsi_buf, true);
   ArraySetAsSeries(atr_buf, true);

   //--- Loop principal de análise
   for(int i = limit - 1; i >= 0; i--)
   {
      //--- Garantir que há dados suficientes
      if(i >= rates_total - OMIT_OLDEST_BARS - Inp_WPR_Period)
         continue;

      //--- Pular se valores inválidos
      if(wpr_buf[i] == EMPTY_VALUE || wpr_buf[i] == 0.0 ||
         rsi_buf[i] == EMPTY_VALUE || rsi_buf[i] == 0.0)
         continue;

      //--- VARIÁVEIS DE SINAL
      bool buy_signal  = false;
      bool sell_signal = false;
      int  signal_strength = 0; // 0=neutro, 1=fraco, 2=médio, 3=forte

      //=== 1. WPR CRUZANDO O PIVOT (sinal clássico melhorado) ===
      bool wpr_bull_cross = (wpr_buf[i] > Inp_WPR_Pivot && wpr_buf[i+1] <= Inp_WPR_Pivot);
      bool wpr_bear_cross = (wpr_buf[i] < Inp_WPR_Pivot && wpr_buf[i+1] >= Inp_WPR_Pivot);

      //=== 2. WPR OVERSOLD/OVERBOUGHT COM CONFIRMAÇÃO RSI ===
      bool wpr_oversold   = (wpr_buf[i] <= Inp_WPR_OS_Level);
      bool wpr_overbought = (wpr_buf[i] >= Inp_WPR_OB_Level);
      bool rsi_oversold   = (rsi_buf[i] <= Inp_RSI_OS_Level);
      bool rsi_overbought = (rsi_buf[i] >= Inp_RSI_OB_Level);

      bool extreme_zone_buy  = (wpr_oversold && rsi_oversold);
      bool extreme_zone_sell = (wpr_overbought && rsi_overbought);

      //=== 3. DIVERGÊNCIA BULLISH/BEARISH ===
      bool bullish_divergence  = DetectBullishDivergence(i, wpr_buf, low_buf);
      bool bearish_divergence  = DetectBearishDivergence(i, wpr_buf, high_buf);

      //=== 4. ACELERAÇÃO DO WPR (momentum) ===
      bool wpr_accel_up = false;
      bool wpr_accel_down = false;
      if(i + 3 < rates_total)
      {
         double mom1 = wpr_buf[i]   - wpr_buf[i+1];
         double mom2 = wpr_buf[i+1] - wpr_buf[i+2];
         wpr_accel_up   = (mom1 > 0 && mom2 > 0 && mom1 > mom2 * 1.3);
         wpr_accel_down = (mom1 < 0 && mom2 < 0 && mom1 < mom2 * 1.3);
      }

      //=== 5. ATR BREAKOUT ===
      bool atr_breakout_up   = false;
      bool atr_breakout_down = false;
      if(i + 2 < rates_total)
      {
         double range1 = high_buf[i] - low_buf[i];
         atr_breakout_up   = (range1 > atr_buf[i] * Inp_ATR_Breakout_Factor
                              && close_buf[i] > open_buf[i]);
         atr_breakout_down = (range1 > atr_buf[i] * Inp_ATR_Breakout_Factor
                              && close_buf[i] < open_buf[i]);
      }

      //=== 6. MTF FILTER (higher timeframe trend) ===
      bool mtf_trend_up   = true;
      bool mtf_trend_down = true;

      if(Inp_Use_MTF_Filter && hWPR_Trend != INVALID_HANDLE && hWPR_Entry != INVALID_HANDLE)
      {
         double wpr_trend[1], wpr_entry[1];
         if(CopyBuffer(hWPR_Trend, 0, 0, 1, wpr_trend) > 0 &&
            CopyBuffer(hWPR_Entry, 0, 0, 1, wpr_entry) > 0)
         {
            mtf_trend_up   = (wpr_trend[0] > Inp_WPR_Pivot && wpr_entry[0] > Inp_WPR_Pivot);
            mtf_trend_down = (wpr_trend[0] < Inp_WPR_Pivot && wpr_entry[0] < Inp_WPR_Pivot);
         }
      }

      //+------------------------------------------------------------------+
      //| COMBINAR SINAIS - LÓGICA ANTECIPATÓRIA PRINCIPAL                |
      //+------------------------------------------------------------------+

      // --- SINAL DE COMPRA ANTECIPADO ---
      // Nível 3 (Forte): Divergência + oversold zone + aceleração
      if(bullish_divergence && extreme_zone_buy && wpr_accel_up)
      {
         buy_signal       = true;
         signal_strength  = 3;
      }
      // Nível 2 (Médio): WPR crucando pivot + RSI oversold + breakout
      else if(wpr_bull_cross && rsi_oversold && atr_breakout_up)
      {
         buy_signal       = true;
         signal_strength  = 2;
      }
      // Nível 1 (Fraco): Apenas divergência ou oversold com aceleração
      else if((bullish_divergence || (wpr_oversold && wpr_accel_up)) && !wpr_overbought)
      {
         buy_signal       = true;
         signal_strength  = 1;
      }

      // Aplicar filtro MTF (se ativo, só compra se MTF concordar)
      if(Inp_Use_MTF_Filter && buy_signal && !mtf_trend_up)
         buy_signal = false;

      // --- SINAL DE VENDA ANTECIPADO ---
      // Nível 3 (Forte): Divergência + overbought zone + aceleração
      if(bearish_divergence && extreme_zone_sell && wpr_accel_down)
      {
         sell_signal      = true;
         signal_strength  = 3;
      }
      // Nível 2 (Médio): WPR crucando pivot + RSI overbought + breakout
      else if(wpr_bear_cross && rsi_overbought && atr_breakout_down)
      {
         sell_signal      = true;
         signal_strength  = 2;
      }
      // Nível 1 (Fraco): Apenas divergência ou overbought com aceleração
      else if((bearish_divergence || (wpr_overbought && wpr_accel_down)) && !wpr_oversold)
      {
         sell_signal      = true;
         signal_strength  = 1;
      }

      // Aplicar filtro MTF
      if(Inp_Use_MTF_Filter && sell_signal && !mtf_trend_down)
         sell_signal = false;

      //--- GERAR SETAS NO GRÁFICO ---
      if(buy_signal && signal_strength >= 2)
      {
         // Sinal forte = offset maior, sinal médio = offset normal
         B1_BUY[i] = low_buf[i] - (signal_strength == 3 ? 2.0 : 1.0) * myPoint * 5.0;
      }
      else
      {
         B1_BUY[i] = EMPTY_VALUE;
      }

      if(sell_signal && signal_strength >= 2)
      {
         B2_SELL[i] = high_buf[i] + (signal_strength == 3 ? 2.0 : 1.0) * myPoint * 5.0;
      }
      else
      {
         B2_SELL[i] = EMPTY_VALUE;
      }
   }

   //--- ATUALIZAR DASHBOARD (apenas na barra nova)
   if(time[0] != last_bar_time)
   {
      last_bar_time = time[0];
      UpdateDashboard();
      UpdateTrendPrediction();
      UpdatePLInfo();
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Copiar buffers dos indicadores auxiliares                        |
//+------------------------------------------------------------------+
bool CopyIndicatorBuffers(int total)
{
   ArrayResize(wpr_buf,    total);
   ArrayResize(rsi_buf,    total);
   ArrayResize(atr_buf,    total);
   ArrayResize(high_buf,   total);
   ArrayResize(low_buf,    total);
   ArrayResize(close_buf,  total);
   ArrayResize(open_buf,   total);

   if(CopyBuffer(hWPR, 0, 0, total, wpr_buf) <= 0) return false;
   if(CopyBuffer(hRSI, 0, 0, total, rsi_buf) <= 0) return false;
   if(CopyBuffer(hATR, 0, 0, total, atr_buf) <= 0) return false;

   return true;
}

//+------------------------------------------------------------------+
//| DETECTAR DIVERGÊNCIA BULLISH                                     |
//| Preço faz fundo mais baixo, WPR faz fundo mais alto            |
//+------------------------------------------------------------------+
bool DetectBullishDivergence(int shift, double &wpr_arr[], double &low_arr[])
{
   int total = ArraySize(wpr_arr);
   if(shift + Inp_Divergence_Bars > total - 1)
      return false;

   int lookback = MathMin(Inp_Divergence_Bars, total - shift - 5);
   if(lookback < 5) return false;

   double price_now = low_arr[shift];
   double wpr_now   = wpr_arr[shift];

   for(int j = shift + 2; j < shift + lookback; j++)
   {
      if(j + 1 < total &&
         low_arr[j] < low_arr[j-1] &&
         low_arr[j] < low_arr[j+1] &&
         low_arr[j] < price_now)
      {
         if(j + 1 < total &&
            wpr_arr[j] < wpr_arr[j-1] &&
            wpr_arr[j] < wpr_arr[j+1])
         {
            if(wpr_arr[j] > wpr_now && wpr_now < Inp_WPR_OS_Level)
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| DETECTAR DIVERGÊNCIA BEARISH                                     |
//| Preço faz topo mais alto, WPR faz topo mais baixo              |
//+------------------------------------------------------------------+
bool DetectBearishDivergence(int shift, double &wpr_arr[], double &high_arr[])
{
   int total = ArraySize(wpr_arr);
   if(shift + Inp_Divergence_Bars > total - 1)
      return false;

   int lookback = MathMin(Inp_Divergence_Bars, total - shift - 5);
   if(lookback < 5) return false;

   double price_now = high_arr[shift];
   double wpr_now   = wpr_arr[shift];

   for(int j = shift + 2; j < shift + lookback; j++)
   {
      if(j + 1 < total &&
         high_arr[j] > high_arr[j-1] &&
         high_arr[j] > high_arr[j+1] &&
         high_arr[j] > price_now)
      {
         if(j + 1 < total &&
            wpr_arr[j] > wpr_arr[j-1] &&
            wpr_arr[j] > wpr_arr[j+1])
         {
            if(wpr_arr[j] < wpr_now && wpr_now > Inp_WPR_OB_Level)
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| DASHBOARD - Atualizar display MTF                                |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int x = Inp_Dash_X;
   int y = Inp_Dash_Y;
   int row_h = 22;
   int col_w = 90;

   //--- Limpar dashboard anterior
   ObjectsDeleteAllByPrefix(objDashPrefix);

   //--- Cabeçalho
   string header = "== VORTEX MTF ANTECIPADOR [" + _Symbol + " " + TFToString(PERIOD_CURRENT) + "] ==";
   CreateLabel(objDashPrefix + "header", header, x, y, clrWhite, clrDarkSlateGray, Inp_Font_Size, 540);
   y += row_h + 2;

   //--- Timeframes para monitorar
   ENUM_TIMEFRAMES tfs[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   string tf_names[] = {"M1","M5","M15","M30","H1","H4","D1"};

   //--- Cabeçalho das colunas
   CreateLabel(objDashPrefix + "col_tf",  " TF",  x, y, clrWhite, clrGray, Inp_Font_Size-1, col_w);
   CreateLabel(objDashPrefix + "col_wpr", " WPR",  x + col_w, y, clrWhite, clrGray, Inp_Font_Size-1, col_w);
   CreateLabel(objDashPrefix + "col_sig", " SINAL", x + col_w*2, y, clrWhite, clrGray, Inp_Font_Size-1, col_w*2);
   y += row_h;

   for(int i = 0; i < ArraySize(tfs); i++)
   {
      //--- Obter WPR para cada timeframe
      int h = iWPR(_Symbol, tfs[i], Inp_WPR_Period);
      if(h == INVALID_HANDLE) continue;

      double wpr_val[1];
      bool ok = (CopyBuffer(h, 0, 0, 1, wpr_val) > 0);
      IndicatorRelease(h);
      if(!ok) continue;

      double wv = wpr_val[0];

      //--- Determinar status
      string status;
      color  bg_color;

      if(wv <= Inp_WPR_OS_Level)
      {
         status   = "COMPRA (OS)";
         bg_color = clrMediumSeaGreen;
      }
      else if(wv >= Inp_WPR_OB_Level)
      {
         status   = "VENDA (OB)";
         bg_color = clrRed;
      }
      else if(wv > Inp_WPR_Pivot)
      {
         status   = "ALTISTA";
         bg_color = clrDodgerBlue;
      }
      else if(wv < Inp_WPR_Pivot)
      {
         status   = "BAIXISTA";
         bg_color = clrDarkOrange;
      }
      else
      {
         status   = "NEUTRO";
         bg_color = clrGray;
      }

      string id = objDashPrefix + tf_names[i];

      CreateLabel(id + "_tf",  " " + tf_names[i],  x, y, clrWhite, clrBlack, Inp_Font_Size-1, col_w);
      CreateLabel(id + "_wpr", " " + DoubleToString(wv, 1), x + col_w, y, clrWhite, clrBlack, Inp_Font_Size-1, col_w);
      CreateLabel(id + "_sig", " " + status, x + col_w*2, y, clrWhite, bg_color, Inp_Font_Size-1, col_w*2);

      y += row_h;
   }

   //--- Legenda
   y += 5;
   CreateLabel(objDashPrefix + "legend",
      "Sinais: Divergencia | Aceleracao | Breakout ATR | Filtro MTF: " + (Inp_Use_MTF_Filter ? "ATIVO" : "INATIVO"),
      x, y, clrLightGray, clrBlack, 9, 540);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| ATUALIZAR PREVISÃO DE TENDÊNCIA                                  |
//+------------------------------------------------------------------+
void UpdateTrendPrediction()
{
   double wpr[1];
   if(CopyBuffer(hWPR, 0, 0, 1, wpr) <= 0) return;

   double wv = wpr[0];
   string text;
   color  clr_color;

   //--- Verificar divergência na barra atual
   bool bullish_div = DetectBullishDivergence(0, wpr_buf, low_buf);
   bool bearish_div = DetectBearishDivergence(0, wpr_buf, high_buf);

   //--- Previsão combinada
   if(bullish_div && wv < Inp_WPR_Pivot)
   {
      text = "ANTECIPACAO: COMPRA (Divergencia Alta)";
      clr_color  = clrSpringGreen;
   }
   else if(bearish_div && wv > Inp_WPR_Pivot)
   {
      text = "ANTECIPACAO: VENDA (Divergencia Baixa)";
      clr_color  = clrOrange;
   }
   else if(wv <= Inp_WPR_OS_Level)
   {
      text = "COMPRAR (WPR Oversold: " + DoubleToString(wv, 1) + ")";
      clr_color  = clrLime;
   }
   else if(wv >= Inp_WPR_OB_Level)
   {
      text = "VENDER (WPR Overbought: " + DoubleToString(wv, 1) + ")";
      clr_color  = clrRed;
   }
   else if(wv > Inp_WPR_Pivot)
   {
      text = "TENDENCIA: ALTA (WPR: " + DoubleToString(wv, 1) + ")";
      clr_color  = clrDodgerBlue;
   }
   else if(wv < Inp_WPR_Pivot)
   {
      text = "TENDENCIA: BAIXA (WPR: " + DoubleToString(wv, 1) + ")";
      clr_color  = clrDarkOrange;
   }
   else
   {
      text = "AGUARDANDO (WPR: " + DoubleToString(wv, 1) + ")";
      clr_color  = clrYellow;
   }

   //--- Adicionar info de força
   if(Inp_Use_MTF_Filter && hWPR_Trend != INVALID_HANDLE)
   {
      double trend_val[1];
      if(CopyBuffer(hWPR_Trend, 0, 0, 1, trend_val) > 0)
      {
         string tf_name = TFToString(Inp_MTF_Trend);
         text += " | " + tf_name + ": " + DoubleToString(trend_val[0], 1);
      }
   }

   ObjectSetString(0, objTrendLabel, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objTrendLabel, OBJPROP_COLOR, clr_color);
}

//+------------------------------------------------------------------+
//| ATUALIZAR P/L E LOTS                                             |
//+------------------------------------------------------------------+
void UpdatePLInfo()
{
   double total_profit    = 0;
   double total_buy_lots  = 0;
   double total_sell_lots = 0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            total_profit    += PositionGetDouble(POSITION_PROFIT);
            long type        = PositionGetInteger(POSITION_TYPE);
            double lots      = PositionGetDouble(POSITION_VOLUME);
            if(type == POSITION_TYPE_BUY)
               total_buy_lots  += lots;
            else if(type == POSITION_TYPE_SELL)
               total_sell_lots += lots;
         }
      }
   }

   //--- Calcular TP/SL dinâmico baseado em ATR
   double atr_val[1];
   string tp_sl_info = "";
   if(CopyBuffer(hATR, 0, 0, 1, atr_val) > 0)
   {
      double tp_dist = atr_val[0] * Inp_ATR_TP_Multiplier;
      double sl_dist = atr_val[0] * Inp_ATR_SL_Multiplier;
      tp_sl_info = StringFormat(" | ATR: %.5f | TP: %.5f | SL: %.5f",
                                atr_val[0], tp_dist, sl_dist);
   }

   //--- Montar texto P/L
   string pl_text;
   color  pl_color;

   if(total_profit >= 0)
   {
      pl_text = StringFormat("LUCRO (%s): +$%.2f", _Symbol, total_profit);
      pl_color = clrLimeGreen;
   }
   else
   {
      pl_text = StringFormat("PREJUIZO (%s): -$%.2f", _Symbol, MathAbs(total_profit));
      pl_color = clrGold;
   }

   string lots_text = StringFormat(" | BUY: %.2f | SELL: %.2f", total_buy_lots, total_sell_lots);
   pl_text += lots_text + tp_sl_info;

   ObjectSetString(0, objPLLabel, OBJPROP_TEXT, pl_text);
   ObjectSetInteger(0, objPLLabel, OBJPROP_COLOR, pl_color);
}

//+------------------------------------------------------------------+
//| CRIAR OBJETOS GRÁFICOS INICIAIS                                  |
//+------------------------------------------------------------------+
void CreateObjects()
{
   //--- Label de previsão de tendência (canto superior)
   ObjectCreate(0, objTrendLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objTrendLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objTrendLabel, OBJPROP_XDISTANCE, Inp_Dash_X);
   ObjectSetInteger(0, objTrendLabel, OBJPROP_YDISTANCE, Inp_Dash_Y - 2);
   ObjectSetInteger(0, objTrendLabel, OBJPROP_FONTSIZE, Inp_Font_Size + 1);
   ObjectSetInteger(0, objTrendLabel, OBJPROP_SELECTABLE, false);

   //--- Label de P/L (canto inferior esquerdo)
   ObjectCreate(0, objPLLabel, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, objPLLabel, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, objPLLabel, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, objPLLabel, OBJPROP_YDISTANCE, 40);
   ObjectSetInteger(0, objPLLabel, OBJPROP_FONTSIZE, Inp_Font_Size + 1);
   ObjectSetInteger(0, objPLLabel, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Criar label com fundo (edit box disfarçado)                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y,
                 color txt_color, color bg_color, int font_size, int width)
{
   ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 20);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_READONLY, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txt_color);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_LEFT);
}

//+------------------------------------------------------------------+
//| Apagar todos os objetos com prefixo                               |
//+------------------------------------------------------------------+
void ObjectsDeleteAllByPrefix(string pref)
{
   for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
   {
      string obj_name = ObjectName(0, i);
      if(StringFind(obj_name, pref) == 0)
         ObjectDelete(0, obj_name);
   }
}

//+------------------------------------------------------------------+
//| Converter timeframe para string                                  |
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return IntegerToString(tf);
   }
}
//+------------------------------------------------------------------+
