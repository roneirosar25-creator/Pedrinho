//+------------------------------------------------------------------+
//| NEXUS369_DIAG.mq5 - EA de diagnostico do TRIVIUM_LEVELS          |
//| Pedrinho 06 JUL 2026 - conta setas no buffer sem depender de     |
//| inspecao visual. Roda no Strategy Tester (Visual=Nao).           |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"

int h_ind;

int OnInit()
{
   h_ind = iCustom(_Symbol, _Period, "TRIVIUM_LEVELS");
   if(h_ind == INVALID_HANDLE)
   {
      Print("DIAG: handle invalido");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
}

void OnDeinit(const int reason)
{
   int total = Bars(_Symbol, _Period);
   double buy[], sell[];
   ArraySetAsSeries(buy, true);
   ArraySetAsSeries(sell, true);

   int cb = CopyBuffer(h_ind, 8, 0, total, buy);
   int cs = CopyBuffer(h_ind, 9, 0, total, sell);

   int nbuy = 0, nsell = 0;
   int first_buy_idx = -1, first_sell_idx = -1;

   for(int i = 0; i < cb; i++)
      if(buy[i] != EMPTY_VALUE && buy[i] != 0.0)
      {
         nbuy++;
         if(first_buy_idx == -1) first_buy_idx = i;
      }
   for(int i = 0; i < cs; i++)
      if(sell[i] != EMPTY_VALUE && sell[i] != 0.0)
      {
         nsell++;
         if(first_sell_idx == -1) first_sell_idx = i;
      }

   string result = StringFormat(
      "DIAG %s %s | Barras copiadas Buy=%d Sell=%d | Setas COMPRA=%d Setas VENDA=%d | 1a compra idx=%d 1a venda idx=%d",
      _Symbol, EnumToString(_Period), cb, cs, nbuy, nsell, first_buy_idx, first_sell_idx);

   Print(result);

   int fh = FileOpen("NEXUS369_DIAG_RESULT.txt", FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(fh != INVALID_HANDLE)
   {
      FileWriteString(fh, result + "\n");
      FileClose(fh);
   }

   IndicatorRelease(h_ind);
}
