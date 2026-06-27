# DOA — Dream Optimization Algorithm (pacote de integração MAESTRO)

> Pacote organizado por **Pedrinho** (Claude Code) para **Cláudio** trabalhar a integração no EA MAESTRO.
> Todo o conteúdo técnico aqui foi conferido **contra o código-fonte oficial** (Andrey Dik / MQL5).

**Status:** ✅ Análise concluída · código oficial no repo · aguardando dados do MAESTRO para integrar
**Data:** 27/06/2026

---

## 1. O que é o DOA

Metaheurístico populacional (Lang & Gao, 2025, *CMAME* vol. 436). Inspiração: sono REM —
retenção parcial de memória, esquecimento seletivo e "compartilhamento de sonhos".
Na prática, a mecânica é: **elitismo agrupado + annealing por-dimensão + crossover**.

- **Ranking (tabela do Andrey Dik, 80+ algoritmos):** 26º lugar, **53,62%** → mediano.
- **Forte em baixa dimensão (10–30 parâmetros):** 73–86% — *exatamente o regime de um EA*.
- **Fraco em alta dimensão (≥100):** 18–37% — refino final pobre.

> ⚠️ **Verdade inconveniente:** a escolha do algoritmo (DOA vs DE vs CMA-ES) vale ~1% do
> resultado. **99% vem da metodologia anti-overfit (walk-forward + função-objetivo).**
> Otimizador não cria *edge* — ele afina uma lógica que já precisa ter *edge*.

---

## 2. Estrutura deste pacote

```
DOA/
├── README.md                         ← você está aqui (comece por ele)
├── codigo/                           ← arquivos para INTEGRAR o DOA num EA
│   ├── AO_DOA_DreamOptimizationAlgorithm.mqh   (algoritmo oficial — Andrey Dik)
│   ├── #C_AO.mqh                               (classe base do framework)
│   └── Utilities.mqh                           (dependência de #C_AO.mqh)
├── testes/                           ← benchmark standalone (NÃO é o mínimo p/ integrar)
│   ├── Test_AO_DOA_dream.mq5                   (script de teste oficial)
│   └── #C_AO_enum.mqh                          (seletor de AOs — precisa dos 80 .mqh)
├── documentacao/
│   ├── ANALISE_TECNICA.md            ← código-a-código (fiel ao oficial)
│   ├── INTEGRACAO_MAESTRO.md         ← passo a passo p/ otimizar parâmetros do EA
│   └── PARA_CLAUDIO.md               ← instruções diretas + checklist + bloqueios
└── referencias/
    └── FONTES.md                     ← papers, artigo MQL5, GitHub (só links verificados)
```

---

## 3. Onde cada arquivo vai (MetaTrader 5)

Para **integrar** o DOA num EA, copie só estes 3 para o seu MetaTrader:

```
<Data Folder>\MQL5\Include\Math\AOs\Utilities.mqh
<Data Folder>\MQL5\Include\Math\AOs\PopulationAO\#C_AO.mqh
<Data Folder>\MQL5\Include\Math\AOs\PopulationAO\AO_DOA_DreamOptimizationAlgorithm.mqh
```

> O `Test_AO_DOA_dream.mq5` (benchmark) depende do framework **completo** (~80 algoritmos +
> bancada de testes `TestFunctions/TestStandFunctions`). Para rodá-lo, baixe o ZIP completo do
> [artigo MQL5 19177](https://www.mql5.com/pt/articles/19177). Para **integrar no MAESTRO você
> NÃO precisa** desse harness — só dos 3 arquivos acima.

---

## 4. Parâmetros (defaults reais do código oficial)

| Parâmetro | Default (classe) | No teste oficial | Papel | Sensibilidade |
|---|---|---|---|---|
| `popSize` | 60 | 60 | tamanho da população | média |
| `numGroups` | 6 | 6 | grupos com memória heterogênea | baixa |
| `explorationRate` | 0.99 | 0.9 | fração de épocas em exploração | **alta** |
| `forgettingProb` | 0.3 | 0.7 | esquecer/annealing **ou** dream-sharing | **crítica** |

**Primeiro knob a ajustar: `forgettingProb`.** Ele decide, por agente, *ou* annealing (suplementação
por cosseno) *ou* dream-sharing (cópia de outro indivíduo) — são **mutuamente exclusivos**, não os dois.

---

## 5. Próximos passos

1. **Cláudio:** ler `documentacao/ANALISE_TECNICA.md` → validar compilação → ler `INTEGRACAO_MAESTRO.md`.
2. **Ronei/Pedrinho:** fornecer ao Cláudio os 4 itens que destravam a integração (ver `PARA_CLAUDIO.md` §"Bloqueios").
3. **Integração:** fitness anti-overfit + walk-forward → benchmark DOA × DE × CMA-ES → demo antes de produção.

---

## 6. Nota de procedência / correções

Uma versão anterior deste pacote foi montada localmente (TRIVIUM369) e continha imprecisões técnicas
que **foram corrigidas aqui**, conferindo contra o `.mqh` oficial:

- A **fase de exploitação** NÃO faz interpolação linear `c += (cB - c)·fator`. O código real **reseta ao
  melhor global** e depois aplica ruído modulado por cosseno (igual à exploração, mas com o `cB` global).
- A **API de leitura do melhor** é `ao.fB` e `ao.cB[i]` (arrays na classe base), **não** `ao.cB.f` / `ao.cB.c[i]`.
- As **tabelas comparativas de % de CMA-ES/DE/PSO** da versão local eram estimativas não verificadas e foram
  removidas. Mantivemos apenas os números do DOA realmente publicados (26º, 53,62%, 73–86% baixa-dim, 18–37% alta-dim).
