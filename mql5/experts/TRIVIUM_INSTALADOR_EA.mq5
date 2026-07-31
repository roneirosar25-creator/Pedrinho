//+------------------------------------------------------------------+
//| TRIVIUM_INSTALADOR_EA.mq5                                         |
//| TRIVIUM369 (c) 2026 - Pedrinho, 20/07/2026                        |
//|                                                                    |
//| Anexar um EA num grafico exige clicar/arrastar - Pedrinho nao tem  |
//| controle de mouse/teclado no MT5. Solucao: Ronei anexa este EA UMA|
//| VEZ (manual, qualquer grafico) e ele abre + configura sozinho      |
//| todos os outros graficos+EAs da lista em TRIVIUM_INSTALAR_LISTA.csv|
//| (formato: simbolo;timeframe;nome_template - sem cabecalho), usando |
//| ChartOpen + ChartApplyTemplate (os templates ja tem o EA e os      |
//| inputs configurados, ver MQL5/Profiles/Templates/TRIVIUM_ANEXAR_*).|
//|                                                                    |
//| Roda uma vez no OnInit, processa a lista inteira, loga o resultado |
//| linha a linha, e depois so fica ocioso (nao faz mais nada,         |
//| seguro deixar anexado indefinidamente).                            |
//|                                                                    |
//| NAO liga kill switch nenhum - so anexa/configura. Ligar a execucao |
//| de fato e sempre acao manual separada do Ronei (script LIGAR_*     |
//| dedicado, ou TRIVIUM369_LIGAR_TUDO_NOVOS.mq5 pra ligar os 6 de uma |
//| vez) - nunca automatico, mesmo com autorizacao verbal previa.      |
//|                                                                    |
//| LIMPEZA DE GRAFICOS ORFAOS (21/07/2026): 4 de 5 contas falharam    |
//| 100% (erro 4105 - limite de graficos abertos do terminal) numa     |
//| rodada onde so faltava anexar 14 graficos novos. Antes de tentar   |
//| abrir mais nada, este EA agora fecha janelas de grafico VAZIAS     |
//| (0 objetos E 0 indicadores - nenhum EA nosso cria painel sem       |
//| desenhar pelo menos 1 objeto no OnInit, entao "vazio" e prova      |
//| segura de que nao tem nada relevante rodando ali). NUNCA fecha o   |
//| proprio grafico onde esta anexado, nem qualquer grafico com objeto |
//| ou indicador (mesmo que nao seja um EA nosso - erra pro lado       |
//| seguro, prefere deixar aberto de mais a fechar algo errado).       |
//|                                                                    |
//| IDEMPOTENCIA (21/07/2026, mesmo dia - bug achado ao vivo): rodar   |
//| o instalador 2x na MESMA conta estava criando graficos DUPLICADOS  |
//| a cada vez (ChartOpen nao reaproveita, sempre abre janela nova) -  |
//| uma conta que ja estava 82/82 caiu pra 52/82 na segunda rodada por|
//| estourar o limite de graficos so de duplicar tudo de novo. Agora,  |
//| antes de ChartOpen, procura um grafico JA aberto com o mesmo       |
//| simbolo+timeframe (ChartFirst/ChartNext) - se achar e ja tiver     |
//| objeto (painel do EA ja configurado), REAPROVEITA e pula (nao      |
//| duplica). So chama ChartOpen se realmente nao existir nenhum.      |
//+------------------------------------------------------------------+
#property copyright "TRIVIUM369 (c) 2026"
#property version   "1.20"

#define ARQUIVO_LISTA "TRIVIUM_INSTALAR_LISTA.csv"
#define ARQUIVO_LOG   "TRIVIUM_INSTALADOR_LOG.txt"

ENUM_TIMEFRAMES StringParaTimeframe(string s)
{
   StringToUpper(s);
   if(s=="M1") return PERIOD_M1;   if(s=="M2") return PERIOD_M2;
   if(s=="M5") return PERIOD_M5;   if(s=="M15") return PERIOD_M15;
   if(s=="M30") return PERIOD_M30; if(s=="H1") return PERIOD_H1;
   if(s=="H4") return PERIOD_H4;   if(s=="D1") return PERIOD_D1;
   return PERIOD_H1;
}

