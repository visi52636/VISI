#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
XPLAN - Client & Payment Manager
=================================
A local, password-protected desktop program (Windows / macOS / Linux) for
tracking architecture / design studio clients and their payments.

Built from the "PGS_KLNT" Excel workbook. Terminology kept close to the
original sheet:

    KLIENTI            -> Client
    VLERA E KONTRATES  -> Contract Value
    PAGESA 1..N        -> Payment 1..N
    DATA E PAGESES     -> Payment Date
    TE DHENA           -> Paid (total received)
    TE MBETURA         -> Remaining (balance)
    PERMBLEDHJE/TOTALI -> Summary

Features
    - Password lock on open (PBKDF2-SHA256, stored salted in the data file).
    - Clients grouped by year (collapsible).
    - Payments & Charts section: totals by year and by month, drawn as bar
      charts (no external libraries needed).
    - Minimalist, modern interface.
    - Add clients, add/edit/delete payments, manage payment methods.
    - Local JSON storage with automatic timestamped backups.
    - Export to Excel (openpyxl, optional) or CSV.

Core app uses ONLY the Python standard library, so it runs on any standard
Python installation with no extra downloads. (Excel export uses 'openpyxl'
if present.)
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
BG       = "#f4f5f7"   # app background
CARD     = "#ffffff"   # cards / panels
INK      = "#1f2933"   # primary text
MUTED    = "#7b8794"   # secondary text
ACCENT   = "#3b82f6"   # primary accent (blue)
ACCENT_DK= "#2563eb"
GREEN    = "#15a34a"
RED      = "#dc2626"
LINE     = "#e4e7eb"   # hairline borders
SIDEBAR  = "#111827"   # dark sidebar
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
def app_dir():
    if getattr(sys, "frozen", False):          # PyInstaller .exe
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


DATA_FILE = os.path.join(app_dir(), "xplan_data.json")
BACKUP_DIR = os.path.join(app_dir(), "backups")

DEFAULT_DATA = {
    "currency": "€",
    "payment_methods": ["Cash", "Bank Transfer", "Card", "Other"],
    "password": None,          # {"salt": b64, "hash": b64}
    "clients": [],
}


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
    data.setdefault("currency", "€")
    data.setdefault("payment_methods", ["Cash", "Bank Transfer", "Card", "Other"])
    data.setdefault("password", None)
    data.setdefault("clients", [])
    for c in data["clients"]:
        c.setdefault("name", "Unnamed")
        c.setdefault("contract_value", 0.0)
        c.setdefault("payments", [])
        c.setdefault("extras", [])
        c.setdefault("year", None)
    return data


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
#  Password helpers (PBKDF2-SHA256)
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
    """Return (year, month) from a stored date string, or (None, None)."""
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


def extras_of(c):
    return sum(to_float(e.get("amount")) for e in c.get("extras", []))


def remaining_of(c):
    return to_float(c.get("contract_value")) - paid_of(c)


def total_received_of(c):
    return paid_of(c) + extras_of(c)


def client_year(c):
    """Year a client belongs to: explicit field, else earliest payment year."""
    if c.get("year"):
        return int(c["year"])
    yrs = [parse_date(p.get("date"))[0] for p in c.get("payments", [])]
    yrs = [y for y in yrs if y]
    return min(yrs) if yrs else None


def today_str():
    return datetime.date.today().strftime("%d/%m/%Y")


def iter_money_items(c, include_extras=True):
    items = list(c.get("payments", []))
    if include_extras:
        items += c.get("extras", [])
    return items


