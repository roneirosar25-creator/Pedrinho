//+------------------------------------------------------------------+
//|                                        Dashboard_Correlacoes_v2   |
//|                     Advanced Correlation Dashboard v2.1           |
//|     Multi-TF | Click-to-Switch c/ Lock | Heatmap | Drag | -T OK  |
//|                                    by AAIF (Agentic AI Foundation)|
//+------------------------------------------------------------------+
#property copyright "AAIF - Agentic AI Foundation"
#property link      "https://aai.foundation"
#property version   "2.10"
#property description "Dashboard de Correlacoes Avancado v2.1"
#property description "Multi-timeframe H1/H4/D1 | Clique c/ trava"
#property description "Heatmap | Arraste o painel | Spread | -T OK"

//+------------------------------------------------------------------+
//| Inputs (use SEM o sufixo -T, o EA adiciona automaticamente)      |
//+------------------------------------------------------------------+
input string InpMainSymbol   = "EURUSD";         // Main Symbol (ex: EURUSD, sem -T)
input ENUM_TIMEFRAMES InpTF  = PERIOD_H1;        // Main TF for correlation
input bool   InpShowD1       = true;             // Show Daily (D1)
input bool   InpShowW1       = false;            // Show Weekly (W1)
input int    InpInterval     = 5;                // Update Interval (sec)
input int    InpBars         = 50;               // Bars for Correlation Calc
input color  InpBgColor      = clrBlack;         // Background Color
input int    InpFontSize     = 8;                // Font Size
input string InpExtraSymbols = "XAUUSD,XAGUSD";  // Extra symbols (comma-separated, sem -T)
input bool   InpAlerts       = false;            // Enable threshold alerts
input double InpAlertHigh    = 0.80;             // High alert threshold
input double InpAlertLow     = -0.80;            // Low alert threshold
input int    InpColWidth     = 100;              // Column width (px)
input int    InpRowHeight    = 22;               // Row height (px)
input bool   InpAutoMinimize = false;            // Auto-minimize on start

//+------------------------------------------------------------------+
//| Constants                                                        |
//+------------------------------------------------------------------+
#define SUFFIX "-T"   // Sua corretora usa -T. Altere aqui se precisar

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct SymData {
   string   name;        // MT5 symbol name (com sufixo)
   string   nameRaw;     // Symbol name sem sufixo
   string   label;       // Display label
   string   group;       // Group for coloring
   double   price;
   double   changeD1;
   double   changePctD1;
   double   spread;
   double   corrMain;    // Correlation on main TF
   double   corrD1;      // Correlation on D1
   double   corrW1;      // Correlation on W1
   bool     ok;
};

//+------------------------------------------------------------------+
//| Global vars                                                       |
//+------------------------------------------------------------------+
SymData   g_sym[];
int       g_count = 0;
datetime  g_lastUpdate = 0;
string    PREFIX = "CD2_";
int       g_dragX = 20, g_dragY = 30;   // dashboard position
bool      g_dragging = false;
int       g_dragOffX = 0, g_dragOffY = 0;
bool      g_minimized = false;
bool      g_switchLocked = true;         // TRUE = protegido, FALSE = modo troca ativo
int       g_lockMsgTick = 0;             // para limpar mensagem de trava
string    g_mainSymbol;                  // SEM sufixo (ex: "EURUSD")
string    g_mainSymbolMT;               // COM sufixo (ex: "EURUSD-T")
int       g_mainDigits;
double    g_mainBid, g_mainAsk;

