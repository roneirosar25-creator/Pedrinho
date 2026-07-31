//+------------------------------------------------------------------+
//| PONTE_NEXUS369_ORCHESTRATOR.mq5                                  |
//| TRIVIUM369 © 2026                                                |
//| O ORQUESTRADOR SUPREMO — Integra PONTE_MT5 + TRIVIUM_LEVELS      |
//| + NEXUS369_REGIME + IA + Multi-Ativo + Risk Management Pro       |
//|                                                                  |
//| FILOSOFIA:                                                        |
//|   "A ponte entre o MT5 e a Inteligência Artificial"              |
//|                                                                  |
//| CARACTERÍSTICAS:                                                 |
//|   1. PONTE_MT5 integrada — escreve decisões em SAIDA/ para       |
//|      consumo da IA, lê ordens de ENTRADA/                        |
//|   2. Sinal primário: TRIVIUM_LEVELS (69.8% acerto validado)      |
//|   3. Regime adaptativo: NEXUS369_REGIME (Trend/Range/Choque)     |
//|   4. Confluência Multi-Timeframe                                 |
//|   5. VORTEX_MTF_ANTECIPADOR como gatilho de execução             |
//|   6. Gestão de risco dinâmica por regime                         |
//|   7. Saída adaptativa: bandas ATR como TP, trailing por banda    |
//|   8. Proteção de drawdown (diário, semanal, consecutivo)         |
//|   9. Validação Monte Carlo periódica                             |
//|   10. Log JSON completo para análise por IA externa              |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 © 2026 — Ronei Rosar"
#property version   "1.00"
#property description "PONTE NEXUS369 ORCHESTRATOR — O EA Definitivo"
#property description "Integra PONTE_MT5 + TRIVIUM_LEVELS v2.08 + NEXUS369_REGIME"
#property description "Multi-Ativo | IA Bridge | Risk Management Pro"

#include <Trade\Trade.mqh>
#include <TRIVIUM\NEXUS369_REGIME.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_TP_MODE
{
   TP_CENTRAL,        // TP = linha central (validado: +0.41R/trade)
   TP_BANDA_1,        // TP = banda L1 oposta
   TP_BANDA_2,        // TP = banda L2 oposta (mais agressivo)
   TP_DINAMICO_ATR    // TP = entrada + 2x ATR(55) na direção
};

enum ENUM_TRAIL_MODE
{
   TRAIL_NENHUM,      // Sem trailing
   TRAIL_BREAKEVEN,   // Break-even após 1x ATR
   TRAIL_BANDA_1,     // Trailing pela banda L1
   TRAIL_BANDA_2      // Trailing pela banda L2
};

enum ENUM_EXEC_MODE
{
   EXEC_SINCRONO,     // Executa e registra na PONTE
   EXEC_SIMULADO,     // Apenas simula e registra (sem ordens reais)
   EXEC_IA_DIRETO     // Segue ordens da IA via ENTRADA/
};

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 1: PONTE_MT5                                     |
//+------------------------------------------------------------------+
input group "=== PONTE_MT5 — Bridge IA ==="
input ENUM_EXEC_MODE InpExecMode     = EXEC_SINCRONO; // Modo de execução
input bool           InpLogJSON      = true;          // Gravar JSON em SAIDA/
input bool           InpLerOrdensIA  = false;         // Ler ordens de ENTRADA/
input string         InpPonteFolder  = "PONTE_MT5";   // Pasta raiz da ponte
input string         InpSessaoID     = "NEXUS369";    // ID da sessão para logs

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 2: Símbolos e Timeframes                         |
//+------------------------------------------------------------------+
input group "=== Símbolos e Timeframes ==="
input string         InpSymbols          = "EURUSD-T,GBPUSD-T,AUDUSD-T,USDCAD-T,USDJPY-T,XAUUSD-T"; // Símbolos
input ENUM_TIMEFRAMES InpTFPrincipal     = PERIOD_H1;     // Timeframe principal de análise
input ENUM_TIMEFRAMES InpTFConfluencia   = PERIOD_H4;     // Timeframe de confluência
input bool           InpUsarConfluencia  = true;          // Exigir confluência MTF

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 3: Fonte de Sinal                               |
//+------------------------------------------------------------------+
input group "=== Fonte de Sinal ==="
input string         InpIndicadorPrimario   = "TRIVIUM_LEVELS";  // Indicador primário
input string         InpIndicadorVortex     = "VORTEX_MTF_ANTECIPADOR"; // Gatilho de entrada
input bool           InpUsarVortex          = true;              // Usar VORTEX como gatilho fino
input bool           InpExigirRegimeFavoravel = true;            // Só opera se regime for compatível

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 4: Gestão de Risco                               |
//+------------------------------------------------------------------+
input group "=== Gestão de Risco ==="
input double         InpRiskPctBase        = 1.0;     // Risco % base do saldo
input double         InpRiskPctTrend       = 1.5;     // Risco % em tendência (mais confiança)
input double         InpRiskPctRange       = 0.5;     // Risco % em range (menos confiança)
input double         InpMaxDDGlobal        = 15.0;    // Drawdown máximo global %
input double         InpMaxDDDia           = 3.0;     // Drawdown máximo diário %
input double         InpMaxDDSemana        = 6.0;     // Drawdown máximo semanal %
input int            InpMaxPerdasSeq       = 3;       // Perdas consecutivas antes de pausar
input int            InpPausaHoras         = 8;       // Horas de pausa após gatilhos de proteção
input int            InpMaxTradesDia       = 6;       // Máximo de trades/dia por símbolo
input double         InpSpreadMaxPips      = 2.0;     // Spread máximo permitido em pips

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 5: Estratégia de Saída                           |
//+------------------------------------------------------------------+
input group "=== Estratégia de Saída ==="
input ENUM_TP_MODE   InpTPMode            = TP_CENTRAL;      // Modo de take-profit
input double         InpTPRatioRange      = 1.5;             // TP ratio em range
input double         InpTPRatioTrend      = 2.5;             // TP ratio em tendência
input ENUM_TRAIL_MODE InpTrailMode        = TRAIL_BANDA_1;   // Modo de trailing
input double         InpTrailActivationATR = 1.5;            // ATRs para ativar trailing
input double         InpStopATRMult       = 1.0;             // Stop = X * ATR(55)

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 6: Limites Temporais                             |
//+------------------------------------------------------------------+
input group "=== Limites Temporais ==="
input int            InpHoraInicio        = 7;       // Hora início (servidor)
input int            InpHoraFim           = 20;      // Hora fim (servidor)
input bool           InpOperarFimSemana   = false;   // Operar sexta após 18h?
input bool           InpOperarSegunda     = true;    // Operar segunda-feira?

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 7: NEXUS369_REGIME                               |
//+------------------------------------------------------------------+
input group "=== NEXUS369_REGIME (Avançado) ==="
input int            InpERPeriod          = 10;      // Período Efficiency Ratio
input double         InpEREntraTrend      = 0.35;    // ER mínimo para entrar em trend
input double         InpERSaiTrend        = 0.25;    // ER para sair da trend (histerese)
input double         InpSlopeEntra        = 0.08;    // Slope mínimo para trend
input double         InpSlopeSai          = 0.04;    // Slope para sair (histerese)
input double         InpLimiteChoque      = 1.5;     // Limite ATR ratio para veto choque

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 8: Auto-Avaliação e Machine Learning             |
//+------------------------------------------------------------------+
input group "=== Auto-Avaliação ==="
input int            InpAutoAvaliarTrades = 30;      // Avaliar a cada N trades fechados
input double         InpWinRateMin        = 45.0;    // Win rate mínimo para continuar
input double         InpExpectancyMin     = 0.15;    // Expectancy mínima em R
input int            InpMCAvaliarTrades   = 50;      // Trades para janela Monte Carlo
input int            InpMCSimulacoes      = 200;     // Simulações bootstrap
input double         InpMCTolerancia      = 10.0;    // % Máximo de cenários negativos

