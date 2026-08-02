using System;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using NoInteraction.Core;
using NoInteraction.UI;

namespace NoInteraction
{
    public partial class App : System.Windows.Application
    {
        private static Mutex? _instanceLock;

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            ShutdownMode = ShutdownMode.OnExplicitShutdown;

            // Kill any previous orphan instances completely
            try
            {
                var currentProc = Process.GetCurrentProcess();
                var others = Process.GetProcessesByName("NoInteraction").Where(p => p.Id != currentProc.Id).ToList();
                foreach (var p in others)
                {
                    try
                    {
                        p.Kill();
                        p.WaitForExit(1000);
                    }
                    catch { }
                    finally { p.Dispose(); }
                }
            }
            catch { }

            // The kill step above isn't atomic — two near-simultaneous launches could both
            // see no conflicting process and both survive. Claim a named mutex to guarantee
            // only one of them actually proceeds; the loser just steps aside.
            _instanceLock = new Mutex(true, "Local\\NoInteraction_SingleInstance_Mutex", out bool acquired);
            if (!acquired)
            {
                Shutdown();
                return;
            }

            // Touch ApproverEngine.Shared to start the scan timer immediately.
            _ = ApproverEngine.Shared;

            // Setup System Tray Icon & Context Menu
            TrayManager.Shared.Setup();

            // Display the main Dashboard window immediately on startup
            TrayManager.Shared.ShowDashboard();

            Console.WriteLine("NoInteraction started — listening for Antigravity/VS Code prompts");
        }

        protected override void OnExit(ExitEventArgs e)
        {
            try { ApproverEngine.Shared.Dispose(); } catch { }
            try { TrayManager.Shared.Dispose(); } catch { }
            try { _instanceLock?.ReleaseMutex(); } catch { }
            try { _instanceLock?.Dispose(); } catch { }
            base.OnExit(e);
        }
    }
}



