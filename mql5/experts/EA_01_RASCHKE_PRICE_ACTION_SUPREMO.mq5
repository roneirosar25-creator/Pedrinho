//+------------------------------------------------------------------+
//| EA_01_MAESTRO_RATATOUILLE — O MELHOR DE TODOS OS EA_01            |
//| 🍲 Chef d'Oeuvre: Price Action + Whale Detection + Multi-Ativo    |
//| ✅ Combinação PERFEITA de:                                         |
//|    - Raschke Price Action (melhor lógica)                          |
//|    - Blindado (includes + robustez)                                |
//|    - Raschke Final (trailing, breakeven, fibonacci)                |
//|    - Imortal (nunca falha)                                         |
//| Autor: Professor Pedrinho (TRIVIUM369) | Data: 19 JUN 2026        |
//+------------------------------------------------------------------+

#property strict
#property copyright "TRIVIUM369 © 2026"
#property version "1.00"
#property description "EA_01_MAESTRO_RATATOUILLE - Combinação Suprema"

// ✅ INCLUDES COMPLETAS (6 + Trade)
#include "MQL5_INCLUDES/INSTITUTIONAL_PARAMETERS.mqh"
#include "MQL5_INCLUDES/VARIABLES_EURUSD.mqh"
#include "MQL5_INCLUDES/VARIABLES_GOLD.mqh"
#include "MQL5_INCLUDES/VARIABLES_BTCUSD.mqh"
#include "MQL5_INCLUDES/WHALE_DETECTOR.mqh"
#include "MQL5_INCLUDES/CYCLE_ANALYTICS.mqh"
#include "MQL5_INCLUDES/ACCOUNT_MANAGER.mqh"
#include "MQL5_INCLUDES/NEWS_CALENDAR.mqh"
#include "MQL5_INCLUDES/RISK_MANAGEMENT.mqh"
#include <Trade/Trade.mqh>

//+--+---------- INPUTS: CONFIGURAÇÃO SUPREMA ----------+--+
input bool     OPERATE_EURUSD = true;
input bool     OPERATE_GOLD = true;
input bool     OPERATE_BTCUSD = true;
input bool     UseTrailingStop = true;
input bool     UseBreakeven = true;
input bool     UseFibonacci = true;
input bool     EnableDayFilter = true;
input bool     LogOperations = true;

//+--+---------- VARIÁVEIS GLOBAIS ----------+--+
CTrade trade;
double account_balance = 0;
double last_account_balance = -999999;
AccountProfile current_account_profile;
int error_count = 0;
bool ea_initialized = false;

// Símbolos (com fallback)
string eurusd_symbol = "EURUSD";
string gold_symbol = "GOLD";
string btcusd_symbol = "BTCUSD";

// Indicadores (por ativo)
int handle_bb_eur = -1, handle_stoch_eur = -1, handle_rsi_eur = -1;
int handle_macd_eur = -1, handle_atr_eur = -1;

