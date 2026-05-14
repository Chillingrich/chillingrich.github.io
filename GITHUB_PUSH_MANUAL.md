# GitHub Push Manual — EA Docs & Trade Data

**Owner:** Chillingrich
**Repo:** https://github.com/Chillingrich/chillingrich.github.io
**Local path:** `~/Documents/chillingrich.github.io`
**Last Updated:** 2026-05-15

---

## 1. สิ่งที่ต้องมีก่อน (Setup ครั้งแรกครั้งเดียว)

### 1.1 Clone repo
```bash
cd ~/Documents
git clone https://github.com/Chillingrich/chillingrich.github.io.git
```

### 1.2 ตั้ง Remote URL พร้อม Token
```bash
git -C ~/Documents/chillingrich.github.io remote set-url origin \
  https://Chillingrich:ghp_TOKEN@github.com/Chillingrich/chillingrich.github.io.git
```
แทน `ghp_TOKEN` ด้วย Personal Access Token จริง

### 1.3 สร้าง Personal Access Token
1. ไปที่ https://github.com/settings/tokens
2. **Generate new token (classic)**
3. ตั้งชื่อ เช่น `mac-push`
4. ติ๊ก ✅ **repo**
5. **Generate token** → Copy `ghp_...`
6. ใส่ใน remote URL ข้างบน

### 1.4 สร้าง Push Script
```bash
cat > ~/Documents/push_ea.sh << 'EOF'
#!/bin/bash
REPO="$HOME/Documents/chillingrich.github.io"
TARGET="$REPO/strategies/twobar-sr-zone"

mkdir -p "$TARGET"
cp "$HOME/Downloads/TwoBar_SR_Zone_EA.md"  "$TARGET/"
cp "$HOME/Downloads/TwoBar_SR_Zone_EA.mq5" "$TARGET/"

cd "$REPO"
git add strategies/twobar-sr-zone/
git commit -m "TwoBar EA update $(date '+%Y-%m-%d %H:%M')"
git push origin main
echo "✅ Done"
EOF

chmod +x ~/Documents/push_ea.sh
```

---

## 2. Workflow ปกติ (ทำทุกครั้งที่อัปเดต)

```
1. คุยกับ Claude → ขอ update .md หรือ .mq5
2. Download ไฟล์จาก Claude → ไปอยู่ใน ~/Downloads
3. เปิด Terminal
4. รัน: ~/Documents/push_ea.sh
5. เช็คที่ GitHub ว่าไฟล์ขึ้นแล้ว
```

---

## 3. Folder Structure ใน Repo

```
chillingrich.github.io/
├── strategies/
│   ├── twobar-sr-zone/
│   │   ├── TwoBar_SR_Zone_EA.md
│   │   └── TwoBar_SR_Zone_EA.mq5
│   ├── bb-rsi/
│   ├── htf-breakout/
│   ├── macd-scalp/
│   ├── mucho/
│   ├── omo-engulfing/
│   └── omo-sniper/
├── data/
├── dashboard.html
├── index.html
└── README.md
```

---

## 4. เพิ่ม EA ตัวใหม่

```bash
# สร้าง folder ใหม่
mkdir -p ~/Documents/chillingrich.github.io/strategies/EA_NAME

# Copy ไฟล์
cp ~/Downloads/NEW_EA.md  ~/Documents/chillingrich.github.io/strategies/EA_NAME/
cp ~/Downloads/NEW_EA.mq5 ~/Documents/chillingrich.github.io/strategies/EA_NAME/

# Push
cd ~/Documents/chillingrich.github.io
git add strategies/EA_NAME/
git commit -m "Add EA_NAME $(date '+%Y-%m-%d')"
git push origin main
```

---

## 5. Trade Data → Dashboard (Auto Update)

### Workflow ที่เป็นไปได้

```
MT5 EA → Export trade log (CSV)
    ↓
Script copy CSV → repo/data/
    ↓
git push → GitHub
    ↓
dashboard.html อ่าน CSV จาก GitHub Raw URL
    ↓
แสดงผลสรุปเทรดอัตโนมัติ ✅
```

### ขั้นตอน
1. **MT5 EA** export trade log เป็น CSV ไปที่ folder ที่กำหนด
2. **Script** (push_trade.sh) copy CSV → repo แล้ว push
3. **dashboard.html** fetch CSV จาก GitHub Raw URL แล้ว render

### GitHub Raw URL ของ CSV
```
https://raw.githubusercontent.com/Chillingrich/chillingrich.github.io/main/data/trades.csv
```

### ตัวอย่าง push_trade.sh
```bash
#!/bin/bash
REPO="$HOME/Documents/chillingrich.github.io"
# แก้ path ให้ตรงกับที่ MT5 export CSV
CSV_SOURCE="$HOME/Documents/MT5_Logs/trades.csv"

cp "$CSV_SOURCE" "$REPO/data/trades.csv"

cd "$REPO"
git add data/trades.csv
git commit -m "Trade data update $(date '+%Y-%m-%d %H:%M')"
git push origin main
echo "✅ Trade data pushed"
```

---

## 6. บอก Claude ครั้งหน้า

เมื่อเปิดแชทใหม่กับ Claude บอกว่า:

> "ฉัน push ไฟล์ขึ้น GitHub ที่ `Chillingrich/chillingrich.github.io`
> local path คือ `~/Documents/chillingrich.github.io`
> EA files อยู่ใน `strategies/twobar-sr-zone/`
> มี push script ที่ `~/Documents/push_ea.sh`"

Claude จะเข้าใจ context ทันทีครับ

---

## 7. คำสั่งที่ใช้บ่อย

```bash
# Push EA docs
~/Documents/push_ea.sh

# เช็ค status
cd ~/Documents/chillingrich.github.io && git status

# ดู commit ล่าสุด
cd ~/Documents/chillingrich.github.io && git log --oneline -5

# Pull update จาก GitHub
cd ~/Documents/chillingrich.github.io && git pull origin main
```
