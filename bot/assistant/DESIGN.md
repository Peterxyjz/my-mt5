# XAUGUARD v1.0 - Ke hoach thiet ke

## Tong quan

Bot moi thay the XauAssistant. Giu lai core Position Tracking, thiet ke lai Signal Detection va Position Advisory, them Market Overview.

---

## 1. Position Tracking (GIU NGUYEN)

Logic hien tai da du, khong thay doi:

- Phat hien lenh **dong** bang so sanh snapshot truoc/sau
- Truy lich su deal de lay gia dong, ly do (SL/TP/Manual), profit
- Gui thong bao WIN / LOSS / BREAKEVEN kem % balance
- Chay moi `CheckInterval` giay (mac dinh 5s)

---

## 2. Signal Detection (THIET KE LAI)

### 2.1. Van de cu

- Bo loc qua chat: H4 EMA phai ro trend + M15 pattern + key level/H1 confirm
- H4 sideway = bo qua hoan toan → 2 tuan khong co signal
- Chi co 8 mau nen don gian

### 2.2. Thiet ke moi: He thong cham diem + nhieu pattern hon

#### A. Mo hinh nen - Mo rong

**Pattern don (1-2 nen):**
| Pattern | Signal | Base Score |
|---------|--------|------------|
| Bullish Engulfing | BUY | 3 |
| Bearish Engulfing | SELL | 3 |
| Bullish Pin Bar | BUY | 3 |
| Bearish Pin Bar | SELL | 3 |
| Hammer | BUY | 2 |
| Shooting Star | SELL | 2 |
| Bullish Marubozu | BUY | 2 |
| Bearish Marubozu | SELL | 2 |
| Dragonfly Doji | BUY | 2 |
| Gravestone Doji | SELL | 2 |

**Pattern phuc tap (3 nen):**
| Pattern | Signal | Base Score |
|---------|--------|------------|
| Morning Star | BUY | 3 |
| Evening Star | SELL | 3 |
| Three White Soldiers | BUY | 3 |
| Three Black Crows | SELL | 3 |
| Tweezer Bottom | BUY | 2 |
| Tweezer Top | SELL | 2 |

> **Ghi chu**: Base score 3-nen giam so voi ban dau (3 thay vi 4) de tranh score qua de dat.

#### B. He thong cham diem

Moi yeu to cho diem, tong diem du nguong thi gui signal:

| Yeu to | Diem | Ghi chu |
|--------|------|---------|
| **M15 Pattern** | +2 den +3 | Tuy loai pattern (base score) |
| **H4 Trend cung chieu** (EMA) | +2 | EMA 50/200 |
| **H4 Sideway** | 0 | Khong cong khong tru |
| **H4 Nguoc chieu** | -3 | Phat trade nguoc trend |
| **H1 Pattern confirm** | +2 | Cung chieu voi M15 |
| **H1 Pattern nguoc** | -1 | Tru diem |
| **Gan Key Level** (S/R) | +2 | Swing H/L tren H1, khoang cach <= 0.3 * ATR |
| **Marubozu breakout key level** | +1 | Bonus rieng cho Marubozu |
| **RSI M15 oversold/overbought** | +1 | RSI < 30 hoac > 70, cung chieu |
| **ATR cao** (volatility tot) | +1 | ATR hien tai > SMA(20) cua ATR |
| **ATR thap** (thi truong chet) | -1 | ATR hien tai < 0.7 * SMA(20) cua ATR |
| **Phien London/NY** | +1 | Dang trong phien co momentum |
| **Phien Asian** | 0 | Khong cong khong tru |
| **Spread cao** | -2 | Spread > nguong (InpMaxSpread) |

**Diem toi da ly thuyet**: 3 + 2 + 2 + 2 + 1 + 1 + 1 = **12 diem**
**Diem thuc te pho bien**: 5-8 diem

#### C. Nguong signal

| Tong diem | Loai | Hanh dong |
|-----------|------|-----------|
| >= 6 | **SIGNAL** | Gui thong bao binh thuong |
| >= 9 | **STRONG SIGNAL** | Gui thong bao nhan manh |
| < 6 | Khong gui | Bo qua |

#### D. Confidence %

Hien thi do tin cay cua signal:

```
Confidence = (score / 12) * 100%

Vi du: score 8 → Confidence = 67%
Message: 🟢 BUY XAUUSD (67%)
```

#### E. Timeframe

- **Entry**: M15 (quet moi bar M15 moi)
- **Confirm**: H1 (pattern confirm)
- **Trend**: H4 (EMA filter - nhung khong block hoan toan)

#### F. Bo loc bo sung

- **Session**: London/NY cho +1 diem, Asian = 0 (khong block cung)
- **Spread filter**: Spread > InpMaxSpread → -2 diem (gan nhu block)
- **Cooldown**: 15 phut giua cac signal (giu nguyen)
- **Khong gui signal** neu dang co lenh mo (de advisory xu ly)

