# 📊 COLETA_HISTORICO_TRIVIUM — Coleta de Histórico (MT5 / Admirals)

Script MQL5 que roda **uma vez** e baixa o histórico de candles direto do
servidor da corretora (Admirals) para arquivos CSV.

## ⚙️ Configuração confirmada

- **Sufixo dos ativos:** `-T` (Admirals) — ex: `EURUSD-T`, `XAUUSD-T`
- **Ativos (15):**
  `EURUSD-T`, `GBPUSD-T`, `USDCHF-T`, `USDCAD-T`, `USDJPY-T`,
  `USDSEK-T`, `USDCNH-T`, `NZDUSD-T`, `AUDUSD-T`, `AUDCAD-T`,
  `XAUUSD-T`, `XAUGBP-T`, `XAUEUR-T`, `XAUCHF-T`, `XAUAUD-T`
- **Timeframes (7):** M1, M2, M5, M15, H1, H4, D1
- **Total esperado:** 15 × 7 = **105 arquivos CSV**

## 📥 Parâmetros editáveis (inputs)

| Parâmetro         | Padrão          | Descrição                              |
|-------------------|-----------------|----------------------------------------|
| `BarrasDesejadas` | `100000`        | Teto de barras por combinação          |
| `MaxTentativas`   | `20`            | Tentativas p/ forçar o download        |
| `EsperaMs`        | `400`           | Espera entre tentativas (ms)           |
| `PastaBase`       | `DADOS_BRUTOS`  | Prefixo da pasta de saída              |

## 🚀 Como compilar e instalar (Windows / MetaTrader 5)

1. Copie `COLETA_HISTORICO_TRIVIUM_FINAL.mq5` para a pasta de scripts do MT5:
   `...\MetaQuotes\Terminal\<ID>\MQL5\Scripts\COLETA_HISTORICO_TRIVIUM.mq5`
2. Compile com o MetaEditor (`metaeditor64.exe /compile:<caminho> /exit`) —
   gera o `.ex5`.
3. Copie o `.ex5` para a pasta de scripts do terminal **Admirals**.

## ▶️ Como executar

1. Abra o terminal Admirals.
2. Menu **Ferramentas → Scripts** (ou painel **Navegador → Scripts**).
3. Localize **COLETA_HISTORICO_TRIVIUM** e dê duplo clique.
4. Acompanhe o progresso no **Terminal (F12) → aba Experts**.

O log mostra `[OK]`, `[PARCIAL]` ou `[FALHA]` para cada combinação. Tempo
estimado: 30–60 min (depende da conexão).

## 📂 Saída

Arquivos CSV em `<MQL5\Files>\DADOS_BRUTOS_<ATIVO>\<TF>_<ATIVO>-T.csv`,
com cabeçalho `date,time,open,high,low,close,volume`.

> O nome da pasta usa o ativo **sem** o sufixo `-T` (ex: `DADOS_BRUTOS_EURUSD`),
> mas o nome do arquivo mantém o sufixo (ex: `M1_EURUSD-T.csv`).

---

# 🩺 qa_consolida_dados.py — Passos 2 e 3 (Validar + Consolidar)

Antes de qualquer backtest ou estratégia, os dados precisam ser **auditados**
e **limpos**. *Lixo entra, lixo sai.* Este script faz isso — usando **apenas a
biblioteca padrão do Python** (nenhum `pip install` necessário).

## O que ele verifica (QA / Passo 2)

Para cada CSV no padrão `<TF>_<ATIVO>-T.csv` dentro das pastas `DADOS_BRUTOS_*`:

- Cabeçalho e colunas corretos
- Linhas que não parseiam (data/hora ou números inválidos)
- **Candles duplicados** (mesmo timestamp)
- **Candles fora de ordem** cronológica
- **OHLC inválido** (high<low, high<max(o,c), low>min(o,c), zero/negativo, NaN)
- Volume negativo
- **Gaps (buracos) suspeitos** na série — ignorando fins de semana

## O que ele entrega (Consolidação / Passo 3)

- Versão **limpa** de cada arquivo (ordenada, sem duplicatas, validada), com
  coluna ISO `datetime` pronta pra análise, em
  `DADOS_LIMPOS/<ATIVO>/<TF>_<ATIVO>-T.csv`
- `RELATORIO_QA.md` — relatório de saúde legível (tabela por arquivo)
- `qa_resumo.csv` — resumo em formato para máquina

Cada arquivo recebe um status: **OK** ✅, **AVISO** ⚠️ (problemas leves, ainda
utilizável) ou **FALHA** ❌ (≥5% de linhas inválidas — não usar até corrigir).

## Como usar (Windows / qualquer SO com Python 3.8+)

```bash
# 1. Copie as pastas DADOS_BRUTOS_* (de <MQL5\Files>) para uma pasta de trabalho
# 2. Rode apontando para essa pasta:
python qa_consolida_dados.py --input "C:\caminho\com\as\DADOS_BRUTOS"

# Opções:
#   --input  / -i   pasta que contém as DADOS_BRUTOS_*   (padrão: atual)
#   --output / -o   pasta de saída dos limpos            (padrão: DADOS_LIMPOS)
#   --no-clean      só audita, não escreve os limpos
```

**Exit code:** `0` se nenhum arquivo deu FALHA, `1` caso contrário (útil para
automação). Os gaps são heurísticos: feriados podem aparecer como AVISO —
por isso AVISO não impede o uso, só FALHA impede.

## Sequência do pipeline

1. **Coletar** → `COLETA_HISTORICO_TRIVIUM_FINAL.mq5` (Admirals) ✅
2. **Validar (QA)** → `qa_consolida_dados.py` ✅
3. **Consolidar** → `qa_consolida_dados.py` (saída `DADOS_LIMPOS/`) ✅
4. **Estratégia** → próximo passo (regras de entrada/saída)
5. Backtest → 6. Gestão de risco → 7. Forward test (demo) → 8. Deploy + monitoramento
