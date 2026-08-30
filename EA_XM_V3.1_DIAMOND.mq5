//+------------------------------------------------------------------+
//|                                       EA_XM_V3.1_DIAMOND.mq5      |
//|   Consolidacao auditada: V2.01 (robustez) + V3.0 (score adaptativo)|
//|                                                                    |
//|   Correcoes desta versao (todas verificadas no codigo):            |
//|    - Todas as protecoes de risco REALMENTE ligadas ao motor        |
//|    - Ticket da posicao obtido via DEAL_POSITION_ID                 |
//|    - SetTypeFillingBySymbol + validacao de STOPS/FREEZE level      |
//|    - Persistencia e restauracao de estado (GlobalVariables)        |
//|    - Suporte/Resistencia por clustering real                       |
//|    - Score normalizado em [0..100] (calibrado)                     |
//|    - Volume como multiplicador de conviccao (nao componente)       |
//|    - Deteccao de transicao de regime por BARRA (nao por tick)      |
//|    - Risco adaptativo anti-martingale por win-rate real + drawdown |
//|    - Estatisticas de historico em passe unico (sem bug de selecao) |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property link      ""
#property version   "3.10"
#property description "EA auditado - single symbol - MT5"

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| CONSTANTES                                                        |
//+------------------------------------------------------------------+
#define  EA_NOME     "EA_XM_V3.1"
#define  PREFIXO_GV  "XM31_"

//==================== EXECUCAO ====================
input group "===== EXECUCAO ====="
input ulong   InpMagic                   = 310310;  // Magic number
input bool    ExecucaoAtiva              = true;    // Habilita novas entradas
input bool    PermitirContaReal          = false;   // Permitir conta REAL (ligar so apos validar)
input bool    PermitirContaDemo          = true;    // Permitir conta demo
input int     DesvioMaximoPontos         = 30;      // Desvio maximo (pontos)
input bool    UmTradePorVela             = true;    // Uma entrada por vela
input int     MaxPosicoesSimultaneas     = 2;       // Max posicoes simultaneas
input int     CooldownEntreTradesSeg     = 120;     // Cooldown entre entradas (seg)
input int     IntervaloProcessamentoS    = 1;       // Intervalo minimo OnTick (seg)

//==================== RISCO ====================
input group "===== RISCO (todos ativos) ====="
input double  RiscoPorTradePct           = 0.75;    // Risco base por trade (% equity)
input double  RiscoMinPorTradePct        = 0.25;    // Piso do risco adaptativo
input double  RiscoMaxPorTradePct        = 1.50;    // Teto do risco adaptativo
input double  RiscoMaximoAgregadoPct     = 3.0;     // Risco agregado maximo (%)
input double  RiscoDiarioMaximoPct       = 4.0;     // Stop diario (% equity)
input bool    FecharNoStopDiario         = true;    // Fecha posicoes no stop diario
input bool    UsarStopGlobal             = true;    // Ativa stop global de equity
input double  DrawdownMaximoGlobalPct    = 10.0;    // Drawdown global maximo (%)
input bool    FecharNoStopGlobal         = true;    // Fecha posicoes no stop global
input int     MaxPerdasConsecutivas      = 3;       // Perdas consecutivas p/ pausa
input int     PausaAposPerdasMinutos     = 240;     // Pausa apos perdas (min)
input double  VolumeMinimoAceitavel      = 0.01;    // Volume minimo aceitavel
input double  MargemMaximaUtilizadaPct   = 30.0;    // % max da equity em margem

//==================== RISCO ADAPTATIVO ====================
input group "===== RISCO ADAPTATIVO (anti-martingale) ====="
input bool    UsarRiscoAdaptativo        = true;    // Ajusta risco por win-rate real
input int     HistoricoTradesAnalise     = 30;      // Trades analisados
input int     MinTradesParaAdaptar       = 15;      // Minimo p/ confiar na estatistica
input bool    ReduzirRiscoEmDrawdown     = true;    // Reduz risco durante drawdown

//==================== MULTI-TIMEFRAME ====================
input group "===== MULTI-TIMEFRAME ====="
input ENUM_TIMEFRAMES TF_Primario        = PERIOD_H4;  // TF tendencia primaria
input ENUM_TIMEFRAMES TF_Medio           = PERIOD_M15; // TF tendencia media
input ENUM_TIMEFRAMES TF_Exec            = PERIOD_M5;  // TF de execucao
input int     EMA_PrimRapida             = 20;
input int     EMA_PrimLenta              = 50;
input int     EMA_MedRapida              = 8;
input int     EMA_MedLenta               = 21;
input int     ATR_Periodo                = 14;
input int     PeriodoRSI                 = 14;
input int     PeriodoMACDRapido          = 12;
input int     PeriodoMACDLento           = 26;
input int     PeriodoMACDSinal           = 9;
input int     PeriodoER                  = 14;
input int     PeriodoStoch               = 14;
input int     PeriodoADX                 = 14;

//==================== SCORE ====================
input group "===== SCORE (normalizado 0..100) ====="
input double  ScoreMinimo_Tendencia      = 62.0;    // Score min em tendencia forte
input double  ScoreMinimo_Base           = 66.0;    // Score min padrao
input double  ScoreMinimo_Lateral        = 74.0;    // Score min em lateral
input bool    AdaptarPesosPorRegime      = true;    // Pesos adaptativos por regime
input bool    OperarEmLateral            = false;   // Permitir entradas em lateral
input int     BarrasBloqueioTransicao    = 3;       // Barras bloqueadas apos virada de regime

//==================== PESOS BASE ====================
input group "===== PESOS BASE DO SCORE ====="
input double  PesoTendencia              = 2.0;
input double  PesoADX                    = 1.5;
input double  PesoMACD                   = 1.0;
input double  PesoRSI                    = 1.0;
input double  PesoStoch                  = 0.8;
input double  PesoER                     = 0.8;
input double  PesoSR                     = 1.2;

//==================== FILTROS ====================
input group "===== FILTROS ====="
input double  ERModerado                 = 0.25;
input double  ERForte                    = 0.45;
input bool    UsarFiltroHorario          = false;   // Filtro de horario (off p/ cripto 24h)
input int     HoraInicioGMT              = 7;
input int     HoraFimGMT                 = 20;
input bool    BloquearNoticias           = false;   // Bloqueia noticias de alto impacto
input int     MinAntesNoticia            = 30;
input int     MinDepoisNoticia           = 30;
input double  SpreadMaximoPips           = 0.0;     // Cap fixo em pips (0 = usa razao ATR)
input double  SpreadMaximoRelativoATR    = 0.10;    // Spread max / ATR
input bool    FiltrarVolatilidade        = true;    // Exige volatilidade minima
input double  VolatilidadeMinimaPct      = 0.05;    // ATR minimo (% do preco)
input bool    FiltrarVolatilidadeMax     = true;    // Bloqueia volatilidade extrema
input double  VolatilidadeMaximaPct      = 3.00;    // ATR maximo (% do preco)
input int     ADXMinimoTendencia         = 20;      // ADX min p/ considerar tendencia
input double  ADXLateralMax              = 20.0;    // ADX abaixo disso = lateral

//==================== ENTRADA ====================
input group "===== ESTRATEGIA DE ENTRADA ====="
enum ENUM_ENTRADA_TIPO { ENTRADA_PULLBACK = 0, ENTRADA_BREAKOUT = 1, ENTRADA_AMBOS = 2 };
input ENUM_ENTRADA_TIPO TipoEntrada      = ENTRADA_AMBOS;
input bool    ValidarPullbackFalso       = true;    // Valida pullback (volume + S/R)
input bool    ValidarBreakoutFalso       = true;    // Valida breakout (volume + corpo)
input int     PeriodoBreakout            = 20;
input double  VolumeMinimoRelativo       = 1.15;    // Volume/media p/ validar rompimento
input int     PeriodoVolume              = 20;
input int     PeriodoSuporteResistencia  = 60;      // Barras p/ cluster de S/R
input double  ToleranciaClusterSR        = 0.30;    // Tolerancia do cluster (x ATR)

//==================== STOPS E TP ====================
input group "===== STOPS E TAKE PROFIT ====="
input double  ATRMultSL_VolBaixa         = 1.8;     // SL x ATR quando vol BAIXA
input double  ATRMultSL_VolNormal        = 1.5;     // SL x ATR quando vol NORMAL
input double  ATRMultSL_VolAlta          = 1.2;     // SL x ATR quando vol ALTA
input double  SLFloorPips                = 0.0;     // Piso do SL em pips (0 = 0.5 ATR)
input double  SLCeilingPips              = 0.0;     // Teto do SL em pips (0 = 3.0 ATR)
input double  RR_TP1                     = 1.5;
input double  RR_TP2                     = 2.5;
input double  RR_TP3                     = 4.0;
input double  RR_Minimo                  = 1.5;     // R:R minimo aceito (vs TP1)

//==================== SAIDA ====================
input group "===== GESTAO DE SAIDA ====="
input bool    UsarSaidaParcial           = true;
input double  PercentualTP1              = 0.40;    // Fracao fechada no TP1
input double  PercentualTP2              = 0.30;    // Fracao fechada no TP2
input bool    UsarBreakeven              = true;
input double  BreakevenGatilhoATR        = 1.0;     // Lucro (x ATR) p/ mover a BE
input double  BreakevenOffsetATR         = 0.15;    // Offset acima da entrada (x ATR)
input bool    UsarTrailing               = true;
input double  TrailingInicioATR          = 1.5;     // Lucro (x ATR) p/ iniciar trailing
input double  TrailingGapATR             = 1.0;     // Distancia do trailing (x ATR)
input double  TrailingGapApertadoATR     = 0.7;     // Distancia apos TP2 (x ATR)
input int     IntervaloMinimoModificacaoS= 20;      // Throttle entre modificacoes (seg)

//==================== LOG ====================
input group "===== LOG E PAINEL ====="
input bool    LogDetalhado               = true;
input bool    MostrarPainel              = true;

