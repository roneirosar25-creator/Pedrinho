//+------------------------------------------------------------------+
//| NEXUS369_PRECURSOR_EA.mq5                                         |
//| TRIVIUM369 (c) 2026 - Pedrinho, 17-18/07/2026                     |
//|                                                                    |
//| Nasce do estudo de "velas gigantes" pedido pelo Ronei (17/07):     |
//| reagir DEPOIS que a vela gigante ja fechou nao tem edge (testado,  |
//| 50/50). O que tem edge de verdade e o que PRECEDE ela - squeeze de |
//| Bollinger estourando (vela+volume ja acima do normal, regime geral |
//| ainda comprimido) e concentracao em horas especificas de sessao.   |
//|                                                                    |
//| REGRA (validada em backtest H1, 5 pares, spread real, treino/teste |
//| 70/30, ver 03_SESSOES/ e ANALISES/REGRA_PRECURSORA_*.csv):         |
//|  - Vela anterior tem range >= 1.2x seu ATR14 (ja maior que normal) |
//|  - Volume da vela anterior >= 1.2x media(20)                       |
//|  - Hora da vela que vai abrir esta em 06-08h ou 11-14h SERVIDOR    |
//|    (concentra 54% de todas as velas gigantes - Toquio/Londres)     |
//|  - Direcao = mesma direcao do corpo da vela anterior (segue o      |
//|    movimento que ja comecou, nao contraria)                        |
//|                                                                    |
//| SAIDA EM 2 FASES (pedido do Ronei: "nao ser estopado nos momentos  |
//| iniciais, apertar nos momentos finais" - calibrado com dado real,  |
//| nao chute: MAE mediano nas 3 primeiras velas = 1.22xATR, p90=      |
//| 3.44xATR):                                                          |
//|  FASE 1 (3 primeiras velas): stop LARGO fixo em 3.5xATR, nao mexe. |
//|  FASE 2 (4a vela em diante): trailing em 0.5xATR do pico a favor,  |
//|    so aperta, nunca afrouxa. SEM take profit fixo (o trailing      |
//|    apertado e quem decide onde sai - testar TP fixo 1.5xATR deu    |
//|    PF<1 em TODOS os pares; trailing 0.5xATR deu PF 1.31-1.91 nos   |
//|    5 pares, treino E teste).                                       |
//|                                                                    |
//| RESULTADO DO BACKTEST (57k+ trades, ver artifact enviado ao Ronei  |
//| 17-18/07): EURUSD-T PF 1.85/1.90, GBPUSD-T 1.91/1.79, USDCAD-T     |
//| 1.83/1.58, AUDUSD-T 1.69/1.47, NZDUSD-T 1.59/1.31 (treino/teste).  |
//| NAO E TRACK RECORD REAL - e backtest historico. Objetivo desta     |
//| versao e rodar na DEMO primeiro, comparar contra o simulado, so    |
//| depois cogitar a real.                                              |
//|                                                                    |
//| KILL SWITCH PROPRIO (GV_EXECUCAO_AUTORIZADA_PRECURSOR), separado   |
//| dos kill switches de tendencia e reversao - autorizacoes           |
//| anteriores do Ronei NAO cobrem este EA. Precisa de "pode rodar"    |
//| novo, especifico.                                                  |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#include <Trade\Trade.mqh>
#include <TRIVIUM\STOP_DIARIO.mqh>

input group "=== Auto-calibragem por ativo ==="
// Os 5 pares abaixo foram validados no backtest (17-18/07/2026). Fora
// deles, o EA fica so visual (g_ParOperavel=false) ate ter novo teste.
input bool   InpAutoCalibrarPorAtivo = true;

input group "=== Filtro de sinal (usado so se auto-calibragem = false) ==="
input int    InpATRPeriod        = 14;
input int    InpVolumePeriod     = 20;
input double InpFiltroForca      = 1.2;  // vela e volume anteriores >= X * (ATR14 / media20)

input group "=== Janela de horario (servidor da corretora) ==="
// Concentra 54% das velas gigantes historicas - Toquio (06-08h) + Londres (11-14h)
input bool   InpUsarHorasFixas   = true; // se false, ignora filtro de hora
input string InpHorasPermitidas  = "6,7,8,11,12,13,14"; // horas do servidor, separadas por virgula

