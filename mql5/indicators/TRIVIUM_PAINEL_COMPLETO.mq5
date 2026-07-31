//+------------------------------------------------------------------+
//| TRIVIUM_PAINEL_COMPLETO.mq5                                       |
//| TRIVIUM369 (c) 2026 - Pedrinho, 15/07/2026                        |
//|                                                                    |
//| Indicador UNICO juntando as ferramentas visuais que o Ronei mais   |
//| usa, pra nao precisar rodar 4-5 scripts separados toda vez:        |
//|  - VWAP (linha, atualiza a cada vela - leve)                       |
//|  - Volume Anomalo (seta, atualiza a cada vela - leve)              |
//|  - PDH/PDL (maxima/minima do dia anterior - objeto, 1x/dia)        |
//|  - Preco Cheio (grid redondo, ex 500 em 500 no GOLD - objeto,      |
//|    1x/dia, versao SIMPLES sem a analise de toque/rompimento -      |
//|    isso fica so no script TRIVIUM_PRECO_REDONDO, mais pesado)      |
//|  - S/R fractal multi-timeframe (M1 a D1 - objeto, 1x/dia)          |
//|                                                                    |
//| Os itens "objeto" (PDH/PDL, preco cheio, S/R) so recalculam quando |
//| fecha uma vela D1 nova - fazer isso a cada tick travaria o grafico |
//| sem necessidade, ja que esses niveis nao mudam durante o dia.      |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMagenta
#property indicator_width1  2
#property indicator_style1  STYLE_SOLID

#property indicator_label2  "Volume Anomalo"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrFuchsia
#property indicator_width2  2

// ---- VWAP / Volume Anomalo ----
input int    InpJanelaMediaVol = 20;   // velas pra tras pra media de volume
input double InpFatorVolAlto   = 2.5;  // volume >= media x fator = anomalo

// ---- PDH/PDL ----
input bool   InpMostrarPDHPDL  = true;
input color  InpCorPDH_Dia     = clrOrange;
input color  InpCorPDH_Semana  = clrDarkOrange;

// ---- Preco Cheio ----
input bool   InpMostrarPrecoCheio = true;
input double InpPassoGrande       = 0;    // 0 = auto (~50x ordem de grandeza, da 500 no GOLD)
input color  InpCorPrecoCheio     = clrMediumOrchid;
input int    InpLarguraPrecoCheio = 2;
input int    InpGrandeQtdAcima    = 3;
input int    InpGrandeQtdAbaixo   = 3;

// ---- S/R fractal multi-timeframe ----
input bool   InpMostrarSR      = true;
input int    InpBarrasAnaliseSR = 200;
input int    InpFractalAsasSR   = 5;
input int    InpMaxNiveisPorTF  = 5;
input double InpTolerancaPctSR  = 0.10;

#define PREFIXO "TRIVIUM_PAINEL_"

double BufVWAP[];
double BufVolAnomalo[];
datetime g_ultimoDiaProcessado = 0;

int OnInit()
{
   SetIndexBuffer(0, BufVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufVolAnomalo, INDICATOR_DATA);
   PlotIndexSetInteger(1, PLOT_ARROW, 174);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_PAINEL_COMPLETO");
   g_ultimoDiaProcessado = 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nome = ObjectName(0, i, 0, -1);
      if(StringFind(nome, PREFIXO) == 0)
         ObjectDelete(0, nome);
   }
}

//+------------------------------------------------------------------+
//| VWAP + Volume Anomalo - recalcula a cada vela (leve)               |
//+------------------------------------------------------------------+
void CalcularVWAP(const int rates_total, const int prev_calculated, const datetime &time[],
                   const double &high[], const double &low[], const double &close[], const long &tick_volume[])
{
   if(prev_calculated == 0) ArrayInitialize(BufVWAP, EMPTY_VALUE);

   int start = (prev_calculated > 1) ? prev_calculated - 2 : 0;
   int inicioDia = start;
   for(int i = start; i >= 0; i--)
   {
      MqlDateTime dt; TimeToStruct(time[i], dt);
      MqlDateTime dtRef; TimeToStruct(time[start], dtRef);
      if(dt.day != dtRef.day || dt.mon != dtRef.mon || dt.year != dtRef.year) { inicioDia = i + 1; break; }
      inicioDia = i;
   }

   double somaPV = 0, somaV = 0;
   for(int i = inicioDia; i < rates_total; i++)
   {
      if(i == inicioDia) { somaPV = 0; somaV = 0; }
      else
      {
         MqlDateTime dt; TimeToStruct(time[i], dt);
         MqlDateTime dtPrev; TimeToStruct(time[i-1], dtPrev);
         if(dt.day != dtPrev.day || dt.mon != dtPrev.mon || dt.year != dtPrev.year) { somaPV = 0; somaV = 0; }
      }
      double precoTipico = (high[i] + low[i] + close[i]) / 3.0;
      double vol = (double)tick_volume[i];
      somaPV += precoTipico * vol;
      somaV  += vol;
      BufVWAP[i] = (somaV > 0) ? somaPV / somaV : precoTipico;
   }
}

