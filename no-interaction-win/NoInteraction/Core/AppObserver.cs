using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Automation;

namespace NoInteraction.Core
{
    public sealed class AppObserver
    {
        public static readonly AppObserver Shared = new();

        /// <summary>Process/window-title fragments to monitor — matches by substring (case-insensitive).
        /// Deliberately excludes bare "Code"/"chat": as substrings they match almost anything (any app
        /// or window with "code" or "chat" anywhere in its title/name — the actual cause of this app
        /// scanning and clicking inside unrelated windows). VS Code is still caught precisely via its
        /// exact process name ("Code.exe") in FindTargetApplications/IsEditor below, and via its
        /// window title, which normally does include "Visual Studio Code".</summary>
        public List<string> TargetAppNames { get; } = new()
        {
            "Antigravity",
            "Anti-Gravity",
            "AntiGravity",
            "Visual Studio Code",
            "VS Code",
            "VSCode",
            "Cursor",
            "Windsurf",
            "Chrome",
            "msedge",
            "Edge",
            "Brave",
            "Firefox",
            "Opera",
            "Vivaldi",
            "Arc"
        };

        /// <summary>Exact (not substring) process names that identify an editor precisely.</summary>
        private static readonly string[] EditorProcessNames = { "code" };

        private static readonly string[] EditorNames =
        {
            "visual studio code", "vs code", "vscode", "cursor", "windsurf", "antigravity"
        };

        private static readonly string[] BrowserProcessNames =
        {
            "chrome", "msedge", "brave", "firefox", "opera", "vivaldi", "arc"
        };

        private static readonly string[] TerminalProcessNames =
        {
            "windowsterminal", "cmd", "powershell", "pwsh", "conhost"
        };

        private AppObserver() { }

        public bool IsTerminal(Process app)
        {
            var procName = (app.ProcessName ?? "").ToLowerInvariant();
            return TerminalProcessNames.Any(procName.Contains);
        }

        public bool IsEditor(Process app)
        {
            var procName = (app.ProcessName ?? "").ToLowerInvariant();
            if (EditorProcessNames.Contains(procName)) return true;

            var name = (SafeMainWindowTitle(app) + " " + procName);
            return EditorNames.Any(name.Contains);
        }

        public bool IsBrowser(Process app)
        {
            var procName = app.ProcessName.ToLowerInvariant();
            return BrowserProcessNames.Any(procName.Contains);
        }

        public bool IsBrowserOrEditor(Process app) => IsBrowser(app) || IsEditor(app);

        /// <summary>Checks whether a top-level window's title contains any Antigravity or target keyword.
        /// Deliberately excludes bare "chat"/"code": those match nearly any window title (a coding
        /// tool's own terminal tab, a support-chat widget, an unrelated "source code" article, ...),
        /// which was letting this app scan and click inside windows it was never meant to touch.</summary>
        public bool IsAntigravityWindow(AutomationElement window)
        {
            string title;
            try { title = window.Current.Name ?? ""; }
            catch { return false; }

            var lower = title.ToLowerInvariant();
            string[] keywords = { "antigravity", "anti-gravity", "agy", "gemini", "no-interaction" };
            return keywords.Any(lower.Contains);
        }

        /// <summary>Returns all running processes whose window title or process name contains a target name.</summary>
        public List<Process> FindTargetApplications(IEnumerable<string>? customTargets = null)
        {
            var allTargets = TargetAppNames.Concat(customTargets ?? Enumerable.Empty<string>())
                                            .Where(t => !string.IsNullOrEmpty(t))
                                            .ToList();

            var results = new List<Process>();
            var seenPids = new HashSet<int>();

            foreach (var proc in Process.GetProcesses())
            {
                // Process.GetProcesses() hands back a live handle per process; every one we
                // don't keep in `results` must be disposed here or it leaks a handle on every
                // scan tick (this loop runs every 1-3.5s for as long as the app is alive).
                var kept = false;
                try
                {
                    if (seenPids.Contains(proc.Id)) continue;

                    var title = SafeMainWindowTitle(proc);
                    var procName = proc.ProcessName ?? "";
                    var haystack = title + " " + procName;

                    bool isMatch = allTargets.Any(t => haystack.IndexOf(t, StringComparison.OrdinalIgnoreCase) >= 0)
                                 || EditorProcessNames.Contains(procName.ToLowerInvariant());
                    if (!isMatch) continue;

                    // Ensure the process has top-level windows before considering it active
                    var windows = GetTopLevelWindows(proc);
                    if (windows.Count > 0)
                    {
                        results.Add(proc);
                        seenPids.Add(proc.Id);
                        kept = true;
                    }
                }
                catch
                {
                    // Process may have exited or be inaccessible; skip it.
                }
                finally
                {
                    if (!kept) proc.Dispose();
                }
            }
            return results;
        }

        /// <summary>Returns all top-level UI Automation windows belonging to a process.</summary>
        public List<AutomationElement> GetTopLevelWindows(Process app)
        {
            var windows = new List<AutomationElement>();
            try
            {
                var condition = new PropertyCondition(AutomationElement.ProcessIdProperty, app.Id);
                var found = AutomationElement.RootElement.FindAll(TreeScope.Children, condition);
                foreach (AutomationElement el in found) windows.Add(el);
            }
            catch
            {
                // UI Automation can throw for windows mid-teardown; treat as "no windows".
            }
            return windows;
        }

        /// <summary>Returns the on-screen bounding rect of the largest relevant window for an app.</summary>
        public Rect? GetWindowBounds(Process app)
        {
            var windows = GetTopLevelWindows(app);
            if (windows.Count == 0) return null;

            var candidates = IsBrowser(app)
                ? windows.Where(IsAntigravityWindow).ToList()
                : windows;
            if (candidates.Count == 0) candidates = windows;

            Rect? best = null;
            double bestArea = 0;
            foreach (var win in candidates)
            {
                Rect rect;
                try { rect = win.Current.BoundingRectangle; }
                catch { continue; }
                if (rect.IsEmpty || rect.Width <= 50 || rect.Height <= 50) continue;
                var area = rect.Width * rect.Height;
                if (area > bestArea)
                {
                    bestArea = area;
                    best = rect;
                }
            }
            return best;
        }

        private static string SafeMainWindowTitle(Process app)
        {
            try { return app.MainWindowTitle ?? ""; }
            catch { return ""; }
        }
    }
}

