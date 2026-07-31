//+------------------------------------------------------------------+
//| EXTRATOR_DADOS_MT5.mq5 — Exportar histórico direto do MT5      |
//| Objetivo: Extrair EURUSD-T, GOLD-T, BTCUSD-T para CSVs         |
//| Períodos: H1, M5, D1 — Data: 01/JUN até hoje                    |
//+------------------------------------------------------------------+

#property script_show_inputs

input string InpAtivos = "EURUSD-T,GOLD-T,BTCUSD-T";
input string InpTimeframes = "H1,M5,D1";
input string InpDataInicio = "2026.06.01";
input string InpDataFim = "2026.07.29";

//+------------------------------------------------------------------+
void OnStart()
{
   Print("🔄 Iniciando extração de dados...");

   string ativos[] = {"EURUSD-T", "GOLD-T", "BTCUSD-T"};
   int timeframes[] = {PERIOD_H1, PERIOD_M5, PERIOD_D1};
   string tf_names[] = {"H1", "M5", "D1"};

   datetime data_inicio = StringToTime(InpDataInicio + " 00:00:00");
   datetime data_fim = StringToTime(InpDataFim + " 23:59:59");

   // Loop por ativo
   for(int i = 0; i < ArraySize(ativos); i++)
   {
      string ativo = ativos[i];

      // Loop por timeframe
      for(int j = 0; j < ArraySize(timeframes); j++)
      {
         int tf = timeframes[j];
         string tf_name = tf_names[j];

         ExtrairDados(ativo, tf, tf_name, data_inicio, data_fim);
      }
   }

   Print("✅ Extração concluída!");
}

//+------------------------------------------------------------------+
void ExtrairDados(string ativo, int timeframe, string tf_name,
                   datetime data_inicio, datetime data_fim)
{
   Print("📊 Extraindo " + ativo + " " + tf_name + "...");

   // Copiar rates (últimas 10000 velas, cobrindo 01/JUN a 29/JUL)
   MqlRates rates[];
   int count = CopyRates(ativo, timeframe, data_fim, 10000, rates);

   if(count <= 0)
   {
      Print("❌ Erro ao copiar dados de " + ativo + " " + tf_name);
      return;
   }

   // Arquivo de saída
   string filename = "PONTE_MT5/ENTRADA/" + ativo + "-T" + tf_name + ".csv";
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV, ",");

   if(handle == INVALID_HANDLE)
   {
      Print("❌ Erro ao abrir arquivo: " + filename);
      return;
   }

   // Escrever cabeçalho
   FileWrite(handle, "datetime,open,high,low,close,volume,spread");

   // Escrever dados (inverter ordem — do mais antigo pro mais novo)
   for(int i = count - 1; i >= 0; i--)
   {
      if(rates[i].time >= data_inicio && rates[i].time <= data_fim)
      {
         string linha = TimeToString(rates[i].time, TIME_DATE | TIME_MINUTES) + "," +
                        DoubleToString(rates[i].open, 5) + "," +
                        DoubleToString(rates[i].high, 5) + "," +
                        DoubleToString(rates[i].low, 5) + "," +
                        DoubleToString(rates[i].close, 5) + "," +
                        (long)rates[i].tick_volume + "," +
                        (int)rates[i].spread;
         FileWrite(handle, linha);
      }
   }

   FileClose(handle);
   Print("✅ " + ativo + " " + tf_name + " → " + filename + " (" + count + " velas)");
}
