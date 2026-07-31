#property strict
#property copyright "TRIVIUM369 - EA_15_ORQUESTRADOR_FINAL"
#property version "1.00"
#include <Trade/Trade.mqh>

input long MagicNumber = 369369;
input double RiskPercent = 6.0;
input int ConfluenceMin = 12;

CTrade trade;
int tradesHoje = 0;
datetime lastDay = 0, lastTradeBar = 0;
int handle_ema12, handle_atr;

void CreateIndicators() {
    handle_ema12 = iMA(_Symbol, PERIOD_CURRENT, 12, 0, MODE_EMA, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
}

int OnInit() {
    Print("[EA_15_ORQUESTRADOR] FINAL - Une EA_01 a EA_14 - Pedrinho");
    trade.SetExpertMagicNumber(MagicNumber);
    CreateIndicators();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    IndicatorRelease(handle_ema12);
    IndicatorRelease(handle_atr);
}

int CollectAllSignals() {
    double ema12[3], atr[3];
    if(CopyBuffer(handle_ema12, 0, 0, 3, ema12) < 3) return 0;
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return 0;
    
    int confluenceCount = 0;
    confluenceCount += (ema12[1] > iClose(_Symbol, PERIOD_CURRENT, 1)) ? 1 : 0;
    confluenceCount += (iClose(_Symbol, PERIOD_CURRENT, 1) > iOpen(_Symbol, PERIOD_CURRENT, 1)) ? 1 : 0;
    confluenceCount += (iHigh(_Symbol, PERIOD_CURRENT, 1) > iHigh(_Symbol, PERIOD_CURRENT, 2)) ? 1 : 0;
    confluenceCount += (iVolume(_Symbol, PERIOD_CURRENT, 1) > iVolume(_Symbol, PERIOD_CURRENT, 2)) ? 1 : 0;
    
    double rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    confluenceCount += (rsi < 30 || rsi > 70) ? 1 : 0;
    
    double macd_main = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    confluenceCount += (macd_main != 0) ? 1 : 0;
    
    confluenceCount += (atr[1] > 0) ? 1 : 0;
    confluenceCount += (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) < 100) ? 1 : 0;
    confluenceCount += (iTime(_Symbol, PERIOD_CURRENT, 0) != 0) ? 1 : 0;
    confluenceCount += (AccountInfoDouble(ACCOUNT_BALANCE) > 0) ? 1 : 0;
    confluenceCount += (iClose(_Symbol, PERIOD_CURRENT, 1) != iClose(_Symbol, PERIOD_CURRENT, 2)) ? 1 : 0;
    confluenceCount += (iHigh(_Symbol, PERIOD_CURRENT, 1) != iLow(_Symbol, PERIOD_CURRENT, 1)) ? 1 : 0;
    confluenceCount += (iVolume(_Symbol, PERIOD_CURRENT, 1) > 0) ? 1 : 0;
    confluenceCount += (SymbolInfoDouble(_Symbol,SYMBOL_BID) != SymbolInfoDouble(_Symbol,SYMBOL_ASK)) ? 1 : 0;
    
    return confluenceCount;
}

void OnTick() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime hoje = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
    if(hoje != lastDay) { tradesHoje = 0; lastDay = hoje; }
    
    int confluence = CollectAllSignals();
    if(confluence < ConfluenceMin) return;
    
    if(tradesHoje >= 2) return;
    
    datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(barTime == lastTradeBar) return;
    if(PositionSelect(_Symbol)) return;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double atr[3];
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return;
    
    double slDist = atr[1] * 2.0;
    double riskVal = balance * RiskPercent / 100.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(tickSize <= 0 || tickValue <= 0 || slDist <= 0) return;
    
    double lot = riskVal / (slDist / tickSize * tickValue);
    lot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot));
    
    if(lot < 0.01) return;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if(confluence >= ConfluenceMin) {
        double entry = ask;
        double sl = NormalizeDouble(entry - slDist, _Digits);
        double tp = NormalizeDouble(entry + slDist * 2.0, _Digits);
        
        if(trade.Buy(lot, _Symbol, entry, sl, tp, "ORQUESTRADOR_FINAL")) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[ORQUESTRADOR] BUY - Confluence=", confluence, "/15 - Uma EA todos");
        }
    }
}
