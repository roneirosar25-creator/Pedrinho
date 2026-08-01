//+------------------------------------------------------------------+
//| NEXUS369_TREND_VALIDADO.mq5                                      |
//| TRIVIUM369 (c) 2026 - GER40 e BTCUSD - unico edge validado        |
//|                                                                   |
//| Pedrinho, madrugada 06-07 JUL 2026                                |
//| VALIDACAO: 20 janelas de tempo sequenciais, teste out-of-sample,  |
//| teste de significancia estatistica (Z>3.7, >99% confianca),       |
//| robustez confirmada em 9 variacoes vizinhas de SL/TP.             |
//|                                                                   |
//| NAO GENERALIZA para outros ativos - testado e descartado em       |
//| COPPER, GOLD, SILVER, USD.indx, USA500, EURUSD e outros 9 pares.  |
//| So usar em GER40 e BTCUSD.                                        |
//|                                                                   |
//| LOGICA (tendencia, nao reversao):                                 |
//|  - ADX(14) > 25 (tendencia confirmada)                            |
//|  - Volume > 1.2x media(20) (participacao real, nao ruido)         |
//|  - Direcao = +DI vs -DI                                           |
//|  - Stop = 2.0x ATR(14), Alvo = 1.5x ATR(14) (alvo MENOR que       |
//|    o stop de proposito - compensado pelo acerto alto ~60-70%)     |
//|                                                                   |
//| REGIME DE AUTONOMIA (revisado 07/07/2026, ver CLAUDE.md):         |
//| Compilar e ANEXAR no grafico = livre (fica pronto, parado).       |
//| AUTORIZAR EXECUCAO DE VERDADE = exige "pode rodar" do Ronei.      |
//| Controlado pelo kill switch GV_EXECUCAO_AUTORIZADA abaixo -       |
//| desligado por padrao, o EA fica montado mas nunca abre posicao.   |
//|                                                                   |
//| REFINO POR ATIVO (treino/teste 70/30, so aceito o que ficou       |
//| positivo nos dois lados):                                         |
//|  GER40:  InpADXMinimo=30.0  InpVolumeMinimo=1.1  (vs default 25/1.2)|
//|  BTCUSD: InpADXMinimo=28.0  InpVolumeMinimo=1.5  (vs default 25/1.2)|
//|          BTCUSD com refino: teste ficou IGUAL/MELHOR que treino    |
//|          (+0.170 vs +0.163 ATR) - forte sinal contra overfitting.  |
//| Ajustar os inputs abaixo por grafico/ativo antes de operar.        |
//|                                                                    |
//| 09/07/2026 - 4 novos ativos calibrados (validacao mais simples:    |
//| treino/teste 70/30, sessao NY 09-18h BRT, spread real descontado,  |
//| PF>1 nos dois lados - MENOS rigoroso que Z>3.7 do GER40/BTCUSD,     |
//| mas dado real). Unicos que cabem no capital real (saldo US$35-74): |
//|  NZDJPY: InpADXMinimo=35.0  InpVolumeMinimo=1.3                    |
//|  USDCAD: InpADXMinimo=35.0  InpVolumeMinimo=1.1                    |
//|  AUDUSD: InpADXMinimo=35.0  InpVolumeMinimo=1.5                    |
//|  NZDUSD: InpADXMinimo=32.0  InpVolumeMinimo=1.5                    |
//| InpRiskPercent=2.0 para esses 4 (nao 1.0) - calibrado pro capital  |
//| pequeno, ver 03_SESSOES/ para a analise completa de viabilidade.   |
//|                                                                    |
//| 16/07/2026 - 4 pares majores testados (pedido do Ronei, mesma      |
//| metodologia 70/30, H1, 8000 barras, spread real descontado):       |
//|  GBPUSD: APROVADO  InpADXMinimo=25.0  InpVolumeMinimo=1.5          |
//|  USDCHF: APROVADO  InpADXMinimo=30.0  InpVolumeMinimo=1.5          |
//|  EURUSD: REPROVADO - nenhuma combinacao deu PF>1 nos dois lados    |
//|          (confirma rejeicao anterior, ver linha 11 acima)          |
//|  USDJPY: REPROVADO - nenhuma combinacao deu PF>1 nos dois lados    |
//| EURUSD/USDJPY ficam BLOQUEADOS (g_ParOperavel=false) mesmo se o    |
//| grafico for aberto - protecao no codigo, nao so documentacao.      |
//|                                                                    |
//| 14/07/2026 - AUTO-CALIBRAGEM POR ATIVO (pedido do Ronei): os 3     |
//| valores acima (ADXMinimo/VolumeMinimo/RiskPercent) agora sao       |
//| escolhidos sozinhos pelo simbolo do grafico (CarregarCalibragem-   |
//| PorAtivo, chamada no OnInit) - nao precisa mais de preset .set     |
//| nem digitar valor manual por conta/grafico. Um unico .ex5 se       |
//| auto-configura em qualquer conta/corretora. Desligar               |
//| InpAutoCalibrarPorAtivo so pra testar ativo novo fora da tabela.   |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.05"
#include <Trade\Trade.mqh>
#include <TRIVIUM\STOP_DIARIO.mqh>

// v1.02 (07/07/2026): Magic Number trocado de hash-por-simbolo para
// SEQUENCIAL COMPARTILHADO (Opcao B, decidido Cladio+Pedrinho, ver
// 00_NUCLEO/LOG_DECISOES_CLAUDIO.md 07:15 e 09:xx). Cada posicao aberta
// ganha um Magic proprio, nunca reutilizado. A verdade de cada sinal
// (ativo, timeframe, setup, motivo, ATR, SL/TP, resultado) vai para
// 04_DADOS_MERCADO/TRIVIUM369_SIGNALS_LOG.csv, nao para o numero do Magic.