input group "=== Saida em 2 fases (validado - NAO mudar sem novo teste) ==="
input int    InpBarrasGraca      = 3;    // fase 1: N velas com stop largo fixo, sem trailing
input double InpStopGracaATRMult = 3.5;  // fase 1: distancia do stop largo (calibrado no p90 do MAE real)
input double InpTrailingATRMult  = 0.5;  // fase 2: distancia do trailing (mais apertado que outros EAs de proposito)
input int    InpMaxBarrasHold    = 20;   // fecha a mercado se nao foi parado ate aqui (mesma regra do backtest)

input group "=== Gestao de Risco ==="
input double InpRiskPercent      = 1.0;  // manual - ignorado se auto-calibragem = true
input double InpMaxDDPercent     = 3.0;
input int    InpMaxTradesDia     = 5;
input int    InpBarrasMinEntreSinais = 5;

// Valores efetivos - vem da tabela de auto-calibragem (se ligada) ou dos inputs manuais
double g_FiltroForca;
double g_RiskPercent;
bool   g_ParOperavel = true;
// Timeframe OPERACIONAL (sempre H1 forex / H4 cripto) - independente do
// timeframe do grafico onde o EA foi anexado. O grafico e so uma "vaga"
// de anexacao (varios EAs desta familia compartilham simbolo+H1, e o MT5
// nao deixa 2 graficos iguais abertos - cada EA usa um timeframe de
// grafico diferente como vaga, mas todos calculam H1/H4 de verdade).
ENUM_TIMEFRAMES g_TFOperacional = PERIOD_H1;

//+------------------------------------------------------------------+
// Tabela de calibragem por ativo. Os 5 pares originais passaram no
// backtest (17-18/07/2026, treino/teste 70/30, PF>1 nos dois lados
// com trailing 0.5xATR). Filtro de forca ficou igual (1.2x) pros 5 -
// testei 1.2/1.4/1.5x e o nivel do filtro quase nao mudou o resultado,
// quem decidiu foi a saida em 2 fases. Risco 1.0% - mesmo raciocinio
// do TREND_VALIDADO pros pares majores, ajustar se Ronei pedir.
//
// EXPANSAO 19/07/2026 (pedido do Ronei - testar todos os pares e
// criptomoedas): +9 cruzamentos forex (EURAUD/EURCAD/EURCHF/EURGBP/
// EURNZD/GBPAUD/GBPCAD/GBPNZD/USDCHF, todos H1, mesmo filtro/risco).
// TODO par com JPY foi testado e REPROVOU (WR caindo a 4-19%, nao e
// so falta de amostra - comportamento estruturalmente diferente,
// nao operar JPY com esta regra). +4 criptomoedas (BTC/ETH/LTC/BCH)
// mas SO EM H4 - a mesma regra testada em H1 pra cripto reprovou
// (mercado 24/7 sem a mesma dinamica de sessao que da o edge no
// forex), em H4 fica boa (PF 1.09-2.24). XRP/SOL/ADA reprovaram em
// todos os timeframes testados - ficam de fora.
//+------------------------------------------------------------------+
void CarregarCalibragemPorAtivo()
{
   g_TFOperacional = PERIOD_H1; // default - so muda no ramo cripto abaixo

   if(!InpAutoCalibrarPorAtivo)
   {
      g_FiltroForca = InpFiltroForca;
      g_RiskPercent = InpRiskPercent;
      return;
   }

   string sym = _Symbol; StringToUpper(sym);
   g_ParOperavel = true;

   bool ehCriptoValidada = (StringFind(sym, "BTCUSD") >= 0 || StringFind(sym, "ETHUSD") >= 0 ||
                             StringFind(sym, "LTCUSD") >= 0 || StringFind(sym, "BCHUSD") >= 0);

   if(StringFind(sym, "EURUSD") >= 0)      { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPUSD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "USDCAD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "AUDUSD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "NZDUSD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURAUD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURCAD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURCHF") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURGBP") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "EURNZD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPAUD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPCAD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "GBPNZD") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "USDCHF") >= 0) { g_FiltroForca = 1.2; g_RiskPercent = 1.0; }
   else if(ehCriptoValidada)
   {
      // So validado em H4 - opera SEMPRE em H4 internamente, independente
      // do timeframe do grafico onde o EA foi anexado (mesmo truque do
      // NEXUS369_GER40_ABERTURA_EA - o grafico e so uma "vaga" de anexacao,
      // quem decide o timeframe de calculo e g_TFOperacional).
      g_FiltroForca = 1.2; g_RiskPercent = 1.0; g_TFOperacional = PERIOD_H4;
   }
   else
   {
      // Fora da tabela validada - EA fica so visual (nao abre posicao)
      // ate ter backtest proprio, mesmo com auto-calibragem ligada.
      g_FiltroForca = 999.0; g_RiskPercent = 0.0; g_ParOperavel = false;
   }
}

