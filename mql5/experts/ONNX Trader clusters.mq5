#include <EURUSD ONNX include clusters.mqh>
#include <Trade\Trade.mqh>
#include <Trade\AccountInfo.mqh>

CTrade mytrade;
CPositionInfo myposition;

input bool Allow_Buy = true;
input bool Allow_Sell = true;
input double main_threshold = 0.5;
input double meta_threshold = 0.5;
sinput double   MaximumRisk=0.001;     //Progressive lot coefficient
sinput double   ManualLot=0;           //Fixed lot
sinput ulong     OrderMagic = 666;     //Orders magic
input int max_orders = 1;              //Orders number
input int stoploss = 2000;             //Stop loss
input int takeprofit = 2000;           //Take profit
input string comment = "The ONNX EA";

static datetime last_time = 0;
#define Ask SymbolInfoDouble(_Symbol, SYMBOL_ASK)
#define Bid SymbolInfoDouble(_Symbol, SYMBOL_BID)

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
const long  ExtInputShape [] = {1, ArraySize(Periods)};
const long  ExtInputShape2 [] = {1, ArraySize(Periods_m)};
long     ExtHandle = INVALID_HANDLE, ExtHandle2 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   mytrade.SetExpertMagicNumber(OrderMagic);
   ExtHandle = OnnxCreateFromBuffer(ExtModel, ONNX_DEFAULT);
   ExtHandle2 = OnnxCreateFromBuffer(ExtModel2, ONNX_DEFAULT);

   if(ExtHandle == INVALID_HANDLE || ExtHandle2 == INVALID_HANDLE)
     {
      Print("OnnxCreateFromBuffer error ", GetLastError());
      return(INIT_FAILED);
     }

   if(!OnnxSetInputShape(ExtHandle, 0, ExtInputShape))
     {
      Print("OnnxSetInputShape failed, error ", GetLastError());
      OnnxRelease(ExtHandle);
      return(-1);
     }

   if(!OnnxSetInputShape(ExtHandle2, 0, ExtInputShape2))
     {
      Print("OnnxSetInputShape failed, error ", GetLastError());
      OnnxRelease(ExtHandle2);
      return(-1);
     }

   const long output_shape[] = {1};
   if(!OnnxSetOutputShape(ExtHandle, 0, output_shape))
     {
      Print("OnnxSetOutputShape error ", GetLastError());
      return(INIT_FAILED);
     }
   if(!OnnxSetOutputShape(ExtHandle2, 0, output_shape))
     {
      Print("OnnxSetOutputShape error ", GetLastError());
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   OnnxRelease(ExtHandle);
   OnnxRelease(ExtHandle2);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!isNewBar())
      return;
   
   double features[], features_m[];
   fill_arays(features);
   fill_arays_m(features_m);

   double f[ArraySize(Periods)], f_m[ArraySize(Periods_m)];

   for(int i = 0; i < ArraySize(Periods); i++)
     {
      f[i] = features[i];
     }
     
    for(int i = 0; i < ArraySize(Periods_m); i++)
     {
      f_m[i] = features_m[i];
     }

   static vector out(1), out_meta(1);

   struct output
     {
      long           label[];
      float          tensor[];
     };

   output out2[], out2_meta[];

   OnnxRun(ExtHandle, ONNX_DEBUG_LOGS, f, out, out2);
   OnnxRun(ExtHandle2, ONNX_DEBUG_LOGS, f_m, out_meta, out2_meta);

   double sig = out2[0].tensor[1];
   double meta_sig = out2_meta[0].tensor[1];
   
   if(meta_sig > meta_threshold)
      if(countOrders() > 0)
         for(int b = PositionsTotal() - 1; b >= 0; b--)
            if(myposition.Select(_Symbol))
              {
               if(myposition.PositionType() == POSITION_TYPE_BUY && myposition.Magic() == OrderMagic && sig > main_threshold)
                  if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) < MathAbs(Bid - myposition.PriceOpen()))
                    {
                     int res = -1;
                     do
                       {
                        res = mytrade.PositionClose(_Symbol);
                        Sleep(50);
                       }
                     while(res == -1);
                    }
               if(myposition.PositionType() == POSITION_TYPE_SELL && myposition.Magic() == OrderMagic && sig < 1-main_threshold)
                  if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) < MathAbs(Bid - myposition.PriceOpen()))
                    {
                     int res = -1;
                     do
                       {
                        res = mytrade.PositionClose(_Symbol);
                        Sleep(50);
                       }
                     while(res == -1);
                    }
              }


   if(meta_sig > meta_threshold)
      if(countOrders() < max_orders && CheckMoneyForTrade(_Symbol, LotsOptimized(), ORDER_TYPE_BUY))
        {
         double l = LotsOptimized();
         if(sig < 1-main_threshold && Allow_Buy)
           {
            int res = -1;
            do
              {
               double stop = Bid - stoploss * _Point;
               double take = Ask + takeprofit * _Point;
               res = mytrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, l, Ask, stop, take, comment);
               Sleep(50);
              }
            while(res == -1);
           }
         else
           {
            if(sig > main_threshold && Allow_Sell)
              {
               int res = -1;
               do
                 {
                  double stop = Ask + stoploss * _Point;
                  double take = Bid - takeprofit * _Point;
                  res = mytrade.PositionOpen(_Symbol, ORDER_TYPE_SELL, l, Bid, stop, take, comment);
                  Sleep(50);
                 }
               while(res == -1);
              }
           }
        }

//---

  }

//+------------------------------------------------------------------+
double LotsOptimized()
  {
   double lot;

   if(MQLInfoInteger(MQL_OPTIMIZATION)==true)
     {
      lot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
      return lot;
     }
   CAccountInfo myaccount; SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);

   lot=NormalizeDouble(myaccount.FreeMargin()*MaximumRisk/1000.0,2);
   if(ManualLot!=0.0) lot=ManualLot;

   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);
   int ratio=(int)MathRound(lot/volume_step);
   if(MathAbs(ratio*volume_step-lot)>0.0000001)
      lot=ratio*volume_step;

   if(lot<SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN)) lot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(lot>SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX)) lot=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   return(lot);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int countOrders()
  {
   int result = 0;
   for(int k = PositionsTotal() - 1; k >= 0; k--)
     {

      if(PositionSelect(_Symbol) == true)
         if(myposition.Magic() == OrderMagic)
            result++;
     }
   return(result);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool isNewBar()
  {
   datetime lastbar_time = datetime(SeriesInfoInteger(Symbol(), PERIOD_CURRENT, SERIES_LASTBAR_DATE));
   if(last_time == 0)
     {
      last_time = lastbar_time;
      return(false);
     }
   if(last_time != lastbar_time)
     {
      last_time = lastbar_time;
      return(true);
     }
   return(false);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckMoneyForTrade(string symb, double lots, ENUM_ORDER_TYPE type)
  {
   MqlTick mqltick;
   SymbolInfoTick(symb, mqltick);
   double price = mqltick.ask;
   if(type == ORDER_TYPE_SELL)
      price = mqltick.bid;
   double margin, free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(!OrderCalcMargin(type, symb, lots, price, margin))
     {
      Print("Error in ", __FUNCTION__, " code=", GetLastError());
      return(false);
     }
   if(margin > free_margin)
     {
      Print("Not enough money for ", EnumToString(type), " ", lots, " ", symb, " Error code=", GetLastError());
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
