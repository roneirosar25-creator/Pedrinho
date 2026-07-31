//+------------------------------------------------------------------+
//|                                             EURUSD_Titan_AI.mq5 |
//|                                         Titan EA - AI Multi-Time |
//|                                                  EURUSD-T Master |
//+------------------------------------------------------------------+
#property copyright "Titan AI Systems"
#property version   "3.00"
#property description "EA Multi-Estrategia para EURUSD-T"
#property description "Trend Following + Momentum + Price Action"
#property description "com gestao inteligente de risco adaptativa"

#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>

input group "=== CONFIGURACOES GERAIS ==="
input ulong    MagicNumber         = 369369;
input string   TradeComment        = "TitanAI";
input bool     NewsFilterEnable    = true;
input bool     AllowMultipleOrders = false;

input group "=== GERENCIAMENTO DE RISCO ==="
input double   RiskPercent         = 1.5;
input double   FixedLotSize        = 0.0;
input double   MaxDailyRisk        = 5.0;
input double   MaxSpreadPts        = 30.0;
input bool     UseAutoLotSize      = true;

input group "=== FILTRO DE TENDENCIA (D1/H4) ==="
input int      TrendEMA_Fast       = 20;
input int      TrendEMA_Slow       = 50;
input int      TrendEMA_Major      = 200;
input int      ADX_Period          = 14;
input double   ADX_TrendThreshold  = 25.0;

input group "=== SINAIS DE ENTRADA (M15) ==="
input int      FastMA_Period       = 9;
input int      SlowMA_Period       = 21;
input int      SignalMA_Period     = 5;
input int      RSI_Period          = 14;
input double   RSI_Overbought      = 70.0;
input double   RSI_Oversold        = 30.0;
input int      Stoch_K             = 5;
input int      Stoch_D             = 3;
input int      Stoch_Slow          = 3;
input double   Stoch_Overbought    = 80.0;
input double   Stoch_Oversold      = 20.0;
input int      BB_Period           = 20;
input double   BB_Deviation        = 2.0;

input group "=== SAIDA E PROTECAO ==="
input double   StopLoss_ATR        = 1.5;
input double   TakeProfit_ATR      = 3.0;
input double   TrailStart_ATR      = 1.0;
input double   TrailStep_ATR       = 0.3;
input bool     UseBreakeven        = true;
input double   BreakevenTrigger_ATR = 1.0;
input double   BreakevenLock_ATR   = 0.2;

input group "=== FECHAMENTO PARCIAL ==="
input bool     UsePartialClose     = true;
input double   PartL1_Pct          = 30.0;
input double   PartL1_ATR          = 1.5;
input double   PartL2_Pct          = 30.0;
input double   PartL2_ATR          = 2.5;

input group "=== RECUPERACAO ==="
input bool     UseRecoveryMode     = true;
input double   RecoveryMultiplier  = 1.5;
input int      MaxRecoveryLevels   = 2;

input group "=== HORARIOS ==="
input bool     UseTradingHours     = true;
input bool     TradeLondon         = true;
input bool     TradeNewYork        = true;
input bool     TradeAsian          = false;
input bool     FridayExitBeforeClose = true;

input group "=== FILTROS ==="
input bool     UseVolatilityFilter = true;
input double   MinVolatilityATR    = 0.0001;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade         Trade;
CAccountInfo   Account;

int hFastMA, hSlowMA, hSignalMA;
int hRSI, hStoch;
int hBB, hADX, hATR;
int hTEMA_Fast, hTEMA_Slow, hTEMA_Maj;
int hATR_H4, hADX_H4;

double g_atr, g_atrH4;
datetime g_lastBar;
int g_losses;
double g_dailyRisk;
int g_tradesToday, g_totalTrades;
double g_totalPL;
bool g_recovery;
int g_recLevel;
datetime g_dayReset;
double g_trendD1, g_trendH4, g_adxD1;
bool g_upD1, g_upH4;

struct PartialRec { ulong ticket; int level; };
PartialRec g_prts[];

