//+------------------------------------------------------------------+
//|                                              EA_FRANKENSTEIN.mq5 |
//|  TRIVIUM369 - v2.0 MULTI-SYMBOL + VORTEX_MTF_ANTECIPADOR        |
//|                                                                    |
//|  - Opera EURUSD-T, BTCUSD-T, ETHUSD-T no mesmo grafico           |
//|  - Gatilho de entrada: VORTEX_MTF_ANTECIPADOR (6 camadas)        |
//|  - Regime: votacao de 9 variaveis por simbolo                    |
//|  - Reversao automatica de regime se taxa de acerto cair          |
//|  - Validacao Monte Carlo periodica                               |
//|  - Saida por multiplos de R, adaptativa ao regime                |
//|  - Guardrails: spread, perda dia/semana, perdas consecutivas     |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 - Ronei Rosar"
#property version   "2.00"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS GLOBAIS                                                    |
//+------------------------------------------------------------------+
input string InpSymbols           = "EURUSD-T,BTCUSD-T,ETHUSD-T"; // Simbolos (separados por virgula)
input ENUM_TIMEFRAMES InpTF       = PERIOD_H1;   // Timeframe de analise
input double InpRiskPct           = 1.0;         // Risco % por trade
input double InpMaxDrawdownPct    = 10.0;        // Nivel 1: drawdown maximo %
input double InpSharpeMinimo      = 0.8;         // Nivel 2: Sharpe minimo (50 trades)
input double InpSpreadMaxPips     = 2.5;         // Guardrail: spread maximo (pips)
input double InpATRMultSL         = 1.5;         // Stop = ATR x este fator
input int    InpAutoavalTrades    = 50;          // Autoavaliacao a cada N trades
input int    InpMinAmostra        = 30;          // Amostra minima p/ metricas agirem
input double InpMargemVotacao     = 1.0;         // Margem minima entre scores de regime
input double InpMaxPerdaDiaPct    = 3.0;         // Perda maxima no dia (% saldo)
input double InpMaxPerdaSemanaPct = 6.0;         // Perda maxima na semana (% saldo)
input int    InpMaxPerdasSeq      = 4;           // Perdas consecutivas -> pausa
input int    InpPausaHoras        = 6;           // Horas de pausa apos perdas consecutivas
input int    InpHoraInicio        = 7;           // Hora inicio operacao (servidor)
input int    InpHoraFim           = 21;          // Hora fim operacao (servidor)
input bool   InpLogCSV            = true;        // Gravar CSVs (Common\Files\TRIVIUM369)
input long   InpMagic             = 200004;      // Magic base (EURUSD-T); BTC+10, ETH+20

//--- INPUTS DO VORTEX_MTF_ANTECIPADOR (gatilho de entrada)
input int    Inp_WPR_Period        = 14;          // VORTEX: WPR Period
input double Inp_WPR_OB_Level      = -20.0;       // VORTEX: WPR Overbought Level
input double Inp_WPR_OS_Level      = -80.0;       // VORTEX: WPR Oversold Level
input double Inp_WPR_Pivot         = -50.0;       // VORTEX: WPR Pivot / Neutro
input int    Inp_RSI_Period        = 7;           // VORTEX: RSI Period
input double Inp_RSI_OB_Level      = 70.0;        // VORTEX: RSI Overbought
input double Inp_RSI_OS_Level      = 30.0;        // VORTEX: RSI Oversold
input int    Inp_ATR_Period        = 14;          // VORTEX: ATR Period
input double Inp_ATR_Breakout_Factor = 1.5;       // VORTEX: ATR Breakout Factor
input int    Inp_Divergence_Bars   = 20;          // VORTEX: Barras p/ divergencia
input bool   Inp_Use_MTF_Filter    = true;        // VORTEX: Usar filtro MTF?
input ENUM_TIMEFRAMES Inp_MTF_Trend  = PERIOD_H1; // VORTEX: TF tendencia
input ENUM_TIMEFRAMES Inp_MTF_Entry  = PERIOD_M15;// VORTEX: TF entrada

//--- reversao automatica de regime (herdado do CLAUDIO)
input int    InpRegimeAvaliarTrades = 5;     // avalia apos N trades fechados no regime atual
input double InpRegimeWinRateMin    = 40.0;  // % minima de acerto pra manter o regime
input int    InpRegimeBloqueioHoras = 10;    // horas bloqueado apos reversao

//--- validacao estatistica Monte Carlo (herdado do MARCAO)
input int    InpMCTrades         = 50;     // trades usados na janela do MC
input int    InpMCSims           = 200;    // numero de simulacoes bootstrap
input double InpMCMaxNegPct      = 10.0;   // % max de cenarios negativos tolerado

//+------------------------------------------------------------------+
//| ESTRUTURA DE DADOS POR SIMBOLO                                    |
//+------------------------------------------------------------------+
struct SSymbolData
{
   string   symbol;
   long     magic;

   // Handles
   int      hADX, hEMA20, hEMA50, hATR, hBands;
   int      hEMA20_M15, hEMA50_M15;
   int      hVortex;

   // Regime
   string   regimeAtual;
   string   regimeAnterior;
   bool     naoOperar;
   double   sizeMultiplier;
   double   equityPico;

   // TP tracking
   bool     tp1Feito, tp2Feito, tp3Feito;
   double   riscoR;
   string   regimeNaEntrada;

   // Reversao de regime (Claudio)
   int      tradesNoRegime;
   int      winsNoRegime;
   string   regimeBloqueado;
   datetime regimeBloqueadoAte;

   // Scores
   double   gScoreTend, gScoreComp, gScoreExp;

   // Monte Carlo
   int      dealsFechadosAntesMC;