//+------------------------------------------------------------------+
//| ESTRUTURAS                                                        |
//+------------------------------------------------------------------+
struct DadosMercado
  {
   double   atr;
   double   ema_prim_rap, ema_prim_len;
   double   ema_med_rap,  ema_med_len;
   double   ema_exec_len;
   double   rsi;
   double   macd_main, macd_signal;
   double   stoch_k, stoch_d;
   double   adx, plus_di, minus_di;
   double   er;
   double   volume_atual, volume_medio;
   double   close, open, high, low;
   double   atr_pct;
   int      tend_prim, tend_med;
   int      vol_nivel;        // 0 = baixa, 1 = normal, 2 = alta
  };

struct NiveisSR
  {
   double   suporte;
   double   resistencia;
   bool     valido;
  };

struct Regime
  {
   int      direcao;          // +1 alta, -1 baixa, 0 indefinido
   double   confianca;        // 0..100
   bool     lateral;
   int      forca;            // 0..3
  };

struct Score
  {
   double   compra;           // 0..100
   double   venda;            // 0..100 (= 100 - compra)
   double   conviccao;        // multiplicador de volume aplicado
  };

struct Pesos
  {
   double   tendencia, adx, macd, rsi, stoch, er, sr;
  };

struct PlanoPosicao
  {
   bool     ok;
   string   motivo;
   double   volume;
   double   entrada, sl, tp1, tp2, tp3;
   double   risco_pct;
  };

struct EstadoPosicao
  {
   ulong             ticket;
   double            entrada;
   double            tp1, tp2, tp3;
   double            volume_inicial;
   ENUM_POSITION_TYPE tipo;
   datetime          ultima_modificacao;
   bool              breakeven_ativado;
   bool              tp1_exec, tp2_exec;
   double            score_entrada;
  };

struct Estatisticas
  {
   int      total;
   int      vitorias;
   double   win_rate;         // 0..1
   double   lucro_total;
   double   payoff;           // media ganho / media perda
   int      perdas_consecutivas;
   datetime calculado_em;
  };

//+------------------------------------------------------------------+
//| ESTADO GLOBAL                                                     |
//+------------------------------------------------------------------+
int g_h_atr = INVALID_HANDLE, g_h_rsi = INVALID_HANDLE, g_h_macd = INVALID_HANDLE;
int g_h_stoch = INVALID_HANDLE, g_h_adx = INVALID_HANDLE;
int g_h_ema_prim_rap = INVALID_HANDLE, g_h_ema_prim_len = INVALID_HANDLE;
int g_h_ema_med_rap  = INVALID_HANDLE, g_h_ema_med_len  = INVALID_HANDLE;
int g_h_ema_exec_len = INVALID_HANDLE;

datetime g_ultima_vela_entrada = 0;
datetime g_ultima_entrada      = 0;

// cache ER
datetime g_er_vela = 0;   double g_er_valor = 0.0;
// cache S/R
datetime g_sr_vela = 0;   NiveisSR g_sr_cache;
// regime por barra (para detectar transicao de verdade)
datetime g_regime_vela      = 0;
int      g_regime_dir_ant   = 0;
int      g_barras_desde_virada = 999;

Estatisticas g_stats;
bool  g_calendario_ok = true;

//+------------------------------------------------------------------+
//| UTILIDADES                                                        |
//+------------------------------------------------------------------+
double PipSize()
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (digits == 3 || digits == 5) ? point * 10.0 : point;
  }

int VolumeDigits()
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return 2;
   int d = 0;
   while(step < 1.0 && d < 8) { step *= 10.0; d++; }
   return d;
  }

double NormalizarVolume(double volume)
  {
   double vmin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0 || vmin <= 0.0) return 0.0;
   volume = MathFloor(volume / vstep) * vstep;
   volume = NormalizeDouble(volume, VolumeDigits());
   if(volume < vmin) return 0.0;
   if(vmax > 0.0 && volume > vmax) volume = vmax;
   return volume;
  }

double NormalizarPreco(double preco)
  {
   return NormalizeDouble(preco, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

// Distancia minima exigida pelo broker para SL/TP (stops level e freeze level)
double DistanciaMinimaBroker()
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stops   = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double d = (double)MathMax(stops, freeze) * point;
   // margem de seguranca: brokers com stops_level = 0 ainda podem rejeitar colado no preco
   MqlTick t;
   if(SymbolInfoTick(_Symbol, t) && t.ask > t.bid)
      d = MathMax(d, (t.ask - t.bid) * 1.5);
   return d;
  }

double Clamp(double v, double lo, double hi)
  {
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
  }

bool LerBuffer(const int handle, const int buffer, const int shift, double &valor)
  {
   if(handle == INVALID_HANDLE) return false;
   double dados[];
   ArraySetAsSeries(dados, true);
   if(CopyBuffer(handle, buffer, shift, 1, dados) != 1) return false;
   if(dados[0] == EMPTY_VALUE || !MathIsValidNumber(dados[0])) return false;
   valor = dados[0];
   return true;
  }

double ObterATR(const int shift = 1)
  {
   double v = 0.0;
   if(!LerBuffer(g_h_atr, 0, shift, v)) return 0.0;
   return v;
  }

bool HorarioEmFaixa(const int hora, const int inicio, const int fim)
  {
   if(inicio == fim) return true;
   if(inicio < fim)  return (hora >= inicio && hora < fim);
   return (hora >= inicio || hora < fim);
  }

bool HorarioPermitido()
  {
   if(!UsarFiltroHorario) return true;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return HorarioEmFaixa(dt.hour, HoraInicioGMT, HoraFimGMT);
  }

//+------------------------------------------------------------------+
//| FILTRO DE SPREAD (ativo de verdade)                               |
//+------------------------------------------------------------------+
bool SpreadAceitavel(string &motivo)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) { motivo = "sem tick"; return false; }
   if(tick.ask <= tick.bid)           { motivo = "tick invalido"; return false; }

   double pip = PipSize();
   if(pip <= 0.0) { motivo = "pip invalido"; return false; }
   double spread_pips = (tick.ask - tick.bid) / pip;

   if(SpreadMaximoPips > 0.0)
     {
      if(spread_pips > SpreadMaximoPips)
        { motivo = StringFormat("spread %.1f > %.1f pips", spread_pips, SpreadMaximoPips); return false; }
      return true;
     }

   double atr = ObterATR(1);
   if(atr <= 0.0) return true;               // sem ATR nao bloqueia
   double atr_pips = atr / pip;
   if(atr_pips <= 0.0) return true;

   double razao = spread_pips / atr_pips;
   if(razao > SpreadMaximoRelativoATR)
     { motivo = StringFormat("spread/ATR %.3f > %.3f", razao, SpreadMaximoRelativoATR); return false; }
   return true;
  }

//+------------------------------------------------------------------+
//| EFICIENCIA DE KAUFMAN (com cache por vela)                        |
//+------------------------------------------------------------------+
double CalcularER()
  {
   datetime vela = iTime(_Symbol, TF_Exec, 0);
   if(vela == g_er_vela && g_er_valor > 0.0) return g_er_valor;
   if(PeriodoER < 2) return 0.0;

   double c_ini = iClose(_Symbol, TF_Exec, PeriodoER + 1);
   double c_fim = iClose(_Symbol, TF_Exec, 1);
   if(c_ini <= 0.0 || c_fim <= 0.0) return 0.0;

   double direcao = MathAbs(c_fim - c_ini);
   double volat = 0.0;
   for(int s = 1; s <= PeriodoER; s++)
     {
      double a = iClose(_Symbol, TF_Exec, s);
      double b = iClose(_Symbol, TF_Exec, s + 1);
      if(a <= 0.0 || b <= 0.0) return 0.0;
      volat += MathAbs(a - b);
     }
   if(volat <= 0.0) return 0.0;

   g_er_valor = direcao / volat;
   g_er_vela  = vela;
   return g_er_valor;
  }

//+------------------------------------------------------------------+
//| SUPORTE / RESISTENCIA POR CLUSTERING REAL (restaurado)            |
//+------------------------------------------------------------------+
void AdicionarNivel(double &niveis[], int &pesos[], const double valor, const double tol)
  {
   if(valor <= 0.0) return;
   int n = ArraySize(niveis);
   for(int i = 0; i < n; i++)
      if(MathAbs(niveis[i] - valor) <= tol)
        {
         // media ponderada pelo numero de toques (cluster mais forte "puxa" menos)
         niveis[i] = (niveis[i] * pesos[i] + valor) / (pesos[i] + 1);
         pesos[i]  = pesos[i] + 1;
         return;
        }
   ArrayResize(niveis, n + 1);
   ArrayResize(pesos,  n + 1);
   niveis[n] = valor;
   pesos[n]  = 1;
  }

NiveisSR CalcularSR()
  {
   datetime vela = iTime(_Symbol, TF_Exec, 0);
   if(vela == g_sr_vela && g_sr_cache.valido) return g_sr_cache;

   NiveisSR nv;
   nv.suporte = 0.0; nv.resistencia = 0.0; nv.valido = false;

   double atr = ObterATR(1);
   if(atr <= 0.0) return nv;
   double tol = atr * ToleranciaClusterSR;

   double niveis[]; int pesos[];
   ArrayResize(niveis, 0); ArrayResize(pesos, 0);

   for(int i = 1; i <= PeriodoSuporteResistencia; i++)
     {
      double h = iHigh(_Symbol, TF_Exec, i);
      double l = iLow(_Symbol, TF_Exec, i);
      if(h > 0.0) AdicionarNivel(niveis, pesos, h, tol);
      if(l > 0.0) AdicionarNivel(niveis, pesos, l, tol);
     }

   double preco = iClose(_Symbol, TF_Exec, 1);
   if(preco <= 0.0) return nv;

   // considera apenas clusters com >= 2 toques (nivel testado de verdade)
   double sup = 0.0, res = 0.0;
   for(int i = 0; i < ArraySize(niveis); i++)
     {
      if(pesos[i] < 2) continue;
      double n = niveis[i];
      if(n < preco && n > sup) sup = n;
      if(n > preco && (res == 0.0 || n < res)) res = n;
     }

   // fallback: se nao ha cluster testado, usa extremos do periodo
   if(sup <= 0.0)
     {
      int il = iLowest(_Symbol, TF_Exec, MODE_LOW, PeriodoSuporteResistencia, 1);
      sup = (il >= 0) ? iLow(_Symbol, TF_Exec, il) : preco - atr * 2.0;
     }
   if(res <= 0.0)
     {
      int ih = iHighest(_Symbol, TF_Exec, MODE_HIGH, PeriodoSuporteResistencia, 1);
      res = (ih >= 0) ? iHigh(_Symbol, TF_Exec, ih) : preco + atr * 2.0;
     }

   nv.suporte = sup;
   nv.resistencia = res;
   nv.valido = (res > sup);

   g_sr_cache = nv;
   g_sr_vela  = vela;
   return nv;
  }

