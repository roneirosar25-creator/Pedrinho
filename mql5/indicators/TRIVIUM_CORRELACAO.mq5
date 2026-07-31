//+------------------------------------------------------------------+
//| TRIVIUM_CORRELACAO.mq5                                            |
//| TRIVIUM369 (c) 2026 - Pedrinho, 17/07/2026                        |
//|                                                                    |
//| Item do roadmap "correlação entre ativos" - painel textual         |
//| mostrando quais dos pares majores estao correlacionados (movem     |
//| junto) ou anti-correlacionados (movem opostos) com o simbolo do    |
//| grafico atual, nas ultimas N velas. Util pra nao abrir 2 posicoes  |
//| que na pratica sao a MESMA aposta (ex: EURUSD comprado + GBPUSD    |
//| comprado = dobrou o risco no dolar fraco, nao diversificou nada).  |
//|                                                                    |
//| So visual/informativo, nao abre posicao, nao mexe em nada do que   |
//| ja existe.                                                         |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input int   InpBarrasCorrelacao = 100;  // quantas velas pra tras calcular a correlacao
input double InpLimiarForte     = 0.70; // acima disso = "correlacionado", abaixo de -isso = "anti-correlacionado"
input color InpCorTexto         = clrWhite;
input int   InpFonteTamanho     = 9;
input int   InpXDistancia       = 5;
input int   InpYDistancia       = 140;

#define PAINEL_NOME "TRIVIUM_PAINEL_CORRELACAO"

string g_pares[] = {"NZDJPY-T", "USDCAD-T", "AUDUSD-T", "NZDUSD-T",
                     "EURUSD-T", "GBPUSD-T", "USDJPY-T", "USDCHF-T"};

int OnInit()
{
   ObjectCreate(0, PAINEL_NOME, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_XDISTANCE, InpXDistancia);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_YDISTANCE, InpYDistancia);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_FONTSIZE, InpFonteTamanho);
   ObjectSetString(0, PAINEL_NOME, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_COLOR, InpCorTexto);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, PAINEL_NOME, OBJPROP_BACK, false);

   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_CORRELACAO");
   EventSetTimer(30); // correlacao muda devagar, nao precisa recalcular toda hora
   AtualizarPainel();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectDelete(0, PAINEL_NOME);
}

// Retorna array de retornos percentuais das ultimas N velas fechadas do simbolo,
// no timeframe do grafico atual. Devolve array vazio se nao conseguir dados.
void ObterRetornos(string symbol, int n, double &retornos[])
{
   ArrayResize(retornos, 0);
   MqlRates rates[];
   int copiado = CopyRates(symbol, _Period, 1, n + 1, rates); // 1 = pula a vela em formacao
   if(copiado < n + 1) return;

   ArrayResize(retornos, n);
   for(int i = 0; i < n; i++)
   {
      if(rates[i].close <= 0) { ArrayResize(retornos, 0); return; }
      retornos[i] = (rates[i+1].close - rates[i].close) / rates[i].close;
   }
}

double Correlacao(double &a[], double &b[])
{
   int n = MathMin(ArraySize(a), ArraySize(b));
   if(n < 10) return 0;

   double mediaA = 0, mediaB = 0;
   for(int i = 0; i < n; i++) { mediaA += a[i]; mediaB += b[i]; }
   mediaA /= n; mediaB /= n;

   double cov = 0, varA = 0, varB = 0;
   for(int i = 0; i < n; i++)
   {
      double da = a[i] - mediaA, db = b[i] - mediaB;
      cov += da * db;
      varA += da * da;
      varB += db * db;
   }
   if(varA <= 0 || varB <= 0) return 0;
   return cov / MathSqrt(varA * varB);
}

void AtualizarPainel()
{
   double retornosAtual[];
   ObterRetornos(_Symbol, InpBarrasCorrelacao, retornosAtual);
   if(ArraySize(retornosAtual) == 0)
   {
      ObjectSetString(0, PAINEL_NOME, OBJPROP_TEXT, "[CORRELAÇÃO]\nSem dados suficientes ainda");
      return;
   }

   string correlacionados = "";
   string antiCorrelacionados = "";
   string neutros = "";

   for(int p = 0; p < ArraySize(g_pares); p++)
   {
      if(g_pares[p] == _Symbol) continue;
      if(!SymbolSelect(g_pares[p], true)) continue;

      double retornosOutro[];
      ObterRetornos(g_pares[p], InpBarrasCorrelacao, retornosOutro);
      if(ArraySize(retornosOutro) == 0) continue;

      double corr = Correlacao(retornosAtual, retornosOutro);
      string linha = StringFormat("  %s (%.2f)\n", g_pares[p], corr);

      if(corr >= InpLimiarForte) correlacionados += linha;
      else if(corr <= -InpLimiarForte) antiCorrelacionados += linha;
      else neutros += StringFormat("%s(%.2f) ", g_pares[p], corr);
   }

   string texto = StringFormat("[CORRELAÇÃO] %s (%d velas %s)\n", _Symbol, InpBarrasCorrelacao, EnumToString((ENUM_TIMEFRAMES)_Period));

   if(correlacionados != "")
      texto += "Move JUNTO (cuidado, é a mesma aposta):\n" + correlacionados;
   if(antiCorrelacionados != "")
      texto += "Move OPOSTO (bom pra diversificar/hedge):\n" + antiCorrelacionados;
   if(neutros != "")
      texto += "Neutros: " + neutros + "\n";
   if(correlacionados == "" && antiCorrelacionados == "")
      texto += "Nenhum par com correlação forte (>|" + DoubleToString(InpLimiarForte,2) + "|) agora";

   ObjectSetString(0, PAINEL_NOME, OBJPROP_TEXT, texto);
   ChartRedraw(0);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   if(rates_total != prev_calculated) AtualizarPainel(); // recalcula em vela nova
   return rates_total;
}

void OnTimer()
{
   AtualizarPainel();
}
//+------------------------------------------------------------------+