void CalcularVolumeAnomalo(const int rates_total, const int prev_calculated,
                            const double &high[], const double &low[], const long &tick_volume[])
{
   if(prev_calculated == 0) ArrayInitialize(BufVolAnomalo, EMPTY_VALUE);
   int start = (prev_calculated > InpJanelaMediaVol) ? prev_calculated - 2 : InpJanelaMediaVol;

   for(int i = start; i < rates_total; i++)
   {
      if(i < InpJanelaMediaVol) { BufVolAnomalo[i] = EMPTY_VALUE; continue; }
      double somaVol = 0;
      for(int j = 1; j <= InpJanelaMediaVol; j++) somaVol += (double)tick_volume[i-j];
      double media = somaVol / InpJanelaMediaVol;
      BufVolAnomalo[i] = (media > 0 && tick_volume[i] >= media * InpFatorVolAlto)
         ? high[i] + (high[i] - low[i]) * 0.3 : EMPTY_VALUE;
   }
}

//+------------------------------------------------------------------+
//| PDH/PDL - so 1x por dia                                            |
//+------------------------------------------------------------------+
void DesenharNivelSimples(string nome, double preco, color cor, int largura, int estilo, string texto, string tooltip)
{
   ObjectCreate(0, nome, OBJ_HLINE, 0, 0, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_STYLE, estilo);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, largura);
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
   ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetString(0, nome, OBJPROP_TOOLTIP, tooltip);
}

void AtualizarPDHPDL()
{
   MqlRates ratesD1[];
   ArraySetAsSeries(ratesD1, true);
   if(CopyRates(_Symbol, PERIOD_D1, 0, 3, ratesD1) < 2) return;

   DesenharNivelSimples(PREFIXO+"PDH", ratesD1[1].high, InpCorPDH_Dia, 2, STYLE_SOLID,
      "PDH: "+DoubleToString(ratesD1[1].high,_Digits),
      "MAXIMA DO DIA ANTERIOR (PDH)\nResistencia intradiaria classica.");
   DesenharNivelSimples(PREFIXO+"PDL", ratesD1[1].low, InpCorPDH_Dia, 2, STYLE_SOLID,
      "PDL: "+DoubleToString(ratesD1[1].low,_Digits),
      "MINIMA DO DIA ANTERIOR (PDL)\nSuporte intradiario classico.");

   MqlRates ratesW1[];
   ArraySetAsSeries(ratesW1, true);
   if(CopyRates(_Symbol, PERIOD_W1, 0, 3, ratesW1) >= 2)
   {
      DesenharNivelSimples(PREFIXO+"PWH", ratesW1[1].high, InpCorPDH_Semana, 1, STYLE_DASH,
         "PWH: "+DoubleToString(ratesW1[1].high,_Digits), "MAXIMA DA SEMANA ANTERIOR");
      DesenharNivelSimples(PREFIXO+"PWL", ratesW1[1].low, InpCorPDH_Semana, 1, STYLE_DASH,
         "PWL: "+DoubleToString(ratesW1[1].low,_Digits), "MINIMA DA SEMANA ANTERIOR");
   }
}

//+------------------------------------------------------------------+
//| Preco Cheio - versao simples, so 1x por dia                        |
//+------------------------------------------------------------------+
double CalcularPassoGrandeAuto(double precoRef)
{
   double ordem = MathPow(10, MathFloor(MathLog10(precoRef)) - 2);
   if(ordem <= 0) ordem = _Point * 10;
   return ordem * 50.0;
}

void AtualizarPrecoCheio()
{
   double precoAtual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(precoAtual <= 0) return;
   double passoGrande = (InpPassoGrande > 0) ? InpPassoGrande : CalcularPassoGrandeAuto(precoAtual);
   double nivelBase = MathRound(precoAtual / passoGrande) * passoGrande;

   for(int i = -InpGrandeQtdAbaixo; i <= InpGrandeQtdAcima; i++)
   {
      double nivel = nivelBase + i * passoGrande;
      if(nivel <= 0) continue;
      string nome = StringFormat("%sCHEIO_%s", PREFIXO, DoubleToString(nivel, _Digits));
      DesenharNivelSimples(nome, nivel, InpCorPrecoCheio, InpLarguraPrecoCheio, STYLE_SOLID,
         "PRECO CHEIO: "+DoubleToString(nivel,_Digits),
         "PRECO REDONDO (nivel psicologico maior)\nPreco: "+DoubleToString(nivel,_Digits)+
         "\nPra historico detalhado de toques/rompimentos, rode o script TRIVIUM_PRECO_REDONDO.");
   }
}

//+------------------------------------------------------------------+
//| S/R fractal multi-timeframe - so 1x por dia (mais pesado)          |
//+------------------------------------------------------------------+
struct TFDefSR { ENUM_TIMEFRAMES tf; string nome; color cor; int largura; };

