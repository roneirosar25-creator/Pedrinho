//+------------------------------------------------------------------+
//| TRIVIUM_AUTO_SLTP_EA.mq5                                          |
//| TRIVIUM369 (c) 2026 - Pedrinho, 15/07/2026                        |
//|                                                                    |
//| Pedido do Ronei: quando ele abre uma posicao manual sem definir    |
//| SL e/ou TP, esse EA preenche automaticamente com base nas linhas   |
//| de suporte/resistencia ja desenhadas pelo TRIVIUM_DESENHAR_SR      |
//| (objetos "TRIVIUM_SR_..._SUP"/"..._RES" no grafico).               |
//|                                                                    |
//| COMPRA sem SL: usa o suporte mais proximo ABAIXO do preco.         |
//| COMPRA sem TP: usa a resistencia mais proxima ACIMA do preco.      |
//| VENDA  sem SL: usa a resistencia mais proxima ACIMA do preco.      |
//| VENDA  sem TP: usa o suporte mais proximo ABAIXO do preco.         |
//|                                                                    |
//| So mexe em posicoes com magic=0 (abertas manualmente) - nunca      |
//| toca em posicoes que ja tem SL/TP definidos, e nunca toca em       |
//| posicoes abertas por outros EAs TRIVIUM/NEXUS (que gerenciam o     |
//| proprio SL/TP sozinhos).                                           |
//|                                                                    |
//| So ativa se o grafico onde esse EA esta anexado tiver as linhas    |
//| TRIVIUM_SR_ desenhadas (rode o script TRIVIUM_DESENHAR_SR antes,   |
//| ou o indicador TRIVIUM_PAINEL_COMPLETO que ja desenha sozinho).    |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

// Kill switch: aqui NAO abre posicao nenhuma, so preenche SL/TP em posicoes ja
// abertas manualmente por Ronei - risco baixo (so protege, nao executa), mas mantem
// o padrao do projeto de ter um interruptor. Default LIGADO porque, sem isso ligado,
// o EA nao serve pra nada (foi pedido explicito do Ronei "quero que isso seja feito
// agora").
input bool   InpAutoSLTP_Ativo   = true;
input int    InpMagicFiltro      = 0;     // so mexe em posicoes com esse magic (0 = manuais)
input double InpMargemExtraPts   = 20;    // pontos de folga alem do nivel de S/R (evita SL/TP grudado)

// 15/07/2026 v2 - PEDIDO DO RONEI: escolher qual linha de S/R usar, nao so "a mais
// proxima". Duas formas, cada uma separada pra SL e pra TP:
//  Timeframe: "" = qualquer TF, ou "M1"/"M2"/"M5"/"M15"/"H1"/"H4"/"D1" pra travar
//   num timeframe especifico (ex: "quero a resistencia do M2").
//  Rank: 1 = a mais proxima (dentro do filtro de timeframe acima), 2 = a segunda
//   mais proxima, etc. (ex: "quero a segunda linha de resistencia").
input string InpSL_Timeframe = ""; // filtro de TF pro SL - vazio = qualquer
input int    InpSL_Rank      = 1;  // 1a, 2a, 3a linha mais proxima pro SL
input string InpTP_Timeframe = ""; // filtro de TF pro TP - vazio = qualquer
input int    InpTP_Rank      = 1;  // 1a, 2a, 3a linha mais proxima pro TP

// Correcao 01/08/2026: se nao existir linha de S/R desenhada (ou o nivel encontrado
// cair dentro do stopLevel da corretora), a posicao ficava sem SL e/ou TP pra sempre,
// em silencio - risco de perda total numa posicao "protegida" so no nome. Agora alerta
// (Alert() + Print()) e reavisa a cada InpAlertaIntervaloMin minutos enquanto persistir.
input int    InpAlertaIntervaloMin = 5; // minutos entre reavisos de posicao ainda sem SL/TP

datetime g_ultimaChecagem = 0;
ulong    g_alertaTickets[];
datetime g_alertaUltimoAviso[];

datetime UltimoAvisoDoTicket(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_alertaTickets); i++)
      if(g_alertaTickets[i] == ticket) return g_alertaUltimoAviso[i];
   return 0;
}

void RegistrarAviso(ulong ticket, datetime quando)
{
   for(int i = 0; i < ArraySize(g_alertaTickets); i++)
      if(g_alertaTickets[i] == ticket) { g_alertaUltimoAviso[i] = quando; return; }

   int n = ArraySize(g_alertaTickets);
   ArrayResize(g_alertaTickets, n + 1);
   ArrayResize(g_alertaUltimoAviso, n + 1);
   g_alertaTickets[n] = ticket;
   g_alertaUltimoAviso[n] = quando;
}