#### G. Anti-spam: Gom nhom signal

Neu 2 signal cung huong trong 15 phut:
- Khong gui 2 tin rieng le
- Gui 1 tin gom: "Multiple confirmations" + tang confidence

#### H. Signal Log (de backtest sau)

Moi signal (du co gui hay khong) deu luu vao file CSV:

```
DateTime, Pattern, Direction, Score, H4Trend, H1Confirm, KeyLevel, RSI, ATR, Spread, Session, Sent(Y/N)
```

File: `XauGuard_SignalLog.csv` trong thu muc MQL5/Files/

---

## 3. Position Advisory (CAI TIEN)

### 3.1. Van de cu

- Chi check moi bar H1 (qua cham cho vang)
- Chi goi y, khong co trailing SL

### 3.2. Thiet ke moi

#### A. Tan suat check

| Loai canh bao | Tan suat | Ly do |
|---------------|----------|-------|
| **Canh bao khan** | Moi bar M15 | Lo lon, trend H4 dao chieu |
| **Tu van chien luoc** | Moi bar H1 | Giu/dong/DCA/trail SL |

**Canh bao khan (M15):**
- Lo >= BigLossPercent + H4 dao chieu → CAT LO NGAY
- Lo >= BigLossPercent + H1 nguoc chieu → CANH BAO
- Drawdown dot ngot (mat > X% trong 1 bar M15) → CANH BAO

**Tu van chien luoc (H1):** (logic tuong tu cu nhung cai tien)
- Dang lo + H4 dao → Cat lo
- Dang lo + H1 nguoc → Goi y dong
- Hoa von + H1 cung → Giu + doi SL breakeven
- Hoa von + H1 nguoc → Goi y dong
- Dang lai + H1 cung + key level → Goi y DCA
- Dang lai + H1 cung → Giu + goi y trailing SL
- Dang lai + gan key nguoc → Doi SL sat
- Dang lai + H1 nguoc → Dong + lock profit

#### B. Trailing SL theo ATR (goi y)

Thay vi chi goi y "doi SL ve swing", tinh toan cu the bang ATR:

```
ATR_Value = ATR(14) tren H1
Trailing_SL = Price - ATR_Value * Multiplier (cho BUY)
Trailing_SL = Price + ATR_Value * Multiplier (cho SELL)
Multiplier mac dinh = 1.5
```

Moi lan gui advisory, kem theo:
- SL goi y theo ATR: xxx.xx
- SL goi y theo Swing H/L: xxx.xx
- De trader tu chon

#### C. Cooldown

- Canh bao khan (M15): cooldown 15 phut
- Tu van chien luoc (H1): cooldown 60 phut (giu nguyen)

---

## 4. Market Overview (MOI)

### 4.1. Mo ta

Gui bao cao tong quan dau moi phien giao dich: Asian, London, New York.

### 4.2. Xu ly DST (Daylight Saving Time)

Van de: Gio mo phien London va NY thay doi theo mua (DST).

**Gio phien (UTC):**

| Phien | Binh thuong (mua dong) | DST (mua he) |
|-------|----------------------|-------------|
| Asian (Tokyo) | 00:00 - 09:00 | 00:00 - 09:00 (khong doi) |
| London | 08:00 - 17:00 | 07:00 - 16:00 |
| New York | 13:00 - 22:00 | 12:00 - 21:00 |

**Giai phap**: Dung `TimeGMT()` (UTC) thay vi `TimeCurrent()` (server time) va tu tinh DST:

```
US DST: Bat dau Chu Nhat thu 2 thang 3, ket thuc Chu Nhat thu 1 thang 11
EU DST: Bat dau Chu Nhat cuoi thang 3, ket thuc Chu Nhat cuoi thang 10
```

Bot tu dong tinh ngay chuyen DST moi nam va dieu chinh gio phien.

### 4.3. Noi dung bao cao

Gui 1 tin nhan dau moi phien gom:

```
📊 XAUGUARD - LONDON SESSION
━━━━━━━━━━━━━━━━━━━━

📈 H4 Trend: UPTREND (EMA 50 > 200)
💲 Price: 2,345.50

📍 Key Levels:
   🔺 Resistance: 2,355.00
   🔻 Support: 2,330.00

📊 RSI (H1): 55.3
📊 ATR (H1): 8.5 points

📋 Phien truoc (Asian):
   High: 2,348.00 | Low: 2,340.00
   Range: 8.0 points

💡 Bias: BUY - 67% (H4 up + Price > Support)
━━━━━━━━━━━━━━━━━━━━
🕐 2024-01-15 07:00 UTC
```

### 4.4. Logic xac dinh Bias

