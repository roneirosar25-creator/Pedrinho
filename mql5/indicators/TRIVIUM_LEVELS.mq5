//+------------------------------------------------------------------+
//| NEXUS369_LEVELS.mq5 (ex-TRIVIUM_LEVELS)                          |
//| TRIVIUM369 © 2026 - Produto NEXUS369 - Fase 2.0                 |
//| Central SMMA/ALMA/EMA(21) + ATR Wilder(55) + 6 bandas + Signal   |
//|                                                                  |
//| T7: Auto-preset por simbolo (AUTO/FOREX/CRIPTO/MANUAL)          |
//| T6: ALMA manual + bandas EMPTY_VALUE na acumulacao              |
//| T5: Visual premium, labels L1/L2/L3, painel info                |
//| T4: Regime (ER10+slope+histerese+veto+BBW) via include          |
//| F3: Signal (maquina estados + setas compra/venda)               |
//| T9: Correcoes auditoria Pedrinho 05JUL (6 bugs)                 |
//| T10-fix: 06JUL Pedrinho — loop historico Regime+Signal (o bug   |
//|          real do "zero setas": so processava a ultima barra)    |
//|                                                                  |
//| Buffers: 0=Central, 1-6=Bandas, 7=BuyArr, 8=SellArr, 9=ATR      |
//| T11-fix: 06JUL Pedrinho - ATR movido pro FIM (buffer 9, calc-  |
//|          only) para eliminar de vez a ambiguidade buffer->plot|
//|          que causava seta de venda sumir e a de compra pegar  |
//|          a cor/posicao errada.                                |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 © 2026"
#property version   "2.09"
#property description "NEXUS369 LEVELS - Fase 2.0"
#property description "Central + 6 bandas ATR Wilder(55) + Regime + Signal"
#property description "Auto-preset: FOREX, CRIPTO ou MANUAL"

#property indicator_chart_window
#property indicator_buffers 10
#property indicator_plots   9

//--- Plot 1: Central
#property indicator_label1  "Central"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_width1  3

//--- Plot 2: Banda Superior N1 (venda)
#property indicator_label2  "Band1_U"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrTomato
#property indicator_width2  1
#property indicator_style2  STYLE_DOT

//--- Plot 3: Banda Inferior N1 (compra)
#property indicator_label3  "Band1_L"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDodgerBlue
#property indicator_width3  1
#property indicator_style3  STYLE_DOT

//--- Plot 4: Banda Superior N2 (venda)
#property indicator_label4  "Band2_U"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrOrangeRed
#property indicator_width4  1
#property indicator_style4  STYLE_DOT

//--- Plot 5: Banda Inferior N2 (compra)
#property indicator_label5  "Band2_L"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRoyalBlue
#property indicator_width5  1
#property indicator_style5  STYLE_DOT

//--- Plot 6: Banda Superior N3 (venda)
#property indicator_label6  "Band3_U"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrRed
#property indicator_width6  2
#property indicator_style6  STYLE_DOT

//--- Plot 7: Banda Inferior N3 (compra)
#property indicator_label7  "Band3_L"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrMediumBlue
#property indicator_width7  2
#property indicator_style7  STYLE_DOT

//--- Plot 8: Seta Compra (flecha para cima)
#property indicator_label8  "Buy"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  clrLimeGreen
#property indicator_width8  2

//--- Plot 9: Seta Venda (flecha para baixo)
#property indicator_label9  "Sell"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  clrRed
#property indicator_width9  2

//+------------------------------------------------------------------+
//| INCLUDES                                                         |
//+------------------------------------------------------------------+
#include <TRIVIUM\NEXUS369_REGIME.mqh>
#include <TRIVIUM\NEXUS369_SIGNAL.mqh>
// T12 (08/07/2026, pedido Ronei): maquina de estados do sinal extraida
// para NEXUS369_SIGNAL.mqh (CNexusSignalEngine) - "um so cerebro, duas
// bocas". O indicador agora so DESENHA o veredito, nao decide mais
// nada por conta propria. Ver diagrama em 03_SESSOES/.

//+------------------------------------------------------------------+
//| ENUM: Metodo da Media Central                                    |
//+------------------------------------------------------------------+
enum ENUM_TRIVIUM_MA
{
   TRIVIUM_SMMA = 0,   // SMMA (Smoothed) - DEFAULT
   TRIVIUM_ALMA = 1,   // ALMA (Arnaud Legoux) - manual
   TRIVIUM_EMA  = 2    // EMA (Exponential)
};