void LogInstalador(string linha)
{
   Print(linha);
   int h = FileOpen(ARQUIVO_LOG, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h != INVALID_HANDLE) { FileSeek(h, 0, SEEK_END); FileWrite(h, linha); FileClose(h); }
}

void LimparGraficosOrfaos()
{
   long meuChartId = ChartID();
   long chartId = ChartFirst();
   int total = 0, fechados = 0;
   while(chartId >= 0)
   {
      total++;
      long proximo = ChartNext(chartId); // pega o proximo ANTES de fechar (fechar invalida a iteracao)
      if(chartId != meuChartId)
      {
         int objetos = ObjectsTotal(chartId, -1, -1);
         int indicadores = ChartIndicatorsTotal(chartId, 0);
         if(objetos == 0 && indicadores == 0)
         {
            string sym = ChartSymbol(chartId);
            ENUM_TIMEFRAMES per = ChartPeriod(chartId);
            if(ChartClose(chartId))
            {
               fechados++;
               LogInstalador(StringFormat("LIMPEZA: fechado grafico vazio %s %s (chart_id=%d)", sym, EnumToString(per), chartId));
            }
         }
      }
      chartId = proximo;
   }
   LogInstalador(StringFormat("LIMPEZA: %d de %d graficos abertos eram vazios e foram fechados.", fechados, total));
}

// Procura um grafico JA aberto com o mesmo simbolo+timeframe. Retorna o
// chart_id se achar (0 se nao achar nenhum).
long ProcurarGraficoExistente(string simbolo, ENUM_TIMEFRAMES tf)
{
   long chartId = ChartFirst();
   while(chartId >= 0)
   {
      if(ChartSymbol(chartId) == simbolo && ChartPeriod(chartId) == tf)
         return chartId;
      chartId = ChartNext(chartId);
   }
   return 0;
}

// Fecha duplicatas (mesmo simbolo+timeframe abertos em mais de um
// grafico) - so as contas com duplicatas de rodadas anteriores (antes
// da correcao de idempotencia acima) chegam a bater no limite de
// graficos do terminal (~100). Mantem sempre o com MAIS objetos (o
// mais "configurado", provavelmente o EA de verdade) e fecha o resto.
void FecharDuplicatas()
{
   long ids[]; string chaves[]; int totalUnicos = 0;
   long chartId = ChartFirst();
   long meuChartId = ChartID();
   while(chartId >= 0)
   {
      ArrayResize(ids, totalUnicos + 1);
      ArrayResize(chaves, totalUnicos + 1);
      ids[totalUnicos] = chartId;
      chaves[totalUnicos] = ChartSymbol(chartId) + "_" + EnumToString(ChartPeriod(chartId));
      totalUnicos++;
      chartId = ChartNext(chartId);
   }

   int fechados = 0;
   bool jaProcessado[];
   ArrayResize(jaProcessado, totalUnicos);
   ArrayInitialize(jaProcessado, false);

   for(int i = 0; i < totalUnicos; i++)
   {
      if(jaProcessado[i]) continue;
      // acha todos os indices com a mesma chave (simbolo+timeframe)
      int grupo[]; int totalGrupo = 0;
      for(int j = i; j < totalUnicos; j++)
      {
         if(chaves[j] == chaves[i])
         {
            ArrayResize(grupo, totalGrupo + 1);
            grupo[totalGrupo] = j;
            totalGrupo++;
            jaProcessado[j] = true;
         }
      }
      if(totalGrupo <= 1) continue; // sem duplicata

      // acha o com mais objetos (o "de verdade") pra manter
      int melhorIdx = grupo[0], melhorObjetos = -1;
      for(int k = 0; k < totalGrupo; k++)
      {
         int objetos = ObjectsTotal(ids[grupo[k]], -1, -1);
         if(objetos > melhorObjetos) { melhorObjetos = objetos; melhorIdx = grupo[k]; }
      }

      for(int k = 0; k < totalGrupo; k++)
      {
         int idx = grupo[k];
         if(idx == melhorIdx) continue;
         if(ids[idx] == meuChartId) continue; // nunca fecha o proprio grafico
         if(ChartClose(ids[idx]))
         {
            fechados++;
            LogInstalador(StringFormat("LIMPEZA DUPLICATA: fechado %s (chart_id=%d) - mantido chart_id=%d com %d objetos",
               chaves[idx], ids[idx], ids[melhorIdx], melhorObjetos));
         }
      }
   }
   LogInstalador(StringFormat("LIMPEZA DUPLICATA: %d graficos duplicados fechados.", fechados));
}

