//+------------------------------------------------------------------+
//| TRIVIUM369_UNIFICADO_EA.mq5                                       |
//| TRIVIUM369 (c) 2026 - 01/08/2026                                  |
//|                                                                    |
//| EA unico que junta o que ja estava validado e funcionando nos      |
//| tres sistemas do projeto, num arquivo so:                          |
//|                                                                    |
//|  NEXUS369_TREND_VALIDADO  -> motor de entrada (ADX + volume + DI), |
//|    SL/TP por ATR, trailing, auto-calibragem por ativo, filtros de  |
//|    spread/sessao/anti-chop, magic sequencial, log CSV estruturado. |
//|  STOP_DIARIO.mqh          -> stop diario e guarda de margem, ambos |
//|    de CONTA INTEIRA (nao por EA).                                  |
//|  TRIVIUM_AUTO_SLTP_EA     -> preenche SL/TP de posicao MANUAL      |
//|    (magic=0) pelas linhas de S/R, e avisa se ficar sem protecao.   |
//|  TRIVIUM_MEDIAS_7         -> alinhamento das medias como           |
//|    confirmacao extra de tendencia (ver nota "SEM iCustom" abaixo). |
//|                                                                    |
//| SEM iCustom (decisao de projeto): o filtro de medias e calculado   |
//| aqui com iMA proprio, usando exatamente os mesmos periodos e tipos |
//| do TRIVIUM_MEDIAS_7 (7/14/21 EMA, 50/100/150/200 SMMA). Motivo:    |
//| iCustom("TRIVIUM_MEDIAS_7") cria dependencia de o indicador estar  |
//| instalado e compilado na maquina, e ja deu handle invalido antes.  |
//| Com iMA nativo o EA se basta - o indicador segue existindo pro     |
//| Ronei ver na tela, mas o EA nao depende dele pra decidir.          |
//|                                                                    |
//| ---------------- CORRECOES DESTA VERSAO ----------------           |
//| Tres bugs achados na releitura de 01/08/2026, todos herdados do    |
//| NEXUS369_TREND_VALIDADO e corrigidos aqui:                         |
//|                                                                    |
//| B1 - DrawdownDiarioEstourado() dividia por saldoInicioDia sem      |
//|   checar se era > 0. Se ACCOUNT_EQUITY/BALANCE ler 0 numa          |
//|   reconexao (exatamente o bug que o Ronei achou ao vivo em 09/07 e |
//|   que o STOP_DIARIO.mqh ja defendia em dois pontos), a divisao     |
//|   virava inf e o EA se bloqueava sozinho o dia inteiro, calado.    |
//|                                                                    |
//| B2 - "ja tenho posicao aberta?" era decidido pelo COMENTARIO da    |
//|   ordem ("TND "). Corretora reescreve/apaga comentario (anota      |
//|   "[sl]", "[tp]", ou simplesmente limpa) - quando isso acontece o  |
//|   EA nao se enxerga mais e ABRE UMA SEGUNDA POSICAO no mesmo par.  |
//|   Agora a identidade e o Magic Number, guardado tambem numa        |
//|   GlobalVariable que sobrevive a reinicio do EA. Comentario virou  |
//|   so plano B.                                                      |
//|                                                                    |
//| B3 - (o mais grave) OnTick chamava TemPosicaoAberta(), que zerava  |
//|   magicAtual assim que a posicao sumia da corretora. Se um tick    |
//|   chegasse antes do OnTradeTransaction do fechamento, a guarda     |
//|   "if(magicAtual == 0) return;" descartava o evento inteiro. Isso  |
//|   nao so perdia a linha de fechamento no CSV: perdia a chamada de  |
//|   RegistrarResultadoRisco(), ou seja, o contador de perdas         |
//|   seguidas nao subia e a REDUCAO DINAMICA DE RISCO (0.5x apos 2    |
//|   perdas, 0.25x apos 3) podia simplesmente nunca ligar - uma       |
//|   protecao que parecia existir e nao existia. Agora o magic da     |
//|   posicao viva mora em g_magicAtivo, que SO o fechamento limpa.    |
//|                                                                    |
//| Mais duas melhorias de risco vindas da revisao anterior (PR #5):   |
//|  - lote minimo da corretora que estoura o risco% agora e LOGADO e, |
//|    se passar de InpRiscoMaxAbsolutoPct, a entrada e REJEITADA (o   |
//|    NEXUS369 so forcava o lote pra cima, calado).                   |
//|  - posicao manual que fica sem SL/TP agora gera Alert recorrente.  |
//|                                                                    |
//| ESCOPO: motor de tendencia validado so em GER40, BTCUSD, NZDJPY,   |
//| USDCAD, AUDUSD, NZDUSD, GBPUSD, USDCHF. EURUSD e USDJPY foram      |
//| testados e REPROVADOS - ficam travados no codigo, nao so na doc.   |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property description "EA unificado TRIVIUM369: tendencia ADX+Volume+Medias, stop diario e margem de conta, auto SL/TP em posicao manual."

#include <Trade\Trade.mqh>
#include <TRIVIUM\STOP_DIARIO.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "=== 1. Kill switch e escopo ==="
// O EA pode ser compilado e anexado livremente - fica montado e parado.
// Pra abrir posicao de verdade precisa do "pode rodar" do Ronei, que liga
// a GlobalVariable GV_EXECUCAO_AUTORIZADA. Nao ha input pra isso de
// proposito: tem que ser um ato deliberado fora do grafico.
input bool   InpMotorTendenciaAtivo = true;  // liga o motor de entrada (tendencia)
input bool   InpAutoSLTPManualAtivo = true;  // liga o preenchimento de SL/TP em posicao MANUAL

input group "=== 2. Auto-calibragem por ativo ==="
// Quando true, ADX minimo / Volume minimo / Risco% sao escolhidos pelo
// simbolo do grafico (tabela em CarregarCalibragemPorAtivo). Um unico .ex5
// se auto-configura em qualquer conta, sem preset .set.
input bool   InpAutoCalibrarPorAtivo = true;
input double InpADXMinimo     = 25.0;   // usado so se auto-calibragem = false
input double InpVolumeMinimo  = 1.2;    // usado so se auto-calibragem = false
input double InpRiskPercent   = 1.0;    // usado so se auto-calibragem = false

input group "=== 3. Indicadores do motor de entrada ==="
input int    InpADXPeriod     = 14;
input int    InpVolumePeriod  = 20;
input int    InpATRPeriod     = 14;

input group "=== 4. Stop/Alvo (validado - NAO mudar sem novo backtest) ==="
input double InpStopATRMult   = 2.0;    // Stop = 2.0x ATR
input double InpAlvoATRMult   = 1.5;    // Alvo = 1.5x ATR (MENOR que o stop de proposito,
                                        // compensado pelo acerto alto ~60-70%)
input int    InpBarrasMinEntreSinais = 10;

input group "=== 5. Gestao de risco ==="
input double InpMaxDDPercent  = 3.0;    // drawdown diario deste EA/simbolo
input int    InpMaxTradesDia  = 5;
// Teto duro de risco por trade. Se o lote MINIMO da corretora obrigar a
// arriscar mais que isso (acontece em conta pequena), a entrada e recusada
// em vez de silenciosamente arriscar demais.
input double InpRiscoMaxAbsolutoPct = 5.0;

input group "=== 6. Trailing stop ==="
input bool   InpTrailingAtivo     = true;
input double InpTrailingActivaATR = 1.0;  // ativa quando o lucro chega a X * ATR
input double InpTrailingTravaATR  = 0.5;  // trava o SL a X * ATR do preco atual

input group "=== 7. Filtro de medias (TRIVIUM_MEDIAS_7 nativo) ==="
// 0 = desligado
// 1 = so exige o preco do lado certo da MA200 (filtro leve)
// 2 = exige alinhamento MA7 > MA21 > MA50 e preco acima da MA200 (compra),
//     espelhado na venda (filtro rigoroso)
input int    InpModoFiltroMedias = 1;