enum ENUM_ALMA_MODE
{
   ALMA_OFFSET_085 = 0,  // offset=0.85, sigma=6
   ALMA_OFFSET_050 = 1,  // offset=0.50, sigma=6
   ALMA_OFFSET_100 = 2   // offset=1.00, sigma=6
};

enum ENUM_PRESET
{
   PRESET_AUTO   = 0,   // AUTO (detecta pelo simbolo)
   PRESET_FOREX  = 1,   // FOREX (k 1.0/2.0/3.0)
   PRESET_CRIPTO = 2,   // CRIPTO (k 1.2/2.4/3.8)
   PRESET_MANUAL = 3    // MANUAL (usa os K digitados)
};

//+------------------------------------------------------------------+
//| INPUTS                                                           |
//+------------------------------------------------------------------+
input group "=== Modulo Estrutural ==="
input ENUM_TRIVIUM_MA InpMetodoMA    = TRIVIUM_SMMA;
input int             InpMAPeriod    = 21;
input ENUM_ALMA_MODE  InpAlmaMode   = ALMA_OFFSET_085;

input group "=== Modulo Volatilidade ==="
input ENUM_PRESET      InpPreset      = PRESET_AUTO;
input int              InpATRPeriod   = 55;
input double           InpK1_Forex    = 1.0;
input double           InpK2_Forex    = 2.0;
input double           InpK3_Forex    = 3.0;
input double           InpK1_Crypto   = 1.2;
input double           InpK2_Crypto   = 2.4;
input double           InpK3_Crypto   = 3.8;

input group "=== Modulo Regime ==="
input int             InpERPeriod     = 10;
input bool            InpUsarBBW      = false;   // Usar BBW squeeze como auxiliar

input group "=== Modulo Signal ==="
input int             InpRSIPeriod    = 14;      // Periodo RSI para confirmacao
input int             InpRSIOverB     = 53;      // RSI sobrecompra (calibrado 06JUL - estudo overnight)
input int             InpRSIOverS     = 47;      // RSI sobrevenda (calibrado 06JUL - estudo overnight)
input int             InpCooldownBars  = 5;      // Barras de cooldown apos sinal
input int             InpArmedWindowBars = 15;    // Barras p/ confirmar apos armar (era 3, fixo)
input bool            InpRequireExtremeAtArm = false; // Exigir RSI extremo NO momento de armar (era obrigatorio)

input group "=== Visual ==="
input color           InpCorCentral   = clrGold;
input int             InpEspCentral   = 3;
input color           InpCorN1Venda   = clrTomato;
input color           InpCorN1Compra  = clrDodgerBlue;
input color           InpCorN2Venda   = clrOrangeRed;
input color           InpCorN2Compra  = clrRoyalBlue;
input color           InpCorN3Venda   = clrRed;
input color           InpCorN3Compra  = clrMediumBlue;
input color           InpCorBuyArrow  = clrLimeGreen;
input color           InpCorSellArrow = clrRed;
input bool            InpMostrarLabels = true;
input bool            InpMostrarPainel = true;

input group "=== Geral ==="
input int             InpWarmUpBars   = 300;

//+------------------------------------------------------------------+
//| BUFFERS                                                          |
//+------------------------------------------------------------------+
double CentralBuff[];       // 0 - Central
double B1UBuff[];           // 1 - Banda Sup N1
double B1LBuff[];           // 2 - Banda Inf N1
double B2UBuff[];           // 3 - Banda Sup N2
double B2LBuff[];           // 4 - Banda Inf N2
double B3UBuff[];           // 5 - Banda Sup N3
double B3LBuff[];           // 6 - Banda Inf N3
double BuyArrowBuff[];      // 7 - Setas compra
double SellArrowBuff[];     // 8 - Setas venda
double ATRBuff[];           // 9 - ATR Wilder oculto (calc-only, por ultimo de proposito)

//+------------------------------------------------------------------+
//| HANDLES E VARIAVEIS GLOBAIS                                      |
//+------------------------------------------------------------------+
int ma_handle;
int rsi_handle;
long last_updated_bar;

//--- Motor de sinal compartilhado (NEXUS369_SIGNAL.mqh) - T12 08/07/2026
CNexusSignalEngine signal_engine;

