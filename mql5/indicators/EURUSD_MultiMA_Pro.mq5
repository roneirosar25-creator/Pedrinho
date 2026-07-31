//+------------------------------------------------------------------+
//|                                              EURUSD_MultiMA_Pro  |
//|                                    Goose AI — RoneiRosar23       |
//|                                  Estrategia Multi-MA + RSI + SR  |
//+------------------------------------------------------------------+
#property copyright "Goose AI / RoneiRosar23"
#property link      ""
#property version   "1.00"
#property strict

#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   5

//--- plot EMA9
#property indicator_label1  "EMA9"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- plot EMA21
#property indicator_label2  "EMA21"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- plot EMA200
#property indicator_label3  "EMA200"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrMagenta
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- plot RSI (janela separada)
#property indicator_label4  "RSI(14)"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLime
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1
#property indicator_separate_window
#property indicator_minimum  0
#property indicator_maximum  100

//--- plot Sinal
#property indicator_label5  "Compra"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrLime
#property indicator_width5  2

//--- buffers
double   EMA9Buffer[];
double   EMA21Buffer[];
double   EMA200Buffer[];
double   RSIBuffer[];
double   SinalBuffer[];
double   tempBuffer1[];
double   tempBuffer2[];
double   tempBuffer3[];

//--- inputs
input int      MAPeriodFast     = 9;           // EMA Rapida
input int      MAPeriodMedium   = 21;          // EMA Media
input int      MAPeriodSlow     = 200;         // EMA Lenta
input int      RSIPeriod        = 14;          // Periodo RSI
input int      RSIMax           = 70;          // Sobrecompra RSI
input int      RSIMin           = 30;          // Sobrevenda RSI
input bool     AlertarCompra    = true;        // Alertar COMPRA
input bool     AlertarVenda     = true;        // Alertar VENDA
input bool     MostrarDivergencias = true;     // Mostrar divergencias RSI
input string   NomeAtivo        = "EURUSD";    // Nome para alerts

