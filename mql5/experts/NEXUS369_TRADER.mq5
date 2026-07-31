//+------------------------------------------------------------------+
//| NEXUS369_TRADER.mq5                                              |
//| TRIVIUM369 © 2026 - "O melhor do melhor" - Fase 4                |
//| Pedrinho, madrugada 06 JUL 2026 - sintese de tudo estudado:      |
//|   - Le os sinais do TRIVIUM_LEVELS v2.08 (ja validado: 69.8%     |
//|     acerto real, +0.41R/trade, 16 ativos, metodo rigoroso)       |
//|   - Position sizing por risco% (ideia reaproveitada do           |
//|     EA_FRANKENSTEIN: CalcularLoteSym)                            |
//|   - Stop = 1xATR(55) contra o sinal, Alvo = linha central         |
//|     (EXATAMENTE a mesma regra usada na validacao Python)         |
//|   - Magic Number incremental por grupo de ativo (369-G-AA)       |
//|   - Anti-martingale: 1 posicao por simbolo, sem piramidar        |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 © 2026"
#property version   "1.10"
#include <Trade\Trade.mqh>

input group "=== Fonte de Sinal ==="
input string InpNomeIndicador = "TRIVIUM_LEVELS"; // Nome do indicador (deve estar compilado)

input group "=== Gestao de Risco ==="
input double InpRiskPercent    = 1.0;   // % do saldo arriscado por trade
input double InpMaxDDPercent   = 3.0;   // Drawdown maximo do dia - para tudo se bater
input int    InpMaxTradesDay   = 4;     // Maximo de trades por dia neste simbolo
input double InpStopATRMult    = 1.0;   // Stop = X * ATR(55) (mesma regra da validacao)

input group "=== Magic Number ==="
input long   InpMagicBase      = 369000; // Prefixo 369 + grupo + ativo (preenchido automatico)
input int    InpMagicAtivo     = 1;      // Numero sequencial do ativo dentro do grupo

input group "=== Confluencia Multi-Timeframe (opcional) ==="
input bool   InpUsarConfluenciaH4 = false; // Ligar = so opera se H4 confirmou (menos trades, +30% no R medio testado)
input ENUM_TIMEFRAMES InpTFConfluencia = PERIOD_H4; // Timeframe de confirmacao
input int    InpJanelaConfluenciaHoras = 48; // Janela pra procurar sinal H4 na mesma direcao

CTrade trade;
int    h_ind = INVALID_HANDLE;
int    h_ind_confl = INVALID_HANDLE;
double saldoInicioDia = 0;
datetime diaAtual = 0;
int    tradesHoje = 0;
long   magicFinal = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   h_ind = iCustom(_Symbol, _Period, InpNomeIndicador);
   if(h_ind == INVALID_HANDLE)
   {
      Print("NEXUS369_TRADER: falha ao carregar indicador ", InpNomeIndicador, ". EA nao vai operar.");
      return INIT_FAILED;
   }

   if(InpUsarConfluenciaH4)
   {
      h_ind_confl = iCustom(_Symbol, InpTFConfluencia, InpNomeIndicador);
      if(h_ind_confl == INVALID_HANDLE)
      {
         Print("NEXUS369_TRADER: falha ao carregar indicador de confluencia. EA nao vai operar.");
         return INIT_FAILED;
      }
   }

   // Magic Number: 369 + grupo(1=forex,2=commodity,3=cripto) + ativo(2 digitos)
   string sym = _Symbol; StringToUpper(sym);
   int grupo = 1;
   if(StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 || StringFind(sym,"XRP")>=0 ||
      StringFind(sym,"LTC")>=0 || StringFind(sym,"DOGE")>=0 || StringFind(sym,"SOL")>=0)
      grupo = 3;
   else if(StringFind(sym,"GOLD")>=0 || StringFind(sym,"XAU")>=0 || StringFind(sym,"SILVER")>=0 ||
           StringFind(sym,"XAG")>=0 || StringFind(sym,"COPPER")>=0)
      grupo = 2;

   magicFinal = InpMagicBase + (grupo * 100) + InpMagicAtivo;
   trade.SetExpertMagicNumber(magicFinal);
   trade.SetDeviationInPoints(30);

   saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   diaAtual = iTime(_Symbol, PERIOD_D1, 0);
   tradesHoje = 0;

   Print("NEXUS369_TRADER INIT | Magic=", magicFinal, " Grupo=", grupo,
         " Risco=", InpRiskPercent, "% StopATR=", InpStopATRMult, "x");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(h_ind != INVALID_HANDLE) IndicatorRelease(h_ind);
   if(h_ind_confl != INVALID_HANDLE) IndicatorRelease(h_ind_confl);
}