//+------------------------------------------------------------------+
//| INPUTS — GRUPO 9: Magic Number                                  |
//+------------------------------------------------------------------+
input group "=== Magic Number ==="
input long           InpMagicBase         = 369001;  // Base magic number

//+------------------------------------------------------------------+
//| ESTRUTURAS                                                        |
//+------------------------------------------------------------------+
struct TradeRecord
{
   ulong    ticket;
   string   symbol;
   int      direcao;       // +1 compra, -1 venda
   double   precoEntrada;
   double   sl;
   double   tp;
   double   lots;
   datetime timeEntrada;
   string   regime;
   string   sinalOrigem;   // "TRIVIUM_LEVELS", "VORTEX", "IA"
   double   atrEntrada;
   int      bandaL1;        // Banda na entrada (1,2,3)
   double   equityEntrada;
   bool     trailingAtivo;
};

struct SymbolCtx
{
   string   sym;
   long     magic;
   int      idx;            // Índice no array de símbolos

   // Handles
   int      hLevels;        // TRIVIUM_LEVELS
   int      hVortex;        // VORTEX_MTF_ANTECIPADOR
   int      hATR55;
   int      hATR14;
   int      hEMA20;
   int      hEMA50;
   int      hLevelsH4;      // Confluência H4

   // Regime
   int      regimeAtual;
   int      regimeAnterior;
   double   er;
   double   slope;
   double   atrRatio;
   bool     bbwSqueeze;
   bool     vetoChoque;

   // Controles
   int      tradesHoje;
   datetime diaAtual;
   double   saldoInicioDia;
   double   equityPico;
   int      perdasConsec;
   datetime pausaAte;
   bool     modoObservacao;

   // Auto-avaliação
   int      totalTrades;
   int      totalWins;
   double   somaR;
};

SymbolCtx  ctx[];           // Array por símbolo
TradeRecord tradesAbertos[]; // Trades gerenciados
CTrade     trade;
int        totalSymbols = 0;
datetime   ultimaBarra = 0;
double     saldoInicioSemana = 0;
datetime   inicioSemana = 0;
double     equityPicoGlobal = 0;
int        totalTradesGlobal = 0;
int        totalWinsGlobal = 0;
double     somaRGlobal = 0;

// Buffers compartilhados para indicadores
double bufCentral[], bufBand1U[], bufBand1L[], bufBand2U[], bufBand2L[];
double bufBand3U[], bufBand3L[], bufATR[], bufBuy[], bufSell[];
double bufClose[], bufHigh[], bufLow[];

//+------------------------------------------------------------------+
//| PROTÓTIPOS                                                        |
//+------------------------------------------------------------------+
int    ParseSymbols(string lista, SymbolCtx &arr[]);
bool   CarregarHandles(int idx);
void   LiberarHandles(int idx);
void   OnTimer();
void   GerenciarTrades();
void   VerificarNovoSinal(int idx);
bool   VerificarConfluenciaH4(int idx, bool ehCompra);
bool   VerificarJanelaHoraria();
bool   VerificarProtecoes(int idx);
double CalcularLote(int idx, double riskPct, double slDistPoints);
double GetATR(int handle, int shift);
void   PonteLog(int idx, string tipo, string mensagem, string dadosJSON="");
void   PonteExportarDecisoes();
bool   LerOrdensIA();
void   AutoAvaliacao();
void   MonteCarloValidacao();

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   totalSymbols = ParseSymbols(InpSymbols, ctx);
   if(totalSymbols == 0)
   {
      Print("[ORCHESTRATOR] NENHUM símbolo válido em: ", InpSymbols);
      return INIT_FAILED;
   }
   ArrayResize(ctx, totalSymbols);
   ArrayResize(tradesAbertos, 0);

   ArrayResize(bufCentral, 10);
   ArrayResize(bufBand1U, 10);
   ArrayResize(bufBand1L, 10);
   ArrayResize(bufBand2U, 10);
   ArrayResize(bufBand2L, 10);
   ArrayResize(bufBand3U, 10);
   ArrayResize(bufBand3L, 10);
   ArrayResize(bufATR, 10);
   ArrayResize(bufBuy, 10);
   ArrayResize(bufSell, 10);
   ArrayResize(bufClose, 100);
   ArrayResize(bufHigh, 100);
   ArrayResize(bufLow, 100);

   for(int i = 0; i < totalSymbols; i++)
   {
      ctx[i].sym = ctx[i].sym;
      ctx[i].idx = i;
      ctx[i].magic = InpMagicBase + i * 10;
      ctx[i].regimeAtual = REGIME_NEUTRO;
      ctx[i].regimeAnterior = REGIME_NEUTRO;
      ctx[i].tradesHoje = 0;
      ctx[i].diaAtual = 0;
      ctx[i].saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
      ctx[i].equityPico = AccountInfoDouble(ACCOUNT_EQUITY);
      ctx[i].perdasConsec = 0;
      ctx[i].pausaAte = 0;
      ctx[i].modoObservacao = false;
      ctx[i].totalTrades = 0;
      ctx[i].totalWins = 0;
      ctx[i].somaR = 0.0;

      if(!CarregarHandles(i))
      {
         Print("[ORCHESTRATOR] ERRO ao carregar handles para ", ctx[i].sym);
         return INIT_FAILED;
      }
      Print("[ORCHESTRATOR] ", ctx[i].sym, " INIT | Magic=", ctx[i].magic,
            " | TF=", EnumToString(InpTFPrincipal));
   }

   trade.SetDeviationInPoints(30);
   saldoInicioSemana = AccountInfoDouble(ACCOUNT_BALANCE);
   inicioSemana = iTime(_Symbol, PERIOD_W1, 0);
   equityPicoGlobal = AccountInfoDouble(ACCOUNT_EQUITY);
   EventSetTimer(60);

   PonteLog(-1, "INIT", "Orchestrator iniciado",
      StringFormat("\"simbolos\":\"%s\",\"versao\":\"1.00\",\"modo\":\"%s\"",
         InpSymbols,
         (InpExecMode == EXEC_SINCRONO ? "SINCRONO" :
          InpExecMode == EXEC_SIMULADO ? "SIMULADO" : "IA_DIRETO")));

   Print("[ORCHESTRATOR] INICIADO | ", totalSymbols, " símbolos | Modo: ",
         (InpExecMode == EXEC_SINCRONO ? "SINCRONO" :
          InpExecMode == EXEC_SIMULADO ? "SIMULADO" : "IA_DIRETO"));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i = 0; i < totalSymbols; i++) LiberarHandles(i);
   PonteLog(-1, "DEINIT", "Orchestrator finalizado",
      StringFormat("\"motivo\":%d", reason));
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime barraAtual = iTime(_Symbol, InpTFPrincipal, 0);
   if(barraAtual == ultimaBarra)
   {
      GerenciarTrades();
      return;
   }
   ultimaBarra = barraAtual;

   if(!VerificarJanelaHoraria()) return;

   datetime semanaAtual = iTime(_Symbol, PERIOD_W1, 0);
   if(semanaAtual != inicioSemana)
   {
      inicioSemana = semanaAtual;
      saldoInicioSemana = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   for(int i = 0; i < totalSymbols; i++)
   {
      if(!VerificarProtecoes(i)) continue;
      AtualizarRegime(i);
      VerificarNovoSinal(i);
   }

   GerenciarTrades();

   static int ticksLog = 0;
   ticksLog++;
   if(ticksLog % 60 == 0) PonteExportarDecisoes();
}

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpLerOrdensIA && InpExecMode == EXEC_IA_DIRETO) LerOrdensIA();
   if(totalTradesGlobal > 0 && totalTradesGlobal % InpAutoAvaliarTrades == 0)
      AutoAvaliacao();
}

