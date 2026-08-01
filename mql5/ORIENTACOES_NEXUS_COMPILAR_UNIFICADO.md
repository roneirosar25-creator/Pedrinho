# Orientações para o Nexus — compilar e validar dois EAs

**De:** Cláudio (Claude Code via GitHub, sem acesso ao PC do Ronei)
**Para:** Nexus (tem Windows, MT5, MetaEditor)
**Data:** 01/08/2026
**Branch:** `claude/risk-validator-trading-1a5ai0` (PR #5)

---

## Contexto: o que eu não consigo fazer

Eu trabalho só pelo GitHub, num container Linux. **MetaEditor é Windows-only, então eu
não compilo nada.** O que eu fiz foi revisão estática: delimitadores balanceados, ordem
de definição, colisão de símbolos com `STOP_DIARIO.mqh`, inputs todos referenciados.
Isso não substitui o compilador — só reduz a chance de erro bobo.

**Você é quem compila. Eu corrijo o que o compilador acusar.**

---

## ⚠️ ATUALIZAÇÃO 01/08/2026 — agora são DOIS arquivos, não um

O Ronei perguntou qual EA vai pra demo (o unificado, ainda não validado, ou o
`NEXUS369_TREND_VALIDADO` atual, que carrega os bugs B1/B2/B3 sem correção). Em vez de
escolher entre "demo sujo" ou "esperar", portei os três fixes **direto pro
`NEXUS369_TREND_VALIDADO.mq5`** também - é um arquivo separado do unificado, não
interfere na rodada A/B/C que você já ia rodar.

**Os dois precisam compilar limpo agora:**

1. `TRIVIUM369_UNIFICADO_EA.mq5` - o EA novo, filtro de médias ainda não validado
   (ver rodadas A/B/C mais abaixo).
2. `NEXUS369_TREND_VALIDADO.mq5` - o EA que já está rodando, agora com B1/B2/B3
   corrigidos. **Este é o candidato a ir pra demo enquanto o unificado ainda é validado.**

Mesmo procedimento de compilação pros dois (Passo 1/2 abaixo, repita pra cada arquivo).
Backtest de 3 rodadas (Passo 3) é só do unificado - o `NEXUS369_TREND_VALIDADO` corrigido
não precisa disso, mas **precisa bater com o resultado histórico igualzinho**, já que os
três fixes só mudam comportamento em cenários de borda (equity=0 na reconexão,
comentário reescrito pela corretora, tick entre fechamento e evento) - no caminho normal
o EA se comporta exatamente como antes. Se o backtest dele divergir do histórico, isso
por si só já seria um sinal de que alguma das correções mudou o caminho normal por
engano - me chama na hora.

---

## ⚠️ PRIMEIRO: o ponto mais importante deste pedido

O `TRIVIUM369_UNIFICADO_EA` **não é** o `NEXUS369_TREND_VALIDADO` com mais recursos.
Ele tem um filtro novo (alinhamento de médias, `InpModoFiltroMedias`) que **está ligado
por padrão em modo 1**.

O edge original foi validado (Z>3.7, 20 janelas sequenciais, out-of-sample, 9 variações
de SL/TP) **sem filtro de médias nenhum**. Ou seja:

> **Com `InpModoFiltroMedias = 1` ou `2`, o EA unificado é uma estratégia NÃO VALIDADA.**
> O filtro pode melhorar, pode piorar, pode destruir o edge. Ninguém sabe ainda.

Por isso o backtest abaixo tem três rodadas obrigatórias, não uma.

---

## Passo 1 — Colocar os arquivos no lugar certo

Atenção a uma pegadinha de caminho: **no repositório a pasta é `mql5/includes/trivium/`
(plural), mas o MT5 exige `MQL5\Include\TRIVIUM\` (singular).** O `#include` do EA é
`<TRIVIUM\STOP_DIARIO.mqh>`, que só resolve no caminho do MT5.

```powershell
# Ajuste estes dois caminhos para a sua máquina
$repo = "C:\Users\ronei\Documents\GitHub\Pedrinho"
$mql5 = "$env:APPDATA\MetaQuotes\Terminal\<SEU_HASH>\MQL5"   # descubra o hash abaixo

# Descobrir o data folder do MT5 (se não souber o hash):
#   No MT5: Arquivo -> Abrir Pasta de Dados
Get-ChildItem "$env:APPDATA\MetaQuotes\Terminal" -Directory |
    Where-Object { Test-Path "$($_.FullName)\MQL5" } |
    Select-Object FullName

# Atualizar o repo para a branch com o EA novo
Set-Location $repo
git fetch origin claude/risk-validator-trading-1a5ai0
git checkout claude/risk-validator-trading-1a5ai0
git pull origin claude/risk-validator-trading-1a5ai0

# Copiar os DOIS EAs
Copy-Item "$repo\mql5\experts\TRIVIUM369_UNIFICADO_EA.mq5" "$mql5\Experts\" -Force
Copy-Item "$repo\mql5\experts\NEXUS369_TREND_VALIDADO.mq5" "$mql5\Experts\" -Force

# Copiar os includes -> note: "includes/trivium" (repo) vira "Include\TRIVIUM" (MT5)
New-Item -ItemType Directory -Force -Path "$mql5\Include\TRIVIUM" | Out-Null
Copy-Item "$repo\mql5\includes\trivium\*.mqh" "$mql5\Include\TRIVIUM\" -Force

Get-ChildItem "$mql5\Include\TRIVIUM\*.mqh" | Select-Object Name
```

---

## Passo 2 — Compilar pela linha de comando

```powershell
# Achar o metaeditor64.exe (varia por corretora)
$me = Get-ChildItem "C:\Program Files" -Recurse -Filter "metaeditor64.exe" `
      -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
Write-Host "MetaEditor: $me"

# Compila os DOIS - repita pros dois arquivos
$arquivos = @("TRIVIUM369_UNIFICADO_EA.mq5", "NEXUS369_TREND_VALIDADO.mq5")
foreach($nome in $arquivos) {
   $src = "$mql5\Experts\$nome"
   $log = "$env:TEMP\compile_$($nome).log"
   & $me /compile:"$src" /inc:"$mql5" /log:"$log"
   Write-Host "$nome -> ExitCode: $LASTEXITCODE"   # 0 = sem erros
   Write-Host "--- log ($nome) ---"
   Get-Content $log -Encoding Unicode              # log do MetaEditor sai em UTF-16
   Write-Host ""
}
```

### O que eu preciso que você me mande de volta (dos DOIS arquivos)

1. **O log inteiro de cada um**, não só o resumo — inclusive os **warnings**. Warning de
   MQL5 costuma esconder bug real (conversão implícita de `long` pra `int`, resultado de
   função ignorado, variável não usada).
2. O `ExitCode` de cada um.
3. Se gerou ou não o `.ex5` de cada um, e o tamanho do arquivo.

Se der erro, **não tente corrigir sozinho** — me manda o log que eu corrijo e faço push.
Assim a correção fica versionada no PR e não diverge entre a sua máquina e o repo.

### Coisas que eu suspeito que possam dar warning

Já reviso pensando nisso, mas fica o aviso do que olhar (vale pros dois arquivos - as
funções de identidade/reconciliação de posição são as mesmas nos dois):

- `StringSplit(linha, ';', campos)` — o `';'` como `ushort`.
- `IntegerToString((long)ticket)` com `ticket` sendo `ulong`.
- `TemPosicaoAberta()` / `AtualizaEstadoPosicao()` chamadas como statement em alguns
  pontos (retorno `bool` ignorado de propósito, mas o compilador pode reclamar).
- `PositionGetInteger(POSITION_MAGIC) != InpMagicManual` — `long` vs `int`.
- Parâmetros `request` e `result` não usados no `OnTradeTransaction`.

---

## Passo 3 — Backtest: TRÊS rodadas, não uma

Rode no **Strategy Tester**, **GER40 H1**, mesmo período/modelo que você usou pra
validar o `NEXUS369_TREND_VALIDADO` originalmente (preciso que seja comparável).

| Rodada | `InpModoFiltroMedias` | O que responde |
|---|---|---|
| **A — baseline** | `0` (desligado) | O unificado reproduz o edge original? Se A ficar longe do resultado do `NEXUS369_TREND_VALIDADO`, **tem bug de porte na unificação** e é aqui que a gente para tudo. |
| **B — filtro leve** | `1` (só lado da MA200) | O filtro ajuda ou atrapalha? |
| **C — filtro rigoroso** | `2` (alinhamento MA7>MA21>MA50) | Idem, mais restritivo. Provavelmente reduz muito o número de trades. |

O EA já grava tudo sozinho em `TRIVIUM369_BACKTEST_RESULTADOS.csv` (pasta `Common\Files`),
uma linha por rodada, com a coluna `modo_medias` pra você distinguir. Me manda esse CSV.

**Critério de decisão** (é aqui que eu entro como validador):

- Se **A** não bater com o resultado histórico do `NEXUS369_TREND_VALIDADO` → bug meu,
  eu conserto antes de qualquer outra coisa.
- Se **A** bate e **B/C** pioram → o padrão do filtro vira `0` e o filtro de médias fica
  como opção desligada. Eu faço esse commit.
- Se **B** ou **C** melhoram → **não basta melhorar numa rodada.** Aí precisa da sua
  metodologia de sempre: treino/teste 70/30, e o lado de teste tem que continuar positivo.
  Uma melhora só no in-sample é overfitting, não edge.

---

## Passo 4 — O que pode e o que NÃO fazer ainda

**`NEXUS369_TREND_VALIDADO.mq5` (corrigido):**
- ✅ Pode ir pra demo assim que compilar limpo e o backtest bater com o histórico.
- ❌ Ainda não em conta real / dinheiro que importe.
- ❌ Kill switch continua desligado até o Ronei mandar "pode rodar" - isso não muda.

**`TRIVIUM369_UNIFICADO_EA.mq5`:**
- ❌ **Não anexar em gráfico de conta real nem demo ainda.** Espera a rodada A bater
  com o histórico primeiro.
- ❌ **Não rodar junto com o `NEXUS369_TREND_VALIDADO` no mesmo símbolo.** Os dois
  abririam posição pelo mesmo sinal - são o mesmo motor de entrada, duplicariam a
  exposição. Só um dos dois por símbolo, nunca os dois juntos.

---

## Passo 5 — Contexto dos 3 bugs (agora corrigidos NOS DOIS arquivos)

Achei estes relendo o `NEXUS369_TREND_VALIDADO` original. Os três já estavam corrigidos
no unificado; agora também portei pro `NEXUS369_TREND_VALIDADO.mq5` que você vai
compilar - **os dois arquivos que você tem na mão já saem com os fixes**, não há mais
nenhuma versão rodando com os bugs em aberto depois deste push.

**B3 (mais grave).** O `OnTick` zerava `magicAtual` assim que a posição sumia da
corretora. Se um tick chegasse antes do `OnTradeTransaction`, a guarda
`if(magicAtual == 0) return;` descartava o evento de fechamento inteiro — e com ele a
chamada de `RegistrarResultadoRisco()`. Consequência: **o contador de perdas seguidas
podia não subir, e a redução dinâmica de risco (0.5x após 2 perdas, 0.25x após 3) podia
nunca ligar.** Se você tiver como conferir a GlobalVariable
`TRIVIUM369_LOSSES_SEGUIDAS_<login>_<simbolo>` numa conta que já teve perdas seguidas
**antes deste push**, isso confirma (ou desmente) o bug em campo, retroativamente.
**Esse dado me interessa muito** - depois deste push a GV passa a ser mantida certo,
então a janela pra confirmar o bug "em ação" é só olhando o estado atual/histórico.

**B2.** A identificação de "já tenho posição aberta" usava o *comentário* da ordem
(`"TND "`). Corretora reescreve/apaga comentário — quando isso acontece o EA não se
enxerga e abre uma segunda posição no mesmo par. Agora a identidade é o magic,
persistido em GlobalVariable que sobrevive a reinício, nos dois arquivos.

**B1.** `DrawdownDiarioEstourado()` dividia por `saldoInicioDia` sem checar `> 0`. É a
mesma race condition de equity=0 na reconexão que o Ronei achou ao vivo em 09/07 — e que
o `STOP_DIARIO.mqh` já defendia em dois pontos, mas a guarda local não. Divisão vira
`inf`, `inf >= 3.0` dá true, EA se bloqueia o dia inteiro em silêncio.

**Importante para o backtest do `NEXUS369_TREND_VALIDADO` corrigido:** os três fixes só
mudam comportamento em cenários de borda (equity zerada, comentário reescrito, tick entre
fechamento e evento). No caminho normal o EA se comporta exatamente como antes - por isso
o backtest dele **precisa bater com o histórico**. Se divergir, é sinal de que uma das
correções mexeu no caminho normal por engano.

---

## Passo 6 — Uma decisão de arquitetura que quero sua opinião

O filtro de médias eu calculei com **`iMA` nativo**, com os mesmos períodos e tipos do
`TRIVIUM_MEDIAS_7` (7/14/21 EMA, 50/100/150/200 SMMA) — **não** via
`iCustom("TRIVIUM_MEDIAS_7")`.

Motivo: `iCustom` cria dependência do indicador estar instalado e compilado na máquina, e
é exatamente onde apareceu o handle inválido (4807) que vocês já discutiram. Com `iMA` o
EA se basta; o indicador continua existindo pro Ronei ver na tela, mas o EA não depende
dele pra decidir.

Se você discordar — por exemplo se o `TRIVIUM_MEDIAS_7` tiver alguma lógica de cálculo
que o `iMA` puro não reproduz — me fala que eu troco.

---

## Resumo do que eu preciso de volta

1. Log completo da compilação (com warnings) + ExitCode **dos dois arquivos**
   (`TRIVIUM369_UNIFICADO_EA.mq5` e `NEXUS369_TREND_VALIDADO.mq5`).
2. `TRIVIUM369_BACKTEST_RESULTADOS.csv` com as três rodadas do unificado (A/B/C).
3. Backtest do `NEXUS369_TREND_VALIDADO` corrigido comparado com o resultado histórico
   (tem que bater).
4. Se possível: valor da GlobalVariable `TRIVIUM369_LOSSES_SEGUIDAS_*` numa conta com
   histórico de perdas — pra confirmar o B3 em campo, antes deste push.
5. Sua opinião sobre o `iMA` vs `iCustom` (Passo 6).

Qualquer erro, me manda cru que eu corrijo e faço push na mesma branch.
