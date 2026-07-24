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

        self.engine.set_clipboard_callback(self.clipboard_set_text)
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
        self._build_queue_tab()

    def _build_log_tab(self):
        tab = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(tab, text="Activity Log")

        top = ttk.Frame(tab)
        top.pack(fill="x", pady=(0, 8))
        
        self.search_var = tk.StringVar()
        
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

        self.search_var.trace_add("write", lambda *_: self.refresh_log())

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

        # Update queue active & loop mode states
        self.queue_active_var.set(self.engine.is_prompt_queue_active)
        self.loop_mode_var.set(self.engine.loop_mode_enabled)
        self.loop_limit_var.set(str(self.engine.loop_mode_limit))

        queue_count = len(self.engine.prompt_queue)
        curr_idx = self.engine.current_prompt_index
        if self.engine.is_prompt_queue_active:
            if curr_idx < queue_count:
                self.queue_status_label.config(text=f"Status: Active — Sending {curr_idx + 1} of {queue_count}", foreground=self.green_accent)
            else:
                self.queue_status_label.config(text="Status: Complete (Queue fully dispatched)", foreground=self.gray_text)
        else:
            self.queue_status_label.config(text="Status: Inactive", foreground=self.gray_text)

        if curr_idx > 0:
            self.restart_queue_btn.pack(side="right")
        else:
            self.restart_queue_btn.pack_forget()

        # Update loop status
        limit_str = "∞" if self.engine.loop_mode_limit == 0 else str(self.engine.loop_mode_limit)
        self.loop_status_label.config(text=f"Dispatched: {self.engine.loop_mode_counter} / {limit_str}")

        if self.engine.loop_mode_enabled:
            self.loop_settings_frame.pack(fill="x", pady=(8, 0))
        else:
            self.loop_settings_frame.pack_forget()

        self._render_queue()

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
            label = ttk.Label(card, text=rule.keyword, font=("Sans", 10, "bold" if rule.is_enabled else "normal"), foreground=label_fg)
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

    def clipboard_set_text(self, text: str) -> None:
        try:
            self.clipboard_clear()
            self.clipboard_append(text)
            self.update()
            print("[Dashboard] Copied prompt to clipboard")
        except Exception as e:
            print(f"[Dashboard] Failed to copy to clipboard: {e}")

    def _build_queue_tab(self):
        tab = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(tab, text="Prompt Queue")

        # Scrollable container
        canvas = tk.Canvas(tab, bg=self.bg_color, bd=0, highlightthickness=0)
        scrollbar = ttk.Scrollbar(tab, orient="vertical", command=canvas.yview)
        scroll_content = ttk.Frame(canvas)

        canvas.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side="right", fill="y")
        canvas.pack(side="left", fill="both", expand=True)

        canvas_window = canvas.create_window((0, 0), window=scroll_content, anchor="nw")

        def _on_configure(event):
            canvas.configure(scrollregion=canvas.bbox("all"))
            canvas.itemconfig(canvas_window, width=event.width)

        canvas.bind("<Configure>", _on_configure)

        # 1. Active Queue Toggle Card
        card1 = ttk.Frame(scroll_content, style="Card.TFrame", padding=12)
        card1.pack(fill="x", pady=6)

        c1_top = ttk.Frame(card1, style="Card.TFrame")
        c1_top.pack(fill="x")

        c1_title_frame = ttk.Frame(c1_top, style="Card.TFrame")
        c1_title_frame.pack(side="left")
        ttk.Label(c1_title_frame, text="Prompt Queue Dispatch", font=("Sans", 11, "bold"), foreground=self.accent_color, background=self.card_bg).pack(anchor="w")
        ttk.Label(c1_title_frame, text="Sequentially paste prompts automatically when the agent window is free.", font=("Sans", 9), foreground=self.gray_text, background=self.card_bg).pack(anchor="w")

        self.queue_active_var = tk.BooleanVar()
        self.queue_active_check = ttk.Checkbutton(c1_top, variable=self.queue_active_var, command=self._toggle_queue_active)
        self.queue_active_check.pack(side="right", padx=10)

        self.queue_status_frame = ttk.Frame(card1, style="Card.TFrame")
        self.queue_status_frame.pack(fill="x", pady=(8, 0))

        self.queue_status_label = ttk.Label(self.queue_status_frame, text="", font=("Sans", 10), background=self.card_bg)
        self.queue_status_label.pack(side="left")

        self.restart_queue_btn = ttk.Button(self.queue_status_frame, text="Restart Queue", command=self._restart_queue)
        self.restart_queue_btn.pack(side="right")

        # 2. Loop Test Mode Settings Card
        card2 = ttk.Frame(scroll_content, style="Card.TFrame", padding=12)
        card2.pack(fill="x", pady=6)

        c2_top = ttk.Frame(card2, style="Card.TFrame")
        c2_top.pack(fill="x")

        c2_title_frame = ttk.Frame(c2_top, style="Card.TFrame")
        c2_title_frame.pack(side="left")
        ttk.Label(c2_title_frame, text="Loop Test Mode", font=("Sans", 11, "bold"), foreground=self.accent_color, background=self.card_bg).pack(anchor="w")
        ttk.Label(c2_title_frame, text="Repetitive stress-testing via sequential system auditing.", font=("Sans", 9), foreground=self.gray_text, background=self.card_bg).pack(anchor="w")

        self.loop_mode_var = tk.BooleanVar()
        self.loop_mode_check = ttk.Checkbutton(c2_top, variable=self.loop_mode_var, command=self._toggle_loop_mode)
        self.loop_mode_check.pack(side="right", padx=10)

        self.loop_settings_frame = ttk.Frame(card2, style="Card.TFrame")
        self.loop_settings_frame.pack(fill="x", pady=(8, 0))

        ttk.Label(self.loop_settings_frame, text="Limit:", font=("Sans", 10), background=self.card_bg).pack(side="left")

        self.loop_limit_var = tk.StringVar()
        self.loop_limit_10 = ttk.Radiobutton(self.loop_settings_frame, text="10 Iterations", variable=self.loop_limit_var, value="10", command=self._set_loop_limit)
        self.loop_limit_10.pack(side="left", padx=10)
        self.loop_limit_inf = ttk.Radiobutton(self.loop_settings_frame, text="Infinite", variable=self.loop_limit_var, value="0", command=self._set_loop_limit)
        self.loop_limit_inf.pack(side="left")

        self.loop_reset_btn = ttk.Button(self.loop_settings_frame, text="Reset", command=self._reset_loop_counter)
        self.loop_reset_btn.pack(side="right")

        self.loop_status_label = ttk.Label(self.loop_settings_frame, text="", font=("Sans", 10), background=self.card_bg)
        self.loop_status_label.pack(side="right", padx=15)

        # 3. Default System Audit Banner
        card3 = ttk.Frame(scroll_content, style="Card.TFrame", padding=12)
        card3.pack(fill="x", pady=6)

        c3_top = ttk.Frame(card3, style="Card.TFrame")
        c3_top.pack(fill="x")

        ttk.Label(c3_top, text="System Audit Template", font=("Sans", 10, "bold"), foreground=self.accent_color, background=self.card_bg).pack(side="left")
        ttk.Button(c3_top, text="Restore Default", command=self._restore_default_queue).pack(side="right")

        prompt_preview = self.engine.default_prompt[:180] + "..."
        ttk.Label(card3, text=prompt_preview, font=("Courier", 8), foreground=self.gray_text, background=self.bg_color, padding=8, relief="solid", borderwidth=1).pack(fill="x", pady=(8, 0))

        # 4. Add New Custom Prompt
        card4 = ttk.Frame(scroll_content, style="Card.TFrame", padding=12)
        card4.pack(fill="x", pady=6)

        ttk.Label(card4, text="Add New Custom Prompt", font=("Sans", 11, "bold"), foreground=self.accent_color, background=self.card_bg).pack(anchor="w")

        self.new_prompt_text = tk.Text(card4, height=3, bg=self.bg_color, fg=self.fg_color, insertbackground=self.fg_color, relief="solid", borderwidth=1, font=("Courier", 9))
        self.new_prompt_text.pack(fill="x", pady=6)

        c4_bot = ttk.Frame(card4, style="Card.TFrame")
        c4_bot.pack(fill="x")
        self.queue_prompt_btn = ttk.Button(c4_bot, text="Queue Prompt", command=self._queue_custom_prompt)
        self.queue_prompt_btn.pack(side="right")

        # 5. Configured Queue List
        card5 = ttk.Frame(scroll_content, style="Card.TFrame", padding=12)
        card5.pack(fill="x", pady=6)

        c5_top = ttk.Frame(card5, style="Card.TFrame")
        c5_top.pack(fill="x")
        ttk.Label(c5_top, text="Configured Queue", font=("Sans", 11, "bold"), foreground=self.accent_color, background=self.card_bg).pack(side="left")
        self.clear_queue_btn = ttk.Button(c5_top, text="Clear All", command=self._clear_queue)
        self.clear_queue_btn.pack(side="right")

        self.queue_list_frame = ttk.Frame(card5, style="Card.TFrame")
        self.queue_list_frame.pack(fill="x", pady=(8, 0))

    def _toggle_queue_active(self):
        self.engine.is_prompt_queue_active = self.queue_active_var.get()

    def _toggle_loop_mode(self):
        self.engine.loop_mode_enabled = self.loop_mode_var.get()

    def _set_loop_limit(self):
        self.engine.loop_mode_limit = int(self.loop_limit_var.get())

    def _reset_loop_counter(self):
        self.engine.loop_mode_counter = 0

    def _restart_queue(self):
        self.engine.current_prompt_index = 0

    def _restore_default_queue(self):
        self.engine.reset_prompt_queue_to_default()

    def _queue_custom_prompt(self):
        txt = self.new_prompt_text.get("1.0", tk.END).strip()
        if txt:
            self.engine.prompt_queue = self.engine.prompt_queue + [txt]
            self.new_prompt_text.delete("1.0", tk.END)

    def _clear_queue(self):
        self.engine.prompt_queue = []
        self.engine.current_prompt_index = 0
        self.engine.is_prompt_queue_active = False

    def _delete_queue_item(self, idx):
        q = list(self.engine.prompt_queue)
        if 0 <= idx < len(q):
            q.pop(idx)
            self.engine.prompt_queue = q
            if self.engine.current_prompt_index > idx:
                self.engine.current_prompt_index = max(0, self.engine.current_prompt_index - 1)

    def _render_queue(self):
        for child in self.queue_list_frame.winfo_children():
            child.destroy()

        queue = self.engine.prompt_queue
        curr_idx = self.engine.current_prompt_index
        is_active = self.engine.is_prompt_queue_active

        if not queue:
            ttk.Label(self.queue_list_frame, text="Queue is empty. Enter a prompt above to schedule.", font=("Sans", 10), foreground=self.gray_text, background=self.card_bg).pack(pady=12)
            return

        for idx, prompt in enumerate(queue):
            row = ttk.Frame(self.queue_list_frame, padding=4, style="Card.TFrame")
            row.pack(fill="x", pady=2)

            if idx < curr_idx:
                dot_color = self.border_color
            elif idx == curr_idx and is_active:
                dot_color = self.green_accent
            else:
                dot_color = self.accent_color

            canvas_dot = tk.Canvas(row, width=12, height=12, bg=self.card_bg, bd=0, highlightthickness=0)
            canvas_dot.pack(side="left", padx=(4, 8))
            canvas_dot.create_oval(2, 2, 10, 10, fill=dot_color, outline="")

            text_frame = ttk.Frame(row, style="Card.TFrame")
            text_frame.pack(side="left", fill="x", expand=True)

            lbl_title = ttk.Label(text_frame, text=f"Prompt {idx + 1}", font=("Sans", 10, "bold"), foreground=self.fg_color if idx >= curr_idx else self.gray_text, background=self.card_bg)
            lbl_title.pack(anchor="w")

            preview = prompt.split("\n")[0][:80]
            if len(prompt) > 80 or len(prompt.split("\n")) > 1:
                preview += "..."

            lbl_preview = ttk.Label(text_frame, text=preview, font=("Courier", 8), foreground=self.gray_text, background=self.card_bg)
            lbl_preview.pack(anchor="w")

            del_btn = ttk.Button(row, text="✕", width=3, style="Action.TButton", command=lambda i=idx: self._delete_queue_item(i))
            del_btn.pack(side="right", padx=4)
