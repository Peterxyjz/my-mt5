//+------------------------------------------------------------------+
//|                                                XauAssistant.mq5   |
//|           XAUUSD Trade Assistant - Signal + Position Tracking      |
//+------------------------------------------------------------------+
#property copyright "XauAssistant"
#property version   "3.50"
#property description "All-in-one XAUUSD Assistant"
#property description "1. EMA Trend Filter (H4) + Key Level (H1)"
#property description "2. Candle pattern detection (M15 entry, H1 confirm)"
#property description "3. Position advisory (hold/close/DCA/SL)"
#property description "4. Position & order tracking"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input string   InpBotToken          = "";              // Telegram Bot Token
input string   InpChatId            = "";              // Telegram Chat/Channel ID
input string   InpTrackingName      = "TRACKING";      // Account Tracking Name
input string   InpSignalName        = "SIGNAL";        // Signal Alert Name
input int      InpCheckInterval     = 5;               // Check interval (seconds)
input int      InpCooldownMinutes   = 15;              // Signal alert cooldown (minutes)
input double   InpStrongBodyRatio   = 0.70;            // Marubozu body ratio (0.70 = 70%)
input double   InpStrongMovePercent = 0.15;            // Strong move threshold (%)
input double   InpBigLossPercent    = 2.0;             // Big loss threshold (% balance) for cut loss alert
input int      InpEmaFast           = 50;              // EMA Fast period (H4)
input int      InpEmaSlow           = 200;             // EMA Slow period (H4)
input int      InpSwingLookback     = 50;              // Swing High/Low lookback bars (H1)
input double   InpKeyLevelDistance  = 5.0;             // Max distance to key level (points)
input int      InpMaxDCA            = 2;               // Max DCA times (0=disable)
input double   InpDCALotSize        = 0.01;            // DCA lot size
input int      InpAdvisoryCooldown  = 60;              // Position advisory cooldown (minutes)

//+------------------------------------------------------------------+
//| ENUMS                                                              |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_TYPE
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
};

enum ENUM_PATTERN
{
   PATTERN_NONE = 0,
   PATTERN_BULLISH_ENGULFING,
   PATTERN_BEARISH_ENGULFING,
   PATTERN_HAMMER,
   PATTERN_SHOOTING_STAR,
   PATTERN_BULLISH_PIN_BAR,
   PATTERN_BEARISH_PIN_BAR,
   PATTERN_BULLISH_MARUBOZU,
   PATTERN_BEARISH_MARUBOZU
};

enum ENUM_TREND
{
   TREND_UP   = 1,
   TREND_DOWN = 2,
   TREND_NONE = 0
};

//+------------------------------------------------------------------+
//| STRUCTS                                                            |
//+------------------------------------------------------------------+
struct PatternResult
{
   ENUM_PATTERN     pattern;
   ENUM_SIGNAL_TYPE signal;
   int              strength;    // 1-5
   string           name;
};

