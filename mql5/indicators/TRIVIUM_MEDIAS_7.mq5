//+------------------------------------------------------------------+
//| TRIVIUM_MEDIAS_7.mq5                                              |
//| TRIVIUM369 (c) 2026 - Pedrinho, 14/07/2026                        |
//|                                                                    |
//| 7 medias moveis (SMMA) escolhidas por Ronei, encadeadas em 3       |
//| grupos de timeframe pra dar continuidade visual entre eles:        |
//|                                                                    |
//| RAPIDAS/SCALP (M1, M2, M5 - central M2):  7 / 14 / 21              |
//| MEDIAS (H1, M15, M5 - central M15):      21 / 50 / 100             |
//| LONGAS (D1, H4, H1 - central H4):       100 / 150 / 200            |
//|                                                                    |
//| 21 e 100 aparecem 2x de proposito (a mais lenta de um grupo = a    |
//| mais rapida do proximo) - por isso so 7 linhas unicas no total,    |
//| nao 9. Sem TP/entrada/saida - e so ferramenta visual de analise,   |
//| nao abre posicao.                                                  |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

#property indicator_label1  "MA7"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_width1  1

#property indicator_label2  "MA14"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  1

#property indicator_label3  "MA21"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_width3  2

#property indicator_label4  "MA50"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLimeGreen
#property indicator_width4  1

#property indicator_label5  "MA100"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrAqua
#property indicator_width5  2

#property indicator_label6  "MA150"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrDodgerBlue
#property indicator_width6  1

#property indicator_label7  "MA200"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrBlueViolet
#property indicator_width7  2

input group "=== Periodos (fixos - encadeados por proposito) ==="
input int InpPeriodo1 = 7;    // Rapidas - fast
input int InpPeriodo2 = 14;   // Rapidas - mid
input int InpPeriodo3 = 21;   // Rapidas - slow / Medias - fast (bridge)
input int InpPeriodo4 = 50;   // Medias - mid
input int InpPeriodo5 = 100;  // Medias - slow / Longas - fast (bridge)
input int InpPeriodo6 = 150;  // Longas - mid
input int InpPeriodo7 = 200;  // Longas - slow

input group "=== Tipo de media (por linha) ==="
input ENUM_MA_METHOD InpMetodo1 = MODE_EMA;  // MA7   - rapida = exponencial (16/07: pedido do Ronei)
input ENUM_MA_METHOD InpMetodo2 = MODE_EMA;  // MA14  - rapida = exponencial
input ENUM_MA_METHOD InpMetodo3 = MODE_EMA;  // MA21  - rapida/bridge = exponencial
input ENUM_MA_METHOD InpMetodo4 = MODE_SMMA; // MA50  - media = SMMA (como sempre foi)
input ENUM_MA_METHOD InpMetodo5 = MODE_SMMA; // MA100 - media/bridge = SMMA
input ENUM_MA_METHOD InpMetodo6 = MODE_SMMA; // MA150 - longa = SMMA
input ENUM_MA_METHOD InpMetodo7 = MODE_SMMA; // MA200 - longa = SMMA

double Buf1[], Buf2[], Buf3[], Buf4[], Buf5[], Buf6[], Buf7[];
int h1, h2, h3, h4, h5, h6, h7;

