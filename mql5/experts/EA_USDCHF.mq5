//+------------------------------------------------------------------+
//|                                                EA_USDCHF.mq5      |
//|                     Expert Advisor USDCHF - TRIVIUM369            |
//|                        Especializado Grupo 2 (INVERSO!)           |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"
#property description "EA_USDCHF - Expert Especializado USDCHF"
#property description "LOGICA INVERSA! COMPRA quando EURUSD vende"
#property description "Herda EA_CORE com parametros USDCHF_PARAMS"
#property description "TRIVIUM369 (c) 2026 - Ronei Rosar + Pedrinho"

//+------------------------------------------------------------------+
//| IMPORTAR PARAMETROS GLOBAIS + USDCHF                             |
//+------------------------------------------------------------------+
#include <TRIVIUM369\COMMON_PARAMS.mqh>
#include <TRIVIUM369\USDCHF_PARAMS.mqh>

//+------------------------------------------------------------------+
//| INCLUIR ENGINE BASE (herda logica com INVERT_LOGIC ativo)        |
//+------------------------------------------------------------------+
#include "EA_CORE.mq5"
//+------------------------------------------------------------------+