//+------------------------------------------------------------------+
//| Helper: resolve full MT5 name (com sufixo se necessario)         |
//+------------------------------------------------------------------+
string ResolveSymbol(string baseName) {
   // Normalizar: remover sufixo se veio com ele
   string clean = baseName;
   int sufPos = StringFind(clean, SUFFIX);
   if(sufPos > 0) clean = StringSubstr(clean, 0, sufPos);
   
   // Tenta com sufixo
   string withSuf = clean + SUFFIX;
   bool exists = false;
   if(SymbolExist(withSuf, exists)) return withSuf;
   
   // Tenta sem sufixo
   if(SymbolExist(clean, exists)) return clean;
   
   // Nao encontrou
   return "";
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit() {
   // Validate main symbol - aceita com ou sem -T
   g_mainSymbol = InpMainSymbol;
   // Remove sufixo se o usuario digitou com ele
   int sufPos = StringFind(g_mainSymbol, SUFFIX);
   if(sufPos > 0) g_mainSymbol = StringSubstr(g_mainSymbol, 0, sufPos);
   
   string resolved = ResolveSymbol(g_mainSymbol);
   if(resolved == "") {
      Print("[ERRO] Simbolo principal '" + g_mainSymbol + "' (ou '" + g_mainSymbol + SUFFIX + "') nao encontrado!");
      return INIT_PARAMETERS_INCORRECT;
   }
   g_mainSymbolMT = resolved;
   SymbolSelect(g_mainSymbolMT, true);
   
   Print("[OK] Simbolo principal: " + g_mainSymbolMT + " (base: " + g_mainSymbol + ")");
   
   // Set initial state
   g_dragX = 20;
   g_dragY = 30;
   g_minimized = InpAutoMinimize;
   g_switchLocked = true;  // Comeca travado!
   g_lockMsgTick = 0;
   
   // Build symbol list
   BuildSymbolList();
   
   // Chart setup
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(0, CHART_FOREGROUND, true);
   ChartSetInteger(0, CHART_BRING_TO_TOP, true);
   
   EventSetTimer(1);
   Print("[OK] Dashboard Correlacoes v2.1 iniciado com " + IntegerToString(g_count) + " simbolos");
   Print("[OK] Modo SWITCH TRAVADO (clique em TRAVADO/LIVRE para alternar)");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   EraseAll();
}

//+------------------------------------------------------------------+
//| Timer event                                                       |
//+------------------------------------------------------------------+
void OnTimer() {
   UpdateAll();
   
   // Limpar mensagem de trava apos alguns segundos
   if(g_lockMsgTick > 0) {
      g_lockMsgTick--;
      if(g_lockMsgTick == 0) Comment("");
   }
}

//+------------------------------------------------------------------+
//| Tick event                                                        |
//+------------------------------------------------------------------+
void OnTick() {
   datetime now = TimeCurrent();
   if(now - g_lastUpdate < InpInterval && g_lastUpdate > 0) return;
   g_lastUpdate = now;
   UpdateAll();
}

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {
                  
   // MOUSE MOVE (para arrastar o painel) - apenas se estiver arrastando
   if(id == CHARTEVENT_MOUSE_MOVE) {
      if(g_dragging) {
         int mx = (int)lparam;
         int my = (int)dparam;
         if(mx > 0 && my > 0) {
            g_dragX = mx - g_dragOffX;
            g_dragY = my - g_dragOffY;
            DrawAll();
         }
      }
   }
   
   // MOUSE DOWN - apenas para INICIAR o drag no titulo
   if(id == CHARTEVENT_CLICK && !g_minimized) {
      int mx = (int)lparam;
      int my = (int)dparam;
      
      // So inicia drag se clicou no cabecalho (faixa do titulo, 28px)
      int headerH = 28;
      if(mx >= g_dragX && mx <= g_dragX + 250 &&
         my >= g_dragY && my <= g_dragY + headerH) {
         g_dragging = true;
         g_dragOffX = mx - g_dragX;
         g_dragOffY = my - g_dragY;
      }
   }
   
   // OBJECT CLICK - usado apenas para botoes e linhas de simbolo
   if(id == CHARTEVENT_OBJECT_CLICK) {
      // Botao minimizar/expandir
      if(sparam == PREFIX + "BTN_MIN") {
         g_minimized = !g_minimized;
         DrawAll();
      }
      // Botao de trava (TRAVADO/LIVRE)
      else if(sparam == PREFIX + "BTN_LOCK") {
         g_switchLocked = !g_switchLocked;
         DrawAll();
         if(g_switchLocked)
            Print("[LOCK] Troca de simbolo TRAVADA");
         else
            Print("[LOCK] Troca de simbolo LIBERADA - clique nas linhas para trocar o grafico");
      }
      // Clique em linha de simbolo (OBJ_EDIT)
      else if(StringFind(sparam, PREFIX + "ROW_") == 0) {
         string idStr = StringSubstr(sparam, StringLen(PREFIX) + 4);
         int idx = (int)StringToInteger(idStr);
         if(idx >= 0 && idx < g_count && g_sym[idx].ok) {
            if(!g_switchLocked) {
               SwitchChart(g_sym[idx].nameRaw);
            } else {
               // Mostra aviso de trava
               Comment(">> SWITCH TRAVADO! Clique no botao TRAVADO/LIVRE para liberar <<");
               g_lockMsgTick = 5; // limpa apos 5 segundos
               Print("[AVISO] Tentativa de troca com switch travado");
            }
         }
      }
   }
   
   // CHART CHANGE (resize)
   if(id == CHARTEVENT_CHART_CHANGE) {
      DrawAll();
   }
}

//+------------------------------------------------------------------+
//| Build list of symbols to monitor                                 |
//+------------------------------------------------------------------+
void BuildSymbolList() {
   g_count = 0;
   ArrayResize(g_sym, 0);
   
   // Nucleo de pares correlacionados
   // So adiciona se for diferente do simbolo principal
   if(g_mainSymbol != "EURUSD") AddSym("EURUSD", "EUR/USD", "Direta");
   if(g_mainSymbol != "GBPUSD") AddSym("GBPUSD", "GBP/USD", "Direta");
   if(g_mainSymbol != "AUDUSD") AddSym("AUDUSD", "AUD/USD", "Direta");
   if(g_mainSymbol != "NZDUSD") AddSym("NZDUSD", "NZD/USD", "Direta");
   if(g_mainSymbol != "EURJPY") AddSym("EURJPY", "EUR/JPY", "Direta");
   if(g_mainSymbol != "EURGBP") AddSym("EURGBP", "EUR/GBP", "Direta");
   if(g_mainSymbol != "USDCAD") AddSym("USDCAD", "USD/CAD", "Inversa");
   if(g_mainSymbol != "USDCHF") AddSym("USDCHF", "USD/CHF", "Inversa");
   if(g_mainSymbol != "USDJPY") AddSym("USDJPY", "USD/JPY", "Inversa");
   
   // Simbolos extras do input
   if(StringLen(InpExtraSymbols) > 0) {
      string extras = InpExtraSymbols;
      StringReplace(extras, " ", "");
      string parts[];
      int n = StringSplit(extras, ',', parts);
      for(int i = 0; i < n; i++) {
         string s = parts[i];
         if(StringLen(s) == 0 || s == g_mainSymbol) continue;
         
         string grp = "Extra";
         if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) grp = "Metais";
         else if(StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0) grp = "Metais";
         else if(StringFind(s, "500") >= 0 || StringFind(s, "US500") >= 0 || StringFind(s, "SPX") >= 0) grp = "Indices";
         else if(StringFind(s, "100") >= 0 || StringFind(s, "NAS") >= 0 || StringFind(s, "US100") >= 0) grp = "Indices";
         else if(StringFind(s, "DXY") >= 0 || StringFind(s, "USDX") >= 0 || StringFind(s, "indx") >= 0) grp = "Indices";
         else if(StringFind(s, "BTC") >= 0 || StringFind(s, "ETH") >= 0) grp = "Crypto";
         AddSym(s, s, grp);
      }
   }
   
   Print("[INFO] Total de simbolos na lista: " + IntegerToString(g_count));
}

