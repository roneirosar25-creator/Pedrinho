# Fontes e referências — DOA

> Só links verificados. Números de DOI/build que não pudemos confirmar foram omitidos de propósito.

---

## Paper original

- **Dream Optimization Algorithm (DOA): A novel metaheuristic optimization algorithm inspired by
  human dreams and its applications to real-world engineering problems**
  Lang, Y. & Gao, Y. — *Computer Methods in Applied Mechanics and Engineering* (CMAME), vol. 436, 2025.
  - ScienceDirect: https://www.sciencedirect.com/science/article/abs/pii/S0045782524009745
  - ADS: https://ui.adsabs.harvard.edu/abs/2025CMAME.43617718L/abstract

## Equações em acesso aberto (variante multi-estratégia, reexpõe o DOA básico)

- Three-Dimensional Path Planning for UAV Based on Multi-Strategy DOA — MDPI Biomimetics, 2025.
  - PMC (open access): https://pmc.ncbi.nlm.nih.gov/articles/PMC12383324/

## Implementação MQL5 (a que está neste repo)

- **Algoritmo de Otimização por Sonhos: Dream Optimization Algorithm (DOA)** — Andrey Dik.
  - Artigo (pt): https://www.mql5.com/pt/articles/19177
  - Contém o `.mqh` oficial + `Test_AO_DOA_dream.mq5` + comparação na bancada Hilly/Forest/Megacity.

- **GitHub — Population optimization algorithms (MQL5)** — JQSakaJoo (Andrey Dik).
  - https://github.com/JQSakaJoo/Population-optimization-algorithms-MQL5
  - Tem o DOA + DE + CMA-ES + ~80 outros AOs (úteis para o benchmark comparativo).

---

## Números de desempenho (da bancada do Andrey Dik — verificados)

- DOA: **26º** lugar entre 80+ algoritmos; score geral **53,62%** ("mediano").
- Baixa dimensão (10): **73–86%**.
- Alta dimensão (1000): **18–37%**.
- Bancada: funções Hilly / Forest / Megacity; 10.000 avaliações; 10 repetições.

> ⚠️ Percentuais específicos de CMA-ES/DE/PSO **não** estão listados aqui porque não foram
> confirmados na fonte. Qualitativamente, CMA-ES, DE e SDSm aparecem **acima** do DOA na tabela.
> Para comparar de verdade, rode os três você mesmo (ver `INTEGRACAO_MAESTRO.md` §7).
