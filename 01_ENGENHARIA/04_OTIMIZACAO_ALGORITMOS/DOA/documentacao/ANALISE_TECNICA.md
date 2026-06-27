# DOA — Análise técnica código-a-código

> Fonte: `AO_DOA_DreamOptimizationAlgorithm.mqh` (classe `C_AO_DOA_dream`, Andrey Dik, 2025).
> Tudo abaixo foi lido **diretamente do arquivo oficial** que está em `../codigo/`.

---

## 1. Arquitetura no framework C_AO

O algoritmo herda de `C_AO`. O loop externo (no EA ou no script de teste) é sempre:

```
Init() → repete[ Moving() → avalia fitness de cada agente → Revision() ]
```

- `a[i].c[]` = coordenadas atuais do agente *i* (= um vetor de parâmetros candidato)
- `a[i].f`   = fitness do agente *i* (você preenche depois do `Moving()`)
- `cB[]` / `fB` = melhores coordenadas / melhor fitness **global**
- `groupBest[m]` = melhor agente do **grupo m** (estado interno do DOA)

## 2. Defaults reais (≠ do paper)

```cpp
popSize         = 60;    // o paper genérico costuma usar 30–50
numGroups       = 6;     // ⚠️ o paper descreve 5 grupos; Dik implementou 6
explorationRate = 0.99;  // 99% das épocas em exploração (o script de teste usa 0.9)
forgettingProb  = 0.3;   // classe usa 0.3; o script de teste usa 0.7
```

Divisão de fase em `Moving()`:

```cpp
explorationIters = (int)(totalIterations * explorationRate);
if (currentIteration <= explorationIters) ExplorationPhase();
else                                      ExploitationPhase();
```

Com `explorationRate ≈ 0.9–0.99`, a exploitação roda só nos **últimos ~1–10% das épocas**.
É o que explica direto o perfil "boa diversidade, refino final fraco".

---

## 3. Fase de EXPLORAÇÃO (o coração do DOA)

```cpp
for (int m = 0; m < numGroups; m++)
{
  UpdateGroupBest (m);                                   // melhor do grupo

  int kMin = ceil(coords/8.0/(m+1));
  int kMax = ceil(coords/3.0/(m+1));
  int k    = RNDintInRange(kMin, kMax);                  // nº de dims a "esquecer"

  for (int j = startIdx(m); j <= endIdx(m); j++)
  {
    ArrayCopy(a[j].c, groupBest[m].c);                   // (A) MEMÓRIA: reset ao melhor do grupo
    // ... embaralha o vetor de dimensões (Fisher–Yates) ...

    if (RNDprobab() < forgettingProb)                    // (B) ESQUECIMENTO + SUPLEMENTAÇÃO
    {
      for (int h = 0; h < k; h++) {
        int dim = dims[h];
        double range = rangeMax[dim] - rangeMin[dim];
        double randomValue = RNDprobab()*range + rangeMin[dim];
        double cosMod = (cos((t + T/10.0)*M_PI/T) + 1.0)/2.0;   // 1 → 0 ao longo das épocas
        a[j].c[dim] += randomValue * cosMod;             // salto grande no início, fino no fim
        a[j].c[dim]  = SeInDiSp(...);                     // clamp ao range/step
      }
    }
    else                                                 // (C) DREAM SHARING (crossover)
    {
      for (int h = 0; h < k; h++) {
        int dim   = dims[h];
        int donor = RNDintInRange(0, popSize-1);
        a[j].c[dim] = a[donor].c[dim];                   // copia a dim de um indivíduo aleatório
      }
    }
  }
}
```

### Os 3 fatos que mudam a leitura

**(1) Memória heterogênea = nº de dimensões esquecidas, não escala de ruído.**
`k ∝ 1/(m+1)`. O grupo 0 esquece muitas dims (até ~D/3 → explorador); o grupo 5 esquece
pouquíssimas (~D/18…D/48 → memória forte, refinador). É assim que o código materializa
"grupos com capacidades de memória distintas".

