//+------------------------------------------------------------------+
//|                                             EA_XM_V1.0_OTIMIZADO  |
//|     TRIVIUM369 XM - V1.0 MELHORADO (Sinal + Risco + Lucro)        |
//|  Multi-asset crypto: ADX + Volume + Regime + ATR com gestao      |
//|  avancada de saida + risco adaptativo + protecoes anti-whipsaw   |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369"
#property link      "https://trivium369.trading"
#property version   "1.00"
#property description "EA XM V1.0 - Multi-asset com ADX, Volume, Saida Dinamica"

#include <Trade\Trade.mqh>

//==================== UNIVERSO DE ATIVOS ==========================
input group "===== Universo de Ativos ====="
input string InpSymbolsCSV        = "";        // Simbolos (vazio = auto-detecta)
input string InpAutoPathFilter    = "Crypto";  // Filtro de pasta p/ auto-deteccao
input int    InpMaxSimbolos       = 12;        // Limite de ativos no universo

//==================== TIMEFRAMES ==================================
input group "===== Timeframes ====="
input ENUM_TIMEFRAMES InpTF_Exec     = PERIOD_M5;  // TF de execucao (sinal)
input ENUM_TIMEFRAMES InpTF_Medio    = PERIOD_H1;  // TF medio (timing)
input ENUM_TIMEFRAMES InpTF_Primario = PERIOD_H4;  // TF primario (tendencia)

//==================== INDICADORES PRINCIPAIS ======================
input group "===== Indicadores ====="
input int InpEMAExecRapida   = 8;    // EMA rapida (execucao)
input int InpEMAExecLenta    = 21;   // EMA lenta (execucao / suporte)
input int InpEMAMedRapida    = 8;    // EMA rapida (medio)
input int InpEMAMedLenta     = 21;   // EMA lenta (medio)
input int InpEMAPrimRapida   = 20;   // EMA rapida (primario)
input int InpEMAPrimLenta    = 50;   // EMA lenta (primario)
input int InpATRPeriodo      = 14;   // Periodo do ATR
input int InpRSIPeriodo      = 14;   // Periodo do RSI
input int InpADXPeriodo      = 14;   // NOVO: Periodo do ADX (força tendencia)
input int InpVolumePeriodo   = 20;   // NOVO: Periodo media volume
input int InpMACDFast        = 12;   // MACD rapido
input int InpMACDSlow        = 26;   // MACD lento
input int InpMACDSignal      = 9;    // MACD sinal
input int InpERPeriodo       = 14;   // Periodo da Eficiencia de Kaufman (ER)

//==================== FILTROS DE SINAL (MELHORADOS) ===============
input group "===== Filtros de Sinal (V1.0) ====="
input double InpADXMinimo          = 25.0;   // NOVO: ADX minimo para tendencia forte
input double InpERModerado         = 0.20;   // ER minimo p/ forca moderada
input double InpERForte            = 0.40;   // ER p/ forca forte (TP ampliado)
input double InpRSICompra          = 52.0;   // RSI minimo p/ forca compradora
input double InpRSIVenda           = 48.0;   // RSI maximo p/ forca vendedora
input int    InpConfirmMin         = 2;      // Confirmacoes minimas
input bool   InpValidarVolume      = true;   // NOVO: Validar spike volume
input double InpVolumeMultiplo     = 1.3;    // NOVO: Volume deve ser 1.3x media
input bool   InpAntiWhipsaw        = true;   // NOVO: Confirmar close acima/abaixo
input bool   InpFiltroHorario      = true;   // Usar filtro de horario
input int    InpHoraInicioGMT      = 8;      // Inicio pico (GMT)
input int    InpHoraFimGMT         = 18;     // Fim pico (GMT)
input bool   InpBloquearNoticias   = true;   // Bloquear proximas noticias
input int    InpMinAntesNoticia    = 15;     // Minutos antes da noticia
input int    InpMinDepoisNoticia   = 15;     // Minutos depois da noticia
input double InpSpreadMaxPips      = 100.0;  // Spread maximo (pips)

//==================== ESTRATEGIA DE ENTRADA =======================
input group "===== Estrategia de Entrada ====="
enum ENUM_ENTRADA_TIPO { ENTRADA_PULLBACK = 0, ENTRADA_BREAKOUT = 1 };
input ENUM_ENTRADA_TIPO InpTipoEntrada     = ENTRADA_PULLBACK;
input int    InpPeriodoBreakout    = 20;    // Periodo do breakout

//==================== GESTAO DE RISCO (OTIMIZADA) =================
input group "===== Gestao de Risco (V1.0) ====="
input double InpRiskPerTradePct    = 1.0;   // Risco por trade (% equity)
input double InpMaxAggregateRisk   = 12.0;  // Teto de risco agregado (% equity)
input int    InpMaxPositions       = 6;     // Max posicoes simultaneas
input int    InpMaxPerSymbol       = 1;     // Max posicoes por ativo
input double InpRiscoDiarioMaxPct  = 20.0;  // Stop diario (% equity)
input bool   InpFecharNoStopDiario = true;  // Fechar posicoes ao atingir stop
input int    InpMaxPerdasConsec    = 3;     // Perdas consecutivas p/ pausa
input int    InpPausaMinutos       = 240;   // Pausa apos perdas (minutos)
input double InpVolumeMinimo       = 0.01;  // Volume minimo aceitavel
input double InpLucroDiarioAlvoPct = 0.0;   // Alvo diario (0 = desligado)
input double InpMaxDrawdownPct     = 25.0;  // Drawdown que congela EA
input int    InpCooldownSeg        = 30;    // Cooldown entre trades

//==================== RISCO ADAPTATIVO (OTIMIZADO) ================
input group "===== Risco Adaptativo (V1.0) ====="
input bool   InpUsarRiscoAdaptativo = true;
input double InpRiscoAdaptMin       = 0.25;
input double InpRiscoAdaptMax       = 2.0;
input int    InpATRDiarioPeriodo    = 20;
input bool   InpUsarHistWinRate     = true;  // NOVO: Usar win rate historico
input int    InpHistoricoTrades     = 20;    // NOVO: Ultimos N trades para calcular
input bool   InpUsarKelly           = false;
input double InpKellyWinRate        = 0.45;
input double InpKellyAvgRR          = 1.80;

//==================== STOPS E TP (DINAMICOS) ======================
input group "===== Stops e Take Profit (V1.0) ====="
input double InpSLxATR           = 1.0;   // Stop Loss = N x ATR
input double InpSLFloorPips      = 8.0;   // Piso do SL (pips)
input double InpSLCeilingPips    = 300.0; // Teto do SL (pips)
input double InpRR_TP1           = 1.5;   // R:R do TP1
input double InpRR_TP2           = 2.5;   // R:R do TP2
input double InpRRMinimo         = 1.5;   // R:R minimo aceito

