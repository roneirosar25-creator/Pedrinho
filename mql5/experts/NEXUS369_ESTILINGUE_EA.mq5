//+------------------------------------------------------------------+
//| NEXUS369_ESTILINGUE_EA.mq5                                        |
//| TRIVIUM369 (c) 2026 - Pedrinho, 19/07/2026                        |
//|                                                                    |
//| Nasce da revisao dos cursos "Setups Matadores" (L&S) e "Analise    |
//| Tecnica" (LibertaPlay) pedida pelo Ronei (18-19/07). Testei 3      |
//| setups do material com a mesma regua de sempre (spread real,       |
//| treino/teste 70/30, PF>1 nos dois lados): Barra Ignorada (PF 0.14- |
//| 0.34, REPROVADA) e FFFD/Fechou-Fora-Fechou-Dentro (PF 0.67-0.86,   |
//| REPROVADA) nao seguraram. So o "Efeito Estilingue" validou de      |
//| verdade - fica so ele neste EA.                                    |
//|                                                                    |
//| REGRA (validada em backtest H1, 5 pares, spread real, treino/teste |
//| 70/30):                                                            |
//|  - Bandas de Bollinger(21,2) comprimidas: largura da banda no      |
//|    percentil <30% das ultimas 100 velas (regime de squeeze)        |
//|  - Vela tenta romper a banda (high>banda_sup OU low<banda_inf) MAS |
//|    fecha de volta PRA DENTRO das bandas - rompimento falso, "trap" |
//|  - Direcao = CONTRARIA ao rompimento que falhou (tentou romper pra |
//|    cima e falhou -> vende; tentou romper pra baixo e falhou ->     |
//|    compra) - e o movimento forte que costuma vir em seguida        |
//|                                                                    |
//| SAIDA EM 2 FASES (mesmo framework validado no NEXUS369_PRECURSOR): |
//|  FASE 1 (3 primeiras velas): stop LARGO fixo em 3.5xATR.           |
//|  FASE 2 (4a vela em diante): trailing em 0.5xATR do pico a favor.  |
//|                                                                    |
//| RESULTADO DO BACKTEST (30k+ trades, 19/07/2026): EURUSD-T PF       |
//| 2.05/1.84, GBPUSD-T 2.02/1.89, USDCAD-T 1.79/1.60, AUDUSD-T        |
//| 1.83/1.85, NZDUSD-T 1.51/1.22 (treino/teste). NAO E TRACK RECORD   |
//| REAL - e backtest historico. Rodar DEMO primeiro.                  |
//|                                                                    |
//| KILL SWITCH PROPRIO (GV_EXECUCAO_AUTORIZADA_ESTILINGUE), separado  |
//| de todos os outros EAs - precisa de "pode rodar" novo, especifico. |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#include <Trade\Trade.mqh>
#include <TRIVIUM\STOP_DIARIO.mqh>

// Timeframe OPERACIONAL fixo - independente do timeframe do grafico onde
// o EA foi anexado (o grafico e so uma "vaga" de anexacao, varios EAs
// desta familia compartilham simbolo+H1 e o MT5 nao deixa 2 graficos
// iguais abertos - ver NEXUS369_PRECURSOR_EA.mq5 pro mesmo raciocinio).
#define PERIOD_OPERACIONAL PERIOD_H1

input group "=== Auto-calibragem por ativo ==="
// Os 5 pares abaixo foram validados no backtest (19/07/2026). Fora
// deles, o EA fica so visual (g_ParOperavel=false) ate ter novo teste.
input bool   InpAutoCalibrarPorAtivo = true;

input group "=== Bollinger / Squeeze (usado so se auto-calibragem = false) ==="
input int    InpBBPeriod         = 21;
input double InpBBDesvio         = 2.0;
input int    InpSqueezePercJanela = 100;  // janela pra calcular o percentil da largura da banda
input double InpSqueezePercMax   = 0.30;  // so considera squeeze se largura atual esta nos 30% mais estreitos

input group "=== Saida em 2 fases (validado - NAO mudar sem novo teste) ==="
input int    InpATRPeriod        = 14;
input int    InpBarrasGraca      = 3;
input double InpStopGracaATRMult = 3.5;
input double InpTrailingATRMult  = 0.5;
input int    InpMaxBarrasHold    = 20;

