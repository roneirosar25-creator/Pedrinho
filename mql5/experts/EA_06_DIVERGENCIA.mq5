#property strict
#property copyright "TRIVIUM369"
#property version "2.00"
#include <Trade/Trade.mqh>
input long MagicNumber = 369369;
input double RiskPercent = 5.0;
int handle_atr;
void CreateIndicators() { handle_atr = iATR(_Symbol, PERIOD_CURRENT, 14); }
void ReleaseIndicators() { IndicatorRelease(handle_atr); }
int OnInit() {
    Print("[EA_06_DIV] Iniciando");
    IndicatorRelease(handle_atr);
    return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { ReleaseIndicators(); }
void OnTick() {}
