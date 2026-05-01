//+------------------------------------------------------------------+
//|                                                    RiskGuard.mq5 |
//|  One-click trading + risk guard cho symbol hiện tại.             |
//|  - Bấm BUY/SELL vào lệnh ngay với lot trên panel (không cần SL). |
//|  - EA quét SL của tất cả position -> Total Risk ($).             |
//|  - Chặn lệnh mới khi:                                            |
//|      * có position chưa đặt SL, HOẶC                             |
//|      * Total Risk <= -MaxTotalRisk, HOẶC                         |
//|      * Daily P/L <= -MaxDailyLoss.                               |
//+------------------------------------------------------------------+
#property copyright "RiskGuard"
#property version   "1.10"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//--- Inputs
input double DefaultLot     = 0.01;   // Lot khởi tạo trên panel
input double MaxTotalRisk   = 30.0;   // Ngưỡng tổng risk (USD, số dương)
input double MaxDailyLoss   = 100.0;  // Max lỗ / ngày (USD, số dương)
input int    BEOffsetPoints = 150;    // BE offset (points) — XAUUSD 150 = 0.150
input long   MagicNumber    = 990011;
input int    Slippage       = 30;

//--- Panel colors
#define COL_BG        C'18,22,30'
#define COL_BORDER    C'55,65,80'
#define COL_PANEL     C'30,36,48'
#define COL_PANEL2    C'40,48,62'
#define COL_TEXT      C'230,235,245'
#define COL_MUTED     C'130,140,158'
#define COL_GREEN     C'46,184,102'
#define COL_GREEN_D   C'32,90,58'
#define COL_RED       C'235,72,76'
#define COL_RED_D     C'105,40,45'
#define COL_AMBER     C'248,178,68'

//--- Object names
#define PFX          "RG_"
#define OBJ_BG       PFX "bg"
#define OBJ_TITLE    PFX "title"
#define OBJ_LOT_LBL  PFX "lot_lbl"
#define OBJ_LOT      PFX "lot"
#define OBJ_LOT_M    PFX "lot_minus"
#define OBJ_LOT_P    PFX "lot_plus"
#define OBJ_BUY      PFX "btn_buy"
#define OBJ_SELL     PFX "btn_sell"
#define OBJ_BE       PFX "btn_be"
#define OBJ_EVEN     PFX "btn_even"
#define OBJ_RISK_BG  PFX "risk_bg"
#define OBJ_RISK_LBL PFX "risk_lbl"
#define OBJ_RISK     PFX "risk"
#define OBJ_DAILY    PFX "daily"
#define OBJ_STATUS   PFX "status"
#define OBJ_POS_HDR  PFX "pos_hdr"
#define OBJ_POS_ROW_ PFX "pos_row_"   // + index

#define MAX_POS_ROWS 10

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFillingBySymbol(_Symbol);
   CreatePanel();
   UpdatePanel();
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, PFX);
}

void OnTimer() { UpdatePanel(); }
void OnTick()  { UpdatePanel(); }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+
int PANEL_X = 2;
int PANEL_Y = 2;
int PANEL_W = 240;
int PANEL_H = 200;

