//+------------------------------------------------------------------+
//|                                      RING_GOLD_PRO.mq5           |
//|                          XAUUSD/GOLD Optimizado (2-dígitos)      |
//+------------------------------------------------------------------+
#property copyright "RoneiRosar23"
#property version   "2.00"
#property description "Sistema Antecipatório Multi-Timeframe para GOLD/XAUUSD"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   4

#property indicator_type1   DRAW_ARROW
#property indicator_width1  2
#property indicator_color1  0x00FF88
#property indicator_label1  "GOLD Buy Early"

#property indicator_type2   DRAW_ARROW
#property indicator_width2  2
#property indicator_color2  0xFF4444
#property indicator_label2  "GOLD Sell Early"

#property indicator_type3   DRAW_ARROW
#property indicator_width3  1
#property indicator_color3  0x4488FF
#property indicator_label3  "GOLD Buy Confirm"

#property indicator_type4   DRAW_ARROW
#property indicator_width4  1
#property indicator_color4  0xFF8800
#property indicator_label4  "GOLD Sell Confirm"

#define PLOT_MAXIMUM_BARS_BACK 5000
#define OMIT_OLDEST_BARS 50

double BuyEarly[],SellEarly[],BuyConfirm[],SellConfirm[],myPoint;
int wpr_handle,rsi_handle,macd_handle,atr_handle,ad_handle;
double WPRbuff[],RSIbuff[],MACDmain[],MACDsignal[],MACDhist[],ATRbuff[],ADbuff[],LowBuff[],HighBuff[];

input int      WPR_Period       = 10;
input int      RSI_Period       = 14;
input int      MACD_Fast        = 10;
input int      MACD_Slow        = 22;
input int      MACD_Signal      = 7;
input int      Overbought       = -15;
input int      Oversold         = -85;
input int      NeutralHigh      = -25;
input int      NeutralLow       = -75;
input double   ATR_TP_Ratio     = 2.5;
input double   ATR_SL_Ratio     = 1.2;
input int      RambooShift      = 14;
input int      DashX            = 500;
input int      DashY            = 200;
input int      MainBoxX         = 380;
input int      MainBoxY         = 113;
input int      MinScoreForEarly  = 55;
input int      MinScoreForEntry  = 75;

string prefix="GOLD_";
ENUM_TIMEFRAMES periods[]={PERIOD_M1,PERIOD_M5,PERIOD_M15,PERIOD_M30,PERIOD_H1,PERIOD_H4,PERIOD_D1,PERIOD_W1};
string period_names[]={"M1","M5","M15","M30","H1","H4","D1","W1"};
string labelBuy="GOLD_TotalBuy",labelSell="GOLD_TotalSell",obj_name="GOLD_InfoBox";

