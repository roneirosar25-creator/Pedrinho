//+------------------------------------------------------------------+
//| NEXUS369_GER40_ABERTURA_EA.mq5                                    |
//| TRIVIUM369 (c) 2026 - Pedrinho, 18/07/2026                        |
//|                                                                    |
//| Nasce da pergunta do Ronei (18/07): "todos os dias as ~10h o        |
//| spread do GER40 cai de 400 pra 120 - onde o preco vai parar, como  |
//| aproveitar?". Achado no dado real: a compressao acontece as        |
//| 07:00-07:05 no horario do SERVIDOR, todo dia util, muito            |
//| consistente (84 dias medidos, sempre no mesmo minuto) - bate com   |
//| a abertura do pregao a vista de Frankfurt/Xetra (09h local =       |
//| 07h UTC, servidor UTC+3 nesse periodo).                             |
//|                                                                    |
//| REGRA A (validada, esta e a que virou EA - ver ANALISES/           |
//| GER40_REGRA_A_ABERTURA_XETRA_18JUL.csv):                            |
//|  - Sinal = direcao da vela M15 que cobre 07:00-07:15 servidor       |
//|    (a vela que engloba o instante da compressao de spread)         |
//|  - Entra na vela SEGUINTE (07:15-07:30), na MESMA direcao do        |
//|    corpo da vela do sinal (segue o movimento que ja comecou)        |
//|                                                                    |
//| Backtest M15, ~8 anos de historico, spread real descontado,         |
//| treino/teste 70/30 cronologico: PF=2.30 treino / PF=2.54 teste,     |
//| WR~55% nos dois lados (799+343 trades). Forte e consistente em      |
//| TODOS os dias da semana (Segunda 2.25 / Terca 2.74 / Quarta 2.57 /  |
//| Quinta 2.05 / Sexta 2.29) - sem anomalia de dia especifico aqui,    |
//| ao contrario da Regra B (fechamento Xetra, mais fraca, Quinta/      |
//| Sexta caem bem - registrada em separado, NAO VIROU EA ainda,        |
//| ver 03_SESSOES/ e conversa 18/07 pra retomar depois).               |
//|                                                                    |
//| SAIDA EM 2 FASES (mesmo framework validado na regra precursora,     |
//| recalibrado com o MAE REAL do GER40 - instrumento e volatilidade   |
//| diferentes do forex, nao reusa os numeros de la):                   |
//|  FASE 1 (3 primeiras velas M15): stop largo fixo 4.0xATR14, nao     |
//|    mexe - calibrado no p90 do adverso real medido nas 3 primeiras   |
//|    velas apos entrada (mediana 1.59xATR, p90 4.23xATR).             |
//|  FASE 2 (4a vela em diante): trailing 0.5xATR do pico a favor, so   |
//|    aperta. SEM take profit fixo. Fecha a mercado se nao foi parado  |
//|    em 8 velas M15 (2h) - mesma janela usada no backtest.            |
//|                                                                    |
//| SO OPERA GER40 - trava se anexado em qualquer outro simbolo         |
//| (regra e especifica do horario de abertura de Frankfurt/Xetra,     |
//| nao generaliza sem novo teste).                                    |
//|                                                                    |
//| NAO E TRACK RECORD REAL - backtest historico. Rodar na demo         |
//| primeiro, comparar contra o simulado, so depois cogitar a real.    |
//|                                                                    |
//| KILL SWITCH PROPRIO (GV_EXECUCAO_AUTORIZADA_GER40_ABERTURA),        |
//| separado de tendencia/reversao/precursor.                          |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#include <Trade\Trade.mqh>
#include <TRIVIUM\STOP_DIARIO.mqh>

input group "=== Janela da regra (horario do SERVIDOR, calibrado no dado real) ==="
input int    InpHoraSinal      = 7;   // vela do sinal comeca aqui (cobre 07:00-07:15)
input int    InpMinutoSinal    = 0;
input int    InpHoraEntrada    = 7;   // vela de entrada (a seguinte, 07:15-07:30)
input int    InpMinutoEntrada  = 15;