input group "=== Gestao de Risco ==="
input double InpRiskPercent      = 1.0;  // manual - ignorado se auto-calibragem = true
input double InpMaxDDPercent     = 3.0;
input int    InpMaxTradesDia     = 5;
input int    InpBarrasMinEntreSinais = 5;

double g_RiskPercent;
bool   g_ParOperavel = true;

//+------------------------------------------------------------------+
// Tabela de calibragem por ativo. Os 5 pares originais passaram no
// backtest (19/07/2026). Risco 1.0% - mesmo raciocinio dos outros EAs
// desta familia, ajustar se Ronei pedir.
//
// EXPANSAO 19/07/2026: +9 cruzamentos forex (EURAUD/EURCAD/EURCHF/
// EURGBP/EURNZD/GBPAUD/GBPCAD/GBPNZD/USDCHF, H1). Pares com JPY
// REPROVARAM (mesma reprovacao sistematica vista no Precursor - nao
// operar). Criptomoedas testadas em H1/H4/D1: resultado fraco demais
// pra confiar (so XRP e BCH aprovaram, e so em D1 com amostra pequena
// ~200 trades) - NAO entraram na tabela, ficam so visuais ate ter
// mais historico ou regra mais especifica pra cripto.
//+------------------------------------------------------------------+
void CarregarCalibragemPorAtivo()
{
   if(!InpAutoCalibrarPorAtivo) { g_RiskPercent = InpRiskPercent; return; }

   string sym = _Symbol; StringToUpper(sym);
   g_ParOperavel = true;

   if(StringFind(sym, "EURUSD") >= 0)      { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPUSD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "USDCAD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "AUDUSD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "NZDUSD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURAUD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURCAD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURCHF") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURGBP") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURNZD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPAUD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPCAD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPNZD") >= 0) { g_RiskPercent = 1.0; }
   else if(StringFind(sym, "USDCHF") >= 0) { g_RiskPercent = 1.0; }
   else
   {
      // Fora da tabela validada - EA fica so visual (nao abre posicao)
      // ate ter backtest proprio, mesmo com auto-calibragem ligada.
      g_RiskPercent = 0.0; g_ParOperavel = false;
   }
}

input group "=== Magic Number ==="
input string InpSetupTipo     = "Estilingue_Squeeze_TrapBollinger";

input group "=== Filtro de Spread ==="
input bool   InpFiltroSpreadAtivo = true;
input double InpMaxSpreadATRPct   = 15.0;

#define GV_MAGIC_SEQUENCIAL "TRIVIUM369_MAGIC_SEQUENCIAL_COUNTER"
#define MAGIC_SEQUENCIAL_INICIO 200000
string g_signalsLogFile = "";
#define SIGNALS_LOG_HEADER "magic;datetime_abertura;ativo;timeframe;direcao;preco_entrada;atr_valor;sl_calculado;tp_calculado;setup_tipo;motivo_entrada;lote;datetime_fechamento;preco_fechamento;motivo_saida;resultado_pips;resultado_reais;barras_duracao;status"

// Kill switch PROPRIO deste EA - separado de todos os outros.
#define GV_EXECUCAO_AUTORIZADA_ESTILINGUE "TRIVIUM369_EXECUCAO_AUTORIZADA_ESTILINGUE"
#define GV_LOSSES_PREFIX "TRIVIUM369_LOSSES_SEGUIDAS_"
string g_gvLosses = "";

bool ExecucaoAutorizada()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   return GlobalVariableCheck(GV_EXECUCAO_AUTORIZADA_ESTILINGUE) && GlobalVariableGet(GV_EXECUCAO_AUTORIZADA_ESTILINGUE) >= 1.0;
}

CTrade trade;
int    h_atr = INVALID_HANDLE;
int    h_bb  = INVALID_HANDLE;
double saldoInicioDia = 0;
datetime diaAtual = 0;
int    tradesHoje = 0;
long   magicAtual = 0;
datetime tempoAberturaPosicaoAtual = 0;
double precoAberturaPosicaoAtual = 0;
ENUM_POSITION_TYPE ladoPosicaoAtual = POSITION_TYPE_BUY;
datetime lastSignalBarTime = 0;
int    barsSinceLastSignal = 999;
string logFileName = "";

