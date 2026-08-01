//+------------------------------------------------------------------+
//| STOP_DIARIO.mqh - Stop Diário de Equity (TRIVIUM369)             |
//| Single source of truth para bloqueio de novas entradas no dia    |
//| Bloqueio vale para a CONTA INTEIRA, não por EA individual.       |
//| Ver: 00_NUCLEO/SPEC_STOP_DIARIO.md (CONFIRMADO 2026-07-06)       |
//+------------------------------------------------------------------+

#property library
#property copyright "Pedrinho/TRIVIUM369"
#property version "1.0"

//--- Nomes de GlobalVariable compartilhadas entre todos os EAs da conta
#define GV_STOP_DIARIO_EQUITY_INICIO   "TRIVIUM369_STOP_DIARIO_EQUITY_INICIO"
#define GV_STOP_DIARIO_DIA             "TRIVIUM369_STOP_DIARIO_DIA"
#define GV_STOP_DIARIO_BLOQUEADO       "TRIVIUM369_STOP_DIARIO_BLOQUEADO"

//--- Percentual confirmado por Ronei em 2026-07-06 (ver SPEC_STOP_DIARIO.md secao 3)
#define STOP_DIARIO_PCT  10.0

//+------------------------------------------------------------------+
//| Retorna a chave do dia atual (YYYYMMDD) no fuso do servidor      |
//+------------------------------------------------------------------+
long DiaAtualServidor() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return (long)dt.year * 10000 + (long)dt.mon * 100 + (long)dt.day;
}

//+------------------------------------------------------------------+
//| Garante que o registro do dia existe e está atualizado.         |
//| Deve ser chamada no início de cada verificação (OnTick/OnTimer). |
//| Se o dia mudou desde o último registro, faz o reset automático. |
//+------------------------------------------------------------------+
void StopDiario_AtualizaRollover() {
    long dia_atual = DiaAtualServidor();
    long dia_registrado = 0;

    if (GlobalVariableCheck(GV_STOP_DIARIO_DIA)) {
        dia_registrado = (long)GlobalVariableGet(GV_STOP_DIARIO_DIA);
    }

    if (dia_registrado != dia_atual) {
        //--- Novo dia (ou primeira execucao): reset completo
        double equity_atual = AccountInfoDouble(ACCOUNT_EQUITY);
        // FIX 09/07/2026 (Ronei achou o bug ao vivo): logo apos o terminal
        // subir, a conexao pode nao estar pronta ainda e ACCOUNT_EQUITY
        // retorna 0 por uma fracao de segundo. Se registrarmos esse 0 como
        // "equity de inicio do dia", QUALQUER equity real depois vira uma
        // "perda" de ~100% (falso positivo, ja aconteceu: alerta de 99.93%
        // de perda sem perda nenhuma de verdade). Enquanto equity<=0, NAO
        // commita o rollover - so tenta de novo no proximo tick.
        if (equity_atual <= 0) {
            return; // adia o rollover, mantem o registro anterior valido
        }
        GlobalVariableSet(GV_STOP_DIARIO_DIA, (double)dia_atual);
        GlobalVariableSet(GV_STOP_DIARIO_EQUITY_INICIO, equity_atual);
        GlobalVariableSet(GV_STOP_DIARIO_BLOQUEADO, 0.0);
    }
}

