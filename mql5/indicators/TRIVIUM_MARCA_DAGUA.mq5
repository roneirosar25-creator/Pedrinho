//+------------------------------------------------------------------+
//| TRIVIUM_MARCA_DAGUA.mq5                                           |
//| TRIVIUM369 (c) 2026 - Pedrinho, 14/07/2026                        |
//|                                                                    |
//| "Marca d'agua" = media das medias, uma por grupo (pedido do Ronei):|
//|  Rapidas       = media(MA7, MA14, MA21)                            |
//|  Intermediarias= media(MA21, MA50, MA100)                          |
//|  Longas        = media(MA100, MA150, MA200)                        |
//|                                                                    |
//| Cores seguem a familia de cada grupo ja estabelecida:               |
//|  Rapidas=Amarelo | Intermediarias=Dourado | Longas=Prata           |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 9
#property indicator_plots   9

// 14/07/2026 v2 - 3 linhas por grupo (pedido do Ronei): maxima
// (pontilhada), media-das-medias (continua), minima (tracejada).

#property indicator_label1  "Rapidas MAX (maior das 7/14/21)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_width1  1
#property indicator_style1  STYLE_DOT

#property indicator_label2  "Rapidas MEDIA (media de 7/14/21)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrYellow
#property indicator_width2  2
#property indicator_style2  STYLE_SOLID

#property indicator_label3  "Rapidas MIN (menor das 7/14/21)"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrYellow
#property indicator_width3  1
#property indicator_style3  STYLE_DASH

#property indicator_label4  "Intermediarias MAX (maior das 21/50/100)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold
#property indicator_width4  1
#property indicator_style4  STYLE_DOT

#property indicator_label5  "Intermediarias MEDIA (media de 21/50/100)"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGold
#property indicator_width5  2
#property indicator_style5  STYLE_SOLID

#property indicator_label6  "Intermediarias MIN (menor das 21/50/100)"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrGold
#property indicator_width6  1
#property indicator_style6  STYLE_DASH

#property indicator_label7  "Longas MAX (maior das 100/150/200)"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrSilver
#property indicator_width7  1
#property indicator_style7  STYLE_DOT

#property indicator_label8  "Longas MEDIA (media de 100/150/200)"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrSilver
#property indicator_width8  2
#property indicator_style8  STYLE_SOLID

#property indicator_label9  "Longas MIN (menor das 100/150/200)"
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrSilver
#property indicator_width9  1
#property indicator_style9  STYLE_DASH

input ENUM_MA_METHOD InpMetodo = MODE_SMMA;

double BufRapMax[], BufRapMed[], BufRapMin[];
double BufInterMax[], BufInterMed[], BufInterMin[];
double BufLongMax[], BufLongMed[], BufLongMin[];
int h7, h14, h21, h50, h100, h150, h200;