input group "=== Saida em 2 fases (validado - NAO mudar sem novo teste) ==="
input int    InpATRPeriod        = 14;
input int    InpBarrasGraca      = 3;    // fase 1: N velas M15 com stop largo fixo, sem trailing
input double InpStopGracaATRMult = 4.0;  // fase 1: calibrado no p90 do MAE real (ver cabecalho)
input double InpTrailingATRMult  = 0.5;  // fase 2: trailing apertado, validado no backtest
input int    InpMaxBarrasHold    = 8;    // fecha a mercado se nao foi parado ate aqui (2h em M15)

input group "=== Gestao de Risco ==="
input double InpRiskPercent      = 1.0;
input double InpMaxDDPercent     = 3.0;
input int    InpMaxTradesDia     = 1;    // a regra so gera 1 sinal por dia (abertura), nao precisa de mais

input group "=== Magic Number ==="
input string InpSetupTipo     = "GER40_Abertura_Xetra";

input group "=== Filtro de Spread ==="
input bool   InpFiltroSpreadAtivo = true;
input double InpMaxSpreadATRPct   = 25.0; // GER40 tem spread base mais alto que forex - limite mais folgado

#define GV_MAGIC_SEQUENCIAL "TRIVIUM369_MAGIC_SEQUENCIAL_COUNTER"
#define MAGIC_SEQUENCIAL_INICIO 200000
string g_signalsLogFile = "";
#define SIGNALS_LOG_HEADER "magic;datetime_abertura;ativo;timeframe;direcao;preco_entrada;atr_valor;sl_calculado;tp_calculado;setup_tipo;motivo_entrada;lote;datetime_fechamento;preco_fechamento;motivo_saida;resultado_pips;resultado_reais;barras_duracao;status"

#define GV_EXECUCAO_AUTORIZADA_GER40_ABERTURA "TRIVIUM369_EXECUCAO_AUTORIZADA_GER40_ABERTURA"
#define GV_LOSSES_PREFIX "TRIVIUM369_LOSSES_SEGUIDAS_"
string g_gvLosses = "";

bool ExecucaoAutorizada()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   return GlobalVariableCheck(GV_EXECUCAO_AUTORIZADA_GER40_ABERTURA) && GlobalVariableGet(GV_EXECUCAO_AUTORIZADA_GER40_ABERTURA) >= 1.0;
}

CTrade trade;
int    h_atr = INVALID_HANDLE; // ATR calculado em M15, independente do timeframe do grafico
bool   g_ParOperavel = true;
double saldoInicioDia = 0;
datetime diaAtual = 0;
int    tradesHoje = 0;
long   magicAtual = 0;
datetime tempoAberturaPosicaoAtual = 0;
double precoAberturaPosicaoAtual = 0;
ENUM_POSITION_TYPE ladoPosicaoAtual = POSITION_TYPE_BUY;
datetime lastM15BarProcessada = 0;
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

void LogRelatorio(string linha)
{
   Print(linha);
   int h = FileOpen(logFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h != INVALID_HANDLE) { FileSeek(h, 0, SEEK_END); FileWrite(h, linha); FileClose(h); }
}

void DesenhaSetaEntrada(long magic, datetime tempo, double preco, ENUM_POSITION_TYPE lado)
{
   string nome = StringFormat("TRIVIUM_GER40_ENTRADA_%d", magic);
   ObjectCreate(0, nome, (lado == POSITION_TYPE_BUY) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_GER40_ENTRADA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" ABERTURA XETRA %s #%d", (lado == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA", magic));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, (lado == POSITION_TYPE_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM);
}

void DesenhaSetaSaida(long magic, datetime tempo, double preco, bool ganho)
{
   string nome = StringFormat("TRIVIUM_GER40_SAIDA_%d", magic);
   ObjectCreate(0, nome, OBJ_ARROW_CHECK, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_GER40_SAIDA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" SAIDA #%d (%s)", magic, ganho ? "GANHO" : "PERDA"));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, ANCHOR_TOP);
}

