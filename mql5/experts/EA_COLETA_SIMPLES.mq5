//+------------------------------------------------------------------+
//| EA COLETA SIMPLES
//+------------------------------------------------------------------+

#property copyright "TRIVIUM369"
#property version   "1.00"

bool executado = false;

int OnInit()
{
    Print("EA Iniciado");
    return INIT_SUCCEEDED;
}

void OnTick()
{
    if (!executado) {
        executado = true;
        Coletar();
    }
}

void Coletar()
{
    Print("Coleta iniciada!");
    Print("Coletando EURUSD-T M5...");

    MqlRates rates[];
    int velas = CopyRates("EURUSD-T", PERIOD_M5, 0, 100000, rates);

    if (velas > 0) {
        Print("Coletadas " + IntegerToString(velas) + " velas");

        int handle = FileOpen("DADOS_BRUTOS_EURUSD/M5_EURUSD-T.csv", FILE_WRITE|FILE_CSV|FILE_ANSI);
        if (handle != INVALID_HANDLE) {
            FileWrite(handle, "date,time,open,high,low,close,volume");

            for (int i = velas - 1; i >= 0; i--) {
                string data = TimeToString(rates[i].time, TIME_DATE);
                string hora = TimeToString(rates[i].time, TIME_MINUTES);

                FileWrite(handle, data, hora,
                    DoubleToString(rates[i].open, 5),
                    DoubleToString(rates[i].high, 5),
                    DoubleToString(rates[i].low, 5),
                    DoubleToString(rates[i].close, 5),
                    IntegerToString((long)rates[i].tick_volume));
            }

            FileClose(handle);
            Print("Arquivo salvo!");
        }
    }
}

void OnDeinit(const int reason)
{
    Print("EA Finalizado");
}