int OnInit()
{
   SetIndexBuffer(0,BuyEarly,INDICATOR_DATA); SetIndexBuffer(1,SellEarly,INDICATOR_DATA);
   SetIndexBuffer(2,BuyConfirm,INDICATOR_DATA); SetIndexBuffer(3,SellConfirm,INDICATOR_DATA);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   int db=MathMax(Bars(_Symbol,PERIOD_CURRENT)-PLOT_MAXIMUM_BARS_BACK+1,OMIT_OLDEST_BARS+1);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,db); PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,db);
   PlotIndexSetInteger(2,PLOT_DRAW_BEGIN,db); PlotIndexSetInteger(3,PLOT_DRAW_BEGIN,db);
   PlotIndexSetInteger(0,PLOT_ARROW,233); PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(2,PLOT_ARROW,159); PlotIndexSetInteger(3,PLOT_ARROW,159);
   myPoint=Point(); if(Digits()==5||Digits()==3) myPoint*=10;
   wpr_handle=iWPR(_Symbol,PERIOD_CURRENT,WPR_Period);
   rsi_handle=iRSI(_Symbol,PERIOD_CURRENT,RSI_Period,PRICE_CLOSE);
   macd_handle=iMACD(_Symbol,PERIOD_CURRENT,MACD_Fast,MACD_Slow,MACD_Signal,PRICE_CLOSE);
   atr_handle=iATR(_Symbol,PERIOD_CURRENT,RambooShift);
   ad_handle=iAD(_Symbol,PERIOD_CURRENT,VOLUME_TICK);
   if(wpr_handle==INVALID_HANDLE||rsi_handle==INVALID_HANDLE||macd_handle==INVALID_HANDLE||atr_handle==INVALID_HANDLE||ad_handle==INVALID_HANDLE)
      return INIT_FAILED;
   CreateMainLabel("GOLD_TrendLabel","GOLD SISTEMA : INICIALIZANDO...",500,15,15,clrWhite);
   CreateMainLabel("GOLD_PLLabel","GOLD P/L : ---",500,80,16,clrWhite);
   CreateMainLabel(labelBuy,"GOLD LOT BUY : 0.00",500,50,13,clrMistyRose);
   CreateMainLabel(labelSell,"GOLD LOT SELL : 0.00",500,65,13,clrMistyRose);
   ObjectDelete(0,obj_name); ObjectCreate(0,obj_name,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,obj_name,OBJPROP_XDISTANCE,MainBoxX); ObjectSetInteger(0,obj_name,OBJPROP_YDISTANCE,MainBoxY);
   ObjectSetInteger(0,obj_name,OBJPROP_XSIZE,650); ObjectSetInteger(0,obj_name,OBJPROP_YSIZE,27);
   ObjectSetInteger(0,obj_name,OBJPROP_FONTSIZE,13); ObjectSetInteger(0,obj_name,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,obj_name,OBJPROP_READONLY,true); ObjectSetInteger(0,obj_name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,obj_name,OBJPROP_ALIGN,ALIGN_CENTER);
   ChartRedraw(); return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0,"GOLD_"); ObjectsDeleteAll(0,prefix);
   IndicatorRelease(wpr_handle); IndicatorRelease(rsi_handle); IndicatorRelease(macd_handle); IndicatorRelease(atr_handle); IndicatorRelease(ad_handle);
   ChartRedraw(0);
}

int OnCalculate(const int rt,const int pc,const datetime&t[],const double&o[],const double&h[],const double&l[],const double&c[],const long&tv[],const long&rv[],const int&s[])
{
   if(rt<WPR_Period+MACD_Slow+10) return 0;
   int limit=(pc<1)?rt-1:rt-pc; if(limit<1) limit=1;
   ArraySetAsSeries(t,true); ArraySetAsSeries(h,true); ArraySetAsSeries(l,true); ArraySetAsSeries(c,true);
   if(!LoadIndicatorData(rt)) return pc;
   if(pc<1)
   {
      ArrayInitialize(BuyEarly,EMPTY_VALUE); ArrayInitialize(SellEarly,EMPTY_VALUE);
      ArrayInitialize(BuyConfirm,EMPTY_VALUE); ArrayInitialize(SellConfirm,EMPTY_VALUE);
   }
   ArraySetAsSeries(BuyEarly,true); ArraySetAsSeries(SellEarly,true);
   ArraySetAsSeries(BuyConfirm,true); ArraySetAsSeries(SellConfirm,true);
   for(int i=limit-1; i>=0; i--)
   {
      if(i>=MathMin(PLOT_MAXIMUM_BARS_BACK-1,rt-1-OMIT_OLDEST_BARS)) continue;
      int bs=CalculateBuyScore(i); int ss=CalculateSellScore(i);
      if(bs>=MinScoreForEarly && bs>ss+10)
      {
         if(BuyEarly[i+1]==EMPTY_VALUE || t[i]!=t[i+1]) BuyEarly[i]=l[i]-(myPoint*10);
      }
      else BuyEarly[i]=EMPTY_VALUE;
      if(ss>=MinScoreForEarly && ss>bs+10)
      {
         if(SellEarly[i+1]==EMPTY_VALUE || t[i]!=t[i+1]) SellEarly[i]=h[i]+(myPoint*10);
      }
      else SellEarly[i]=EMPTY_VALUE;
      if(bs>=MinScoreForEntry)
      {
         if(BuyConfirm[i+1]==EMPTY_VALUE || t[i]!=t[i+1]) BuyConfirm[i]=l[i]-(myPoint*5);
      }
      else BuyConfirm[i]=EMPTY_VALUE;
      if(ss>=MinScoreForEntry)
      {
         if(SellConfirm[i+1]==EMPTY_VALUE || t[i]!=t[i+1]) SellConfirm[i]=h[i]+(myPoint*5);
      }
      else SellConfirm[i]=EMPTY_VALUE;
   }
   UpdateGraphicObjects(c,h,l);
   DrawMTFDashboard();
   return rt;
}