//--- globais
datetime       ultimoAlertaCompra = 0;
datetime       ultimoAlertaVenda  = 0;
int            handleRSI;
int            handleEMA9;
int            handleEMA21;
int            handleEMA200;

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "EURUSD MultiMA Pro ("
      + IntegerToString(MAPeriodFast) + ","
      + IntegerToString(MAPeriodMedium) + ","
      + IntegerToString(MAPeriodSlow) + ")");

   SetIndexBuffer(0, EMA9Buffer,   INDICATOR_DATA);
   SetIndexBuffer(1, EMA21Buffer,  INDICATOR_DATA);
   SetIndexBuffer(2, EMA200Buffer, INDICATOR_DATA);
   SetIndexBuffer(3, RSIBuffer,    INDICATOR_DATA);
   SetIndexBuffer(4, SinalBuffer,  INDICATOR_DATA);
   SetIndexBuffer(5, tempBuffer1,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, tempBuffer2,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, tempBuffer3,  INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(4, PLOT_ARROW, 233);

   //--- levels RSI
   IndicatorSetInteger(INDICATOR_LEVELS, 3);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, RSIMax);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, RSIMin);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, 50.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrGray);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrGray);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 2, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 2, STYLE_DOT);

   ArrayInitialize(EMA9Buffer,   EMPTY_VALUE);
   ArrayInitialize(EMA21Buffer,  EMPTY_VALUE);
   ArrayInitialize(EMA200Buffer, EMPTY_VALUE);
   ArrayInitialize(RSIBuffer,    EMPTY_VALUE);
   ArrayInitialize(SinalBuffer,  EMPTY_VALUE);

   handleEMA9   = iMA(_Symbol, PERIOD_CURRENT, MAPeriodFast,   0, MODE_EMA, PRICE_CLOSE);
   handleEMA21  = iMA(_Symbol, PERIOD_CURRENT, MAPeriodMedium, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA200 = iMA(_Symbol, PERIOD_CURRENT, MAPeriodSlow,   0, MODE_EMA, PRICE_CLOSE);
   handleRSI    = iRSI(_Symbol, PERIOD_CURRENT, RSIPeriod, PRICE_CLOSE);

   if(handleEMA9 == INVALID_HANDLE || handleEMA21 == INVALID_HANDLE
      || handleEMA200 == INVALID_HANDLE || handleRSI == INVALID_HANDLE)
   {
      Print("Erro criando handles! Codigo: ", GetLastError());
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleEMA9 != INVALID_HANDLE)   IndicatorRelease(handleEMA9);
   if(handleEMA21 != INVALID_HANDLE)  IndicatorRelease(handleEMA21);
   if(handleEMA200 != INVALID_HANDLE) IndicatorRelease(handleEMA200);
   if(handleRSI != INVALID_HANDLE)    IndicatorRelease(handleRSI);
   ObjectsDeleteAll(0, "MultiMA_");
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
   if(rates_total < MAPeriodSlow + RSIPeriod + 10)
      return(0);

   int start = prev_calculated - 1;
   if(start < MAPeriodSlow + 5)
      start = MAPeriodSlow + 5;

   if(CopyBuffer(handleEMA9,   0, 0, rates_total, tempBuffer1) <= 0) return(0);
   if(CopyBuffer(handleEMA21,  0, 0, rates_total, tempBuffer2) <= 0) return(0);
   if(CopyBuffer(handleEMA200, 0, 0, rates_total, tempBuffer3) <= 0) return(0);
   if(CopyBuffer(handleRSI,    0, 0, rates_total, RSIBuffer)   <= 0) return(0);

   for(int i = start; i < rates_total; i++)
   {
      EMA9Buffer[i]   = tempBuffer1[i];
      EMA21Buffer[i]  = tempBuffer2[i];
      EMA200Buffer[i] = tempBuffer3[i];
   }

   //--- calcular sinais
   for(int i = start; i < rates_total; i++)
   {
      SinalBuffer[i] = EMPTY_VALUE;

      if(i < 3) continue;
      if(EMA9Buffer[i] == EMPTY_VALUE || EMA21Buffer[i] == EMPTY_VALUE) continue;

      bool condCompra = false;

      //--- SINAL COMPRA: EMA9 cruza EMA21 p/ cima + RSI neutro
      if(EMA9Buffer[i-1] <= EMA21Buffer[i-1] && EMA9Buffer[i] > EMA21Buffer[i])
      {
         if(RSIBuffer[i] < RSIMax && RSIBuffer[i] > RSIMin - 5)
            condCompra = true;
      }

      //--- SINAL COMPRA: Pullback na EMA21
      if(!condCompra && i >= 3)
      {
         double lowBody = MathMin(close[i], open[i]);
         if(lowBody <= EMA21Buffer[i] + 5 * _Point
            && lowBody >= EMA21Buffer[i] - 3 * _Point
            && EMA9Buffer[i] > EMA21Buffer[i]
            && close[i] > open[i])
         {
            condCompra = true;
         }
      }

      //--- SINAL VENDA: EMA9 cruza EMA21 p/ baixo
      bool condVenda = false;
      if(EMA9Buffer[i-1] >= EMA21Buffer[i-1] && EMA9Buffer[i] < EMA21Buffer[i])
      {
         if(RSIBuffer[i] > RSIMin && RSIBuffer[i] < RSIMax + 5)
            condVenda = true;
      }

      //--- SINAL VENDA: Pullback na EMA21 por cima
      if(!condVenda && i >= 3)
      {
         double highBody = MathMax(close[i], open[i]);
         if(highBody >= EMA21Buffer[i] - 5 * _Point
            && highBody <= EMA21Buffer[i] + 3 * _Point
            && EMA9Buffer[i] < EMA21Buffer[i]
            && close[i] < open[i])
         {
            condVenda = true;
         }
      }

      //--- Plotar setas
      if(condCompra)
      {
         SinalBuffer[i] = low[i] - 15 * _Point;

         if(AlertarCompra && time[i] != ultimoAlertaCompra)
         {
            string msg = NomeAtivo + " COMPRA | EMA9: " + DoubleToString(EMA9Buffer[i],5)
               + " | EMA21: " + DoubleToString(EMA21Buffer[i],5)
               + " | RSI: " + DoubleToString(RSIBuffer[i],1);
            Alert(msg);
            SendNotification(msg);
            LogToFile("COMPRA", msg);
            ultimoAlertaCompra = time[i];
         }
      }

      if(condVenda)
      {
         DrawArrowVenda(time[i], high[i] + 20 * _Point, "MultiMA_V_" + IntegerToString(i));

         if(AlertarVenda && time[i] != ultimoAlertaVenda)
         {
            string msg = NomeAtivo + " VENDA | EMA9: " + DoubleToString(EMA9Buffer[i],5)
               + " | EMA21: " + DoubleToString(EMA21Buffer[i],5)
               + " | RSI: " + DoubleToString(RSIBuffer[i],1);
            Alert(msg);
            SendNotification(msg);
            LogToFile("VENDA", msg);
            ultimoAlertaVenda = time[i];
         }
      }

      //--- Divergencias RSI
      if(MostrarDivergencias && i >= 5 && RSIBuffer[i] != EMPTY_VALUE
         && RSIBuffer[i-1] != EMPTY_VALUE && RSIBuffer[i-2] != EMPTY_VALUE
         && RSIBuffer[i-3] != EMPTY_VALUE)
      {
         if(close[i] > close[i-2] && close[i-1] > close[i-3]
            && RSIBuffer[i] < RSIBuffer[i-2] && RSIBuffer[i-1] < RSIBuffer[i-3])
         {
            DrawLabel(time[i], high[i] + 40 * _Point, "DIV BEAR", clrRed, "MultiMA_DivB_" + IntegerToString(i));
         }
         else if(close[i] < close[i-2] && close[i-1] < close[i-3]
                 && RSIBuffer[i] > RSIBuffer[i-2] && RSIBuffer[i-1] > RSIBuffer[i-3])
         {
            DrawLabel(time[i], low[i] - 40 * _Point, "DIV BULL", clrLime, "MultiMA_DivU_" + IntegerToString(i));
         }
      }
   }

   //--- SR levels
   int last = rates_total - 1;
   DesenharNiveisSR(time, high, low, last);

   //--- Status no canto
   DrawStatus(close, last);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Suportes e Resistencias (Fibonacci)                              |
//+------------------------------------------------------------------+
void DesenharNiveisSR(const datetime &time[], const double &high[],
                       const double &low[], int last)
{
   string prefix = "MultiMA_SR_";
   for(int i = 0; i < 10; i++)
      ObjectDelete(0, prefix + IntegerToString(i));

   if(last < 50) return;

   double max50 = high[last];
   double min50 = low[last];
   for(int i = last - 49; i <= last; i++)
   {
      if(i < 0) continue;
      if(high[i] > max50) max50 = high[i];
      if(low[i]  < min50) min50 = low[i];
   }

   double range = max50 - min50;
   if(range <= 0) return;

   double fibs[5] = {0.236, 0.382, 0.500, 0.618, 0.786};
   color  cores[5] = {clrYellow, clrOrange, clrGold, clrRed, clrGray};

   for(int i = 0; i < 5; i++)
   {
      double nivel = max50 - range * fibs[i];
      string nome = prefix + IntegerToString(i);

      ObjectCreate(0, nome, OBJ_HLINE, 0, time[last], nivel);
      ObjectSetInteger(0, nome, OBJPROP_COLOR, cores[i]);
      ObjectSetInteger(0, nome, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, nome, OBJPROP_WIDTH, 1);
      ObjectSetString(0, nome, OBJPROP_TEXT, DoubleToString(nivel,5)
         + " (" + DoubleToString(fibs[i]*100,1) + "%)");
      ObjectSetInteger(0, nome, OBJPROP_BACK, true);
   }
}

//+------------------------------------------------------------------+
//| Status na tela                                                    |
//+------------------------------------------------------------------+
void DrawStatus(const double &close[], int last)
{
   string prefix = "MultiMA_Status_";
   ObjectDelete(0, prefix + "Info");

   string tendencia;
   color corTend;
   if(EMA9Buffer[last] > EMA21Buffer[last] && EMA21Buffer[last] > EMA200Buffer[last])
   {
      tendencia = "ALTA FORTE";
      corTend = clrLime;
   }
   else if(EMA9Buffer[last] < EMA21Buffer[last] && EMA21Buffer[last] < EMA200Buffer[last])
   {
      tendencia = "BAIXA FORTE";
      corTend = clrRed;
   }
   else if(EMA9Buffer[last] > EMA21Buffer[last])
   {
      tendencia = "ALTA FRACA";
      corTend = clrYellow;
   }
   else
   {
      tendencia = "BAIXA FRACA";
      corTend = clrYellow;
   }

   string info = NomeAtivo + " | " + tendencia
      + " | RSI: " + DoubleToString(RSIBuffer[last], 1)
      + " | E9: " + DoubleToString(EMA9Buffer[last],5)
      + " | E21: " + DoubleToString(EMA21Buffer[last],5)
      + " | E200: " + DoubleToString(EMA200Buffer[last],5);

   ObjectCreate(0, prefix + "Info", OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, prefix + "Info", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, prefix + "Info", OBJPROP_YDISTANCE, 25);
   ObjectSetInteger(0, prefix + "Info", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, prefix + "Info", OBJPROP_TEXT, info);
   ObjectSetInteger(0, prefix + "Info", OBJPROP_COLOR, corTend);
   ObjectSetInteger(0, prefix + "Info", OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, prefix + "Info", OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Seta de venda                                                     |
//+------------------------------------------------------------------+
void DrawArrowVenda(datetime t, double price, string nome)
{
   ObjectCreate(0, nome, OBJ_ARROW_DOWN, 0, t, price);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nome, OBJPROP_BACK, false);
}

//+------------------------------------------------------------------+
//| Label de texto                                                    |
//+------------------------------------------------------------------+
void DrawLabel(datetime t, double price, string texto, color cor, string nome)
{
   ObjectCreate(0, nome, OBJ_TEXT, 0, t, price);
   ObjectSetString(0, nome, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, nome, OBJPROP_BACK, false);
   ObjectSetInteger(0, nome, OBJPROP_ANCHOR, ANCHOR_CENTER);
}

//+------------------------------------------------------------------+
//| Log para arquivo                                                  |
//+------------------------------------------------------------------+
void LogToFile(string tipo, string msg)
{
   int h = FileOpen("MultiMA_Pro_" + NomeAtivo + ".csv", FILE_WRITE|FILE_CSV|FILE_READ|FILE_TXT, ",");
   if(h != INVALID_HANDLE)
   {
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, TimeToString(TimeCurrent()), tipo, msg);
      FileClose(h);
   }
}
//+------------------------------------------------------------------+
