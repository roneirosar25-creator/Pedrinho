//+------------------------------------------------------------------+
//| INSTITUTIONAL_PARAMETERS.mqh                                     |
//| TRIVIUM369 © 2026 - Stub criado por Goose                        |
//+------------------------------------------------------------------+
#property strict
struct AccountProfile {
    string profile_name;
};
AccountProfile GetAccountProfile(double balance) {
    AccountProfile p;
    if(balance < 1000) p.profile_name = "Micro";
    else if(balance < 10000) p.profile_name = "Mini";
    else p.profile_name = "Standard";
    return p;
}