struct PositionState
{
   ulong    ticket;
   ulong    positionId;
   string   symbol;
   string   type;
   double   volume;
   double   openPrice;
   double   sl;
   double   tp;
   double   profit;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
// Signal detection
datetime g_lastAlertTime_M15 = 0;
datetime g_lastBarTime_M15   = 0;
datetime g_lastBarTime_H1    = 0;

// EMA handles
int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;

// Position tracking
PositionState g_positions[];
int g_posCount = 0;

// Position advisory
datetime g_lastAdvisoryTime = 0;
datetime g_lastBarTime_H1_Adv = 0;

//+------------------------------------------------------------------+
//| TELEGRAM FUNCTIONS                                                 |
//+------------------------------------------------------------------+
string UrlEncode(string text)
{
   string result = "";
   uchar bytes[];
   int len = StringToCharArray(text, bytes, 0, -1, CP_UTF8);
   for(int i = 0; i < len - 1; i++)
   {
      uchar c = bytes[i];
      if((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~')
         result += CharToString(c);
      else if(c == ' ')
         result += "+";
      else
         result += StringFormat("%%%02X", c);
   }
   return result;
}

bool SendTelegram(string message)
{
   string url = "https://api.telegram.org/bot" + InpBotToken + "/sendMessage";
   string postData = "chat_id=" + InpChatId + "&text=" + UrlEncode(message) + "&parse_mode=HTML";

   char data[], result[];
   string resultHeaders;
   StringToCharArray(postData, data, 0, StringLen(postData), CP_UTF8);
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";

   int res = WebRequest("POST", url, headers, 5000, data, result, resultHeaders);
   if(res == -1)
   {
      Print("Telegram Error: ", GetLastError(), " - Add https://api.telegram.org to Expert Advisors Allow WebRequest");
      return false;
   }

   string response = CharArrayToString(result);
   if(StringFind(response, "\"ok\":true") >= 0)
   {
      Print("Telegram: Message sent!");
      return true;
   }
   Print("Telegram Error: ", response);
   return false;
}

//+------------------------------------------------------------------+
//| HELPER FUNCTIONS                                                   |
//+------------------------------------------------------------------+
string FormatMoney(double value)
{
   if(value >= 0)
      return "+" + DoubleToString(value, 2) + "$";
   else
      return DoubleToString(value, 2) + "$";
}

string FormatPercent(double value)
{
   if(value >= 0)
      return "+" + DoubleToString(value, 2) + "%";
   else
      return DoubleToString(value, 2) + "%";
}

string GetCloseReason(ENUM_DEAL_REASON reason)
{
   switch(reason)
   {
      case DEAL_REASON_SL:      return "STOP LOSS";
      case DEAL_REASON_TP:      return "TARGET PROFIT";
      case DEAL_REASON_CLIENT:  return "MANUAL CLOSE";
      case DEAL_REASON_EXPERT:  return "EA CLOSE";
      default:                  return "OTHER";
   }
}

string GetStrengthBar(int strength)
{
   string filled = "";
   string empty  = "";
   for(int i = 0; i < strength; i++) filled += "🟩";
   for(int i = strength; i < 5; i++) empty  += "⬜";
   return filled + empty;
}

string Line()
{
   return "━━━━━━━━━━━━━━━━━━━━\n";
}

//+------------------------------------------------------------------+
//| TREND DETECTION - EMA on H4                                        |
//+------------------------------------------------------------------+
ENUM_TREND GetH4Trend()
{
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);

   if(CopyBuffer(g_emaFastHandle, 0, 0, 1, emaFast) <= 0) return TREND_NONE;
   if(CopyBuffer(g_emaSlowHandle, 0, 0, 1, emaSlow) <= 0) return TREND_NONE;

   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   if(price > emaFast[0] && emaFast[0] > emaSlow[0])
      return TREND_UP;
   if(price < emaFast[0] && emaFast[0] < emaSlow[0])
      return TREND_DOWN;

   return TREND_NONE;
}

string GetTrendName(ENUM_TREND trend)
{
   switch(trend)
   {
      case TREND_UP:   return "UPTREND";
      case TREND_DOWN: return "DOWNTREND";
      default:         return "SIDEWAY";
   }
}

//+------------------------------------------------------------------+
//| KEY LEVEL - Swing High/Low on H1                                   |
//+------------------------------------------------------------------+
double FindNearestSupport(double price)
{
   double nearest = 0;
   double minDist = 999999;

   for(int i = 2; i < InpSwingLookback - 1; i++)
   {
      double low  = iLow(Symbol(), PERIOD_H1, i);
      double lowL = iLow(Symbol(), PERIOD_H1, i - 1);
      double lowR = iLow(Symbol(), PERIOD_H1, i + 1);
      double low2L = (i >= 3) ? iLow(Symbol(), PERIOD_H1, i - 2) : lowL;
      double low2R = (i + 2 < InpSwingLookback) ? iLow(Symbol(), PERIOD_H1, i + 2) : lowR;

      // Swing low: lower than 2 bars on each side
      if(low <= lowL && low <= lowR && low <= low2L && low <= low2R)
      {
         double dist = MathAbs(price - low);
         if(dist < minDist)
         {
            minDist = dist;
            nearest = low;
         }
      }
   }
   return nearest;
}

double FindNearestResistance(double price)
{
   double nearest = 0;
   double minDist = 999999;

   for(int i = 2; i < InpSwingLookback - 1; i++)
   {
      double high  = iHigh(Symbol(), PERIOD_H1, i);
      double highL = iHigh(Symbol(), PERIOD_H1, i - 1);
      double highR = iHigh(Symbol(), PERIOD_H1, i + 1);
      double high2L = (i >= 3) ? iHigh(Symbol(), PERIOD_H1, i - 2) : highL;
      double high2R = (i + 2 < InpSwingLookback) ? iHigh(Symbol(), PERIOD_H1, i + 2) : highR;

      // Swing high: higher than 2 bars on each side
      if(high >= highL && high >= highR && high >= high2L && high >= high2R)
      {
         double dist = MathAbs(price - high);
         if(dist < minDist)
         {
            minDist = dist;
            nearest = high;
         }
      }
   }
   return nearest;
}

bool IsNearKeyLevel(double price, double &nearestLevel, string &levelType)
{
   double support = FindNearestSupport(price);
   double resistance = FindNearestResistance(price);

   double distSupport = (support > 0) ? MathAbs(price - support) : 999999;
   double distResistance = (resistance > 0) ? MathAbs(price - resistance) : 999999;

   if(distSupport <= InpKeyLevelDistance && distSupport <= distResistance)
   {
      nearestLevel = support;
      levelType = "Support";
      return true;
   }
   if(distResistance <= InpKeyLevelDistance)
   {
      nearestLevel = resistance;
      levelType = "Resistance";
      return true;
   }
   return false;
}

// Check if Marubozu breaks out a key level
bool IsBreakoutKeyLevel(ENUM_SIGNAL_TYPE signal)
{
   double close1 = iClose(Symbol(), PERIOD_M15, 1);

   if(signal == SIGNAL_BUY)
   {
      double resistance = FindNearestResistance(close1);
      if(resistance > 0 && close1 > resistance)
         return true;
   }
   else if(signal == SIGNAL_SELL)
   {
      double support = FindNearestSupport(close1);
      if(support > 0 && close1 < support)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringLen(InpBotToken) == 0 || StringLen(InpChatId) == 0)
   {
      Print("ERROR: Please enter Bot Token and Chat ID!");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(StringFind(Symbol(), "XAU") < 0 && StringFind(Symbol(), "GOLD") < 0)
   {
      Print("WARNING: This EA is designed for XAUUSD. Current symbol: ", Symbol());
   }

   // Create EMA handles on H4
   g_emaFastHandle = iMA(Symbol(), PERIOD_H4, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(Symbol(), PERIOD_H4, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);

   if(g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create EMA indicators!");
      return INIT_FAILED;
   }

   EventSetTimer(InpCheckInterval);

   // Init bar times
   g_lastBarTime_M15 = iTime(Symbol(), PERIOD_M15, 0);
   g_lastBarTime_H1  = iTime(Symbol(), PERIOD_H1, 0);
   g_lastBarTime_H1_Adv = g_lastBarTime_H1;

   // Save current snapshots
   SaveCurrentPositions();

   // Get initial trend
   ENUM_TREND trend = GetH4Trend();

   // Startup message
   string msg = "🟢 <b>XAU ASSISTANT v3.5</b>\n";
   msg += Line();
   msg += "📊 " + Symbol() + " | " + GetTrendName(trend) + "\n";
   msg += "📈 EMA " + IntegerToString(InpEmaFast) + "/" + IntegerToString(InpEmaSlow) + " (H4)\n";
   msg += "👤 #" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\n";
   msg += "💰 " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n";
   msg += Line();
   msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
   SendTelegram(msg);

   Print("XauAssistant v3.5 initialized!");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);

   string msg = "🔴 <b>XAU ASSISTANT - STOPPED</b>\n";
   msg += Line();
   msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
   SendTelegram(msg);
}

//+------------------------------------------------------------------+
//| TRADE EVENT                                                        |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Let OnTimer handle everything with proper delay
}

//+------------------------------------------------------------------+
//| TIMER - MAIN LOGIC                                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
   //=== PART 1: SIGNAL DETECTION (M15 entry only) ===
   datetime currentBar_M15 = iTime(Symbol(), PERIOD_M15, 0);
   if(currentBar_M15 != g_lastBarTime_M15)
   {
      g_lastBarTime_M15 = currentBar_M15;
      ProcessSignal();
   }

   // Track H1 bar time (for H1 pattern confirm check)
   datetime currentBar_H1 = iTime(Symbol(), PERIOD_H1, 0);
   if(currentBar_H1 != g_lastBarTime_H1)
      g_lastBarTime_H1 = currentBar_H1;

   //=== PART 2: POSITION ADVISORY (H1) ===
   if(currentBar_H1 != g_lastBarTime_H1_Adv)
   {
      g_lastBarTime_H1_Adv = currentBar_H1;
      CheckPositionAdvisory();
   }

   //=== PART 3: POSITION TRACKING (close/open/SL-TP/partial) ===
   CheckPositionChanges();
   SaveCurrentPositions();
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  ========== PART 1: SIGNAL DETECTION ==========                    |
//|                                                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| PROCESS SIGNAL - M15 entry, H1 confirm, H4 trend filter           |
//+------------------------------------------------------------------+
void ProcessSignal()
{
   // Check cooldown
   if(TimeCurrent() - g_lastAlertTime_M15 < InpCooldownMinutes * 60)
      return;

   //--- Step 1: H4 Trend Filter
   ENUM_TREND h4Trend = GetH4Trend();
   if(h4Trend == TREND_NONE)
      return;  // Sideway/crossing = no signal

   //--- Step 2: Detect M15 pattern (entry)
   PatternResult m15Pat = DetectPattern(PERIOD_M15, 1);
   if(m15Pat.pattern == PATTERN_NONE)
      return;

   //--- Step 3: Trend filter - only trade with H4 trend
   if(h4Trend == TREND_UP && m15Pat.signal != SIGNAL_BUY)
      return;
   if(h4Trend == TREND_DOWN && m15Pat.signal != SIGNAL_SELL)
      return;

   //--- Step 4: Marubozu needs breakout key level
   if(m15Pat.pattern == PATTERN_BULLISH_MARUBOZU || m15Pat.pattern == PATTERN_BEARISH_MARUBOZU)
   {
      if(!IsBreakoutKeyLevel(m15Pat.signal))
         return;
   }

   //--- Step 5: Key level check (for non-Marubozu patterns)
   double nearestLevel = 0;
   string levelType = "";
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   bool nearKey = IsNearKeyLevel(price, nearestLevel, levelType);

   //--- Step 6: H1 confluence check
   PatternResult h1Pat = DetectPattern(PERIOD_H1, 1);
   bool h1Confirm = (h1Pat.signal == m15Pat.signal && h1Pat.signal != SIGNAL_NONE);

   //--- Step 7: Calculate final strength
   int strength = m15Pat.strength;
   if(nearKey) strength += 1;       // Near key level bonus
   if(h1Confirm) strength += 1;     // H1 confirm bonus
   if(strength > 5) strength = 5;

   // Must have at least key level OR H1 confirm (avoid weak signals)
   if(!nearKey && !h1Confirm)
   {
      // Exception: Engulfing with strength >= 4 can pass alone
      if(m15Pat.pattern != PATTERN_BULLISH_ENGULFING && m15Pat.pattern != PATTERN_BEARISH_ENGULFING)
         return;
   }

   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);

   //--- Skip signal if has open position (advisory system handles this)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == Symbol()) return;
   }

