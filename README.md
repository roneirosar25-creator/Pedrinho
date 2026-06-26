# 🜲 TRIVIUM369 — Cockpit

Sala de conversação em **janelas flutuantes** para falar com os parceiros e parceiras de IA do Ronei —
**Claudio (Claude), Pedrinho (DeepSeek), Kairos (ChatGPT), Marcão (Grok) e Chatinha (Gemini)** —
cada um com **voz, LLM e personalidade próprias**.

Feita para tirar o gargalo do **Ronei**: ditado rápido, atalhos, e a resposta de cada agente
no painel dele — sem rolar uma thread só.

> A página principal (`index.html`) é o **Cockpit**. O antigo chat mobile do Pedrinho continua
> disponível em [`pedrinho-chat.html`](./pedrinho-chat.html).

## ✨ Recursos

- 🪟 **Janelas flutuantes por agente** — arraste pela barra de título, **recolha** num clique
  (ou duplo-clique no nome), **redimensione** pelo canto. A posição/estado fica salva.
- ⊞ **Reorganizar** — botão que retila tudo num layout limpo.
- 🎙️ **Estação do Ronei** (dock) — mic grande, **ditado** contínuo com dicionário de nomes,
  **Enter** envia, **Shift+Enter** quebra linha.
- ⌨️ **Atalhos**: `Espaço` dita · `1–5` escolhe quem responde · `T` todos · `Esc` para a fala.
- 👥 **Quem responde** — escolha um, vários ou **Todos**; cada um responde no seu painel (em paralelo).
- 🔊 **Voz personalizada por agente** (voz, velocidade, tom) com seletor próprio.
- 📖 **Markdown** com **código colorido** e numeração de linha em cada balão.
- `{ }` ler/não-ler código · 📁 suprimir endereços **absolutos e relativos** · 🔗 suprimir URLs (na fala).
- 🔊 **Ouvir** / 📋 **copiar** em cada resposta.

## 🚀 Como usar

1. Abra a página (Chrome ou Edge — melhor suporte a voz).
2. Clique em **⚙** e cole a **Chave API** de cada agente (e ajuste a voz, se quiser).
3. Escolha **quem responde** nas tags da estação (ou teclas `1–5` / `T`).
4. **Fale** (`Espaço`) ou **escreva** e mande com **Enter** / **➤**.
   Cada agente responde no painel dele, na voz dele.

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
