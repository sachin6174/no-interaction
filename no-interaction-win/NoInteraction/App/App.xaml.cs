using System;
using System.Windows;
using NoInteraction.Core;
using NoInteraction.UI;

namespace NoInteraction
{
    public partial class App : System.Windows.Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            // Touch ApproverEngine.Shared to start the scan timer immediately.
            _ = ApproverEngine.Shared;

            TrayManager.Shared.Setup();

            Dispatcher.BeginInvoke(new Action(() => TrayManager.Shared.ShowDashboard()));

            Console.WriteLine("NoInteraction started — listening for Antigravity/VS Code prompts");
        }

        protected override void OnExit(ExitEventArgs e)
        {
            ApproverEngine.Shared.Dispose();
            TrayManager.Shared.Dispose();
            base.OnExit(e);
        }
    }
}
