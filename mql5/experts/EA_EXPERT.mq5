//+------------------------------------------------------------------+
//|                                                    EA_EXPERT.mq5 |
//|  TRIVIUM369 - FASE 4 - Foco: Arquitetonico + Validacao           |
//|  Spec: MQL5_SPECS_FASE_4_EXPERT.md (1 JUL 2026)                  |
//|  - Votacao de 9 variaveis (regime)                               |
//|  - Hierarquia: capital > edge > expectancy > lucro               |
//|  - Guardrails 5-9 (indefinido, liquidez, execucao, autoaval.)    |
//|  - Realizacao por multiplos de R (1R/2R/3R + trailing)           |
//|  - So metricas verificaveis (Sharpe, PF, Sortino, Calmar)        |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 - Ronei Rosar"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- inputs
input ENUM_TIMEFRAMES InpTF        = PERIOD_H1;  // Timeframe de analise
input double InpRiskPct           = 1.0;        // Risco % por trade
input double InpMaxDrawdownPct    = 10.0;       // Nivel 1: drawdown maximo %
input double InpSharpeMinimo      = 0.8;        // Nivel 2: Sharpe minimo (50 trades)
input double InpSpreadMaxPips     = 2.5;        // Guardrail 6: spread maximo (pips)
input double InpATRMultSL         = 1.5;        // Stop = ATR x este fator
input int    InpAutoavalTrades    = 50;         // Guardrail 9: autoavaliacao a cada N trades
input int    InpMinAmostra        = 30;         // Amostra minima p/ metricas agirem (review Expert)
input double InpMargemVotacao     = 1.0;        // Margem minima entre scores de regime (empate = incerto)
input double InpMaxPerdaDiaPct    = 3.0;        // Perda maxima no dia (% saldo)
input double InpMaxPerdaSemanaPct = 6.0;        // Perda maxima na semana (% saldo)
input int    InpMaxPerdasSeq      = 4;          // Perdas consecutivas -> pausa
input int    InpPausaHoras        = 6;          // Horas de pausa apos perdas consecutivas
input int    InpHoraInicio        = 7;          // Hora inicio operacao (servidor)
input int    InpHoraFim           = 21;         // Hora fim operacao (servidor)
input bool   InpLogCSV            = true;       // Gravar CSVs (Common\Files\TRIVIUM369)
input long   InpMagic             = 200002;     // Magic number

//--- globals
CTrade  trade;
int     hADX, hEMA20, hEMA50, hATR, hBands, hEMA20_M15, hEMA50_M15;
datetime lastBarTime = 0;

string  regimeAtual = "INDEFINIDO";
bool    naoOperar   = false;
bool    modoObservacao = false;
double  sizeMultiplier = 1.0;
double  equityPico  = 0.0;

// realizacao por R
bool    tp1Feito=false, tp2Feito=false, tp3Feito=false;
double  riscoR = 0.0;   // distancia entry->stop no momento da entrada (points)

// autoavaliacao
int     tradesDesdeAutoaval = 0;
int     dealsFechadosAntes  = 0;

// guardrails extras (review Expert)
int      falhasExecucaoSeq = 0;
datetime tsPausaAte        = 0;
string   regimeNaEntrada   = "";

// scores da ultima votacao (p/ log CSV)
double   gScoreTend=0, gScoreComp=0, gScoreExp=0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetDeviationInPoints(20);

   hADX       = iADX(_Symbol, InpTF, 14);
   hEMA20     = iMA(_Symbol, InpTF, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50     = iMA(_Symbol, InpTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   hATR       = iATR(_Symbol, InpTF, 14);
   hBands     = iBands(_Symbol, InpTF, 20, 0, 2.0, PRICE_CLOSE);
   hEMA20_M15 = iMA(_Symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50_M15 = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(hADX==INVALID_HANDLE || hEMA20==INVALID_HANDLE || hEMA50==INVALID_HANDLE ||
      hATR==INVALID_HANDLE || hBands==INVALID_HANDLE ||
      hEMA20_M15==INVALID_HANDLE || hEMA50_M15==INVALID_HANDLE)
   {
      Print("[EA_EXPERT] Erro criando handles de indicadores");
      return INIT_FAILED;
   }

   equityPico = AccountInfoDouble(ACCOUNT_EQUITY);
   dealsFechadosAntes = ContarDealsFechados();
   Print("[EA_EXPERT] Iniciado. Magic=", InpMagic, " TF=", EnumToString(InpTF));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hADX); IndicatorRelease(hEMA20); IndicatorRelease(hEMA50);
   IndicatorRelease(hATR); IndicatorRelease(hBands);
   IndicatorRelease(hEMA20_M15); IndicatorRelease(hEMA50_M15);
}

//+------------------------------------------------------------------+
//| Helpers basicos                                                  |
//+------------------------------------------------------------------+
double Buf(int handle, int buffer, int shift)
{
   double v[1];
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1) return 0.0;
   return v[0];
}

