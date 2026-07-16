"""Entry point wiring the engine, tray icon, and dashboard together."""

from __future__ import annotations

import sys

# Perform startup checks for Linux system dependencies before importing other modules
missing_deps = []
try:
    import pyatspi
except ImportError:
    missing_deps.append("python3-pyatspi")

try:
    import gi
except ImportError:
    missing_deps.append("python3-gi")

if missing_deps:
    print(f"\n[Error] Missing required system accessibility/GUI bindings: {', '.join(missing_deps)}", file=sys.stderr)
    print("NoInteraction requires these system libraries to inspect windows and render the system tray.", file=sys.stderr)
    print("Please install them using your package manager:", file=sys.stderr)
    print(f"  Debian/Ubuntu: sudo apt install {' '.join(missing_deps)}", file=sys.stderr)
    print("Also ensure you launch the application via './run.sh' so that the virtual environment", file=sys.stderr)
    print("can access these system-wide packages.\n", file=sys.stderr)
    sys.exit(1)

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
