//+------------------------------------------------------------------+
//| TRIVIUM_VOLUME_ANOMALO.mq5                                        |
//| TRIVIUM369 (c) 2026 - Pedrinho, 14/07/2026                        |
//|                                                                    |
//| Marca com uma seta abaixo/acima da vela quando o volume (tick      |
//| volume) daquela vela esta muito acima da media recente - ajuda a   |
//| identificar clímax de movimento / possivel exaustao ou entrada de  |
//| "dinheiro grande". Fator e janela ajustaveis.                      |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_label1  "Volume Anomalo"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrFuchsia
#property indicator_width1  2

input int    InpJanelaMedia = 20;   // quantas velas pra tras pra calcular a media de volume
input double InpFator       = 2.5;  // volume acima de (media x fator) = anomalo

double BufMarca[];

int OnInit()
{
   SetIndexBuffer(0, BufMarca, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_ARROW, 174); // seta pra cima estilizada
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_VOLUME_ANOMALO");
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(prev_calculated == 0)
      ArrayInitialize(BufMarca, EMPTY_VALUE);

   int start = (prev_calculated > InpJanelaMedia) ? prev_calculated - 2 : InpJanelaMedia;

   for(int i = start; i < rates_total; i++)
   {
      if(i < InpJanelaMedia) { BufMarca[i] = EMPTY_VALUE; continue; }

      double somaVol = 0;
      for(int j = 1; j <= InpJanelaMedia; j++)
         somaVol += (double)tick_volume[i-j];
      double media = somaVol / InpJanelaMedia;

      if(media > 0 && tick_volume[i] >= media * InpFator)
         BufMarca[i] = high[i] + (high[i] - low[i]) * 0.3; // marca um pouco acima da vela
      else
         BufMarca[i] = EMPTY_VALUE;
   }

   return rates_total;
}
//+------------------------------------------------------------------+