//+------------------------------------------------------------------+
//| COLETA DE DADOS                                                   |
//+------------------------------------------------------------------+
bool ColetarDados(DadosMercado &d)
  {
   ZeroMemory(d);
   const int shift = 1;

   if(!LerBuffer(g_h_atr, 0, shift, d.atr))                    return false;
   if(!LerBuffer(g_h_ema_prim_rap, 0, shift, d.ema_prim_rap))  return false;
   if(!LerBuffer(g_h_ema_prim_len, 0, shift, d.ema_prim_len))  return false;
   if(!LerBuffer(g_h_ema_med_rap,  0, shift, d.ema_med_rap))   return false;
   if(!LerBuffer(g_h_ema_med_len,  0, shift, d.ema_med_len))   return false;
   if(!LerBuffer(g_h_ema_exec_len, 0, shift, d.ema_exec_len))  return false;
   if(!LerBuffer(g_h_rsi,  0, shift, d.rsi))                   return false;
   if(!LerBuffer(g_h_macd, 0, shift, d.macd_main))             return false;
   if(!LerBuffer(g_h_macd, 1, shift, d.macd_signal))           return false;
   if(!LerBuffer(g_h_stoch,0, shift, d.stoch_k))               return false;
   if(!LerBuffer(g_h_stoch,1, shift, d.stoch_d))               return false;
   if(!LerBuffer(g_h_adx,  0, shift, d.adx))                   return false;
   if(!LerBuffer(g_h_adx,  1, shift, d.plus_di))               return false;
   if(!LerBuffer(g_h_adx,  2, shift, d.minus_di))              return false;

   d.close = iClose(_Symbol, TF_Exec, shift);
   d.open  = iOpen (_Symbol, TF_Exec, shift);
   d.high  = iHigh (_Symbol, TF_Exec, shift);
   d.low   = iLow  (_Symbol, TF_Exec, shift);
   if(d.close <= 0.0 || d.atr <= 0.0) return false;

   d.tend_prim = (d.ema_prim_rap > d.ema_prim_len) ? 1 : (d.ema_prim_rap < d.ema_prim_len) ? -1 : 0;
   d.tend_med  = (d.ema_med_rap  > d.ema_med_len)  ? 1 : (d.ema_med_rap  < d.ema_med_len)  ? -1 : 0;
   d.er = CalcularER();

   d.volume_atual = (double)iVolume(_Symbol, TF_Exec, shift);
   double soma = 0.0;
   int n = MathMax(PeriodoVolume, 1);
   for(int i = 1; i <= n; i++) soma += (double)iVolume(_Symbol, TF_Exec, i);
   d.volume_medio = soma / n;

   d.atr_pct = d.atr / d.close * 100.0;
   // classificacao de volatilidade relativa ao proprio ativo
   if(d.atr_pct < VolatilidadeMinimaPct * 2.0)      d.vol_nivel = 0;   // baixa
   else if(d.atr_pct > VolatilidadeMaximaPct * 0.5) d.vol_nivel = 2;   // alta
   else                                             d.vol_nivel = 1;   // normal

   return true;
  }

//+------------------------------------------------------------------+
//| REGIME (com deteccao de transicao POR BARRA)                      |
//+------------------------------------------------------------------+
Regime DetectarRegime(const DadosMercado &d)
  {
   Regime r;
   r.direcao = 0; r.confianca = 0.0; r.lateral = false; r.forca = 0;

   double conf = 0.0;
   if(d.tend_prim > 0)      conf += 55.0;
   else if(d.tend_prim < 0) conf -= 55.0;
   if(d.tend_med > 0)       conf += 25.0;
   else if(d.tend_med < 0)  conf -= 25.0;
   if(d.macd_main > d.macd_signal) conf += 12.0; else conf -= 12.0;
   if(d.er >= ERForte)        conf += (conf > 0.0) ? 8.0 : -8.0;
   else if(d.er >= ERModerado)conf += (conf > 0.0) ? 4.0 : -4.0;

   r.direcao   = (conf > 0.0) ? 1 : (conf < 0.0) ? -1 : 0;
   r.confianca = MathAbs(conf);
   r.lateral   = (d.adx < ADXLateralMax);

   if(d.adx >= 30.0)      r.forca = 3;
   else if(d.adx >= 25.0) r.forca = 2;
   else if(d.adx >= ADXMinimoTendencia) r.forca = 1;
   else                   r.forca = 0;

   // transicao: comparada apenas quando FECHA uma nova vela de execucao
   datetime vela = iTime(_Symbol, TF_Exec, 0);
   if(vela != g_regime_vela)
     {
      g_regime_vela = vela;
      if(g_regime_dir_ant != 0 && r.direcao != 0 && r.direcao != g_regime_dir_ant)
         g_barras_desde_virada = 0;
      else if(g_barras_desde_virada < 100000)
         g_barras_desde_virada++;
      if(r.direcao != 0) g_regime_dir_ant = r.direcao;
     }

   return r;
  }

bool EmTransicaoDeRegime()
  {
   return (g_barras_desde_virada < BarrasBloqueioTransicao);
  }

//+------------------------------------------------------------------+
//| PESOS ADAPTATIVOS                                                 |
//+------------------------------------------------------------------+
Pesos CalcularPesos(const Regime &reg)
  {
   Pesos p;
   p.tendencia = PesoTendencia; p.adx = PesoADX; p.macd = PesoMACD;
   p.rsi = PesoRSI; p.stoch = PesoStoch; p.er = PesoER; p.sr = PesoSR;

   if(!AdaptarPesosPorRegime) return p;

   if(reg.forca >= 2 && !reg.lateral)
     {
      // tendencia estabelecida: seguir a tendencia pesa mais, S/R pesa menos
      p.tendencia *= 1.5;
      p.adx       *= 0.7;
      p.macd      *= 1.2;
      p.rsi       *= 1.2;
      p.er        *= 1.3;
      p.sr        *= 0.7;
     }
   else if(reg.lateral)
     {
      // lateral: S/R e timing dominam, tendencia perde relevancia
      p.tendencia *= 0.4;
      p.adx       *= 0.8;
      p.macd      *= 0.7;
      p.stoch     *= 1.8;
      p.er        *= 0.5;
      p.sr        *= 2.0;
     }
   return p;
  }

//+------------------------------------------------------------------+
//| SCORE NORMALIZADO 0..100                                          |
//| Cada componente devolve direcao em [-1..+1]; media ponderada;      |
//| volume entra como MULTIPLICADOR de conviccao (nao como componente) |
//+------------------------------------------------------------------+
Score CalcularScore(const DadosMercado &d, const Regime &reg)
  {
   Score s;
   s.compra = 50.0; s.venda = 50.0; s.conviccao = 1.0;

   Pesos w = CalcularPesos(reg);
   double soma_pesos = w.tendencia + w.adx + w.macd + w.rsi + w.stoch + w.er + w.sr;
   if(soma_pesos <= 0.0) return s;

   double acc = 0.0;

   // 1) Tendencia multi-TF
   double c_tend = 0.0;
   if(d.tend_prim > 0 && d.tend_med > 0)      c_tend =  1.0;
   else if(d.tend_prim > 0 && d.tend_med < 0) c_tend =  0.3;
   else if(d.tend_prim < 0 && d.tend_med < 0) c_tend = -1.0;
   else if(d.tend_prim < 0 && d.tend_med > 0) c_tend = -0.3;
   acc += w.tendencia * c_tend;

   // 2) ADX / DI - direcao com magnitude pela forca
   double forca = Clamp(d.adx / 30.0, 0.0, 1.0);
   double c_adx = 0.0;
   if(d.plus_di > d.minus_di)      c_adx =  forca;
   else if(d.minus_di > d.plus_di) c_adx = -forca;
   acc += w.adx * c_adx;

   // 3) MACD - cruzamento (60%) + posicao vs zero (40%)
   double c_macd = 0.6 * ((d.macd_main > d.macd_signal) ? 1.0 : -1.0)
                 + 0.4 * ((d.macd_main > 0.0) ? 1.0 : -1.0);
   acc += w.macd * c_macd;

   // 4) RSI - 50 neutro, satura em 30/70
   double c_rsi = Clamp((d.rsi - 50.0) / 20.0, -1.0, 1.0);
   acc += w.rsi * c_rsi;

   // 5) Stochastic - cruzamento (50%) + nivel (50%), com exaustao nos extremos
   double c_st_cross = (d.stoch_k > d.stoch_d) ? 1.0 : -1.0;
   double c_st_nivel = Clamp((d.stoch_k - 50.0) / 40.0, -1.0, 1.0);
   double c_stoch = 0.5 * c_st_cross + 0.5 * c_st_nivel;
   if(d.stoch_k > 88.0) c_stoch = MathMin(c_stoch, 0.2);   // sobrecomprado: nao empurra compra
   if(d.stoch_k < 12.0) c_stoch = MathMax(c_stoch, -0.2);  // sobrevendido: nao empurra venda
   acc += w.stoch * c_stoch;

   // 6) ER - eficiencia confirma a direcao da tendencia primaria
   double mag_er = Clamp(d.er / MathMax(ERForte, 0.01), 0.0, 1.0);
   double c_er = (d.tend_prim > 0) ? mag_er : (d.tend_prim < 0) ? -mag_er : 0.0;
   acc += w.er * c_er;

   // 7) S/R - QUALIDADE DE ENTRADA: perto do suporte favorece compra
   double c_sr = 0.0;
   NiveisSR nv = CalcularSR();
   if(nv.valido && nv.resistencia > nv.suporte)
     {
      double pos = (d.close - nv.suporte) / (nv.resistencia - nv.suporte); // 0 = no suporte
      pos = Clamp(pos, 0.0, 1.0);
      c_sr = (0.5 - pos) * 2.0;   // +1 no suporte, -1 na resistencia
     }
   acc += w.sr * c_sr;

   // media ponderada em [-1..+1]
   double net = acc / soma_pesos;
   net = Clamp(net, -1.0, 1.0);

   // conviccao por volume: amplifica ou atenua a distancia do neutro
   double v_ratio = (d.volume_medio > 0.0) ? (d.volume_atual / d.volume_medio) : 1.0;
   s.conviccao = Clamp(0.75 + 0.25 * (v_ratio / MathMax(VolumeMinimoRelativo, 0.01)), 0.70, 1.15);
   net *= s.conviccao;
   net = Clamp(net, -1.0, 1.0);

   s.compra = (net + 1.0) * 50.0;
   s.venda  = 100.0 - s.compra;
   return s;
  }

