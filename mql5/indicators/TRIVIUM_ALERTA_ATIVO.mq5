//+------------------------------------------------------------------+
//| TRIVIUM_ALERTA_ATIVO.mq5                                          |
//| TRIVIUM369 (c) 2026 - Pedrinho, 16/07/2026                        |
//|                                                                    |
//| Item #1 do roadmap: alerta ativo (som + popup) quando o preco se   |
//| aproxima de QUALQUER linha horizontal desenhada pelas ferramentas  |
//| TRIVIUM (S/R fractal, Preco Redondo/Cheio, Pivos, PDH/PDL, Painel  |
//| Completo) - elimina precisar ficar olhando a tela o tempo todo.    |
//|                                                                    |
//| So dispara UMA VEZ por linha ate o preco se afastar e reaproximar  |
//| de novo (evita alerta repetido a cada tick perto da mesma linha).  |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

input bool   InpSomAtivo         = true;
input string InpArquivoSom       = "alert.wav"; // som padrao do MT5 - troque se quiser outro
input double InpDistanciaPct     = 0.10;  // % do preco - distancia pra disparar o alerta
input int    InpCooldownSegundos = 120;   // nao repete alerta da MESMA linha antes desse tempo

// Prefixos de todos os objetos de linha horizontal criados pelas
// ferramentas TRIVIUM ate agora - adicionar aqui se criar ferramenta nova.
string g_prefixos[] = {
   "TRIVIUM_SR_",      // suporte/resistencia fractal
   "TRIVIUM_BOLA_",    // preco redondo / preco cheio
   "TRIVIUM_PIVO_",    // pivos classicos
   "TRIVIUM_PDHL_",    // PDH/PDL
   "TRIVIUM_PAINEL_"   // painel completo (SR + PDH/PDL + preco cheio embutidos)
};

// Controle de cooldown por linha - arrays paralelos (nome + hora do ultimo alerta)
string   g_alertNome[];
datetime g_alertHora[];

int AcharIndiceAlerta(string nome)
{
   for(int i = 0; i < ArraySize(g_alertNome); i++)
      if(g_alertNome[i] == nome) return i;
   return -1;
}

void RegistrarAlerta(string nome)
{
   int idx = AcharIndiceAlerta(nome);
   if(idx >= 0) { g_alertHora[idx] = TimeCurrent(); return; }
   int n = ArraySize(g_alertNome);
   ArrayResize(g_alertNome, n + 1);
   ArrayResize(g_alertHora, n + 1);
   g_alertNome[n] = nome;
   g_alertHora[n] = TimeCurrent();
}

bool EmCooldown(string nome)
{
   int idx = AcharIndiceAlerta(nome);
   if(idx < 0) return false;
   return (TimeCurrent() - g_alertHora[idx]) < InpCooldownSegundos;
}

bool TemPrefixoValido(string nome)
{
   for(int i = 0; i < ArraySize(g_prefixos); i++)
      if(StringFind(nome, g_prefixos[i]) == 0) return true;
   return false;
}

void VerificarProximidade()
{
   double precoAtual = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(precoAtual <= 0) return;
   double tolerancia = precoAtual * InpDistanciaPct / 100.0;

   int total = ObjectsTotal(0, 0, OBJ_HLINE);
   for(int i = 0; i < total; i++)
   {
      string nome = ObjectName(0, i, 0, OBJ_HLINE);
      if(!TemPrefixoValido(nome)) continue;

      double nivel = ObjectGetDouble(0, nome, OBJPROP_PRICE, 0);
      if(nivel <= 0) continue;

      double distancia = MathAbs(precoAtual - nivel);
      if(distancia > tolerancia)
      {
         // preco se afastou - libera esse nome pra alertar de novo no futuro
         int idx = AcharIndiceAlerta(nome);
         if(idx >= 0 && (TimeCurrent() - g_alertHora[idx]) >= InpCooldownSegundos)
         {
            // ja passou do cooldown mesmo longe - remove do controle (limpeza, opcional)
         }
         continue;
      }

      if(EmCooldown(nome)) continue;

      string texto = ObjectGetString(0, nome, OBJPROP_TEXT);
      if(texto == "") texto = nome;
      string msg = StringFormat("TRIVIUM ALERTA: %s | preco atual %s perto de %s (dist %.2f%%)",
         texto, DoubleToString(precoAtual, _Digits), DoubleToString(nivel, _Digits),
         distancia / precoAtual * 100.0);

      Alert(msg);
      Print(msg);
      if(InpSomAtivo) PlaySound(InpArquivoSom);
      RegistrarAlerta(nome);
   }
}

int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "TRIVIUM_ALERTA_ATIVO");
   EventSetTimer(2); // checa a cada 2s, nao precisa ser todo tick
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   VerificarProximidade();
}

int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                 const double &open[], const double &high[], const double &low[], const double &close[],
                 const long &tick_volume[], const long &volume[], const int &spread[])
{
   return rates_total;
}
//+------------------------------------------------------------------+