bool LoadIndicatorData(int total)
{
   if(BarsCalculated(wpr_handle)<=0||BarsCalculated(rsi_handle)<=0||BarsCalculated(macd_handle)<=0||BarsCalculated(atr_handle)<=0||BarsCalculated(ad_handle)<=0) return false;
   if(CopyBuffer(wpr_handle,0,0,total,WPRbuff)<=0||CopyBuffer(rsi_handle,0,0,total,RSIbuff)<=0) return false;
   if(CopyBuffer(macd_handle,0,0,total,MACDmain)<=0||CopyBuffer(macd_handle,1,0,total,MACDsignal)<=0||CopyBuffer(macd_handle,2,0,total,MACDhist)<=0) return false;
   if(CopyBuffer(atr_handle,0,0,total,ATRbuff)<=0||CopyBuffer(ad_handle,0,0,total,ADbuff)<=0) return false;
   if(CopyLow(_Symbol,PERIOD_CURRENT,0,total,LowBuff)<=0||CopyHigh(_Symbol,PERIOD_CURRENT,0,total,HighBuff)<=0) return false;
   ArraySetAsSeries(WPRbuff,true); ArraySetAsSeries(RSIbuff,true); ArraySetAsSeries(MACDmain,true);
   ArraySetAsSeries(MACDsignal,true); ArraySetAsSeries(MACDhist,true); ArraySetAsSeries(ATRbuff,true);
   ArraySetAsSeries(ADbuff,true); ArraySetAsSeries(LowBuff,true); ArraySetAsSeries(HighBuff,true);
   return true;
}

int CalculateBuyScore(int i)
{
   int sc=0;
   if(WPRbuff[i]<Oversold) sc+=25;
   else if(WPRbuff[i]<NeutralLow) sc+=15;
   else if(WPRbuff[i]<-50) sc+=5;
   if(i+2<ArraySize(WPRbuff))
   {
      if(LowBuff[i]<LowBuff[i+1]&&LowBuff[i+1]<LowBuff[i+2]&&WPRbuff[i]>WPRbuff[i+1]&&WPRbuff[i+1]>WPRbuff[i+2]) sc+=20;
      else if(LowBuff[i]<LowBuff[i+1]&&WPRbuff[i]>WPRbuff[i+1]) sc+=10;
   }
   if(i+2<ArraySize(MACDhist))
   {
      if(MACDhist[i]>MACDhist[i+1]&&MACDhist[i+1]>MACDhist[i+2]) sc+=20;
      else if(MACDhist[i]>MACDhist[i+1]) sc+=10;
      if(MACDhist[i]>0&&MACDhist[i+1]<=0) sc+=10;
   }
   if(RSIbuff[i]<25) sc+=15;
   else if(RSIbuff[i]<35) sc+=8;
   if(i+1<ArraySize(ADbuff)&&ADbuff[i]>ADbuff[i+1]) sc+=10;
   if(i+2<ArraySize(WPRbuff))
   {
      double v=WPRbuff[i]-WPRbuff[i+1];
      double vp=WPRbuff[i+1]-WPRbuff[i+2];
      if(v>0&&v>vp) sc+=10;
      else if(v>0) sc+=5;
   }
   return MathMin(sc,100);
}

