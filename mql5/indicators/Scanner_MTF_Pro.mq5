//+------------------------------------------------------------------+
//|                                            Scanner_MTF_Pro.mq5    |
//|                              Multi-Timeframe Trend Scanner        |
//|                                    by AAIF (Agentic AI Foundation)|
//+------------------------------------------------------------------+
#property copyright "AAIF - Agentic AI Foundation"
#property link      "https://aai.foundation"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

#include <Canvas/Canvas.mqh>

//--- input parameters
input string InpSymbolName = "EURUSD-T";        // Asset
input int    InpMAPeriodFast = 9;                // MA Fast Period
input int    InpMAPeriodMedium = 21;             // MA Medium Period
input int    InpRSIPeriod = 14;                  // RSI Period
input int    InpRSIMax = 70;                     // RSI Overbought
input int    InpRSIMin = 30;                     // RSI Oversold
input int    InpLookbackBars = 50;              // Lookback Bars per TF
input color  InpColorBull = clrLimeGreen;        // Bullish Color
input color  InpColorBear = clrRed;              // Bearish Color
input color  InpColorNeutral = clrYellow;        // Neutral Color
input int    InpFontSize = 9;                    // Font Size
input bool   InpShowAlert = true;                // Show Alert on Trend Change
input int    InpUpdateSeconds = 30;              // Update Interval (sec)

//--- enums
enum ENUM_TREND { TREND_BULLISH = 1, TREND_BEARISH = -1, TREND_NEUTRAL = 0 };

//--- timeframe names for display
string g_TFNames[] = {"MN1","W1","D1","H4","H1","M15","M5"};
ENUM_TIMEFRAMES g_TFs[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H4, PERIOD_H1, PERIOD_M15, PERIOD_M5};
int g_TFCount = 7;

//--- struct for timeframe analysis
struct TFData {
   ENUM_TREND trend;
   ENUM_TREND prevTrend;
   double     price;
   double     emaFast;
   double     emaMedium;
   double     rsi;
   double     atr;
   string     signal;
   color      signalColor;
};

TFData g_Data[];

//--- canvas drawing
CCanvas *g_canvas = NULL;
int g_canvasX = 10;
int g_canvasY = 30;
int g_cellW = 120;
int g_cellH = 24;
int g_pad = 4;
int g_prevBars = 0;
datetime g_lastUpdate = 0;

//+------------------------------------------------------------------+
int OnInit() {
   ArrayResize(g_Data, g_TFCount);
   for(int i=0; i<g_TFCount; i++) {
      g_Data[i].trend = TREND_NEUTRAL;
      g_Data[i].prevTrend = TREND_NEUTRAL;
   }
   
   IndicatorSetString(INDICATOR_SHORTNAME, "Scanner_MTF_Pro ("+InpSymbolName+")");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   if(g_canvas != NULL) { delete g_canvas; g_canvas = NULL; }
   ObjectsDeleteAll(0, "ScannerMTF_");
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[]) {
   
   if(IsStopped()) return(0);
   
   datetime now = TimeCurrent();
   if(now - g_lastUpdate < InpUpdateSeconds && g_lastUpdate > 0) return(rates_total);
   g_lastUpdate = now;
   
   AnalyzeAllTimeframes();
   DrawPanel();
   
   return(rates_total);
}

//+------------------------------------------------------------------+
void AnalyzeAllTimeframes() {
   for(int i=0; i<g_TFCount; i++) {
      AnalyzeTimeframe(g_TFs[i], i);
   }
}

