//+------------------------------------------------------------------+
//|                    ORCHESTRATOR_MAESTRO_V2_FIBONACCI.mq5         |
//|                    Expert Advisor — TRIVIUM369                    |
//|                    Versão 2.0 — Sistema Fibonacci Completo        |
//|                                                                   |
//|  ESTRATÉGIA CENTRAL:                                              |
//|  1. Calcula Fibonacci 38.2% / 50% / 61.8% das últimas 500 velas  |
//|  2. Aguarda preço chegar num nível Fibonacci                      |
//|  3. Confirma reversão via candle padrão (engolfo/pino/doji)       |
//|  4. Entra com SL = mínima dos últimos 10 candles - buffer         |
//|  5. TP = próximo nível Fibonacci                                  |
//|  6. Trailing stop só ativa quando trade está positivo confirmado  |
//|  7. Pirâmide de 5 ordens (Magic 100000-100004)                    |
//+------------------------------------------------------------------+

#property copyright   "TRIVIUM369 — Pedrinho & Ronei"
#property version     "2.00"
#property description "EA Fibonacci V2 — Entrada em níveis Fib com confirmação de reversão"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//+------------------------------------------------------------------+
//| PARÂMETROS DE ENTRADA                                             |
//+------------------------------------------------------------------+

// --- Fibonacci ---
input group "=== FIBONACCI ==="
input int    FibPeriodo         = 500;    // Número de candles para calcular o swing
input double FibToleranciaPips  = 5.0;    // Tolerância em pips para considerar "em nível Fib"
input bool   UsarFib382         = true;   // Usar nível 38.2%
input bool   UsarFib500         = true;   // Usar nível 50.0%
input bool   UsarFib618         = true;   // Usar nível 61.8%

// --- Confirmação de Reversão ---
input group "=== CONFIRMAÇÃO DE REVERSÃO ==="
input bool   UsarEngolfo        = true;   // Confirmar por candle de engolfo (bullish/bearish)
input bool   UsarPinBar         = true;   // Confirmar por pin bar (martelo/estrela cadente)
input bool   UsarDoji           = false;  // Confirmar por doji (incerteza)
input double PinBarRatio        = 2.5;    // Ratio mínimo sombra/corpo para pin bar
input double EngolfoRatio       = 1.1;    // Ratio mínimo corpo atual/anterior para engolfo

// --- Stop Loss Dinâmico ---
input group "=== STOP LOSS DINÂMICO ==="
input int    SLCandles          = 10;     // Número de candles para buscar mínima/máxima do SL
input double SLBufferPips       = 5.0;    // Buffer adicional abaixo da mínima (em pips)
input double SLMaxPips          = 100.0;  // SL máximo permitido em pips (proteção)

// --- Take Profit (próximo Fibonacci) ---
input group "=== TAKE PROFIT ==="
input double TPBufferPips       = 3.0;    // Buffer antes do nível Fib alvo (em pips)
input double TPMinPips          = 20.0;   // TP mínimo em pips (não entra se TP for pequeno)

// --- Trailing Stop ---
input group "=== TRAILING STOP ==="
input bool   TrailingAtivo      = true;   // Ativar trailing stop
input double TrailingMinLucro   = 15.0;   // Lucro mínimo em pips para ativar trailing
input double TrailingPasso      = 10.0;   // Passo do trailing em pips
input double TrailingBuffer     = 5.0;    // Buffer trailing (distância do preço ao SL)
input bool   TrailingPullback   = true;   // Só move trailing após pullback confirmado

// --- Gestão de Capital ---
input group "=== GESTÃO DE CAPITAL ==="
input double LoteBase           = 0.01;   // Lote base por ordem
input double LoteMultiplicador  = 1.5;    // Multiplicador para pirâmide
input int    MaxOrdens          = 5;      // Máximo de ordens simultâneas (pirâmide)
input double RiscoMaxPorcentagem= 2.0;    // Risco máximo por operação (% do saldo)

// --- Magic Numbers (pirâmide 5 ordens) ---
input group "=== MAGIC NUMBERS ==="
input int    MagicBase          = 100000; // Magic base (100000-100004 para 5 ordens)

// --- Filtros Gerais ---
input group "=== FILTROS GERAIS ==="
input int    HoraInicio         = 1;      // Hora de início das operações (servidor)
input int    HoraFim            = 22;     // Hora de fim das operações (servidor)
input bool   FecharNaVela       = false;  // Fechar posições ao fim do dia
input int    MaxTradesPorDia    = 10;     // Máximo de trades por dia
input bool   ModoDebug          = true;   // Exibir logs detalhados

//+------------------------------------------------------------------+
//| ESTRUTURAS INTERNAS                                               |
//+------------------------------------------------------------------+

