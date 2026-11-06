#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
XPLAN - Client & Payment Manager
=================================
A local, password-protected desktop program (Windows / macOS / Linux) for
tracking architecture / design studio clients, their projects and payments.

Built from the "PGS_KLNT" Excel workbook. Terminology kept close to the
original sheet:

    KLIENTI            -> Client
    KONTRAKTUESI       -> Contractor
    VLERA E KONTRATES  -> Contract Value
    PAGESA 1..N        -> Payment 1..N (from the client)
    DATA E PAGESES     -> Payment Date
    TE DHENA           -> Paid (total received)
    TE MBETURA         -> Remaining (balance)
    PERMBLEDHJE/TOTALI -> Summary

Money is tracked in TWO categories, like the original sheet:
    * Payments from the client      (income against the contract)
    * Commissions from contractors  (ATMOSFERE, PORCELANOSA, OZ, ...)

    Remaining       = Contract value - Payments from client
    Total received  = Payments from client + Contractor commissions

Features
    - Password lock on open (PBKDF2-SHA256, salted, stored in the data file).
    - Clients grouped by year; open a client for its full project ledger.
    - Payments & Charts: totals by year and by month, as bar charts, with a
      filter for client payments / contractor commissions / both.
    - Add clients, add/edit/delete payments and commissions, manage methods.
    - Local JSON storage with automatic timestamped backups.
    - Export to Excel (openpyxl, optional) or CSV.