//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(50);
   if(!InitIndicators()) { Print("Falha indicadores"); return INIT_FAILED; }
   g_lastBar=0; g_losses=0; g_dailyRisk=0;
   g_tradesToday=0; g_totalTrades=0; g_totalPL=0;
   g_recovery=false; g_recLevel=0; g_dayReset=0;
   Print("Titan AI EA - EURUSD-T Inicializado | Magic:",MagicNumber," Risco:",RiskPercent,"%");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { ReleaseIndicators(); }

//+------------------------------------------------------------------+
void OnTick()
{
   if(!NewBar()) return;
   UpdateATR();
   UpdateDaily();
   if(SymbolInfoInteger(Symbol(),SYMBOL_SPREAD)>(int)MaxSpreadPts) return;
   if(g_dailyRisk>=MaxDailyRisk) return;
   if(NewsFilterEnable&&IsNews()) return;
   if(UseTradingHours&&!TradingHour()) return;
   if(FridayExitBeforeClose&&IsWeekendClose()){CloseAll();return;}
   UpdateTrend();
   ManagePos();
   if(!AllowMultipleOrders&&CountPos()>0) return;
   int sig=GetSignal();
   if(sig!=0) ExecTrade(sig);
}

//+------------------------------------------------------------------+
bool InitIndicators()
{
   string s=Symbol();
   hFastMA=iMA(s,PERIOD_M15,FastMA_Period,0,MODE_EMA,PRICE_CLOSE); if(hFastMA==INVALID_HANDLE)return false;
   hSlowMA=iMA(s,PERIOD_M15,SlowMA_Period,0,MODE_EMA,PRICE_CLOSE); if(hSlowMA==INVALID_HANDLE)return false;
   hSignalMA=iMA(s,PERIOD_M15,SignalMA_Period,0,MODE_EMA,PRICE_CLOSE); if(hSignalMA==INVALID_HANDLE)return false;
   hRSI=iRSI(s,PERIOD_M15,RSI_Period,PRICE_CLOSE); if(hRSI==INVALID_HANDLE)return false;
   hStoch=iStochastic(s,PERIOD_M15,Stoch_K,Stoch_D,Stoch_Slow,MODE_SMA,STO_LOWHIGH); if(hStoch==INVALID_HANDLE)return false;
   hBB=iBands(s,PERIOD_M15,BB_Period,0,BB_Deviation,PRICE_CLOSE); if(hBB==INVALID_HANDLE)return false;
   hADX=iADX(s,PERIOD_M15,ADX_Period); if(hADX==INVALID_HANDLE)return false;
   hATR=iATR(s,PERIOD_M15,14); if(hATR==INVALID_HANDLE)return false;
   hTEMA_Fast=iMA(s,PERIOD_D1,TrendEMA_Fast,0,MODE_EMA,PRICE_CLOSE); if(hTEMA_Fast==INVALID_HANDLE)return false;
   hTEMA_Slow=iMA(s,PERIOD_D1,TrendEMA_Slow,0,MODE_EMA,PRICE_CLOSE); if(hTEMA_Slow==INVALID_HANDLE)return false;
   hTEMA_Maj=iMA(s,PERIOD_D1,TrendEMA_Major,0,MODE_EMA,PRICE_CLOSE); if(hTEMA_Maj==INVALID_HANDLE)return false;
   hATR_H4=iATR(s,PERIOD_H4,14); if(hATR_H4==INVALID_HANDLE)return false;
   hADX_H4=iADX(s,PERIOD_H4,ADX_Period); if(hADX_H4==INVALID_HANDLE)return false;
   return true;
}