int CalculateSellScore(int i)
{
   int sc=0;
   if(WPRbuff[i]>Overbought) sc+=25;
   else if(WPRbuff[i]>NeutralHigh) sc+=15;
   else if(WPRbuff[i]>-50) sc+=5;
   if(i+2<ArraySize(WPRbuff))
   {
      if(HighBuff[i]>HighBuff[i+1]&&HighBuff[i+1]>HighBuff[i+2]&&WPRbuff[i]<WPRbuff[i+1]&&WPRbuff[i+1]<WPRbuff[i+2]) sc+=20;
      else if(HighBuff[i]>HighBuff[i+1]&&WPRbuff[i]<WPRbuff[i+1]) sc+=10;
   }
   if(i+2<ArraySize(MACDhist))
   {
      if(MACDhist[i]<MACDhist[i+1]&&MACDhist[i+1]<MACDhist[i+2]) sc+=20;
      else if(MACDhist[i]<MACDhist[i+1]) sc+=10;
      if(MACDhist[i]<0&&MACDhist[i+1]>=0) sc+=10;
   }
   if(RSIbuff[i]>75) sc+=15;
   else if(RSIbuff[i]>65) sc+=8;
   if(i+1<ArraySize(ADbuff)&&ADbuff[i]<ADbuff[i+1]) sc+=10;
   if(i+2<ArraySize(WPRbuff))
   {
      double v=WPRbuff[i]-WPRbuff[i+1];
      double vp=WPRbuff[i+1]-WPRbuff[i+2];
      if(v<0&&v<vp) sc+=10;
      else if(v<0) sc+=5;
   }
   return MathMin(sc,100);
}

void UpdateGraphicObjects(const double&c[],const double&h[],const double&l[])
{
   double wpr=WPRbuff[0],rsi=RSIbuff[0],atr=ATRbuff[0];
   int bs=CalculateBuyScore(0),ss=CalculateSellScore(0);
   string tt,tp="",sl=""; color tc; string st="NEUTRAL";
   if(bs>=MinScoreForEntry){tt="GOLD SINAL FORTE COMPRA ["+IntegerToString(bs)+"/100]"; tc=clrDeepSkyBlue; st="BUY";}
   else if(ss>=MinScoreForEntry){tt="GOLD SINAL FORTE VENDA ["+IntegerToString(ss)+"/100]"; tc=clrMagenta; st="SELL";}
   else if(bs>=MinScoreForEarly){tt="GOLD ANTECIPACAO COMPRA ["+IntegerToString(bs)+"/100]"; tc=clrAqua; st="BUY_EARLY";}
   else if(ss>=MinScoreForEarly){tt="GOLD ANTECIPACAO VENDA ["+IntegerToString(ss)+"/100]"; tc=clrOrange; st="SELL_EARLY";}
   else {tt="GOLD NEUTRO [B:"+IntegerToString(bs)+" S:"+IntegerToString(ss)+"]"; tc=clrYellow;}
   if(StringFind(st,"BUY")>=0)
   {
      tp="TP:"+DoubleToString(c[0]+atr*ATR_TP_Ratio,2)+" ("+DoubleToString(ATR_TP_Ratio,1)+"ATR)";
      sl="SL:"+DoubleToString(c[0]-atr*ATR_SL_Ratio,2)+" ("+DoubleToString(ATR_SL_Ratio,1)+"ATR)";
   }
   else if(StringFind(st,"SELL")>=0)
   {
      tp="TP:"+DoubleToString(c[0]-atr*ATR_TP_Ratio,2)+" ("+DoubleToString(ATR_TP_Ratio,1)+"ATR)";
      sl="SL:"+DoubleToString(c[0]+atr*ATR_SL_Ratio,2)+" ("+DoubleToString(ATR_SL_Ratio,1)+"ATR)";
   }
   string info="WPR:"+DoubleToString(wpr,2)+"|RSI:"+DoubleToString(rsi,2)+"|ATR:"+DoubleToString(atr,2)+"|"+tt+"|"+tp+"|"+sl;
   ObjectSetString(0,obj_name,OBJPROP_TEXT,info); ObjectSetInteger(0,obj_name,OBJPROP_COLOR,tc);
   ObjectSetString(0,"GOLD_TrendLabel",OBJPROP_TEXT,tt); ObjectSetInteger(0,"GOLD_TrendLabel",OBJPROP_COLOR,tc);
   double pft=0;
   for(int i=0;i<PositionsTotal();i++){ulong tk=PositionGetTicket(i); if(PositionGetString(POSITION_SYMBOL)==_Symbol) pft+=PositionGetDouble(POSITION_PROFIT);}
   string pl; color plc;
   if(pft>=0){pl="LUCRO ("+_Symbol+"):$"+DoubleToString(pft,2); plc=clrDeepSkyBlue;}
   else{pl="PERDA ("+_Symbol+"):$"+DoubleToString(MathAbs(pft),2); plc=clrGold;}
   ObjectSetString(0,"GOLD_PLLabel",OBJPROP_TEXT,pl); ObjectSetInteger(0,"GOLD_PLLabel",OBJPROP_COLOR,plc);
   double tb=0,ts=0; string cs=Symbol();
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong tk=PositionGetTicket(i);
      if(PositionSelectByTicket(tk)&&PositionGetString(POSITION_SYMBOL)==cs)
      {
         double lv=PositionGetDouble(POSITION_VOLUME);
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY) tb+=lv; else ts+=lv;
      }
   }
   ObjectSetString(0,labelBuy,OBJPROP_TEXT,"("+cs+") LOT BUY:"+DoubleToString(tb,2));
   ObjectSetString(0,labelSell,OBJPROP_TEXT,"("+cs+") LOT SELL:"+DoubleToString(ts,2));
   ObjectDelete(0,"GOLD_TP_Line"); ObjectDelete(0,"GOLD_SL_Line");
   if(StringFind(st,"BUY")>=0)
   {
      ObjectCreate(0,"GOLD_TP_Line",OBJ_HLINE,0,0,c[0]+atr*ATR_TP_Ratio);
      ObjectSetInteger(0,"GOLD_TP_Line",OBJPROP_COLOR,clrLime); ObjectSetInteger(0,"GOLD_TP_Line",OBJPROP_WIDTH,1); ObjectSetInteger(0,"GOLD_TP_Line",OBJPROP_STYLE,STYLE_DASH);
      ObjectCreate(0,"GOLD_SL_Line",OBJ_HLINE,0,0,c[0]-atr*ATR_SL_Ratio);
      ObjectSetInteger(0,"GOLD_SL_Line",OBJPROP_COLOR,clrRed); ObjectSetInteger(0,"GOLD_SL_Line",OBJPROP_WIDTH,1); ObjectSetInteger(0,"GOLD_SL_Line",OBJPROP_STYLE,STYLE_DASH);
   }
   else if(StringFind(st,"SELL")>=0)
   {
      ObjectCreate(0,"GOLD_TP_Line",OBJ_HLINE,0,0,c[0]-atr*ATR_TP_Ratio);
      ObjectSetInteger(0,"GOLD_TP_Line",OBJPROP_COLOR,clrLime); ObjectSetInteger(0,"GOLD_TP_Line",OBJPROP_WIDTH,1); ObjectSetInteger(0,"GOLD_TP_Line",OBJPROP_STYLE,STYLE_DASH);
      ObjectCreate(0,"GOLD_SL_Line",OBJ_HLINE,0,0,c[0]+atr*ATR_SL_Ratio);
      ObjectSetInteger(0,"GOLD_SL_Line",OBJPROP_COLOR,clrRed); ObjectSetInteger(0,"GOLD_SL_Line",OBJPROP_WIDTH,1); ObjectSetInteger(0,"GOLD_SL_Line",OBJPROP_STYLE,STYLE_DASH);
   }
   ChartRedraw();
}