//+------------------------------------------------------------------+
//| Detecta preset pelo simbolo                                      |
//+------------------------------------------------------------------+
ENUM_PRESET DetectPreset()
{
   string sym = _Symbol;
   StringToUpper(sym);

   // PEDRINHO FIX 06 JUL: "-T" e sufixo generico da Admirals p/ TODOS os
   // ativos (forex, ouro, cripto) - NAO e indicativo de cripto. Removido.
   if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0 ||
      StringFind(sym, "XRP") >= 0 || StringFind(sym, "LTC") >= 0 ||
      StringFind(sym, "DOGE") >= 0 || StringFind(sym, "SOL") >= 0 ||
      StringFind(sym, "ADA") >= 0 || StringFind(sym, "BNB") >= 0)
      return PRESET_CRIPTO;

   return PRESET_FOREX;
}

void GetKs(ENUM_PRESET preset, double &k1, double &k2, double &k3)
{
   if(preset == PRESET_CRIPTO)
   {
      k1 = InpK1_Crypto; k2 = InpK2_Crypto; k3 = InpK3_Crypto;
   }
   else
   {
      k1 = InpK1_Forex; k2 = InpK2_Forex; k3 = InpK3_Forex;
   }
}

string PresetName(ENUM_PRESET preset)
{
   if(preset == PRESET_AUTO)   return "AUTO";
   if(preset == PRESET_FOREX)  return "FOREX";
   if(preset == PRESET_CRIPTO) return "CRIPTO";
   return "MANUAL";
}

//+------------------------------------------------------------------+
//| Calcula ALMA manualmente                                         |
//+------------------------------------------------------------------+
double CalcALMA(const double &price[], int len, int period, double offset, double sigma)
{
   if(len < period) return 0.0;
   double m = offset * (period - 1);
   double s = period / sigma;
   double sum_w = 0.0, sum_wp = 0.0;
   for(int j = 0; j < period; j++)
   {
      double w = MathExp(-((j - m) * (j - m)) / (2.0 * s * s));
      sum_w += w;
      sum_wp += w * price[len - period + j];
   }
   return (sum_w > 0.0) ? (sum_wp / sum_w) : 0.0;
}

//+------------------------------------------------------------------+
//| Objetos graficos                                                 |
//+------------------------------------------------------------------+
void SetLabel(string name, string text, int x, int y, color clr, int fontSize=8, bool bold=false)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
}

void SetRectangle(string name, int x, int y, int w, int h, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
}

void DeleteObjects()
{
   string prefixes[] = {"TL_", "PN_", "RECT_"};
   for(int i = 0; i < ArraySize(prefixes); i++)
   {
      for(int j = ObjectsTotal(0, 0, -1) - 1; j >= 0; j--)
      {
         string obj_name = ObjectName(0, j);
         if(StringFind(obj_name, prefixes[i]) == 0)
            ObjectDelete(0, obj_name);
      }
   }
}

