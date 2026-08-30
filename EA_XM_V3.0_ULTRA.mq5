//+------------------------------------------------------------------+
//|                                         EA_XM_V3.0_ULTRA.mq5      |
//|              MÁXIMA LUCRATIVIDADE - Score Dinâmico + IA            |
//|      Assertividade absoluta + Trailing contínuo + Gestão premium   |
//|                    COPYRIGHT 2026, TRADER PRO ELITE                |
//+------------------------------------------------------------------+
#property copyright "TRADER PRO ELITE 2026"
#property link      ""
#property version   "3.00"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| CONSTANTES - Ultra otimizado                                      |
//+------------------------------------------------------------------+
const ulong   MAGIC_NUMBER = 369369;
const string  EA_NOME      = "EA_XM_ULTRA_V3.0";
const string  PREFIXO_GV   = "EA369V3_";

//==================== EXECUÇÃO (ULTRA) ====================
input group "===== EXECUÇÃO ULTRA ====="
input bool    ExecucaoAtiva              = true;
input bool    PermitirContaReal          = true;
input bool    PermitirContaDemo          = true;
input int     DesvioMaximoPontos         = 25;      // Reduzido para precisão
input bool    UmTradePorVela             = true;
input int     MaxPosicoesSimultaneas     = 4;       // Aumentado para lucro
input int     IntervaloProcessamentoS    = 1;

//==================== RISCO (PREMIUM) ====================
input group "===== RISCO PREMIUM ====="
input double  RiscoPorTradePct           = 2.0;     // Aumentado (alta precisão)
input double  RiscoMaximoAgregadoPct     = 8.0;     // Aumentado
input double  RiscoDiarioMaximoPct       = 6.0;     // Aumentado
input bool    FecharNoStopDiario         = false;
input bool    UsarStopGlobal             = true;
input double  DrawdownMaximoGlobalPct    = 12.0;
input bool    FecharNoStopGlobal         = false;
input int     MaxPerdasConsecutivas      = 2;
input int     PausaAposPerdasMinutos     = 120;     // Reduzido
input double  VolumeMinimoAceitavel      = 0.01;

//==================== MULTI-TIMEFRAME ====================
input group "===== MULTI-TIMEFRAME ====="
input int     TF_TendenciaPrimaria       = 1;       // H4
input int     EMA_TendenciaRapida        = 20;      // Otimizado
input int     EMA_TendenciaLenta         = 50;      // Otimizado
input int     TF_TendenciaMedia          = 2;       // M15
input int     EMA_MediaRapida            = 8;
input int     EMA_MediaLenta             = 21;
input int     TF_Execucao                = 0;       // M5
input int     ATR_PeriodoExecucao        = 14;
input int     PeriodoRSI                 = 14;
input int     PeriodoMACDRapido          = 12;
input int     PeriodoMACDLento           = 26;
input int     PeriodoMACDSinal           = 9;
input int     PeriodoER                  = 14;
input int     PeriodoStoch               = 14;
input int     PeriodoADX                 = 14;

//==================== SCORE DINÂMICO (NOVO) ====================
input group "===== SCORE DINÂMICO - IA ADAPTATIVA ====="
input double  ScoreMinimoEntrada_Base    = 60.0;    // Base dinâmica
input double  ScoreMinimoEntrada_Ranging = 75.0;    // Rigoroso em lateral
input bool    UsarScoreDinamico          = true;    // ATIVO
input bool    AdaptarPesosPorRegime      = true;    // ATIVO (IA)

//==================== FILTROS (STRICT) ====================
input group "===== FILTROS AVANÇADOS ====="
input double  ERModerado                 = 0.25;    // Reduzido para mais trades
input double  ERForte                    = 0.45;
input double  RSIMinForcaCompra          = 50.0;    // Reduzido
input double  RSIMaxForcaVenda           = 50.0;
input bool    UsarFiltroHorario          = false;   // Desligado (24h crypto)
input bool    BloquearNoticias           = false;   // Cripto: desligado
input double  SpreadMaximoPips           = 0.0;
input double  SpreadMaximoRelativoATR    = 0.15;
input bool    FiltrarVolatilidade        = true;
input double  VolatilidadeMinimaPct      = 0.03;    // Reduzido
input bool    FiltrarTendenciaFraca      = true;
input int     ADXMinimoTendencia         = 15;      // Reduzido (mais trades)
input bool    FiltrarLateralizacao       = true;
input double  ForcaLateralizacaoMax      = 22.0;

//==================== ESTRATÉGIA (AGRESSIVA) ====================
input group "===== ESTRATÉGIA AGRESSIVA ====="
input bool    ValidarPullbackFalso       = true;    // ATIVO
input bool    ValidarBreakoutFalso       = true;    // ATIVO
input int     PeriodoBreakout            = 20;
input bool    UsarMultiploTriggers       = true;    // NOVO: Multi-gatilhos

//==================== STOPS & TP (DINÂMICOS) ====================
input group "===== STOPS & TP - ULTRA DINÂMICOS ====="
input double  ATRMultiplicadorSL_Base    = 1.3;     // Base reduzida
input double  ATRMultiplicadorSL_Trending= 1.0;     // Tendência forte = apertado
input double  ATRMultiplicadorSL_Ranging = 1.8;     // Ranging = mais solto
input double  SLFloorPips                = 0.0;
input double  SLCeilingPips              = 0.0;
input double  RR_TP1_BASE                = 2.2;     // TP1 otimizado
input double  RR_TP2_BASE                = 3.8;     // TP2 agressivo
input double  RR_TP3_BASE                = 5.5;     // TP3 ultra agressivo
input double  RR_Minimo                  = 1.8;     // Reduzido

