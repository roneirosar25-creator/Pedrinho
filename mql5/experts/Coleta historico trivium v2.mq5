//+------------------------------------------------------------------+
//|                              COLETA_HISTORICO_TRIVIUM_v2.mq5     |
//|                                        TRIVIUM369 / Cláudio      |
//|                                                                   |
//|  SCRIPT MQL5 — roda UMA vez e encerra.                           |
//|  Coleta histórico direto do servidor da corretora (Admirals).    |
//|                                                                   |
//|  Colunas: datetime, open, high, low, close,                      |
//|           tick_volume, real_volume, spread                        |
//|                                                                   |
//|  - datetime unificado: YYYY.MM.DD HH:MM                          |
//|  - OHLC com dígitos exatos do símbolo (sem distorção)            |
//|  - Arredondamento ao mais próximo (padrão matemático)            |
//|  - tick_volume, real_volume e spread como inteiro                 |
//|  - Retentativas para forçar download do histórico                |
//|  - Loga OK / PARCIAL / FALHA por combinação                      |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

//=== PARÂMETROS EDITÁVEIS ==========================================
input int    BarrasDesejadas = 100000;         // teto de barras por combinação
input int    MaxTentativas   = 20;             // tentativas p/ forçar download
input int    EsperaMs        = 400;            // espera entre tentativas (ms)
input string PastaBase       = "DADOS_BRUTOS"; // prefixo da pasta de saída

//=== NOMES DOS SÍMBOLOS NA ADMIRALS ================================
//  Se a Admirals usa sufixo (ex: "EURUSD-T"), corrija aqui.
//  O script avisa se não encontrar o símbolo.
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
//| Formata datetime como YYYY.MM.DD HH:MM                           |
//+------------------------------------------------------------------+
string FormatDatetime(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d.%02d.%02d %02d:%02d",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min);
}

//+------------------------------------------------------------------+
//| Força download e copia. Retorna nº de barras (ou -1 em erro).   |
//| Para quando atinge teto OU quando estabiliza (histórico esgotado)|
//+------------------------------------------------------------------+
int ColetaRates(string simbolo, ENUM_TIMEFRAMES tf, MqlRates &rates[])
{
   ArraySetAsSeries(rates, false); // index 0 = barra mais antiga
   int copiadas = 0;
   int anterior = -999;
   int estavel  = 0;

   for(int tent=0; tent<MaxTentativas; tent++)
   {
      copiadas = CopyRates(simbolo, tf, 0, BarrasDesejadas, rates);

      if(copiadas >= BarrasDesejadas)
         break;                    // chegou no teto pedido

      if(copiadas > 0 && copiadas == anterior)
      {
         estavel++;
         if(estavel >= 2)
            break;                 // estabilizou = é todo o histórico disponível
      }
      else
         estavel = 0;

      anterior = copiadas;
      Sleep(EsperaMs);
   }
   return copiadas;
}

//+------------------------------------------------------------------+
void OnStart()
{
   int nAtivos     = ArraySize(Ativos);
   int nTFs        = ArraySize(TFs);
   int totalCombos = nAtivos * nTFs;
   int ok=0, parcial=0, falha=0;
   long totalBarras=0;

   PrintFormat("=== COLETA TRIVIUM369 v2 — %d combinações (%d ativos × %d TFs) ===",
               totalCombos, nAtivos, nTFs);

   for(int a=0; a<nAtivos; a++)
   {
      string simbolo = Ativos[a];

      if(!SymbolSelect(simbolo, true))
      {
         PrintFormat("[ERRO] Símbolo não encontrado: '%s' — verifique o nome exato. Pulando %d TFs.",
                     simbolo, nTFs);
         falha += nTFs;
         continue;
      }

      // dígitos exatos do símbolo (EURUSD=5, USDJPY=3, XAUUSD=2, etc.)
      int digs = (int)SymbolInfoInteger(simbolo, SYMBOL_DIGITS);
      if(digs <= 0) digs = 5;

      for(int t=0; t<nTFs; t++)
      {
         ENUM_TIMEFRAMES tf = TFs[t];
         MqlRates rates[];
         int n = ColetaRates(simbolo, tf, rates);

         if(n <= 0)
         {
            PrintFormat("[FALHA] %s %s — CopyRates retornou %d (erro %d)",
                        simbolo, TFNome(tf), n, GetLastError());
            ResetLastError();
            falha++;
            continue;
         }

         // pasta: DADOS_BRUTOS_EURUSD-T\ etc.
         string pasta   = StringFormat("%s_%s", PastaBase, simbolo);
         // arquivo: M1_EURUSD-T.csv etc.
         string arquivo = StringFormat("%s\\%s_%s.csv", pasta, TFNome(tf), simbolo);

         int h = FileOpen(arquivo, FILE_WRITE|FILE_TXT|FILE_ANSI);
         if(h == INVALID_HANDLE)
         {
            PrintFormat("[FALHA] Não abriu arquivo '%s' (erro %d)", arquivo, GetLastError());
            ResetLastError();
            falha++;
            continue;
         }

         // cabeçalho
         FileWriteString(h, "datetime,open,high,low,close,tick_volume,real_volume,spread\r\n");

         // dados
         for(int i=0; i<n; i++)
         {
            string linha = StringFormat("%s,%s,%s,%s,%s,%I64d,%I64d,%d\r\n",
               FormatDatetime(rates[i].time),
               DoubleToString(rates[i].open,  digs),
               DoubleToString(rates[i].high,  digs),
               DoubleToString(rates[i].low,   digs),
               DoubleToString(rates[i].close, digs),
               (long)rates[i].tick_volume,
               (long)rates[i].real_volume,
               (int) rates[i].spread);
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
            PrintFormat("[PARCIAL] %s %s — %d/%d barras (todo histórico disponível)",
                        simbolo, TFNome(tf), n, BarrasDesejadas);
         }
      }
   }

   PrintFormat("=== FIM === OK=%d  PARCIAL=%d  FALHA=%d  | total barras=%I64d",
               ok, parcial, falha, totalBarras);
   PrintFormat("Arquivos em: <Pasta de Dados>\\MQL5\\Files\\%s_<ATIVO>\\", PastaBase);
}
//+------------------------------------------------------------------+