//+------------------------------------------------------------------+
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
      Print("AVISO: contador de magic estava atras do historico real - corrigido.");
   }
}

long GerarMagicSequencial()
{
   double atual, novo;
   int tentativas = 0;
   do
   {
      atual = GlobalVariableCheck(GV_MAGIC_SEQUENCIAL) ? GlobalVariableGet(GV_MAGIC_SEQUENCIAL) : (double)MAGIC_SEQUENCIAL_INICIO;
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
      DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), setupTipo, motivo, lote);
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
   while(!FileIsEnding(h)) { ArrayResize(linhas, total + 1); linhas[total] = FileReadString(h); total++; }
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
   string nome = StringFormat("TRIVIUM_ESTL_ENTRADA_%d", magic);
   ObjectCreate(0, nome, (lado == POSITION_TYPE_BUY) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_ESTL_ENTRADA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" ESTILINGUE %s #%d", (lado == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA", magic));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, (lado == POSITION_TYPE_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM);
}

void DesenhaSetaSaida(long magic, datetime tempo, double preco, bool ganho)
{
   string nome = StringFormat("TRIVIUM_ESTL_SAIDA_%d", magic);
   ObjectCreate(0, nome, OBJ_ARROW_CHECK, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_ESTL_SAIDA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" SAIDA #%d (%s)", magic, ganho ? "GANHO" : "PERDA"));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, ANCHOR_TOP);
}

#define PAINEL_ESTL_NOME "TRIVIUM_PAINEL_ESTILINGUE"
void AtualizaParecer(string texto)
{
   if(ObjectFind(0, PAINEL_ESTL_NOME) < 0)
   {
      ObjectCreate(0, PAINEL_ESTL_NOME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_YDISTANCE, 130); // abaixo dos outros paineis desta familia
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, PAINEL_ESTL_NOME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_COLOR, clrCyan);
      ObjectSetInteger(0, PAINEL_ESTL_NOME, OBJPROP_BACK, false);
   }
   ObjectSetString(0, PAINEL_ESTL_NOME, OBJPROP_TEXT, "[ESTILINGUE]\n" + texto);
}

//+------------------------------------------------------------------+
int OnInit()
{
   string sym = _Symbol; StringToUpper(sym);
   CarregarCalibragemPorAtivo();
   GarantirContadorMagicNuncaRetrocede();
   if(!g_ParOperavel)
      Print("AVISO: ", sym, " fora da tabela validada do NEXUS369_ESTILINGUE_EA (14 pares forex H1: EURUSD/GBPUSD/USDCAD/AUDUSD/NZDUSD/EURAUD/EURCAD/EURCHF/EURGBP/EURNZD/GBPAUD/GBPCAD/GBPNZD/USDCHF-T; pares com JPY e criptomoedas nao operam, edge fraco demais) - grafico so visual, EA nao abre posicao aqui.");

   h_atr = iATR(_Symbol, PERIOD_OPERACIONAL, InpATRPeriod);
   if(h_atr == INVALID_HANDLE) { Print("Erro ao criar handle ATR: ", GetLastError()); return INIT_FAILED; }
   h_bb = iBands(_Symbol, PERIOD_OPERACIONAL, InpBBPeriod, 0, InpBBDesvio, PRICE_CLOSE);
   if(h_bb == INVALID_HANDLE) { Print("Erro ao criar handle Bollinger: ", GetLastError()); return INIT_FAILED; }

   trade.SetDeviationInPoints(30);
   magicAtual = 0;
   saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   diaAtual = iTime(_Symbol, PERIOD_D1, 0);
   tradesHoje = 0;

   long contaLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   logFileName = "NEXUS369_ESTILINGUE_RELATORIO_" + sym + "_" + IntegerToString(contaLogin) + ".txt";
   g_signalsLogFile = "TRIVIUM369_SIGNALS_LOG_" + IntegerToString(contaLogin) + ".csv";
   g_gvLosses = GV_LOSSES_PREFIX + IntegerToString(contaLogin) + "_" + sym + "_ESTL";

   LogRelatorio(StringFormat("=== INIT ESTILINGUE %s | %s %s | Squeeze<=%.0f%% pct | Fase1=%dvelas@%.1fxATR Fase2=trailing%.1fxATR | Risco=%.1f%% | EXECUCAO=%s ===",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), sym, NomePeriodo(PERIOD_OPERACIONAL),
      InpSqueezePercMax*100, InpBarrasGraca, InpStopGracaATRMult, InpTrailingATRMult, g_RiskPercent,
      ExecucaoAutorizada() ? "AUTORIZADA" : "AGUARDANDO 'pode rodar' do Ronei"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);
   if(h_bb != INVALID_HANDLE) IndicatorRelease(h_bb);
   ObjectDelete(0, PAINEL_ESTL_NOME);
}