double PipSize(){ return (_Digits==3 || _Digits==5) ? 10.0*_Point : _Point; }

double SpreadPips()
{
   return (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/PipSize();
}

double VolumeMedia(int barras)
{
   long vols[];
   if(CopyTickVolume(_Symbol, InpTF, 1, barras, vols) < barras) return 0.0;
   double soma=0; for(int i=0;i<barras;i++) soma += (double)vols[i];
   return soma/barras;
}

double NormalizarLote(double lots)
{
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots/vstep)*vstep;
   return MathMin(MathMax(lots, vmin), vmax);
}

double CalcularLote(double riskPct, double slDistPoints)
{
   if(slDistPoints <= 0) return 0.0;
   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct/100.0;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0 || tickSize<=0) return 0.0;
   double valorPorPontoLote = tickValue * (_Point/tickSize);
   return NormalizarLote(riskMoney / (slDistPoints*valorPorPontoLote) * sizeMultiplier);
}

int ContarDealsFechados()
{
   HistorySelect(0, TimeCurrent());
   int n=0;
   for(int i=HistoryDealsTotal()-1; i>=0; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Metricas verificaveis (Sharpe, PF, Sortino, Calmar, Expectancy)  |
//+------------------------------------------------------------------+
int ColetarRetornos(double &rets[], int maxN)
{
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal(), n=0;
   ArrayResize(rets, 0);
   for(int i=total-1; i>=0 && n<maxN; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(tk, DEAL_PROFIT)
               + HistoryDealGetDouble(tk, DEAL_SWAP)
               + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      ArrayResize(rets, n+1);
      rets[n++] = p;
   }
   return n;
}

double CalcularSharpe(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n<InpMinAmostra) return 999.0; // amostra insuficiente: nao penalizar (review Expert)
   double media=0; for(int i=0;i<n;i++) media+=rets[i]; media/=n;
   double var=0;   for(int i=0;i<n;i++) var+=MathPow(rets[i]-media,2); var/=n;
   double desvio = MathSqrt(var);
   return (desvio>0) ? media/desvio : 0.0;
}

double CalcularSortino(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n<InpMinAmostra) return 999.0;
   double media=0; for(int i=0;i<n;i++) media+=rets[i]; media/=n;
   double varNeg=0; int nNeg=0;
   for(int i=0;i<n;i++) if(rets[i]<0){ varNeg+=rets[i]*rets[i]; nNeg++; }
   if(nNeg==0) return 999.0;
   double desvioNeg = MathSqrt(varNeg/nNeg);
   return (desvioNeg>0) ? media/desvioNeg : 0.0;
}

double CalcularProfitFactor(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n<InpMinAmostra) return 999.0;
   double ganho=0, perda=0;
   for(int i=0;i<n;i++){ if(rets[i]>0) ganho+=rets[i]; else perda-=rets[i]; }
   return (perda>0) ? ganho/perda : 999.0;
}

double CalcularCalmar(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n<InpMinAmostra) return 999.0;
   // curva de equity dos retornos (ordem cronologica = inverso do array)
   double eq=0, pico=0, maxDD=0, total=0;
   for(int i=n-1;i>=0;i--)
   {
      eq += rets[i]; total += rets[i];
      if(eq>pico) pico=eq;
      if(pico-eq>maxDD) maxDD=pico-eq;
   }
   return (maxDD>0) ? total/maxDD : 999.0;
}