input group "=== Magic Number ==="
input string InpSetupTipo     = "Precursor_Squeeze_Sessao";

input group "=== Filtro de Spread ==="
input bool   InpFiltroSpreadAtivo = true;
input double InpMaxSpreadATRPct   = 15.0;

#define GV_MAGIC_SEQUENCIAL "TRIVIUM369_MAGIC_SEQUENCIAL_COUNTER"
#define MAGIC_SEQUENCIAL_INICIO 200000
string g_signalsLogFile = "";
#define SIGNALS_LOG_HEADER "magic;datetime_abertura;ativo;timeframe;direcao;preco_entrada;atr_valor;sl_calculado;tp_calculado;setup_tipo;motivo_entrada;lote;datetime_fechamento;preco_fechamento;motivo_saida;resultado_pips;resultado_reais;barras_duracao;status"

// Kill switch PROPRIO deste EA - separado de tendencia/reversao.
#define GV_EXECUCAO_AUTORIZADA_PRECURSOR "TRIVIUM369_EXECUCAO_AUTORIZADA_PRECURSOR"
#define GV_LOSSES_PREFIX "TRIVIUM369_LOSSES_SEGUIDAS_"
string g_gvLosses = "";

bool ExecucaoAutorizada()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   return GlobalVariableCheck(GV_EXECUCAO_AUTORIZADA_PRECURSOR) && GlobalVariableGet(GV_EXECUCAO_AUTORIZADA_PRECURSOR) >= 1.0;
}

CTrade trade;
int    h_atr = INVALID_HANDLE;
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
   string nome = StringFormat("TRIVIUM_PREC_ENTRADA_%d", magic);
   ObjectCreate(0, nome, (lado == POSITION_TYPE_BUY) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_PREC_ENTRADA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" PRECURSOR %s #%d", (lado == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA", magic));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, (lado == POSITION_TYPE_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM);
}

void DesenhaSetaSaida(long magic, datetime tempo, double preco, bool ganho)
{
   string nome = StringFormat("TRIVIUM_PREC_SAIDA_%d", magic);
   ObjectCreate(0, nome, OBJ_ARROW_CHECK, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_PREC_SAIDA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" SAIDA #%d (%s)", magic, ganho ? "GANHO" : "PERDA"));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, ANCHOR_TOP);
}

#define PAINEL_PREC_NOME "TRIVIUM_PAINEL_PRECURSOR"
void AtualizaParecer(string texto)
{
   if(ObjectFind(0, PAINEL_PREC_NOME) < 0)
   {
      ObjectCreate(0, PAINEL_PREC_NOME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_YDISTANCE, 90); // abaixo do painel de tendencia/reversao
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, PAINEL_PREC_NOME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_COLOR, clrGold);
      ObjectSetInteger(0, PAINEL_PREC_NOME, OBJPROP_BACK, false);
   }
   ObjectSetString(0, PAINEL_PREC_NOME, OBJPROP_TEXT, "[PRECURSOR]\n" + texto);
}