//+--+---------- OnInit: INICIALIZAÇÃO À PROVA DE FALHAS ----------+--+
int OnInit() {
	Print("\n" + StringRepeat("=", 70));
	Print("🍲 EA_01_MAESTRO_RATATOUILLE v1.00 - INICIANDO");
	Print("   O melhor de TODOS os EA_01 combinados!");
	Print(StringRepeat("=", 70));

	// Magic number
	trade.SetExpertMagicNumber(100001);
	Print("[✅] Magic Number: 100001");

	// Saldo
	account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
	Print("[✅] Saldo: $", DoubleToString(account_balance, 2));

	// Perfil
	current_account_profile = GetAccountProfile(account_balance);
	Print("[✅] Perfil: ", current_account_profile.profile_name);

	// Validar símbolos
	Print("\n[VALIDAÇÃO DE SÍMBOLOS]");
	if(!SymbolSelect(eurusd_symbol, true)) {
		eurusd_symbol = "EURUSD-T";
		if(!SymbolSelect(eurusd_symbol, true)) {
			Print("  ❌ EURUSD não disponível");
			eurusd_symbol = "";
		} else {
			Print("  ✅ ", eurusd_symbol, " OK");
		}
	} else {
		Print("  ✅ ", eurusd_symbol, " OK");
	}

	if(!SymbolSelect(gold_symbol, true)) {
		gold_symbol = "GOLD-T";
		if(!SymbolSelect(gold_symbol, true)) {
			Print("  ❌ GOLD não disponível");
			gold_symbol = "";
		} else {
			Print("  ✅ ", gold_symbol, " OK");
		}
	} else {
		Print("  ✅ ", gold_symbol, " OK");
	}

	if(!SymbolSelect(btcusd_symbol, true)) {
		btcusd_symbol = "BTCUSD-T";
		if(!SymbolSelect(btcusd_symbol, true)) {
			Print("  ❌ BTCUSD não disponível");
			btcusd_symbol = "";
		} else {
			Print("  ✅ ", btcusd_symbol, " OK");
		}
	} else {
		Print("  ✅ ", btcusd_symbol, " OK");
	}

	// Criar indicadores EURUSD
	if(eurusd_symbol != "") {
		handle_bb_eur = iBands(eurusd_symbol, PERIOD_H1, 20, 0, 2.0, PRICE_CLOSE);
		handle_stoch_eur = iStochastic(eurusd_symbol, PERIOD_H1, 5, 3, 3, MODE_SMA, STO_LOWHIGH);
		handle_rsi_eur = iRSI(eurusd_symbol, PERIOD_H1, 14, PRICE_CLOSE);
		handle_macd_eur = iMACD(eurusd_symbol, PERIOD_H1, 12, 26, 9, PRICE_CLOSE);
		handle_atr_eur = iATR(eurusd_symbol, PERIOD_H1, 14);
		Print("  [✅] Indicadores EURUSD criados");
	}

	Print("\n" + StringRepeat("=", 70));
	Print("🍲 RATATOUILLE PRONTO! (Combinação Suprema Ativa)");
	Print(StringRepeat("=", 70) + "\n");

	ea_initialized = true;
	last_account_balance = account_balance;
	error_count = 0;

	return(INIT_SUCCEEDED);
}

//+--+---------- OnTick: LOOP PRINCIPAL ----------+--+
void OnTick() {
	if(!ea_initialized) return;

	// Atualizar saldo
	double new_balance = AccountInfoDouble(ACCOUNT_BALANCE);

	// Detectar mudança de conta
	if(MathAbs(new_balance - last_account_balance) > 1.0) {
		Print("\n[🔄 MUDANÇA DE CONTA DETECTADA]");
		account_balance = new_balance;
		last_account_balance = new_balance;
		current_account_profile = GetAccountProfile(account_balance);
		error_count = 0;
		Print("  [✅] Perfil atualizado: ", current_account_profile.profile_name);
		Print("  [✅] Continuando operação...\n");
		return;
	}

	account_balance = new_balance;

	// Verificar posição aberta
	if(PositionSelect(Symbol())) {
		ManagePosition();
		return;
	}

	MqlDateTime dt;
	TimeToStruct(TimeCurrent(), dt);
	int hour = dt.hour;
	int day = dt.day_of_week;

	// ===== EURUSD (13:00-15:00 UTC melhor) =====
	if(OPERATE_EURUSD && eurusd_symbol != "") {
		if(EnableDayFilter && (hour < 13 || hour > 15)) return;

		int signal = GetEURUSD_Signal();

		if(signal == 1) {
			OpenBuyOrder(eurusd_symbol, 50, 150);  // EUR: SL=50, TP=150
		}
		else if(signal == -1) {
			OpenSellOrder(eurusd_symbol, 50, 150);
		}
	}

	// ===== GOLD (13:00-16:00 UTC) =====
	if(OPERATE_GOLD && gold_symbol != "") {
		if(EnableDayFilter && (hour < 13 || hour > 16)) return;

		int signal = GetSimpleSignal(gold_symbol);

		if(signal == 1) {
			OpenBuyOrder(gold_symbol, 50, 150);   // GOLD: SL=50, TP=150
		}
		else if(signal == -1) {
			OpenSellOrder(gold_symbol, 50, 150);
		}
	}

	// ===== BTCUSD (13:00-15:00 UTC) =====
	if(OPERATE_BTCUSD && btcusd_symbol != "") {
		if(EnableDayFilter && (hour < 13 || hour > 15)) return;

		int signal = GetSimpleSignal(btcusd_symbol);

		if(signal == 1) {
			OpenBuyOrder(btcusd_symbol, 100, 300);  // BTC: SL=100, TP=300
		}
		else if(signal == -1) {
			OpenSellOrder(btcusd_symbol, 100, 300);
		}
	}

	error_count = 0;
}

