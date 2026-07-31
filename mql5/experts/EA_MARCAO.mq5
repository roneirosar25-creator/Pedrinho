//+------------------------------------------------------------------+
//|                                                    EA_MARCAO.mq5 |
//|  TRIVIUM369 - FASE 4 - Foco: Pragmatico + Robustez               |
//|  Spec: MQL5_SPECS_FASE_4_MARCAO.md (1 JUL 2026)                  |
//|  - Apenas 2 cenarios: Tendencia Forte + Compressao Extrema       |
//|  - Prioridade do detector: Volatil > Tendencia > Lateral         |
//|  - Monte Carlo (bootstrap dos retornos) a cada 100 trades        |
//|  - Demo tracking: 90 dias obrigatorios antes de live             |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 - Ronei Rosar"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- inputs
input ENUM_TIMEFRAMES InpTF        = PERIOD_H1;  // Timeframe de analise
input double InpRiskPct           = 1.0;        // Risco % por trade
input double InpADXTendencia      = 25.0;       // ADX minimo p/ tendencia forte
input double InpVolMultTendencia  = 1.2;        // Volume > media x este fator
input double InpATRMultSL         = 1.5;        // Stop = ATR x este fator
input double InpATRMultTP         = 3.0;        // TP = ATR x este fator (R:R 1:2)
input double InpMaxDrawdownPct    = 12.0;       // Drawdown maximo %
input int    InpMonteCarloCada    = 100;        // Monte Carlo a cada N trades
input int    InpDiasDemoMinimo    = 90;         // Demo obrigatoria (dias)
input bool   InpLogCSV            = true;       // Gravar CSVs (Common\Files\TRIVIUM369)
input long   InpMagic             = 200003;     // Magic number

//--- regime
enum MarketRegime
{
   REGIME_TENDENCIA_FORTE,
   REGIME_COMPRESSAO_EXTREMA,
   REGIME_INDEFINIDO
};

//--- globals
CTrade  trade;
int     hADX, hEMA20, hEMA50, hATR, hBands;
datetime lastBarTime = 0;
MarketRegime regimeAtual = REGIME_INDEFINIDO;
double  equityPico = 0.0;
bool    pausado = false;

// demo tracking
datetime inicioDemo = 0;
bool     liberadoParaLive = false;

// monte carlo
int      dealsUltimoMC = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetDeviationInPoints(20);

   hADX   = iADX(_Symbol, InpTF, 14);
   hEMA20 = iMA(_Symbol, InpTF, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, InpTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   hATR   = iATR(_Symbol, InpTF, 14);
   hBands = iBands(_Symbol, InpTF, 20, 0, 2.0, PRICE_CLOSE);

   if(hADX==INVALID_HANDLE || hEMA20==INVALID_HANDLE || hEMA50==INVALID_HANDLE ||
      hATR==INVALID_HANDLE || hBands==INVALID_HANDLE)
   {
      Print("[EA_MARCAO] Erro criando handles de indicadores");
      return INIT_FAILED;
   }

   equityPico = AccountInfoDouble(ACCOUNT_EQUITY);
   IniciarDemoObrigatorio();
   Print("[EA_MARCAO] Iniciado. Magic=", InpMagic, " TF=", EnumToString(InpTF));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hADX); IndicatorRelease(hEMA20); IndicatorRelease(hEMA50);
   IndicatorRelease(hATR); IndicatorRelease(hBands);
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double Buf(int handle, int buffer, int shift)
{
   double v[1];
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1) return 0.0;
   return v[0];
}

double PipSize(){ return (_Digits==3 || _Digits==5) ? 10.0*_Point : _Point; }

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
   return NormalizarLote(riskMoney / (slDistPoints*valorPorPontoLote));
}

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

double SharpeDe(const double &rets[], int n)
{
   if(n<2) return 0.0;
   double media=0; for(int i=0;i<n;i++) media+=rets[i]; media/=n;
   double var=0;   for(int i=0;i<n;i++) var+=MathPow(rets[i]-media,2); var/=n;
   double d = MathSqrt(var);
   return (d>0) ? media/d : 0.0;
}

double PFDe(const double &rets[], int n)
{
   double g=0, p=0;
   for(int i=0;i<n;i++){ if(rets[i]>0) g+=rets[i]; else p-=rets[i]; }
   return (p>0) ? g/p : 999.0;
}

double DrawdownDe(const double &rets[], int n)
{
   // percorre em ordem cronologica (array esta do mais novo p/ mais velho)
   double eq=0, pico=0, maxDD=0;
   for(int i=n-1;i>=0;i--)
   {
      eq += rets[i];
      if(eq>pico) pico=eq;
      if(pico-eq>maxDD) maxDD=pico-eq;
   }
   return maxDD;
}