// Estrutura para armazenar os níveis Fibonacci calculados
struct FibNiveis
{
   double swing_high;       // Topo do swing
   double swing_low;        // Fundo do swing
   double nivel_236;        // 23.6%
   double nivel_382;        // 38.2% — nível de entrada principal
   double nivel_500;        // 50.0% — nível de entrada principal
   double nivel_618;        // 61.8% — nível de entrada principal (golden ratio)
   double nivel_786;        // 78.6%
   bool   tendencia_alta;   // true = swing de baixo para cima (compra em retração)
   bool   calculado;        // true = Fibonacci foi calculado com sucesso
};

// Estrutura para rastrear estado de cada nível Fibonacci
struct EstadoNivel
{
   double   nivel_preco;     // Preço do nível Fibonacci
   double   preco_nivel_fib; // Percentual do nível (ex: 0.382)
   bool     preco_tocou;     // true = preço já tocou o nível
   bool     confirmado;      // true = reversão confirmada neste nível
   datetime hora_toque;      // Quando o preço tocou o nível
   int      tipo;            // 1=compra, -1=venda
};

// Estrutura para trailing stop por ticket
struct TrailingInfo
{
   ulong    ticket;
   double   sl_atual;
   double   melhor_preco;   // Melhor preço registrado (para trailing)
   bool     trailing_ativo; // true = trailing já foi ativado
   bool     pullback_visto; // true = pullback confirmado (para modo conservador)
};

//+------------------------------------------------------------------+
//| VARIÁVEIS GLOBAIS                                                 |
//+------------------------------------------------------------------+

CTrade         trader;          // Objeto de trading
FibNiveis      fib;             // Níveis Fibonacci atuais
EstadoNivel    estados[6];      // Estado de cada nível (0-5)
TrailingInfo   trailing[5];     // Trailing stop por slot de pirâmide
int            trailing_count = 0;

double         pip_size;        // Tamanho do pip para o ativo
double         tolerancia_pts;  // Tolerância em pontos
double         sl_buffer_pts;   // Buffer SL em pontos
double         tp_buffer_pts;   // Buffer TP em pontos
double         trailing_pts;    // Trailing em pontos

int            trades_hoje     = 0;    // Contador de trades no dia
datetime       ultimo_dia      = 0;    // Controle de troca de dia
datetime       ultima_vela     = 0;    // Controle de nova vela

int            ordens_abertas  = 0;    // Ordens abertas com nosso magic

//+------------------------------------------------------------------+
//| FUNÇÕES DE LOG                                                    |
//+------------------------------------------------------------------+

void Log(string msg, bool forcado = false)
{
   if(ModoDebug || forcado)
      Print("[MAESTRO-V2-FIB] ", msg);
}

void LogTrade(string msg)
{
   Print("[TRADE] ", msg);
}

//+------------------------------------------------------------------+
//| OnInit — Inicialização do EA                                      |
//+------------------------------------------------------------------+

int OnInit()
{
   // Configura o trader
   trader.SetExpertMagicNumber(MagicBase);
   trader.SetDeviationInPoints(10);
   trader.SetTypeFilling(ORDER_FILLING_FOK);

   // Calcula o tamanho do pip baseado no ativo
   // Para pares com 5 casas decimais (EURUSD), pip = 0.00010
   // Para pares com 3 casas decimais (USDJPY), pip = 0.010
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 5 || digits == 3)
      pip_size = _Point * 10;  // Pip = 10 pontos
   else
      pip_size = _Point;       // Pip = 1 ponto

   // Converte pips para pontos
   tolerancia_pts  = FibToleranciaPips  * pip_size;
   sl_buffer_pts   = SLBufferPips       * pip_size;
   tp_buffer_pts   = TPBufferPips       * pip_size;
   trailing_pts    = TrailingPasso      * pip_size;

   fib.calculado = false;

   Log(StringFormat("EA Fibonacci V2 iniciado — Ativo: %s | Pip: %.5f | Tolerancia: %.5f pts",
       _Symbol, pip_size, tolerancia_pts), true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit — Finalização                                            |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   Log("EA finalizado.", true);
}

//+------------------------------------------------------------------+
//| OnTick — Executado a cada tick                                    |
//+------------------------------------------------------------------+

