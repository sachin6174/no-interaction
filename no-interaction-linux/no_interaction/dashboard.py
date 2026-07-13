"""Tkinter dashboard — Linux equivalent of the Mac build's DashboardView.
Styled with a custom modern dark theme for premium UI/UX feel.
"""

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
        self.geometry("680x520")
        self.minsize(580, 420)

        self.protocol("WM_DELETE_WINDOW", self.hide)

        # ── Setup Modern Dark Theme Styles ───────────────────────────────────────────
        self.style = ttk.Style()
        self.style.theme_use('default')
        
        # Color Palette
        self.bg_color = "#1e1e2e"       # Catppuccin Mocha Base
        self.fg_color = "#cdd6f4"       # Text color
        self.card_bg = "#252538"        # Card background
        self.accent_color = "#cba6f7"   # Mauve accent
        self.border_color = "#45475a"   # Border
        self.green_accent = "#a6e3a1"   # Green
        self.gray_text = "#bac2de"      # Subtext
        self.red_accent = "#f38ba8"     # Red

        self.configure(bg=self.bg_color)
        
        # Base Configuration
        self.style.configure(".", background=self.bg_color, foreground=self.fg_color)
        self.style.configure("TFrame", background=self.bg_color)
        self.style.configure("TLabel", background=self.bg_color, foreground=self.fg_color)
        
        # Specific styles
        self.style.configure("Header.TFrame", background=self.bg_color)
        self.style.configure("Card.TFrame", background=self.card_bg, borderwidth=1, relief="solid")
        
        self.style.configure("Title.TLabel", font=("Sans", 16, "bold"), foreground=self.accent_color, background=self.bg_color)
        self.style.configure("Status.TLabel", font=("Sans", 10), foreground=self.gray_text, background=self.bg_color)
        self.style.configure("Approved.TLabel", font=("Sans", 11, "bold"), foreground=self.green_accent, background=self.card_bg)
        
        # Notebook (tabs)
        self.style.configure("TNotebook", background=self.bg_color, borderwidth=0, padding=0)
        self.style.configure("TNotebook.Tab", background=self.card_bg, foreground=self.fg_color, padding=[16, 8], font=("Sans", 10, "bold"))
        self.style.map("TNotebook.Tab", 
                       background=[("selected", self.bg_color)], 
                       foreground=[("selected", self.accent_color)])
        
        # Entry
        self.style.configure("TEntry", fieldbackground=self.card_bg, foreground=self.fg_color, borderwidth=1, bordercolor=self.border_color)
        
        # Buttons
        self.style.configure("TButton", background=self.card_bg, foreground=self.fg_color, borderwidth=0, padding=[10, 6], font=("Sans", 9, "bold"))
        self.style.map("TButton", 
                       background=[("active", self.accent_color), ("hover", self.accent_color)], 
                       foreground=[("active", self.bg_color)])
        
        # Secondary small buttons (delete/cross)
        self.style.configure("Action.TButton", background=self.card_bg, foreground=self.red_accent, padding=[4, 2], font=("Sans", 8))
        self.style.map("Action.TButton", background=[("active", self.red_accent)], foreground=[("active", self.bg_color)])

        # Treeview (Logs Table)
        self.style.configure("Treeview", background=self.card_bg, fieldbackground=self.card_bg, foreground=self.fg_color, rowheight=26, borderwidth=0)
        self.style.configure("Treeview.Heading", background=self.bg_color, foreground=self.fg_color, font=("Sans", 10, "bold"), borderwidth=0)
        self.style.map("Treeview", background=[("selected", self.accent_color)], foreground=[("selected", self.bg_color)])

        self._build_header()
        self._build_tabs()
        self._build_footer()

        self.engine.add_listener(lambda: self.after(0, self.refresh))
        self.refresh()

    # MARK: Layout

    def _build_header(self):
        header = ttk.Frame(self, padding=(18, 14), style="Header.TFrame")
        header.pack(fill="x")

        title_frame = ttk.Frame(header, style="Header.TFrame")
        title_frame.pack(side="left")
        
        ttk.Label(title_frame, text="NoInteraction", style="Title.TLabel").pack(anchor="w")
        self.status_label = ttk.Label(title_frame, text="", style="Status.TLabel")
        self.status_label.pack(anchor="w", pady=(2, 0))

        right = ttk.Frame(header, style="Header.TFrame")
        right.pack(side="right")

        # Visual indicator badge card
        badge_card = ttk.Frame(right, style="Card.TFrame", padding=(10, 5))
        badge_card.pack(side="left", padx=(0, 12))
        
        self.approved_label = ttk.Label(badge_card, text="0 Approved", style="Approved.TLabel")
        self.approved_label.pack()

        self.sound_btn = ttk.Button(right, text="🔊", width=4, command=self._toggle_sound)
        self.sound_btn.pack(side="left", padx=(0, 12))

        self.enabled_var = tk.BooleanVar()
        self.enabled_check = ttk.Checkbutton(right, text="Enable Scanner", variable=self.enabled_var, command=self._toggle_enabled)
        self.enabled_check.pack(side="left")

    def _build_tabs(self):
        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=12, pady=6)

        self._build_log_tab()
        self._build_rules_tab()

    def _build_log_tab(self):
        tab = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(tab, text="Activity Log")

        top = ttk.Frame(tab)
        top.pack(fill="x", pady=(0, 8))
        
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *_: self.refresh_log())
        
        search_entry = ttk.Entry(top, textvariable=self.search_var, font=("Sans", 10))
        search_entry.pack(side="left", fill="x", expand=True)
        search_entry.insert(0, "Filter logs...")
        search_entry.bind("<FocusIn>", lambda e: search_entry.delete(0, tk.END) if self.search_var.get() == "Filter logs..." else None)
        
        ttk.Button(top, text="Clear Logs", command=self._clear_log).pack(side="left", padx=(8, 0))

        columns = ("target", "app", "method", "time")
        self.log_tree = ttk.Treeview(tab, columns=columns, show="headings")
        self.log_tree.heading("target", text="Target Element Text")
        self.log_tree.heading("app", text="Application")
        self.log_tree.heading("method", text="Method")
        self.log_tree.heading("time", text="Time Detected")
        
        self.log_tree.column("target", width=220)
        self.log_tree.column("app", width=140)
        self.log_tree.column("method", width=110)
        self.log_tree.column("time", width=100)
        
        # Add scrollbar to log treeview
        scrollbar = ttk.Scrollbar(tab, orient="vertical", command=self.log_tree.yview)
        self.log_tree.configure(yscrollcommand=scrollbar.set)
        
        scrollbar.pack(side="right", fill="y")
        self.log_tree.pack(fill="both", expand=True)

    def _build_rules_tab(self):
        tab = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(tab, text="Approval Bypass Rules")

        top = ttk.Frame(tab)
        top.pack(fill="x", pady=(0, 10))
        
        ttk.Label(
            top, text="Configure target confirmation labels for buttons and checkboxes.",
            font=("Sans", 10), foreground=self.gray_text, wraplength=480,
        ).pack(side="left", fill="x", expand=True)
        
        ttk.Button(top, text="Reset Defaults", command=self._reset_defaults).pack(side="right")

        # Scrollable container for rules list
        scroll_container = tk.Canvas(tab, bg=self.bg_color, bd=0, highlightthickness=0)
        scroll_container.pack(fill="both", expand=True)
        
        rule_content = ttk.Frame(scroll_container)
        scroll_container.create_window((0,0), window=rule_content, anchor="nw")
        
        # Set scroll configurations
        rule_content.bind("<Configure>", lambda e: scroll_container.configure(scrollregion=scroll_container.bbox("all")))

        # Section: Buttons
        ttk.Label(rule_content, text="Auto-Click Buttons", font=("Sans", 11, "bold"), foreground=self.accent_color).pack(anchor="w", pady=(6, 2))
        btn_add = ttk.Frame(rule_content)
        btn_add.pack(fill="x", pady=(2, 6))
        self.new_button_var = tk.StringVar()
        ttk.Entry(btn_add, textvariable=self.new_button_var, font=("Sans", 10)).pack(side="left", fill="x", expand=True)
        ttk.Button(btn_add, text="Add Keyword", command=self._add_button_rule).pack(side="left", padx=(8, 0))
        
        self.button_rules_frame = ttk.Frame(rule_content)
        self.button_rules_frame.pack(fill="x", pady=(2, 8))

        ttk.Separator(rule_content).pack(fill="x", pady=12)

        # Section: Checkboxes
        ttk.Label(rule_content, text="Auto-Tick Checkboxes", font=("Sans", 11, "bold"), foreground=self.accent_color).pack(anchor="w", pady=(4, 2))
        chk_add = ttk.Frame(rule_content)
        chk_add.pack(fill="x", pady=(2, 6))
        self.new_checkbox_var = tk.StringVar()
        ttk.Entry(chk_add, textvariable=self.new_checkbox_var, font=("Sans", 10)).pack(side="left", fill="x", expand=True)
        ttk.Button(chk_add, text="Add Keyword", command=self._add_checkbox_rule).pack(side="left", padx=(8, 0))
        
        self.checkbox_rules_frame = ttk.Frame(rule_content)
        self.checkbox_rules_frame.pack(fill="x", pady=(2, 8))

    def _build_footer(self):
        footer = ttk.Frame(self, padding=(14, 8))
        footer.pack(fill="x")
        ttk.Label(footer, text="AT-SPI Registry Connected", font=("Sans", 9), foreground=self.gray_text).pack(side="left")
        ttk.Button(footer, text="Hide to System Tray", command=self.hide).pack(side="right")

    # MARK: Refresh

    def refresh(self):
        self.enabled_var.set(self.engine.is_enabled)
        self.status_label.config(text="Active & Monitoring Workspace Prompts" if self.engine.is_enabled else "Scanner Disabled (Paused)")
        self.approved_label.config(text=f"{self.engine.total_approvals_count} Approved")
        self.sound_btn.config(text="🔊" if self.engine.sound_enabled else "🔇")
        self.refresh_log()
        self._render_rules(self.button_rules_frame, self.engine.button_rules, TargetType.BUTTON)
        self._render_rules(self.checkbox_rules_frame, self.engine.checkbox_rules, TargetType.CHECKBOX)

    def refresh_log(self):
        query = self.search_var.get().strip().lower()
        if query == "filter logs...":
            query = ""
        self.log_tree.delete(*self.log_tree.get_children())
        for entry in self.engine.get_logs():
            if query and query not in entry.target_text.lower() and query not in entry.app_name.lower() and query not in entry.detection_method.lower():
                continue
            self.log_tree.insert("", "end", values=(entry.target_text, entry.app_name, entry.detection_method, entry.formatted_time))

    def _render_rules(self, frame: ttk.Frame, rules: list[ApprovalRule], target_type: TargetType):
        for child in frame.winfo_children():
            child.destroy()
        
        # Render rule chips inside card layout frame
        for rule in rules:
            row = ttk.Frame(frame, padding=4)
            row.pack(fill="x", pady=2)
            
            # Sub-card frame for spacing and background
            card = ttk.Frame(row, style="Card.TFrame", padding=(8, 4))
            card.pack(fill="x")
            
            var = tk.BooleanVar(value=rule.is_enabled)
            ttk.Checkbutton(card, variable=var, command=lambda rid=rule.id: self.engine.toggle_rule(rid, target_type)).pack(side="left")
            
            label_fg = self.fg_color if rule.is_enabled else self.gray_text
            label = ttk.Label(card, text=rule.keyword, font=("Sans", 10, "medium" if rule.is_enabled else "normal"), foreground=label_fg)
            label.pack(side="left", padx=(8, 0), fill="x", expand=True)
            
            del_btn = ttk.Button(card, text="✕", width=3, style="Action.TButton", command=lambda rid=rule.id: self.engine.remove_rule(rid, target_type))
            del_btn.pack(side="right")

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
        val = self.new_button_var.get().strip()
        if val and val != "Filter logs...":
            self.engine.add_rule(val, TargetType.BUTTON)
            self.new_button_var.set("")

    def _add_checkbox_rule(self):
        val = self.new_checkbox_var.get().strip()
        if val:
            self.engine.add_rule(val, TargetType.CHECKBOX)
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