//+------------------------------------------------------------------+
void ReleaseIndicators()
{
   if(hFastMA!=INVALID_HANDLE) IndicatorRelease(hFastMA);
   if(hSlowMA!=INVALID_HANDLE) IndicatorRelease(hSlowMA);
   if(hSignalMA!=INVALID_HANDLE) IndicatorRelease(hSignalMA);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hBB!=INVALID_HANDLE) IndicatorRelease(hBB);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hTEMA_Fast!=INVALID_HANDLE) IndicatorRelease(hTEMA_Fast);
   if(hTEMA_Slow!=INVALID_HANDLE) IndicatorRelease(hTEMA_Slow);
   if(hTEMA_Maj!=INVALID_HANDLE) IndicatorRelease(hTEMA_Maj);
   if(hATR_H4!=INVALID_HANDLE) IndicatorRelease(hATR_H4);
   if(hADX_H4!=INVALID_HANDLE) IndicatorRelease(hADX_H4);
}

//+------------------------------------------------------------------+
bool NewBar()
{
   datetime t=iTime(Symbol(),PERIOD_M15,0);
   if(t==0) return false;
   if(t!=g_lastBar){g_lastBar=t; return true;}
   return false;
}

//+------------------------------------------------------------------+
void UpdateATR()
{
   double b[1];
   if(CopyBuffer(hATR,0,0,1,b)==1) g_atr=b[0];
   if(CopyBuffer(hATR_H4,0,0,1,b)==1) g_atrH4=b[0];
}

//+------------------------------------------------------------------+
void UpdateDaily()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today=StringToTime(StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day));
   if(today!=g_dayReset)
   {
      g_dayReset=today; g_dailyRisk=0; g_tradesToday=0;
      if(g_totalPL>0&&g_recovery){g_recovery=false; g_recLevel=0; g_losses=0;}
   }
}

//+------------------------------------------------------------------+
bool IsNews()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week==5&&dt.hour==12&&dt.min>=25&&dt.min<=35&&dt.day<=7) return true;
   if(dt.day_of_week==3&&dt.hour>=17&&dt.hour<=19) return true;
   if((dt.hour==12&&dt.min>=25&&dt.min<=35)||(dt.hour==14&&dt.min>=55&&dt.min<=60)) return true;
   return false;
}

//+------------------------------------------------------------------+
bool TradingHour()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int h=dt.hour, w=dt.day_of_week;
   if(w==6||w==0) return false;
   if(TradeLondon&&h>=7&&h<16) return true;
   if(TradeNewYork&&h>=12&&h<21) return true;
   if(TradeAsian&&h>=0&&h<9) return true;
   return (h>=7&&h<21);
}

//+------------------------------------------------------------------+
bool IsWeekendClose()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return (dt.day_of_week==5&&dt.hour>=20);
}

//+------------------------------------------------------------------+
void UpdateTrend()
{
   double b1[1],b2[1],b3[1];
   string s=Symbol();
   if(CopyBuffer(hTEMA_Fast,0,0,1,b1)==1&&CopyBuffer(hTEMA_Slow,0,1,1,b2)==1&&CopyBuffer(hTEMA_Maj,0,1,1,b3)==1)
   {
      double cd1=iClose(s,PERIOD_D1,0);
      g_upD1=(cd1>b3[0])&&(b1[0]>b2[0]);
      g_trendD1=(cd1>b1[0])?1.0:-1.0;
      if(CopyBuffer(hADX_H4,0,0,1,b1)==1) g_adxD1=b1[0];
   }
   int h4f=iMA(s,PERIOD_H4,TrendEMA_Fast,0,MODE_EMA,PRICE_CLOSE);
   int h4s=iMA(s,PERIOD_H4,TrendEMA_Slow,0,MODE_EMA,PRICE_CLOSE);
   if(h4f!=INVALID_HANDLE&&h4s!=INVALID_HANDLE)
   {
      if(CopyBuffer(h4f,0,0,1,b1)==1&&CopyBuffer(h4s,0,0,1,b2)==1)
      { g_upH4=(b1[0]>b2[0]); g_trendH4=(iClose(s,PERIOD_H4,0)>b1[0])?1.0:-1.0; }
      IndicatorRelease(h4f); IndicatorRelease(h4s);
   }
}

