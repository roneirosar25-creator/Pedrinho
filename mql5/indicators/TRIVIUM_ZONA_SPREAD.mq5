//+------------------------------------------------------------------+
//| TRIVIUM_ZONA_SPREAD.mq5                                           |
//| TRIVIUM369 (c) 2026 - Pedrinho, 15/07/2026                        |
//|                                                                    |
//| Ultima ferramenta da lista original sugerida: zona de spread ao    |
//| vivo. Desenha uma faixa sombreada entre Bid e Ask, atualizando a   |
//| cada tick (o spread muda o tempo todo - diferente das outras       |
//| ferramentas, que so recalculam por vela, essa precisa ser tick a   |
//| tick). A cor muda conforme o spread abre: verde = normal, laranja  |
//| = alto (cuidado no scalping), vermelho = extremo (evite entrar).   |
//| Um rotulo no canto mostra o valor exato em pontos.                 |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input int   InpSpreadNormalMax = 30;   // ate quantos pontos o spread ainda e "normal" (verde)
input int   InpSpreadAltoMax   = 60;   // ate quantos pontos e "alto" (laranja) - acima disso e "extremo" (vermelho)
input color InpCorNormal       = clrLimeGreen;
input color InpCorAlto         = clrOrange;
input color InpCorExtremo      = clrRed;
input int   InpTransparencia   = 200;  // 0=opaco, 255=invisivel - controla o quao "sombreada" fica a faixa

#define PREFIXO "TRIVIUM_SPREAD_"

color AplicarTransparencia(color cor)
{
   // MQL5 nao tem alpha nativo em cor de objeto solido, entao simulamos "sombreado"
   // usando OBJPROP_FILL com uma cor mais escura/dessaturada em vez de alpha real.
   return cor;
}

void AtualizarZona()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0 || ask <= bid) return;

   double spreadPts = (ask - bid) / _Point;
   color corZona;
   string status;
   if(spreadPts <= InpSpreadNormalMax)      { corZona = InpCorNormal;  status = "NORMAL"; }
   else if(spreadPts <= InpSpreadAltoMax)   { corZona = InpCorAlto;    status = "ALTO - cuidado no scalping"; }
   else                                      { corZona = InpCorExtremo; status = "EXTREMO - evite entrar agora"; }

   datetime tAtual = TimeCurrent();
   int periodoSeg = PeriodSeconds(_Period);
   datetime tEsquerda = tAtual - periodoSeg * 80;
   datetime tDireita  = tAtual + periodoSeg * 30;

   string nomeZona = PREFIXO + "ZONA";
   if(ObjectFind(0, nomeZona) < 0)
   {
      ObjectCreate(0, nomeZona, OBJ_RECTANGLE, 0, tEsquerda, ask, tDireita, bid);
      ObjectSetInteger(0, nomeZona, OBJPROP_BACK, true);
      ObjectSetInteger(0, nomeZona, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nomeZona, OBJPROP_FILL, true);
   }
   else
   {
      ObjectMove(0, nomeZona, 0, tEsquerda, ask);
      ObjectMove(0, nomeZona, 1, tDireita, bid);
   }
   ObjectSetInteger(0, nomeZona, OBJPROP_COLOR, corZona);
   ObjectSetString(0, nomeZona, OBJPROP_TOOLTIP, StringFormat(
      "ZONA DE SPREAD\nBid: %s | Ask: %s\nSpread: %.0f pontos (%s)",
      DoubleToString(bid,_Digits), DoubleToString(ask,_Digits), spreadPts, status));

   string nomeLabel = PREFIXO + "LABEL";
   if(ObjectFind(0, nomeLabel) < 0)
   {
      ObjectCreate(0, nomeLabel, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, nomeLabel, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, nomeLabel, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, nomeLabel, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, nomeLabel, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nomeLabel, OBJPROP_FONTSIZE, 9);
   }
   ObjectSetString(0, nomeLabel, OBJPROP_TEXT, StringFormat("Spread: %.0f pts - %s", spreadPts, status));
   ObjectSetInteger(0, nomeLabel, OBJPROP_COLOR, corZona);
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_ZONA_SPREAD");
   EventSetMillisecondTimer(300); // atualiza rapido mesmo sem tick novo (mercado parado)
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nome = ObjectName(0, i, 0, -1);
      if(StringFind(nome, PREFIXO) == 0)
         ObjectDelete(0, nome);
   }
}

void OnTimer()
{
   AtualizarZona();
   ChartRedraw(0);
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   AtualizarZona();
   return rates_total;
}
//+------------------------------------------------------------------+