int OnInit()
{
   EventSetTimer(2); // checa a cada 2s - nao precisa ser por tick
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

// Acha um nivel de S/R por criterio: tipo (suporte/resistencia), filtro de timeframe
// (vazio = qualquer) e rank (1 = mais proximo do preco de referencia, 2 = segundo
// mais proximo, etc). Aceita objetos tanto do script TRIVIUM_DESENHAR_SR
// ("TRIVIUM_SR_M1_SUP_0") quanto do indicador TRIVIUM_PAINEL_COMPLETO
// ("TRIVIUM_PAINEL_SRM1_SUP_0") - o filtro de TF usa "M1_SUP"/"M1_RES" como token
// pra nao confundir M1 com M15 (M15_SUP nao contem a substring "M1_SUP").
double AcharNivelSR(double precoRef, bool suporte, string tfFiltro, int rank)
{
   string tag = suporte ? "_SUP" : "_RES";
   string tokenTF = (tfFiltro != "") ? (tfFiltro + tag) : "";

   double precos[];
   int totalEncontrados = 0;
   int totalObjs = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < totalObjs; i++)
   {
      string nome = ObjectName(0, i, 0, -1);
      bool prefixoOk = (StringFind(nome, "TRIVIUM_SR_") == 0) || (StringFind(nome, "TRIVIUM_PAINEL_SR") == 0);
      if(!prefixoOk) continue;
      if(StringFind(nome, tag) < 0) continue;
      if(tokenTF != "" && StringFind(nome, tokenTF) < 0) continue;

      double preco = ObjectGetDouble(0, nome, OBJPROP_PRICE, 0);
      bool valido = suporte ? (preco < precoRef) : (preco > precoRef);
      if(!valido) continue;

      ArrayResize(precos, totalEncontrados + 1);
      precos[totalEncontrados] = preco;
      totalEncontrados++;
   }

   // ordena por distancia do preco de referencia, crescente (mais proximo primeiro)
   for(int i = 0; i < totalEncontrados - 1; i++)
      for(int j = 0; j < totalEncontrados - i - 1; j++)
      {
         double distJ  = suporte ? (precoRef - precos[j])   : (precos[j]   - precoRef);
         double distJ1 = suporte ? (precoRef - precos[j+1]) : (precos[j+1] - precoRef);
         if(distJ > distJ1)
         {
            double tmp = precos[j]; precos[j] = precos[j+1]; precos[j+1] = tmp;
         }
      }

   int idx = rank - 1;
   if(idx < 0 || idx >= totalEncontrados) return 0;
   return precos[idx];
}

void ProcessarPosicoes()
{
   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double margem = InpMargemExtraPts * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicFiltro) continue;

      double slAtual = PositionGetDouble(POSITION_SL);
      double tpAtual = PositionGetDouble(POSITION_TP);
      if(slAtual != 0 && tpAtual != 0) continue; // ja tem os dois, nao mexe

      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double precoAbertura = PositionGetDouble(POSITION_PRICE_OPEN);
      double precoAtual = (tipo == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double novoSL = slAtual;
      double novoTP = tpAtual;

      if(tipo == POSITION_TYPE_BUY)
      {
         if(slAtual == 0)
         {
            double suporte = AcharNivelSR(precoAbertura, true, InpSL_Timeframe, InpSL_Rank);
            if(suporte > 0)
            {
               double candidato = suporte - margem;
               if(precoAtual - candidato >= stopLevel) novoSL = candidato;
            }
         }
         if(tpAtual == 0)
         {
            double resistencia = AcharNivelSR(precoAbertura, false, InpTP_Timeframe, InpTP_Rank);
            if(resistencia > 0)
            {
               double candidato = resistencia + margem;
               if(candidato - precoAtual >= stopLevel) novoTP = candidato;
            }
         }
      }
      else if(tipo == POSITION_TYPE_SELL)
      {
         if(slAtual == 0)
         {
            double resistencia = AcharNivelSR(precoAbertura, false, InpSL_Timeframe, InpSL_Rank);
            if(resistencia > 0)
            {
               double candidato = resistencia + margem;
               if(candidato - precoAtual >= stopLevel) novoSL = candidato;
            }
         }
         if(tpAtual == 0)
         {
            double suporte = AcharNivelSR(precoAbertura, true, InpTP_Timeframe, InpTP_Rank);
            if(suporte > 0)
            {
               double candidato = suporte - margem;
               if(precoAtual - candidato >= stopLevel) novoTP = candidato;
            }
         }
      }

      if(novoSL != slAtual || novoTP != tpAtual)
      {
         if(trade.PositionModify(ticket, novoSL, novoTP))
            Print("TRIVIUM_AUTO_SLTP: posicao #", ticket, " SL=", DoubleToString(novoSL,_Digits), " TP=", DoubleToString(novoTP,_Digits), " definidos por S/R");
         else
            Print("TRIVIUM_AUTO_SLTP: falha ao modificar #", ticket, " - erro ", GetLastError());
      }

      // ainda falta SL e/ou TP (sem linha de S/R encontrada, ou nivel rejeitado pelo
      // stopLevel da corretora) - avisa, nao deixa a posicao desprotegida em silencio.
      if(novoSL == 0 || novoTP == 0)
      {
         datetime agora = TimeCurrent();
         if(agora - UltimoAvisoDoTicket(ticket) >= InpAlertaIntervaloMin * 60)
         {
            string faltando = (novoSL == 0 && novoTP == 0) ? "SL e TP" : (novoSL == 0 ? "SL" : "TP");
            string msg = StringFormat("TRIVIUM_AUTO_SLTP: posicao #%d (%s) SEM %s ha %d min - sem linha de S/R valida encontrada, protecao pendente",
                                       ticket, _Symbol, faltando, (int)((agora - PositionGetInteger(POSITION_TIME)) / 60));
            Alert(msg);
            Print(msg);
            RegistrarAviso(ticket, agora);
         }
      }
   }
}

void OnTimer()
{
   if(!InpAutoSLTP_Ativo) return;
   ProcessarPosicoes();
}

void OnTick()
{
   if(!InpAutoSLTP_Ativo) return;
   // checagem extra no tick tambem, pra pegar posicao recem-aberta sem esperar o timer
   ProcessarPosicoes();
}
//+------------------------------------------------------------------+
