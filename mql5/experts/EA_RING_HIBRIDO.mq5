//+------------------------------------------------------------------+
//| EA_RING_HIBRIDO.mq5                                              |
//|       RING MTF TREND PRO + Validacao Inteligente                 |
//|  Combina RING Score (0-100), divergencias, momentum              |
//|  e confluencia MTF para filtragem de sinais.                     |
//|  Preparado para integracao futura com modelos ONNX.              |
//+------------------------------------------------------------------+
#property copyright "RoneiRosar23"
#property version "2.00"
#property description "EA Hibrido: RING Score + Divergencias + ONNX-ready"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string   I0="======== CONFIGURACOES GERAIS ========";
input int      InpMagic        = 20240703;
input double   InpLots         = 0.01;
input bool     InpAutoLot      = false;
input double   InpRiskPct      = 1.0;

input string   I1="======== FILTRO DE SINAIS ========";
input int      InpMinScore     = 80;
input int      InpMinScoreEarly= 60;

input string   I2="======== TP/SL ========";
input bool     InpUseATR       = true;
input double   InpTP_Ratio     = 2.0;
input double   InpSL_Ratio     = 1.0;

input string   I3="======== GESTAO ========";
input int      InpMaxPos       = 1;
input bool     InpTrailSL      = false;
input double   InpTrailATR     = 1.5;
input bool     InpBE           = true;
input double   InpBE_ATR       = 1.0;

//--- ONNX (preparado para uso futuro)
input string   I4="======== ONNX ML (FUTURO) ========";
input bool     InpONNX_Ready   = false;
input string   InpONNX_File    = "model.onnx";

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade         Trade;
CPositionInfo  Pos;
CAccountInfo   Acc;

int            hIndicator;
double         lastATR = 0;
datetime       lastBar = 0;
int            dDigits;
double         dPoint;
string         sSymbol;