double ScoreMinimoAtual(const Regime &reg)
  {
   if(reg.lateral)      return ScoreMinimo_Lateral;
   if(reg.forca >= 2)   return ScoreMinimo_Tendencia;
   return ScoreMinimo_Base;
  }

//+------------------------------------------------------------------+
//| VALIDACAO DE PULLBACK / BREAKOUT (restaurada e ligada)            |
//+------------------------------------------------------------------+
bool ValidarPullback(const bool compra, const DadosMercado &d)
  {
   if(!ValidarPullbackFalso) return true;

   // volume nao pode estar anemico
   if(d.volume_medio > 0.0 && d.volume_atual < d.volume_medio * 0.7) return false;

   // deve estar perto de um nivel real de S/R do lado correto
   NiveisSR nv = CalcularSR();
   if(!nv.valido) return true;
   double limiar = d.atr * 0.6;
   if(compra) return ((d.close - nv.suporte) <= limiar) || (d.low <= nv.suporte + limiar);
   return ((nv.resistencia - d.close) <= limiar) || (d.high >= nv.resistencia - limiar);
  }

bool ValidarBreakout(const DadosMercado &d)
  {
   if(!ValidarBreakoutFalso) return true;

   if(d.volume_medio > 0.0 && d.volume_atual < d.volume_medio * VolumeMinimoRelativo) return false;

   double range = d.high - d.low;
   if(range <= 0.0) return false;
   double corpo = MathAbs(d.close - d.open);
   if(corpo / range < 0.55) return false;      // vela decisiva
   if(range < d.atr * 0.5)  return false;      // rompimento sem amplitude
   return true;
  }

bool GatilhoPullback(const bool compra, const DadosMercado &d)
  {
   double range = d.high - d.low;
   if(range <= 0.0) return false;
   if(MathAbs(d.close - d.open) / range < 0.35) return false;

   if(compra)
     {
      if(d.low <= d.ema_exec_len && d.close > d.ema_exec_len && d.close > d.open)
         if(d.close > iHigh(_Symbol, TF_Exec, 2))
            return ValidarPullback(true, d);
     }
   else
     {
      if(d.high >= d.ema_exec_len && d.close < d.ema_exec_len && d.close < d.open)
         if(d.close < iLow(_Symbol, TF_Exec, 2))
            return ValidarPullback(false, d);
     }
   return false;
  }

bool GatilhoBreakout(const bool compra, const DadosMercado &d)
  {
   int ih = iHighest(_Symbol, TF_Exec, MODE_HIGH, PeriodoBreakout, 2);
   int il = iLowest (_Symbol, TF_Exec, MODE_LOW,  PeriodoBreakout, 2);
   if(ih < 0 || il < 0) return false;

   double ext_high = iHigh(_Symbol, TF_Exec, ih);
   double ext_low  = iLow (_Symbol, TF_Exec, il);
   double prev     = iClose(_Symbol, TF_Exec, 2);

   if(compra && d.close > ext_high && prev <= ext_high) return ValidarBreakout(d);
   if(!compra && d.close < ext_low  && prev >= ext_low)  return ValidarBreakout(d);
   return false;
  }

bool GatilhoEntrada(const bool compra, const DadosMercado &d, string &tipo)
  {
   if(TipoEntrada == ENTRADA_PULLBACK)
     { if(GatilhoPullback(compra, d)) { tipo = "PULLBACK"; return true; } return false; }
   if(TipoEntrada == ENTRADA_BREAKOUT)
     { if(GatilhoBreakout(compra, d)) { tipo = "BREAKOUT"; return true; } return false; }

   if(GatilhoPullback(compra, d)) { tipo = "PULLBACK"; return true; }
   if(GatilhoBreakout(compra, d)) { tipo = "BREAKOUT"; return true; }
   return false;
  }

//+------------------------------------------------------------------+
//| ESTATISTICAS DE HISTORICO - PASSE UNICO (corrige bug do V2.01)    |
//| Nao usa HistorySelectByPosition dentro do loop de HistorySelect.  |
//+------------------------------------------------------------------+
void AtualizarEstatisticas(const bool forcar = false)
  {
   if(!forcar && g_stats.calculado_em > 0 && TimeCurrent() - g_stats.calculado_em < 30)
      return;

   g_stats.total = 0; g_stats.vitorias = 0; g_stats.win_rate = 0.0;
   g_stats.lucro_total = 0.0; g_stats.payoff = 0.0; g_stats.perdas_consecutivas = 0;
   g_stats.calculado_em = TimeCurrent();

   datetime desde = TimeCurrent() - 90 * 86400;
   if(!HistorySelect(desde, TimeCurrent())) return;

   ulong    ids[];      // position id
   double   pnl[];      // lucro acumulado da posicao
   datetime fech[];     // horario do ultimo deal de saida
   bool     fechada[];  // teve deal OUT
   int      n = 0;

   int total_deals = HistoryDealsTotal();
   for(int i = 0; i < total_deals; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;

      ulong pid = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(pid == 0) continue;

      double p = HistoryDealGetDouble(deal, DEAL_PROFIT)
               + HistoryDealGetDouble(deal, DEAL_SWAP)
               + HistoryDealGetDouble(deal, DEAL_COMMISSION);
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);

      int idx = -1;
      for(int k = 0; k < n; k++) if(ids[k] == pid) { idx = k; break; }
      if(idx < 0)
        {
         idx = n; n++;
         ArrayResize(ids, n, 128); ArrayResize(pnl, n, 128);
         ArrayResize(fech, n, 128); ArrayResize(fechada, n, 128);
         ids[idx] = pid; pnl[idx] = 0.0; fech[idx] = 0; fechada[idx] = false;
        }
      pnl[idx] += p;
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
        { fechada[idx] = true; if(t > fech[idx]) fech[idx] = t; }
     }

   // mantem apenas posicoes fechadas, ordenadas por fechamento (mais recente primeiro)
   ulong  f_id[];  double f_pnl[]; datetime f_t[];
   int m = 0;
   for(int k = 0; k < n; k++)
     {
      if(!fechada[k]) continue;
      m++; ArrayResize(f_id, m, 128); ArrayResize(f_pnl, m, 128); ArrayResize(f_t, m, 128);
      f_id[m-1] = ids[k]; f_pnl[m-1] = pnl[k]; f_t[m-1] = fech[k];
     }
   if(m == 0) return;

   for(int a = 0; a < m - 1; a++)                       // selection sort desc por tempo
      for(int b = a + 1; b < m; b++)
         if(f_t[b] > f_t[a])
           {
            datetime tt = f_t[a]; f_t[a] = f_t[b]; f_t[b] = tt;
            double dd = f_pnl[a]; f_pnl[a] = f_pnl[b]; f_pnl[b] = dd;
            ulong  ii = f_id[a];  f_id[a]  = f_id[b];  f_id[b]  = ii;
           }

   int limite = MathMin(m, MathMax(HistoricoTradesAnalise, 1));
   double soma_ganhos = 0.0, soma_perdas = 0.0;
   int n_ganhos = 0, n_perdas = 0;

   for(int k = 0; k < limite; k++)
     {
      g_stats.total++;
      g_stats.lucro_total += f_pnl[k];
      if(f_pnl[k] > 0.0) { g_stats.vitorias++; soma_ganhos += f_pnl[k]; n_ganhos++; }
      else               { soma_perdas += MathAbs(f_pnl[k]); n_perdas++; }
     }
   if(g_stats.total > 0) g_stats.win_rate = (double)g_stats.vitorias / g_stats.total;
   if(n_ganhos > 0 && n_perdas > 0 && soma_perdas > 0.0)
      g_stats.payoff = (soma_ganhos / n_ganhos) / (soma_perdas / n_perdas);

   // perdas consecutivas mais recentes
   for(int k = 0; k < m; k++)
     {
      if(f_pnl[k] < 0.0) g_stats.perdas_consecutivas++;
      else break;
     }
  }

//+------------------------------------------------------------------+
//| GESTOR DE RISCO - TUDO LIGADO DE VERDADE                          |
//+------------------------------------------------------------------+
class CRisco
  {
private:
   datetime m_dia_ref;
   datetime m_pausa_ate;
   double   m_equity_inicio_dia;
   double   m_equity_pico_global;
   bool     m_stop_diario;
   bool     m_stop_global;
   string   m_ultimo_bloqueio;

   datetime InicioDoDia()
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
     }

