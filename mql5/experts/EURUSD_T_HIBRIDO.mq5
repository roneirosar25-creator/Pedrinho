//+------------------------------------------------------------------+
//| EURUSD_T_HIBRIDO.mq5 - Sistema Híbrido: Trading + Export + Log  |
//| Combina EA automático + exportação de dados + monitoramento      |
//+------------------------------------------------------------------+

#property copyright "TRIVIUM369"
#property link      "https://trivium369.com"
#property version   "3.00"
#property description "Sistema Híbrido EURUSD-T v3.0"
#property strict

#include <Trade\Trade.mqh>

CTrade trade;

//--- CONFIGURAÇÕES GERAIS
input double RiskPercent = 1.0;
input int EMA5_Period = 5;
input int EMA21_Period = 21;
input int EMA50_Period = 50;
input int RSI_Period = 14;
input int ATR_Period = 14;
input int TimeFrame = PERIOD_H1;
input bool AllowMonday = true;
input bool AllowFriday = true;
input int StartHour = 0;
input int EndHour = 23;
input int ExportIntervalSeconds = 3600;  // Export a cada 1h

//--- VARIÁVEIS GLOBAIS
double ema5, ema21, ema50, rsi, atr;
double bid, ask;
datetime last_signal_time = 0;
datetime last_export_time = 0;
double opening_balance = 0;
int trade_counter = 0;

struct TradeRecord
{
    string datetime_str;
    string symbol;
    string type;
    double entry_price;
    double exit_price;
    double stop_loss;
    double take_profit;
    double profit_loss;
    double profit_percent;
};