int OnInit()
{
   SetIndexBuffer(0, Buf1, INDICATOR_DATA);
   SetIndexBuffer(1, Buf2, INDICATOR_DATA);
   SetIndexBuffer(2, Buf3, INDICATOR_DATA);
   SetIndexBuffer(3, Buf4, INDICATOR_DATA);
   SetIndexBuffer(4, Buf5, INDICATOR_DATA);
   SetIndexBuffer(5, Buf6, INDICATOR_DATA);
   SetIndexBuffer(6, Buf7, INDICATOR_DATA);

   h1 = iMA(_Symbol, _Period, InpPeriodo1, 0, InpMetodo1, PRICE_CLOSE);
   h2 = iMA(_Symbol, _Period, InpPeriodo2, 0, InpMetodo2, PRICE_CLOSE);
   h3 = iMA(_Symbol, _Period, InpPeriodo3, 0, InpMetodo3, PRICE_CLOSE);
   h4 = iMA(_Symbol, _Period, InpPeriodo4, 0, InpMetodo4, PRICE_CLOSE);
   h5 = iMA(_Symbol, _Period, InpPeriodo5, 0, InpMetodo5, PRICE_CLOSE);
   h6 = iMA(_Symbol, _Period, InpPeriodo6, 0, InpMetodo6, PRICE_CLOSE);
   h7 = iMA(_Symbol, _Period, InpPeriodo7, 0, InpMetodo7, PRICE_CLOSE);

   if(h1==INVALID_HANDLE || h2==INVALID_HANDLE || h3==INVALID_HANDLE || h4==INVALID_HANDLE ||
      h5==INVALID_HANDLE || h6==INVALID_HANDLE || h7==INVALID_HANDLE)
   {
      Print("Erro ao criar handles das medias: ", GetLastError());
      return INIT_FAILED;
   }

   // 14/07/2026 v3 - causa real do bug (achado apos v1/v2 nao resolverem):
   // pontos ainda nao calculados ficavam com valor 0.0 por padrao, o que
   // distorcia a escala de preco do grafico inteiro (eixo ia ate 0,
   // "achatando" as linhas la em cima, invisiveis - nao era ausencia de
   // linha, era escala quebrada). Declarando EMPTY_VALUE como "nao
   // desenhar", o MT5 ignora esses pontos na escala.
   for(int i = 0; i < 7; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_MEDIAS_7");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(h1); IndicatorRelease(h2); IndicatorRelease(h3);
   IndicatorRelease(h4); IndicatorRelease(h5); IndicatorRelease(h6); IndicatorRelease(h7);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   // 14/07/2026 v3 - buffers tratados como series (index 0 = barra mais
   // recente), igual o CopyBuffer devolve por padrao - evita qualquer
   // desalinhamento de indice entre origem e destino. Se faltar historico
   // pra alguma media (ex: MA200 com pouco dado), essa media so fica mais
   // curta na tela (pontos nao preenchidos ficam EMPTY_VALUE, nao 0.0).
   ArraySetAsSeries(Buf1, true); ArraySetAsSeries(Buf2, true); ArraySetAsSeries(Buf3, true);
   ArraySetAsSeries(Buf4, true); ArraySetAsSeries(Buf5, true); ArraySetAsSeries(Buf6, true);
   ArraySetAsSeries(Buf7, true);

   if(prev_calculated == 0)
   {
      ArrayInitialize(Buf1, EMPTY_VALUE); ArrayInitialize(Buf2, EMPTY_VALUE);
      ArrayInitialize(Buf3, EMPTY_VALUE); ArrayInitialize(Buf4, EMPTY_VALUE);
      ArrayInitialize(Buf5, EMPTY_VALUE); ArrayInitialize(Buf6, EMPTY_VALUE);
      ArrayInitialize(Buf7, EMPTY_VALUE);
   }

   CopyBuffer(h1, 0, 0, MathMax(0, MathMin(rates_total, BarsCalculated(h1))), Buf1);
   CopyBuffer(h2, 0, 0, MathMax(0, MathMin(rates_total, BarsCalculated(h2))), Buf2);
   CopyBuffer(h3, 0, 0, MathMax(0, MathMin(rates_total, BarsCalculated(h3))), Buf3);
   CopyBuffer(h4, 0, 0, MathMax(0, MathMin(rates_total, BarsCalculated(h4))), Buf4);
   CopyBuffer(h5, 0, 0, MathMax(0, MathMin(rates_total, BarsCalculated(h5))), Buf5);
   CopyBuffer(h6, 0, 0, MathMax(0, MathMin(rates_total, BarsCalculated(h6))), Buf6);
   CopyBuffer(h7, 0, 0, MathMax(0, MathMin(rates_total, BarsCalculated(h7))), Buf7);

   return rates_total;
}
//+------------------------------------------------------------------+
