//+------------------------------------------------------------------+
//| TRIVIUM_REPLAY_EA.mq5                                             |
//| TRIVIUM369 (c) 2026 - Pedrinho, 18-19/07/2026                     |
//|                                                                    |
//| v2 do replay - a v1 (TRIVIUM_REPLAY_OPERACAO.mq5, script) exigia   |
//| reiniciar o MT5 inteiro via linha de comando pra cada trade, e     |
//| descobrimos ao vivo (log confirmou: nenhuma execucao do script     |
//| apareceu) que o MT5 so honra Script= no [StartUp] de config pra    |
//| ALGUNS cenarios - na pratica nao disparou nada, so reabriu o       |
//| terminal com o perfil salvo de sempre.                             |
//|                                                                    |
//| CORRIGIDO com desenho diferente: este e um EA (fica anexado, nao   |
//| executa uma vez e morre) que fica de olho (via OnTimer, 1x/seg)    |
//| num arquivo de pedido escrito pelo replay_watcher.py. Quando       |
//| aparece um pedido novo, abre (ou reaproveita) o grafico do         |
//| ativo+timeframe DENTRO do mesmo MT5 (sem reiniciar nada), anexa    |
//| as medias, desenha os marcadores - tudo em menos de 1 segundo.     |
//|                                                                    |
//| SETUP (uma vez so): arrasta este EA pra QUALQUER grafico do        |
//| terminal MT5_Lev100 (o dedicado ao replay) e deixa anexado. Depois |
//| disso, todo clique em "Abrir no MT5" no dashboard funciona sem     |
//| precisar tocar em nada aqui de novo.                               |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "2.00"

#define ARQUIVO_PEDIDO "TRIVIUM_REPLAY_PEDIDO.json"
#define ARQUIVO_PROCESSADO "TRIVIUM_REPLAY_PROCESSADO.json"

datetime g_ultimoProcessado = 0;

// Reforco de posicionamento (achado 19/07/2026: o MT5 tem o costume de
// "pular pro fim" sozinho alguns instantes depois que um grafico novo
// termina de carregar o historico, desfazendo o CHART_FIRST_VISIBLE_BAR
// que a gente seta na hora - por isso reaplicamos por alguns segundos
// ate o grafico estabilizar de vez).
long   g_reforcoChartId = 0;
int    g_reforcoFirstBar = 0;
int    g_reforcoScale = 0;
int    g_reforcoRestantes = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(1);
   Print("=== TRIVIUM_REPLAY_EA ativo - vigiando ", ARQUIVO_PEDIDO, " (MQL5\\Files) a cada 1s ===");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
// Le um campo string simples de um JSON raso (sem aninhamento) - o
// replay_watcher.py sempre escreve um objeto plano de 1 nivel so.
//+------------------------------------------------------------------+
string JsonCampo(string json, string chave)
{
   string busca = "\"" + chave + "\"";
   int pos = StringFind(json, busca);
   if(pos < 0) return "";
   pos = StringFind(json, ":", pos);
   if(pos < 0) return "";
   pos++;
   while(pos < StringLen(json) && (StringGetCharacter(json, pos) == ' ')) pos++;

   bool ehString = (StringGetCharacter(json, pos) == '"');
   if(ehString)
   {
      pos++;
      int fim = StringFind(json, "\"", pos);
      if(fim < 0) return "";
      return StringSubstr(json, pos, fim - pos);
   }
   else
   {
      int fim = pos;
      while(fim < StringLen(json))
      {
         ushort c = StringGetCharacter(json, fim);
         if(c == ',' || c == '}') break;
         fim++;
      }
      return StringSubstr(json, pos, fim - pos);
   }
}