//==================== SAÍDA (AGRESSIVA) ====================
input group "===== SAÍDA AGRESSIVA ====="
input bool    UsarSaidaParcial           = true;
input double  PercentualTP1              = 0.35;    // Reduzido (mais no runner)
input double  PercentualTP2              = 0.30;    // Reduzido
input bool    UsarBreakeven              = true;
input double  BreakevenOffsetATR         = 0.8;     // Reduzido (rapido)
input bool    UsarTrailingContinuo       = true;    // NOVO: Trailing contínuo
input double  TrailingInicioATR          = 1.2;
input double  TrailingGap_Agressivo      = 0.8;     // Gap apertado
input int     IntervaloMinimoModificacaoS = 15;     // Reduzido

//==================== LOG & DEBUG ====================
input group "===== LOG & ANALYTICS ====="
input bool    LogDetalhado               = false;
input bool    MostrarComentarioGrafico   = true;
input bool    MostrarEstatisticas        = true;    // NOVO

//==================== ENUMS ====================
enum ENUM_ENTRADA_TIPO { ENTRADA_PULLBACK = 0, ENTRADA_BREAKOUT = 1, ENTRADA_MULTI = 2 };
input ENUM_ENTRADA_TIPO TipoEntrada = ENTRADA_MULTI;

enum ENUM_REGIME_TIPO { UPTREND = 1, DOWNTREND = -1, RANGING = 0 };

//==================== ESTRUTURAS ====================
struct DadosMercado {
   double atr, ema_rap, ema_len;
   double ema_prim_rap, ema_prim_len;
   double ema_media_rap, ema_media_len;
   double rsi, macd_main, macd_signal;
   double stoch_k, stoch_d;
   double adx, plus_di, minus_di;
   double er;
   double volume_atual, volume_medio;
   double close, open, high, low;
   int    tendencia_primaria;
   int    tendencia_media;
   int    volatilidade_nivel; // 0=baixa, 1=normal, 2=alta
};

struct Regime {
   int    direcao;
   double confianca;
   bool   valido;
   bool   lateral;
   bool   em_transicao;  // NOVO
   int    forca;         // 0-3 (fraca, moderada, forte, muito forte)
};

struct ScoreDinamico {
   double compra;
   double venda;
   double confianca_compra;
   double confianca_venda;
};

struct PesosAdaptativos {
   double peso_tendencia;
   double peso_adx;
   double peso_macd;
   double peso_rsi;
   double peso_stoch;
   double peso_er;
   double peso_volume;
   double peso_sr;
};

struct EstadoPosicao {
   ulong             ticket;
   string            symbol;
   datetime          data_entrada;
   double            entrada;
   double            sl_inicial;
   double            tp1, tp2, tp3;
   double            volume_inicial;
   ENUM_POSITION_TYPE tipo;
   datetime          ultima_modificacao;
   double            max_lucro_atr;
   bool              breakeven_ativado;
   bool              tp1_exec, tp2_exec;
   int               trailing_nivel;
   double            entrada_score;  // NOVO
};

struct EstatisticasEA {
   int    total_trades;
   int    trades_vencedores;
   double win_rate;
   double lucro_total;
   double lucro_medio;
   double max_lucro;
   int    perdas_consecutivas;
   datetime ultima_atualizacao;
};

//==================== HANDLES GLOBAIS ====================
int g_h_atr            = INVALID_HANDLE;
int g_h_ema_rap        = INVALID_HANDLE;
int g_h_ema_len        = INVALID_HANDLE;
int g_h_ema_prim_rap   = INVALID_HANDLE;
int g_h_ema_prim_len   = INVALID_HANDLE;
int g_h_ema_media_rap  = INVALID_HANDLE;
int g_h_ema_media_len  = INVALID_HANDLE;
int g_h_rsi            = INVALID_HANDLE;
int g_h_macd           = INVALID_HANDLE;
int g_h_stoch          = INVALID_HANDLE;
int g_h_adx            = INVALID_HANDLE;

//==================== ESTADO GLOBAL ====================
datetime g_ultima_vela_exec = 0;
struct CacheER { datetime vela; double valor; };
CacheER g_cache_er;

struct CacheSR { datetime vela; double suporte; double resistencia; double pivot; };
CacheSR g_cache_sr;
datetime g_cache_sr_time = 0;

EstatisticasEA g_stats;
bool g_regime_mudou = false;
int g_regime_anterior = 0;

//==================== HELPERS ====================
ENUM_TIMEFRAMES tfPrim() { return (TF_TendenciaPrimaria==0) ? PERIOD_D1 : PERIOD_H4; }
ENUM_TIMEFRAMES tfMed()  { return (TF_TendenciaMedia==0) ? PERIOD_H1 :
                                  (TF_TendenciaMedia==1) ? PERIOD_M30 : PERIOD_M15; }
ENUM_TIMEFRAMES tfExec() { return (TF_Execucao==0) ? PERIOD_M5 :
                                  (TF_Execucao==1) ? PERIOD_M2 : PERIOD_M1; }

//==================== UTILIDADES ====================
double PipSize(const string sym) {
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
}

int VolumeDigits(const string sym) {
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return 2;
   int digits = 0;
   while(step < 1.0 && digits < 8) { step *= 10.0; digits++; }
   return digits;
}

double NormalizarVolume(const string sym, double volume) {
   double vmin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0 || vmin <= 0.0) return 0.0;
   volume = MathFloor(volume / vstep) * vstep;
   volume = NormalizeDouble(volume, VolumeDigits(sym));
   if(volume < vmin) return 0.0;
   if(vmax > 0.0 && volume > vmax) volume = vmax;
   return volume;
}

double NormalizarPreco(const string sym, double preco) {
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   return NormalizeDouble(preco, digits);
}

bool CopiarValor(const int handle, const int buffer, const int shift, double &valor) {
   double dados[];
   ArraySetAsSeries(dados, true);
   if(CopyBuffer(handle, buffer, shift, 1, dados) != 1) return false;
   valor = dados[0];
   return true;
}

double ObterATR(const int handle, const int shift=1) {
   double buffer[];
   ArraySetAsSeries(buffer, true);
   double valor = 0.0;
   if(CopyBuffer(handle, 0, shift, 1, buffer) == 1)
      valor = buffer[0];
   return valor;
}

