# 🎯 TRIVIUM_SETUP — Cockpit Visual (Passo 4: leitura de mercado)

Indicador **overlay** para MetaTrader 5 (Admirals) que junta numa tela só as
ferramentas de leitura de oportunidade. A ideia: você *enxerga* o cenário e
depois traduz em regras de estratégia.

## 🧰 O que vem embutido no indicador (1 arquivo só)

| Ferramenta | Detalhe | Liga/desliga |
|---|---|---|
| **4 Médias Móveis** | EMA 9 / 21 / 50 / 200 (período e método configuráveis) | `UsarMAs` |
| **Banda de Bollinger** | zoneamento por volatilidade (20, desvio 2) | `UsarBollinger` |
| **Envelope** | canal % fixo (20, 0,5%) | `UsarEnvelope` |
| **Marca d'água** | ativo + timeframe ao fundo do gráfico | `UsarMarca` |
| **Zonas de Suporte/Resistência** | automáticas, por fractais; espessura pela volatilidade (ATR) | `UsarSR` |
| **Linhas de Tendência** | alta (verde) e baixa (vermelha), automáticas pelos swings | `UsarTendencia` |

Tudo é **configurável nos inputs** ao aplicar o indicador. Ele usa
automaticamente o ativo e o timeframe do gráfico onde for aplicado.

## 📥 Instalação (Windows / MetaTrader 5)

1. Copie `TRIVIUM_SETUP.mq5` para a pasta de indicadores do MT5:
   `...\MQL5\Indicators\TRIVIUM_SETUP.mq5`
2. Compile no **MetaEditor** (abra o arquivo e tecle **F7**, ou
   `metaeditor64.exe /compile:<caminho> /exit`) — gera o `.ex5`.
3. No terminal, painel **Navegador → Indicadores**, arraste
   **TRIVIUM_SETUP** para o gráfico.

> ⚠️ **Não consegui compilar aqui** (ambiente Linux, sem MetaTrader). O código
> está escrito de forma padrão; se o MetaEditor acusar algum errinho de
> compilação, **a IA do MetaEditor resolve em segundos** — é exatamente o tipo
> de tarefa cirúrgica de código MQL5 pra ela (lembra a divisão de trabalho?).

## 📊 Os 4 osciladores (janelas separadas, embaixo do gráfico)

Estes são indicadores **padrão do MT5** — é só arrastar cada um para o gráfico
(Navegador → Indicadores → Osciladores):

| Oscilador | Parâmetros | Lê o quê |
|---|---|---|
| **RSI** | período 14 | força / sobrecompra e sobrevenda |
| **MACD** | 12, 26, 9 | tendência + momentum |
| **Estocástico** | 5, 3, 3 | timing de virada |
| **ADX** | 14 | força da tendência (não a direção) |

## 💾 Salvar como template (aplicar com 1 clique em qualquer ativo)

Depois de montar o gráfico (TRIVIUM_SETUP + os 4 osciladores do seu jeito):

1. Clique-direito no gráfico → **Modelo (Template) → Salvar modelo...**
2. Salve como **`TRIVIUM369`**.
3. Para aplicar em outro ativo: clique-direito → **Modelo → TRIVIUM369**.

Pronto — todo gráfico fica idêntico, com o cockpit completo.

## 🎨 Leitura rápida (como interpretar)

- **EMAs alinhadas** (9>21>50>200 subindo, ou o contrário) = tendência clara.
- **Bollinger apertando** (squeeze) = volatilidade baixa, possível explosão.
- **Preço fora do Envelope/Bollinger** = esticado, possível exagero.
- **Zonas S/R** = onde o preço já reagiu antes (decisão).
- **Linhas de tendência** = a inclinação do movimento; rompimento chama atenção.

## ➡️ Próximo passo

Use este setup pra observar os 15 ativos e me dizer **o que você vê de
oportunidade** (ex: "quando o preço encosta na Bollinger de baixo com RSI
sobrevendido e respeita a linha de tendência de alta, eu compro"). A partir
daí eu transformo a sua leitura em **regras objetivas** e depois em **EA**.
