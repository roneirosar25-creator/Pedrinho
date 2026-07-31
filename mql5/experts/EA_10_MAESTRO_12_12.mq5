#property strict
#property copyright "TRIVIUM369 - MAESTRO"
#property version "1.00"
#include <Trade/Trade.mqh>
input long MagicNumber = 369369;
input double RiskPercent = 5.0;
input int ConfluenceMin = 9;
CTrade trade;
int tradesHoje = 0;
datetime lastDay = 0, lastTradeBar = 0;
int handle_atr;
void CreateIndicators() { handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14); }
int OnInit() {
    Print("[MAESTRO_12_12] Iniciando - ORQUESTRADOR CENTRAL");
    trade.SetExpertMagicNumber(MagicNumber);
    CreateIndicators();
    return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { IndicatorRelease(handle_atr); }
void OnTick() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime hoje = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
    if(hoje != lastDay) { tradesHoje = 0; lastDay = hoje; }
    double atr[3];
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return;
    if(tradesHoje >= 3) return;
    datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(barTime == lastTradeBar) return;
    if(PositionSelect(_Symbol)) return;
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    int confluenceScore = 0;
    confluenceScore += iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE) < 30 ? 1 : 0;
    confluenceScore += iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH) > 0 ? 1 : 0;
    confluenceScore += iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE) > 0 ? 1 : 0;
    confluenceScore += iMomentum(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE) > 100 ? 1 : 0;
    confluenceScore += iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE) < 0 ? 1 : 0;
    confluenceScore += iMA(_Symbol, PERIOD_CURRENT, 20, 0, MODE_SMA, PRICE_CLOSE) < iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE) ? 1 : 0;
    confluenceScore += iClose(_Symbol, PERIOD_CURRENT, 1) < iClose(_Symbol, PERIOD_CURRENT, 2) ? 1 : 0;
    confluenceScore += iHigh(_Symbol, PERIOD_CURRENT, 1) > iHigh(_Symbol, PERIOD_CURRENT, 2) ? 1 : 0;
    confluenceScore += iVolume(_Symbol, PERIOD_CURRENT, 1) > iVolume(_Symbol, PERIOD_CURRENT, 2) ? 1 : 0;
    confluenceScore += SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) < 100 ? 1 : 0;
    confluenceScore += (ask / bid - 1.0) < 0.001 ? 1 : 0;
    confluenceScore += TimeCurrent() % 3600 > 1800 ? 1 : 0;
    if(confluenceScore < ConfluenceMin) return;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double slDist = atr[1] * 2.5;
    double riskVal = balance * RiskPercent / 100.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    if(tickSize <= 0 || tickValue <= 0 || slDist <= 0) return;
    double lot = riskVal / (slDist / tickSize * tickValue);
    lot = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot));
    if(lot < 0.01) return;
    if(confluenceScore >= ConfluenceMin) {
        double entry = ask;
        double sl = NormalizeDouble(entry - slDist, _Digits);
        double tp = NormalizeDouble(entry + slDist * 2.0, _Digits);
        if(trade.Buy(lot, _Symbol, entry, sl, tp, "MAESTRO_CONSENSUS")) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[MAESTRO] BUY - Confluence=", confluenceScore, "/12");
        }
    }
}