input group "=== 8. Filtro anti-chop (timeframe maior precisa concordar) ==="
input bool             InpFiltroAntiChopAtivo = true;
input ENUM_TIMEFRAMES  InpAntiChopTimeframe   = PERIOD_H4;
input double           InpAntiChopADXMinimo   = 20.0;

input group "=== 9. Filtro de spread ==="
input bool   InpFiltroSpreadAtivo = true;
input double InpMaxSpreadATRPct   = 15.0; // rejeita se spread > X% da distancia do stop

input group "=== 10. Filtro de sessao (hora do SERVIDOR da corretora) ==="
// Servidor UTC+3, BRT UTC-3 -> diferenca de 6h. Sessao NY 09-18h BRT = 15-24h servidor.
input bool   InpFiltroSessaoAtivo = false;
input int    InpSessaoInicioHora  = 15;
input int    InpSessaoFimHora     = 24;   // exclusiva; 24 = ate o fim do dia

input group "=== 11. Auto SL/TP em posicao MANUAL (magic=0) ==="
input int    InpMagicManual        = 0;   // qual magic e considerado "manual"
input double InpMargemExtraPts     = 20;  // folga alem da linha de S/R
input string InpSL_Timeframe       = "";  // "" = qualquer TF; ou "M1","M5","H1"...
input int    InpSL_Rank            = 1;   // 1 = linha mais proxima, 2 = segunda...
input string InpTP_Timeframe       = "";
input int    InpTP_Rank            = 1;
input int    InpAlertaIntervaloMin = 5;   // minutos entre reavisos de posicao desprotegida

input group "=== 12. Log ==="
input string InpSetupTipo = "Trend_ADX_VolConfirm_Medias";

//+------------------------------------------------------------------+
//| CONSTANTES E ESTADO GLOBAL                                        |
//+------------------------------------------------------------------+
#define GV_EXECUCAO_AUTORIZADA  "TRIVIUM369_EXECUCAO_AUTORIZADA"
#define GV_MAGIC_SEQUENCIAL     "TRIVIUM369_MAGIC_SEQUENCIAL_COUNTER"
#define MAGIC_SEQUENCIAL_INICIO 200000
#define GV_LOSSES_PREFIX        "TRIVIUM369_LOSSES_SEGUIDAS_"
// B2 - magic da posicao viva deste EA/simbolo, persistido. Sobrevive a
// reinicio do EA e nao depende do comentario da ordem (que a corretora mexe).
#define GV_MAGIC_ATIVO_PREFIX   "TRIVIUM369_MAGIC_ATIVO_"
#define PAINEL_NOME             "TRIVIUM369_PAINEL_UNIFICADO"
#define COMENTARIO_PREFIXO      "TND "
#define SIGNALS_LOG_HEADER "magic;datetime_abertura;ativo;timeframe;direcao;preco_entrada;atr_valor;sl_calculado;tp_calculado;setup_tipo;motivo_entrada;lote;datetime_fechamento;preco_fechamento;motivo_saida;resultado_pips;resultado_reais;barras_duracao;status"

CTrade trade;

// valores efetivos (da tabela de calibragem ou dos inputs manuais)
double g_ADXMinimo    = 25.0;
double g_VolumeMinimo = 1.2;
double g_RiskPercent  = 1.0;
bool   g_ParOperavel  = true;

int    h_adx           = INVALID_HANDLE;
int    h_atr           = INVALID_HANDLE;
int    h_adx_anti_chop = INVALID_HANDLE;
int    h_ma7 = INVALID_HANDLE, h_ma21 = INVALID_HANDLE;
int    h_ma50 = INVALID_HANDLE, h_ma200 = INVALID_HANDLE;

double   saldoInicioDia  = 0;
datetime diaAtual        = 0;
int      tradesHoje      = 0;

// B3 - magic da posicao viva. SO o fechamento (OnTradeTransaction) limpa.
// A varredura de posicoes NUNCA zera isso, senao o evento de fechamento se
// perde e a reducao dinamica de risco deixa de contar as perdas.
long     g_magicAtivo    = 0;
bool     g_temPosicao    = false;

datetime tempoAberturaPosicaoAtual = 0;
double   precoAberturaPosicaoAtual = 0;
ENUM_POSITION_TYPE ladoPosicaoAtual = POSITION_TYPE_BUY;

datetime lastSignalBarTime  = 0;
int      barsSinceLastSignal = 999;

string g_logFileName    = "";
string g_signalsLogFile = "";
string g_gvLosses       = "";
string g_gvMagicAtivo   = "";

// controle dos avisos de posicao manual desprotegida
ulong    g_alertaTickets[];
datetime g_alertaUltimoAviso[];

//+------------------------------------------------------------------+
//| Tabela de calibragem por ativo                                    |
//| GER40/BTCUSD  = validacao rigorosa (Z>3.7, 20 janelas, OOS).      |
//| Demais pares  = treino/teste 70/30, H1, spread real descontado.   |
//| EURUSD/USDJPY = reprovados, travados no codigo.                   |
//+------------------------------------------------------------------+
void CarregarCalibragemPorAtivo()
{
   g_ParOperavel = true;

   if(!InpAutoCalibrarPorAtivo)
   {
      g_ADXMinimo    = InpADXMinimo;
      g_VolumeMinimo = InpVolumeMinimo;
      g_RiskPercent  = InpRiskPercent;
      return;
   }

   string sym = _Symbol;
   StringToUpper(sym);

   if(StringFind(sym, "GER40") >= 0)        { g_ADXMinimo = 30.0; g_VolumeMinimo = 1.1; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "BTC") >= 0)     { g_ADXMinimo = 28.0; g_VolumeMinimo = 1.5; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "NZDJPY") >= 0)  { g_ADXMinimo = 35.0; g_VolumeMinimo = 1.3; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "USDCAD") >= 0)  { g_ADXMinimo = 35.0; g_VolumeMinimo = 1.1; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "AUDUSD") >= 0)  { g_ADXMinimo = 35.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "NZDUSD") >= 0)  { g_ADXMinimo = 32.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "GBPUSD") >= 0)  { g_ADXMinimo = 25.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "USDCHF") >= 0)  { g_ADXMinimo = 30.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "EURUSD") >= 0 || StringFind(sym, "USDJPY") >= 0)
   {
      // Testados 16/07/2026 e reprovados - nenhuma combinacao de ADX/Volume
      // deu PF>1 nos dois lados. Grafico pode ficar aberto (visual), mas o
      // motor de tendencia nao abre posicao aqui.
      g_ADXMinimo = 999.0; g_VolumeMinimo = 999.0; g_RiskPercent = 0.0;
      g_ParOperavel = false;
   }
   else
   {
      g_ADXMinimo    = InpADXMinimo;
      g_VolumeMinimo = InpVolumeMinimo;
      g_RiskPercent  = InpRiskPercent;
   }
}

//+------------------------------------------------------------------+
//| Kill switch                                                       |
//+------------------------------------------------------------------+
bool ExecucaoAutorizada()
{
   // No Strategy Tester nao existe conta real nem risco de execucao indevida,
   // e GlobalVariable nao persiste la - sem isso o backtest ficaria travado.
   if(MQLInfoInteger(MQL_TESTER)) return true;
   return GlobalVariableCheck(GV_EXECUCAO_AUTORIZADA) &&
          GlobalVariableGet(GV_EXECUCAO_AUTORIZADA) >= 1.0;
}

