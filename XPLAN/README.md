# XPLAN — Client & Payment Manager

A local, **password-protected** desktop program for tracking architecture /
design studio clients, their project payments and contractor commissions.
Rebuilt from the `PGS_KLNT` Excel workbook and pre-loaded with all 28 clients.

## What it does

- 🔒 **Password lock on open.** First launch asks you to set a password; it's
  required on every start afterwards. (PBKDF2-hashed, stored locally. Change it
  any time from the sidebar → *Change Password*.)
- **Clients grouped by year** — each year shows its own totals; open a client
  to see its full **project ledger**.
- **Two payment categories, like the original sheet:**
  - **Payments from the client** — money against the contract.
  - **Commissions from contractors** — ATMOSFERE, PORCELANOSA, OZ, …
  - *Remaining = Contract − client payments. Total received = client payments
    + contractor commissions.*
- **Add clients**, add/edit/delete **payments** and **commissions**, manage
  **payment methods**.
- 📈 **Payments & Charts** — bar charts of totals **by year** and **by month**,
  with a *Show* filter to see client payments, contractor commissions, or both.
- **Export to Excel** (`TOTALI`, `PAGESAT` by year+month+type, one sheet per
  client) and automatic timestamped **backups**.

Albanian terms: *Vlera e Kontratës = Contract · Pagesa = Payment ·
Të Dhëna = Paid · Të Mbetura = Remaining · Kontraktuesi = Contractor.*

## Getting a single `XPLAN.exe`

A Windows `.exe` must be built on Windows. Two easy ways:

### A. Build it yourself (gives a single exe with your data inside)
1. Install **Python 3** from <https://www.python.org/downloads/> (tick
   *“Add python.exe to PATH”*; leave tcl/tk enabled).
2. Double-click **`BUILD_EXE.bat`**.
3. You get **`dist\XPLAN.exe`** — one standalone file. Copy it anywhere and
   double-click to run. Your clients are embedded; the live data is then kept
   in `%APPDATA%\XPLAN`.

### B. Download the exe built automatically on GitHub
The repository builds `XPLAN.exe` on every change (GitHub → **Actions** →
*Build XPLAN Windows exe* → latest run → **Artifacts** → `XPLAN-windows-exe`).
That exe starts empty; load your data once via **Settings → Restore data from
file…** and pick the `xplan_data.json` you were given.

## Run without building (needs Python)
Double-click **`run_XPLAN.bat`** to start straight from the source. In this mode
the data file lives next to the program.

## Your data
- Script mode: `xplan_data.json` next to the program.
- Single-exe mode: `%APPDATA%\XPLAN\xplan_data.json`.
- Backups are written to a `backups` folder on every start and save.
- Forgot the password? Delete the `"password"` entry inside `xplan_data.json`
  (in the data folder) and the program will ask you to set a new one.

## Files

| File | What it is |
|---|---|
| `xplan.py` | The program. |
| `xplan_data.json` | Your clients & payments (script mode / build seed). |
| `run_XPLAN.bat` | Run from source (needs Python). |
| `BUILD_EXE.bat` | Build one standalone `XPLAN.exe` (needs Python once). |
| `backups/` | Automatic backups. |
