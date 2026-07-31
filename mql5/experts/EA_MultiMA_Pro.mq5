//+------------------------------------------------------------------+
//|                                            EA_MultiMA_Pro.mq5     |
//|               Expert Advisor Automatico Multi-Timeframe           |
//|                                    by AAIF (Agentic AI Foundation)|
//+------------------------------------------------------------------+
#property copyright "AAIF - Agentic AI Foundation"
#property link      "https://aai.foundation"
#property version   "1.01"
#property description "EA Automatico baseado em MultiMA + RSI + Filtros"
#property description "Opera EURUSD em multiplos timeframes"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//+------------------------------------------------------------------+
//--- INPUTS - ESTRATEGIA
//+------------------------------------------------------------------+
input string   InpStrategy_1 = "====== ESTRATEGIA ======";
input int      InpMAPeriodFast = 9;
input int      InpMAPeriodMedium = 21;
input int      InpRSIPeriod = 14;
input int      InpRSIMax = 70;
input int      InpRSIMin = 30;
input ENUM_TIMEFRAMES InpTradeTF = PERIOD_H1;
input ENUM_TIMEFRAMES InpTrendTF = PERIOD_H4;

//+------------------------------------------------------------------+
//--- INPUTS - RISCO
//+------------------------------------------------------------------+
input string   InpRisk_1 = "====== GERENCIAMENTO ======";
input double   InpRiskPercent = 1.0;
input double   InpLotFixed = 0.01;
enum ENUM_RISK_TYPE { RISK_FIXED, RISK_PERCENT };
input ENUM_RISK_TYPE InpRiskType = RISK_PERCENT;
input int      InpStopLoss = 200;
input int      InpTakeProfit = 400;
input int      InpTrailStart = 100;
input int      InpTrailStep = 50;
input bool     InpUseBreakeven = true;
input int      InpBreakEvenTrigger = 150;

//+------------------------------------------------------------------+
//--- INPUTS - FILTROS
//+------------------------------------------------------------------+
input string   InpFilter_1 = "====== FILTROS ======";
input bool     InpUseRSIFilter = true;
input bool     InpUseTrendFilter = true;
input bool     InpUseTimeFilter = false;
input string   InpTradeStart = "08:00";
input string   InpTradeEnd = "17:00";
input bool     InpTradeOnFriday = false;
input bool     InpTradeOnMonday = true;

//+------------------------------------------------------------------+
//--- INPUTS - MONEY MGMT
//+------------------------------------------------------------------+
input string   InpMM_1 = "====== MONEY MGMT ======";
input bool     InpUseMartingale = false;
input int      InpMaxOrdersPerDay = 3;
input int      InpMaxSpread = 30;
input double   InpMaxSlippage = 10;

//+------------------------------------------------------------------+
//--- INPUTS - GERAIS
//+------------------------------------------------------------------+
input string   InpGeneral_1 = "====== GERAIS ======";
input string   InpSymbol = "EURUSD-T";
input int      InpMagicNumber = 20240701;
input bool     InpShowPanel = true;
input bool     InpAlerts = true;
input bool     InpCloseOnOpposite = true;

//+------------------------------------------------------------------+
//--- GLOBAIS
//+------------------------------------------------------------------+
CTrade         g_trade;
CPositionInfo  g_pos;
CAccountInfo   g_account;
CSymbolInfo    g_sym;

datetime g_lastBarTime = 0;
int      g_ordersToday = 0;
int      g_lastOrderDay = 0;
int      g_totalTrades = 0;
int      g_winTrades = 0;
int      g_lossTrades = 0;
double   g_totalProfit = 0;
datetime g_startTime = 0;
string   g_ver = "1.01";

//+------------------------------------------------------------------+
int OnInit() {
   g_sym.Name(InpSymbol);
   if(!g_sym.Refresh()) {
      Print("Erro: simbolo ", InpSymbol, " nao encontrado");
      return(INIT_FAILED);
   }
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints((int)InpMaxSlippage);
   g_trade.SetAsyncMode(false);
   g_startTime = TimeCurrent();
   ChartSetInteger(0, CHART_SHOW, false);
   Print("EA_MultiMA_Pro v", g_ver, " para ", InpSymbol, " | Magic: ", InpMagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "EA_MM_");
   Comment("");
   Print("Finalizado. Trades: ", g_totalTrades, " W:", g_winTrades, " L:", g_lossTrades);
}

