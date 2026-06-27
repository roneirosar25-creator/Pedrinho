# Instruções para o Cláudio

> De: **Pedrinho** (Claude Code — cuida do repositório GitHub `pedrinho`)
> Para: **Cláudio** (trabalha localmente na máquina do Ronei — TRIVIUM369 / MetaTrader)
> Data: 27/06/2026

---

## 1. Onde está tudo

Tudo está versionado no repositório GitHub **`roneirosar25-creator/pedrinho`**, na branch
**`claude/amazing-clarke-451086`**, dentro de:

```
01_ENGENHARIA/04_OTIMIZACAO_ALGORITMOS/DOA/
```

(Mesma árvore que você já tinha montado localmente — agora é a fonte única, conferida e corrigida.)

Para puxar:
```bash
git fetch origin claude/amazing-clarke-451086
git checkout claude/amazing-clarke-451086
```

---

## 2. Ordem de leitura

1. `README.md` — visão geral, parâmetros, onde cada arquivo vai no MetaTrader.
2. `documentacao/ANALISE_TECNICA.md` — o código-a-código fiel (leia os "3 fatos" e as caixas de **Correção**).
3. `documentacao/INTEGRACAO_MAESTRO.md` — esqueleto de otimização + fitness anti-overfit + walk-forward.
4. `referencias/FONTES.md` — paper, artigo MQL5, GitHub.

---

## 3. ⚠️ Correções em relação ao material local (leia antes de codar)

A versão que montamos na máquina tinha 3 erros técnicos. **Use a versão deste repo:**

1. **Fase de exploitação** — NÃO é interpolação `c += (cB − c)·(t/T)`. O código real **reseta ao
   melhor global e aplica ruído por cosseno**. (Detalhe em `ANALISE_TECNICA.md` §4.)
2. **API do melhor resultado** — é **`ao.fB`** (fitness) e **`ao.cB[j]`** (vetor, array).
   `ao.cB.f` / `ao.cB.c[j]` **não compilam**.
3. **Tabelas de % de CMA-ES/DE/PSO** do material antigo eram chute — removidas. Só os números do
   DOA são oficiais (26º, 53,62%, 73–86% baixa-dim, 18–37% alta-dim).

---

## 4. O que dá pra fazer já (sem depender de ninguém)

- [ ] Copiar p/ o MetaTrader os 3 arquivos de `codigo/` (caminhos no `README.md` §3).
- [ ] Compilar um script vazio que dê `#include` no `AO_DOA_DreamOptimizationAlgorithm.mqh` → confirmar 0 erros.
- [ ] Ler `ANALISE_TECNICA.md` e fixar os 3 fatos (memória=nº de dims; forgetting é either/or; exploração domina).

> O benchmark `Test_AO_DOA_dream.mq5` (em `testes/`) só compila com o framework **completo** (~80 .mqh +
> bancada de testes). Para rodá-lo, baixe o ZIP inteiro do artigo MQL5 19177. **Não é necessário** para
> integrar no MAESTRO.

---

## 5. 🔴 Bloqueios — o que o Cláudio precisa receber do Ronei/Pedrinho

Sem estes 4 itens, dá pra validar o código mas **não dá pra integrar de verdade**:

- [ ] **(A) Lista de inputs do MAESTRO a otimizar** — quantos e com limites:
      ```
      param[0]: RSI_Period     min=5   max=50   step=1
      param[1]: RSI_BuyLevel   min=20  max=50   step=1
      param[2]: MA_Period      min=10  max=200  step=5
      ...
      ```
- [ ] **(B) Como o MAESTRO faz backtest** — a função/rotina que, dado um vetor de parâmetros,
      devolve uma métrica (lucro, Sharpe, etc.). Código ou pseudocódigo serve.
- [ ] **(C) Períodos separados** — in-sample (treino) e out-of-sample (validação). Ex.: treino
      2024‑01→2024‑12, validação 2025‑01→2025‑03.
- [ ] **(D) Qual métrica otimizar** — lucro? Sharpe? Calmar? profit factor? híbrida anti-overfit?

---

## 6. Quando tiver A+B+C+D

1. Implementar `BacktestMAESTRO()` (fitness) seguindo `INTEGRACAO_MAESTRO.md` §3.
2. Montar o loop de otimização (§2) e validar com **walk-forward** (§4).
3. Varrer `forgettingProb` ∈ {0.3, 0.5, 0.7} e comparar **resultado out-of-sample**.
4. Rodar benchmark **DOA × DE × CMA-ES** (§7) — escolher pelo OOS, não pelo backtest.
5. Demo antes de produção, com guard-rails (§6).

---

## 7. Princípio que não pode esquecer

> A escolha do algoritmo vale ~1% do resultado. **99% é walk-forward + fitness anti-overfit.**
> O DOA (ou qualquer AO) só afina uma lógica que já tem *edge*. Não cria *edge*.
