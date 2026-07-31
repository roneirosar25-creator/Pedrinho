#property strict
#property copyright "TRIVIUM369 - EA_14_ULTRA_EXECUTION"
#property version "2.00"
#include <Trade/Trade.mqh>

input long MagicNumber = 369369;
input double RiskPercent = 7.5;
input double WinRateTarget = 0.75;
input int MaxTradesDay = 10;

CTrade trade;
int tradesHoje = 0, winsHoje = 0;
datetime lastDay = 0, lastTradeBar = 0;
int handle_ema12, handle_rsi, handle_macd, handle_atr;

void CreateIndicators() {
    handle_ema12 = iMA(_Symbol, PERIOD_CURRENT, 12, 0, MODE_EMA, PRICE_CLOSE);
    handle_rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    handle_macd = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
}

int OnInit() {
    Print("[EA_14_ULTRA] EXECUÇÃO ASSERTIVA - Ronei");
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(40);
    CreateIndicators();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    IndicatorRelease(handle_ema12);
    IndicatorRelease(handle_rsi);
    IndicatorRelease(handle_macd);
    IndicatorRelease(handle_atr);
}

void OnTick() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime hoje = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
    if(hoje != lastDay) { tradesHoje = 0; winsHoje = 0; lastDay = hoje; }
    
    if(tradesHoje >= MaxTradesDay) return;
    if((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > 50) return;
    
    double ema12[3], rsi[3], macd[3], atr[3];
    if(CopyBuffer(handle_ema12, 0, 0, 3, ema12) < 3) return;
    if(CopyBuffer(handle_rsi, 0, 0, 3, rsi) < 3) return;
    if(CopyBuffer(handle_macd, 0, 0, 3, macd) < 3) return;
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return;
    
    datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(barTime == lastTradeBar) return;
    if(PositionSelect(_Symbol)) return;
    
    bool buySignal = (rsi[1] < 35 && macd[1] > 0 && ema12[1] > iClose(_Symbol, PERIOD_CURRENT, 1));
    bool sellSignal = (rsi[1] > 65 && macd[1] < 0 && ema12[1] < iClose(_Symbol, PERIOD_CURRENT, 1));
    
    if(!buySignal && !sellSignal) return;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double winRate = tradesHoje > 0 ? (double)winsHoje / tradesHoje : 0;
    double dynamicRisk = winRate >= WinRateTarget ? RiskPercent * 1.2 : RiskPercent * 0.8;
    
    double slDist = atr[1] * 1.8;
    double riskVal = equity * dynamicRisk / 100.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(tickSize <= 0 || tickValue <= 0 || slDist <= 0) return;
    
    double lot = riskVal / (slDist / tickSize * tickValue);
    lot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot));
    
    if(lot < 0.01) return;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if(buySignal) {
        double entry = ask;
        double sl = NormalizeDouble(entry - slDist, _Digits);
        double tp = NormalizeDouble(entry + slDist * 2.5, _Digits);
        if(trade.Buy(lot, _Symbol, entry, sl, tp, "ULTRA_BUY")) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[ULTRA] BUY | WR=", DoubleToString(winRate*100, 1), "%");
        }
    }
}