   // Pausa local
   datetime tsPausaAte;
   int      falhasExecucaoSeq;
};

SSymbolData symData[];
CTrade      trade;
datetime    lastBarTime = 0;
int         totalSymbols = 0;

// Metricas globais (hierarquia)
double   equityPicoGlobal = 0.0;
bool     modoObservacao = false;
double   sizeMultiplierGlobal = 1.0;

// Monte Carlo global
int      dealsFechadosAntesMCGlobal = 0;
bool     mcAprovado = true;

// Autoavaliacao
int      dealsFechadosAntesAuto = 0;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // Parse simbolos
   totalSymbols = ParseSymbols(InpSymbols, symData);
   if(totalSymbols == 0)
   {
      Print("[FRANKENSTEIN] Nenhum simbolo valido em: ", InpSymbols);
      return INIT_FAILED;
   }

   ArrayResize(symData, totalSymbols);

   for(int i = 0; i < totalSymbols; i++)
   {
      string sym = symData[i].symbol;
      long   mag = InpMagic + i * 10;

      symData[i].magic   = mag;
      symData[i].regimeAtual    = "INDEFINIDO";
      symData[i].regimeAnterior = "INDEFINIDO";
      symData[i].naoOperar      = false;
      symData[i].sizeMultiplier = 1.0;
      symData[i].equityPico     = AccountInfoDouble(ACCOUNT_EQUITY);
      symData[i].tp1Feito = false;
      symData[i].tp2Feito = false;
      symData[i].tp3Feito = false;
      symData[i].riscoR   = 0.0;
      symData[i].regimeNaEntrada = "";
      symData[i].tradesNoRegime  = 0;
      symData[i].winsNoRegime    = 0;
      symData[i].regimeBloqueado    = "";
      symData[i].regimeBloqueadoAte = 0;
      symData[i].gScoreTend  = 0;
      symData[i].gScoreComp  = 0;
      symData[i].gScoreExp   = 0;
      symData[i].dealsFechadosAntesMC = 0;
      symData[i].tsPausaAte       = 0;
      symData[i].falhasExecucaoSeq = 0;

      // Criar handles
      symData[i].hADX       = iADX(sym, InpTF, 14);
      symData[i].hEMA20     = iMA(sym, InpTF, 20, 0, MODE_EMA, PRICE_CLOSE);
      symData[i].hEMA50     = iMA(sym, InpTF, 50, 0, MODE_EMA, PRICE_CLOSE);
      symData[i].hATR       = iATR(sym, InpTF, 14);
      symData[i].hBands     = iBands(sym, InpTF, 20, 0, 2.0, PRICE_CLOSE);
      symData[i].hEMA20_M15 = iMA(sym, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
      symData[i].hEMA50_M15 = iMA(sym, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);

      // VORTEX como gatilho de entrada (iCustom)
      symData[i].hVortex = iCustom(sym, InpTF, "VORTEX_MTF_ANTECIPADOR",
         Inp_WPR_Period, Inp_WPR_OB_Level, Inp_WPR_OS_Level, Inp_WPR_Pivot,
         Inp_RSI_Period, Inp_RSI_OB_Level, Inp_RSI_OS_Level,
         Inp_ATR_Period, Inp_ATR_Breakout_Factor,
         Inp_Divergence_Bars,
         Inp_Use_MTF_Filter, Inp_MTF_Trend, Inp_MTF_Entry,
         3.0, 1.5,    // ATR_TP_Multiplier, ATR_SL_Multiplier (nao critical p/ sinal)
         10, 15, 11); // Dashboard pos (nao usado no EA)

      // Verificar handles
      if(symData[i].hADX == INVALID_HANDLE || symData[i].hEMA20 == INVALID_HANDLE ||
         symData[i].hEMA50 == INVALID_HANDLE || symData[i].hATR == INVALID_HANDLE ||
         symData[i].hBands == INVALID_HANDLE ||
         symData[i].hEMA20_M15 == INVALID_HANDLE || symData[i].hEMA50_M15 == INVALID_HANDLE ||
         symData[i].hVortex == INVALID_HANDLE)
      {
         PrintFormat("[FRANKENSTEIN] Erro handles para %s (confira se VORTEX_MTF_ANTECIPADOR esta compilado)", sym);
         return INIT_FAILED;
      }

      PrintFormat("[FRANKENSTEIN] %s iniciado. Magic=%lld HandleVortex=%d", sym, mag, symData[i].hVortex);
   }

   equityPicoGlobal = AccountInfoDouble(ACCOUNT_EQUITY);
   dealsFechadosAntesAuto = ContarDealsFechadosTotal();
   dealsFechadosAntesMCGlobal = dealsFechadosAntesAuto;

   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetDeviationInPoints(20);

   Print("[FRANKENSTEIN v2.0] Multi-symbol iniciado com ", totalSymbols, " simbolo(s): ", InpSymbols);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| ParseSymbols: extrai lista de simbolos de string csv             |
//+------------------------------------------------------------------+
int ParseSymbols(string csv, SSymbolData &out[])
{
   string parts[];
   int n = StringSplit(csv, ',', parts);
   if(n <= 0) return 0;

   // Primeira passagem: contar validos
   int count = 0;
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(s != "") count++;
   }
   if(count == 0) return 0;

   ArrayResize(out, count);
   int idx = 0;
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      if(s == "") continue;
      // Garantir que o simbolo existe no MarketWatch
      if(!SymbolSelect(s, true))
      {
         Print("[FRANKENSTEIN] Aviso: ", s, " nao encontrado - tentando mesmo assim");
      }
      out[idx].symbol = s;
      idx++;
   }
   return count;
}

