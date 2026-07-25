using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

namespace NoInteraction.Core
{
    /// <summary>
    /// Fallback synthetic click used when UI Automation's Invoke/LegacyAction is unavailable.
    /// Restores the user's original cursor position immediately after clicking using SendInput.
    /// </summary>
    public sealed class ClickAutomation
    {
        public static readonly ClickAutomation Shared = new();
        private ClickAutomation() { }

        [DllImport("user32.dll")]
        private static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct INPUT
        {
            [FieldOffset(0)] public uint type;
            [FieldOffset(4)] public MOUSEINPUT mi;
        }

        private const uint INPUT_MOUSE = 0;
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
                Thread.Sleep(15);

                INPUT[] inputs = new INPUT[2];
                inputs[0].type = INPUT_MOUSE;
                inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;

                inputs[1].type = INPUT_MOUSE;
                inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;

                SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
                Thread.Sleep(20);

                SetCursorPos(original.X, original.Y);

                Console.WriteLine($"[ClickAutomation] Clicked ({x}, {y}) using SendInput and restored cursor to ({original.X}, {original.Y})");

                completion?.Invoke();
            });
        }
    }
}

