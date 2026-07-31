//+------------------------------------------------------------------+
//| NEXUS369_REGIME.mqh                                              |
//| TRIVIUM369 © 2026 - Modulo 3: Classificacao de Regime            |
//|  T9: fix histerese (param prev_estado), fix veto choque (TR7),   |
//|  fix BBW squeeze (media movel 50 periodos)                       |
//|                                                                  |
//| Efficiency Ratio(10) + slope da central (ATRs/barra)             |
//| + histerese + veto de choque + BBW squeeze flag                  |
//|                                                                  |
//| Uso: incluir e chamar TriviumRegime() a cada barra fechada.      |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 © 2026"

//+------------------------------------------------------------------+
//| Estados do Regime                                                |
//+------------------------------------------------------------------+
#define REGIME_TREND_UP    2   // Tendencia de alta
#define REGIME_TREND_DOWN -2   // Tendencia de baixa
#define REGIME_RANGE       1   // Range (lateral)
#define REGIME_NEUTRO      0   // Neutro / transicao

//+------------------------------------------------------------------+
//| Struct de retorno do Regime                                      |
//+------------------------------------------------------------------+
struct RegimeResult
{
   int    estado;          // -2..+2
   double er;              // Efficiency Ratio de Kaufman
   double slope;           // Slope da central em ATRs/barra
   double atr_ratio;       // ATR(7) / ATR(55) - choque
   bool   bbw_squeeze;     // Bollinger Band Width squeeze
   bool   veto_choque;     // True se ATR_ratio > limite
};

//+------------------------------------------------------------------+
//| Calcula Efficiency Ratio de Kaufman (ER)                         |
//+------------------------------------------------------------------+
double CalcER(const double &price[], int len, int period)
{
   if(len < period + 1) return 0.0;

   double direction = MathAbs(price[len - 1] - price[len - 1 - period]);
   double volatility = 0.0;

   for(int i = len - period; i < len - 1; i++)
   {
      volatility += MathAbs(price[i + 1] - price[i]);
   }

   if(volatility > 0.0)
      return direction / volatility;
   else
      return 0.0;
}

//+------------------------------------------------------------------+
//| Calcula slope da central em ATRs/barra                           |
//| Formula canonica (Claudio): slope[i] = (central[i] - central[i+5])|
//|                                / (5 * ATR55[i])                  |
//+------------------------------------------------------------------+
double CalcSlope(double central_atual, double central_5atras, double atr_atual)
{
   if(atr_atual <= 0.0) return 0.0;
   return (central_atual - central_5atras) / (5.0 * atr_atual);
}

//+------------------------------------------------------------------+
//| T9 Bug 5: Calcula o True Range de uma barra                      |
//+------------------------------------------------------------------+
double CalcTR(double high, double low, double prev_close)
{
   double tr1 = high - low;
   double tr2 = MathAbs(high - prev_close);
   double tr3 = MathAbs(low - prev_close);
   return MathMax(tr1, MathMax(tr2, tr3));
}

//+------------------------------------------------------------------+
//| T9 Bug 5: Calcula ATR(7) REAL a partir dos TRs                  |
//+------------------------------------------------------------------+
double CalcATR7_Real(const double &high[], const double &low[], const double &close[], int len, int idx)
{
   // Precisa de 8 barras (7 TRs)
   if(len < idx + 8) return 0.0;

   // Calcular TR das 7 barras
   double tr_sum = 0.0;
   for(int j = 0; j < 7; j++)
   {
      int bar = idx + j;
      double prev_close = (bar + 1 < len) ? close[bar + 1] : close[bar];
      tr_sum += CalcTR(high[bar], low[bar], prev_close);
   }
   return tr_sum / 7.0;
}

//+------------------------------------------------------------------+
//| T9 Bug 6b: Calcula BBW squeeze com media movel (50 periodos)     |
//+------------------------------------------------------------------+
struct BBWResult
{
   double bbw_atual;
   double bbw_media_50;
   bool   squeeze;
};