void ColetarNiveisSR(ENUM_TIMEFRAMES tf, bool topos, double &niveis[], int &total)
{
   total = 0;
   ArrayResize(niveis, 0);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copiados = CopyRates(_Symbol, tf, 0, InpBarrasAnaliseSR, rates);
   if(copiados < InpFractalAsasSR * 2 + 1) return;

   for(int i = InpFractalAsasSR; i < copiados - InpFractalAsasSR; i++)
   {
      bool confirma = true;
      for(int j = 1; j <= InpFractalAsasSR; j++)
      {
         if(topos) { if(rates[i].high < rates[i-j].high || rates[i].high < rates[i+j].high) { confirma = false; break; } }
         else      { if(rates[i].low  > rates[i-j].low  || rates[i].low  > rates[i+j].low)  { confirma = false; break; } }
      }
      if(!confirma) continue;

      double novoNivel = topos ? rates[i].high : rates[i].low;
      double tolerancia = novoNivel * InpTolerancaPctSR / 100.0;
      bool fundiu = false;
      for(int k = 0; k < total; k++)
         if(MathAbs(niveis[k] - novoNivel) <= tolerancia) { niveis[k] = (niveis[k]+novoNivel)/2.0; fundiu = true; break; }
      if(!fundiu && total < InpMaxNiveisPorTF)
      {
         ArrayResize(niveis, total + 1);
         niveis[total] = novoNivel;
         total++;
      }
   }
}

void DesenharNiveisSR(double &niveis[], int total, string sufixo, string nomeTF, color cor, int estilo, int largura)
{
   bool ehSuporte = (StringFind(sufixo, "_SUP") >= 0);
   string tipo = ehSuporte ? "SUPORTE" : "RESISTENCIA";
   for(int i = 0; i < total; i++)
   {
      string nome = StringFormat("%sSR%s_%d", PREFIXO, sufixo, i);
      DesenharNivelSimples(nome, niveis[i], cor, largura, estilo,
         StringFormat("%s %s: %s", nomeTF, tipo, DoubleToString(niveis[i], _Digits)),
         StringFormat("%s de %s\nPreco: %s", tipo, nomeTF, DoubleToString(niveis[i], _Digits)));
   }
}

void AtualizarSR()
{
   color corBronze = C'205,127,50';
   TFDefSR tfs[7] = {
      {PERIOD_M1,  "M1",  clrWhite,   1},
      {PERIOD_M2,  "M2",  clrYellow,  1},
      {PERIOD_M5,  "M5",  clrRed,     1},
      {PERIOD_M15, "M15", clrGold,    2},
      {PERIOD_H1,  "H1",  corBronze,  2},
      {PERIOD_H4,  "H4",  clrSilver,  3},
      {PERIOD_D1,  "D1",  clrDimGray, 3}
   };
   for(int t = 0; t < 7; t++)
   {
      double niveisSuporte[], niveisResist[];
      int totalSuporte, totalResist;
      ColetarNiveisSR(tfs[t].tf, false, niveisSuporte, totalSuporte);
      ColetarNiveisSR(tfs[t].tf, true,  niveisResist,  totalResist);
      DesenharNiveisSR(niveisSuporte, totalSuporte, tfs[t].nome+"_SUP", tfs[t].nome, tfs[t].cor, STYLE_SOLID, tfs[t].largura);
      DesenharNiveisSR(niveisResist,  totalResist,  tfs[t].nome+"_RES", tfs[t].nome, tfs[t].cor, STYLE_DASH,  tfs[t].largura);
   }
}

//+------------------------------------------------------------------+
//| Remove so os objetos que dependem de recalculo diario (PDH/PDL,    |
//| preco cheio, SR) - VWAP/Volume Anomalo sao buffers, nao objetos.   |
//+------------------------------------------------------------------+
void RemoverObjetosDiarios()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nome = ObjectName(0, i, 0, -1);
      if(StringFind(nome, PREFIXO) == 0)
         ObjectDelete(0, nome);
   }
}

void AtualizarObjetosDiarios()
{
   RemoverObjetosDiarios();
   if(InpMostrarPDHPDL)     AtualizarPDHPDL();
   if(InpMostrarPrecoCheio) AtualizarPrecoCheio();
   if(InpMostrarSR)         AtualizarSR();
   ChartRedraw(0);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   // BufVWAP/BufVolAnomalo ficam em modo cronologico (default), igual time[]/high[]/
   // low[]/tick_volume[] do OnCalculate - NAO usar ArraySetAsSeries aqui, senao os
   // indices dos buffers ficam desalinhados com os das series de preco/tempo.
   CalcularVWAP(rates_total, prev_calculated, time, high, low, close, tick_volume);
   CalcularVolumeAnomalo(rates_total, prev_calculated, high, low, tick_volume);

   datetime hoje = iTime(_Symbol, PERIOD_D1, 0);
   if(hoje != g_ultimoDiaProcessado)
   {
      g_ultimoDiaProcessado = hoje;
      AtualizarObjetosDiarios();
   }

   return rates_total;
}
//+------------------------------------------------------------------+
