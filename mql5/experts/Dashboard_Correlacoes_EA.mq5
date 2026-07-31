//+------------------------------------------------------------------+
//|                                   Dashboard_Correlacoes_EA.mq5   |
//|                     Advanced Correlation Dashboard for EURUSD     |
//|                                    by AAIF (Agentic AI Foundation)|
//+------------------------------------------------------------------+
#property copyright "AAIF - Agentic AI Foundation"
#property link      "https://aai.foundation"
#property version   "1.01"
#property description "Dashboard de Correlacoes do EURUSD"
#property description "Exibe correlacoes diretas e inversas em tempo real"

input string InpMainSymbol = "EURUSD-T";         // Main Symbol
input int    InpUpdateInterval = 10;             // Update Interval (sec)
input int    InpCorrelationBars = 50;            // Bars for Correlation Calc
input color  InpBgColor = clrBlack;              // Background Color
input int    InpFontSize = 8;                    // Font Size
input bool   InpShowDXY = true;                  // Show DXY (USD Index)
input bool   InpShowGOLD = true;                 // Show GOLD
input bool   InpShowSILVER = true;               // Show SILVER
input bool   InpShowSP500 = true;                // Show S&P 500
input bool   InpShowNASDAQ = true;               // Show NASDAQ

struct CorrSymbol {
   string symbol;
   string label;
   string relType;
   double price;
   double change;
   double changePct;
   double correlation;
   bool   hasData;
};

CorrSymbol g_symbols[];
int g_symbolCount = 0;
datetime g_lastUpdate = 0;
string g_prefix = "CorrDash_";

//+------------------------------------------------------------------+
int OnInit() {
   ChartSetInteger(0, CHART_SHOW, false);
   ChartSetInteger(0, CHART_FOREGROUND, true);
   BuildSymbolList();
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
}

//+------------------------------------------------------------------+
void OnTick() {
   datetime now = TimeCurrent();
   if(now - g_lastUpdate < InpUpdateInterval && g_lastUpdate > 0) return;
   g_lastUpdate = now;
   UpdateData();
   DrawDashboard();
}

//+------------------------------------------------------------------+
void OnTimer() { OnTick(); }

//+------------------------------------------------------------------+
void BuildSymbolList() {
   AddSymbol("GBPUSD-T","GBP/USD","Direta (+)");
   AddSymbol("EURJPY-T","EUR/JPY","Direta (+)");
   AddSymbol("EURGBP-T","EUR/GBP","Direta (+)");
   AddSymbol("AUDUSD-T","AUD/USD","Direta (+)");
   AddSymbol("NZDUSD-T","NZD/USD","Direta (+)");
   AddSymbol("USDCAD-T","USD/CAD","Inversa (-)");
   AddSymbol("USDCHF-T","USD/CHF","Inversa (-)");
   AddSymbol("USDJPY-T","USD/JPY","Inversa (-)");
   if(InpShowDXY)    AddSymbol("USD.indx-T","DXY","Dolar Index");
   if(InpShowGOLD)   AddSymbol("GOLD-T","XAU/USD","Ouro (+)");
   if(InpShowSILVER) AddSymbol("SILVER-T","XAG/USD","Prata (+)");
   if(InpShowSP500)  AddSymbol("[USA500]-T","S&P 500","Indice (+)");
   if(InpShowNASDAQ) AddSymbol("US100-T","NAS100","NASDAQ (+)");
}

//+------------------------------------------------------------------+
void AddSymbol(string sym, string label, string relType) {
   int idx = g_symbolCount++;
   ArrayResize(g_symbols, g_symbolCount);
   g_symbols[idx].symbol=sym; g_symbols[idx].label=label; g_symbols[idx].relType=relType;
   g_symbols[idx].price=0; g_symbols[idx].change=0; g_symbols[idx].changePct=0;
   g_symbols[idx].correlation=0; g_symbols[idx].hasData=false;
   SymbolSelect(sym, true);
}