//+------------------------------------------------------------------+
void OnTick() {
   datetime barTime = iTime(InpSymbol, InpTradeTF, 0);
   if(barTime == g_lastBarTime) {
      if(InpTrailStart > 0) ManageTrailingStops();
      if(InpUseBreakeven) ManageBreakeven();
      if(InpShowPanel) DrawPanel();
      return;
   }
   g_lastBarTime = barTime;
   
   if(!CanTrade()) return;
   
   MqlDateTime dt;
   TimeToStruct(barTime, dt);
   if(dt.day != g_lastOrderDay) {
      g_ordersToday = 0;
      g_lastOrderDay = dt.day;
   }
   
   if(g_ordersToday >= InpMaxOrdersPerDay) {
      if(InpAlerts) Comment("Limite diario: ", g_ordersToday, "/", InpMaxOrdersPerDay);
      return;
   }
   
   int signal = GetSignal();
   
   if(signal == 1) {
      if(InpCloseOnOpposite) CloseOpposite(POSITION_TYPE_SELL);
      if(!HasPosition(POSITION_TYPE_BUY)) ExecuteBuy();
   }
   else if(signal == -1) {
      if(InpCloseOnOpposite) CloseOpposite(POSITION_TYPE_BUY);
      if(!HasPosition(POSITION_TYPE_SELL)) ExecuteSell();
   }
   
   if(InpShowPanel) DrawPanel();
}

