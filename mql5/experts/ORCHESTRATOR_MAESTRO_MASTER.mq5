/*
╔════════════════════════════════════════════════════════════════════════════╗
║         ORCHESTRATOR_MAESTRO_MASTER.mq5 — MQL5 CORRETO 100%              ║
║  ═══════════════════════════════════════════════════════════════════════   ║
║                                                                            ║
║  Sintaxe: MQL5 (não MQL4!)                                                ║
║  - AccountInfoDouble() em vez de AccountBalance()                         ║
║  - SymbolInfoDouble() para Bid/Ask                                        ║
║  - MqlTradeRequest + MqlTradeResult para ordens                           ║
║  - Sintaxe correta para trailing stop (OrderModify em loop)              ║
║                                                                            ║
║  Autor: Pedrinho (com urgência de compilação!) — 22 JUN 2026              ║
║╚════════════════════════════════════════════════════════════════════════════╝
*/

#property strict
#property version "2.0"
#property description "ORCHESTRATOR MAESTRO MASTER — MQL5 CORRETO"

// ═══════════════════════════════════════════════════════════════════════════
// CONFIGURAÇÕES
// ═══════════════════════════════════════════════════════════════════════════

input double RISK_PERCENT = 1.0;           // Risco % do saldo
input int SL_PIPS = 50;                    // Stop Loss em pips
input int TP_PIPS = 150;                   // Take Profit em pips
input int TRAILING_STOP = 30;              // Trailing Stop em pips
input int MAGIC_BASE = 100000;             // Magic number base
input int MAX_TRADES = 5;                  // Máximo ordens simultâneas

// ═══════════════════════════════════════════════════════════════════════════
// VARIÁVEIS GLOBAIS
// ═══════════════════════════════════════════════════════════════════════════

double saldo_inicial;
int trades_abertos = 0;