#define PAINEL_GER40_NOME "TRIVIUM_PAINEL_GER40_ABERTURA"
void AtualizaParecer(string texto)
{
   if(ObjectFind(0, PAINEL_GER40_NOME) < 0)
   {
      ObjectCreate(0, PAINEL_GER40_NOME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_YDISTANCE, 175); // abaixo dos outros paineis
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, PAINEL_GER40_NOME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_COLOR, clrCyan);
      ObjectSetInteger(0, PAINEL_GER40_NOME, OBJPROP_BACK, false);
   }
   ObjectSetString(0, PAINEL_GER40_NOME, OBJPROP_TEXT, "[GER40 ABERTURA XETRA]\n" + texto);
}

//+------------------------------------------------------------------+
int OnInit()
{
   string sym = _Symbol; StringToUpper(sym);
   g_ParOperavel = (StringFind(sym, "GER40") >= 0);
   if(!g_ParOperavel)
      Print("AVISO: NEXUS369_GER40_ABERTURA_EA so foi validado em GER40 - anexado em ", sym, ", grafico so visual, EA nao abre posicao aqui.");

   GarantirContadorMagicNuncaRetrocede();

   h_atr = iATR(_Symbol, PERIOD_M15, InpATRPeriod); // sempre M15, independente do timeframe do grafico anexado
   if(h_atr == INVALID_HANDLE) { Print("Erro ao criar handle ATR M15: ", GetLastError()); return INIT_FAILED; }

   trade.SetDeviationInPoints(30);
   magicAtual = 0;
   saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   diaAtual = iTime(_Symbol, PERIOD_D1, 0);
   tradesHoje = 0;

   long contaLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   logFileName = "NEXUS369_GER40_ABERTURA_RELATORIO_" + sym + "_" + IntegerToString(contaLogin) + ".txt";
   g_signalsLogFile = "TRIVIUM369_SIGNALS_LOG_" + IntegerToString(contaLogin) + ".csv";
   g_gvLosses = GV_LOSSES_PREFIX + IntegerToString(contaLogin) + "_" + sym + "_GER40ABERTURA";

   LogRelatorio(StringFormat("=== INIT GER40_ABERTURA %s | %s | Sinal=%02d:%02d Entrada=%02d:%02d servidor | Fase1=%dvelas@%.1fxATR Fase2=trailing%.1fxATR | Risco=%.1f%% | EXECUCAO=%s ===",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), sym, InpHoraSinal, InpMinutoSinal, InpHoraEntrada, InpMinutoEntrada,
      InpBarrasGraca, InpStopGracaATRMult, InpTrailingATRMult, InpRiskPercent,
      ExecucaoAutorizada() ? "AUTORIZADA" : "AGUARDANDO 'pode rodar' do Ronei"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);
   ObjectDelete(0, PAINEL_GER40_NOME);
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

bool TemPosicaoAberta()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      string comentario = PositionGetString(POSITION_COMMENT);
      if(StringFind(comentario, "GERAB " ) == 0)
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

int BarrasM15DesdeAbertura()
{
   if(tempoAberturaPosicaoAtual == 0) return 0;
   int shift = iBarShift(_Symbol, PERIOD_M15, tempoAberturaPosicaoAtual, false);
   return (shift < 0) ? 0 : shift;
}

//+------------------------------------------------------------------+
void GerenciaSaidaDuasFases()
{
   if(magicAtual == 0) return;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magicAtual) continue;

      int barrasAberta = BarrasM15DesdeAbertura();

      if(barrasAberta >= InpMaxBarrasHold)
      {
         if(trade.PositionClose(tk))
            LogRelatorio(StringFormat("SAIDA POR TEMPO #%d | %s | %d velas M15 sem ser parado (limite %d) - fechado a mercado",
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
      int copiados = CopyRates(_Symbol, PERIOD_M15, 0, barrasAberta + 1, rates);
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

   // So processa uma vez por vela M15 nova, independente do timeframe do grafico anexado.
   datetime curM15 = iTime(_Symbol, PERIOD_M15, 0);
   if(curM15 == lastM15BarProcessada) return;
   lastM15BarProcessada = curM15;

   MqlDateTime dt;
   TimeToStruct(curM15, dt);
   // A vela ATUAL (recem-aberta, indice 0) precisa ser exatamente a vela de ENTRADA
   // (07:15). O sinal vem da vela ANTERIOR (indice 1, ja fechada, 07:00-07:15).
   if(dt.hour != InpHoraEntrada || dt.min != InpMinutoEntrada) return;

   MqlRates velaSinal[1];
   if(CopyRates(_Symbol, PERIOD_M15, 1, 1, velaSinal) < 1) return;
   MqlDateTime dtSinal;
   TimeToStruct(velaSinal[0].time, dtSinal);
   if(dtSinal.hour != InpHoraSinal || dtSinal.min != InpMinutoSinal) return; // confirma que a vela anterior e mesmo a do sinal (protege contra gap de fim de semana etc.)

   double atr_buf[2];
   if(CopyBuffer(h_atr, 0, 1, 1, atr_buf) < 1) return;
   double atr_sinal = atr_buf[0];
   if(atr_sinal <= 0) return;

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
         LogRelatorio(StringFormat("SINAL REJEITADO POR SPREAD | %s | spread=%.2f (%.1f%% do stop, limite %.1f%%) | %s",
            _Symbol, spread_atual, spread_pct_do_stop, InpMaxSpreadATRPct, side));
         return;
      }
   }

   string comentario = StringFormat("GERAB %s %02d%02d", side, InpHoraSinal, InpMinutoSinal);
   if(StringLen(comentario) > 31) comentario = StringSubstr(comentario, 0, 31);

   string motivoDetalhado = StringFormat(
      "Abertura Xetra: vela %02d:%02d servidor fechou %s (corpo %s), entrada segue a mesma direcao",
      InpHoraSinal, InpMinutoSinal, side, (corpoAlta ? "de alta" : "de baixa"));

   double entry = (side == "BUY") ? ask : bid;
   double sl = (side == "BUY") ? entry - InpStopGracaATRMult * atr_sinal : entry + InpStopGracaATRMult * atr_sinal;
   double slDistPoints = MathAbs(entry - sl) / point;
   double lots = CalcularLote(InpRiskPercent, slDistPoints);
   if(lots <= 0) return;

   long novoMagic = GerarMagicSequencial();
   trade.SetExpertMagicNumber(novoMagic);
   bool ok = (side == "BUY") ? trade.Buy(lots, _Symbol, entry, sl, 0, comentario)
                              : trade.Sell(lots, _Symbol, entry, sl, 0, comentario);
   if(ok)
   {
      magicAtual = novoMagic;
      tempoAberturaPosicaoAtual = curM15;
      precoAberturaPosicaoAtual = entry;
      ladoPosicaoAtual = (side == "BUY") ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      tradesHoje++;
      RegistraSinalAbertura(novoMagic, _Symbol, "M15", side, entry, atr_sinal, sl, 0, InpSetupTipo, motivoDetalhado, lots);
      LogRelatorio(StringFormat(
         "ENTRADA #%d Magic=%d | %s | %s | motivo: %s | entrada=%s | stop(fase1)=%s (%.1fxATR, %d velas de graca) | SEM TP fixo (trailing %.1fxATR na fase2) | lote=%.2f",
         (int)trade.ResultOrder(), novoMagic, _Symbol, side, motivoDetalhado,
         DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), InpStopGracaATRMult, InpBarrasGraca,
         InpTrailingATRMult, lots));
      DesenhaSetaEntrada(novoMagic, curM15, entry, ladoPosicaoAtual);
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
   int barrasDuracao = (tempoAberturaPosicaoAtual > 0) ? (int)iBarShift(_Symbol, PERIOD_M15, tempoAberturaPosicaoAtual) : -1;
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
         _Symbol, "M15", "GER40_ABERTURA_XETRA", InpRiskPercent, (int)AccountInfoInteger(ACCOUNT_LEVERAGE), deposito,
         retornoPct, ddPct, pf, winRatePct, (int)seqMaxPerdas, margemMin, equityMin, (int)trades));
      FileClose(h);
   }
   return retornoPct;
}
//+------------------------------------------------------------------+