//+------------------------------------------------------------------+
void AnalyzeTimeframe(ENUM_TIMEFRAMES tf, int idx) {
   //--- save previous trend
   g_Data[idx].prevTrend = g_Data[idx].trend;
   
   //--- get price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(InpSymbolName, tf, 0, InpLookbackBars+100, rates);
   if(copied < InpLookbackBars+20) {
      g_Data[idx].trend = TREND_NEUTRAL;
      g_Data[idx].signal = "No Data";
      g_Data[idx].signalColor = clrGray;
      return;
   }
   
   //--- price arrays for calculations
   double closeArr[], highArr[], lowArr[];
   ArrayResize(closeArr, copied);
   ArrayResize(highArr, copied);
   ArrayResize(lowArr, copied);
   for(int j=0; j<copied; j++) {
      closeArr[j] = rates[j].close;
      highArr[j] = rates[j].high;
      lowArr[j] = rates[j].low;
   }
   ArraySetAsSeries(closeArr, true);
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);
   
   //--- current price
   g_Data[idx].price = rates[0].close;
   
   //--- calculate EMAs
   double emaFast[], emaMedium[];
   ArrayResize(emaFast, copied);
   ArrayResize(emaMedium, copied);
   
   // EMA Fast
   double kFast = 2.0 / (InpMAPeriodFast + 1);
   emaFast[copied-1] = closeArr[copied-1];
   for(int j=copied-2; j>=0; j--)
      emaFast[j] = closeArr[j] * kFast + emaFast[j+1] * (1 - kFast);
   
   // EMA Medium
   double kMed = 2.0 / (InpMAPeriodMedium + 1);
   emaMedium[copied-1] = closeArr[copied-1];
   for(int j=copied-2; j>=0; j--)
      emaMedium[j] = closeArr[j] * kMed + emaMedium[j+1] * (1 - kMed);
   
   g_Data[idx].emaFast = emaFast[0];
   g_Data[idx].emaMedium = emaMedium[0];
   
   //--- calculate RSI
   double rsiArr[];
   ArrayResize(rsiArr, copied);
   double gain = 0, loss = 0;
   for(int j=1; j<=InpRSIPeriod; j++) {
      double diff = closeArr[copied-1-j] - closeArr[copied-1-j+1];
      if(diff > 0) gain += diff; else loss -= diff;
   }
   gain /= InpRSIPeriod;
   loss /= InpRSIPeriod;
   if(loss == 0) rsiArr[copied-1-InpRSIPeriod] = 100;
   else rsiArr[copied-1-InpRSIPeriod] = 100 - 100 / (1 + gain/loss);
   
   for(int j=copied-1-InpRSIPeriod-1; j>=0; j--) {
      double diff = closeArr[j] - closeArr[j+1];
      if(diff > 0) gain = (gain * (InpRSIPeriod-1) + diff) / InpRSIPeriod;
      else loss = (loss * (InpRSIPeriod-1) - diff) / InpRSIPeriod;
      
      if(loss == 0) rsiArr[j] = 100;
      else rsiArr[j] = 100 - 100 / (1 + gain/loss);
   }
   g_Data[idx].rsi = rsiArr[0];
   
   //--- calculate ATR
   double atrSum = 0;
   for(int j=0; j<14 && j<copied-1; j++) {
      double tr = MathMax(highArr[j], rates[j+1].close) - MathMin(lowArr[j], rates[j+1].close);
      atrSum += tr;
   }
   g_Data[idx].atr = atrSum / MathMin(14, copied-1);
   
   //--- trend logic
   bool emaBull = (emaFast[0] > emaMedium[0]);
   bool emaBear = (emaFast[0] < emaMedium[0]);
   
   //--- cross detection
   bool crossUp = (emaFast[1] <= emaMedium[1] && emaFast[0] > emaMedium[0]);
   bool crossDn = (emaFast[1] >= emaMedium[1] && emaFast[0] < emaMedium[0]);
   
   //--- determine signal
   if(crossUp && rsiArr[0] < InpRSIMax && rsiArr[0] > 25) {
      g_Data[idx].trend = TREND_BULLISH;
      g_Data[idx].signal = "COMPRA ↑";
      g_Data[idx].signalColor = clrLime;
   }
   else if(crossDn && rsiArr[0] > InpRSIMin && rsiArr[0] < 75) {
      g_Data[idx].trend = TREND_BEARISH;
      g_Data[idx].signal = "VENDA ↓";
      g_Data[idx].signalColor = clrRed;
   }
   else if(emaBull && rsiArr[0] > 50) {
      g_Data[idx].trend = TREND_BULLISH;
      g_Data[idx].signal = "Alta ↑";
      g_Data[idx].signalColor = clrLimeGreen;
   }
   else if(emaBear && rsiArr[0] < 50) {
      g_Data[idx].trend = TREND_BEARISH;
      g_Data[idx].signal = "Baixa ↓";
      g_Data[idx].signalColor = clrCoral;
   }
   else {
      g_Data[idx].trend = TREND_NEUTRAL;
      g_Data[idx].signal = "Neutro ↔";
      g_Data[idx].signalColor = clrYellow;
   }
   
   //--- alert on trend change
   if(InpShowAlert && g_Data[idx].prevTrend != TREND_NEUTRAL && 
      g_Data[idx].trend != g_Data[idx].prevTrend) {
      string msg = InpSymbolName + " " + g_TFNames[idx] + ": " + 
                   TrendToString(g_Data[idx].prevTrend) + " -> " + 
                   TrendToString(g_Data[idx].trend);
      Alert(msg);
   }
}