//+------------------------------------------------------------------+
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

// Consulta a REALIDADE da corretora (nao memoria).
bool TemPosicaoAberta()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      string comentario = PositionGetString(POSITION_COMMENT);
      if(StringFind(comentario, "ESTL ") == 0)
      {
         magicAtual = PositionGetInteger(POSITION_MAGIC);
         tempoAberturaPosicaoAtual = (datetime)PositionGetInteger(POSITION_TIME);
         precoAberturaPosicaoAtual = PositionGetDouble(POSITION_PRICE_OPEN);
         ladoPosicaoAtual = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         return true;
      }
   }
   magicAtual = 0;
   return false;
}

int BarrasDesdeAbertura()
{
   if(tempoAberturaPosicaoAtual == 0) return 0;
   int shift = iBarShift(_Symbol, PERIOD_OPERACIONAL, tempoAberturaPosicaoAtual, false);
   return (shift < 0) ? 0 : shift;
}

//+------------------------------------------------------------------+
// Mesmo framework de saida em 2 fases do NEXUS369_PRECURSOR_EA -
// validado, ver comentario la para o raciocinio completo.
//+------------------------------------------------------------------+
void GerenciaSaidaDuasFases()
{
   if(magicAtual == 0) return;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magicAtual) continue;

      int barrasAberta = BarrasDesdeAbertura();

      if(barrasAberta >= InpMaxBarrasHold)
      {
         if(trade.PositionClose(tk))
            LogRelatorio(StringFormat("SAIDA POR TEMPO #%d | %s | %d barras sem ser parado (limite %d) - fechado a mercado",
               (int)tk, _Symbol, barrasAberta, InpMaxBarrasHold));
         continue;
      }

      if(barrasAberta < InpBarrasGraca) continue;

      double atr_buf[1];
      if(CopyBuffer(h_atr, 0, 0, 1, atr_buf) < 1) continue;
      double atr_now = atr_buf[0];
      if(atr_now <= 0) continue;

      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double slAtual = PositionGetDouble(POSITION_SL);

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copiados = CopyRates(_Symbol, PERIOD_OPERACIONAL, 0, barrasAberta + 1, rates);
      if(copiados < 1) continue;

      if(tipo == POSITION_TYPE_BUY)
      {
         double pico = rates[0].high;
         for(int b = 1; b < copiados; b++) pico = MathMax(pico, rates[b].high);
         double novoSL = pico - InpTrailingATRMult * atr_now;
         if(novoSL > slAtual)
         {
            if(trade.PositionModify(tk, novoSL, 0))
               LogRelatorio(StringFormat("TRAILING FASE2 #%d | %s | SL movido para %s (pico=%s, ATR=%.5f)",
                  (int)tk, _Symbol, DoubleToString(novoSL, _Digits), DoubleToString(pico, _Digits), atr_now));
         }
      }
      else
      {
         double pico = rates[0].low;
         for(int b = 1; b < copiados; b++) pico = MathMin(pico, rates[b].low);
         double novoSL = pico + InpTrailingATRMult * atr_now;
         if(slAtual == 0 || novoSL < slAtual)
         {
            if(trade.PositionModify(tk, novoSL, 0))
               LogRelatorio(StringFormat("TRAILING FASE2 #%d | %s | SL movido para %s (pico=%s, ATR=%.5f)",
                  (int)tk, _Symbol, DoubleToString(novoSL, _Digits), DoubleToString(pico, _Digits), atr_now));
         }
      }
   }
}

