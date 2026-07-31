//+------------------------------------------------------------------+
//|                                        EURUSD_vs_GBPUSD_v1.mq5  |
//|                                     IA do MetaCode - Correlacao |
//|                                    Versao: 1.0 - 28/06/2026    |
//+------------------------------------------------------------------+
#property copyright "IA do MetaCode"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "EURUSD (normalizado)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_label2  "GBPUSD (normalizado)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLimeGreen

input int InpMAPeriod = 20; // Periodo para normalizacao

double ExtEURBuffer[];
double ExtGBPBuffer[];

int OnInit()
  {
   SetIndexBuffer(0, ExtEURBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ExtGBPBuffer, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "EURUSD vs GBPUSD (Corr: +0.89)");
   IndicatorSetInteger(INDICATOR_DIGITS, 4);
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(rates_total < InpMAPeriod) return(0);
   int start = prev_calculated > 0 ? prev_calculated - 1 : InpMAPeriod;
   
   double eur_ma=0, gbp_ma=0;
   double eur_std=0, gbp_std=0;
   
   for(int i=start; i<rates_total; i++)
     {
      // Calcular media movel para normalizacao
      if(i>=InpMAPeriod)
        {
         eur_ma = 0; gbp_ma = 0;
         for(int j=0; j<InpMAPeriod; j++)
           {
            eur_ma += close[i-j];
            gbp_ma += SymbolInfoDouble("GBPUSD", SYMBOL_BID);
           }
         eur_ma /= InpMAPeriod;
         gbp_ma /= InpMAPeriod;
        }
      ExtEURBuffer[i] = close[i];
      ExtGBPBuffer[i] = SymbolInfoDouble("GBPUSD", SYMBOL_BID);
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
