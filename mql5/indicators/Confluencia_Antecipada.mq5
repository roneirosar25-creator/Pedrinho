//+------------------------------------------------------------------+
//|                                       Confluencia_Antecipada.mq5 |
//|  TRIVIUM369 - Gatilho de entrada antecipado por confluencia      |
//|  Substitui cruzamento de EMA (atrasado) por zonas de reversao:   |
//|  Suporte/Resistencia (fractais) + Fibonacci + Bollinger +        |
//|  Envelope, so dispara com vela de rejeicao confirmando no local  |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 - Ronei Rosar"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   2

#property indicator_label1  "Compra Antecipada"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "Venda Antecipada"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//--- inputs
input int    InpFractalRange     = 2;     // Barras de cada lado p/ fractal (padrao 2 = fractal de 5 velas)
input int    InpZonasMax         = 8;     // Quantas zonas de S/R manter em memoria
input double InpZonaTolerPct     = 0.06;  // Tolerancia p/ agrupar niveis (% do preco)
input int    InpSwingLookback    = 150;   // Velas pra tras p/ achar o swing do Fibonacci
input int    InpBBPeriod         = 20;
input double InpBBDesvio         = 2.0;
input int    InpEnvPeriod        = 20;
input double InpEnvPct           = 0.15;  // % de desvio do envelope
input int    InpRSIPeriod        = 14;
input double InpRSISobrevenda    = 30.0;
input double InpRSISobrecompra   = 70.0;
input int    InpConfluenciaMin   = 2;     // Minimo de zonas batendo juntas p/ validar sinal
input double InpRejeicaoMinPct   = 0.55;  // % do range da vela que tem que ser "pavio" de rejeicao
input bool   InpDesenharZonas    = true;  // Desenhar linhas de S/R e Fibo no grafico

//--- buffers
double BufBuy[];
double BufSell[];
double BufScore[];

//--- handles
int hBands, hEnv, hRSI;

//--- fractais guardados (preco + tempo)
double fracHighs[]; datetime fracHighTimes[];
double fracLows[];  datetime fracLowTimes[];

#define OBJ_PREFIX "CONF_"

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufBuy,   INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,  INDICATOR_DATA);
   SetIndexBuffer(2, BufScore, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 233); // seta pra cima
   PlotIndexSetInteger(1, PLOT_ARROW, 234); // seta pra baixo
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   hBands = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDesvio, PRICE_CLOSE);
   hEnv   = iEnvelopes(_Symbol, _Period, InpEnvPeriod, 0, MODE_SMA, PRICE_CLOSE, InpEnvPct);
   hRSI   = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);

   if(hBands==INVALID_HANDLE || hEnv==INVALID_HANDLE || hRSI==INVALID_HANDLE)
   {
      Print("[CONFLUENCIA] Erro criando handles de indicadores");
      return INIT_FAILED;
   }

   ArrayResize(fracHighs, 0); ArrayResize(fracHighTimes, 0);
   ArrayResize(fracLows,  0); ArrayResize(fracLowTimes,  0);

   IndicatorSetString(INDICATOR_SHORTNAME, "Confluencia Antecipada");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hBands);
   IndicatorRelease(hEnv);
   IndicatorRelease(hRSI);
   if(InpDesenharZonas) ObjectsDeleteAll(0, OBJ_PREFIX);
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double Buf(int handle, int buffer, int shift)
{
   double v[1];
   if(CopyBuffer(handle, buffer, shift, 1, v) != 1) return 0.0;
   return v[0];
}

// registra um novo fractal na lista, sem duplicar nivel muito proximo
void RegistrarFractal(double &lista[], datetime &tempos[], double preco, datetime tempo)
{
   int n = ArraySize(lista);
   double tolerAbs = preco * InpZonaTolerPct/100.0;
   for(int i=0;i<n;i++)
      if(MathAbs(lista[i]-preco) < tolerAbs) return; // ja tem nivel parecido

   ArrayResize(lista, n+1);
   ArrayResize(tempos, n+1);
   lista[n]  = preco;
   tempos[n] = tempo;

   // mantem so os ultimos InpZonasMax (remove o mais antigo)
   if(ArraySize(lista) > InpZonasMax)
   {
      for(int i=0;i<ArraySize(lista)-1;i++){ lista[i]=lista[i+1]; tempos[i]=tempos[i+1]; }
      ArrayResize(lista, InpZonasMax);
      ArrayResize(tempos, InpZonasMax);
   }
}