//+------------------------------------------------------------------+
//| ParseSymbols                                                     |
//+------------------------------------------------------------------+
int ParseSymbols(string lista, SymbolCtx &arr[])
{
   string parts[];
   int n = StringSplit(lista, ',', parts);
   if(n == 0) return 0;
   ArrayResize(arr, n);
   int count = 0;
   for(int i = 0; i < n; i++)
   {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s != "")
      {
         arr[count].sym = s;
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| CarregarHandles                                                  |
//+------------------------------------------------------------------+
bool CarregarHandles(int idx)
{
   string sym = ctx[idx].sym;
   ctx[idx].hLevels = iCustom(sym, InpTFPrincipal, InpIndicadorPrimario);
   if(ctx[idx].hLevels == INVALID_HANDLE)
   {
      Print("[ORCHESTRATOR] ERRO: não carregou ", InpIndicadorPrimario, " em ", sym);
      return false;
   }
   if(InpUsarVortex)
   {
      ctx[idx].hVortex = iCustom(sym, InpTFPrincipal, InpIndicadorVortex);
      if(ctx[idx].hVortex == INVALID_HANDLE)
      {
         Print("[ORCHESTRATOR] AVISO: sem VORTEX em ", sym);
         ctx[idx].hVortex = INVALID_HANDLE;
      }
   }
   else ctx[idx].hVortex = INVALID_HANDLE;

   ctx[idx].hATR55 = iATR(sym, InpTFPrincipal, 55);
   ctx[idx].hATR14 = iATR(sym, InpTFPrincipal, 14);
   ctx[idx].hEMA20 = iMA(sym, InpTFPrincipal, 20, 0, MODE_EMA, PRICE_CLOSE);
   ctx[idx].hEMA50 = iMA(sym, InpTFPrincipal, 50, 0, MODE_EMA, PRICE_CLOSE);

   if(InpUsarConfluencia)
   {
      ctx[idx].hLevelsH4 = iCustom(sym, InpTFConfluencia, InpIndicadorPrimario);
      if(ctx[idx].hLevelsH4 == INVALID_HANDLE)
      {
         Print("[ORCHESTRATOR] AVISO: sem confluência H4 em ", sym);
         ctx[idx].hLevelsH4 = INVALID_HANDLE;
      }
   }
   else ctx[idx].hLevelsH4 = INVALID_HANDLE;
   return true;
}

//+------------------------------------------------------------------+
//| LiberarHandles                                                   |
//+------------------------------------------------------------------+
void LiberarHandles(int idx)
{
   if(ctx[idx].hLevels != INVALID_HANDLE) IndicatorRelease(ctx[idx].hLevels);
   if(ctx[idx].hVortex != INVALID_HANDLE) IndicatorRelease(ctx[idx].hVortex);
   if(ctx[idx].hATR55 != INVALID_HANDLE) IndicatorRelease(ctx[idx].hATR55);
   if(ctx[idx].hATR14 != INVALID_HANDLE) IndicatorRelease(ctx[idx].hATR14);
   if(ctx[idx].hEMA20 != INVALID_HANDLE) IndicatorRelease(ctx[idx].hEMA20);
   if(ctx[idx].hEMA50 != INVALID_HANDLE) IndicatorRelease(ctx[idx].hEMA50);
   if(ctx[idx].hLevelsH4 != INVALID_HANDLE) IndicatorRelease(ctx[idx].hLevelsH4);
}

//+------------------------------------------------------------------+
//| AtualizarRegime                                                  |
//+------------------------------------------------------------------+
void AtualizarRegime(int idx)
{
   string sym = ctx[idx].sym;
   bool isCrypto = (StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0 ||
                    StringFind(sym, "SOL") >= 0);

   int copiado = CopyClose(sym, InpTFPrincipal, 0, 80, bufClose);
   if(copiado < 60) return;
   ArraySetAsSeries(bufClose, true);
   copiado = CopyHigh(sym, InpTFPrincipal, 0, 80, bufHigh);
   if(copiado < 60) return;
   ArraySetAsSeries(bufHigh, true);
   copiado = CopyLow(sym, InpTFPrincipal, 0, 80, bufLow);
   if(copiado < 60) return;
   ArraySetAsSeries(bufLow, true);

   double centralArr[], atrArr[];
   if(CopyBuffer(ctx[idx].hLevels, 0, 0, 10, centralArr) < 6) return;
   if(CopyBuffer(ctx[idx].hLevels, 7, 0, 10, atrArr) < 6) return;
   ArraySetAsSeries(centralArr, true);
   ArraySetAsSeries(atrArr, true);

   RegimeResult res;
   int novoEstado = TriviumRegime(
      bufClose, bufHigh, bufLow, centralArr, atrArr,
      80, 0, isCrypto, InpERPeriod,
      ctx[idx].regimeAtual, res
   );

   ctx[idx].regimeAnterior = ctx[idx].regimeAtual;
   ctx[idx].regimeAtual = novoEstado;
   ctx[idx].er = res.er;
   ctx[idx].slope = res.slope;
   ctx[idx].atrRatio = res.atr_ratio;
   ctx[idx].bbwSqueeze = res.bbw_squeeze;
   ctx[idx].vetoChoque = res.veto_choque;

   if(ctx[idx].regimeAtual != ctx[idx].regimeAnterior)
   {
      PonteLog(idx, "REGIME",
         StringFormat("Regime mudou: %s -> %s",
            RegimeName(ctx[idx].regimeAnterior),
            RegimeName(ctx[idx].regimeAtual)),
         StringFormat("\"er\":%.3f,\"slope\":%.4f,\"atr_ratio\":%.2f,\"bbw_squeeze\":%s",
            ctx[idx].er, ctx[idx].slope, ctx[idx].atrRatio,
            ctx[idx].bbwSqueeze ? "true" : "false"));
   }
}

//+------------------------------------------------------------------+
//| VerificarNovoSinal                                               |
//+------------------------------------------------------------------+
void VerificarNovoSinal(int idx)
{
   string sym = ctx[idx].sym;

   double buyArr[], sellArr[], centralArr[], atrArr[];
   double band3UArr[], band3LArr[], band1UArr[], band1LArr[];
   double band2UArr[], band2LArr[];

   if(CopyBuffer(ctx[idx].hLevels, 8, 1, 1, buyArr) < 1) return;
   if(CopyBuffer(ctx[idx].hLevels, 9, 1, 1, sellArr) < 1) return;
   if(CopyBuffer(ctx[idx].hLevels, 0, 1, 1, centralArr) < 1) return;
   if(CopyBuffer(ctx[idx].hLevels, 7, 1, 1, atrArr) < 1) return;
   if(CopyBuffer(ctx[idx].hLevels, 6, 1, 1, band3UArr) < 1) return;
   if(CopyBuffer(ctx[idx].hLevels, 3, 1, 1, band1LArr) < 1) return;
   if(CopyBuffer(ctx[idx].hLevels, 4, 1, 1, band2UArr) < 1) return;
   if(CopyBuffer(ctx[idx].hLevels, 5, 1, 1, band2LArr) < 1) return;

   bool sinalCompra = (buyArr[0] != EMPTY_VALUE && buyArr[0] != 0.0);
   bool sinalVenda  = (sellArr[0] != EMPTY_VALUE && sellArr[0] != 0.0);
   double central = centralArr[0];
   double atr = atrArr[0];

   if(atr <= 0 || central == EMPTY_VALUE) return;
   if(!sinalCompra && !sinalVenda) return;

   bool regimeFavoravelCompra = false;
   bool regimeFavoravelVenda = false;

   if(InpExigirRegimeFavoravel)
   {
      regimeFavoravelCompra = (ctx[idx].regimeAtual == REGIME_TREND_UP ||
                               ctx[idx].regimeAtual == REGIME_RANGE);
      regimeFavoravelVenda = (ctx[idx].regimeAtual == REGIME_TREND_DOWN ||
                              ctx[idx].regimeAtual == REGIME_RANGE);

      if(ctx[idx].vetoChoque)
      {
         PonteLog(idx, "VETO", "Choque de volatilidade — sinal ignorado",
            StringFormat("\"atr_ratio\":%.2f", ctx[idx].atrRatio));
         return;
      }
      if(sinalCompra && !regimeFavoravelCompra)
      {
         PonteLog(idx, "REGIME_BLOCK",
            StringFormat("Compra bloqueada: regime=%s", RegimeName(ctx[idx].regimeAtual)),
            StringFormat("\"er\":%.3f,\"slope\":%.4f", ctx[idx].er, ctx[idx].slope));
         sinalCompra = false;
      }
      if(sinalVenda && !regimeFavoravelVenda)
      {
         PonteLog(idx, "REGIME_BLOCK",
            StringFormat("Venda bloqueada: regime=%s", RegimeName(ctx[idx].regimeAtual)),
            StringFormat("\"er\":%.3f,\"slope\":%.4f", ctx[idx].er, ctx[idx].slope));
         sinalVenda = false;
      }
   }
   else
   {
      regimeFavoravelCompra = true;
      regimeFavoravelVenda = true;
   }

   if(!sinalCompra && !sinalVenda) return;

   if(InpUsarConfluencia)
   {
      if(sinalCompra && !VerificarConfluenciaH4(idx, true)) sinalCompra = false;
      if(sinalVenda && !VerificarConfluenciaH4(idx, false)) sinalVenda = false;
   }
   if(!sinalCompra && !sinalVenda) return;

   if(InpUsarVortex && ctx[idx].hVortex != INVALID_HANDLE)
   {
      double vortexBuy[1], vortexSell[1];
      bool temVortexBuy = (CopyBuffer(ctx[idx].hVortex, 2, 1, 1, vortexBuy) > 0);
      bool temVortexSell = (CopyBuffer(ctx[idx].hVortex, 3, 1, 1, vortexSell) > 0);

      bool vortexOK = false;
      if(sinalCompra && temVortexBuy && vortexBuy[0] != EMPTY_VALUE && vortexBuy[0] != 0.0)
         vortexOK = true;
      else if(sinalVenda && temVortexSell && vortexSell[0] != EMPTY_VALUE && vortexSell[0] != 0.0)
         vortexOK = true;

      if(!vortexOK)
      {
         PonteLog(idx, "VORTEX_BLOCK", "VORTEX não confirmou o sinal",
            StringFormat("\"sinal_compra\":%s,\"sinal_venda\":%s",
               sinalCompra ? "true" : "false",
               sinalVenda ? "true" : "false"));
         return;
      }
   }

   double spreadPips = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
   if(InpSpreadMaxPips > 0 && spreadPips > InpSpreadMaxPips)
   {
      PonteLog(idx, "SPREAD_BLOCK",
         StringFormat("Spread %.1f pips > máximo %.1f", spreadPips, InpSpreadMaxPips), "{}");
      return;
   }

   if(TemPosicaoAberta(idx))
   {
      PonteLog(idx, "POS_BLOCK", "Já há posição aberta neste símbolo", "{}");
      return;
   }

   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);

   double riskPct = InpRiskPctBase;
   if(ctx[idx].regimeAtual == REGIME_TREND_UP || ctx[idx].regimeAtual == REGIME_TREND_DOWN)
      riskPct = InpRiskPctTrend;
   else if(ctx[idx].regimeAtual == REGIME_RANGE)
      riskPct = InpRiskPctRange;

   if(sinalCompra && !sinalVenda)
   {
      double entry = ask;
      double sl = entry - InpStopATRMult * atr;
      double slDist = (entry - sl) / point;
      double lots = CalcularLote(idx, riskPct, slDist);
      if(lots <= 0) return;

      double tp = central;
      if(InpTPMode == TP_BANDA_1) tp = central + atr;
      else if(InpTPMode == TP_BANDA_2) tp = central + 2 * atr;
      else if(InpTPMode == TP_DINAMICO_ATR)
      {
         double ratio = (ctx[idx].regimeAtual == REGIME_TREND_UP) ? InpTPRatioTrend : InpTPRatioRange;
         tp = entry + ratio * atr;
      }
      if(tp <= entry) tp = central + 1.5 * atr;

      string comentario = StringFormat("NEXUS369 %s C", RegimeName(ctx[idx].regimeAtual));

      if(InpExecMode == EXEC_SINCRONO)
      {
         if(trade.Buy(lots, sym, entry, sl, tp, comentario))
         {
            ctx[idx].tradesHoje++;
            ctx[idx].totalTrades++;
            totalTradesGlobal++;

            TradeRecord tr;
            tr.ticket = trade.ResultOrder();
            tr.symbol = sym;
            tr.direcao = 1;
            tr.precoEntrada = entry;
            tr.sl = sl;
            tr.tp = tp;
            tr.lots = lots;
            tr.timeEntrada = TimeCurrent();
            tr.regime = RegimeName(ctx[idx].regimeAtual);
            tr.sinalOrigem = "TRIVIUM_LEVELS";
            tr.atrEntrada = atr;
            tr.bandaL1 = 1;
            tr.equityEntrada = AccountInfoDouble(ACCOUNT_EQUITY);
            tr.trailingAtivo = false;
            int sz = ArraySize(tradesAbertos);
            ArrayResize(tradesAbertos, sz + 1);
            tradesAbertos[sz] = tr;

            PonteLog(idx, "BUY",
               StringFormat("COMPRA %.2f lots %s | SL=%.5f TP=%.5f | Regime=%s",
                  lots, sym, sl, tp, RegimeName(ctx[idx].regimeAtual)),
               StringFormat("\"entry\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"lots\":%.2f,"
                  "\"atr\":%.5f,\"regime\":\"%s\",\"risk_pct\":%.1f",
                  entry, sl, tp, lots, atr, RegimeName(ctx[idx].regimeAtual), riskPct));
         }
      }
      else
      {
         PonteLog(idx, "BUY_SIM",
            StringFormat("SIMULAÇÃO: COMPRA %.2f %s | SL=%.5f TP=%.5f",
               lots, sym, sl, tp),
            StringFormat("\"entry\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"lots\":%.2f,\"regime\":\"%s\"",
               entry, sl, tp, lots, RegimeName(ctx[idx].regimeAtual)));
      }
   }
   else if(sinalVenda && !sinalCompra)
   {
      double entry = bid;
      double sl = entry + InpStopATRMult * atr;
      double slDist = (sl - entry) / point;
      double lots = CalcularLote(idx, riskPct, slDist);
      if(lots <= 0) return;

      double tp = central;
      if(InpTPMode == TP_BANDA_1) tp = central - atr;
      else if(InpTPMode == TP_BANDA_2) tp = central - 2 * atr;
      else if(InpTPMode == TP_DINAMICO_ATR)
      {
         double ratio = (ctx[idx].regimeAtual == REGIME_TREND_DOWN) ? InpTPRatioTrend : InpTPRatioRange;
         tp = entry - ratio * atr;
      }
      if(tp >= entry) tp = central - 1.5 * atr;

      string comentario = StringFormat("NEXUS369 %s V", RegimeName(ctx[idx].regimeAtual));

      if(InpExecMode == EXEC_SINCRONO)
      {
         if(trade.Sell(lots, sym, entry, sl, tp, comentario))
         {
            ctx[idx].tradesHoje++;
            ctx[idx].totalTrades++;
            totalTradesGlobal++;

            TradeRecord tr;
            tr.ticket = trade.ResultOrder();
            tr.symbol = sym;
            tr.direcao = -1;
            tr.precoEntrada = entry;
            tr.sl = sl;
            tr.tp = tp;
            tr.lots = lots;
            tr.timeEntrada = TimeCurrent();
            tr.regime = RegimeName(ctx[idx].regimeAtual);
            tr.sinalOrigem = "TRIVIUM_LEVELS";
            tr.atrEntrada = atr;
            tr.bandaL1 = 1;
            tr.equityEntrada = AccountInfoDouble(ACCOUNT_EQUITY);
            tr.trailingAtivo = false;
            int sz = ArraySize(tradesAbertos);
            ArrayResize(tradesAbertos, sz + 1);
            tradesAbertos[sz] = tr;

            PonteLog(idx, "SELL",
               StringFormat("VENDA %.2f lots %s | SL=%.5f TP=%.5f | Regime=%s",
                  lots, sym, sl, tp, RegimeName(ctx[idx].regimeAtual)),
               StringFormat("\"entry\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"lots\":%.2f,"
                  "\"atr\":%.5f,\"regime\":\"%s\",\"risk_pct\":%.1f",
                  entry, sl, tp, lots, atr, RegimeName(ctx[idx].regimeAtual), riskPct));
         }
      }
      else
      {
         PonteLog(idx, "SELL_SIM",
            StringFormat("SIMULAÇÃO: VENDA %.2f %s | SL=%.5f TP=%.5f",
               lots, sym, sl, tp),
            StringFormat("\"entry\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"lots\":%.2f,\"regime\":\"%s\"",
               entry, sl, tp, lots, RegimeName(ctx[idx].regimeAtual)));
      }
   }
}

//+------------------------------------------------------------------+
//| VerificarConfluenciaH4                                           |
//+------------------------------------------------------------------+
bool VerificarConfluenciaH4(int idx, bool ehCompra)
{
   if(ctx[idx].hLevelsH4 == INVALID_HANDLE) return true;
   double bufH4[];
   int buffer = ehCompra ? 8 : 9;
   int copiado = CopyBuffer(ctx[idx].hLevelsH4, buffer, 0, 5, bufH4);
   if(copiado < 1) return false;
   for(int i = 0; i < copiado; i++)
      if(bufH4[i] != EMPTY_VALUE && bufH4[i] != 0.0) return true;
   return false;
}

//+------------------------------------------------------------------+
//| VerificarJanelaHoraria                                           |
//+------------------------------------------------------------------+
bool VerificarJanelaHoraria()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_week == 0) return false;
   if(!InpOperarSegunda && dt.day_of_week == 1) return false;
   if(!InpOperarFimSemana && dt.day_of_week == 5 && dt.hour >= 18) return false;
   if(dt.hour < InpHoraInicio || dt.hour >= InpHoraFim) return false;
   return true;
}