//+------------------------------------------------------------------+
//| SECOES 1-2: Detector com prioridade Volatil > Tendencia > Lateral|
//+------------------------------------------------------------------+
double BBWidthMedia(int barras)
{
   double up[], lo[];
   if(CopyBuffer(hBands, 1, 1, barras, up) < barras) return 0.0;
   if(CopyBuffer(hBands, 2, 1, barras, lo) < barras) return 0.0;
   double soma=0; int n=0;
   for(int i=0;i<barras;i++)
   {
      double c = iClose(_Symbol, InpTF, barras-i);
      if(c>0){ soma += (up[i]-lo[i])/c; n++; }
   }
   return (n>0) ? soma/n : 0.0;
}

MarketRegime DetectarApenasDoisCenarios()
{
   double adx   = Buf(hADX,0,1);
   double vol1  = (double)iVolume(_Symbol,InpTF,1);
   double volMa = VolumeMedia(20);
   double close1 = iClose(_Symbol,InpTF,1);
   double bbWpct = (close1>0) ? (Buf(hBands,1,1)-Buf(hBands,2,1))/close1 : 0.0;
   double bbWmedia = BBWidthMedia(50);
   double atr = Buf(hATR,0,1);

   // PRIORIDADE 1: VOLATIL -> nao opera (evita chicote)
   bool volatil = (adx<20 && bbWmedia>0 && bbWpct>bbWmedia*1.5) ||
                  (close1>0 && atr/close1>0.006);
   if(volatil) return REGIME_INDEFINIDO;

   // PRIORIDADE 2: TENDENCIA FORTE
   if(adx>InpADXTendencia && vol1>volMa*InpVolMultTendencia)
      return REGIME_TENDENCIA_FORTE;

   // PRIORIDADE 3: COMPRESSAO EXTREMA (lateral apertado)
   if(bbWmedia>0 && bbWpct<bbWmedia*0.5 && vol1<volMa)
      return REGIME_COMPRESSAO_EXTREMA;

   return REGIME_INDEFINIDO;
}

//+------------------------------------------------------------------+
//| Estrategias dos 2 cenarios                                       |
//+------------------------------------------------------------------+
void EstrategiaTendencia()
{
   double ema20a=Buf(hEMA20,0,2), ema50a=Buf(hEMA50,0,2);
   double ema20=Buf(hEMA20,0,1),  ema50=Buf(hEMA50,0,1);
   double atr = Buf(hATR,0,1);
   if(atr<=0) return;
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double slDist = atr*InpATRMultSL;
   double tpDist = atr*InpATRMultTP;

   bool cruzouAcima  = (ema20a<=ema50a && ema20>ema50);
   bool cruzouAbaixo = (ema20a>=ema50a && ema20<ema50);

   if(cruzouAcima)
   {
      double lots = CalcularLote(InpRiskPct, slDist/_Point);
      if(lots>0 && trade.Buy(lots,_Symbol,ask,NormalizeDouble(ask-slDist,_Digits),NormalizeDouble(ask+tpDist,_Digits),"MARCAO-TEND-BUY"))
         Print("[TENDENCIA] EMA 20/50 cruzou pra cima - COMPRA ", DoubleToString(lots,2), " lotes");
   }
   else if(cruzouAbaixo)
   {
      double lots = CalcularLote(InpRiskPct, slDist/_Point);
      if(lots>0 && trade.Sell(lots,_Symbol,bid,NormalizeDouble(bid+slDist,_Digits),NormalizeDouble(bid-tpDist,_Digits),"MARCAO-TEND-SELL"))
         Print("[TENDENCIA] EMA 20/50 cruzou pra baixo - VENDA ", DoubleToString(lots,2), " lotes");
   }
}

void EstrategiaCompressao()
{
   // breakout da compressao com confirmacao de volume
   double bbUp = Buf(hBands,1,1), bbLo = Buf(hBands,2,1);
   double close1 = iClose(_Symbol,InpTF,1);
   double vol1  = (double)iVolume(_Symbol,InpTF,1);
   double volMa = VolumeMedia(20);
   double atr = Buf(hATR,0,1);
   if(atr<=0 || volMa<=0) return;
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double pip = PipSize();

   if(close1>=bbUp && vol1>volMa*1.5)
   {
      double sl = bbLo - 10*pip;
      double tp = ask + atr*InpATRMultTP;
      double lots = CalcularLote(InpRiskPct, (ask-sl)/_Point);
      if(lots>0 && trade.Buy(lots,_Symbol,ask,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),"MARCAO-COMP-BUY"))
         Print("[COMPRESSAO] Breakout banda superior com volume - COMPRA");
   }
   else if(close1<=bbLo && vol1>volMa*1.5)
   {
      double sl = bbUp + 10*pip;
      double tp = bid - atr*InpATRMultTP;
      double lots = CalcularLote(InpRiskPct, (sl-bid)/_Point);
      if(lots>0 && trade.Sell(lots,_Symbol,bid,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),"MARCAO-COMP-SELL"))
         Print("[COMPRESSAO] Breakout banda inferior com volume - VENDA");
   }
}