void CreatePanel()
{
   int x = PANEL_X, y = PANEL_Y, w = PANEL_W;
   int pad = 8;

   MakeRect(OBJ_BG, x, y, w, PANEL_H, COL_BG, COL_BORDER);

   // Row 1: Lot
   int ly = y + 8;
   MakeButton(OBJ_LOT_M, x+pad,       ly, 22, 22, "−", COL_TEXT, COL_PANEL2);
   MakeEdit  (OBJ_LOT,   x+pad+24,    ly, w-pad*2-48, 22,
              DoubleToString(DefaultLot,2), COL_TEXT, COL_PANEL2);
   MakeButton(OBJ_LOT_P, x+w-pad-22,  ly, 22, 22, "+", COL_TEXT, COL_PANEL2);

   // Row 2: Buy / Sell
   int by = y + 36;
   int gap = 6;
   int bw = (w - pad*2 - gap) / 2;
   MakeButton(OBJ_BUY,  x+pad,        by, bw, 30, "BUY",  COL_TEXT, COL_GREEN);
   MakeButton(OBJ_SELL, x+pad+bw+gap, by, bw, 30, "SELL", COL_TEXT, COL_RED);

   // Row 3: BE / EVEN (smaller management buttons)
   int my = y + 70;
   MakeButton(OBJ_BE,   x+pad,        my, bw, 22, "BE",   COL_TEXT, COL_PANEL2);
   MakeButton(OBJ_EVEN, x+pad+bw+gap, my, bw, 22, "EVEN", COL_TEXT, COL_PANEL2);

   // Row 4: Risk · Daily box (lớn hơn, là trọng tâm)
   int ry = y + 98;
   int rh = 56;
   MakeRect (OBJ_RISK_BG, x+pad, ry, w-pad*2, rh, COL_PANEL, COL_BORDER);
   MakeLabel(OBJ_RISK_LBL, x+pad+10, ry+6,  "RISK  ·  DAILY", COL_MUTED, 8, true);
   MakeLabel(OBJ_RISK,     x+pad+10, ry+22, "$0.00",          COL_TEXT, 16, true);
   MakeLabel(OBJ_DAILY, x+w-pad-10, ry+26, "$0.00", COL_MUTED, 11, true);
   ObjectSetInteger(0, OBJ_DAILY, OBJPROP_ANCHOR, ANCHOR_RIGHT);

   // Row 5: Status
   MakeLabel(OBJ_STATUS, x+pad, ry+rh+8, "Ready", COL_MUTED, 8, false);

   // Row 6: Positions summary (căn giữa)
   MakeLabel(OBJ_POS_HDR, x+w/2, ry+rh+26, "—", COL_MUTED, 8, false);
   ObjectSetInteger(0, OBJ_POS_HDR, OBJPROP_ANCHOR, ANCHOR_CENTER);
   for(int i = 0; i < MAX_POS_ROWS; i++)
      MakeLabel(OBJ_POS_ROW_ + IntegerToString(i),
                x+pad, ry+rh+46 + i*11, " ", COL_TEXT, 7, false);
}

void MakeRect(string name, int x, int y, int w, int h, color bg, color border)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,100);
}

void MakeLabel(string name, int x, int y, string text, color clr, int fontSize, bool bold)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fontSize);
   ObjectSetString (0,name,OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,101);
}

void MakeEdit(string name, int x, int y, int w, int h, string text, color clr, color bg)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_EDIT,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,COL_BORDER);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString (0,name,OBJPROP_FONT,"Segoe UI");
   ObjectSetInteger(0,name,OBJPROP_ALIGN,ALIGN_CENTER);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_READONLY,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,102);
}

void MakeButton(string name, int x, int y, int w, int h, string text, color clr, color bg)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,COL_BORDER);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE, (h >= 28) ? 10 : 8);
   ObjectSetString (0,name,OBJPROP_FONT,"Segoe UI Semibold");
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,103);
}

