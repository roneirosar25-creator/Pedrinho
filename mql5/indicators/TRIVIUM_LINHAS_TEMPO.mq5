//+------------------------------------------------------------------+
//| TRIVIUM_LINHAS_TEMPO.mq5                                          |
//| TRIVIUM369 (c) 2026 - Pedrinho, 17/07/2026                        |
//|                                                                    |
//| Pedido do Ronei (17/07 noite): separar visualmente as semanas e   |
//| os dias em qualquer timeframe abaixo de D1, pra ajudar a ler onde |
//| comecou cada perna do movimento - junto com VWAP e Volume Anomalo |
//| (indicadores separados, TRIVIUM_VWAP.mq5 / TRIVIUM_VOLUME_        |
//| ANOMALO.mq5) isso marca contexto de abertura de dia/semana mais   |
//| pontos de forca, sem precisar decorar calendario.                 |
//|                                                                    |
//| Cor casada com a paleta que ja existe (TRIVIUM_MEDIAS_7 / TRIVIUM_|
//| DESENHAR_SR): SEMANA = cor do D1 (BlueViolet/roxo, igual MA200).  |
//| DIA = cor do H1 (Aqua, igual MA100). Nao pode divergir - se mudar |
//| uma paleta, mudar a outra tambem.                                 |
//|                                                                    |
//| So visual (linha vertical OBJ_VLINE), nao abre posicao. Roda      |
//| sozinho via OnCalculate, so redesenha quando fecha uma vela D1    |
//| nova (nao trava o grafico a cada tick).                           |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0

input group "=== O que mostrar ==="
input bool  InpMostrarLinhaSemana = true;
input bool  InpMostrarLinhaDia    = true;

input group "=== Alcance (quantas velas D1 pra tras) ==="
input int   InpBarrasD1 = 90;   // ~3 meses de historico

input group "=== Cores (casadas com TRIVIUM_MEDIAS_7 / TRIVIUM_DESENHAR_SR) ==="
input color InpCorSemana   = clrBlueViolet;  // igual D1 / MA200
input color InpCorDia      = clrAqua;        // igual H1 / MA100
input int   InpLarguraSemana = 2;
input int   InpLarguraDia    = 1;
input ENUM_LINE_STYLE InpEstiloSemana = STYLE_SOLID;
input ENUM_LINE_STYLE InpEstiloDia    = STYLE_DOT;

#define PREFIXO_DIA    "TRIVIUM_TEMPO_DIA_"
#define PREFIXO_SEMANA "TRIVIUM_TEMPO_SEMANA_"

int g_UltimoTotalD1 = -1;

//+------------------------------------------------------------------+
void RemoverLinhasAntigas()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nome = ObjectName(0, i, 0, -1);
      if(StringFind(nome, PREFIXO_DIA) == 0 || StringFind(nome, PREFIXO_SEMANA) == 0)
         ObjectDelete(0, nome);
   }
}

//+------------------------------------------------------------------+
void CriarLinha(string nome, datetime tempo, color cor, int largura, ENUM_LINE_STYLE estilo, string tooltip)
{
   ObjectCreate(0, nome, OBJ_VLINE, 0, tempo, 0);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
   ObjectSetInteger(0, nome, OBJPROP_WIDTH, largura);
   ObjectSetInteger(0, nome, OBJPROP_STYLE, estilo);
   ObjectSetInteger(0, nome, OBJPROP_BACK, true);
   ObjectSetInteger(0, nome, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, nome, OBJPROP_TOOLTIP, tooltip);
}

//+------------------------------------------------------------------+
void DesenharLinhasDeTempo()
{
   RemoverLinhasAntigas();
   if(!InpMostrarLinhaSemana && !InpMostrarLinhaDia) return;

   datetime tempos[];
   ArraySetAsSeries(tempos, true);

   int copiados = 0;
   for(int tentativa = 0; tentativa < 10; tentativa++)
   {
      copiados = CopyTime(_Symbol, PERIOD_D1, 0, InpBarrasD1, tempos);
      if(copiados > 1) break;
      Sleep(300);
   }
   if(copiados < 2)
   {
      Print("AVISO TRIVIUM_LINHAS_TEMPO: historico D1 insuficiente (", copiados, " velas) - tenta de novo depois.");
      return;
   }

   // percorre do mais antigo pro mais novo pra detectar virada de semana
   // (dia_da_semana cai ou repete em relacao ao anterior = comecou semana nova)
   int diaSemanaAnterior = -1;
   int diasDesenhados = 0, semanasDesenhadas = 0;

   for(int i = copiados - 1; i >= 0; i--)
   {
      MqlDateTime dt;
      TimeToStruct(tempos[i], dt);

      if(InpMostrarLinhaDia)
      {
         string nomeDia = StringFormat("%s%d", PREFIXO_DIA, (long)tempos[i]);
         string tooltipDia = StringFormat("Abertura do dia: %s", TimeToString(tempos[i], TIME_DATE));
         CriarLinha(nomeDia, tempos[i], InpCorDia, InpLarguraDia, InpEstiloDia, tooltipDia);
         diasDesenhados++;
      }

      if(InpMostrarLinhaSemana && diaSemanaAnterior >= 0 && dt.day_of_week <= diaSemanaAnterior)
      {
         string nomeSemana = StringFormat("%s%d", PREFIXO_SEMANA, (long)tempos[i]);
         string tooltipSemana = StringFormat("Abertura da semana: %s", TimeToString(tempos[i], TIME_DATE));
         CriarLinha(nomeSemana, tempos[i], InpCorSemana, InpLarguraSemana, InpEstiloSemana, tooltipSemana);
         semanasDesenhadas++;
      }
      diaSemanaAnterior = dt.day_of_week;
   }

   ChartRedraw(0);
   Print(StringFormat("TRIVIUM_LINHAS_TEMPO: %d linhas de dia + %d linhas de semana desenhadas em %s (%d velas D1 analisadas).",
         diasDesenhados, semanasDesenhadas, _Symbol, copiados));
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_UltimoTotalD1 = -1;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   RemoverLinhasAntigas();
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   int totalD1 = iBars(_Symbol, PERIOD_D1);
   if(totalD1 != g_UltimoTotalD1)
   {
      g_UltimoTotalD1 = totalD1;
      DesenharLinhasDeTempo();
   }
   return(rates_total);
}
//+------------------------------------------------------------------+
