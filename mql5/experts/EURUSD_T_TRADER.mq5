//+------------------------------------------------------------------+
//| EURUSD_T_TRADER.mq5 - EA Automático de Trading                  |
//| Estratégia: EMA5/EMA21/EMA50 + RSI + ATR dinâmico              |
//| Gerenciamento: 3 Take Profits + Break-even + Trailing Stop      |
//+------------------------------------------------------------------+

#property copyright "TRIVIUM369"
#property link      "https://trivium369.com"
#property version   "1.00"
#property strict
#property description "EA Automático com análise multicamada para EURUSD-T"

#include <Trade\Trade.mqh>

CTrade trade;

//--- Entrada
input double RiskPercent = 1.0;           // % de risco por trade
input int EMA5_Period = 5;                // Período EMA rápida
input int EMA21_Period = 21;              // Período EMA média
input int EMA50_Period = 50;              // Período EMA tendência
input int RSI_Period = 14;                // Período RSI
input int ATR_Period = 14;                // Período ATR
input int TimeFrame = PERIOD_H1;          // Timeframe operacional (H1)
input bool AllowMonday = true;            // Operar segunda
input bool AllowFriday = true;            // Operar sexta
input int StartHour = 0;                  // Hora inicial (0-23)
input int EndHour = 23;                   // Hora final (0-23)

//--- Globais
double ema5, ema21, ema50, rsi, atr;
double sl, tp1, tp2, tp3;
double bid, ask;
int bars_counted = 0;
ulong ticket = 0;
datetime last_signal_time = 0;
double position_open_price = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(20260701);  // Magic number único
    Print("EA EURUSD-T TRADER iniciado - ", TimeToString(TimeCurrent()));
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("EA EURUSD-T TRADER finalizado - Razão:", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Obter preços
    bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Calcular indicadores
    CalculateIndicators();

    // Checar filtros de horário
    if (!IsAllowedTime()) return;

    // Gerenciar posições abertas
    ManageOpenPositions();

    // Procurar sinais de entrada
    if (PositionsTotal() == 0)
    {
        CheckEntrySignals();
    }
}

//+------------------------------------------------------------------+
//| Calcular indicadores                                             |
//+------------------------------------------------------------------+
void CalculateIndicators()
{
    // EMA5
    ema5 = iMA(_Symbol, TimeFrame, EMA5_Period, 0, MODE_EMA, PRICE_CLOSE, 0);

    // EMA21
    ema21 = iMA(_Symbol, TimeFrame, EMA21_Period, 0, MODE_EMA, PRICE_CLOSE, 0);

    // EMA50 (tendência)
    ema50 = iMA(_Symbol, TimeFrame, EMA50_Period, 0, MODE_EMA, PRICE_CLOSE, 0);

    // RSI
    rsi = iRSI(_Symbol, TimeFrame, RSI_Period, PRICE_CLOSE, 0);

    // ATR (volatilidade)
    atr = iATR(_Symbol, TimeFrame, ATR_Period, 0);
}

//+------------------------------------------------------------------+
//| Checar filtro de horário                                         |
//+------------------------------------------------------------------+
bool IsAllowedTime()
{
    int dow = DayOfWeek();
    int hour = Hour();

    // Bloquear segunda-feira se não permitido
    if (dow == 1 && !AllowMonday) return false;

    // Bloquear sexta-feira se não permitido
    if (dow == 5 && !AllowFriday) return false;

    // Checar horário
    if (hour < StartHour || hour >= EndHour) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Procurar sinais de entrada                                       |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    // Evitar múltiplos sinais na mesma barra
    if (last_signal_time == Time[0]) return;

    // COMPRA: EMA5 > EMA21, EMA21 > EMA50 (tendência) + RSI 50-70
    if (ema5 > ema21 && ema21 > ema50 && rsi > 50 && rsi < 70)
    {
        OpenBuy();
        last_signal_time = Time[0];
    }

    // VENDA: EMA5 < EMA21, EMA21 < EMA50 (tendência) + RSI 30-50
    else if (ema5 < ema21 && ema21 < ema50 && rsi < 50 && rsi > 30)
    {
        OpenSell();
        last_signal_time = Time[0];
    }
}