void SetButtonColor(string name, color bg, color fg)
{
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   double totalRisk;
   bool   hasNoSL;
   int    openCount;
   ScanPositions(totalRisk, hasNoSL, openCount);

   double pl = DailyPL();

   // Total risk box color/text
   color riskColor;
   string riskTxt;
   if(hasNoSL)
   {
      riskColor = COL_AMBER;
      riskTxt = "⚠ No SL";
   }
   else if(totalRisk >= 0)
   {
      riskColor = COL_GREEN;
      riskTxt = StringFormat("+$%.2f", totalRisk);
   }
   else
   {
      riskColor = COL_RED;
      riskTxt = StringFormat("-$%.2f", MathAbs(totalRisk));
   }
   ObjectSetString (0, OBJ_RISK, OBJPROP_TEXT, riskTxt);
   ObjectSetInteger(0, OBJ_RISK, OBJPROP_COLOR, riskColor);

   // Daily (nằm bên phải risk box)
   color plClr = (pl >= 0) ? COL_GREEN : COL_RED;
   ObjectSetInteger(0, OBJ_DAILY, OBJPROP_COLOR, plClr);
   ObjectSetString (0, OBJ_DAILY, OBJPROP_TEXT,
                    StringFormat("%s$%.0f", pl<0?"-":"+", MathAbs(pl)));

   // Position rows
   PaintPositions();

   // Determine block
   string blockReason = "";
   bool blocked = false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   { blocked = true; blockReason = "AutoTrading OFF (toolbar)"; }
   else if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   { blocked = true; blockReason = "Allow Algo Trading OFF (F7)"; }
   else if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   { blocked = true; blockReason = "Trading disabled on account"; }
   else if(pl <= -MaxDailyLoss)        { blocked = true; blockReason = "Daily loss limit hit"; }
   else if(hasNoSL)                    { blocked = true; blockReason = "Position without SL"; }
   else if(totalRisk <= -MaxTotalRisk) { blocked = true; blockReason = StringFormat("Total risk > -$%.0f", MaxTotalRisk); }

   if(blocked)
   {
      SetButtonColor(OBJ_BUY,  COL_GREEN_D, COL_MUTED);
      SetButtonColor(OBJ_SELL, COL_RED_D,   COL_MUTED);
      ObjectSetString (0, OBJ_STATUS, OBJPROP_TEXT, "BLOCKED: " + blockReason);
      ObjectSetInteger(0, OBJ_STATUS, OBJPROP_COLOR, COL_AMBER);
   }
   else
   {
      SetButtonColor(OBJ_BUY,  COL_GREEN, COL_TEXT);
      SetButtonColor(OBJ_SELL, COL_RED,   COL_TEXT);
      ObjectSetString (0, OBJ_STATUS, OBJPROP_TEXT, " ");
   }

   // BE / EVEN enable state
   bool beOk   = CanApplyBE();
   bool evenOk = CanApplyEven();
   SetButtonColor(OBJ_BE,   beOk   ? COL_PANEL2 : COL_PANEL, beOk   ? COL_TEXT : COL_MUTED);
   SetButtonColor(OBJ_EVEN, evenOk ? COL_PANEL2 : COL_PANEL, evenOk ? COL_TEXT : COL_MUTED);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Scan positions on current symbol                                 |
//+------------------------------------------------------------------+
void ScanPositions(double &totalRisk, bool &hasNoSL, int &count)
{
   totalRisk = 0.0;
   hasNoSL = false;
   count = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      count++;
      double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0) { hasNoSL = true; continue; }

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double lot   = PositionGetDouble(POSITION_VOLUME);
      long   type  = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (type == POSITION_TYPE_BUY);

      // P/L nếu chạm SL (có thể dương nếu SL đã lock lời)
      totalRisk += PLAtPrice(entry, sl, lot, isBuy);
   }
}

double PLAtPrice(double entry, double target, double lot, bool isBuy)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0) return 0.0;
   double diff = isBuy ? (target - entry) : (entry - target);
   return (diff / tickSize) * tickValue * lot;
}

//+------------------------------------------------------------------+
//| Paint positions list                                             |
//+------------------------------------------------------------------+
void PaintPositions()
{
   int total = PositionsTotal();
   int cnt = 0;
   double totalLot = 0;
   double sumEntryLot = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double lot = PositionGetDouble(POSITION_VOLUME);
      cnt++;
      totalLot += lot;
      sumEntryLot += PositionGetDouble(POSITION_PRICE_OPEN) * lot;
   }

   string hdr;
   if(cnt == 0)
   {
      hdr = "— no positions —";
   }
   else
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double avg = sumEntryLot / totalLot;
      hdr = StringFormat("%d pos · %.2f lot · @%s",
                        cnt, totalLot, DoubleToString(avg, digits));
   }
   ObjectSetString (0, OBJ_POS_HDR, OBJPROP_TEXT, hdr);
   ObjectSetInteger(0, OBJ_POS_HDR, OBJPROP_COLOR, COL_MUTED);

   for(int j = 0; j < MAX_POS_ROWS; j++)
   {
      string name = OBJ_POS_ROW_ + IntegerToString(j);
      ObjectSetString(0, name, OBJPROP_TEXT, " ");
   }
}