double CalcularExpectancy(int trades)
{
   double rets[]; int n = ColetarRetornos(rets, trades);
   if(n<InpMinAmostra) return 999.0;
   double soma=0; for(int i=0;i<n;i++) soma+=rets[i];
   return soma/n;
}

//+------------------------------------------------------------------+
//| SECAO 1: Votacao de 9 variaveis                                  |
//+------------------------------------------------------------------+
double AnalisarEstrutura()
{
   // HH/HL = tendencia (voto 1.0) | LH/LL = reversao (0.0) | misto = 0.5
   double h1=iHigh(_Symbol,InpTF,1), h2=iHigh(_Symbol,InpTF,6), h3=iHigh(_Symbol,InpTF,12);
   double l1=iLow(_Symbol,InpTF,1),  l2=iLow(_Symbol,InpTF,6),  l3=iLow(_Symbol,InpTF,12);
   bool altaHH = (h1>h2 && h2>h3), altaHL = (l1>l2 && l2>l3);
   bool baixaLH = (h1<h2 && h2<h3), baixaLL = (l1<l2 && l2<l3);
   if((altaHH && altaHL) || (baixaLH && baixaLL)) return 1.0;
   if(altaHH || altaHL || baixaLH || baixaLL) return 0.5;
   return 0.0;
}

double CorrelacaoTFs()
{
   // H1 e M15 apontando na mesma direcao = 1.0
   double dH1  = Buf(hEMA20,0,1)     - Buf(hEMA50,0,1);
   double dM15 = Buf(hEMA20_M15,0,1) - Buf(hEMA50_M15,0,1);
   if(dH1==0 || dM15==0) return 0.5;
   return (dH1*dM15 > 0) ? 1.0 : 0.0;
}

double ATRMedio(int barras)
{
   double atrs[];
   if(CopyBuffer(hATR, 0, 1, barras, atrs) < barras) return 0.0;
   double soma=0; for(int i=0;i<barras;i++) soma+=atrs[i];
   return soma/barras;
}

string DetectarRegimeVotacao()
{
   double adx = Buf(hADX,0,1);
   double vAdx = (adx>25) ? 1.0 : (adx>20) ? 0.5 : 0.0;

   double ema20=Buf(hEMA20,0,1), ema50=Buf(hEMA50,0,1);
   double slope = (ema50>0) ? (ema20-ema50)/ema50 : 0.0;
   double vSlope = (MathAbs(slope)>0.0005) ? 1.0 : 0.0;

   double atr = Buf(hATR,0,1);
   double atrMed = ATRMedio(100);
   double vAtr = (atrMed>0 && atr>atrMed*1.3) ? 1.0 : 0.0;

   double volMa = VolumeMedia(20);
   double vVol = ((double)iVolume(_Symbol,InpTF,1) > volMa) ? 1.0 : 0.0;

   double close1 = iClose(_Symbol,InpTF,1);
   double bbW = (close1>0) ? (Buf(hBands,1,1)-Buf(hBands,2,1))/close1 : 0.0;
   double vBB = (bbW<0.004) ? 1.0 : 0.0;   // compressao

   double vEstrutura = AnalisarEstrutura();
   double vCorrel    = CorrelacaoTFs();
   double vSpread    = (SpreadPips()<InpSpreadMaxPips) ? 1.0 : 0.0;
   double vVolatil   = (close1>0 && atr/close1>0.003) ? 1.0 : 0.0;

   double scoreTendencia  = vAdx + vSlope + vVol + vEstrutura + vCorrel;   // max 5
   double scoreCompressao = vBB*2.0 + (1.0-vVolatil) + (1.0-vAdx);         // max 4
   double scoreExpansao   = vVolatil + vAtr;                                // max 2
   gScoreTend=scoreTendencia; gScoreComp=scoreCompressao; gScoreExp=scoreExpansao;

   double maxScore = MathMax(scoreTendencia, MathMax(scoreCompressao, scoreExpansao));

   // review Expert: scores proximos = incerteza, exige margem sobre o 2o colocado
   double segundo = scoreTendencia + scoreCompressao + scoreExpansao - maxScore
                  - MathMin(scoreTendencia, MathMin(scoreCompressao, scoreExpansao));
   if(maxScore - segundo < InpMargemVotacao) return "INDEFINIDO";

   // exige maioria clara (>=60% do proprio teto) senao INDEFINIDO
   if(maxScore==scoreTendencia  && scoreTendencia>=3.0)  return "TENDENCIA";
   if(maxScore==scoreCompressao && scoreCompressao>=2.5) return "COMPRESSAO";
   if(maxScore==scoreExpansao   && scoreExpansao>=2.0)   return "EXPANSAO";
   return "INDEFINIDO";
}