//+------------------------------------------------------------------+
//| Magic sequencial: nunca repete, compartilhado por toda a conta.   |
//| CAS atomico (duas instancias liam o mesmo valor antes de escrever)|
//| + piso vindo do historico real (GlobalVariable se perde se o      |
//| terminal for morto a forca, e o contador voltava do zero).        |
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
         if(dealTicket == 0) continue;
         long magic = (long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         if(magic > maiorMagicHistorico) maiorMagicHistorico = magic;
      }
   }

   double atualGV = GlobalVariableCheck(GV_MAGIC_SEQUENCIAL)
                    ? GlobalVariableGet(GV_MAGIC_SEQUENCIAL)
                    : (double)MAGIC_SEQUENCIAL_INICIO;

   if((double)maiorMagicHistorico > atualGV)
   {
      GlobalVariableSet(GV_MAGIC_SEQUENCIAL, (double)maiorMagicHistorico);
      Print("AVISO: contador de magic estava atras do historico real (GV=", atualGV,
            ", historico=", maiorMagicHistorico, ") - corrigido, nao vai recriar numero repetido.");
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

   if(tentativas >= 50)
      Print("AVISO: GerarMagicSequencial nao conseguiu CAS apos 50 tentativas - concorrencia muito alta.");

   return (long)novo;
}

//+------------------------------------------------------------------+
//| Log em texto + CSV estruturado                                    |
//+------------------------------------------------------------------+
string NomePeriodo(ENUM_TIMEFRAMES p)
{
   switch(p)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         return EnumToString(p);
   }
}

void LogRelatorio(string linha)
{
   Print(linha);
   if(g_logFileName == "") return;
   int h = FileOpen(g_logFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, linha);
      FileClose(h);
   }
}