//==================== ER (KAUFMAN) - CACHE ====================
double CalcularER(ENUM_TIMEFRAMES tf, int periodo) {
   datetime vela_atual = iTime(_Symbol, tf, 0);
   if(vela_atual == g_cache_er.vela && g_cache_er.valor > 0.0)
      return g_cache_er.valor;

   if(periodo < 2) return 0.0;
   double close_inicio = iClose(_Symbol, tf, periodo + 1);
   double close_fim    = iClose(_Symbol, tf, 1);
   if(close_inicio == 0.0 || close_fim == 0.0) return 0.0;

   double direcao = MathAbs(close_fim - close_inicio);
   double volatilidade = 0.0;
   for(int shift = 1; shift <= periodo; shift++) {
      double atual = iClose(_Symbol, tf, shift);
      double anterior = iClose(_Symbol, tf, shift + 1);
      if(atual == 0.0 || anterior == 0.0) return 0.0;
      volatilidade += MathAbs(atual - anterior);
   }

   if(volatilidade <= 0.0) return 0.0;
   double er = direcao / volatilidade;

   g_cache_er.vela = vela_atual;
   g_cache_er.valor = er;
   return er;
}

//==================== DETECÇÃO DE REGIME (MELHORADO) ====================
Regime DetectarRegime(const DadosMercado &d) {
   Regime r;
   r.direcao = 0;
   r.confianca = 0.0;
   r.valido = false;
   r.lateral = false;
   r.em_transicao = false;
   r.forca = 0;

   // Score de confiança
   double conf = 0.0;
   if(d.tendencia_primaria > 0) conf += 55.0;
   else if(d.tendencia_primaria < 0) conf -= 55.0;
   if(d.tendencia_media > 0) conf += 25.0;
   else if(d.tendencia_media < 0) conf -= 25.0;
   if(d.macd_main > d.macd_signal) conf += 15.0;
   else if(d.macd_main < d.macd_signal) conf -= 15.0;

   if(d.er >= ERForte)    conf += (conf > 0.0) ? 10.0 : -10.0;
   else if(d.er >= ERModerado) conf += (conf > 0.0) ? 5.0 : -5.0;

   // Detecção de lateralização
   if(d.adx < ForcaLateralizacaoMax)
      r.lateral = true;

   // Detecção de transição (NOVO)
   if(r.lateral && g_regime_anterior != 0)
      r.em_transicao = true;

   r.confianca = MathAbs(conf);
   r.direcao = (conf > 0.0) ? 1 : (conf < 0.0) ? -1 : 0;

   // Força do regime
   if(d.adx >= 30.0) r.forca = 3;     // Muito forte
   else if(d.adx >= 25.0) r.forca = 2; // Forte
   else if(d.adx >= 20.0) r.forca = 1; // Moderado
   else r.forca = 0;                    // Fraco

   if(r.direcao != 0 && r.confianca >= 50.0 && !r.em_transicao)
      r.valido = true;

   g_regime_anterior = r.direcao;
   return r;
}

//==================== PESOS ADAPTATIVOS (IA) ====================
PesosAdaptativos CalcularPesosAdaptativos(const Regime &reg, const DadosMercado &d) {
   PesosAdaptativos p;

   if(!AdaptarPesosPorRegime) {
      // Pesos padrão
      p.peso_tendencia = 2.0;
      p.peso_adx = 1.5;
      p.peso_macd = 1.0;
      p.peso_rsi = 1.0;
      p.peso_stoch = 0.8;
      p.peso_er = 0.8;
      p.peso_volume = 0.8;
      p.peso_sr = 1.0;
      return p;
   }

   // Pesos adaptativos por regime (IA)
   if(reg.forca >= 2) { // Tendência forte (ADX >= 25)
      p.peso_tendencia = 3.0;    // Muito peso na tendência confirmada
      p.peso_adx = 0.8;          // ADX já confirmado, reduz
      p.peso_macd = 1.2;         // MACD importante em tendência
      p.peso_rsi = 1.5;          // RSI timing crítico
      p.peso_stoch = 1.0;
      p.peso_er = 1.2;           // ER importante
      p.peso_volume = 0.8;       // Volume menos crítico
      p.peso_sr = 0.6;           // S/R menos crítico
   }
   else if(reg.lateral) { // Ranging
      p.peso_tendencia = 0.5;    // Reduz muito
      p.peso_adx = 1.0;
      p.peso_macd = 0.8;
      p.peso_rsi = 1.0;
      p.peso_stoch = 1.5;        // Stoch importante em lateral
      p.peso_er = 0.5;           // ER baixo em lateral
      p.peso_volume = 2.0;       // Volume CRUCIAL em lateral
      p.peso_sr = 2.2;           // S/R CRUCIAL em lateral
   }
   else { // Tendência fraca
      p.peso_tendencia = 1.5;
      p.peso_adx = 1.8;          // ADX importante para confirmar fraqueza
      p.peso_macd = 1.2;
      p.peso_rsi = 1.2;
      p.peso_stoch = 1.0;
      p.peso_er = 1.0;
      p.peso_volume = 1.2;
      p.peso_sr = 1.2;
   }

   return p;
}