//+------------------------------------------------------------------+
//| Add a symbol to the list                                         |
//+------------------------------------------------------------------+
void AddSym(string symBase, string label, string group) {
   if(symBase == g_mainSymbol) return;
   
   // Resolver nome MT5 (com/sem -T)
   string symMT = ResolveSymbol(symBase);
   if(symMT == "") {
      Print("[AVISO] Simbolo '" + symBase + "' nao encontrado (tentado: '" + symBase + SUFFIX + "'), pulando");
      return;
   }
   
   // Verificar se jah existe na lista
   for(int i = 0; i < g_count; i++) {
      if(g_sym[i].name == symMT) return;
   }
   
   SymbolSelect(symMT, true);
   
   int n = g_count++;
   ArrayResize(g_sym, g_count);
   g_sym[n].name     = symMT;
   g_sym[n].nameRaw  = symBase;
   g_sym[n].label    = label;
   g_sym[n].group    = group;
   g_sym[n].price    = 0;
   g_sym[n].changeD1 = 0;
   g_sym[n].changePctD1 = 0;
   g_sym[n].spread   = 0;
   g_sym[n].corrMain = 0;
   g_sym[n].corrD1   = 0;
   g_sym[n].corrW1   = 0;
   g_sym[n].ok = false;
}

//+------------------------------------------------------------------+
//| Update all symbol data                                           |
//+------------------------------------------------------------------+
void UpdateAll() {
   // Update main symbol
   g_mainBid = SymbolInfoDouble(g_mainSymbolMT, SYMBOL_BID);
   g_mainAsk = SymbolInfoDouble(g_mainSymbolMT, SYMBOL_ASK);
   g_mainDigits = (int)SymbolInfoInteger(g_mainSymbolMT, SYMBOL_DIGITS);
   
   if(g_mainBid <= 0 || g_mainAsk <= 0) return;
   
   // Pre-load main price series
   double mainRet[], mainRetD1[], mainRetW1[];
   int nMain = LoadReturns(g_mainSymbolMT, InpTF, InpBars, mainRet);
   int nMainD1 = 0, nMainW1 = 0;
   if(InpShowD1) nMainD1 = LoadReturns(g_mainSymbolMT, PERIOD_D1, InpBars, mainRetD1);
   if(InpShowW1) nMainW1 = LoadReturns(g_mainSymbolMT, PERIOD_W1, InpBars, mainRetW1);
   
   if(nMain < 10) return;
   
   // Update each symbol
   for(int i = 0; i < g_count; i++) {
      UpdateOne(i, mainRet, nMain, mainRetD1, nMainD1, mainRetW1, nMainW1);
   }
   
   // Alerts
   if(InpAlerts) CheckAlerts();
   
   // Redraw
   DrawAll();
}