| Dieu kien | Bias |
|-----------|------|
| H4 Uptrend + Price gan Support | BUY |
| H4 Downtrend + Price gan Resistance | SELL |
| H4 Uptrend + Price gan Resistance | CAUTION (co the dao) |
| H4 Downtrend + Price gan Support | CAUTION |
| H4 Sideway | NEUTRAL |

---

## 5. Cau truc code

### 5.1. Input Parameters

```
// --- Core ---
input string InpBotToken          = "";         // Telegram Bot Token
input string InpChatId            = "";         // Telegram Chat/Channel ID
input string InpTrackingName      = "TRACKING"; // Account Tracking Name
input string InpSignalName        = "SIGNAL";   // Signal Alert Name
input int    InpCheckInterval     = 5;          // Check interval (seconds)

// --- Signal Detection ---
input int    InpCooldownMinutes   = 15;         // Signal cooldown (minutes)
input int    InpEmaFast           = 50;         // EMA Fast period (H4)
input int    InpEmaSlow           = 200;        // EMA Slow period (H4)
input int    InpSwingLookback     = 50;         // Swing H/L lookback bars (H1)
input int    InpRSIPeriod         = 14;         // RSI period (M15)
input int    InpATRPeriod         = 14;         // ATR period (H1)
input int    InpVolumeSMAPeriod   = 20;         // ATR SMA period (for volatility filter)
input int    InpSignalThreshold   = 6;          // Signal score threshold
input int    InpStrongThreshold   = 9;          // Strong signal score threshold
input double InpMaxSpread         = 30.0;       // Max spread (points) - tren muc nay -2 diem

// --- Position Advisory ---
input double InpBigLossPercent    = 2.0;        // Big loss threshold (% balance)
input int    InpMaxDCA            = 2;          // Max DCA times (0=disable)
input double InpDCALotSize        = 0.01;       // DCA lot size
input double InpATRMultiplier     = 1.5;        // ATR trailing SL multiplier
input int    InpUrgentCooldown    = 15;         // Urgent advisory cooldown (minutes)
input int    InpAdvisoryCooldown  = 60;         // Strategic advisory cooldown (minutes)

// --- Market Overview ---
input bool   InpMarketOverview    = true;       // Enable Market Overview

// --- Logging ---
input bool   InpSignalLog         = true;       // Log all signals to CSV
```

### 5.2. Key Level - Cai tien

Key level distance khong con dung gia tri co dinh, ma dung ATR:

```
KeyLevelDistance = 0.3 * ATR(14, H1)
```

Loi ich: Tu dong dieu chinh theo do bien dong cua thi truong.

### 5.3. Cau truc OnTimer()

```
OnTimer()
{
   // 1. Market Overview - check dau phien
   if(InpMarketOverview)
      CheckMarketOverview();

   // 2. Signal Detection - moi bar M15 moi
   if(new M15 bar)
      ProcessSignal();

   // 3. Position Advisory
   if(new M15 bar)
      CheckUrgentAdvisory();     // Canh bao khan (lo lon, trend dao)
   if(new H1 bar)
      CheckStrategicAdvisory();  // Tu van chien luoc + trailing SL

   // 4. Position Tracking - moi lan check
   CheckPositionChanges();
   SaveCurrentPositions();
}
```

### 5.4. Indicator Handles

```
g_emaFastHandle    // EMA 50 H4
g_emaSlowHandle    // EMA 200 H4
g_rsiHandle        // RSI 14 M15
g_atrHandle        // ATR 14 H1
```

---

## 6. Tom tat

| Tinh nang | XauAssistant v3.5 | XauGuard v1.0 |
|-----------|-------------------|---------------|
| Position Tracking | Detect dong lenh | **Giu nguyen** |
| Signal - Pattern | 8 pattern | **16 pattern** (them 3-nen, Doji) |
| Signal - Filter | H4 phai ro trend (block cung) | **Cham diem linh hoat**, H4 sideway van co signal |
| Signal - Confirm | Key level HOAC H1 | **Multi-factor**: RSI + ATR + Key level + H1 + Session |
| Signal - Output | Chi BUY/SELL + strength bar | **Confidence %** + score chi tiet |
| Signal - Anti-spam | Cooldown 15p | Cooldown + **gom signal cung huong** |
| Signal - Log | Khong co | **CSV log** de backtest |
| Advisory - Tan suat | Moi H1 | **M15 (khan) + H1 (chien luoc)** |
| Advisory - SL | Goi y swing H/L | **Goi y ATR + Swing H/L** |
| Key Level distance | Co dinh (5 points) | **Dong 0.3 * ATR** |
| Spread filter | Khong co | **Spread cao → -2 diem** |
| Volatility filter | Khong co | **ATR cao/thap → +1/-1 diem** |
| Market Overview | Khong co | **Bao cao dau moi phien** |
| DST handling | Khong co | **Tu dong tinh DST** |
