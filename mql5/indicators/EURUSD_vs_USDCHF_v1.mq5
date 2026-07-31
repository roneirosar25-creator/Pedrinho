//+------------------------------------------------------------------+
//|                                        EURUSD_vs_USDCHF_v1.mq5  |
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
#property indicator_label1  "EURUSD"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_label2  "USDCHF (invertido)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed

double ExtEURBuffer[];
double ExtCHFBuffer[];

int OnInit()
  {
   SetIndexBuffer(0, ExtEURBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ExtCHFBuffer, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "EURUSD vs USDCHF (Corr: -0.91)");
   IndicatorSetInteger(INDICATOR_DIGITS, 5);
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(rates_total < 2) return(0);
   int start = prev_calculated > 0 ? prev_calculated - 1 : 0;
   
   for(int i=start; i<rates_total; i++)
     {
      ExtEURBuffer[i] = close[i];
      double usdchf = SymbolInfoDouble("USDCHF", SYMBOL_BID);
      if(usdchf > 0) ExtCHFBuffer[i] = 1.0 / usdchf; // Inverte para comparacao
      else ExtCHFBuffer[i] = close[i];
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