//+------------------------------------------------------------------+
//| Update a single symbol                                           |
//+------------------------------------------------------------------+
void UpdateOne(int idx, double &mainRet[], int nMain,
               double &mainRetD1[], int nMainD1,
               double &mainRetW1[], int nMainW1) {
   
   string sym = g_sym[idx].name;
   
   // Price
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) { g_sym[idx].ok = false; return; }
   
   g_sym[idx].price  = (bid + ask) / 2.0;
   g_sym[idx].spread = (ask - bid) / SymbolInfoDouble(sym, SYMBOL_POINT);
   
   // Daily change
   MqlRates rD1[2];
   if(CopyRates(sym, PERIOD_D1, 0, 2, rD1) >= 2) {
      double open = rD1[1].close;
      g_sym[idx].changeD1   = g_sym[idx].price - open;
      g_sym[idx].changePctD1 = (open > 0) ? (g_sym[idx].changeD1 / open) * 100.0 : 0;
   }
   
   // Correlations
   double ret[];
   int n = LoadReturns(sym, InpTF, InpBars, ret);
   if(n >= 10 && nMain >= 10) {
      int m = MathMin(n, nMain);
      g_sym[idx].corrMain = PearsonCorr(mainRet, ret, m);
   }
   
   if(InpShowD1 && nMainD1 >= 10) {
      double retD1[];
      int n2 = LoadReturns(sym, PERIOD_D1, InpBars, retD1);
      if(n2 >= 10) {
         int m2 = MathMin(n2, nMainD1);
         g_sym[idx].corrD1 = PearsonCorr(mainRetD1, retD1, m2);
      }
   }
   
   if(InpShowW1 && nMainW1 >= 10) {
      double retW1[];
      int n3 = LoadReturns(sym, PERIOD_W1, InpBars, retW1);
      if(n3 >= 10) {
         int m3 = MathMin(n3, nMainW1);
         g_sym[idx].corrW1 = PearsonCorr(mainRetW1, retW1, m3);
      }
   }
   
   g_sym[idx].ok = true;
}