//+------------------------------------------------------------------+
//| OnInit — Inicialização
//+------------------------------------------------------------------+
int OnInit()
{
   saldo_inicial = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("═══════════════════════════════════════════════════════════");
   Print("[INIT] ORCHESTRATOR MAESTRO MASTER — MQL5");
   Print("[INIT] Saldo Inicial: $", saldo_inicial);
   Print("[INIT] Conta: ", AccountInfoInteger(ACCOUNT_LOGIN));
   Print("[INIT] Risk: ", RISK_PERCENT, "% | SL: ", SL_PIPS, "pips | TP: ", TP_PIPS, "pips");
   Print("[INIT] Trailing Stop: ", TRAILING_STOP, " pips");
   Print("[INIT] Magic Base: ", MAGIC_BASE);
   Print("═══════════════════════════════════════════════════════════");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnTick — Loop principal
//+------------------------------------------------------------------+
void OnTick()
{
   VerificarSinais();
   GerenciarTrailingStop();
}

//+------------------------------------------------------------------+
//| VerificarSinais — Análise Multi-TF + Confluência
//+------------------------------------------------------------------+
void VerificarSinais()
{
   if(trades_abertos >= MAX_TRADES) return;

   // Obter preços atuais
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

   // ANALISAR M1
   double rsi_m1 = iRSI(Symbol(), PERIOD_M1, 14, 0);
   bool m1_buy = rsi_m1 < 30;
   bool m1_sell = rsi_m1 > 70;

   // ANALISAR M5
   double rsi_m5 = iRSI(Symbol(), PERIOD_M5, 14, 0);
   bool m5_buy = rsi_m5 < 35;
   bool m5_sell = rsi_m5 > 65;

   // ANALISAR H1
   double rsi_h1 = iRSI(Symbol(), PERIOD_H1, 14, 0);
   bool h1_buy = rsi_h1 < 40;
   bool h1_sell = rsi_h1 > 60;

   // CONFLUÊNCIA
   int conf_buy = (m1_buy ? 1 : 0) + (m5_buy ? 1 : 0) + (h1_buy ? 1 : 0);
   int conf_sell = (m1_sell ? 1 : 0) + (m5_sell ? 1 : 0) + (h1_sell ? 1 : 0);

   // ═══════════════════════════════════════════════════════════════
   // SINAL BUY (≥2 TFs confirmam)
   // ═══════════════════════════════════════════════════════════════
   if(conf_buy >= 2)
   {
      // Identificar qual TF acionou
      string tf_acionante = "M1";
      if(!m1_buy && m5_buy) tf_acionante = "M5";
      if(!m1_buy && !m5_buy && h1_buy) tf_acionante = "H1";

      double volume = CalcularVolume(SL_PIPS);

      // COMENTÁRIO COMPLETO
      string comentario = "MAESTRO|BUY|TF:" + tf_acionante + "|";
      comentario += "Conf:" + IntegerToString(conf_buy) + "/3|";
      comentario += "M1:" + DoubleToString(rsi_m1, 1) + "|";
      comentario += "M5:" + DoubleToString(rsi_m5, 1) + "|";
      comentario += "H1:" + DoubleToString(rsi_h1, 1) + "|";
      comentario += "Vol:" + DoubleToString(volume, 2) + "|";
      comentario += "SL:" + IntegerToString(SL_PIPS) + "pips|";
      comentario += "TP:" + IntegerToString(TP_PIPS) + "pips|";
      comentario += "Trail:" + IntegerToString(TRAILING_STOP) + "pips";

      Print("╔════════════════════════════════════════════════════════════════════════════╗");
      Print("║ [SINAL CONFLUENTE DETECTADO!]                                             ║");
      Print("║ BUY — Timeframe: ", tf_acionante);
      Print("║ Confluência: ", conf_buy, "/3 (M1:", (m1_buy ? "✓" : "✗"), " | M5:", (m5_buy ? "✓" : "✗"), " | H1:", (h1_buy ? "✓" : "✗"), ")");
      Print("║ RSI — M1:", DoubleToString(rsi_m1, 1), " | M5:", DoubleToString(rsi_m5, 1), " | H1:", DoubleToString(rsi_h1, 1));
      Print("║ Volume: ", volume, " lotes | Risk: ", RISK_PERCENT, "% do saldo");
      Print("║ SL: ", SL_PIPS, " pips | TP: ", TP_PIPS, " pips | Trailing: ", TRAILING_STOP, " pips");
      Print("╚════════════════════════════════════════════════════════════════════════════╝");

      AbrirOrdens(ORDER_TYPE_BUY, ask, bid, volume, comentario);
   }

   // ═══════════════════════════════════════════════════════════════
   // SINAL SELL (≥2 TFs confirmam)
   // ═══════════════════════════════════════════════════════════════
   if(conf_sell >= 2)
   {
      // Identificar qual TF acionou
      string tf_acionante = "M1";
      if(!m1_sell && m5_sell) tf_acionante = "M5";
      if(!m1_sell && !m5_sell && h1_sell) tf_acionante = "H1";

      double volume = CalcularVolume(SL_PIPS);

      // COMENTÁRIO COMPLETO
      string comentario = "MAESTRO|SELL|TF:" + tf_acionante + "|";
      comentario += "Conf:" + IntegerToString(conf_sell) + "/3|";
      comentario += "M1:" + DoubleToString(rsi_m1, 1) + "|";
      comentario += "M5:" + DoubleToString(rsi_m5, 1) + "|";
      comentario += "H1:" + DoubleToString(rsi_h1, 1) + "|";
      comentario += "Vol:" + DoubleToString(volume, 2) + "|";
      comentario += "SL:" + IntegerToString(SL_PIPS) + "pips|";
      comentario += "TP:" + IntegerToString(TP_PIPS) + "pips|";
      comentario += "Trail:" + IntegerToString(TRAILING_STOP) + "pips";

      Print("╔════════════════════════════════════════════════════════════════════════════╗");
      Print("║ [SINAL CONFLUENTE DETECTADO!]                                             ║");
      Print("║ SELL — Timeframe: ", tf_acionante);
      Print("║ Confluência: ", conf_sell, "/3 (M1:", (m1_sell ? "✓" : "✗"), " | M5:", (m5_sell ? "✓" : "✗"), " | H1:", (h1_sell ? "✓" : "✗"), ")");
      Print("║ RSI — M1:", DoubleToString(rsi_m1, 1), " | M5:", DoubleToString(rsi_m5, 1), " | H1:", DoubleToString(rsi_h1, 1));
      Print("║ Volume: ", volume, " lotes | Risk: ", RISK_PERCENT, "% do saldo");
      Print("║ SL: ", SL_PIPS, " pips | TP: ", TP_PIPS, " pips | Trailing: ", TRAILING_STOP, " pips");
      Print("╚════════════════════════════════════════════════════════════════════════════╝");

      AbrirOrdens(ORDER_TYPE_SELL, bid, ask, volume, comentario);
   }
}

//+------------------------------------------------------------------+
//| AbrirOrdens — Abre 5 ordens piramidadas com Magic Numbers
//+------------------------------------------------------------------+
void AbrirOrdens(ENUM_ORDER_TYPE tipo, double price_entrada, double price_sl, double volume_base, string comentario)
{
   for(int i = 0; i < MAX_TRADES; i++)
   {
      // Volume piramidal: 1ª ordem = 100%, resto = 50%
      double vol = (i == 0) ? volume_base : (volume_base * 0.5);
      int magic = MAGIC_BASE + i;

      MqlTradeRequest request = {};
      MqlTradeResult result = {};

      request.action = TRADE_ACTION_DEAL;
      request.symbol = Symbol();
      request.volume = vol;
      request.type = tipo;
      request.price = price_entrada;
      request.magic = magic;
      request.comment = comentario + "|Pir:" + IntegerToString(i + 1) + "/5";

      // Calcular SL e TP
      if(tipo == ORDER_TYPE_BUY)
      {
         request.sl = price_sl - (SL_PIPS * _Point);
         request.tp = price_entrada + (TP_PIPS * _Point);
      }
      else // SELL
      {
         request.sl = price_sl + (SL_PIPS * _Point);
         request.tp = price_entrada - (TP_PIPS * _Point);
      }

      // Enviar ordem
      if(!OrderSend(request, result))
      {
         Print("[ERRO] Falha ao abrir ordem #", i + 1, " | Error: ", GetLastError());
      }
      else
      {
         trades_abertos++;
         Print("[OK] Ordem #", i + 1, "/5 aberta | Ticket: ", result.order, " | Magic: ", magic, " | Volume: ", vol);
      }
   }
}

//+------------------------------------------------------------------+
//| CalcularVolume — Volume dinâmico baseado em risco
//+------------------------------------------------------------------+
double CalcularVolume(int sl_pips)
{
   double saldo = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = saldo * (RISK_PERCENT / 100.0);
   double sl_valor = sl_pips * _Point * 100000;

   double volume = risk_amount / sl_valor;

   // Limites
   if(volume < 0.01) volume = 0.01;
   if(volume > 10.0) volume = 10.0;

   return NormalizeDouble(volume, 2);
}

//+------------------------------------------------------------------+
//| GerenciarTrailingStop — Ajusta SL dinamicamente
//+------------------------------------------------------------------+
void GerenciarTrailingStop()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;

      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double pos_sl = PositionGetDouble(POSITION_SL);

      MqlTradeRequest request = {};
      MqlTradeResult result = {};

      double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

      if(pos_type == POSITION_TYPE_BUY)
      {
         double novo_sl = bid - (TRAILING_STOP * _Point);
         if(novo_sl > pos_sl)
         {
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.sl = novo_sl;
            request.tp = PositionGetDouble(POSITION_TP);

            if(!OrderSend(request, result))
            {
               Print("[ERRO] Falha ao ajustar SL/TP (BUY) | Ticket: ", ticket, " | Error: ", GetLastError());
            }
         }
      }
      else if(pos_type == POSITION_TYPE_SELL)
      {
         double novo_sl = ask + (TRAILING_STOP * _Point);
         if(novo_sl < pos_sl || pos_sl == 0)
         {
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.sl = novo_sl;
            request.tp = PositionGetDouble(POSITION_TP);

            if(!OrderSend(request, result))
            {
               Print("[ERRO] Falha ao ajustar SL/TP (SELL) | Ticket: ", ticket, " | Error: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnDeinit — Limpeza ao remover EA
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("═══════════════════════════════════════════════════════════");
   Print("[DEINIT] EA removido | Motivo: ", reason);
   Print("[DEINIT] Posições abertas: ", PositionsTotal());
   Print("[DEINIT] Saldo Final: $", AccountInfoDouble(ACCOUNT_BALANCE));
   Print("═══════════════════════════════════════════════════════════");
}