//+------------------------------------------------------------------+
int OnInit()
{
   string sym = _Symbol; StringToUpper(sym);
   CarregarCalibragemPorAtivo();
   GarantirContadorMagicNuncaRetrocede();
   if(!g_ParOperavel)
      Print("AVISO: ", sym, " fora da tabela validada do NEXUS369_PRECURSOR_EA (14 pares forex H1: EURUSD/GBPUSD/USDCAD/AUDUSD/NZDUSD/EURAUD/EURCAD/EURCHF/EURGBP/EURNZD/GBPAUD/GBPCAD/GBPNZD/USDCHF-T; 4 criptos SO em H4: BTCUSD/ETHUSD/LTCUSD/BCHUSD-T; pares com JPY nao operam) - grafico so visual, EA nao abre posicao aqui.");

   h_atr = iATR(_Symbol, g_TFOperacional, InpATRPeriod);
   if(h_atr == INVALID_HANDLE) { Print("Erro ao criar handle ATR: ", GetLastError()); return INIT_FAILED; }

   trade.SetDeviationInPoints(30);
   magicAtual = 0;
   saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   diaAtual = iTime(_Symbol, PERIOD_D1, 0);
   tradesHoje = 0;

   long contaLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   logFileName = "NEXUS369_PRECURSOR_RELATORIO_" + sym + "_" + IntegerToString(contaLogin) + ".txt";
   g_signalsLogFile = "TRIVIUM369_SIGNALS_LOG_" + IntegerToString(contaLogin) + ".csv";
   g_gvLosses = GV_LOSSES_PREFIX + IntegerToString(contaLogin) + "_" + sym + "_PREC";

   LogRelatorio(StringFormat("=== INIT PRECURSOR %s | %s %s | Filtro=%.1fx | Fase1=%dvelas@%.1fxATR Fase2=trailing%.1fxATR | Risco=%.1f%% | EXECUCAO=%s ===",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), sym, NomePeriodo(g_TFOperacional),
      g_FiltroForca, InpBarrasGraca, InpStopGracaATRMult, InpTrailingATRMult, g_RiskPercent,
      ExecucaoAutorizada() ? "AUTORIZADA" : "AGUARDANDO 'pode rodar' do Ronei"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);
   ObjectDelete(0, PAINEL_PREC_NOME);
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

// Consulta a REALIDADE da corretora (nao memoria) - mesma correcao aplicada
// aos outros EAs depois do bug de posicao duplicada apos reload (16/07/2026).
bool TemPosicaoAberta()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      string comentario = PositionGetString(POSITION_COMMENT);
      if(StringFind(comentario, "PREC ") == 0)
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
   int shift = iBarShift(_Symbol, g_TFOperacional, tempoAberturaPosicaoAtual, false);
   return (shift < 0) ? 0 : shift;
}

//+------------------------------------------------------------------+
// Gerencia a saida em 2 fases. FASE 1 (barras < InpBarrasGraca): nao
// mexe no stop, deixa a folga inicial (definida no momento da entrada)
// absorver o ruido normal do comeco. FASE 2 (barras >= InpBarrasGraca):
// trailing apertado, calcula o pico a favor desde a abertura usando o
// HISTORICO DE PRECO REAL (nao memoria de instancia - sobrevive a
// reinicializacao do EA). MAX_BARRAS_HOLD: fecha a mercado se nao foi
// parado ate la (mesma regra usada no backtest).
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

      if(barrasAberta < InpBarrasGraca) continue; // fase 1: nao mexe, folga inicial ja esta no SL desde a entrada

      double atr_buf[1];
      if(CopyBuffer(h_atr, 0, 0, 1, atr_buf) < 1) continue;
      double atr_now = atr_buf[0];
      if(atr_now <= 0) continue;

      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double slAtual = PositionGetDouble(POSITION_SL);

      // Pico a favor desde a abertura, calculado do historico real (nao
      // memoria) - MqlRates das barras entre abertura e agora.
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copiados = CopyRates(_Symbol, g_TFOperacional, 0, barrasAberta + 1, rates);
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

int TimeHour(datetime t) { MqlDateTime dt; TimeToStruct(t, dt); return dt.hour; }