input group "=== Auto-calibragem por ativo (novo 14/07/2026) ==="
// Quando true (padrao), ADX minimo / Volume minimo / Risco% sao escolhidos
// automaticamente pelo simbolo do grafico (tabela em CarregarCalibragemPorAtivo),
// dispensando presets .set manuais - um unico EA/.ex5 se auto-configura em
// qualquer conta. Desligar so se quiser forcar os valores manuais abaixo
// (util pra testar um ativo novo fora da tabela).
input bool   InpAutoCalibrarPorAtivo = true;

input group "=== Filtro de Tendencia (usado so se auto-calibragem = false) ==="
input int    InpADXPeriod     = 14;
input double InpADXMinimo     = 25.0;   // ADX minimo p/ tendencia confirmada (manual)
input int    InpVolumePeriod  = 20;
input double InpVolumeMinimo  = 1.2;    // Volume > media * este fator (manual)

input group "=== Stop/Alvo (validado - NAO mudar sem novo teste) ==="
input int    InpATRPeriod     = 14;
input double InpStopATRMult   = 2.0;    // Stop = 2.0x ATR (validado)
input double InpAlvoATRMult   = 1.5;    // Alvo = 1.5x ATR (MENOR que o stop de proposito)
input int    InpBarrasMinEntreSinais = 10; // Evita cluster de sinais

input group "=== Gestao de Risco (Risco% usado so se auto-calibragem = false) ==="
input double InpRiskPercent   = 1.0;    // manual - ignorado se auto-calibragem = true
input double InpMaxDDPercent  = 3.0;
input int    InpMaxTradesDia  = 5;

// Valores efetivos usados pelo EA - vem da tabela de auto-calibragem (se ligada)
// ou dos inputs manuais acima (se desligada). Sempre usar estas, nunca Inp* direto
// no corpo da logica, exceto dentro de CarregarCalibragemPorAtivo/OnInit.
double g_ADXMinimo;
double g_VolumeMinimo;
double g_RiskPercent;
bool   g_ParOperavel = true; // 16/07/2026 - false trava entrada mesmo com grafico aberto (par testado e reprovado)

//+------------------------------------------------------------------+
// Tabela de calibragem por ativo (mesmos valores documentados no cabecalho
// do arquivo, linhas 27-44). GER40/BTCUSD = validacao rigorosa (Z>3.7).
// NZDJPY/USDCAD/AUDUSD/NZDUSD = validacao 09/07/2026 (treino/teste 70/30).
// Simbolo fora da tabela cai no default via Inp* manuais (com aviso no OnInit).
//+------------------------------------------------------------------+
void CarregarCalibragemPorAtivo()
{
   if(!InpAutoCalibrarPorAtivo)
   {
      g_ADXMinimo    = InpADXMinimo;
      g_VolumeMinimo = InpVolumeMinimo;
      g_RiskPercent  = InpRiskPercent;
      return;
   }

   string sym = _Symbol; StringToUpper(sym);
   g_ParOperavel = true;

   if(StringFind(sym, "GER40") >= 0)        { g_ADXMinimo = 30.0; g_VolumeMinimo = 1.1; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "BTC") >= 0)     { g_ADXMinimo = 28.0; g_VolumeMinimo = 1.5; g_RiskPercent = 1.0; }
   else if(StringFind(sym, "NZDJPY") >= 0)  { g_ADXMinimo = 35.0; g_VolumeMinimo = 1.3; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "USDCAD") >= 0)  { g_ADXMinimo = 35.0; g_VolumeMinimo = 1.1; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "AUDUSD") >= 0)  { g_ADXMinimo = 35.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "NZDUSD") >= 0)  { g_ADXMinimo = 32.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   // 16/07/2026 - calibragem dos 4 pares majores novos (backtest treino/teste
   // 70/30, H1, 8000 barras, spread real descontado, sessao NY 09-18h):
   else if(StringFind(sym, "GBPUSD") >= 0)  { g_ADXMinimo = 25.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "USDCHF") >= 0)  { g_ADXMinimo = 30.0; g_VolumeMinimo = 1.5; g_RiskPercent = 2.0; }
   else if(StringFind(sym, "EURUSD") >= 0)
   {
      // REPROVADO no backtest 16/07 (e ja tinha sido descartado na validacao
      // rigorosa original, ver cabecalho do arquivo) - nenhuma combinacao
      // de ADX/Volume deu PF>1 nos dois lados. Grafico pode ficar aberto
      // (visual), mas NAO abre posicao - ver g_ParOperavel no OnTick.
      g_ADXMinimo = 999.0; g_VolumeMinimo = 999.0; g_RiskPercent = 0.0; g_ParOperavel = false;
   }
   else if(StringFind(sym, "USDJPY") >= 0)
   {
      // REPROVADO no backtest 16/07 - mesma logica do EURUSD acima.
      g_ADXMinimo = 999.0; g_VolumeMinimo = 999.0; g_RiskPercent = 0.0; g_ParOperavel = false;
   }
   else
   {
      // Simbolo fora da tabela validada - usa os inputs manuais como fallback
      g_ADXMinimo    = InpADXMinimo;
      g_VolumeMinimo = InpVolumeMinimo;
      g_RiskPercent  = InpRiskPercent;
   }
}