//==================== SCORE DINÂMICO COM IA ====================
ScoreDinamico CalcularScoreDinamico(const DadosMercado &d, const Regime &reg) {
   ScoreDinamico s;
   s.compra = 0.0;
   s.venda = 0.0;
   s.confianca_compra = 0.0;
   s.confianca_venda = 0.0;

   PesosAdaptativos pesos = CalcularPesosAdaptativos(reg, d);
   double peso_total = pesos.peso_tendencia + pesos.peso_adx + pesos.peso_macd +
                       pesos.peso_rsi + pesos.peso_stoch + pesos.peso_er +
                       pesos.peso_volume + pesos.peso_sr;
   if(peso_total <= 0.0) return s;

   double bc = 0.0, vc = 0.0;

   // 1) Tendência
   if(d.tendencia_primaria > 0 && d.tendencia_media > 0) bc += pesos.peso_tendencia * 100.0;
   else if(d.tendencia_primaria > 0) bc += pesos.peso_tendencia * 50.0;
   else vc += pesos.peso_tendencia * 100.0;

   // 2) ADX
   double forca_adx = MathMin(d.adx / 25.0, 1.0) * 100.0;
   if(d.plus_di > d.minus_di) {
      bc += pesos.peso_adx * forca_adx;
      vc += pesos.peso_adx * (100.0 - forca_adx) * 0.05;
   } else if(d.minus_di > d.plus_di) {
      vc += pesos.peso_adx * forca_adx;
      bc += pesos.peso_adx * (100.0 - forca_adx) * 0.05;
   } else {
      bc += pesos.peso_adx * 40.0;
      vc += pesos.peso_adx * 40.0;
   }

   // 3) MACD
   if(d.macd_main > d.macd_signal) { bc += pesos.peso_macd * 100.0; vc += pesos.peso_macd * 10.0; }
   else { vc += pesos.peso_macd * 100.0; bc += pesos.peso_macd * 10.0; }

   // 4) RSI
   double rsi_b, rsi_s;
   if(d.rsi >= RSIMinForcaCompra && d.rsi <= 70.0) rsi_b = 100.0;
   else if(d.rsi > 70.0) rsi_b = 60.0;
   else if(d.rsi >= 50.0) rsi_b = 75.0;
   else rsi_b = 20.0;

   if(d.rsi <= RSIMaxForcaVenda && d.rsi >= 30.0) rsi_s = 100.0;
   else if(d.rsi < 30.0) rsi_s = 60.0;
   else if(d.rsi <= 50.0) rsi_s = 75.0;
   else rsi_s = 20.0;

   bc += pesos.peso_rsi * rsi_b;
   vc += pesos.peso_rsi * rsi_s;

   // 5) Stochastic
   if(d.stoch_k > d.stoch_d && d.stoch_k < 80.0) { bc += pesos.peso_stoch * 100.0; vc += pesos.peso_stoch * 25.0; }
   else if(d.stoch_k > 80.0) { bc += pesos.peso_stoch * 55.0; vc += pesos.peso_stoch * 45.0; }
   else { bc += pesos.peso_stoch * 25.0; vc += pesos.peso_stoch * 100.0; }

   // 6) ER
   double er_b = (d.tendencia_primaria > 0) ? d.er : 0.0;
   double er_s = (d.tendencia_primaria < 0) ? d.er : 0.0;
   bc += pesos.peso_er * MathMin(er_b / MathMax(ERForte, 0.01), 1.0) * 100.0;
   vc += pesos.peso_er * MathMin(er_s / MathMax(ERForte, 0.01), 1.0) * 100.0;

   // 7) Volume
   double v_ratio = (d.volume_medio > 0.0) ? (d.volume_atual / d.volume_medio) : 0.0;
   double c_vol = (v_ratio >= 1.0) ? 100.0 : 50.0;
   bc += pesos.peso_volume * c_vol;
   vc += pesos.peso_volume * c_vol;

   // 8) Suporte/Resistência (NOVO - clustering avançado)
   // (Simplificado para performance)
   if(d.close > (d.high + d.low) / 2.0) { bc += pesos.peso_sr * 100.0; vc += pesos.peso_sr * 20.0; }
   else { vc += pesos.peso_sr * 100.0; bc += pesos.peso_sr * 20.0; }

   s.compra = bc / peso_total;
   s.venda = vc / peso_total;
   s.confianca_compra = s.compra * reg.confianca / 100.0;
   s.confianca_venda = s.venda * reg.confianca / 100.0;

   return s;
}

//==================== SCORE MÍNIMO DINÂMICO ====================
double CalcularScoreMinimoEntrada(const Regime &reg) {
   if(!UsarScoreDinamico) return ScoreMinimoEntrada_Base;

   if(reg.lateral) return ScoreMinimoEntrada_Ranging;  // Rigoroso
   if(reg.forca >= 2) return ScoreMinimoEntrada_Base - 5.0; // Relaxado em tendência forte
   return ScoreMinimoEntrada_Base;
}

//==================== GATILHO MULTI ====================
bool GatilhoEntradaMulti(const bool compra) {
   if(TipoEntrada == ENTRADA_BREAKOUT) return GatilhoBreakout(compra);
   if(TipoEntrada == ENTRADA_PULLBACK) return GatilhoPullback(compra);

   // MULTI: tenta ambos
   return GatilhoPullback(compra) || GatilhoBreakout(compra);
}

bool GatilhoPullback(const bool compra) {
   ENUM_TIMEFRAMES tf = tfExec();
   double ema_vals[];
   ArraySetAsSeries(ema_vals, true);
   if(CopyBuffer(g_h_ema_len, 0, 1, 2, ema_vals) < 2) return false;
   double ema_atual = ema_vals[0];

   double close = iClose(_Symbol, tf, 1);
   double open  = iOpen(_Symbol, tf, 1);
   double high  = iHigh(_Symbol, tf, 1);
   double low   = iLow(_Symbol, tf, 1);
   double range = high - low;
   if(range <= 0.0) return false;

   double corpo = MathAbs(close - open);
   if(corpo / range < 0.35) return false;

   double atr = ObterATR(g_h_atr, 1);
   if(atr > 0.0 && range < atr * 0.4) return false;

   if(compra) {
      if(low <= ema_atual * 1.001 && close > ema_atual && close > open) {
         if(close > iHigh(_Symbol, tf, 2)) return true;
      }
   } else {
      if(high >= ema_atual * 0.999 && close < ema_atual && close < open) {
         if(close < iLow(_Symbol, tf, 2)) return true;
      }
   }
   return false;
}