public:
   void Init()
     {
      m_dia_ref = 0; m_pausa_ate = 0;
      m_equity_inicio_dia = AccountInfoDouble(ACCOUNT_EQUITY);
      m_equity_pico_global = m_equity_inicio_dia;
      m_stop_diario = false; m_stop_global = false;
      m_ultimo_bloqueio = "";
      // restaura pico global entre reinicios
      string k = PREFIXO_GV + "PEAK";
      if(GlobalVariableCheck(k))
        {
         double v = GlobalVariableGet(k);
         if(v > 0.0) m_equity_pico_global = v;
        }
      Atualizar();
     }

   void Atualizar()
     {
      datetime agora = TimeCurrent();
      MqlDateTime a, r;
      TimeToStruct(agora, a); TimeToStruct(m_dia_ref, r);
      if(a.year != r.year || a.mon != r.mon || a.day != r.day)
        {
         m_equity_inicio_dia = AccountInfoDouble(ACCOUNT_EQUITY);
         m_dia_ref = agora;
         m_stop_diario = false;
         m_stop_global = false;
         if(m_pausa_ate < agora) m_pausa_ate = 0;
         if(LogDetalhado) PrintFormat("[DIA NOVO] equity inicial = %.2f", m_equity_inicio_dia);
        }

      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_equity_pico_global)
        {
         m_equity_pico_global = eq;
         GlobalVariableSet(PREFIXO_GV + "PEAK", eq);
        }
     }

   double DrawdownAtualPct()
     {
      if(m_equity_pico_global <= 0.0) return 0.0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return 100.0 * (m_equity_pico_global - eq) / m_equity_pico_global;
     }

   double PerdaDiariaPct()
     {
      if(m_equity_inicio_dia <= 0.0) return 0.0;
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      return 100.0 * (m_equity_inicio_dia - eq) / m_equity_inicio_dia;
     }

   bool StopDiarioAtingido()
     {
      if(PerdaDiariaPct() >= RiscoDiarioMaximoPct)
        {
         if(!m_stop_diario)
           {
            m_stop_diario = true;
            m_pausa_ate = InicioDoDia() + 86400;
            PrintFormat("[STOP DIARIO] perda %.2f%% >= %.2f%% - pausado ate amanha",
                        PerdaDiariaPct(), RiscoDiarioMaximoPct);
           }
         return true;
        }
      return m_stop_diario;
     }

   bool StopGlobalAtingido()
     {
      if(!UsarStopGlobal) return false;
      if(DrawdownAtualPct() >= DrawdownMaximoGlobalPct)
        {
         if(!m_stop_global)
           {
            m_stop_global = true;
            m_pausa_ate = InicioDoDia() + 86400;
            PrintFormat("[STOP GLOBAL] drawdown %.2f%% >= %.2f%% - pausado",
                        DrawdownAtualPct(), DrawdownMaximoGlobalPct);
           }
         return true;
        }
      return m_stop_global;
     }

   void VerificarPerdasConsecutivas()
     {
      if(MaxPerdasConsecutivas <= 0) return;
      if(g_stats.perdas_consecutivas >= MaxPerdasConsecutivas && TimeCurrent() >= m_pausa_ate)
        {
         m_pausa_ate = TimeCurrent() + PausaAposPerdasMinutos * 60;
         PrintFormat("[PAUSA] %d perdas consecutivas - retomada em %s",
                     g_stats.perdas_consecutivas, TimeToString(m_pausa_ate));
        }
     }

   // Fator anti-martingale: reduz apos perdas / em drawdown, aumenta pouco apos ganhos
   double FatorRisco()
     {
      if(!UsarRiscoAdaptativo) return 1.0;
      double f;
      if(g_stats.total < MinTradesParaAdaptar)
         f = 0.60;                                  // aquecimento: risco reduzido
      else
        {
         double wr = g_stats.win_rate;
         if(wr < 0.35)      f = 0.50;
         else if(wr < 0.45) f = 0.75;
         else if(wr < 0.55) f = 1.00;
         else if(wr < 0.65) f = 1.15;
         else               f = 1.25;
        }
      if(ReduzirRiscoEmDrawdown && DrawdownMaximoGlobalPct > 0.0)
        {
         double dd = DrawdownAtualPct();
         if(dd > 0.0)
            f *= MathMax(0.40, 1.0 - (dd / DrawdownMaximoGlobalPct));
        }
      return Clamp(f, 0.30, 1.30);
     }

   bool PodeAbrir(const int posicoes_abertas, string &motivo)
     {
      motivo = "";
      if(!ExecucaoAtiva)                       { motivo = "EA desativado"; return false; }

      bool real = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL);
      if(real && !PermitirContaReal)           { motivo = "conta REAL bloqueada"; return false; }
      if(!real && !PermitirContaDemo)          { motivo = "conta demo bloqueada"; return false; }

      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { motivo = "AutoTrading off"; return false; }
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))   { motivo = "trade nao permitido ao EA"; return false; }
      if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) { motivo = "conta nao permite EA"; return false; }

      if(StopDiarioAtingido())                 { motivo = "stop diario"; return false; }
      if(StopGlobalAtingido())                 { motivo = "stop global"; return false; }
      if(TimeCurrent() < m_pausa_ate)          { motivo = "em pausa"; return false; }
      if(posicoes_abertas >= MaxPosicoesSimultaneas) { motivo = "max posicoes"; return false; }
      if(g_ultima_entrada > 0 && TimeCurrent() - g_ultima_entrada < CooldownEntreTradesSeg)
                                               { motivo = "cooldown"; return false; }
      if(!HorarioPermitido())                  { motivo = "fora do horario"; return false; }

      string ms;
      if(!SpreadAceitavel(ms))                 { motivo = "spread: " + ms; return false; }
      if(NoticiaProxima())                     { motivo = "noticia de alto impacto"; return false; }
      return true;
     }

   bool NoticiaProxima()
     {
      if(!BloquearNoticias || !g_calendario_ok) return false;

      string moedas[2]; int nm = 0;
      string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      string prof = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
      if(base != "") moedas[nm++] = base;
      if(prof != "" && prof != base && nm < 2) moedas[nm++] = prof;
      if(nm == 0) return false;

      datetime agora = TimeCurrent();
      MqlCalendarValue vals[];
      int c = CalendarValueHistory(vals, agora - MinDepoisNoticia * 60, agora + MinAntesNoticia * 60);
      if(c <= 0)
        {
         if(GetLastError() != 0) { g_calendario_ok = false; ResetLastError(); }
         return false;
        }
      for(int i = 0; i < c; i++)
        {
         if((int)vals[i].impact_type != (int)CALENDAR_IMPORTANCE_HIGH) continue;
         MqlCalendarEvent ev;
         if(!CalendarEventById((long)vals[i].event_id, ev)) continue;
         MqlCalendarCountry pais;
         if(!CalendarCountryById((long)ev.country_id, pais)) continue;
         string cur = (pais.currency != "") ? pais.currency : pais.code;
         for(int k = 0; k < nm; k++) if(cur == moedas[k]) return true;
        }
      return false;
     }

   datetime PausaAte() { return m_pausa_ate; }
   double   PicoGlobal(){ return m_equity_pico_global; }
  };
CRisco gestorRisco;

//+------------------------------------------------------------------+
//| RISCO AGREGADO REAL (perda em dinheiro se todos os SL baterem)    |
//+------------------------------------------------------------------+
double RiscoAgregadoPct()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) return 100.0;

   double risco = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !PositionSelectByTicket(tk)) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      string sym  = PositionGetString(POSITION_SYMBOL);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double sl   = PositionGetDouble(POSITION_SL);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(vol <= 0.0) continue;
      if(sl <= 0.0)
        {
         // posicao sem SL: assume o pior caso configurado (conservador)
         risco += equity * RiscoMaxPorTradePct / 100.0 * 2.0;
         continue;
        }
      double lucro_sl = 0.0;
      ENUM_ORDER_TYPE ot = (tipo == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, sym, vol, open, sl, lucro_sl))
        {
         if(lucro_sl < 0.0) risco += MathAbs(lucro_sl);  // SL ainda em prejuizo
         // SL em lucro (breakeven+) nao soma risco
        }
     }
   return 100.0 * risco / equity;
  }