//+------------------------------------------------------------------+
int OnInit()
{
   Trade.SetExpertMagicNumber(InpMagic);
   sSymbol = _Symbol;
   dDigits = (int)SymbolInfoInteger(sSymbol, SYMBOL_DIGITS);
   dPoint  = SymbolInfoDouble(sSymbol, SYMBOL_POINT);

   hIndicator = iCustom(sSymbol, PERIOD_CURRENT, "RING_MTF_TREND_PRO", 0, 0);
   if(hIndicator == INVALID_HANDLE)
   {
      Print("ERRO: Indicador RING_MTF_TREND_PRO nao encontrado!");
      Print("Compile: Indicators\\RING_MTF_TREND_PRO.mq5 primeiro");
      return INIT_FAILED;
   }

   if(InpONNX_Ready)
      Print("MODO ONNX: Ative quando tiver o modelo .onnx em \\Files\\");

   lastBar = 0;
   ChartRedraw();
   Print("EA RING HIBRIDO iniciado em ", sSymbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int r)
{
   if(hIndicator != INVALID_HANDLE)
      IndicatorRelease(hIndicator);
   Comment("");
   Print("EA RING HIBRIDO finalizado.");
}

//+------------------------------------------------------------------+
void OnTick()
{
   //--- Nova barra?
   datetime barTime = iTime(sSymbol, PERIOD_CURRENT, 0);
   bool newBar = (barTime != lastBar);
   if(newBar) lastBar = barTime;

   //--- Atualizar ATR
   int hATR = iATR(sSymbol, PERIOD_CURRENT, 14);
   double bufATR[];
   if(CopyBuffer(hATR, 0, 0, 1, bufATR) > 0)
      lastATR = bufATR[0];
   IndicatorRelease(hATR);

   //--- Ler buffers do indicador RING
   double bEarlyBuy[], bEarlySell[], bConfBuy[], bConfSell[];
   ArraySetAsSeries(bEarlyBuy, true);
   ArraySetAsSeries(bEarlySell, true);
   ArraySetAsSeries(bConfBuy, true);
   ArraySetAsSeries(bConfSell, true);

   bool hasData = false;
   if(CopyBuffer(hIndicator, 0, 0, 1, bEarlyBuy)  > 0) hasData = true;
   if(CopyBuffer(hIndicator, 1, 0, 1, bEarlySell) > 0) hasData = true;
   if(CopyBuffer(hIndicator, 2, 0, 1, bConfBuy)   > 0) hasData = true;
   if(CopyBuffer(hIndicator, 3, 0, 1, bConfSell)  > 0) hasData = true;

   if(!hasData)
   {
      Comment("A aguardar dados do RING...");
      return;
   }

   bool buyEarly  = (bEarlyBuy[0]  != EMPTY_VALUE);
   bool sellEarly = (bEarlySell[0] != EMPTY_VALUE);
   bool buyConf   = (bConfBuy[0]   != EMPTY_VALUE);
   bool sellConf  = (bConfSell[0]  != EMPTY_VALUE);

   //--- Decidir acao
   int acao = -1; // 0=Buy, 1=Sell
   string sSinal = "", sRazao = "";

   if(buyConf)
   {
      acao = 0;
      sSinal = "COMPRA FORTE";
      sRazao = "RING Score >= " + IntegerToString(InpMinScore);
   }
   else if(buyEarly && !sellConf)
   {
      acao = 0;
      sSinal = "COMPRA EARLY";
      sRazao = "RING Score >= " + IntegerToString(InpMinScoreEarly);
   }

   if(sellConf)
   {
      acao = 1;
      sSinal = "VENDA FORTE";
      sRazao = "RING Score >= " + IntegerToString(InpMinScore);
   }
   else if(sellEarly && !buyConf)
   {
      acao = 1;
      sSinal = "VENDA EARLY";
      sRazao = "RING Score >= " + IntegerToString(InpMinScoreEarly);
   }

   //--- ONNX validation (preparado para futuro)
   if(InpONNX_Ready && acao >= 0)
   {
      //--- Aqui chamara a funcao de validacao ONNX
      //--- Quando voce tiver o modelo .onnx, descomente:
      // if(!ValidarONNX(acao))
      // {
      //    sRazao += " [BLOQUEADO ONNX]";
      //    acao = -1;
      // }
      // else sRazao += " [VALIDADO ONNX]";

      //--- Por enquanto: simula validacao ONNX baseada em RSI
      int hRSI = iRSI(sSymbol, PERIOD_CURRENT, 14, PRICE_CLOSE);
      double bufRSI[];
      bool onnxOk = true;

      if(CopyBuffer(hRSI, 0, 0, 1, bufRSI) > 0)
      {
         double rsi = bufRSI[0];
         //--- Simula validacao ML: RSI confirmando o sinal
         if(acao == 0 && rsi > 70) onnxOk = false; // RSI muito alto para compra
         if(acao == 1 && rsi < 30) onnxOk = false; // RSI muito baixo para venda

         if(onnxOk)
            sRazao += " [RSI OK]";
         else
         {
            sRazao += " [RSI BLOQUEOU]";
            acao = -1;
         }
      }
      IndicatorRelease(hRSI);
   }

   //--- Executar trade
   if(acao >= 0)
      Executar(acao, sSinal, sRazao);

   //--- Gerenciar posicoes abertas
   if(InpTrailSL || InpBE)
      Gerenciar();

   //--- Info no ecra
   Info(sSinal, sRazao, acao);
}

//+------------------------------------------------------------------+
void Executar(int acao, string sinal, string razao)
{
   //--- Verificar limite de posicoes
   if(CountPos() >= InpMaxPos)
   {
      Print("Maximo de ", InpMaxPos, " posicoes atingido.");
      return;
   }

   double bid = SymbolInfoDouble(sSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(sSymbol, SYMBOL_ASK);
   double lot = InpAutoLot ? CalcLote() : InpLots;
   double sl, tp;

   if(InpUseATR && lastATR > 0)
   {
      if(acao == 0) // Buy
      {
         sl = bid - lastATR * InpSL_Ratio;
         tp = ask + lastATR * InpTP_Ratio;
      }
      else // Sell
      {
         sl = ask + lastATR * InpSL_Ratio;
         tp = bid - lastATR * InpTP_Ratio;
      }
   }
   else
   {
      double pips = 50 * dPoint * 10;
      if(acao == 0)
      {
         sl = bid - pips;
         tp = ask + pips * 2;
      }
      else
      {
         sl = ask + pips;
         tp = bid - pips * 2;
      }
   }

   sl = NormalizeDouble(sl, dDigits);
   tp = NormalizeDouble(tp, dDigits);

   bool ok = false;
   if(acao == 0)
      ok = Trade.Buy(lot, sSymbol, 0, sl, tp, razao);
   else
      ok = Trade.Sell(lot, sSymbol, 0, sl, tp, razao);

   if(ok)
   {
      Print("=== ", (acao==0?"COMPRA":"VENDA"), " EXECUTADA ===");
      Print("Sinal: ", sinal, " | ", razao);
      Print("Lot: ", lot, " | SL: ", sl, " | TP: ", tp);
   }
   else
      Print("ERRO ao executar: ", GetLastError());
}

//+------------------------------------------------------------------+
void Gerenciar()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!Pos.SelectByIndex(i)) continue;
      if(Pos.Symbol() != sSymbol || Pos.Magic() != InpMagic) continue;

      double sl = Pos.StopLoss();
      double tp = Pos.TakeProfit();
      double openPrice = Pos.PriceOpen();
      double current = Pos.PriceCurrent();
      int tipo = (int)Pos.PositionType();
      double dist = MathAbs(current - openPrice);

      //--- Breakeven
      if(InpBE && sl == 0 && dist >= lastATR * InpBE_ATR)
      {
         double novoSL = (tipo == POSITION_TYPE_BUY) ?
            openPrice - dPoint * 10 :
            openPrice + dPoint * 10;
         Trade.PositionModify(Pos.Ticket(), NormalizeDouble(novoSL, dDigits), tp);
         Print("Breakeven ativado!");
      }

      //--- Trailing Stop
      if(InpTrailSL && dist >= lastATR * InpTrailATR)
      {
         double trail = (tipo == POSITION_TYPE_BUY) ?
            current - lastATR * InpSL_Ratio :
            current + lastATR * InpSL_Ratio;

         bool podeMover = (tipo == POSITION_TYPE_BUY) ? (trail > sl) : (trail < sl);
         if(podeMover)
            Trade.PositionModify(Pos.Ticket(), NormalizeDouble(trail, dDigits), tp);
      }
   }
}

