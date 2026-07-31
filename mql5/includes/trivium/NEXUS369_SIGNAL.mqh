//+------------------------------------------------------------------+
//| NEXUS369_SIGNAL.mqh                                              |
//| TRIVIUM369 (c) 2026 - Nucleo de sinal compartilhado               |
//|                                                                    |
//| Extraido de NEXUS369_LEVELS.mq5 (08/07/2026, pedido Ronei) para   |
//| virar biblioteca reutilizavel - "um so cerebro, duas bocas".      |
//| Hoje so o indicador consome isto. NAO esta plugado no EA de       |
//| execucao (NEXUS369_TREND_VALIDADO), que continua com sua propria  |
//| logica ja validada estatisticamente (ADX+Volume+DI). Este nucleo  |
//| so deve virar sinal de EXECUCAO depois de validado com o mesmo    |
//| rigor (backtest, permutacao, out-of-sample) - ver SPEC_EA_        |
//| SELETOR_ATIVO.md secao 6 como modelo do processo de validacao.    |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#include <TRIVIUM\NEXUS369_REGIME.mqh>

//+------------------------------------------------------------------+
//| Estados da maquina de sinal                                       |
//+------------------------------------------------------------------+
enum ENUM_NEXUS_SIGNAL_STATE
{
   NEXUS_STATE_IDLE,
   NEXUS_STATE_ARMED_BUY,
   NEXUS_STATE_ARMED_SELL,
   NEXUS_STATE_COOLDOWN
};

//+------------------------------------------------------------------+
//| Veredito retornado a cada barra                                   |
//+------------------------------------------------------------------+
struct NexusVeredito
{
   int    acao;           // +1 = BUY, -1 = SELL, 0 = nada nesta barra
   double confianca;      // 0-100, aproximado (baseado em distancia do RSI da zona)
   ENUM_NEXUS_SIGNAL_STATE estado; // estado da maquina apos processar a barra
};

//+------------------------------------------------------------------+
//| Motor de sinal - mantem seu proprio estado internamente.         |
//| Cada consumidor (indicador, EA) instancia o SEU objeto - nunca    |
//| compartilham estado entre si, so a LOGICA (o codigo) e comum.    |
//+------------------------------------------------------------------+
class CNexusSignalEngine
{
private:
   ENUM_NEXUS_SIGNAL_STATE m_estado;
   int    m_armed_bar_count;
   int    m_armed_level;
   double m_rsi_at_arming;
   int    m_regime_at_arming;
   int    m_cooldown_counter;
   double m_central_when_triggered;

   int    m_rsi_overb;
   int    m_rsi_overs;
   int    m_cooldown_bars;
   int    m_armed_window_bars;
   bool   m_require_extreme_at_arm;

public:
   void Config(int rsi_overb, int rsi_overs, int cooldown_bars,
               int armed_window_bars, bool require_extreme_at_arm)
   {
      m_rsi_overb = rsi_overb;
      m_rsi_overs = rsi_overs;
      m_cooldown_bars = cooldown_bars;
      m_armed_window_bars = armed_window_bars;
      m_require_extreme_at_arm = require_extreme_at_arm;
      Reset();
   }

   void Reset()
   {
      m_estado = NEXUS_STATE_IDLE;
      m_armed_bar_count = 0;
      m_armed_level = 0;
      m_rsi_at_arming = 50.0;
      m_regime_at_arming = REGIME_NEUTRO;
      m_cooldown_counter = 0;
      m_central_when_triggered = 0.0;
   }

   ENUM_NEXUS_SIGNAL_STATE Estado() const { return m_estado; }