//+------------------------------------------------------------------+
//| Load returns series from symbol/timeframe                        |
//+------------------------------------------------------------------+
int LoadReturns(string sym, ENUM_TIMEFRAMES tf, int bars, double &ret[]) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int c = CopyRates(sym, tf, 0, bars + 1, rates);
   if(c < 11) return 0;
   
   int n = c - 1;
   ArrayResize(ret, n);
   for(int i = 0; i < n; i++) {
      double prev = rates[i + 1].close;
      if(prev > 0)
         ret[i] = (rates[i].close - prev) / prev;
      else
         ret[i] = 0;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Pearson Correlation Coefficient                                  |
//+------------------------------------------------------------------+
double PearsonCorr(double &x[], double &y[], int n) {
   if(n < 3) return 0;
   
   double sx = 0, sy = 0;
   for(int i = 0; i < n; i++) { sx += x[i]; sy += y[i]; }
   double mx = sx / n, my = sy / n;
   
   double cov = 0, vx = 0, vy = 0;
   for(int i = 0; i < n; i++) {
      double dx = x[i] - mx, dy = y[i] - my;
      cov += dx * dy;
      vx  += dx * dx;
      vy  += dy * dy;
   }
   
   if(vx <= 0 || vy <= 0) return 0;
   return cov / MathSqrt(vx * vy);
}

//+------------------------------------------------------------------+
//| Check correlation alerts                                         |
//+------------------------------------------------------------------+
void CheckAlerts() {
   for(int i = 0; i < g_count; i++) {
      if(!g_sym[i].ok) continue;
      if(g_sym[i].corrMain >= InpAlertHigh)
         Alert("[ALERTA] ", g_sym[i].label, " correlacao alta: +", DoubleToString(g_sym[i].corrMain, 3));
      if(g_sym[i].corrMain <= InpAlertLow)
         Alert("[ALERTA] ", g_sym[i].label, " correlacao baixa: ", DoubleToString(g_sym[i].corrMain, 3));
   }
}

//+------------------------------------------------------------------+
//| Main drawing routine                                             |
//+------------------------------------------------------------------+
void DrawAll() {
   EraseAll();
   if(g_minimized) {
      DrawMinimizedBar();
      return;
   }
   DrawFullDashboard();
}

//+------------------------------------------------------------------+
//| Draw minimized bar                                               |
//+------------------------------------------------------------------+
void DrawMinimizedBar() {
   int x = g_dragX, y = g_dragY;
   int w = 230, h = 26;
   
   CreateRect("MIN_BG", x, y, w, h, InpBgColor, clrGray);
   CreateLabel("MIN_TXT", x + 8, y + 4, 
               "[+] Correlacoes v2.1", clrGold, InpFontSize + 2, true);
   CreateLabel("MIN_HINT", x + w - 70, y + 4, 
               "clique = expandir", clrLightGray, InpFontSize - 1, false);
}

//+------------------------------------------------------------------+
//| Draw full dashboard                                              |
//+------------------------------------------------------------------+
void DrawFullDashboard() {
   int cols = 7;
   if(InpShowD1) cols = 8;
   if(InpShowW1) cols = InpShowD1 ? 9 : 8;
   
   int cw = InpColWidth;
   int rh = InpRowHeight;
   int pd = 4;
   
   int tw = cols * cw + pd * 2 + 50;
   int th = 28 + 26 + rh + 5 + g_count * (rh - 2) + 54;
   
   // Auto-fit ao chart
   int chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(tw > chartW - 20) { 
      cw = MathMax(60, (chartW - 70) / cols); 
      tw = cols * cw + pd * 2 + 50; 
   }
   if(g_dragY + th > chartH - 10) g_dragY = MathMax(5, chartH - th - 10);
   if(g_dragX + tw > chartW - 10) g_dragX = MathMax(5, chartW - tw - 10);
   
   int x = g_dragX, y = g_dragY;
   
   // Fundo principal
   CreateRect("BG", x - 2, y - 2, tw + 4, th + 4, InpBgColor, clrDarkGray);
   CreateRect("BG_INNER", x, y, tw, th, InpBgColor, clrDimGray);
   
   // ================================================================
   // BOTOES no cabecalho
   // ================================================================
   int btnY = y + 4;
   int btnS = 18;
   
   // Botao minimizar [-]
   CreateClickButton("BTN_MIN", x + tw - btnS - 4, btnY, btnS, btnS, 
                     "-", clrOrange, InpFontSize + 1);
   
   // Botao TRAVA (TRAVADO / LIVRE)
   string lockLabel = g_switchLocked ? "TRAVADO" : "LIVRE";
   color lockColor = g_switchLocked ? clrRed : clrLime;
   int lockW = 55;
   CreateClickButton("BTN_LOCK", x + tw - lockW - 24, btnY, lockW, btnS, 
                     lockLabel, lockColor, InpFontSize);
   
   // ================================================================
   // TITULO
   // ================================================================
   string title = "CORRELACOES: " + g_mainSymbol;
   string tfName = TimeframeToString(InpTF);
   if(InpShowD1)  title += " | " + tfName + "/D1";
   if(InpShowW1)  title += "/W1";
   CreateLabel("TITLE", x + pd + 5, y + 6, title, clrGold, InpFontSize + 3, true);
   
   // ================================================================
   // CABECALHO DAS COLUNAS
   // ================================================================
   int hx = x + pd;
   int hy = y + 28;
   
   int hdrCols = 0;
   string hdrs[10];
   hdrs[hdrCols++] = "Ativo";
   hdrs[hdrCols++] = "Preco";
   hdrs[hdrCols++] = "Var.D1";
   hdrs[hdrCols++] = "Spread";
   hdrs[hdrCols++] = tfName;
   if(InpShowD1)  hdrs[hdrCols++] = "D1";
   if(InpShowW1)  hdrs[hdrCols++] = "W1";
   hdrs[hdrCols++] = "Sinal";
   
   for(int c = 0; c < hdrCols; c++) {
      CreateLabel("H" + IntegerToString(c), hx + c * cw, hy, 
                  hdrs[c], clrWhite, InpFontSize, true);
   }
   
   // Separador
   int sy1 = hy + rh - 4;
   CreateRect("SEP", x + pd, sy1, tw - pd * 2 - 50, 1, clrDimGray, clrDimGray);
   
   // ================================================================
   // LINHA DO SIMBOLO PRINCIPAL
   // ================================================================
   int rowY = sy1 + 6;
   DrawMainRow(rowY, hdrCols, cw, rh, pd, x);
   rowY += rh + 1;
   
   // Separador
   CreateRect("SEP2", x + pd, rowY, tw - pd * 2 - 50, 1, clrDimGray, clrDimGray);
   rowY += 4;
   
   // ================================================================
   // LINHAS DOS SIMBOLOS
   // ================================================================
   for(int i = 0; i < g_count; i++) {
      DrawDataRow(i, rowY, hdrCols, cw, rh, pd, x, cols);
      rowY += rh - 2;
   }
   
   rowY += 6;
   
   // ================================================================
   // LEGENDA E RODAPE
   // ================================================================
   string statusLock = g_switchLocked ? "TRAVADO" : "LIVRE";
   color statusColor = g_switchLocked ? clrRed : clrLime;
   
   CreateLabel("LOCK_STATUS", x + pd, rowY, 
               "Switch: " + statusLock + " (clique p/ alternar)", 
               statusColor, InpFontSize - 1, false);
   
   CreateLabel("LEG", x + pd, rowY + 14, 
               "Corr: >|0.7| Forte | >|0.4| Moderada | <|0.3| Fraca", 
               clrLightGray, InpFontSize - 1, false);
   
   CreateLabel("TS", x + pd + 5, rowY + 28, 
               "Atualizado: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + 
               " | " + IntegerToString(g_count) + " simbolos | -T automatico", 
               clrGray, InpFontSize - 2, false);
               
   CreateLabel("HINT", x + pd + 5, rowY + 40, 
               "Dica: Digite o nome SEM o -T (ex: EURUSD). Simbolos com -T sao resolvidos automaticamente.", 
               clrDarkGray, InpFontSize - 3, false);
}

//+------------------------------------------------------------------+
//| Draw the main symbol row                                         |
//+------------------------------------------------------------------+
void DrawMainRow(int &y, int cols, int cw, int rh, int pd, int x) {
   int hx = x + pd;
   int col = 0;
   double price = (g_mainBid + g_mainAsk) / 2.0;
   
   CreateLabel("M_A", hx + col * cw, y + 2, 
               ">> " + g_mainSymbol, clrGold, InpFontSize + 1, true); col++;
   
   int dig = GetDigits(g_mainSymbolMT);
   CreateLabel("M_P", hx + col * cw, y + 2, 
               DoubleToString(price, dig), clrWhite, InpFontSize, false); col++;
   
   MqlRates mr[2];
   double chg = 0, chgPct = 0;
   if(CopyRates(g_mainSymbolMT, PERIOD_D1, 0, 2, mr) >= 2) {
      chg = price - mr[1].close;
      chgPct = (mr[1].close > 0) ? (chg / mr[1].close) * 100.0 : 0;
   }
   color cCol = (chg >= 0) ? clrLimeGreen : clrRed;
   double ptSz = SymbolInfoDouble(g_mainSymbolMT, SYMBOL_POINT);
   string chgStr = StringFormat("%+.0f (%.2f%%)", chg / ptSz, chgPct);
   CreateLabel("M_V", hx + col * cw, y + 2, chgStr, cCol, InpFontSize, false); col++;
   
   double spreadPts = (g_mainAsk - g_mainBid) / ptSz;
   CreateLabel("M_S", hx + col * cw, y + 2, DoubleToString(spreadPts, 0), clrCyan, InpFontSize, false); col++;
   
   CreateLabel("M_C0", hx + col * cw, y + 2, "+1.000", clrLime, InpFontSize + 1, true); col++;
   
   if(InpShowD1) {
      CreateLabel("M_C1", hx + col * cw, y + 2, "+1.000", clrLime, InpFontSize + 1, true); col++;
   }
   if(InpShowW1) {
      CreateLabel("M_C2", hx + col * cw, y + 2, "+1.000", clrLime, InpFontSize + 1, true); col++;
   }
   
   CreateLabel("M_SIG", hx + col * cw, y + 2, "REF", clrLime, InpFontSize, true);
}

//+------------------------------------------------------------------+
//| Draw a data row for a symbol                                     |
//+------------------------------------------------------------------+
void DrawDataRow(int idx, int y, int cols, int cw, int rh, int pd, int x, int totalCols) {
   int hx = x + pd;
   int col = 0;
   int rowW = totalCols * cw;
   
   // OBJ_EDIT invisivel sobreposta para capturar clique
   string rowBtn = "ROW_" + IntegerToString(idx);
   if(ObjectFind(0, PREFIX + rowBtn) < 0) {
      ObjectCreate(0, PREFIX + rowBtn, OBJ_EDIT, 0, 0, 0);
   }
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_XDISTANCE, hx);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_XSIZE, rowW);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_YSIZE, rh);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_BGCOLOR, clrNONE);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_BORDER_COLOR, clrNONE);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_CORNER, 0);
   ObjectSetString(0, PREFIX + rowBtn, OBJPROP_TEXT, "");
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_READONLY, true);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_HIDDEN, false);  // visivel para clique
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_BACK, true);
   ObjectSetInteger(0, PREFIX + rowBtn, OBJPROP_FONTSIZE, 1);
   
   if(!g_sym[idx].ok) {
      CreateLabel("A_" + IntegerToString(idx), hx + 2, y + 2, 
                  g_sym[idx].label + " (offline)", clrGray, InpFontSize, false);
      return;
   }
   
   // ---- Coluna 0: Nome do ativo ----
   color groupCol = GetGroupColor(g_sym[idx].group);
   CreateLabel("A_" + IntegerToString(idx), hx + col * cw + 2, y + 2, 
               g_sym[idx].label, groupCol, InpFontSize, false); col++;
   
   // ---- Coluna 1: Preco ----
   int dig = GetDigits(g_sym[idx].name);
   CreateLabel("P_" + IntegerToString(idx), hx + col * cw, y + 2, 
               DoubleToString(g_sym[idx].price, dig), clrWhite, InpFontSize, false); col++;
   
   // ---- Coluna 2: Variacao diaria ----
   color chgCol = (g_sym[idx].changeD1 >= 0) ? clrLimeGreen : clrRed;
   double pt = SymbolInfoDouble(g_sym[idx].name, SYMBOL_POINT);
   string chgStr = StringFormat("%+.0f", g_sym[idx].changeD1 / pt);
   CreateLabel("V_" + IntegerToString(idx), hx + col * cw, y + 2, 
               chgStr, chgCol, InpFontSize, false); col++;
   
   // ---- Coluna 3: Spread ----
   color spreadCol = (g_sym[idx].spread < 20) ? clrLimeGreen : 
                     (g_sym[idx].spread < 50) ? clrYellow : clrRed;
   CreateLabel("SP_" + IntegerToString(idx), hx + col * cw, y + 2, 
               DoubleToString(g_sym[idx].spread, 0), spreadCol, InpFontSize, false); col++;
   
   // ---- Coluna 4: Correlacao TF principal ----
   DrawCorrCell("C0_" + IntegerToString(idx), hx + col * cw, y, cw, rh, 
                g_sym[idx].corrMain, g_sym[idx].ok); col++;
   
   // ---- Coluna 5: Correlacao D1 ----
   if(InpShowD1) {
      DrawCorrCell("C1_" + IntegerToString(idx), hx + col * cw, y, cw, rh, 
                   g_sym[idx].corrD1, g_sym[idx].ok); col++;
   }
   
   // ---- Coluna 6: Correlacao W1 ----
   if(InpShowW1) {
      DrawCorrCell("C2_" + IntegerToString(idx), hx + col * cw, y, cw, rh, 
                   g_sym[idx].corrW1, g_sym[idx].ok); col++;
   }
   
   // ---- Ultima coluna: Sinal ----
   string sig = "---";
   color sigCol = clrGray;
   if(g_sym[idx].ok && g_sym[idx].corrMain != 0) {
      double ac = MathAbs(g_sym[idx].corrMain);
      if(ac > 0.7) {
         sig = (g_sym[idx].corrMain > 0) ? "↑ FORTE" : "↓ FORTE";
         sigCol = (g_sym[idx].corrMain > 0) ? clrLime : clrRed;
      } else if(ac > 0.4) {
         sig = (g_sym[idx].corrMain > 0) ? "↑ moder." : "↓ moder.";
         sigCol = (g_sym[idx].corrMain > 0) ? clrPaleGreen : clrCoral;
      } else {
         sig = "→ fraco";
         sigCol = clrYellow;
      }
   }
   CreateLabel("S_" + IntegerToString(idx), hx + col * cw, y + 2, sig, sigCol, InpFontSize, true);
}

