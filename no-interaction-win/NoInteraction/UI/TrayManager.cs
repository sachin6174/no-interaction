using System;
using System.Drawing;
using System.Windows.Forms;
using NoInteraction.Core;

namespace NoInteraction.UI
{
    /// <summary>
    /// System tray equivalent of the Mac build's MenuBarManager: a status icon with a
    /// right-click menu (pause/resume, mute/unmute, open dashboard, quit) and left-click/double-click
    /// to open the dashboard.
    /// </summary>
    public sealed class TrayManager : IDisposable
    {
        public static readonly TrayManager Shared = new();

        private NotifyIcon? _icon;
        private DashboardWindow? _dashboard;
        private IntPtr _currentHIcon = IntPtr.Zero;

        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyIcon(IntPtr handle);

        private TrayManager() { }

        public void Setup()
        {
            _icon = new NotifyIcon
            {
                Visible = true,
                Text = "NoInteraction"
            };
            
            _icon.MouseClick += (s, e) =>
            {
                if (e.Button == MouseButtons.Left)
                {
                    ShowDashboard();
                }
            };
            
            _icon.DoubleClick += (_, _) => ShowDashboard();

            UpdateIcon();
            ApproverEngine.Shared.PropertyChanged += (_, _) => UpdateIcon();
        }

        public void UpdateIcon()
        {
            if (_icon == null) return;
            var engine = ApproverEngine.Shared;

            // Bitmap.GetHicon() allocates a brand-new native GDI icon handle every call, and
            // Icon.FromHandle() does NOT take ownership of it — it must be destroyed manually
            // or it leaks. UpdateIcon() runs on every property change (every approval, every
            // toggle), so an unmanaged app would exhaust its GDI handle quota over long uptime.
            var previousHIcon = _currentHIcon;
            _currentHIcon = IntPtr.Zero;

            try
            {
                _currentHIcon = CreateTrayIconHandle(engine.IsEnabled);
                _icon.Icon = Icon.FromHandle(_currentHIcon);
            }
            catch
            {
                _icon.Icon = engine.IsEnabled ? SystemIcons.Shield : SystemIcons.Application;
            }

            if (previousHIcon != IntPtr.Zero)
            {
                try { DestroyIcon(previousHIcon); } catch { }
            }

            var statusText = engine.IsEnabled ? "Active — Monitoring Prompts" : "Paused";
            _icon.Text = $"NoInteraction — {statusText}";
            _icon.ContextMenuStrip = BuildMenu();
        }

        private IntPtr CreateTrayIconHandle(bool active)
        {
            using var bmp = new Bitmap(32, 32);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);

                // Draw solid rounded background (Catppuccin Mauve when active, Muted Gray when paused)
                using var bgBrush = new SolidBrush(active ? Color.FromArgb(203, 166, 247) : Color.FromArgb(108, 112, 134));
                g.FillEllipse(bgBrush, 2, 2, 28, 28);

                // Draw inner dark symbol "N"
                using var font = new Font("Segoe UI", 16, FontStyle.Bold, GraphicsUnit.Pixel);
                using var textBrush = new SolidBrush(Color.FromArgb(30, 30, 46));
                var format = new StringFormat
                {
                    Alignment = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center
                };
                g.DrawString("N", font, textBrush, new RectangleF(0, 0, 32, 32), format);
            }
            return bmp.GetHicon();
        }

        private ContextMenuStrip BuildMenu()
        {
            var engine = ApproverEngine.Shared;
            var menu = new ContextMenuStrip();

            var statusItem = new ToolStripMenuItem(engine.IsEnabled ? "Active — Monitoring Prompts" : "Paused") { Enabled = false };
            menu.Items.Add(statusItem);

            var countItem = new ToolStripMenuItem($"Total Auto-Approved: {engine.TotalApprovalsCount}") { Enabled = false };
            menu.Items.Add(countItem);

            menu.Items.Add(new ToolStripSeparator());

            var toggleItem = new ToolStripMenuItem(engine.IsEnabled ? "Pause Monitoring" : "Resume Monitoring");
            toggleItem.Click += (_, _) => { engine.IsEnabled = !engine.IsEnabled; UpdateIcon(); };
            menu.Items.Add(toggleItem);

            var soundItem = new ToolStripMenuItem(engine.SoundEnabled ? "Mute Sound Feedback" : "Enable Sound Feedback");
            soundItem.Click += (_, _) => { engine.SoundEnabled = !engine.SoundEnabled; };
            menu.Items.Add(soundItem);

            var dashboardItem = new ToolStripMenuItem("Open Dashboard...");
            dashboardItem.Click += (_, _) => ShowDashboard();
            menu.Items.Add(dashboardItem);

            menu.Items.Add(new ToolStripSeparator());

            var quitItem = new ToolStripMenuItem("Quit NoInteraction");
            quitItem.Click += (_, _) => System.Windows.Application.Current.Shutdown();
            menu.Items.Add(quitItem);

            return menu;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool AllowSetForegroundWindow(int dwProcessId);

        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        private static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_SHOWWINDOW = 0x0040;
        private const int SW_RESTORE = 9;
        private const int ASFW_ANY = -1;

        public void ShowDashboard()
        {
            try
            {
                AllowSetForegroundWindow(ASFW_ANY);

                if (_dashboard == null || !_dashboard.IsLoaded)
                {
                    _dashboard = new DashboardWindow();
                    _dashboard.Closed += (_, _) => _dashboard = null;
                }

                _dashboard.Show();
                _dashboard.WindowState = System.Windows.WindowState.Normal;

                var helper = new System.Windows.Interop.WindowInteropHelper(_dashboard);
                if (helper.Handle != IntPtr.Zero)
                {
                    SetWindowPos(helper.Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                    ShowWindow(helper.Handle, SW_RESTORE);
                    SetForegroundWindow(helper.Handle);
                    SetWindowPos(helper.Handle, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
                }

                _dashboard.Activate();
                _dashboard.Focus();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[TrayManager] Error showing dashboard: {ex}");
            }
        }

        public void Dispose()
        {
            if (_currentHIcon != IntPtr.Zero)
            {
                try { DestroyIcon(_currentHIcon); } catch { }
                _currentHIcon = IntPtr.Zero;
            }
            _icon?.Dispose();
        }
    }
}