//+------------------------------------------------------------------+
//| PLANO DE POSICAO (com todas as validacoes ligadas)                |
//+------------------------------------------------------------------+
PlanoPosicao CalcularPlano(const int direcao, const DadosMercado &d)
  {
   PlanoPosicao p;
   p.ok = false; p.motivo = ""; p.volume = 0.0; p.risco_pct = 0.0;
   p.entrada = 0.0; p.sl = 0.0; p.tp1 = 0.0; p.tp2 = 0.0; p.tp3 = 0.0;

   if(d.atr <= 0.0) { p.motivo = "ATR invalido"; return p; }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0) { p.motivo = "equity invalida"; return p; }

   double risco_aberto = RiscoAgregadoPct();
   double disponivel = RiscoMaximoAgregadoPct - risco_aberto;
   if(disponivel <= 0.05)
     { p.motivo = StringFormat("risco agregado %.2f%% no teto", risco_aberto); return p; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) { p.motivo = "sem tick"; return p; }
   p.entrada = (direcao > 0) ? tick.ask : tick.bid;
   if(p.entrada <= 0.0) { p.motivo = "preco invalido"; return p; }

   double pip = PipSize();

   // --- SL por volatilidade: vol ALTA => multiplicador MENOR (ATR ja e grande)
   double mult = ATRMultSL_VolNormal;
   if(d.vol_nivel == 0)      mult = ATRMultSL_VolBaixa;
   else if(d.vol_nivel == 2) mult = ATRMultSL_VolAlta;

   double dist_sl = mult * d.atr;

   double piso = (SLFloorPips   > 0.0) ? SLFloorPips   * pip : d.atr * 0.5;
   double teto = (SLCeilingPips > 0.0) ? SLCeilingPips * pip : d.atr * 3.0;
   dist_sl = MathMax(dist_sl, piso);
   dist_sl = MathMin(dist_sl, teto);

   // --- distancia minima do broker (stops level / freeze / spread)
   double dmin = DistanciaMinimaBroker();
   if(dist_sl < dmin) dist_sl = dmin * 1.1;
   if(dist_sl <= 0.0) { p.motivo = "distancia SL invalida"; return p; }

   p.sl  = (direcao > 0) ? p.entrada - dist_sl : p.entrada + dist_sl;
   p.tp1 = (direcao > 0) ? p.entrada + RR_TP1 * dist_sl : p.entrada - RR_TP1 * dist_sl;
   p.tp2 = (direcao > 0) ? p.entrada + RR_TP2 * dist_sl : p.entrada - RR_TP2 * dist_sl;
   p.tp3 = (direcao > 0) ? p.entrada + RR_TP3 * dist_sl : p.entrada - RR_TP3 * dist_sl;

   p.sl  = NormalizarPreco(p.sl);
   p.tp1 = NormalizarPreco(p.tp1);
   p.tp2 = NormalizarPreco(p.tp2);
   p.tp3 = NormalizarPreco(p.tp3);

   // --- R:R minimo (agora realmente validado)
   double risco_preco = MathAbs(p.entrada - p.sl);
   double lucro_tp1   = MathAbs(p.tp1 - p.entrada);
   if(risco_preco <= 0.0) { p.motivo = "risco de preco nulo"; return p; }
   if(lucro_tp1 / risco_preco < RR_Minimo)
     { p.motivo = StringFormat("R:R %.2f < %.2f", lucro_tp1 / risco_preco, RR_Minimo); return p; }

   // --- TP1 deve respeitar distancia minima do broker
   if(MathAbs(p.tp1 - p.entrada) < dmin)
     { p.motivo = "TP1 dentro da distancia minima"; return p; }

   // --- volume pelo risco efetivo
   ENUM_ORDER_TYPE ot = (direcao > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double risco_por_lote = 0.0;
   if(!OrderCalcProfit(ot, _Symbol, 1.0, p.entrada, p.sl, risco_por_lote))
     { p.motivo = "OrderCalcProfit falhou"; return p; }
   risco_por_lote = MathAbs(risco_por_lote);
   if(risco_por_lote <= 0.0) { p.motivo = "risco por lote invalido"; return p; }

   double risco_alvo = RiscoPorTradePct * gestorRisco.FatorRisco();
   risco_alvo = Clamp(risco_alvo, RiscoMinPorTradePct, RiscoMaxPorTradePct);
   risco_alvo = MathMin(risco_alvo, disponivel);

   double risco_dinheiro = equity * risco_alvo / 100.0;
   p.volume = NormalizarVolume(risco_dinheiro / risco_por_lote);
   if(p.volume < VolumeMinimoAceitavel || p.volume <= 0.0)
     { p.motivo = "volume abaixo do minimo"; return p; }

   p.risco_pct = 100.0 * (p.volume * risco_por_lote) / equity;
   if(risco_aberto + p.risco_pct > RiscoMaximoAgregadoPct + 0.01)
     { p.motivo = "estouraria o risco agregado"; return p; }

   // --- margem
   double margem = 0.0;
   if(!OrderCalcMargin(ot, _Symbol, p.volume, p.entrada, margem))
     { p.motivo = "OrderCalcMargin falhou"; return p; }
   if(margem > equity * MargemMaximaUtilizadaPct / 100.0)
     { p.motivo = "margem acima do limite"; return p; }
   if(margem > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
     { p.motivo = "margem livre insuficiente"; return p; }

   p.ok = true; p.motivo = "ok";
   return p;
  }

//+------------------------------------------------------------------+
//| GESTOR DE POSICOES (com persistencia e restauracao)               |
//+------------------------------------------------------------------+
class CGestorPosicoes
  {
private:
   EstadoPosicao m_estados[];
   CTrade        m_trade;

   string Pre(const ulong tk) { return PREFIXO_GV + "P" + IntegerToString(tk) + "_"; }

   void SalvarGV(const ulong tk, const EstadoPosicao &e)
     {
      string p = Pre(tk);
      GlobalVariableSet(p + "ENT", e.entrada);
      GlobalVariableSet(p + "T1",  e.tp1);
      GlobalVariableSet(p + "T2",  e.tp2);
      GlobalVariableSet(p + "T3",  e.tp3);
      GlobalVariableSet(p + "V0",  e.volume_inicial);
      GlobalVariableSet(p + "FL",  (e.tp1_exec ? 1 : 0) + (e.tp2_exec ? 2 : 0) + (e.breakeven_ativado ? 4 : 0));
     }

   bool CarregarGV(const ulong tk, EstadoPosicao &e)
     {
      string p = Pre(tk);
      if(!GlobalVariableCheck(p + "ENT")) return false;
      e.entrada        = GlobalVariableGet(p + "ENT");
      e.tp1            = GlobalVariableGet(p + "T1");
      e.tp2            = GlobalVariableGet(p + "T2");
      e.tp3            = GlobalVariableGet(p + "T3");
      e.volume_inicial = GlobalVariableGet(p + "V0");
      int fl           = (int)GlobalVariableGet(p + "FL");
      e.tp1_exec          = ((fl & 1) != 0);
      e.tp2_exec          = ((fl & 2) != 0);
      e.breakeven_ativado = ((fl & 4) != 0);
      return (e.tp1 > 0.0 && e.tp2 > 0.0);
     }

   void LimparGV(const ulong tk)
     {
      string p = Pre(tk);
      GlobalVariableDel(p + "ENT"); GlobalVariableDel(p + "T1");
      GlobalVariableDel(p + "T2");  GlobalVariableDel(p + "T3");
      GlobalVariableDel(p + "V0");  GlobalVariableDel(p + "FL");
     }

   int AcharEstado(const ulong tk)
     {
      for(int i = 0; i < ArraySize(m_estados); i++)
         if(m_estados[i].ticket == tk) return i;
      return -1;
     }

   void RemoverEstado(const int idx)
     {
      int n = ArraySize(m_estados);
      if(idx < 0 || idx >= n) return;
      LimparGV(m_estados[idx].ticket);
      m_estados[idx] = m_estados[n - 1];
      ArrayResize(m_estados, n - 1);
     }

   // SL valido: do lado correto e respeitando a distancia minima do broker
   bool SLValido(const bool compra, const double preco_atual, const double sl)
     {
      if(sl <= 0.0) return false;
      double dmin = DistanciaMinimaBroker();
      if(compra) return (sl < preco_atual) && ((preco_atual - sl) >= dmin);
      return (sl > preco_atual) && ((sl - preco_atual) >= dmin);
     }

   void AplicarGestao(EstadoPosicao &e)
     {
      if(!PositionSelectByTicket(e.ticket)) return;

      double vol_atual = PositionGetDouble(POSITION_VOLUME);
      double sl_atual  = PositionGetDouble(POSITION_SL);
      double tp_atual  = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      bool compra = (tipo == POSITION_TYPE_BUY);

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return;
      double preco = compra ? tick.bid : tick.ask;
      double lucro = compra ? (tick.bid - e.entrada) : (e.entrada - tick.ask);

      double atr = ObterATR(1);
      if(atr <= 0.0) return;

      m_trade.SetTypeFillingBySymbol(_Symbol);

      // ---------- saidas parciais ----------
      if(UsarSaidaParcial && !e.tp1_exec && e.tp1 > 0.0)
        {
         bool hit = compra ? (tick.bid >= e.tp1) : (tick.ask <= e.tp1);
         if(hit)
           {
            double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double vpar = NormalizarVolume(e.volume_inicial * PercentualTP1);
            if(vpar >= vmin && (vol_atual - vpar) >= vmin)
              {
               if(m_trade.PositionClosePartial(e.ticket, vpar))
                 {
                  e.tp1_exec = true; SalvarGV(e.ticket, e);
                  if(LogDetalhado) PrintFormat("[TP1] #%I64u fechou %.2f", e.ticket, vpar);
                 }
              }
            else { e.tp1_exec = true; SalvarGV(e.ticket, e); }
            return;                       // uma acao por ciclo
           }
        }

      if(UsarSaidaParcial && e.tp1_exec && !e.tp2_exec && e.tp2 > 0.0)
        {
         bool hit = compra ? (tick.bid >= e.tp2) : (tick.ask <= e.tp2);
         if(hit)
           {
            double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double vpar = NormalizarVolume(e.volume_inicial * PercentualTP2);
            if(vpar >= vmin && (vol_atual - vpar) >= vmin)
              {
               if(m_trade.PositionClosePartial(e.ticket, vpar))
                 {
                  e.tp2_exec = true; SalvarGV(e.ticket, e);
                  if(LogDetalhado) PrintFormat("[TP2] #%I64u fechou %.2f", e.ticket, vpar);
                 }
              }
            else { e.tp2_exec = true; SalvarGV(e.ticket, e); }
            return;
           }
        }

      // ---------- breakeven / trailing ----------
      double novo_sl = sl_atual;
      bool   mudou   = false;
      bool   foi_breakeven = false;

      if(UsarBreakeven && !e.breakeven_ativado && lucro >= BreakevenGatilhoATR * atr)
        {
         double be = compra ? (e.entrada + BreakevenOffsetATR * atr)
                            : (e.entrada - BreakevenOffsetATR * atr);
         if((compra && (sl_atual <= 0.0 || be > sl_atual)) ||
            (!compra && (sl_atual <= 0.0 || be < sl_atual)))
           { novo_sl = be; mudou = true; foi_breakeven = true; }
        }

      if(UsarTrailing && lucro >= TrailingInicioATR * atr)
        {
         double gap = e.tp2_exec ? TrailingGapApertadoATR : TrailingGapATR;
         double trail = compra ? (preco - gap * atr) : (preco + gap * atr);
         if((compra && trail > novo_sl) || (!compra && (novo_sl <= 0.0 || trail < novo_sl)))
           { novo_sl = trail; mudou = true; }
        }

      // ---------- TP no ladder ----------
      double novo_tp = tp_atual;
      if(UsarSaidaParcial)
        {
         if(!e.tp1_exec)                    novo_tp = 0.0;          // gerido pelo EA
         else if(!e.tp2_exec && e.tp2 > 0.0) novo_tp = e.tp2;
         else if(e.tp3 > 0.0)                novo_tp = e.tp3;
        }

      if(!mudou && MathAbs(novo_tp - tp_atual) < _Point / 2.0) return;
      if(TimeCurrent() - e.ultima_modificacao < IntervaloMinimoModificacaoS) return;

      novo_sl = NormalizarPreco(novo_sl);
      novo_tp = NormalizarPreco(novo_tp);

      // nunca piorar o stop e nunca violar a distancia minima
      if(mudou)
        {
         if(!SLValido(compra, preco, novo_sl)) return;
         if(sl_atual > 0.0)
           {
            if(compra && novo_sl <= sl_atual) return;
            if(!compra && novo_sl >= sl_atual) return;
           }
        }

      if(m_trade.PositionModify(e.ticket, novo_sl, novo_tp))
        {
         e.ultima_modificacao = TimeCurrent();
         if(foi_breakeven) e.breakeven_ativado = true;
         SalvarGV(e.ticket, e);
         if(LogDetalhado) PrintFormat("[MODIFY] #%I64u SL=%.*f TP=%.*f",
                                      e.ticket, _Digits, novo_sl, _Digits, novo_tp);
        }
      else if(LogDetalhado)
         PrintFormat("[MODIFY FALHOU] #%I64u ret=%u %s",
                     e.ticket, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
     }

public:
   void Init()
     {
      m_trade.SetExpertMagicNumber(InpMagic);
      m_trade.SetDeviationInPoints((ulong)DesvioMaximoPontos);
      m_trade.SetAsyncMode(false);
      m_trade.SetTypeFillingBySymbol(_Symbol);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      ArrayResize(m_estados, 0);
     }

   int ContarPosicoes()
     {
      int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         n++;
        }
      return n;
     }

   // Reconstroi flags a partir do preco - evita parcial duplicada apos restart
   void ReconciliarFlags(EstadoPosicao &e)
     {
      if(!PositionSelectByTicket(e.ticket)) return;
      MqlTick t; if(!SymbolInfoTick(_Symbol, t)) return;
      bool compra = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double sl = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);

      if(compra)
        {
         if(t.bid >= e.tp2) { e.tp1_exec = true; e.tp2_exec = true; }
         else if(t.bid >= e.tp1) e.tp1_exec = true;
         if(sl > 0.0 && sl >= e.entrada) e.breakeven_ativado = true;
        }
      else
        {
         if(t.ask <= e.tp2) { e.tp1_exec = true; e.tp2_exec = true; }
         else if(t.ask <= e.tp1) e.tp1_exec = true;
         if(sl > 0.0 && sl <= e.entrada) e.breakeven_ativado = true;
        }
      // se o volume atual ja e menor que o inicial, alguma parcial ocorreu
      if(e.volume_inicial > 0.0 && vol < e.volume_inicial * 0.95) e.tp1_exec = true;
     }

   void Sincronizar()
     {
      // 1) descarta estados de posicoes que nao existem mais
      for(int i = ArraySize(m_estados) - 1; i >= 0; i--)
        {
         ulong tk = m_estados[i].ticket;
         if(tk == 0 || !PositionSelectByTicket(tk) ||
            (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
            RemoverEstado(i);
        }

      // 2) adota posicoes nossas sem estado (restart / recompile)
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(AcharEstado(tk) >= 0) continue;

         EstadoPosicao e;
         e.ticket = tk;
         e.tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         e.ultima_modificacao = 0;
         e.score_entrada = 0.0;
         e.tp1_exec = false; e.tp2_exec = false; e.breakeven_ativado = false;

         if(!CarregarGV(tk, e))
           {
            // fallback: reconstroi o ladder a partir da entrada e do SL reais
            e.entrada = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double dist = (sl > 0.0) ? MathAbs(e.entrada - sl) : ObterATR(1) * ATRMultSL_VolNormal;
            if(dist <= 0.0) continue;
            bool compra = (e.tipo == POSITION_TYPE_BUY);
            e.tp1 = compra ? e.entrada + RR_TP1 * dist : e.entrada - RR_TP1 * dist;
            e.tp2 = compra ? e.entrada + RR_TP2 * dist : e.entrada - RR_TP2 * dist;
            e.tp3 = compra ? e.entrada + RR_TP3 * dist : e.entrada - RR_TP3 * dist;
            e.volume_inicial = PositionGetDouble(POSITION_VOLUME);
            PrintFormat("[ADOTADA] #%I64u sem GV - ladder reconstruido", tk);
           }
         else
            PrintFormat("[RESTAURADA] #%I64u da GlobalVariable", tk);

         ReconciliarFlags(e);
         int n = ArraySize(m_estados);
         ArrayResize(m_estados, n + 1);
         m_estados[n] = e;
         SalvarGV(tk, e);
        }
     }

   void Gerenciar()
     {
      for(int i = ArraySize(m_estados) - 1; i >= 0; i--)
         AplicarGestao(m_estados[i]);
     }

   void FecharTodas(const string razao)
     {
      m_trade.SetTypeFillingBySymbol(_Symbol);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !PositionSelectByTicket(tk)) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if(m_trade.PositionClose(tk))
            PrintFormat("[FECHADA] #%I64u - %s", tk, razao);
         else
            PrintFormat("[FALHA AO FECHAR] #%I64u ret=%u", tk, m_trade.ResultRetcode());
        }
     }

   bool Entrar(const int direcao, const PlanoPosicao &p, const double score, const string tipo_gatilho)
     {
      m_trade.SetTypeFillingBySymbol(_Symbol);

      // TP no broker: 0 no modo parcial (o EA gere o ladder); senao TP3 como rede
      double tp_broker = UsarSaidaParcial ? 0.0 : p.tp3;

      bool ok = (direcao > 0)
              ? m_trade.Buy (p.volume, _Symbol, 0.0, p.sl, tp_broker, EA_NOME)
              : m_trade.Sell(p.volume, _Symbol, 0.0, p.sl, tp_broker, EA_NOME);

      if(!ok)
        {
         PrintFormat("[ENTRADA REJEITADA] ret=%u %s",
                     m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription());
         return false;
        }

      // --- ticket CORRETO: position id via deal (nao ResultOrder)
      ulong pos_id = 0;
      ulong deal = m_trade.ResultDeal();
      if(deal > 0 && HistoryDealSelect(deal))
         pos_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(pos_id == 0)
        {
         ulong ord = m_trade.ResultOrder();
         if(ord > 0 && HistoryOrderSelect(ord))
            pos_id = (ulong)HistoryOrderGetInteger(ord, ORDER_POSITION_ID);
         if(pos_id == 0) pos_id = ord;
        }
      if(pos_id == 0 || !PositionSelectByTicket(pos_id))
        {
         Print("[AVISO] posicao aberta mas ticket nao resolvido - Sincronizar() vai adotar");
         g_ultima_entrada = TimeCurrent();
         return true;
        }

      EstadoPosicao e;
      e.ticket = pos_id;
      e.entrada = PositionGetDouble(POSITION_PRICE_OPEN);
      e.tp1 = p.tp1; e.tp2 = p.tp2; e.tp3 = p.tp3;
      e.volume_inicial = PositionGetDouble(POSITION_VOLUME);
      e.tipo = (direcao > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      e.ultima_modificacao = 0;
      e.breakeven_ativado = false;
      e.tp1_exec = false; e.tp2_exec = false;
      e.score_entrada = score;

      int n = ArraySize(m_estados);
      ArrayResize(m_estados, n + 1);
      m_estados[n] = e;
      SalvarGV(pos_id, e);

      g_ultima_entrada = TimeCurrent();

      PrintFormat("[ENTRADA] %s %s #%I64u | %s | vol=%.2f score=%.1f risco=%.2f%% | SL=%.*f TP1=%.*f TP2=%.*f TP3=%.*f",
                  _Symbol, (direcao > 0 ? "COMPRA" : "VENDA"), pos_id, tipo_gatilho,
                  e.volume_inicial, score, p.risco_pct,
                  _Digits, p.sl, _Digits, p.tp1, _Digits, p.tp2, _Digits, p.tp3);
      return true;
     }

   // remove GVs orfas (posicoes ja encerradas)
   void LimparOrfas()
     {
      int total = GlobalVariablesTotal();
      for(int i = total - 1; i >= 0; i--)
        {
         string nome = GlobalVariableName(i);
         if(StringFind(nome, PREFIXO_GV + "P") != 0) continue;
         if(StringFind(nome, "_ENT") < 0) continue;

         string meio = StringSubstr(nome, StringLen(PREFIXO_GV) + 1);
         int corte = StringFind(meio, "_");
         if(corte <= 0) continue;
         ulong tk = (ulong)StringToInteger(StringSubstr(meio, 0, corte));
         if(tk == 0) continue;
         if(!PositionSelectByTicket(tk)) LimparGV(tk);
        }
     }
  };