//+------------------------------------------------------------------+
int GetSignal()
{
   double fMA[2],sMA[2],sigMA[2];
   double rsi[2],stM[2],stS[2];
   double bbU[1],bbL[1],bbM[1];
   double adxM[2],adxP[2],adxN[2];
   double pr[2];
   string sym=Symbol();
   if(CopyBuffer(hFastMA,0,0,2,fMA)<2)return 0;
   if(CopyBuffer(hSlowMA,0,0,2,sMA)<2)return 0;
   if(CopyBuffer(hSignalMA,0,0,2,sigMA)<2)return 0;
   if(CopyBuffer(hRSI,0,0,2,rsi)<2)return 0;
   if(CopyBuffer(hStoch,0,0,2,stM)<2)return 0;
   if(CopyBuffer(hStoch,1,0,2,stS)<2)return 0;
   if(CopyBuffer(hBB,0,0,1,bbM)<1)return 0;
   if(CopyBuffer(hBB,1,0,1,bbU)<1)return 0;
   if(CopyBuffer(hBB,2,0,1,bbL)<1)return 0;
   if(CopyBuffer(hADX,0,0,2,adxM)<2)return 0;
   if(CopyBuffer(hADX,1,0,2,adxP)<2)return 0;
   if(CopyBuffer(hADX,2,0,2,adxN)<2)return 0;
   if(CopyClose(sym,PERIOD_M15,0,2,pr)<2)return 0;
   if(UseVolatilityFilter&&g_atr<MinVolatilityATR)return 0;

   double buy=0,sell=0;
   if(g_upD1&&g_trendD1>0){buy+=25; if(g_adxD1>ADX_TrendThreshold)buy+=10;}
   else if(!g_upD1&&g_trendD1<0){sell+=25; if(g_adxD1>ADX_TrendThreshold)sell+=10;}
   if(g_upH4)buy+=10; else sell+=10;

   if(fMA[1]<=sMA[1]&&fMA[0]>sMA[0])buy+=20;
   else if(fMA[1]>=sMA[1]&&fMA[0]<sMA[0])sell+=20;
   if(fMA[0]>sMA[0])buy+=5; else sell+=5;
   if(pr[0]>sigMA[0])buy+=5; else sell+=5;

   if(rsi[1]<RSI_Oversold&&rsi[0]>RSI_Oversold&&rsi[0]<50)buy+=15;
   else if(rsi[1]>RSI_Overbought&&rsi[0]<RSI_Overbought&&rsi[0]>50)sell+=15;
   if(rsi[0]<40&&rsi[0]>RSI_Oversold)buy+=5;
   if(rsi[0]>60&&rsi[0]<RSI_Overbought)sell+=5;
   if(pr[1]>pr[0]&&rsi[1]<rsi[0])buy+=8;
   else if(pr[1]<pr[0]&&rsi[1]>rsi[0])sell+=8;

   if(stM[1]<Stoch_Oversold&&stM[0]>Stoch_Oversold&&stM[0]<40)buy+=10;
   else if(stM[1]>Stoch_Overbought&&stM[0]<Stoch_Overbought&&stM[0]>60)sell+=10;
   if(stM[1]<stS[1]&&stM[0]>stS[0])buy+=5;
   else if(stM[1]>stS[1]&&stM[0]<stS[0])sell+=5;

   if(pr[0]<bbL[0]&&pr[0]>bbL[0]*0.995)buy+=10;
   else if(pr[0]>bbU[0]&&pr[0]<bbU[0]*1.005)sell+=10;

   double thr=45.0;
   if(buy>sell&&buy>=thr){if(adxM[0]<20&&buy<60)return 0; return 1;}
   else if(sell>buy&&sell>=thr){if(adxM[0]<20&&sell<60)return 0; return -1;}
   return 0;
}