//+------------------------------------------------------------------+
//| Draw a correlation cell with heatmap background                  |
//+------------------------------------------------------------------+
void DrawCorrCell(string objName, int x, int y, int w, int h, double corr, bool ok) {
   if(!ok) {
      CreateLabel(objName, x + 2, y + 2, "---", clrGray, InpFontSize, false);
      return;
   }
   
   color bg = GetHeatmapColor(corr);
   
   if(w > 4 && h > 2) {
      CreateRect(objName + "_BG", x + 1, y + 1, w - 2, h - 2, bg, bg);
   }
   
   color txtCol = (MathAbs(corr) > 0.5) ? clrWhite : clrBlack;
   string corrStr = StringFormat("%+.3f", corr);
   CreateLabel(objName, x + w / 2 - 25, y + 2, corrStr, txtCol, InpFontSize + 1, true);
   
   string arrow = (corr > 0) ? "▲" : "▼";
   color arrCol = (corr > 0) ? clrLime : clrRed;
   CreateLabel(objName + "_ARR", x + w - 18, y + 2, arrow, arrCol, InpFontSize, true);
}

//+------------------------------------------------------------------+
//| Get heatmap background color from correlation value              |
//+------------------------------------------------------------------+
color GetHeatmapColor(double corr) {
   double ac = MathAbs(corr);
   if(ac > 0.85) return corr > 0 ? clrDarkGreen : clrMaroon;
   if(ac > 0.70) return corr > 0 ? clrGreen : clrDarkRed;
   if(ac > 0.50) return corr > 0 ? clrForestGreen : clrFireBrick;
   if(ac > 0.35) return corr > 0 ? clrOlive : clrSaddleBrown;
   if(ac > 0.20) return corr > 0 ? clrDarkOliveGreen : clrChocolate;
   return clrDimGray;
}

