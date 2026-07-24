using System;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using NoInteraction.Core;
using NoInteraction.UI;

namespace NoInteraction
{
    public partial class App : System.Windows.Application
    {
        private static Mutex? _mutex;
        private static EventWaitHandle? _showEventHandle;

        protected override void OnStartup(StartupEventArgs e)
        {
            const string mutexName = "NoInteraction_SingleInstance_Mutex";
            const string eventName = "NoInteraction_SingleInstance_ShowEvent";

            _mutex = new Mutex(true, mutexName, out bool isNewInstance);
            _showEventHandle = new EventWaitHandle(false, EventResetMode.AutoReset, eventName);

            if (!isNewInstance)
            {
                // Signal the already-running instance to show its Dashboard window, then exit.
                _showEventHandle.Set();
                Environment.Exit(0);
                return;
            }

            base.OnStartup(e);

            // Listen for signals from double-clicks or shortcut launches while already running.
            ThreadPool.RegisterWaitForSingleObject(_showEventHandle, (state, timedOut) =>
            {
                Dispatcher.BeginInvoke(new Action(() => TrayManager.Shared.ShowDashboard()));
            }, null, -1, false);

            // Touch ApproverEngine.Shared to start the scan timer immediately.
            _ = ApproverEngine.Shared;

            // Setup System Tray Icon & Context Menu
            TrayManager.Shared.Setup();

            // Display the main Dashboard window immediately on startup
            Dispatcher.BeginInvoke(new Action(() => TrayManager.Shared.ShowDashboard()), DispatcherPriority.Loaded);

            Console.WriteLine("NoInteraction started — listening for Antigravity/VS Code prompts");
        }

        protected override void OnExit(ExitEventArgs e)
        {
            ApproverEngine.Shared.Dispose();
            TrayManager.Shared.Dispose();
            _mutex?.ReleaseMutex();
            base.OnExit(e);
        }
    }
}