void OnDeinit(const int reason)
{
   for(int i = 0; i < totalSymbols; i++)
   {
      IndicatorRelease(symData[i].hADX);
      IndicatorRelease(symData[i].hEMA20);
      IndicatorRelease(symData[i].hEMA50);
      IndicatorRelease(symData[i].hATR);
      IndicatorRelease(symData[i].hBands);
      IndicatorRelease(symData[i].hEMA20_M15);
      IndicatorRelease(symData[i].hEMA50_M15);
      IndicatorRelease(symData[i].hVortex);
   }
   ArrayFree(symData);
}

//+------------------------------------------------------------------+
//| HELPERS BASICOS                                                   |
//+------------------------------------------------------------------+
double Buf(int handle, int buffer, int shift)
{
   double v[1];
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1) return 0.0;
   return v[0];
}

double PipSizeSym(string sym)
{
   int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return (d == 3 || d == 5) ? 10.0 * SymbolInfoDouble(sym, SYMBOL_POINT) : SymbolInfoDouble(sym, SYMBOL_POINT);
}

double SpreadPipsSym(string sym)
{
   return (SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID)) / PipSizeSym(sym);
}

double VolumeMediaSym(string sym, int barras)
{
   long vols[];
   if(CopyTickVolume(sym, InpTF, 1, barras, vols) < barras) return 0.0;
   double soma = 0;
   for(int i = 0; i < barras; i++) soma += (double)vols[i];
   return soma / barras;
}

double NormalizarLoteSym(string sym, double lots)
{
   double vmin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / vstep) * vstep;
   return MathMin(MathMax(lots, vmin), vmax);
}

double CalcularLoteSym(string sym, double riskPct, double slDistPoints)
{
   if(slDistPoints <= 0) return 0.0;
   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct / 100.0;
   double tickValue  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(tickValue <= 0 || tickSize <= 0) return 0.0;
   double valorPorPontoLote = tickValue * (point / tickSize);
   return NormalizarLoteSym(sym, riskMoney / (slDistPoints * valorPorPontoLote));
}

int ContarDealsFechadosSym(long magic)
{
   HistorySelect(0, TimeCurrent());
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != magic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      n++;
   }
   return n;
}

int ContarDealsFechadosTotal()
{
   HistorySelect(0, TimeCurrent());
   int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      long mag = (long)HistoryDealGetInteger(tk, DEAL_MAGIC);
      // Aceita qualquer magic dentro da faixa dos simbolos
      if(mag >= InpMagic && mag <= InpMagic + (totalSymbols - 1) * 10)
      {
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            n++;
      }
   }
   return n;
}

//+------------------------------------------------------------------+
//| METRICAS (GLOBAIS - agregam todos os simbolos)                   |
//+------------------------------------------------------------------+
int ColetarRetornos(double &rets[], int maxN)
{
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal(), n = 0;
   ArrayResize(rets, 0);
   for(int i = total - 1; i >= 0 && n < maxN; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      long mag = (long)HistoryDealGetInteger(tk, DEAL_MAGIC);
      if(mag < InpMagic || mag > InpMagic + (totalSymbols - 1) * 10) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(tk, DEAL_PROFIT)
               + HistoryDealGetDouble(tk, DEAL_SWAP)
               + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      ArrayResize(rets, n + 1);
      rets[n++] = p;
   }
   return n;
}

double CalcularSharpe(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n < InpMinAmostra) return 999.0;
   double media = 0; for(int i = 0; i < n; i++) media += rets[i]; media /= n;
   double var = 0;   for(int i = 0; i < n; i++) var += MathPow(rets[i] - media, 2); var /= n;
   double desvio = MathSqrt(var);
   return (desvio > 0) ? media / desvio : 0.0;
}

double CalcularProfitFactor(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n < InpMinAmostra) return 999.0;
   double ganho = 0, perda = 0;
   for(int i = 0; i < n; i++) { if(rets[i] > 0) ganho += rets[i]; else perda -= rets[i]; }
   return (perda > 0) ? ganho / perda : 999.0;
}

double CalcularExpectancy(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n < InpMinAmostra) return 999.0;
   double soma = 0; for(int i = 0; i < n; i++) soma += rets[i];
   return soma / n;
}

//+------------------------------------------------------------------+
//| SECAO 1: VOTACAO DE 9 VARIAVEIS (por simbolo)                    |
//+------------------------------------------------------------------+
double AnalisarEstruturaSym(string sym)
{
   double h1 = iHigh(sym, InpTF, 1),  h2 = iHigh(sym, InpTF, 6),  h3 = iHigh(sym, InpTF, 12);
   double l1 = iLow(sym, InpTF, 1),   l2 = iLow(sym, InpTF, 6),   l3 = iLow(sym, InpTF, 12);
   bool altaHH = (h1 > h2 && h2 > h3), altaHL = (l1 > l2 && l2 > l3);
   bool baixaLH = (h1 < h2 && h2 < h3), baixaLL = (l1 < l2 && l2 < l3);
   if((altaHH && altaHL) || (baixaLH && baixaLL)) return 1.0;
   if(altaHH || altaHL || baixaLH || baixaLL) return 0.5;
   return 0.0;
}

double CorrelacaoTFsSym(int hEMA20_handle, int hEMA50_handle, int hEMA20_M15_handle, int hEMA50_M15_handle)
{
   double dH1  = Buf(hEMA20_handle, 0, 1) - Buf(hEMA50_handle, 0, 1);
   double dM15 = Buf(hEMA20_M15_handle, 0, 1) - Buf(hEMA50_M15_handle, 0, 1);
   if(dH1 == 0 || dM15 == 0) return 0.5;
   return (dH1 * dM15 > 0) ? 1.0 : 0.0;
}

