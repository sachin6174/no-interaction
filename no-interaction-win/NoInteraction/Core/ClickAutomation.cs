using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace NoInteraction.Core
{
    /// <summary>
    /// Fallback synthetic click used when UI Automation's InvokePattern is unavailable
    /// (mirrors the Mac build's CGEvent-based ClickAutomation). Restores the user's
    /// original cursor position immediately after clicking so typing is never interrupted.
    /// </summary>
    public sealed class ClickAutomation
    {
        public static readonly ClickAutomation Shared = new();
        private ClickAutomation() { }

        [DllImport("user32.dll")]
        private static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, IntPtr dwExtraInfo);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;

        public void PerformClick(Point point, Action? completion = null)
        {
            Task.Run(() =>
            {
                GetCursorPos(out var original);

                var x = (int)Math.Round(point.X);
                var y = (int)Math.Round(point.Y);

                SetCursorPos(x, y);
                Thread.Sleep(10);
                mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
                Thread.Sleep(30);
                mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);
                Thread.Sleep(10);

                SetCursorPos(original.X, original.Y);

                Console.WriteLine($"[ClickAutomation] Clicked ({x}, {y}) and restored cursor to ({original.X}, {original.Y})");

                completion?.Invoke();
            });
        }
    }
}