//+------------------------------------------------------------------+
double CalcLot()
{
   string sym=Symbol();
   double minL=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxL=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   if(FixedLotSize>0) return NormalizeDouble(MathMin(FixedLotSize,maxL),2);
   double bal=Account.Balance();
   double riskAmt=bal*RiskPercent/100.0;
   double slPts=g_atr*StopLoss_ATR/SymbolInfoDouble(sym,SYMBOL_POINT);
   double tickVal=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   if(tickVal<=0||slPts<=0)return minL;
   double mult=1.0;
   if(g_recovery&&UseRecoveryMode){mult=MathPow(RecoveryMultiplier,g_recLevel); mult=MathMin(mult,MathPow(RecoveryMultiplier,MaxRecoveryLevels));}
   double lot=(riskAmt*mult)/(slPts*tickVal);
   if(UseAutoLotSize&&g_losses>0){double red=1.0-(0.1*MathMin(g_losses,5)); lot*=MathMax(red,0.5);}
   lot=MathFloor(lot/step)*step;
   lot=MathMax(minL,MathMin(lot,maxL));
   return NormalizeDouble(lot,2);
}

//+------------------------------------------------------------------+
double CalcSL(int sig)
{
   string sym=Symbol();
   double sl=g_atr*StopLoss_ATR;
   double p=(sig>0)?SymbolInfoDouble(sym,SYMBOL_ASK):SymbolInfoDouble(sym,SYMBOL_BID);
   double out=(sig>0)?p-sl:p+sl;
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   out=MathRound(out/ts)*ts;
   return NormalizeDouble(out,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
double CalcTP(int sig)
{
   string sym=Symbol();
   double tp=g_atr*TakeProfit_ATR;
   double p=(sig>0)?SymbolInfoDouble(sym,SYMBOL_ASK):SymbolInfoDouble(sym,SYMBOL_BID);
   double out=(sig>0)?p+tp:p-tp;
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   out=MathRound(out/ts)*ts;
   return NormalizeDouble(out,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
void ExecTrade(int sig)
{
   string sym=Symbol();
   double lot=CalcLot();
   if(lot<SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN)){Print("Lote minimo:",lot); return;}
   double pr=(sig>0)?SymbolInfoDouble(sym,SYMBOL_ASK):SymbolInfoDouble(sym,SYMBOL_BID);
   double sl=CalcSL(sig),tp=CalcTP(sig);
   double dist=MathAbs(pr-sl);
   double minD=SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL)*SymbolInfoDouble(sym,SYMBOL_POINT);
   if(dist<minD){if(sig>0)sl=pr-minD; else sl=pr+minD;}
   bool ok=(sig>0)?Trade.Buy(lot,sym,pr,sl,tp,TradeComment):Trade.Sell(lot,sym,pr,sl,tp,TradeComment);
   if(ok){g_tradesToday++; Print("[TRADE]",(sig>0?"COMPRA":"VENDA")," Lote:",lot," Entry:",pr," SL:",sl," TP:",tp);}
   else Print("[ERRO]",GetLastError());
}

//+------------------------------------------------------------------+
int CountPos()
{
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i); if(PositionSelectByTicket(t)&&PositionGetString(POSITION_SYMBOL)==Symbol()&&PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber)c++;}
   return c;
}

//+------------------------------------------------------------------+
bool IsOurs(ulong t)
{
   if(!PositionSelectByTicket(t)) return false;
   return (PositionGetString(POSITION_SYMBOL)==Symbol()&&PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber);
}