//+------------------------------------------------------------------+
// Reconstroi o horario REAL de entrada quando o pedido nao trouxe um
// (dataset do simulador so guarda a saida). Procura PRA TRAS a partir
// da vela de saida a vela mais recente cujo range [low,high] contem o
// preco de entrada - mesma logica ja validada no estudo do GER40 H1
// (49 de 50 trades casaram certo). Pedido do Ronei 19/07/2026: "quero
// ver a abertura e o fechamento" - com entrada==saida os dois marcadores
// ficavam empilhados no mesmo ponto, sem mostrar a operacao de verdade.
//+------------------------------------------------------------------+
datetime ReconstruirEntrada(string ativo, ENUM_TIMEFRAMES tf, datetime tSaida, double precoEntrada, int maxVelasTras = 300)
{
   if(precoEntrada <= 0) return tSaida;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int shiftSaida = iBarShift(ativo, tf, tSaida, false);
   if(shiftSaida < 0) return tSaida;

   int copiados = CopyRates(ativo, tf, shiftSaida, maxVelasTras, rates);
   if(copiados < 1) return tSaida;

   for(int i = 0; i < copiados; i++)
   {
      if(rates[i].low <= precoEntrada && precoEntrada <= rates[i].high)
         return rates[i].time;
   }
   // fallback: vela cujo close mais se aproxima do preco de entrada
   int melhor = 0;
   double menorDist = MathAbs(rates[0].close - precoEntrada);
   for(int i = 1; i < copiados; i++)
   {
      double dist = MathAbs(rates[i].close - precoEntrada);
      if(dist < menorDist) { menorDist = dist; melhor = i; }
   }
   return rates[melhor].time;
}

//+------------------------------------------------------------------+
// Abre o grafico JA direto no ponto da operacao, com zoom calculado pra
// caber entrada+saida (e uma folga) numa tela so, sem precisar catar
// manualmente (pedido do Ronei 19/07/2026: "as vezes fica bem
// complicado ate encontrar"). MQL5 nao tem "ajustar zoom pra caber N
// velas" pronto - aproxima escolhendo o nivel de CHART_SCALE (0-5,
// cada nivel ~dobra a quantidade de velas visiveis) mais proximo do
// necessario pra essa operacao especifica.
//+------------------------------------------------------------------+
void EnquadrarOperacao(long chartId, string ativo, ENUM_TIMEFRAMES tf, datetime tEntrada, datetime tSaida)
{
   int shiftEntrada = iBarShift(ativo, tf, tEntrada, false);
   int shiftSaida = iBarShift(ativo, tf, tSaida, false);
   if(shiftEntrada < 0 || shiftSaida < 0) return;

   int maisAntigo = MathMax(shiftEntrada, shiftSaida);
   int maisRecente = MathMin(shiftEntrada, shiftSaida);
   int duracaoVelas = maisAntigo - maisRecente;

   // folga de 25% pra cada lado (minimo 8 velas) - deixa contexto de
   // antes/depois visivel, sem cortar a operacao rente na borda.
   int folga = MathMax(8, (int)(duracaoVelas * 0.25));
   int totalVelasNecessario = duracaoVelas + folga * 2;

   // capacidade aproximada de velas visiveis por nivel de zoom (0=mais
   // zoom, 5=mais afastado) - heuristica calibrada pra largura tipica
   // de janela de grafico, nao e exata mas fica proxima o suficiente.
   int capacidadePorEscala[6] = {60, 110, 200, 380, 700, 1300};
   int escala = 5;
   for(int i = 0; i <= 5; i++)
   {
      if(capacidadePorEscala[i] >= totalVelasNecessario) { escala = i; break; }
   }

   ChartSetInteger(chartId, CHART_AUTOSCROLL, false);
   ChartSetInteger(chartId, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(chartId, CHART_SCALE, escala);
   ChartRedraw(chartId);
   ChartSetInteger(chartId, CHART_FIRST_VISIBLE_BAR, maisAntigo + folga);
   ChartRedraw(chartId);

   // Agenda reforco: reaplica essa mesma posicao nos proximos ~6 segundos
   // (OnTimer roda 1x/seg) pra vencer o "pulo pro fim" que o MT5 faz
   // sozinho quando um grafico novo termina de carregar.
   g_reforcoChartId = chartId;
   g_reforcoFirstBar = maisAntigo + folga;
   g_reforcoScale = escala;
   g_reforcoRestantes = 6;
}

//+------------------------------------------------------------------+
long ChartAbrirOuReaproveitar(string simbolo, ENUM_TIMEFRAMES tf)
{
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(ChartSymbol(chartId) == simbolo && ChartPeriod(chartId) == tf)
         return chartId;
      chartId = ChartNext(chartId);
   }
   long novo = ChartOpen(simbolo, tf);
   if(novo != 0) Sleep(400); // da tempo do historico carregar
   return novo;
}

