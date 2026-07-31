//+------------------------------------------------------------------+
//|                                      MultiMA_Cross_Scanner.mq5   |
//|        Multi-TF MA Crossover Scanner + Indicators Panel          |
//|                                    by AAIF (Agentic AI Foundation)|
//+------------------------------------------------------------------+
#property copyright "AAIF - Agentic AI Foundation"
#property link      "https://aai.foundation"
#property version   "1.00"
#property description "Scanner Multi-TF: Cruzamento MAs 9/20/50/100/200"
#property description "M1 M2 M5 M15 H1 H4 D1 | Seta ✗ nos cruzamentos"
#property description "Painel: RSI | Stoch | MACD | ATR"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "MA9"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "MA20"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

#property indicator_label3  "MA50"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrMagenta
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

#property indicator_label4  "MA100"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrYellow
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

#property indicator_label5  "MA200"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrRed
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

//+------------------------------------------------------------------+
//| Inputs - Medias Moveis                                           |
//+------------------------------------------------------------------+
input int    InpMA1    = 9;             // Periodo MA Rapida (9)
input int    InpMA2    = 20;            // Periodo MA Media 1 (20)
input int    InpMA3    = 50;            // Periodo MA Media 2 (50)
input int    InpMA4    = 100;           // Periodo MA Longa 1 (100)
input int    InpMA5    = 200;           // Periodo MA Longa 2 (200)
input ENUM_MA_METHOD          InpMAMethod  = MODE_SMA;  // Metodo MA
input ENUM_APPLIED_PRICE      InpMAPrice   = PRICE_CLOSE; // Preco MA

//+------------------------------------------------------------------+
//| Inputs - Multi-Timeframe Scanning                                |
//+------------------------------------------------------------------+
input bool   InpScanM1   = true;        // Escanear M1
input bool   InpScanM2   = true;        // Escanear M2
input bool   InpScanM5   = true;        // Escanear M5
input bool   InpScanM15  = true;        // Escanear M15
input bool   InpScanH1   = true;        // Escanear H1
input bool   InpScanH4   = true;        // Escanear H4
input bool   InpScanD1   = true;        // Escanear D1
input int    InpLookBars = 5;           // Barras p/ revisar
input color  InpCrossUp  = clrLime;     // Cor cruzamento ALTA
input color  InpCrossDn  = clrRed;      // Cor cruzamento BAIXA

//+------------------------------------------------------------------+
//| Inputs - RSI                                                     |
//+------------------------------------------------------------------+
input bool   InpShowRSI   = true;       // Mostrar RSI
input int    InpRSIPeriod = 14;         // Periodo RSI
input double InpRSIOverb  = 70.0;       // Sobrecompra RSI
input double InpRSIOverd  = 30.0;       // Sobrevenda RSI

//+------------------------------------------------------------------+
//| Inputs - Stochastic                                              |
//+------------------------------------------------------------------+
input bool   InpShowStoch  = true;      // Mostrar Stochastic
input int    InpStochK     = 5;         // Stoch %K
input int    InpStochD     = 3;         // Stoch %D
input int    InpStochSlow  = 3;         // Stoch Slowing
input double InpStochOverb = 80.0;      // Sobrecompra Stoch
input double InpStochOverd = 20.0;      // Sobrevenda Stoch

//+------------------------------------------------------------------+
//| Inputs - MACD                                                    |
//+------------------------------------------------------------------+
input bool   InpShowMACD  = true;       // Mostrar MACD
input int    InpMACDFast  = 12;         // MACD fast
input int    InpMACDSlow  = 26;         // MACD slow
input int    InpMACDSig   = 9;          // MACD signal

//+------------------------------------------------------------------+
//| Inputs - ATR                                                     |
//+------------------------------------------------------------------+
input bool   InpShowATR   = true;       // Mostrar ATR
input int    InpATRPeriod = 14;         // Periodo ATR

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double g_ma1[];
double g_ma2[];
double g_ma3[];
double g_ma4[];
double g_ma5[];

//+------------------------------------------------------------------+
//| Handles                                                          |
//+------------------------------------------------------------------+
int hMA1 = INVALID_HANDLE;
int hMA2 = INVALID_HANDLE;
int hMA3 = INVALID_HANDLE;
int hMA4 = INVALID_HANDLE;
int hMA5 = INVALID_HANDLE;
int hRSI = INVALID_HANDLE;
int hStoch = INVALID_HANDLE;
int hMACD = INVALID_HANDLE;
int hATR = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Timeframe list                                                   |
//+------------------------------------------------------------------+
struct TFInfo { ENUM_TIMEFRAMES tf; string label; bool active; };
TFInfo g_tfs[7];
int    g_tfCount = 0;

