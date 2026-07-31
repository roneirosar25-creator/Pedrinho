//+------------------------------------------------------------------+
//| TRIVIUM_VWAP.mq5                                                  |
//| TRIVIUM369 (c) 2026 - Pedrinho, 14/07/2026                        |
//|                                                                    |
//| VWAP diario (preco medio ponderado por volume), reinicia a cada    |
//| novo dia (D1). "Linha de justica" do scalper: preco acima = mais   |
//| gente comprou caro que barato hoje (viés comprador), abaixo = o    |
//| inverso.                                                            |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrWhite
#property indicator_width1  1
#property indicator_style1  STYLE_SOLID

double BufVWAP[];

int OnInit()
{
   SetIndexBuffer(0, BufVWAP, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_VWAP");
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(prev_calculated == 0)
      ArrayInitialize(BufVWAP, EMPTY_VALUE);

   int start = (prev_calculated > 1) ? prev_calculated - 2 : 0;

   double somaPV = 0, somaV = 0;
   datetime diaAtual = 0;

   // acha o inicio do dia atual pra recomecar a soma do zero
   int inicioDia = start;
   for(int i = start; i >= 0; i--)
   {
      MqlDateTime dt; TimeToStruct(time[i], dt);
      MqlDateTime dtRef; TimeToStruct(time[start], dtRef);
      if(dt.day != dtRef.day || dt.mon != dtRef.mon || dt.year != dtRef.year) { inicioDia = i + 1; break; }
      inicioDia = i;
   }

   for(int i = inicioDia; i < rates_total; i++)
   {
      MqlDateTime dt; TimeToStruct(time[i], dt);
      if(i == inicioDia) { somaPV = 0; somaV = 0; diaAtual = time[i]; }
      else
      {
         MqlDateTime dtPrev; TimeToStruct(time[i-1], dtPrev);
         if(dt.day != dtPrev.day || dt.mon != dtPrev.mon || dt.year != dtPrev.year) { somaPV = 0; somaV = 0; }
      }

      double precoTipico = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (double)tick_volume[i];
      somaPV += precoTipico * vol;
      somaV  += vol;

      BufVWAP[i] = (somaV > 0) ? somaPV / somaV : precoTipico;
   }

   return rates_total;
}
//+------------------------------------------------------------------+