input group "=== Trailing Stop (novo 07/07/2026, ver conversa_ativa 08:10) ==="
input bool   InpTrailingAtivo       = true;
input double InpTrailingActivaATR   = 1.0;  // ativa trailing quando lucro >= X * ATR
input double InpTrailingTravaATR    = 0.5;  // trava o SL a X * ATR de distancia do preco atual

input group "=== Magic Number (sequencial - ver LOG_DECISOES_CLAUDIO) ==="
input string InpSetupTipo     = "Trend_ADX_VolConfirm"; // nome do setup p/ log estruturado

input group "=== Filtro de Spread (novo 09/07/2026, achado por Ronei ao vivo) ==="
input bool   InpFiltroSpreadAtivo = true;
input double InpMaxSpreadATRPct   = 15.0; // rejeita entrada se spread > X% da distancia do stop (2xATR)

input group "=== Filtro de Sessao (novo 10/07/2026, teste Fase NY) ==="
// Servidor da corretora = UTC+3, BRT = UTC-3 -> diferenca de 6h (checado 10/07/2026
// via tick.time vs UTC real). Sessao NY 09h-18h BRT = 15h-24h no horario do SERVIDOR.
input bool   InpFiltroSessaoAtivo = false; // liga/desliga o filtro de horario
input int    InpSessaoInicioHora  = 15;    // hora de INICIO (horario do SERVIDOR/corretora = BRT+6)
input int    InpSessaoFimHora     = 24;    // hora de FIM (exclusiva, horario do servidor) - 24 = ate o fim do dia

input group "=== Filtro Anti-Chop (novo 16/07/2026, achado do Ronei) ==="
// Ronei achou o EA comprando E vendendo o mesmo par (USDCAD) em poucas horas,
// as duas batendo stop - mercado sem tendencia real, so ruido dentro de um
// range. Esse filtro exige que um timeframe MAIOR (H4 por padrao) concorde
// com a direcao do sinal antes de deixar entrar - se o H4 nao tem uma
// inclinacao clara na mesma direcao, o sinal do timeframe curto e tratado
// como ruido de range, nao tendencia de verdade.
input bool             InpFiltroAntiChopAtivo   = true;
input ENUM_TIMEFRAMES  InpAntiChopTimeframe     = PERIOD_H4;
input double           InpAntiChopADXMinimo     = 20.0; // barra bem mais baixa que o filtro principal - so precisa de alguma inclinacao no TF maior, nao uma tendencia forte

#define GV_MAGIC_SEQUENCIAL "TRIVIUM369_MAGIC_SEQUENCIAL_COUNTER"
#define MAGIC_SEQUENCIAL_INICIO 200000
// 14/07/2026 - nome do CSV agora inclui o login da conta (pedido do
// Ronei): cada conta grava o proprio arquivo, sem depender de faixa de
// Magic Number pra identificar de onde veio cada operacao.
string g_signalsLogFile = "";
#define SIGNALS_LOG_HEADER "magic;datetime_abertura;ativo;timeframe;direcao;preco_entrada;atr_valor;sl_calculado;tp_calculado;setup_tipo;motivo_entrada;lote;datetime_fechamento;preco_fechamento;motivo_saida;resultado_pips;resultado_reais;barras_duracao;status"

// KILL SWITCH — desligado por padrao. So Ronei liga (GlobalVariableSet = 1.0)
// via "pode rodar". Enquanto 0 (ou nao existir), o EA fica anexado, inicializa,
// loga, mas NUNCA abre posicao nova. Trailing/gestao de posicao ja aberta
// continua funcionando normalmente (nao ha posicao aberta antes de autorizar).
#define GV_EXECUCAO_AUTORIZADA "TRIVIUM369_EXECUCAO_AUTORIZADA"

// 17/07/2026 - calculadora de risco dinamica (mesmo padrao da versao
// real) - #define precisa vir antes do uso em OnInit.
#define GV_LOSSES_PREFIX "TRIVIUM369_LOSSES_SEGUIDAS_"
string g_gvLosses = "";

bool ExecucaoAutorizada()
{
   // No Strategy Tester (backtest/otimizacao) nao existe conta real nem risco de
   // execucao indevida - o kill switch so faz sentido pra graficos ao vivo. Sem
   // isso o backtest ficaria sempre bloqueado (GlobalVariable nao existe no Tester).
   if(MQLInfoInteger(MQL_TESTER)) return true;
   return GlobalVariableCheck(GV_EXECUCAO_AUTORIZADA) && GlobalVariableGet(GV_EXECUCAO_AUTORIZADA) >= 1.0;
}

CTrade trade;
int    h_adx = INVALID_HANDLE;
int    h_atr = INVALID_HANDLE;
int    h_adx_anti_chop = INVALID_HANDLE;
double saldoInicioDia = 0;
datetime diaAtual = 0;
int    tradesHoje = 0;
long   magicAtual = 0;           // magic da posicao atualmente aberta por ESTA instancia (0 = nenhuma)
datetime tempoAberturaPosicaoAtual = 0;
double precoAberturaPosicaoAtual = 0;
ENUM_POSITION_TYPE ladoPosicaoAtual = POSITION_TYPE_BUY;
datetime lastSignalBarTime = 0;
int    barsSinceLastSignal = 999;
string logFileName = "";