//+------------------------------------------------------------------+
//| Get group color for asset label                                  |
//+------------------------------------------------------------------+
color GetGroupColor(string grp) {
   if(grp == "Principal")  return clrGold;
   if(grp == "Direta")     return clrLimeGreen;
   if(grp == "Inversa")    return clrCoral;
   if(grp == "Metais")     return clrOrange;
   if(grp == "Indices")    return clrCyan;
   if(grp == "Crypto")     return clrMagenta;
   return clrLightGray;
}

//+------------------------------------------------------------------+
//| Switch main chart to a different symbol                          |
//+------------------------------------------------------------------+
void SwitchChart(string newSymbolBase) {
   if(newSymbolBase == g_mainSymbol) return;
   
   // Resolver nome MT5 do novo simbolo
   string newMT = ResolveSymbol(newSymbolBase);
   if(newMT == "") {
      Print("[ERRO] Nao foi possivel resolver simbolo: " + newSymbolBase);
      return;
   }
   
   Print("[SWITCH] Trocando grafico para: " + newMT + " (base: " + newSymbolBase + ")");
   
   // Guardar simbolo antigo
   string oldMain = g_mainSymbol;
   
   // Atualizar simbolo principal
   g_mainSymbol = newSymbolBase;
   g_mainSymbolMT = newMT;
   g_mainBid = SymbolInfoDouble(g_mainSymbolMT, SYMBOL_BID);
   g_mainAsk = SymbolInfoDouble(g_mainSymbolMT, SYMBOL_ASK);
   g_mainDigits = (int)SymbolInfoInteger(g_mainSymbolMT, SYMBOL_DIGITS);
   
   SymbolSelect(g_mainSymbolMT, true);
   
   // Mudar o grafico
   ChartSetSymbolPeriod(0, g_mainSymbolMT, PERIOD_CURRENT);
   
   // Adicionar o simbolo antigo de volta na lista se nao estiver
   bool oldInList = false;
   for(int i = 0; i < g_count; i++) {
      if(g_sym[i].nameRaw == oldMain) { oldInList = true; break; }
   }
   if(!oldInList && oldMain != g_mainSymbol) {
      AddSym(oldMain, oldMain, "Direta");
   }
   
   // Atualizar dados imediatamente
   g_lastUpdate = 0; // forca update
   UpdateAll();
   
   Print("[SWITCH] Grafico alterado para " + g_mainSymbolMT);
}

