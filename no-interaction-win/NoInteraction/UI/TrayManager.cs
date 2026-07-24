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

            try
            {
                _icon.Icon = CreateTrayIcon(engine.IsEnabled);
            }
            catch
            {
                _icon.Icon = engine.IsEnabled ? SystemIcons.Shield : SystemIcons.Application;
            }

            var statusText = engine.IsEnabled ? "Active — Monitoring Prompts" : "Paused";
            _icon.Text = $"NoInteraction — {statusText}";
            _icon.ContextMenuStrip = BuildMenu();
        }

        private Icon CreateTrayIcon(bool active)
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
            IntPtr hIcon = bmp.GetHicon();
            return Icon.FromHandle(hIcon);
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

        public void ShowDashboard()
        {
            if (_dashboard == null || !_dashboard.IsLoaded)
            {
                _dashboard = new DashboardWindow();
                _dashboard.Closed += (_, _) => _dashboard = null;
            }

            if (_dashboard.WindowState == System.Windows.WindowState.Minimized)
            {
                _dashboard.WindowState = System.Windows.WindowState.Normal;
            }

            _dashboard.Show();
            _dashboard.Activate();
            _dashboard.Topmost = true;
            _dashboard.Topmost = false;
        }

        public void Dispose()
        {
            _icon?.Dispose();
        }
    }
}
