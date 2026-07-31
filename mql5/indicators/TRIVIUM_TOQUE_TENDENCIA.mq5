//+------------------------------------------------------------------+
//| TRIVIUM_TOQUE_TENDENCIA.mq5                                       |
//| TRIVIUM369 (c) 2026 - Pedrinho, 16/07/2026                        |
//|                                                                    |
//| Marca automaticamente o padrao "pullback ate a media + retomada"   |
//| que a gente identificou olhando o grafico do NZDJPY M15/M5/M2 -    |
//| preco recua ate uma media (ex: MA21 EMA), toca, e volta a favor da |
//| tendencia maior (ex: MA100 SMMA). Seta verde = entrada a favor da  |
//| tendencia. Seta vermelha = entrada a favor de tendencia de baixa.  |
//| X laranja = tendencia quebrou (cautela/saida), preco fechou do     |
//| lado errado da media de tendencia depois de vir do lado certo.     |
//|                                                                    |
//| So visual - nao abre posicao, so identifica o setup pra voce ver.  |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "Compra (toque+retomada)"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "Venda (toque+retomada)"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

#property indicator_label3  "Cautela (tendencia de alta quebrou)"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrOrange
#property indicator_width3  2

#property indicator_label4  "Cautela (tendencia de baixa quebrou)"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrOrange
#property indicator_width4  2

input group "=== Media de toque (a que o preco recua ate) ==="
input int             InpPeriodoToque = 21;       // periodo (padrao: MA21, a rapida/bridge)
input ENUM_MA_METHOD  InpMetodoToque  = MODE_EMA; // 16/07: rapidas viraram EMA

input group "=== Media de tendencia (define o vies maior) ==="
input int             InpPeriodoTendencia = 100;       // periodo (padrao: MA100, bridge medias/longas)
input ENUM_MA_METHOD  InpMetodoTendencia  = MODE_SMMA;

input group "=== Ajuste visual ==="
input double InpOffsetATRPct = 15.0; // % do range da vela pra afastar a seta do preco

double BufCompra[], BufVenda[], BufCautelaAlta[], BufCautelaBaixa[];
int h_toque, h_tendencia;

int OnInit()
{
   SetIndexBuffer(0, BufCompra, INDICATOR_DATA);
   SetIndexBuffer(1, BufVenda, INDICATOR_DATA);
   SetIndexBuffer(2, BufCautelaAlta, INDICATOR_DATA);
   SetIndexBuffer(3, BufCautelaBaixa, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // seta pra cima
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // seta pra baixo
   PlotIndexSetInteger(2, PLOT_ARROW, 251); // X
   PlotIndexSetInteger(3, PLOT_ARROW, 251); // X

   for(int i = 0; i < 4; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   h_toque     = iMA(_Symbol, _Period, InpPeriodoToque, 0, InpMetodoToque, PRICE_CLOSE);
   h_tendencia = iMA(_Symbol, _Period, InpPeriodoTendencia, 0, InpMetodoTendencia, PRICE_CLOSE);

   if(h_toque == INVALID_HANDLE || h_tendencia == INVALID_HANDLE)
   {
      Print("TRIVIUM_TOQUE_TENDENCIA: erro ao criar medias, ", GetLastError());
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_TOQUE_TENDENCIA");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(h_toque);
   IndicatorRelease(h_tendencia);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   int disponivel = MathMin(BarsCalculated(h_toque), BarsCalculated(h_tendencia));
   if(disponivel < 3) return 0;

   double bufToque[], bufTend[];
   ArraySetAsSeries(bufToque, false);
   ArraySetAsSeries(bufTend, false);
   int qtd = MathMin(rates_total, disponivel);
   if(CopyBuffer(h_toque, 0, 0, qtd, bufToque) <= 0) return 0;
   if(CopyBuffer(h_tendencia, 0, 0, qtd, bufTend) <= 0) return 0;

   if(prev_calculated == 0)
   {
      ArrayInitialize(BufCompra, EMPTY_VALUE);
      ArrayInitialize(BufVenda, EMPTY_VALUE);
      ArrayInitialize(BufCautelaAlta, EMPTY_VALUE);
      ArrayInitialize(BufCautelaBaixa, EMPTY_VALUE);
   }

   int start = (prev_calculated > 2) ? prev_calculated - 2 : 1;

   for(int i = start; i < qtd - 1; i++) // -1: nao avalia a vela ainda formando
   {
      BufCompra[i] = EMPTY_VALUE;
      BufVenda[i] = EMPTY_VALUE;
      BufCautelaAlta[i] = EMPTY_VALUE;
      BufCautelaBaixa[i] = EMPTY_VALUE;

      double offset = (high[i] - low[i]) * InpOffsetATRPct / 100.0;
      if(offset <= 0) offset = _Point * 10;

      bool tendenciaAlta  = close[i] > bufTend[i];
      bool tendenciaBaixa = close[i] < bufTend[i];
      bool velaAlta = close[i] > open[i];
      bool velaBaixa = close[i] < open[i];

      // toque + retomada a favor da tendencia
      bool tocouDeCima = low[i] <= bufToque[i] && close[i] > bufToque[i];
      bool tocouDeBaixo = high[i] >= bufToque[i] && close[i] < bufToque[i];

      if(tendenciaAlta && tocouDeCima && velaAlta)
         BufCompra[i] = low[i] - offset;

      if(tendenciaBaixa && tocouDeBaixo && velaBaixa)
         BufVenda[i] = high[i] + offset;

      // cautela: tendencia mudou de lado da media de tendencia (quebra)
      bool estavaAcimaAntes = close[i-1] > bufTend[i-1];
      bool estavaAbaixoAntes = close[i-1] < bufTend[i-1];

      if(estavaAcimaAntes && tendenciaBaixa)
         BufCautelaAlta[i] = high[i] + offset;

      if(estavaAbaixoAntes && tendenciaAlta)
         BufCautelaBaixa[i] = low[i] - offset;
   }

   return qtd;
}
//+------------------------------------------------------------------+