string PREFIX = "MCS_";

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   SetIndexBuffer(0, g_ma1, INDICATOR_DATA);
   SetIndexBuffer(1, g_ma2, INDICATOR_DATA);
   SetIndexBuffer(2, g_ma3, INDICATOR_DATA);
   SetIndexBuffer(3, g_ma4, INDICATOR_DATA);
   SetIndexBuffer(4, g_ma5, INDICATOR_DATA);

   hMA1 = iMA(_Symbol, PERIOD_CURRENT, InpMA1, 0, InpMAMethod, InpMAPrice);
   hMA2 = iMA(_Symbol, PERIOD_CURRENT, InpMA2, 0, InpMAMethod, InpMAPrice);
   hMA3 = iMA(_Symbol, PERIOD_CURRENT, InpMA3, 0, InpMAMethod, InpMAPrice);
   hMA4 = iMA(_Symbol, PERIOD_CURRENT, InpMA4, 0, InpMAMethod, InpMAPrice);
   hMA5 = iMA(_Symbol, PERIOD_CURRENT, InpMA5, 0, InpMAMethod, InpMAPrice);

   bool ok = (hMA1!=INVALID_HANDLE && hMA2!=INVALID_HANDLE && hMA3!=INVALID_HANDLE &&
              hMA4!=INVALID_HANDLE && hMA5!=INVALID_HANDLE);
   if(!ok) { Print("ERRO: handles MA"); return INIT_FAILED; }

   if(InpShowRSI)   hRSI   = iRSI(_Symbol, PERIOD_CURRENT, InpRSIPeriod, PRICE_CLOSE);
   if(InpShowStoch) hStoch = iStochastic(_Symbol, PERIOD_CURRENT, InpStochK, InpStochD, InpStochSlow, MODE_SMA, STO_LOWHIGH);
   if(InpShowMACD)  hMACD  = iMACD(_Symbol, PERIOD_CURRENT, InpMACDFast, InpMACDSlow, InpMACDSig, PRICE_CLOSE);
   if(InpShowATR)   hATR   = iATR(_Symbol, PERIOD_CURRENT, InpATRPeriod);

   // TF list
   g_tfCount = 0;
   if(InpScanM1)  { g_tfs[g_tfCount].tf=PERIOD_M1;  g_tfs[g_tfCount].label="M1";  g_tfs[g_tfCount].active=true; g_tfCount++; }
   if(InpScanM2)  { g_tfs[g_tfCount].tf=PERIOD_M2;  g_tfs[g_tfCount].label="M2";  g_tfs[g_tfCount].active=true; g_tfCount++; }
   if(InpScanM5)  { g_tfs[g_tfCount].tf=PERIOD_M5;  g_tfs[g_tfCount].label="M5";  g_tfs[g_tfCount].active=true; g_tfCount++; }
   if(InpScanM15) { g_tfs[g_tfCount].tf=PERIOD_M15; g_tfs[g_tfCount].label="M15"; g_tfs[g_tfCount].active=true; g_tfCount++; }
   if(InpScanH1)  { g_tfs[g_tfCount].tf=PERIOD_H1;  g_tfs[g_tfCount].label="H1";  g_tfs[g_tfCount].active=true; g_tfCount++; }
   if(InpScanH4)  { g_tfs[g_tfCount].tf=PERIOD_H4;  g_tfs[g_tfCount].label="H4";  g_tfs[g_tfCount].active=true; g_tfCount++; }
   if(InpScanD1)  { g_tfs[g_tfCount].tf=PERIOD_D1;  g_tfs[g_tfCount].label="D1";  g_tfs[g_tfCount].active=true; g_tfCount++; }

   Print("MultiMA Cross Scanner iniciado em "+_Symbol);
   Print("MAs: "+IntegerToString(InpMA1)+"/"+IntegerToString(InpMA2)+"/"+
         IntegerToString(InpMA3)+"/"+IntegerToString(InpMA4)+"/"+IntegerToString(InpMA5));
   Print("Escaneando "+IntegerToString(g_tfCount)+" timeframes");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int) {
   if(hMA1!=INVALID_HANDLE) IndicatorRelease(hMA1);
   if(hMA2!=INVALID_HANDLE) IndicatorRelease(hMA2);
   if(hMA3!=INVALID_HANDLE) IndicatorRelease(hMA3);
   if(hMA4!=INVALID_HANDLE) IndicatorRelease(hMA4);
   if(hMA5!=INVALID_HANDLE) IndicatorRelease(hMA5);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hStoch!=INVALID_HANDLE) IndicatorRelease(hStoch);
   if(hMACD!=INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
//| Calculation                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[], const double &high[],
                const double &low[], const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[]) {

   if(rates_total < InpMA5+5) return 0;

   if(CopyBuffer(hMA1,0,0,rates_total,g_ma1) < rates_total) return 0;
   if(CopyBuffer(hMA2,0,0,rates_total,g_ma2) < rates_total) return 0;
   if(CopyBuffer(hMA3,0,0,rates_total,g_ma3) < rates_total) return 0;
   if(CopyBuffer(hMA4,0,0,rates_total,g_ma4) < rates_total) return 0;
   if(CopyBuffer(hMA5,0,0,rates_total,g_ma5) < rates_total) return 0;

   //--- Draw arrows on new bars
   static datetime lastBarTime = 0;
   if(time[rates_total-1] != lastBarTime) {
      lastBarTime = time[rates_total-1];
      DrawAllArrows(time, high, low, rates_total);
      DrawPanel(rates_total);
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Draw all crossover arrows                                        |
//+------------------------------------------------------------------+
void DrawAllArrows(const datetime &time[], const double &high[],
                   const double &low[], int total) {
   // Clean old arrows
   int objTotal = ObjectsTotal(0);
   string toDel[];
   int delCount = 0;
   for(int i=0; i<objTotal; i++) {
      string name = ObjectName(0, i);
      if(StringFind(name, PREFIX) == 0) {
         ArrayResize(toDel, delCount+1);
         toDel[delCount++] = name;
      }
   }
   for(int i=0; i<delCount; i++)
      ObjectDelete(0, toDel[i]);

   // Current TF crossovers
   int checkTo = MathMin(total-2, InpLookBars+2);
   if(checkTo < 2) return;

   CheckCross(time, high, low, g_ma1, g_ma2, checkTo, "9/20");
   CheckCross(time, high, low, g_ma2, g_ma3, checkTo, "20/50");
   CheckCross(time, high, low, g_ma3, g_ma4, checkTo, "50/100");
   CheckCross(time, high, low, g_ma4, g_ma5, checkTo, "100/200");

   // Multi-timeframe scanning
   for(int t=0; t<g_tfCount; t++) {
      ScanTF(g_tfs[t].tf, g_tfs[t].label);
   }
}

//+------------------------------------------------------------------+
//| Check crossover on a pair of MA buffers                          |
//+------------------------------------------------------------------+
void CheckCross(const datetime &time[], const double &high[], const double &low[],
                double &fast[], double &slow[], int total, string label) {
   for(int i=1; i<total; i++) {
      if(i+1 >= ArraySize(fast) || i+1 >= ArraySize(slow)) break;
      double f0=fast[i], s0=slow[i], f1=fast[i+1], s1=slow[i+1];
      if(f0==0||s0==0||f1==0||s1==0) continue;

      if(f1<=s1 && f0>s0) {
         double p = MathMin(low[i], MathMin(f0,s0));
         if(p<=0) p=low[i];
         DrawX(time[i], p, true, label);
      }
      else if(f1>=s1 && f0<s0) {
         double p = MathMax(high[i], MathMax(f0,s0));
         DrawX(time[i], p, false, label);
      }
   }
}

//+------------------------------------------------------------------+
//| Scan a specific timeframe for crossovers                         |
//+------------------------------------------------------------------+
void ScanTF(ENUM_TIMEFRAMES tf, string tfLabel) {
   if(tf == PERIOD_CURRENT) return;

   int h1 = iMA(_Symbol, tf, InpMA1, 0, InpMAMethod, InpMAPrice);
   int h2 = iMA(_Symbol, tf, InpMA2, 0, InpMAMethod, InpMAPrice);
   int h3 = iMA(_Symbol, tf, InpMA3, 0, InpMAMethod, InpMAPrice);
   int h4 = iMA(_Symbol, tf, InpMA4, 0, InpMAMethod, InpMAPrice);
   int h5 = iMA(_Symbol, tf, InpMA5, 0, InpMAMethod, InpMAPrice);

   if(h1==INVALID_HANDLE || h2==INVALID_HANDLE) {
      ReleaseHandles(h1,h2,h3,h4,h5);
      return;
   }

   double a1[],a2[],a3[],a4[],a5[];
   datetime tfmt[];
   int need = InpMA5 + InpLookBars + 5;
   CopyBuffer(h1,0,0,need,a1); CopyBuffer(h2,0,0,need,a2);
   CopyBuffer(h3,0,0,need,a3); CopyBuffer(h4,0,0,need,a4);
   CopyBuffer(h5,0,0,need,a5);
   CopyTime(_Symbol, tf, 0, need, tfmt);

   int maxBars = MathMin(InpLookBars, ArraySize(a1)-2);
   maxBars = MathMin(maxBars, ArraySize(a2)-2);
   maxBars = MathMin(maxBars, ArraySize(tfmt)-1);
   if(maxBars < 1) { ReleaseHandles(h1,h2,h3,h4,h5); return; }

   for(int i=1; i<=maxBars; i++) {
      if(i+1<ArraySize(a1) && i+1<ArraySize(a2) && i<ArraySize(tfmt)) {
         double f0=a1[i],s0=a2[i],f1=a1[i+1],s1=a2[i+1];
         if(f0!=0&&s0!=0&&f1!=0&&s1!=0) {
            if(f1<=s1&&f0>s0) DrawTFLabel(tfmt[i], tfLabel, true, "9/20");
            else if(f1>=s1&&f0<s0) DrawTFLabel(tfmt[i], tfLabel, false, "9/20");
         }
      }
      if(i+1<ArraySize(a2) && i+1<ArraySize(a3)) {
         double f0=a2[i],s0=a3[i],f1=a2[i+1],s1=a3[i+1];
         if(f0!=0&&s0!=0&&f1!=0&&s1!=0) {
            if(f1<=s1&&f0>s0) DrawTFLabel(tfmt[i], tfLabel, true, "20/50");
            else if(f1>=s1&&f0<s0) DrawTFLabel(tfmt[i], tfLabel, false, "20/50");
         }
      }
      if(i+1<ArraySize(a3) && i+1<ArraySize(a4)) {
         double f0=a3[i],s0=a4[i],f1=a3[i+1],s1=a4[i+1];
         if(f0!=0&&s0!=0&&f1!=0&&s1!=0) {
            if(f1<=s1&&f0>s0) DrawTFLabel(tfmt[i], tfLabel, true, "50/100");
            else if(f1>=s1&&f0<s0) DrawTFLabel(tfmt[i], tfLabel, false, "50/100");
         }
      }
      if(i+1<ArraySize(a4) && i+1<ArraySize(a5)) {
         double f0=a4[i],s0=a5[i],f1=a4[i+1],s1=a5[i+1];
         if(f0!=0&&s0!=0&&f1!=0&&s1!=0) {
            if(f1<=s1&&f0>s0) DrawTFLabel(tfmt[i], tfLabel, true, "100/200");
            else if(f1>=s1&&f0<s0) DrawTFLabel(tfmt[i], tfLabel, false, "100/200");
         }
      }
   }

   ReleaseHandles(h1,h2,h3,h4,h5);
}

//+------------------------------------------------------------------+
//| Release handles                                                  |
//+------------------------------------------------------------------+
void ReleaseHandles(int h1, int h2, int h3, int h4, int h5) {
   if(h1!=INVALID_HANDLE) IndicatorRelease(h1);
   if(h2!=INVALID_HANDLE) IndicatorRelease(h2);
   if(h3!=INVALID_HANDLE) IndicatorRelease(h3);
   if(h4!=INVALID_HANDLE) IndicatorRelease(h4);
   if(h5!=INVALID_HANDLE) IndicatorRelease(h5);
}

//+------------------------------------------------------------------+
//| Draw ✗ cross marker on chart                                     |
//+------------------------------------------------------------------+
void DrawX(datetime t, double price, bool bullish, string pair) {
   string uid = IntegerToString(t) + "_" + IntegerToString((int)(price*100000));
   string objName = PREFIX + "X_" + uid;
   if(ObjectFind(0, objName) >= 0) return;

   color clr = bullish ? InpCrossUp : InpCrossDn;
   string tip = (bullish ? "COMPRA " : "VENDA ") + pair;

   if(!ObjectCreate(0, objName, OBJ_TEXT, 0, t, price)) return;
   ObjectSetString(0, objName, OBJPROP_TEXT, "✗");
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 16);
   ObjectSetString(0, objName, OBJPROP_FONT, "Wingdings 2");
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetString(0, objName, OBJPROP_TOOLTIP, tip);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);

   string arrName = objName + "_A";
   if(!ObjectCreate(0, arrName, OBJ_ARROW, 0, t, price)) return;
   ObjectSetInteger(0, arrName, OBJPROP_ARROWCODE, bullish ? 233 : 234);
   ObjectSetInteger(0, arrName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, arrName, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, arrName, OBJPROP_BACK, false);
   ObjectSetInteger(0, arrName, OBJPROP_SELECTABLE, false);

   string lbl = objName + "_L";
   double lblY = bullish ? price - 20*_Point : price + 20*_Point;
   if(!ObjectCreate(0, lbl, OBJ_TEXT, 0, t, lblY)) return;
   ObjectSetString(0, lbl, OBJPROP_TEXT, pair);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, lbl, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, lbl, OBJPROP_BACK, false);
   ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw multi-timeframe crossover label                             |
