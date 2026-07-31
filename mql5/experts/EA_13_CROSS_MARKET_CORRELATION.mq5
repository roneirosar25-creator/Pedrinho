#property strict
#property copyright "TRIVIUM369 - EA_13_CROSS_MARKET_CORRELATION"
#property version "2.00"
#include <Trade/Trade.mqh>

input long MagicNumber = 369369;
input double RiskPercent = 5.0;
input int ConfluenceMin = 9;

CTrade trade;
int tradesHoje = 0;
datetime lastDay = 0, lastTradeBar = 0;
int handle_ema12, handle_tema, handle_dema, handle_hma, handle_atr;

struct SignalCollector {
    int ea01_signal;
    int ea02_signal;
    int ea03_signal;
    int ea04_signal;
    int ea05_signal;
    int ea06_signal;
    int ea07_signal;
    int ea08_signal;
    int ea09_signal;
};

void CreateIndicators() {
    handle_ema12 = iMA(_Symbol, PERIOD_CURRENT, 12, 0, MODE_EMA, PRICE_CLOSE);
    handle_tema = iMA(_Symbol, PERIOD_CURRENT, 9, 0, MODE_SMMA, PRICE_CLOSE);
    handle_dema = iMA(_Symbol, PERIOD_CURRENT, 5, 0, MODE_SMA, PRICE_CLOSE);
    handle_hma = iMA(_Symbol, PERIOD_CURRENT, 13, 0, MODE_SMA, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
}

int OnInit() {
    Print("[EA_13_CROSS_MARKET_CORRELATION] ORQUESTRADOR CENTRAL - Arquitetura Correta");
    trade.SetExpertMagicNumber(MagicNumber);
    CreateIndicators();
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    IndicatorRelease(handle_ema12);
    IndicatorRelease(handle_tema);
    IndicatorRelease(handle_dema);
    IndicatorRelease(handle_hma);
    IndicatorRelease(handle_atr);
}

int CollectSignals() {
    SignalCollector signals = {0,0,0,0,0,0,0,0,0};
    double ema12[3], tema[3], dema[3], hma[3], atr[3];
    
    if(CopyBuffer(handle_ema12, 0, 0, 3, ema12) < 3) return 0;
    if(CopyBuffer(handle_tema, 0, 0, 3, tema) < 3) return 0;
    if(CopyBuffer(handle_dema, 0, 0, 3, dema) < 3) return 0;
    if(CopyBuffer(handle_hma, 0, 0, 3, hma) < 3) return 0;
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return 0;
    
    int confluenceCount = 0;
    if(ema12[1] > tema[1]) confluenceCount++;
    if(tema[1] > dema[1]) confluenceCount++;
    if(dema[1] > hma[1]) confluenceCount++;
    if(ema12[1] > iClose(_Symbol, PERIOD_CURRENT, 1)) confluenceCount++;
    if(iClose(_Symbol, PERIOD_CURRENT, 1) > iOpen(_Symbol, PERIOD_CURRENT, 1)) confluenceCount++;
    if(iHigh(_Symbol, PERIOD_CURRENT, 1) > iHigh(_Symbol, PERIOD_CURRENT, 2)) confluenceCount++;
    if(iVolume(_Symbol, PERIOD_CURRENT, 1) > iVolume(_Symbol, PERIOD_CURRENT, 2)) confluenceCount++;
    if(atr[1] > 0) confluenceCount++;
    
    return confluenceCount;
}

void OnTick() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime hoje = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
    if(hoje != lastDay) { tradesHoje = 0; lastDay = hoje; }
    
    int confluence = CollectSignals();
    if(confluence < ConfluenceMin) return;
    
    if(tradesHoje >= 3) return;
    
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
        
        if(trade.Buy(lot, _Symbol, entry, sl, tp, "EA_13_CROSS_MARKET_CORRELATION")) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[MAESTRO] BUY - Confluence=", confluence, "/9");
        }
    }
}