void DrawMTFDashboard()
{
   int x=DashX,y=DashY,rh=20;
   CreateLabel(prefix+"header"," GOLD MTF MOMENTUM MATRIX [Score]",x,y,clrWhite,clrDarkSlateGray,10,315); y+=rh;
   CreateLabel(prefix+"c1"," TF ",x,y,clrWhite,clrBlack,9,35);
   CreateLabel(prefix+"c2"," WPR ",x+38,y,clrWhite,clrBlack,9,50);
   CreateLabel(prefix+"c3"," RSI ",x+90,y,clrWhite,clrBlack,9,45);
   CreateLabel(prefix+"c4"," SCORE ",x+138,y,clrWhite,clrBlack,9,60);
   CreateLabel(prefix+"c5"," SINAL ",x+200,y,clrWhite,clrBlack,9,115); y+=rh;
   for(int i=0;i<ArraySize(periods);i++)
   {
      if(periods[i]==PERIOD_CURRENT) continue;
      int sc=GetMTFScore(periods[i]);
      string st="---"; color bg=clrGray;
      if(sc>=MinScoreForEntry) {st="COMPRA"; bg=clrDodgerBlue;}
      else if(sc<=-MinScoreForEntry) {st="VENDA"; bg=clrRed;}
      else if(sc>=MinScoreForEarly) {st="C.EARLY"; bg=clrSteelBlue;}
      else if(sc<=-MinScoreForEarly) {st="V.EARLY"; bg=clrDarkRed;}
      CreateLabel(prefix+"tf_"+period_names[i]," "+period_names[i]+" ",x,y,clrWhite,clrBlack,9,35);
      CreateLabel(prefix+"wp_"+period_names[i],DoubleToString(GetMTFWPR(periods[i]),1),x+38,y,clrWhite,clrBlack,9,50);
      CreateLabel(prefix+"rs_"+period_names[i],DoubleToString(GetMTFRSI(periods[i]),1),x+90,y,clrWhite,clrBlack,9,45);
      CreateLabel(prefix+"sc_"+period_names[i],IntegerToString(sc),x+138,y,clrWhite,clrBlack,9,60);
      CreateLabel(prefix+"si_"+period_names[i]," "+st+" ",x+200,y,clrWhite,bg,9,115); y+=rh;
   }
}