void GarantirCabecalhoSignalsLog()
{
   if(!FileIsExist(g_signalsLogFile, FILE_COMMON))
   {
      int h = FileOpen(g_signalsLogFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
      if(h != INVALID_HANDLE)
      {
         FileWriteString(h, SIGNALS_LOG_HEADER + "\r\n");
         FileClose(h);
      }
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
   // IntegerToString no magic de proposito: %d com long em StringFormat nao e
   // confiavel no MQL5 (long e 64 bits), e o magic so cresce com o tempo.
   string linha = IntegerToString(magic) + ";" +
                  TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ";" +
                  ativo + ";" + tf + ";" + direcao + ";" +
                  DoubleToString(precoEntrada, _Digits) + ";" +
                  DoubleToString(atrValor, 5) + ";" +
                  DoubleToString(sl, _Digits) + ";" +
                  DoubleToString(tp, _Digits) + ";" +
                  setupTipo + ";" + motivo + ";" +
                  DoubleToString(lote, 2) + ";;;;;;;";
   FileWriteString(h, linha + "\r\n");
   FileClose(h);
}

void RegistraSinalFechamento(long magic, double precoFechamento, string motivoSaida,
                             double resultadoPips, double resultadoReais,
                             int barrasDuracao, string status)
{
   if(!FileIsExist(g_signalsLogFile, FILE_COMMON)) return;

   string linhas[];
   int total = 0;
   int h = FileOpen(g_signalsLogFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      string linha = FileReadString(h);
      ArrayResize(linhas, total + 1);
      linhas[total] = linha;
      total++;
   }
   FileClose(h);

   string magicStr = IntegerToString(magic);
   bool achou = false;
   for(int i = 0; i < total; i++)
   {
      string campos[];
      int n = StringSplit(linhas[i], ';', campos);
      if(n >= 12 && campos[0] == magicStr)
      {
         linhas[i] = campos[0] + ";" + campos[1] + ";" + campos[2] + ";" + campos[3] + ";" +
                     campos[4] + ";" + campos[5] + ";" + campos[6] + ";" + campos[7] + ";" +
                     campos[8] + ";" + campos[9] + ";" + campos[10] + ";" + campos[11] + ";" +
                     TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ";" +
                     DoubleToString(precoFechamento, _Digits) + ";" + motivoSaida + ";" +
                     DoubleToString(resultadoPips, 1) + ";" +
                     DoubleToString(resultadoReais, 2) + ";" +
                     IntegerToString(barrasDuracao) + ";" + status;
         achou = true;
         break;
      }
   }

   if(!achou)
   {
      // Nao achou a linha de abertura (CSV apagado no meio do caminho, ou
      // posicao aberta por uma instancia que gravou em outro arquivo).
      // Grava uma linha de fechamento avulsa em vez de perder o resultado.
      ArrayResize(linhas, total + 1);
      linhas[total] = magicStr + ";;" + _Symbol + ";" + NomePeriodo(_Period) +
                      ";;;;;;;;;" +
                      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + ";" +
                      DoubleToString(precoFechamento, _Digits) + ";" + motivoSaida + ";" +
                      DoubleToString(resultadoPips, 1) + ";" +
                      DoubleToString(resultadoReais, 2) + ";" +
                      IntegerToString(barrasDuracao) + ";" + status;
      total++;
   }

   h = FileOpen(g_signalsLogFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   for(int i = 0; i < total; i++)
      FileWriteString(h, linhas[i] + "\r\n");
   FileClose(h);
}

//+------------------------------------------------------------------+
//| Visual: setas de entrada/saida e painel de parecer                |
//+------------------------------------------------------------------+
void DesenhaSetaEntrada(long magic, datetime tempo, double preco, ENUM_POSITION_TYPE lado)
{
   string sufixo = IntegerToString(magic);
   string nome = "TRIVIUM_ENTRADA_" + sufixo;
   ObjectCreate(0, nome, (lado == POSITION_TYPE_BUY) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);

   string rotulo = "TRIVIUM_ENTRADA_TXT_" + sufixo;
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT,
      " ENTRADA " + ((lado == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA") + " #" + sufixo);
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, (lado == POSITION_TYPE_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM);
}

void DesenhaSetaSaida(long magic, datetime tempo, double preco, bool ganho)
{
   string sufixo = IntegerToString(magic);
   string nome = "TRIVIUM_SAIDA_" + sufixo;
   ObjectCreate(0, nome, OBJ_ARROW_CHECK, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);

   string rotulo = "TRIVIUM_SAIDA_TXT_" + sufixo;
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT,
      " SAIDA #" + sufixo + " (" + (ganho ? "GANHO" : "PERDA") + ")");
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, ANCHOR_TOP);
}

// Painel proprio (objeto de texto, nao Comment()) pra nao brigar com o painel
// de outros EAs TRIVIUM/NEXUS no mesmo grafico.
void AtualizaParecer(string texto)
{
   if(ObjectFind(0, PAINEL_NOME) < 0)
   {
      ObjectCreate(0, PAINEL_NOME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_YDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, PAINEL_NOME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(0, PAINEL_NOME, OBJPROP_BACK, false);
   }
   ObjectSetString(0, PAINEL_NOME, OBJPROP_TEXT, "[TRIVIUM369 UNIFICADO]\n" + texto);
}

//+------------------------------------------------------------------+
//| Controle do dia e drawdown local                                  |
//+------------------------------------------------------------------+
void NovoDia()
{
   datetime hoje = iTime(_Symbol, PERIOD_D1, 0);
   if(hoje == diaAtual) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   // B1 - mesma defesa que o STOP_DIARIO.mqh ja fazia: numa reconexao o
   // ACCOUNT_EQUITY pode ler 0 por uma fracao de segundo. Gravar esse 0 como
   // "saldo do inicio do dia" fazia qualquer equity real virar ~100% de perda.
   // Sem leitura valida, adia a virada do dia pro proximo tick.
   if(equity <= 0) return;

   diaAtual       = hoje;
   tradesHoje     = 0;
   saldoInicioDia = equity;
}

bool DrawdownDiarioEstourado()
{
   // B1 - sem essa guarda, saldoInicioDia == 0 gerava divisao por zero (inf),
   // "inf >= 3.0" dava true e o EA se bloqueava o dia inteiro, sem log nenhum.
   if(saldoInicioDia <= 0) return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0) return false; // leitura invalida - nao decide nada neste tick

   double ddPct = (saldoInicioDia - equity) / saldoInicioDia * 100.0;
   return (ddPct >= InpMaxDDPercent);
}

//+------------------------------------------------------------------+
//| Identidade da posicao deste EA (B2 + B3)                          |
//|                                                                    |
//| Ordem de confianca:                                                |
//|  1. Magic guardado na GlobalVariable (sobrevive a reinicio do EA). |
//|  2. Magic em memoria (g_magicAtivo).                               |
//|  3. Comentario "TND " - so plano B, porque corretora reescreve.    |
//|                                                                    |
//| IMPORTANTE: esta funcao NUNCA zera g_magicAtivo. Quem limpa e so o |
//| fechamento em OnTradeTransaction - foi exatamente isso que fazia o |
//| evento de fechamento se perder (B3).                               |
//+------------------------------------------------------------------+
long MagicAtivoPersistido()
{
   if(g_gvMagicAtivo == "") return 0;
   if(!GlobalVariableCheck(g_gvMagicAtivo)) return 0;
   return (long)GlobalVariableGet(g_gvMagicAtivo);
}

void GravarMagicAtivo(long magic)
{
   g_magicAtivo = magic;
   if(g_gvMagicAtivo == "") return;
   if(magic == 0) GlobalVariableDel(g_gvMagicAtivo);
   else           GlobalVariableSet(g_gvMagicAtivo, (double)magic);
}

bool AtualizaEstadoPosicao()
{
   long magicEsperado = (g_magicAtivo != 0) ? g_magicAtivo : MagicAtivoPersistido();

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);

      // 1/2. bate com o magic que sabemos ser nosso
      if(magicEsperado != 0 && magic == magicEsperado)
      {
         if(g_magicAtivo != magic) GravarMagicAtivo(magic);
         g_temPosicao = true;
         return true;
      }

      // 3. plano B: comentario ainda intacto e magic dentro da nossa faixa.
      // So aceita se nao temos magic conhecido, pra nao sequestrar posicao
      // de outra instancia do mesmo EA em outro grafico do mesmo simbolo.
      if(magicEsperado == 0 && magic >= MAGIC_SEQUENCIAL_INICIO)
      {
         string comentario = PositionGetString(POSITION_COMMENT);
         if(StringFind(comentario, COMENTARIO_PREFIXO) == 0)
         {
            GravarMagicAtivo(magic);
            g_temPosicao = true;
            LogRelatorio("Posicao #" + IntegerToString(magic) +
                         " readotada pelo comentario apos reinicio (magic nao estava persistido).");
            return true;
         }
      }
   }

   g_temPosicao = false;
   return false;
}

//+------------------------------------------------------------------+
//| Trailing stop - so aperta o SL, nunca afrouxa. Roda mesmo com o    |
//| stop diario acionado ou execucao nao autorizada: nao abre nada,    |
//| so protege o que ja esta aberto.                                   |
//+------------------------------------------------------------------+
void GerenciaTrailingStop()
{
   if(!InpTrailingAtivo || g_magicAtivo == 0 || !g_temPosicao) return;

   double atr_buf[1];
   if(CopyBuffer(h_atr, 0, 0, 1, atr_buf) < 1) return;
   double atr_now = atr_buf[0];
   if(atr_now <= 0) return;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_magicAtivo) continue;

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
            if(slAtual == 0 || novoSL > slAtual)
            {
               if(trade.PositionModify(tk, novoSL, tpAtual))
                  LogRelatorio("TRAILING #" + IntegerToString((long)tk) + " | " + _Symbol +
                               " | SL -> " + DoubleToString(novoSL, _Digits) +
                               " (lucro " + DoubleToString(lucroDist, _Digits) +
                               ", ATR=" + DoubleToString(atr_now, 5) + ")");
            }
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
            {
               if(trade.PositionModify(tk, novoSL, tpAtual))
                  LogRelatorio("TRAILING #" + IntegerToString((long)tk) + " | " + _Symbol +
                               " | SL -> " + DoubleToString(novoSL, _Digits) +
                               " (lucro " + DoubleToString(lucroDist, _Digits) +
                               ", ATR=" + DoubleToString(atr_now, 5) + ")");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Risco: perdas seguidas reduzem o tamanho da proxima entrada       |
//+------------------------------------------------------------------+
int LossesSeguidosAtual()
{
   if(g_gvLosses == "") return 0;
   return GlobalVariableCheck(g_gvLosses) ? (int)GlobalVariableGet(g_gvLosses) : 0;
}

void RegistrarResultadoRisco(bool ganhou)
{
   if(g_gvLosses == "") return;
   if(ganhou) GlobalVariableSet(g_gvLosses, 0.0);
   else       GlobalVariableSet(g_gvLosses, (double)(LossesSeguidosAtual() + 1));
}

double MultiplicadorRiscoDinamico()
{
   int losses = LossesSeguidosAtual();
   if(losses >= 3) return 0.25;
   if(losses == 2) return 0.50;
   return 1.0;
}

//+------------------------------------------------------------------+
//| Calculo do lote pelo risco%.                                       |
//| Devolve 0 = nao entrar.                                            |
//|                                                                    |
//| Quando o lote pedido pelo risco fica ABAIXO do lote minimo da      |
//| corretora, operar exige arriscar mais do que o configurado. O      |
//| NEXUS369 forcava o lote pra cima calado; aqui o risco real e       |
//| calculado, logado, e se passar de InpRiscoMaxAbsolutoPct a entrada |
//| e recusada. Em conta pequena isso e a diferenca entre arriscar 2%  |
//| e arriscar 15% sem perceber.                                       |
//+------------------------------------------------------------------+
double CalcularLote(double riskPct, double slDistPoints)
{
   if(slDistPoints <= 0) return 0.0;

   double mult = MultiplicadorRiscoDinamico();
   if(mult < 1.0)
      LogRelatorio("RISCO REDUZIDO | " + _Symbol + " | " + IntegerToString(LossesSeguidosAtual()) +
                   " perdas seguidas | risco% " + DoubleToString(riskPct, 2) + " -> " +
                   DoubleToString(riskPct * mult, 2) + " (x" + DoubleToString(mult, 2) + ")");
   riskPct = riskPct * mult;

   double saldo     = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(saldo <= 0 || tickSize <= 0 || tickValue <= 0) return 0.0;

   double valorPorPonto = tickValue * (point / tickSize);
   if(valorPorPonto <= 0) return 0.0;

   double riskMoney = saldo * riskPct / 100.0;
   double lots = riskMoney / (slDistPoints * valorPorPonto);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(stepLot <= 0) stepLot = minLot;
   if(stepLot <= 0) return 0.0;

   double lotsPeloRisco = MathFloor(lots / stepLot) * stepLot;
   double lotsFinal = MathMax(minLot, MathMin(maxLot, lotsPeloRisco));

   if(lotsPeloRisco < minLot)
   {
      double riscoRealMoney = lotsFinal * slDistPoints * valorPorPonto;
      double riscoRealPct   = riscoRealMoney / saldo * 100.0;

      if(riscoRealPct > InpRiscoMaxAbsolutoPct)
      {
         LogRelatorio("ENTRADA RECUSADA POR RISCO | " + _Symbol +
                      " | lote minimo da corretora (" + DoubleToString(minLot, 2) +
                      ") exigiria risco de " + DoubleToString(riscoRealPct, 2) +
                      "% (" + DoubleToString(riscoRealMoney, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) +
                      "), acima do teto de " + DoubleToString(InpRiscoMaxAbsolutoPct, 2) +
                      "%. Saldo insuficiente para operar este ativo com risco controlado.");
         return 0.0;
      }

      LogRelatorio("RISCO ACIMA DO CONFIGURADO | " + _Symbol +
                   " | lote minimo (" + DoubleToString(minLot, 2) +
                   ") forcado | risco% pedido " + DoubleToString(riskPct, 2) +
                   " -> risco% real " + DoubleToString(riscoRealPct, 2) +
                   " (" + DoubleToString(riscoRealMoney, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) + ")");
   }

   return lotsFinal;
}

//+------------------------------------------------------------------+
//| Filtro de medias (periodos e tipos do TRIVIUM_MEDIAS_7)           |
//| Modo 0 = off | 1 = so lado da MA200 | 2 = alinhamento completo    |
//+------------------------------------------------------------------+
bool FiltroMediasConcorda(bool compra, string &motivo)
{
   motivo = "";
   if(InpModoFiltroMedias <= 0) return true;

   double ma7[1], ma21[1], ma50[1], ma200[1];
   if(CopyBuffer(h_ma7,   0, 1, 1, ma7)   < 1) return true; // sem dado, nao bloqueia
   if(CopyBuffer(h_ma21,  0, 1, 1, ma21)  < 1) return true;
   if(CopyBuffer(h_ma50,  0, 1, 1, ma50)  < 1) return true;
   if(CopyBuffer(h_ma200, 0, 1, 1, ma200) < 1) return true;

   double fechamento = iClose(_Symbol, _Period, 1);
   if(fechamento <= 0) return true;

   bool ladoOk = compra ? (fechamento > ma200[0]) : (fechamento < ma200[0]);
   if(!ladoOk)
   {
      motivo = "preco " + DoubleToString(fechamento, _Digits) +
               (compra ? " abaixo" : " acima") + " da MA200 (" + DoubleToString(ma200[0], _Digits) + ")";
      return false;
   }

   if(InpModoFiltroMedias >= 2)
   {
      bool alinhado = compra
                      ? (ma7[0] > ma21[0] && ma21[0] > ma50[0])
                      : (ma7[0] < ma21[0] && ma21[0] < ma50[0]);
      if(!alinhado)
      {
         motivo = "medias sem alinhamento (MA7=" + DoubleToString(ma7[0], _Digits) +
                  " MA21=" + DoubleToString(ma21[0], _Digits) +
                  " MA50=" + DoubleToString(ma50[0], _Digits) + ")";
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| AUTO SL/TP EM POSICAO MANUAL (herdado do TRIVIUM_AUTO_SLTP_EA)    |
//|                                                                    |
//| So mexe em posicao com magic == InpMagicManual (0 = aberta na mao  |
//| pelo Ronei). Nunca toca nas posicoes deste EA nem de outros EAs -  |
//| esses gerenciam o proprio SL/TP.                                   |
//|                                                                    |
//| Le as linhas desenhadas pelo TRIVIUM_DESENHAR_SR ("TRIVIUM_SR_*")  |
//| ou pelo TRIVIUM_PAINEL_COMPLETO ("TRIVIUM_PAINEL_SR*").            |
//+------------------------------------------------------------------+
double AcharNivelSR(double precoRef, bool suporte, string tfFiltro, int rank)
{
   string tag = suporte ? "_SUP" : "_RES";
   // token com o TF junto evita confundir M1 com M15 ("M15_SUP" nao contem "M1_SUP")
   string tokenTF = (tfFiltro != "") ? (tfFiltro + tag) : "";

   double precos[];
   int totalEncontrados = 0;
   int totalObjs = ObjectsTotal(0, 0, -1);

   for(int i = 0; i < totalObjs; i++)
   {
      string nome = ObjectName(0, i, 0, -1);
      bool prefixoOk = (StringFind(nome, "TRIVIUM_SR_") == 0) ||
                       (StringFind(nome, "TRIVIUM_PAINEL_SR") == 0);
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

   // ordena por distancia do preco de referencia (mais proximo primeiro)
   for(int i = 0; i < totalEncontrados - 1; i++)
      for(int j = 0; j < totalEncontrados - i - 1; j++)
      {
         double distJ  = suporte ? (precoRef - precos[j])   : (precos[j]   - precoRef);
         double distJ1 = suporte ? (precoRef - precos[j+1]) : (precos[j+1] - precoRef);
         if(distJ > distJ1)
         {
            double tmp = precos[j];
            precos[j] = precos[j+1];
            precos[j+1] = tmp;
         }
      }

   int idx = rank - 1;
   if(idx < 0 || idx >= totalEncontrados) return 0;
   return precos[idx];
}

datetime UltimoAvisoDoTicket(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_alertaTickets); i++)
      if(g_alertaTickets[i] == ticket) return g_alertaUltimoAviso[i];
   return 0;
}

void RegistrarAviso(ulong ticket, datetime quando)
{
   for(int i = 0; i < ArraySize(g_alertaTickets); i++)
      if(g_alertaTickets[i] == ticket)
      {
         g_alertaUltimoAviso[i] = quando;
         return;
      }

   int n = ArraySize(g_alertaTickets);
   ArrayResize(g_alertaTickets, n + 1);
   ArrayResize(g_alertaUltimoAviso, n + 1);
   g_alertaTickets[n] = ticket;
   g_alertaUltimoAviso[n] = quando;
}

void ProcessarPosicoesManuais()
{
   double stopLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double margem    = InpMargemExtraPts * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicManual) continue;

      double slAtual = PositionGetDouble(POSITION_SL);
      double tpAtual = PositionGetDouble(POSITION_TP);
      if(slAtual != 0 && tpAtual != 0) continue; // ja protegida dos dois lados

      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double precoAbertura = PositionGetDouble(POSITION_PRICE_OPEN);
      double precoAtual = (tipo == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                          : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      datetime abertaEm = (datetime)PositionGetInteger(POSITION_TIME);

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
      else
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
            LogRelatorio("AUTO_SLTP: posicao manual #" + IntegerToString((long)ticket) +
                         " SL=" + DoubleToString(novoSL, _Digits) +
                         " TP=" + DoubleToString(novoTP, _Digits) + " definidos por S/R");
         else
            LogRelatorio("AUTO_SLTP: falha ao modificar #" + IntegerToString((long)ticket) +
                         " - erro " + IntegerToString(GetLastError()));
      }

      // Ainda sem protecao (nenhuma linha de S/R util, ou nivel rejeitado pelo
      // stopLevel da corretora). Nao pode ficar calado: posicao manual sem stop
      // e perda ilimitada num black swan.
      if(novoSL == 0 || novoTP == 0)
      {
         datetime agora = TimeCurrent();
         if(agora - UltimoAvisoDoTicket(ticket) >= InpAlertaIntervaloMin * 60)
         {
            string faltando = (novoSL == 0 && novoTP == 0) ? "SL e TP" : ((novoSL == 0) ? "SL" : "TP");
            int minutosAberta = (abertaEm > 0) ? (int)((agora - abertaEm) / 60) : 0;
            string msg = "TRIVIUM369: posicao manual #" + IntegerToString((long)ticket) +
                         " (" + _Symbol + ") SEM " + faltando + " ha " +
                         IntegerToString(minutosAberta) +
                         " min - nenhuma linha de S/R valida encontrada, protecao pendente.";
            Alert(msg);
            LogRelatorio(msg);
            RegistrarAviso(ticket, agora);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MOTOR DE ENTRADA (tendencia)                                      |
//+------------------------------------------------------------------+
void ProcessarMotorTendencia()
{
   if(!g_ParOperavel) return;           // par testado e reprovado
   if(tradesHoje >= InpMaxTradesDia) return;
   if(g_temPosicao) return;             // uma posicao por vez neste simbolo

   if(InpFiltroSessaoAtivo)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < InpSessaoInicioHora || dt.hour >= InpSessaoFimHora) return;
   }

   // decide uma vez por barra (logica de fechamento de barra)
   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == lastSignalBarTime) return;
   lastSignalBarTime = curBar;
   barsSinceLastSignal++;
   if(barsSinceLastSignal < InpBarrasMinEntreSinais) return;

   double adx_buf[1], plus_di[1], minus_di[1], atr_buf[1];
   if(CopyBuffer(h_adx, 0, 1, 1, adx_buf)  < 1) return;
   if(CopyBuffer(h_adx, 1, 1, 1, plus_di)  < 1) return;
   if(CopyBuffer(h_adx, 2, 1, 1, minus_di) < 1) return;
   if(CopyBuffer(h_atr, 0, 1, 1, atr_buf)  < 1) return;

   double adx_val = adx_buf[0];
   double plusDI  = plus_di[0];
   double minusDI = minus_di[0];
   double atr_val = atr_buf[0];

   if(adx_val <= g_ADXMinimo) return;
   if(atr_val <= 0) return;

   // volume: participacao real, nao ruido
   long vol_buf[];
   ArraySetAsSeries(vol_buf, true);
   if(CopyTickVolume(_Symbol, _Period, 1, InpVolumePeriod + 1, vol_buf) < InpVolumePeriod + 1) return;
   double vol_avg = 0;
   for(int i = 1; i <= InpVolumePeriod; i++) vol_avg += (double)vol_buf[i];
   vol_avg /= InpVolumePeriod;
   if(vol_avg <= 0) return;
   double vol_atual = (double)vol_buf[0];
   if(vol_atual <= vol_avg * g_VolumeMinimo) return;

   string side = "";
   if(plusDI > minusDI)       side = "BUY";
   else if(minusDI > plusDI)  side = "SELL";
   else return;

   bool compra = (side == "BUY");

   // filtro de medias (TRIVIUM_MEDIAS_7 nativo)
   string motivoMedias = "";
   if(!FiltroMediasConcorda(compra, motivoMedias))
   {
      LogRelatorio("SINAL REJEITADO POR MEDIAS | " + _Symbol + " | " + side + " | " + motivoMedias);
      return;
   }

   // filtro anti-chop: o timeframe maior precisa concordar com a direcao.
   // Sem isso o EA compra E vende o mesmo par em poucas horas num range,
   // as duas batendo stop (achado ao vivo em USDCAD, 16/07/2026).
   if(InpFiltroAntiChopAtivo)
   {
      double adx2[1], plus2[1], minus2[1];
      if(CopyBuffer(h_adx_anti_chop, 0, 1, 1, adx2)   < 1) return;
      if(CopyBuffer(h_adx_anti_chop, 1, 1, 1, plus2)  < 1) return;
      if(CopyBuffer(h_adx_anti_chop, 2, 1, 1, minus2) < 1) return;

      bool tfMaiorConcorda = false;
      if(adx2[0] > InpAntiChopADXMinimo)
      {
         if(compra  && plus2[0]  > minus2[0]) tfMaiorConcorda = true;
         if(!compra && minus2[0] > plus2[0])  tfMaiorConcorda = true;
      }

      if(!tfMaiorConcorda)
      {
         LogRelatorio("SINAL REJEITADO POR ANTI-CHOP | " + _Symbol + " | " + NomePeriodo(_Period) +
                      " pede " + side + ", mas " + EnumToString(InpAntiChopTimeframe) +
                      " nao concorda (ADX=" + DoubleToString(adx2[0], 1) +
                      " +DI=" + DoubleToString(plus2[0], 1) +
                      " -DI=" + DoubleToString(minus2[0], 1) + ")");
         return;
      }
   }

   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) return;

   // filtro de spread: spread anomalo (ja visto 8 -> 70 pontos) comia ate um
   // terco do orcamento de risco antes do preco andar.
   if(InpFiltroSpreadAtivo)
   {
      double spread_atual   = ask - bid;
      double stop_dist      = InpStopATRMult * atr_val;
      double spread_pct     = (stop_dist > 0) ? (spread_atual / stop_dist * 100.0) : 999.0;
      if(spread_pct > InpMaxSpreadATRPct)
      {
         LogRelatorio("SINAL REJEITADO POR SPREAD | " + _Symbol +
                      " | spread=" + DoubleToString(spread_atual, _Digits) +
                      " (" + DoubleToString(spread_pct, 1) + "% do stop, limite " +
                      DoubleToString(InpMaxSpreadATRPct, 1) + "%) | " + side);
         return;
      }
   }

   string tf = NomePeriodo(_Period);
   // corretora costuma truncar o comentario em ~31 caracteres
   string comentario = COMENTARIO_PREFIXO + tf + " ADX" + DoubleToString(adx_val, 0) +
                       " V" + DoubleToString(vol_atual / vol_avg, 1) + "x " + side;
   if(StringLen(comentario) > 31) comentario = StringSubstr(comentario, 0, 31);

   string motivo = "ADX=" + DoubleToString(adx_val, 1) + " (min " + DoubleToString(g_ADXMinimo, 1) +
                   ") tendencia " + (compra ? "de alta" : "de baixa") +
                   ", Volume=" + DoubleToString(vol_atual / vol_avg, 2) + "x media (min " +
                   DoubleToString(g_VolumeMinimo, 1) + "x), +DI=" + DoubleToString(plusDI, 1) +
                   " -DI=" + DoubleToString(minusDI, 1) +
                   ", medias e " + EnumToString(InpAntiChopTimeframe) + " de acordo";

   double entry = compra ? ask : bid;
   double sl    = compra ? (entry - InpStopATRMult * atr_val) : (entry + InpStopATRMult * atr_val);
   double tp    = compra ? (entry + InpAlvoATRMult * atr_val) : (entry - InpAlvoATRMult * atr_val);
   double slDistPoints = MathAbs(entry - sl) / point;

   double lots = CalcularLote(g_RiskPercent, slDistPoints);
   if(lots <= 0) return; // recusado (risco acima do teto ou dado invalido)

   long novoMagic = GerarMagicSequencial();
   trade.SetExpertMagicNumber(novoMagic);

   bool ok = compra ? trade.Buy(lots, _Symbol, entry, sl, tp, comentario)
                    : trade.Sell(lots, _Symbol, entry, sl, tp, comentario);
   if(!ok)
   {
      LogRelatorio("FALHA AO ABRIR " + side + " | " + _Symbol +
                   " | erro " + IntegerToString(trade.ResultRetcode()) +
                   " (" + trade.ResultRetcodeDescription() + ")");
      return;
   }

   // Grava o magic ANTES de qualquer outra coisa: e ele que identifica a
   // posicao como nossa daqui pra frente, inclusive apos reinicio do EA.
   GravarMagicAtivo(novoMagic);
   g_temPosicao = true;
   tempoAberturaPosicaoAtual = curBar;
   precoAberturaPosicaoAtual = entry;
   ladoPosicaoAtual = compra ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   tradesHoje++;
   barsSinceLastSignal = 0;

   RegistraSinalAbertura(novoMagic, _Symbol, tf, side, entry, atr_val, sl, tp,
                         InpSetupTipo, motivo, lots);

   LogRelatorio("ENTRADA Magic=" + IntegerToString(novoMagic) + " | " + _Symbol + " " + tf +
                " " + side + " | " + motivo +
                " | entrada=" + DoubleToString(entry, _Digits) +
                " | stop=" + DoubleToString(sl, _Digits) + " (" + DoubleToString(InpStopATRMult, 1) + " ATR)" +
                " | alvo=" + DoubleToString(tp, _Digits) + " (" + DoubleToString(InpAlvoATRMult, 1) + " ATR)" +
                " | ATR=" + DoubleToString(atr_val, 5) +
                " | lote=" + DoubleToString(lots, 2));

   DesenhaSetaEntrada(novoMagic, curBar, entry, ladoPosicaoAtual);
   AtualizaParecer("ULTIMA ORDEM\n" + _Symbol + " | " + (compra ? "COMPRA" : "VENDA") +
                   " #" + IntegerToString(novoMagic) +
                   "\nEntrada: " + DoubleToString(entry, _Digits) +
                   " | Stop: " + DoubleToString(sl, _Digits) +
                   " | Alvo: " + DoubleToString(tp, _Digits) +
                   "\nLote: " + DoubleToString(lots, 2) + "\nMotivo: " + motivo);
}

//+------------------------------------------------------------------+
//| FECHAMENTO - registro do resultado                                |
//|                                                                    |
//| Dois caminhos chegam aqui:                                         |
//|  1. OnTradeTransaction (normal, em tempo real);                    |
//|  2. ReconciliarFechamentoPerdido (rede de seguranca, se o evento   |
//|     nao chegou - terminal reiniciado no meio do fechamento, EA     |
//|     reanexado depois, etc).                                        |
//|                                                                    |
//| Quem chama PRECISA ter "reivindicado" o magic antes (chamado       |
//| GravarMagicAtivo(0)), pra que o outro caminho veja 0 e nao conte a |
//| mesma perda duas vezes - contar duas vezes reduziria o risco mais  |
//| do que devia, o que tambem e errado.                               |
//+------------------------------------------------------------------+
void ProcessarFechamento(long magic, double precoSaida, double profit,
                         long posicaoId, string origem)
{
   bool   ganhou    = (profit >= 0);
   string status    = ganhou ? "GANHO" : "PERDA";
   string resultado = ganhou ? "GANHO (bateu o alvo)" : "PERDA (bateu o stop)";

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double resultadoPips = 0;
   if(point > 0 && precoAberturaPosicaoAtual > 0)
      resultadoPips = (ladoPosicaoAtual == POSITION_TYPE_BUY)
                      ? (precoSaida - precoAberturaPosicaoAtual) / point
                      : (precoAberturaPosicaoAtual - precoSaida) / point;

   int barrasDuracao = (tempoAberturaPosicaoAtual > 0)
                       ? (int)iBarShift(_Symbol, _Period, tempoAberturaPosicaoAtual)
                       : -1;

   RegistraSinalFechamento(magic, precoSaida, "SL_ou_TP", resultadoPips,
                           profit, barrasDuracao, status);
   // Coracao da reducao dinamica de risco. Perder esta chamada (bug B3)
   // significava nunca contar as perdas seguidas - a protecao existia no
   // codigo mas nunca ligava na pratica.
   RegistrarResultadoRisco(ganhou);

   LogRelatorio("FECHAMENTO (" + origem + ") posicao=" + IntegerToString(posicaoId) +
                " Magic=" + IntegerToString(magic) + " | " + _Symbol +
                " | saida=" + DoubleToString(precoSaida, _Digits) +
                " | " + resultado +
                " | P&L=" + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) +
                " | perdas seguidas agora: " + IntegerToString(LossesSeguidosAtual()));

   DesenhaSetaSaida(magic, TimeCurrent(), precoSaida, ganhou);
   AtualizaParecer("ULTIMA ORDEM\n" + _Symbol + " | FECHADA #" + IntegerToString(magic) +
                   "\nSaida: " + DoubleToString(precoSaida, _Digits) + " | " + resultado +
                   "\nP&L: " + DoubleToString(profit, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY) +
                   " | Pips: " + DoubleToString(resultadoPips, 1));

   g_temPosicao = false;
   tempoAberturaPosicaoAtual = 0;
   precoAberturaPosicaoAtual = 0;
}

//+------------------------------------------------------------------+
//| Rede de seguranca do B3: temos magic registrado mas a posicao nao  |
//| existe mais e o evento de fechamento nunca chegou. Procura o deal  |
//| de saida no historico real da corretora (que nunca se perde) e     |
//| registra o resultado, pra que a contagem de perdas seguidas nao    |
//| fique furada.                                                      |
//+------------------------------------------------------------------+
void ReconciliarFechamentoPerdido()
{
   if(g_magicAtivo == 0 || g_temPosicao) return;

   long magic = g_magicAtivo;

   // janela curta: um fechamento perdido e sempre recente
   datetime desde = TimeCurrent() - 7 * 24 * 60 * 60;
   if(!HistorySelect(desde, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != magic) continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                      HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                      HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double precoSaida = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      long   posicaoId  = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

      GravarMagicAtivo(0); // reivindica ANTES de processar (evita contar 2x)
      ProcessarFechamento(magic, precoSaida, profit, posicaoId, "reconciliado do historico");
      return;
   }

   // Sem posicao aberta E sem deal de saida no historico: registro orfao
   // (ex: magic gravado e o terminal caiu antes da ordem existir de fato).
   // Limpa pra nao ficar varrendo o historico a cada tick.
   LogRelatorio("AVISO: magic #" + IntegerToString(magic) +
                " nao tem posicao aberta nem deal de saida no historico recente - registro limpo.");
   GravarMagicAtivo(0);
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   string sym = _Symbol;
   StringToUpper(sym);

   CarregarCalibragemPorAtivo();

   bool escopoValido = (StringFind(sym,"GER40")>=0  || StringFind(sym,"BTC")>=0    ||
                        StringFind(sym,"NZDJPY")>=0 || StringFind(sym,"USDCAD")>=0 ||
                        StringFind(sym,"AUDUSD")>=0 || StringFind(sym,"NZDUSD")>=0 ||
                        StringFind(sym,"GBPUSD")>=0 || StringFind(sym,"USDCHF")>=0);
   if(!escopoValido)
   {
      Print("AVISO: o motor de tendencia so foi validado em GER40, BTCUSD, NZDJPY, USDCAD, AUDUSD, NZDUSD, GBPUSD, USDCHF.");
      Print("Rodando em ", sym, " - fora do escopo testado. Nao operar aqui sem novo backtest.");
   }
   if(!g_ParOperavel)
      Print("AVISO: ", sym, " foi testado e REPROVADO (16/07/2026) - grafico fica so visual, o motor nao abre posicao aqui.");

   h_adx = iADX(_Symbol, _Period, InpADXPeriod);
   h_atr = iATR(_Symbol, _Period, InpATRPeriod);
   if(h_adx == INVALID_HANDLE || h_atr == INVALID_HANDLE)
   {
      Print("Erro ao criar handles ADX/ATR: ", GetLastError());
      return INIT_FAILED;
   }

   if(InpFiltroAntiChopAtivo)
   {
      h_adx_anti_chop = iADX(_Symbol, InpAntiChopTimeframe, InpADXPeriod);
      if(h_adx_anti_chop == INVALID_HANDLE)
      {
         Print("Erro ao criar handle ADX anti-chop (", EnumToString(InpAntiChopTimeframe), "): ", GetLastError());
         return INIT_FAILED;
      }
   }

   if(InpModoFiltroMedias > 0)
   {
      // mesmos periodos/tipos do TRIVIUM_MEDIAS_7: rapidas EMA, longas SMMA
      h_ma7   = iMA(_Symbol, _Period, 7,   0, MODE_EMA,  PRICE_CLOSE);
      h_ma21  = iMA(_Symbol, _Period, 21,  0, MODE_EMA,  PRICE_CLOSE);
      h_ma50  = iMA(_Symbol, _Period, 50,  0, MODE_SMMA, PRICE_CLOSE);
      h_ma200 = iMA(_Symbol, _Period, 200, 0, MODE_SMMA, PRICE_CLOSE);
      if(h_ma7 == INVALID_HANDLE || h_ma21 == INVALID_HANDLE ||
         h_ma50 == INVALID_HANDLE || h_ma200 == INVALID_HANDLE)
      {
         Print("Erro ao criar handles das medias: ", GetLastError());
         return INIT_FAILED;
      }
   }

   trade.SetDeviationInPoints(30);

   long contaLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   g_logFileName    = "TRIVIUM369_UNIFICADO_RELATORIO_" + sym + "_" + IntegerToString(contaLogin) + ".txt";
   g_signalsLogFile = "TRIVIUM369_SIGNALS_LOG_" + IntegerToString(contaLogin) + ".csv";
   g_gvLosses       = GV_LOSSES_PREFIX + IntegerToString(contaLogin) + "_" + sym;
   g_gvMagicAtivo   = GV_MAGIC_ATIVO_PREFIX + IntegerToString(contaLogin) + "_" + sym;

   GarantirContadorMagicNuncaRetrocede();

   // Recupera a posicao viva (se o EA foi reiniciado com posicao aberta).
   g_magicAtivo = MagicAtivoPersistido();
   AtualizaEstadoPosicao();
   // Se fechou enquanto o EA estava desligado, o resultado ainda precisa
   // entrar na contagem de perdas seguidas - por isso reconcilia, em vez de
   // simplesmente descartar o registro.
   ReconciliarFechamentoPerdido();

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   saldoInicioDia = (equity > 0) ? equity : 0; // 0 = ainda invalido, NovoDia() resolve
   diaAtual   = iTime(_Symbol, PERIOD_D1, 0);
   tradesHoje = 0;

   LogRelatorio("=== INIT " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + " | " +
                sym + " " + NomePeriodo(_Period) +
                " | ADX>" + DoubleToString(g_ADXMinimo, 1) +
                " Vol>" + DoubleToString(g_VolumeMinimo, 1) + "x" +
                " | SL=" + DoubleToString(InpStopATRMult, 1) + "xATR" +
                " TP=" + DoubleToString(InpAlvoATRMult, 1) + "xATR" +
                " | Risco=" + DoubleToString(g_RiskPercent, 1) + "%" +
                " (teto " + DoubleToString(InpRiscoMaxAbsolutoPct, 1) + "%)" +
                " | Medias=modo " + IntegerToString(InpModoFiltroMedias) +
                " | Calibragem=" + (InpAutoCalibrarPorAtivo ? "AUTOMATICA" : "MANUAL") +
                " | EXECUCAO=" + (ExecucaoAutorizada() ? "AUTORIZADA" : "AGUARDANDO 'pode rodar' do Ronei") + " ===");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_adx != INVALID_HANDLE)           IndicatorRelease(h_adx);
   if(h_atr != INVALID_HANDLE)           IndicatorRelease(h_atr);
   if(h_adx_anti_chop != INVALID_HANDLE) IndicatorRelease(h_adx_anti_chop);
   if(h_ma7 != INVALID_HANDLE)           IndicatorRelease(h_ma7);
   if(h_ma21 != INVALID_HANDLE)          IndicatorRelease(h_ma21);
   if(h_ma50 != INVALID_HANDLE)          IndicatorRelease(h_ma50);
   if(h_ma200 != INVALID_HANDLE)         IndicatorRelease(h_ma200);
   ObjectDelete(0, PAINEL_NOME);
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//|                                                                    |
//| Ordem das guardas (da mais ampla pra mais especifica):             |
//|  proteger o que ja esta aberto  -> sempre                          |
//|  kill switch                    -> so Ronei libera                 |
//|  stop diario   (CONTA INTEIRA)  -> 10% de equity                   |
//|  guarda margem (CONTA INTEIRA)  -> nivel < 150%                    |
//|  drawdown local (este EA)       -> defesa em profundidade          |
//+------------------------------------------------------------------+
void OnTick()
{
   NovoDia();

   // Estado da posicao ANTES do trailing: o trailing depende de saber qual e
   // a posicao viva; se rodasse antes, ficava cego por um tick apos reinicio.
   AtualizaEstadoPosicao();
   // Se a posicao sumiu e o evento de fechamento nao chegou, busca o resultado
   // no historico (senao a contagem de perdas seguidas fica furada - ver B3).
   ReconciliarFechamentoPerdido();
   GerenciaTrailingStop();

   // Protecao de posicao MANUAL roda mesmo sem autorizacao de execucao e
   // mesmo com stop diario batido: nao abre nada, so coloca stop no que ja
   // esta aberto na mao. Deixar posicao manual sem SL e o risco maior aqui.
   if(InpAutoSLTPManualAtivo) ProcessarPosicoesManuais();

   if(!InpMotorTendenciaAtivo) return;
   if(!ExecucaoAutorizada())   return;  // KILL SWITCH
   if(StopDiario_Bloqueado())  return;  // stop diario de CONTA INTEIRA (10% equity)
   if(MargemBloqueada())       return;  // guarda de margem de CONTA INTEIRA (<150%)
   if(DrawdownDiarioEstourado()) return; // guarda local deste EA/simbolo

   ProcessarMotorTendencia();
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - caminho normal do fechamento                 |
//|                                                                    |
//| B3: a guarda antiga era "if(magicAtual == 0) return;", e magicAtual|
//| ja tinha sido zerado pela varredura de posicoes no OnTick, entao o |
//| evento inteiro era descartado. Agora g_magicAtivo so e limpo nos   |
//| caminhos de fechamento, nunca pela varredura.                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   long magic = g_magicAtivo;
   if(magic == 0) return; // ja processado (ou nada nosso aberto)

   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != magic) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double precoSaida = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   long   posicaoId  = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   GravarMagicAtivo(0); // reivindica ANTES de processar (evita contar 2x)
   ProcessarFechamento(magic, precoSaida, profit, posicaoId, "evento");
}