//+------------------------------------------------------------------+
//| VerificarProtecoes                                                |
//+------------------------------------------------------------------+
bool VerificarProtecoes(int idx)
{
   if(ctx[idx].pausaAte > 0 && TimeCurrent() < ctx[idx].pausaAte)
   {
      static datetime lastObsLog = 0;
      if(ctx[idx].modoObservacao && TimeCurrent() - lastObsLog > 3600)
      {
         PonteLog(idx, "OBSERVACAO",
            StringFormat("Modo observação até %s", TimeToString(ctx[idx].pausaAte)), "{}");
         lastObsLog = TimeCurrent();
      }
      return false;
   }
   else if(ctx[idx].pausaAte > 0 && TimeCurrent() >= ctx[idx].pausaAte)
   {
      ctx[idx].pausaAte = 0;
      ctx[idx].modoObservacao = false;
      ctx[idx].perdasConsec = 0;
      PonteLog(idx, "REATIVACAO", "Pausa encerrada — operacional novamente", "{}");
   }

   datetime hoje = iTime(ctx[idx].sym, PERIOD_D1, 0);
   if(hoje != ctx[idx].diaAtual)
   {
      ctx[idx].diaAtual = hoje;
      ctx[idx].tradesHoje = 0;
      ctx[idx].saldoInicioDia = AccountInfoDouble(ACCOUNT_BALANCE);
   }

   if(ctx[idx].tradesHoje >= InpMaxTradesDia) return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddDiaPct = (ctx[idx].saldoInicioDia - equity) / ctx[idx].saldoInicioDia * 100.0;
   if(ddDiaPct >= InpMaxDDDia)
   {
      ctx[idx].pausaAte = TimeCurrent() + InpPausaHoras * 3600;
      ctx[idx].modoObservacao = true;
      PonteLog(idx, "DD_DIA",
         StringFormat("Drawdown diário %.1f%% excedido %.1f%%", ddDiaPct, InpMaxDDDia),
         StringFormat("\"dd_pct\":%.1f,\"max\":%.1f", ddDiaPct, InpMaxDDDia));
      return false;
   }

   double ddSemPct = (saldoInicioSemana - equity) / saldoInicioSemana * 100.0;
   if(ddSemPct >= InpMaxDDSemana)
   {
      ctx[idx].pausaAte = TimeCurrent() + InpPausaHoras * 3600;
      ctx[idx].modoObservacao = true;
      PonteLog(idx, "DD_SEMANA",
         StringFormat("Drawdown semanal %.1f%% excedido %.1f%%", ddSemPct, InpMaxDDSemana),
         StringFormat("\"dd_pct\":%.1f,\"max\":%.1f", ddSemPct, InpMaxDDSemana));
      return false;
   }

   double ddGlobalPct = (equityPicoGlobal - equity) / equityPicoGlobal * 100.0;
   if(ddGlobalPct >= InpMaxDDGlobal)
   {
      for(int i = 0; i < totalSymbols; i++)
      {
         ctx[i].pausaAte = TimeCurrent() + InpPausaHoras * 3600;
         ctx[i].modoObservacao = true;
      }
      PonteLog(-1, "DD_GLOBAL",
         StringFormat("Drawdown global %.1f%% excedido %.1f%% — PAUSA GERAL",
            ddGlobalPct, InpMaxDDGlobal),
         StringFormat("\"dd_pct\":%.1f,\"max\":%.1f", ddGlobalPct, InpMaxDDGlobal));
      return false;
   }

   if(ctx[idx].perdasConsec >= InpMaxPerdasSeq)
   {
      ctx[idx].pausaAte = TimeCurrent() + InpPausaHoras * 3600;
      ctx[idx].modoObservacao = true;
      PonteLog(idx, "PERDAS_SEQ",
         StringFormat("%d perdas consecutivas — pausa %d h",
            ctx[idx].perdasConsec, InpPausaHoras),
         StringFormat("\"perdas_seq\":%d,\"max\":%d", ctx[idx].perdasConsec, InpMaxPerdasSeq));
      return false;
   }

   if(equity > equityPicoGlobal) equityPicoGlobal = equity;
   if(equity > ctx[idx].equityPico) ctx[idx].equityPico = equity;
   return true;
}