//+------------------------------------------------------------------+
void UpdateData() {
   for(int i=0;i<g_symbolCount;i++) {
      double bid=SymbolInfoDouble(g_symbols[i].symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(g_symbols[i].symbol,SYMBOL_ASK);
      if(bid==0||ask==0) { g_symbols[i].hasData=false; continue; }
      g_symbols[i].price=(bid+ask)/2.0; g_symbols[i].hasData=true;
      MqlRates r[2];
      if(CopyRates(g_symbols[i].symbol,PERIOD_D1,0,2,r)>=2) {
         g_symbols[i].change=g_symbols[i].price-r[0].open;
         g_symbols[i].changePct=(g_symbols[i].change/r[0].open)*100.0;
      }
      g_symbols[i].correlation=CalcCorr(InpMainSymbol,g_symbols[i].symbol,InpCorrelationBars);
   }
}

//+------------------------------------------------------------------+
double CalcCorr(string s1, string s2, int bars) {
   MqlRates r1[],r2[];
   ArraySetAsSeries(r1,true); ArraySetAsSeries(r2,true);
   int c1=CopyRates(s1,PERIOD_H1,0,bars,r1);
   int c2=CopyRates(s2,PERIOD_H1,0,bars,r2);
   if(c1<10||c2<10) return 0;
   int n=MathMin(c1,c2)-1; if(n<10) return 0;
   double ret1[],ret2[];
   ArrayResize(ret1,n); ArrayResize(ret2,n);
   double s1v=0,s2v=0;
   for(int i=0;i<n;i++) {
      ret1[i]=(r1[i].close-r1[i+1].close)/r1[i+1].close;
      ret2[i]=(r2[i].close-r2[i+1].close)/r2[i+1].close;
      s1v+=ret1[i]; s2v+=ret2[i];
   }
   double m1=s1v/n,m2=s2v/n,covar=0,v1=0,v2=0;
   for(int i=0;i<n;i++) {
      double d1=ret1[i]-m1,d2=ret2[i]-m2;
      covar+=d1*d2; v1+=d1*d1; v2+=d2*d2;
   }
   if(v1==0||v2==0) return 0;
   return covar/MathSqrt(v1*v2);
}

//+------------------------------------------------------------------+
void DrawDashboard() {
   int cols=6,rh=22,cw=115,pad=4;
   int tw=cols*cw+pad*2+20;
   int th=55+(g_symbolCount+2)*rh+pad*6;
   int sx=20,sy=30;
   int i=0;
   
   ObjectCreate(0,g_prefix+"bg",OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_XDISTANCE,sx-2);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_YDISTANCE,sy-2);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_XSIZE,tw+4);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_YSIZE,th+4);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,g_prefix+"bg",OBJPROP_FILL,true);
   
   int y=sy+5;
   SetLabel("TITLE",sx+5,y,"=== CORRELACOES "+InpMainSymbol+" ===",clrGold,InpFontSize+3,true);
   y+=26;
   
   string hdrs[]={"Ativo","Relacao","Preco","Var.Diaria","Correlacao","Sinal"};
   for(int c=0;c<cols;c++) SetLabel("H"+IntegerToString(c),sx+pad+c*cw,y,hdrs[c],clrWhite,InpFontSize,true);
   y+=rh;
   
   double mb=SymbolInfoDouble(InpMainSymbol,SYMBOL_BID),ma=SymbolInfoDouble(InpMainSymbol,SYMBOL_ASK);
   double mp=(mb+ma)/2.0,mc=0,mcp=0;
   MqlRates mr[2];
   if(CopyRates(InpMainSymbol,PERIOD_D1,0,2,mr)>=2){mc=mp-mr[0].open;mcp=(mc/mr[0].open)*100;}
   DrawRow(y,">>EURUSD","PRINCIPAL",mp,mc,mcp,1.0,true,rh,cw,sx,pad,"MAIN");
   y+=rh-2;
   SetLabel("SEP1",sx+pad,y,"------------------------------------------------------------",clrGray,InpFontSize-2,false);
   y+=rh-8;
   
   for(i=0;i<g_symbolCount;i++)
      DrawRow(y,g_symbols[i].label,g_symbols[i].relType,g_symbols[i].price,
              g_symbols[i].change,g_symbols[i].changePct,g_symbols[i].correlation,
              g_symbols[i].hasData,rh,cw,sx,pad,IntegerToString(i));
   y+=rh+4;
   
   SetLabel("LEG",sx+pad,y,"Corr: >+0.7=Forte Direta | >+0.4=Moderada | <0.3=Fraca | <-0.7=Forte Inversa",clrLightGray,InpFontSize-1,false);
   SetLabel("TS",sx+pad,y+14,"Atualizado: "+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),clrGray,InpFontSize-1,false);
}