//+------------------------------------------------------------------+
// Gera um Magic Number sequencial, nunca repetido, compartilhado por
// TODOS os EAs/instancias da conta via GlobalVariable persistida.
//
// 15/07/2026 - CORRIGIDO (Ronei achou magic duplicado em todas as       |
// contas, ex: 200031 duas vezes na mesma conta). Causa: Get + soma +   |
// Set eram 3 passos separados, nao atomicos. Cada grafico roda numa    |
// thread propria no MT5 - duas instancias podiam ler o mesmo valor     |
// antes de qualquer uma escrever de volta, gerando o mesmo magic pras  |
// duas. Corrigido com GlobalVariableSetOnCondition (compare-and-swap   |
// atomico do MQL5): so escreve se o valor ainda for o que a gente leu;  |
// se outra instancia mudou no meio, tenta de novo com o valor novo.    |
//+------------------------------------------------------------------+
// 17/07/2026 - CORRIGIDO bug real achado pelo Ronei ao vivo: o contador
// de magic mora numa GlobalVariable, que so persiste se o terminal fechar
// normalmente. Fechamento forcado (taskkill, ou o terminal travar) perde
// a GlobalVariable - na proxima abertura o contador reiniciava do zero
// (200000) e recriava magic numbers ja usados em dias anteriores
// (confirmado no CSV: magic 200020 usado em 15/07 E de novo em 17/07).
// Fix: antes de gerar qualquer magic novo, consulta o HISTORICO REAL da
// corretora (nunca se perde, independe de GlobalVariable) e garante que
// o contador nunca fique abaixo do maior magic ja usado nesta conta.
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
      Print("AVISO: contador de magic estava atras do historico real (GV=", atualGV, ", historico=", maiorMagicHistorico, ") - corrigido, nao vai mais recriar numero repetido.");
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
      Print("AVISO: GerarMagicSequencial nao conseguiu CAS apos 50 tentativas - concorrencia muito alta");

   return (long)novo;
}

//+------------------------------------------------------------------+
// Garante que o CSV estruturado existe com cabecalho antes de escrever.
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
// Registra a ABERTURA de um sinal no CSV estruturado (campos 1-12;
// campos 13-19, de fechamento, ficam vazios ate a posicao fechar).
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
// Preenche os campos de FECHAMENTO na linha do CSV que tem este Magic.
// Reescreve o arquivo inteiro (custo aceitavel - poucas centenas de
// linhas esperadas por ciclo de teste).
//+------------------------------------------------------------------+
void RegistraSinalFechamento(long magic, double precoFechamento, string motivoSaida,
                              double resultadoPips, double resultadoReais,
                              int barrasDuracao, string status)
{
   if(!FileIsExist(g_signalsLogFile, FILE_COMMON)) return;

   string linhas[]; int total = 0;
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
   for(int i = 0; i < total; i++)
      FileWriteString(h, linhas[i] + "\r\n");
   FileClose(h);
}

//+------------------------------------------------------------------+
// Nome do timeframe em texto (H1, H4, M15...)
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
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, linha);
      FileClose(h);
   }
}

//+------------------------------------------------------------------+
// Sinalizacao visual (10/07/2026, pedido do Ronei): seta no grafico
// no ponto de entrada e no ponto de saida, mais um "parecer" (Alert +
// painel Comment persistente) toda vez que uma ordem e executada.
//+------------------------------------------------------------------+
void DesenhaSetaEntrada(long magic, datetime tempo, double preco, ENUM_POSITION_TYPE lado)
{
   string nome = StringFormat("TRIVIUM_ENTRADA_%d", magic);
   ObjectCreate(0, nome, (lado == POSITION_TYPE_BUY) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_ENTRADA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" ENTRADA %s #%d", (lado == POSITION_TYPE_BUY) ? "COMPRA" : "VENDA", magic));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, (lado == POSITION_TYPE_BUY) ? clrLime : clrRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, (lado == POSITION_TYPE_BUY) ? ANCHOR_TOP : ANCHOR_BOTTOM);
}

void DesenhaSetaSaida(long magic, datetime tempo, double preco, bool ganho)
{
   string nome = StringFormat("TRIVIUM_SAIDA_%d", magic);
   ObjectCreate(0, nome, OBJ_ARROW_CHECK, 0, tempo, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 3);
   string rotulo = StringFormat("TRIVIUM_SAIDA_TXT_%d", magic);
   ObjectCreate(0, rotulo, OBJ_TEXT, 0, tempo, preco);
   ObjectSetString(0, rotulo, OBJPROP_TEXT, StringFormat(" SAIDA #%d (%s)", magic, ganho ? "GANHO" : "PERDA"));
   ObjectSetInteger(0, rotulo, OBJPROP_COLOR, ganho ? clrLime : clrOrangeRed);
   ObjectSetInteger(0, rotulo, OBJPROP_ANCHOR, ANCHOR_TOP);
}

// Painel "parecer" persistente no canto do grafico - ultima acao executada.
// Usa objeto de texto fixo (nao Comment()) pra nao ser sobrescrito pelo
// painel do NEXUS369_REVERSAO_EA quando os dois estao no mesmo grafico
// (pedido do Ronei 14/07/2026 - quer ver confluencia/motivo de entrada e
// saida direto na tela, dos dois sistemas ao mesmo tempo).
#define PAINEL_TREND_NOME "TRIVIUM_PAINEL_TENDENCIA"
void AtualizaParecer(string texto)
{
   if(ObjectFind(0, PAINEL_TREND_NOME) < 0)
   {
      ObjectCreate(0, PAINEL_TREND_NOME, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_YDISTANCE, 5);
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, PAINEL_TREND_NOME, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_COLOR, clrLimeGreen);
      ObjectSetInteger(0, PAINEL_TREND_NOME, OBJPROP_BACK, false);
   }
   ObjectSetString(0, PAINEL_TREND_NOME, OBJPROP_TEXT, "[TENDENCIA]\n" + texto);
}

