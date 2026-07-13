import Cocoa
import CoreGraphics

public final class ClickAutomation {
    public static let shared = ClickAutomation()
    private init() {}

    /// Performs a precise hardware click at screen coordinates `point`.
    /// Immediately restores the user's original mouse cursor position so typing & editing are never interrupted.
    public func performClick(at point: CGPoint, targetPid: pid_t, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInteractive).async {
            let source = CGEventSource(stateID: .hidSystemState)

            // Save user's current mouse position before clicking
            let originalPos = CGEvent(source: nil)?.location

            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,    mouseCursorPosition: point, mouseButton: .left)
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            let up   = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,   mouseCursorPosition: point, mouseButton: .left)

            // Move to target & post click
            move?.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.01)

            down?.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.03)

            up?.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.01)

            // Instantly restore original cursor position
            if let restorePt = originalPos,
               let restoreMove = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: restorePt, mouseButton: .left) {
                restoreMove.post(tap: .cgSessionEventTap)
            }

            print("🎯 ClickAutomation: Clicked (\(Int(point.x)), \(Int(point.y))) and restored mouse position to \(originalPos ?? .zero)")

            if let cb = completion {
                DispatchQueue.main.async { cb() }
            }
        }
    }
}
