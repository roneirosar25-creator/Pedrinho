#property strict
#property copyright "TRIVIUM369"
#property version "2.00"
#include <Trade/Trade.mqh>

input long MagicNumber = 369369;
input double RiskPercent = 5.0;
input int MaxTradesDay = 5;

CTrade trade;
int tradesHoje = 0;
datetime lastDay = 0, lastTradeBar = 0;
int handle_ma_fast, handle_ma_slow, handle_atr;

void CreateIndicators() {
    handle_ma_fast = iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE);
    handle_ma_slow = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
}

void ReleaseIndicators() {
    IndicatorRelease(handle_ma_fast);
    IndicatorRelease(handle_ma_slow);
    IndicatorRelease(handle_atr);
}

int OnInit() {
    Print("[EA_04_TREND] Iniciando");
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(100);
    CreateIndicators();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    ReleaseIndicators();
}

void OnTick() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime hoje = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
    if(hoje != lastDay) { tradesHoje = 0; lastDay = hoje; }
    
    double ma_fast[3], ma_slow[3], atr[3];
    if(CopyBuffer(handle_ma_fast, 0, 0, 3, ma_fast) < 3) return;
    if(CopyBuffer(handle_ma_slow, 0, 0, 3, ma_slow) < 3) return;
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return;
    
    if(tradesHoje >= MaxTradesDay) return;
    if((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > 100) return;
    
    datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(barTime == lastTradeBar) return;
    if(PositionSelect(_Symbol)) return;
    
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    bool buySignal = (ma_fast[1] > ma_slow[1] && ma_fast[2] <= ma_slow[2]);
    bool sellSignal = (ma_fast[1] < ma_slow[1] && ma_fast[2] >= ma_slow[2]);
    
    if(!buySignal && !sellSignal) return;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double slDist = atr[1] * 2.0;
    double riskVal = balance * RiskPercent / 100.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(tickSize <= 0 || tickValue <= 0 || slDist <= 0) return;
    
    double lot = riskVal / (slDist / tickSize * tickValue);
    lot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot));
    
    if(lot < 0.01) return;
    
    if(buySignal) {
        double entry = ask;
        double sl = NormalizeDouble(entry - slDist, _Digits);
        double tp = NormalizeDouble(entry + slDist * 1.5, _Digits);
        if(trade.Buy(lot, _Symbol, entry, sl, tp, "TREND_BUY")) {
            tradesHoje++;
            lastTradeBar = barTime;
        }
    } else if(sellSignal) {
        double entry = bid;
        double sl = NormalizeDouble(entry + slDist, _Digits);
        double tp = NormalizeDouble(entry - slDist * 1.5, _Digits);
        if(trade.Sell(lot, _Symbol, entry, sl, tp, "TREND_SELL")) {
            tradesHoje++;
            lastTradeBar = barTime;
        }
    }
}
