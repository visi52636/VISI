#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
XPLAN - Client & Payment Manager
=================================
A local desktop program (Windows / macOS / Linux) for tracking architecture /
design studio clients and their payments.

Built from the "PGS_KLNT" Excel workbook. Terminology kept close to the
original sheet:

    KLIENTI            -> Client
    VLERA E KONTRATES  -> Contract Value
    PAGESA 1..N        -> Payment 1..N
    DATA E PAGESES     -> Payment Date
    TE DHENA           -> Paid (total received)
    TE MBETURA         -> Remaining (balance)
    PERMBLEDHJE/TOTALI -> Summary

Core app uses ONLY the Python standard library (tkinter, json), so it runs on
any standard Python installation with no extra downloads. Exporting to Excel
uses 'openpyxl' if it is installed (optional).

Data is stored next to this file in 'xplan_data.json'. A timestamped backup is
written to the 'backups' folder every time you start the program and every time
you save.
"""

import os
import sys
import json
import shutil
import datetime
import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, filedialog

# --------------------------------------------------------------------------- #
#  Paths & persistence
# --------------------------------------------------------------------------- #

APP_TITLE = "XPLAN — Client & Payment Manager"


def app_dir():
    """Folder where the program (and its data file) lives."""
    if getattr(sys, "frozen", False):          # running as a PyInstaller .exe
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


DATA_FILE = os.path.join(app_dir(), "xplan_data.json")
BACKUP_DIR = os.path.join(app_dir(), "backups")

DEFAULT_DATA = {
    "currency": "€",
    "payment_methods": ["Cash", "Bank Transfer", "Card", "Other"],
    "clients": [],
}


def load_data():
    if not os.path.exists(DATA_FILE):
        return dict(DEFAULT_DATA)
    try:
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        messagebox.showerror(
            "Data error",
            "Could not read the data file:\n%s\n\n%s\n\nStarting empty."
            % (DATA_FILE, e),
        )
        return dict(DEFAULT_DATA)
    # make sure all expected keys exist
    data.setdefault("currency", "€")
    data.setdefault("payment_methods", ["Cash", "Bank Transfer", "Card", "Other"])
    data.setdefault("clients", [])
    for c in data["clients"]:
        c.setdefault("name", "Unnamed")
        c.setdefault("contract_value", 0.0)
        c.setdefault("payments", [])
        c.setdefault("extras", [])
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
        pass  # backups are best-effort, never block the app


def _prune_backups(keep=40):
    try:
        files = sorted(
            (os.path.join(BACKUP_DIR, f) for f in os.listdir(BACKUP_DIR) if f.endswith(".json")),
            key=os.path.getmtime,
        )
        for old in files[:-keep]:
            os.remove(old)
    except Exception:
        pass


def save_data(data):
    make_backup("save")
    tmp = DATA_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, DATA_FILE)   # atomic write


# --------------------------------------------------------------------------- #
#  Helpers
# --------------------------------------------------------------------------- #

def to_float(value, default=0.0):
    if value is None:
        return default
    try:
        return float(str(value).replace(",", "").replace(" ", ""))
    except Exception:
        return default


def paid_of(client):
    return sum(to_float(p.get("amount")) for p in client.get("payments", []))


def extras_of(client):
    return sum(to_float(e.get("amount")) for e in client.get("extras", []))


def remaining_of(client):
    return to_float(client.get("contract_value")) - paid_of(client)


def total_received_of(client):
    return paid_of(client) + extras_of(client)


def today_str():
    return datetime.date.today().strftime("%d/%m/%Y")


# --------------------------------------------------------------------------- #
#  Dialogs
# --------------------------------------------------------------------------- #

class PaymentDialog(tk.Toplevel):
    """Add or edit a single payment (amount, date, method, note)."""

    def __init__(self, parent, methods, currency, payment=None, title="Add Payment"):
        super().__init__(parent)
        self.title(title)
        self.resizable(False, False)
        self.result = None
        self.transient(parent)
        self.configure(padx=16, pady=14)

        payment = payment or {}

        ttk.Label(self, text="Amount (%s):" % currency).grid(row=0, column=0, sticky="w", pady=4)
        self.amount = ttk.Entry(self, width=24)
        self.amount.grid(row=0, column=1, pady=4)
        self.amount.insert(0, "" if payment.get("amount") in (None, "") else str(payment.get("amount")))

        ttk.Label(self, text="Date (dd/mm/yyyy):").grid(row=1, column=0, sticky="w", pady=4)
        self.date = ttk.Entry(self, width=24)
        self.date.grid(row=1, column=1, pady=4)
        self.date.insert(0, payment.get("date") or today_str())

        ttk.Label(self, text="Method:").grid(row=2, column=0, sticky="w", pady=4)
        self.method = ttk.Combobox(self, width=21, values=methods, state="readonly")
        self.method.grid(row=2, column=1, pady=4)
        cur = payment.get("method") or (methods[0] if methods else "")
        if cur in methods:
            self.method.set(cur)
        elif methods:
            self.method.set(methods[0])

        ttk.Label(self, text="Note:").grid(row=3, column=0, sticky="w", pady=4)
        self.note = ttk.Entry(self, width=24)
        self.note.grid(row=3, column=1, pady=4)
        self.note.insert(0, payment.get("note") or "")

        btns = ttk.Frame(self)
        btns.grid(row=4, column=0, columnspan=2, pady=(12, 0), sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="OK", command=self._ok).pack(side="right")

        self.amount.focus_set()
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()
        self.wait_window(self)

    def _ok(self):
        amt = to_float(self.amount.get(), None)
        if amt is None:
            messagebox.showwarning("Invalid amount", "Please enter a number for the amount.", parent=self)
            return
        self.result = {
            "amount": amt,
            "date": self.date.get().strip(),
            "method": self.method.get().strip(),
            "note": self.note.get().strip(),
        }
        self.destroy()


class ExtraDialog(tk.Toplevel):
    """Add or edit an extra line-item (name, amount, date, method, note)."""

    def __init__(self, parent, methods, currency, extra=None, title="Add Extra Item"):
        super().__init__(parent)
        self.title(title)
        self.resizable(False, False)
        self.result = None
        self.transient(parent)
        self.configure(padx=16, pady=14)

        extra = extra or {}

        ttk.Label(self, text="Item name:").grid(row=0, column=0, sticky="w", pady=4)
        self.name = ttk.Entry(self, width=24)
        self.name.grid(row=0, column=1, pady=4)
        self.name.insert(0, extra.get("name") or "")

        ttk.Label(self, text="Amount (%s):" % currency).grid(row=1, column=0, sticky="w", pady=4)
        self.amount = ttk.Entry(self, width=24)
        self.amount.grid(row=1, column=1, pady=4)
        self.amount.insert(0, "" if extra.get("amount") in (None, "") else str(extra.get("amount")))

        ttk.Label(self, text="Date (dd/mm/yyyy):").grid(row=2, column=0, sticky="w", pady=4)
        self.date = ttk.Entry(self, width=24)
        self.date.grid(row=2, column=1, pady=4)
        self.date.insert(0, extra.get("date") or today_str())

        ttk.Label(self, text="Method:").grid(row=3, column=0, sticky="w", pady=4)
        self.method = ttk.Combobox(self, width=21, values=methods, state="readonly")
        self.method.grid(row=3, column=1, pady=4)
        if (extra.get("method") or "") in methods:
            self.method.set(extra.get("method"))
        elif methods:
            self.method.set(methods[0])

        btns = ttk.Frame(self)
        btns.grid(row=4, column=0, columnspan=2, pady=(12, 0), sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="OK", command=self._ok).pack(side="right")

        self.name.focus_set()
        self.bind("<Return>", lambda e: self._ok())
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()
        self.wait_window(self)

    def _ok(self):
        if not self.name.get().strip():
            messagebox.showwarning("Missing name", "Please enter a name for the item.", parent=self)
            return
        amt = to_float(self.amount.get(), None)
        if amt is None:
            messagebox.showwarning("Invalid amount", "Please enter a number for the amount.", parent=self)
            return
        self.result = {
            "name": self.name.get().strip(),
            "amount": amt,
            "date": self.date.get().strip(),
            "method": self.method.get().strip(),
            "note": "",
        }
        self.destroy()


class ClientDialog(tk.Toplevel):
    """Add or edit a client (name, contract value, optional first payment)."""

    def __init__(self, parent, methods, currency, client=None, title="Add New Client"):
        super().__init__(parent)
        self.title(title)
        self.resizable(False, False)
        self.result = None
        self.transient(parent)
        self.configure(padx=16, pady=14)
        self._methods = methods
        self._currency = currency
        client = client or {}
        self._editing = bool(client)

        ttk.Label(self, text="Client name:").grid(row=0, column=0, sticky="w", pady=4)
        self.name = ttk.Entry(self, width=30)
        self.name.grid(row=0, column=1, pady=4)
        self.name.insert(0, client.get("name") or "")

        ttk.Label(self, text="Contract value (%s):" % currency).grid(row=1, column=0, sticky="w", pady=4)
        self.contract = ttk.Entry(self, width=30)
        self.contract.grid(row=1, column=1, pady=4)
        self.contract.insert(0, "" if client.get("contract_value") in (None, "") else str(client.get("contract_value", "")))

        self._first_payment = None
        if not self._editing:
            self.add_first = tk.BooleanVar(value=False)
            ttk.Checkbutton(
                self, text="Also record a first payment now",
                variable=self.add_first,
            ).grid(row=2, column=0, columnspan=2, sticky="w", pady=(8, 2))

        btns = ttk.Frame(self)
        btns.grid(row=3, column=0, columnspan=2, pady=(12, 0), sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="OK", command=self._ok).pack(side="right")

        self.name.focus_set()
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()
        self.wait_window(self)

    def _ok(self):
        name = self.name.get().strip()
        if not name:
            messagebox.showwarning("Missing name", "Please enter a client name.", parent=self)
            return
        contract = to_float(self.contract.get(), None)
        if contract is None:
            messagebox.showwarning("Invalid value", "Contract value must be a number.", parent=self)
            return
        result = {"name": name, "contract_value": contract}
        if not self._editing and self.add_first.get():
            dlg = PaymentDialog(self, self._methods, self._currency, title="First Payment")
            if dlg.result:
                result["first_payment"] = dlg.result
        self.result = result
        self.destroy()


class MethodsDialog(tk.Toplevel):
    """Manage the list of payment methods (add / remove)."""

    def __init__(self, parent, methods):
        super().__init__(parent)
        self.title("Payment Methods")
        self.resizable(False, False)
        self.transient(parent)
        self.configure(padx=16, pady=14)
        self.result = None
        self._methods = list(methods)

        ttk.Label(self, text="Payment methods used when recording a payment:").grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, 6))

        self.listbox = tk.Listbox(self, height=8, width=34, activestyle="none")
        self.listbox.grid(row=1, column=0, columnspan=2, sticky="nsew")
        for m in self._methods:
            self.listbox.insert("end", m)

        entry_row = ttk.Frame(self)
        entry_row.grid(row=2, column=0, columnspan=2, sticky="we", pady=(8, 4))
        self.new_entry = ttk.Entry(entry_row, width=24)
        self.new_entry.pack(side="left", fill="x", expand=True)
        ttk.Button(entry_row, text="Add", command=self._add).pack(side="left", padx=(6, 0))

        ttk.Button(self, text="Remove selected", command=self._remove).grid(
            row=3, column=0, sticky="w", pady=(0, 8))

        btns = ttk.Frame(self)
        btns.grid(row=4, column=0, columnspan=2, sticky="e")
        ttk.Button(btns, text="Cancel", command=self.destroy).pack(side="right", padx=4)
        ttk.Button(btns, text="Save", command=self._save).pack(side="right")

        self.new_entry.bind("<Return>", lambda e: self._add())
        self.new_entry.focus_set()
        self.bind("<Escape>", lambda e: self.destroy())
        self.grab_set()
        self.wait_window(self)

    def _add(self):
        val = self.new_entry.get().strip()
        if val and val not in self._methods:
            self._methods.append(val)
            self.listbox.insert("end", val)
        self.new_entry.delete(0, "end")

    def _remove(self):
        sel = self.listbox.curselection()
        if not sel:
            return
        idx = sel[0]
        del self._methods[idx]
        self.listbox.delete(idx)

    def _save(self):
        if not self._methods:
            messagebox.showwarning("Empty list", "Keep at least one payment method.", parent=self)
            return
        self.result = self._methods
        self.destroy()


# --------------------------------------------------------------------------- #
#  Main application
# --------------------------------------------------------------------------- #

class XplanApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.data = load_data()
        make_backup("start")

        self.title(APP_TITLE)
        self.geometry("1040x640")
        self.minsize(860, 520)

        try:
            ttk.Style().theme_use("clam")
        except tk.TclError:
            pass
        style = ttk.Style()
        style.configure("Treeview", rowheight=24)
        style.configure("Total.TLabel", font=("TkDefaultFont", 10, "bold"))
        style.configure("Head.TLabel", font=("TkDefaultFont", 13, "bold"))

        self.selected_client = None  # dict reference

        self._build_menu()
        self._build_toolbar()
        self._build_body()
        self._build_statusbar()

        self.refresh_client_list()
        self.update_status()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    # ---- currency / formatting ----------------------------------------- #
    @property
    def currency(self):
        return self.data.get("currency", "€")

    def money(self, value):
        return "%s %s" % (self.currency, "{:,.0f}".format(to_float(value)))

    # ---- UI construction ----------------------------------------------- #
    def _build_menu(self):
        menubar = tk.Menu(self)

        filem = tk.Menu(menubar, tearoff=0)
        filem.add_command(label="Save", command=self.save, accelerator="Ctrl+S")
        filem.add_command(label="Export to Excel…", command=self.export_excel)
        filem.add_command(label="Import from Excel…", command=self.import_excel)
        filem.add_separator()
        filem.add_command(label="Open data folder", command=self.open_data_folder)
        filem.add_separator()
        filem.add_command(label="Exit", command=self.on_close)
        menubar.add_cascade(label="File", menu=filem)

        managem = tk.Menu(menubar, tearoff=0)
        managem.add_command(label="Add New Client…", command=self.add_client)
        managem.add_command(label="Payment Methods…", command=self.manage_methods)
        managem.add_command(label="Set currency symbol…", command=self.set_currency)
        menubar.add_cascade(label="Manage", menu=managem)

        helpm = tk.Menu(menubar, tearoff=0)
        helpm.add_command(label="About", command=self.show_about)
        menubar.add_cascade(label="Help", menu=helpm)

        self.config(menu=menubar)
        self.bind("<Control-s>", lambda e: self.save())

    def _build_toolbar(self):
        bar = ttk.Frame(self, padding=(8, 6))
        bar.pack(side="top", fill="x")
        ttk.Button(bar, text="➕ Add Client", command=self.add_client).pack(side="left")
        ttk.Button(bar, text="💳 Payment Methods", command=self.manage_methods).pack(side="left", padx=(6, 0))
        ttk.Button(bar, text="📊 Export to Excel", command=self.export_excel).pack(side="left", padx=(6, 0))
        ttk.Button(bar, text="💾 Save", command=self.save).pack(side="left", padx=(6, 0))

        ttk.Label(bar, text="Search:").pack(side="left", padx=(18, 4))
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *a: self.refresh_client_list())
        ttk.Entry(bar, textvariable=self.search_var, width=22).pack(side="left")

    def _build_body(self):
        pan = ttk.PanedWindow(self, orient="horizontal")
        pan.pack(side="top", fill="both", expand=True, padx=8, pady=(0, 6))

        # ---- left: clients list -------------------------------------- #
        left = ttk.Frame(pan)
        pan.add(left, weight=1)
        ttk.Label(left, text="Clients (Klientët)", style="Head.TLabel").pack(anchor="w", pady=(4, 4))

        cols = ("name", "contract", "paid", "remaining")
        self.tree = ttk.Treeview(left, columns=cols, show="headings", selectmode="browse")
        for key, txt, w, anchor in (
            ("name", "Client", 150, "w"),
            ("contract", "Contract", 90, "e"),
            ("paid", "Paid", 90, "e"),
            ("remaining", "Remaining", 90, "e"),
        ):
            self.tree.heading(key, text=txt)
            self.tree.column(key, width=w, anchor=anchor, stretch=(key == "name"))
        self.tree.tag_configure("paidoff", foreground="#1a7f37")
        self.tree.tag_configure("owing", foreground="#b00020")
        vsb = ttk.Scrollbar(left, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=vsb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        vsb.pack(side="right", fill="y")
        self.tree.bind("<<TreeviewSelect>>", self.on_select_client)

        # ---- right: client detail ------------------------------------ #
        right = ttk.Frame(pan)
        pan.add(right, weight=2)
        self.detail = right
        self._build_detail_empty()

    def _clear_detail(self):
        for w in self.detail.winfo_children():
            w.destroy()

    def _build_detail_empty(self):
        self._clear_detail()
        ttk.Label(
            self.detail,
            text="Select a client on the left,\nor use ➕ Add Client to create one.",
            style="Head.TLabel", justify="center",
        ).place(relx=0.5, rely=0.45, anchor="center")

    def _build_detail(self, client):
        self._clear_detail()
        d = self.detail

        header = ttk.Frame(d, padding=(4, 4))
        header.pack(fill="x")
        ttk.Label(header, text=client["name"], style="Head.TLabel").pack(side="left")
        ttk.Button(header, text="Edit client", command=self.edit_client).pack(side="right")
        ttk.Button(header, text="Delete client", command=self.delete_client).pack(side="right", padx=(0, 6))

        # summary numbers
        info = ttk.Frame(d, padding=(4, 2))
        info.pack(fill="x")
        contract = to_float(client.get("contract_value"))
        paid = paid_of(client)
        rem = remaining_of(client)
        extras = extras_of(client)
        cells = [
            ("Contract value (Vlera e Kontratës)", self.money(contract)),
            ("Paid on contract (Të Dhëna)", self.money(paid)),
            ("Remaining (Të Mbetura)", self.money(rem)),
        ]
        if extras:
            cells.append(("Extras", self.money(extras)))
            cells.append(("Total received", self.money(paid + extras)))
        for i, (lbl, val) in enumerate(cells):
            box = ttk.Frame(info, relief="groove", borderwidth=1, padding=8)
            box.grid(row=0, column=i, padx=4, pady=4, sticky="nsew")
            info.columnconfigure(i, weight=1)
            ttk.Label(box, text=lbl, foreground="#555").pack(anchor="w")
            fg = "#b00020" if (lbl.startswith("Remaining") and rem > 0) else ("#1a7f37" if lbl.startswith("Remaining") else "#000")
            ttk.Label(box, text=val, font=("TkDefaultFont", 13, "bold"), foreground=fg).pack(anchor="w")

        # ---- payments ---- #
        pay_head = ttk.Frame(d, padding=(4, 8))
        pay_head.pack(fill="x")
        ttk.Label(pay_head, text="Payments (Pagesat)", style="Total.TLabel").pack(side="left")
        ttk.Button(pay_head, text="➕ Add Payment", command=self.add_payment).pack(side="right")
        ttk.Button(pay_head, text="Edit", command=self.edit_payment).pack(side="right", padx=(0, 6))
        ttk.Button(pay_head, text="Delete", command=self.delete_payment).pack(side="right", padx=(0, 6))

        pcols = ("no", "date", "amount", "method", "note")
        self.pay_tree = ttk.Treeview(d, columns=pcols, show="headings", height=7, selectmode="browse")
        for key, txt, w, anchor in (
            ("no", "#", 36, "center"),
            ("date", "Date", 100, "center"),
            ("amount", "Amount", 110, "e"),
            ("method", "Method", 130, "w"),
            ("note", "Note", 180, "w"),
        ):
            self.pay_tree.heading(key, text=txt)
            self.pay_tree.column(key, width=w, anchor=anchor, stretch=(key == "note"))
        self.pay_tree.pack(fill="both", expand=True, padx=4)
        self.pay_tree.bind("<Double-1>", lambda e: self.edit_payment())
        for i, p in enumerate(client.get("payments", []), 1):
            self.pay_tree.insert("", "end", iid=str(i - 1), values=(
                i, p.get("date", ""), self.money(p.get("amount")),
                p.get("method", ""), p.get("note", "")))

        # ---- extras ---- #
        ex_head = ttk.Frame(d, padding=(4, 8))
        ex_head.pack(fill="x")
        ttk.Label(ex_head, text="Extra items (Ekstra)", style="Total.TLabel").pack(side="left")
        ttk.Button(ex_head, text="➕ Add Extra", command=self.add_extra).pack(side="right")
        ttk.Button(ex_head, text="Delete", command=self.delete_extra).pack(side="right", padx=(0, 6))

        ecols = ("name", "date", "amount", "method")
        self.ex_tree = ttk.Treeview(d, columns=ecols, show="headings", height=4, selectmode="browse")
        for key, txt, w, anchor in (
            ("name", "Item", 200, "w"),
            ("date", "Date", 100, "center"),
            ("amount", "Amount", 110, "e"),
            ("method", "Method", 130, "w"),
        ):
            self.ex_tree.heading(key, text=txt)
            self.ex_tree.column(key, width=w, anchor=anchor, stretch=(key == "name"))
        self.ex_tree.pack(fill="both", expand=False, padx=4, pady=(0, 6))
        for i, e in enumerate(client.get("extras", [])):
            self.ex_tree.insert("", "end", iid=str(i), values=(
                e.get("name", ""), e.get("date", ""), self.money(e.get("amount")),
                e.get("method", "")))

    def _build_statusbar(self):
        self.status = ttk.Frame(self, relief="sunken", padding=(8, 4))
        self.status.pack(side="bottom", fill="x")
        self.status_label = ttk.Label(self.status, text="", style="Total.TLabel")
        self.status_label.pack(side="left")
        self.saved_label = ttk.Label(self.status, text="", foreground="#1a7f37")
        self.saved_label.pack(side="right")

    # ---- list / selection ---------------------------------------------- #
    def refresh_client_list(self):
        query = (self.search_var.get() if hasattr(self, "search_var") else "").strip().lower()
        self.tree.delete(*self.tree.get_children())
        clients = sorted(self.data["clients"], key=lambda c: c["name"].lower())
        for c in clients:
            if query and query not in c["name"].lower():
                continue
            rem = remaining_of(c)
            tag = "owing" if rem > 0 else "paidoff"
            self.tree.insert("", "end", iid=c["name"], tags=(tag,), values=(
                c["name"], self.money(c.get("contract_value")),
                self.money(paid_of(c)), self.money(rem)))
        # keep selection if still visible
        if self.selected_client and self.tree.exists(self.selected_client["name"]):
            self.tree.selection_set(self.selected_client["name"])

    def _client_by_name(self, name):
        for c in self.data["clients"]:
            if c["name"] == name:
                return c
        return None

    def on_select_client(self, event=None):
        sel = self.tree.selection()
        if not sel:
            return
        client = self._client_by_name(sel[0])
        if client:
            self.selected_client = client
            self._build_detail(client)

    # ---- status --------------------------------------------------------- #
    def update_status(self, saved=False):
        clients = self.data["clients"]
        total_contract = sum(to_float(c.get("contract_value")) for c in clients)
        total_paid = sum(total_received_of(c) for c in clients)
        total_rem = sum(remaining_of(c) for c in clients)
        self.status_label.config(text="%d clients   |   Contracts: %s   |   Received: %s   |   Outstanding: %s" % (
            len(clients), self.money(total_contract), self.money(total_paid), self.money(total_rem)))
        if saved:
            self.saved_label.config(text="Saved ✓  %s" % datetime.datetime.now().strftime("%H:%M:%S"))

    # ---- actions: clients ---------------------------------------------- #
    def add_client(self):
        dlg = ClientDialog(self, self.data["payment_methods"], self.currency)
        if not dlg.result:
            return
        if self._client_by_name(dlg.result["name"]):
            messagebox.showwarning("Duplicate", "A client with that name already exists.")
            return
        client = {
            "name": dlg.result["name"],
            "contract_value": dlg.result["contract_value"],
            "payments": [],
            "extras": [],
        }
        if dlg.result.get("first_payment"):
            client["payments"].append(dlg.result["first_payment"])
        self.data["clients"].append(client)
        self.selected_client = client
        self.save(silent=True)
        self.refresh_client_list()
        self.tree.selection_set(client["name"])
        self.on_select_client()

    def edit_client(self):
        c = self.selected_client
        if not c:
            return
        dlg = ClientDialog(self, self.data["payment_methods"], self.currency, client=c, title="Edit Client")
        if not dlg.result:
            return
        new_name = dlg.result["name"]
        if new_name != c["name"] and self._client_by_name(new_name):
            messagebox.showwarning("Duplicate", "A client with that name already exists.")
            return
        c["name"] = new_name
        c["contract_value"] = dlg.result["contract_value"]
        self.save(silent=True)
        self.refresh_client_list()
        self.tree.selection_set(c["name"])
        self.on_select_client()

    def delete_client(self):
        c = self.selected_client
        if not c:
            return
        if not messagebox.askyesno("Delete client", "Delete '%s' and all its payments?\nThis cannot be undone." % c["name"]):
            return
        self.data["clients"].remove(c)
        self.selected_client = None
        self.save(silent=True)
        self.refresh_client_list()
        self._build_detail_empty()

    # ---- actions: payments --------------------------------------------- #
    def add_payment(self):
        c = self.selected_client
        if not c:
            return
        dlg = PaymentDialog(self, self.data["payment_methods"], self.currency)
        if dlg.result:
            c.setdefault("payments", []).append(dlg.result)
            self._after_change(c)

    def _selected_payment_index(self):
        sel = self.pay_tree.selection()
        if not sel:
            messagebox.showinfo("Select a payment", "Please select a payment in the table first.")
            return None
        return int(sel[0])

    def edit_payment(self):
        c = self.selected_client
        if not c:
            return
        idx = self._selected_payment_index()
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
        idx = self._selected_payment_index()
        if idx is None:
            return
        if messagebox.askyesno("Delete payment", "Delete the selected payment?"):
            del c["payments"][idx]
            self._after_change(c)

    # ---- actions: extras ----------------------------------------------- #
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
            messagebox.showinfo("Select an item", "Please select an extra item first.")
            return
        idx = int(sel[0])
        if messagebox.askyesno("Delete item", "Delete the selected extra item?"):
            del c["extras"][idx]
            self._after_change(c)

    def _after_change(self, client):
        self.save(silent=True)
        self.refresh_client_list()
        self._build_detail(client)
        self.update_status()

    # ---- actions: methods / currency ----------------------------------- #
    def manage_methods(self):
        dlg = MethodsDialog(self, self.data["payment_methods"])
        if dlg.result is not None:
            self.data["payment_methods"] = dlg.result
            self.save(silent=True)
            if self.selected_client:
                self._build_detail(self.selected_client)

    def set_currency(self):
        val = simpledialog.askstring("Currency", "Currency symbol (e.g. €, $, L, ALL):",
                                     initialvalue=self.currency, parent=self)
        if val:
            self.data["currency"] = val.strip()
            self.save(silent=True)
            self.refresh_client_list()
            self.update_status()
            if self.selected_client:
                self._build_detail(self.selected_client)

    # ---- save / close --------------------------------------------------- #
    def save(self, silent=False):
        try:
            save_data(self.data)
        except Exception as e:
            messagebox.showerror("Save failed", "Could not save data:\n%s" % e)
            return
        self.update_status(saved=True)
        if not silent:
            self.saved_label.config(text="Saved ✓  %s" % datetime.datetime.now().strftime("%H:%M:%S"))

    def on_close(self):
        try:
            self.save(silent=True)
        finally:
            self.destroy()

    def open_data_folder(self):
        folder = app_dir()
        try:
            if sys.platform.startswith("win"):
                os.startfile(folder)                       # noqa
            elif sys.platform == "darwin":
                os.system("open '%s'" % folder)
            else:
                os.system("xdg-open '%s'" % folder)
        except Exception:
            messagebox.showinfo("Data folder", folder)

    # ---- Excel export / import ----------------------------------------- #
    def export_excel(self):
        try:
            import openpyxl  # noqa
        except ImportError:
            if messagebox.askyesno(
                "openpyxl not installed",
                "Exporting to Excel needs the 'openpyxl' package, which is not "
                "installed.\n\nExport as a CSV file instead?"):
                self._export_csv()
            else:
                messagebox.showinfo(
                    "Install openpyxl",
                    "To enable Excel export, open Command Prompt and run:\n\n"
                    "    pip install openpyxl")
            return

        path = filedialog.asksaveasfilename(
            title="Export to Excel", defaultextension=".xlsx",
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
        ws.append(["KLIENTI", "VLERA E KONTRATES", "TE DHENA", "TE MBETURA"])
        for cell in ws[1]:
            cell.font = bold
        for c in sorted(self.data["clients"], key=lambda x: x["name"].lower()):
            ws.append([c["name"], to_float(c.get("contract_value")),
                       total_received_of(c), remaining_of(c)])
        total_row = ["TOTAL",
                     sum(to_float(c.get("contract_value")) for c in self.data["clients"]),
                     sum(total_received_of(c) for c in self.data["clients"]),
                     sum(remaining_of(c) for c in self.data["clients"])]
        ws.append([])
        ws.append(total_row)
        for cell in ws[ws.max_row]:
            cell.font = bold
        for col, width in zip("ABCD", (26, 18, 14, 14)):
            ws.column_dimensions[col].width = width

        used = {"TOTALI"}
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
            s.append(["KONTRAKTUESI", "DATA", "SHUMA", "METODA", "SHENIM"])
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
            for col, width in zip("ABCDE", (22, 14, 12, 16, 20)):
                s.column_dimensions[col].width = width
        wb.save(path)

    def _export_csv(self):
        import csv
        path = filedialog.asksaveasfilename(
            title="Export as CSV", defaultextension=".csv",
            initialfile="XPLAN_payments.csv",
            filetypes=[("CSV file", "*.csv")])
        if not path:
            return
        try:
            with open(path, "w", newline="", encoding="utf-8-sig") as f:
                w = csv.writer(f)
                w.writerow(["Client", "Contract", "Type", "Date", "Amount", "Method", "Note"])
                for c in self.data["clients"]:
                    if not c.get("payments") and not c.get("extras"):
                        w.writerow([c["name"], to_float(c.get("contract_value")), "", "", "", "", ""])
                    for p in c.get("payments", []):
                        w.writerow([c["name"], to_float(c.get("contract_value")), "Payment",
                                    p.get("date", ""), to_float(p.get("amount")),
                                    p.get("method", ""), p.get("note", "")])
                    for e in c.get("extras", []):
                        w.writerow([c["name"], to_float(c.get("contract_value")), "Extra",
                                    e.get("date", ""), to_float(e.get("amount")),
                                    e.get("method", ""), e.get("name", "")])
            messagebox.showinfo("Exported", "Saved:\n%s" % path)
        except Exception as e:
            messagebox.showerror("Export failed", str(e))

    def import_excel(self):
        try:
            import openpyxl  # noqa
        except ImportError:
            messagebox.showinfo(
                "Install openpyxl",
                "Importing from Excel needs the 'openpyxl' package.\n\n"
                "Open Command Prompt and run:\n\n    pip install openpyxl\n\n"
                "Note: the file must NOT be password-protected. If it is, open it "
                "in Excel and save a copy without a password first.")
            return
        path = filedialog.askopenfilename(
            title="Import from Excel", filetypes=[("Excel workbook", "*.xlsx")])
        if not path:
            return
        messagebox.showinfo(
            "Import",
            "Automatic import works with files exported by XPLAN (the layout above).\n\n"
            "Your original PGS_KLNT workbook has already been loaded into this "
            "program, so you normally do not need to import again. If you need to "
            "merge a specific file, send it to your developer to map the columns.")

    # ---- about ---------------------------------------------------------- #
    def show_about(self):
        messagebox.showinfo(
            "About XPLAN",
            "XPLAN — Client & Payment Manager\n\n"
            "Tracks clients, contract values and payments for your studio.\n"
            "Data is stored locally in:\n%s\n\n"
            "Backups are kept in the 'backups' folder.\n\n"
            "Albanian terms:\n"
            "  Vlera e Kontratës = Contract value\n"
            "  Pagesa = Payment    Data e Pagesës = Payment date\n"
            "  Të Dhëna = Paid     Të Mbetura = Remaining" % DATA_FILE)


def main():
    app = XplanApp()
    app.mainloop()


if __name__ == "__main__":
    main()