int GetMTFScore(ENUM_TIMEFRAMES tf)
{
   double wpr[],rsi[],ad[];
   int hw=iWPR(_Symbol,tf,WPR_Period); int hr=iRSI(_Symbol,tf,RSI_Period,PRICE_CLOSE);
   int ha=iAD(_Symbol,tf,VOLUME_TICK);
   if(hw==INVALID_HANDLE||hr==INVALID_HANDLE||ha==INVALID_HANDLE)
   {IndicatorRelease(hw);IndicatorRelease(hr);IndicatorRelease(ha);return 0;}
   if(CopyBuffer(hw,0,0,2,wpr)<=0||CopyBuffer(hr,0,0,1,rsi)<=0||CopyBuffer(ha,0,0,2,ad)<=0)
   {IndicatorRelease(hw);IndicatorRelease(hr);IndicatorRelease(ha);return 0;}
   ArraySetAsSeries(wpr,true); ArraySetAsSeries(ad,true);
   int sc=0;
   if(wpr[0]<Oversold) sc+=25; else if(wpr[0]<-50) sc+=10;
   if(rsi[0]<25) sc+=15; else if(rsi[0]<35) sc+=5;
   if(ad[0]>ad[1]) sc+=10;
   if(wpr[0]>wpr[1]&&wpr[0]<-50) sc+=10;
   if(wpr[0]>Overbought) sc-=25; else if(wpr[0]>-50) sc-=10;
   if(rsi[0]>75) sc-=15; else if(rsi[0]>65) sc-=5;
   if(ad[0]<ad[1]) sc-=10;
   if(wpr[0]<wpr[1]&&wpr[0]>-50) sc-=10;
   IndicatorRelease(hw); IndicatorRelease(hr); IndicatorRelease(ha);
   return sc;
}

double GetMTFWPR(ENUM_TIMEFRAMES tf){int h=iWPR(_Symbol,tf,WPR_Period); double b[]; if(CopyBuffer(h,0,0,1,b)<=0){IndicatorRelease(h);return 0;} IndicatorRelease(h); return b[0];}
double GetMTFRSI(ENUM_TIMEFRAMES tf){int h=iRSI(_Symbol,tf,RSI_Period,PRICE_CLOSE); double b[]; if(CopyBuffer(h,0,0,1,b)<=0){IndicatorRelease(h);return 0;} IndicatorRelease(h); return b[0];}
void CreateMainLabel(string n,string t,int x,int y,int fs,color c){ObjectDelete(0,n);ObjectCreate(0,n,OBJ_LABEL,0,0,0);ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);ObjectSetString(0,n,OBJPROP_TEXT,t);ObjectSetInteger(0,n,OBJPROP_FONTSIZE,fs);ObjectSetInteger(0,n,OBJPROP_COLOR,c);}
void CreateLabel(string n,string t,int x,int y,color tc,color bc,int sz,int wd){ObjectDelete(0,n);ObjectCreate(0,n,OBJ_EDIT,0,0,0);ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,n,OBJPROP_XSIZE,wd);ObjectSetInteger(0,n,OBJPROP_YSIZE,18);ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bc);ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);ObjectSetString(0,n,OBJPROP_TEXT,t);ObjectSetInteger(0,n,OBJPROP_COLOR,tc);ObjectSetInteger(0,n,OBJPROP_FONTSIZE,sz);ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);}
//+------------------------------------------------------------------+
