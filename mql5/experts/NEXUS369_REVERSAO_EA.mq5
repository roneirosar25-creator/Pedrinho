//+------------------------------------------------------------------+
//| NEXUS369_REVERSAO_EA.mq5                                          |
//| TRIVIUM369 (c) 2026 - Pedrinho, 14/07/2026                        |
//|                                                                    |
//| NAO VALIDADO ainda (diferente do NEXUS369_TREND_VALIDADO, que      |
//| passou por teste estatistico Z>3.7). Esta e a primeira versao que  |
//| executa de verdade a logica de reversao que ja existia (so         |
//| visual) no indicador TRIVIUM_LEVELS / NEXUS369_SIGNAL.mqh.         |
//|                                                                    |
//| COMO FUNCIONA: le os buffers 7 (BuyArrow) e 8 (SellArrow) do       |
//| indicador TRIVIUM_LEVELS via iCustom - esse indicador ja roda      |
//| internamente o mesmo CSignalEngine (NEXUS369_SIGNAL.mqh) que       |
//| decide toque de banda + rejeicao + RSI extremo cruzado. Quando o   |
//| buffer correspondente NAO esta EMPTY_VALUE na barra fechada, este  |
//| EA abre a posicao de verdade (o indicador so desenhava a seta).    |
//|                                                                    |
//| SEM TAKE PROFIT FIXO (pedido do Ronei 14/07/2026): "nao vamos      |
//| limitar o ganho, so limitamos a perda" - TP=0 (aberto), so SL, com |
//| trailing stop ATR pra travar lucro progressivamente sem deixar     |
//| dinheiro na mesa.                                                  |
//|                                                                    |
//| PRIORIDADE vs NEXUS369_TREND_VALIDADO: AINDA NAO DEFINIDA. Ronei   |
//| pediu pra decidir depois de ver os dois rodando (14/07/2026). Por  |
//| enquanto esta 100% independente - nao mexe em posicao do EA de     |
//| tendencia, nem o contrario.                                        |
//|                                                                    |
//| KILL SWITCH PROPRIO (GV_EXECUCAO_AUTORIZADA_REVERSAO), separado do |
//| kill switch do EA de tendencia - autorizacao anterior do Ronei     |
//| ("pode rodar" 14/07/2026) foi dada pro EA JA VALIDADO, nao cobre   |
//| este. Precisa de "pode rodar" novo, especifico pra reversao.       |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#include <Trade\Trade.mqh>
#include <TRIVIUM\STOP_DIARIO.mqh>

input group "=== Fonte do sinal (indicador TRIVIUM_LEVELS) ==="
input int    InpMetodoMA      = 0;    // ver TRIVIUM_LEVELS - 0=SMMA
input int    InpMAPeriod      = 21;
input int    InpAlmaMode      = 0;
input int    InpPreset        = 0;    // 0=AUTO (detecta pelo simbolo)
input int    InpATRPeriodInd  = 55;
input int    InpRSIPeriod     = 14;

input group "=== Stop (validado - SEM take profit de proposito) ==="
input int    InpATRPeriod     = 14;   // ATR proprio deste EA p/ calcular o SL
input double InpStopATRMult   = 1.5;  // Stop = 1.5x ATR (mais apertado - reversao erra rapido se errar)

input group "=== Gestao de Risco ==="
input double InpRiskPercent   = 1.0;
input double InpMaxDDPercent  = 3.0;
input int    InpMaxTradesDia  = 5;

input group "=== Trailing Stop (substitui o TP - trava lucro sem limitar alta) ==="
input bool   InpTrailingAtivo       = true;
input double InpTrailingActivaATR   = 0.8;  // ativa mais cedo que o EA de tendencia (reversao quer capturar rapido)
input double InpTrailingTravaATR    = 0.4;

input group "=== Magic Number ==="
input string InpSetupTipo     = "Reversao_Bandas_RSI";

input group "=== Filtro de Spread ==="
input bool   InpFiltroSpreadAtivo = true;
input double InpMaxSpreadATRPct   = 15.0;