   //--- Build signal message (no position)
   string msg = BuildSignalMessage(m15Pat, price, digits, h4Trend, nearKey, nearestLevel, levelType, h1Confirm, h1Pat, strength);

   if(StringLen(msg) > 0)
   {
      SendTelegram(msg);
      g_lastAlertTime_M15 = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| DETECT CANDLE PATTERN (no Doji, Marubozu filtered separately)      |
//+------------------------------------------------------------------+
PatternResult DetectPattern(ENUM_TIMEFRAMES tf, int shift)
{
   PatternResult result;
   result.pattern  = PATTERN_NONE;
   result.signal   = SIGNAL_NONE;
   result.strength = 0;
   result.name     = "";

   double open1  = iOpen(Symbol(), tf, shift);
   double high1  = iHigh(Symbol(), tf, shift);
   double low1   = iLow(Symbol(), tf, shift);
   double close1 = iClose(Symbol(), tf, shift);

   double open2  = iOpen(Symbol(), tf, shift + 1);
   double high2  = iHigh(Symbol(), tf, shift + 1);
   double low2   = iLow(Symbol(), tf, shift + 1);
   double close2 = iClose(Symbol(), tf, shift + 1);

   if(open1 == 0 || open2 == 0) return result;

   double body1 = MathAbs(close1 - open1);
   double range1 = high1 - low1;
   double body2 = MathAbs(close2 - open2);

   if(range1 == 0) return result;

   double bodyRatio1 = body1 / range1;
   double upperWick1 = high1 - MathMax(open1, close1);
   double lowerWick1 = MathMin(open1, close1) - low1;

   bool isBullish1 = close1 > open1;
   bool isBearish1 = close1 < open1;
   bool isBullish2 = close2 > open2;
   bool isBearish2 = close2 < open2;

   double movePercent = MathAbs((close1 - open1) / open1) * 100.0;

   //--- 1. BULLISH ENGULFING
   if(isBullish1 && isBearish2 && close1 >= open2 && open1 <= close2 && body1 > body2
      && bodyRatio1 >= 0.50 && body1 >= range1 * 0.40)
   {
      result.pattern  = PATTERN_BULLISH_ENGULFING;
      result.signal   = SIGNAL_BUY;
      result.strength = 4;
      result.name     = "Bullish Engulfing";
      return result;
   }

   //--- 2. BEARISH ENGULFING
   if(isBearish1 && isBullish2 && open1 >= close2 && close1 <= open2 && body1 > body2
      && bodyRatio1 >= 0.50 && body1 >= range1 * 0.40)
   {
      result.pattern  = PATTERN_BEARISH_ENGULFING;
      result.signal   = SIGNAL_SELL;
      result.strength = 4;
      result.name     = "Bearish Engulfing";
      return result;
   }

   //--- 3. BULLISH PIN BAR
   if(lowerWick1 >= range1 * 0.65 && bodyRatio1 < 0.25 && body1 > 0)
   {
      result.pattern  = PATTERN_BULLISH_PIN_BAR;
      result.signal   = SIGNAL_BUY;
      result.strength = 4;
      result.name     = "Bullish Pin Bar";
      return result;
   }

   //--- 4. BEARISH PIN BAR
   if(upperWick1 >= range1 * 0.65 && bodyRatio1 < 0.25 && body1 > 0)
   {
      result.pattern  = PATTERN_BEARISH_PIN_BAR;
      result.signal   = SIGNAL_SELL;
      result.strength = 4;
      result.name     = "Bearish Pin Bar";
      return result;
   }

   //--- 5. HAMMER (only valid in uptrend context - filtered in ProcessSignal)
   if(isBullish1 && lowerWick1 >= body1 * 2.0 && upperWick1 <= body1 * 0.3 && body1 > 0)
   {
      result.pattern  = PATTERN_HAMMER;
      result.signal   = SIGNAL_BUY;
      result.strength = 3;
      result.name     = "Hammer";
      return result;
   }

   //--- 6. SHOOTING STAR (only valid in downtrend context - filtered in ProcessSignal)
   if(isBearish1 && upperWick1 >= body1 * 2.0 && lowerWick1 <= body1 * 0.3 && body1 > 0)
   {
      result.pattern  = PATTERN_SHOOTING_STAR;
      result.signal   = SIGNAL_SELL;
      result.strength = 3;
      result.name     = "Shooting Star";
      return result;
   }

   //--- 7. BULLISH MARUBOZU (only valid on breakout - filtered in ProcessSignal)
   if(isBullish1 && bodyRatio1 >= InpStrongBodyRatio && movePercent >= InpStrongMovePercent)
   {
      result.pattern  = PATTERN_BULLISH_MARUBOZU;
      result.signal   = SIGNAL_BUY;
      result.strength = 4;
      result.name     = "Bullish Marubozu (Breakout)";
      return result;
   }

   //--- 8. BEARISH MARUBOZU (only valid on breakout - filtered in ProcessSignal)
   if(isBearish1 && bodyRatio1 >= InpStrongBodyRatio && movePercent >= InpStrongMovePercent)
   {
      result.pattern  = PATTERN_BEARISH_MARUBOZU;
      result.signal   = SIGNAL_SELL;
      result.strength = 4;
      result.name     = "Bearish Marubozu (Breakout)";
      return result;
   }

   return result;
}

//+------------------------------------------------------------------+
//| BUILD SIGNAL MESSAGE (no position)                                 |
//+------------------------------------------------------------------+
string BuildSignalMessage(PatternResult &pat, double price, int digits,
                          ENUM_TREND h4Trend, bool nearKey, double keyLevel,
                          string levelType, bool h1Confirm, PatternResult &h1Pat,
                          int strength)
{
   string direction = (pat.signal == SIGNAL_BUY) ? "BUY" : "SELL";
   string arrow = (pat.signal == SIGNAL_BUY) ? "🟢" : "🔴";
   bool isStrong = (strength >= 4 && h1Confirm);

   string msg = "";
   if(isStrong)
      msg += "🔥 <b>" + direction + " " + Symbol() + "</b>  ⚡ STRONG\n";
   else
      msg += arrow + " <b>" + direction + " " + Symbol() + "</b>\n";

   msg += Line();
   msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b>\n";
   msg += "🕯 M15: <b>" + pat.name + "</b>\n";

   if(h1Confirm)
      msg += "✅ H1: <b>" + h1Pat.name + "</b>\n";

   if(nearKey)
      msg += "📍 " + levelType + ": <b>" + DoubleToString(keyLevel, digits) + "</b>\n";

   msg += Line();
   msg += "💲 Price: <b>" + DoubleToString(price, digits) + "</b>\n";
   msg += "💪 " + GetStrengthBar(strength) + "\n";
   msg += Line();
   msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
   return msg;
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  ========== PART 2: POSITION ADVISORY SYSTEM ==========            |
//|                                                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| COUNT POSITIONS SAME DIRECTION (for DCA counting)                  |
//+------------------------------------------------------------------+
int CountPositionsSameDirection(ENUM_SIGNAL_TYPE direction)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
      long pType = PositionGetInteger(POSITION_TYPE);
      if(direction == SIGNAL_BUY && pType == POSITION_TYPE_BUY) count++;
      if(direction == SIGNAL_SELL && pType == POSITION_TYPE_SELL) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| FIND SUGGESTED SL LEVEL                                            |
//+------------------------------------------------------------------+
double FindSuggestedSL(ENUM_SIGNAL_TYPE posDirection, double entryPrice)
{
   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);

   if(posDirection == SIGNAL_BUY)
   {
      // For BUY: SL = nearest swing low below current price on H1
      double swingLow = FindNearestSupport(price);
      if(swingLow > 0 && swingLow < price)
         return swingLow;
      return entryPrice;  // fallback to breakeven
   }
   else
   {
      // For SELL: SL = nearest swing high above current price on H1
      double swingHigh = FindNearestResistance(price);
      if(swingHigh > 0 && swingHigh > price)
         return swingHigh;
      return entryPrice;  // fallback to breakeven
   }
}

//+------------------------------------------------------------------+
//| CHECK POSITION ADVISORY - runs every H1 bar                        |
//+------------------------------------------------------------------+
void CheckPositionAdvisory()
{
   // Cooldown check
   if(TimeCurrent() - g_lastAdvisoryTime < InpAdvisoryCooldown * 60)
      return;

   // Gather all open positions for this symbol
   double totalProfit = 0;
   double totalVolume = 0;
   double totalSwap = 0;
   double entryPrice = 0;
   double currentSL = 0;
   double currentTP = 0;
   ENUM_SIGNAL_TYPE posDirection = SIGNAL_NONE;
   string posType = "";
   int posCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;

      totalProfit += PositionGetDouble(POSITION_PROFIT);
      totalSwap += PositionGetDouble(POSITION_SWAP);
      totalVolume += PositionGetDouble(POSITION_VOLUME);
      long pType = PositionGetInteger(POSITION_TYPE);
      posType = (pType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      posDirection = (pType == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
      entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      currentSL = PositionGetDouble(POSITION_SL);
      currentTP = PositionGetDouble(POSITION_TP);
      posCount++;
   }

   // No position = no advisory
   if(posCount == 0) return;

   totalProfit += totalSwap;

   double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double profitPct = (balance > 0) ? (totalProfit / balance) * 100.0 : 0;
   double bigLossThreshold = -(balance * InpBigLossPercent / 100.0);

   // Get market context
   ENUM_TREND h4Trend = GetH4Trend();
   PatternResult h1Pat = DetectPattern(PERIOD_H1, 1);

   bool trendAligned = false;
   if(posDirection == SIGNAL_BUY && h4Trend == TREND_UP) trendAligned = true;
   if(posDirection == SIGNAL_SELL && h4Trend == TREND_DOWN) trendAligned = true;

   bool h1SameDir = (h1Pat.signal == posDirection && h1Pat.signal != SIGNAL_NONE);
   bool h1Opposite = (h1Pat.signal != SIGNAL_NONE && h1Pat.signal != posDirection);

   // Key levels
   double nearestLevel = 0;
   string levelType = "";
   bool nearKey = IsNearKeyLevel(price, nearestLevel, levelType);

   // DCA conditions
   bool nearKeySupport = false;
   if(posDirection == SIGNAL_BUY)
   {
      double sup = FindNearestSupport(price);
      if(sup > 0 && MathAbs(price - sup) <= InpKeyLevelDistance)
         nearKeySupport = true;
   }
   else
   {
      double res = FindNearestResistance(price);
      if(res > 0 && MathAbs(price - res) <= InpKeyLevelDistance)
         nearKeySupport = true;
   }

   int dcaCount = CountPositionsSameDirection(posDirection);
   bool canDCA = (InpMaxDCA > 0 && dcaCount < (1 + InpMaxDCA) && trendAligned && nearKeySupport && h1SameDir);

   // Suggested SL
   double suggestedSL = FindSuggestedSL(posDirection, entryPrice);

   string msg = "";

   //=== ĐANG LỖ ===
   if(totalProfit < 0)
   {
      if(totalProfit <= bigLossThreshold && !trendAligned)
      {
         // 🚨 CẮT LỖ: Lỗ lớn + H4 đảo chiều
         msg = "🚨 <b>CAT LO - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💸 Loss: <b>" + FormatMoney(totalProfit) + " (" + FormatPercent(profitPct) + ")</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b> ❌ Nguoc chieu!\n";
         if(h1Opposite)
            msg += "🕯 H1: <b>" + h1Pat.name + "</b> ❌\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "🚨 <b>Lo lon + trend dao, CAT LO NGAY!</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
      else if(!trendAligned)
      {
         // ⚠️ CẢNH BÁO: H4 trend đang chuyển
         msg = "⚠️ <b>CANH BAO TREND - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + " (" + FormatPercent(profitPct) + ")</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b> ⚠️ Dang chuyen!\n";
         if(h1Opposite)
            msg += "🕯 H1: <b>" + h1Pat.name + "</b> ❌\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "⚠️ <b>Trend H4 nguoc chieu, theo doi sat!</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
      else if(h1Opposite)
      {
         // ⚠️ GỢI Ý ĐÓNG: H1 pattern ngược chiều
         msg = "⚠️ <b>GOI Y DONG LENH - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + " (" + FormatPercent(profitPct) + ")</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b>\n";
         msg += "🕯 H1: <b>" + h1Pat.name + "</b> ❌ Nguoc chieu!\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "👉 <b>Can nhac DONG LENH " + posType + "</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
   }
   //=== HÒA VỐN / LÃI NHẸ (0 đến 0.5% balance) ===
   else if(totalProfit >= 0 && profitPct < 0.5)
   {
      if(h1SameDir)
      {
         // ✅ GIỮ + gợi ý dời SL về breakeven
         msg = "✅ <b>GIU LENH - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + "</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b> ✅\n";
         msg += "🕯 H1: <b>" + h1Pat.name + "</b> ✅\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(currentSL != 0)
            msg += "🛡 SL hien tai: " + DoubleToString(currentSL, digits) + "\n";
         if(currentTP != 0)
            msg += "🎯 TP hien tai: " + DoubleToString(currentTP, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "👉 <b>GIU LENH, doi SL ve breakeven: " + DoubleToString(entryPrice, digits) + "</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
      else if(h1Opposite)
      {
         // ⚠️ GỢI Ý ĐÓNG
         msg = "⚠️ <b>GOI Y DONG LENH - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + "</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b>\n";
         msg += "🕯 H1: <b>" + h1Pat.name + "</b> ❌ Nguoc chieu!\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "👉 <b>Can nhac DONG LENH " + posType + "</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
   }
   //=== ĐANG LÃI (>= 0.5% balance) ===
   else
   {
      if(h1SameDir && canDCA)
      {
         // 💡 GỢI Ý DCA
         msg = "💡 <b>GOI Y DCA - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots (x" + IntegerToString(dcaCount) + ")\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + " (" + FormatPercent(profitPct) + ")</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b> ✅\n";
         msg += "🕯 H1: <b>" + h1Pat.name + "</b> ✅\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "💡 <b>DCA " + posType + " " + DoubleToString(InpDCALotSize, 2) + " lots</b>\n";
         msg += "📊 Con " + IntegerToString(1 + InpMaxDCA - dcaCount) + " lan DCA\n";
         msg += "🛡 Doi SL: " + DoubleToString(suggestedSL, digits) + "\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
      else if(h1SameDir)
      {
         // ✅ GIỮ + gợi ý dời SL theo swing
         msg = "✅ <b>GIU LENH - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + " (" + FormatPercent(profitPct) + ")</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b> ✅\n";
         msg += "🕯 H1: <b>" + h1Pat.name + "</b> ✅\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(currentSL != 0)
            msg += "🛡 SL hien tai: " + DoubleToString(currentSL, digits) + "\n";
         if(currentTP != 0)
            msg += "🎯 TP hien tai: " + DoubleToString(currentTP, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "👉 <b>GIU LENH, doi SL: " + DoubleToString(suggestedSL, digits) + "</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
      else if(nearKey && ((posDirection == SIGNAL_BUY && levelType == "Resistance") ||
                           (posDirection == SIGNAL_SELL && levelType == "Support")))
      {
         // 💡 Giá chạm key level ngược → dời SL sát
         msg = "💡 <b>DOI SL SAT - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + " (" + FormatPercent(profitPct) + ")</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b>\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         msg += "📍 <b>" + levelType + ": " + DoubleToString(nearestLevel, digits) + "</b> ⚠️\n";
         if(currentSL != 0)
            msg += "🛡 SL hien tai: " + DoubleToString(currentSL, digits) + "\n";
         msg += Line();
         msg += "👉 <b>Gia gan " + levelType + ", doi SL: " + DoubleToString(suggestedSL, digits) + "</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
      else if(h1Opposite)
      {
         // ⚠️ GỢI Ý ĐÓNG + lock profit
         msg = "⚠️ <b>GOI Y DONG LENH - LOCK PROFIT - " + Symbol() + "</b>\n";
         msg += Line();
         msg += "📌 " + posType + " " + DoubleToString(totalVolume, 2) + " lots\n";
         msg += "💰 P/L: <b>" + FormatMoney(totalProfit) + " (" + FormatPercent(profitPct) + ")</b>\n";
         msg += Line();
         msg += "📊 H4: <b>" + GetTrendName(h4Trend) + "</b>\n";
         msg += "🕯 H1: <b>" + h1Pat.name + "</b> ❌ Nguoc chieu!\n";
         msg += "💲 Price: " + DoubleToString(price, digits) + "\n";
         if(nearKey)
            msg += "📍 " + levelType + ": " + DoubleToString(nearestLevel, digits) + "\n";
         msg += Line();
         msg += "👉 <b>Dang lai, can nhac DONG LENH hoac doi SL: " + DoubleToString(suggestedSL, digits) + "</b>\n";
         msg += Line();
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      }
   }

   if(StringLen(msg) > 0)
   {
      SendTelegram(msg);
      g_lastAdvisoryTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//|                                                                    |
//|  ========== PART 3: POSITION & ORDER TRACKING ==========           |
//|                                                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| CHECK POSITION CHANGES (closed only)                               |
//+------------------------------------------------------------------+
void CheckPositionChanges()
{
   //=== Check for CLOSED positions only ===
   for(int j = 0; j < g_posCount; j++)
   {
      bool stillOpen = false;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == g_positions[j].ticket)
         {
            stillOpen = true;
            break;
         }
      }

      if(!stillOpen)
      {
         // Position closed
         double closePrice = 0;
         double profit = 0;
         ENUM_DEAL_REASON closeReason = DEAL_REASON_CLIENT;
         bool dealFound = false;

         ulong posId = g_positions[j].positionId;
         if(posId == 0) posId = g_positions[j].ticket;

         if(HistorySelectByPosition(posId))
         {
            int totalDeals = HistoryDealsTotal();
            for(int d = totalDeals - 1; d >= 0; d--)
            {
               ulong dealTicket = HistoryDealGetTicket(d);
               if(dealTicket > 0)
               {
                  ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                  if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
                  {
                     closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                     profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                     profit += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                     profit += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                     closeReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
                     dealFound = true;
                     break;
                  }
               }
            }
         }

         if(!dealFound)
         {
            HistorySelect(TimeCurrent() - 300, TimeCurrent());
            int totalDeals = HistoryDealsTotal();
            for(int d = totalDeals - 1; d >= 0; d--)
            {
               ulong dealTicket = HistoryDealGetTicket(d);
               if(dealTicket > 0 && HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == (long)posId)
               {
                  ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                  if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT)
                  {
                     closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                     profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                     profit += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                     profit += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                     closeReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
                     dealFound = true;
                     break;
                  }
               }
            }
         }

         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double percent = (balance > 0) ? (profit / balance) * 100.0 : 0;
         string symbol = g_positions[j].symbol;
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

         string resultEmoji = "";
         string resultText = "";
         if(profit > 0)
         {
            resultEmoji = "🟢";
            resultText = "WIN";
         }
         else if(profit < 0)
         {
            resultEmoji = "🔴";
            resultText = "LOSS";
         }
         else
         {
            resultEmoji = "⚪";
            resultText = "BREAKEVEN";
         }

         string reasonText = GetCloseReason(closeReason);
         if(closeReason == DEAL_REASON_SL && profit > 0)
            reasonText = "STOP LOSS (SL+)";
         else if(closeReason == DEAL_REASON_TP && profit < 0)
            reasonText = "TARGET PROFIT (TP-)";

         string msg = resultEmoji + " <b>CLOSED - " + resultText + "</b>\n";
         msg += Line();
         msg += "📌 " + g_positions[j].type + " " + symbol + " | " + DoubleToString(g_positions[j].volume, 2) + " lots\n";
         msg += "🔹 Entry: " + DoubleToString(g_positions[j].openPrice, digits) + "\n";
         msg += "🔸 Close: " + DoubleToString(closePrice, digits) + "\n";
         msg += "📋 " + reasonText + "\n";
         msg += Line();
         msg += "💰 <b>" + FormatMoney(profit) + " (" + FormatPercent(percent) + ")</b>\n";
         msg += "💼 Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "$\n";
         msg += Line();
         msg += "🏷 #" + IntegerToString(g_positions[j].ticket) + "\n";
         msg += "🕐 " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
         SendTelegram(msg);
      }
   }
}


//+------------------------------------------------------------------+
//| SAVE CURRENT POSITIONS SNAPSHOT                                    |
//+------------------------------------------------------------------+
void SaveCurrentPositions()
{
   g_posCount = PositionsTotal();
   ArrayResize(g_positions, g_posCount);

   for(int i = 0; i < g_posCount; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         g_positions[i].ticket = ticket;
         g_positions[i].positionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         g_positions[i].symbol = PositionGetString(POSITION_SYMBOL);
         long posType = PositionGetInteger(POSITION_TYPE);
         g_positions[i].type = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         g_positions[i].volume = PositionGetDouble(POSITION_VOLUME);
         g_positions[i].openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         g_positions[i].sl = PositionGetDouble(POSITION_SL);
         g_positions[i].tp = PositionGetDouble(POSITION_TP);
         g_positions[i].profit = PositionGetDouble(POSITION_PROFIT);
      }
   }
}

//+------------------------------------------------------------------+