//+------------------------------------------------------------------+
//| SECAO 2: Hierarquia de objetivos                                 |
//+------------------------------------------------------------------+
bool AplicarHierarquia()
{
   // NIVEL 1: preservar capital
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>equityPico) equityPico=eq;
   double dd = (equityPico>0) ? (equityPico-eq)/equityPico : 0.0;
   if(dd > InpMaxDrawdownPct/100.0)
   {
      if(!modoObservacao) Print("[HIERARQUIA] Nivel 1 FALHOU: drawdown > ", InpMaxDrawdownPct, "% - PAUSA");
      modoObservacao = true;
      return false;
   }

   // NIVEL 2: preservar edge
   double sharpe = CalcularSharpe(50);
   if(sharpe < InpSharpeMinimo)
   {
      if(!modoObservacao) PrintFormat("[HIERARQUIA] Nivel 2 FALHOU: Sharpe %.2f < %.2f - modo observacao", sharpe, InpSharpeMinimo);
      modoObservacao = true;
      return false;
   }
   modoObservacao = false;

   // NIVEL 3: maximizar expectancy
   double expectancy = CalcularExpectancy(50);
   if(expectancy!=999.0 && expectancy <= 0)
   {
      sizeMultiplier = 0.5;
      Print("[HIERARQUIA] Nivel 3: expectancy <= 0, position size reduzido 50%");
   }
   else sizeMultiplier = 1.0;

   // NIVEL 4: lucro = consequencia
   return true;
}

