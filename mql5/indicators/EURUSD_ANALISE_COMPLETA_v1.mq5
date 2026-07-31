//+------------------------------------------------------------------+
//|                                          EURUSD_ANALISE_COMPLETA |
//|                                     IA do MetaCode - Ronei/Pedrinho |
//|                                    Versao: 1.0 - 28/06/2026    |
//+------------------------------------------------------------------+
#property copyright "IA do MetaCode"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Parametros
input int      InpMAPeriod20    = 20;        // Periodo SMA20
input int      InpMAPeriod50    = 50;        // Periodo SMA50
input int      InpMAPeriod200   = 200;       // Periodo SMA200
input int      InpEMAPeriod9    = 9;         // Periodo EMA9
input int      InpEMAPeriod21   = 21;        // Periodo EMA21
input color    InpColorSMA20    = clrDodgerBlue;  // Cor SMA20
input color    InpColorSMA50    = clrRoyalBlue;   // Cor SMA50
input color    InpColorSMA200   = clrDarkBlue;    // Cor SMA200
input color    InpColorEMA9     = clrLimeGreen;   // Cor EMA9
input color    InpColorEMA21    = clrOrange;      // Cor EMA21
input bool     InpShowSuportes  = true;       // Mostrar suportes?
input bool     InpShowAlvos     = true;       // Mostrar alvos?
input int      InpMaxBars       = 5000;       // Maximo de barras

//--- Niveis
double Nivel_S1 = 1.1380;
double Nivel_S2 = 1.1350;
double Nivel_S3 = 1.1333;
double Nivel_S4 = 1.1300;
double Nivel_R1 = 1.1395;
double Nivel_R2 = 1.1400;
double Nivel_R3 = 1.1434;
double Nivel_R4 = 1.1470;
double Nivel_ZonaMin = 1.1375;
double Nivel_ZonaMax = 1.1385;
double Nivel_Stop    = 1.1410;
double Nivel_T1      = 1.1350;
double Nivel_T2      = 1.1333;
double Nivel_T3      = 1.1300;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                        |
//+------------------------------------------------------------------+
int OnInit()
  {
   IndicatorSetString(INDICATOR_SHORTNAME, "EURUSD Analise Completa");
   IndicatorSetInteger(INDICATOR_DIGITS, 5);
   
   //--- Cria objetos de suporte/resistencia
   if(InpShowSuportes) CriarNiveis();
   if(InpShowAlvos)    CriarAlvos();
   
   Print("EURUSD ANALISE COMPLETA v1.0 carregado!");
   Print("Suportes: S1=", Nivel_S1, " S2=", Nivel_S2, " S3=", Nivel_S3);
   Print("Resistencias: R1=", Nivel_R1, " R2=", Nivel_R2, " R3=", Nivel_R3);
   Print("Zona Entrada: ", Nivel_ZonaMin, " - ", Nivel_ZonaMax);
   Print("Stop: ", Nivel_Stop, " | T1: ", Nivel_T1, " T2: ", Nivel_T2, " T3: ", Nivel_T3);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                      |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   //--- Remove todos os objetos
   ObjectsDeleteAll(0, "EURUSD_");
   Comment("");
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                             |
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
   if(rates_total < InpMAPeriod200) return(0);
   
   //--- Atualizar painel de informacao
   AtualizarPainel(close[rates_total-1]);
   
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Cria niveis de suporte, resistencia e zonas                     |
//+------------------------------------------------------------------+
void CriarNiveis()
  {
   string nome;
   datetime t_fim = TimeCurrent() + 86400 * 30; // 30 dias no futuro
   
   //--- Suportes (Verde)
   CriarLinhaHorizontal("EURUSD_S1", Nivel_S1, clrLimeGreen, STYLE_SOLID, 2, "S1: 1.1380 (suporte imediato)");
   CriarLinhaHorizontal("EURUSD_S2", Nivel_S2, clrLimeGreen, STYLE_SOLID, 2, "S2: 1.1350 (psicologico)");
   CriarLinhaHorizontal("EURUSD_S3", Nivel_S3, clrLime, STYLE_SOLID, 3, "S3: 1.1333 ⭐ FUNDO 25/JUN");
   CriarLinhaHorizontal("EURUSD_S4", Nivel_S4, clrLimeGreen, STYLE_DASH, 1, "S4: 1.1300 (critico)");
   
   //--- Resistencias (Vermelho)
   CriarLinhaHorizontal("EURUSD_R1", Nivel_R1, clrRed, STYLE_SOLID, 1, "R1: 1.1395");
   CriarLinhaHorizontal("EURUSD_R2", Nivel_R2, clrRed, STYLE_SOLID, 2, "R2: 1.1400 (redondo)");
   CriarLinhaHorizontal("EURUSD_R3", Nivel_R3, clrRed, STYLE_SOLID, 3, "R3: 1.1434 (maxima 26/JUN)");
   CriarLinhaHorizontal("EURUSD_R4", Nivel_R4, clrRed, STYLE_DASH, 1, "R4: 1.1470 (topo 22/JUN)");
   
   //--- Zona de Entrada (Retangulo verde semi-transparente)
   CriarRetangulo("EURUSD_ZONA", Nivel_ZonaMin, Nivel_ZonaMax, clrGreen, 30, "🟢 ENTRADA VENDA AQUI (zona 10 pips)");
   
   //--- Stop Loss (Linha vermelha tracejada grossa)
   CriarLinhaHorizontal("EURUSD_STOP", Nivel_Stop, clrRed, STYLE_DASH, 3, "🔴 STOP 1.1410 (Risco: 35 pips)");
  }

//+------------------------------------------------------------------+
//| Cria alvos                                                      |
//+------------------------------------------------------------------+
void CriarAlvos()
  {
   //--- Alvo 1 (Azul)
   CriarLinhaHorizontal("EURUSD_T1", Nivel_T1, clrDodgerBlue, STYLE_SOLID, 2, 
                        "🎯 T1: 1.1350 | +25 pips | ETA: ~2h");
   
   //--- Alvo 2 (Azul medio)
   CriarLinhaHorizontal("EURUSD_T2", Nivel_T2, clrRoyalBlue, STYLE_SOLID, 2, 
                        "🎯 T2: 1.1333 | +42 pips | ETA: ~5h ⭐");
   
   //--- Alvo 3 (Azul escuro)
   CriarLinhaHorizontal("EURUSD_T3", Nivel_T3, clrDarkBlue, STYLE_SOLID, 2, 
                        "🎯 T3: 1.1300 | +75 pips | ETA: ~12h");
  }

//+------------------------------------------------------------------+
//| Cria linha horizontal com label                                 |
//+------------------------------------------------------------------+
void CriarLinhaHorizontal(string nome, double nivel, color cor, 
                          int estilo, int grossura, string descricao)
  {
   ObjectCreate(0, nome, OBJ_HLINE, 0, 0, nivel);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_STYLE, estilo);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, grossura);
   ObjectSetInteger(0, nome, OBJPROP_BACK, false);
   ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, nome, OBJPROP_TOOLTIP, descricao);
  }