int OnInit()
{
   SetIndexBuffer(0, BufRapMax,   INDICATOR_DATA);
   SetIndexBuffer(1, BufRapMed,   INDICATOR_DATA);
   SetIndexBuffer(2, BufRapMin,   INDICATOR_DATA);
   SetIndexBuffer(3, BufInterMax, INDICATOR_DATA);
   SetIndexBuffer(4, BufInterMed, INDICATOR_DATA);
   SetIndexBuffer(5, BufInterMin, INDICATOR_DATA);
   SetIndexBuffer(6, BufLongMax,  INDICATOR_DATA);
   SetIndexBuffer(7, BufLongMed,  INDICATOR_DATA);
   SetIndexBuffer(8, BufLongMin,  INDICATOR_DATA);

   h7   = iMA(_Symbol, _Period, 7,   0, InpMetodo, PRICE_CLOSE);
   h14  = iMA(_Symbol, _Period, 14,  0, InpMetodo, PRICE_CLOSE);
   h21  = iMA(_Symbol, _Period, 21,  0, InpMetodo, PRICE_CLOSE);
   h50  = iMA(_Symbol, _Period, 50,  0, InpMetodo, PRICE_CLOSE);
   h100 = iMA(_Symbol, _Period, 100, 0, InpMetodo, PRICE_CLOSE);
   h150 = iMA(_Symbol, _Period, 150, 0, InpMetodo, PRICE_CLOSE);
   h200 = iMA(_Symbol, _Period, 200, 0, InpMetodo, PRICE_CLOSE);

   if(h7==INVALID_HANDLE || h14==INVALID_HANDLE || h21==INVALID_HANDLE || h50==INVALID_HANDLE ||
      h100==INVALID_HANDLE || h150==INVALID_HANDLE || h200==INVALID_HANDLE)
   {
      Print("Erro ao criar handles das medias: ", GetLastError());
      return INIT_FAILED;
   }

   for(int i = 0; i < 9; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_MARCA_DAGUA");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(h7); IndicatorRelease(h14); IndicatorRelease(h21);
   IndicatorRelease(h50); IndicatorRelease(h100); IndicatorRelease(h150); IndicatorRelease(h200);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   ArraySetAsSeries(BufRapMax, true);   ArraySetAsSeries(BufRapMed, true);   ArraySetAsSeries(BufRapMin, true);
   ArraySetAsSeries(BufInterMax, true); ArraySetAsSeries(BufInterMed, true); ArraySetAsSeries(BufInterMin, true);
   ArraySetAsSeries(BufLongMax, true);  ArraySetAsSeries(BufLongMed, true);  ArraySetAsSeries(BufLongMin, true);

   if(prev_calculated == 0)
   {
      ArrayInitialize(BufRapMax, EMPTY_VALUE);   ArrayInitialize(BufRapMed, EMPTY_VALUE);   ArrayInitialize(BufRapMin, EMPTY_VALUE);
      ArrayInitialize(BufInterMax, EMPTY_VALUE); ArrayInitialize(BufInterMed, EMPTY_VALUE); ArrayInitialize(BufInterMin, EMPTY_VALUE);
      ArrayInitialize(BufLongMax, EMPTY_VALUE);  ArrayInitialize(BufLongMed, EMPTY_VALUE);  ArrayInitialize(BufLongMin, EMPTY_VALUE);
   }

   double v7[], v14[], v21[], v50[], v100[], v150[], v200[];
   ArraySetAsSeries(v7, true); ArraySetAsSeries(v14, true); ArraySetAsSeries(v21, true);
   ArraySetAsSeries(v50, true); ArraySetAsSeries(v100, true); ArraySetAsSeries(v150, true); ArraySetAsSeries(v200, true);

   int disp = MathMin(rates_total, MathMin(BarsCalculated(h7), MathMin(BarsCalculated(h14), MathMin(BarsCalculated(h21),
              MathMin(BarsCalculated(h50), MathMin(BarsCalculated(h100), MathMin(BarsCalculated(h150), BarsCalculated(h200))))))));
   if(disp <= 0) return 0;

   CopyBuffer(h7,   0, 0, disp, v7);
   CopyBuffer(h14,  0, 0, disp, v14);
   CopyBuffer(h21,  0, 0, disp, v21);
   CopyBuffer(h50,  0, 0, disp, v50);
   CopyBuffer(h100, 0, 0, disp, v100);
   CopyBuffer(h150, 0, 0, disp, v150);
   CopyBuffer(h200, 0, 0, disp, v200);

   for(int i = 0; i < disp; i++)
   {
      BufRapMax[i] = MathMax(v7[i], MathMax(v14[i], v21[i]));
      BufRapMed[i] = (v7[i] + v14[i] + v21[i]) / 3.0;
      BufRapMin[i] = MathMin(v7[i], MathMin(v14[i], v21[i]));

      BufInterMax[i] = MathMax(v21[i], MathMax(v50[i], v100[i]));
      BufInterMed[i] = (v21[i] + v50[i] + v100[i]) / 3.0;
      BufInterMin[i] = MathMin(v21[i], MathMin(v50[i], v100[i]));

      BufLongMax[i] = MathMax(v100[i], MathMax(v150[i], v200[i]));
      BufLongMed[i] = (v100[i] + v150[i] + v200[i]) / 3.0;
      BufLongMin[i] = MathMin(v100[i], MathMin(v150[i], v200[i]));
   }

   return rates_total;
}
//+------------------------------------------------------------------+
