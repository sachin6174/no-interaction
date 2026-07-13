"""Tkinter dashboard — Linux equivalent of the Mac build's DashboardView.
Two tabs (Activity Log, Approval Rules); no Prompt Queue / Loop Mode tab."""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from .approver_engine import ApproverEngine
from .models import ApprovalRule, TargetType


class Dashboard(tk.Tk):
    def __init__(self, on_quit=None):
        super().__init__()
        self.engine = ApproverEngine.shared()
        self._on_quit = on_quit

        self.title("NoInteraction")
        self.geometry("640x480")
        self.minsize(520, 380)

        self.protocol("WM_DELETE_WINDOW", self.hide)

        self._build_header()
        self._build_tabs()
        self._build_footer()

        self.engine.add_listener(lambda: self.after(0, self.refresh))
        self.refresh()

    # MARK: Layout

    def _build_header(self):
        header = ttk.Frame(self, padding=10)
        header.pack(fill="x")

        title_frame = ttk.Frame(header)
        title_frame.pack(side="left")
        ttk.Label(title_frame, text="NoInteraction", font=("Sans", 14, "bold")).pack(anchor="w")
        self.status_label = ttk.Label(title_frame, text="", foreground="#666666")
        self.status_label.pack(anchor="w")

        right = ttk.Frame(header)
        right.pack(side="right")

        self.approved_label = ttk.Label(right, text="0 Approved", foreground="#2E7D32")
        self.approved_label.pack(side="left", padx=(0, 10))

        self.sound_btn = ttk.Button(right, text="\U0001F50A", width=3, command=self._toggle_sound)
        self.sound_btn.pack(side="left", padx=(0, 10))

        self.enabled_var = tk.BooleanVar()
        self.enabled_check = ttk.Checkbutton(right, text="Enabled", variable=self.enabled_var, command=self._toggle_enabled)
        self.enabled_check.pack(side="left")

    def _build_tabs(self):
        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=8, pady=4)

        self._build_log_tab()
        self._build_rules_tab()

    def _build_log_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Activity Log")

        top = ttk.Frame(tab)
        top.pack(fill="x", pady=(0, 6))
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *_: self.refresh_log())
        ttk.Entry(top, textvariable=self.search_var).pack(side="left", fill="x", expand=True)
        ttk.Button(top, text="Clear Log", command=self._clear_log).pack(side="left", padx=(6, 0))

        columns = ("target", "app", "method", "time")
        self.log_tree = ttk.Treeview(tab, columns=columns, show="headings")
        self.log_tree.heading("target", text="Target")
        self.log_tree.heading("app", text="App")
        self.log_tree.heading("method", text="Method")
        self.log_tree.heading("time", text="Time")
        self.log_tree.column("target", width=200)
        self.log_tree.column("app", width=140)
        self.log_tree.column("method", width=120)
        self.log_tree.column("time", width=90)
        self.log_tree.pack(fill="both", expand=True)

    def _build_rules_tab(self):
        tab = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab, text="Approval Rules")

        top = ttk.Frame(tab)
        top.pack(fill="x", pady=(0, 8))
        ttk.Label(
            top, text="Configure keywords for auto-clicking buttons and auto-ticking checkboxes.",
            foreground="#666666", wraplength=420,
        ).pack(side="left", fill="x", expand=True)
        ttk.Button(top, text="Reset Defaults", command=self._reset_defaults).pack(side="right")

        ttk.Label(tab, text="Auto-Click Buttons", font=("Sans", 10, "bold")).pack(anchor="w", pady=(4, 0))
        btn_add = ttk.Frame(tab)
        btn_add.pack(fill="x", pady=(2, 4))
        self.new_button_var = tk.StringVar()
        ttk.Entry(btn_add, textvariable=self.new_button_var).pack(side="left", fill="x", expand=True)
        ttk.Button(btn_add, text="Add", command=self._add_button_rule).pack(side="left", padx=(6, 0))
        self.button_rules_frame = ttk.Frame(tab)
        self.button_rules_frame.pack(fill="x")

        ttk.Separator(tab).pack(fill="x", pady=10)

        ttk.Label(tab, text="Auto-Tick Checkboxes", font=("Sans", 10, "bold")).pack(anchor="w")
        chk_add = ttk.Frame(tab)
        chk_add.pack(fill="x", pady=(2, 4))
        self.new_checkbox_var = tk.StringVar()
        ttk.Entry(chk_add, textvariable=self.new_checkbox_var).pack(side="left", fill="x", expand=True)
        ttk.Button(chk_add, text="Add", command=self._add_checkbox_rule).pack(side="left", padx=(6, 0))
        self.checkbox_rules_frame = ttk.Frame(tab)
        self.checkbox_rules_frame.pack(fill="x")

    def _build_footer(self):
        footer = ttk.Frame(self, padding=(10, 6))
        footer.pack(fill="x")
        ttk.Label(footer, text="AT-SPI Ready", foreground="#666666").pack(side="left")
        ttk.Button(footer, text="Hide to Tray", command=self.hide).pack(side="right")

    # MARK: Refresh

    def refresh(self):
        self.enabled_var.set(self.engine.is_enabled)
        self.status_label.config(text="Active & Monitoring Prompts" if self.engine.is_enabled else "Paused")
        self.approved_label.config(text=f"{self.engine.total_approvals_count} Approved")
        self.sound_btn.config(text="\U0001F50A" if self.engine.sound_enabled else "\U0001F507")
        self.refresh_log()
        self._render_rules(self.button_rules_frame, self.engine.button_rules, TargetType.BUTTON)
        self._render_rules(self.checkbox_rules_frame, self.engine.checkbox_rules, TargetType.CHECKBOX)

    def refresh_log(self):
        query = self.search_var.get().strip().lower()
        self.log_tree.delete(*self.log_tree.get_children())
        for entry in self.engine.logs:
            if query and query not in entry.target_text.lower() and query not in entry.app_name.lower() and query not in entry.detection_method.lower():
                continue
            self.log_tree.insert("", "end", values=(entry.target_text, entry.app_name, entry.detection_method, entry.formatted_time))

    def _render_rules(self, frame: ttk.Frame, rules: list[ApprovalRule], target_type: TargetType):
        for child in frame.winfo_children():
            child.destroy()
        for rule in rules:
            row = ttk.Frame(frame)
            row.pack(fill="x", pady=1)
            var = tk.BooleanVar(value=rule.is_enabled)
            ttk.Checkbutton(row, variable=var, command=lambda rid=rule.id: self.engine.toggle_rule(rid, target_type)).pack(side="left")
            label = ttk.Label(row, text=rule.keyword, foreground="#000000" if rule.is_enabled else "#999999")
            label.pack(side="left", padx=(4, 0), fill="x", expand=True)
            ttk.Button(row, text="✕", width=2, command=lambda rid=rule.id: self.engine.remove_rule(rid, target_type)).pack(side="right")

    # MARK: Actions

    def _toggle_enabled(self):
        self.engine.is_enabled = self.enabled_var.get()

    def _toggle_sound(self):
        self.engine.sound_enabled = not self.engine.sound_enabled

    def _clear_log(self):
        self.engine.clear_logs()

    def _reset_defaults(self):
        self.engine.reset_rules_to_default()

    def _add_button_rule(self):
        self.engine.add_rule(self.new_button_var.get(), TargetType.BUTTON)
        self.new_button_var.set("")

    def _add_checkbox_rule(self):
        self.engine.add_rule(self.new_checkbox_var.get(), TargetType.CHECKBOX)
        self.new_checkbox_var.set("")

    def hide(self):
        self.withdraw()

    def show(self):
        self.deiconify()
        self.lift()
        self.focus_force()

    def quit_app(self):
        if self._on_quit:
            self._on_quit()
        self.destroy()