//+------------------------------------------------------------------+
int OnInit()
{
   // Aviso de escopo - validado em GER40/BTCUSD (rigoroso) + 6 pares majores
   // (09/07 e 16/07, treino/teste). EURUSD/USDJPY testados 16/07 e REPROVADOS
   // (ver CarregarCalibragemPorAtivo) - ficam fora mesmo com grafico aberto.
   string sym = _Symbol; StringToUpper(sym);
   bool escopoValido = (StringFind(sym,"GER40")>=0 || StringFind(sym,"BTC")>=0 ||
                        StringFind(sym,"NZDJPY")>=0 || StringFind(sym,"USDCAD")>=0 ||
                        StringFind(sym,"AUDUSD")>=0 || StringFind(sym,"NZDUSD")>=0 ||
                        StringFind(sym,"GBPUSD")>=0 || StringFind(sym,"USDCHF")>=0);
   if(!escopoValido)
   {
      Print("AVISO: NEXUS369_TREND_VALIDADO so foi validado em GER40, BTCUSD, NZDJPY, USDCAD, AUDUSD, NZDUSD, GBPUSD, USDCHF.");
      Print("Rodando em ", sym, " - fora do escopo testado. Recomendo NAO operar aqui sem novo teste.");
   }

   CarregarCalibragemPorAtivo();
   GarantirContadorMagicNuncaRetrocede();
   if(!g_ParOperavel)
      Print("AVISO: ", sym, " foi testado e REPROVADO no backtest (16/07/2026) - grafico fica so visual, EA nao abre posicao aqui.");

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

   trade.SetDeviationInPoints(30);
   magicAtual = 0; // nenhuma posicao aberta por esta instancia ainda

   saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   diaAtual = iTime(_Symbol, PERIOD_D1, 0);
   tradesHoje = 0;

   long contaLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   logFileName = "NEXUS369_TREND_RELATORIO_" + sym + "_" + IntegerToString(contaLogin) + ".txt";
   g_signalsLogFile = "TRIVIUM369_SIGNALS_LOG_" + IntegerToString(contaLogin) + ".csv";
   g_gvLosses = GV_LOSSES_PREFIX + IntegerToString(contaLogin) + "_" + sym;

   LogRelatorio(StringFormat("=== INIT %s | %s %s | Magic=sequencial (ver TRIVIUM369_SIGNALS_LOG.csv) | ADX>%.1f Vol>%.1fx | SL=%.1fxATR TP=%.1fxATR | Risco=%.1f%% | Calibragem=%s | EXECUCAO=%s ===",
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), sym, NomePeriodo(_Period),
      g_ADXMinimo, g_VolumeMinimo, InpStopATRMult, InpAlvoATRMult, g_RiskPercent,
      InpAutoCalibrarPorAtivo ? "AUTOMATICA" : "MANUAL",
      ExecucaoAutorizada() ? "AUTORIZADA" : "AGUARDANDO 'pode rodar' do Ronei"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(h_adx != INVALID_HANDLE) IndicatorRelease(h_adx);
   if(h_atr != INVALID_HANDLE) IndicatorRelease(h_atr);
   if(h_adx_anti_chop != INVALID_HANDLE) IndicatorRelease(h_adx_anti_chop);
   ObjectDelete(0, PAINEL_TREND_NOME);
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

// 15/07/2026 - CORRIGIDO (mesmo bug achado na conta real: entradas
// duplicadas apos reload da matriz). magicAtual e memoria, zera ao
// reinicializar - fechar a JANELA do grafico nao fecha a POSICAO na
// corretora. Agora checa por REALIDADE (simbolo + comentario "TND "),
// sobrevive a reinicializacao do EA.
bool TemPosicaoAberta()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      string comentario = PositionGetString(POSITION_COMMENT);
      if(StringFind(comentario, "TND ") == 0)
      {
         magicAtual = PositionGetInteger(POSITION_MAGIC);
         return true;
      }
   }
   magicAtual = 0;
   return false;
}

//+------------------------------------------------------------------+
// Trailing stop dinamico por ATR - so aperta o SL, nunca afrouxa.
// Roda mesmo se o Stop Diario estiver bloqueado (nao abre posicao
// nova, mas continua protegendo a que ja esta aberta).
//+------------------------------------------------------------------+
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
            {
               if(trade.PositionModify(tk, novoSL, tpAtual))
                  LogRelatorio(StringFormat("TRAILING #%d | %s | SL movido para %s (lucro %.1f pts, ATR=%.5f)",
                     (int)tk, _Symbol, DoubleToString(novoSL, _Digits), lucroDist, atr_now));
            }
         }
      }
      else // SELL
      {
         double atual = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double lucroDist = entry - atual;
         if(lucroDist >= InpTrailingActivaATR * atr_now)
         {
            double novoSL = atual + InpTrailingTravaATR * atr_now;
            if(slAtual == 0 || novoSL < slAtual)
            {
               if(trade.PositionModify(tk, novoSL, tpAtual))
                  LogRelatorio(StringFormat("TRAILING #%d | %s | SL movido para %s (lucro %.1f pts, ATR=%.5f)",
                     (int)tk, _Symbol, DoubleToString(novoSL, _Digits), lucroDist, atr_now));
            }
         }
      }
   }
}