//+------------------------------------------------------------------+
//| Chart events                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == OBJ_BUY)   { HandleTrade(true);  ResetButton(OBJ_BUY);  }
   if(sparam == OBJ_SELL)  { HandleTrade(false); ResetButton(OBJ_SELL); }
   if(sparam == OBJ_LOT_M) { AdjustLot(-1); ResetButton(OBJ_LOT_M); }
   if(sparam == OBJ_LOT_P) { AdjustLot(+1); ResetButton(OBJ_LOT_P); }
   if(sparam == OBJ_BE)
   {
      if(CanApplyBE()) ApplyBE();
      else Flash("BE: no eligible position");
      ResetButton(OBJ_BE);
   }
   if(sparam == OBJ_EVEN)
   {
      if(CanApplyEven()) ApplyEven();
      else Flash("EVEN: not available");
      ResetButton(OBJ_EVEN);
   }
}

void ResetButton(string name)
{
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ChartRedraw();
}

void AdjustLot(int dir)
{
   double lot = ReadLotInput();
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lot += dir * step;
   lot = NormalizeLot(lot);
   ObjectSetString(0, OBJ_LOT, OBJPROP_TEXT, DoubleToString(lot, 2));
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Trade                                                            |
//+------------------------------------------------------------------+
void HandleTrade(bool isBuy)
{
   // Re-check blockers tại thời điểm click (không tin panel cache)
   double totalRisk; bool hasNoSL; int count;
   ScanPositions(totalRisk, hasNoSL, count);
   double pl = DailyPL();

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) { Flash("Enable AutoTrading (Ctrl+E)"); return; }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))           { Flash("F7 → tick Allow Algo Trading"); return; }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))   { Flash("Trading disabled on account"); return; }
   if(pl <= -MaxDailyLoss)             { Flash("BLOCKED: Daily loss"); return; }
   if(hasNoSL)                         { Flash("BLOCKED: Position without SL"); return; }
   if(totalRisk <= -MaxTotalRisk)      { Flash(StringFormat("BLOCKED: Total risk -$%.2f", MathAbs(totalRisk))); return; }

   double lot = NormalizeLot(ReadLotInput());
   if(lot <= 0) { Flash("Invalid lot"); return; }

   bool ok = isBuy ? trade.Buy (lot, _Symbol, 0, 0, 0, "RiskGuard")
                   : trade.Sell(lot, _Symbol, 0, 0, 0, "RiskGuard");
   if(ok)
   {
      PlaySound("ok.wav");
      Flash(StringFormat("OK %s %.2f", isBuy?"BUY":"SELL", lot));
   }
   else
   {
      PlaySound("timeout.wav");
      Flash(StringFormat("FAIL %d %s", trade.ResultRetcode(), trade.ResultComment()));
   }
}

void Flash(string s)
{
   ObjectSetString (0, OBJ_STATUS, OBJPROP_TEXT, s);
   ObjectSetInteger(0, OBJ_STATUS, OBJPROP_COLOR, COL_AMBER);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| BE — set SL = entry ± BEOffsetPoints cho mọi position đủ điều    |
//| kiện (đang lời hơn offset). Không kéo SL xuống vị trí tệ hơn.    |
//+------------------------------------------------------------------+
bool CanApplyBE()
{
   double offset = BEOffsetPoints * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      bool isBuy   = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double newSL = NormalizeDouble(isBuy ? entry + offset : entry - offset, digits);

      // giá hiện tại đã vượt newSL chưa? (broker reject SL đặt ngược/quá sát)
      bool priceOK = isBuy ? (bid > newSL) : (ask < newSL);
      // SL hiện tại đã = newSL thì không cần áp
      bool needsUpdate = MathAbs(sl - newSL) > _Point/2;
      if(priceOK && needsUpdate) return true;
   }
   return false;
}

void ApplyBE()
{
   double offset = BEOffsetPoints * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int done = 0, skipped = 0, failed = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      bool isBuy   = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double newSL = NormalizeDouble(isBuy ? entry + offset : entry - offset, digits);

      bool priceOK     = isBuy ? (bid > newSL) : (ask < newSL);
      bool needsUpdate = MathAbs(sl - newSL) > _Point/2;
      if(!priceOK || !needsUpdate) { skipped++; continue; }

      if(trade.PositionModify(ticket, newSL, tp)) { done++; PlaySound("ok.wav"); }
      else { failed++; }
   }
   Flash(StringFormat("BE: %d done · %d skip · %d fail", done, skipped, failed));
   if(failed > 0) PlaySound("timeout.wav");
}