**(2) Esquecimento e dream-sharing são MUTUAMENTE EXCLUSIVOS por agente.**
`if (RNDprobab() < forgettingProb) annealing; else dream_sharing;`.
Com `forgettingProb=0.3` (default) → **70% dos agentes fazem dream-sharing** (crossover puro).
Com `0.7` (teste) → inverte para 70% annealing. **Um único float vira o comportamento do algoritmo
de "PSO-like (crossover)" para "SA-like (annealing)".** É o knob mais sensível.

**(3) A suplementação ADICIONA um valor de coordenada (não um delta pequeno).**
`randomValue ∈ [rangeMin, rangeMax]` somado à coordenada atual e modulado por `cosMod`.
No início (`cosMod≈1`) é praticamente um salto aleatório de escala do domínio (depois clampado);
no fim (`cosMod≈0`) o ajuste tende a zero. É o annealing schedule.

---

## 4. Fase de EXPLOITAÇÃO (1–10% final)

```cpp
for (int j = 0; j < popSize; j++)
{
  ArrayCopy(a[j].c, cB);                                 // reset ao melhor GLOBAL (não ao do grupo)

  int km = max(2, ceil(coords/3.0));
  int k  = RNDintInRange(2, km);                         // SEMPRE perturba ao menos 2 dims
  // ... embaralha dims ...

  for (int h = 0; h < k; h++) {
    int dim = dims[h];
    double range = rangeMax[dim] - rangeMin[dim];
    double randomValue = RNDprobab()*range + rangeMin[dim];
    double cosMod = (cos(t*M_PI/T) + 1.0)/2.0;           // sem o +T/10 da exploração
    a[j].c[dim] += randomValue * cosMod;
    a[j].c[dim]  = SeInDiSp(...);
  }
}
```

Diferenças vs. exploração: (i) reset ao **melhor global** `cB`, não ao melhor do grupo;
(ii) **não há dream-sharing**; (iii) `k = rand(2, ⌈D/3⌉)` (garante perturbação mínima);
(iv) cosseno sem o deslocamento `+T/10`.

> ❗ **Correção importante:** o material local anterior descrevia esta fase como interpolação
> linear `c += (cB − c)·(t/T)`. **Isso está errado.** O código real reseta a `cB` e aplica
> ruído modulado por cosseno, exatamente como acima.

---

## 5. Revisão (atualização dos melhores)

```cpp
void Revision() {
  for (int i = 0; i < popSize; i++)
    if (a[i].f > fB) { fB = a[i].f; ArrayCopy(cB, a[i].c); }   // melhor global

  if (currentIteration <= explorationIters)                    // só na exploração:
    for (int m = 0; m < numGroups; m++)
      if (groupBest[m].f > fB) { fB = groupBest[m].f; ArrayCopy(cB, groupBest[m].c); }
}
```

---

## 6. API para uso externo (decorar isto)

| O que você quer | Como acessar |
|---|---|
| Setar parâmetros | `ao.params[i].val = x;` depois `ao.SetParams();` |
| Inicializar | `ao.Init(rangeMin[], rangeMax[], rangeStep[], epochs)` |
| Gerar candidatos | `ao.Moving();` |
| Ler/escrever candidato i | coords `ao.a[i].c[j]` · fitness `ao.a[i].f` |
| Consolidar geração | `ao.Revision();` |
| Melhor solução | coords `ao.cB[j]` · fitness `ao.fB` |

> ❗ **Correção:** é `ao.fB` e `ao.cB[j]` (a base `C_AO` declara `double cB[]` e `double fB`).
> **Não** existe `ao.cB.f` nem `ao.cB.c[i]` — isso quebra a compilação.

---

## 7. Veredito técnico

- DOA é um clássico bem-feito: 2 fases, memória por grupo, annealing por-dimensão e crossover.
  A metáfora REM é honesta como mnemônica, mas a mecânica é conhecida.
- **Bom para o regime de EA (10–30 parâmetros).** Fraco em refino fino e alta-dimensão (efeito do
  `explorationRate≈0.99`).
- Para o MAESTRO, o gargalo de resultado **não é o DOA** — é overfitting de backtest. Ver
  `INTEGRACAO_MAESTRO.md`.
