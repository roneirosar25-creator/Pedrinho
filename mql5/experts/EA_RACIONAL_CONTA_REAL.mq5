//+------------------------------------------------------------------+
//| EA_RACIONAL_CONTA_REAL.mq5                                       |
//| Conta REAL Headway 200987914 (Patricia) - alavancagem 1:500.     |
//| Objetivo: crescimento moderado, gestao de risco real,             |
//| respeitando janela de sessao por ativo. NAO EH agressivo.        |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"

input double RiscoPercentualMargemLivre = 15.0;   // % da margem livre usada por entrada (moderado)
input int    MomentumLookbackBars       = 12;      // velas M1 pra medir momentum
input double MomentumMinPips            = 3.0;     // distancia minima (pips) pra considerar sinal
input double StopLossPips               = 15.0;    // SL fixo em pips
input double TakeProfitPips             = 25.0;    // TP fixo em pips (RR ~1:1.7)
input int    MagicNumber                = 936902;

input bool   FiltrarSessao              = true;    // respeita janela de horario abaixo
input int    SessaoInicioHoraServidor   = 9;        // ajustar conforme fuso do servidor
input int    SessaoFimHoraServidor      = 17;

#include <Trade\Trade.mqh>
CTrade trade;

datetime ultimaVelaProcessada = 0;

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   Print("EA_RACIONAL_CONTA_REAL iniciado. Risco por entrada: ", RiscoPercentualMargemLivre,
         "% da margem livre. SL=", StopLossPips, " TP=", TakeProfitPips, " pips.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {}

bool DentroDaSessao()
{
   if(!FiltrarSessao) return true;
   MqlDateTime agora;
   TimeToStruct(TimeCurrent(), agora);
   return (agora.hour >= SessaoInicioHoraServidor && agora.hour < SessaoFimHoraServidor);
}

double PipSize(string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? point * 10 : point;
}

double CalcularLoteModerado(string symbol, ENUM_ORDER_TYPE tipo)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double alvoMargem = freeMargin * (RiscoPercentualMargemLivre / 100.0);

   double preco = (tipo == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(symbol, SYMBOL_BID);

   double margemPorLote = 0;
   if(!OrderCalcMargin(tipo, symbol, 1.0, preco, margemPorLote) || margemPorLote <= 0)
      return 0;

   double lote = alvoMargem / margemPorLote;

   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   lote = MathFloor(lote / lotStep) * lotStep;
   lote = MathMax(lotMin, MathMin(lotMax, lote));

   return lote;
}

double MomentumPips(string symbol, int lookback)
{
   double fechAtual = iClose(symbol, PERIOD_M1, 0);
   double fechAntigo = iClose(symbol, PERIOD_M1, lookback);
   return (fechAtual - fechAntigo) / PipSize(symbol);
}

void AbrirPosicaoModerada(string symbol, ENUM_ORDER_TYPE tipo)
{
   double lote = CalcularLoteModerado(symbol, tipo);
   if(lote <= 0)
   {
      Print("Margem insuficiente pro risco configurado em ", symbol, ".");
      return;
   }

   double pip = PipSize(symbol);
   double preco = (tipo == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                            : SymbolInfoDouble(symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   double sl = (tipo == ORDER_TYPE_BUY) ? preco - StopLossPips * pip : preco + StopLossPips * pip;
   double tp = (tipo == ORDER_TYPE_BUY) ? preco + TakeProfitPips * pip : preco - TakeProfitPips * pip;
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   bool ok = (tipo == ORDER_TYPE_BUY)
             ? trade.Buy(lote, symbol, 0, sl, tp, "RACIONAL-BUY")
             : trade.Sell(lote, symbol, 0, sl, tp, "RACIONAL-SELL");

   if(ok)
      Print("Posicao aberta em ", symbol, ": ", EnumToString(tipo), " lote=", lote, " SL=", sl, " TP=", tp);
   else
      Print("Falha ao abrir posicao em ", symbol, ". Erro: ", GetLastError());
}

void OnTick()
{
   string symbol = Symbol();
   if(!DentroDaSessao()) return;

   datetime velaAtual = iTime(symbol, PERIOD_M1, 0);
   if(velaAtual == ultimaVelaProcessada) return;
   ultimaVelaProcessada = velaAtual;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNumber
         && PositionGetString(POSITION_SYMBOL) == symbol)
         return;   // ja tem posicao aberta nesse ativo, nao duplica
   }

   double momentum = MomentumPips(symbol, MomentumLookbackBars);

   if(momentum >= MomentumMinPips)
      AbrirPosicaoModerada(symbol, ORDER_TYPE_BUY);
   else if(momentum <= -MomentumMinPips)
      AbrirPosicaoModerada(symbol, ORDER_TYPE_SELL);
}