BBWResult CalcBBWAvancado(const double &close_array[], int len, int idx, int bb_period=20, double bb_std=2.0)
{
   BBWResult res;
   res.bbw_atual   = 0.0;
   res.bbw_media_50 = 0.0;
   res.squeeze     = false;

   // Precisa de bb_period + 50 barras para media
   if(len < idx + bb_period + 50) return res;

   // Calcular BBW para as ultimas 50 barras
   double bbw_vals[50];
   int count = 0;

   for(int k = 0; k < 50; k++)
   {
      int start = idx + k;
      if(start + bb_period > len) break;

      // Media
      double sum = 0.0;
      for(int i = start; i < start + bb_period; i++)
         sum += close_array[i];
      double mean = sum / bb_period;

      // Desvio padrao
      double sq_sum = 0.0;
      for(int i = start; i < start + bb_period; i++)
         sq_sum += (close_array[i] - mean) * (close_array[i] - mean);
      double std = MathSqrt(sq_sum / bb_period);

      // BBW
      if(mean > 0.0)
         bbw_vals[count] = (2.0 * bb_std * std) / mean;
      else
         bbw_vals[count] = 0.0;

      count++;
   }

   if(count < 20) return res;

   // BBW atual = mais recente (primeiro do loop)
   res.bbw_atual = bbw_vals[0];

   // Media dos 50 periodos
   double soma = 0.0;
   for(int k = 0; k < count; k++)
      soma += bbw_vals[k];
   res.bbw_media_50 = soma / count;

   // T9 Bug 6b: squeeze = BBW atual < media_BBW_50 * 0.75
   if(res.bbw_media_50 > 0.0)
      res.squeeze = (res.bbw_atual < res.bbw_media_50 * 0.75);

   return res;
}