//+------------------------------------------------------------------+
//| SECAO 3: Monte Carlo (bootstrap dos retornos reais)              |
//+------------------------------------------------------------------+
bool ExecutarMonteCarloValidation()
{
   double rets[];
   int n = ColetarRetornos(rets, InpMonteCarloCada);
   if(n<30){ Print("[MONTE CARLO] Historico insuficiente (", n, " trades)"); return true; }

   double sharpeBase = SharpeDe(rets, n);
   double pfBase     = PFDe(rets, n);
   PrintFormat("[MONTE CARLO] Baseline: Sharpe=%.2f PF=%.2f (%d trades)", sharpeBase, pfBase, n);

   // bootstrap: 200 reamostragens com reposicao
   int    simulacoes = 200;
   int    pioresCasos = 0;
   double sharpeMin = sharpeBase, sharpeMax = sharpeBase;
   double amostra[];
   ArrayResize(amostra, n);

   for(int s=0; s<simulacoes; s++)
   {
      for(int i=0;i<n;i++)
         amostra[i] = rets[MathRand()%n];
      double sh = SharpeDe(amostra, n);
      double pf = PFDe(amostra, n);
      if(sh<sharpeMin) sharpeMin=sh;
      if(sh>sharpeMax) sharpeMax=sh;
      if(sh<0.0 || pf<1.0) pioresCasos++;
   }

   double pctPiores = (double)pioresCasos/simulacoes*100.0;
   PrintFormat("[MONTE CARLO] Sharpe min=%.2f max=%.2f | cenarios ruins=%.1f%%",
               sharpeMin, sharpeMax, pctPiores);
   CsvAppend(LogPrefixo()+"_montecarlo.csv",
      "datetime,symbol,trades_amostra,simulacoes,sharpe_base,sharpe_min,sharpe_max,pf_base,pct_cenarios_ruins,passou",
      TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS)+","+_Symbol+","+
      IntegerToString(n)+","+IntegerToString(simulacoes)+","+
      DoubleToString(sharpeBase,3)+","+DoubleToString(sharpeMin,3)+","+DoubleToString(sharpeMax,3)+","+
      DoubleToString(pfBase,3)+","+DoubleToString(pctPiores,1)+","+
      (pctPiores<10.0 ? "SIM" : "NAO"));

   // PASSOU: menos de 10% das simulacoes com edge negativo
   if(pctPiores < 10.0)
   {
      Print("[MONTE CARLO] PASSOU - sistema robusto");
      return true;
   }
   Print("[MONTE CARLO] FALHOU - sistema fragil, pausando novas entradas");
   return false;
}

//+------------------------------------------------------------------+
//| SECAO 5: Demo obrigatoria (90 dias)                              |
//+------------------------------------------------------------------+
void IniciarDemoObrigatorio()
{
   string gv = "EA_MARCAO_DEMO_INICIO_" + _Symbol;
   if(GlobalVariableCheck(gv))
      inicioDemo = (datetime)GlobalVariableGet(gv);
   else
   {
      inicioDemo = TimeCurrent();
      GlobalVariableSet(gv, (double)inicioDemo);
   }
   Print("[MARCAO] Demo iniciada em ", TimeToString(inicioDemo, TIME_DATE));
   Print("[MARCAO] Minimo ", InpDiasDemoMinimo, " dias antes de considerar live");

   bool contaDemo = (AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);
   if(!contaDemo && !liberadoParaLive)
      Print("[MARCAO] ATENCAO: conta REAL detectada antes da liberacao - opere em DEMO primeiro!");
}

void AvaliarReadinessParaLive()
{
   int diasRodando = (int)((TimeCurrent()-inicioDemo)/86400);
   if(diasRodando < InpDiasDemoMinimo) return;

   double rets[];
   int n = ColetarRetornos(rets, 1000);
   double sharpe = SharpeDe(rets, n);
   double pf = PFDe(rets, n);
   double dd = DrawdownDe(rets, n);
   double saldoInicial = MathMax(1.0, AccountInfoDouble(ACCOUNT_BALANCE) - DrawdownDe(rets,n));
   double ddPct = dd/saldoInicial;

   bool ok = (n>=50 && sharpe>1.0 && pf>1.4 && ddPct<=0.15);
   if(ok && !liberadoParaLive)
   {
      liberadoParaLive = true;
      Print("=== LIBERADO PARA LIVE ===");
      PrintFormat("Dias=%d Trades=%d Sharpe=%.2f PF=%.2f DD=%.1f%%", diasRodando, n, sharpe, pf, ddPct*100.0);
   }
}

