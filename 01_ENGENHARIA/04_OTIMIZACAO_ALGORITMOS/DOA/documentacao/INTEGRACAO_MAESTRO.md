# Integração do DOA no MAESTRO — guia técnico

> Para: **Cláudio** (implementador). Todo código aqui usa a **API correta** da classe `C_AO_DOA_dream`.

---

## 1. Modelo mental

DOA otimiza um **vetor de números reais** (`coords` dimensões). Cada dimensão = um input do EA.
A "fitness" é uma métrica que **você** calcula rodando um backtest do MAESTRO com aquele vetor.

```
candidato (a[i].c[]) ──► BacktestMAESTRO() ──► métrica ──► a[i].f
```

---

## 2. Esqueleto mínimo (otimização offline de parâmetros)

```cpp
#include <Math\AOs\PopulationAO\#C_AO.mqh>
#include <Math\AOs\PopulationAO\AO_DOA_DreamOptimizationAlgorithm.mqh>

void OnStart()
{
  C_AO_DOA_dream ao;

  // (1) parâmetros do DOA (opcional — tem defaults)
  ao.params[0].val = 60;    // popSize
  ao.params[1].val = 6;     // numGroups
  ao.params[2].val = 0.9;   // explorationRate  (0.9 deixa mais tempo p/ refino que 0.99)
  ao.params[3].val = 0.5;   // forgettingProb   (tunar entre 0.3 e 0.7)
  ao.SetParams();

  // (2) limites de CADA input do MAESTRO (um índice por parâmetro)
  double rangeMin [] = {  5,  20,  50,  10 };   // mínimos
  double rangeMax [] = { 50,  50,  80, 200 };   // máximos
  double rangeStep[] = {  1,   1,   1,   5 };   // passo (discretização)

  // (3) orçamento. epochs = avaliações_totais / popSize
  int popSize = (int)ao.params[0].val;
  int totalEvals = 15000;
  int epochs = totalEvals / popSize;            // ~250 épocas

  if (!ao.Init(rangeMin, rangeMax, rangeStep, epochs)) { Print("Init falhou"); return; }

  // (4) loop de otimização
  for (int e = 1; e <= epochs && !IsStopped(); e++)
  {
    ao.Moving();                                // gera candidatos em ao.a[i].c[]

    for (int i = 0; i < popSize; i++)
      ao.a[i].f = BacktestMAESTRO(ao.a[i].c);   // <<< VOCÊ implementa isto

    ao.Revision();                              // consolida melhores

    if (e % 25 == 0) Print("época ", e, "  melhor fitness = ", ao.fB);
  }

  // (5) resultado
  Print("=== Parâmetros ótimos (fitness = ", ao.fB, ") ===");
  for (int j = 0; j < ArraySize(rangeMin); j++)
    Print("  param[", j, "] = ", ao.cB[j]);    // <<< ao.cB[j], NÃO ao.cB.c[j]
}
```

> ⚠️ Pontos onde a versão local errava e que aqui estão certos:
> melhor fitness = **`ao.fB`**; melhor vetor = **`ao.cB[j]`** (array). `ao.cB.f`/`ao.cB.c[j]` não existem.

---

## 3. A parte que realmente importa: função de fitness anti-overfit

Um otimizador bom **vai cravar o ótimo do backtest** — que quase sempre é ruído super-ajustado.
A defesa é a *função-objetivo*, não o algoritmo. Esqueleto recomendado:

```cpp
double BacktestMAESTRO(const double &p[])
{
  // 1) roda DOIS períodos com os MESMOS parâmetros p[]
  Result in  = RunBacktest(p, IN_SAMPLE_START,  IN_SAMPLE_END);    // treino
  Result out = RunBacktest(p, OUT_SAMPLE_START, OUT_SAMPLE_END);   // validação (nunca vista)

  // 2) exige robustez mínima (corta lixo cedo)
  if (in.trades < 30 || out.trades < 10) return -1e9;             // amostra insuficiente

  // 3) penaliza discrepância in→out (sintoma de overfit)
  double overfitPenalty = MathMax(0.0, (in.profit - out.profit) - 100.0);

  // 4) score combinado: recompensa lucro consistente, pune drawdown
  double score = (in.profit + out.profit) / 2.0
               - MathSqrt(MathMax(in.maxDD,1e-6) * MathMax(out.maxDD,1e-6)) / 10.0
               - overfitPenalty;
  return score;
}
```

Use métricas estáveis (Sharpe, Calmar, profit factor) em vez de lucro bruto sempre que possível.

---

## 4. Walk-forward (obrigatório antes de confiar)

Não otimize num período só. Otimize numa janela, **valide na janela seguinte**, repita e
some os resultados *fora-da-amostra*:

```cpp
double WalkForward()
{
  double oosTotal = 0.0;                         // out-of-sample acumulado
  for (int w = 0; w < NUM_JANELAS; w++)
  {
    C_AO_DOA_dream ao;  ao.SetParams();
    ao.Init(rangeMin, rangeMax, rangeStep, epochs);

    for (int e = 1; e <= epochs; e++) {           // otimiza só na janela de TREINO w
      ao.Moving();
      for (int i = 0; i < popSize; i++)
        ao.a[i].f = RunBacktest(ao.a[i].c, train_start[w], train_end[w]).profit;
      ao.Revision();
    }
    // valida os parâmetros ótimos na janela SEGUINTE (jamais vista)
    oosTotal += RunBacktest(ao.cB, valid_start[w], valid_end[w]).profit;
  }
  return oosTotal;                                // é ISTO que indica se há edge real
}
```

---

## 5. Recomendação de configuração inicial

```cpp
popSize         = 60;     // padrão funciona bem
numGroups       = 6;      // não mexer
explorationRate = 0.9;    // < 0.99 → mais épocas de refino
forgettingProb  = 0.5;    // ponto de partida; varrer 0.3 / 0.5 / 0.7 e comparar OOS
totalEvals      = 15000;  // bom p/ 10–30 parâmetros
```

Travar a seed (`MathSrand`) antes de comparar configurações — o DOA é estocástico e duas
execuções dão resultados diferentes sem seed fixa.

---

## 6. Guard-rails de produção (independente do otimizador)

- Lote com teto rígido (ex.: `0.01` por trade enquanto valida).
- Stop diário de equity (ex.: −2%).
- Teto de trades/dia.
- **Demo primeiro.** Backtest ≠ mercado ao vivo (spread, slippage, latência, requote).

---

## 7. Benchmark honesto (faça antes de adotar)

Rode **DOA × DE × CMA-ES** nos *mesmos* parâmetros do MAESTRO, mesma fitness, mesmo orçamento,
comparando **resultado out-of-sample** (não in-sample). DE e CMA-ES também estão no framework do
Andrey Dik. Deixe os dados decidirem — não a narrativa bonita do "sonho".