//+------------------------------------------------------------------+
//| Abrir posição de COMPRA                                          |
//+------------------------------------------------------------------+
void OpenBuy()
{
    // Stop Loss: ATR × 1.5 abaixo do preço
    sl = ask - (atr * 1.5);

    // Take Profits
    tp1 = ask + (atr * 1.5);    // TP1: ATR × 1.5
    tp2 = ask + (atr * 3.0);    // TP2: ATR × 3.0
    tp3 = ask + (atr * 5.0);    // TP3: ATR × 5.0

    // Calcular volume baseado no risco
    double risk_amount = AccountBalance() * (RiskPercent / 100.0);
    double points_risk = (ask - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double volume = risk_amount / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * points_risk);
    volume = NormalizeDouble(volume, 2);

    // Limitar volume (segurança)
    volume = MathMin(volume, 1.0);

    if (trade.Buy(volume, _Symbol, ask, sl, tp1, "EURUSD-T COMPRA"))
    {
        ticket = trade.ResultOrder();
        position_open_price = ask;
        Print("COMPRA aberta em ", ask, " SL=", sl, " TP1=", tp1);
    }
}

//+------------------------------------------------------------------+
//| Abrir posição de VENDA                                           |
//+------------------------------------------------------------------+
void OpenSell()
{
    // Stop Loss: ATR × 1.5 acima do preço
    sl = bid + (atr * 1.5);

    // Take Profits
    tp1 = bid - (atr * 1.5);    // TP1: ATR × 1.5
    tp2 = bid - (atr * 3.0);    // TP2: ATR × 3.0
    tp3 = bid - (atr * 5.0);    // TP3: ATR × 5.0

    // Calcular volume
    double risk_amount = AccountBalance() * (RiskPercent / 100.0);
    double points_risk = (sl - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double volume = risk_amount / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * points_risk);
    volume = NormalizeDouble(volume, 2);

    // Limitar volume
    volume = MathMin(volume, 1.0);

    if (trade.Sell(volume, _Symbol, bid, sl, tp1, "EURUSD-T VENDA"))
    {
        ticket = trade.ResultOrder();
        position_open_price = bid;
        Print("VENDA aberta em ", bid, " SL=", sl, " TP1=", tp1);
    }
}

//+------------------------------------------------------------------+
//| Gerenciar posições abertas (Break-even + Trailing Stop)          |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (PositionSelectByTicket(PositionGetTicket(i)))
        {
            if (PositionGetSymbol(i) != _Symbol) continue;

            double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
            double pos_sl = PositionGetDouble(POSITION_SL);
            int pos_type = PositionGetInteger(POSITION_TYPE);

            // Break-even: move SL para entrada ao atingir TP1
            if (pos_type == POSITION_TYPE_BUY)
            {
                if (bid > (pos_open + atr * 1.5))  // Passou TP1
                {
                    if (pos_sl < pos_open)  // SL ainda abaixo da entrada
                    {
                        double new_sl = pos_open + 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                        trade.PositionModify(PositionGetTicket(i), new_sl, PositionGetDouble(POSITION_TP));
                        Print("Break-even ativado em ", new_sl);
                    }

                    // Trailing Stop: TP2 atingido?
                    if (bid > (pos_open + atr * 3.0))
                    {
                        double trail_sl = bid - (atr * 0.3);
                        if (trail_sl > pos_sl)
                        {
                            trade.PositionModify(PositionGetTicket(i), trail_sl, PositionGetDouble(POSITION_TP));
                        }
                    }
                }
            }
            else if (pos_type == POSITION_TYPE_SELL)
            {
                if (ask < (pos_open - atr * 1.5))  // Passou TP1
                {
                    if (pos_sl > pos_open)  // SL ainda acima da entrada
                    {
                        double new_sl = pos_open - 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                        trade.PositionModify(PositionGetTicket(i), new_sl, PositionGetDouble(POSITION_TP));
                        Print("Break-even ativado em ", new_sl);
                    }

                    // Trailing Stop
                    if (ask < (pos_open - atr * 3.0))
                    {
                        double trail_sl = ask + (atr * 0.3);
                        if (trail_sl < pos_sl)
                        {
                            trade.PositionModify(PositionGetTicket(i), trail_sl, PositionGetDouble(POSITION_TP));
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
