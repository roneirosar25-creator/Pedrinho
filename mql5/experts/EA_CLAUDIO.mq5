//+------------------------------------------------------------------+
//|                                                   EA_CLAUDIO.mq5 |
//|  TRIVIUM369 - FASE 4 - Foco: Operacional + Guardrails 1-4        |
//|  Spec: MQL5_SPECS_FASE_4_CLAUDIO.md (1 JUL 2026)                 |
//|  - Regime: fila de 5 velas + confianca > 65%                     |
//|  - Cascata: regime -> indicadores -> risco -> SL -> TP           |
//|  - Guardrails: drawdown, hiperadaptacao, regime falho, atraso    |
//|  - Realizacao: PIPS (tendencia) / % saldo (compressao)           |
//|  - Agressividade por contador de falhas                          |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 - Ronei Rosar"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- inputs
input ENUM_TIMEFRAMES InpTF          = PERIOD_H1; // Timeframe de analise
input double InpRiskTendencia       = 1.5;       // Risco % por trade (tendencia)
input double InpRiskCompressao      = 0.5;       // Risco % por trade (compressao)
input double InpMaxDrawdownPct      = 10.0;      // Guardrail 1: drawdown maximo %
input double InpConfMinima          = 0.65;      // Confianca minima p/ trocar regime
input int    InpMaxMudancasDia      = 3;         // Guardrail 2: mudancas de regime/dia
input double InpSpreadMaxPips       = 3.0;       // Spread maximo (pips)
input bool   InpLogCSV              = true;      // Gravar CSVs (Common\Files\TRIVIUM369)
input long   InpMagic               = 200001;    // Magic number

//--- globals
CTrade  trade;
int     hADX, hEMA20, hEMA50, hRSI, hATR, hBands;
datetime lastBarTime = 0;

// fila de regime (5 velas)
string  regQueue[5];
double  confQueue[5];
int     regIdx = 0;
string  regimeAtual    = "INDEFINIDO";
string  regimeAnterior = "INDEFINIDO";
double  confAtual      = 0.0;
datetime tsUltimaMudanca   = 0;
datetime tsProibeMudancaAte = 0;
double  minConf        = 0.65;
int     mudancasHoje   = 0;
int     diaAtual       = -1;

// agressividade / realizacao
int     contadorFalhas = 0;
int     dealsFechadosAntes = 0;
bool    tp1Feito = false, tp2Feito = false;
double  equityPico = 0.0;
double  saldoNaEntrada = 0.0;
bool    pausado = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetDeviationInPoints(20);

   hADX   = iADX(_Symbol, InpTF, 14);
   hEMA20 = iMA(_Symbol, InpTF, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, InpTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, InpTF, 14, PRICE_CLOSE);
   hATR   = iATR(_Symbol, InpTF, 14);
   hBands = iBands(_Symbol, InpTF, 20, 0, 2.0, PRICE_CLOSE);

   if(hADX==INVALID_HANDLE || hEMA20==INVALID_HANDLE || hEMA50==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE || hBands==INVALID_HANDLE)
   {
      Print("[EA_CLAUDIO] Erro criando handles de indicadores");
      return INIT_FAILED;
   }

   for(int i=0;i<5;i++){ regQueue[i]="INDEFINIDO"; confQueue[i]=0.0; }
   minConf    = InpConfMinima;
   equityPico = AccountInfoDouble(ACCOUNT_EQUITY);
   dealsFechadosAntes = ContarDealsFechados();

   Print("[EA_CLAUDIO] Iniciado. Magic=", InpMagic, " TF=", EnumToString(InpTF));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hADX); IndicatorRelease(hEMA20); IndicatorRelease(hEMA50);
   IndicatorRelease(hRSI); IndicatorRelease(hATR);  IndicatorRelease(hBands);
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

double PipSize()
{
   return (_Digits==3 || _Digits==5) ? 10.0*_Point : _Point;
}

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
   return NormalizarLote(riskMoney / (slDistPoints*valorPorPontoLote));
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

// win rate e resultado acumulado dos trades desde um timestamp
void StatsDesde(datetime desde, int &trades, double &winRate, double &lucroTotal)
{
   trades=0; winRate=0.0; lucroTotal=0.0;
   int wins=0;
   HistorySelect(desde, TimeCurrent());
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(tk, DEAL_PROFIT)
               + HistoryDealGetDouble(tk, DEAL_SWAP)
               + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      trades++; lucroTotal += p;
      if(p>0) wins++;
   }
   if(trades>0) winRate = (double)wins/trades;
}