#define GV_MAGIC_SEQUENCIAL "TRIVIUM369_MAGIC_SEQUENCIAL_COUNTER"
#define MAGIC_SEQUENCIAL_INICIO 200000
// 14/07/2026 - nome do CSV agora inclui o login da conta (pedido do
// Ronei): cada conta grava o proprio arquivo, sem depender de faixa de
// Magic Number pra identificar de onde veio cada operacao.
string g_signalsLogFile = "";
#define SIGNALS_LOG_HEADER "magic;datetime_abertura;ativo;timeframe;direcao;preco_entrada;atr_valor;sl_calculado;tp_calculado;setup_tipo;motivo_entrada;lote;datetime_fechamento;preco_fechamento;motivo_saida;resultado_pips;resultado_reais;barras_duracao;status"

// Kill switch PROPRIO deste EA - separado do TRIVIUM369_EXECUCAO_AUTORIZADA
// (esse ultimo e do NEXUS369_TREND_VALIDADO, ja validado e ja autorizado).
#define GV_EXECUCAO_AUTORIZADA_REVERSAO "TRIVIUM369_EXECUCAO_AUTORIZADA_REVERSAO"

bool ExecucaoAutorizada()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   return GlobalVariableCheck(GV_EXECUCAO_AUTORIZADA_REVERSAO) && GlobalVariableGet(GV_EXECUCAO_AUTORIZADA_REVERSAO) >= 1.0;
}

CTrade trade;
int    h_levels = INVALID_HANDLE;
int    h_atr    = INVALID_HANDLE;
double saldoInicioDia = 0;
datetime diaAtual = 0;
int    tradesHoje = 0;
long   magicAtual = 0;
datetime tempoAberturaPosicaoAtual = 0;
double precoAberturaPosicaoAtual = 0;
ENUM_POSITION_TYPE ladoPosicaoAtual = POSITION_TYPE_BUY;
datetime lastSignalBarTime = 0;
string logFileName = "";

