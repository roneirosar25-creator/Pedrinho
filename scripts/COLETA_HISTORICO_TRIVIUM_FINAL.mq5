//+------------------------------------------------------------------+
//|                                    COLETA_HISTORICO_TRIVIUM.mq5   |
//|                                          TRIVIUM369 / Cláudio     |
//|   SCRIPT (roda UMA vez e encerra) — coleta de histórico direto    |
//|   do servidor da corretora (Admirals) para CSV.                   |
//|                                                                   |
//|   AJUSTADO PARA ADMIRALS: todos os ativos com sufixo -T           |
//|   (ex: EURUSD-T, GBPUSD-T, etc.)                                 |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

//=== PARÂMETROS EDITÁVEIS ==========================================
input int    BarrasDesejadas = 100000;          // teto de barras por combinação
input int    MaxTentativas   = 20;              // tentativas p/ forçar download
input int    EsperaMs        = 400;             // espera entre tentativas (ms)
input string PastaBase       = "DADOS_BRUTOS";  // prefixo da pasta de saída

//=== ATIVOS COM SUFIXO -T (ADMIRALS) ==============================
string Ativos[] =
{
   "EURUSD-T","GBPUSD-T","USDCHF-T","USDCAD-T","USDJPY-T",
   "USDSEK-T","USDCNH-T","NZDUSD-T","AUDUSD-T","AUDCAD-T",
   "XAUUSD-T","XAUGBP-T","XAUEUR-T","XAUCHF-T","XAUAUD-T"
};

ENUM_TIMEFRAMES TFs[] =
{
   PERIOD_M1, PERIOD_M2, PERIOD_M5, PERIOD_M15,
   PERIOD_H1, PERIOD_H4, PERIOD_D1
};

//+------------------------------------------------------------------+
string TFNome(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         return EnumToString(tf);
   }
}

//+------------------------------------------------------------------+
//| Força o download e copia. Retorna nº de barras (ou -1 em erro).  |
//| Para de insistir quando o teto chega OU quando o nº estabiliza   |
//| (sinal de que aquele é todo o histórico disponível).             |
//+------------------------------------------------------------------+
int ColetaRates(string simbolo, ENUM_TIMEFRAMES tf, MqlRates &rates[])
{
   ArraySetAsSeries(rates, false);   // index 0 = barra mais ANTIGA
   int copiadas = 0;
   int anterior = -999;
   int estavel  = 0;

   for(int tent=0; tent<MaxTentativas; tent++)
   {
      copiadas = CopyRates(simbolo, tf, 0, BarrasDesejadas, rates);

      if(copiadas >= BarrasDesejadas)
         break;                       // veio o teto pedido

      if(copiadas > 0 && copiadas == anterior)
      {
         estavel++;
         if(estavel >= 2)
            break;                    // estabilizou = é todo o histórico que existe
      }
      else
         estavel = 0;

      anterior = copiadas;
      Sleep(EsperaMs);                // dá tempo do terminal baixar do servidor
   }
   return copiadas;
}

//+------------------------------------------------------------------+
void OnStart()
{
   int nAtivos = ArraySize(Ativos);
   int nTFs    = ArraySize(TFs);
   int totalCombos = nAtivos * nTFs;

   int ok=0, parcial=0, falha=0;
   long totalBarras=0;

   PrintFormat("=== COLETA TRIVIUM369 — %d combinações (%d ativos x %d TFs) ===",
               totalCombos, nAtivos, nTFs);

   for(int a=0; a<nAtivos; a++)
   {
      string simbolo = Ativos[a];

      // garante o símbolo na Observação de Mercado
      if(!SymbolSelect(simbolo, true))
      {
         PrintFormat("[ERRO] Símbolo NÃO encontrado: '%s' — confira na Obs. Mercado. Pulando %d TFs.",
                     simbolo, nTFs);
         falha += nTFs;
         continue;
      }

      int digs = (int)SymbolInfoInteger(simbolo, SYMBOL_DIGITS);
      if(digs <= 0) digs = 5;

      for(int t=0; t<nTFs; t++)
      {
         ENUM_TIMEFRAMES tf = TFs[t];
         MqlRates rates[];
         int n = ColetaRates(simbolo, tf, rates);

         if(n <= 0)
         {
            PrintFormat("[FALHA] %s %s — CopyRates=%d (erro %d)",
                        simbolo, TFNome(tf), n, GetLastError());
            ResetLastError();
            falha++;
            continue;
         }

         string ativoLimpo = StringSubstr(simbolo, 0, StringLen(simbolo) - 2);  // remove -T
         string pasta   = StringFormat("%s_%s", PastaBase, ativoLimpo);
         string arquivo = StringFormat("%s\\%s_%s.csv", pasta, TFNome(tf), simbolo);

         int h = FileOpen(arquivo, FILE_WRITE|FILE_TXT|FILE_ANSI);
         if(h == INVALID_HANDLE)
         {
            PrintFormat("[FALHA] Não abriu %s (erro %d)", arquivo, GetLastError());
            ResetLastError();
            falha++;
            continue;
         }

         FileWriteString(h, "date,time,open,high,low,close,volume\r\n");
         for(int i=0; i<n; i++)
         {
            string linha =
               TimeToString(rates[i].time, TIME_DATE)            + "," +
               TimeToString(rates[i].time, TIME_MINUTES)         + "," +
               DoubleToString(rates[i].open,  digs)              + "," +
               DoubleToString(rates[i].high,  digs)              + "," +
               DoubleToString(rates[i].low,   digs)              + "," +
               DoubleToString(rates[i].close, digs)              + "," +
               IntegerToString((long)rates[i].tick_volume)       + "\r\n";
            FileWriteString(h, linha);
         }
         FileClose(h);

         totalBarras += n;
         if(n >= BarrasDesejadas)
         {
            ok++;
            PrintFormat("[OK]      %s %s — %d barras", simbolo, TFNome(tf), n);
         }
         else
         {
            parcial++;
            PrintFormat("[PARCIAL] %s %s — %d/%d barras", simbolo, TFNome(tf), n, BarrasDesejadas);
         }
      }
   }

   PrintFormat("=== RESUMO === OK=%d  PARCIAL=%d  FALHA=%d  | TOTAL BARRAS=%I64d",
               ok, parcial, falha, totalBarras);
   PrintFormat("Arquivos em: <MQL5\\Files>\\%s_*\\", PastaBase);
}
//+------------------------------------------------------------------+