//+------------------------------------------------------------------+
//| SECAO 1: Deteccao de regime (fila de 5 velas)                    |
//+------------------------------------------------------------------+
void DetectarRegimeOperacional()
{
   double adx    = Buf(hADX, 0, 1);
   double ema20  = Buf(hEMA20, 0, 1);
   double ema50  = Buf(hEMA50, 0, 1);
   double bbUp   = Buf(hBands, 1, 1);
   double bbLo   = Buf(hBands, 2, 1);
   double close1 = iClose(_Symbol, InpTF, 1);
   double volMa  = VolumeMedia(20);
   double vol1   = (double)iVolume(_Symbol, InpTF, 1);
   double bbWidthPct = (close1>0) ? (bbUp-bbLo)/close1 : 0.0;

   // votacao simples da vela
   double votoTendencia=0.0, votoCompressao=0.0;
   if(adx>25 && vol1>volMa && MathAbs(ema20-ema50)>Buf(hATR,0,1)*0.3)
      votoTendencia = MathMin(1.0, 0.5 + (adx-25.0)/50.0 + 0.25);
   if(adx<20 && bbWidthPct<0.004 && vol1<volMa*0.8)
      votoCompressao = MathMin(1.0, 0.5 + (20.0-adx)/40.0 + 0.25);

   string regimeVela = "INDEFINIDO";
   double confVela   = 0.0;
   if(votoTendencia>votoCompressao && votoTendencia>0){ regimeVela="TENDENCIA"; confVela=votoTendencia; }
   else if(votoCompressao>0){ regimeVela="COMPRESSAO"; confVela=votoCompressao; }

   // guarda na fila
   regQueue[regIdx]  = regimeVela;
   confQueue[regIdx] = confVela;
   regIdx = (regIdx+1)%5;

   if(regimeVela=="INDEFINIDO") return;

   // consenso 3+ de 5 com confianca media > minimo
   int consenso=0; double somaConf=0.0;
   for(int i=0;i<5;i++)
      if(regQueue[i]==regimeVela){ consenso++; somaConf+=confQueue[i]; }
   double confConsenso = (consenso>0) ? somaConf/consenso : 0.0;

   if(consenso>=3 && confConsenso>minConf && regimeVela!=regimeAtual
      && TimeCurrent()>=tsProibeMudancaAte)
   {
      regimeAnterior   = regimeAtual;
      regimeAtual      = regimeVela;
      confAtual        = confConsenso;
      tsUltimaMudanca  = TimeCurrent();
      saldoNaEntrada   = AccountInfoDouble(ACCOUNT_BALANCE);
      mudancasHoje++;
      PrintFormat("[REGIME] Mudanca: %s -> %s (confianca %.1f%%, consenso %d/5)",
                  regimeAnterior, regimeAtual, confConsenso*100.0, consenso);
   }
}

