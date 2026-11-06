# XPLAN — Client & Payment Manager

A small **local desktop program for Windows** (also works on macOS/Linux) that
replaces the `PGS_KLNT` Excel workbook for tracking studio clients and their
payments. It already contains **all 28 clients** imported from your spreadsheet.


## What it does

- **Summary of every client** — contract value, amount paid and remaining
  balance, with grand totals at the bottom (like the old `TOTALI` sheet).
- **Add new clients** — name + contract value (and an optional first payment).
- **Add / edit / delete payments** — each payment has an amount, date, a
  **payment method** and a note. Paid and remaining update automatically.
- **Manage payment methods** — add your own (Cash, Bank Transfer, Card, …).
- **Extra items** — one-off extras per client (like `ATMOSFERE`, `PORCELANOSA`
  in the original sheet).
- **Export back to Excel** (`TOTALI` + one sheet per client) and auto-backups.

Terms kept close to your sheet: *Vlera e Kontratës = Contract value •
Pagesa = Payment • Data e Pagesës = Payment date • Të Dhëna = Paid •
Të Mbetura = Remaining.*

## How to run it (easiest)

1. Install **Python 3** (free) from <https://www.python.org/downloads/>.
   On the first install screen, tick **“Add python.exe to PATH”**. Leave
   **tcl/tk** enabled (it is on by default — that is the window toolkit).
2. Double-click **`run_XPLAN.bat`**. The program window opens.

That's it — no other downloads are needed for day-to-day use. (The Excel
*export* feature additionally uses `openpyxl`; the program will offer a CSV
export and show the one-line install command if it isn't present.)

## How to make a single double-click `XPLAN.exe` (optional)

If you'd rather not keep Python around, build a standalone program once:

1. On a Windows PC with Python installed, double-click **`BUILD_EXE.bat`**.
2. When it finishes, your program is **`dist\XPLAN.exe`**.
3. Keep `XPLAN.exe` and `xplan_data.json` together in one folder.

## Your data

- Everything is stored in **`xplan_data.json`** next to the program — plain,
  portable, easy to back up (just copy the file).
- A timestamped copy is written to the **`backups`** folder every time you
  start the program and every time it saves, so you can always roll back.
- To move to another computer, copy the whole `XPLAN` folder.

## Files in this folder

| File | What it is |
|---|---|
| `xplan.py` | The program. |
| `xplan_data.json` | Your clients and payments (live data). |
| `run_XPLAN.bat` | Double-click to start on Windows. |
| `BUILD_EXE.bat` | Optional: build a standalone `XPLAN.exe`. |
| `backups/` | Automatic backups of your data. |
