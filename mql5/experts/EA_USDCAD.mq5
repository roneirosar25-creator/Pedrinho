//+------------------------------------------------------------------+
//|                                                EA_USDCAD.mq5      |
//|                     Expert Advisor USDCAD - TRIVIUM369            |
//|                        Especializado Grupo 2 (INVERSO!)           |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"
#property description "EA_USDCAD - Expert Especializado USDCAD"
#property description "LOGICA INVERSA! COMPRA quando EURUSD vende"
#property description "Herda EA_CORE com parametros USDCAD_PARAMS"
#property description "TRIVIUM369 (c) 2026 - Ronei Rosar + Pedrinho"

//+------------------------------------------------------------------+
//| IMPORTAR PARAMETROS GLOBAIS + USDCAD                             |
//+------------------------------------------------------------------+
#include <TRIVIUM369\COMMON_PARAMS.mqh>
#include <TRIVIUM369\USDCAD_PARAMS.mqh>

//+------------------------------------------------------------------+
//| INCLUIR ENGINE BASE (herda logica com INVERT_LOGIC ativo)        |
//+------------------------------------------------------------------+
#include "EA_CORE.mq5"
//+------------------------------------------------------------------+