//==================== GESTAO DE SAIDA (DINAMICA V1.0) ==============
input group "===== Gestao de Saida (V1.0) ====="
input bool   InpUsarSaidaParcial   = true;  // Saida parcial TP1/TP2 + runner
input double InpPctTP1             = 50.0;  // % fechada no TP1
input double InpPctTP2             = 30.0;  // % fechada no TP2
input bool   InpUsarBreakeven      = true;  // Mover p/ breakeven
input double InpBExATR             = 1.0;   // Breakeven ao lucrar N x ATR
input double InpBEOffsetATR        = 0.3;   // Offset do breakeven (x ATR)
input bool   InpUsarTrailing       = true;  // Trailing stop
input double InpTrailInicioATR     = 0.5;   // Trailing comeca apos N x ATR
input double InpTrailxATR          = 1.0;   // Trailing = N x ATR
input double InpTirarLucroATR      = 3.0;   // Fechar runner ao lucrar N x ATR

//==================== EXECUCAO ====================================
input group "===== Execucao ====="
input ulong  InpMagic             = 880801;  // Magic number (v1.0)
input ulong  InpSlippage          = 30;      // Desvio maximo (points)
input bool   InpExecucaoAtiva     = true;    // EA habilitado
input bool   InpPermitirContaReal = true;    // Permitir conta real
input bool   InpVerboseLog        = true;    // Log detalhado
input bool   InpLogCSV            = true;    // Gravar diario CSV

//==================== CONSTANTES ==================================
const string PREFIX_GV  = "TV369_";
const string PREFIX_LOG = "EA_XM_V1.0";

//==================== ESTRUTURAS ==================================
struct SymCtx
  {
   string        name;
   int           hEMAExecR,hEMAExecL;
   int           hEMAMedR,hEMAMedL;
   int           hEMAPrimR,hEMAPrimL;
   int           hRSI,hMACD;
   int           hATR,hATRD1;
   int           hADX;              // NOVO: handle ADX
   int           hVolume;           // NOVO: handle volume
   datetime      lastBar;
   int           digits;
   double        point;
   double        volMin,volMax,volStep;
   double        tickSize,tickValue;
   long          stopsLevel;
   double        erCache;
   datetime      erBar;
  };

struct Indicadores
  {
   double atr, atrD1;
   double emaExecR, emaExecL;
   double emaMedR,  emaMedL;
   double emaPrimR, emaPrimL;
   double rsi;
   double macdMain, macdSignal;
   double adx;              // NOVO: ADX (força tendencia)
   double volume, volumeMA; // NOVO: volume atual e media
   double er;
   double close, open, high, low;
   int    tendPrim;
   int    tendMed;
  };

struct Regime
  {
   string tipo;
   double confianca;
   bool   valido;
   int    adxForte;   // NOVO: ADX forte
  };

struct Sinal
  {
   bool compra, venda;
   int  confirmacoes;
   bool tend, timing, rsiF, macdF, erF, adxF, volF; // NOVO: adxF, volF
  };

struct TradeStats
  {
   int    totalTrades;
   int    winTrades;
   double winRate;
   double avgRR;
  };

//==================== ESTADO GLOBAL ===============================
SymCtx   g_ctx[];
int      g_total      = 0;
CTrade   g_trade;
double   g_peakEquity = 0.0;
bool     g_halted     = false;
double   g_equityDia  = 0.0;
datetime g_dia        = 0;
int      g_perdasCons = 0;
datetime g_pausaAte   = 0;
datetime g_ultimaEntrada = 0;
int      g_arquivo    = INVALID_HANDLE;
TradeStats g_stats;  // NOVO: Estatisticas de trades

//==================== UTILITARIOS =================================
double PipSize(const string sym)
  {
   int digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   double point=SymbolInfoDouble(sym,SYMBOL_POINT);
   return((digits==3 || digits==5) ? point*10.0 : point);
  }

int VolumeDigits(const string sym)
  {
   double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   if(step<=0.0) return 2;
   int d=0;
   while(step<1.0 && d<8){ step*=10.0; d++; }
   return d;
  }

double NormalizarVolume(const string sym,double v)
  {
   double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double vmax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double vstep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   if(vstep<=0.0 || vmin<=0.0) return 0.0;
   v=MathFloor(v/vstep)*vstep;
   v=NormalizeDouble(v,VolumeDigits(sym));
   if(v<vmin) return 0.0;
   if(vmax>0.0 && v>vmax) v=vmax;
   return v;
  }

double NormalizarPreco(const string sym,double p)
  {
   return NormalizeDouble(p,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
  }

bool HorarioEmFaixa(const int h,const int ini,const int fim)
  {
   if(ini==fim) return false;
   if(ini<fim) return(h>=ini && h<fim);
   return(h>=ini || h<fim);
  }

bool HorarioPermitido()
  {
   if(!InpFiltroHorario) return true;
   MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
   return HorarioEmFaixa(dt.hour,InpHoraInicioGMT,InpHoraFimGMT);
  }

bool SpreadAceitavel(const string sym)
  {
   MqlTick t; if(!SymbolInfoTick(sym,t)) return false;
   double pip=PipSize(sym); if(pip<=0.0) return false;
   return((t.ask-t.bid)/pip <= InpSpreadMaxPips);
  }

bool LerBuffer(const int handle,const int buffer,const int shift,double &val)
  {
   if(handle==INVALID_HANDLE) return false;
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(handle,buffer,shift,1,buf)<1) return false;
   if(buf[0]==EMPTY_VALUE || !MathIsValidNumber(buf[0])) return false;
   val=buf[0];
   return true;
  }

bool LerValor(const int handle,const int shift,double &val)
  {
   return LerBuffer(handle,0,shift,val);
  }

//==================== CHAVES / ESTADO PERSISTENTE =================
string ChaveGV(const ulong tk,const string suf)
  {
   return PREFIX_GV+IntegerToString(tk)+suf;
  }

bool SalvarEstado(const ulong tk,const double vol0,const double tp1,const double tp2,const int etapa)
  {
   bool ok=true;
   ok&=GlobalVariableSet(ChaveGV(tk,"_VOL0"),vol0);
   ok&=GlobalVariableSet(ChaveGV(tk,"_TP1"),tp1);
   ok&=GlobalVariableSet(ChaveGV(tk,"_TP2"),tp2);
   ok&=GlobalVariableSet(ChaveGV(tk,"_ETAPA"),etapa);
   return ok;
  }