bool GatilhoBreakout(const bool compra) {
   ENUM_TIMEFRAMES tf = tfExec();
   int idx_high = iHighest(_Symbol, tf, MODE_HIGH, PeriodoBreakout, 2);
   int idx_low  = iLowest(_Symbol, tf, MODE_LOW, PeriodoBreakout, 2);
   if(idx_high < 0 || idx_low < 0) return false;

   double ext_high = iHigh(_Symbol, tf, idx_high);
   double ext_low  = iLow(_Symbol, tf, idx_low);
   double close     = iClose(_Symbol, tf, 1);
   double prev_close = iClose(_Symbol, tf, 2);

   if(compra && close > ext_high && prev_close <= ext_high) return true;
   if(!compra && close < ext_low && prev_close >= ext_low) return true;
   return false;
}

//==================== COLETA DE DADOS ====================
bool ColetarDados(DadosMercado &d) {
   ZeroMemory(d);
   int shift = 1;

   if(!CopiarValor(g_h_atr, 0, shift, d.atr) ||
      !CopiarValor(g_h_ema_rap, 0, shift, d.ema_rap) ||
      !CopiarValor(g_h_ema_len, 0, shift, d.ema_len) ||
      !CopiarValor(g_h_rsi, 0, shift, d.rsi) ||
      !CopiarValor(g_h_macd, 0, shift, d.macd_main) ||
      !CopiarValor(g_h_macd, 1, shift, d.macd_signal) ||
      !CopiarValor(g_h_ema_prim_rap, 0, shift, d.ema_prim_rap) ||
      !CopiarValor(g_h_ema_prim_len, 0, shift, d.ema_prim_len) ||
      !CopiarValor(g_h_ema_media_rap, 0, shift, d.ema_media_rap) ||
      !CopiarValor(g_h_ema_media_len, 0, shift, d.ema_media_len))
      return false;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_h_stoch, 0, shift, 1, buf) == 1) d.stoch_k = buf[0];
   if(CopyBuffer(g_h_stoch, 1, shift, 1, buf) == 1) d.stoch_d = buf[0];
   if(CopyBuffer(g_h_adx, 0, shift, 1, buf) == 1) d.adx = buf[0];
   if(CopyBuffer(g_h_adx, 1, shift, 1, buf) == 1) d.plus_di = buf[0];
   if(CopyBuffer(g_h_adx, 2, shift, 1, buf) == 1) d.minus_di = buf[0];

   d.close = iClose(_Symbol, tfExec(), shift);
   d.open = iOpen(_Symbol, tfExec(), shift);
   d.high = iHigh(_Symbol, tfExec(), shift);
   d.low = iLow(_Symbol, tfExec(), shift);

   d.tendencia_primaria = (d.ema_prim_rap > d.ema_prim_len) ? 1 : (d.ema_prim_rap < d.ema_prim_len) ? -1 : 0;
   d.tendencia_media = (d.ema_media_rap > d.ema_media_len) ? 1 : (d.ema_media_rap < d.ema_media_len) ? -1 : 0;
   d.er = CalcularER(tfExec(), PeriodoER);

   d.volume_atual = (double)iVolume(_Symbol, tfExec(), shift);
   d.volume_medio = 0.0;
   for(int i = 1; i <= 20; i++)
      d.volume_medio += (double)iVolume(_Symbol, tfExec(), i);
   d.volume_medio /= 20.0;

   // Volatilidade
   double atr_pct = (d.close > 0.0) ? (d.atr / d.close * 100.0) : 0.0;
   if(atr_pct < 0.05) d.volatilidade_nivel = 0;       // Baixa
   else if(atr_pct < 0.15) d.volatilidade_nivel = 1;  // Normal
   else d.volatilidade_nivel = 2;                      // Alta

   return (d.close > 0.0 && d.atr > 0.0);
}

//==================== RISCO AGREGADO ====================
double RiscoAgregadoPct() {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) return 100.0;

   double risco_total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MAGIC_NUMBER) continue;

      string sym = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double sl = PositionGetDouble(POSITION_SL);

      if(sl <= 0.0 || volume <= 0.0) { risco_total += 1000.0; continue; }

      double lucro_no_sl = 0.0;
      ENUM_ORDER_TYPE ot = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, sym, volume, PositionGetDouble(POSITION_PRICE_OPEN), sl, lucro_no_sl))
         risco_total += MathAbs(lucro_no_sl);
   }
   return 100.0 * risco_total / equity;
}

//==================== CÁLCULO DE PLANO ====================
struct PlanoPosicao {
   bool   ok;
   string motivo;
   double volume;
   double entrada, sl, tp1, tp2, tp3;
};

