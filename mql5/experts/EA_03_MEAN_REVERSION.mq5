#property strict
#property copyright "TRIVIUM369"
#property version "1.00"
#include <Trade/Trade.mqh>
input long MagicNumber = 369369;
input double RiskPercent = 5.0;
int handle_bb, handle_atr;
void CreateIndicators() {
    handle_bb = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
    handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14);
}
int OnInit() {
    Print("[EA_03] Init");
    IndicatorRelease(handle_bb);
    IndicatorRelease(handle_atr);
    return INIT_SUCCEEDED;
}
void OnTick() {}