TradeRecord trades_history[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(20260702);
    opening_balance = AccountBalance();

    CreateExportDirectories();

    Print("=== EA EURUSD-T HIBRIDO INICIADO ===");
    Print("Data/Hora: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
    Print("Saldo inicial: ", DoubleToString(opening_balance, 2));

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Criar diretórios de exportação                                   |
//+------------------------------------------------------------------+
void CreateExportDirectories()
{
    string base = "PONTE_MT5\\HIBRIDO";
    // Os diretórios são criados automaticamente ao salvar arquivos
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

    // Exportar dados periódicos
    if ((TimeCurrent() - last_export_time) >= ExportIntervalSeconds)
    {
        ExportData();
        last_export_time = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Calcular indicadores                                             |
//+------------------------------------------------------------------+
void CalculateIndicators()
{
    ema5 = iMA(_Symbol, TimeFrame, EMA5_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
    ema21 = iMA(_Symbol, TimeFrame, EMA21_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
    ema50 = iMA(_Symbol, TimeFrame, EMA50_Period, 0, MODE_EMA, PRICE_CLOSE, 0);
    rsi = iRSI(_Symbol, TimeFrame, RSI_Period, PRICE_CLOSE, 0);
    atr = iATR(_Symbol, TimeFrame, ATR_Period, 0);
}

//+------------------------------------------------------------------+
//| Checar filtro de horário                                         |
//+------------------------------------------------------------------+
bool IsAllowedTime()
{
    int dow = DayOfWeek();
    int hour = Hour();

    if (dow == 1 && !AllowMonday) return false;
    if (dow == 5 && !AllowFriday) return false;
    if (hour < StartHour || hour >= EndHour) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Procurar sinais de entrada                                       |
//+------------------------------------------------------------------+
void CheckEntrySignals()
{
    if (last_signal_time == Time[0]) return;

    // COMPRA
    if (ema5 > ema21 && ema21 > ema50 && rsi > 50 && rsi < 70)
    {
        OpenBuy();
        last_signal_time = Time[0];
    }
    // VENDA
    else if (ema5 < ema21 && ema21 < ema50 && rsi < 50 && rsi > 30)
    {
        OpenSell();
        last_signal_time = Time[0];
    }
}

//+------------------------------------------------------------------+
//| Abrir COMPRA                                                     |
//+------------------------------------------------------------------+
void OpenBuy()
{
    double sl = ask - (atr * 1.5);
    double tp1 = ask + (atr * 1.5);

    double risk_amount = AccountBalance() * (RiskPercent / 100.0);
    double points_risk = (ask - sl) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double volume = risk_amount / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * points_risk);
    volume = NormalizeDouble(volume, 2);
    volume = MathMin(volume, 1.0);

    if (trade.Buy(volume, _Symbol, ask, sl, tp1, "EURUSD-T HIBRIDO COMPRA"))
    {
        trade_counter++;
        Print("COMPRA #", trade_counter, " aberta em ", ask);
        LogTrade("BUY", ask, sl, tp1);
    }
}

//+------------------------------------------------------------------+
//| Abrir VENDA                                                      |
//+------------------------------------------------------------------+
void OpenSell()
{
    double sl = bid + (atr * 1.5);
    double tp1 = bid - (atr * 1.5);

    double risk_amount = AccountBalance() * (RiskPercent / 100.0);
    double points_risk = (sl - bid) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double volume = risk_amount / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) * points_risk);
    volume = NormalizeDouble(volume, 2);
    volume = MathMin(volume, 1.0);

    if (trade.Sell(volume, _Symbol, bid, sl, tp1, "EURUSD-T HIBRIDO VENDA"))
    {
        trade_counter++;
        Print("VENDA #", trade_counter, " aberta em ", bid);
        LogTrade("SELL", bid, sl, tp1);
    }
}

//+------------------------------------------------------------------+
//| Registrar trade em histórico                                     |
//+------------------------------------------------------------------+
void LogTrade(string type, double entry, double sl, double tp)
{
    // Adicionar ao array
    ArrayResize(trades_history, ArraySize(trades_history) + 1);

    int idx = ArraySize(trades_history) - 1;
    trades_history[idx].datetime_str = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    trades_history[idx].symbol = _Symbol;
    trades_history[idx].type = type;
    trades_history[idx].entry_price = entry;
    trades_history[idx].stop_loss = sl;
    trades_history[idx].take_profit = tp;
}

//+------------------------------------------------------------------+
//| Gerenciar posições abertas                                       |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (PositionSelectByTicket(PositionGetTicket(i)))
        {
            if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

            double pos_open = PositionGetDouble(POSITION_PRICE_OPEN);
            double pos_sl = PositionGetDouble(POSITION_SL);
            long pos_type = PositionGetInteger(POSITION_TYPE);

            // Break-even em COMPRA
            if (pos_type == POSITION_TYPE_BUY)
            {
                if (bid > (pos_open + atr * 1.5))
                {
                    if (pos_sl < pos_open)
                    {
                        double new_sl = pos_open + 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                        trade.PositionModify(PositionGetTicket(i), new_sl, PositionGetDouble(POSITION_TP));
                    }
                }
            }
            // Break-even em VENDA
            else if (pos_type == POSITION_TYPE_SELL)
            {
                if (ask < (pos_open - atr * 1.5))
                {
                    if (pos_sl > pos_open)
                    {
                        double new_sl = pos_open - 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                        trade.PositionModify(PositionGetTicket(i), new_sl, PositionGetDouble(POSITION_TP));
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Exportar dados (RAW + Indicadores + Performance)                 |
//+------------------------------------------------------------------+
void ExportData()
{
    ExportRawData();
    ExportIndicators();
    ExportPerformance();
    LogCurrentEquity();
}

//+------------------------------------------------------------------+
//| Exportar dados brutos                                            |
//+------------------------------------------------------------------+
void ExportRawData()
{
    string filename = "PONTE_MT5\\HIBRIDO\\EXPORT\\EURUSD-T_H1.csv";
    int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');

    if (handle == INVALID_HANDLE) return;

    FileWrite(handle, "datetime", "open", "high", "low", "close", "volume");

    MqlRates rates[];
    int copied = CopyRates(_Symbol, PERIOD_H1, 0, 100, rates);

    for (int i = copied - 1; i >= 0; i--)
    {
        FileWrite(handle,
                  TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
                  DoubleToString(rates[i].open, 5),
                  DoubleToString(rates[i].high, 5),
                  DoubleToString(rates[i].low, 5),
                  DoubleToString(rates[i].close, 5),
                  IntegerToString((long)rates[i].tick_volume));
    }

    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Exportar indicadores                                             |
//+------------------------------------------------------------------+
void ExportIndicators()
{
    string filename = "PONTE_MT5\\HIBRIDO\\EXPORT\\EURUSD-T_H1_IND.csv";
    int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');

    if (handle == INVALID_HANDLE) return;

    FileWrite(handle, "datetime", "close", "ema5", "ema21", "ema50", "rsi", "atr", "sinal");

    MqlRates rates[];
    int copied = CopyRates(_Symbol, PERIOD_H1, 0, 100, rates);

    for (int i = 0; i < copied; i++)
    {
        double close = iClose(_Symbol, PERIOD_H1, i);
        double ema5_val = iMA(_Symbol, PERIOD_H1, 5, 0, MODE_EMA, PRICE_CLOSE, i);
        double ema21_val = iMA(_Symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE, i);
        double ema50_val = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE, i);
        double rsi_val = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE, i);
        double atr_val = iATR(_Symbol, PERIOD_H1, 14, i);

        string sinal = "NEUTRO";
        if (ema5_val > ema21_val && ema21_val > ema50_val) sinal = "COMPRA";
        else if (ema5_val < ema21_val && ema21_val < ema50_val) sinal = "VENDA";

        FileWrite(handle,
                  TimeToString(rates[i].time, TIME_DATE|TIME_MINUTES),
                  DoubleToString(close, 5),
                  DoubleToString(ema5_val, 5),
                  DoubleToString(ema21_val, 5),
                  DoubleToString(ema50_val, 5),
                  DoubleToString(rsi_val, 2),
                  DoubleToString(atr_val, 5),
                  sinal);
    }

    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Exportar performance                                             |
//+------------------------------------------------------------------+
void ExportPerformance()
{
    string filename = "PONTE_MT5\\HIBRIDO\\LOGS\\PERFORMANCE.csv";
    int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');

    if (handle == INVALID_HANDLE) return;

    FileWrite(handle, "metric", "value");
    FileWrite(handle, "Current_Balance", DoubleToString(AccountBalance(), 2));
    FileWrite(handle, "Equity", DoubleToString(AccountEquity(), 2));
    FileWrite(handle, "Profit_Loss", DoubleToString(AccountEquity() - opening_balance, 2));
    FileWrite(handle, "Total_Trades", IntegerToString(trade_counter));
    FileWrite(handle, "Timestamp", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));

    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Log de equity periódico                                          |
//+------------------------------------------------------------------+
void LogCurrentEquity()
{
    string filename = "PONTE_MT5\\HIBRIDO\\LOGS\\EQUITY.csv";
    int handle = FileOpen(filename, FILE_APPEND | FILE_CSV | FILE_ANSI, ',');

    if (handle == INVALID_HANDLE) return;

    if (FileSize(filename) == 0)  // Arquivo novo
    {
        FileWrite(handle, "timestamp", "balance", "equity", "profit");
    }

    FileWrite(handle,
              TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
              DoubleToString(AccountBalance(), 2),
              DoubleToString(AccountEquity(), 2),
              DoubleToString(AccountEquity() - opening_balance, 2));

    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("=== EA EURUSD-T HIBRIDO FINALIZADO ===");
    Print("Razão: ", reason);
    Print("Saldo Final: ", DoubleToString(AccountBalance(), 2));
    Print("Trades realizados: ", trade_counter);
}

//+------------------------------------------------------------------+