int LossesSeguidosAtual()
{
   if(g_gvLosses == "") return 0;
   return GlobalVariableCheck(g_gvLosses) ? (int)GlobalVariableGet(g_gvLosses) : 0;
}

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
   double lotsPeloRisco = MathFloor(lots / stepLot) * stepLot;
   lots = MathMax(minLot, MathMin(maxLot, lotsPeloRisco));

   // Correcao 01/08/2026: quando o lote pedido pelo risco% fica abaixo do lote minimo
   // da corretora, o EA era obrigado a arredondar pra cima (minLot) pra conseguir operar -
   // mas isso fazia o risco real da conta silenciosamente estourar o risco% configurado,
   // sem log nenhum. Em conta pequena (ex: saldo US$35-100) isso pode significar arriscar
   // 5x-10x mais do que o Ronei pediu. Agora avisa quanto de risco real esta sendo tomado.
   if(lotsPeloRisco < minLot && slDistPoints > 0 && valorPorPonto > 0)
   {
      double riscoRealMoney = lots * slDistPoints * valorPorPonto;
      double saldo = AccountInfoDouble(ACCOUNT_BALANCE);
      double riscoRealPct = (saldo > 0) ? (riscoRealMoney / saldo * 100.0) : 0.0;
      LogRelatorio(StringFormat(
         "RISCO ACIMA DO CONFIGURADO | %s | lote minimo da corretora (%.2f) forcado - risco%% pedido %.2f -> risco%% real %.2f (US$%.2f)",
         _Symbol, minLot, riskPct, riscoRealPct, riscoRealMoney));
   }
   return lots;
}