//+------------------------------------------------------------------+
int CountPos()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(Pos.SelectByIndex(i) && Pos.Symbol() == sSymbol && Pos.Magic() == InpMagic)
         c++;
   }
   return c;
}

//+------------------------------------------------------------------+
double CalcLote()
{
   double bal = Acc.Balance();
   double slDist = InpUseATR ? lastATR * InpSL_Ratio : 50 * dPoint * 10;
   double tickVal = SymbolInfoDouble(sSymbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickVal <= 0 || slDist <= 0) return InpLots;

   double riskAmt = bal * InpRiskPct / 100.0;
   double lot = riskAmt / (slDist / dPoint * tickVal);

   double minLot = SymbolInfoDouble(sSymbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(sSymbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / step) * step;
   if(lot < minLot) lot = minLot;

   double maxLot = SymbolInfoDouble(sSymbol, SYMBOL_VOLUME_MAX);
   if(lot > maxLot) lot = maxLot;

   return lot;
}

//+------------------------------------------------------------------+
void Info(string sinal, string razao, int acao)
{
   string txt = "";
   txt += "=== EA RING HIBRIDO ===\n";
   txt += sSymbol + " | " + EnumToString(PERIOD_CURRENT) + "\n";
   txt += "ATR: " + DoubleToString(lastATR, dDigits) + "\n";
   txt += "Posicoes: " + IntegerToString(CountPos()) + "/" + IntegerToString(InpMaxPos) + "\n";
   txt += "ONNX: " + (InpONNX_Ready ? "PRONTO" : "---") + "\n";
   txt += "\n";

   if(acao >= 0)
   {
      txt += ">>> " + sinal + " <<<\n";
      txt += razao + "\n";
   }
   else
      txt += "Aguardando sinal...\n";

   txt += "\n";
   txt += "Balance: $" + DoubleToString(Acc.Balance(), 2) + "\n";
   txt += "Equity:  $" + DoubleToString(Acc.Equity(), 2);

   Comment(txt);
}
//+------------------------------------------------------------------+
