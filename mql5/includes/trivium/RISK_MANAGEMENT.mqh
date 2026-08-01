//+------------------------------------------------------------------+
//| RISK_MANAGEMENT.mqh - Hard-Cap de Risco (TRIVIUM369)            |
//| Single source of truth para dimensionamento de lote             |
//| Nenhum EA pode furar este cap. Determinística e pura.          |
//+------------------------------------------------------------------+

#property library
#property copyright "Pedrinho/TRIVIUM369"
#property version "1.0"

//--- Resultado de cálculo de risco
struct RiskResult {
    double lot;                    // Lote final (normalizado ao passo)
    string status;                 // "OK", "LIMITADO_AO_TETO", "REJEITADO_*"
    double risk_money;             // Risco em dinheiro
    double risk_pct;               // Risco em % da equity
};

//--- Parâmetros de configuração (defaults EURUSD)
//--- Sobrescritíveis por símbolo através de arquivos VARIABLES
struct RiskConfig {
    double target_pct;             // 3.0 — alvo padrão de risco por trade
    double hard_cap_pct;           // 5.0 — teto que nenhum trade ultrapassa
    double red_line_pct;           // 6.0 — guarda de segurança: jamais alcançável
};

//+------------------------------------------------------------------+
//| Obtém configuração de risco (padrão ou por símbolo)             |
//+------------------------------------------------------------------+
RiskConfig GetRiskConfig(string symbol = "") {
    RiskConfig cfg = {3.0, 5.0, 6.0};  // defaults provisórios

    // TODO: Ler de arquivo VARIABLES por símbolo quando existir
    // Exemplo: cfg = LoadRiskConfigFromFile("VARIABLES_" + symbol + ".mqh");

    return cfg;
}

//+------------------------------------------------------------------+
//| Normaliza lote ao passo de volume do símbolo                   |
//+------------------------------------------------------------------+
double NormalizeToVolumeStep(double lot, double volume_step) {
    if (volume_step <= 0) return 0;
    return MathFloor(lot / volume_step) * volume_step;
}

//+------------------------------------------------------------------+
//| Calcula risco por lote em dinheiro                              |
//+------------------------------------------------------------------+
double CalculateRiskPerLot(string symbol, double stop_distance_pips) {
    double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

    if (tick_size <= 0) return 0;

    return (stop_distance_pips / tick_size) * tick_value;
}

//+------------------------------------------------------------------+
//| FUNÇÃO PRINCIPAL: Calcula lote com hard-cap de risco            |
//|                                                                  |
//| Entradas:                                                       |
//|   symbol          - símbolo de trading (ex: "EURUSD")          |
//|   stop_distance   - distância do stop em pips                  |
//|   proposed_lot    - lote proposto pelo Kelly (0 = ignorar)     |
//|   equity          - equity atual (usa EQUITY, não BALANCE)     |
//|                                                                  |
//| Saída:                                                          |
//|   RiskResult com:                                              |
//|     - lot: lote final (0 = não opera)                         |
//|     - status: motivo da decisão                               |
//|     - risk_money: risco real em dinheiro                      |
//|     - risk_pct: risco real em % da equity                     |
//+------------------------------------------------------------------+
RiskResult CalculateLotWithHardCap(
    string symbol,
    double stop_distance,          // em pips
    double proposed_lot = 0,       // do Kelly/sizer (opcional)
    double equity = 0              // se 0, usa AccountInfoDouble(ACCOUNT_EQUITY)
) {
    RiskResult result = {0, "REJEITADO_SEM_STOP", 0, 0};

    //--- Lei Zero: stop obrigatório
    if (stop_distance <= 0) {
        return result;
    }

    //--- Obtém configuração de risco
    RiskConfig cfg = GetRiskConfig(symbol);

    //--- Se equity não fornecida, usa a conta
    if (equity <= 0) {
        equity = AccountInfoDouble(ACCOUNT_EQUITY);
    }

    if (equity <= 0) {
        result.status = "REJEITADO_EQUITY_INVALIDA";
        return result;
    }

    //--- Informações do símbolo
    double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double volume_min = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double volume_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    if (tick_value <= 0 || tick_size <= 0 || volume_step <= 0) {
        result.status = "REJEITADO_SIMBOLO_INVALIDO";
        return result;
    }

    //--- Calcula risco por lote em dinheiro
    double risk_per_lot = CalculateRiskPerLot(symbol, stop_distance);
    if (risk_per_lot <= 0) {
        result.status = "REJEITADO_RISCO_ZERO";
        return result;
    }

    //--- Limites de risco em dinheiro
    double cap_money = (cfg.hard_cap_pct / 100.0) * equity;
    double target_money = (cfg.target_pct / 100.0) * equity;

    //--- Dimensiona pelo alvo
    double lot = target_money / risk_per_lot;

    //--- Se foi proposto um lote, usa o menor
    if (proposed_lot > 0) {
        lot = MathMin(lot, proposed_lot);
    }

    //--- Normaliza ao passo de volume
    lot = NormalizeToVolumeStep(lot, volume_step);

    double risk_money = lot * risk_per_lot;

    //--- Aplica teto duro
    if (risk_money > cap_money) {
        lot = NormalizeToVolumeStep(cap_money / risk_per_lot, volume_step);
        risk_money = lot * risk_per_lot;
        result.status = "LIMITADO_AO_TETO";
    } else {
        result.status = "OK";
    }

    //--- Proteção: lote mínimo já estoura o teto?
    if (lot < volume_min || (volume_min * risk_per_lot) > cap_money) {
        result.status = "REJEITADO_LOTE_MINIMO_ACIMA_DO_TETO";
        return result;
    }

    //--- Guarda da linha vermelha (defesa em profundidade)
    double red_line_money = (cfg.red_line_pct / 100.0) * equity;
    if (risk_money >= red_line_money) {
        result.status = "REJEITADO_LINHA_VERMELHA";
        Alert("🚨 LINHA VERMELHA ACIONADA — Risco ", DoubleToString(risk_money, 2),
              " >= ", DoubleToString(red_line_money, 2));
        return result;
    }

    //--- Sucesso
    result.lot = lot;
    result.risk_money = risk_money;
    result.risk_pct = (risk_money / equity) * 100.0;

    return result;
}

//+------------------------------------------------------------------+
//| Função de conveniência: retorna apenas o lote                  |
//+------------------------------------------------------------------+
double GetSafeLot(
    string symbol,
    double stop_distance,
    double proposed_lot = 0,
    double equity = 0
) {
    RiskResult r = CalculateLotWithHardCap(symbol, stop_distance, proposed_lot, equity);
    return r.lot;
}

//--- FIM RISK_MANAGEMENT.mqh