//+------------------------------------------------------------------+
//| SECAO 4: Guardrails 5-9                                          |
//+------------------------------------------------------------------+
bool GuardrailsArquitetonicas()
{
   // TRAVA 5: regime indefinido
   if(regimeAtual=="INDEFINIDO" || regimeAtual=="EXPANSAO")
   {
      naoOperar = true;   // expansao volatil tambem fica de fora (prudencia)
      return false;
   }

   // TRAVA 6: liquidez (spread)
   if(SpreadPips() > InpSpreadMaxPips)
   {
      naoOperar = true;
      return false;
   }

   // TRAVA 7: execucao - deviation ja limitada em 20 points no CTrade
   // TRAVA 8: consistencia coberta pela exigencia de maioria clara na votacao

   naoOperar = false;

   // TRAVA 9: autoavaliacao a cada N trades
   int fechados = ContarDealsFechados();
   if(fechados - dealsFechadosAntes >= InpAutoavalTrades)
   {
      dealsFechadosAntes = fechados;
      double sharpe  = CalcularSharpe(InpAutoavalTrades);
      double pf      = CalcularProfitFactor(InpAutoavalTrades);
      double sortino = CalcularSortino(InpAutoavalTrades);
      double calmar  = CalcularCalmar(InpAutoavalTrades);
      double expect = CalcularExpectancy(InpAutoavalTrades);
      double ddAtual = (equityPico>0 ? (equityPico-AccountInfoDouble(ACCOUNT_EQUITY))/equityPico*100.0 : 0.0);
      PrintFormat("[AUTOAVALIACAO] Sharpe=%.2f PF=%.2f Sortino=%.2f Calmar=%.2f",
                  sharpe, pf, sortino, calmar);
      PrintFormat("[AUTOAVALIACAO] Expectancy=%.2f DrawdownAtual=%.1f%%", expect, ddAtual);
      CsvAppend(LogPrefixo()+"_metricas.csv",
         "datetime,symbol,trades_janela,sharpe,profit_factor,sortino,calmar,expectancy,drawdown_pct,saldo,equity",
         TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS)+","+_Symbol+","+
         IntegerToString(InpAutoavalTrades)+","+
         DoubleToString(sharpe,3)+","+DoubleToString(pf,3)+","+
         DoubleToString(sortino,3)+","+DoubleToString(calmar,3)+","+
         DoubleToString(expect,2)+","+DoubleToString(ddAtual,2)+","+
         DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+
         DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
      if(sharpe<0.8 || pf<1.3)
      {
         Print("[GUARDRAIL 9] Metricas abaixo do minimo - risco reduzido 50%");
         sizeMultiplier = 0.5;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Guardrails de risco extras (review Expert 2 JUL)                 |
//+------------------------------------------------------------------+
double LucroRealizadoDesde(datetime desde)
{
   double soma=0;
   HistorySelect(desde, TimeCurrent());
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      soma += HistoryDealGetDouble(tk, DEAL_PROFIT)
            + HistoryDealGetDouble(tk, DEAL_SWAP)
            + HistoryDealGetDouble(tk, DEAL_COMMISSION);
   }
   return soma;
}

int PerdasConsecutivas()
{
   HistorySelect(0, TimeCurrent());
   int seq=0;
   for(int i=HistoryDealsTotal()-1; i>=0; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(tk, DEAL_PROFIT);
      if(p<0) seq++;
      else break;
   }
   return seq;
}

bool GuardrailsRisco()
{
   // pausa ativa (perdas consecutivas ou falhas de execucao)
   if(TimeCurrent() < tsPausaAte) return false;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);

   // filtro de horario/liquidez
   if(dt.hour < InpHoraInicio || dt.hour >= InpHoraFim) return false;

   double saldo = AccountInfoDouble(ACCOUNT_BALANCE);
   if(saldo<=0) return false;

   // perda maxima do dia
   datetime hojeIni = TimeCurrent() - (dt.hour*3600 + dt.min*60 + dt.sec);
   double resDia = LucroRealizadoDesde(hojeIni);
   if(resDia/saldo < -InpMaxPerdaDiaPct/100.0)
   {
      Print("[GUARDRAIL DIA] Perda do dia ", DoubleToString(resDia,2), " excede ", InpMaxPerdaDiaPct, "% - sem novas entradas hoje");
      return false;
   }

   // perda maxima da semana (desde segunda)
   int diasDesdeSegunda = (dt.day_of_week + 6) % 7;
   datetime semanaIni = hojeIni - (datetime)diasDesdeSegunda*86400;
   double resSemana = LucroRealizadoDesde(semanaIni);
   if(resSemana/saldo < -InpMaxPerdaSemanaPct/100.0)
   {
      Print("[GUARDRAIL SEMANA] Perda semanal excede ", InpMaxPerdaSemanaPct, "% - sem novas entradas na semana");
      return false;
   }

   // perdas consecutivas -> pausa temporizada
   if(PerdasConsecutivas() >= InpMaxPerdasSeq)
   {
      tsPausaAte = TimeCurrent() + (datetime)InpPausaHoras*3600;
      PrintFormat("[GUARDRAIL SEQ] %d perdas consecutivas - pausa de %d horas", InpMaxPerdasSeq, InpPausaHoras);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| SECAO 3: Realizacao por multiplos de R                           |
//+------------------------------------------------------------------+
void RealizarPorMultiplosDeR()
{
   if(!PositionSelect(_Symbol))
   { tp1Feito=false; tp2Feito=false; tp3Feito=false; riscoR=0; regimeNaEntrada=""; return; }
   if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) return;
   if(riscoR<=0) return;

   // review Expert: alvos adaptativos ao regime da entrada
   // TENDENCIA: realiza menos cedo, deixa runner maior correr
   // COMPRESSAO: realiza mais cedo, encerra em 2R
   bool emTendencia = (regimeNaEntrada!="COMPRESSAO");
   double fracTP1 = emTendencia ? 0.20 : 0.50;
   double fracTP2 = emTendencia ? 0.25 : 1.00;  // compressao: fecha tudo em 2R
   double fracTP3 = emTendencia ? 0.33 : 0.00;

   long   tipo  = PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double lucroPoints = (tipo==POSITION_TYPE_BUY) ? (bid-entry)/_Point : (entry-ask)/_Point;
   double profitR = lucroPoints/riscoR;
   ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   double vmin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double atr    = Buf(hATR,0,1);

   if(profitR>=1.0 && !tp1Feito)
   {
      double vol = PositionGetDouble(POSITION_VOLUME);
      double v = NormalizarLote(vol*fracTP1);
      if(v>=vmin && vol-v>=vmin && trade.PositionClosePartial(ticket, v))
      {
         // stop para breakeven
         trade.PositionModify(ticket, NormalizeDouble(entry,_Digits), PositionGetDouble(POSITION_TP));
         PrintFormat("[TP1] 1R alcancado - realiza %.0f%%, stop no breakeven (%s)", fracTP1*100, regimeNaEntrada);
         tp1Feito = true;
      }
   }
   if(profitR>=2.0 && !tp2Feito && PositionSelect(_Symbol))
   {
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(fracTP2>=1.0)
      {
         if(trade.PositionClose(ticket))
         { tp2Feito=true; Print("[TP2] 2R alcancado - fecha tudo (Compressao)"); return; }
      }
      else
      {
         double v = NormalizarLote(vol*fracTP2);
         if(v>=vmin && vol-v>=vmin && trade.PositionClosePartial(ticket, v))
         {
            double novoSL = (tipo==POSITION_TYPE_BUY) ? entry+atr : entry-atr;
            trade.PositionModify(ticket, NormalizeDouble(novoSL,_Digits), PositionGetDouble(POSITION_TP));
            PrintFormat("[TP2] 2R alcancado - realiza %.0f%%, stop entry+1ATR", fracTP2*100);
            tp2Feito = true;
         }
      }
   }
   if(profitR>=3.0 && !tp3Feito && fracTP3>0 && PositionSelect(_Symbol))
   {
      double vol = PositionGetDouble(POSITION_VOLUME);
      double v = NormalizarLote(vol*fracTP3);
      if(v>=vmin && vol-v>=vmin && trade.PositionClosePartial(ticket, v))
      {
         Print("[TP3] 3R alcancado - realiza parcial, resto trailing (runner)");
         tp3Feito = true;
      }
   }
   // trailing do runner apos 1R
   if(tp1Feito && PositionSelect(_Symbol) && atr>0)
   {
      double sl = PositionGetDouble(POSITION_SL);
      double novoSL = (tipo==POSITION_TYPE_BUY) ? bid-atr : ask+atr;
      bool melhora = (tipo==POSITION_TYPE_BUY) ? (novoSL>sl) : (sl==0 || novoSL<sl);
      if(melhora) trade.PositionModify(ticket, NormalizeDouble(novoSL,_Digits), PositionGetDouble(POSITION_TP));
   }
}

//+------------------------------------------------------------------+
//| Entrada                                                          |
//+------------------------------------------------------------------+
bool AbrirOrdem(bool isBuy, double lots, double preco, double sl, double tp, string comentario)
{
   bool ok = isBuy ? trade.Buy(lots,_Symbol,preco,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),comentario)
                   : trade.Sell(lots,_Symbol,preco,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),comentario);
   if(ok)
   {
      falhasExecucaoSeq = 0;
      regimeNaEntrada = regimeAtual;
   }
   else
   {
      falhasExecucaoSeq++;
      PrintFormat("[EXECUCAO] Falha na ordem (%d seguidas): %d - %s",
                  falhasExecucaoSeq, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      if(falhasExecucaoSeq>=3)
      {
         tsPausaAte = TimeCurrent() + 3600;
         Print("[GUARDRAIL EXECUCAO] 3 falhas seguidas - pausa de 1 hora");
         falhasExecucaoSeq = 0;
      }
   }
   return ok;
}

void ProcurarEntrada()
{
   if(PositionSelect(_Symbol)) return;
   if(naoOperar || modoObservacao) return;
   if(!GuardrailsRisco()) return;

   double atr = Buf(hATR,0,1);
   if(atr<=0) return;
   double ema20a=Buf(hEMA20,0,2), ema50a=Buf(hEMA50,0,2);
   double ema20=Buf(hEMA20,0,1),  ema50=Buf(hEMA50,0,1);
   double bbUp=Buf(hBands,1,1), bbLo=Buf(hBands,2,1), bbMid=Buf(hBands,0,1);
   double close1 = iClose(_Symbol,InpTF,1);
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double slDist = atr*InpATRMultSL;

   if(regimeAtual=="TENDENCIA")
   {
      bool cruzouAcima  = (ema20a<=ema50a && ema20>ema50);
      bool cruzouAbaixo = (ema20a>=ema50a && ema20<ema50);
      bool momentumAlta  = (ema20>ema50 && close1>ema20 && CorrelacaoTFs()==1.0 && AnalisarEstrutura()==1.0 && iClose(_Symbol,InpTF,2)<Buf(hEMA20,0,2));
      bool momentumBaixa = (ema20<ema50 && close1<ema20 && CorrelacaoTFs()==1.0 && AnalisarEstrutura()==1.0 && iClose(_Symbol,InpTF,2)>Buf(hEMA20,0,2));

      if(cruzouAcima || momentumAlta)
      {
         double sl = ask - slDist;
         double tp = ask + slDist*3.0;   // TP final em 3R (parciais antes)
         double lots = CalcularLote(InpRiskPct, slDist/_Point);
         if(lots>0 && AbrirOrdem(true, lots, ask, sl, tp, "EXPERT-TEND-BUY"))
         { riscoR = slDist/_Point; PrintFormat("[ENTRADA] BUY tendencia %.2f lotes R=%.0f points", lots, riscoR); }
      }
      else if(cruzouAbaixo || momentumBaixa)
      {
         double sl = bid + slDist;
         double tp = bid - slDist*3.0;
         double lots = CalcularLote(InpRiskPct, slDist/_Point);
         if(lots>0 && AbrirOrdem(false, lots, bid, sl, tp, "EXPERT-TEND-SELL"))
         { riscoR = slDist/_Point; PrintFormat("[ENTRADA] SELL tendencia %.2f lotes R=%.0f points", lots, riscoR); }
      }
   }
   else if(regimeAtual=="COMPRESSAO")
   {
      // bounce nas bandas com R:R fixo por multiplos de R
      if(close1<=bbLo)
      {
         double sl = close1 - slDist;
         double tp = bbMid;
         double lots = CalcularLote(InpRiskPct*0.5, (ask-sl)/_Point);
         if(lots>0 && AbrirOrdem(true, lots, ask, sl, tp, "EXPERT-COMP-BUY"))
         { riscoR = (ask-sl)/_Point; Print("[ENTRADA] BUY compressao (banda inferior)"); }
      }
      else if(close1>=bbUp)
      {
         double sl = close1 + slDist;
         double tp = bbMid;
         double lots = CalcularLote(InpRiskPct*0.5, (sl-bid)/_Point);
         if(lots>0 && AbrirOrdem(false, lots, bid, sl, tp, "EXPERT-COMP-SELL"))
         { riscoR = (sl-bid)/_Point; Print("[ENTRADA] SELL compressao (banda superior)"); }
      }
   }
}

//+------------------------------------------------------------------+
//| LOGS CSV (Common\Files\TRIVIUM369)                               |
//+------------------------------------------------------------------+
string LogPrefixo(){ return "TRIVIUM369\\EA_EXPERT_" + _Symbol; }

void CsvAppend(string arquivo, string cabecalho, string linha)
{
   if(!InpLogCSV) return;
   int h = FileOpen(arquivo, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0) FileWriteString(h, cabecalho + "\n");
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, linha + "\n");
   FileClose(h);
}