//+------------------------------------------------------------------+
//| Funcao principal: classifica o regime                             |
//|                                                                  |
//| Parametros:                                                      |
//|   close[]      - array de precos de fechamento (as series)        |
//|   high[]       - array de precos maxima (as series)               |
//|   low[]        - array de precos minima (as series)               |
//|   central[]    - array da linha central (as series)               |
//|   atr55[]      - array do ATR Wilder(55) (as series)              |
//|   len          - comprimento dos arrays                           |
//|   idx          - indice atual (0 = barra atual)                   |
//|   is_crypto    - true se modo cripto (limiares diferentes)        |
//|   er_period    - periodo do ER (default 10)                       |
//|   prev_estado  - T9: estado anterior para histerese funcionar     |
//|   result       - [saida] struct RegimeResult                      |
//|                                                                  |
//| Retorna: int estado (-2..+2)                                     |
//+------------------------------------------------------------------+
int TriviumRegime(const double &close_array[],
                  const double &high_array[],
                  const double &low_array[],
                  const double &central[],
                  const double &atr55[],
                  int len,
                  int idx,
                  bool is_crypto,
                  int er_period,
                  int prev_estado,     // T9 Bug 4: estado anterior para histerese
                  RegimeResult &result)
{
//--- Inicializar resultado
   result.estado      = REGIME_NEUTRO;
   result.er          = 0.0;
   result.slope       = 0.0;
   result.atr_ratio   = 0.0;
   result.bbw_squeeze = false;
   result.veto_choque = false;

//--- Verificar dados suficientes
   int need = (er_period + 1);
   if(is_crypto) need = MathMax(need, 7);
   else need = MathMax(need, 5);

   if(len < need + 55) return REGIME_NEUTRO;
   if(idx + need >= len) return REGIME_NEUTRO;

//--- 1. Efficiency Ratio de Kaufman
//     Precisamos de close[idx+er_period] ate close[idx] (er_period+1 valores)
   double er_prices[];
   ArrayResize(er_prices, er_period + 1);
   for(int j = 0; j <= er_period; j++)
      er_prices[j] = close_array[idx + j];
   ArraySetAsSeries(er_prices, false);  // ordem cronologica
   result.er = CalcER(er_prices, er_period + 1, er_period);

//--- 2. Slope da central em ATRs/barra
//     Formula: (central[idx] - central[idx+5]) / (5 * ATR55[idx])
   double central_atual  = central[idx];
   double central_5atras = (idx + 5 < len) ? central[idx + 5] : central[idx];
   double atr_atual      = atr55[idx];

   result.slope = CalcSlope(central_atual, central_5atras, atr_atual);

//--- T9 Bug 5: ATR(7) REAL a partir dos True Ranges das ultimas 7 barras
   double atr7 = CalcATR7_Real(high_array, low_array, close_array, len, idx);

   if(atr_atual > 0.0)
      result.atr_ratio = atr7 / atr_atual;
   else
      result.atr_ratio = 0.0;

//--- 4. Veto de choque
   double limite_choque = is_crypto ? 1.4 : 1.5;
   result.veto_choque = (result.atr_ratio > limite_choque);

//--- T9 Bug 6b: BBW squeeze com media movel 50 periodos
   BBWResult bbw = CalcBBWAvancado(close_array, len, idx);
   result.bbw_squeeze = bbw.squeeze;

//--- 6. CLASSIFICAR REGIME COM HISTERESE (T9 Bug 4)

   // Limiares
   double er_entra  = is_crypto ? 0.30 : 0.35;
   double er_sai    = is_crypto ? 0.22 : 0.25;
   double slope_entra = is_crypto ? 0.06 : 0.08;
   double slope_sai   = is_crypto ? 0.03 : 0.04;

   // T9 Bug 4: usar prev_estado em vez de result.estado (que foi zerado)
   bool trend_up   = (result.er > er_entra && result.slope > slope_entra);
   bool trend_down = (result.er > er_entra && result.slope < -slope_entra);

   // Histerese: se ja esta em trend, criterios de saida sao mais frouxos
   if(prev_estado == REGIME_TREND_UP)
      trend_up = (result.er > er_sai && result.slope > slope_sai);
   if(prev_estado == REGIME_TREND_DOWN)
      trend_down = (result.er > er_sai && result.slope < -slope_sai);

   // Range: ER baixo e slope baixo
   bool is_range = (result.er < er_entra && MathAbs(result.slope) < slope_entra && !result.veto_choque);

   // Decisao
   if(result.veto_choque)
   {
      // Veto de choque: NAO_OPERA
      result.estado = REGIME_NEUTRO;
   }
   else if(trend_up)
   {
      result.estado = REGIME_TREND_UP;
   }
   else if(trend_down)
   {
      result.estado = REGIME_TREND_DOWN;
   }
   else if(is_range)
   {
      result.estado = REGIME_RANGE;
   }
   else
   {
      result.estado = REGIME_NEUTRO;
   }

   return result.estado;
}

//+------------------------------------------------------------------+
//| Retorna nome do estado                                           |
//+------------------------------------------------------------------+
string RegimeName(int estado)
{
   switch(estado)
   {
      case REGIME_TREND_UP:   return "TREND_UP";
      case REGIME_TREND_DOWN: return "TREND_DOWN";
      case REGIME_RANGE:      return "RANGE";
      case REGIME_NEUTRO:     return "NEUTRO";
      default:                return "DESCONHECIDO";
   }
}

//+------------------------------------------------------------------+
//| Retorna semaforo do estado                                       |
//+------------------------------------------------------------------+
string RegimeSemaforo(int estado)
{
   switch(estado)
   {
      case REGIME_TREND_UP:   return "OPERATENDENCIA";
      case REGIME_TREND_DOWN: return "OPERATENDENCIA";
      case REGIME_RANGE:      return "OPERAREVERSAO";
      case REGIME_NEUTRO:     return "NAO_OPERA";
      default:                return "NAO_OPERA";
   }
}
//+------------------------------------------------------------------+
