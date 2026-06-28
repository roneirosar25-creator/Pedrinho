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