void LogEvento(string categoria, string detalhe)
{
   Print("[", categoria, "] ", detalhe);
   CsvAppend(LogPrefixo()+"_eventos.csv",
      "datetime,symbol,categoria,detalhe,regime,saldo,equity",
      TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS)+","+_Symbol+","+categoria+
      ",\""+detalhe+"\","+regimeAtual+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
}

void LogBarra()
{
   if(!InpLogCSV) return;
   double spreadPts = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   CsvAppend(LogPrefixo()+"_barras.csv",
      "datetime,open,high,low,close,tick_volume,spread_points,adx,ema20,ema50,atr,bb_upper,bb_lower,score_tendencia,score_compressao,score_expansao,regime,size_mult,modo_observacao,nao_operar",
      TimeToString(iTime(_Symbol,InpTF,1),TIME_DATE|TIME_MINUTES)+","+
      DoubleToString(iOpen(_Symbol,InpTF,1),_Digits)+","+
      DoubleToString(iHigh(_Symbol,InpTF,1),_Digits)+","+
      DoubleToString(iLow(_Symbol,InpTF,1),_Digits)+","+
      DoubleToString(iClose(_Symbol,InpTF,1),_Digits)+","+
      IntegerToString(iVolume(_Symbol,InpTF,1))+","+
      DoubleToString(spreadPts,1)+","+
      DoubleToString(Buf(hADX,0,1),2)+","+
      DoubleToString(Buf(hEMA20,0,1),_Digits)+","+
      DoubleToString(Buf(hEMA50,0,1),_Digits)+","+
      DoubleToString(Buf(hATR,0,1),_Digits)+","+
      DoubleToString(Buf(hBands,1,1),_Digits)+","+
      DoubleToString(Buf(hBands,2,1),_Digits)+","+
      DoubleToString(gScoreTend,1)+","+DoubleToString(gScoreComp,1)+","+DoubleToString(gScoreExp,1)+","+
      regimeAtual+","+DoubleToString(sizeMultiplier,2)+","+
      (modoObservacao?"1":"0")+","+(naoOperar?"1":"0"));
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal;
   if(!HistoryDealSelect(deal)) return;
   if(HistoryDealGetInteger(deal, DEAL_MAGIC)!=InpMagic) return;
   CsvAppend(LogPrefixo()+"_trades.csv",
      "datetime,symbol,deal,tipo,entrada,volume,preco,sl,tp,profit,swap,comissao,regime,risco_r_points,comentario,saldo,equity",
      TimeToString((datetime)HistoryDealGetInteger(deal,DEAL_TIME),TIME_DATE|TIME_MINUTES|TIME_SECONDS)+","+_Symbol+","+
      IntegerToString((long)deal)+","+
      EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE))+","+
      EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY))+","+
      DoubleToString(HistoryDealGetDouble(deal,DEAL_VOLUME),2)+","+
      DoubleToString(HistoryDealGetDouble(deal,DEAL_PRICE),_Digits)+","+
      DoubleToString(HistoryDealGetDouble(deal,DEAL_SL),_Digits)+","+
      DoubleToString(HistoryDealGetDouble(deal,DEAL_TP),_Digits)+","+
      DoubleToString(HistoryDealGetDouble(deal,DEAL_PROFIT),2)+","+
      DoubleToString(HistoryDealGetDouble(deal,DEAL_SWAP),2)+","+
      DoubleToString(HistoryDealGetDouble(deal,DEAL_COMMISSION),2)+","+
      regimeNaEntrada+","+DoubleToString(riscoR,0)+",\""+HistoryDealGetString(deal,DEAL_COMMENT)+"\","+
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
}

//+------------------------------------------------------------------+
void OnTick()
{
   RealizarPorMultiplosDeR();

   datetime barTime = iTime(_Symbol, InpTF, 0);
   if(barTime==lastBarTime) return;
   lastBarTime = barTime;

   string regimeAntes = regimeAtual;
   regimeAtual = DetectarRegimeVotacao();
   if(regimeAtual!=regimeAntes)
      LogEvento("REGIME", "Mudanca "+regimeAntes+" -> "+regimeAtual+
                " (T="+DoubleToString(gScoreTend,1)+" C="+DoubleToString(gScoreComp,1)+" E="+DoubleToString(gScoreExp,1)+")");
   LogBarra();

   if(!AplicarHierarquia()) return;
   if(!GuardrailsArquitetonicas()) return;

   ProcurarEntrada();
}
//+------------------------------------------------------------------+