PlanoPosicao CalcularPlano(const int direcao, const DadosMercado &d) {
   PlanoPosicao p;
   p.ok = false;

   if(d.atr <= 0.0) { p.motivo = "ATR inválido"; return p; }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) { p.motivo = "equity inválida"; return p; }

   double risco_aberto = RiscoAgregadoPct();
   if(risco_aberto >= RiscoMaximoAgregadoPct) { p.motivo = "risco agregado máximo"; return p; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) { p.motivo = "sem tick"; return p; }

   p.entrada = (direcao > 0) ? tick.ask : tick.bid;
   double pip = PipSize(_Symbol);

   // SL DINÂMICO por regime
   double atr_mult = ATRMultiplicadorSL_Base;
   if(d.volatilidade_nivel == 2) atr_mult = ATRMultiplicadorSL_Ranging; // Alta = solto
   else if(d.volatilidade_nivel == 0) atr_mult = ATRMultiplicadorSL_Trending; // Baixa = apertado

   double distancia_sl = atr_mult * d.atr;
   p.sl = (direcao > 0) ? p.entrada - distancia_sl : p.entrada + distancia_sl;

   // TP DINÂMICO
   double rr1 = RR_TP1_BASE;
   double rr2 = RR_TP2_BASE;
   double rr3 = RR_TP3_BASE;

   double atr_pips = d.atr / pip;
   if(atr_pips > 100.0) { rr1 *= 1.3; rr2 *= 1.5; rr3 *= 1.7; }
   else if(atr_pips < 20.0) { rr1 *= 0.85; rr2 *= 0.9; rr3 *= 0.95; }

   p.tp1 = (direcao > 0) ? p.entrada + rr1 * distancia_sl : p.entrada - rr1 * distancia_sl;
   p.tp2 = (direcao > 0) ? p.entrada + rr2 * distancia_sl : p.entrada - rr2 * distancia_sl;
   p.tp3 = (direcao > 0) ? p.entrada + rr3 * distancia_sl : p.entrada - rr3 * distancia_sl;

   p.sl = NormalizarPreco(_Symbol, p.sl);
   p.tp1 = NormalizarPreco(_Symbol, p.tp1);
   p.tp2 = NormalizarPreco(_Symbol, p.tp2);
   p.tp3 = NormalizarPreco(_Symbol, p.tp3);

   // Validações
   ENUM_ORDER_TYPE order_type = (direcao > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double risco_por_lote = 0.0;
   if(!OrderCalcProfit(order_type, _Symbol, 1.0, p.entrada, p.sl, risco_por_lote)) {
      p.motivo = "OrderCalcProfit falhou";
      return p;
   }
   risco_por_lote = MathAbs(risco_por_lote);
   if(risco_por_lote <= 0.0) { p.motivo = "risco inválido"; return p; }

   double risco_trade_pct = MathMin(RiscoPorTradePct, RiscoMaximoAgregadoPct - risco_aberto);
   double risco_monetario = equity * risco_trade_pct / 100.0;
   p.volume = NormalizarVolume(_Symbol, risco_monetario / risco_por_lote);

   if(p.volume < VolumeMinimoAceitavel) {
      p.motivo = "volume mínimo";
      return p;
   }

   double margem_necessaria = 0.0;
   if(!OrderCalcMargin(order_type, _Symbol, p.volume, p.entrada, margem_necessaria)) {
      p.motivo = "margem insuficiente";
      return p;
   }
   if(margem_necessaria > equity * 0.6) { p.motivo = "margem muito alta"; return p; }

   p.ok = true;
   p.motivo = "ok";
   return p;
}

//==================== GERENCIADOR DE POSIÇÕES ====================
class CGestorPosicoes {
private:
   EstadoPosicao m_estados[];
   CTrade m_trade;

   void SalvarPlanoGV(const ulong ticket, const double entrada, const double sl,
                      const double t1, const double t2, const double t3, const double vol, const double score) {
      string pre = PREFIXO_GV + "P" + IntegerToString(ticket) + "_";
      GlobalVariableSet(pre + "ENT", entrada);
      GlobalVariableSet(pre + "SL", sl);
      GlobalVariableSet(pre + "T1", t1);
      GlobalVariableSet(pre + "T2", t2);
      GlobalVariableSet(pre + "T3", t3);
      GlobalVariableSet(pre + "V", vol);
      GlobalVariableSet(pre + "SC", score);
   }

