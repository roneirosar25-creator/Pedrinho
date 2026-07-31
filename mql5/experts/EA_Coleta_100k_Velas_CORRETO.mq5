//+------------------------------------------------------------------+
//| COLETA 100.000 VELAS — EXPERT ADVISOR                           |
//| Versão corrigida — não é Script                                 |
//+------------------------------------------------------------------+

#property copyright "TRIVIUM369"
#property version   "1.00"
#property description "Coleta 100.000 velas de ativos"

// Arrays para ativos e timeframes
string Ativos[] = {
    "EURUSD-T", "GBPUSD-T", "USDCHF-T", "USDCAD-T", "USDJPY-T", "USDSEK-T", "USDCNH-T",
    "NZDUSD-T", "AUDUSD-T", "AUDCAD-T",
    "XAUUSD-T", "XAUGBP-T", "XAUEUR-T", "XAUCHF-T", "XAUAUD-T"
};

ENUM_TIMEFRAMES Timeframes[] = {
    PERIOD_M1, PERIOD_M2, PERIOD_M5, PERIOD_M15,
    PERIOD_H1, PERIOD_H4, PERIOD_D1
};

bool coleta_iniciada = false;

string SepLine()
{
   string result;
   StringInit(result, 80, '=');
   return(result);
}

//+------------------------------------------------------------------+
int OnInit()
{
    Print(SepLine());
    Print("EA COLETA 100.000 VELAS");
    Print(SepLine());
    Print("[OK] Expert Advisor iniciado");
    Print("");
    Print("Clique em um botao ou abra grafico para iniciar coleta");
    Print("");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
    if (!coleta_iniciada) {
        coleta_iniciada = true;
        ColetarTodosOsDados();
    }
}

//+------------------------------------------------------------------+
void ColetarTodosOsDados()
{
    int totalAtivos = ArraySize(Ativos);
    int totalTimeframes = ArraySize(Timeframes);
    int totalArquivos = totalAtivos * totalTimeframes;
    int arquivosCriados = 0;
    int arquivosErro = 0;

    Print("================================================================================");
    Print("COLETA DE DADOS ADMIRALS - 100.000 VELAS");
    Print("================================================================================");
    Print("");
    Print("Total a processar: " + IntegerToString(totalArquivos) + " arquivos");
    Print("");

    for(int i = 0; i < totalAtivos; i++)
    {
        string ativo = Ativos[i];
        string ativoLimpo = StringSubstr(ativo, 0, StringLen(ativo) - 2);

        Print("[" + IntegerToString(i+1) + "/" + IntegerToString(totalAtivos) + "] " + ativo + " | ", false);

        for(int j = 0; j < totalTimeframes; j++)
        {
            ENUM_TIMEFRAMES tf = Timeframes[j];
            string tfNome = PeriodToString(tf);

            MqlRates rates[];
            int velas = CopyRates(ativo, tf, 0, 100000, rates);

            if(velas <= 0)
            {
                Print(tfNome + ":[ VAZIO ] ", false);
                arquivosErro++;
                continue;
            }

            if(SalvarCSV(ativo, ativoLimpo, tfNome, rates, velas))
            {
                Print(tfNome + ":[ OK:" + IntegerToString(velas) + " ] ", false);
                arquivosCriados++;
            }
            else
            {
                Print(tfNome + ":[ ERRO ] ", false);
                arquivosErro++;
            }
        }

        Print("");
    }

    Print("");
    Print("================================================================================");
    Print("RESUMO FINAL");
    Print("================================================================================");
    Print("Total arquivos processados: " + IntegerToString(totalArquivos));
    Print("  [OK] Criados: " + IntegerToString(arquivosCriados));
    Print("  [ERRO] Falhados: " + IntegerToString(arquivosErro));
    Print("");
    Print("Localizacao: MQL5\\Files\\DADOS_BRUTOS_[ATIVO]\\");
    Print("================================================================================");
    Print("");
    Print("[CONCLUIDO] Coleta finalizada!");
}

//+------------------------------------------------------------------+
string PeriodToString(ENUM_TIMEFRAMES period)
{
    switch(period)
    {
        case PERIOD_M1:  return "M1";
        case PERIOD_M2:  return "M2";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        default:         return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
bool SalvarCSV(string ativo, string ativoLimpo, string tf, MqlRates &rates[], int velas)
{
    string pastaAtivo = "DADOS_BRUTOS_" + ativoLimpo;
    string nomeArquivo = pastaAtivo + "\\" + tf + "_" + ativo + ".csv";

    int handle = FileOpen(nomeArquivo, FILE_WRITE|FILE_CSV|FILE_ANSI);
    if(handle == INVALID_HANDLE)
        return false;

    FileWrite(handle, "date,time,open,high,low,close,volume");

    for(int i = velas - 1; i >= 0; i--)
    {
        string data = TimeToString(rates[i].time, TIME_DATE);
        string hora = TimeToString(rates[i].time, TIME_MINUTES);

        string dataFormatada = StringSubstr(data, 0, 4) + "." +
                               StringSubstr(data, 5, 2) + "." +
                               StringSubstr(data, 8, 2);

        string horaFormatada = StringSubstr(hora, 0, 5) + ":00";

        string open = DoubleToString(rates[i].open, 5);
        string high = DoubleToString(rates[i].high, 5);
        string low = DoubleToString(rates[i].low, 5);
        string close = DoubleToString(rates[i].close, 5);
        string volume = IntegerToString((long)rates[i].tick_volume);

        FileWrite(handle, dataFormatada, horaFormatada, open, high, low, close, volume);
    }

    FileClose(handle);
    return true;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("[FIM] Expert Advisor finalizado");
}