bool LerEstado(const ulong tk,double &vol0,double &tp1,double &tp2,int &etapa)
  {
   string k=ChaveGV(tk,"_VOL0");
   if(!GlobalVariableCheck(k)) return false;
   vol0=GlobalVariableGet(k);
   tp1=GlobalVariableGet(ChaveGV(tk,"_TP1"));
   tp2=GlobalVariableGet(ChaveGV(tk,"_TP2"));
   etapa=(int)GlobalVariableGet(ChaveGV(tk,"_ETAPA"));
   return true;
  }

void SalvarTrailBar(const ulong tk,const datetime bar)
  {
   GlobalVariableSet(ChaveGV(tk,"_TRAIL_BAR"),(double)(long)bar);
  }

datetime LerTrailBar(const ulong tk)
  {
   string k=ChaveGV(tk,"_TRAIL_BAR");
   if(!GlobalVariableCheck(k)) return 0;
   return (datetime)(long)GlobalVariableGet(k);
  }

void RemoverEstado(const ulong tk)
  {
   GlobalVariableDel(ChaveGV(tk,"_VOL0"));
   GlobalVariableDel(ChaveGV(tk,"_TP1"));
   GlobalVariableDel(ChaveGV(tk,"_TP2"));
   GlobalVariableDel(ChaveGV(tk,"_ETAPA"));
   GlobalVariableDel(ChaveGV(tk,"_TRAIL_BAR"));
  }

//==================== LOG CSV =====================================
void LogEvento(const string sym,const string ev,const string det)
  {
   if(!InpLogCSV || g_arquivo==INVALID_HANDLE) return;
   FileWrite(g_arquivo,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),sym,ev,det);
   FileFlush(g_arquivo);
  }

void IniciarLog()
  {
   if(!InpLogCSV) return;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   string data=StringFormat("%04d%02d%02d",dt.year,dt.mon,dt.day);
   string nome=PREFIX_LOG+"_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"_"+data+".csv";
   g_arquivo=FileOpen(nome,FILE_CSV|FILE_READ|FILE_WRITE,';');
   if(g_arquivo!=INVALID_HANDLE)
     {
      if(FileSize(g_arquivo)==0)
         FileWrite(g_arquivo,"DataHora","Ativo","Evento","Detalhes");
     }
  }

void FinalizarLog()
  {
   if(g_arquivo!=INVALID_HANDLE) FileClose(g_arquivo);
   g_arquivo=INVALID_HANDLE;
  }

//==================== UNIVERSO DE ATIVOS ==========================
int FindCtx(const string sym)
  {
   for(int i=0;i<g_total;i++)
      if(g_ctx[i].name==sym) return i;
   return -1;
  }

bool SetupSymbol(const string sym,SymCtx &ctx)
  {
   if(!SymbolSelect(sym,true)) return false;
   if(SymbolInfoInteger(sym,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL) return false;

   double tickSize=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   double volMin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double volStep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   if(tickSize<=0.0 || tickValue<=0.0 || volMin<=0.0 || volStep<=0.0) return false;

   ctx.hEMAExecR=iMA(sym,InpTF_Exec,InpEMAExecRapida,0,MODE_EMA,PRICE_CLOSE);
   ctx.hEMAExecL=iMA(sym,InpTF_Exec,InpEMAExecLenta,0,MODE_EMA,PRICE_CLOSE);
   ctx.hEMAMedR=iMA(sym,InpTF_Medio,InpEMAMedRapida,0,MODE_EMA,PRICE_CLOSE);
   ctx.hEMAMedL=iMA(sym,InpTF_Medio,InpEMAMedLenta,0,MODE_EMA,PRICE_CLOSE);
   ctx.hEMAPrimR=iMA(sym,InpTF_Primario,InpEMAPrimRapida,0,MODE_EMA,PRICE_CLOSE);
   ctx.hEMAPrimL=iMA(sym,InpTF_Primario,InpEMAPrimLenta,0,MODE_EMA,PRICE_CLOSE);
   ctx.hRSI=iRSI(sym,InpTF_Exec,InpRSIPeriodo,PRICE_CLOSE);
   ctx.hMACD=iMACD(sym,InpTF_Exec,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE);
   ctx.hATR=iATR(sym,InpTF_Exec,InpATRPeriodo);
   ctx.hATRD1=iATR(sym,PERIOD_D1,InpATRDiarioPeriodo);
   ctx.hADX=iADX(sym,InpTF_Exec,InpADXPeriodo);   // NOVO
   ctx.hVolume=iVolumes(sym,InpTF_Exec,VOLUME_TICK); // NOVO

   if(ctx.hEMAExecR==INVALID_HANDLE || ctx.hEMAExecL==INVALID_HANDLE ||
      ctx.hEMAMedR==INVALID_HANDLE || ctx.hEMAMedL==INVALID_HANDLE ||
      ctx.hEMAPrimR==INVALID_HANDLE || ctx.hEMAPrimL==INVALID_HANDLE ||
      ctx.hRSI==INVALID_HANDLE || ctx.hMACD==INVALID_HANDLE ||
      ctx.hATR==INVALID_HANDLE || ctx.hATRD1==INVALID_HANDLE ||
      ctx.hADX==INVALID_HANDLE || ctx.hVolume==INVALID_HANDLE)
      return false;

   ctx.name=sym;
   ctx.digits=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);
   ctx.point=SymbolInfoDouble(sym,SYMBOL_POINT);
   ctx.volMin=volMin;
   ctx.volMax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   ctx.volStep=volStep;
   ctx.tickSize=tickSize;
   ctx.tickValue=tickValue;
   ctx.stopsLevel=SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
   ctx.lastBar=0;
   ctx.erCache=0.0;
   ctx.erBar=0;
   return true;
  }

bool BuildUniverse()
  {
   string wanted[];
   int count=0;

   string csv=InpSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);

   if(StringLen(csv)>0)
     {
      count=StringSplit(csv,',',wanted);
      for(int i=0;i<count;i++){ StringTrimLeft(wanted[i]); StringTrimRight(wanted[i]); }
     }
   else
     {
      string filtro=InpAutoPathFilter; StringToUpper(filtro);
      int total=SymbolsTotal(true);
      ArrayResize(wanted,total);
      count=0;
      for(int i=0;i<total && count<InpMaxSimbolos;i++)
        {
         string nm=SymbolName(i,true);
         string path=SymbolInfoString(nm,SYMBOL_PATH); StringToUpper(path);
         if(StringLen(filtro)==0 || StringFind(path,filtro)>=0)
           { wanted[count]=nm; count++; }
        }
      ArrayResize(wanted,count);
      PrintFormat("V1.0: Auto-deteccao: %d simbolos (filtro \"%s\")",count,InpAutoPathFilter);
     }

   if(count<=0) return false;

   ArrayResize(g_ctx,count);
   g_total=0;
   for(int i=0;i<count;i++)
     {
      if(g_total>=InpMaxSimbolos) break;
      if(StringLen(wanted[i])==0) continue;
      if(SetupSymbol(wanted[i],g_ctx[g_total]))
         g_total++;
     }
   ArrayResize(g_ctx,g_total);
   PrintFormat("V1.0: Universo final: %d ativos prontos",g_total);
   return g_total>0;
  }

