//+------------------------------------------------------------------+
//|                                          TRIVIUM_TESTE_EA.mq5    |
//|  EA minimo so para validar o fluxo colar -> compilar -> anexar  |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"

int OnInit()
{
   Print("TRIVIUM_TESTE_EA inicializado em ", Symbol(), " ", EnumToString(Period()));
   Comment("TRIVIUM_TESTE_EA rodando - ", TimeToString(TimeCurrent()));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Comment("");
}

void OnTick()
{
   static datetime lastBar = 0;
   datetime currentBar = iTime(Symbol(), Period(), 0);
   if (currentBar != lastBar)
   {
      lastBar = currentBar;
      Print("Novo candle em ", Symbol(), " - close anterior: ", iClose(Symbol(), Period(), 1));
   }
}