//+------------------------------------------------------------------+
void DrawTFLabel(datetime t, string tfLabel, bool bullish, string pair) {
   string uid = tfLabel + "_" + pair + "_" + IntegerToString(t);
   string objName = PREFIX + "TF_" + uid;
   if(ObjectFind(0, objName) >= 0) return;

   int barIdx = iBarShift(_Symbol, PERIOD_CURRENT, t);
   if(barIdx < 0) return;
   double price = iClose(_Symbol, PERIOD_CURRENT, barIdx);
   if(price <= 0) price = iOpen(_Symbol, PERIOD_CURRENT, barIdx);
   if(price <= 0) return;

   color clr = bullish ? InpCrossUp : InpCrossDn;
   string txt = tfLabel + " " + pair + (bullish ? " ▲" : " ▼");

   double offset = price * 0.002;
   if(offset < 10*_Point) offset = 10*_Point;
   double yPos = bullish ? price - offset : price + offset;

   if(!ObjectCreate(0, objName, OBJ_TEXT, 0, t, yPos)) return;
   ObjectSetString(0, objName, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 7);
   ObjectSetString(0, objName, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetString(0, objName, OBJPROP_TOOLTIP, "Cruzamento "+tfLabel+" "+pair);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Draw info panel (RSI, Stoch, MACD, ATR)                          |
//+------------------------------------------------------------------+
void DrawPanel(int total) {
   if(!InpShowRSI && !InpShowStoch && !InpShowMACD && !InpShowATR) return;

   double rsiVal[3]={0,0,0}, stochK[3]={0,0,0}, stochD[3]={0,0,0};
   double macd[3]={0,0,0}, macdSig[3]={0,0,0}, atrArr[3]={0,0,0};
   double atrVal = 0;

   if(InpShowRSI && hRSI!=INVALID_HANDLE)
      CopyBuffer(hRSI,0,0,3,rsiVal);
   if(InpShowStoch && hStoch!=INVALID_HANDLE) {
      CopyBuffer(hStoch,0,0,3,stochK);
      CopyBuffer(hStoch,1,0,3,stochD);
   }
   if(InpShowMACD && hMACD!=INVALID_HANDLE) {
      CopyBuffer(hMACD,0,0,3,macd);
      CopyBuffer(hMACD,1,0,3,macdSig);
   }
   if(InpShowATR && hATR!=INVALID_HANDLE) {
      CopyBuffer(hATR,0,0,3,atrArr);
      atrVal = atrArr[0];
   }

   string txt = "";
   string sep = "  |  ";

   if(InpShowRSI && rsiVal[0]!=0) {
      color cRsi = (rsiVal[0]>=InpRSIOverb) ? clrRed : (rsiVal[0]<=InpRSIOverd) ? clrLime : clrYellow;
      txt += "RSI("+IntegerToString(InpRSIPeriod)+"): " + StringFormat("%.1f", rsiVal[0]);
      txt += (rsiVal[0]>rsiVal[1]) ? " ▲" : " ▼";
      txt += sep;
   }

   if(InpShowStoch && stochK[0]!=0) {
      color cSt = (stochK[0]>=InpStochOverb) ? clrRed : (stochK[0]<=InpStochOverd) ? clrLime : clrYellow;
      txt += "Stoch("+IntegerToString(InpStochK)+"): " + StringFormat("%.1f", stochK[0]);
      txt += (stochK[0]>stochK[1]) ? " ▲" : " ▼";
      txt += sep;
   }

   if(InpShowMACD && macd[0]!=0) {
      color cMacd = (macd[0]>macdSig[0]) ? clrLime : clrRed;
      txt += "MACD: " + StringFormat("%+.5f", macd[0]);
      txt += sep;
   }

   if(InpShowATR && atrVal!=0) {
      txt += "ATR("+IntegerToString(InpATRPeriod)+"): " + StringFormat("%.5f", atrVal);
      txt += sep;
   }

   string leg = "MAs: ";
   leg += IntegerToString(InpMA1)+" "+IntegerToString(InpMA2)+" "+
          IntegerToString(InpMA3)+" "+IntegerToString(InpMA4)+" "+IntegerToString(InpMA5);

   // Show in Comment (top-left corner)
   Comment(txt + "\n" + leg);
}

//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester() { return 0; }
//+------------------------------------------------------------------+