//+------------------------------------------------------------------+
void OnTick()
{
   NovoDia();
   // 16/07/2026 - auditoria pos-bug: TemPosicaoAberta() agora e quem
   // atualiza magicAtual a partir da realidade da corretora (nao mais so
   // memoria). GerenciaTrailingStop() DEPENDE de magicAtual estar fresco -
   // antes rodava primeiro, deixando o trailing "cego" por 1 tick logo
   // apos qualquer reinicializacao do EA (magicAtual ainda em 0). Chamando
   // TemPosicaoAberta() ANTES elimina esse blind-spot.
   TemPosicaoAberta();
   GerenciaTrailingStop(); // roda sempre - protege posicao aberta mesmo com stop diario acionado ou execucao nao autorizada
   if(!ExecucaoAutorizada()) return; // KILL SWITCH - EA anexado e pronto, mas so abre posicao com "pode rodar" do Ronei
   if(!g_ParOperavel) return; // 16/07/2026 - par testado e reprovado no backtest (ver CarregarCalibragemPorAtivo), grafico fica so visual
   if(StopDiario_Bloqueado()) return; // Stop diario de CONTA INTEIRA (10% equity) - ver SPEC_STOP_DIARIO.md
   if(MargemBloqueada()) return; // guarda de margem da CONTA INTEIRA (20/07/2026)
   if(DrawdownDiarioEstourado()) return; // guarda local adicional deste EA/simbolo (3% - defesa em profundidade)
   if(tradesHoje >= InpMaxTradesDia) return;
   if(TemPosicaoAberta()) return;

   // Filtro de sessao (hora do servidor da corretora, ver comentario do input)
   if(InpFiltroSessaoAtivo)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < InpSessaoInicioHora || dt.hour >= InpSessaoFimHora) return;
   }

   datetime curBar = iTime(_Symbol, _Period, 0);
   if(curBar == lastSignalBarTime) return;
   lastSignalBarTime = curBar;
   barsSinceLastSignal++;

   if(barsSinceLastSignal < InpBarrasMinEntreSinais) return;

   double adx_buf[2], plus_di[2], minus_di[2], atr_buf[2];
   if(CopyBuffer(h_adx, 0, 1, 1, adx_buf) < 1) return;
   if(CopyBuffer(h_adx, 1, 1, 1, plus_di) < 1) return;
   if(CopyBuffer(h_adx, 2, 1, 1, minus_di) < 1) return;
   if(CopyBuffer(h_atr, 0, 1, 1, atr_buf) < 1) return;

   double adx_val = adx_buf[0];
   double plusDI = plus_di[0];
   double minusDI = minus_di[0];
   double atr_val = atr_buf[0];

   if(adx_val <= g_ADXMinimo) return;
   if(atr_val <= 0) return;

   // Filtro de volume
   long vol_buf[];
   ArraySetAsSeries(vol_buf, true);
   if(CopyTickVolume(_Symbol, _Period, 1, InpVolumePeriod+1, vol_buf) < InpVolumePeriod+1) return;
   double vol_avg = 0;
   for(int i = 1; i <= InpVolumePeriod; i++) vol_avg += (double)vol_buf[i];
   vol_avg /= InpVolumePeriod;
   double vol_atual = (double)vol_buf[0];
   if(vol_atual <= vol_avg * g_VolumeMinimo) return;

   string side = "";
   if(plusDI > minusDI) side = "BUY";
   else if(minusDI > plusDI) side = "SELL";
   else return;

   // Filtro anti-chop (16/07/2026): exige que o timeframe MAIOR (H4 por
   // padrao) concorde com a direcao do sinal. Sem isso, o EA pode comprar E
   // vender o mesmo par em poucas horas quando o mercado esta lateral -
   // ambas as entradas batem stop porque nao ha tendencia real, so ruido
   // dentro de um range. Achado ao vivo pelo Ronei em USDCAD-T, 16/07/2026.
   if(InpFiltroAntiChopAtivo)
   {
      double adxBuf2[1], plusDI2[1], minusDI2[1];
      if(CopyBuffer(h_adx_anti_chop, 0, 1, 1, adxBuf2) < 1) return;
      if(CopyBuffer(h_adx_anti_chop, 1, 1, 1, plusDI2) < 1) return;
      if(CopyBuffer(h_adx_anti_chop, 2, 1, 1, minusDI2) < 1) return;

      bool tfMaiorConcorda = false;
      if(adxBuf2[0] > InpAntiChopADXMinimo)
      {
         if(side == "BUY"  && plusDI2[0]  > minusDI2[0]) tfMaiorConcorda = true;
         if(side == "SELL" && minusDI2[0] > plusDI2[0])  tfMaiorConcorda = true;
      }

      if(!tfMaiorConcorda)
      {
         LogRelatorio(StringFormat(
            "SINAL REJEITADO POR ANTI-CHOP | %s | %s pede %s, mas %s nao concorda (ADX=%.1f +DI=%.1f -DI=%.1f) | ADX_local=%.1f",
            _Symbol, NomePeriodo(_Period), side, EnumToString(InpAntiChopTimeframe),
            adxBuf2[0], plusDI2[0], minusDI2[0], adx_val));
         return;
      }
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Filtro de spread (achado por Ronei ao vivo, 09/07/2026): rejeita entrada
   // se o spread do momento consumir mais que X% da distancia do stop (2xATR).
   // Sem isso, um spread anomalo (ex: 8->70 pontos no EURUSD, ~9x o normal)
   // podia comer ate 33% do orcamento de risco antes do preco se mexer.
   if(InpFiltroSpreadAtivo)
   {
      double spread_atual = ask - bid;
      double stop_dist_preco = InpStopATRMult * atr_val;
      double spread_pct_do_stop = (stop_dist_preco > 0) ? (spread_atual / stop_dist_preco * 100.0) : 999.0;
      if(spread_pct_do_stop > InpMaxSpreadATRPct)
      {
         LogRelatorio(StringFormat(
            "SINAL REJEITADO POR SPREAD | %s | spread=%.5f (%.1f%% do stop, limite %.1f%%) | ADX=%.1f Vol=%.2fx %s",
            _Symbol, spread_atual, spread_pct_do_stop, InpMaxSpreadATRPct, adx_val, vol_atual/vol_avg, side));
         return;
      }
   }

   string tf = NomePeriodo(_Period);
   // Comentario da ordem - MT5/corretora costuma truncar em ~31 caracteres,
   // entao vai so o essencial. O motivo completo vai pro log de texto.
   string comentario = StringFormat("TND %s ADX%.0f V%.1fx %s", tf, adx_val, vol_atual/vol_avg, side);
   if(StringLen(comentario) > 31) comentario = StringSubstr(comentario, 0, 31);

   string motivoDetalhado = StringFormat(
      "ADX=%.1f (min %.1f) tendencia %s, Volume=%.2fx media (min %.1fx), +DI=%.1f -DI=%.1f",
      adx_val, g_ADXMinimo, (side=="BUY"?"de alta":"de baixa"), vol_atual/vol_avg, g_VolumeMinimo, plusDI, minusDI);

   if(side == "BUY")
   {
      double entry = ask;
      double sl = entry - InpStopATRMult * atr_val;
      double tp = entry + InpAlvoATRMult * atr_val;
      double slDistPoints = (entry - sl) / point;
      double lots = CalcularLote(g_RiskPercent, slDistPoints);
      if(lots > 0)
      {
         long novoMagic = GerarMagicSequencial();
         trade.SetExpertMagicNumber(novoMagic);
         if(trade.Buy(lots, _Symbol, entry, sl, tp, comentario))
         {
            magicAtual = novoMagic;
            tempoAberturaPosicaoAtual = curBar;
            precoAberturaPosicaoAtual = entry;
            ladoPosicaoAtual = POSITION_TYPE_BUY;
            tradesHoje++;
            barsSinceLastSignal = 0;
            RegistraSinalAbertura(novoMagic, _Symbol, tf, side, entry, atr_val, sl, tp, InpSetupTipo, motivoDetalhado, lots);
            LogRelatorio(StringFormat(
               "ENTRADA #%d Magic=%d | %s | %s %s | timeframe=%s | motivo: %s | entrada=%s | stop=%s (%.1f ATR) | alvo previsto=%s (%.1f ATR) | ATR=%.5f | lote=%.2f",
               (int)trade.ResultOrder(), novoMagic, _Symbol, tf, side, tf, motivoDetalhado,
               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), InpStopATRMult,
               DoubleToString(tp, _Digits), InpAlvoATRMult, atr_val, lots));
            DesenhaSetaEntrada(novoMagic, curBar, entry, POSITION_TYPE_BUY);
            AtualizaParecer(StringFormat(
               "TRIVIUM369 - PARECER DA ULTIMA ORDEM\n%s | COMPRA #%d\nEntrada: %s | Stop: %s | Alvo: %s\nLote: %.2f | Motivo: %s",
               _Symbol, novoMagic, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
               DoubleToString(tp, _Digits), lots, motivoDetalhado));
         }
      }
   }
   else
   {
      double entry = bid;
      double sl = entry + InpStopATRMult * atr_val;
      double tp = entry - InpAlvoATRMult * atr_val;
      double slDistPoints = (sl - entry) / point;
      double lots = CalcularLote(g_RiskPercent, slDistPoints);
      if(lots > 0)
      {
         long novoMagic = GerarMagicSequencial();
         trade.SetExpertMagicNumber(novoMagic);
         if(trade.Sell(lots, _Symbol, entry, sl, tp, comentario))
         {
            magicAtual = novoMagic;
            tempoAberturaPosicaoAtual = curBar;
            precoAberturaPosicaoAtual = entry;
            ladoPosicaoAtual = POSITION_TYPE_SELL;
            tradesHoje++;
            barsSinceLastSignal = 0;
            RegistraSinalAbertura(novoMagic, _Symbol, tf, side, entry, atr_val, sl, tp, InpSetupTipo, motivoDetalhado, lots);
            LogRelatorio(StringFormat(
               "ENTRADA #%d Magic=%d | %s | %s %s | timeframe=%s | motivo: %s | entrada=%s | stop=%s (%.1f ATR) | alvo previsto=%s (%.1f ATR) | ATR=%.5f | lote=%.2f",
               (int)trade.ResultOrder(), novoMagic, _Symbol, tf, side, tf, motivoDetalhado,
               DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), InpStopATRMult,
               DoubleToString(tp, _Digits), InpAlvoATRMult, atr_val, lots));
            DesenhaSetaEntrada(novoMagic, curBar, entry, POSITION_TYPE_SELL);
            AtualizaParecer(StringFormat(
               "TRIVIUM369 - PARECER DA ULTIMA ORDEM\n%s | VENDA #%d\nEntrada: %s | Stop: %s | Alvo: %s\nLote: %.2f | Motivo: %s",
               _Symbol, novoMagic, DoubleToString(entry, _Digits), DoubleToString(sl, _Digits),
               DoubleToString(tp, _Digits), lots, motivoDetalhado));
         }
      }
   }
}

