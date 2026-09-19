using System;
using System.Runtime.InteropServices;
using System.Threading;
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

        [DllImport("user32.dll")]
        private static extern IntPtr WindowFromPoint(POINT point);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        private readonly object _clickLock = new();

        public bool IsTargetAt(Point point, int processId)
        {
            var window = WindowFromPoint(new POINT { X = (int)Math.Round(point.X), Y = (int)Math.Round(point.Y) });
            return window != IntPtr.Zero && GetWindowThreadProcessId(window, out var owner) != 0
                && owner == (uint)processId;
        }

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

        // INPUT must be Sequential (not a hand-picked FieldOffset) so the CLR inserts the
        // same platform-correct padding a C compiler would: on x64 the union is 8-byte
        // aligned (MOUSEINPUT.dwExtraInfo is pointer-sized), so it actually starts at
        // offset 8, not 4. A hardcoded FieldOffset(4) silently corrupts every SendInput
        // call on 64-bit Windows — this app only ships as win-x64, so it always would have.
        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public MOUSEINPUT mi;
        }

        private const uint INPUT_MOUSE = 0;
        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;

        public bool PerformClick(Point point, int processId, Func<bool> canClick, Action? completion = null)
        {
            lock (_clickLock)
            {
                if (!canClick() || !IsTargetAt(point, processId) || !GetCursorPos(out var original)) return false;

                var x = (int)Math.Round(point.X);
                var y = (int)Math.Round(point.Y);

                if (!SetCursorPos(x, y)) return false;
                try
                {
                    if (!canClick() || !IsTargetAt(point, processId)) return false;

                    INPUT[] inputs = new INPUT[2];
                    inputs[0].type = INPUT_MOUSE;
                    inputs[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;

                    inputs[1].type = INPUT_MOUSE;
                    inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;

                    var sent = SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
                    if (sent != 2)
                    {
                        // Release a potentially inserted down event before reporting failure.
                        if (sent == 1) SendInput(1, new[] { inputs[1] }, Marshal.SizeOf(typeof(INPUT)));
                        return false;
                    }
                    Thread.Sleep(20);
                }
                finally
                {
                    SetCursorPos(original.X, original.Y);
                }

                Console.WriteLine($"[ClickAutomation] Clicked ({x}, {y}) using SendInput and restored cursor to ({original.X}, {original.Y})");

                completion?.Invoke();
                return true;
            }
        }
    }
}