void ProcessarInstalacao()
{
   if(!FileIsExist(ARQUIVO_LISTA, FILE_COMMON))
   {
      LogInstalador("TRIVIUM_INSTALADOR: arquivo " + ARQUIVO_LISTA + " nao encontrado em Files\\Common. Nada a instalar.");
      return;
   }

   int h = FileOpen(ARQUIVO_LISTA, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h == INVALID_HANDLE) { LogInstalador("TRIVIUM_INSTALADOR: falha ao abrir " + ARQUIVO_LISTA); return; }

   int total = 0, sucesso = 0;
   while(!FileIsEnding(h))
   {
      string linha = FileReadString(h);
      if(StringLen(linha) < 3) continue;
      string campos[];
      int n = StringSplit(linha, ';', campos);
      if(n < 3) continue;
      total++;

      string simbolo = campos[0];
      ENUM_TIMEFRAMES tf = StringParaTimeframe(campos[1]);
      string nomeTemplate = campos[2];

      if(!SymbolSelect(simbolo, true))
      {
         LogInstalador(StringFormat("  [%d] FALHA: simbolo %s nao encontrado no Market Watch", total, simbolo));
         continue;
      }

      long chartId = ProcurarGraficoExistente(simbolo, tf);
      if(chartId != 0 && ObjectsTotal(chartId, -1, -1) > 0)
      {
         sucesso++;
         LogInstalador(StringFormat("  [%d] JA INSTALADO: %s %s <- %s (chart_id=%d, reaproveitado, nao duplicado)", total, simbolo, campos[1], nomeTemplate, chartId));
         continue;
      }

      if(chartId == 0)
      {
         chartId = ChartOpen(simbolo, tf);
         if(chartId == 0)
         {
            LogInstalador(StringFormat("  [%d] FALHA: ChartOpen(%s, %s) retornou 0 (erro %d)", total, simbolo, campos[1], GetLastError()));
            continue;
         }
         Sleep(300); // da tempo do grafico carregar antes de aplicar o template
      }

      bool ok = ChartApplyTemplate(chartId, nomeTemplate + ".tpl");
      if(ok)
      {
         sucesso++;
         LogInstalador(StringFormat("  [%d] OK: %s %s <- %s (chart_id=%d)", total, simbolo, campos[1], nomeTemplate, chartId));
      }
      else
      {
         LogInstalador(StringFormat("  [%d] FALHA ao aplicar template: %s %s <- %s (erro %d)", total, simbolo, campos[1], nomeTemplate, GetLastError()));
      }
   }
   FileClose(h);
   LogInstalador(StringFormat("TRIVIUM_INSTALADOR: concluido - %d de %d instalados com sucesso.", sucesso, total));
}

int OnInit()
{
   LogInstalador("=== TRIVIUM_INSTALADOR iniciado " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES) + " | conta " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " (" + AccountInfoString(ACCOUNT_SERVER) + ") ===");
   LimparGraficosOrfaos();
   FecharDuplicatas();
   ProcessarInstalacao();
   LogInstalador("=== TRIVIUM_INSTALADOR: graficos anexados, kill switches continuam DESLIGADOS - rode TRIVIUM369_LIGAR_TUDO_NOVOS.mq5 quando quiser autorizar de fato ===");
   return INIT_SUCCEEDED;
}

void OnTick() {} // ocioso depois de instalar - seguro deixar anexado
//+------------------------------------------------------------------+
