# XAU ASSISTANT v3.5.0

Expert Advisor (EA) cho MetaTrader 5 - Tro ly giam sat trade XAUUSD, gui thong bao qua Telegram.

## Tinh nang

### 1. Phat hien tin hieu (Signal Detection)

- Loc trend **H4** bang EMA 50/200 (chi trade theo trend)
- Quet nen tren **M15** (entry) + **H1** (confluence confirm)
- Nhan dien 8 mau nen: Bullish/Bearish Engulfing, Hammer, Shooting Star, Pin Bar, Marubozu
- **Key Level** - Swing High/Low tren H1, Marubozu chi tinh khi breakout key level
- **Confluence** - xac nhan da khung thoi gian (M15 + H1 + key level = strength max)
- Strength bar 1-5 voi bonus cho key level va H1 confirm

### 2. Tu van lenh dang mo (Position Advisory)

He thong doc lap, chay moi bar **H1**, khong phu thuoc signal M15:

- **Dang lo:**
  - Lo lon + H4 dao chieu → canh bao **CAT LO NGAY**
  - H4 dao chieu (chua lo lon) → **CANH BAO TREND** dang chuyen
  - H1 pattern nguoc chieu → goi y **DONG LENH**
- **Hoa von / lai nhe:**
  - H1 cung chieu → **GIU LENH** + goi y doi SL ve breakeven
  - H1 nguoc chieu → goi y **DONG LENH**
- **Dang lai:**
  - H1 cung chieu + key level → goi y **DCA** (toi da 2 lan, chi khi dang lai)
  - H1 cung chieu → **GIU LENH** + goi y doi SL theo swing H1
  - Gia gan key level nguoc → goi y **DOI SL SAT**
  - H1 nguoc chieu → goi y **DONG LENH + LOCK PROFIT**

### 3. Theo doi lenh (Position Tracking)

- Thong bao khi **mo lenh moi** (NEW POSITION)
- Thong bao khi **dong lenh** voi ket qua: WIN / LOSS / BREAKEVEN
- Thong bao khi **thay doi SL/TP** (SL/TP MODIFIED)
- Thong bao khi **dong 1 phan** (PARTIAL CLOSE)
- Hien thi day du: loai lenh, volume, entry, close price, ly do dong (SL/TP/Manual)
- Ket qua tinh theo $ va % balance

## Cau hinh

| Tham so              | Mo ta                                     | Mac dinh |
| -------------------- | ----------------------------------------- | -------- |
| `BotToken`           | Telegram Bot Token                        | -        |
| `ChatId`             | Telegram Chat/Channel ID                  | -        |
| `TrackingName`       | Ten hien thi cho tracking                 | TRACKING |
| `SignalName`         | Ten hien thi cho signal                   | SIGNAL   |
| `CheckInterval`      | Chu ky kiem tra (giay)                    | 5        |
| `CooldownMinutes`    | Cooldown giua cac signal (phut)           | 15       |
| `StrongBodyRatio`    | Ty le body Marubozu                       | 0.70     |
| `StrongMovePercent`  | Nguong bien dong manh (%)                 | 0.15     |
| `BigLossPercent`     | Nguong lo lon (% balance) de canh bao     | 2.0      |
| `EmaFast`            | EMA nhanh (H4)                            | 50       |
| `EmaSlow`            | EMA cham (H4)                             | 200      |
| `SwingLookback`      | So bar tim Swing High/Low (H1)            | 50       |
| `KeyLevelDistance`   | Khoang cach toi key level (points)        | 5.0      |
| `MaxDCA`             | So lan DCA toi da (0=tat)                 | 2        |
| `DCALotSize`         | Lot size moi lan DCA                      | 0.01     |
| `AdvisoryCooldown`   | Cooldown tu van lenh (phut)               | 60       |

## Cai dat

1. Copy `XauAssistant.mq5` vao thu muc `MQL5/Experts/` cua MetaTrader 5
2. Compile trong MetaEditor
3. Keo EA vao chart **XAUUSD**
4. Nhap **Bot Token** va **Chat ID** cua Telegram
5. Trong MT5: Tools → Options → Expert Advisors → cho phep **WebRequest** toi `https://api.telegram.org`