// distancia minima (%) do preco a qualquer zona da lista
bool PertoDeAlgumNivel(const double &lista[], double preco, double tolerPct, double &nivelAchado)
{
   int n = ArraySize(lista);
   double tolerAbs = preco * tolerPct/100.0;
   for(int i=0;i<n;i++)
   {
      if(MathAbs(lista[i]-preco) <= tolerAbs)
      {
         nivelAchado = lista[i];
         return true;
      }
   }
   return false;
}

// acha o swing mais recente (ultimo fractal alto e ultimo fractal baixo dentro do lookback)
bool AcharSwingFibo(int totalBars, double &swingHigh, double &swingLow, datetime &tHigh, datetime &tLow)
{
   int nH = ArraySize(fracHighs), nL = ArraySize(fracLows);
   if(nH==0 || nL==0) return false;
   swingHigh = fracHighs[nH-1]; tHigh = fracHighTimes[nH-1];
   swingLow  = fracLows[nL-1];  tLow  = fracLowTimes[nL-1];
   return true;
}

// desenha uma linha horizontal (zona) no grafico
void DesenharLinha(string nome, double preco, color cor, int estilo, string texto)
{
   if(!InpDesenharZonas) return;
   if(ObjectFind(0, nome) < 0)
      ObjectCreate(0, nome, OBJ_HLINE, 0, 0, preco);
   ObjectSetDouble(0, nome, OBJPROP_PRICE, preco);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_STYLE, estilo);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
   ObjectSetString(0, nome, OBJPROP_TOOLTIP, texto);
}

//+------------------------------------------------------------------+
//| Deteccao de fractais (padrao 5 velas: InpFractalRange de cada lado)|
//+------------------------------------------------------------------+
void AtualizarFractais(int shiftFechado)
{
   int r = InpFractalRange;
   int centro = shiftFechado + r; // vela candidata a fractal, cercada por r velas de cada lado

   double highC = iHigh(_Symbol, _Period, centro);
   double lowC  = iLow(_Symbol, _Period, centro);
   bool ehFractalAlto = true, ehFractalBaixo = true;

   for(int i=1;i<=r;i++)
   {
      if(iHigh(_Symbol,_Period,centro-i) >= highC || iHigh(_Symbol,_Period,centro+i) >= highC) ehFractalAlto = false;
      if(iLow(_Symbol,_Period,centro-i)  <= lowC  || iLow(_Symbol,_Period,centro+i)  <= lowC)  ehFractalBaixo = false;
   }

   datetime tCentro = iTime(_Symbol, _Period, centro);
   if(ehFractalAlto) RegistrarFractal(fracHighs, fracHighTimes, highC, tCentro);
   if(ehFractalBaixo) RegistrarFractal(fracLows, fracLowTimes, lowC, tCentro);
}

//+------------------------------------------------------------------+
//| Vela de rejeicao (pavio grande na direcao contraria ao rompimento)|
//+------------------------------------------------------------------+
bool RejeicaoAlta(int shift) // pavio inferior grande = rejeitou queda, potencial compra
{
   double o=iOpen(_Symbol,_Period,shift), c=iClose(_Symbol,_Period,shift);
   double h=iHigh(_Symbol,_Period,shift), l=iLow(_Symbol,_Period,shift);
   double range = h-l;
   if(range<=0) return false;
   double pavioInferior = MathMin(o,c) - l;
   return (pavioInferior/range) >= InpRejeicaoMinPct;
}