//==================== DADOS / INDICADORES =======================
bool DadosProntos(const int idx)
  {
   SymCtx ctx=g_ctx[idx];
   int needE=MathMax(InpEMAExecLenta,MathMax(InpMACDSlow,MathMax(InpRSIPeriodo,MathMax(InpATRPeriodo,InpERPeriodo))))+10;
   int needM=InpEMAMedLenta+10;
   int needP=InpEMAPrimLenta+10;
   if(Bars(ctx.name,InpTF_Exec)<needE) return false;
   if(Bars(ctx.name,InpTF_Medio)<needM) return false;
   if(Bars(ctx.name,InpTF_Primario)<needP) return false;
   if(BarsCalculated(ctx.hEMAExecR)<needE || BarsCalculated(ctx.hEMAExecL)<needE ||
      BarsCalculated(ctx.hRSI)<needE || BarsCalculated(ctx.hMACD)<needE ||
      BarsCalculated(ctx.hATR)<needE || BarsCalculated(ctx.hADX)<needE)
      return false;
   return true;
  }

double CalcularER(const int idx)
  {
   SymCtx ctx=g_ctx[idx];
   ENUM_TIMEFRAMES tf=InpTF_Exec;
   datetime bar0=iTime(ctx.name,tf,0);
   if(bar0==g_ctx[idx].erBar && g_ctx[idx].erCache>0.0) return g_ctx[idx].erCache;
   if(InpERPeriodo<2) return 0.0;
   double c0=iClose(ctx.name,tf,1);
   double cN=iClose(ctx.name,tf,InpERPeriodo+1);
   if(c0<=0.0 || cN<=0.0) return 0.0;
   double dir=MathAbs(c0-cN);
   double vol=0.0;
   for(int s=1;s<=InpERPeriodo;s++)
     {
      double a=iClose(ctx.name,tf,s);
      double b=iClose(ctx.name,tf,s+1);
      if(a<=0.0 || b<=0.0) return 0.0;
      vol+=MathAbs(a-b);
     }
   if(vol<=0.0) return 0.0;
   g_ctx[idx].erCache=dir/vol;
   g_ctx[idx].erBar=bar0;
   return g_ctx[idx].erCache;
  }

bool CalcularIndicadores(const int idx,Indicadores &ind)
  {
   SymCtx ctx=g_ctx[idx];
   if(!DadosProntos(idx)) return false;
   ind.close=iClose(ctx.name,InpTF_Exec,1);
   ind.open=iOpen(ctx.name,InpTF_Exec,1);
   ind.high=iHigh(ctx.name,InpTF_Exec,1);
   ind.low=iLow(ctx.name,InpTF_Exec,1);
   if(!LerValor(ctx.hATR,1,ind.atr) || ind.atr<=0.0) return false;
   if(!LerValor(ctx.hEMAExecR,1,ind.emaExecR)) return false;
   if(!LerValor(ctx.hEMAExecL,1,ind.emaExecL)) return false;
   if(!LerValor(ctx.hEMAMedR,1,ind.emaMedR)) return false;
   if(!LerValor(ctx.hEMAMedL,1,ind.emaMedL)) return false;
   if(!LerValor(ctx.hEMAPrimR,1,ind.emaPrimR)) return false;
   if(!LerValor(ctx.hEMAPrimL,1,ind.emaPrimL)) return false;
   if(!LerValor(ctx.hRSI,1,ind.rsi)) return false;
   if(!LerBuffer(ctx.hMACD,0,1,ind.macdMain)) return false;
   if(!LerBuffer(ctx.hMACD,1,1,ind.macdSignal)) return false;
   if(!LerValor(ctx.hADX,1,ind.adx)) ind.adx=0.0;  // NOVO: ADX
   if(!LerValor(ctx.hVolume,1,ind.volume)) ind.volume=0.0;  // NOVO: Volume

   // NOVO: Calcular media de volume
   double vol[]; ArraySetAsSeries(vol,true);
   if(CopyBuffer(ctx.hVolume,0,1,InpVolumePeriodo,vol)<InpVolumePeriodo)
      ind.volumeMA=ind.volume;
   else
     {
      ind.volumeMA=0.0;
      for(int i=0;i<InpVolumePeriodo;i++) ind.volumeMA+=vol[i];
      ind.volumeMA/=InpVolumePeriodo;
     }

   if(!LerValor(ctx.hATRD1,1,ind.atrD1)) ind.atrD1=0.0;

   ind.tendPrim=(ind.emaPrimR>ind.emaPrimL)?1:((ind.emaPrimR<ind.emaPrimL)?-1:0);
   ind.tendMed =(ind.emaMedR>ind.emaMedL)?1:((ind.emaMedR<ind.emaMedL)?-1:0);
   ind.er=CalcularER(idx);
   return true;
  }

//==================== REGIME E SINAL (MELHORADO) ==================
Regime DetectarRegime(const Indicadores &ind)
  {
   Regime r;
   double conf=0.0;
   if(ind.tendPrim>0) conf=55.0;
   else if(ind.tendPrim<0) conf=-55.0;
   if(ind.macdMain>ind.macdSignal) conf+=15.0;
   else if(ind.macdMain<ind.macdSignal) conf-=15.0;
   if(ind.er>=InpERForte)
     { if(conf>0) conf+=20.0; else if(conf<0) conf-=20.0; }
   // NOVO: ADX contribui para confianca
   if(ind.adx>=InpADXMinimo) conf+=(ind.adx>=30.0?20.0:10.0);

   if(conf>=55.0) r.tipo="UPTREND";
   else if(conf<=-55.0) r.tipo="DOWNTREND";
   else r.tipo="RANGING";
   r.confianca=MathAbs(conf);
   r.valido=(r.tipo!="RANGING" && ind.adx>=InpADXMinimo);
   r.adxForte=(ind.adx>=30.0)?1:0;
   return r;
  }