Core app uses ONLY the Python standard library, so it runs on any standard
Python installation with no extra downloads.
"""

import os
import re
import sys
import csv
import json
import base64
import shutil
import hashlib
import datetime
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, filedialog

APP_TITLE = "XPLAN — Client & Payment Manager"

# --------------------------------------------------------------------------- #
#  Modern minimalist palette & fonts
# --------------------------------------------------------------------------- #
BG       = "#f4f5f7"
CARD     = "#ffffff"
INK      = "#1f2933"
MUTED    = "#7b8794"
ACCENT   = "#3b82f6"   # client payments (blue)
ACCENT_DK= "#2563eb"
GREEN    = "#15a34a"
RED      = "#dc2626"
AMBER    = "#f59e0b"   # contractor commissions (amber)
LINE     = "#e4e7eb"
SIDEBAR  = "#111827"
SIDE_TXT = "#cbd5e1"
SIDE_SEL = "#1f2937"
GRID     = "#eceef1"

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def _font(size=10, bold=False):
    fam = "Segoe UI"
    try:
        import tkinter.font as tkfont
        if fam not in tkfont.families():
            fam = "TkDefaultFont"
    except Exception:
        fam = "TkDefaultFont"
    return (fam, size, "bold") if bold else (fam, size)


# --------------------------------------------------------------------------- #
#  Paths & persistence
# --------------------------------------------------------------------------- #
def data_dir():
    """Where the live data file lives.

    A single-file .exe keeps its data in a stable per-user folder so the
    program itself can stay ONE standalone file. When run as a plain script
    (e.g. via run_XPLAN.bat) the data sits next to the script.
    """
    if getattr(sys, "frozen", False):
        if sys.platform.startswith("win"):
            base = os.environ.get("APPDATA") or os.path.expanduser("~")
            d = os.path.join(base, "XPLAN")
        elif sys.platform == "darwin":
            d = os.path.join(os.path.expanduser("~/Library/Application Support"), "XPLAN")
        else:
            d = os.path.join(os.path.expanduser("~/.local/share"), "XPLAN")
    else:
        d = os.path.dirname(os.path.abspath(__file__))
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        d = os.path.dirname(os.path.abspath(__file__))
    return d


DATA_DIR = data_dir()
DATA_FILE = os.path.join(DATA_DIR, "xplan_data.json")
BACKUP_DIR = os.path.join(DATA_DIR, "backups")


def seed_if_needed():
    """On first run of a bundled .exe, copy embedded seed data to DATA_FILE."""
    if os.path.exists(DATA_FILE):
        return
    base = getattr(sys, "_MEIPASS", None)
    if not base:
        return
    seed = os.path.join(base, "xplan_seed.json")
    if os.path.exists(seed):
        try:
            shutil.copy2(seed, DATA_FILE)
        except Exception:
            pass

DEFAULT_DATA = {
    "currency": "€",
    "payment_methods": ["Cash", "Bank Transfer", "Card", "Other"],
    "password": None,
    "clients": [],
}


def load_data_normalize(data):
    data.setdefault("currency", "€")
    data.setdefault("payment_methods", ["Cash", "Bank Transfer", "Card", "Other"])
    data.setdefault("password", None)
    data.setdefault("clients", [])
    for c in data["clients"]:
        c.setdefault("name", "Unnamed")
        c.setdefault("contract_value", 0.0)
        c.setdefault("payments", [])
        c.setdefault("year", None)
        if "commissions" not in c:
            c["commissions"] = c.pop("extras", [])
        for cm in c["commissions"]:
            cm.setdefault("name", cm.get("contractor", "Contractor"))
            cm.setdefault("amount", 0.0)
            cm.setdefault("date", "")
            cm.setdefault("method", "")
            cm.setdefault("note", "")
    return data


def load_data():
    if not os.path.exists(DATA_FILE):
        return dict(DEFAULT_DATA)
    try:
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        messagebox.showerror("Data error",
                             "Could not read data file:\n%s\n\n%s" % (DATA_FILE, e))
        return dict(DEFAULT_DATA)
    return load_data_normalize(data)


def make_backup(tag="start"):
    if not os.path.exists(DATA_FILE):
        return
    try:
        os.makedirs(BACKUP_DIR, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        shutil.copy2(DATA_FILE, os.path.join(BACKUP_DIR, "xplan_%s_%s.json" % (stamp, tag)))
        _prune_backups()
    except Exception:
        pass


def _prune_backups(keep=40):
    try:
        files = sorted((os.path.join(BACKUP_DIR, f) for f in os.listdir(BACKUP_DIR)
                        if f.endswith(".json")), key=os.path.getmtime)
        for old in files[:-keep]:
            os.remove(old)
    except Exception:
        pass


def save_data(data):
    make_backup("save")
    tmp = DATA_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, DATA_FILE)


# --------------------------------------------------------------------------- #
#  Password helpers
# --------------------------------------------------------------------------- #
def hash_password(pw, salt=None):
    if salt is None:
        salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", pw.encode("utf-8"), salt, 120000)
    return {"salt": base64.b64encode(salt).decode(), "hash": base64.b64encode(dk).decode()}


def verify_password(pw, record):
    try:
        salt = base64.b64decode(record["salt"])
        dk = hashlib.pbkdf2_hmac("sha256", pw.encode("utf-8"), salt, 120000)
        return base64.b64encode(dk).decode() == record["hash"]
    except Exception:
        return False


# --------------------------------------------------------------------------- #
#  Value / date helpers
# --------------------------------------------------------------------------- #
def to_float(value, default=0.0):
    if value is None:
        return default
    try:
        return float(str(value).replace(",", "").replace(" ", ""))
    except Exception:
        return default


def parse_date(s):
    if not s:
        return (None, None)
    if isinstance(s, (datetime.date, datetime.datetime)):
        return (s.year, s.month)
    s = str(s).strip()
    m = re.match(r"^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$", s)
    if m:
        d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if y < 100:
            y += 2000
        if 1 <= mo <= 12 and 2000 <= y <= 2100:
            return (y, mo)
    m2 = re.search(r"(20\d{2})", s)
    if m2:
        return (int(m2.group(1)), None)
    return (None, None)


def paid_of(c):
    return sum(to_float(p.get("amount")) for p in c.get("payments", []))


def commissions_of(c):
    return sum(to_float(e.get("amount")) for e in c.get("commissions", []))


def remaining_of(c):
    return to_float(c.get("contract_value")) - paid_of(c)


def total_received_of(c):
    return paid_of(c) + commissions_of(c)


def client_year(c):
    if c.get("year"):
        return int(c["year"])
    yrs = [parse_date(p.get("date"))[0] for p in c.get("payments", [])]
    yrs = [y for y in yrs if y]
    return min(yrs) if yrs else None


def today_str():
    return datetime.date.today().strftime("%d/%m/%Y")


def money_items(c, which="all"):
    """which: 'client' | 'commission' | 'all'."""
    out = []
    if which in ("client", "all"):
        out += c.get("payments", [])
    if which in ("commission", "all"):
        out += c.get("commissions", [])
    return out


# --------------------------------------------------------------------------- #
#  Bar chart widget
# --------------------------------------------------------------------------- #
class BarChart(tk.Canvas):
    def __init__(self, parent, bar_color=ACCENT, **kw):
        super().__init__(parent, bg=CARD, highlightthickness=0, **kw)
        self.bar_color = bar_color
        self.pairs = []
        self.bind("<Configure>", lambda e: self.redraw())

    def set_data(self, pairs, color=None):
        self.pairs = pairs
        if color:
            self.bar_color = color
        self.redraw()

    def redraw(self):
        self.delete("all")
        w, h = self.winfo_width(), self.winfo_height()
        if w < 40 or h < 40:
            return
        pad_l, pad_r, pad_t, pad_b = 54, 16, 22, 34
        plot_w, plot_h = w - pad_l - pad_r, h - pad_t - pad_b
        if not self.pairs or max((v for _, v in self.pairs), default=0) <= 0:
            self.create_text(w / 2, h / 2, text="No payments in this period",
                             fill=MUTED, font=_font(10))
            return
        vmax = max(v for _, v in self.pairs)
        step = _nice_step(vmax)
        axis_max = step * (int(vmax / step) + 1)
        for i in range(5):
            val = axis_max * i / 4
            y = pad_t + plot_h - (val / axis_max) * plot_h
            self.create_line(pad_l, y, w - pad_r, y, fill=GRID)
            self.create_text(pad_l - 8, y, text=self._short(val), anchor="e",
                             fill=MUTED, font=_font(8))
        n = len(self.pairs)
        slot = plot_w / n
        bw = min(slot * 0.6, 54)
        for i, (label, val) in enumerate(self.pairs):
            cx = pad_l + slot * i + slot / 2
            bh = (val / axis_max) * plot_h if val > 0 else 0
            if bh > 0:
                self.create_rectangle(cx - bw / 2, pad_t + plot_h - bh, cx + bw / 2,
                                      pad_t + plot_h, fill=self.bar_color, outline=self.bar_color)
                self.create_text(cx, pad_t + plot_h - bh - 8, text=self._short(val),
                                 fill=INK, font=_font(8, True))
            self.create_text(cx, pad_t + plot_h + 14, text=str(label), fill=MUTED, font=_font(8))

    def _short(self, v):
        v = float(v)
        if v >= 1_000_000:
            return "%.1fM" % (v / 1_000_000)
        if v >= 1_000:
            return "%.0fk" % (v / 1_000)
        return "%.0f" % v


def _nice_step(vmax):
    import math
    if vmax <= 0:
        return 1
    raw = vmax / 4.0
    mag = 10 ** int(math.floor(math.log10(raw)))
    for mult in (1, 2, 2.5, 5, 10):
        if mult * mag >= raw:
            return mult * mag
    return 10 * mag


# --------------------------------------------------------------------------- #
#  Dialogs
# --------------------------------------------------------------------------- #
class _BaseDialog(tk.Toplevel):
    def __init__(self, parent, title):
        super().__init__(parent)
        self.title(title)
        self.configure(bg=CARD, padx=18, pady=16)
        self.resizable(False, False)
        self.result = None
        self.transient(parent)

    def _finish(self):
        self.grab_set()
        self.wait_window(self)


class PaymentDialog(_BaseDialog):
    def __init__(self, parent, methods, currency, payment=None, title="Add Payment from Client"):
        super().__init__(parent, title)
        payment = payment or {}
        f = _font(10)
        ttk.Label(self, text="Amount (%s)" % currency).grid(row=0, column=0, sticky="w", pady=5)
        self.amount = ttk.Entry(self, width=26, font=f)
        self.amount.grid(row=0, column=1, pady=5)
        self.amount.insert(0, "" if payment.get("amount") in (None, "") else str(payment.get("amount")))
        ttk.Label(self, text="Date (dd/mm/yyyy)").grid(row=1, column=0, sticky="w", pady=5)
        self.date = ttk.Entry(self, width=26, font=f)
        self.date.grid(row=1, column=1, pady=5)
        self.date.insert(0, payment.get("date") or today_str())
        ttk.Label(self, text="Method").grid(row=2, column=0, sticky="w", pady=5)
        self.method = ttk.Combobox(self, width=23, values=methods, state="readonly", font=f)
        self.method.grid(row=2, column=1, pady=5)
        cur = payment.get("method") or (methods[0] if methods else "")
        self.method.set(cur if cur in methods else (methods[0] if methods else ""))
        ttk.Label(self, text="Note").grid(row=3, column=0, sticky="w", pady=5)
        self.note = ttk.Entry(self, width=26, font=f)
        self.note.grid(row=3, column=1, pady=5)
        self.note.insert(0, payment.get("note") or "")
        btns = ttk.Frame(self)
        btns.grid(row=4, column=0, columnspan=2, pady=(14, 0), sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="OK", style="Accent.TButton", command=self._ok).pack(side="right")
        self.amount.focus_set()
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self.destroy())
        self._finish()

    def _ok(self):
        amt = to_float(self.amount.get(), None)
        if amt is None:
            messagebox.showwarning("Invalid amount", "Please enter a number.", parent=self)
            return
        self.result = {"amount": amt, "date": self.date.get().strip(),
                       "method": self.method.get().strip(), "note": self.note.get().strip()}
        self.destroy()


class CommissionDialog(_BaseDialog):
    def __init__(self, parent, methods, currency, item=None, title="Add Contractor Commission"):
        super().__init__(parent, title)
        item = item or {}
        f = _font(10)
        ttk.Label(self, text="Contractor name").grid(row=0, column=0, sticky="w", pady=5)
        self.name = ttk.Entry(self, width=26, font=f)
        self.name.grid(row=0, column=1, pady=5)
        self.name.insert(0, item.get("name") or "")
        ttk.Label(self, text="Commission (%s)" % currency).grid(row=1, column=0, sticky="w", pady=5)
        self.amount = ttk.Entry(self, width=26, font=f)
        self.amount.grid(row=1, column=1, pady=5)
        self.amount.insert(0, "" if item.get("amount") in (None, "") else str(item.get("amount")))
        ttk.Label(self, text="Date (dd/mm/yyyy)").grid(row=2, column=0, sticky="w", pady=5)
        self.date = ttk.Entry(self, width=26, font=f)
        self.date.grid(row=2, column=1, pady=5)
        self.date.insert(0, item.get("date") or today_str())
        ttk.Label(self, text="Method").grid(row=3, column=0, sticky="w", pady=5)
        self.method = ttk.Combobox(self, width=23, values=methods, state="readonly", font=f)
        self.method.grid(row=3, column=1, pady=5)
        self.method.set(item.get("method") if item.get("method") in methods else (methods[0] if methods else ""))
        ttk.Label(self, text="Note").grid(row=4, column=0, sticky="w", pady=5)
        self.note = ttk.Entry(self, width=26, font=f)
        self.note.grid(row=4, column=1, pady=5)
        self.note.insert(0, item.get("note") or "")
        btns = ttk.Frame(self)
        btns.grid(row=5, column=0, columnspan=2, pady=(14, 0), sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="OK", style="Accent.TButton", command=self._ok).pack(side="right")
        self.name.focus_set()
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self.destroy())
        self._finish()

    def _ok(self):
        if not self.name.get().strip():
            messagebox.showwarning("Missing name", "Enter the contractor's name.", parent=self)
            return
        amt = to_float(self.amount.get(), None)
        if amt is None:
            messagebox.showwarning("Invalid amount", "Please enter a number.", parent=self)
            return
        self.result = {"name": self.name.get().strip(), "amount": amt,
                       "date": self.date.get().strip(), "method": self.method.get().strip(),
                       "note": self.note.get().strip()}
        self.destroy()


class ClientDialog(_BaseDialog):
    def __init__(self, parent, methods, currency, client=None, title="Add New Client"):
        super().__init__(parent, title)
        self._methods, self._currency = methods, currency
        client = client or {}
        self._editing = bool(client)
        f = _font(10)
        ttk.Label(self, text="Client name").grid(row=0, column=0, sticky="w", pady=5)
        self.name = ttk.Entry(self, width=30, font=f)
        self.name.grid(row=0, column=1, pady=5)
        self.name.insert(0, client.get("name") or "")
        ttk.Label(self, text="Contract value (%s)" % currency).grid(row=1, column=0, sticky="w", pady=5)
        self.contract = ttk.Entry(self, width=30, font=f)
        self.contract.grid(row=1, column=1, pady=5)
        self.contract.insert(0, "" if client.get("contract_value") in (None, "") else str(client.get("contract_value", "")))
        ttk.Label(self, text="Year").grid(row=2, column=0, sticky="w", pady=5)
        yr_now = datetime.date.today().year
        years = [""] + [str(y) for y in range(yr_now + 1, 2021, -1)]
        self.year = ttk.Combobox(self, width=27, values=years, font=f)
        self.year.grid(row=2, column=1, pady=5)
        self.year.set(str(client.get("year")) if client.get("year") else "")
        if not self._editing:
            self.add_first = tk.BooleanVar(value=False)
            ttk.Checkbutton(self, text="Also record a first payment now",
                            variable=self.add_first).grid(row=3, column=0, columnspan=2, sticky="w", pady=(8, 2))
        btns = ttk.Frame(self)
        btns.grid(row=4, column=0, columnspan=2, pady=(14, 0), sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="OK", style="Accent.TButton", command=self._ok).pack(side="right")
        self.name.focus_set()
        self.bind("<Escape>", lambda e: self.destroy())
        self._finish()

    def _ok(self):
        name = self.name.get().strip()
        if not name:
            messagebox.showwarning("Missing name", "Please enter a client name.", parent=self)
            return
        contract = to_float(self.contract.get(), None)
        if contract is None:
            messagebox.showwarning("Invalid value", "Contract value must be a number.", parent=self)
            return
        year = None
        if self.year.get().strip():
            try:
                year = int(self.year.get().strip())
            except ValueError:
                messagebox.showwarning("Invalid year", "Year must be like 2025.", parent=self)
                return
        result = {"name": name, "contract_value": contract, "year": year}
        if not self._editing and self.add_first.get():
            dlg = PaymentDialog(self, self._methods, self._currency, title="First Payment")
            if dlg.result:
                result["first_payment"] = dlg.result
        self.result = result
        self.destroy()


class MethodsDialog(_BaseDialog):
    def __init__(self, parent, methods):
        super().__init__(parent, "Payment Methods")
        self._methods = list(methods)
        ttk.Label(self, text="Methods available when recording a payment:").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 6))
        self.listbox = tk.Listbox(self, height=8, width=34, activestyle="none",
                                  bg=BG, fg=INK, highlightthickness=0, bd=0, font=_font(10))
        self.listbox.grid(row=1, column=0, columnspan=2, sticky="nsew")
        for m in self._methods:
            self.listbox.insert("end", m)
        row = ttk.Frame(self)
        row.grid(row=2, column=0, columnspan=2, sticky="we", pady=(8, 4))
        self.entry = ttk.Entry(row, width=24, font=_font(10))
        self.entry.pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="Add", command=self._add).pack(side="left", padx=(6, 0))
        ttk.Button(self, text="Remove selected", command=self._remove).grid(row=3, column=0, sticky="w", pady=(0, 8))
        btns = ttk.Frame(self)
        btns.grid(row=4, column=0, columnspan=2, sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="Save", style="Accent.TButton", command=self._save).pack(side="right")
        self.entry.bind("<Return>", lambda e: self._add())
        self.entry.focus_set()
        self.bind("<Escape>", lambda e: self.destroy())
        self._finish()

    def _add(self):
        v = self.entry.get().strip()
        if v and v not in self._methods:
            self._methods.append(v)
            self.listbox.insert("end", v)
        self.entry.delete(0, "end")

    def _remove(self):
        sel = self.listbox.curselection()
        if sel:
            del self._methods[sel[0]]
            self.listbox.delete(sel[0])

    def _save(self):
        if not self._methods:
            messagebox.showwarning("Empty list", "Keep at least one method.", parent=self)
            return
        self.result = self._methods
        self.destroy()


class PasswordDialog(tk.Toplevel):
    def __init__(self, parent, mode, verify_record=None):
        super().__init__(parent)
        self.mode, self.verify_record, self.result = mode, verify_record, None
        self.title("XPLAN")
        self.configure(bg=CARD)
        self.resizable(False, False)
        self.transient(parent)
        wrap = tk.Frame(self, bg=CARD, padx=34, pady=30)
        wrap.pack()
        tk.Label(wrap, text="XPLAN", bg=CARD, fg=INK, font=_font(22, True)).pack()
        sub = "Set a password to protect your data" if mode == "set" else "Enter your password"
        tk.Label(wrap, text=sub, bg=CARD, fg=MUTED, font=_font(10)).pack(pady=(2, 16))
        self.pw1 = ttk.Entry(wrap, show="•", width=28, font=_font(11), justify="center")
        self.pw1.pack(ipady=3)
        if mode == "set":
            tk.Label(wrap, text="", bg=CARD).pack(pady=2)
            self.pw2 = ttk.Entry(wrap, show="•", width=28, font=_font(11), justify="center")
            self.pw2.pack(ipady=3)
            tk.Label(wrap, text="Confirm password", bg=CARD, fg=MUTED, font=_font(8)).pack()
        self.msg = tk.Label(wrap, text="", bg=CARD, fg=RED, font=_font(9))
        self.msg.pack(pady=(10, 4))
        ttk.Button(wrap, text="Unlock" if mode == "login" else "Set password",
                   style="Accent.TButton", command=self._ok).pack(fill="x", pady=(4, 0))
        self.pw1.focus_set()
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self._cancel())
        self.protocol("WM_DELETE_WINDOW", self._cancel)
        self._center()
        self.grab_set()
        self.wait_window(self)

    def _center(self):
        self.update_idletasks()
        w, h = self.winfo_width(), self.winfo_height()
        sw, sh = self.winfo_screenwidth(), self.winfo_screenheight()
        self.geometry("+%d+%d" % ((sw - w) // 2, (sh - h) // 3))

    def _ok(self):
        pw = self.pw1.get()
        if self.mode == "set":
            if len(pw) < 4:
                self.msg.config(text="Use at least 4 characters."); return
            if pw != self.pw2.get():
                self.msg.config(text="Passwords do not match."); return
            self.result = ("set", pw); self.destroy()
        else:
            if verify_password(pw, self.verify_record):
                self.result = ("ok", pw); self.destroy()
            else:
                self.msg.config(text="Wrong password."); self.pw1.delete(0, "end")

    def _cancel(self):
        self.result = None
        self.destroy()


# --------------------------------------------------------------------------- #
#  Main application
# --------------------------------------------------------------------------- #
class XplanApp(tk.Tk):
    def __init__(self):
        super().__init__()
        seed_if_needed()
        self.data = load_data()
        make_backup("start")
        self.ok = False
        self.selected_client = None
        self.current_page = "clients"

        self.title(APP_TITLE)
        self.geometry("1140x720")
        self.minsize(980, 620)
        self.configure(bg=BG)
        self._setup_style()

        self.withdraw()
        if not self._authenticate():
            self.destroy()
            return
        self.deiconify()
        self.ok = True

        self._build_header()
        self._build_sidebar()
        self._build_content()
        self.show_page("clients")
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.bind("<Control-s>", lambda e: self.save())

    def _setup_style(self):
        st = ttk.Style(self)
        try:
            st.theme_use("clam")
        except tk.TclError:
            pass
        st.configure(".", background=BG, foreground=INK, font=_font(10))
        st.configure("TFrame", background=BG)
        st.configure("Card.TFrame", background=CARD)
        st.configure("TLabel", background=BG, foreground=INK)
        st.configure("TButton", padding=(12, 7), relief="flat", background="#e8eaed",
                     foreground=INK, font=_font(10))
        st.map("TButton", background=[("active", "#dfe2e6")])
        st.configure("Accent.TButton", background=ACCENT, foreground="#ffffff",
                     padding=(14, 8), font=_font(10, True))
        st.map("Accent.TButton", background=[("active", ACCENT_DK)])
        st.configure("TEntry", fieldbackground=CARD, bordercolor=LINE, relief="flat")
        st.configure("TCombobox", fieldbackground=CARD, relief="flat")
        st.configure("Treeview", background=CARD, fieldbackground=CARD, foreground=INK,
                     rowheight=26, borderwidth=0, font=_font(10))
        st.configure("Treeview.Heading", background=BG, foreground=MUTED, relief="flat", font=_font(9, True))
        st.map("Treeview", background=[("selected", "#e6efff")], foreground=[("selected", INK)])

    def _authenticate(self):
        rec = self.data.get("password")
        if not rec:
            dlg = PasswordDialog(self, mode="set")
            if not dlg.result:
                return False
            self.data["password"] = hash_password(dlg.result[1])
            try:
                save_data(self.data)
            except Exception as e:
                messagebox.showerror("Error", "Could not save password:\n%s" % e)
                return False
            return True
        for _ in range(3):
            dlg = PasswordDialog(self, mode="login", verify_record=rec)
            if dlg.result and dlg.result[0] == "ok":
                return True
            if dlg.result is None:
                return False
        return False

    @property
    def currency(self):
        return self.data.get("currency", "€")

    def money(self, v):
        return "%s %s" % (self.currency, "{:,.0f}".format(to_float(v)))

    # ---- header --------------------------------------------------------- #
    def _build_header(self):
        bar = tk.Frame(self, bg=CARD, height=60)
        bar.pack(side="top", fill="x")
        bar.pack_propagate(False)
        tk.Frame(self, bg=LINE, height=1).pack(side="top", fill="x")
        tk.Label(bar, text="XPLAN", bg=CARD, fg=INK, font=_font(16, True)).pack(side="left", padx=(20, 6))
        tk.Label(bar, text="Client & Payment Manager", bg=CARD, fg=MUTED, font=_font(10)).pack(side="left")
        self.header_stat = tk.Label(bar, text="", bg=CARD, fg=MUTED, font=_font(10))
        self.header_stat.pack(side="right", padx=20)
        ttk.Button(bar, text="＋  Add Client", style="Accent.TButton",
                   command=self.add_client).pack(side="right", padx=(0, 6), pady=12)

    # ---- sidebar -------------------------------------------------------- #
    def _build_sidebar(self):
        self._body = tk.Frame(self, bg=BG)
        self._body.pack(side="top", fill="both", expand=True)
        side = tk.Frame(self._body, bg=SIDEBAR, width=190)
        side.pack(side="left", fill="y")
        side.pack_propagate(False)
        self.nav_buttons = {}
        for key, label, icon in (("clients", "Clients", "👥"),
                                 ("payments", "Payments & Charts", "📈")):
            b = tk.Label(side, text="  %s   %s" % (icon, label), bg=SIDEBAR, fg=SIDE_TXT,
                         font=_font(11), anchor="w", padx=12, pady=12, cursor="hand2")
            b.pack(fill="x", pady=(6 if key == "clients" else 0, 0))
            b.bind("<Button-1>", lambda e, k=key: self.show_page(k))
            self.nav_buttons[key] = b
        bottom = tk.Frame(side, bg=SIDEBAR)
        bottom.pack(side="bottom", fill="x", pady=10)
        for label, cmd in (("Payment Methods", self.manage_methods),
                           ("Export to Excel", self.export_excel),
                           ("Change Password", self.change_password),
                           ("Settings", self.open_settings)):
            lab = tk.Label(bottom, text="  " + label, bg=SIDEBAR, fg="#8a94a6", font=_font(9),
                           anchor="w", padx=12, pady=6, cursor="hand2")
            lab.pack(fill="x")
            lab.bind("<Button-1>", lambda e, c=cmd: c())

    def _highlight_nav(self):
        for k, b in self.nav_buttons.items():
            b.configure(bg=SIDE_SEL if k == self.current_page else SIDEBAR,
                        fg="#ffffff" if k == self.current_page else SIDE_TXT)

    # ---- content -------------------------------------------------------- #
    def _build_content(self):
        self.content = tk.Frame(self._body, bg=BG)
        self.content.pack(side="left", fill="both", expand=True)
        self.pages = {}
        self._build_clients_page()
        self._build_payments_page()

    def show_page(self, key):
        self.current_page = key
        for p in self.pages.values():
            p.pack_forget()
        self.pages[key].pack(fill="both", expand=True)
        self._highlight_nav()
        if key == "clients":
            self.refresh_client_tree()
        else:
            self.refresh_charts()
        self.update_header()

    # ---- CLIENTS page --------------------------------------------------- #
    def _build_clients_page(self):
        page = tk.Frame(self.content, bg=BG)
        self.pages["clients"] = page
        pan = ttk.PanedWindow(page, orient="horizontal")
        pan.pack(fill="both", expand=True, padx=16, pady=16)

        left = tk.Frame(pan, bg=CARD)
        pan.add(left, weight=1)
        ctrl = tk.Frame(left, bg=CARD)
        ctrl.pack(fill="x", padx=12, pady=(12, 6))
        tk.Label(ctrl, text="Clients by year", bg=CARD, fg=INK, font=_font(12, True)).pack(side="left")
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *a: self.refresh_client_tree())
        ttk.Entry(ctrl, textvariable=self.search_var, width=18, font=_font(10)).pack(side="right")
        tk.Label(ctrl, text="Search", bg=CARD, fg=MUTED, font=_font(9)).pack(side="right", padx=(0, 6))

        self.ctree = ttk.Treeview(left, columns=("contract", "paid", "remaining"),
                                  show="tree headings", selectmode="browse")
        self.ctree.heading("#0", text="Client")
        self.ctree.column("#0", width=210, stretch=True)
        for key, txt, w in (("contract", "Contract", 90), ("paid", "Paid", 90), ("remaining", "Remaining", 90)):
            self.ctree.heading(key, text=txt)
            self.ctree.column(key, width=w, anchor="e", stretch=False)
        self.ctree.tag_configure("year", font=_font(10, True), foreground=INK)
        self.ctree.tag_configure("owing", foreground=RED)
        self.ctree.tag_configure("paidoff", foreground=GREEN)
        vsb = ttk.Scrollbar(left, orient="vertical", command=self.ctree.yview)
        self.ctree.configure(yscrollcommand=vsb.set)
        self.ctree.pack(side="left", fill="both", expand=True, padx=(12, 0), pady=(0, 12))
        vsb.pack(side="right", fill="y", pady=(0, 12))
        self.ctree.bind("<<TreeviewSelect>>", self.on_select_client)

        right = tk.Frame(pan, bg=CARD)
        pan.add(right, weight=2)
        self.detail = right
        self._build_detail_empty()

    def refresh_client_tree(self):
        q = (self.search_var.get() if hasattr(self, "search_var") else "").strip().lower()
        self.ctree.delete(*self.ctree.get_children())
        groups = {}
        for c in self.data["clients"]:
            if q and q not in c["name"].lower():
                continue
            groups.setdefault(client_year(c), []).append(c)
        order = lambda y: (-1 if y is None else 0, -(y or 0))
        for y in sorted(groups.keys(), key=order):
            label = str(y) if y else "Unspecified year"
            gcl = sorted(groups[y], key=lambda c: c["name"].lower())
            parent = self.ctree.insert("", "end", iid="year::%s" % label, open=True,
                                       text="%s   (%d)" % (label, len(gcl)),
                                       values=(self.money(sum(to_float(c.get("contract_value")) for c in gcl)),
                                               self.money(sum(paid_of(c) for c in gcl)),
                                               self.money(sum(remaining_of(c) for c in gcl))),
                                       tags=("year",))
            for c in gcl:
                rem = remaining_of(c)
                self.ctree.insert(parent, "end", iid="client::%s" % c["name"], text="   " + c["name"],
                                  values=(self.money(c.get("contract_value")), self.money(paid_of(c)),
                                          self.money(rem)),
                                  tags=("owing" if rem > 0 else "paidoff",))
        if self.selected_client:
            iid = "client::%s" % self.selected_client["name"]
            if self.ctree.exists(iid):
                self.ctree.selection_set(iid)
        self.update_header()

    def _client_by_name(self, name):
        for c in self.data["clients"]:
            if c["name"] == name:
                return c
        return None

    def on_select_client(self, event=None):
        sel = self.ctree.selection()
        if not sel or not sel[0].startswith("client::"):
            return
        c = self._client_by_name(sel[0][len("client::"):])
        if c:
            self.selected_client = c
            self._build_detail(c)

    def _clear_detail(self):
        for w in self.detail.winfo_children():
            w.destroy()

    def _build_detail_empty(self):
        self._clear_detail()
        tk.Label(self.detail, text="Select a client to open its project,\nor use ＋ Add Client.",
                 bg=CARD, fg=MUTED, font=_font(13), justify="center").place(relx=0.5, rely=0.45, anchor="center")

    def _stat_card(self, parent, col, label, value, fg):
        card = tk.Frame(parent, bg=BG)
        card.grid(row=0, column=col, padx=4, pady=4, sticky="nsew")
        parent.columnconfigure(col, weight=1)
        tk.Label(card, text=label, bg=BG, fg=MUTED, font=_font(8)).pack(anchor="w", padx=10, pady=(9, 0))
        tk.Label(card, text=value, bg=BG, fg=fg, font=_font(14, True)).pack(anchor="w", padx=10, pady=(0, 9))

    def _build_detail(self, c):
        self._clear_detail()
        d = self.detail
        # scrollable container so a long ledger fits
        head = tk.Frame(d, bg=CARD)
        head.pack(fill="x", padx=16, pady=(14, 2))
        tk.Label(head, text=c["name"], bg=CARD, fg=INK, font=_font(15, True)).pack(side="left")
        tk.Label(head, text="   project ledger · %s" % (client_year(c) or "year not set"),
                 bg=CARD, fg=MUTED, font=_font(10)).pack(side="left")
        ttk.Button(head, text="Delete", command=self.delete_client).pack(side="right")
        ttk.Button(head, text="Edit", command=self.edit_client).pack(side="right", padx=(0, 6))

        info = tk.Frame(d, bg=CARD)
        info.pack(fill="x", padx=12, pady=6)
        contract, paid, rem, com = (to_float(c.get("contract_value")), paid_of(c),
                                    remaining_of(c), commissions_of(c))
        self._stat_card(info, 0, "CONTRACT (Vlera)", self.money(contract), INK)
        self._stat_card(info, 1, "PAID BY CLIENT (Të Dhëna)", self.money(paid), ACCENT)
        self._stat_card(info, 2, "REMAINING (Të Mbetura)", self.money(rem), RED if rem > 0 else GREEN)
        self._stat_card(info, 3, "CONTRACTOR COMMISSIONS", self.money(com), AMBER)
        self._stat_card(info, 4, "TOTAL RECEIVED", self.money(paid + com), GREEN)

        # ---- payments from client ---- #
        ph = tk.Frame(d, bg=CARD)
        ph.pack(fill="x", padx=16, pady=(14, 4))
        tk.Label(ph, text="● Payments from client", bg=CARD, fg=ACCENT, font=_font(11, True)).pack(side="left")
        ttk.Button(ph, text="＋ Add", style="Accent.TButton", command=self.add_payment).pack(side="right")
        ttk.Button(ph, text="Edit", command=self.edit_payment).pack(side="right", padx=(0, 6))
        ttk.Button(ph, text="Delete", command=self.delete_payment).pack(side="right", padx=(0, 6))
        self.pay_tree = ttk.Treeview(d, columns=("no", "date", "amount", "method", "note"),
                                     show="headings", height=6, selectmode="browse")
        for key, txt, w, a in (("no", "#", 34, "center"), ("date", "Date", 96, "center"),
                               ("amount", "Amount", 104, "e"), ("method", "Method", 120, "w"),
                               ("note", "Note", 150, "w")):
            self.pay_tree.heading(key, text=txt)
            self.pay_tree.column(key, width=w, anchor=a, stretch=(key == "note"))
        self.pay_tree.pack(fill="x", padx=16)
        self.pay_tree.bind("<Double-1>", lambda e: self.edit_payment())
        for i, p in enumerate(c.get("payments", []), 1):
            self.pay_tree.insert("", "end", iid=str(i - 1),
                                 values=(i, p.get("date", ""), self.money(p.get("amount")),
                                         p.get("method", ""), p.get("note", "")))

        # ---- contractor commissions ---- #
        eh = tk.Frame(d, bg=CARD)
        eh.pack(fill="x", padx=16, pady=(14, 4))
        tk.Label(eh, text="● Commissions from contractors", bg=CARD, fg=AMBER, font=_font(11, True)).pack(side="left")
        ttk.Button(eh, text="＋ Add", command=self.add_commission).pack(side="right")
        ttk.Button(eh, text="Edit", command=self.edit_commission).pack(side="right", padx=(0, 6))
        ttk.Button(eh, text="Delete", command=self.delete_commission).pack(side="right", padx=(0, 6))
        self.com_tree = ttk.Treeview(d, columns=("contractor", "date", "amount", "method", "note"),
                                     show="headings", height=5, selectmode="browse")
        for key, txt, w, a in (("contractor", "Contractor", 150, "w"), ("date", "Date", 96, "center"),
                               ("amount", "Commission", 104, "e"), ("method", "Method", 120, "w"),
                               ("note", "Note", 120, "w")):
            self.com_tree.heading(key, text=txt)
            self.com_tree.column(key, width=w, anchor=a, stretch=(key == "note"))
        self.com_tree.pack(fill="x", padx=16, pady=(0, 14))
        self.com_tree.bind("<Double-1>", lambda e: self.edit_commission())
        for i, e in enumerate(c.get("commissions", [])):
            self.com_tree.insert("", "end", iid=str(i),
                                 values=(e.get("name", ""), e.get("date", ""),
                                         self.money(e.get("amount")), e.get("method", ""), e.get("note", "")))

    # ---- PAYMENTS / CHARTS page ---------------------------------------- #
    def _build_payments_page(self):
        page = tk.Frame(self.content, bg=BG)
        self.pages["payments"] = page
        top = tk.Frame(page, bg=BG)
        top.pack(fill="x", padx=16, pady=(16, 6))
        tk.Label(top, text="Payments by year & month", bg=BG, fg=INK, font=_font(16, True)).pack(side="left")
        tk.Label(top, text="Show", bg=BG, fg=MUTED, font=_font(9)).pack(side="left", padx=(20, 4))
        self.view_sel = ttk.Combobox(top, width=26, state="readonly", font=_font(10),
                                     values=["Client payments + commissions",
                                             "Client payments only",
                                             "Contractor commissions only"])
        self.view_sel.current(0)
        self.view_sel.pack(side="left")
        self.view_sel.bind("<<ComboboxSelected>>", lambda e: self.refresh_charts())
        tk.Label(top, text="Year", bg=BG, fg=MUTED, font=_font(9)).pack(side="left", padx=(16, 4))
        self.chart_year = ttk.Combobox(top, width=8, state="readonly", font=_font(10))
        self.chart_year.pack(side="left")
        self.chart_year.bind("<<ComboboxSelected>>", lambda e: self._draw_month_chart())

        c1 = tk.Frame(page, bg=CARD, highlightbackground=LINE, highlightthickness=1)
        c1.pack(fill="x", padx=16, pady=8)
        tk.Label(c1, text="Total per year", bg=CARD, fg=INK, font=_font(11, True)).pack(anchor="w", padx=14, pady=(12, 0))
        self.year_chart = BarChart(c1, bar_color=ACCENT, height=170)
        self.year_chart.pack(fill="x", padx=10, pady=(4, 6))
        self.year_summary = tk.Label(c1, text="", bg=CARD, fg=MUTED, font=_font(9))
        self.year_summary.pack(anchor="w", padx=14, pady=(0, 12))

        c2 = tk.Frame(page, bg=CARD, highlightbackground=LINE, highlightthickness=1)
        c2.pack(fill="both", expand=True, padx=16, pady=(8, 16))
        self.month_title = tk.Label(c2, text="Monthly", bg=CARD, fg=INK, font=_font(11, True))
        self.month_title.pack(anchor="w", padx=14, pady=(12, 0))
        self.month_chart = BarChart(c2, bar_color=GREEN, height=240)
        self.month_chart.pack(fill="both", expand=True, padx=10, pady=(4, 6))
        self.month_summary = tk.Label(c2, text="", bg=CARD, fg=MUTED, font=_font(9))
        self.month_summary.pack(anchor="w", padx=14, pady=(0, 12))

    def _which(self):
        return {0: "all", 1: "client", 2: "commission"}[self.view_sel.current()]

    def _color(self):
        return {"all": ACCENT, "client": ACCENT, "commission": AMBER}[self._which()]

    def _all_years(self, which):
        yrs = set()
        for c in self.data["clients"]:
            for p in money_items(c, which):
                y, _ = parse_date(p.get("date"))
                if y:
                    yrs.add(y)
        return sorted(yrs)

    def _by_year(self, which):
        agg = {}
        for c in self.data["clients"]:
            for p in money_items(c, which):
                y, _ = parse_date(p.get("date"))
                if y:
                    agg[y] = agg.get(y, 0.0) + to_float(p.get("amount"))
        return agg

    def _by_month(self, year, which):
        months = [0.0] * 12
        for c in self.data["clients"]:
            for p in money_items(c, which):
                y, m = parse_date(p.get("date"))
                if y == year and m:
                    months[m - 1] += to_float(p.get("amount"))
        return months

    def refresh_charts(self):
        which, color = self._which(), self._color()
        years = sorted(set(self._all_years("all")))
        agg = self._by_year(which)
        self.year_chart.set_data([(str(y), agg.get(y, 0.0)) for y in years], color=color)
        ctot = sum(self._by_year("client").values())
        mtot = sum(self._by_year("commission").values())
        self.year_summary.config(text="Client payments: %s      Contractor commissions: %s      Total: %s"
                                 % (self.money(ctot), self.money(mtot), self.money(ctot + mtot)))
        vals = [str(y) for y in years]
        self.chart_year["values"] = vals
        if self.chart_year.get() not in vals:
            self.chart_year.set(vals[-1] if vals else "")
        self._draw_month_chart()

    def _draw_month_chart(self):
        which, color = self._which(), self._color()
        cur = self.chart_year.get()
        if not cur:
            self.month_chart.set_data([]); self.month_summary.config(text=""); return
        year = int(cur)
        months = self._by_month(year, which)
        self.month_chart.set_data([(MONTHS[i], months[i]) for i in range(12)], color=color)
        total = sum(months)
        best = max(range(12), key=lambda i: months[i]) if total > 0 else None
        kind = {"all": "all", "client": "client payments", "commission": "commissions"}[which]
        self.month_title.config(text="Monthly (%s) — %d" % (kind, year))
        txt = "Total %d: %s" % (year, self.money(total))
        if best is not None and months[best] > 0:
            txt += "      Best month: %s (%s)" % (MONTHS[best], self.money(months[best]))
        self.month_summary.config(text=txt)

    # ---- header totals -------------------------------------------------- #
    def update_header(self):
        cl = self.data["clients"]
        rem = sum(remaining_of(c) for c in cl)
        rec = sum(total_received_of(c) for c in cl)
        self.header_stat.config(text="%d clients   ·   Received %s   ·   Outstanding %s"
                                % (len(cl), self.money(rec), self.money(rem)))

    # ---- client actions ------------------------------------------------- #
    def add_client(self):
        dlg = ClientDialog(self, self.data["payment_methods"], self.currency)
        if not dlg.result:
            return
        if self._client_by_name(dlg.result["name"]):
            messagebox.showwarning("Duplicate", "A client with that name already exists.")
            return
        c = {"name": dlg.result["name"], "contract_value": dlg.result["contract_value"],
             "year": dlg.result.get("year"), "payments": [], "commissions": []}
        if dlg.result.get("first_payment"):
            c["payments"].append(dlg.result["first_payment"])
        self.data["clients"].append(c)
        self.selected_client = c
        self.save(silent=True)
        self.show_page("clients")
        self.refresh_client_tree()
        iid = "client::%s" % c["name"]
        if self.ctree.exists(iid):
            self.ctree.see(iid)
            self.ctree.selection_set(iid)
        self.on_select_client()

    def edit_client(self):
        c = self.selected_client
        if not c:
            return
        dlg = ClientDialog(self, self.data["payment_methods"], self.currency, client=c, title="Edit Client")
        if not dlg.result:
            return
        nn = dlg.result["name"]
        if nn != c["name"] and self._client_by_name(nn):
            messagebox.showwarning("Duplicate", "A client with that name already exists.")
            return
        c["name"], c["contract_value"], c["year"] = nn, dlg.result["contract_value"], dlg.result.get("year")
        self.save(silent=True)
        self.refresh_client_tree()
        self._build_detail(c)

    def delete_client(self):
        c = self.selected_client
        if not c:
            return
        if not messagebox.askyesno("Delete client", "Delete '%s' and all its records?" % c["name"]):
            return
        self.data["clients"].remove(c)
        self.selected_client = None
        self.save(silent=True)
        self.refresh_client_tree()
        self._build_detail_empty()

    # ---- payment (from client) actions --------------------------------- #
    def add_payment(self):
        c = self.selected_client
        if not c:
            return
        dlg = PaymentDialog(self, self.data["payment_methods"], self.currency)
        if dlg.result:
            c.setdefault("payments", []).append(dlg.result)
            self._after_change(c)

    def _sel_idx(self, tree, what):
        sel = tree.selection()
        if not sel:
            messagebox.showinfo("Select a row", "Select a %s in the table first." % what)
            return None
        return int(sel[0])

    def edit_payment(self):
        c = self.selected_client
        if not c:
            return
        idx = self._sel_idx(self.pay_tree, "payment")
        if idx is None:
            return
        dlg = PaymentDialog(self, self.data["payment_methods"], self.currency,
                            payment=c["payments"][idx], title="Edit Payment from Client")
        if dlg.result:
            c["payments"][idx] = dlg.result
            self._after_change(c)

    def delete_payment(self):
        c = self.selected_client
        if not c:
            return
        idx = self._sel_idx(self.pay_tree, "payment")
        if idx is None:
            return
        if messagebox.askyesno("Delete payment", "Delete the selected payment?"):
            del c["payments"][idx]
            self._after_change(c)

    # ---- commission (from contractor) actions -------------------------- #
    def add_commission(self):
        c = self.selected_client
        if not c:
            return
        dlg = CommissionDialog(self, self.data["payment_methods"], self.currency)
        if dlg.result:
            c.setdefault("commissions", []).append(dlg.result)
            self._after_change(c)

    def edit_commission(self):
        c = self.selected_client
        if not c:
            return
        idx = self._sel_idx(self.com_tree, "commission")
        if idx is None:
            return
        dlg = CommissionDialog(self, self.data["payment_methods"], self.currency,
                               item=c["commissions"][idx], title="Edit Contractor Commission")
        if dlg.result:
            c["commissions"][idx] = dlg.result
            self._after_change(c)

    def delete_commission(self):
        c = self.selected_client
        if not c:
            return
        idx = self._sel_idx(self.com_tree, "commission")
        if idx is None:
            return
        if messagebox.askyesno("Delete commission", "Delete the selected commission?"):
            del c["commissions"][idx]
            self._after_change(c)

    def _after_change(self, c):
        self.save(silent=True)
        self.refresh_client_tree()
        self._build_detail(c)
        self.update_header()

    # ---- methods / settings / password --------------------------------- #
    def manage_methods(self):
        dlg = MethodsDialog(self, self.data["payment_methods"])
        if dlg.result is not None:
            self.data["payment_methods"] = dlg.result
            self.save(silent=True)
            if self.selected_client:
                self._build_detail(self.selected_client)

    def change_password(self):
        dlg = PasswordDialog(self, mode="set")
        if dlg.result:
            self.data["password"] = hash_password(dlg.result[1])
            self.save(silent=True)
            messagebox.showinfo("Password changed", "Your password has been updated.")

    def open_settings(self):
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Set currency symbol…", command=self.set_currency)
        menu.add_command(label="Export to Excel…", command=self.export_excel)
        menu.add_command(label="Restore data from file…", command=self.restore_from_file)
        menu.add_command(label="Open data folder", command=self.open_data_folder)
        menu.add_separator()
        menu.add_command(label="About", command=self.show_about)
        try:
            menu.tk_popup(self.winfo_pointerx(), self.winfo_pointery())
        finally:
            menu.grab_release()

    def restore_from_file(self):
        """Load clients/methods/currency from a chosen xplan_data.json.
        Keeps the current password so the lock stays in place."""
        path = filedialog.askopenfilename(title="Restore data from file",
                                          filetypes=[("XPLAN data", "*.json"), ("All files", "*.*")])
        if not path:
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                incoming = json.load(f)
        except Exception as e:
            messagebox.showerror("Restore failed", "Could not read that file:\n%s" % e)
            return
        if "clients" not in incoming:
            messagebox.showwarning("Not an XPLAN file", "That file has no 'clients' data.")
            return
        if not messagebox.askyesno("Restore data",
                                   "Replace all current clients with the %d client(s) in that file?"
                                   % len(incoming.get("clients", []))):
            return
        keep_pw = self.data.get("password")
        self.data["clients"] = incoming.get("clients", [])
        self.data["payment_methods"] = incoming.get("payment_methods", self.data["payment_methods"])
        self.data["currency"] = incoming.get("currency", self.data["currency"])
        self.data["password"] = keep_pw
        self.data = load_data_normalize(self.data)
        self.selected_client = None
        self.save(silent=True)
        self.refresh_client_tree()
        self.refresh_charts()
        self._build_detail_empty()
        messagebox.showinfo("Restored", "Loaded %d client(s)." % len(self.data["clients"]))

    def set_currency(self):
        val = simpledialog.askstring("Currency", "Currency symbol (e.g. €, $, L, ALL):",
                                     initialvalue=self.currency, parent=self)
        if val:
            self.data["currency"] = val.strip()
            self.save(silent=True)
            self.refresh_client_tree()
            self.refresh_charts()
            if self.selected_client:
                self._build_detail(self.selected_client)

    def save(self, silent=False):
        try:
            save_data(self.data)
        except Exception as e:
            messagebox.showerror("Save failed", str(e))
            return
        self.update_header()

    def on_close(self):
        try:
            self.save(silent=True)
        finally:
            self.destroy()

    def open_data_folder(self):
        folder = DATA_DIR
        try:
            if sys.platform.startswith("win"):
                os.startfile(folder)             # noqa
            elif sys.platform == "darwin":
                os.system("open '%s'" % folder)
            else:
                os.system("xdg-open '%s'" % folder)
        except Exception:
            messagebox.showinfo("Data folder", folder)

    def show_about(self):
        messagebox.showinfo("About XPLAN",
                            "XPLAN — Client & Payment Manager\n\n"
                            "Password-protected. Data stored locally in:\n%s\n\n"
                            "Backups are kept in the 'backups' folder.\n\n"
                            "Payments from client vs commissions from contractors.\n"
                            "Vlera = Contract · Të Dhëna = Paid · Të Mbetura = Remaining" % DATA_FILE)

    # ---- Excel / CSV ---------------------------------------------------- #
    def export_excel(self):
        try:
            import openpyxl  # noqa
        except ImportError:
            if messagebox.askyesno("openpyxl not installed",
                                   "Excel export needs 'openpyxl' (not installed).\n\nExport as CSV instead?"):
                self._export_csv()
            else:
                messagebox.showinfo("Install openpyxl", "Run in Command Prompt:\n\n    pip install openpyxl")
            return
        path = filedialog.asksaveasfilename(title="Export to Excel", defaultextension=".xlsx",
                                            initialfile="XPLAN_clients.xlsx",
                                            filetypes=[("Excel workbook", "*.xlsx")])
        if not path:
            return
        try:
            self._write_xlsx(path)
        except Exception as e:
            messagebox.showerror("Export failed", str(e))
            return
        messagebox.showinfo("Exported", "Saved:\n%s" % path)

    def _write_xlsx(self, path):
        import openpyxl
        from openpyxl.styles import Font
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "TOTALI"
        bold = Font(bold=True)
        ws.append(["YEAR", "KLIENTI", "VLERA E KONTRATES", "PAID BY CLIENT",
                   "CONTRACTOR COMMISSIONS", "TOTAL RECEIVED", "TE MBETURA"])
        for cell in ws[1]:
            cell.font = bold
        for c in sorted(self.data["clients"], key=lambda x: (client_year(x) or 0, x["name"].lower())):
            ws.append([client_year(c) or "", c["name"], to_float(c.get("contract_value")),
                       paid_of(c), commissions_of(c), total_received_of(c), remaining_of(c)])
        ws.append([])
        ws.append(["", "TOTAL",
                   sum(to_float(c.get("contract_value")) for c in self.data["clients"]),
                   sum(paid_of(c) for c in self.data["clients"]),
                   sum(commissions_of(c) for c in self.data["clients"]),
                   sum(total_received_of(c) for c in self.data["clients"]),
                   sum(remaining_of(c) for c in self.data["clients"])])
        for cell in ws[ws.max_row]:
            cell.font = bold
        for col, wdt in zip("ABCDEFG", (8, 26, 16, 14, 18, 15, 13)):
            ws.column_dimensions[col].width = wdt

        pm = wb.create_sheet("PAGESAT")
        pm.append(["YEAR", "MONTH", "TYPE", "AMOUNT"])
        for cell in pm[1]:
            cell.font = bold
        agg = {}
        for c in self.data["clients"]:
            for p in c.get("payments", []):
                y, m = parse_date(p.get("date"))
                if y and m:
                    agg[(y, m, "Client payment")] = agg.get((y, m, "Client payment"), 0.0) + to_float(p.get("amount"))
            for e in c.get("commissions", []):
                y, m = parse_date(e.get("date"))
                if y and m:
                    agg[(y, m, "Commission")] = agg.get((y, m, "Commission"), 0.0) + to_float(e.get("amount"))
        for (y, m, t) in sorted(agg):
            pm.append([y, MONTHS[m - 1], t, agg[(y, m, t)]])
        for col, wdt in zip("ABCD", (8, 10, 16, 14)):
            pm.column_dimensions[col].width = wdt

        used = {"TOTALI", "PAGESAT"}
        for c in self.data["clients"]:
            title = (c["name"] or "Client")[:28]
            base, n = title, 1
            while title in used:
                n += 1
                title = "%s_%d" % (base[:26], n)
            used.add(title)
            s = wb.create_sheet(title)
            s.append([c["name"], "", "", "Contract:", to_float(c.get("contract_value"))])
            s["A1"].font = bold
            s.append(["CATEGORY", "NAME", "DATE", "AMOUNT", "METHOD", "NOTE"])
            for cell in s[2]:
                cell.font = bold
            for p in c.get("payments", []):
                s.append(["Client payment", c["name"], p.get("date", ""), to_float(p.get("amount")),
                          p.get("method", ""), p.get("note", "")])
            for e in c.get("commissions", []):
                s.append(["Contractor commission", e.get("name", ""), e.get("date", ""),
                          to_float(e.get("amount")), e.get("method", ""), e.get("note", "")])
            s.append([])
            s.append(["", "PAID BY CLIENT", "", paid_of(c)])
            s.append(["", "COMMISSIONS", "", commissions_of(c)])
            s.append(["", "TOTAL RECEIVED", "", total_received_of(c)])
            s.append(["", "REMAINING", "", remaining_of(c)])
            for col, wdt in zip("ABCDEF", (22, 20, 12, 12, 14, 18)):
                s.column_dimensions[col].width = wdt
        wb.save(path)

    def _export_csv(self):
        path = filedialog.asksaveasfilename(title="Export as CSV", defaultextension=".csv",
                                            initialfile="XPLAN_payments.csv",
                                            filetypes=[("CSV file", "*.csv")])
        if not path:
            return
        try:
            with open(path, "w", newline="", encoding="utf-8-sig") as f:
                w = csv.writer(f)
                w.writerow(["Year", "Client", "Contract", "Category", "Name", "Date", "Amount", "Method", "Note"])
                for c in self.data["clients"]:
                    yr = client_year(c) or ""
                    for p in c.get("payments", []):
                        w.writerow([yr, c["name"], to_float(c.get("contract_value")), "Client payment", c["name"],
                                    p.get("date", ""), to_float(p.get("amount")), p.get("method", ""), p.get("note", "")])
                    for e in c.get("commissions", []):
                        w.writerow([yr, c["name"], to_float(c.get("contract_value")), "Contractor commission",
                                    e.get("name", ""), e.get("date", ""), to_float(e.get("amount")),
                                    e.get("method", ""), e.get("note", "")])
                    if not c.get("payments") and not c.get("commissions"):
                        w.writerow([yr, c["name"], to_float(c.get("contract_value")), "", "", "", "", "", ""])
            messagebox.showinfo("Exported", "Saved:\n%s" % path)
        except Exception as e:
            messagebox.showerror("Export failed", str(e))


def main():
    app = XplanApp()
    if getattr(app, "ok", False):
        app.mainloop()


if __name__ == "__main__":
    main()