void OnTick()
{
   // Verifica se é nova vela (processamento principal só na abertura)
   datetime hora_atual = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool nova_vela = (hora_atual != ultima_vela);
   if(nova_vela) ultima_vela = hora_atual;

   // Verifica troca de dia
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime dia_hoje = StringToTime(StringFormat("%04d.%02d.%02d 00:00:00",
                                                  dt.year, dt.mon, dt.day));
   if(dia_hoje != ultimo_dia)
   {
      ultimo_dia   = dia_hoje;
      trades_hoje  = 0;
      Log("Novo dia — contador de trades zerado.");
   }

   // Verifica horário de operação
   int hora_srv = dt.hour;
   if(hora_srv < HoraInicio || hora_srv >= HoraFim)
   {
      if(nova_vela) Log(StringFormat("Fora do horário (%dh-%dh). Hora atual: %dh", HoraInicio, HoraFim, hora_srv));
      // Trailing continua funcionando mesmo fora do horário
      GerenciarTrailing();
      return;
   }

   // Processa na abertura de nova vela
   if(nova_vela)
   {
      // 1. Recalcula Fibonacci a cada nova vela
      CalcularFibonacci();

      // 2. Conta ordens abertas com nosso magic
      ordens_abertas = ContarOrdens();

      // 3. Verifica se preço tocou algum nível Fibonacci
      VerificarToqueNiveis();

      // 4. Verifica confirmações de reversão nos níveis tocados
      VerificarConfirmacoes();

      // 5. Se há confirmação e podemos abrir mais ordens — ENTRA
      if(ordens_abertas < MaxOrdens && trades_hoje < MaxTradesPorDia)
         TentarEntrar();
   }

   // 6. Gerencia trailing stop a cada tick (não só na vela)
   if(TrailingAtivo)
      GerenciarTrailing();

   // 7. Exibe status no gráfico
   ExibirStatus();
}

//+------------------------------------------------------------------+
//| CalcularFibonacci — Calcula swing e níveis Fib nas últimas N velas|
//+------------------------------------------------------------------+

void CalcularFibonacci()
{
   int total = FibPeriodo;

   // Copia arrays de high e low
   double highs[], lows[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);

   if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, total, highs) < total ||
      CopyLow(_Symbol, PERIOD_CURRENT, 1, total, lows)  < total)
   {
      Log("Erro ao copiar dados para Fibonacci.");
      fib.calculado = false;
      return;
   }

   // Encontra o swing high e swing low do período
   int idx_high = ArrayMaximum(highs, 0, total);
   int idx_low  = ArrayMinimum(lows,  0, total);

   fib.swing_high = highs[idx_high];
   fib.swing_low  = lows[idx_low];

   // Determina direção do swing (para saber se é retração de alta ou baixa)
   // Se o high veio DEPOIS do low (idx_high < idx_low em array series),
   // o swing é: baixo → alto → estamos em retração para baixo → possível compra
   fib.tendencia_alta = (idx_high < idx_low); // Candle do high é mais recente

   double range = fib.swing_high - fib.swing_low;
   if(range <= 0)
   {
      Log("Range Fibonacci zerado — dados insuficientes.");
      fib.calculado = false;
      return;
   }

   if(fib.tendencia_alta)
   {
      // Tendência de alta: Fibonacci de baixo para cima
      // Retração = preço caindo de volta — possível COMPRA nos níveis
      fib.nivel_236 = fib.swing_high - range * 0.236;
      fib.nivel_382 = fib.swing_high - range * 0.382;
      fib.nivel_500 = fib.swing_high - range * 0.500;
      fib.nivel_618 = fib.swing_high - range * 0.618;
      fib.nivel_786 = fib.swing_high - range * 0.786;
   }
   else
   {
      // Tendência de baixa: Fibonacci de cima para baixo
      // Retração = preço subindo de volta — possível VENDA nos níveis
      fib.nivel_236 = fib.swing_low + range * 0.236;
      fib.nivel_382 = fib.swing_low + range * 0.382;
      fib.nivel_500 = fib.swing_low + range * 0.500;
      fib.nivel_618 = fib.swing_low + range * 0.618;
      fib.nivel_786 = fib.swing_low + range * 0.786;
   }

   fib.calculado = true;

   Log(StringFormat("Fibonacci calculado | Swing H:%.5f L:%.5f | Tendência: %s | 38.2:%.5f | 50:%.5f | 61.8:%.5f",
       fib.swing_high, fib.swing_low,
       fib.tendencia_alta ? "ALTA" : "BAIXA",
       fib.nivel_382, fib.nivel_500, fib.nivel_618));
}

//+------------------------------------------------------------------+
//| VerificarToqueNiveis — Verifica se o preço tocou nível Fibonacci  |
//+------------------------------------------------------------------+