//+------------------------------------------------------------------+
//| EVEN — tính breakeven chung (weighted avg entry) cho các         |
//| position cùng chiều, set SL = BE để tổng P/L = 0.                |
//| Disable khi: có hedge (cả 2 chiều), hoặc giá chưa vượt BE đủ.   |
//+------------------------------------------------------------------+
bool ComputeEven(double &bePrice, bool &isBuy)
{
   double sumLotBuy = 0, sumLotSell = 0;
   double sumEntryLotBuy = 0, sumEntryLotSell = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double lot   = PositionGetDouble(POSITION_VOLUME);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      { sumLotBuy += lot; sumEntryLotBuy += entry*lot; }
      else
      { sumLotSell += lot; sumEntryLotSell += entry*lot; }
   }

   // Yêu cầu: chỉ 1 chiều, có ít nhất 2 lot tổng (hoặc ≥1 lệnh)
   if(sumLotBuy > 0 && sumLotSell > 0) return false;  // hedge → skip
   if(sumLotBuy + sumLotSell <= 0) return false;

   if(sumLotBuy > 0)
   {
      isBuy = true;
      bePrice = sumEntryLotBuy / sumLotBuy;
   }
   else
   {
      isBuy = false;
      bePrice = sumEntryLotSell / sumLotSell;
   }
   return true;
}

bool CanApplyEven()
{
   double bePrice; bool isBuy;
   if(!ComputeEven(bePrice, isBuy)) return false;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   bePrice = NormalizeDouble(bePrice, digits);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // giá phải vượt BE đủ (không broker nào cho đặt SL ngược/sát giá)
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * _Point;
   if(isBuy  && bid - bePrice <= minDist) return false;
   if(!isBuy && bePrice - ask <= minDist) return false;

   // Kiểm tra có ít nhất 1 position cần update (SL hiện tại không = BE)
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(MathAbs(PositionGetDouble(POSITION_SL) - bePrice) > _Point/2) return true;
   }
   return false;
}

void ApplyEven()
{
   double bePrice; bool isBuy;
   if(!ComputeEven(bePrice, isBuy)) { Flash("EVEN: hedged or no position"); return; }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   bePrice = NormalizeDouble(bePrice, digits);
   int done = 0, failed = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double tp = PositionGetDouble(POSITION_TP);
      if(trade.PositionModify(ticket, bePrice, tp)) done++;
      else failed++;
   }
   Flash(StringFormat("EVEN @ %s: %d done · %d fail",
                     DoubleToString(bePrice,digits), done, failed));
   if(done > 0) PlaySound("ok.wav");
   if(failed > 0) PlaySound("timeout.wav");
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
double ReadLotInput()
{
   string t = ObjectGetString(0, OBJ_LOT, OBJPROP_TEXT);
   StringTrimLeft(t); StringTrimRight(t);
   StringReplace(t, ",", ".");
   double v = StringToDouble(t);
   return (v > 0.0) ? v : DefaultLot;
}

double NormalizeLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lot = MathFloor(lot / step + 0.5) * step;
   if(lot < minL) lot = minL;
   if(lot > maxL) lot = maxL;
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Daily P/L (realized hôm nay + floating toàn account)             |
//+------------------------------------------------------------------+
double DailyPL()
{
   datetime dayStart = StartOfDay(TimeCurrent());
   double pl = 0.0;

   if(HistorySelect(dayStart, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         pl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         pl += HistoryDealGetDouble(ticket, DEAL_SWAP);
         pl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }

   int posTotal = PositionsTotal();
   for(int i = 0; i < posTotal; i++)
   {
      ulong pt = PositionGetTicket(i);
      if(pt == 0) continue;
      if(!PositionSelectByTicket(pt)) continue;
      pl += PositionGetDouble(POSITION_PROFIT);
      pl += PositionGetDouble(POSITION_SWAP);
   }
   return pl;
}

datetime StartOfDay(datetime t)
{
   MqlDateTime mt; TimeToStruct(t, mt);
   mt.hour = 0; mt.min = 0; mt.sec = 0;
   return StructToTime(mt);
}
//+------------------------------------------------------------------+