//+------------------------------------------------------------------+
bool CanTrade() {
   if(!g_sym.Refresh()) return false;
   int spread = (int)g_sym.Spread();
   if(spread > InpMaxSpread) {
      if(InpAlerts) Comment("Spread alto: ", spread);
      return false;
   }
   if(InpUseTimeFilter) {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(!InpTradeOnFriday && dt.day_of_week == 5) return false;
      if(!InpTradeOnMonday && dt.day_of_week == 1) return false;
      string timeStr = TimeToString(TimeCurrent(), TIME_MINUTES);
      if(timeStr < InpTradeStart || timeStr > InpTradeEnd) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
int GetSignal() {
   //--- Get ALL data first (trend + trade TFs)
   double trendFast  = CalcEMA(InpTrendTF, InpMAPeriodFast, 0);
   double trendMed   = CalcEMA(InpTrendTF, InpMAPeriodMedium, 0);
   double trendFast1 = CalcEMA(InpTrendTF, InpMAPeriodFast, 1);
   double trendMed1  = CalcEMA(InpTrendTF, InpMAPeriodMedium, 1);
   double trendRSI   = CalcRSI(InpTrendTF, InpRSIPeriod, 0);
   
   double tradeFast  = CalcEMA(InpTradeTF, InpMAPeriodFast, 0);
   double tradeMed   = CalcEMA(InpTradeTF, InpMAPeriodMedium, 0);
   double tradeFast1 = CalcEMA(InpTradeTF, InpMAPeriodFast, 1);
   double tradeMed1  = CalcEMA(InpTradeTF, InpMAPeriodMedium, 1);
   double tradeRSI   = CalcRSI(InpTradeTF, InpRSIPeriod, 0);
   
   if(trendFast==0 || trendMed==0 || tradeFast==0 || tradeMed==0) return 0;
   
   bool trendUp = (trendFast > trendMed);
   bool trendDn = (trendFast < trendMed);
   
   bool crossUp = (tradeFast1 <= tradeMed1 && tradeFast > tradeMed);
   bool crossDn = (tradeFast1 >= tradeMed1 && tradeFast < tradeMed);
   
   //--- Pullback: price approaching EMA21 with trend confirmation
   double midLine = (tradeFast + tradeMed) / 2.0;
   bool pullbackBuy  = (tradeFast > tradeMed && tradeFast < tradeMed * 1.002);
   bool pullbackSell = (tradeFast < tradeMed && tradeFast > tradeMed * 0.998);
   
   //--- BUY
   if(crossUp && tradeRSI < InpRSIMax && tradeRSI > 25) {
      if(InpUseTrendFilter && !trendUp) return 0;
      if(InpUseRSIFilter && (tradeRSI > InpRSIMax || trendRSI > InpRSIMax)) return 0;
      return 1;
   }
   if(pullbackBuy && trendUp && tradeRSI > 40 && tradeRSI < InpRSIMax) {
      return 1;
   }
   
   //--- SELL
   if(crossDn && tradeRSI > InpRSIMin && tradeRSI < 75) {
      if(InpUseTrendFilter && !trendDn) return 0;
      if(InpUseRSIFilter && (tradeRSI < InpRSIMin || trendRSI < InpRSIMin)) return 0;
      return -1;
   }
   if(pullbackSell && trendDn && tradeRSI < 60 && tradeRSI > InpRSIMin) {
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//--- EMA VERDADEIRA (Exponencial)
//+------------------------------------------------------------------+
double CalcEMA(ENUM_TIMEFRAMES tf, int period, int shift) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(InpSymbol, tf, 0, period+shift+50, rates);
   if(copied < period+shift+5) return 0;
   
   double k = 2.0 / (period + 1);
   int startIdx = copied - 1; // oldest bar
   
   //--- SMA inicial
   double ema = 0;
   for(int i=0; i<period; i++) ema += rates[copied-1-i].close;
   ema /= period;
   
   //--- calcular EMA para cada barra
   for(int i=copied-period-1; i>=0; i--) {
      ema = rates[i].close * k + ema * (1 - k);
   }
   
   //--- No shift=0, o valor esta em rates[0]
   //--- Para shift>0, precisamos recalcular
   if(shift == 0) return ema;
   
   //--- Recalcular para o shift desejado
   ema = 0;
   for(int i=0; i<period; i++) ema += rates[copied-1-i].close;
   ema /= period;
   
   for(int i=copied-period-1; i>=shift; i--) {
      ema = rates[i].close * k + ema * (1 - k);
   }
   
   return ema;
}

//+------------------------------------------------------------------+
//--- RSI CORRETO (Wilder)
//+------------------------------------------------------------------+
double CalcRSI(ENUM_TIMEFRAMES tf, int period, int shift) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(InpSymbol, tf, 0, period+shift+50, rates);
   if(copied < period+shift+5) return 50;
   
   //--- Calcular ganhos/perdas iniciais
   double avgGain = 0, avgLoss = 0;
   for(int i=copied-2; i>=copied-1-period; i--) {
      double diff = rates[i].close - rates[i+1].close;
      if(diff > 0) avgGain += diff;
      else avgLoss -= diff;
   }
   avgGain /= period;
   avgLoss /= period;
   
   if(avgLoss == 0) return 100;
   
   //--- Wilder smoothing
   for(int i=copied-2-period; i>=shift; i--) {
      double diff = rates[i].close - rates[i+1].close;
      double gain = (diff > 0) ? diff : 0;
      double loss = (diff < 0) ? -diff : 0;
      avgGain = (avgGain * (period-1) + gain) / period;
      avgLoss = (avgLoss * (period-1) + loss) / period;
   }
   
   if(avgLoss == 0) return 100;
   double rs = avgGain / avgLoss;
   return 100 - 100 / (1 + rs);
}

//+------------------------------------------------------------------+
void ExecuteBuy() {
   g_sym.Refresh();
   double price = g_sym.Ask();
   double sl = (InpStopLoss > 0) ? price - InpStopLoss * g_sym.Point() : 0;
   double tp = (InpTakeProfit > 0) ? price + InpTakeProfit * g_sym.Point() : 0;
   double lot = CalculateLot();
   if(lot < g_sym.LotsMin()) { Print("Lote minimo: ", g_sym.LotsMin()); return; }
   
   if(g_trade.Buy(lot, InpSymbol, price, sl, tp, "EA_MM_Pro Buy")) {
      g_ordersToday++; g_totalTrades++;
      Print("BUY ", lot, " lotes @ ", price, " SL:", sl, " TP:", tp);
      if(InpAlerts) PlaySound("alert.wav");
   }
}

//+------------------------------------------------------------------+
void ExecuteSell() {
   g_sym.Refresh();
   double price = g_sym.Bid();
   double sl = (InpStopLoss > 0) ? price + InpStopLoss * g_sym.Point() : 0;
   double tp = (InpTakeProfit > 0) ? price - InpTakeProfit * g_sym.Point() : 0;
   double lot = CalculateLot();
   if(lot < g_sym.LotsMin()) { Print("Lote minimo: ", g_sym.LotsMin()); return; }
   
   if(g_trade.Sell(lot, InpSymbol, price, sl, tp, "EA_MM_Pro Sell")) {
      g_ordersToday++; g_totalTrades++;
      Print("SELL ", lot, " lotes @ ", price, " SL:", sl, " TP:", tp);
      if(InpAlerts) PlaySound("alert.wav");
   }
}

//+------------------------------------------------------------------+
double CalculateLot() {
   if(InpRiskType == RISK_FIXED) {
      double lot = InpLotFixed;
      lot = MathMax(lot, g_sym.LotsMin());
      lot = MathMin(lot, g_sym.LotsMax());
      return NormalizeDouble(lot, 2);
   }
   else {
      double balance = g_account.Balance();
      double riskMoney = balance * InpRiskPercent / 100.0;
      double tickValue = g_sym.TickValue();
      double tickSize  = g_sym.TickSize();
      if(tickValue == 0 || tickSize == 0) return InpLotFixed;
      double stopLossMoney = InpStopLoss * g_sym.Point();
      double lot = riskMoney / (stopLossMoney / tickSize * tickValue);
      double step = g_sym.LotsStep();
      if(step > 0) lot = MathFloor(lot / step) * step;
      lot = MathMax(lot, g_sym.LotsMin());
      lot = MathMin(lot, g_sym.LotsMax());
      if(InpUseMartingale) {
         int losses = CountConsecutiveLosses();
         if(losses > 0) lot *= MathPow(2, losses);
      }
      return NormalizeDouble(lot, 2);
   }
}

//+------------------------------------------------------------------+
int CountConsecutiveLosses() {
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   int losses = 0;
   for(int i=total-1; i>=0; i--) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != InpSymbol) continue;
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit < 0) losses++; else break;
   }
   return losses;
}

