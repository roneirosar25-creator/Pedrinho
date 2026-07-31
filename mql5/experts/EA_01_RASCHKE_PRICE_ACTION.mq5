//+------------------------------------------------------------------+
//| EA_SIMPLIFICADO_v1 — SEM FIRULAS, APENAS OPERA                  |
//| Baseado em MASCOTINHO TRIVIUM369 — FUNCIONA!                    |
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
int handle_bb, handle_stoch, handle_rsi, handle_macd, handle_atr;

//+------------------------------------------------------------------+
void CreateIndicators() {
    handle_bb = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
    handle_stoch = iStochastic(_Symbol, PERIOD_CURRENT, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
    handle_rsi = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
    handle_macd = iMACD(_Symbol, PERIOD_CURRENT, 12, 26, 9, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
}

void ReleaseIndicators() {
    IndicatorRelease(handle_bb);
    IndicatorRelease(handle_stoch);
    IndicatorRelease(handle_rsi);
    IndicatorRelease(handle_macd);
    IndicatorRelease(handle_atr);
}

//+------------------------------------------------------------------+
int OnInit() {
    Print("[EA_SIMPLIFICADO] Iniciando em ", _Symbol, " | Magic=", MagicNumber);
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(100);
    CreateIndicators();
    lastBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
    ReleaseIndicators();
    Print("[EA_SIMPLIFICADO] Finalizado | Reason=", reason);
}

//+------------------------------------------------------------------+
void OnTick() {
    // Reset diário
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime hoje = (datetime)(TimeCurrent() - dt.hour*3600 - dt.min*60 - dt.sec);
    if(hoje != lastDay) {
        tradesHoje = 0;
        lastDay = hoje;
        Print("[RESET] Novo dia - reset trades");
    }

    // Carregar indicadores
    double bb_upper[3], bb_lower[3], bb_mid[3];
    double stoch_k[3], stoch_d[3];
    double rsi[3];
    double macd_main[3], macd_sig[3];
    double atr[3];

    if(CopyBuffer(handle_bb, 1, 0, 3, bb_upper) < 3) return;
    if(CopyBuffer(handle_bb, 2, 0, 3, bb_lower) < 3) return;
    if(CopyBuffer(handle_bb, 0, 0, 3, bb_mid) < 3) return;
    if(CopyBuffer(handle_stoch, 0, 0, 3, stoch_k) < 3) return;
    if(CopyBuffer(handle_stoch, 1, 0, 3, stoch_d) < 3) return;
    if(CopyBuffer(handle_rsi, 0, 0, 3, rsi) < 3) return;
    if(CopyBuffer(handle_macd, 0, 0, 3, macd_main) < 3) return;
    if(CopyBuffer(handle_macd, 1, 0, 3, macd_sig) < 3) return;
    if(CopyBuffer(handle_atr, 0, 0, 3, atr) < 3) return;

    // Cheques básicos
    if(tradesHoje >= MaxTradesDay) return;
    if((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > (int)MaxSpread) return;

    datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(barTime == lastTradeBar) return;

    // Checar posição aberta
    if(PositionSelect(_Symbol)) return;

    // Sinais simples
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    bool buyBB = (ask <= bb_lower[1]);
    bool buyStoch = (stoch_k[1] < stoch_d[1] && stoch_k[1] < 50);
    bool buyRSI = (rsi[1] < 50);
    bool buyMACD = (macd_main[1] > macd_sig[1]);

    bool sellBB = (bid >= bb_upper[1]);
    bool sellStoch = (stoch_k[1] > stoch_d[1] && stoch_k[1] > 50);
    bool sellRSI = (rsi[1] > 50);
    bool sellMACD = (macd_main[1] < macd_sig[1]);

    int signal = 0;
    if(buyBB && buyStoch && buyRSI && buyMACD) signal = 1;
    if(sellBB && sellStoch && sellRSI && sellMACD) signal = -1;

    if(signal == 0) return;

    // Calcular lote
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

    // Executar trade
    double entry, sl, tp;
    string comment;

    if(signal == 1) {
        entry = ask;
        sl = NormalizeDouble(entry - slDist, _Digits);
        tp = NormalizeDouble(entry + slDist * 1.5, _Digits);
        comment = "SIMPLIFICADO_BUY";
        if(trade.Buy(lot, _Symbol, entry, sl, tp, comment)) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[BUY] ", _Symbol, " | Lot=", DoubleToString(lot, 3),
                  " | Entry=", DoubleToString(entry, _Digits),
                  " | SL=", DoubleToString(sl, _Digits));
        }
    }
    else if(signal == -1) {
        entry = bid;
        sl = NormalizeDouble(entry + slDist, _Digits);
        tp = NormalizeDouble(entry - slDist * 1.5, _Digits);
        comment = "SIMPLIFICADO_SELL";
        if(trade.Sell(lot, _Symbol, entry, sl, tp, comment)) {
            tradesHoje++;
            lastTradeBar = barTime;
            Print("[SELL] ", _Symbol, " | Lot=", DoubleToString(lot, 3),
                  " | Entry=", DoubleToString(entry, _Digits),
                  " | SL=", DoubleToString(sl, _Digits));
        }
    }
}
//+------------------------------------------------------------------+