CGestorPosicoes gestor;

//+------------------------------------------------------------------+
//| PAINEL                                                            |
//+------------------------------------------------------------------+
void AtualizarPainel(const DadosMercado &d, const Regime &reg, const Score &sc, const string bloqueio)
  {
   if(!MostrarPainel) { Comment(""); return; }

   string dir = (reg.direcao > 0) ? "ALTA" : (reg.direcao < 0) ? "BAIXA" : "-";
   string lat = reg.lateral ? " [LATERAL]" : "";
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   string t = "";
   t += EA_NOME + "  |  " + _Symbol + "  |  " + EnumToString(TF_Exec) + "\n";
   t += "--------------------------------------------\n";
   t += StringFormat("Regime: %s%s   forca %d/3   conf %.0f\n", dir, lat, reg.forca, reg.confianca);
   t += StringFormat("ADX %.1f   ATR %.*f (%.3f%%)   ER %.2f\n", d.adx, _Digits, d.atr, d.atr_pct, d.er);
   t += StringFormat("Score  compra %.1f  |  venda %.1f  |  min %.1f\n",
                     sc.compra, sc.venda, ScoreMinimoAtual(reg));
   t += StringFormat("Conviccao (volume): x%.2f\n", sc.conviccao);
   t += "--------------------------------------------\n";
   t += StringFormat("Posicoes %d/%d   risco aberto %.2f%% / %.2f%%\n",
                     gestor.ContarPosicoes(), MaxPosicoesSimultaneas,
                     RiscoAgregadoPct(), RiscoMaximoAgregadoPct);
   t += StringFormat("Risco/trade efetivo: %.2f%%  (fator %.2f)\n",
                     Clamp(RiscoPorTradePct * gestorRisco.FatorRisco(), RiscoMinPorTradePct, RiscoMaxPorTradePct),
                     gestorRisco.FatorRisco());
   t += "--------------------------------------------\n";
   if(g_stats.total > 0)
      t += StringFormat("Historico (%d trades): WR %.1f%%  payoff %.2f  PnL %.2f\n",
                        g_stats.total, g_stats.win_rate * 100.0, g_stats.payoff, g_stats.lucro_total);
   else
      t += "Historico: sem trades encerrados ainda\n";
   t += StringFormat("Perdas consecutivas: %d/%d\n", g_stats.perdas_consecutivas, MaxPerdasConsecutivas);
   t += StringFormat("Equity %.2f   pico %.2f   DD %.2f%%   dia %.2f%%\n",
                     eq, gestorRisco.PicoGlobal(), gestorRisco.DrawdownAtualPct(), gestorRisco.PerdaDiariaPct());
   t += "--------------------------------------------\n";
   t += (bloqueio == "" ? "Status: operacional" : "Bloqueio: " + bloqueio);
   Comment(t);
  }