double ATRMedioSym(int hATR_handle, int barras)
{
   double atrs[];
   if(CopyBuffer(hATR_handle, 0, 1, barras, atrs) < barras) return 0.0;
   double soma = 0; for(int i = 0; i < barras; i++) soma += atrs[i];
   return soma / barras;
}

void DetectarRegimeVotacaoSym(int idx)
{
   double adx = Buf(symData[idx].hADX, 0, 1);
   double vAdx = (adx > 25) ? 1.0 : (adx > 20) ? 0.5 : 0.0;

   double ema20 = Buf(symData[idx].hEMA20, 0, 1), ema50 = Buf(symData[idx].hEMA50, 0, 1);
   double slope = (ema50 > 0) ? (ema20 - ema50) / ema50 : 0.0;
   double vSlope = (MathAbs(slope) > 0.0005) ? 1.0 : 0.0;

   double atr   = Buf(symData[idx].hATR, 0, 1);
   double atrMed = ATRMedioSym(symData[idx].hATR, 100);
   double vAtr  = (atrMed > 0 && atr > atrMed * 1.3) ? 1.0 : 0.0;

   double volMa = VolumeMediaSym(symData[idx].symbol, 20);
   double vVol  = ((double)iVolume(symData[idx].symbol, InpTF, 1) > volMa) ? 1.0 : 0.0;

   double close1 = iClose(symData[idx].symbol, InpTF, 1);
   double bbW = (close1 > 0) ? (Buf(symData[idx].hBands, 1, 1) - Buf(symData[idx].hBands, 2, 1)) / close1 : 0.0;
   double vBB = (bbW < 0.004) ? 1.0 : 0.0;

   double vEstrutura = AnalisarEstruturaSym(symData[idx].symbol);
   double vCorrel    = CorrelacaoTFsSym(symData[idx].hEMA20, symData[idx].hEMA50, symData[idx].hEMA20_M15, symData[idx].hEMA50_M15);
   double vSpread    = (SpreadPipsSym(symData[idx].symbol) < InpSpreadMaxPips) ? 1.0 : 0.0;
   double vVolatil   = (close1 > 0 && atr / close1 > 0.003) ? 1.0 : 0.0;

   double scoreTendencia  = vAdx + vSlope + vVol + vEstrutura + vCorrel;
   double scoreCompressao = vBB * 2.0 + (1.0 - vVolatil) + (1.0 - vAdx);
   double scoreExpansao   = vVolatil + vAtr;
   symData[idx].gScoreTend = scoreTendencia;
   symData[idx].gScoreComp = scoreCompressao;
   symData[idx].gScoreExp  = scoreExpansao;

   double maxScore = MathMax(scoreTendencia, MathMax(scoreCompressao, scoreExpansao));
   double segundo = scoreTendencia + scoreCompressao + scoreExpansao - maxScore
                  - MathMin(scoreTendencia, MathMin(scoreCompressao, scoreExpansao));
   string candidato;
   if(maxScore - segundo < InpMargemVotacao)
      candidato = "INDEFINIDO";
   else if(maxScore == scoreTendencia  && scoreTendencia >= 3.0)
      candidato = "TENDENCIA";
   else if(maxScore == scoreCompressao && scoreCompressao >= 2.5)
      candidato = "COMPRESSAO";
   else if(maxScore == scoreExpansao   && scoreExpansao >= 2.0)
      candidato = "EXPANSAO";
   else
      candidato = "INDEFINIDO";

   // Aplicar regime
   if(candidato == symData[idx].regimeAtual) return;

   if(candidato == symData[idx].regimeBloqueado && TimeCurrent() < symData[idx].regimeBloqueadoAte)
      return;

   LogEventoIdx(idx, "REGIME", "Mudanca " + symData[idx].regimeAtual + " -> " + candidato +
                " (T=" + DoubleToString(symData[idx].gScoreTend, 1) +
                " C=" + DoubleToString(symData[idx].gScoreComp, 1) +
                " E=" + DoubleToString(symData[idx].gScoreExp, 1) + ")");

   symData[idx].regimeAnterior = symData[idx].regimeAtual;
   symData[idx].regimeAtual    = candidato;
   symData[idx].tradesNoRegime = 0;
   symData[idx].winsNoRegime   = 0;
}

//+------------------------------------------------------------------+
//| HIERARQUIA GLOBAL                                                 |
//+------------------------------------------------------------------+
bool AplicarHierarquia()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > equityPicoGlobal) equityPicoGlobal = eq;
   double dd = (equityPicoGlobal > 0) ? (equityPicoGlobal - eq) / equityPicoGlobal : 0.0;
   if(dd > InpMaxDrawdownPct / 100.0)
   {
      if(!modoObservacao) Print("[HIERARQUIA] Nivel 1 FALHOU: drawdown > ", InpMaxDrawdownPct, "% - PAUSA");
      modoObservacao = true;
      return false;
   }

   double sharpe = CalcularSharpe(50);
   if(sharpe < InpSharpeMinimo)
   {
      if(!modoObservacao) PrintFormat("[HIERARQUIA] Nivel 2 FALHOU: Sharpe %.2f < %.2f - modo observacao", sharpe, InpSharpeMinimo);
      modoObservacao = true;
      return false;
   }
   modoObservacao = false;

   double expectancy = CalcularExpectancy(50);
   if(expectancy != 999.0 && expectancy <= 0)
   {
      sizeMultiplierGlobal = 0.5;
      Print("[HIERARQUIA] Nivel 3: expectancy <= 0, position size reduzido 50%");
   }
   else sizeMultiplierGlobal = 1.0;

   return true;
}