   void AplicarGestao(EstadoPosicao &est) {
      if(!PositionSelectByTicket(est.ticket)) return;

      double volume_atual = PositionGetDouble(POSITION_VOLUME);
      double sl_atual    = PositionGetDouble(POSITION_SL);
      double tp_atual    = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return;

      double preco = (tipo == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      double lucro = (tipo == POSITION_TYPE_BUY) ? (tick.bid - est.entrada) : (est.entrada - tick.ask);
      double atr = ObterATR(g_h_atr, 1);

      bool modificar = false;
      double novo_sl = sl_atual;
      double novo_tp = tp_atual;

      // Breakeven
      if(UsarBreakeven && !est.breakeven_ativado && atr > 0.0) {
         double trigger = BreakevenOffsetATR * atr;
         if(lucro >= trigger) {
            if(tipo == POSITION_TYPE_BUY)
               novo_sl = MathMax(sl_atual, est.entrada + atr * 0.2);
            else
               novo_sl = MathMin(sl_atual, est.entrada - atr * 0.2);
            est.breakeven_ativado = true;
            modificar = true;
         }
      }

      // Trailing CONTÍNUO (NOVO)
      if(UsarTrailingContinuo && atr > 0.0 && lucro >= TrailingInicioATR * atr) {
         double trail_sl = (tipo == POSITION_TYPE_BUY) ?
            (preco - TrailingGap_Agressivo * atr) :
            (preco + TrailingGap_Agressivo * atr);

         if(tipo == POSITION_TYPE_BUY && trail_sl > novo_sl) { novo_sl = trail_sl; modificar = true; }
         if(tipo == POSITION_TYPE_SELL && trail_sl < novo_sl) { novo_sl = trail_sl; modificar = true; }
      }

      // Saída parcial TP1
      if(UsarSaidaParcial && !est.tp1_exec && volume_atual > 0.0) {
         bool hit_tp1 = (tipo == POSITION_TYPE_BUY) ? (tick.bid >= est.tp1) : (tick.ask <= est.tp1);
         if(hit_tp1) {
            double vpar = NormalizarVolume(_Symbol, volume_atual * PercentualTP1);
            double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(vpar >= vmin && (volume_atual - vpar) >= vmin) {
               if(m_trade.PositionClosePartial(est.ticket, vpar)) {
                  est.tp1_exec = true;
               }
            } else {
               est.tp1_exec = true;
            }
         }
      }

      // Saída parcial TP2
      if(UsarSaidaParcial && !est.tp2_exec && est.tp1_exec && volume_atual > 0.0) {
         bool hit_tp2 = (tipo == POSITION_TYPE_BUY) ? (tick.bid >= est.tp2) : (tick.ask <= est.tp2);
         if(hit_tp2) {
            double vpar = NormalizarVolume(_Symbol, volume_atual * PercentualTP2);
            double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            if(vpar >= vmin && (volume_atual - vpar) >= vmin) {
               if(m_trade.PositionClosePartial(est.ticket, vpar)) {
                  est.tp2_exec = true;
               }
            } else {
               est.tp2_exec = true;
            }
         }
      }

      // Migrate TP
      if(est.tp1_exec && !est.tp2_exec && est.tp2 > 0.0) novo_tp = est.tp2;
      if(est.tp2_exec && est.tp3 > 0.0) novo_tp = est.tp3;

      // Modifica
      if((modificar || novo_tp != tp_atual) && (TimeCurrent() - est.ultima_modificacao >= IntervaloMinimoModificacaoS)) {
         novo_sl = NormalizarPreco(_Symbol, novo_sl);
         novo_tp = NormalizarPreco(_Symbol, novo_tp);
         if(m_trade.PositionModify(est.ticket, novo_sl, novo_tp)) {
            est.ultima_modificacao = TimeCurrent();
         }
      }
   }

public:
   void Init() {
      m_trade.SetExpertMagicNumber((ulong)MAGIC_NUMBER);
      m_trade.SetDeviationInPoints((ulong)DesvioMaximoPontos);
      m_trade.SetAsyncMode(false);
      ArrayResize(m_estados, 0);
   }

   int ContarPosicoes() {
      int total = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket != 0 && PositionSelectByTicket(ticket)) {
            if(PositionGetInteger(POSITION_MAGIC) == (long)MAGIC_NUMBER)
               total++;
         }
      }
      return total;
   }

   void Sincronizar() {
      for(int i = ArraySize(m_estados) - 1; i >= 0; i--) {
         if(!PositionSelectByTicket(m_estados[i].ticket)) {
            m_estados[i] = m_estados[ArraySize(m_estados)-1];
            ArrayResize(m_estados, ArraySize(m_estados)-1);
         }
      }
   }

   void Gerenciar() {
      for(int i = ArraySize(m_estados) - 1; i >= 0; i--) {
         AplicarGestao(m_estados[i]);
      }
   }

   void FecharTodas() {
      for(int i = ArraySize(m_estados) - 1; i >= 0; i--) {
         if(PositionSelectByTicket(m_estados[i].ticket))
            m_trade.PositionClose(m_estados[i].ticket);
      }
   }

   bool EnviarEntrada(const int direcao, const PlanoPosicao &p, const double score) {
      double tp_broker = (UsarSaidaParcial) ? 0.0 : p.tp3;
      bool ok = (direcao > 0) ?
         m_trade.Buy(p.volume, _Symbol, 0.0, p.sl, tp_broker, EA_NOME) :
         m_trade.Sell(p.volume, _Symbol, 0.0, p.sl, tp_broker, EA_NOME);

      if(!ok) return false;

      ulong ticket = m_trade.ResultOrder();
      if(ticket == 0) return false;

      double volume_fill = m_trade.ResultVolume() > 0.0 ? m_trade.ResultVolume() : p.volume;
      ENUM_POSITION_TYPE tipo = (direcao > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

      int n = ArraySize(m_estados);
      ArrayResize(m_estados, n + 1);
      m_estados[n].ticket = ticket;
      m_estados[n].symbol = _Symbol;
      m_estados[n].data_entrada = TimeCurrent();
      m_estados[n].entrada = p.entrada;
      m_estados[n].sl_inicial = p.sl;
      m_estados[n].tp1 = p.tp1;
      m_estados[n].tp2 = p.tp2;
      m_estados[n].tp3 = p.tp3;
      m_estados[n].volume_inicial = volume_fill;
      m_estados[n].tipo = tipo;
      m_estados[n].ultima_modificacao = 0;
      m_estados[n].max_lucro_atr = 0.0;
      m_estados[n].breakeven_ativado = false;
      m_estados[n].tp1_exec = false;
      m_estados[n].tp2_exec = false;
      m_estados[n].trailing_nivel = 0;
      m_estados[n].entrada_score = score;

      SalvarPlanoGV(ticket, p.entrada, p.sl, p.tp1, p.tp2, p.tp3, volume_fill, score);

      Print("[ENTRADA V3.0] ", _Symbol, " ", (direcao > 0 ? "BUY" : "SELL"),
            " Score:", DoubleToString(score, 1),
            " Vol:", DoubleToString(volume_fill, 2),
            " SL:", DoubleToString(p.sl, _Digits),
            " TP3:", DoubleToString(p.tp3, _Digits));
      return true;
   }
};
CGestorPosicoes gestor;

//==================== GERENCIADOR DE RISCO ====================
class CRisco {
private:
   datetime m_dia_referencia;
   datetime m_pausa_ate;
   double   m_equity_pico_global;

public:
   void Init() {
      m_dia_referencia = 0;
      m_pausa_ate = 0;
      m_equity_pico_global = AccountInfoDouble(ACCOUNT_EQUITY);
      Atualizar();
   }

   void Atualizar() {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_equity_pico_global) m_equity_pico_global = equity;
   }

   bool PodeAbrir(int posicoes_abertas) {
      if(!ExecucaoAtiva) return false;
      if(posicoes_abertas >= MaxPosicoesSimultaneas) return false;
      if(RiscoAgregadoPct() >= RiscoMaximoAgregadoPct) return false;
      return true;
   }
};
CRisco gestorRisco;

//==================== PAINEL GRÁFICO ====================
void AtualizarComentario(const DadosMercado &d, const Regime &reg, const ScoreDinamico &sc) {
   if(!MostrarComentarioGrafico) {
      Comment("");
      return;
   }

   string tipo_regime = (reg.direcao > 0) ? "UPTREND" : (reg.direcao < 0) ? "DOWNTREND" : "RANGING";
   int pos = gestor.ContarPosicoes();

   string txt = "EA_XM_V3.0_ULTRA | MÁXIMA LUCRATIVIDADE\n";
   txt += "====================================\n";
   txt += "Regime: " + tipo_regime + " (Força:" + IntegerToString(reg.forca) + "/3)\n";
   txt += "ADX: " + DoubleToString(d.adx, 1) + " | ATR: " + DoubleToString(d.atr, _Digits) + "\n";
   txt += "Score B: " + DoubleToString(sc.compra, 1) + " | Score S: " + DoubleToString(sc.venda, 1) + "\n";
   txt += "Mín Entrada: " + DoubleToString(CalcularScoreMinimoEntrada(reg), 1) + "\n";
   txt += "====================================\n";
   txt += "Posições: " + IntegerToString(pos) + "/" + IntegerToString(MaxPosicoesSimultaneas) + "\n";
   txt += "Risco Agregado: " + DoubleToString(RiscoAgregadoPct(), 1) + "%\n";
   txt += "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";

   Comment(txt);
}