# --------------------------------------------------------------------------- #
#  Bar chart widget (pure tkinter Canvas)
# --------------------------------------------------------------------------- #
class BarChart(tk.Canvas):
    def __init__(self, parent, money_fmt, bar_color=ACCENT, **kw):
        super().__init__(parent, bg=CARD, highlightthickness=0, **kw)
        self.money_fmt = money_fmt
        self.bar_color = bar_color
        self.pairs = []          # list of (label, value)
        self.bind("<Configure>", lambda e: self.redraw())

    def set_data(self, pairs):
        self.pairs = pairs
        self.redraw()

    def redraw(self):
        self.delete("all")
        w = self.winfo_width()
        h = self.winfo_height()
        if w < 40 or h < 40:
            return
        pad_l, pad_r, pad_t, pad_b = 54, 16, 22, 34
        plot_w = w - pad_l - pad_r
        plot_h = h - pad_t - pad_b
        if not self.pairs:
            self.create_text(w / 2, h / 2, text="No dated payments to show",
                             fill=MUTED, font=_font(10))
            return
        vmax = max((v for _, v in self.pairs), default=0)
        if vmax <= 0:
            self.create_text(w / 2, h / 2, text="No payments in this period",
                             fill=MUTED, font=_font(10))
            return
        # nice axis max
        step = _nice_step(vmax)
        axis_max = step * (int(vmax / step) + 1)
        # gridlines + y labels
        lines = 4
        for i in range(lines + 1):
            val = axis_max * i / lines
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
            x0, x1 = cx - bw / 2, cx + bw / 2
            y0, y1 = pad_t + plot_h - bh, pad_t + plot_h
            if bh > 0:
                self.create_rectangle(x0, y0, x1, y1, fill=self.bar_color,
                                      outline=self.bar_color)
                self.create_text(cx, y0 - 8, text=self._short(val),
                                 fill=INK, font=_font(8, True))
            self.create_text(cx, pad_t + plot_h + 14, text=str(label),
                             fill=MUTED, font=_font(8))

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
    def __init__(self, parent, methods, currency, payment=None, title="Add Payment"):
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


class ExtraDialog(_BaseDialog):
    def __init__(self, parent, methods, currency, extra=None, title="Add Extra Item"):
        super().__init__(parent, title)
        extra = extra or {}
        f = _font(10)
        ttk.Label(self, text="Item name").grid(row=0, column=0, sticky="w", pady=5)
        self.name = ttk.Entry(self, width=26, font=f)
        self.name.grid(row=0, column=1, pady=5)
        self.name.insert(0, extra.get("name") or "")

        ttk.Label(self, text="Amount (%s)" % currency).grid(row=1, column=0, sticky="w", pady=5)
        self.amount = ttk.Entry(self, width=26, font=f)
        self.amount.grid(row=1, column=1, pady=5)
        self.amount.insert(0, "" if extra.get("amount") in (None, "") else str(extra.get("amount")))

        ttk.Label(self, text="Date (dd/mm/yyyy)").grid(row=2, column=0, sticky="w", pady=5)
        self.date = ttk.Entry(self, width=26, font=f)
        self.date.grid(row=2, column=1, pady=5)
        self.date.insert(0, extra.get("date") or today_str())

        ttk.Label(self, text="Method").grid(row=3, column=0, sticky="w", pady=5)
        self.method = ttk.Combobox(self, width=23, values=methods, state="readonly", font=f)
        self.method.grid(row=3, column=1, pady=5)
        self.method.set(extra.get("method") if extra.get("method") in methods else (methods[0] if methods else ""))

        btns = ttk.Frame(self)
        btns.grid(row=4, column=0, columnspan=2, pady=(14, 0), sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="OK", style="Accent.TButton", command=self._ok).pack(side="right")
        self.name.focus_set()
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self.destroy())
        self._finish()

    def _ok(self):
        if not self.name.get().strip():
            messagebox.showwarning("Missing name", "Please enter a name.", parent=self)
            return
        amt = to_float(self.amount.get(), None)
        if amt is None:
            messagebox.showwarning("Invalid amount", "Please enter a number.", parent=self)
            return
        self.result = {"name": self.name.get().strip(), "amount": amt,
                       "date": self.date.get().strip(), "method": self.method.get().strip(), "note": ""}
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
                messagebox.showwarning("Invalid year", "Year must be a number like 2025.", parent=self)
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
    """Login (mode='login') or set a new password (mode='set')."""
    def __init__(self, parent, mode, verify_record=None):
        super().__init__(parent)
        self.mode = mode
        self.verify_record = verify_record
        self.result = None
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
                self.msg.config(text="Use at least 4 characters.")
                return
            if pw != self.pw2.get():
                self.msg.config(text="Passwords do not match.")
                return
            self.result = ("set", pw)
            self.destroy()
        else:
            if verify_password(pw, self.verify_record):
                self.result = ("ok", pw)
                self.destroy()
            else:
                self.msg.config(text="Wrong password.")
                self.pw1.delete(0, "end")

    def _cancel(self):
        self.result = None
        self.destroy()


