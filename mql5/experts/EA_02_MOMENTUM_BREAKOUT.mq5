//+------------------------------------------------------------------+
//| EA_02_MOMENTUM_BREAKOUT — Detecção de Breakout com Momentum     |
//| Entra quando há breakout + momentum forte                        |
//| Autor: Pedrinho | Data: 19 JUN 2026                             |
//+------------------------------------------------------------------+
#property strict
#property copyright "TRIVIUM369"
#property version "1.00"

#include <Trade/Trade.mqh>

input long MagicNumber = 369369;
input double RiskPercent = 5.0;
input int MaxTradesDay = 5;
input double MaxSpread = 100;

CTrade trade;
int tradesHoje = 0;
datetime lastDay = 0;
datetime lastTradeBar = 0;
double lastBalance = 0;
int handle_momentum, handle_rsi, handle_atr;

void CreateIndicators() {
    handle_momentum = iMomentum(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    handle_rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
}

void ReleaseIndicators() {
    IndicatorRelease(handle_momentum);
    IndicatorRelease(handle_rsi);
    IndicatorRelease(handle_atr);
}

int OnInit() {
    Print("[EA_02_MOMENTUM] Iniciando em ", _Symbol, " | Magic=", MagicNumber);
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(100);
    CreateIndicators();
    lastBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    ReleaseIndicators();
    Print("[EA_02_MOMENTUM] Finalizado | Reason=", reason);
}

void OnTick() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime hoje = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
    if(hoje != lastDay) {
        tradesHoje = 0;
        lastDay = hoje;
    }

    double momentum[3], rsi[3], atr[3];
    if(CopyBuffer(handle_momentum, 0, 0, 3, momentum) < 3) return;
    if(CopyBuffer(handle_rsi, 0, 0, 3, rsi) < 3) return;
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return;

    if(tradesHoje >= MaxTradesDay) return;
    if((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > (int)MaxSpread) return;

    datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(barTime == lastTradeBar) return;
    if(PositionSelect(_Symbol)) return;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    bool buySignal = (momentum[1] > 100 && momentum[2] <= 100 && rsi[1] < 70);
    bool sellSignal = (momentum[1] < 100 && momentum[2] >= 100 && rsi[1] > 30);

    int signal = 0;
    if(buySignal) signal = 1;
    if(sellSignal) signal = -1;
    if(signal == 0) return;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double slDist = atr[1] * 2.0;
    double riskVal = balance * RiskPercent / 100.0;
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

    if(tickSize <= 0 || tickValue <= 0 || slDist <= 0) return;

    double lot = riskVal / (slDist / tickSize * tickValue);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lot = MathMax(minLot, MathMin(maxLot, lot));

    if(lot < 0.01) return;

    double entry, sl, tp;
    if(signal == 1) {
        entry = ask;
        sl = NormalizeDouble(entry - slDist, _Digits);
        tp = NormalizeDouble(entry + slDist * 1.5, _Digits);
        if(trade.Buy(lot, _Symbol, entry, sl, tp, "MOMENTUM_BUY")) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[BUY] ", _Symbol, " | Momentum=", DoubleToString(momentum[1], 2));
        }
    }
    else if(signal == -1) {
        entry = bid;
        sl = NormalizeDouble(entry + slDist, _Digits);
        tp = NormalizeDouble(entry - slDist * 1.5, _Digits);
        if(trade.Sell(lot, _Symbol, entry, sl, tp, "MOMENTUM_SELL")) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[SELL] ", _Symbol, " | Momentum=", DoubleToString(momentum[1], 2));
        }
    }
}
//+------------------------------------------------------------------+