//+------------------------------------------------------------------+
//| SECAO 4: Guardrails 1-4                                          |
//+------------------------------------------------------------------+
bool GuardrailsOperacionais()
{
   // reset diario do contador de mudancas
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day != diaAtual){ diaAtual = dt.day; mudancasHoje = 0; minConf = InpConfMinima; }

   // TRAVA 1: drawdown global
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > equityPico) equityPico = eq;
   double dd = (equityPico>0) ? (equityPico-eq)/equityPico : 0.0;
   if(dd > InpMaxDrawdownPct/100.0)
   {
      if(!pausado)
      {
         PrintFormat("[GUARDRAIL 1] Drawdown %.1f%% > %.1f%% - PAUSA", dd*100.0, InpMaxDrawdownPct);
         pausado = true;
      }
      return false;
   }
   pausado = false;

   // TRAVA 2: hiperadaptacao (mudancas demais no dia)
   if(mudancasHoje > InpMaxMudancasDia && minConf < 0.75)
   {
      minConf = 0.75;
      PrintFormat("[GUARDRAIL 2] %d mudancas hoje - confianca minima sobe p/ 75%%", mudancasHoje);
   }

   // TRAVA 3: regime novo falha (WR < 40% em 5+ trades)
   if(tsUltimaMudanca>0)
   {
      int trades; double wr, lucro;
      StatsDesde(tsUltimaMudanca, trades, wr, lucro);
      if(trades>=5 && wr<0.40)
      {
         PrintFormat("[GUARDRAIL 3] Regime %s falhou (WR %.0f%% em %d trades) - REVERTE p/ %s",
                     regimeAtual, wr*100.0, trades, regimeAnterior);
         regimeAtual = regimeAnterior;
         tsProibeMudancaAte = TimeCurrent() + 36000; // 10 horas
         tsUltimaMudanca = TimeCurrent();
      }
      // TRAVA 4: atraso de deteccao (perda > 2% do saldo desde a mudanca)
      if(saldoNaEntrada>0 && lucro/saldoNaEntrada < -0.02)
      {
         double novoMin = MathMin(0.90, minConf+0.05);
         if(novoMin>minConf)
         {
            minConf = novoMin;
            PrintFormat("[GUARDRAIL 4] Perda acumulada no regime novo - confianca minima %.0f%%", minConf*100.0);
         }
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| SECAO 5: Agressividade adaptativa (contador de falhas)           |
//+------------------------------------------------------------------+
void AtualizarAgressividade()
{
   int fechadosAgora = ContarDealsFechados();
   if(fechadosAgora <= dealsFechadosAntes) return;

   // processa apenas o deal mais recente fechado
   HistorySelect(0, TimeCurrent());
   for(int i=HistoryDealsTotal()-1; i>=0; i--)
   {
      ulong tk = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(tk, DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(tk, DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(tk, DEAL_PROFIT);
      if(p<0){ contadorFalhas++; PrintFormat("[AGRESSIVIDADE] Falha +1 (total %d)", contadorFalhas); }
      else   { contadorFalhas = MathMax(0, contadorFalhas-1); }
      break;
   }
   dealsFechadosAntes = fechadosAgora;

   if(contadorFalhas>=4)
   {
      Print("[AGRESSIVIDADE] 4+ falhas - forca reclassificacao de regime");
      confAtual = 0.0;
      regimeAtual = "INDEFINIDO";
      contadorFalhas = 0;
   }
}

//+------------------------------------------------------------------+
//| SECAO 3: Realizacao inteligente por regime                       |
//+------------------------------------------------------------------+
void RealizarLucrosParciais()
{
   if(!PositionSelect(_Symbol)){ tp1Feito=false; tp2Feito=false; return; }
   if(PositionGetInteger(POSITION_MAGIC)!=InpMagic) return;

   long   tipo   = PositionGetInteger(POSITION_TYPE);
   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double vol    = PositionGetDouble(POSITION_VOLUME);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pip    = PipSize();
   double lucroPips = (tipo==POSITION_TYPE_BUY) ? (bid-entry)/pip : (entry-ask)/pip;
   ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   double vmin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(regimeAtual=="TENDENCIA")
   {
      if(lucroPips>25 && !tp1Feito)
      {
         double v = NormalizarLote(vol*0.50);
         if(v>=vmin && vol-v>=vmin && trade.PositionClosePartial(ticket, v))
         { tp1Feito=true; Print("[REALIZA] 50% em 25 pips (Tendencia)"); }
      }
      if(lucroPips>50 && !tp2Feito && PositionSelect(_Symbol))
      {
         vol = PositionGetDouble(POSITION_VOLUME);
         double v = NormalizarLote(vol*0.60); // ~30% do original
         if(v>=vmin && vol-v>=vmin && trade.PositionClosePartial(ticket, v))
         { tp2Feito=true; Print("[REALIZA] 30% em 50 pips (Tendencia) - resto vira runner"); }
      }
      // runner: trailing stop de 1x ATR
      if(tp2Feito && PositionSelect(_Symbol))
      {
         double atr = Buf(hATR,0,1);
         double sl  = PositionGetDouble(POSITION_SL);
         double novoSL = (tipo==POSITION_TYPE_BUY) ? bid-atr : ask+atr;
         bool melhora = (tipo==POSITION_TYPE_BUY) ? (novoSL>sl) : (sl==0 || novoSL<sl);
         if(melhora) trade.PositionModify(ticket, NormalizeDouble(novoSL,_Digits), PositionGetDouble(POSITION_TP));
      }
   }
   else if(regimeAtual=="COMPRESSAO")
   {
      double saldo = AccountInfoDouble(ACCOUNT_BALANCE);
      double lucroPct = (saldo>0) ? PositionGetDouble(POSITION_PROFIT)/saldo : 0.0;
      if(lucroPct>0.01 && !tp1Feito)
      {
         double v = NormalizarLote(vol*0.60);
         if(v>=vmin && vol-v>=vmin && trade.PositionClosePartial(ticket, v))
         { tp1Feito=true; Print("[REALIZA] 60% em 1% do saldo (Compressao)"); }
      }
      if(lucroPct>0.02 && !tp2Feito && PositionSelect(_Symbol))
      {
         if(trade.PositionClose(ticket))
         { tp2Feito=true; Print("[REALIZA] Fecha resto em 2% do saldo (Compressao)"); }
      }
   }
}

//+------------------------------------------------------------------+
//| SECAO 2: Cascata operacional (entrada)                           |
//+------------------------------------------------------------------+
void ProcurarEntrada()
{
   if(PositionSelect(_Symbol)) return;              // uma posicao por vez
   if(regimeAtual=="INDEFINIDO") return;
   if(SpreadPips() > InpSpreadMaxPips) return;

   double atr    = Buf(hATR, 0, 1);
   double ema20a = Buf(hEMA20, 0, 2), ema50a = Buf(hEMA50, 0, 2);
   double ema20  = Buf(hEMA20, 0, 1), ema50  = Buf(hEMA50, 0, 1);
   double rsi    = Buf(hRSI, 0, 1);
   double bbUp   = Buf(hBands, 1, 1), bbLo = Buf(hBands, 2, 1), bbMid = Buf(hBands, 0, 1);
   double close1 = iClose(_Symbol, InpTF, 1);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double pip    = PipSize();
   if(atr<=0) return;

   if(regimeAtual=="TENDENCIA")
   {
      bool cruzouAcima  = (ema20a<=ema50a && ema20>ema50);
      bool cruzouAbaixo = (ema20a>=ema50a && ema20<ema50);
      if(cruzouAcima && rsi<75)
      {
         double sl = ask - atr*1.5;
         double tp = ask + 100*pip;   // TP final = runner 100 pips
         double lots = CalcularLote(InpRiskTendencia, (ask-sl)/_Point);
         if(lots>0 && trade.Buy(lots, _Symbol, ask, NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "CLAUDIO-TEND-BUY"))
            PrintFormat("[ENTRADA] BUY tendencia %.2f lotes (conf %.0f%%)", lots, confAtual*100.0);
      }
      else if(cruzouAbaixo && rsi>25)
      {
         double sl = bid + atr*1.5;
         double tp = bid - 100*pip;
         double lots = CalcularLote(InpRiskTendencia, (sl-bid)/_Point);
         if(lots>0 && trade.Sell(lots, _Symbol, bid, NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "CLAUDIO-TEND-SELL"))
            PrintFormat("[ENTRADA] SELL tendencia %.2f lotes (conf %.0f%%)", lots, confAtual*100.0);
      }
   }
   else if(regimeAtual=="COMPRESSAO")
   {
      if(close1<=bbLo && rsi<30)
      {
         double sl = bbLo - 10*pip - atr*0.5;
         double tp = bbMid;
         double lots = CalcularLote(InpRiskCompressao, (ask-sl)/_Point);
         if(lots>0 && trade.Buy(lots, _Symbol, ask, NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "CLAUDIO-COMP-BUY"))
            Print("[ENTRADA] BUY bounce banda inferior (Compressao)");
      }
      else if(close1>=bbUp && rsi>70)
      {
         double sl = bbUp + 10*pip + atr*0.5;
         double tp = bbMid;
         double lots = CalcularLote(InpRiskCompressao, (sl-bid)/_Point);
         if(lots>0 && trade.Sell(lots, _Symbol, bid, NormalizeDouble(sl,_Digits), NormalizeDouble(tp,_Digits), "CLAUDIO-COMP-SELL"))
            Print("[ENTRADA] SELL bounce banda superior (Compressao)");
      }
   }
}

//+------------------------------------------------------------------+
//| LOGS CSV (Common\Files\TRIVIUM369)                               |
//+------------------------------------------------------------------+
string LogPrefixo(){ return "TRIVIUM369\\EA_CLAUDIO_" + _Symbol; }

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
      "datetime,symbol,categoria,detalhe,regime,confianca,saldo,equity",
      TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS)+","+_Symbol+","+categoria+
      ",\""+detalhe+"\","+regimeAtual+","+DoubleToString(confAtual,2)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
}

void LogBarra()
{
   if(!InpLogCSV) return;
   double spreadPts = (SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;
   CsvAppend(LogPrefixo()+"_barras.csv",
      "datetime,open,high,low,close,tick_volume,spread_points,adx,ema20,ema50,rsi,atr,bb_upper,bb_lower,regime,confianca,min_conf,mudancas_hoje,contador_falhas",
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
      DoubleToString(Buf(hRSI,0,1),2)+","+
      DoubleToString(Buf(hATR,0,1),_Digits)+","+
      DoubleToString(Buf(hBands,1,1),_Digits)+","+
      DoubleToString(Buf(hBands,2,1),_Digits)+","+
      regimeAtual+","+DoubleToString(confAtual,2)+","+DoubleToString(minConf,2)+","+
      IntegerToString(mudancasHoje)+","+IntegerToString(contadorFalhas));
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
      regimeAtual+",\""+HistoryDealGetString(deal,DEAL_COMMENT)+"\","+
      DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+","+
      DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
}

//+------------------------------------------------------------------+
void OnTick()
{
   // gestao de posicao roda a cada tick
   AtualizarAgressividade();
   if(!GuardrailsOperacionais()) return;
   RealizarLucrosParciais();

   // deteccao e entrada apenas em vela nova
   datetime barTime = iTime(_Symbol, InpTF, 0);
   if(barTime==lastBarTime) return;
   lastBarTime = barTime;

   string regimeAntes = regimeAtual;
   DetectarRegimeOperacional();
   if(regimeAtual!=regimeAntes)
      LogEvento("REGIME", "Mudanca "+regimeAntes+" -> "+regimeAtual);
   LogBarra();
   ProcurarEntrada();
}
//+------------------------------------------------------------------+