//+------------------------------------------------------------------+
// Confluencia: procura sinal no TF maior, mesma direcao, dentro da janela
//+------------------------------------------------------------------+
bool ConfluenciaConfirmada(bool ehCompra)
{
   if(!InpUsarConfluenciaH4) return true; // filtro desligado = sempre passa

   int barrasNecessarias = (int)MathCeil((double)InpJanelaConfluenciaHoras /
                                          (PeriodSeconds(InpTFConfluencia) / 3600.0)) + 2;
   barrasNecessarias = MathMax(barrasNecessarias, 5);

   double bufArr[];
   int bufferIdx = ehCompra ? 8 : 9;
   if(CopyBuffer(h_ind_confl, bufferIdx, 0, barrasNecessarias, bufArr) < 1)
      return false;

   for(int i = 0; i < ArraySize(bufArr); i++)
   {
      if(bufArr[i] != EMPTY_VALUE && bufArr[i] != 0.0)
         return true; // achou sinal na mesma direcao dentro da janela
   }
   return false;
}

//+------------------------------------------------------------------+
bool NovoDia()
{
   datetime hoje = iTime(_Symbol, PERIOD_D1, 0);
   if(hoje != diaAtual)
   {
      diaAtual = hoje;
      tradesHoje = 0;
      saldoInicioDia = AccountInfoDouble(ACCOUNT_EQUITY);
      return true;
   }
   return false;
}

bool DrawdownDiarioEstourado()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = (saldoInicioDia - equity) / saldoInicioDia * 100.0;
   return (ddPct >= InpMaxDDPercent);
}

bool TemPosicaoAberta()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == magicFinal)
            return true;
      }
   }
   return false;
}

double CalcularLote(double riskPct, double slDistPoints)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0 || slDistPoints <= 0) return 0.0;

   double valorPorPonto = tickValue * (point / tickSize);
   double lots = riskMoney / (slDistPoints * valorPorPonto);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / stepLot) * stepLot;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
}

//+------------------------------------------------------------------+
void OnTick()
{
   NovoDia();

   if(DrawdownDiarioEstourado())
      return; // trava de seguranca - nao opera mais hoje neste simbolo

   if(tradesHoje >= InpMaxTradesDay)
      return;

   if(TemPosicaoAberta())
      return; // anti-martingale: 1 posicao por vez, sem piramidar

   static datetime lastBarProcessed = 0;
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == lastBarProcessed)
      return; // so processa 1x por barra fechada
   lastBarProcessed = curBar;

   // Le os buffers do indicador na barra recem-fechada (shift 1)
   double buyArr[2], sellArr[2], centralArr[2], atrArr[2];
   if(CopyBuffer(h_ind, 8, 1, 1, buyArr) < 1) return;
   if(CopyBuffer(h_ind, 9, 1, 1, sellArr) < 1) return;
   if(CopyBuffer(h_ind, 0, 1, 1, centralArr) < 1) return;
   if(CopyBuffer(h_ind, 7, 1, 1, atrArr) < 1) return;

   bool sinalCompra = (buyArr[0] != EMPTY_VALUE && buyArr[0] != 0.0);
   bool sinalVenda  = (sellArr[0] != EMPTY_VALUE && sellArr[0] != 0.0);
   double central = centralArr[0];
   double atr = atrArr[0];

   if(atr <= 0 || central == EMPTY_VALUE) return;
   if(!sinalCompra && !sinalVenda) return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(sinalCompra && !ConfluenciaConfirmada(true)) sinalCompra = false;
   if(sinalVenda && !ConfluenciaConfirmada(false)) sinalVenda = false;
   if(!sinalCompra && !sinalVenda) return;

   if(sinalCompra && !sinalVenda)
   {
      double entry = ask;
      double sl = entry - InpStopATRMult * atr;
      double tp = central;
      double slDistPoints = (entry - sl) / point;
      double lots = CalcularLote(InpRiskPercent, slDistPoints);
      if(lots > 0 && tp > entry)
      {
         if(trade.Buy(lots, _Symbol, entry, sl, tp, "NEXUS369 v2.08"))
            tradesHoje++;
      }
   }
   else if(sinalVenda && !sinalCompra)
   {
      double entry = bid;
      double sl = entry + InpStopATRMult * atr;
      double tp = central;
      double slDistPoints = (sl - entry) / point;
      double lots = CalcularLote(InpRiskPercent, slDistPoints);
      if(lots > 0 && tp < entry)
      {
         if(trade.Sell(lots, _Symbol, entry, sl, tp, "NEXUS369 v2.08"))
            tradesHoje++;
      }
   }
}
//+------------------------------------------------------------------+