// 15/07/2026 - CORRIGIDO (mesmo bug de magic duplicado do TREND_VALIDADO,
// que compartilha esse mesmo contador): Get+soma+Set nao atomicos.
// Corrigido com GlobalVariableSetOnCondition (compare-and-swap).
// 17/07/2026 - CORRIGIDO bug real achado pelo Ronei ao vivo: contador de
// magic perdia a GlobalVariable em fechamento forcado do terminal e
// reiniciava do zero, recriando numeros ja usados. Fix: consulta o
// historico real da corretora antes de gerar magic novo.
void GarantirContadorMagicNuncaRetrocede()
{
   long maiorMagicHistorico = MAGIC_SEQUENCIAL_INICIO;
   if(HistorySelect(0, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         long magic = (long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         if(magic > maiorMagicHistorico) maiorMagicHistorico = magic;
      }
   }
   double atualGV = GlobalVariableCheck(GV_MAGIC_SEQUENCIAL) ? GlobalVariableGet(GV_MAGIC_SEQUENCIAL) : (double)MAGIC_SEQUENCIAL_INICIO;
   if((double)maiorMagicHistorico > atualGV)
   {
      GlobalVariableSet(GV_MAGIC_SEQUENCIAL, (double)maiorMagicHistorico);
      Print("AVISO: contador de magic estava atras do historico real (GV=", atualGV, ", historico=", maiorMagicHistorico, ") - corrigido.");
   }
}

long GerarMagicSequencial()
{
   double atual, novo;
   int tentativas = 0;
   do
   {
      atual = GlobalVariableCheck(GV_MAGIC_SEQUENCIAL)
              ? GlobalVariableGet(GV_MAGIC_SEQUENCIAL)
              : (double)MAGIC_SEQUENCIAL_INICIO;
      novo = atual + 1;
      tentativas++;
   }
   while(!GlobalVariableSetOnCondition(GV_MAGIC_SEQUENCIAL, novo, atual) && tentativas < 50);
   if(tentativas >= 50) Print("AVISO: GerarMagicSequencial nao conseguiu CAS apos 50 tentativas");
   return (long)novo;
}

void GarantirCabecalhoSignalsLog()
{
   if(!FileIsExist(g_signalsLogFile, FILE_COMMON))
   {
      int h = FileOpen(g_signalsLogFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(h != INVALID_HANDLE) { FileWriteString(h, SIGNALS_LOG_HEADER + "\r\n"); FileClose(h); }
   }
}

void RegistraSinalAbertura(long magic, string ativo, string tf, string direcao,
                            double precoEntrada, double atrValor, double sl, double tp,
                            string setupTipo, string motivo, double lote)
{
   GarantirCabecalhoSignalsLog();
   int h = FileOpen(g_signalsLogFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   FileSeek(h, 0, SEEK_END);
   string linha = StringFormat("%d;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%.2f;;;;;;;",
      magic, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), ativo, tf, direcao,
      DoubleToString(precoEntrada, _Digits), DoubleToString(atrValor, 5),
      DoubleToString(sl, _Digits), (tp > 0 ? DoubleToString(tp, _Digits) : "ABERTO_SEM_TP"),
      setupTipo, motivo, lote);
   FileWriteString(h, linha + "\r\n");
   FileClose(h);
}

void RegistraSinalFechamento(long magic, double precoFechamento, string motivoSaida,
                              double resultadoPips, double resultadoReais,
                              int barrasDuracao, string status)
{
   if(!FileIsExist(g_signalsLogFile, FILE_COMMON)) return;
   string linhas[]; int total = 0;
   int h = FileOpen(g_signalsLogFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h)) { string linha = FileReadString(h); ArrayResize(linhas, total + 1); linhas[total] = linha; total++; }
   FileClose(h);

   string magicStr = IntegerToString(magic);
   for(int i = 0; i < total; i++)
   {
      string campos[];
      int n = StringSplit(linhas[i], ';', campos);
      if(n >= 12 && campos[0] == magicStr)
      {
         linhas[i] = StringFormat("%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%s;%.1f;%.2f;%d;%s",
            campos[0], campos[1], campos[2], campos[3], campos[4], campos[5], campos[6],
            campos[7], campos[8], campos[9], campos[10], campos[11],
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
            DoubleToString(precoFechamento, _Digits), motivoSaida,
            resultadoPips, resultadoReais, barrasDuracao, status);
         break;
      }
   }
   h = FileOpen(g_signalsLogFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   for(int i = 0; i < total; i++) FileWriteString(h, linhas[i] + "\r\n");
   FileClose(h);
}

string NomePeriodo(ENUM_TIMEFRAMES p)
{
   switch(p)
   {
      case PERIOD_M1: return "M1"; case PERIOD_M5: return "M5"; case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30"; case PERIOD_H1: return "H1"; case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1"; default: return EnumToString(p);
   }
}

void LogRelatorio(string linha)
{
   Print(linha);
   int h = FileOpen(logFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h != INVALID_HANDLE) { FileSeek(h, 0, SEEK_END); FileWrite(h, linha); FileClose(h); }
}

void DesenhaSetaEntrada(long magic, datetime tempo, double preco, ENUM_POSITION_TYPE lado)
{
   string nome = StringFormat("TRIVIUM_REV_ENTRADA_%d", magic);
   ObjectCreate(0, nome, (lado == POSITION_TYPE_BUY) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrDodgerBlue : clrMagenta);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
}

void DesenhaSetaSaida(long magic, datetime tempo, double preco, bool ganho)
{
   string nome = StringFormat("TRIVIUM_REV_SAIDA_%d", magic);
   ObjectCreate(0, nome, OBJ_ARROW_CHECK, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
}

// Painel "parecer" fixo do EA de reversao - posicionado ABAIXO do painel
// do NEXUS369_TREND_VALIDADO (y=100) pra nao sobrepor quando os dois
// estao no mesmo grafico (pedido do Ronei 14/07/2026).
#define PAINEL_REV_NOME "TRIVIUM_PAINEL_REVERSAO"
void AtualizaParecerRev(string texto)
{
   if(ObjectFind(0, PAINEL_REV_NOME) < 0)
   {
      ObjectCreate(0, PAINEL_REV_NOME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_YDISTANCE, 110);
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, PAINEL_REV_NOME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_COLOR, clrMagenta);
      ObjectSetInteger(0, PAINEL_REV_NOME, OBJPROP_BACK, false);
   }
   ObjectSetString(0, PAINEL_REV_NOME, OBJPROP_TEXT, "[REVERSAO]\n" + texto);
}

//+------------------------------------------------------------------+
int OnInit()
{
   string sym = _Symbol;

   // Abre o indicador TRIVIUM_LEVELS como fonte do sinal (mesmos inputs
   // que o template padrao usa - AUTO detecta preset por simbolo)
   // 15/07/2026 - CORRIGIDO (bug 4802 que travava a reversao em TODAS as
   // contas desde 14/07): iCustom ja assume a pasta Indicators por padrao -
   // o prefixo "Indicators\\" fazia procurar em Indicators\Indicators\...,
   // que nao existe. Confirmado com TRIVIUM_TESTE_ICUSTOM.mq5 (script de
   // diagnostico): "TRIVIUM_LEVELS" sem prefixo = sucesso.
   h_levels = iCustom(_Symbol, _Period, "TRIVIUM_LEVELS",
                       InpMetodoMA, InpMAPeriod, InpAlmaMode, InpPreset, InpATRPeriodInd,
                       1.0, 2.0, 3.0, 1.2, 2.4, 3.8,  // K1/K2/K3 Forex e Crypto (defaults do indicador)
                       10, false,                       // ERPeriod, UsarBBW
                       InpRSIPeriod, 53, 47, 5, 15, false); // RSI period/overB/overS/cooldown/armedWindow/requireExtreme

   h_atr = iATR(_Symbol, _Period, InpATRPeriod);

   if(h_levels == INVALID_HANDLE || h_atr == INVALID_HANDLE)
   {
      Print("Erro ao criar handles TRIVIUM_LEVELS/ATR: ", GetLastError());
      return INIT_FAILED;
   }

   trade.SetDeviationInPoints(30);
   magicAtual = 0;
   GarantirContadorMagicNuncaRetrocede();
   saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   diaAtual = iTime(_Symbol, PERIOD_D1, 0);
   tradesHoje = 0;
   long contaLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   logFileName = "NEXUS369_REVERSAO_RELATORIO_" + sym + "_" + IntegerToString(contaLogin) + ".txt";
   g_signalsLogFile = "TRIVIUM369_SIGNALS_LOG_" + IntegerToString(contaLogin) + ".csv";

   LogRelatorio(StringFormat("=== INIT REVERSAO %s | %s %s | fonte=TRIVIUM_LEVELS (buffers Buy/Sell) | SL=%.1fxATR SEM_TP | Risco=%.1f%% | EXECUCAO=%s (kill switch PROPRIO, separado do EA de tendencia) ===",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), sym, NomePeriodo(_Period),
      InpStopATRMult, InpRiskPercent,
      ExecucaoAutorizada() ? "AUTORIZADA" : "AGUARDANDO 'pode rodar' (reversao) do Ronei"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_levels != INVALID_HANDLE) IndicatorRelease(h_levels);
   if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);
   ObjectDelete(0, PAINEL_REV_NOME);
}

bool NovoDia()
{
   datetime hoje = iTime(_Symbol, PERIOD_D1, 0);
   if(hoje != diaAtual) { diaAtual = hoje; tradesHoje = 0; saldoInicioDia = AccountInfoDouble(ACCOUNT_EQUITY); return true; }
   return false;
}

bool DrawdownDiarioEstourado()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = (saldoInicioDia - equity) / saldoInicioDia * 100.0;
   return (ddPct >= InpMaxDDPercent);
}