bool RejeicaoBaixa(int shift) // pavio superior grande = rejeitou alta, potencial venda
{
   double o=iOpen(_Symbol,_Period,shift), c=iClose(_Symbol,_Period,shift);
   double h=iHigh(_Symbol,_Period,shift), l=iLow(_Symbol,_Period,shift);
   double range = h-l;
   if(range<=0) return false;
   double pavioSuperior = h - MathMax(o,c);
   return (pavioSuperior/range) >= InpRejeicaoMinPct;
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
{
   int minBars = MathMax(InpBBPeriod, MathMax(InpEnvPeriod, InpSwingLookback)) + InpFractalRange + 5;
   if(rates_total < minBars) return 0;

   int start = (prev_calculated>1) ? prev_calculated-2 : InpFractalRange+2;
   if(start < InpFractalRange+2) start = InpFractalRange+2;

   for(int idx = start; idx < rates_total - InpFractalRange; idx++)
   {
      int shift = rates_total - 1 - idx; // shift estilo iHigh/iLow (0 = vela atual)

      BufBuy[idx]  = EMPTY_VALUE;
      BufSell[idx] = EMPTY_VALUE;
      BufScore[idx] = 0;

      if(shift < 1) continue; // so avalia velas fechadas

      // 1) atualiza lista de fractais usando essa posicao como possivel centro
      AtualizarFractais(shift);

      // 2) monta o swing do fibonacci
      double swingHigh, swingLow; datetime tH, tL;
      bool temSwing = AcharSwingFibo(InpSwingLookback, swingHigh, swingLow, tH, tL);

      double preco = close[idx];
      double tolerPct = InpZonaTolerPct;

      // 3) confluencias
      int score = 0;
      bool pertoSR=false, pertoFibo=false, pertoBB=false, pertoEnv=false;
      double nivel=0.0;

      if(PertoDeAlgumNivel(fracHighs, preco, tolerPct, nivel)) { pertoSR=true; score++; }
      if(!pertoSR && PertoDeAlgumNivel(fracLows, preco, tolerPct, nivel)) { pertoSR=true; score++; }

      if(temSwing && swingHigh>swingLow)
      {
         double amplitude = swingHigh - swingLow;
         double fibLevels[5];
         fibLevels[0] = swingHigh - amplitude*0.236;
         fibLevels[1] = swingHigh - amplitude*0.382;
         fibLevels[2] = swingHigh - amplitude*0.5;
         fibLevels[3] = swingHigh - amplitude*0.618;
         fibLevels[4] = swingHigh - amplitude*0.786;
         double tolerAbs = preco*tolerPct/100.0;
         for(int f=0; f<5; f++)
            if(MathAbs(fibLevels[f]-preco) <= tolerAbs){ pertoFibo=true; break; }
         if(pertoFibo) score++;
      }

      double bbUp = Buf(hBands,1,shift), bbLo = Buf(hBands,2,shift);
      double tolerAbs2 = preco*tolerPct/100.0;
      if(bbUp>0 && MathAbs(close[idx]-bbUp)<=tolerAbs2) { pertoBB=true; score++; }
      if(bbLo>0 && MathAbs(close[idx]-bbLo)<=tolerAbs2) { pertoBB=true; score++; }

      double envUp = Buf(hEnv,0,shift), envLo = Buf(hEnv,1,shift);
      if(envUp>0 && MathAbs(close[idx]-envUp)<=tolerAbs2) { pertoEnv=true; score++; }
      if(envLo>0 && MathAbs(close[idx]-envLo)<=tolerAbs2) { pertoEnv=true; score++; }

      BufScore[idx] = score;

      if(score < InpConfluenciaMin) continue;

      double rsi = Buf(hRSI, 0, shift);
      bool proximoTopo  = (close[idx] >= bbUp || close[idx] >= envUp) || (temSwing && MathAbs(swingHigh-preco) <= tolerAbs2*2);
      bool proximoFundo = (close[idx] <= bbLo || close[idx] <= envLo) || (temSwing && MathAbs(swingLow-preco)  <= tolerAbs2*2);

      // 4) so confirma com vela de rejeicao no local (evita pegar faca caindo)
      if(proximoFundo && RejeicaoAlta(shift) && rsi <= InpRSISobrevenda+10.0)
         BufBuy[idx] = low[idx] - (high[idx]-low[idx])*0.3;

      if(proximoTopo && RejeicaoBaixa(shift) && rsi >= InpRSISobrecompra-10.0)
         BufSell[idx] = high[idx] + (high[idx]-low[idx])*0.3;
   }

   // desenha zonas atuais (so na ultima chamada, pra nao pesar)
   if(InpDesenharZonas)
   {
      for(int i=0;i<ArraySize(fracHighs);i++)
         DesenharLinha(OBJ_PREFIX+"R_"+IntegerToString(i), fracHighs[i], clrOrange, STYLE_DOT, "Resistencia (fractal)");
      for(int i=0;i<ArraySize(fracLows);i++)
         DesenharLinha(OBJ_PREFIX+"S_"+IntegerToString(i), fracLows[i], clrAqua, STYLE_DOT, "Suporte (fractal)");

      double swingHigh, swingLow; datetime tH, tL;
      if(AcharSwingFibo(InpSwingLookback, swingHigh, swingLow, tH, tL) && swingHigh>swingLow)
      {
         double amplitude = swingHigh - swingLow;
         double niveis[5] = {0.236,0.382,0.5,0.618,0.786};
         for(int f=0; f<5; f++)
            DesenharLinha(OBJ_PREFIX+"FIBO_"+IntegerToString(f), swingHigh-amplitude*niveis[f], clrGold, STYLE_DASH,
                           "Fibo "+DoubleToString(niveis[f]*100,1)+"%");
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