//+------------------------------------------------------------------+
//| OnTester - metricas do backtest numa linha de CSV                 |
//+------------------------------------------------------------------+
double OnTester()
{
   double deposito    = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double lucro       = TesterStatistics(STAT_PROFIT);
   double retornoPct  = (deposito > 0) ? (lucro / deposito * 100.0) : 0.0;
   double ddPct       = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double pf          = TesterStatistics(STAT_PROFIT_FACTOR);
   double trades      = TesterStatistics(STAT_TRADES);
   double vencedores  = TesterStatistics(STAT_PROFIT_TRADES);
   double winRatePct  = (trades > 0) ? (vencedores / trades * 100.0) : 0.0;
   double seqMaxPerdas = TesterStatistics(STAT_CONLOSSMAX_TRADES);
   double margemMin    = TesterStatistics(STAT_MIN_MARGINLEVEL);
   double equityMin    = TesterStatistics(STAT_EQUITYMIN);

   int h = FileOpen("TRIVIUM369_BACKTEST_RESULTADOS.csv", FILE_READ|FILE_WRITE|FILE_ANSI|FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      if(FileSize(h) == 0)
         FileWriteString(h, "ea;simbolo;timeframe;sessao_filtro;modo_medias;risco_pct;leverage_conta;deposito;retorno_pct;drawdown_max_pct;profit_factor;win_rate_pct;seq_max_perdas;margem_minima_pct;equity_minima;total_trades\r\n");

      FileWriteString(h, "TRIVIUM369_UNIFICADO;" + _Symbol + ";" + EnumToString(_Period) + ";" +
                         (InpFiltroSessaoAtivo ? "NY" : "24h") + ";" +
                         IntegerToString(InpModoFiltroMedias) + ";" +
                         DoubleToString(g_RiskPercent, 1) + ";" +
                         IntegerToString(AccountInfoInteger(ACCOUNT_LEVERAGE)) + ";" +
                         DoubleToString(deposito, 2) + ";" +
                         DoubleToString(retornoPct, 2) + ";" +
                         DoubleToString(ddPct, 2) + ";" +
                         DoubleToString(pf, 2) + ";" +
                         DoubleToString(winRatePct, 2) + ";" +
                         IntegerToString((int)seqMaxPerdas) + ";" +
                         DoubleToString(margemMin, 2) + ";" +
                         DoubleToString(equityMin, 2) + ";" +
                         IntegerToString((int)trades) + "\r\n");
      FileClose(h);
   }

   return retornoPct;
}
//+------------------------------------------------------------------+