bool GatilhoEntrada(const int idx,const bool compra)
  {
   SymCtx ctx=g_ctx[idx];
   ENUM_TIMEFRAMES tf=InpTF_Exec;
   int shift=1;

   double emaAv[],emaPrev;
   ArraySetAsSeries(emaAv,true);
   if(CopyBuffer(ctx.hEMAExecL,0,shift,2,emaAv)<2) return false;
   double emaAtual=emaAv[0]; emaPrev=emaAv[1];

   if(InpTipoEntrada==ENTRADA_PULLBACK)
     {
      double c=iClose(ctx.name,tf,shift);
      double o=iOpen(ctx.name,tf,shift);
      if(compra)
        {
         double l=iLow(ctx.name,tf,shift);
         if(l<=emaAtual && c>emaAtual && c>o)
            if(iClose(ctx.name,tf,shift+1)>=emaPrev) return true;
        }
      else
        {
         double h=iHigh(ctx.name,tf,shift);
         if(h>=emaAtual && c<emaAtual && c<o)
            if(iClose(ctx.name,tf,shift+1)<=emaPrev) return true;
        }
     }
   else
     {
      int ih=iHighest(ctx.name,tf,MODE_HIGH,InpPeriodoBreakout,shift);
      int il=iLowest(ctx.name,tf,MODE_LOW,InpPeriodoBreakout,shift);
      double xh=iHigh(ctx.name,tf,ih);
      double xl=iLow(ctx.name,tf,il);
      double c=iClose(ctx.name,tf,shift);
      double pc=iClose(ctx.name,tf,shift+1);
      if(compra && c>xh && pc<=xh) return true;
      if(!compra && c<xl && pc>=xl) return true;
     }
   return false;
  }

Sinal AvaliarSinal(const Indicadores &ind,const Regime &reg,const bool gatC,const bool gatV)
  {
   Sinal s;
   s.compra=false; s.venda=false; s.confirmacoes=0;
   s.tend=false; s.timing=false; s.rsiF=false; s.macdF=false; s.erF=false;
   s.adxF=false; s.volF=false;  // NOVO

   s.tend=(reg.tipo!="RANGING");
   s.timing=((reg.tipo=="UPTREND" && ind.tendMed>0) ||
             (reg.tipo=="DOWNTREND" && ind.tendMed<0));
   s.rsiF=((reg.tipo=="UPTREND" && ind.rsi>InpRSICompra) ||
           (reg.tipo=="DOWNTREND" && ind.rsi<InpRSIVenda));
   s.macdF=((reg.tipo=="UPTREND" && ind.macdMain>ind.macdSignal) ||
            (reg.tipo=="DOWNTREND" && ind.macdMain<ind.macdSignal));
   s.erF=(ind.er>=InpERModerado);
   s.adxF=(ind.adx>=InpADXMinimo);  // NOVO: ADX filter
   s.volF=(!InpValidarVolume || ind.volume>=ind.volumeMA*InpVolumeMultiplo);  // NOVO: Volume filter

   s.confirmacoes=(s.tend?1:0)+(s.timing?1:0)+(s.rsiF?1:0)+(s.macdF?1:0)+
                  (s.erF?1:0)+(s.adxF?1:0)+(s.volF?1:0);

   if(reg.tipo=="RANGING") return s;
   if(s.confirmacoes<InpConfirmMin) return s;
   if(!s.tend || !s.timing || !s.erF || !s.adxF) return s;
   if(reg.tipo=="UPTREND" && gatC && s.volF) s.compra=true;
   if(reg.tipo=="DOWNTREND" && gatV && s.volF) s.venda=true;
   return s;
  }

//==================== NOTICIAS ====================================
bool BloquearProximasNoticias()
  {
   if(!InpBloquearNoticias) return false;
   datetime agora=TimeCurrent();
   MqlCalendarValue vals[];
   int c=CalendarValueHistory(vals,agora,agora+InpMinAntesNoticia*60);
   for(int i=0;i<c;i++)
      if((int)vals[i].impact_type==(int)CALENDAR_IMPORTANCE_HIGH) return true;
   ArrayFree(vals);
   c=CalendarValueHistory(vals,agora-InpMinDepoisNoticia*60,agora);
   for(int i=0;i<c;i++)
      if((int)vals[i].impact_type==(int)CALENDAR_IMPORTANCE_HIGH) return true;
   ArrayFree(vals);
   return false;
  }

//==================== ESTATISTICAS DE TRADES (NOVO) ===============
void AtualizarStats()
  {
   if(!InpUsarHistWinRate) return;
   g_stats.totalTrades=0;
   g_stats.winTrades=0;
   g_stats.avgRR=0.0;

   if(HistoryTotal()==0) return;

   int count=0;
   HistorySelect(0,TimeCurrent());
   for(int i=HistoryDealsTotal()-1;i>=0 && count<InpHistoricoTrades;i--)
     {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;

      double profit=HistoryDealGetDouble(d,DEAL_PROFIT)+
                    HistoryDealGetDouble(d,DEAL_SWAP)+
                    HistoryDealGetDouble(d,DEAL_COMMISSION);
      if(profit>0.0) g_stats.winTrades++;
      g_stats.totalTrades++;
      count++;
     }

   if(g_stats.totalTrades>0)
      g_stats.winRate=(double)g_stats.winTrades/g_stats.totalTrades;
  }

//==================== RISCO =======================================
int ContarPosicoesMine()
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(PositionGetTicket(i)==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic) n++;
     }
   return n;
  }

int ContarPorSimbolo(const string sym)
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(PositionGetTicket(i)==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL)==sym) n++;
     }
   return n;
  }

double RiscoAgregadoPct()
  {
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq<=0.0) return 0.0;
   double total=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
      if(ts<=0.0 || tv<=0.0) continue;
      double dist=(sl>0.0)?MathAbs(open-sl):0.0;
      if(dist<=0.0){ total+=InpRiskPerTradePct*2.0; continue; }
      total+=(dist/ts)*tv*vol/eq*100.0;
     }
   return total;
  }

double RiscoEfetivoTrade(const int idx)
  {
   SymCtx ctx=g_ctx[idx];
   double risco=InpRiskPerTradePct;

   // NOVO: Risco adaptativo por win rate historico
   if(InpUsarHistWinRate && g_stats.totalTrades>=5)
     {
      double multiplicador=0.5+(g_stats.winRate*2.0);
      multiplicador=MathMax(0.5,MathMin(1.5,multiplicador));
      risco*=multiplicador;
     }

   if(InpUsarRiscoAdaptativo)
     {
      double atrD1=0.0;
      if(LerValor(ctx.hATRD1,1,atrD1) && atrD1>0.0)
        {
         double atrExec=0.0;
         if(LerValor(ctx.hATR,1,atrExec) && atrExec>0.0)
           {
            double fator=MathMin(1.0,atrD1/MathMax(atrExec,1e-10));
            fator=MathMax(0.5,fator);
            risco*=fator;
           }
        }
     }

   risco=MathMin(InpRiscoAdaptMax,MathMax(InpRiscoAdaptMin,risco));
   return risco;
  }