//+------------------------------------------------------------------+
//| Guardrail simples de drawdown                                    |
//+------------------------------------------------------------------+
bool ChecarDrawdown()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>equityPico) equityPico=eq;
   double dd = (equityPico>0) ? (equityPico-eq)/equityPico : 0.0;
   if(dd > InpMaxDrawdownPct/100.0)
   {
      if(!pausado){ PrintFormat("[GUARDRAIL] Drawdown %.1f%% > %.1f%% - PAUSA", dd*100.0, InpMaxDrawdownPct); pausado=true; }
      return false;
   }
   pausado = false;
   return true;
}

//+------------------------------------------------------------------+
//| LOGS CSV (Common\Files\TRIVIUM369)                               |
//+------------------------------------------------------------------+
string LogPrefixo(){ return "TRIVIUM369\\EA_MARCAO_" + _Symbol; }

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
      ",\""+detalhe+"\","+EnumToString(regimeAtual)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
}

void LogBarra()
{
   if(!InpLogCSV) return;
   double spreadPts = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   double close1 = iClose(_Symbol,InpTF,1);
   double bbWpct = (close1>0) ? (Buf(hBands,1,1)-Buf(hBands,2,1))/close1 : 0.0;
   CsvAppend(LogPrefixo()+"_barras.csv",
      "datetime,open,high,low,close,tick_volume,spread_points,adx,ema20,ema50,atr,bb_width_pct,bb_width_media,regime",
      TimeToString(iTime(_Symbol,InpTF,1),TIME_DATE|TIME_MINUTES)+","+
      DoubleToString(iOpen(_Symbol,InpTF,1),_Digits)+","+
      DoubleToString(iHigh(_Symbol,InpTF,1),_Digits)+","+
      DoubleToString(iLow(_Symbol,InpTF,1),_Digits)+","+
      DoubleToString(close1,_Digits)+","+
      IntegerToString(iVolume(_Symbol,InpTF,1))+","+
      DoubleToString(spreadPts,1)+","+
      DoubleToString(Buf(hADX,0,1),2)+","+
      DoubleToString(Buf(hEMA20,0,1),_Digits)+","+
      DoubleToString(Buf(hEMA50,0,1),_Digits)+","+
      DoubleToString(Buf(hATR,0,1),_Digits)+","+
      DoubleToString(bbWpct*100.0,3)+","+
      DoubleToString(BBWidthMedia(50)*100.0,3)+","+
      EnumToString(regimeAtual));
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal = trans.deal;
   if(!HistoryDealSelect(deal)) return;
   if(HistoryDealGetInteger(deal, DEAL_MAGIC)!=InpMagic) return;
   CsvAppend(LogPrefixo()+"_trades.csv",
      "datetime,symbol,deal,tipo,entrada,volume,preco,sl,tp,profit,swap,comissao,regime,comentario,saldo,equity",
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
      EnumToString(regimeAtual)+",\""+HistoryDealGetString(deal,DEAL_COMMENT)+"\","+
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime barTime = iTime(_Symbol, InpTF, 0);
   if(barTime==lastBarTime) return;
   lastBarTime = barTime;

   if(!ChecarDrawdown()) return;
   AvaliarReadinessParaLive();

   // monte carlo periodico
   HistorySelect(0, TimeCurrent());
   int deals=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong tk=HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk,DEAL_MAGIC)==InpMagic &&
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk,DEAL_ENTRY)==DEAL_ENTRY_OUT) deals++;
   }
   static bool mcPassou = true;
   if(deals-dealsUltimoMC >= InpMonteCarloCada)
   {
      dealsUltimoMC = deals;
      mcPassou = ExecutarMonteCarloValidation();
   }
   if(!mcPassou) return;

   MarketRegime regimeAntes = regimeAtual;
   regimeAtual = DetectarApenasDoisCenarios();
   if(regimeAtual!=regimeAntes)
      LogEvento("REGIME", "Mudanca "+EnumToString(regimeAntes)+" -> "+EnumToString(regimeAtual));
   LogBarra();

   if(PositionSelect(_Symbol)) return;   // uma posicao por vez

   if(regimeAtual==REGIME_TENDENCIA_FORTE)       EstrategiaTendencia();
   else if(regimeAtual==REGIME_COMPRESSAO_EXTREMA) EstrategiaCompressao();
   // INDEFINIDO: nao opera
}
//+------------------------------------------------------------------+