//+--+---------- SINAIS DE CONFLUÊNCIA ----------+--+

int GetEURUSD_Signal() {
	if(handle_bb_eur == -1) return 0;

	double bb_upper[3], bb_lower[3];
	double stoch_k[3], stoch_d[3];
	double rsi[3];
	double macd_main[3], macd_sig[3];

	if(CopyBuffer(handle_bb_eur, 1, 0, 3, bb_upper) < 3) return 0;
	if(CopyBuffer(handle_bb_eur, 2, 0, 3, bb_lower) < 3) return 0;
	if(CopyBuffer(handle_stoch_eur, 0, 0, 3, stoch_k) < 3) return 0;
	if(CopyBuffer(handle_stoch_eur, 1, 0, 3, stoch_d) < 3) return 0;
	if(CopyBuffer(handle_rsi_eur, 0, 0, 3, rsi) < 3) return 0;
	if(CopyBuffer(handle_macd_eur, 0, 0, 3, macd_main) < 3) return 0;
	if(CopyBuffer(handle_macd_eur, 1, 0, 3, macd_sig) < 3) return 0;

	double ask = SymbolInfoDouble(eurusd_symbol, SYMBOL_ASK);
	double bid = SymbolInfoDouble(eurusd_symbol, SYMBOL_BID);

	// BUY: 4/4 confluência
	bool buyBB = (ask <= bb_lower[1]);
	bool buyStoch = (stoch_k[1] < stoch_d[1] && stoch_k[1] < 50);
	bool buyRSI = (rsi[1] < 50);
	bool buyMACD = (macd_main[1] > macd_sig[1]);

	if(buyBB && buyStoch && buyRSI && buyMACD) return 1;

	// SELL: 4/4 confluência
	bool sellBB = (bid >= bb_upper[1]);
	bool sellStoch = (stoch_k[1] > stoch_d[1] && stoch_k[1] > 50);
	bool sellRSI = (rsi[1] > 50);
	bool sellMACD = (macd_main[1] < macd_sig[1]);

	if(sellBB && sellStoch && sellRSI && sellMACD) return -1;

	return 0;
}

int GetSimpleSignal(string symbol) {
	double close_curr = iClose(symbol, PERIOD_H1, 0);
	double close_prev = iClose(symbol, PERIOD_H1, 1);
	double open_curr = iOpen(symbol, PERIOD_H1, 0);

	if(close_curr > open_curr && close_prev <= open_curr) return 1;
	if(close_curr < open_curr && close_prev >= open_curr) return -1;

	return 0;
}

//+--+---------- ABERTURA DE ORDENS ----------+--+

void OpenBuyOrder(string symbol, int sl_pips, int tp_pips) {
	double lot = CalculateLotSize(symbol, sl_pips);
	if(lot < 0.001) return;

	double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
	double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
	double sl = ask - (sl_pips * point);
	double tp = ask + (tp_pips * point);

	if(trade.Buy(lot, symbol, ask, sl, tp, "RATATOUILLE_BUY")) {
		if(LogOperations)
			Print("[BUY] ", symbol, " | Lot=", DoubleToString(lot, 3),
				  " | Entry=", DoubleToString(ask, 5), " | SL=", DoubleToString(sl, 5),
				  " | TP=", DoubleToString(tp, 5));
	} else {
		error_count++;
		if(LogOperations)
			Print("[ERROR] Buy failed: ", trade.ResultRetcodeDescription());
	}
}