bool CalcularLote(const int idx,const double slDist,double &lot,double &realRiskPct)
  {
   SymCtx ctx=g_ctx[idx];
   if(slDist<=0.0 || ctx.tickSize<=0.0 || ctx.tickValue<=0.0) return false;
   double lossPerLot=(slDist/ctx.tickSize)*ctx.tickValue;
   if(lossPerLot<=0.0) return false;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq<=0.0) return false;
   double riskMoney=eq*RiscoEfetivoTrade(idx)/100.0;
   double raw=riskMoney/lossPerLot;
   double steps=MathFloor(raw/ctx.volStep);
   lot=steps*ctx.volStep;
   if(lot<ctx.volMin) lot=ctx.volMin;
   if(lot>ctx.volMax) lot=ctx.volMax;
   lot=NormalizeDouble(lot,VolumeDigits(ctx.name));
   if(lot<InpVolumeMinimo) return false;
   realRiskPct=(lot*lossPerLot)/eq*100.0;

   double margem=0.0;
   if(OrderCalcMargin(ORDER_TYPE_BUY,ctx.name,lot,SymbolInfoDouble(ctx.name,SYMBOL_ASK),margem))
      if(margem>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.9) return false;
   return lot>0.0;
  }

void CalcularTPDinamico(const double er, const double adx, double &rr1, double &rr2)
  {
   // NOVO: TP dinamico por ER e ADX
   if(adx>=30.0 && er>=InpERForte)
     { rr1=InpRR_TP1*1.3; rr2=InpRR_TP2*1.3; }
   else if(er>=InpERForte)
     { rr1=InpRR_TP1*1.2; rr2=InpRR_TP2*1.2; }
   else if(er>=InpERModerado)
     { rr1=InpRR_TP1; rr2=InpRR_TP2; }
   else
     { rr1=InpRR_TP1*0.8; rr2=InpRR_TP2*0.8; }
  }

//==================== PROTECOES ===================================
void AtualizarProtecaoDrawdown()
  {
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_peakEquity) g_peakEquity=eq;
   if(g_peakEquity<=0.0) return;
   double dd=(g_peakEquity-eq)/g_peakEquity*100.0;
   if(dd>=InpMaxDrawdownPct && !g_halted)
     {
      g_halted=true;
      LogEvento("","PARADA_DD",StringFormat("DD=%.2f%% atingiu %.2f%%",dd,InpMaxDrawdownPct));
      FecharMinhasPosicoes();
     }
  }

bool StopDiarioAtingido()
  {
   if(g_equityDia<=0.0) return false;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double perda=(g_equityDia-eq)/g_equityDia*100.0;
   if(perda>=InpRiscoDiarioMaxPct)
     {
      if(InpFecharNoStopDiario) FecharMinhasPosicoes();
      return true;
     }
   return false;
  }

bool PodeAbrir()
  {
   if(!InpExecucaoAtiva) return false;
   if(!InpPermitirContaReal && AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL)
      return false;
   if(StopDiarioAtingido()) return false;
   if(!HorarioPermitido()) return false;
   if(BloquearProximasNoticias()) return false;
   if(TimeCurrent()<g_pausaAte) return false;
   if(ContarPosicoesMine()>=InpMaxPositions) return false;
   if(g_ultimaEntrada>0 && TimeCurrent()-g_ultimaEntrada<InpCooldownSeg) return false;
   if(InpLucroDiarioAlvoPct>0.0)
     {
      double lucroDia=(AccountInfoDouble(ACCOUNT_EQUITY)-g_equityDia)/MathMax(g_equityDia,1.0)*100.0;
      if(lucroDia>=InpLucroDiarioAlvoPct) return false;
     }
   return true;
  }

//==================== ABERTURA ====================================
bool BarraNova(const int idx)
  {
   datetime t=(datetime)SeriesInfoInteger(g_ctx[idx].name,InpTF_Exec,SERIES_LASTBAR_DATE);
   if(t==0 || t==g_ctx[idx].lastBar) return false;
   g_ctx[idx].lastBar=t;
   return true;
  }

void TentarAbrir(const int idx,const bool compra,const Indicadores &ind,const Regime &reg,const Sinal &s)
  {
   SymCtx ctx=g_ctx[idx];
   if(!SpreadAceitavel(ctx.name)) return;
   if(ContarPorSimbolo(ctx.name)>=InpMaxPerSymbol) return;

   MqlTick tick;
   if(!SymbolInfoTick(ctx.name,tick)) return;
   if(tick.ask<=0.0 || tick.bid<=0.0) return;

   double entry=compra?tick.ask:tick.bid;
   double pip=PipSize(ctx.name);

   // Anti-whipsaw: confirmar close fora da EMA
   if(InpAntiWhipsaw)
     {
      if(compra && ind.low>=ind.emaExecL) return;
      if(!compra && ind.high<=ind.emaExecL) return;
     }

   double slDist=InpSLxATR*ind.atr;
   slDist=MathMin(MathMax(slDist,InpSLFloorPips*pip),InpSLCeilingPips*pip);
   double minDist=(double)ctx.stopsLevel*ctx.point;
   double spread=tick.ask-tick.bid;
   double floorD=MathMax(minDist,spread*2.0);
   if(slDist<floorD) slDist=floorD;

   double rr1,rr2;
   CalcularTPDinamico(ind.er,ind.adx,rr1,rr2);  // NOVO: passar ADX
   double tpDist1=rr1*slDist, tpDist2=rr2*slDist;
   if(tpDist2/slDist < InpRRMinimo) return;

   double sl=compra?(entry-slDist):(entry+slDist);
   double tp1=compra?(entry+tpDist1):(entry-tpDist1);
   double tp2=compra?(entry+tpDist2):(entry-tpDist2);
   sl=NormalizarPreco(ctx.name,sl);
   tp1=NormalizarPreco(ctx.name,tp1);
   tp2=NormalizarPreco(ctx.name,tp2);

   double lot=0.0, realRisk=0.0;
   if(!CalcularLote(idx,slDist,lot,realRisk)) return;
   if(lot<InpVolumeMinimo) return;

   double agg=RiscoAgregadoPct();
   if(agg+realRisk>InpMaxAggregateRisk) return;

   double tpBroker=InpUsarSaidaParcial?0.0:tp2;
   g_trade.SetTypeFillingBySymbol(ctx.name);
   bool ok=compra
           ? g_trade.Buy(lot,ctx.name,0.0,sl,tpBroker,"V1.0")
           : g_trade.Sell(lot,ctx.name,0.0,sl,tpBroker,"V1.0");

   if(!ok)
     {
      LogEvento(ctx.name,"REJEICAO",StringFormat("retcode=%u",g_trade.ResultRetcode()));
      return;
     }

   ulong posId=0;
   ulong deal=g_trade.ResultDeal();
   if(deal>0 && HistoryDealSelect(deal)) posId=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   if(posId==0) posId=g_trade.ResultOrder();
   if(posId>0)
     {
      SalvarEstado(posId,lot,tp1,tp2,0);
      g_ultimaEntrada=TimeCurrent();
      LogEvento(ctx.name,"ABERTURA_V1.0",
         StringFormat("%s | lote=%.4f | SL=%.5f | TP2=%.5f | risco=%.2f%% | ADX=%.1f | VOL=%.0f | WinRate=%.1f%%",
            (compra?"BUY":"SELL"),lot,sl,tp2,realRisk,ind.adx,ind.volume,g_stats.winRate*100.0));
     }
  }