//+------------------------------------------------------------------+
void DrawPanel() {
   if(g_canvas == NULL) g_canvas = new CCanvas();
   
   int totalW = (g_TFCount + 1) * g_cellW + g_pad * 2;
   int totalH = 7 * g_cellH + 3*g_pad + 24;
   
   if(g_canvas.CreateBitmap("ScannerMTF_Panel", g_canvasX, g_canvasY, 
                            totalW, totalH, COLOR_FORMAT_XRGB_NOALPHA)) {
      g_canvas.Erase(clrNONE);
      g_canvas.FillRectangle(0, 0, totalW-1, totalH-1, clrBlack);
      g_canvas.Rectangle(0, 0, totalW-1, totalH-1, clrWhite);
      
      //--- draw header
      string headers[] = {"Timeframe", "Preco", "EMA9", "EMA21", "RSI", "Sinal"};
      int y = g_pad;
      int rowH = 22;
      
      for(int h=0; h<6; h++) {
         int x = g_pad;
         if(h > 0) x += g_cellW;
         
         DrawCell(g_canvas, x + (h==0?0:g_cellW), y, 
                  (h==0?g_cellW:g_cellW-2), rowH, 
                  headers[h], clrWhite, clrDarkSlateGray, InpFontSize, true);
      }
      
      y += rowH;
      
      //--- draw data rows
      for(int i=0; i<g_TFCount; i++) {
         int x = g_pad;
         
         color rowBg = (i%2==0) ? clrDarkGray : clrDimGray;
         DrawCell(g_canvas, x, y, g_cellW, rowH, 
                  g_TFNames[i], clrWhite, rowBg, InpFontSize, true);
         
         x += g_cellW;
         
         DrawCell(g_canvas, x, y, g_cellW-2, rowH, 
                  DoubleToString(g_Data[i].price, 5), clrWhite, rowBg, InpFontSize, false);
         
         x += g_cellW-2;
         
         DrawCell(g_canvas, x, y, g_cellW-2, rowH, 
                  DoubleToString(g_Data[i].emaFast, 5), clrCyan, rowBg, InpFontSize, false);
         
         x += g_cellW-2;
         
         DrawCell(g_canvas, x, y, g_cellW-2, rowH, 
                  DoubleToString(g_Data[i].emaMedium, 5), clrOrange, rowBg, InpFontSize, false);
         
         x += g_cellW-2;
         
         color rsiColor = clrYellow;
         if(g_Data[i].rsi > 70) rsiColor = clrRed;
         else if(g_Data[i].rsi < 30) rsiColor = clrLime;
         DrawCell(g_canvas, x, y, g_cellW-2, rowH, 
                  DoubleToString(g_Data[i].rsi, 1), rsiColor, rowBg, InpFontSize, false);
         
         x += g_cellW-2;
         
         DrawCell(g_canvas, x, y, g_cellW-2, rowH, 
                  g_Data[i].signal, g_Data[i].signalColor, rowBg, InpFontSize, true);
         
         y += rowH;
      }
      
      y += 2;
      
      //--- draw summary row
      int bullCount=0, bearCount=0, neutralCount=0;
      for(int i=0; i<g_TFCount; i++) {
         if(g_Data[i].trend == TREND_BULLISH) bullCount++;
         else if(g_Data[i].trend == TREND_BEARISH) bearCount++;
         else neutralCount++;
      }
      
      string summary = StringFormat("Altas:%d  Baixas:%d  Neutros:%d", bullCount, bearCount, neutralCount);
      color summaryColor = clrYellow;
      if(bullCount > bearCount && bullCount >= neutralCount) summaryColor = clrLime;
      else if(bearCount > bullCount && bearCount >= neutralCount) summaryColor = clrRed;
      
      DrawCell(g_canvas, g_pad, y, totalW - g_pad * 2, 24, 
               "Resumo: " + summary, summaryColor, clrBlack, InpFontSize+1, true);
      
      g_canvas.Update();
   }
}

//+------------------------------------------------------------------+
void DrawCell(CCanvas &canvas, int x, int y, int w, int h, 
              string text, color txtColor, color bgColor, int fontSize, bool bold) {
   canvas.FillRectangle(x, y, x+w, y+h, bgColor);
   canvas.Rectangle(x, y, x+w, y+h, clrWhite);
   
   uint txtW = 0, txtH = 0;
   TextSetFont("Consolas", fontSize, bold ? FW_BOLD : FW_NORMAL);
   TextGetSize(text, txtW, txtH);
   
   int txtX = x + (w - (int)txtW) / 2;
   int txtY = y + (h - (int)txtH) / 2;
   
   canvas.TextOut(txtX, txtY, text, txtColor, clrNONE);
}

//+------------------------------------------------------------------+
string TrendToString(ENUM_TREND trend) {
   switch(trend) {
      case TREND_BULLISH: return "Bullish";
      case TREND_BEARISH: return "Bearish";
      default: return "Neutral";
   }
}
//+------------------------------------------------------------------+