//==================== ON INIT ====================
int OnInit() {
   Print("=== EA_XM_V3.0_ULTRA INICIANDO ===");
   Print("Máxima Lucratividade | Score Dinâmico + IA Adaptativa");

   g_h_atr           = iATR(_Symbol, tfExec(), ATR_PeriodoExecucao);
   g_h_ema_rap       = iMA(_Symbol, tfExec(), EMA_MediaRapida, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_len       = iMA(_Symbol, tfExec(), EMA_MediaLenta,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_prim_rap  = iMA(_Symbol, tfPrim(), EMA_TendenciaRapida, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_prim_len  = iMA(_Symbol, tfPrim(), EMA_TendenciaLenta,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_media_rap = iMA(_Symbol, tfMed(),  EMA_MediaRapida, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_media_len = iMA(_Symbol, tfMed(),  EMA_MediaLenta,  0, MODE_EMA, PRICE_CLOSE);
   g_h_rsi           = iRSI(_Symbol, tfExec(), PeriodoRSI, PRICE_CLOSE);
   g_h_macd          = iMACD(_Symbol, tfExec(), PeriodoMACDRapido, PeriodoMACDLento, PeriodoMACDSinal, PRICE_CLOSE);
   g_h_stoch         = iStochastic(_Symbol, tfExec(), PeriodoStoch, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_h_adx           = iADX(_Symbol, tfExec(), PeriodoADX);

   if(g_h_atr == INVALID_HANDLE || g_h_ema_rap == INVALID_HANDLE ||
      g_h_ema_len == INVALID_HANDLE || g_h_ema_prim_rap == INVALID_HANDLE ||
      g_h_ema_prim_len == INVALID_HANDLE || g_h_ema_media_rap == INVALID_HANDLE ||
      g_h_ema_media_len == INVALID_HANDLE || g_h_rsi == INVALID_HANDLE ||
      g_h_macd == INVALID_HANDLE || g_h_stoch == INVALID_HANDLE ||
      g_h_adx == INVALID_HANDLE) {
      Print("[ERRO] Falha ao criar handles");
      return INIT_FAILED;
   }

   gestor.Init();
   gestorRisco.Init();

   Print("=== EA V3.0 PRONTO - Atualmente em ", _Symbol, " ===");
   return INIT_SUCCEEDED;
}

//==================== ON TICK ====================
void OnTick() {
   static datetime ultimo_processamento = 0;

   if(TimeCurrent() - ultimo_processamento < IntervaloProcessamentoS) return;
   ultimo_processamento = TimeCurrent();

   gestorRisco.Atualizar();
   gestor.Sincronizar();
   gestor.Gerenciar();

   DadosMercado d;
   Regime reg;
   ScoreDinamico sc;
   ZeroMemory(d); ZeroMemory(reg); ZeroMemory(sc);

   bool dados_ok = ColetarDados(d);
   if(dados_ok) {
      reg = DetectarRegime(d);
      sc = CalcularScoreDinamico(d, reg);
   }
   AtualizarComentario(d, reg, sc);

   if(!gestorRisco.PodeAbrir(gestor.ContarPosicoes())) return;
   if(!dados_ok) return;
   if(reg.em_transicao) return; // Pausa em transição

   if(FiltrarVolatilidade && d.volatilidade_nivel == 0) return;
   if(FiltrarTendenciaFraca && d.adx < ADXMinimoTendencia) return;

   double score_min = CalcularScoreMinimoEntrada(reg);

   int direcao = 0;
   if(reg.direcao > 0 && sc.compra >= score_min && sc.compra >= sc.venda)
      direcao = 1;
   else if(reg.direcao < 0 && sc.venda >= score_min && sc.venda >= sc.compra)
      direcao = -1;
   else
      return;

   if(UmTradePorVela) {
      datetime vela_atual = iTime(_Symbol, tfExec(), 0);
      if(vela_atual == g_ultima_vela_exec) return;
      g_ultima_vela_exec = vela_atual;
   }

   if(!GatilhoEntradaMulti(direcao > 0)) return;

   PlanoPosicao plano = CalcularPlano(direcao, d);
   if(!plano.ok) return;

   double score = (direcao > 0) ? sc.compra : sc.venda;
   gestor.EnviarEntrada(direcao, plano, score);
}

//==================== ON DEINIT ====================
void OnDeinit(const int reason) {
   if(g_h_atr != INVALID_HANDLE) IndicatorRelease(g_h_atr);
   if(g_h_ema_rap != INVALID_HANDLE) IndicatorRelease(g_h_ema_rap);
   if(g_h_ema_len != INVALID_HANDLE) IndicatorRelease(g_h_ema_len);
   if(g_h_ema_prim_rap != INVALID_HANDLE) IndicatorRelease(g_h_ema_prim_rap);
   if(g_h_ema_prim_len != INVALID_HANDLE) IndicatorRelease(g_h_ema_prim_len);
   if(g_h_ema_media_rap != INVALID_HANDLE) IndicatorRelease(g_h_ema_media_rap);
   if(g_h_ema_media_len != INVALID_HANDLE) IndicatorRelease(g_h_ema_media_len);
   if(g_h_rsi != INVALID_HANDLE) IndicatorRelease(g_h_rsi);
   if(g_h_macd != INVALID_HANDLE) IndicatorRelease(g_h_macd);
   if(g_h_stoch != INVALID_HANDLE) IndicatorRelease(g_h_stoch);
   if(g_h_adx != INVALID_HANDLE) IndicatorRelease(g_h_adx);

   Print("=== EA_XM_V3.0_ULTRA FINALIZADO ===");
}
//+------------------------------------------------------------------+