//+------------------------------------------------------------------+
//| Verifica se o trading está bloqueado hoje por atingir o stop    |
//| diário. Atualiza o estado de bloqueio como efeito colateral.    |
//|                                                                    |
//| Retorna true se BLOQUEADO (nenhum EA deve abrir posição nova).  |
//+------------------------------------------------------------------+
bool StopDiario_Bloqueado() {
    StopDiario_AtualizaRollover();

    //--- Se já estava bloqueado hoje, permanece bloqueado (não reavalia pra cima)
    if (GlobalVariableCheck(GV_STOP_DIARIO_BLOQUEADO) &&
        GlobalVariableGet(GV_STOP_DIARIO_BLOQUEADO) >= 1.0) {
        return true;
    }

    double equity_inicio = GlobalVariableGet(GV_STOP_DIARIO_EQUITY_INICIO);
    if (equity_inicio <= 0) {
        return false; // estado inválido, não bloqueia por segurança de dado
    }

    double equity_atual = AccountInfoDouble(ACCOUNT_EQUITY);
    // FIX 09/07/2026 (bug real encontrado ao vivo por Ronei): se a equity
    // atual ler 0 (ou negativa) por causa de reconexao/race condition, o
    // calculo dava quase 100% de "perda" sem perda nenhuma de verdade
    // (alerta falso de 99.93% ja aconteceu). Sem leitura valida, nao
    // avalia bloqueio nesta chamada - so tenta de novo no proximo tick.
    if (equity_atual <= 0) {
        return false;
    }
    double perda_dia_pct = (equity_inicio - equity_atual) / equity_inicio * 100.0;

    if (perda_dia_pct >= STOP_DIARIO_PCT) {
        GlobalVariableSet(GV_STOP_DIARIO_BLOQUEADO, 1.0);
        Alert("🛑 STOP DIÁRIO ACIONADO — Perda do dia: ", DoubleToString(perda_dia_pct, 2),
              "% >= limite de ", DoubleToString(STOP_DIARIO_PCT, 1), "%. Novas entradas bloqueadas até o próximo dia.");
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Conveniência: perda do dia atual em % (para logging/painel)     |
//+------------------------------------------------------------------+
double StopDiario_PerdaAtualPct() {
    StopDiario_AtualizaRollover();
    double equity_inicio = GlobalVariableGet(GV_STOP_DIARIO_EQUITY_INICIO);
    if (equity_inicio <= 0) return 0.0;
    double equity_atual = AccountInfoDouble(ACCOUNT_EQUITY);
    return (equity_inicio - equity_atual) / equity_inicio * 100.0;
}

//+------------------------------------------------------------------+
//| GUARDA DE MARGEM (20/07/2026) - Ronei pediu depois de ver a conta |
//| com varios EAs novos rodando ao mesmo tempo (margem em 133%,      |
//| chamada da corretora acontece em 100%, sem muita folga). Cada EA  |
//| so controla o proprio risco por trade, nenhum olha pro nivel de   |
//| margem da CONTA INTEIRA - vários EAs podem empilhar posicao no    |
//| mesmo ativo (ja aconteceu: 2 SELL EURCHF simultaneos, Estilingue  |
//| + Rompimento Falso, cada um sem saber do outro).                  |
//|                                                                    |
//| Bloqueia NOVAS entradas (nao mexe em posicao ja aberta - quem      |
//| gerencia saida e o trailing de cada EA) se o nivel de margem cair  |
//| abaixo de MARGEM_MINIMA_PCT. Nivel 0 = sem posicao aberta, nao     |
//| bloqueia (evita falso positivo, mesmo raciocinio do fix de equity  |
//| zerada acima). Uma vez que dispara, fica bloqueado ate o Ronei     |
//| decidir (nao rearma sozinho quando a margem recupera - decisao     |
//| dele, nao automatica, mesmo padrao do kill switch).                |
//+------------------------------------------------------------------+
#define GV_MARGEM_BLOQUEADA "TRIVIUM369_MARGEM_BLOQUEADA"
#define MARGEM_MINIMA_PCT 150.0

bool MargemBloqueada() {
    if (GlobalVariableCheck(GV_MARGEM_BLOQUEADA) && GlobalVariableGet(GV_MARGEM_BLOQUEADA) >= 1.0) {
        return true; // ja disparou - fica bloqueado ate reset manual (GlobalVariableSet 0 ou reinicio da conta)
    }

    double nivel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    if (nivel <= 0) return false; // sem posicao aberta (ou dado invalido) - nao bloqueia

    if (nivel < MARGEM_MINIMA_PCT) {
        GlobalVariableSet(GV_MARGEM_BLOQUEADA, 1.0);
        Alert("MARGEM BAIXA - nivel ", DoubleToString(nivel, 1), "% abaixo do minimo seguro de ",
              DoubleToString(MARGEM_MINIMA_PCT, 0), "%. Novas entradas de TODOS os EAs bloqueadas ate o Ronei revisar.");
        return true;
    }
    return false;
}

//--- FIM STOP_DIARIO.mqh