# --------------------------------------------------------------------------- #
#  Main application
# --------------------------------------------------------------------------- #
class XplanApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.data = load_data()
        make_backup("start")
        self.ok = False
        self.selected_client = None
        self.current_page = "clients"

        self.title(APP_TITLE)
        self.geometry("1120x700")
        self.minsize(960, 600)
        self.configure(bg=BG)
        self._setup_style()

        # Password gate -------------------------------------------------- #
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

    # ---- style ---------------------------------------------------------- #
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
        st.configure("Card.TLabel", background=CARD, foreground=INK)
        st.configure("Muted.TLabel", background=CARD, foreground=MUTED)
        st.configure("H1.TLabel", background=BG, foreground=INK, font=_font(16, True))
        st.configure("H2.TLabel", background=CARD, foreground=INK, font=_font(12, True))
        st.configure("Stat.TLabel", background=CARD, foreground=INK, font=_font(18, True))
        st.configure("TButton", padding=(12, 7), relief="flat",
                     background="#e8eaed", foreground=INK, font=_font(10))
        st.map("TButton", background=[("active", "#dfe2e6")])
        st.configure("Accent.TButton", background=ACCENT, foreground="#ffffff",
                     padding=(14, 8), font=_font(10, True))
        st.map("Accent.TButton", background=[("active", ACCENT_DK)])
        st.configure("TEntry", fieldbackground=CARD, bordercolor=LINE, relief="flat")
        st.configure("TCombobox", fieldbackground=CARD, relief="flat")
        # Treeview
        st.configure("Treeview", background=CARD, fieldbackground=CARD, foreground=INK,
                     rowheight=26, borderwidth=0, font=_font(10))
        st.configure("Treeview.Heading", background=BG, foreground=MUTED,
                     relief="flat", font=_font(9, True))
        st.map("Treeview", background=[("selected", "#e6efff")], foreground=[("selected", INK)])

    # ---- auth ----------------------------------------------------------- #
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

    # ---- currency / format --------------------------------------------- #
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
        tk.Label(bar, text="Client & Payment Manager", bg=CARD, fg=MUTED,
                 font=_font(10)).pack(side="left")
        self.header_stat = tk.Label(bar, text="", bg=CARD, fg=MUTED, font=_font(10))
        self.header_stat.pack(side="right", padx=20)
        ttk.Button(bar, text="＋  Add Client", style="Accent.TButton",
                   command=self.add_client).pack(side="right", padx=(0, 6), pady=12)

    # ---- sidebar -------------------------------------------------------- #
    def _build_sidebar(self):
        self._body = tk.Frame(self, bg=BG)
        self._body.pack(side="top", fill="both", expand=True)

        side = tk.Frame(self._body, bg=SIDEBAR, width=188)
        side.pack(side="left", fill="y")
        side.pack_propagate(False)
        self.nav_buttons = {}
        for key, label, icon in (("clients", "Clients", "👥"),
                                 ("payments", "Payments & Charts", "📈")):
            b = tk.Label(side, text="  %s   %s" % (icon, label), bg=SIDEBAR, fg=SIDE_TXT,
                         font=_font(11), anchor="w", padx=12, pady=12, cursor="hand2")
            b.pack(fill="x", pady=(6 if key == "clients" else 0, 0), padx=0)
            b.bind("<Button-1>", lambda e, k=key: self.show_page(k))
            self.nav_buttons[key] = b

        # bottom actions
        bottom = tk.Frame(side, bg=SIDEBAR)
        bottom.pack(side="bottom", fill="x", pady=10)
        for label, cmd in (("Payment Methods", self.manage_methods),
                           ("Export to Excel", self.export_excel),
                           ("Change Password", self.change_password),
                           ("Settings", self.open_settings)):
            tk.Label(bottom, text="  "+label, bg=SIDEBAR, fg="#8a94a6", font=_font(9),
                     anchor="w", padx=12, pady=6, cursor="hand2").pack(fill="x")\
                .bind("<Button-1>", lambda e, c=cmd: c())

    def _highlight_nav(self):
        for k, b in self.nav_buttons.items():
            if k == self.current_page:
                b.configure(bg=SIDE_SEL, fg="#ffffff")
            else:
                b.configure(bg=SIDEBAR, fg=SIDE_TXT)

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
        se = ttk.Entry(ctrl, textvariable=self.search_var, width=18, font=_font(10))
        se.pack(side="right")
        tk.Label(ctrl, text="Search", bg=CARD, fg=MUTED, font=_font(9)).pack(side="right", padx=(0, 6))

        self.ctree = ttk.Treeview(left, columns=("contract", "paid", "remaining"),
                                  show="tree headings", selectmode="browse")
        self.ctree.heading("#0", text="Client")
        self.ctree.column("#0", width=200, stretch=True)
        for key, txt, w in (("contract", "Contract", 90), ("paid", "Paid", 90),
                            ("remaining", "Remaining", 90)):
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
        # group clients by year
        groups = {}
        for c in self.data["clients"]:
            if q and q not in c["name"].lower():
                continue
            y = client_year(c)
            groups.setdefault(y, []).append(c)
        # order years newest first; None ("Unspecified") last
        def order(y):
            return (-1 if y is None else 0, -(y or 0))
        for y in sorted(groups.keys(), key=order):
            label = str(y) if y else "Unspecified year"
            gclients = sorted(groups[y], key=lambda c: c["name"].lower())
            gcontract = sum(to_float(c.get("contract_value")) for c in gclients)
            gpaid = sum(paid_of(c) for c in gclients)
            grem = sum(remaining_of(c) for c in gclients)
            parent = self.ctree.insert("", "end", iid="year::%s" % label, open=True,
                                       text="%s   (%d)" % (label, len(gclients)),
                                       values=(self.money(gcontract), self.money(gpaid), self.money(grem)),
                                       tags=("year",))
            for c in gclients:
                rem = remaining_of(c)
                tag = "owing" if rem > 0 else "paidoff"
                self.ctree.insert(parent, "end", iid="client::%s" % c["name"],
                                  text="   " + c["name"],
                                  values=(self.money(c.get("contract_value")),
                                          self.money(paid_of(c)), self.money(rem)),
                                  tags=(tag,))
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
        tk.Label(self.detail, text="Select a client,\nor use ＋ Add Client.",
                 bg=CARD, fg=MUTED, font=_font(13), justify="center").place(relx=0.5, rely=0.45, anchor="center")

    def _build_detail(self, c):
        self._clear_detail()
        d = self.detail
        head = tk.Frame(d, bg=CARD)
        head.pack(fill="x", padx=16, pady=(14, 2))
        tk.Label(head, text=c["name"], bg=CARD, fg=INK, font=_font(15, True)).pack(side="left")
        y = client_year(c)
        tk.Label(head, text="  ·  %s" % (y or "year not set"), bg=CARD, fg=MUTED, font=_font(10)).pack(side="left")
        ttk.Button(head, text="Delete", command=self.delete_client).pack(side="right")
        ttk.Button(head, text="Edit", command=self.edit_client).pack(side="right", padx=(0, 6))

        info = tk.Frame(d, bg=CARD)
        info.pack(fill="x", padx=12, pady=6)
        contract, paid, rem, extras = (to_float(c.get("contract_value")), paid_of(c),
                                       remaining_of(c), extras_of(c))
        cells = [("Contract (Vlera)", self.money(contract), INK),
                 ("Paid (Të Dhëna)", self.money(paid), GREEN),
                 ("Remaining (Të Mbetura)", self.money(rem), RED if rem > 0 else GREEN)]
        if extras:
            cells.append(("Extras", self.money(extras), INK))
        for i, (lbl, val, fg) in enumerate(cells):
            card = tk.Frame(info, bg=BG)
            card.grid(row=0, column=i, padx=4, pady=4, sticky="nsew")
            info.columnconfigure(i, weight=1)
            tk.Label(card, text=lbl, bg=BG, fg=MUTED, font=_font(9)).pack(anchor="w", padx=12, pady=(10, 0))
            tk.Label(card, text=val, bg=BG, fg=fg, font=_font(16, True)).pack(anchor="w", padx=12, pady=(0, 10))

        ph = tk.Frame(d, bg=CARD)
        ph.pack(fill="x", padx=16, pady=(12, 4))
        tk.Label(ph, text="Payments", bg=CARD, fg=INK, font=_font(11, True)).pack(side="left")
        ttk.Button(ph, text="＋ Add Payment", style="Accent.TButton", command=self.add_payment).pack(side="right")
        ttk.Button(ph, text="Edit", command=self.edit_payment).pack(side="right", padx=(0, 6))
        ttk.Button(ph, text="Delete", command=self.delete_payment).pack(side="right", padx=(0, 6))

        self.pay_tree = ttk.Treeview(d, columns=("no", "date", "amount", "method", "note"),
                                     show="headings", height=7, selectmode="browse")
        for key, txt, w, a in (("no", "#", 34, "center"), ("date", "Date", 96, "center"),
                               ("amount", "Amount", 104, "e"), ("method", "Method", 120, "w"),
                               ("note", "Note", 160, "w")):
            self.pay_tree.heading(key, text=txt)
            self.pay_tree.column(key, width=w, anchor=a, stretch=(key == "note"))
        self.pay_tree.pack(fill="both", expand=True, padx=16)
        self.pay_tree.bind("<Double-1>", lambda e: self.edit_payment())
        for i, p in enumerate(c.get("payments", []), 1):
            self.pay_tree.insert("", "end", iid=str(i - 1),
                                 values=(i, p.get("date", ""), self.money(p.get("amount")),
                                         p.get("method", ""), p.get("note", "")))

        eh = tk.Frame(d, bg=CARD)
        eh.pack(fill="x", padx=16, pady=(12, 4))
        tk.Label(eh, text="Extra items", bg=CARD, fg=INK, font=_font(11, True)).pack(side="left")
        ttk.Button(eh, text="＋ Add Extra", command=self.add_extra).pack(side="right")
        ttk.Button(eh, text="Delete", command=self.delete_extra).pack(side="right", padx=(0, 6))
        self.ex_tree = ttk.Treeview(d, columns=("name", "date", "amount", "method"),
                                    show="headings", height=4, selectmode="browse")
        for key, txt, w, a in (("name", "Item", 190, "w"), ("date", "Date", 96, "center"),
                               ("amount", "Amount", 104, "e"), ("method", "Method", 120, "w")):
            self.ex_tree.heading(key, text=txt)
            self.ex_tree.column(key, width=w, anchor=a, stretch=(key == "name"))
        self.ex_tree.pack(fill="both", expand=False, padx=16, pady=(0, 14))
        for i, e in enumerate(c.get("extras", [])):
            self.ex_tree.insert("", "end", iid=str(i),
                                values=(e.get("name", ""), e.get("date", ""),
                                        self.money(e.get("amount")), e.get("method", "")))

    # ---- PAYMENTS / CHARTS page ---------------------------------------- #
    def _build_payments_page(self):
        page = tk.Frame(self.content, bg=BG)
        self.pages["payments"] = page

        # top controls
        top = tk.Frame(page, bg=BG)
        top.pack(fill="x", padx=16, pady=(16, 6))
        tk.Label(top, text="Payments by year & month", bg=BG, fg=INK, font=_font(16, True)).pack(side="left")
        tk.Label(top, text="Year", bg=BG, fg=MUTED, font=_font(9)).pack(side="left", padx=(20, 4))
        self.chart_year = ttk.Combobox(top, width=8, state="readonly", font=_font(10))
        self.chart_year.pack(side="left")
        self.chart_year.bind("<<ComboboxSelected>>", lambda e: self._draw_month_chart())
        self.inc_extras = tk.BooleanVar(value=True)
        ttk.Checkbutton(top, text="Include extras", variable=self.inc_extras,
                        command=self.refresh_charts).pack(side="left", padx=16)

        # yearly chart card
        c1 = tk.Frame(page, bg=CARD, highlightbackground=LINE, highlightthickness=1)
        c1.pack(fill="x", padx=16, pady=8)
        tk.Label(c1, text="Total received per year", bg=CARD, fg=INK, font=_font(11, True)).pack(anchor="w", padx=14, pady=(12, 0))
        self.year_chart = BarChart(c1, self.money, bar_color=ACCENT, height=170)
        self.year_chart.pack(fill="x", padx=10, pady=(4, 12))

        # monthly chart card
        c2 = tk.Frame(page, bg=CARD, highlightbackground=LINE, highlightthickness=1)
        c2.pack(fill="both", expand=True, padx=16, pady=(8, 16))
        self.month_title = tk.Label(c2, text="Monthly payments", bg=CARD, fg=INK, font=_font(11, True))
        self.month_title.pack(anchor="w", padx=14, pady=(12, 0))
        self.month_chart = BarChart(c2, self.money, bar_color="#22c55e", height=240)
        self.month_chart.pack(fill="both", expand=True, padx=10, pady=(4, 6))
        self.month_summary = tk.Label(c2, text="", bg=CARD, fg=MUTED, font=_font(9))
        self.month_summary.pack(anchor="w", padx=14, pady=(0, 12))

    def _all_years(self):
        yrs = set()
        for c in self.data["clients"]:
            for p in iter_money_items(c, self.inc_extras.get()):
                y, _ = parse_date(p.get("date"))
                if y:
                    yrs.add(y)
        return sorted(yrs)

    def payments_by_year(self):
        agg = {}
        for c in self.data["clients"]:
            for p in iter_money_items(c, self.inc_extras.get()):
                y, _ = parse_date(p.get("date"))
                if y:
                    agg[y] = agg.get(y, 0.0) + to_float(p.get("amount"))
        return agg

    def payments_by_month(self, year):
        months = [0.0] * 12
        for c in self.data["clients"]:
            for p in iter_money_items(c, self.inc_extras.get()):
                y, m = parse_date(p.get("date"))
                if y == year and m:
                    months[m - 1] += to_float(p.get("amount"))
        return months

    def refresh_charts(self):
        years = self._all_years()
        agg = self.payments_by_year()
        self.year_chart.set_data([(str(y), agg.get(y, 0.0)) for y in years])
        # year selector
        vals = [str(y) for y in years]
        self.chart_year["values"] = vals
        cur = self.chart_year.get()
        if cur not in vals:
            cur = vals[-1] if vals else ""
            self.chart_year.set(cur)
        self._draw_month_chart()

    def _draw_month_chart(self):
        cur = self.chart_year.get()
        if not cur:
            self.month_chart.set_data([])
            self.month_summary.config(text="")
            self.month_title.config(text="Monthly payments")
            return
        year = int(cur)
        months = self.payments_by_month(year)
        self.month_chart.set_data([(MONTHS[i], months[i]) for i in range(12)])
        total = sum(months)
        best = max(range(12), key=lambda i: months[i]) if total > 0 else None
        self.month_title.config(text="Monthly payments — %d" % year)
        txt = "Total %d: %s" % (year, self.money(total))
        if best is not None and months[best] > 0:
            txt += "     Best month: %s (%s)" % (MONTHS[best], self.money(months[best]))
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
             "year": dlg.result.get("year"), "payments": [], "extras": []}
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
        if not messagebox.askyesno("Delete client", "Delete '%s' and all its payments?" % c["name"]):
            return
        self.data["clients"].remove(c)
        self.selected_client = None
        self.save(silent=True)
        self.refresh_client_tree()
        self._build_detail_empty()

    # ---- payment actions ------------------------------------------------ #
    def add_payment(self):
        c = self.selected_client
        if not c:
            return
        dlg = PaymentDialog(self, self.data["payment_methods"], self.currency)
        if dlg.result:
            c.setdefault("payments", []).append(dlg.result)
            self._after_change(c)

    def _sel_pay_idx(self):
        sel = self.pay_tree.selection()
        if not sel:
            messagebox.showinfo("Select a payment", "Select a payment in the table first.")
            return None
        return int(sel[0])

    def edit_payment(self):
        c = self.selected_client
        if not c:
            return
        idx = self._sel_pay_idx()
        if idx is None:
            return
        dlg = PaymentDialog(self, self.data["payment_methods"], self.currency,
                            payment=c["payments"][idx], title="Edit Payment")
        if dlg.result:
            c["payments"][idx] = dlg.result
            self._after_change(c)

    def delete_payment(self):
        c = self.selected_client
        if not c:
            return
        idx = self._sel_pay_idx()
        if idx is None:
            return
        if messagebox.askyesno("Delete payment", "Delete the selected payment?"):
            del c["payments"][idx]
            self._after_change(c)

    def add_extra(self):
        c = self.selected_client
        if not c:
            return
        dlg = ExtraDialog(self, self.data["payment_methods"], self.currency)
        if dlg.result:
            c.setdefault("extras", []).append(dlg.result)
            self._after_change(c)

    def delete_extra(self):
        c = self.selected_client
        if not c:
            return
        sel = self.ex_tree.selection()
        if not sel:
            messagebox.showinfo("Select an item", "Select an extra item first.")
            return
        if messagebox.askyesno("Delete item", "Delete the selected extra item?"):
            del c["extras"][int(sel[0])]
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
        menu.add_command(label="Open data folder", command=self.open_data_folder)
        menu.add_separator()
        menu.add_command(label="About", command=self.show_about)
        try:
            menu.tk_popup(self.winfo_pointerx(), self.winfo_pointery())
        finally:
            menu.grab_release()

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

    # ---- save / misc ---------------------------------------------------- #
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
        folder = app_dir()
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
                            "Vlera e Kontratës = Contract · Pagesa = Payment\n"
                            "Të Dhëna = Paid · Të Mbetura = Remaining" % DATA_FILE)

    # ---- Excel / CSV export --------------------------------------------- #
    def export_excel(self):
        try:
            import openpyxl  # noqa
        except ImportError:
            if messagebox.askyesno("openpyxl not installed",
                                   "Excel export needs 'openpyxl' (not installed).\n\nExport as CSV instead?"):
                self._export_csv()
            else:
                messagebox.showinfo("Install openpyxl",
                                    "Run in Command Prompt:\n\n    pip install openpyxl")
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
        ws.append(["YEAR", "KLIENTI", "VLERA E KONTRATES", "TE DHENA", "TE MBETURA"])
        for cell in ws[1]:
            cell.font = bold
        for c in sorted(self.data["clients"], key=lambda x: (client_year(x) or 0, x["name"].lower())):
            ws.append([client_year(c) or "", c["name"], to_float(c.get("contract_value")),
                       total_received_of(c), remaining_of(c)])
        ws.append([])
        ws.append(["", "TOTAL", sum(to_float(c.get("contract_value")) for c in self.data["clients"]),
                   sum(total_received_of(c) for c in self.data["clients"]),
                   sum(remaining_of(c) for c in self.data["clients"])])
        for cell in ws[ws.max_row]:
            cell.font = bold
        # payments-by-month sheet
        pm = wb.create_sheet("PAGESAT")
        pm.append(["YEAR", "MONTH", "AMOUNT"])
        for cell in pm[1]:
            cell.font = bold
        agg = {}
        for c in self.data["clients"]:
            for p in iter_money_items(c, True):
                y, m = parse_date(p.get("date"))
                if y and m:
                    agg[(y, m)] = agg.get((y, m), 0.0) + to_float(p.get("amount"))
        for (y, m) in sorted(agg):
            pm.append([y, MONTHS[m - 1], agg[(y, m)]])
        for col, wdt in zip("ABCDE", (10, 26, 18, 14, 14)):
            ws.column_dimensions[col].width = wdt
        used = {"TOTALI", "PAGESAT"}
        for c in self.data["clients"]:
            title = (c["name"] or "Client")[:28]
            base, n = title, 1
            while title in used:
                n += 1
                title = "%s_%d" % (base[:26], n)
            used.add(title)
            s = wb.create_sheet(title)
            s.append([c["name"]])
            s["A1"].font = bold
            s.append(["TYPE", "DATA", "SHUMA", "METODA", "SHENIM"])
            for cell in s[2]:
                cell.font = bold
            for p in c.get("payments", []):
                s.append(["Pagesë", p.get("date", ""), to_float(p.get("amount")),
                          p.get("method", ""), p.get("note", "")])
            for e in c.get("extras", []):
                s.append([e.get("name", "Ekstra"), e.get("date", ""),
                          to_float(e.get("amount")), e.get("method", ""), "ekstra"])
            s.append([])
            s.append(["VLERA E KONTRATES", "", to_float(c.get("contract_value"))])
            s.append(["TE DHENA", "", total_received_of(c)])
            s.append(["TE MBETURA", "", remaining_of(c)])
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
                w.writerow(["Year", "Client", "Contract", "Type", "Date", "Amount", "Method", "Note"])
                for c in self.data["clients"]:
                    yr = client_year(c) or ""
                    if not c.get("payments") and not c.get("extras"):
                        w.writerow([yr, c["name"], to_float(c.get("contract_value")), "", "", "", "", ""])
                    for p in c.get("payments", []):
                        w.writerow([yr, c["name"], to_float(c.get("contract_value")), "Payment",
                                    p.get("date", ""), to_float(p.get("amount")), p.get("method", ""), p.get("note", "")])
                    for e in c.get("extras", []):
                        w.writerow([yr, c["name"], to_float(c.get("contract_value")), "Extra",
                                    e.get("date", ""), to_float(e.get("amount")), e.get("method", ""), e.get("name", "")])
            messagebox.showinfo("Exported", "Saved:\n%s" % path)
        except Exception as e:
            messagebox.showerror("Export failed", str(e))


def main():
    app = XplanApp()
    if getattr(app, "ok", False):
        app.mainloop()


if __name__ == "__main__":
    main()
