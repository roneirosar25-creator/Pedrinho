//+------------------------------------------------------------------+
//|                                              TRIVIUM_SETUP.mq5    |
//|                                          TRIVIUM369 / Cláudio     |
//|                                                                   |
//|  COCKPIT VISUAL (indicador overlay) — junta numa tela só:         |
//|   - 4 Médias Móveis (EMA 9/21/50/200, configuráveis)              |
//|   - Banda de Bollinger  (zoneamento por volatilidade)             |
//|   - Envelope            (canal % fixo)                            |
//|   - Marca d'água        (ativo + timeframe ao fundo)              |
//|   - Zonas de Suporte/Resistência automáticas (por fractais)       |
//|   - Linhas de Tendência de alta e de baixa (automáticas)          |
//|                                                                   |
//|  Os 4 osciladores (RSI, MACD, Estocástico, ADX) entram em janelas |
//|  separadas — ver README e salvar como template TRIVIUM369.tmpl.   |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   9

//--- 1..4: Médias Móveis
#property indicator_label1  "EMA rapida"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_label2  "EMA curta"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  2
#property indicator_label3  "EMA media"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrMediumOrchid
#property indicator_width3  2
#property indicator_label4  "EMA tendencia"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrRed
#property indicator_width4  2
//--- 5..7: Bollinger
#property indicator_label5  "BB superior"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrSilver
#property indicator_style5  STYLE_DOT
#property indicator_label6  "BB media"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrSilver
#property indicator_style6  STYLE_DASH
#property indicator_label7  "BB inferior"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrSilver
#property indicator_style7  STYLE_DOT
//--- 8..9: Envelope
#property indicator_label8  "Envelope superior"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrAqua
#property indicator_style8  STYLE_DOT
#property indicator_label9  "Envelope inferior"
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrAqua
#property indicator_style9  STYLE_DOT

//=== INPUTS =========================================================
input group "=== MEDIAS MOVEIS ==="
input bool             UsarMAs     = true;
input int              MA1_Periodo = 9;       // EMA rapida
input int              MA2_Periodo = 21;      // EMA curta
input int              MA3_Periodo = 50;      // EMA media
input int              MA4_Periodo = 200;     // EMA tendencia
input ENUM_MA_METHOD   MA_Metodo   = MODE_EMA;
input ENUM_APPLIED_PRICE MA_Preco  = PRICE_CLOSE;

input group "=== ZONEAMENTO: BOLLINGER ==="
input bool   UsarBollinger = true;
input int    BB_Periodo    = 20;
input double BB_Desvio     = 2.0;

input group "=== ZONEAMENTO: ENVELOPE ==="
input bool             UsarEnvelope = true;
input int              Env_Periodo  = 20;
input ENUM_MA_METHOD   Env_Metodo   = MODE_EMA;
input double           Env_Desvio   = 0.5;    // desvio em %

input group "=== MARCA D'AGUA ==="
input bool   UsarMarca    = true;
input color  Marca_Cor    = clrGray;
input int    Marca_Tamanho= 54;

input group "=== ZONAS SUPORTE / RESISTENCIA ==="
input bool   UsarSR        = true;
input int    SR_Fractal    = 2;      // lado do fractal (2 = janela de 5 barras)
input int    SR_MaxZonas   = 5;      // qtd de zonas recentes por lado
input color  SR_CorResist  = clrCrimson;
input color  SR_CorSuporte = clrTeal;

input group "=== LINHAS DE TENDENCIA ==="
input bool   UsarTendencia = true;
input int    Tend_Lookback = 300;    // barras p/ buscar os swings
input color  Tend_CorAlta  = clrLimeGreen;
input color  Tend_CorBaixa = clrOrangeRed;

//=== BUFFERS ========================================================
double MA1Buf[], MA2Buf[], MA3Buf[], MA4Buf[];
double BBUp[], BBMid[], BBLo[];
double EnvUp[], EnvLo[];

//=== HANDLES ========================================================
int hMA1=INVALID_HANDLE, hMA2=INVALID_HANDLE, hMA3=INVALID_HANDLE, hMA4=INVALID_HANDLE;
int hBB=INVALID_HANDLE, hEnv=INVALID_HANDLE, hATR=INVALID_HANDLE;

string PREFIXO = "TRSU_";