//+------------------------------------------------------------------+
// Reconstroi o contexto tecnico NA VELA DE ENTRADA - o dataset do
// simulador (backtest) nao guarda o motivo por trade, entao calculamos
// aqui, ao vivo, a partir do historico real do proprio MT5 (pedido do
// Ronei 19/07/2026: "quais foram os indicadores tecnicos que foram
// usados"). Usa a mesma logica de referencia do NEXUS369_TREND_VALIDADO
// (ADX/DI/Volume) - e o padrao usado pra gerar a maioria dos trades
// desse dataset.
//+------------------------------------------------------------------+
int CalcularContextoTecnicoLinhas(string ativo, ENUM_TIMEFRAMES tf, datetime tEntrada, string &saida[])
{
   int shift = iBarShift(ativo, tf, tEntrada, false);
   if(shift < 0) { saida[0] = "Contexto tecnico: nao disponivel (vela fora do historico carregado)"; return 1; }

   int hAdx = iADX(ativo, tf, 14);
   int hAtr = iATR(ativo, tf, 14);
   if(hAdx == INVALID_HANDLE || hAtr == INVALID_HANDLE) { saida[0] = "Contexto tecnico: erro ao calcular indicadores"; return 1; }

   double adxBuf[1], plusDiBuf[1], minusDiBuf[1], atrBuf[1];
   if(CopyBuffer(hAdx, 0, shift, 1, adxBuf) < 1) { saida[0] = "Contexto tecnico: sem dado de ADX nessa vela"; return 1; }
   if(CopyBuffer(hAdx, 1, shift, 1, plusDiBuf) < 1) { saida[0] = "Contexto tecnico: sem dado de DI nessa vela"; return 1; }
   if(CopyBuffer(hAdx, 2, shift, 1, minusDiBuf) < 1) { saida[0] = "Contexto tecnico: sem dado de DI nessa vela"; return 1; }
   if(CopyBuffer(hAtr, 0, shift, 1, atrBuf) < 1) { saida[0] = "Contexto tecnico: sem dado de ATR nessa vela"; return 1; }

   long volBuf[];
   ArraySetAsSeries(volBuf, true);
   double volRel = 0;
   if(CopyTickVolume(ativo, tf, shift, 21, volBuf) >= 21)
   {
      double somaMedia = 0;
      for(int i = 1; i <= 20; i++) somaMedia += (double)volBuf[i];
      double media = somaMedia / 20.0;
      if(media > 0) volRel = (double)volBuf[0] / media;
   }

   string direcaoSugerida = (plusDiBuf[0] > minusDiBuf[0]) ? "alta (+DI dominante)" : "baixa (-DI dominante)";

   saida[0] = "--- Contexto tecnico na vela de entrada (calculado agora, dado real) ---";
   saida[1] = StringFormat("ADX(14)=%.1f | +DI=%.1f  -DI=%.1f  (tendencia %s)", adxBuf[0], plusDiBuf[0], minusDiBuf[0], direcaoSugerida);
   saida[2] = StringFormat("Volume=%.2fx media(20) | ATR(14)=%.2f", volRel, atrBuf[0]);
   return 3;
}