// 16/07/2026 - CORRIGIDO (auditoria pos-bug do TREND: mesmo padrao de
// memoria-vs-realidade). Checa a corretora (simbolo + comentario "REV "),
// nao a memoria da instancia, que zera ao reinicializar.
bool TemPosicaoAberta()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "REV ") == 0)
      {
         magicAtual = PositionGetInteger(POSITION_MAGIC);
         return true;
      }
   }
   magicAtual = 0;
   return false;
}

// 16/07/2026 - Regra de prioridade decidida com o Ronei: a reversao NAO
// abre posicao contra uma posicao de tendencia ja aberta no mesmo par
// (evita pagar spread duas vezes numa posicao que se anula sozinha).
// A tendencia continua 100% livre - essa checagem existe SO do lado da
// reversao, nao mexe em nada do NEXUS369_TREND_VALIDADO/REAL.
bool TendenciaTemPosicaoAberta()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "TND ") == 0) return true;
   }
   return false;
}

// Trailing stop - unica forma de "sair", ja que nao ha TP fixo
void GerenciaTrailingStop()
{
   if(!InpTrailingAtivo || magicAtual == 0) return;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magicAtual) continue;

      double atr_buf[1];
      if(CopyBuffer(h_atr, 0, 0, 1, atr_buf) < 1) continue;
      double atr_now = atr_buf[0];
      if(atr_now <= 0) continue;

      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double slAtual = PositionGetDouble(POSITION_SL);
      double tpAtual = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(tipo == POSITION_TYPE_BUY)
      {
         double atual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double lucroDist = atual - entry;
         if(lucroDist >= InpTrailingActivaATR * atr_now)
         {
            double novoSL = atual - InpTrailingTravaATR * atr_now;
            if(novoSL > slAtual)
               if(trade.PositionModify(tk, novoSL, tpAtual))
                  LogRelatorio(StringFormat("TRAILING REVERSAO #%d | %s | SL movido para %s", (int)tk, _Symbol, DoubleToString(novoSL, _Digits)));
         }
      }
      else
      {
         double atual = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double lucroDist = entry - atual;
         if(lucroDist >= InpTrailingActivaATR * atr_now)
         {
            double novoSL = atual + InpTrailingTravaATR * atr_now;
            if(slAtual == 0 || novoSL < slAtual)
               if(trade.PositionModify(tk, novoSL, tpAtual))
                  LogRelatorio(StringFormat("TRAILING REVERSAO #%d | %s | SL movido para %s", (int)tk, _Symbol, DoubleToString(novoSL, _Digits)));
         }
      }
   }
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
   TemPosicaoAberta(); // 16/07/2026 - atualiza magicAtual antes do trailing depender dele
   GerenciaTrailingStop();
   if(!ExecucaoAutorizada()) return;
   if(StopDiario_Bloqueado()) return;
   if(MargemBloqueada()) return; // guarda de margem da CONTA INTEIRA (20/07/2026)
   if(DrawdownDiarioEstourado()) return;
   if(tradesHoje >= InpMaxTradesDia) return;
   if(TemPosicaoAberta()) return;
   if(TendenciaTemPosicaoAberta())
   {
      datetime curBarChk = iTime(_Symbol, _Period, 0);
      if(curBarChk != lastSignalBarTime) // loga so uma vez por barra, nao a cada tick
      {
         lastSignalBarTime = curBarChk;
         LogRelatorio(StringFormat("REVERSAO EM ESPERA | %s | tendencia ja tem posicao aberta neste par - prioridade da tendencia (16/07/2026)", _Symbol));
      }
      return;
   }

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == lastSignalBarTime) return;
   lastSignalBarTime = curBar;

   // Le os buffers 7 (Buy) e 8 (Sell) do TRIVIUM_LEVELS na barra ja fechada (indice 1)
   double buyBuf[1], sellBuf[1], atrIndBuf[1];
   if(CopyBuffer(h_levels, 7, 1, 1, buyBuf) < 1) return;
   if(CopyBuffer(h_levels, 8, 1, 1, sellBuf) < 1) return;
   if(CopyBuffer(h_atr, 0, 1, 1, atrIndBuf) < 1) return;
   double atr_val = atrIndBuf[0];
   if(atr_val <= 0) return;

   string side = "";
   if(buyBuf[0] != EMPTY_VALUE) side = "BUY";
   else if(sellBuf[0] != EMPTY_VALUE) side = "SELL";
   else return; // sem sinal nesta barra

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(InpFiltroSpreadAtivo)
   {
      double spread_atual = ask - bid;
      double stop_dist_preco = InpStopATRMult * atr_val;
      double spread_pct_do_stop = (stop_dist_preco > 0) ? (spread_atual / stop_dist_preco * 100.0) : 999.0;
      if(spread_pct_do_stop > InpMaxSpreadATRPct)
      {
         LogRelatorio(StringFormat("SINAL REVERSAO REJEITADO POR SPREAD | %s | spread=%.5f (%.1f%% do stop)", _Symbol, spread_atual, spread_pct_do_stop));
         return;
      }
   }

   string tf = NomePeriodo(_Period);
   string comentario = StringFormat("REV %s %s", tf, side);
   if(StringLen(comentario) > 31) comentario = StringSubstr(comentario, 0, 31);
   string motivoDetalhado = StringFormat("Sinal de reversao TRIVIUM_LEVELS (toque banda + rejeicao + RSI extremo cruzado), ATR=%.5f", atr_val);

   if(side == "BUY")
   {
      double entry = ask;
      double sl = entry - InpStopATRMult * atr_val;
      double slDistPoints = (entry - sl) / point;
      double lots = CalcularLote(InpRiskPercent, slDistPoints);
      if(lots > 0)
      {
         long novoMagic = GerarMagicSequencial();
         trade.SetExpertMagicNumber(novoMagic);
         if(trade.Buy(lots, _Symbol, entry, sl, 0.0, comentario)) // TP=0 de proposito
         {
            magicAtual = novoMagic; tempoAberturaPosicaoAtual = curBar; precoAberturaPosicaoAtual = entry;
            ladoPosicaoAtual = POSITION_TYPE_BUY; tradesHoje++;
            RegistraSinalAbertura(novoMagic, _Symbol, tf, side, entry, atr_val, sl, 0.0, InpSetupTipo, motivoDetalhado, lots);
            LogRelatorio(StringFormat("ENTRADA REVERSAO #%d Magic=%d | %s | %s | entrada=%s | stop=%s | SEM TP (trailing controla saida) | lote=%.2f",
               (int)trade.ResultOrder(), novoMagic, _Symbol, side, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), lots));
            DesenhaSetaEntrada(novoMagic, curBar, entry, POSITION_TYPE_BUY);
            AtualizaParecerRev(StringFormat(
               "%s | COMPRA #%d\nEntrada: %s | Stop: %s | SEM TP (trailing)\nLote: %.2f | Motivo: %s",
               _Symbol, novoMagic, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), lots, motivoDetalhado));
         }
      }
   }
   else
   {
      double entry = bid;
      double sl = entry + InpStopATRMult * atr_val;
      double slDistPoints = (sl - entry) / point;
      double lots = CalcularLote(InpRiskPercent, slDistPoints);
      if(lots > 0)
      {
         long novoMagic = GerarMagicSequencial();
         trade.SetExpertMagicNumber(novoMagic);
         if(trade.Sell(lots, _Symbol, entry, sl, 0.0, comentario)) // TP=0 de proposito
         {
            magicAtual = novoMagic; tempoAberturaPosicaoAtual = curBar; precoAberturaPosicaoAtual = entry;
            ladoPosicaoAtual = POSITION_TYPE_SELL; tradesHoje++;
            RegistraSinalAbertura(novoMagic, _Symbol, tf, side, entry, atr_val, sl, 0.0, InpSetupTipo, motivoDetalhado, lots);
            LogRelatorio(StringFormat("ENTRADA REVERSAO #%d Magic=%d | %s | %s | entrada=%s | stop=%s | SEM TP (trailing controla saida) | lote=%.2f",
               (int)trade.ResultOrder(), novoMagic, _Symbol, side, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), lots));
            DesenhaSetaEntrada(novoMagic, curBar, entry, POSITION_TYPE_SELL);
            AtualizaParecerRev(StringFormat(
               "%s | VENDA #%d\nEntrada: %s | Stop: %s | SEM TP (trailing)\nLote: %.2f | Motivo: %s",
               _Symbol, novoMagic, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), lots, motivoDetalhado));
         }
      }
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(magicAtual == 0 || HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != magicAtual) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double precoSaida = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   long ticket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   string status = profit >= 0 ? "GANHO" : "PERDA";

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int barrasDuracao = (tempoAberturaPosicaoAtual > 0) ? (int)iBarShift(_Symbol, _Period, tempoAberturaPosicaoAtual) : -1;
   double resultadoPips = 0;
   if(point > 0 && precoAberturaPosicaoAtual > 0)
      resultadoPips = (ladoPosicaoAtual == POSITION_TYPE_BUY)
         ? (precoSaida - precoAberturaPosicaoAtual) / point
         : (precoAberturaPosicaoAtual - precoSaida) / point;

   RegistraSinalFechamento(magicAtual, precoSaida, "SL_ou_Trailing", resultadoPips, profit, barrasDuracao, status);
   LogRelatorio(StringFormat("FECHAMENTO REVERSAO #%d Magic=%d | %s | saida=%s | P&L=%.2f %s",
      (int)ticket, (int)magicAtual, _Symbol, DoubleToString(precoSaida, _Digits), profit, AccountInfoString(ACCOUNT_CURRENCY)));
   DesenhaSetaSaida(magicAtual, TimeCurrent(), precoSaida, profit >= 0);
   AtualizaParecerRev(StringFormat(
      "%s | FECHADA #%d\nSaida: %s | Resultado: %s\nP&L: %.2f %s | Pips: %.1f",
      _Symbol, (int)magicAtual, DoubleToString(precoSaida, _Digits), status,
      profit, AccountInfoString(ACCOUNT_CURRENCY), resultadoPips));
   magicAtual = 0; tempoAberturaPosicaoAtual = 0; precoAberturaPosicaoAtual = 0;
}
//+------------------------------------------------------------------+