//==================== GESTAO DE SAIDA =============================
void GerenciarPosicoes()
  {
   if(!InpUsarBreakeven && !InpUsarTrailing && !InpUsarSaidaParcial) return;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;

      string sym=PositionGetString(POSITION_SYMBOL);
      int idx=FindCtx(sym);
      if(idx<0) continue;

      ENUM_POSITION_TYPE tipo=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      double volAtual=PositionGetDouble(POSITION_VOLUME);

      double atr=0.0;
      if(!LerValor(g_ctx[idx].hATR,1,atr) || atr<=0.0) continue;

      MqlTick tick;
      if(!SymbolInfoTick(sym,tick)) continue;
      double px=(tipo==POSITION_TYPE_BUY)?tick.bid:tick.ask;
      double lucro=(tipo==POSITION_TYPE_BUY)?(px-open):(open-px);
      bool compra=(tipo==POSITION_TYPE_BUY);

      double vol0=0.0,tp1=0.0,tp2=0.0;
      int etapa=0;
      if(!LerEstado(tk,vol0,tp1,tp2,etapa))
        {
         vol0=volAtual; tp1=0.0; tp2=0.0; etapa=0;
         SalvarEstado(tk,vol0,tp1,tp2,etapa);
        }

      // Saida parcial
      if(InpUsarSaidaParcial && tp1>0.0 && tp2>0.0)
        {
         bool tp1Hit=compra?(px>=tp1):(px<=tp1);
         bool tp2Hit=compra?(px>=tp2):(px<=tp2);

         if(etapa==0 && tp1Hit)
           {
            double fechar=vol0*InpPctTP1/100.0;
            if(fechar>=InpVolumeMinimo && fechar<volAtual-1e-9)
              {
               g_trade.SetTypeFillingBySymbol(sym);
               if(g_trade.PositionClosePartial(tk,fechar))
                 {
                  etapa=1;
                  SalvarEstado(tk,vol0,tp1,tp2,etapa);
                  LogEvento(sym,"TP1_PARCIAL",StringFormat("%.4f de %.4f",fechar,vol0));
                 }
              }
            continue;
           }
         else if(etapa==1 && tp2Hit)
           {
            double fechar=vol0*InpPctTP2/100.0;
            if(fechar>=InpVolumeMinimo && fechar<volAtual-1e-9)
              {
               g_trade.SetTypeFillingBySymbol(sym);
               if(g_trade.PositionClosePartial(tk,fechar))
                 {
                  etapa=2;
                  SalvarEstado(tk,vol0,tp1,tp2,etapa);
                  LogEvento(sym,"TP2_PARCIAL",StringFormat("%.4f de %.4f",fechar,vol0));
                 }
              }
            continue;
           }
        }

      // Runner com lucro-alvo
      if(InpUsarSaidaParcial && etapa>=2 && InpTirarLucroATR>0.0)
        {
         if(lucro>=InpTirarLucroATR*atr)
           {
            g_trade.SetTypeFillingBySymbol(sym);
            if(g_trade.PositionClose(tk)) RemoverEstado(tk);
            continue;
           }
        }

      // Breakeven + Trailing
      double newSL=curSL;
      bool mexeu=false;
      if(InpUsarBreakeven && (etapa>=1 || lucro>=InpBExATR*atr))
        {
         double be=compra?(open+InpBEOffsetATR*atr):(open-InpBEOffsetATR*atr);
         if(compra && (curSL<be || curSL==0.0)){ newSL=be; mexeu=true; }
         if(!compra && (curSL>be || curSL==0.0)){ newSL=be; mexeu=true; }
        }

      if(InpUsarTrailing && lucro>=InpTrailInicioATR*atr)
        {
         datetime barAtual=iTime(sym,InpTF_Exec,0);
         datetime trailBar=LerTrailBar(tk);
         if(barAtual!=trailBar)
           {
            double trail=compra?(px-InpTrailxATR*atr):(px+InpTrailxATR*atr);
            if(compra && trail>newSL){ newSL=trail; mexeu=true; }
            if(!compra && (trail<newSL || newSL==0.0)){ newSL=trail; mexeu=true; }
            SalvarTrailBar(tk,barAtual);
           }
        }

      if(!mexeu || newSL==curSL) continue;

      double minDist=(double)g_ctx[idx].stopsLevel*g_ctx[idx].point;
      if(compra && (px-newSL)<minDist) continue;
      if(!compra && (newSL-px)<minDist) continue;
      if(compra && curSL>0.0 && newSL<=curSL) continue;
      if(!compra && curSL>0.0 && newSL>=curSL) continue;

      newSL=NormalizarPreco(sym,newSL);
      if(!g_trade.PositionModify(tk,newSL,curTP))
        {
         if(InpVerboseLog)
            PrintFormat("%s: falha ao mover stop. retcode=%u",sym,g_trade.ResultRetcode());
        }
      else
         LogEvento(sym,"STOP_MOVIDO",StringFormat("SL=%.5f (lucro=%.5f)",newSL,lucro));
     }
  }

//==================== FECHAMENTO ==================================
void FecharMinhasPosicoes()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong tk=PositionGetTicket(i);
      if(tk==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      g_trade.SetTypeFillingBySymbol(PositionGetString(POSITION_SYMBOL));
      if(!g_trade.PositionClose(tk))
         PrintFormat("Falha ao fechar #%I64u. retcode=%u",tk,g_trade.ResultRetcode());
     }
  }