void VerificarToqueNiveis()
{
   if(!fib.calculado) return;

   // Preço de fechamento da última vela fechada (índice 1)
   double close_atual = iClose(_Symbol, PERIOD_CURRENT, 1);
   double low_atual   = iLow(_Symbol,   PERIOD_CURRENT, 1);
   double high_atual  = iHigh(_Symbol,  PERIOD_CURRENT, 1);

   // Array dos níveis a verificar
   double niveis[3];
   bool   usar[3];
   niveis[0] = fib.nivel_382; usar[0] = UsarFib382;
   niveis[1] = fib.nivel_500; usar[1] = UsarFib500;
   niveis[2] = fib.nivel_618; usar[2] = UsarFib618;

   for(int i = 0; i < 3; i++)
   {
      if(!usar[i]) continue;

      // Verifica se o low (compra) ou high (venda) tocou o nível
      bool tocou = false;
      if(fib.tendencia_alta)
         tocou = (low_atual <= niveis[i] + tolerancia_pts && low_atual >= niveis[i] - tolerancia_pts)
              || (close_atual <= niveis[i] + tolerancia_pts && close_atual >= niveis[i] - tolerancia_pts);
      else
         tocou = (high_atual >= niveis[i] - tolerancia_pts && high_atual <= niveis[i] + tolerancia_pts)
              || (close_atual >= niveis[i] - tolerancia_pts && close_atual <= niveis[i] + tolerancia_pts);

      if(tocou && !estados[i].preco_tocou)
      {
         estados[i].preco_tocou    = true;
         estados[i].nivel_preco    = niveis[i];
         estados[i].confirmado     = false;
         estados[i].hora_toque     = TimeCurrent();
         estados[i].tipo           = fib.tendencia_alta ? 1 : -1; // 1=compra, -1=venda

         Log(StringFormat("Toque no nivel Fib %s (%.5f) | Tipo: %s",
             i==0 ? "38.2%" : (i==1 ? "50.0%" : "61.8%"),
             niveis[i],
             estados[i].tipo == 1 ? "COMPRA" : "VENDA"), true);
      }
      else if(!tocou)
      {
         // Reset se o preço passou muito longe do nível
         double distancia = MathAbs(close_atual - niveis[i]);
         if(distancia > tolerancia_pts * 10)
         {
            estados[i].preco_tocou = false;
            estados[i].confirmado  = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| VerificarConfirmacoes — Confirma reversão por padrão de candle    |
//+------------------------------------------------------------------+

void VerificarConfirmacoes()
{
   if(!fib.calculado) return;

   for(int i = 0; i < 3; i++)
   {
      if(!estados[i].preco_tocou || estados[i].confirmado) continue;

      int tipo = estados[i].tipo;

      // Lê dados das últimas 3 velas fechadas
      double open0  = iOpen(_Symbol,  PERIOD_CURRENT, 1); // Vela mais recente fechada
      double close0 = iClose(_Symbol, PERIOD_CURRENT, 1);
      double high0  = iHigh(_Symbol,  PERIOD_CURRENT, 1);
      double low0   = iLow(_Symbol,   PERIOD_CURRENT, 1);
      double open1  = iOpen(_Symbol,  PERIOD_CURRENT, 2); // Vela anterior
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 2);
      double high1  = iHigh(_Symbol,  PERIOD_CURRENT, 2);
      double low1   = iLow(_Symbol,   PERIOD_CURRENT, 2);

      double corpo0      = MathAbs(close0 - open0);
      double corpo1      = MathAbs(close1 - open1);
      double sombra_inf0 = MathMin(open0, close0) - low0;
      double sombra_sup0 = high0 - MathMax(open0, close0);
      bool   alta0       = close0 > open0; // true = candle de alta
      bool   alta1       = close1 > open1;

      bool confirmado = false;

      // --- VERIFICA ENGOLFO ---
      if(UsarEngolfo && !confirmado)
      {
         if(tipo == 1) // Compra: engolfo de alta (bullish engulfing)
         {
            // Vela anterior de baixa, vela atual de alta que engolfa
            bool engolfo_alta = !alta1 && alta0
                             && close0 > open1
                             && open0  < close1
                             && corpo0 >= corpo1 * EngolfoRatio;
            if(engolfo_alta)
            {
               confirmado = true;
               Log(StringFormat("Confirmacao ENGOLFO ALTA no nivel %d (%.5f)", i, estados[i].nivel_preco), true);
            }
         }
         else // Venda: engolfo de baixa (bearish engulfing)
         {
            bool engolfo_baixa = alta1 && !alta0
                              && close0 < open1
                              && open0  > close1
                              && corpo0 >= corpo1 * EngolfoRatio;
            if(engolfo_baixa)
            {
               confirmado = true;
               Log(StringFormat("Confirmacao ENGOLFO BAIXA no nivel %d (%.5f)", i, estados[i].nivel_preco), true);
            }
         }
      }

      // --- VERIFICA PIN BAR ---
      if(UsarPinBar && !confirmado && corpo0 > 0)
      {
         if(tipo == 1) // Compra: pin bar de alta (martelo) — sombra inferior longa
         {
            bool martelo = sombra_inf0 >= corpo0 * PinBarRatio
                        && sombra_sup0 <= corpo0 * 0.5
                        && alta0; // Preferência por fechar positivo
            if(martelo)
            {
               confirmado = true;
               Log(StringFormat("Confirmacao PIN BAR ALTA (Martelo) no nivel %d (%.5f)", i, estados[i].nivel_preco), true);
            }
         }
         else // Venda: pin bar de baixa (estrela cadente) — sombra superior longa
         {
            bool estrela = sombra_sup0 >= corpo0 * PinBarRatio
                        && sombra_inf0 <= corpo0 * 0.5
                        && !alta0; // Preferência por fechar negativo
            if(estrela)
            {
               confirmado = true;
               Log(StringFormat("Confirmacao PIN BAR BAIXA (Estrela Cadente) no nivel %d (%.5f)", i, estados[i].nivel_preco), true);
            }
         }
      }

      // --- VERIFICA DOJI ---
      if(UsarDoji && !confirmado)
      {
         // Doji = corpo muito pequeno (menos de 10% do range da vela)
         double range0 = high0 - low0;
         if(range0 > 0 && corpo0 / range0 < 0.1)
         {
            confirmado = true;
            Log(StringFormat("Confirmacao DOJI no nivel %d (%.5f)", i, estados[i].nivel_preco), true);
         }
      }

      if(confirmado)
      {
         estados[i].confirmado = true;
      }
   }
}

//+------------------------------------------------------------------+
//| TentarEntrar — Executa entrada quando há confirmação Fibonacci     |
//+------------------------------------------------------------------+

void TentarEntrar()
{
   if(!fib.calculado) return;

   double preco_atual = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = 0; i < 3; i++)
   {
      if(!estados[i].confirmado) continue;

      int    tipo = estados[i].tipo;
      double nivel_entrada = estados[i].nivel_preco;

      // ---- CALCULA STOP LOSS DINÂMICO ----
      double sl = CalcularSL(tipo, SLCandles);
      if(sl <= 0)
      {
         Log("SL inválido calculado — ignorando entrada.");
         estados[i].confirmado = false;
         continue;
      }

      // Verifica se o SL não excede o máximo permitido
      double sl_em_pips = MathAbs(preco_atual - sl) / pip_size;
      if(sl_em_pips > SLMaxPips)
      {
         Log(StringFormat("SL muito grande (%.1f pips > máx %.1f pips) — ignorando.", sl_em_pips, SLMaxPips));
         estados[i].confirmado = false;
         continue;
      }

      // ---- CALCULA TAKE PROFIT (próximo nível Fibonacci) ----
      double tp = CalcularTP(tipo, nivel_entrada, i);
      if(tp <= 0)
      {
         Log("TP inválido calculado — ignorando entrada.");
         estados[i].confirmado = false;
         continue;
      }

      // Verifica TP mínimo
      double tp_em_pips = MathAbs(tp - preco_atual) / pip_size;
      if(tp_em_pips < TPMinPips)
      {
         Log(StringFormat("TP muito pequeno (%.1f pips < mín %.1f pips) — ignorando.", tp_em_pips, TPMinPips));
         estados[i].confirmado = false;
         continue;
      }

      // ---- CALCULA LOTE ----
      int slot_ordem = ordens_abertas; // Índice do slot atual (0-4)
      double lote = CalcularLote(sl, tipo, slot_ordem);
      if(lote <= 0)
      {
         Log("Lote inválido — ignorando entrada.");
         continue;
      }

      // ---- EXECUTA A ORDEM ----
      int magic_ordem = MagicBase + slot_ordem;
      trader.SetExpertMagicNumber(magic_ordem);

      string comentario = StringFormat("FIB-V2 Nível %s | SL_din | TP_fib",
                                       i==0 ? "38.2%" : (i==1 ? "50.0%" : "61.8%"));
      bool resultado = false;

      if(tipo == 1)
      {
         double preco_compra = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         resultado = trader.Buy(lote, _Symbol, preco_compra, sl, tp, comentario);
         LogTrade(StringFormat("COMPRA | Nível Fib %d | Preço: %.5f | SL: %.5f (%.1f pips) | TP: %.5f (%.1f pips) | Lote: %.2f | Magic: %d",
                               i, preco_compra, sl, sl_em_pips, tp, tp_em_pips, lote, magic_ordem));
      }
      else
      {
         double preco_venda = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         resultado = trader.Sell(lote, _Symbol, preco_venda, sl, tp, comentario);
         LogTrade(StringFormat("VENDA | Nível Fib %d | Preço: %.5f | SL: %.5f (%.1f pips) | TP: %.5f (%.1f pips) | Lote: %.2f | Magic: %d",
                               i, preco_venda, sl, sl_em_pips, tp, tp_em_pips, lote, magic_ordem));
      }

      if(resultado)
      {
         trades_hoje++;
         ordens_abertas++;
         estados[i].confirmado  = false; // Reset para não entrar duplo
         estados[i].preco_tocou = false;

         // Registra trailing info
         ulong ticket_novo = trader.ResultOrder();
         RegistrarTrailing(ticket_novo, sl);

         LogTrade(StringFormat("Ordem aberta com sucesso! Ticket: %d | Trades hoje: %d", ticket_novo, trades_hoje));
      }
      else
      {
         Log(StringFormat("Falha ao abrir ordem | Erro: %d — %s",
             GetLastError(), trader.ResultComment()), true);
      }

      // Só entra em 1 nível por vez (espera próxima vela para o seguinte)
      break;
   }
}

//+------------------------------------------------------------------+
//| CalcularSL — Stop Loss dinâmico baseado nos últimos N candles      |
//+------------------------------------------------------------------+

double CalcularSL(int tipo, int n_candles)
{
   double extremo = 0;

   if(tipo == 1) // Compra: SL abaixo da mínima dos últimos N candles
   {
      double lows[];
      ArraySetAsSeries(lows, true);
      if(CopyLow(_Symbol, PERIOD_CURRENT, 1, n_candles, lows) < n_candles)
      {
         Log("Erro ao copiar lows para SL dinâmico.");
         return 0;
      }
      int idx = ArrayMinimum(lows, 0, n_candles);
      extremo = lows[idx];
      return extremo - sl_buffer_pts; // SL = mínima - buffer
   }
   else // Venda: SL acima da máxima dos últimos N candles
   {
      double highs[];
      ArraySetAsSeries(highs, true);
      if(CopyHigh(_Symbol, PERIOD_CURRENT, 1, n_candles, highs) < n_candles)
      {
         Log("Erro ao copiar highs para SL dinâmico.");
         return 0;
      }
      int idx = ArrayMaximum(highs, 0, n_candles);
      extremo = highs[idx];
      return extremo + sl_buffer_pts; // SL = máxima + buffer
   }
}

//+------------------------------------------------------------------+
//| CalcularTP — Próximo nível Fibonacci como alvo                    |
//+------------------------------------------------------------------+

double CalcularTP(int tipo, double nivel_atual, int idx_atual)
{
   if(!fib.calculado) return 0;

   // Nivéis disponíveis em ordem para tendência de alta (compra)
   // Em tendência de alta: os níveis de retração são 61.8 → 50 → 38.2 (de baixo p/ cima)
   // Entrada em 61.8, TP em 50.0 ou 38.2 ou swing_high
   // Entrada em 50.0, TP em 38.2 ou swing_high
   // Entrada em 38.2, TP em swing_high

   double tp = 0;

   if(tipo == 1) // Compra — TP acima (subindo pelos niveis Fib)
   {
      if(idx_atual == 2) // Entrada no 61.8 — TP no 50.0
         tp = fib.nivel_500 - tp_buffer_pts;
      else if(idx_atual == 1) // Entrada no 50.0 — TP no 38.2
         tp = fib.nivel_382 - tp_buffer_pts;
      else if(idx_atual == 0) // Entrada no 38.2 — TP no swing_high
         tp = fib.swing_high - tp_buffer_pts;

      // Garante que TP está acima do preço atual
      if(tp <= SymbolInfoDouble(_Symbol, SYMBOL_ASK))
      {
         Log("TP calculado está abaixo do preço de compra — usando swing_high.");
         tp = fib.swing_high - tp_buffer_pts;
      }
   }
   else // Venda — TP abaixo (descendo pelos niveis Fib)
   {
      if(idx_atual == 2) // Entrada no 61.8 (retração de baixa) — TP no 50.0
         tp = fib.nivel_500 + tp_buffer_pts;
      else if(idx_atual == 1) // Entrada no 50.0 — TP no 38.2
         tp = fib.nivel_382 + tp_buffer_pts;
      else if(idx_atual == 0) // Entrada no 38.2 — TP no swing_low
         tp = fib.swing_low + tp_buffer_pts;

      // Garante que TP está abaixo do preço atual
      if(tp >= SymbolInfoDouble(_Symbol, SYMBOL_BID))
      {
         Log("TP calculado está acima do preço de venda — usando swing_low.");
         tp = fib.swing_low + tp_buffer_pts;
      }
   }

   return tp;
}

//+------------------------------------------------------------------+
//| CalcularLote — Calcula lote com gestão de risco                   |
//+------------------------------------------------------------------+

double CalcularLote(double sl, int tipo, int slot)
{
   double saldo = AccountInfoDouble(ACCOUNT_BALANCE);
   double preco;

   if(tipo == 1)
      preco = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      preco = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Risco máximo em dinheiro
   double risco_max = saldo * RiscoMaxPorcentagem / 100.0;

   // Distância ao SL em pontos
   double dist_sl = MathAbs(preco - sl);
   if(dist_sl <= 0) return LoteBase;

   // Valor do pip
   double valor_pip = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(valor_pip <= 0) return LoteBase;

   // Lote calculado pelo risco
   double lote_calculado = risco_max / (dist_sl / _Point * valor_pip);

   // Aplica multiplicador de pirâmide (ordens mais tardias são maiores se in profit)
   // Mas só aumenta se as outras ordens estiverem positivas
   double multiplicador = 1.0;
   if(slot > 0 && LoteMultiplicador > 1.0)
   {
      // Verifica se ordens anteriores estão positivas
      double lucro_total = 0;
      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionGetInteger(POSITION_MAGIC) >= MagicBase &&
            PositionGetInteger(POSITION_MAGIC) <= MagicBase + MaxOrdens - 1)
         {
            lucro_total += PositionGetDouble(POSITION_PROFIT);
         }
      }
      if(lucro_total > 0)
         multiplicador = MathPow(LoteMultiplicador, slot);
      Log(StringFormat("Pirâmide slot %d | Lucro total: %.2f | Multiplicador: %.2f", slot, lucro_total, multiplicador));
   }

   lote_calculado *= multiplicador;

   // Normaliza e limita aos mínimos/máximos do ativo
   double lote_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lote_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lote_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lote_calculado = MathMax(lote_min, MathMin(lote_max, lote_calculado));
   lote_calculado = MathRound(lote_calculado / lote_step) * lote_step;

   Log(StringFormat("Lote calculado: %.2f | Risco máx: %.2f | Slot: %d", lote_calculado, risco_max, slot));
   return lote_calculado;
}