//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE type) {
   for(int i=0; i<PositionsTotal(); i++) {
      if(g_pos.SelectByIndex(i))
         if(g_pos.Symbol()==InpSymbol && g_pos.Magic()==InpMagicNumber && g_pos.PositionType()==type)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void CloseOpposite(ENUM_POSITION_TYPE type) {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(g_pos.SelectByIndex(i))
         if(g_pos.Symbol()==InpSymbol && g_pos.Magic()==InpMagicNumber && g_pos.PositionType()==type)
            g_trade.PositionClose(g_pos.Ticket());
   }
}

//+------------------------------------------------------------------+
void ManageTrailingStops() {
   double point = g_sym.Point();
   for(int i=0; i<PositionsTotal(); i++) {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=InpSymbol || g_pos.Magic()!=InpMagicNumber) continue;
      
      if(g_pos.PositionType() == POSITION_TYPE_BUY) {
         double profitPts = (g_sym.Bid() - g_pos.PriceOpen()) / point;
         if(profitPts >= InpTrailStart) {
            double newSL = g_sym.Bid() - (InpTrailStart - InpTrailStep) * point;
            if(newSL > g_pos.StopLoss())
               g_trade.PositionModify(g_pos.Ticket(), newSL, g_pos.TakeProfit());
         }
      }
      else if(g_pos.PositionType() == POSITION_TYPE_SELL) {
         double profitPts = (g_pos.PriceOpen() - g_sym.Ask()) / point;
         if(profitPts >= InpTrailStart) {
            double newSL = g_sym.Ask() + (InpTrailStart - InpTrailStep) * point;
            if(g_pos.StopLoss()==0 || newSL < g_pos.StopLoss())
               g_trade.PositionModify(g_pos.Ticket(), newSL, g_pos.TakeProfit());
         }
      }
   }
}