//+------------------------------------------------------------------+
void DrawRow(int y,string label,string relType,double price,double change,
             double changePct,double corr,bool hasData,int rh,int cw,int sx,int pad,string uid) {
   int x=sx+pad;
   SetLabel("A_"+uid,x,y+2,label,clrWhite,InpFontSize,false); x+=cw;
   color rc=clrYellow;
   if(StringFind(relType,"Direta")>=0) rc=clrLimeGreen;
   else if(StringFind(relType,"Inversa")>=0) rc=clrCoral;
   else if(StringFind(relType,"Ouro")>=0||StringFind(relType,"Prata")>=0) rc=clrOrange;
   else if(StringFind(relType,"Index")>=0) rc=clrCyan;
   SetLabel("R_"+uid,x,y+2,relType,rc,InpFontSize-1,false); x+=cw;
   SetLabel("P_"+uid,x,y+2,hasData?DoubleToString(price,GetDig(label)):"---",clrWhite,InpFontSize,false); x+=cw;
   color cc=(change>=0)?clrLimeGreen:clrRed;
   SetLabel("V_"+uid,x,y+2,hasData?StringFormat("%+.5f (%.2f%%)",change,changePct):"---",cc,InpFontSize,false); x+=cw;
   color corc=clrGray;
   if(hasData){double ac=MathAbs(corr);if(ac>0.7)corc=(corr>0)?clrLime:clrRed;else if(ac>0.4)corc=(corr>0)?clrPaleGreen:clrCoral;else corc=clrYellow;}
   SetLabel("C_"+uid,x,y+2,hasData?StringFormat("%+.3f",corr):"---",corc,InpFontSize+1,true); x+=cw;
   string sig="---"; color sc=clrGray;
   if(hasData&&corr!=0){
      if(corr>0.5){sig="ALTA";sc=clrLime;}
      else if(corr<-0.5){sig="BAIXA";sc=clrRed;}
      else if(corr>0.3){sig="leve alta";sc=clrPaleGreen;}
      else if(corr<-0.3){sig="leve baixa";sc=clrCoral;}
      else{sig="neutro";sc=clrYellow;}
   }
   SetLabel("S_"+uid,x,y+2,sig,sc,InpFontSize,true);
}

//+------------------------------------------------------------------+
void SetLabel(string n,int x,int y,string txt,color cl,int sz,bool bd){
   string o=g_prefix+n;
   if(ObjectFind(0,o)<0) ObjectCreate(0,o,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,o,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,o,OBJPROP_COLOR,cl);
   ObjectSetInteger(0,o,OBJPROP_FONTSIZE,sz);
   ObjectSetString(0,o,OBJPROP_FONT,bd?"Consolas Bold":"Consolas");
   ObjectSetInteger(0,o,OBJPROP_BACK,false);
   ObjectSetInteger(0,o,OBJPROP_CORNER,0);
}

//+------------------------------------------------------------------+
int GetDig(string s){
   if(StringFind(s,"JPY")>=0) return 3;
   if(StringFind(s,"GOLD")>=0||StringFind(s,"XAU")>=0||StringFind(s,"500")>=0||
      StringFind(s,"NAS")>=0||StringFind(s,"DXY")>=0) return 2;
   if(StringFind(s,"SILVER")>=0||StringFind(s,"XAG")>=0) return 3;
   return 5;
}
double OnTester(){return 0;}
//+------------------------------------------------------------------+