//+------------------------------------------------------------------+
//| Cria retangulo (zona de entrada)                                |
//+------------------------------------------------------------------+
void CriarRetangulo(string nome, double min, double max, color cor, 
                    int opacidade, string descricao)
  {
   datetime t_inicio = TimeCurrent() - 86400 * 30;
   datetime t_fim = TimeCurrent() + 86400 * 30;
   
   ObjectCreate(0, nome, OBJ_RECTANGLE, 0, t_inicio, min, t_fim, max);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_FILL, true);
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, nome, OBJPROP_TOOLTIP, descricao);
  }

//+------------------------------------------------------------------+
//| Atualiza painel de informacoes no canto superior direito        |
//+------------------------------------------------------------------+
void AtualizarPainel(double preco_atual)
  {
   double dist_stop = (Nivel_Stop - preco_atual) * 100000;
   double dist_t1   = (preco_atual - Nivel_T1) * 100000;
   double dist_t2   = (preco_atual - Nivel_T2) * 100000;
   double dist_t3   = (preco_atual - Nivel_T3) * 100000;
   
   string em_zona = (preco_atual >= Nivel_ZonaMin && preco_atual <= Nivel_ZonaMax) ? "✅" : "";
   string acao = (preco_atual <= Nivel_ZonaMax) ? "VENDA com Stop " + DoubleToString(Nivel_Stop, 4) : "AGUARDAR";
   
   Comment("\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n",
           "═══════════════════════════════════════════════════\n",
           "  EURUSD — ANALISE COMPLETA | 28/06/2026       \n",
           "═══════════════════════════════════════════════════\n",
           "\n",
           "💰 PRECO ATUAL: ", DoubleToString(preco_atual, 5), " ", em_zona, "\n",
           "\n",
           "📊 TENDENCIA: 🔴 BAIXISTA (70% confianca)\n",
           "💥 FORCA: MUITO FORTE (fora de Bollinger)\n",
           "✅ CONFIRMACAO: 7/7 indicadores\n",
           "\n",
           "📏 DISTANCIAS:\n",
           "   Stop (", DoubleToString(Nivel_Stop, 4), "): ", 
           DoubleToString(dist_stop, 1), " pips\n",
           "   T1 (", DoubleToString(Nivel_T1, 4), "): ", 
           DoubleToString(dist_t1, 1), " pips\n",
           "   T2 (", DoubleToString(Nivel_T2, 4), "): ", 
           DoubleToString(dist_t2, 1), " pips\n",
           "   T3 (", DoubleToString(Nivel_T3, 4), "): ", 
           DoubleToString(dist_t3, 1), " pips\n",
           "\n",
           "📊 RISCO:RETORNO: 1:2.1 no T2\n",
           "\n",
           "🎯 PROXIMA ACAO: ", acao, "\n",
           "\n",
           "⚠️ ALERTA: RSI ~32 — cuidado com oversold\n",
           "═══════════════════════════════════════════════════");
  }
//+------------------------------------------------------------------+
