//+------------------------------------------------------------------+
//| TRIVIUM_PAINEL_TEXTUAL.mq5                                        |
//| TRIVIUM369 (c) 2026 - Pedrinho, 17/07/2026                        |
//|                                                                    |
//| Item do roadmap "painel textual de contexto": um resumo em         |
//| PALAVRAS do que o gráfico está dizendo agora, sem precisar juntar  |
//| visualmente varios indicadores na cabeca - viés (VWAP), tendência  |
//| (médias 21/100), força (ADX/DI), tudo num texto só.                |
//|                                                                    |
//| So visual/informativo, nao abre posicao.                           |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input int    InpPeriodoRapido    = 21;   // MA rapida (EMA) pro vies de tendencia
input int    InpPeriodoTendencia = 100;  // MA de tendencia (SMMA)
input int    InpADXPeriod        = 14;
input color  InpCorTexto         = clrWhite;
input int    InpFonteTamanho     = 9;
input int    InpXDistancia       = 5;
input int    InpYDistancia       = 20;

#define PAINEL_NOME "TRIVIUM_PAINEL_TEXTUAL"

int h_ma_rapida, h_ma_tendencia, h_adx;
double g_vwap_soma_pv = 0, g_vwap_soma_v = 0;
datetime g_vwap_dia_atual = 0;

int OnInit()
{
   h_ma_rapida    = iMA(_Symbol, _Period, InpPeriodoRapido, 0, MODE_EMA, PRICE_CLOSE);
   h_ma_tendencia = iMA(_Symbol, _Period, InpPeriodoTendencia, 0, MODE_SMMA, PRICE_CLOSE);
   h_adx          = iADX(_Symbol, _Period, InpADXPeriod);

   if(h_ma_rapida == INVALID_HANDLE || h_ma_tendencia == INVALID_HANDLE || h_adx == INVALID_HANDLE)
   {
      Print("TRIVIUM_PAINEL_TEXTUAL: erro ao criar handles, ", GetLastError());
      return INIT_FAILED;
   }

   ObjectCreate(0, PAINEL_NOME, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_XDISTANCE, InpXDistancia);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_YDISTANCE, InpYDistancia);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_FONTSIZE, InpFonteTamanho);
   ObjectSetString(0, PAINEL_NOME, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_COLOR, InpCorTexto);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_BACK, false);

   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_PAINEL_TEXTUAL");
   EventSetTimer(2);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectDelete(0, PAINEL_NOME);
}

// VWAP simples, reinicia por dia (mesma logica do TRIVIUM_VWAP.mq5)
double CalcularVWAP()
{
   datetime hoje = iTime(_Symbol, PERIOD_D1, 0);
   int barras = Bars(_Symbol, _Period);
   if(barras <= 0) return 0;

   MqlRates rates[];
   int copiado = CopyRates(_Symbol, _Period, 0, MathMin(barras, 500), rates);
   if(copiado <= 0) return 0;

   double somaPV = 0, somaV = 0;
   for(int i = 0; i < copiado; i++)
   {
      if(rates[i].time < hoje) continue;
      double precoTipico = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      somaPV += precoTipico * (double)rates[i].tick_volume;
      somaV  += (double)rates[i].tick_volume;
   }
   if(somaV <= 0) return 0;
   return somaPV / somaV;
}

void AtualizarPainel()
{
   double maRapida[1], maTendencia[1], adxBuf[1], plusDI[1], minusDI[1];
   if(CopyBuffer(h_ma_rapida, 0, 0, 1, maRapida) < 1) return;
   if(CopyBuffer(h_ma_tendencia, 0, 0, 1, maTendencia) < 1) return;
   if(CopyBuffer(h_adx, 0, 0, 1, adxBuf) < 1) return;
   if(CopyBuffer(h_adx, 1, 0, 1, plusDI) < 1) return;
   if(CopyBuffer(h_adx, 2, 0, 1, minusDI) < 1) return;

   double precoAtual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double vwap = CalcularVWAP();

   // Tendencia: preco vs media de tendencia + inclinacao da media rapida
   string tendencia;
   color corTendencia;
   if(precoAtual > maTendencia[0] * 1.0005)
   {
      tendencia = "ALTA";
      corTendencia = clrLimeGreen;
   }
   else if(precoAtual < maTendencia[0] * 0.9995)
   {
      tendencia = "BAIXA";
      corTendencia = clrRed;
   }
   else
   {
      tendencia = "LATERAL";
      corTendencia = clrYellow;
   }

   // Forca da tendencia via ADX
   string forca;
   if(adxBuf[0] >= 35) forca = "MUITO FORTE";
   else if(adxBuf[0] >= 25) forca = "FORTE";
   else if(adxBuf[0] >= 15) forca = "FRACA";
   else forca = "SEM TENDENCIA (mercado lateral/ruido)";

   string direcaoDI = (plusDI[0] > minusDI[0]) ? "compradores no controle" : "vendedores no controle";

   // Vies VWAP
   string viesVwap = "sem dado";
   if(vwap > 0)
   {
      double distPct = (precoAtual - vwap) / vwap * 100.0;
      if(distPct > 0.02)
         viesVwap = StringFormat("ACIMA da VWAP (+%.2f%%) - viés comprador do dia", distPct);
      else if(distPct < -0.02)
         viesVwap = StringFormat("ABAIXO da VWAP (%.2f%%) - viés vendedor do dia", distPct);
      else
         viesVwap = "NA VWAP - equilibrio, sem viés claro";
   }

   // Resumo motor - so combina os fatores acima em uma frase
   string resumo;
   if(tendencia == "ALTA" && adxBuf[0] >= 25 && plusDI[0] > minusDI[0])
      resumo = "Favorece COMPRA (tendência de alta forte, compradores no controle)";
   else if(tendencia == "BAIXA" && adxBuf[0] >= 25 && minusDI[0] > plusDI[0])
      resumo = "Favorece VENDA (tendência de baixa forte, vendedores no controle)";
   else if(adxBuf[0] < 15)
      resumo = "EVITAR entrada de tendência - mercado sem direção clara";
   else
      resumo = "Sinal misto - tendência e força não concordam, cautela";

   string texto = StringFormat(
      "=== %s %s ===\nTendência: %s (ADX %.1f, %s)\n%s\n%s",
      _Symbol, EnumToString((ENUM_TIMEFRAMES)_Period),
      tendencia, adxBuf[0], forca,
      viesVwap,
      resumo);

   ObjectSetString(0, PAINEL_NOME, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_COLOR, corTendencia);
   ChartRedraw(0);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   AtualizarPainel();
   return rates_total;
}

void OnTimer()
{
   AtualizarPainel();
}
//+------------------------------------------------------------------+