int LossesSeguidosAtual() { return (g_gvLosses != "" && GlobalVariableCheck(g_gvLosses)) ? (int)GlobalVariableGet(g_gvLosses) : 0; }

void RegistrarResultadoRisco(bool ganhou)
{
   if(g_gvLosses == "") return;
   if(ganhou) GlobalVariableSet(g_gvLosses, 0.0);
   else GlobalVariableSet(g_gvLosses, (double)(LossesSeguidosAtual() + 1));
}

double MultiplicadorRiscoDinamico()
{
   int losses = LossesSeguidosAtual();
   if(losses >= 3) return 0.25;
   if(losses == 2) return 0.50;
   return 1.0;
}

double CalcularLote(double riskPct, double slDistPoints)
{
   double mult = MultiplicadorRiscoDinamico();
   if(mult < 1.0)
      LogRelatorio(StringFormat("RISCO REDUZIDO | %s | %d perdas seguidas | risco%% %.2f -> %.2f (x%.2f)",
         _Symbol, LossesSeguidosAtual(), riskPct, riskPct * mult, mult));
   riskPct = riskPct * mult;

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
// Largura da banda no percentil das ultimas InpSqueezePercJanela velas
// (rank simples, sem depender de array externo - CopyBuffer direto).
//+------------------------------------------------------------------+
bool CalcularSqueezePercentil(double &percentilAtual)
{
   double upper[], lower[], mid[];
   int total = InpSqueezePercJanela + 2;
   if(CopyBuffer(h_bb, 1, 1, total, upper) < total) return false; // banda superior
   if(CopyBuffer(h_bb, 2, 1, total, lower) < total) return false; // banda inferior
   if(CopyBuffer(h_bb, 0, 1, total, mid)   < total) return false; // banda media

   double larguras[];
   ArrayResize(larguras, total);
   for(int i = 0; i < total; i++)
      larguras[i] = (mid[i] > 0) ? (upper[i] - lower[i]) / mid[i] : 0;

   // larguras[] vem do CopyBuffer em ordem "series=false" (index 0 = mais antigo
   // do range pedido). O ultimo elemento (total-1) e a largura da vela de sinal
   // (indice 1 do grafico, ja fechada) - compara ela contra a janela toda.
   double larguraSinal = larguras[total-1];
   int menores = 0;
   for(int i = 0; i < total - 1; i++)
      if(larguras[i] <= larguraSinal) menores++;
   percentilAtual = (double)menores / (double)(total - 1);
   return true;
}

//+------------------------------------------------------------------+
void OnTick()
{
   NovoDia();
   TemPosicaoAberta();
   GerenciaSaidaDuasFases();
   if(!ExecucaoAutorizada()) return;
   if(!g_ParOperavel) return;
   if(StopDiario_Bloqueado()) return;
   if(MargemBloqueada()) return; // guarda de margem da CONTA INTEIRA (20/07/2026)
   if(DrawdownDiarioEstourado()) return;
   if(tradesHoje >= InpMaxTradesDia) return;
   if(TemPosicaoAberta()) return;

   datetime curBar = iTime(_Symbol, PERIOD_OPERACIONAL, 0);
   if(curBar == lastSignalBarTime) return;
   lastSignalBarTime = curBar;
   barsSinceLastSignal++;
   if(barsSinceLastSignal < InpBarrasMinEntreSinais) return;

   // Vela ANTERIOR (ja fechada, indice 1) - carrega o sinal do trap.
   double atr_buf[1];
   if(CopyBuffer(h_atr, 0, 1, 1, atr_buf) < 1) return;
   double atr_sinal = atr_buf[0];
   if(atr_sinal <= 0) return;

   double bb_upper[1], bb_lower[1];
   if(CopyBuffer(h_bb, 1, 1, 1, bb_upper) < 1) return;
   if(CopyBuffer(h_bb, 2, 1, 1, bb_lower) < 1) return;

   double percentilLargura;
   if(!CalcularSqueezePercentil(percentilLargura)) return;
   if(percentilLargura > InpSqueezePercMax) return; // so opera em regime de squeeze

   MqlRates velaSinal[1];
   if(CopyRates(_Symbol, PERIOD_OPERACIONAL, 1, 1, velaSinal) < 1) return;

   bool tentouCima  = (velaSinal[0].high > bb_upper[0]) && (velaSinal[0].close < bb_upper[0]);
   bool tentouBaixo = (velaSinal[0].low  < bb_lower[0]) && (velaSinal[0].close > bb_lower[0]);

   string side = "";
   if(tentouCima) side = "SELL";       // rompimento pra cima falhou -> contraria (vende)
   else if(tentouBaixo) side = "BUY";  // rompimento pra baixo falhou -> contraria (compra)
   else return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(InpFiltroSpreadAtivo)
   {
      double spread_atual = ask - bid;
      double stop_dist_preco = InpStopGracaATRMult * atr_sinal;
      double spread_pct_do_stop = (stop_dist_preco > 0) ? (spread_atual / stop_dist_preco * 100.0) : 999.0;
      if(spread_pct_do_stop > InpMaxSpreadATRPct)
      {
         LogRelatorio(StringFormat("SINAL REJEITADO POR SPREAD | %s | spread=%.5f (%.1f%% do stop, limite %.1f%%) | squeeze_pct=%.0f%% %s",
            _Symbol, spread_atual, spread_pct_do_stop, InpMaxSpreadATRPct, percentilLargura*100, side));
         return;
      }
   }

   string tf = NomePeriodo(PERIOD_OPERACIONAL);
   string comentario = StringFormat("ESTL %s SQ%.0f%% %s", tf, percentilLargura*100, side);
   if(StringLen(comentario) > 31) comentario = StringSubstr(comentario, 0, 31);

   string motivoDetalhado = StringFormat(
      "Squeeze: largura banda no percentil %.0f%% (limite <=%.0f%%). Vela anterior tentou romper banda %s e fechou de volta pra dentro (trap) - entra contraria: %s",
      percentilLargura*100, InpSqueezePercMax*100, tentouCima ? "SUPERIOR" : "INFERIOR", side);

   double entry = (side == "BUY") ? ask : bid;
   double sl = (side == "BUY") ? entry - InpStopGracaATRMult * atr_sinal : entry + InpStopGracaATRMult * atr_sinal;
   double slDistPoints = MathAbs(entry - sl) / point;
   double lots = CalcularLote(g_RiskPercent, slDistPoints);
   if(lots <= 0) return;

   long novoMagic = GerarMagicSequencial();
   trade.SetExpertMagicNumber(novoMagic);
   bool ok = (side == "BUY") ? trade.Buy(lots, _Symbol, entry, sl, 0, comentario)
                              : trade.Sell(lots, _Symbol, entry, sl, 0, comentario);
   if(ok)
   {
      magicAtual = novoMagic;
      tempoAberturaPosicaoAtual = curBar;
      precoAberturaPosicaoAtual = entry;
      ladoPosicaoAtual = (side == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      tradesHoje++;
      barsSinceLastSignal = 0;
      RegistraSinalAbertura(novoMagic, _Symbol, tf, side, entry, atr_sinal, sl, 0, InpSetupTipo, motivoDetalhado, lots);
      LogRelatorio(StringFormat(
         "ENTRADA #%d Magic=%d | %s | %s %s | motivo: %s | entrada=%s | stop(fase1)=%s (%.1fxATR, %d velas de graca) | SEM TP fixo (trailing %.1fxATR na fase2) | lote=%.2f",
         (int)trade.ResultOrder(), novoMagic, _Symbol, tf, side, motivoDetalhado,
         DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), InpStopGracaATRMult, InpBarrasGraca,
         InpTrailingATRMult, lots));
      DesenhaSetaEntrada(novoMagic, curBar, entry, ladoPosicaoAtual);
      AtualizaParecer(StringFormat(
         "TRIVIUM369 - PARECER ULTIMA ORDEM\n%s | %s #%d\nEntrada: %s | Stop inicial: %s\nLote: %.2f | %s",
         _Symbol, (side=="BUY"?"COMPRA":"VENDA"), novoMagic, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
         lots, motivoDetalhado));
   }
}

//+------------------------------------------------------------------+
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
   string resultado = profit >= 0 ? "GANHO (trailing travou lucro)" : "PERDA (bateu o stop)";
   string status = profit >= 0 ? "GANHO" : "PERDA";

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   string motivoSaida = "STOP_ou_TRAILING_ou_TEMPO";
   int barrasDuracao = (tempoAberturaPosicaoAtual > 0) ? (int)iBarShift(_Symbol, PERIOD_OPERACIONAL, tempoAberturaPosicaoAtual) : -1;
   double resultadoPips = 0;
   if(point > 0 && precoAberturaPosicaoAtual > 0)
      resultadoPips = (ladoPosicaoAtual == POSITION_TYPE_BUY)
         ? (precoSaida - precoAberturaPosicaoAtual) / point
         : (precoAberturaPosicaoAtual - precoSaida) / point;

   RegistraSinalFechamento(magicAtual, precoSaida, motivoSaida, resultadoPips, profit, barrasDuracao, status);
   RegistrarResultadoRisco(profit >= 0);

   LogRelatorio(StringFormat("FECHAMENTO #%d Magic=%d | %s | %s | saida=%s | resultado=%s | P&L=%.2f %s",
      (int)ticket, (int)magicAtual, _Symbol, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
      DoubleToString(precoSaida, _Digits), resultado, profit, AccountInfoString(ACCOUNT_CURRENCY)));

   DesenhaSetaSaida(magicAtual, TimeCurrent(), precoSaida, profit >= 0);
   AtualizaParecer(StringFormat("TRIVIUM369 - PARECER ULTIMA ORDEM\n%s | FECHADA #%d\nSaida: %s | Resultado: %s\nP&L: %.2f %s | Pips: %.1f",
      _Symbol, (int)magicAtual, DoubleToString(precoSaida, _Digits), resultado, profit, AccountInfoString(ACCOUNT_CURRENCY), resultadoPips));

   magicAtual = 0;
   tempoAberturaPosicaoAtual = 0;
   precoAberturaPosicaoAtual = 0;
}