//+------------------------------------------------------------------+
//| RegistrarTrailing — Registra info de trailing para ticket         |
//+------------------------------------------------------------------+

void RegistrarTrailing(ulong ticket, double sl_inicial)
{
   for(int i = 0; i < 5; i++)
   {
      if(trailing[i].ticket == 0)
      {
         trailing[i].ticket         = ticket;
         trailing[i].sl_atual       = sl_inicial;
         trailing[i].melhor_preco   = 0;
         trailing[i].trailing_ativo = false;
         trailing[i].pullback_visto = false;
         trailing_count++;
         Log(StringFormat("Trailing registrado | Ticket: %d | SL inicial: %.5f", ticket, sl_inicial));
         return;
      }
   }
   Log("Slots de trailing cheios — não foi possível registrar.", true);
}

//+------------------------------------------------------------------+
//| GerenciarTrailing — Atualiza trailing stop a cada tick            |
//+------------------------------------------------------------------+

void GerenciarTrailing()
{
   for(int i = 0; i < 5; i++)
   {
      if(trailing[i].ticket == 0) continue;

      // Verifica se a posição ainda existe
      if(!PositionSelectByTicket(trailing[i].ticket))
      {
         // Posição fechada — limpa o slot
         Log(StringFormat("Trailing: Posição %d fechada — limpando slot.", trailing[i].ticket));
         trailing[i].ticket = 0;
         trailing[i].trailing_ativo = false;
         trailing_count--;
         continue;
      }

      ENUM_POSITION_TYPE pos_tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double sl_atual  = PositionGetDouble(POSITION_SL);
      double preco_aberto = PositionGetDouble(POSITION_PRICE_OPEN);
      double lucro    = PositionGetDouble(POSITION_PROFIT);

      double preco_mercado;
      double lucro_em_pips;

      if(pos_tipo == POSITION_TYPE_BUY)
      {
         preco_mercado  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         lucro_em_pips  = (preco_mercado - preco_aberto) / pip_size;
      }
      else
      {
         preco_mercado  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         lucro_em_pips  = (preco_aberto - preco_mercado) / pip_size;
      }

      // Verifica lucro mínimo para ativar trailing
      if(lucro_em_pips < TrailingMinLucro)
      {
         // Atualiza melhor preço mesmo sem trailing ativo
         if(trailing[i].melhor_preco == 0)
            trailing[i].melhor_preco = preco_aberto;
         continue; // Trailing ainda não pode ser ativado
      }

      // ---- VERIFICA PULLBACK CONFIRMADO (para modo conservador) ----
      bool pode_mover = true;
      if(TrailingPullback && !trailing[i].pullback_visto)
      {
         // Verifica se houve pullback: preço recuou pelo menos 1 pip e voltou
         if(trailing[i].melhor_preco == 0)
            trailing[i].melhor_preco = preco_mercado;

         if(pos_tipo == POSITION_TYPE_BUY)
         {
            // Melhor preço no buy é o mais alto
            if(preco_mercado > trailing[i].melhor_preco)
               trailing[i].melhor_preco = preco_mercado;

            // Pullback = preço recuou 5+ pips da máxima e está subindo de novo
            double recuo = (trailing[i].melhor_preco - preco_mercado) / pip_size;
            if(recuo >= 3.0)
            {
               // Registra que houve pullback
               trailing[i].pullback_visto = true;
               Log(StringFormat("Pullback confirmado em compra | Ticket: %d | Recuo: %.1f pips",
                   trailing[i].ticket, recuo));
            }
         }
         else
         {
            // Melhor preço no sell é o mais baixo
            if(preco_mercado < trailing[i].melhor_preco || trailing[i].melhor_preco == 0)
               trailing[i].melhor_preco = preco_mercado;

            double recuo = (preco_mercado - trailing[i].melhor_preco) / pip_size;
            if(recuo >= 3.0)
            {
               trailing[i].pullback_visto = true;
               Log(StringFormat("Pullback confirmado em venda | Ticket: %d | Recuo: %.1f pips",
                   trailing[i].ticket, recuo));
            }
         }

         if(!trailing[i].pullback_visto)
            pode_mover = false; // Ainda aguardando pullback
      }

      if(!pode_mover) continue;

      // ---- CALCULA NOVO SL DO TRAILING ----
      double novo_sl = 0;

      if(pos_tipo == POSITION_TYPE_BUY)
      {
         novo_sl = preco_mercado - (TrailingBuffer * pip_size);
         // Trailing só move para CIMA (nunca reduz proteção)
         if(novo_sl > sl_atual + trailing_pts)
         {
            // Confirma o novo SL
            if(trader.PositionModify(trailing[i].ticket, novo_sl, PositionGetDouble(POSITION_TP)))
            {
               trailing[i].sl_atual = novo_sl;
               trailing[i].trailing_ativo = true;
               Log(StringFormat("Trailing movido COMPRA | Ticket: %d | Novo SL: %.5f (lucro: %.1f pips)",
                   trailing[i].ticket, novo_sl, lucro_em_pips));
            }
         }
      }
      else
      {
         novo_sl = preco_mercado + (TrailingBuffer * pip_size);
         // Trailing só move para BAIXO (nunca reduz proteção)
         if(novo_sl < sl_atual - trailing_pts)
         {
            if(trader.PositionModify(trailing[i].ticket, novo_sl, PositionGetDouble(POSITION_TP)))
            {
               trailing[i].sl_atual = novo_sl;
               trailing[i].trailing_ativo = true;
               Log(StringFormat("Trailing movido VENDA | Ticket: %d | Novo SL: %.5f (lucro: %.1f pips)",
                   trailing[i].ticket, novo_sl, lucro_em_pips));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ContarOrdens — Conta posições abertas com nosso magic             |
//+------------------------------------------------------------------+

int ContarOrdens()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(magic >= MagicBase && magic <= MagicBase + MaxOrdens - 1)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| OnChartEvent — Painel informativo no gráfico                      |
//+------------------------------------------------------------------+

void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
{
   // Reservado para futuras interações de painel
}

//+------------------------------------------------------------------+
//| ExibirStatus — Mostra informações no gráfico do chart             |
//+------------------------------------------------------------------+

void ExibirStatus()
{
   if(fib.calculado)
   {
      string info = StringFormat(
         "MAESTRO V2 FIBONACCI\n"
         "========================\n"
         "Fib Swing: H=%.5f | L=%.5f\n"
         "Tendência: %s\n"
         "38.2%%: %.5f  %s\n"
         "50.0%%: %.5f  %s\n"
         "61.8%%: %.5f  %s\n"
         "========================\n"
         "Ordens abertas: %d/%d\n"
         "Trades hoje: %d/%d",
         fib.swing_high, fib.swing_low,
         fib.tendencia_alta ? "ALTA (comprar retração)" : "BAIXA (vender retração)",
         fib.nivel_382, estados[0].confirmado ? "[CONFIRMADO]" : (estados[0].preco_tocou ? "[TOCADO]" : ""),
         fib.nivel_500, estados[1].confirmado ? "[CONFIRMADO]" : (estados[1].preco_tocou ? "[TOCADO]" : ""),
         fib.nivel_618, estados[2].confirmado ? "[CONFIRMADO]" : (estados[2].preco_tocou ? "[TOCADO]" : ""),
         ordens_abertas, MaxOrdens,
         trades_hoje, MaxTradesPorDia
      );
      Comment(info);
   }
   else
   {
      Comment("MAESTRO V2 FIBONACCI\nCalculando Fibonacci...");
   }
}

//+------------------------------------------------------------------+
//| FIM DO EXPERT ADVISOR                                             |
//+------------------------------------------------------------------+