//+------------------------------------------------------------------+
//| Create a clickable button (OBJ_EDIT readonly)                    |
//+------------------------------------------------------------------+
void CreateClickButton(string name, int x, int y, int w, int h, string txt, color cl, int sz) {
   string objName = PREFIX + name;
   
   // Criar o fundo do botao (retangulo)
   string bgName = objName + "_BG";
   if(ObjectFind(0, bgName) < 0) {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, clrDarkGray);
   ObjectSetInteger(0, bgName, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_FILL, true);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, 0);
   
   // OBJ_EDIT clicavel por cima
   if(ObjectFind(0, objName) < 0) {
      ObjectCreate(0, objName, OBJ_EDIT, 0, 0, 0);
   }
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, objName, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, objName, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clrNONE);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clrNONE);
   ObjectSetInteger(0, objName, OBJPROP_BORDER_COLOR, clrNONE);
   ObjectSetInteger(0, objName, OBJPROP_CORNER, 0);
   ObjectSetString(0, objName, OBJPROP_TEXT, "");
   ObjectSetInteger(0, objName, OBJPROP_READONLY, true);
   ObjectSetInteger(0, objName, OBJPROP_BACK, true);
   ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 1);
   
   // Label do botao
   string lblName = name + "_LBL";
   if(ObjectFind(0, PREFIX + lblName) < 0) {
      ObjectCreate(0, PREFIX + lblName, OBJ_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, PREFIX + lblName, OBJPROP_XDISTANCE, x + 2);
   ObjectSetInteger(0, PREFIX + lblName, OBJPROP_YDISTANCE, y + 1);
   ObjectSetString(0, PREFIX + lblName, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, PREFIX + lblName, OBJPROP_COLOR, cl);
   ObjectSetInteger(0, PREFIX + lblName, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, PREFIX + lblName, OBJPROP_FONT, "Consolas Bold");
   ObjectSetInteger(0, PREFIX + lblName, OBJPROP_CORNER, 0);
}

//+------------------------------------------------------------------+
//| Create a label object                                            |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string txt, color cl, int sz, bool bold) {
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0) {
      ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, obj, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, cl);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, obj, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, 0);
}

//+------------------------------------------------------------------+
//| Create a rectangle object                                        |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color bg, color border) {
   string obj = PREFIX + name;
   if(ObjectFind(0, obj) < 0) {
      ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, border);
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, obj, OBJPROP_FILL, true);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, 0);
}

//+------------------------------------------------------------------+
//| Delete all dashboard objects                                     |
//+------------------------------------------------------------------+
void EraseAll() {
   ObjectsDeleteAll(0, PREFIX);
}

//+------------------------------------------------------------------+
//| Get appropriate decimal places for a symbol                      |
//+------------------------------------------------------------------+
int GetDigits(string sym) {
   if(StringFind(sym, "JPY") >= 0 || StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0) return 3;
   if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0) return 2;
   if(StringFind(sym, "500") >= 0 || StringFind(sym, "SPX") >= 0) return 2;
   if(StringFind(sym, "100") >= 0 || StringFind(sym, "NAS") >= 0) return 2;
   if(StringFind(sym, "DXY") >= 0 || StringFind(sym, "indx") >= 0) return 2;
   if(StringFind(sym, "BTC") >= 0 || StringFind(sym, "ETH") >= 0) return 2;
   return 5;
}

//+------------------------------------------------------------------+
//| Convert timeframe to readable string                             |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf) {
   switch(tf) {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return EnumToString(tf);
   }
}

//+------------------------------------------------------------------+
//| Tester function                                                  |
//+------------------------------------------------------------------+
double OnTester() { return 0; }
//+------------------------------------------------------------------+