void UpdateVisuals(ENUM_PRESET active_preset, int regime_estado)
{
   datetime last_time = iTime(_Symbol, _Period, 0);
   double last_central = CentralBuff[0];
   double last_atr = ATRBuff[0];

   if(last_central == EMPTY_VALUE || last_central == 0.0) return;

   if(InpMostrarLabels)
   {
      int cx = 0, cy = 0;
      double b[6] = {B1UBuff[0], B1LBuff[0], B2UBuff[0], B2LBuff[0], B3UBuff[0], B3LBuff[0]};
      color c[6] = {InpCorN1Venda, InpCorN1Compra, InpCorN2Venda, InpCorN2Compra, InpCorN3Venda, InpCorN3Compra};
      string lbl[6] = {"TL_L1_U","TL_L1_L","TL_L2_U","TL_L2_L","TL_L3_U","TL_L3_L"};
      for(int i = 0; i < 6; i++)
      {
         if(ChartTimePriceToXY(0, 0, last_time, b[i], cx, cy) && b[i] != EMPTY_VALUE)
            SetLabel(lbl[i], "L" + string((i/2)+1), 5, cy - 10, c[i], 7, false);
      }
   }

   if(InpMostrarPainel)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double dist_atr = (bid - last_central) / last_atr;
      string modo_str = PresetName(active_preset);

      SetRectangle("RECT_PAINEL_BG", 5, 5, 175, 96, clrBlack);
      SetLabel("PN_TITULO", "NEXUS369 LEVELS", 170, 7, clrGold, 8, true);
      SetLabel("PN_MODO", "Modo: " + modo_str, 170, 22, clrWhite, 7, false);
      SetLabel("PN_REGIME", "Regime: " + RegimeSemaforo(regime_estado), 170, 34, clrWhite, 7, false);
      SetLabel("PN_CENTRAL", "Central: " + DoubleToString(NormalizeDouble(last_central, _Digits), _Digits), 170, 46, InpCorCentral, 7, false);
      SetLabel("PN_ATR", "ATR(" + IntegerToString(InpATRPeriod) + "): " + DoubleToString(NormalizeDouble(last_atr, _Digits), _Digits), 170, 58, clrWhite, 7, false);

      string dist_label = "Dist: " + DoubleToString(dist_atr, 2) + " ATRs";
      color dist_color = (dist_atr > 0) ? clrLimeGreen : ((dist_atr < 0) ? clrTomato : clrWhite);
      SetLabel("PN_DIST", dist_label, 170, 70, dist_color, 7, false);

      ENUM_NEXUS_SIGNAL_STATE est = signal_engine.Estado();
      string estado_str = (est == NEXUS_STATE_IDLE) ? "IDLE" :
                          (est == NEXUS_STATE_ARMED_BUY) ? "ARMED BUY" :
                          (est == NEXUS_STATE_ARMED_SELL) ? "ARMED SELL" :
                          "COOLDOWN";
      SetLabel("PN_SIGNAL", "Signal: " + estado_str, 170, 82, clrLightGray, 7, false);
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, CentralBuff, INDICATOR_DATA);
   SetIndexBuffer(1, B1UBuff, INDICATOR_DATA);
   SetIndexBuffer(2, B1LBuff, INDICATOR_DATA);
   SetIndexBuffer(3, B2UBuff, INDICATOR_DATA);
   SetIndexBuffer(4, B2LBuff, INDICATOR_DATA);
   SetIndexBuffer(5, B3UBuff, INDICATOR_DATA);
   SetIndexBuffer(6, B3LBuff, INDICATOR_DATA);
   SetIndexBuffer(7, BuyArrowBuff, INDICATOR_DATA);
   SetIndexBuffer(8, SellArrowBuff, INDICATOR_DATA);
   SetIndexBuffer(9, ATRBuff, INDICATOR_CALCULATIONS);

   ArraySetAsSeries(CentralBuff, true);
   ArraySetAsSeries(B1UBuff, true);
   ArraySetAsSeries(B1LBuff, true);
   ArraySetAsSeries(B2UBuff, true);
   ArraySetAsSeries(B2LBuff, true);
   ArraySetAsSeries(B3UBuff, true);
   ArraySetAsSeries(B3LBuff, true);
   ArraySetAsSeries(BuyArrowBuff, true);
   ArraySetAsSeries(SellArrowBuff, true);
   ArraySetAsSeries(ATRBuff, true);

   // Handles
   ma_handle = INVALID_HANDLE;
   if(InpMetodoMA == TRIVIUM_SMMA)
      ma_handle = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMMA, PRICE_TYPICAL);
   else if(InpMetodoMA == TRIVIUM_EMA)
      ma_handle = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_EMA, PRICE_TYPICAL);

   if(ma_handle == INVALID_HANDLE && InpMetodoMA != TRIVIUM_ALMA)
   {
      Print("Erro handle iMA: ", GetLastError());
      return INIT_FAILED;
   }

   rsi_handle = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(rsi_handle == INVALID_HANDLE)
   {
      Print("Erro handle RSI: ", GetLastError());
      return INIT_FAILED;
   }

   // Cores
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpCorCentral);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpEspCentral);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpCorN1Venda);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, InpCorN1Compra);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, InpCorN2Venda);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, InpCorN2Compra);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, InpCorN3Venda);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, InpCorN3Compra);
   // PEDRINHO FIX 06 JUL (v2): buffers reordenados - Buy=7, Sell=8, ATR=9
   // (ATR por ultimo, calc-only) - agora plot7=Buy e plot8=Sell sem ambiguidade
   PlotIndexSetInteger(7, PLOT_ARROW, 233);  // Seta p/ cima (BUY)
   PlotIndexSetInteger(7, PLOT_LINE_COLOR, InpCorBuyArrow);
   PlotIndexSetInteger(8, PLOT_ARROW, 234);  // Seta p/ baixo (SELL)
   PlotIndexSetInteger(8, PLOT_LINE_COLOR, InpCorSellArrow);

   // Draw begin
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpWarmUpBars);
   for(int i = 1; i <= 7; i++)
      PlotIndexSetInteger(i, PLOT_DRAW_BEGIN, InpWarmUpBars);
   PlotIndexSetInteger(8, PLOT_DRAW_BEGIN, InpWarmUpBars);
   PlotIndexSetInteger(9, PLOT_DRAW_BEGIN, InpWarmUpBars);

   // Shortname
   ENUM_PRESET ap = (InpPreset == PRESET_AUTO) ? DetectPreset() : InpPreset;
   string mm = (InpMetodoMA == TRIVIUM_SMMA) ? "SMMA" : ((InpMetodoMA == TRIVIUM_ALMA) ? "ALMA" : "EMA");
   IndicatorSetString(INDICATOR_SHORTNAME, "NEXUS369 LEVELS (" + mm + " " + PresetName(ap) + ")");

   // Estado inicial
   signal_engine.Config(InpRSIOverB, InpRSIOverS, InpCooldownBars,
                         InpArmedWindowBars, InpRequireExtremeAtArm);
   last_updated_bar = 0;
   DeleteObjects();

   Print("NEXUS369_LEVELS v2.09 INIT (T12 - sinal via NEXUS369_SIGNAL.mqh) | ", mm, " ", InpMAPeriod,
         " ATR", InpATRPeriod, " ER", InpERPeriod, " RSI", InpRSIPeriod,
         " Preset=", PresetName(ap));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpWarmUpBars + InpATRPeriod + InpMAPeriod)
      return 0;

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);

   int limit;
   if(prev_calculated == 0) limit = rates_total - 1;
   else
   {
      limit = rates_total - prev_calculated;
      if(limit < 0) limit = 0;
      if(limit > rates_total - 1) limit = rates_total - 1;
   }

   // Warm-up first run
   if(prev_calculated == 0)
   {
      int ws = rates_total - 1 - InpWarmUpBars;
      if(ws < 0) ws = 0;
      limit = rates_total - 1;
      for(int i = ws + 1; i < rates_total; i++)
      {
         CentralBuff[i] = EMPTY_VALUE;
         B1UBuff[i] = EMPTY_VALUE; B1LBuff[i] = EMPTY_VALUE;
         B2UBuff[i] = EMPTY_VALUE; B2LBuff[i] = EMPTY_VALUE;
         B3UBuff[i] = EMPTY_VALUE; B3LBuff[i] = EMPTY_VALUE;
         ATRBuff[i] = 0.0;
         BuyArrowBuff[i] = EMPTY_VALUE;
         SellArrowBuff[i] = EMPTY_VALUE;
      }

      // Resetar motor de sinal para full recalc
      signal_engine.Reset();
   }

   if(limit > rates_total - 2) limit = rates_total - 2;
   if(limit < 0) limit = 0;

   //--- Preset ativo
   ENUM_PRESET active_preset = (InpPreset == PRESET_AUTO) ? DetectPreset() : InpPreset;
   bool is_crypto = (active_preset == PRESET_CRIPTO);

   //=================================================================
   // 1. CALCULAR CENTRAL
   //=================================================================
   if(InpMetodoMA == TRIVIUM_ALMA)
   {
      double offset = (InpAlmaMode == ALMA_OFFSET_050) ? 0.50 :
                      (InpAlmaMode == ALMA_OFFSET_100) ? 1.00 : 0.85;
      for(int i = limit; i >= 0; i--)
      {
         int end = i + InpMAPeriod - 1;
         if(end < rates_total)
         {
            double ap[];
            ArrayResize(ap, InpMAPeriod);
            for(int j = 0; j < InpMAPeriod; j++)
            {
               int pi = end - j;
               ap[j] = (high[pi] + low[pi] + close[pi]) / 3.0;
            }
            CentralBuff[i] = CalcALMA(ap, InpMAPeriod, InpMAPeriod, offset, 6.0);
         }
      }
   }
   else
   {
      double ma[];
      ArraySetAsSeries(ma, true);
      int copied = CopyBuffer(ma_handle, 0, 0, rates_total, ma);
      if(copied < rates_total)
      {
         copied = CopyBuffer(ma_handle, 0, 0, rates_total - limit, ma);
         if(copied < rates_total - limit) return 0;
      }
      for(int i = limit; i >= 0; i--)
         if(i < rates_total && i < ArraySize(ma)) CentralBuff[i] = ma[i];
   }

   //=================================================================
   // 2. CALCULAR ATR WILDER(55)
   //=================================================================
   for(int i = limit; i >= 0; i--)
   {
      double tr1 = high[i] - low[i];
      double tr2 = (i + 1 < rates_total) ? MathAbs(high[i] - close[i + 1]) : 0;
      double tr3 = (i + 1 < rates_total) ? MathAbs(low[i] - close[i + 1]) : 0;
      double tr = MathMax(tr1, MathMax(tr2, tr3));
      int bfe = rates_total - 1 - i;

      if(bfe < InpATRPeriod - 1) ATRBuff[i] = tr;
      else if(bfe == InpATRPeriod - 1)
      {
         double s = 0;
         for(int j = 0; j < InpATRPeriod; j++)
            if(i + j < rates_total) s += ATRBuff[i + j];
         ATRBuff[i] = s / (double)InpATRPeriod;
      }
      else
         ATRBuff[i] = (ATRBuff[i + 1] * (InpATRPeriod - 1) + tr) / (double)InpATRPeriod;
   }

   //=================================================================
   // 3. CALCULAR BANDAS
   //=================================================================
   double k1, k2, k3;
   GetKs(active_preset, k1, k2, k3);

   for(int i = limit; i >= 0; i--)
   {
      double cv = CentralBuff[i], av = ATRBuff[i];
      int bfe = rates_total - 1 - i;
      if(cv == EMPTY_VALUE || av <= 0.0 || bfe < InpATRPeriod - 1)
      {
         B1UBuff[i] = EMPTY_VALUE; B1LBuff[i] = EMPTY_VALUE;
         B2UBuff[i] = EMPTY_VALUE; B2LBuff[i] = EMPTY_VALUE;
         B3UBuff[i] = EMPTY_VALUE; B3LBuff[i] = EMPTY_VALUE;
         continue;
      }
      B1UBuff[i] = cv + k1 * av; B1LBuff[i] = cv - k1 * av;
      B2UBuff[i] = cv + k2 * av; B2LBuff[i] = cv - k2 * av;
      B3UBuff[i] = cv + k3 * av; B3LBuff[i] = cv - k3 * av;
   }

   //=================================================================
   // 4+5. REGIME + SIGNAL — PEDRINHO FIX 06 JUL: loop histórico completo
   // (o bug real: antes só processava a última barra fechada, nunca
   //  percorria o histórico -> nenhuma seta histórica era desenhada)
   //=================================================================
   static int prev_regime_state = REGIME_NEUTRO;
   int regime_state = prev_regime_state;

   double rsi_arr[];
   ArraySetAsSeries(rsi_arr, true);
   int rsi_copied = CopyBuffer(rsi_handle, 0, 0, rates_total, rsi_arr);
   if(rsi_copied < rates_total)
      rsi_copied = CopyBuffer(rsi_handle, 0, 0, rates_total - limit, rsi_arr);

   for(int i = limit; i >= 1; i--)
   {
      if(i + 1 >= rates_total || i >= ArraySize(rsi_arr)) continue;

      RegimeResult regime;
      regime_state = TriviumRegime(close, high, low, CentralBuff, ATRBuff,
                                    rates_total, i, is_crypto,
                                    InpERPeriod, prev_regime_state, regime);
      prev_regime_state = regime_state;

      double rsi_val  = rsi_arr[i];
      double rsi_prev = rsi_arr[i + 1];

      double close_sig = close[i];
      double high_sig = high[i];
      double low_sig = low[i];
      double central_sig = CentralBuff[i];
      double b1u = B1UBuff[i], b1l = B1LBuff[i];
      double b2u = B2UBuff[i], b2l = B2LBuff[i];
      double b3u = B3UBuff[i], b3l = B3LBuff[i];
      double prev_close = close[i + 1];

      BuyArrowBuff[i] = EMPTY_VALUE;
      SellArrowBuff[i] = EMPTY_VALUE;

      NexusVeredito v = signal_engine.Processar(close_sig, high_sig, low_sig, prev_close,
                                                 central_sig, b1u, b1l, b2u, b2l, b3u, b3l,
                                                 rsi_val, rsi_prev, regime, ATRBuff[i]);

      if(v.acao == +1)
         BuyArrowBuff[i] = low_sig - 2.0 * (ATRBuff[i] * 0.1);
      else if(v.acao == -1)
         SellArrowBuff[i] = high_sig + 2.0 * (ATRBuff[i] * 0.1);
   }

   //=================================================================
   // 6. ATUALIZAR VISUAIS
   //=================================================================
   if(time[0] != last_updated_bar)
   {
      UpdateVisuals(active_preset, regime_state);
      last_updated_bar = time[0];
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ma_handle != INVALID_HANDLE) IndicatorRelease(ma_handle);
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
   DeleteObjects();
   Print("NEXUS369_LEVELS v2.02 deinitialized. Reason: ", reason);
}
//+------------------------------------------------------------------+