//+------------------------------------------------------------------+
// Escreve o painel como VARIAS labels empilhadas (uma por linha) - o
// MT5 nao quebra linha (\n) dentro de um OBJ_LABEL sozinho nessa versao
// (achado ao vivo: "VENDAEntrada..." grudado, sem quebra). Cada linha
// vira seu proprio objeto, empilhado por Y.
//+------------------------------------------------------------------+
void DesenharPainel(long chartId, string prefixo, string &linhas[], color &cores[])
{
   int y = 20;
   for(int i = 0; i < ArraySize(linhas); i++)
   {
      string nome = StringFormat("%sPAINEL_L%d", prefixo, i);
      ObjectCreate(chartId, nome, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(chartId, nome, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chartId, nome, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(chartId, nome, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(chartId, nome, OBJPROP_FONTSIZE, 9);
      ObjectSetString(chartId, nome, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(chartId, nome, OBJPROP_COLOR, cores[i]);
      ObjectSetInteger(chartId, nome, OBJPROP_BACK, false);
      ObjectSetString(chartId, nome, OBJPROP_TEXT, linhas[i]);
      y += 15;
   }
}

//+------------------------------------------------------------------+
void DesenharMarcadores(long chartId, string ativo, ENUM_TIMEFRAMES tf, datetime tEntrada, datetime tSaida,
                         double precoEntrada, double precoSaida, int lado, double pnl, string motivo,
                         string resultado, double stopLoss, double takeProfit, bool entradaReconstruida)
{
   string prefixo = "TRIVIUM_REPLAY_";
   int total = ObjectsTotal(chartId, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nome = ObjectName(chartId, i, 0, -1);
      if(StringFind(nome, prefixo) == 0)
         ObjectDelete(chartId, nome);
   }

   bool ehCompra = (lado == 0);
   bool ganhou = pnl >= 0;
   // Cor de ENTRADA = direcao (verde=compra, vermelho=venda, pedido do Ronei).
   // Cor de SAIDA = resultado (verde=ganho, vermelho=perda) - tambem pedido dele.
   color corEntrada = ehCompra ? clrLime : clrRed;
   color corSaida = ganhou ? clrLime : clrRed;

   // --- barra vertical de ENTRADA ---
   ObjectCreate(chartId, prefixo + "V_ENTRADA", OBJ_VLINE, 0, tEntrada, 0);
   ObjectSetInteger(chartId, prefixo + "V_ENTRADA", OBJPROP_COLOR, corEntrada);
   ObjectSetInteger(chartId, prefixo + "V_ENTRADA", OBJPROP_WIDTH, 2);
   ObjectSetInteger(chartId, prefixo + "V_ENTRADA", OBJPROP_STYLE, STYLE_SOLID);

   // --- barra vertical de SAIDA (pedido do Ronei: faltava, agora colorida pelo resultado) ---
   ObjectCreate(chartId, prefixo + "V_SAIDA", OBJ_VLINE, 0, tSaida, 0);
   ObjectSetInteger(chartId, prefixo + "V_SAIDA", OBJPROP_COLOR, corSaida);
   ObjectSetInteger(chartId, prefixo + "V_SAIDA", OBJPROP_WIDTH, 2);
   ObjectSetInteger(chartId, prefixo + "V_SAIDA", OBJPROP_STYLE, STYLE_SOLID);

   // --- linha ligando entrada -> saida (pedido do Ronei: faltava) ---
   if(precoEntrada > 0 && precoSaida > 0)
   {
      ObjectCreate(chartId, prefixo + "LIGACAO", OBJ_TREND, 0, tEntrada, precoEntrada, tSaida, precoSaida);
      ObjectSetInteger(chartId, prefixo + "LIGACAO", OBJPROP_COLOR, corSaida);
      ObjectSetInteger(chartId, prefixo + "LIGACAO", OBJPROP_WIDTH, 2);
      ObjectSetInteger(chartId, prefixo + "LIGACAO", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(chartId, prefixo + "LIGACAO", OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(chartId, prefixo + "LIGACAO", OBJPROP_BACK, true);
   }

   // --- seta de ENTRADA, maior (pedido do Ronei), pra cima se compra / pra baixo se venda ---
   if(precoEntrada > 0)
   {
      ObjectCreate(chartId, prefixo + "SETA_ENTRADA", ehCompra ? OBJ_ARROW_UP : OBJ_ARROW_DOWN, 0, tEntrada, precoEntrada);
      ObjectSetInteger(chartId, prefixo + "SETA_ENTRADA", OBJPROP_COLOR, corEntrada);
      ObjectSetInteger(chartId, prefixo + "SETA_ENTRADA", OBJPROP_WIDTH, 8);
      ObjectSetInteger(chartId, prefixo + "SETA_ENTRADA", OBJPROP_ANCHOR, ehCompra ? ANCHOR_TOP : ANCHOR_BOTTOM);

      ObjectCreate(chartId, prefixo + "H_ENTRADA", OBJ_HLINE, 0, 0, precoEntrada);
      ObjectSetInteger(chartId, prefixo + "H_ENTRADA", OBJPROP_COLOR, corEntrada);
      ObjectSetInteger(chartId, prefixo + "H_ENTRADA", OBJPROP_STYLE, STYLE_DOT);
   }
   // --- seta de SAIDA, maior, colorida pelo resultado ---
   if(precoSaida > 0)
   {
      ObjectCreate(chartId, prefixo + "SETA_SAIDA", OBJ_ARROW_CHECK, 0, tSaida, precoSaida);
      ObjectSetInteger(chartId, prefixo + "SETA_SAIDA", OBJPROP_COLOR, corSaida);
      ObjectSetInteger(chartId, prefixo + "SETA_SAIDA", OBJPROP_WIDTH, 8);

      ObjectCreate(chartId, prefixo + "H_SAIDA", OBJ_HLINE, 0, 0, precoSaida);
      ObjectSetInteger(chartId, prefixo + "H_SAIDA", OBJPROP_COLOR, corSaida);
      ObjectSetInteger(chartId, prefixo + "H_SAIDA", OBJPROP_STYLE, STYLE_DOT);
   }
   if(stopLoss > 0)
   {
      ObjectCreate(chartId, prefixo + "H_SL", OBJ_HLINE, 0, 0, stopLoss);
      ObjectSetInteger(chartId, prefixo + "H_SL", OBJPROP_COLOR, clrOrangeRed);
      ObjectSetInteger(chartId, prefixo + "H_SL", OBJPROP_STYLE, STYLE_DASHDOT);
   }
   if(takeProfit > 0)
   {
      ObjectCreate(chartId, prefixo + "H_TP", OBJ_HLINE, 0, 0, takeProfit);
      ObjectSetInteger(chartId, prefixo + "H_TP", OBJPROP_COLOR, clrLime);
      ObjectSetInteger(chartId, prefixo + "H_TP", OBJPROP_STYLE, STYLE_DASHDOT);
   }

   // --- painel completo, linha por linha (pedido do Ronei: "todas as metricas que puderes botar") ---
   string linhas[]; color cores[];
   int n = 0;
   #define ADD_LINHA(txt, cor) { ArrayResize(linhas, n+1); ArrayResize(cores, n+1); linhas[n]=(txt); cores[n]=(cor); n++; }

   ADD_LINHA(StringFormat("=== REPLAY: %s %s ===", ativo, ehCompra ? "COMPRA" : "VENDA"), corEntrada);
   ADD_LINHA(StringFormat("ENTRADA: %s  @ %s", TimeToString(tEntrada, TIME_DATE|TIME_MINUTES), DoubleToString(precoEntrada, 5)), corEntrada);
   if(entradaReconstruida) ADD_LINHA("  (horario reconstruido - dado original so tinha a saida)", clrSilver);
   ADD_LINHA(StringFormat("SAIDA:   %s  @ %s", TimeToString(tSaida, TIME_DATE|TIME_MINUTES), DoubleToString(precoSaida, 5)), corSaida);
   if(StringLen(resultado) > 0) ADD_LINHA("Resultado: " + resultado, corSaida);
   ADD_LINHA(StringFormat("P&L: %s%.2f", (pnl >= 0 ? "+" : ""), pnl), corSaida);
   if(stopLoss > 0) ADD_LINHA(StringFormat("Stop Loss: %s", DoubleToString(stopLoss, 5)), clrOrangeRed);
   if(takeProfit > 0) ADD_LINHA(StringFormat("Take Profit: %s", DoubleToString(takeProfit, 5)), clrLime);
   if(StringLen(motivo) > 0) ADD_LINHA("Motivo: " + motivo, clrKhaki);

   string ctxLinhas[8];
   int ctxN = CalcularContextoTecnicoLinhas(ativo, ChartPeriod(chartId), tEntrada, ctxLinhas);
   for(int i = 0; i < ctxN; i++) ADD_LINHA(ctxLinhas[i], clrAqua);

   DesenharPainel(chartId, prefixo, linhas, cores);

   ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StringParaTimeframe(string s)
{
   StringReplace(s, "PERIOD_", "");
   if(s == "M1")  return PERIOD_M1;
   if(s == "M2")  return PERIOD_M2;
   if(s == "M5")  return PERIOD_M5;
   if(s == "M15") return PERIOD_M15;
   if(s == "M30") return PERIOD_M30;
   if(s == "H1")  return PERIOD_H1;
   if(s == "H4")  return PERIOD_H4;
   if(s == "D1")  return PERIOD_D1;
   return PERIOD_H1;
}

//+------------------------------------------------------------------+
void ProcessarPedido()
{
   if(!FileIsExist(ARQUIVO_PEDIDO, FILE_COMMON) && !FileIsExist(ARQUIVO_PEDIDO)) return;

   int flags = FILE_READ | FILE_TXT | FILE_ANSI;
   int h = FileOpen(ARQUIVO_PEDIDO, flags);
   if(h == INVALID_HANDLE) return;

   string conteudo = "";
   while(!FileIsEnding(h)) conteudo += FileReadString(h) + "\n";
   FileClose(h);

   if(StringLen(conteudo) < 5) return; // arquivo vazio/incompleto (ainda escrevendo)

   string ativo         = JsonCampo(conteudo, "ativo");
   string tfStr         = JsonCampo(conteudo, "timeframe");
   string lado_s        = JsonCampo(conteudo, "lado");
   string precoEntrada_s= JsonCampo(conteudo, "preco_entrada");
   string precoSaida_s  = JsonCampo(conteudo, "preco_saida");
   string dataHoraEntrada_s = JsonCampo(conteudo, "data_hora_entrada");
   string dataHoraSaida_s   = JsonCampo(conteudo, "data_hora_saida");
   string pnl_s          = JsonCampo(conteudo, "pnl");
   string motivo         = JsonCampo(conteudo, "motivo");
   string resultado      = JsonCampo(conteudo, "resultado");
   string sl_s           = JsonCampo(conteudo, "stop_loss");
   string tp_s           = JsonCampo(conteudo, "take_profit");

   if(StringLen(ativo) == 0)
   {
      Print("AVISO REPLAY: pedido sem ativo valido, ignorado. Conteudo: ", conteudo);
      FileDelete(ARQUIVO_PEDIDO);
      return;
   }

   ENUM_TIMEFRAMES tf = StringParaTimeframe(tfStr);
   int lado = (lado_s == "SELL") ? 1 : 0;
   double precoEntrada = StringToDouble(precoEntrada_s);
   double precoSaida = StringToDouble(precoSaida_s);
   double pnl = StringToDouble(pnl_s);
   double sl = StringToDouble(sl_s);
   double tp = StringToDouble(tp_s);
   datetime tEntrada = StringToTime(dataHoraEntrada_s);
   datetime tSaida = StringToTime(dataHoraSaida_s);
   if(tEntrada == 0) tEntrada = tSaida;

   if(!SymbolSelect(ativo, true))
   {
      Print("ERRO REPLAY: simbolo '", ativo, "' nao encontrado no Market Watch deste terminal.");
      FileDelete(ARQUIVO_PEDIDO);
      return;
   }

   long chartId = ChartAbrirOuReaproveitar(ativo, tf);
   if(chartId <= 0)
   {
      Print("ERRO REPLAY: nao consegui abrir/achar grafico de ", ativo, " ", EnumToString(tf));
      FileDelete(ARQUIVO_PEDIDO);
      return;
   }

   // Se o pedido nao trouxe hora de entrada real (tEntrada==tSaida), tenta
   // reconstruir procurando no historico real qual vela teve esse preco.
   bool entradaReconstruida = false;
   if(tEntrada == tSaida)
   {
      datetime reconstruida = ReconstruirEntrada(ativo, tf, tSaida, precoEntrada);
      if(reconstruida != tSaida)
      {
         tEntrada = reconstruida;
         entradaReconstruida = true;
      }
   }

   int hInd = iCustom(ativo, tf, "TRIVIUM_MEDIAS_7");
   if(hInd != INVALID_HANDLE) ChartIndicatorAdd(chartId, 0, hInd);

   DesenharMarcadores(chartId, ativo, tf, tEntrada, tSaida, precoEntrada, precoSaida, lado, pnl, motivo, resultado, sl, tp, entradaReconstruida);

   EnquadrarOperacao(chartId, ativo, tf, tEntrada, tSaida);

   ChartSetInteger(chartId, CHART_BRING_TO_TOP, true);

   Print(StringFormat("=== REPLAY EXECUTADO: %s %s %s @ %s -> %s @ %s | P&L %.2f ===",
      ativo, EnumToString(tf), (lado==0?"COMPRA":"VENDA"), DoubleToString(precoEntrada,5),
      TimeToString(tSaida, TIME_DATE|TIME_MINUTES), DoubleToString(precoSaida,5), pnl));

   FileDelete(ARQUIVO_PEDIDO);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   ProcessarPedido();

   if(g_reforcoRestantes > 0 && g_reforcoChartId != 0)
   {
      ChartSetInteger(g_reforcoChartId, CHART_AUTOSCROLL, false);
      ChartSetInteger(g_reforcoChartId, CHART_SCALE, g_reforcoScale);
      ChartSetInteger(g_reforcoChartId, CHART_FIRST_VISIBLE_BAR, g_reforcoFirstBar);
      ChartRedraw(g_reforcoChartId);
      g_reforcoRestantes--;
   }
}
//+------------------------------------------------------------------+
