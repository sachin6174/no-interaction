"""Entry point wiring the engine, tray icon, and dashboard together."""

from __future__ import annotations

from .approver_engine import ApproverEngine
from .dashboard import Dashboard
from .tray_manager import TrayManager


def main() -> None:
    # Instantiate the engine first so the scan loop starts immediately.
    ApproverEngine.shared()

    dashboard = Dashboard()

    tray = TrayManager.shared()
    tray.set_show_dashboard_callback(lambda: dashboard.after(0, dashboard.show))
    tray.set_quit_callback(lambda: dashboard.after(0, dashboard.destroy))
    tray.setup()

    print("NoInteraction started — listening for Antigravity/VS Code prompts")

    dashboard.show()
    dashboard.mainloop()

    tray.shutdown()


if __name__ == "__main__":
    main()