//+------------------------------------------------------------------+
void ManagePos()
{
   string sym=Symbol();
   double bid=SymbolInfoDouble(sym,SYMBOL_BID),ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double minL=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN), stepL=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurs(ticket)) continue;
      double openP=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL),curTP=PositionGetDouble(POSITION_TP);
      double vol=PositionGetDouble(POSITION_VOLUME);
      int type=(int)PositionGetInteger(POSITION_TYPE);

      if(UseBreakeven)
      {
         double trig=g_atr*BreakevenTrigger_ATR,lock=g_atr*BreakevenLock_ATR;
         if(type==POSITION_TYPE_BUY&&bid-openP>=trig&&(curSL<=0||curSL<openP+lock))
         {double nsl=openP+lock; if(Trade.PositionModify(ticket,NormalizeDouble(nsl,digits),curTP))Print("[BE]BUY#",ticket);}
         else if(type==POSITION_TYPE_SELL&&openP-ask>=trig&&(curSL<=0||curSL>openP-lock))
         {double nsl=openP-lock; if(Trade.PositionModify(ticket,NormalizeDouble(nsl,digits),curTP))Print("[BE]SELL#",ticket);}
      }

      double tStart=g_atr*TrailStart_ATR,tStep=g_atr*TrailStep_ATR;
      if(type==POSITION_TYPE_BUY&&bid-openP>tStart)
      {
         double nsl=bid-tStart+tStep;
         if(curSL<0||nsl>curSL+tStep*0.5){nsl=MathFloor(nsl/ts)*ts; if(Trade.PositionModify(ticket,NormalizeDouble(nsl,digits),curTP))Print("[TRAIL]BUY#",ticket);}
      }
      else if(type==POSITION_TYPE_SELL&&openP-ask>tStart)
      {
         double nsl=ask+tStart-tStep;
         if(curSL<0||nsl<curSL-tStep*0.5){nsl=MathCeil(nsl/ts)*ts; if(Trade.PositionModify(ticket,NormalizeDouble(nsl,digits),curTP))Print("[TRAIL]SELL#",ticket);}
      }

      if(UsePartialClose&&vol>minL*1.5)
      {
         double pts=(type==POSITION_TYPE_BUY)?(bid-openP):(openP-ask);
         double atrP=pts/g_atr;
         if(atrP>=PartL1_ATR&&atrP<PartL2_ATR&&!HasPart(ticket,1))
         {double cv=MathFloor(vol*PartL1_Pct/100.0/stepL)*stepL; if(cv>=minL){Trade.PositionClosePartial(ticket,cv,-1);AddPart(ticket,1);Print("[PARTIAL]L1#",ticket);}}
         else if(atrP>=PartL2_ATR&&!HasPart(ticket,2))
         {double cv=MathFloor(vol*PartL2_Pct/100.0/stepL)*stepL; if(cv>=minL){Trade.PositionClosePartial(ticket,cv,-1);AddPart(ticket,2);Print("[PARTIAL]L2#",ticket);}}
      }
   }
}

//+------------------------------------------------------------------+
bool HasPart(ulong t,int l){for(int i=0;i<ArraySize(g_prts);i++)if(g_prts[i].ticket==t&&g_prts[i].level==l)return true; return false;}
void AddPart(ulong t,int l){int sz=ArraySize(g_prts); ArrayResize(g_prts,sz+1); g_prts[sz].ticket=t; g_prts[sz].level=l;}

//+------------------------------------------------------------------+
void CloseAll(){for(int i=PositionsTotal()-1;i>=0;i--){ulong t=PositionGetTicket(i); if(IsOurs(t))Trade.PositionClose(t);}}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD&&trans.symbol==Symbol())
   {
      ulong deal=trans.deal;
      if(deal>0&&HistoryDealSelect(deal))
      {
         if(HistoryDealGetInteger(deal,DEAL_MAGIC)!=(long)MagicNumber) return;
         double profit=HistoryDealGetDouble(deal,DEAL_PROFIT);
         if(profit==0) return;
         g_totalPL+=profit; g_totalTrades++;
         if(profit<0){g_losses++; g_dailyRisk+=MathAbs(profit)/Account.Balance()*100.0; if(UseRecoveryMode&&g_losses>=2){g_recovery=true; g_recLevel=MathMin(g_losses-1,MaxRecoveryLevels);}}
         else{if(g_losses>0){g_losses--; if(g_losses<=0){g_recovery=false; g_recLevel=0;}}}
         Print("[RESULT]T#",g_totalTrades," PL:",profit," Total:",g_totalPL," Losses:",g_losses);
      }
   }
}
//+------------------------------------------------------------------+
