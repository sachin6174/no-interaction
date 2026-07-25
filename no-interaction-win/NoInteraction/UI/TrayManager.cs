using System;
using System.Drawing;
using System.IO;
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

        /// <summary>Loads the same artwork used for the exe/taskbar icon (embedded from
        /// app.ico — the macOS app's icon, converted) instead of drawing a separate,
        /// mismatched shape here, so the tray icon and the rest of the app's icon look
        /// like the same app.
        ///
        /// Deliberately does NOT use System.Drawing.Icon(stream, w, h): GDI+'s icon frame
        /// picker/decoder is unreliable for PNG-compressed ICO entries at non-256 sizes (it
        /// produced solid noise here, not a decode error, so it fails silently) — every
        /// frame in app.ico is PNG-compressed. Parsing the ICO directory ourselves and
        /// decoding the chosen frame's PNG bytes directly sidesteps that entirely.</summary>
        private Bitmap LoadBaseIconBitmap(int size)
        {
            var asm = System.Reflection.Assembly.GetExecutingAssembly();
            using var stream = asm.GetManifestResourceStream("NoInteraction.app.ico")
                ?? throw new InvalidOperationException("Embedded app.ico resource not found.");
            using var ms = new MemoryStream();
            stream.CopyTo(ms);
            var icoBytes = ms.ToArray();

            var pngBytes = ExtractClosestIcoFramePng(icoBytes, size)
                ?? throw new InvalidOperationException("No usable frame found in app.ico.");

            using var pngStream = new MemoryStream(pngBytes);
            var decoded = new Bitmap(pngStream);
            if (decoded.Width == size && decoded.Height == size) return decoded;

            using (decoded)
            {
                return new Bitmap(decoded, size, size);
            }
        }

        /// <summary>Reads the ICONDIR/ICONDIRENTRY table and returns the raw PNG bytes of
        /// whichever frame's declared size is closest to <paramref name="targetSize"/>.</summary>
        private static byte[]? ExtractClosestIcoFramePng(byte[] icoBytes, int targetSize)
        {
            if (icoBytes.Length < 6) return null;
            int count = BitConverter.ToUInt16(icoBytes, 4);

            byte[]? best = null;
            int bestDiff = int.MaxValue;
            for (int i = 0; i < count; i++)
            {
                int entryOffset = 6 + i * 16;
                if (entryOffset + 16 > icoBytes.Length) break;

                int w = icoBytes[entryOffset]; if (w == 0) w = 256;
                int dataSize = BitConverter.ToInt32(icoBytes, entryOffset + 8);
                int dataOffset = BitConverter.ToInt32(icoBytes, entryOffset + 12);
                if (dataOffset < 0 || dataSize <= 0 || dataOffset + dataSize > icoBytes.Length) continue;

                int diff = Math.Abs(w - targetSize);
                if (diff < bestDiff)
                {
                    bestDiff = diff;
                    best = new byte[dataSize];
                    Array.Copy(icoBytes, dataOffset, best, 0, dataSize);
                }
            }
            return best;
        }

        /// <summary>Desaturates the icon for the "paused" tray state — keeps the same
        /// artwork instead of swapping to an unrelated color/shape, so it's still instantly
        /// recognizable as NoInteraction while clearly reading as inactive.</summary>
        private static Bitmap ToGrayscale(Bitmap source)
        {
            var result = new Bitmap(source.Width, source.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using var g = Graphics.FromImage(result);
            var colorMatrix = new System.Drawing.Imaging.ColorMatrix(new float[][]
            {
                new float[] { 0.3f, 0.3f, 0.3f, 0, 0 },
                new float[] { 0.59f, 0.59f, 0.59f, 0, 0 },
                new float[] { 0.11f, 0.11f, 0.11f, 0, 0 },
                new float[] { 0, 0, 0, 0.75f, 0 },
                new float[] { 0, 0, 0, 0, 1 }
            });
            using var attributes = new System.Drawing.Imaging.ImageAttributes();
            attributes.SetColorMatrix(colorMatrix);
            g.DrawImage(source, new Rectangle(0, 0, source.Width, source.Height), 0, 0, source.Width, source.Height, GraphicsUnit.Pixel, attributes);
            return result;
        }

        private IntPtr CreateTrayIconHandle(bool active)
        {
            using var baseBmp = LoadBaseIconBitmap(32);
            if (active) return baseBmp.GetHicon();

            using var grayBmp = ToGrayscale(baseBmp);
            return grayBmp.GetHicon();
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