//+------------------------------------------------------------------+
void ManageBreakeven() {
   double point = g_sym.Point();
   for(int i=0; i<PositionsTotal(); i++) {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=InpSymbol || g_pos.Magic()!=InpMagicNumber) continue;
      
      if(g_pos.PositionType() == POSITION_TYPE_BUY) {
         double profitPts = (g_sym.Bid() - g_pos.PriceOpen()) / point;
         if(profitPts >= InpBreakEvenTrigger && g_pos.StopLoss() < g_pos.PriceOpen())
            g_trade.PositionModify(g_pos.Ticket(), g_pos.PriceOpen()+5*point, g_pos.TakeProfit());
      }
      else if(g_pos.PositionType() == POSITION_TYPE_SELL) {
         double profitPts = (g_pos.PriceOpen() - g_sym.Ask()) / point;
         if(profitPts >= InpBreakEvenTrigger && (g_pos.StopLoss()==0 || g_pos.StopLoss()>g_pos.PriceOpen()))
            g_trade.PositionModify(g_pos.Ticket(), g_pos.PriceOpen()-5*point, g_pos.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
void OnTrade() { if(InpShowPanel) DrawPanel(); }

//+------------------------------------------------------------------+
void DrawPanel() {
   string prefix = "EA_MM_";
   int x=10, y=30, w=340, h=320;
   
   ObjectCreate(0, prefix+"bg", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_XDISTANCE, x-5);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_YDISTANCE, y-5);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_XSIZE, w);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_YSIZE, h);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, prefix+"bg", OBJPROP_FILL, true);
   
   y += 5;
   DrawLabel(prefix+"title", x+5, y, "=== EA MultiMA Pro v"+g_ver+" ===", clrGold, 10); y+=20;
   
   double balance = g_account.Balance();
   double equity  = g_account.Equity();
   
   DrawLabel(prefix+"bal", x+5, y, "Saldo: $"+DoubleToString(balance,2), clrWhite, 9); y+=15;
   DrawLabel(prefix+"eq", x+5, y, "Equity: $"+DoubleToString(equity,2),
             (equity>=balance)?clrLimeGreen:clrRed, 9); y+=15;
   DrawLabel(prefix+"dd", x+5, y, "Drawdown: "+DoubleToString((1-equity/balance)*100,1)+"%",
             clrYellow, 9); y+=18;
   
   DrawLabel(prefix+"sep1", x+5, y, "------------------------------", clrGray, 9); y+=16;
   
   //--- positions
   double posProfit=0; int posCount=0;
   for(int i=0;i<PositionsTotal();i++) {
      if(g_pos.SelectByIndex(i))
         if(g_pos.Symbol()==InpSymbol && g_pos.Magic()==InpMagicNumber) {
            posProfit+=g_pos.Profit(); posCount++;
         }
   }
   DrawLabel(prefix+"pos", x+5, y, "Pos.: "+IntegerToString(posCount)+" Lucro: $"+DoubleToString(posProfit,2),
             (posProfit>=0)?clrLimeGreen:clrRed, 9); y+=15;
   
   //--- signal
   int sig = GetSignal();
   string sigStr = (sig==1)?"COMPRA ↑":(sig==-1)?"VENDA ↓":"AGUARDANDO ↔";
   color sigC = (sig==1)?clrLime:(sig==-1)?clrRed:clrYellow;
   DrawLabel(prefix+"sig", x+5, y, "Sinal: "+sigStr, sigC, 11); y+=20;
   
   //--- TFs
   string tfTrade = StringSubstr(EnumToString(InpTradeTF),7);
   string tfTrend = StringSubstr(EnumToString(InpTrendTF),7);
   DrawLabel(prefix+"tf", x+5, y, "TF Entrada: "+tfTrade+" | TF Tend.: "+tfTrend, clrCyan, 9); y+=15;
   
   //--- stats
   DrawLabel(prefix+"stats", x+5, y, "Total: "+IntegerToString(g_totalTrades)+
             " W:"+IntegerToString(g_winTrades)+" L:"+IntegerToString(g_lossTrades), clrCyan, 9); y+=15;
   
   double wr = (g_totalTrades>0)?(double)g_winTrades/g_totalTrades*100:0;
   DrawLabel(prefix+"wr", x+5, y, "Win Rate: "+DoubleToString(wr,1)+"%", clrCyan, 9); y+=15;
   DrawLabel(prefix+"ord", x+5, y, "Hoje: "+IntegerToString(g_ordersToday)+"/"+IntegerToString(InpMaxOrdersPerDay),
             clrLightGray, 9); y+=15;
   
   g_sym.Refresh();
   int spread = (int)g_sym.Spread();
   DrawLabel(prefix+"spr", x+5, y, "Spread: "+IntegerToString(spread)+" pts",
             (spread<InpMaxSpread)?clrLimeGreen:clrRed, 9); y+=18;
   
   //--- SL/TP/Trail info
   DrawLabel(prefix+"sl", x+5, y, "SL:"+IntegerToString(InpStopLoss)+" TP:"+IntegerToString(InpTakeProfit)+
             " Trail:"+IntegerToString(InpTrailStart)+"/"+IntegerToString(InpTrailStep), clrGray, 8); y+=15;
   
   DrawLabel(prefix+"time", x+5, y, TimeToString(TimeCurrent()), clrDarkGray, 7);
}

//+------------------------------------------------------------------+
void DrawLabel(string name, int x, int y, string text, color clr, int sz) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_CORNER, 0);
}

//+------------------------------------------------------------------+
double OnTester() { return g_totalProfit; }
//+------------------------------------------------------------------+