bool HoraPermitida()
{
   if(!InpUsarHorasFixas) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string partes[];
   int n = StringSplit(InpHorasPermitidas, ',', partes);
   for(int i = 0; i < n; i++)
      if((int)StringToInteger(partes[i]) == dt.hour) return true;
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   NovoDia();
   TemPosicaoAberta();
   GerenciaSaidaDuasFases(); // roda sempre - protege posicao aberta mesmo com stop diario acionado ou execucao nao autorizada
   if(!ExecucaoAutorizada()) return; // KILL SWITCH proprio deste EA
   if(!g_ParOperavel) return;
   if(StopDiario_Bloqueado()) return;
   if(MargemBloqueada()) return; // guarda de margem da CONTA INTEIRA (20/07/2026)
   if(DrawdownDiarioEstourado()) return;
   if(tradesHoje >= InpMaxTradesDia) return;
   if(TemPosicaoAberta()) return;

   datetime curBar = iTime(_Symbol, g_TFOperacional, 0);
   if(curBar == lastSignalBarTime) return;
   lastSignalBarTime = curBar;
   barsSinceLastSignal++;
   if(barsSinceLastSignal < InpBarrasMinEntreSinais) return;

   if(!HoraPermitida()) return;

   // Vela ANTERIOR (ja fechada, indice 1) - e ela que carrega o sinal.
   double atr_buf[2];
   if(CopyBuffer(h_atr, 0, 1, 1, atr_buf) < 1) return;
   double atr_sinal = atr_buf[0];
   if(atr_sinal <= 0) return;

   MqlRates velaSinal[1];
   if(CopyRates(_Symbol, g_TFOperacional, 1, 1, velaSinal) < 1) return;
   double range_sinal = velaSinal[0].high - velaSinal[0].low;
   double compressao = range_sinal / atr_sinal;

   long vol_buf[];
   ArraySetAsSeries(vol_buf, true);
   if(CopyTickVolume(_Symbol, g_TFOperacional, 1, InpVolumePeriod + 1, vol_buf) < InpVolumePeriod + 1) return;
   double vol_avg = 0;
   for(int i = 1; i <= InpVolumePeriod; i++) vol_avg += (double)vol_buf[i];
   vol_avg /= InpVolumePeriod;
   double volume_rel = (vol_avg > 0) ? (double)vol_buf[0] / vol_avg : 0;

   if(compressao < g_FiltroForca) return;
   if(volume_rel < g_FiltroForca) return;

   bool corpoAlta = velaSinal[0].close > velaSinal[0].open;
   string side = corpoAlta ? "BUY" : "SELL";

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
         LogRelatorio(StringFormat("SINAL REJEITADO POR SPREAD | %s | spread=%.5f (%.1f%% do stop, limite %.1f%%) | compressao=%.2fx vol=%.2fx %s",
            _Symbol, spread_atual, spread_pct_do_stop, InpMaxSpreadATRPct, compressao, volume_rel, side));
         return;
      }
   }

   string tf = NomePeriodo(g_TFOperacional);
   string comentario = StringFormat("PREC %s C%.1f V%.1f %s", tf, compressao, volume_rel, side);
   if(StringLen(comentario) > 31) comentario = StringSubstr(comentario, 0, 31);

   string motivoDetalhado = StringFormat(
      "Vela anterior: compressao=%.2fx ATR14 (min %.1fx), volume=%.2fx media20 (min %.1fx), hora=%02dh servidor, direcao=%s (corpo da vela do sinal)",
      compressao, g_FiltroForca, volume_rel, g_FiltroForca, (int)TimeHour(TimeCurrent()), side);

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
   int barrasDuracao = (tempoAberturaPosicaoAtual > 0) ? (int)iBarShift(_Symbol, g_TFOperacional, tempoAberturaPosicaoAtual) : -1;
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
         _Symbol, EnumToString(g_TFOperacional), "PRECURSOR", g_RiskPercent, (int)AccountInfoInteger(ACCOUNT_LEVERAGE), deposito,
         retornoPct, ddPct, pf, winRatePct, (int)seqMaxPerdas, margemMin, equityMin, (int)trades));
      FileClose(h);
   }
   return retornoPct;
}
//+------------------------------------------------------------------+
