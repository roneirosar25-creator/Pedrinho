//+------------------------------------------------------------------+
//| TRIVIUM_ESTILINGUE_IND.mq5                                        |
//| TRIVIUM369 (c) 2026 - Pedrinho, 19/07/2026                        |
//|                                                                    |
//| Visualiza o setup Efeito Estilingue (validado, ver               |
//| NEXUS369_ESTILINGUE_EA.mq5): plota as Bandas de Bollinger(21,2) e  |
//| marca com seta a vela que tentou romper a banda e fechou de volta  |
//| pra dentro (trap) durante um regime de squeeze - so pra leitura    |
//| discricionaria, nao abre posicao (isso e o EA).                    |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   3

#property indicator_label1  "BB Superior"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_DOT
#property indicator_width1  1

#property indicator_label2  "BB Inferior"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSilver
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "Estilingue"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrCyan
#property indicator_width3  3

input int    InpBBPeriod          = 21;
input double InpBBDesvio          = 2.0;
input int    InpSqueezePercJanela = 100;
input double InpSqueezePercMax    = 0.30;

double BufSup[], BufInf[], BufSeta[];
double BufMid[], BufWidth[]; // internos, nao plotados diretamente

int h_bb = INVALID_HANDLE;

int OnInit()
{
   SetIndexBuffer(0, BufSup, INDICATOR_DATA);
   SetIndexBuffer(1, BufInf, INDICATOR_DATA);
   SetIndexBuffer(2, BufSeta, INDICATOR_DATA);
   SetIndexBuffer(3, BufMid, INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufWidth, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(2, PLOT_ARROW, 159); // seta "estrela" - trap do squeeze
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 0);

   h_bb = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDesvio, PRICE_CLOSE);
   if(h_bb == INVALID_HANDLE) return INIT_FAILED;

   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM Estilingue");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_bb != INVALID_HANDLE) IndicatorRelease(h_bb);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   int minBars = InpBBPeriod + InpSqueezePercJanela + 2;
   if(rates_total < minBars) return 0;

   double bufUpperRaw[], bufLowerRaw[], bufMidRaw[];
   if(CopyBuffer(h_bb, 1, 0, rates_total, bufUpperRaw) <= 0) return 0;
   if(CopyBuffer(h_bb, 2, 0, rates_total, bufLowerRaw) <= 0) return 0;
   if(CopyBuffer(h_bb, 0, 0, rates_total, bufMidRaw)   <= 0) return 0;

   int start = MathMax(prev_calculated - 1, minBars);
   for(int i = start; i < rates_total; i++)
   {
      BufSup[i] = bufUpperRaw[i];
      BufInf[i] = bufLowerRaw[i];
      BufWidth[i] = (bufMidRaw[i] > 0) ? (bufUpperRaw[i] - bufLowerRaw[i]) / bufMidRaw[i] : 0;
      BufSeta[i] = EMPTY_VALUE;

      if(i < InpSqueezePercJanela + 1) continue;

      // percentil da largura atual contra a janela anterior
      int menores = 0;
      for(int k = i - InpSqueezePercJanela; k < i; k++)
         if(BufWidth[k] <= BufWidth[i]) menores++;
      double percentil = (double)menores / (double)InpSqueezePercJanela;
      if(percentil > InpSqueezePercMax) continue; // so em regime de squeeze

      bool tentouCima  = (high[i] > bufUpperRaw[i]) && (close[i] < bufUpperRaw[i]);
      bool tentouBaixo = (low[i]  < bufLowerRaw[i]) && (close[i] > bufLowerRaw[i]);
      if(tentouCima)
         BufSeta[i] = high[i]; // trap em cima - marca no topo da vela
      else if(tentouBaixo)
         BufSeta[i] = low[i]; // trap embaixo - marca na base da vela
   }
   return rates_total;
}
//+------------------------------------------------------------------+