//+------------------------------------------------------------------+
//| MONTE CARLO GLOBAL                                                |
//+------------------------------------------------------------------+
void ValidarMonteCarlo()
{
   int fechados = ContarDealsFechadosTotal();
   if(fechados - dealsFechadosAntesMCGlobal < InpMCTrades) return;
   dealsFechadosAntesMCGlobal = fechados;

   double rets[]; int n = ColetarRetornos(rets, InpMCTrades);
   if(n < InpMCTrades / 2) { mcAprovado = true; return; }

   int negativos = 0;
   for(int s = 0; s < InpMCSims; s++)
   {
      double soma = 0;
      for(int t = 0; t < n; t++)
      {
         int idx = MathRand() % n;
         soma += rets[idx];
      }
      if(soma < 0) negativos++;
   }
   double pctNeg = (double)negativos / InpMCSims * 100.0;
   mcAprovado = (pctNeg <= InpMCMaxNegPct);

   PrintFormat("[MONTECARLO] %d simulacoes, %.1f%% negativas (limite %.1f%%) -> %s",
               InpMCSims, pctNeg, InpMCMaxNegPct, mcAprovado ? "APROVADO" : "PAUSADO");
   CsvAppendGlobal("_montecarlo.csv",
      "datetime,symbol,trades_janela,pct_cenarios_negativos,limite,aprovado",
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS) + ",TODOS," +
      IntegerToString(n) + "," + DoubleToString(pctNeg, 1) + "," +
      DoubleToString(InpMCMaxNegPct, 1) + "," + (mcAprovado ? "1" : "0"));
}

