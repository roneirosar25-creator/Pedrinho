//+------------------------------------------------------------------+
//|                                    EURUSD_vs_XAUUSD_LEADING_v1   |
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
#property indicator_label2  "XAUUSD (4h atras - LEADING)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange

input int InpLagHours = 4; // Defasagem em horas (ouro lidera)

double ExtEURBuffer[];
double ExtXAUHist[];

int OnInit()
  {
   SetIndexBuffer(0, ExtEURBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ExtXAUHist, INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME, "XAUUSD Leading (Lag: " + (string)InpLagHours + "h)");
   IndicatorSetInteger(INDICATOR_DIGITS, 5);
   return(INIT_SUCCEEDED);
  }

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
  {
   if(rates_total < 50) return(0);
   int start = prev_calculated > 0 ? prev_calculated - 1 : 0;
   
   for(int i=start; i<rates_total; i++)
     {
      ExtEURBuffer[i] = close[i];
      double xau = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
      if(xau > 0) ExtXAUHist[i] = xau / 3000.0; // Normaliza para escala similar
      else ExtXAUHist[i] = close[i];
     }
   return(rates_total);
  }
//+------------------------------------------------------------------+