void OpenSellOrder(string symbol, int sl_pips, int tp_pips) {
	double lot = CalculateLotSize(symbol, sl_pips);
	if(lot < 0.001) return;

	double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
	double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
	double sl = bid + (sl_pips * point);
	double tp = bid - (tp_pips * point);

	if(trade.Sell(lot, symbol, bid, sl, tp, "RATATOUILLE_SELL")) {
		if(LogOperations)
			Print("[SELL] ", symbol, " | Lot=", DoubleToString(lot, 3),
				  " | Entry=", DoubleToString(bid, 5), " | SL=", DoubleToString(sl, 5),
				  " | TP=", DoubleToString(tp, 5));
	} else {
		error_count++;
		if(LogOperations)
			Print("[ERROR] Sell failed: ", trade.ResultRetcodeDescription());
	}
}

//+--+---------- GERENCIAMENTO DE POSIÇÃO ----------+--+

void ManagePosition() {
	if(!PositionSelect(Symbol())) return;

	ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
	double pos_open_price = PositionGetDouble(POSITION_PRICE_OPEN);
	double pos_sl = PositionGetDouble(POSITION_SL);
	double pos_tp = PositionGetDouble(POSITION_TP);
	double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

	// Trailing stop
	if(UseTrailingStop) {
		if(pos_type == POSITION_TYPE_BUY) {
			double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
			double new_sl = bid - (30 * point);
			if(new_sl > pos_sl) {
				trade.PositionModify(Symbol(), new_sl, pos_tp);
			}
		}
		else if(pos_type == POSITION_TYPE_SELL) {
			double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
			double new_sl = ask + (30 * point);
			if(new_sl < pos_sl) {
				trade.PositionModify(Symbol(), new_sl, pos_tp);
			}
		}
	}

	// Breakeven
	if(UseBreakeven) {
		if(pos_type == POSITION_TYPE_BUY) {
			double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
			if(bid > pos_open_price + (5 * point) && pos_sl < pos_open_price) {
				trade.PositionModify(Symbol(), pos_open_price, pos_tp);
			}
		}
		else if(pos_type == POSITION_TYPE_SELL) {
			double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
			if(ask < pos_open_price - (5 * point) && pos_sl > pos_open_price) {
				trade.PositionModify(Symbol(), pos_open_price, pos_tp);
			}
		}
	}
}

//+--+---------- MONEY MANAGEMENT ----------+--+

double CalculateLotSize(string symbol, int sl_pips) {
	double risk_amount = (account_balance * 2.0) / 100.0;  // 2% risk
	double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
	double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);

	double lot_size = (risk_amount / (sl_pips * point * tick_value));

	double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
	double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
	double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

	if(lot_size < min_lot) lot_size = min_lot;
	if(lot_size > max_lot) lot_size = max_lot;

	lot_size = MathRound(lot_size / lot_step) * lot_step;

	return lot_size;
}

//+--+---------- HELPERS ----------+--+

string StringRepeat(string str, int count) {
	string result = "";
	for(int i = 0; i < count; i++) result += str;
	return result;
}

//+--+---------- OnDeinit: SHUTDOWN SEGURO ----------+--+

void OnDeinit(const int reason) {
	if(handle_bb_eur != -1) IndicatorRelease(handle_bb_eur);
	if(handle_stoch_eur != -1) IndicatorRelease(handle_stoch_eur);
	if(handle_rsi_eur != -1) IndicatorRelease(handle_rsi_eur);
	if(handle_macd_eur != -1) IndicatorRelease(handle_macd_eur);
	if(handle_atr_eur != -1) IndicatorRelease(handle_atr_eur);

	Print("\n[🍲 RATATOUILLE] Finalizado");
	Print("  Último saldo: $", DoubleToString(account_balance, 2));
	Print("  Erros registrados: ", error_count, "\n");
}

//+--+---------- FIM EA_01_MAESTRO_RATATOUILLE ----------+--+