//+------------------------------------------------------------------+
//| GUARDRAILS ARQUITETONICAS (por simbolo)                          |
//+------------------------------------------------------------------+
bool GuardrailsArquitetonicasSym(int idx)
{
   if(symData[idx].regimeAtual == "INDEFINIDO" || symData[idx].regimeAtual == "EXPANSAO")
   {
      symData[idx].naoOperar = true;
      return false;
   }

   if(SpreadPipsSym(symData[idx].symbol) > InpSpreadMaxPips)
   {
      symData[idx].naoOperar = true;
      return false;
   }

   symData[idx].naoOperar = false;

   // Autoavaliacao global
   int fechados = ContarDealsFechadosTotal();
   if(fechados - dealsFechadosAntesAuto >= InpAutoavalTrades)
   {
      dealsFechadosAntesAuto = fechados;
      double sharpe  = CalcularSharpe(InpAutoavalTrades);
      double pf      = CalcularProfitFactor(InpAutoavalTrades);
      double expect  = CalcularExpectancy(InpAutoavalTrades);
      double ddAtual = (equityPicoGlobal > 0 ?
                       (equityPicoGlobal - AccountInfoDouble(ACCOUNT_EQUITY)) / equityPicoGlobal * 100.0 : 0.0);
      PrintFormat("[AUTOAVALIACAO] Sharpe=%.2f PF=%.2f Expectancy=%.2f DrawdownAtual=%.1f%%", sharpe, pf, expect, ddAtual);
      if(sharpe < 0.8 || pf < 1.3)
      {
         Print("[GUARDRAIL] Metricas abaixo do minimo - risco reduzido 50%");
         sizeMultiplierGlobal = 0.5;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| GUARDRAILS DE RISCO (por simbolo)                                |
//+------------------------------------------------------------------+
double LucroRealizadoDesdeSym(datetime desde, long magic)
{
   double soma = 0;
   HistorySelect(desde, TimeCurrent());
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != magic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      soma += HistoryDealGetDouble(tk, DEAL_PROFIT)
            + HistoryDealGetDouble(tk, DEAL_SWAP)
            + HistoryDealGetDouble(tk, DEAL_COMMISSION);
   }
   return soma;
}

int PerdasConsecutivasSym(long magic)
{
   HistorySelect(0, TimeCurrent());
   int seq = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != magic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(tk, DEAL_PROFIT);
      if(p < 0) seq++;
      else break;
   }
   return seq;
}

bool GuardrailsRiscoSym(int idx)
{
   if(TimeCurrent() < symData[idx].tsPausaAte) return false;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);

   if(dt.hour < InpHoraInicio || dt.hour >= InpHoraFim) return false;

   double saldo = AccountInfoDouble(ACCOUNT_BALANCE);
   if(saldo <= 0) return false;

   datetime hojeIni = TimeCurrent() - (dt.hour * 3600 + dt.min * 60 + dt.sec);
   double resDia = LucroRealizadoDesdeSym(hojeIni, symData[idx].magic);
   if(resDia / saldo < -InpMaxPerdaDiaPct / 100.0)
   {
      PrintFormat("[GUARDRAIL DIA] %s: Perda do dia excede %.1f%%", symData[idx].symbol, InpMaxPerdaDiaPct);
      return false;
   }

   int diasDesdeSegunda = (dt.day_of_week + 6) % 7;
   datetime semanaIni = hojeIni - (datetime)diasDesdeSegunda * 86400;
   double resSemana = LucroRealizadoDesdeSym(semanaIni, symData[idx].magic);
   if(resSemana / saldo < -InpMaxPerdaSemanaPct / 100.0)
   {
      PrintFormat("[GUARDRAIL SEMANA] %s: Perda semanal excede %.1f%%", symData[idx].symbol, InpMaxPerdaSemanaPct);
      return false;
   }

   if(PerdasConsecutivasSym(symData[idx].magic) >= InpMaxPerdasSeq)
   {
      symData[idx].tsPausaAte = TimeCurrent() + (datetime)InpPausaHoras * 3600;
      PrintFormat("[GUARDRAIL SEQ] %s: %d perdas consecutivas - pausa %dh", symData[idx].symbol, InpMaxPerdasSeq, InpPausaHoras);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| REALIZACAO POR MULTIPLOS DE R (por simbolo)                      |
//+------------------------------------------------------------------+
void RealizarPorMultiplosDeRSym(int idx)
{
   if(!PositionSelect(symData[idx].symbol))
   {
      symData[idx].tp1Feito = false; symData[idx].tp2Feito = false; symData[idx].tp3Feito = false;
      symData[idx].riscoR = 0; symData[idx].regimeNaEntrada = "";
      return;
   }
   if(PositionGetInteger(POSITION_MAGIC) != symData[idx].magic) return;
   if(symData[idx].riscoR <= 0) return;

   bool emTendencia = (symData[idx].regimeNaEntrada != "COMPRESSAO");
   double fracTP1 = emTendencia ? 0.20 : 0.50;
   double fracTP2 = emTendencia ? 0.25 : 1.00;
   double fracTP3 = emTendencia ? 0.33 : 0.00;

   long   tipo  = PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double bid   = SymbolInfoDouble(symData[idx].symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(symData[idx].symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(symData[idx].symbol, SYMBOL_POINT);
   double lucroPoints = (tipo == POSITION_TYPE_BUY) ? (bid - entry) / point : (entry - ask) / point;
   double profitR = lucroPoints / symData[idx].riscoR;
   ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   double vmin   = SymbolInfoDouble(symData[idx].symbol, SYMBOL_VOLUME_MIN);
   double atr    = Buf(symData[idx].hATR, 0, 1);

   if(profitR >= 1.0 && !symData[idx].tp1Feito)
   {
      double vol = PositionGetDouble(POSITION_VOLUME);
      double v = NormalizarLoteSym(symData[idx].symbol, vol * fracTP1);
      if(v >= vmin && vol - v >= vmin && trade.PositionClosePartial(ticket, v))
      {
         trade.PositionModify(ticket, NormalizeDouble(entry, (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)),
                              PositionGetDouble(POSITION_TP));
         PrintFormat("[TP1] %s: 1R alcancado - realiza %.0f%%, stop no breakeven (%s)",
                     symData[idx].symbol, fracTP1 * 100, symData[idx].regimeNaEntrada);
         symData[idx].tp1Feito = true;
      }
   }
   if(profitR >= 2.0 && !symData[idx].tp2Feito && PositionSelect(symData[idx].symbol))
   {
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(fracTP2 >= 1.0)
      {
         if(trade.PositionClose(ticket))
         {
            symData[idx].tp2Feito = true;
            Print("[TP2] ", symData[idx].symbol, ": 2R alcancado - fecha tudo (Compressao)");
            return;
         }
      }
      else
      {
         double v = NormalizarLoteSym(symData[idx].symbol, vol * fracTP2);
         if(v >= vmin && vol - v >= vmin && trade.PositionClosePartial(ticket, v))
         {
            double novoSL = (tipo == POSITION_TYPE_BUY) ? entry + atr : entry - atr;
            trade.PositionModify(ticket, NormalizeDouble(novoSL, (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)),
                                 PositionGetDouble(POSITION_TP));
            PrintFormat("[TP2] %s: 2R alcancado - realiza %.0f%%, stop entry+1ATR", symData[idx].symbol, fracTP2 * 100);
            symData[idx].tp2Feito = true;
         }
      }
   }
   if(profitR >= 3.0 && !symData[idx].tp3Feito && fracTP3 > 0 && PositionSelect(symData[idx].symbol))
   {
      double vol = PositionGetDouble(POSITION_VOLUME);
      double v = NormalizarLoteSym(symData[idx].symbol, vol * fracTP3);
      if(v >= vmin && vol - v >= vmin && trade.PositionClosePartial(ticket, v))
      {
         Print("[TP3] ", symData[idx].symbol, ": 3R alcancado - realiza parcial, trailing runner");
         symData[idx].tp3Feito = true;
      }
   }
   if(symData[idx].tp1Feito && PositionSelect(symData[idx].symbol) && atr > 0)
   {
      double sl = PositionGetDouble(POSITION_SL);
      double novoSL = (tipo == POSITION_TYPE_BUY) ? bid - atr : ask + atr;
      bool melhora = (tipo == POSITION_TYPE_BUY) ? (novoSL > sl) : (sl == 0 || novoSL < sl);
      if(melhora)
      {
         int digits = (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS);
         trade.PositionModify(ticket, NormalizeDouble(novoSL, digits), PositionGetDouble(POSITION_TP));
      }
   }
}

//+------------------------------------------------------------------+
//| EXECUCAO DE ORDENS (por simbolo)                                 |
//+------------------------------------------------------------------+
bool AbrirOrdemSym(int idx, bool isBuy, double lots, double preco, double sl, double tp, string comentario)
{
   trade.SetExpertMagicNumber(symData[idx].magic);

   bool ok = isBuy ? trade.Buy(lots, symData[idx].symbol, preco,
                               NormalizeDouble(sl, (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)),
                               NormalizeDouble(tp, (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)), comentario)
                   : trade.Sell(lots, symData[idx].symbol, preco,
                                NormalizeDouble(sl, (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)),
                                NormalizeDouble(tp, (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)), comentario);
   if(ok)
   {
      symData[idx].falhasExecucaoSeq = 0;
      symData[idx].regimeNaEntrada = symData[idx].regimeAtual;
   }
   else
   {
      symData[idx].falhasExecucaoSeq++;
      PrintFormat("[EXECUCAO] %s: Falha na ordem (%d seguidas): %d - %s",
                  symData[idx].symbol, symData[idx].falhasExecucaoSeq, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      if(symData[idx].falhasExecucaoSeq >= 3)
      {
         symData[idx].tsPausaAte = TimeCurrent() + 3600;
         Print("[GUARDRAIL EXECUCAO] ", symData[idx].symbol, ": 3 falhas seguidas - pausa 1h");
         symData[idx].falhasExecucaoSeq = 0;
      }
   }
   return ok;
}

//+------------------------------------------------------------------+
//| ENTRADA VIA VORTEX (substitui Confluencia_Antecipada)            |
//+------------------------------------------------------------------+
void ProcurarEntradaSym(int idx)
{
   if(PositionSelect(symData[idx].symbol))
   {
      // Ja ha posicao aberta - verificar se e nossa
      if(PositionGetInteger(POSITION_MAGIC) == symData[idx].magic) return;
   }
   if(symData[idx].naoOperar || modoObservacao || !mcAprovado) return;
   if(!GuardrailsRiscoSym(idx)) return;

   double atr = Buf(symData[idx].hATR, 0, 1);
   if(atr <= 0) return;

   // Ler sinal do VORTEX (buffer 0 = compra, buffer 1 = venda)
   double sinalBuy  = Buf(symData[idx].hVortex, 0, 1);
   double sinalSell = Buf(symData[idx].hVortex, 1, 1);
   bool temBuy  = (sinalBuy  < EMPTY_VALUE * 0.9 && sinalBuy  != 0);
   bool temSell = (sinalSell < EMPTY_VALUE * 0.9 && sinalSell != 0);

   double ask = SymbolInfoDouble(symData[idx].symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symData[idx].symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symData[idx].symbol, SYMBOL_POINT);
   double slDist = atr * InpATRMultSL;

   if(temBuy)
   {
      double sl = ask - slDist;
      double tp = ask + slDist * 3.0;
      double lots = CalcularLoteSym(symData[idx].symbol, InpRiskPct * sizeMultiplierGlobal, slDist / point);
      if(lots > 0 && AbrirOrdemSym(idx, true, lots, ask, sl, tp, "FRANK-VORTEX-BUY"))
      {
         symData[idx].riscoR = slDist / point;
         PrintFormat("[ENTRADA VORTEX] %s: BUY nivel %.2f lotes R=%.0f points regime=%s",
                     symData[idx].symbol, lots, symData[idx].riscoR, symData[idx].regimeAtual);
      }
   }
   else if(temSell)
   {
      double sl = bid + slDist;
      double tp = bid - slDist * 3.0;
      double lots = CalcularLoteSym(symData[idx].symbol, InpRiskPct * sizeMultiplierGlobal, slDist / point);
      if(lots > 0 && AbrirOrdemSym(idx, false, lots, bid, sl, tp, "FRANK-VORTEX-SELL"))
      {
         symData[idx].riscoR = slDist / point;
         PrintFormat("[ENTRADA VORTEX] %s: SELL nivel %.2f lotes R=%.0f points regime=%s",
                     symData[idx].symbol, lots, symData[idx].riscoR, symData[idx].regimeAtual);
      }
   }
}

//+------------------------------------------------------------------+
//| LOGS CSV                                                          |
//+------------------------------------------------------------------+
string LogPrefixoSimbolo(string sym)
{
   return "TRIVIUM369\\EA_FRANKENSTEIN_" + sym;
}

void CsvAppend(string arquivo, string cabecalho, string linha)
{
   if(!InpLogCSV) return;
   int h = FileOpen(arquivo, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   if(FileSize(h) == 0) FileWriteString(h, cabecalho + "\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, linha + "\n");
   FileClose(h);
}

void CsvAppendGlobal(string sufixo, string cabecalho, string linha)
{
   string arquivo = "TRIVIUM369\\EA_FRANKENSTEIN" + sufixo;
   CsvAppend(arquivo, cabecalho, linha);
}

void LogEventoIdx(int idx, string categoria, string detalhe)
{
   Print("[", categoria, "] ", symData[idx].symbol, ": ", detalhe);
   CsvAppend(LogPrefixoSimbolo(symData[idx].symbol) + "_eventos.csv",
      "datetime,symbol,categoria,detalhe,regime,saldo,equity",
      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS) + "," +
      symData[idx].symbol + "," + categoria + ",\"" + detalhe + "\"," +
      symData[idx].regimeAtual + "," +
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "," +
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
}

void LogBarraSym(int idx)
{
   if(!InpLogCSV) return;
   double spreadPts = (SymbolInfoDouble(symData[idx].symbol, SYMBOL_ASK) - SymbolInfoDouble(symData[idx].symbol, SYMBOL_BID)) /
                       PipSizeSym(symData[idx].symbol);
   CsvAppend(LogPrefixoSimbolo(symData[idx].symbol) + "_barras.csv",
      "datetime,open,high,low,close,tick_volume,spread_points,adx,ema20,ema50,atr,bb_upper,bb_lower,score_tendencia,score_compressao,score_expansao,regime,size_mult,modo_observacao,nao_operar,mc_aprovado",
      TimeToString(iTime(symData[idx].symbol, InpTF, 1), TIME_DATE | TIME_MINUTES) + "," +
      DoubleToString(iOpen(symData[idx].symbol, InpTF, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(iHigh(symData[idx].symbol, InpTF, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(iLow(symData[idx].symbol, InpTF, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(iClose(symData[idx].symbol, InpTF, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      IntegerToString(iVolume(symData[idx].symbol, InpTF, 1)) + "," +
      DoubleToString(spreadPts, 1) + "," +
      DoubleToString(Buf(symData[idx].hADX, 0, 1), 2) + "," +
      DoubleToString(Buf(symData[idx].hEMA20, 0, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(Buf(symData[idx].hEMA50, 0, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(Buf(symData[idx].hATR, 0, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(Buf(symData[idx].hBands, 1, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(Buf(symData[idx].hBands, 2, 1), (int)SymbolInfoInteger(symData[idx].symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(symData[idx].gScoreTend, 1) + "," +
      DoubleToString(symData[idx].gScoreComp, 1) + "," +
      DoubleToString(symData[idx].gScoreExp, 1) + "," +
      symData[idx].regimeAtual + "," +
      DoubleToString(symData[idx].sizeMultiplier * sizeMultiplierGlobal, 2) + "," +
      (modoObservacao ? "1" : "0") + "," +
      (symData[idx].naoOperar ? "1" : "0") + "," +
      (mcAprovado ? "1" : "0"));
}

//+------------------------------------------------------------------+
//| OnTradeTransaction                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal;
   if(!HistoryDealSelect(deal)) return;

   long dealMagic = HistoryDealGetInteger(deal, DEAL_MAGIC);
   if(dealMagic < InpMagic || dealMagic > InpMagic + (totalSymbols - 1) * 10) return;

   // Encontrar simbolo correspondente
   int idx = -1;
   for(int i = 0; i < totalSymbols; i++)
   {
      if(symData[i].magic == dealMagic) { idx = i; break; }
   }
   if(idx < 0) return;

   bool ehSaida = ((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_OUT);

   if(ehSaida)
   {
      double lucro = HistoryDealGetDouble(deal, DEAL_PROFIT)
                   + HistoryDealGetDouble(deal, DEAL_SWAP)
                   + HistoryDealGetDouble(deal, DEAL_COMMISSION);

      // Reversao automatica de regime (Claudio) - por simbolo
      if(symData[idx].regimeNaEntrada == symData[idx].regimeAtual)
      {
         symData[idx].tradesNoRegime++;
         if(lucro > 0) symData[idx].winsNoRegime++;
         if(symData[idx].tradesNoRegime >= InpRegimeAvaliarTrades)
         {
            double winRate = (double)symData[idx].winsNoRegime / symData[idx].tradesNoRegime * 100.0;
            if(winRate < InpRegimeWinRateMin)
            {
               PrintFormat("[REVERSAO] %s: Regime %s com %.1f%% acerto (<%.1f%%) - revertendo p/ %s por %dh",
                           symData[idx].symbol, symData[idx].regimeAtual, winRate, InpRegimeWinRateMin,
                           symData[idx].regimeAnterior, InpRegimeBloqueioHoras);
               symData[idx].regimeBloqueado    = symData[idx].regimeAtual;
               symData[idx].regimeBloqueadoAte = TimeCurrent() + (datetime)InpRegimeBloqueioHoras * 3600;
               symData[idx].regimeAtual        = symData[idx].regimeAnterior;
            }
            symData[idx].tradesNoRegime = 0; symData[idx].winsNoRegime = 0;
         }
      }
   }

   // Log do trade
   string dealSymbol = HistoryDealGetString(deal, DEAL_SYMBOL);
   CsvAppend(LogPrefixoSimbolo(dealSymbol) + "_trades.csv",
      "datetime,symbol,deal,tipo,entrada,volume,preco,sl,tp,profit,swap,comissao,regime,risco_r_points,comentario,saldo,equity",
      TimeToString((datetime)HistoryDealGetInteger(deal, DEAL_TIME), TIME_DATE | TIME_MINUTES | TIME_SECONDS) + "," +
      dealSymbol + "," +
      IntegerToString((long)deal) + "," +
      EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE)) + "," +
      EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY)) + "," +
      DoubleToString(HistoryDealGetDouble(deal, DEAL_VOLUME), 2) + "," +
      DoubleToString(HistoryDealGetDouble(deal, DEAL_PRICE), (int)SymbolInfoInteger(dealSymbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(HistoryDealGetDouble(deal, DEAL_SL), (int)SymbolInfoInteger(dealSymbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(HistoryDealGetDouble(deal, DEAL_TP), (int)SymbolInfoInteger(dealSymbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(HistoryDealGetDouble(deal, DEAL_PROFIT), 2) + "," +
      DoubleToString(HistoryDealGetDouble(deal, DEAL_SWAP), 2) + "," +
      DoubleToString(HistoryDealGetDouble(deal, DEAL_COMMISSION), 2) + "," +
      symData[idx].regimeNaEntrada + "," +
      DoubleToString(symData[idx].riscoR, 0) + ",\"" +
      HistoryDealGetString(deal, DEAL_COMMENT) + "\"," +
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "," +
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
}

//+------------------------------------------------------------------+
//| OnTick - loop por todos os simbolos                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Gerenciamento de saidas: para cada simbolo com posicao
   for(int i = 0; i < totalSymbols; i++)
   {
      RealizarPorMultiplosDeRSym(i);
   }

   // Processar nova barra (usar o primeiro simbolo como referencia de tempo)
   string refSym = symData[0].symbol;
   datetime barTime = iTime(refSym, InpTF, 0);
   if(barTime == lastBarTime) return;
   lastBarTime = barTime;

   // Processar cada simbolo
   for(int i = 0; i < totalSymbols; i++)
   {
      DetectarRegimeVotacaoSym(i);

      LogBarraSym(i);

      if(!AplicarHierarquia()) continue;
      ValidarMonteCarlo();
      if(!GuardrailsArquitetonicasSym(i)) continue;

      ProcurarEntradaSym(i);
   }
}
//+------------------------------------------------------------------+