//+------------------------------------------------------------------+
//| ONINIT                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   // --- validacao de parametros
   if(EMA_PrimRapida >= EMA_PrimLenta || EMA_MedRapida >= EMA_MedLenta)
     { Print("ERRO: EMA rapida deve ser menor que a lenta"); return INIT_PARAMETERS_INCORRECT; }
   if(PeriodoMACDLento <= PeriodoMACDRapido)
     { Print("ERRO: MACD lento deve ser maior que o rapido"); return INIT_PARAMETERS_INCORRECT; }
   if(RiscoPorTradePct <= 0.0 || RiscoMaxPorTradePct < RiscoMinPorTradePct)
     { Print("ERRO: faixa de risco invalida"); return INIT_PARAMETERS_INCORRECT; }
   if(RiscoMaximoAgregadoPct < RiscoMaxPorTradePct)
     { Print("ERRO: risco agregado nao pode ser menor que o risco por trade"); return INIT_PARAMETERS_INCORRECT; }
   if(RR_TP1 < RR_Minimo)
     { PrintFormat("ERRO: RR_TP1 (%.2f) < RR_Minimo (%.2f)", RR_TP1, RR_Minimo); return INIT_PARAMETERS_INCORRECT; }
   if(RR_TP2 <= RR_TP1 || RR_TP3 <= RR_TP2)
     { Print("ERRO: TPs devem ser crescentes (TP1 < TP2 < TP3)"); return INIT_PARAMETERS_INCORRECT; }
   if(UsarSaidaParcial && (PercentualTP1 + PercentualTP2) >= 1.0)
     { Print("ERRO: PercentualTP1 + PercentualTP2 deve ser < 1.0 para sobrar runner"); return INIT_PARAMETERS_INCORRECT; }
   if(VolatilidadeMaximaPct <= VolatilidadeMinimaPct)
     { Print("ERRO: volatilidade maxima deve ser maior que a minima"); return INIT_PARAMETERS_INCORRECT; }

   // --- handles
   g_h_atr          = iATR(_Symbol, TF_Exec, ATR_Periodo);
   g_h_rsi          = iRSI(_Symbol, TF_Exec, PeriodoRSI, PRICE_CLOSE);
   g_h_macd         = iMACD(_Symbol, TF_Exec, PeriodoMACDRapido, PeriodoMACDLento, PeriodoMACDSinal, PRICE_CLOSE);
   g_h_stoch        = iStochastic(_Symbol, TF_Exec, PeriodoStoch, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_h_adx          = iADX(_Symbol, TF_Exec, PeriodoADX);
   g_h_ema_exec_len = iMA(_Symbol, TF_Exec, EMA_MedLenta, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_prim_rap = iMA(_Symbol, TF_Primario, EMA_PrimRapida, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_prim_len = iMA(_Symbol, TF_Primario, EMA_PrimLenta,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_med_rap  = iMA(_Symbol, TF_Medio, EMA_MedRapida, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_med_len  = iMA(_Symbol, TF_Medio, EMA_MedLenta,  0, MODE_EMA, PRICE_CLOSE);

   if(g_h_atr == INVALID_HANDLE || g_h_rsi == INVALID_HANDLE || g_h_macd == INVALID_HANDLE ||
      g_h_stoch == INVALID_HANDLE || g_h_adx == INVALID_HANDLE ||
      g_h_ema_exec_len == INVALID_HANDLE ||
      g_h_ema_prim_rap == INVALID_HANDLE || g_h_ema_prim_len == INVALID_HANDLE ||
      g_h_ema_med_rap == INVALID_HANDLE || g_h_ema_med_len == INVALID_HANDLE)
     { Print("ERRO: falha ao criar handles de indicadores"); return INIT_FAILED; }

   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
      Print("AVISO: simbolo nao permite operacao completa (SYMBOL_TRADE_MODE != FULL)");

   gestor.Init();
   gestorRisco.Init();
   gestor.LimparOrfas();
   gestor.Sincronizar();
   AtualizarEstatisticas(true);

   g_er_vela = 0; g_er_valor = 0.0;
   g_sr_vela = 0; g_sr_cache.valido = false;
   g_regime_vela = 0; g_regime_dir_ant = 0; g_barras_desde_virada = 999;

   PrintFormat("=== %s iniciado em %s ===", EA_NOME, _Symbol);
   PrintFormat("Risco base %.2f%% (faixa %.2f-%.2f) | agregado %.2f%% | diario %.2f%% | DD global %.2f%%",
               RiscoPorTradePct, RiscoMinPorTradePct, RiscoMaxPorTradePct,
               RiscoMaximoAgregadoPct, RiscoDiarioMaximoPct, DrawdownMaximoGlobalPct);
   PrintFormat("Conta: %s | AutoTrading: %s",
               (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL ? "REAL" : "DEMO"),
               (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ? "ON" : "OFF"));
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL && !PermitirContaReal)
      Print(">>> CONTA REAL BLOQUEADA por configuracao. Ative PermitirContaReal apenas apos validar. <<<");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| ONTICK                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime ultimo = 0;
   if(TimeCurrent() - ultimo < IntervaloProcessamentoS) return;
   ultimo = TimeCurrent();

   gestorRisco.Atualizar();
   AtualizarEstatisticas();
   gestorRisco.VerificarPerdasConsecutivas();

   gestor.Sincronizar();
   gestor.Gerenciar();

   // protecoes que fecham posicoes (agora realmente ligadas)
   if(FecharNoStopDiario && gestorRisco.StopDiarioAtingido() && gestor.ContarPosicoes() > 0)
      gestor.FecharTodas("stop diario");
   if(FecharNoStopGlobal && gestorRisco.StopGlobalAtingido() && gestor.ContarPosicoes() > 0)
      gestor.FecharTodas("stop global");

   DadosMercado d; Regime reg; Score sc;
   ZeroMemory(d); ZeroMemory(reg); ZeroMemory(sc);

   bool dados_ok = ColetarDados(d);
   if(dados_ok)
     {
      reg = DetectarRegime(d);
      sc  = CalcularScore(d, reg);
     }

   string bloqueio = "";
   if(!dados_ok) bloqueio = "aguardando dados";

   if(dados_ok && !gestorRisco.PodeAbrir(gestor.ContarPosicoes(), bloqueio))
     { AtualizarPainel(d, reg, sc, bloqueio); return; }

   if(!dados_ok) { AtualizarPainel(d, reg, sc, bloqueio); return; }

   // ---- filtros de contexto ----
   if(EmTransicaoDeRegime())
     { AtualizarPainel(d, reg, sc, "transicao de regime"); return; }

   if(FiltrarVolatilidade && d.atr_pct < VolatilidadeMinimaPct)
     { AtualizarPainel(d, reg, sc, StringFormat("volatilidade baixa %.3f%%", d.atr_pct)); return; }

   if(FiltrarVolatilidadeMax && d.atr_pct > VolatilidadeMaximaPct)
     { AtualizarPainel(d, reg, sc, StringFormat("volatilidade extrema %.3f%%", d.atr_pct)); return; }

   if(reg.lateral && !OperarEmLateral)
     { AtualizarPainel(d, reg, sc, "mercado lateral"); return; }

   if(!reg.lateral && d.adx < ADXMinimoTendencia)
     { AtualizarPainel(d, reg, sc, StringFormat("ADX fraco %.1f", d.adx)); return; }

   if(reg.direcao == 0)
     { AtualizarPainel(d, reg, sc, "regime indefinido"); return; }

   // ---- decisao ----
   double score_min = ScoreMinimoAtual(reg);
   int direcao = 0;
   if(reg.direcao > 0 && sc.compra >= score_min) direcao = 1;
   else if(reg.direcao < 0 && sc.venda >= score_min) direcao = -1;

   if(direcao == 0)
     {
      AtualizarPainel(d, reg, sc,
         StringFormat("score insuficiente (%.1f < %.1f)",
                      (reg.direcao > 0 ? sc.compra : sc.venda), score_min));
      return;
     }

   // ---- uma entrada por vela ----
   datetime vela = iTime(_Symbol, TF_Exec, 0);
   if(UmTradePorVela && vela == g_ultima_vela_entrada)
     { AtualizarPainel(d, reg, sc, "ja avaliou esta vela"); return; }

   string tipo_gatilho = "";
   if(!GatilhoEntrada(direcao > 0, d, tipo_gatilho))
     { AtualizarPainel(d, reg, sc, "sem gatilho"); return; }

   PlanoPosicao plano = CalcularPlano(direcao, d);
   if(!plano.ok)
     {
      if(LogDetalhado) Print("[REJEITADO] ", plano.motivo);
      AtualizarPainel(d, reg, sc, "plano: " + plano.motivo);
      return;
     }

   double score = (direcao > 0) ? sc.compra : sc.venda;
   if(gestor.Entrar(direcao, plano, score, tipo_gatilho))
     {
      g_ultima_vela_entrada = vela;
      AtualizarEstatisticas(true);
     }

   AtualizarPainel(d, reg, sc, "");
  }

//+------------------------------------------------------------------+
//| ONTRADETRANSACTION                                                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
      trans.type == TRADE_TRANSACTION_POSITION ||
      trans.type == TRADE_TRANSACTION_HISTORY_ADD)
     {
      gestor.Sincronizar();
      AtualizarEstatisticas(true);
      gestorRisco.VerificarPerdasConsecutivas();
     }
  }

//+------------------------------------------------------------------+
//| ONDEINIT                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_h_atr          != INVALID_HANDLE) IndicatorRelease(g_h_atr);
   if(g_h_rsi          != INVALID_HANDLE) IndicatorRelease(g_h_rsi);
   if(g_h_macd         != INVALID_HANDLE) IndicatorRelease(g_h_macd);
   if(g_h_stoch        != INVALID_HANDLE) IndicatorRelease(g_h_stoch);
   if(g_h_adx          != INVALID_HANDLE) IndicatorRelease(g_h_adx);
   if(g_h_ema_exec_len != INVALID_HANDLE) IndicatorRelease(g_h_ema_exec_len);
   if(g_h_ema_prim_rap != INVALID_HANDLE) IndicatorRelease(g_h_ema_prim_rap);
   if(g_h_ema_prim_len != INVALID_HANDLE) IndicatorRelease(g_h_ema_prim_len);
   if(g_h_ema_med_rap  != INVALID_HANDLE) IndicatorRelease(g_h_ema_med_rap);
   if(g_h_ema_med_len  != INVALID_HANDLE) IndicatorRelease(g_h_ema_med_len);

   Comment("");
   PrintFormat("=== %s finalizado (motivo %d) ===", EA_NOME, reason);
  }
//+------------------------------------------------------------------+