//+------------------------------------------------------------------+
double OnTester()
{
   double deposito   = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double lucro      = TesterStatistics(STAT_PROFIT);
   double retornoPct = (deposito > 0) ? (lucro / deposito * 100.0) : 0.0;
   double ddPct      = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double pf         = TesterStatistics(STAT_PROFIT_FACTOR);
   double trades     = TesterStatistics(STAT_TRADES);
   double vencedores = TesterStatistics(STAT_PROFIT_TRADES);
   double winRatePct = (trades > 0) ? (vencedores / trades * 100.0) : 0.0;
   double seqMaxPerdas = TesterStatistics(STAT_CONLOSSMAX_TRADES);
   double margemMin  = TesterStatistics(STAT_MIN_MARGINLEVEL);
   double equityMin  = TesterStatistics(STAT_EQUITYMIN);

   int h = FileOpen("TRIVIUM369_BACKTEST_RESULTADOS.csv", FILE_READ|FILE_WRITE|FILE_ANSI|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      if(FileSize(h) == 0)
         FileWriteString(h, "simbolo;timeframe;sessao_filtro;risco_pct;leverage_conta;deposito;retorno_pct;drawdown_max_pct;profit_factor;win_rate_pct;seq_max_perdas;margem_minima_pct;equity_minima;total_trades\r\n");
      FileWriteString(h, StringFormat("%s;%s;%s;%.1f;%d;%.2f;%.2f;%.2f;%.2f;%.2f;%d;%.2f;%.2f;%d\r\n",
         _Symbol, EnumToString(PERIOD_OPERACIONAL), "ESTILINGUE", g_RiskPercent, (int)AccountInfoInteger(ACCOUNT_LEVERAGE), deposito,
         retornoPct, ddPct, pf, winRatePct, (int)seqMaxPerdas, margemMin, equityMin, (int)trades));
      FileClose(h);
   }
   return retornoPct;
}
//+------------------------------------------------------------------+