//==================== ENCERRAMENTO (HISTORICO) ====================
void RegistrarEncerramento(const ulong posId)
  {
   if(!HistorySelectByPosition(posId)) return;

   int n=HistoryDealsTotal();
   double total=0.0;
   string sym="";
   bool nosso=false;
   for(int i=0;i<n;i++)
     {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID)!=posId) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)==InpMagic) nosso=true;
      total+=HistoryDealGetDouble(d,DEAL_PROFIT)+
             HistoryDealGetDouble(d,DEAL_SWAP)+
             HistoryDealGetDouble(d,DEAL_COMMISSION);
      if(sym=="") sym=HistoryDealGetString(d,DEAL_SYMBOL);
     }

   if(!nosso) return;

   g_perdasCons=(total<0.0)?(g_perdasCons+1):0;
   if(g_perdasCons>=InpMaxPerdasConsec && InpMaxPerdasConsec>0)
      g_pausaAte=TimeCurrent()+InpPausaMinutos*60;

   LogEvento(sym,"FECHAMENTO_V1.0",StringFormat("P&L=%.2f | perdasCons=%d | WinRate=%.1f%%",total,g_perdasCons,g_stats.winRate*100.0));
   RemoverEstado(posId);
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_HISTORY_ADD) return;
   ulong posId=trans.position;
   if(posId==0) return;
   if(!GlobalVariableCheck(ChaveGV(posId,"_VOL0"))) return;
   if(PositionSelectByTicket(posId)) return;
   RegistrarEncerramento(posId);
  }

//==================== ONINIT ======================================
int OnInit()
  {
   if(InpEMAExecRapida<=0 || InpEMAExecLenta<=0 || InpEMAExecRapida>=InpEMAExecLenta ||
      InpEMAMedRapida<=0 || InpEMAMedLenta<=0 || InpEMAMedRapida>=InpEMAMedLenta ||
      InpEMAPrimRapida<=0 || InpEMAPrimLenta<=0 || InpEMAPrimRapida>=InpEMAPrimLenta)
     { Print("ERRO: EMAs devem ser crescentes"); return INIT_PARAMETERS_INCORRECT; }
   if(InpATRPeriodo<=0 || InpRSIPeriodo<=0 || InpADXPeriodo<=0 || InpVolumePeriodo<=0)
     { Print("ERRO: periodo de indicador invalido"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRiskPerTradePct<=0.0 || InpRiskPerTradePct>100.0)
     { Print("ERRO: risco por trade fora da faixa"); return INIT_PARAMETERS_INCORRECT; }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetAsyncMode(false);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);

   if(!BuildUniverse())
     { Print("ERRO: nenhum ativo valido"); return INIT_FAILED; }

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_equityDia=g_peakEquity;
   g_dia=TimeCurrent();
   g_halted=false;

   IniciarLog();
   LogEvento("","INICIO","EA_XM_V1.0_OTIMIZADO");

   EventSetTimer(60);

   PrintFormat("EA_XM_V1.0 OTIMIZADO iniciado | ativos=%d | ADX=%.0f | VolumeCheck=%s",
               g_total,InpADXMinimo,InpValidarVolume?"SIM":"NAO");
   return INIT_SUCCEEDED;
  }

//==================== ONDEINIT ====================================
void OnDeinit(const int reason)
  {
   EventKillTimer();

   for(int i=0;i<g_total;i++)
     {
      SymCtx c=g_ctx[i];
      if(c.hEMAExecR!=INVALID_HANDLE) IndicatorRelease(c.hEMAExecR);
      if(c.hEMAExecL!=INVALID_HANDLE) IndicatorRelease(c.hEMAExecL);
      if(c.hEMAMedR!=INVALID_HANDLE)  IndicatorRelease(c.hEMAMedR);
      if(c.hEMAMedL!=INVALID_HANDLE)  IndicatorRelease(c.hEMAMedL);
      if(c.hEMAPrimR!=INVALID_HANDLE) IndicatorRelease(c.hEMAPrimR);
      if(c.hEMAPrimL!=INVALID_HANDLE) IndicatorRelease(c.hEMAPrimL);
      if(c.hRSI!=INVALID_HANDLE)      IndicatorRelease(c.hRSI);
      if(c.hMACD!=INVALID_HANDLE)     IndicatorRelease(c.hMACD);
      if(c.hATR!=INVALID_HANDLE)      IndicatorRelease(c.hATR);
      if(c.hATRD1!=INVALID_HANDLE)    IndicatorRelease(c.hATRD1);
      if(c.hADX!=INVALID_HANDLE)      IndicatorRelease(c.hADX);
      if(c.hVolume!=INVALID_HANDLE)   IndicatorRelease(c.hVolume);
     }

   LogEvento("","FIM","EA_XM_V1.0 (motivo "+IntegerToString(reason)+")");
   FinalizarLog();
   PrintFormat("EA_XM_V1.0 finalizado");
  }

//==================== ONTICK ======================================
void OnTick()
  {
   AtualizarProtecaoDrawdown();
   if(g_halted) return;

   AtualizarStats();  // NOVO: Atualizar stats
   GerenciarPosicoes();

   if(!PodeAbrir()) return;

   for(int i=0;i<g_total;i++)
     {
      if(ContarPosicoesMine()>=InpMaxPositions) break;
      if(!BarraNova(i)) continue;
      AvaliarSimbolo(i);
     }
  }

//==================== AVALIACAO POR ATIVO ========================
void AvaliarSimbolo(const int idx)
  {
   SymCtx ctx=g_ctx[idx];
   if(ContarPorSimbolo(ctx.name)>=InpMaxPerSymbol) return;

   Indicadores ind;
   if(!CalcularIndicadores(idx,ind)) return;

   Regime reg=DetectarRegime(ind);
   bool gatC=GatilhoEntrada(idx,true);
   bool gatV=GatilhoEntrada(idx,false);
   Sinal s=AvaliarSinal(ind,reg,gatC,gatV);

   if(s.compra) TentarAbrir(idx,true,ind,reg,s);
   else if(s.venda) TentarAbrir(idx,false,ind,reg,s);
  }

//==================== ONTIMER =====================================
void OnTimer()
  {
   MqlDateTime agora,ref;
   TimeToStruct(TimeCurrent(),agora);
   TimeToStruct(g_dia,ref);
   if(agora.day!=ref.day || agora.mon!=ref.mon || agora.year!=ref.year)
     {
      g_dia=TimeCurrent();
      g_equityDia=AccountInfoDouble(ACCOUNT_EQUITY);
      g_perdasCons=0;
      g_pausaAte=0;
      if(g_halted)
        {
         g_halted=false;
         g_peakEquity=g_equityDia;
         LogEvento("","DIA_NOVO","halt liberado");
        }
      LogEvento("","DIA_NOVO","reset");
     }

   if(!InpVerboseLog) return;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   double dd=(g_peakEquity>0.0)?(g_peakEquity-eq)/g_peakEquity*100.0:0.0;
   PrintFormat("V1.0 | equity=%.2f | DD=%.2f%% | pos=%d | WinRate=%.1f%% | ADX_MIN=%.0f",
               eq,dd,ContarPosicoesMine(),g_stats.winRate*100.0,InpADXMinimo);
  }
//+------------------------------------------------------------------+
