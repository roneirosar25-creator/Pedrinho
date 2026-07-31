//+------------------------------------------------------------------+
//| TRIVIUM_SINAL_EA.mq5                                              |
//| Espelha a logica exata do NEXUS369_TREND_VALIDADO.mq5              |
//| (ADX + Volume + DI). Desenha seta de compra/venda em TODA barra   |
//| historica onde as 3 condicoes bateram juntas (nao so nas que      |
//| viraram ordem de verdade) + painel ao vivo com os valores atuais  |
//| vs o limiar calibrado do ativo, pra acompanhar o quao perto esta  |
//| de gerar um sinal.                                                |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label1  "Sinal Compra"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_label2  "Sinal Venda"

input int InpADXPeriod    = 14;
input int InpVolumePeriod = 20;

double bufCompra[];
double bufVenda[];
int    h_adx = INVALID_HANDLE;
double g_adxMin, g_volMin;

//+------------------------------------------------------------------+
// Limiares calibrados por ativo - mesmos valores usados no EA
// NEXUS369_TREND_VALIDADO (ver cabecalho do .mq5 pra referencia)
//+------------------------------------------------------------------+
void CarregarLimiaresPorAtivo()
{
   string s = _Symbol;
   StringToUpper(s);
   if(StringFind(s,"NZDJPY")>=0)      { g_adxMin=35.0; g_volMin=1.3; }
   else if(StringFind(s,"USDCAD")>=0) { g_adxMin=35.0; g_volMin=1.1; }
   else if(StringFind(s,"AUDUSD")>=0) { g_adxMin=35.0; g_volMin=1.5; }
   else if(StringFind(s,"NZDUSD")>=0) { g_adxMin=32.0; g_volMin=1.5; }
   else if(StringFind(s,"GER40")>=0)  { g_adxMin=30.0; g_volMin=1.1; }
   else if(StringFind(s,"BTC")>=0)    { g_adxMin=28.0; g_volMin=1.5; }
   else                               { g_adxMin=25.0; g_volMin=1.2; } // default do EA
}

int OnInit()
{
   SetIndexBuffer(0, bufCompra, INDICATOR_DATA);
   SetIndexBuffer(1, bufVenda,  INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -15);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT, 15);

   CarregarLimiaresPorAtivo();

   h_adx = iADX(_Symbol, _Period, InpADXPeriod);
   if(h_adx == INVALID_HANDLE)
   {
      Print("Erro ao criar handle ADX: ", GetLastError());
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("TRIVIUM_SINAL_EA (ADX>%.1f Vol>%.1fx)", g_adxMin, g_volMin));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_adx != INVALID_HANDLE) IndicatorRelease(h_adx);
   Comment("");
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpVolumePeriod + InpADXPeriod + 2) return 0;

   int start = (prev_calculated > InpVolumePeriod + 2) ? prev_calculated - 1 : InpVolumePeriod + 2;

   double adx_buf[], plus_di[], minus_di[];
   int need = rates_total - start + 5;
   if(CopyBuffer(h_adx, 0, 0, rates_total, adx_buf)   <= 0) return 0;
   if(CopyBuffer(h_adx, 1, 0, rates_total, plus_di)   <= 0) return 0;
   if(CopyBuffer(h_adx, 2, 0, rates_total, minus_di)  <= 0) return 0;

   for(int i = start; i < rates_total; i++)
   {
      bufCompra[i] = EMPTY_VALUE;
      bufVenda[i]  = EMPTY_VALUE;
      if(i < InpVolumePeriod + 1) continue;

      double vol_avg = 0;
      for(int j = 1; j <= InpVolumePeriod; j++) vol_avg += (double)tick_volume[i-j];
      vol_avg /= InpVolumePeriod;
      if(vol_avg <= 0) continue;

      double vol_ratio = (double)tick_volume[i] / vol_avg;
      double adx_val = adx_buf[i];
      double dPlus   = plus_di[i];
      double dMinus  = minus_di[i];

      if(adx_val > g_adxMin && vol_ratio > g_volMin)
      {
         if(dPlus > dMinus)       bufCompra[i] = low[i];
         else if(dMinus > dPlus)  bufVenda[i]  = high[i];
      }
   }

   // Painel ao vivo com o estado ATUAL (ultima barra fechada)
   int last = rates_total - 1;
   if(last >= InpVolumePeriod + 1)
   {
      double vol_avg_now = 0;
      for(int j = 1; j <= InpVolumePeriod; j++) vol_avg_now += (double)tick_volume[last-j];
      vol_avg_now /= InpVolumePeriod;
      double vol_ratio_now = (vol_avg_now > 0) ? (double)tick_volume[last] / vol_avg_now : 0;
      double adx_now   = adx_buf[last];
      double plus_now  = plus_di[last];
      double minus_now = minus_di[last];

      string direcao = (plus_now > minus_now) ? "COMPRA" : (minus_now > plus_now) ? "VENDA" : "NEUTRO";
      bool adxOk = adx_now > g_adxMin;
      bool volOk = vol_ratio_now > g_volMin;
      string status = (adxOk && volOk) ? "SINAL ARMADO -> " + direcao : "esperando (falta: " +
                       (!adxOk ? "ADX " : "") + (!volOk ? "Volume" : "") + ")";

      Comment(StringFormat(
         "TRIVIUM SINAL EA - %s\nADX atual: %.1f (min %.1f) %s\nVolume atual: %.2fx (min %.1fx) %s\nDirecao (+DI/-DI): %s\nStatus: %s",
         _Symbol, adx_now, g_adxMin, (adxOk?"OK":"abaixo"),
         vol_ratio_now, g_volMin, (volOk?"OK":"abaixo"),
         direcao, status));
   }

   return rates_total;
}
