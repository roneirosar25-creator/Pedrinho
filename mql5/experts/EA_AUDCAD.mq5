//+------------------------------------------------------------------+
//|                                                EA_AUDCAD.mq5      |
//|                     Expert Advisor AUDCAD - TRIVIUM369            |
//|                        Especializado Grupo 2 (INVERSO!)           |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property version   "1.00"
#property description "EA_AUDCAD - Expert Especializado AUDCAD"
#property description "LOGICA INVERSA! COMPRA quando EURUSD vende"
#property description "Herda EA_CORE com parametros AUDCAD_PARAMS"
#property description "TRIVIUM369 (c) 2026 - Ronei Rosar + Pedrinho"

//+------------------------------------------------------------------+
//| IMPORTAR PARAMETROS GLOBAIS + AUDCAD                             |
//+------------------------------------------------------------------+
#include <TRIVIUM369\COMMON_PARAMS.mqh>
#include <TRIVIUM369\AUDCAD_PARAMS.mqh>

//+------------------------------------------------------------------+
//| INCLUIR ENGINE BASE (herda logica com INVERT_LOGIC ativo)        |
//+------------------------------------------------------------------+
#include "EA_CORE.mq5"
//+------------------------------------------------------------------+