// Retorna o ticket da ultima posicao aberta por este EA neste simbolo (para o log)
ulong ticket_after()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==magicAtual)
         return tk;
   }
   return 0;
}

//+------------------------------------------------------------------+
// Relatorio de fechamento - registra resultado real de cada trade
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(magicAtual == 0 || HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != magicAtual) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT) return; // so registra ao FECHAR a posicao

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double precoSaida = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   long ticket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   string resultado = profit >= 0 ? "GANHO (bateu o alvo)" : "PERDA (bateu o stop)";
   string status = profit >= 0 ? "GANHO" : "PERDA";

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   // motivo da saida: aproxima por SL/TP mais proximo do preco de saida (nao ha campo direto no deal)
   string motivoSaida = "SL_ou_TP";
   int barrasDuracao = (tempoAberturaPosicaoAtual > 0) ? (int)iBarShift(_Symbol, _Period, tempoAberturaPosicaoAtual) : -1;
   double resultadoPips = 0;
   if(point > 0 && precoAberturaPosicaoAtual > 0)
      resultadoPips = (ladoPosicaoAtual == POSITION_TYPE_BUY)
         ? (precoSaida - precoAberturaPosicaoAtual) / point
         : (precoAberturaPosicaoAtual - precoSaida) / point;

   RegistraSinalFechamento(magicAtual, precoSaida, motivoSaida, resultadoPips, profit, barrasDuracao, status);
   RegistrarResultadoRisco(profit >= 0);

   LogRelatorio(StringFormat(
      "FECHAMENTO #%d Magic=%d | %s | %s | saida=%s | resultado=%s | P&L=%.2f %s",
      (int)ticket, (int)magicAtual, _Symbol, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
      DoubleToString(precoSaida, _Digits), resultado, profit, AccountInfoString(ACCOUNT_CURRENCY)));

   DesenhaSetaSaida(magicAtual, TimeCurrent(), precoSaida, profit >= 0);
   AtualizaParecer(StringFormat(
      "TRIVIUM369 - PARECER DA ULTIMA ORDEM\n%s | FECHADA #%d\nSaida: %s | Resultado: %s\nP&L: %.2f %s | Pips: %.1f",
      _Symbol, (int)magicAtual, DoubleToString(precoSaida, _Digits), resultado,
      profit, AccountInfoString(ACCOUNT_CURRENCY), resultadoPips));

   magicAtual = 0; // libera esta instancia pra gerar um Magic novo no proximo sinal
   tempoAberturaPosicaoAtual = 0;
   precoAberturaPosicaoAtual = 0;
}

//+------------------------------------------------------------------+
// OnTester (10/07/2026) - roda so dentro do Strategy Tester, ao final
// de cada backtest. Junta as metricas pedidas pro teste de fase 1/2/3
// (retorno%, drawdown max, profit factor, win rate, sequencia maxima
// de perdas, margem minima, total de trades) numa linha de CSV, pra
// nao precisar ler relatorio .htm na mao depois de cada rodada.
//+------------------------------------------------------------------+
double OnTester()
{
   double deposito   = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double lucro      = TesterStatistics(STAT_PROFIT);
   double retornoPct = (deposito > 0) ? (lucro / deposito * 100.0) : 0.0;
   double ddPct      = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double pf         = TesterStatistics(STAT_PROFIT_FACTOR);
   double trades     = TesterStatistics(STAT_TRADES);
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
         FileWriteString(h, "simbolo;timeframe;sessao_filtro;risco_pct;leverage_conta;deposito;retorno_pct;drawdown_max_pct;profit_factor;win_rate_pct;seq_max_perdas;margem_minima_pct;equity_minima;total_trades\r\n");
      FileWriteString(h, StringFormat("%s;%s;%s;%.1f;%d;%.2f;%.2f;%.2f;%.2f;%.2f;%d;%.2f;%.2f;%d\r\n",
         _Symbol, EnumToString(_Period), (InpFiltroSessaoAtivo ? "NY" : "24h"), g_RiskPercent, (int)AccountInfoInteger(ACCOUNT_LEVERAGE), deposito,
         retornoPct, ddPct, pf, winRatePct, (int)seqMaxPerdas, margemMin, equityMin, (int)trades));
      FileClose(h);
   }

   return retornoPct; // valor de otimizacao, nao usado aqui (sem otimizacao automatica)
}
//+------------------------------------------------------------------+
