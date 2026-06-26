# 🜲 TRIVIUM369 — Sala de Conversação

Divisão de identidades, vozes e LLMs dos parceiros e parceiras de trabalho do Ronei.
Cada um tem **identidade singular**: ferramenta (LLM), voz, forma de falar, forma de pensar e forma de agir.

> Princípio: *poupar recursos em comunicação e inteligência é burrice e perder dinheiro.*
> Logo cada agente terá a **sua própria Chave API** — a sala já está preparada para isso
> (chamadas diretas por agente; a chave fica só no navegador, nunca no repositório).

---

## 1. Quem é quem

| Agente | Papel na mesa | Ferramenta (LLM) | Modelo sugerido | Voz | Cor |
|---|---|---|---|---|---|
| **Claudio** | Arquiteto-chefe. Raciocínio longo, decisões de arquitetura, código complexo, revisão e "última palavra" técnica. | **Claude (Anthropic)** | `claude-opus-4-8` | Masculina PT-BR, calma e precisa (ex.: *Daniel*) | Índigo `#6366f1` |
| **Pedrinho** (Dr. Pedro) | Dev de EA/MQL5, automação no MetaTrader 5, código de execução rápido e barato. | **DeepSeek** | `deepseek-coder` / `deepseek-chat` | Masculina PT-BR grave, técnica | Verde `#22c55e` |
| **Kairos** | Orquestrador de trading. Análise de mercado, ferramentas, tempo real, varredura de dados. | **ChatGPT (OpenAI)** | `gpt-4o` (ou `o3` p/ raciocínio) | Masculina/neutra, ágil | Laranja `#fb923c` |
| **Marcão** | Mentor de disciplina e gestão de risco. O "durão" — corta euforia, impõe stop, cobra plano. | **Grok (xAI)** | `grok-2` | Masculina firme, direta | Vermelho `#ef4444` |
| **Chatinha** | Secretária/organização. Conversa leve, resumos, agenda, lembretes, traduções. | **Gemini (Google)** | `gemini-2.0-flash` | Feminina PT-BR leve (ex.: *Thalita/Maria*) | Rosa/violeta `#a78bfa` |
| **Ronei** (você) | Humano no comando. Fala (voz→texto) ou digita; envia para um agente por vez. | — | — | — | — |

---

## 2. Por que cada LLM (o raciocínio da divisão)

A ideia é que **nenhum dois pensem igual** — diversidade de modelo = diversidade de erro, e isso protege o dinheiro.

- **Claudio → Claude Opus 4.8** — o mais forte em raciocínio longo, código grande e revisão crítica. É a "cabeça fria" da mesa: quando a decisão é cara e irreversível, é o Claudio que fecha. Voz calma e pausada reforça o papel.
- **Pedrinho → DeepSeek** — foco em **código** (MQL5/EA, scripts), barato por token e muito competente em programação. Perfeito para o trabalho braçal de implementação no MT5 sem queimar orçamento. Voz grave e técnica.
- **Kairos → ChatGPT (OpenAI)** — melhor ecossistema de **ferramentas/realtime** e function-calling para orquestrar análise de mercado, puxar dados e coordenar o pipeline. Voz ágil, de operador.
- **Marcão → Grok (xAI)** — estilo **direto e sem rodeios**, ótimo para o papel de disciplina/risco: ele te confronta quando você quer "dobrar a aposta". Voz firme. (API compatível com OpenAI — `https://api.x.ai/v1`.)
- **Chatinha → Gemini (Google)** — rápida, multimodal, ótima para **organização, resumos e tradução** do dia a dia, com custo baixo no `flash`. Voz feminina leve, de secretária.

> Trocar é fácil: tudo está em `AGENTS` no `index.html`. Mudar provedor/modelo/voz de um agente é uma linha.

---

## 3. Como falam, pensam e agem (persona resumida)

- **Claudio** — analítico, estruturado, honesto sobre incerteza. Dá recomendação, não cardápio. Cita trade-offs. Não puxa saco.
- **Pedrinho** — mão na massa, objetivo, entrega código pronto para colar. Comenta o porquê das escolhas técnicas.
- **Kairos** — operador. Fala em setups, níveis, risco/retorno, confluências. Pragmático e rápido.
- **Marcão** — guardião do capital. Pergunta "qual o seu stop?" antes de qualquer coisa. Firme, às vezes incômodo — de propósito.
- **Chatinha** — leve e organizada. Resume, agenda, traduz, mantém a casa em ordem. Tom acolhedor.

As personas vivem no campo `system` de cada agente em `index.html` — edite à vontade.

---

## 4. Recursos da sala (Cockpit — já implementados)

- **Janelas flutuantes por agente** — arrastáveis pela barra de título, **recolhíveis** (▾ ou duplo-clique no nome) e **redimensionáveis**; posição/estado salvos. Botão **⊞** reorganiza tudo.
- **Estação do Ronei** (dock) com mic grande e ditado contínuo — feita para tirar o gargalo do humano.
- **Atalhos**: `Espaço` dita · `1–5` escolhe quem responde · `T` todos · `Enter` envia · `Esc` para a fala.
- **Voz personalizada por agente** (voz + velocidade + tom), com seletor de voz por agente.
- **Markdown** com **código colorido** (syntax highlight) e numeração de linha em cada balão.
- **Ler / Não-ler código** (`{ }`) · **Supressão de endereços** (📁) **absolutos** (`C:\...`, `/home/...`) **e relativos** (`./src/x.js`, `pasta/arquivo.ext`) · **URLs** (🔗) — aplicado à fala (TTS).
- **Voz→Texto (ditado)** contínuo com dicionário de correção dos nomes (Ronei, Kairos, Pedrinho, Marcão, Chatinha, TRIVIUM369, pares de FX).
- **Enviar para quem você escolher** — um, vários ou Todos; cada agente com chave responde **no seu painel, em paralelo**, e fala na voz dele. **🔊 ouvir** e **📋 copiar** em cada resposta.

---

## 5. Segurança das chaves

- Cada chave é guardada **apenas no `localStorage` do seu navegador** (⚙ Configurações).
- **Nunca** vai para o repositório, nem para o GitHub, nem para a Vercel.
- Como as chamadas saem do navegador, use chaves com escopo/limite quando possível.

---

## 6. Tecnologia

Página única, sem build, sem servidor: **HTML + CSS + JavaScript puro** + **Web Speech API**
(`speechSynthesis` para TTS e `SpeechRecognition` para ditado). Funciona melhor no **Chrome/Edge**.
Provedores suportados via REST direto: Anthropic, OpenAI, DeepSeek, xAI/Grok (compatível OpenAI) e Google Gemini.