   //+---------------------------------------------------------------+
   //| Processa UMA barra fechada. Chamar em ordem cronologica,      |
   //| barra por barra (nunca pular), do mais antigo pro mais novo.  |
   //+---------------------------------------------------------------+
   NexusVeredito Processar(double close_sig, double high_sig, double low_sig, double prev_close,
                           double central_sig, double b1u, double b1l,
                           double b2u, double b2l, double b3u, double b3l,
                           double rsi_val, double rsi_prev,
                           const RegimeResult &regime, double atr_val)
   {
      NexusVeredito v;
      v.acao = 0;
      v.confianca = 0;

      if(m_estado == NEXUS_STATE_ARMED_BUY || m_estado == NEXUS_STATE_ARMED_SELL)
         m_armed_bar_count++;

      if(m_estado == NEXUS_STATE_COOLDOWN)
      {
         m_cooldown_counter++;
         bool visitou_central = false;
         if(central_sig != EMPTY_VALUE && m_central_when_triggered != 0.0)
         {
            if((prev_close >= m_central_when_triggered && close_sig <= m_central_when_triggered) ||
               (prev_close <= m_central_when_triggered && close_sig >= m_central_when_triggered))
               visitou_central = true;
         }
         if(visitou_central || m_cooldown_counter >= m_cooldown_bars)
         {
            m_estado = NEXUS_STATE_IDLE;
            m_cooldown_counter = 0;
            m_armed_bar_count = 0;
         }
      }

      switch(m_estado)
      {
         case NEXUS_STATE_IDLE:
         {
            if(low_sig < b3l && b3l != EMPTY_VALUE)
            {
               m_estado = NEXUS_STATE_ARMED_BUY; m_armed_bar_count = 0; m_armed_level = 3;
               m_rsi_at_arming = rsi_val; m_regime_at_arming = regime.estado;
            }
            else if(low_sig < b2l && b2l != EMPTY_VALUE)
            {
               m_estado = NEXUS_STATE_ARMED_BUY; m_armed_bar_count = 0; m_armed_level = 2;
               m_rsi_at_arming = rsi_val; m_regime_at_arming = regime.estado;
            }
            else if(high_sig > b3u && b3u != EMPTY_VALUE)
            {
               m_estado = NEXUS_STATE_ARMED_SELL; m_armed_bar_count = 0; m_armed_level = 3;
               m_rsi_at_arming = rsi_val; m_regime_at_arming = regime.estado;
            }
            else if(high_sig > b2u && b2u != EMPTY_VALUE)
            {
               m_estado = NEXUS_STATE_ARMED_SELL; m_armed_bar_count = 0; m_armed_level = 2;
               m_rsi_at_arming = rsi_val; m_regime_at_arming = regime.estado;
            }
            break;
         }

         case NEXUS_STATE_ARMED_BUY:
         {
            bool rejection = (m_armed_level == 3)
               ? (close_sig > b3l && b3l != EMPTY_VALUE && close_sig < b2u)
               : (close_sig > b2l && b2l != EMPTY_VALUE && close_sig < b2u);
            bool expired = (m_armed_bar_count > m_armed_window_bars);

            if(rejection && !regime.veto_choque)
            {
               bool rsi_extreme = (!m_require_extreme_at_arm) || (m_rsi_at_arming <= m_rsi_overs);
               bool rsi_crossed = (rsi_prev <= m_rsi_overs && rsi_val > m_rsi_overs);
               bool regime_ok = (regime.estado == REGIME_RANGE || regime.estado == REGIME_TREND_UP);

               if(rsi_extreme && rsi_crossed && regime_ok)
               {
                  v.acao = +1;
                  v.confianca = MathMin(100.0, MathAbs(m_rsi_overs - m_rsi_at_arming) * 4.0 + 60.0);
                  m_central_when_triggered = central_sig;
                  m_estado = NEXUS_STATE_COOLDOWN; m_cooldown_counter = 0; m_armed_bar_count = 0;
               }
            }

            if(expired && m_estado == NEXUS_STATE_ARMED_BUY)
            {
               m_estado = NEXUS_STATE_COOLDOWN; m_cooldown_counter = 0;
               m_central_when_triggered = central_sig; m_armed_bar_count = 0;
            }
            break;
         }

         case NEXUS_STATE_ARMED_SELL:
         {
            bool rejection = (m_armed_level == 3)
               ? (close_sig < b3u && b3u != EMPTY_VALUE && close_sig > b2l)
               : (close_sig < b2u && b2u != EMPTY_VALUE && close_sig > b2l);
            bool expired = (m_armed_bar_count > m_armed_window_bars);

            if(rejection && !regime.veto_choque)
            {
               bool rsi_extreme = (!m_require_extreme_at_arm) || (m_rsi_at_arming >= m_rsi_overb);
               bool rsi_crossed = (rsi_prev >= m_rsi_overb && rsi_val < m_rsi_overb);
               bool regime_ok = (regime.estado == REGIME_RANGE || regime.estado == REGIME_TREND_DOWN);

               if(rsi_extreme && rsi_crossed && regime_ok)
               {
                  v.acao = -1;
                  v.confianca = MathMin(100.0, MathAbs(m_rsi_at_arming - m_rsi_overb) * 4.0 + 60.0);
                  m_central_when_triggered = central_sig;
                  m_estado = NEXUS_STATE_COOLDOWN; m_cooldown_counter = 0; m_armed_bar_count = 0;
               }
            }

            if(expired && m_estado == NEXUS_STATE_ARMED_SELL)
            {
               m_estado = NEXUS_STATE_COOLDOWN; m_cooldown_counter = 0;
               m_central_when_triggered = central_sig; m_armed_bar_count = 0;
            }
            break;
         }

         case NEXUS_STATE_COOLDOWN:
            break;
      }

      v.estado = m_estado;
      return v;
   }
};
//+------------------------------------------------------------------+