//+------------------------------------------------------------------+
string TFParaTexto(ENUM_TIMEFRAMES tf)
{
   string s = EnumToString(tf);      // ex: "PERIOD_H1"
   int p = StringFind(s, "_");
   return (p >= 0) ? StringSubstr(s, p + 1) : s;
}

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, MA1Buf, INDICATOR_DATA);
   SetIndexBuffer(1, MA2Buf, INDICATOR_DATA);
   SetIndexBuffer(2, MA3Buf, INDICATOR_DATA);
   SetIndexBuffer(3, MA4Buf, INDICATOR_DATA);
   SetIndexBuffer(4, BBUp,   INDICATOR_DATA);
   SetIndexBuffer(5, BBMid,  INDICATOR_DATA);
   SetIndexBuffer(6, BBLo,   INDICATOR_DATA);
   SetIndexBuffer(7, EnvUp,  INDICATOR_DATA);
   SetIndexBuffer(8, EnvLo,  INDICATOR_DATA);

   // buffers como série (index 0 = barra atual) p/ CopyBuffer alinhar certo
   ArraySetAsSeries(MA1Buf, true); ArraySetAsSeries(MA2Buf, true);
   ArraySetAsSeries(MA3Buf, true); ArraySetAsSeries(MA4Buf, true);
   ArraySetAsSeries(BBUp,  true);  ArraySetAsSeries(BBMid, true);
   ArraySetAsSeries(BBLo,  true);  ArraySetAsSeries(EnvUp, true);
   ArraySetAsSeries(EnvLo, true);

   for(int i = 0; i < 9; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ArrayInitialize(MA1Buf, EMPTY_VALUE); ArrayInitialize(MA2Buf, EMPTY_VALUE);
   ArrayInitialize(MA3Buf, EMPTY_VALUE); ArrayInitialize(MA4Buf, EMPTY_VALUE);
   ArrayInitialize(BBUp,  EMPTY_VALUE);  ArrayInitialize(BBMid, EMPTY_VALUE);
   ArrayInitialize(BBLo,  EMPTY_VALUE);  ArrayInitialize(EnvUp, EMPTY_VALUE);
   ArrayInitialize(EnvLo, EMPTY_VALUE);

   hMA1 = iMA(_Symbol, _Period, MA1_Periodo, 0, MA_Metodo, MA_Preco);
   hMA2 = iMA(_Symbol, _Period, MA2_Periodo, 0, MA_Metodo, MA_Preco);
   hMA3 = iMA(_Symbol, _Period, MA3_Periodo, 0, MA_Metodo, MA_Preco);
   hMA4 = iMA(_Symbol, _Period, MA4_Periodo, 0, MA_Metodo, MA_Preco);
   hBB  = iBands(_Symbol, _Period, BB_Periodo, 0, BB_Desvio, PRICE_CLOSE);
   hEnv = iEnvelopes(_Symbol, _Period, Env_Periodo, 0, Env_Metodo, PRICE_CLOSE, Env_Desvio);
   hATR = iATR(_Symbol, _Period, 14);

   if(hMA1==INVALID_HANDLE || hMA2==INVALID_HANDLE || hMA3==INVALID_HANDLE ||
      hMA4==INVALID_HANDLE || hBB==INVALID_HANDLE  || hEnv==INVALID_HANDLE)
   {
      Print("TRIVIUM_SETUP: falha ao criar handles dos indicadores.");
      return INIT_FAILED;
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_SETUP");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, PREFIXO);
   IndicatorRelease(hMA1); IndicatorRelease(hMA2);
   IndicatorRelease(hMA3); IndicatorRelease(hMA4);
   IndicatorRelease(hBB);  IndicatorRelease(hEnv);
   IndicatorRelease(hATR);
   ChartRedraw();
}

//+------------------------------------------------------------------+
bool CopiaBuf(int handle, int hbuf, double &dest[], int cnt)
{
   if(handle == INVALID_HANDLE) return false;
   return (CopyBuffer(handle, hbuf, 0, cnt, dest) > 0);
}

//+------------------------------------------------------------------+
//| Desenha a marca d'agua centralizada (atras dos candles)          |
//+------------------------------------------------------------------+
void DesenhaMarca()
{
   string n = PREFIXO + "MARCA";
   long w = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   long h = ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, (int)(w / 2));
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, (int)(h / 2));
   ObjectSetString (0, n, OBJPROP_TEXT, _Symbol + "  " + TFParaTexto((ENUM_TIMEFRAMES)_Period));
   ObjectSetString (0, n, OBJPROP_FONT, "Arial Black");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, Marca_Tamanho);
   ObjectSetInteger(0, n, OBJPROP_COLOR, Marca_Cor);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void CriaTrend(string nome, datetime t1, double p1, datetime t2, double p2, color cor)
{
   string n = PREFIXO + nome;
   ObjectCreate(0, n, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, n, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
void CriaRect(string nome, datetime t1, double p1, datetime t2, double p2, color cor)
{
   string n = PREFIXO + nome;
   ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   ObjectSetInteger(0, n, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, n, OBJPROP_FILL, true);
   ObjectSetInteger(0, n, OBJPROP_BACK, true);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Recalcula e redesenha marca, zonas S/R e linhas de tendencia     |
//+------------------------------------------------------------------+
void AtualizaObjetos()
{
   ObjectsDeleteAll(0, PREFIXO);

   if(UsarMarca) DesenhaMarca();

   if(!UsarSR && !UsarTendencia) { ChartRedraw(); return; }

   int barras = Bars(_Symbol, _Period);
   int look = Tend_Lookback;
   if(look > barras - 10) look = barras - 10;
   if(look < 50) { ChartRedraw(); return; }

   double hi[], lo[]; datetime tm[];
   ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true); ArraySetAsSeries(tm, true);
   if(CopyHigh(_Symbol, _Period, 0, look, hi) <= 0) return;
   if(CopyLow (_Symbol, _Period, 0, look, lo) <= 0) return;
   if(CopyTime(_Symbol, _Period, 0, look, tm) <= 0) return;

   int f = (SR_Fractal < 1) ? 1 : SR_Fractal;

   int shIdx[]; int slIdx[];
   ArrayResize(shIdx, 0); ArrayResize(slIdx, 0);
   for(int i = f; i < look - f; i++)
   {
      bool topo = true, fundo = true;
      for(int k = 1; k <= f; k++)
      {
         if(hi[i] < hi[i - k] || hi[i] < hi[i + k]) topo  = false;
         if(lo[i] > lo[i - k] || lo[i] > lo[i + k]) fundo = false;
      }
      if(topo)  { int s = ArraySize(shIdx); ArrayResize(shIdx, s + 1); shIdx[s] = i; }
      if(fundo) { int s = ArraySize(slIdx); ArrayResize(slIdx, s + 1); slIdx[s] = i; }
   }

   // meia-altura das zonas a partir do ATR (volatilidade)
   double half = 10 * _Point;
   if(hATR != INVALID_HANDLE)
   {
      double a[];
      if(CopyBuffer(hATR, 0, 0, 1, a) > 0 && a[0] > 0) half = a[0] * 0.25;
   }

   datetime tRight = tm[0];

   if(UsarSR)
   {
      int nz = MathMin(SR_MaxZonas, ArraySize(shIdx));
      for(int z = 0; z < nz; z++)
      {
         double lvl = hi[shIdx[z]];
         CriaRect("R_" + (string)z, tm[shIdx[z]], lvl + half, tRight, lvl - half, SR_CorResist);
      }
      nz = MathMin(SR_MaxZonas, ArraySize(slIdx));
      for(int z = 0; z < nz; z++)
      {
         double lvl = lo[slIdx[z]];
         CriaRect("S_" + (string)z, tm[slIdx[z]], lvl + half, tRight, lvl - half, SR_CorSuporte);
      }
   }

   if(UsarTendencia)
   {
      if(ArraySize(shIdx) >= 2)
      {
         int a = shIdx[0], b = shIdx[1];   // a = mais recente, b = anterior
         CriaTrend("LTB", tm[b], hi[b], tm[a], hi[a], Tend_CorBaixa);
      }
      if(ArraySize(slIdx) >= 2)
      {
         int a = slIdx[0], b = slIdx[1];
         CriaTrend("LTA", tm[b], lo[b], tm[a], lo[a], Tend_CorAlta);
      }
   }
   ChartRedraw();
}

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
   if(rates_total < MA4_Periodo + 10) return 0;

   int to_copy = (prev_calculated == 0) ? rates_total : (rates_total - prev_calculated + 1);

   if(UsarMAs)
   {
      if(!CopiaBuf(hMA1, 0, MA1Buf, to_copy)) return prev_calculated;
      if(!CopiaBuf(hMA2, 0, MA2Buf, to_copy)) return prev_calculated;
      if(!CopiaBuf(hMA3, 0, MA3Buf, to_copy)) return prev_calculated;
      if(!CopiaBuf(hMA4, 0, MA4Buf, to_copy)) return prev_calculated;
   }
   else if(prev_calculated == 0)
   {
      ArrayInitialize(MA1Buf, EMPTY_VALUE); ArrayInitialize(MA2Buf, EMPTY_VALUE);
      ArrayInitialize(MA3Buf, EMPTY_VALUE); ArrayInitialize(MA4Buf, EMPTY_VALUE);
   }

   if(UsarBollinger)
   {
      if(!CopiaBuf(hBB, 1, BBUp,  to_copy)) return prev_calculated;  // 1 = upper
      CopiaBuf(hBB, 0, BBMid, to_copy);                              // 0 = middle
      CopiaBuf(hBB, 2, BBLo,  to_copy);                              // 2 = lower
   }
   else if(prev_calculated == 0)
   {
      ArrayInitialize(BBUp, EMPTY_VALUE); ArrayInitialize(BBMid, EMPTY_VALUE);
      ArrayInitialize(BBLo, EMPTY_VALUE);
   }

   if(UsarEnvelope)
   {
      if(!CopiaBuf(hEnv, 0, EnvUp, to_copy)) return prev_calculated; // 0 = upper
      CopiaBuf(hEnv, 1, EnvLo, to_copy);                            // 1 = lower
   }
   else if(prev_calculated == 0)
   {
      ArrayInitialize(EnvUp, EMPTY_VALUE); ArrayInitialize(EnvLo, EMPTY_VALUE);
   }

   // objetos (marca, S/R, tendencia) so a cada nova barra
   static datetime ultBarra = 0;
   datetime atual = time[rates_total - 1];
   if(atual != ultBarra)
   {
      ultBarra = atual;
      AtualizaObjetos();
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Recentraliza a marca d'agua quando o grafico muda de tamanho     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE && UsarMarca)
   {
      DesenhaMarca();
      ChartRedraw();
   }
}
//+------------------------------------------------------------------+