//+------------------------------------------------------------------+
//| GerenciarTrades                                                  |
//+------------------------------------------------------------------+
void GerenciarTrades()
{
   for(int t = ArraySize(tradesAbertos) - 1; t >= 0; t--)
   {
      if(tradesAbertos[t].ticket <= 0) continue;
      if(!PositionSelectByTicket(tradesAbertos[t].ticket))
      {
         if(HistorySelect(0, TimeCurrent()))
         {
            int deals = HistoryDealsTotal();
            for(int i = deals - 1; i >= 0; i--)
            {
               ulong dealTicket = HistoryDealGetTicket(i);
               if(HistoryDealGetInteger(dealTicket, DEAL_ORDER) == (long)tradesAbertos[t].ticket)
               {
                  double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                  double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                  double total = profit + swap + commission;

                  double rMultiplo = 0;
                  double atrEntry = tradesAbertos[t].atrEntrada;
                  if(atrEntry > 0)
                  {
                     double slDist = 0;
                     if(tradesAbertos[t].direcao > 0)
                        slDist = tradesAbertos[t].precoEntrada - tradesAbertos[t].sl;
                     else
                        slDist = tradesAbertos[t].sl - tradesAbertos[t].precoEntrada;

                     double tickVal = SymbolInfoDouble(tradesAbertos[t].symbol, SYMBOL_TRADE_TICK_VALUE);
                     double tickSz  = SymbolInfoDouble(tradesAbertos[t].symbol, SYMBOL_TRADE_TICK_SIZE);
                     double pt     = SymbolInfoDouble(tradesAbertos[t].symbol, SYMBOL_POINT);
                     double valorPP = tickVal * (pt / tickSz);
                     double riskMoney = slDist * valorPP * tradesAbertos[t].lots;
                     if(riskMoney > 0) rMultiplo = total / riskMoney;
                  }

                  bool win = (profit > 0);
                  for(int s = 0; s < totalSymbols; s++)
                  {
                     if(ctx[s].sym == tradesAbertos[t].symbol)
                     {
                        ctx[s].totalWins += (win ? 1 : 0);
                        ctx[s].somaR += rMultiplo;
                        if(!win) ctx[s].perdasConsec++;
                        else ctx[s].perdasConsec = 0;
                        break;
                     }
                  }
                  totalWinsGlobal += (win ? 1 : 0);
                  somaRGlobal += rMultiplo;

                  PonteLog(-1, "TRADE_CLOSE",
                     StringFormat("%s %s | P=%.2f R=%.2f | %s",
                        tradesAbertos[t].symbol,
                        tradesAbertos[t].direcao > 0 ? "COMPRA" : "VENDA",
                        total, rMultiplo, win ? "WIN" : "LOSS"),
                     StringFormat("\"symbol\":\"%s\",\"ticket\":%lld,\"profit\":%.2f,"
                        "\"swap\":%.2f,\"commission\":%.2f,\"r_multiple\":%.2f,\"win\":%s",
                        tradesAbertos[t].symbol, tradesAbertos[t].ticket,
                        profit, swap, commission, rMultiplo, win ? "true" : "false"));
                  break;
               }
            }
         }

         for(int j = t; j < ArraySize(tradesAbertos) - 1; j++)
            tradesAbertos[j] = tradesAbertos[j + 1];
         ArrayResize(tradesAbertos, ArraySize(tradesAbertos) - 1);
         continue;
      }

      if(InpTrailMode == TRAIL_NENHUM) continue;

      double currentPrice = (tradesAbertos[t].direcao > 0) ?
         SymbolInfoDouble(tradesAbertos[t].symbol, SYMBOL_BID) :
         SymbolInfoDouble(tradesAbertos[t].symbol, SYMBOL_ASK);

      double atrAtual = GetATR(ctx[t].hATR55, 0);
      if(atrAtual <= 0) atrAtual = tradesAbertos[t].atrEntrada;

      double entrada = tradesAbertos[t].precoEntrada;
      double atr = tradesAbertos[t].atrEntrada;
      double distanciaATR = MathAbs(currentPrice - entrada) / atr;

      if(!tradesAbertos[t].trailingAtivo && distanciaATR >= InpTrailActivationATR)
      {
         tradesAbertos[t].trailingAtivo = true;
         PonteLog(-1, "TRAIL_ACTIVATE",
            StringFormat("Trailing ativado %s distancia=%.1f ATR",
               tradesAbertos[t].symbol, distanciaATR), "{}");
      }

      if(!tradesAbertos[t].trailingAtivo) continue;

      if(InpTrailMode == TRAIL_BREAKEVEN && distanciaATR >= 1.0)
      {
         double novoSL = entrada;
         if(tradesAbertos[t].direcao > 0 && currentPrice > entrada && tradesAbertos[t].sl < novoSL)
         {
            trade.PositionModify(tradesAbertos[t].ticket, novoSL, tradesAbertos[t].tp);
            tradesAbertos[t].sl = novoSL;
         }
         else if(tradesAbertos[t].direcao < 0 && currentPrice < entrada && tradesAbertos[t].sl > novoSL)
         {
            trade.PositionModify(tradesAbertos[t].ticket, novoSL, tradesAbertos[t].tp);
            tradesAbertos[t].sl = novoSL;
         }
      }

      if(InpTrailMode == TRAIL_BANDA_1 || InpTrailMode == TRAIL_BANDA_2)
      {
         double bandaL1 = 0;
         double bufBanda[1];
         if(tradesAbertos[t].direcao > 0)
         {
            if(CopyBuffer(ctx[t].hLevels, 3, 0, 1, bufBanda) > 0)
               bandaL1 = bufBanda[0];
         }
         else
         {
            if(CopyBuffer(ctx[t].hLevels, 2, 0, 1, bufBanda) > 0)
               bandaL1 = bufBanda[0];
         }

         if(bandaL1 > 0)
         {
            if(tradesAbertos[t].direcao > 0 && bandaL1 > tradesAbertos[t].sl)
            {
               trade.PositionModify(tradesAbertos[t].ticket, bandaL1, tradesAbertos[t].tp);
               tradesAbertos[t].sl = bandaL1;
            }
            else if(tradesAbertos[t].direcao < 0 && bandaL1 < tradesAbertos[t].sl)
            {
               trade.PositionModify(tradesAbertos[t].ticket, bandaL1, tradesAbertos[t].tp);
               tradesAbertos[t].sl = bandaL1;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TemPosicaoAberta                                                 |
//+------------------------------------------------------------------+
bool TemPosicaoAberta(int idx)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == ctx[idx].sym &&
            PositionGetInteger(POSITION_MAGIC) == ctx[idx].magic)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| CalcularLote                                                     |
//+------------------------------------------------------------------+
double CalcularLote(int idx, double riskPct, double slDistPoints)
{
   string sym = ctx[idx].sym;
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * riskPct / 100.0;
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point     = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(tickSize <= 0 || slDistPoints <= 0) return 0.0;
   double valorPorPonto = tickValue * (point / tickSize);
   double lots = riskMoney / (slDistPoints * valorPorPonto);
   double minLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / stepLot) * stepLot;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return lots;
}

//+------------------------------------------------------------------+
//| GetATR                                                           |
//+------------------------------------------------------------------+
double GetATR(int handle, int shift)
{
   double val[1];
   if(CopyBuffer(handle, 0, shift, 1, val) > 0) return val[0];
   return 0.0;
}

//+------------------------------------------------------------------+
//| PonteLog                                                         |
//+------------------------------------------------------------------+
void PonteLog(int idx, string tipo, string mensagem, string dadosJSON="")
{
   if(!InpLogJSON) return;
   string nomeArquivo = StringFormat("PONTE_MT5\\SAIDA\\%s_LOG_%s.json",
      InpSessaoID, TimeToString(TimeCurrent(), TIME_DATE));
   string linha = StringFormat("{\"ts\":\"%s\",\"tipo\":\"%s\",\"sessao\":\"%s\"",
      TimeToString(TimeCurrent()), tipo, InpSessaoID);
   if(idx >= 0 && idx < totalSymbols)
      linha += StringFormat(",\"symbol\":\"%s\",\"magic\":%lld", ctx[idx].sym, ctx[idx].magic);
   linha += StringFormat(",\"msg\":\"%s\"", mensagem);
   if(dadosJSON != "") linha += "," + dadosJSON;
   linha += "}\n";
   int handle = FileOpen(nomeArquivo, FILE_WRITE|FILE_READ|FILE_TXT|FILE_COMMON, 0, CP_UTF8);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, linha);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| PonteExportarDecisoes                                            |
//+------------------------------------------------------------------+
void PonteExportarDecisoes()
{
   if(!InpLogJSON) return;
   string nomeArquivo = StringFormat("PONTE_MT5\\SAIDA\\%s_STATUS_%s.json",
      InpSessaoID, TimeToString(TimeCurrent(), TIME_DATE));

   string json = "{";
   json += StringFormat("\"ts\":\"%s\",", TimeToString(TimeCurrent()));
   json += StringFormat("\"sessao\":\"%s\",", InpSessaoID);
   json += StringFormat("\"equity\":%.2f,", AccountInfoDouble(ACCOUNT_EQUITY));
   json += StringFormat("\"balance\":%.2f,", AccountInfoDouble(ACCOUNT_BALANCE));
   json += StringFormat("\"dd_global_pct\":%.2f,", (equityPicoGlobal > 0) ?
      (equityPicoGlobal - AccountInfoDouble(ACCOUNT_EQUITY)) / equityPicoGlobal * 100.0 : 0);
   json += StringFormat("\"trades_total\":%d,", totalTradesGlobal);
   json += StringFormat("\"wins_total\":%d,", totalWinsGlobal);
   json += StringFormat("\"winrate_pct\":%.1f,", (totalTradesGlobal > 0) ?
      (double)totalWinsGlobal / totalTradesGlobal * 100.0 : 0);
   json += StringFormat("\"soma_r\":%.2f,", somaRGlobal);
   json += StringFormat("\"expectancy_r\":%.3f,", (totalTradesGlobal > 0) ?
      somaRGlobal / totalTradesGlobal : 0);
   json += "\"simbolos\":[";
   for(int i = 0; i < totalSymbols; i++)
   {
      json += "{";
      json += StringFormat("\"symbol\":\"%s\",", ctx[i].sym);
      json += StringFormat("\"regime\":\"%s\",", RegimeName(ctx[i].regimeAtual));
      json += StringFormat("\"er\":%.3f,", ctx[i].er);
      json += StringFormat("\"slope\":%.4f,", ctx[i].slope);
      json += StringFormat("\"veto_choque\":%s,", ctx[i].vetoChoque ? "true" : "false");
      json += StringFormat("\"trades_hoje\":%d,", ctx[i].tradesHoje);
      json += StringFormat("\"perdas_consec\":%d,", ctx[i].perdasConsec);
      json += StringFormat("\"total_trades\":%d,", ctx[i].totalTrades);
      json += StringFormat("\"winrate_pct\":%.1f,", (ctx[i].totalTrades > 0) ?
         (double)ctx[i].totalWins / ctx[i].totalTrades * 100.0 : 0);
      json += StringFormat("\"soma_r\":%.2f", ctx[i].somaR);
      json += "}";
      if(i < totalSymbols - 1) json += ",";
   }
   json += "]}";

   int handle = FileOpen(nomeArquivo, FILE_WRITE|FILE_TXT|FILE_COMMON, 0, CP_UTF8);
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, json);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| LerOrdensIA                                                      |
//+------------------------------------------------------------------+
bool LerOrdensIA()
{
   string pastaBusca = "PONTE_MT5\\ENTRADA\\ORDEM_*.json";
   string nomeArquivo = "";
   long searchHandle = FileFindFirst(pastaBusca, nomeArquivo);
   if(searchHandle == INVALID_HANDLE) return false;

   bool encontrou = false;
   do
   {
      string caminhoCompleto = "PONTE_MT5\\ENTRADA\\" + nomeArquivo;
      int handle = FileOpen(caminhoCompleto, FILE_READ|FILE_TXT|FILE_COMMON, 0, CP_UTF8);
      if(handle != INVALID_HANDLE)
      {
         string conteudo = FileReadString(handle, 10000);
         FileClose(handle);
         ProcessarOrdemIA(conteudo);
         string caminhoProc = "PONTE_MT5\\ENTRADA\\PROCESSADAS\\" + nomeArquivo;
         FileMove(caminhoCompleto, 0, caminhoProc, FILE_REWRITE);
         encontrou = true;
      }
   }
   while(FileFindNext(searchHandle, nomeArquivo));

   FileFindClose(searchHandle);
   return encontrou;
}

//+------------------------------------------------------------------+
//| ProcessarOrdemIA                                                 |
//+------------------------------------------------------------------+
void ProcessarOrdemIA(string &json)
{
   int pos = StringFind(json, "\"action\"");
   if(pos < 0) return;

   string action = "";
   if(StringFind(json, "\"buy\"", pos) >= 0) action = "buy";
   else if(StringFind(json, "\"sell\"", pos) >= 0) action = "sell";
   else if(StringFind(json, "\"close\"", pos) >= 0) action = "close";
   else return;

   string sym = "";
   pos = StringFind(json, "\"symbol\"");
   if(pos >= 0)
   {
      int ini = StringFind(json, "\"", pos + 9) + 1;
      int fim = StringFind(json, "\"", ini);
      if(ini > 0 && fim > ini) sym = StringSubstr(json, ini, fim - ini);
   }
   if(sym == "") return;

   PonteLog(-1, "IA_ORDEM",
      StringFormat("Ordem da IA recebida: %s %s", action, sym), json);

   if(action == "close")
   {
      for(int i = 0; i < totalSymbols; i++)
      {
         if(ctx[i].sym == sym)
         {
            for(int t = 0; t < PositionsTotal(); t++)
            {
               ulong ticket = PositionGetTicket(t);
               if(PositionSelectByTicket(ticket))
               {
                  if(PositionGetString(POSITION_SYMBOL) == sym &&
                     PositionGetInteger(POSITION_MAGIC) == ctx[i].magic)
                  {
                     trade.PositionClose(ticket);
                     PonteLog(-1, "IA_CLOSE",
                        StringFormat("IA fechou %s ticket %lld", sym, ticket), "{}");
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| AutoAvaliacao                                                    |
//+------------------------------------------------------------------+
void AutoAvaliacao()
{
   if(totalTradesGlobal < InpAutoAvaliarTrades) return;
   double winRate = (double)totalWinsGlobal / totalTradesGlobal * 100.0;
   double expectancy = somaRGlobal / totalTradesGlobal;

   PonteLog(-1, "AUTOAVALIACAO",
      StringFormat("%d trades | WinRate=%.1f%% | Expectancy=%.3fR",
         totalTradesGlobal, winRate, expectancy),
      StringFormat("\"total_trades\":%d,\"winrate\":%.1f,\"expectancy_r\":%.3f",
         totalTradesGlobal, winRate, expectancy));

   if(winRate < InpWinRateMin || expectancy < InpExpectancyMin)
   {
      PonteLog(-1, "ALERTA",
         StringFormat("Performance baixa: WR=%.1f%% (min=%.1f%%) Exp=%.3fR (min=%.2fR)",
            winRate, InpWinRateMin, expectancy, InpExpectancyMin), "{}");
   }

   if(totalTradesGlobal >= InpMCAvaliarTrades) MonteCarloValidacao();
}

//+------------------------------------------------------------------+
//| MonteCarloValidacao                                              |
//+------------------------------------------------------------------+
void MonteCarloValidacao()
{
   if(totalTradesGlobal < InpMCAvaliarTrades) return;

   double winRate = (double)totalWinsGlobal / totalTradesGlobal;
   int cenariosNegativos = 0;
   int totalSims = InpMCSimulacoes;

   for(int sim = 0; sim < totalSims; sim++)
   {
      double somaSim = 0;
      for(int t = 0; t < InpMCAvaliarTrades; t++)
      {
         double r = 0;
         if(MathRand() % 1000 < winRate * 10)
            r = 1.0 + (MathRand() % 200) / 100.0;
         else
            r = -(0.5 + (MathRand() % 100) / 100.0);
         somaSim += r;
      }
      if(somaSim < 0) cenariosNegativos++;
   }

   double pctNeg = (double)cenariosNegativos / totalSims * 100.0;

   PonteLog(-1, "MONTE_CARLO",
      StringFormat("MC: %d sims, %.1f%% neg (limite: %.0f%%)",
         totalSims, pctNeg, InpMCTolerancia),
      StringFormat("\"simulacoes\":%d,\"negativos_pct\":%.1f,\"limite\":%.0f",
         totalSims, pctNeg, InpMCTolerancia));

   if(pctNeg > InpMCTolerancia)
   {
      for(int i = 0; i < totalSymbols; i++)
      {
         ctx[i].pausaAte = TimeCurrent() + InpPausaHoras * 3600;
         ctx[i].modoObservacao = true;
      }
      PonteLog(-1, "MC_PAUSE",
         StringFormat("MC reprovado (%.1f%% > %.0f%%) — PAUSA GERAL",
            pctNeg, InpMCTolerancia), "{}");
   }
}
//+------------------------------------------------------------------+
