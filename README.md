# 🜲 TRIVIUM369 — Sala de Conversação

Transcritor e leitor de voz para conversar com os parceiros e parceiras de IA do Ronei —
**Claudio (Claude), Pedrinho (DeepSeek), Kairos (ChatGPT), Marcão (Grok) e Chatinha (Gemini)** —
cada um com **voz, LLM e personalidade próprias**.

> A página principal (`index.html`) é a **Sala**. O antigo chat mobile do Pedrinho continua
> disponível em [`pedrinho-chat.html`](./pedrinho-chat.html).

## ✨ Recursos

- 🎙️ **Ditado** (voz→texto) contínuo, com dicionário de correção dos nomes do time.
- 🔊 **Voz personalizada por agente** (nome da voz, velocidade e tom), com seletor próprio.
- 📖 **Leitor de Markdown** com **código colorido** e numeração de linha.
- `{ }` **Ler / não-ler código** — pula código na leitura, mantém a exibição.
- 📁 **Supressão de endereços** absolutos (`C:\…`, `/home/…`) **e** relativos (`./src/x.js`, `pasta/arquivo.ext`).
- 🔗 **Supressão de URLs**.
- ⏯️ **Leitura frase a frase** com destaque de palavra; clicar para pular.
- ➤ **Enviar para o agente ativo** — chama a IA direto (se a chave estiver configurada) e lê a resposta na voz dele.
- ✏️ Corrigir / 📋 Copiar / 💾 Salvar (.md) / **MD** preview no painel de fala.

## 🚀 Como usar

1. Abra a página (Chrome ou Edge — melhor suporte a voz).
2. Clique em **⚙** e cole a **Chave API** de cada agente que quiser ativar (e ajuste a voz).
3. Escolha o agente na barra de **abas** no topo.
4. **Fale** (tecla Espaço) ou **escreva** no painel direito e clique **➤** para enviar.
   - Sem chave configurada, é só **colar** a resposta do agente no painel esquerdo (📋) que a sala lê.

## 🔐 Segurança

As chaves API ficam **apenas no `localStorage` do seu navegador** — nunca no repositório,
no GitHub ou na Vercel. Como as chamadas saem do navegador, use chaves com limite quando possível.

## 🧠 Quem é quem / qual LLM

Veja **[`AGENTES.md`](./AGENTES.md)** — a divisão de identidades, vozes e a recomendação de LLM por agente.

## 🛠️ Tecnologia

Página única, sem build, sem servidor: **HTML + CSS + JavaScript** + **Web Speech API**.
Provedores via REST direto: Anthropic, OpenAI, DeepSeek, xAI/Grok (compatível OpenAI) e Google Gemini.

---

**Desenvolvido para o TRIVIUM369** ❤️
