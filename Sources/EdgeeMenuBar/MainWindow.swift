import AppKit
import SwiftUI

/// Manages the app's on-demand main window — the "full app" surface, opened from
/// the menubar rather than at launch.
///
/// The app stays a menubar accessory (`LSUIElement`, no Dock icon) until the user
/// opens this window; then we switch the activation policy to `.regular` so a Dock
/// icon and app-switcher entry appear, and switch back to `.accessory` when it
/// closes. That gives the Docker-Desktop feel — a real windowed app while you're
/// in it, out of the way when you're not — without a window popping up at launch
/// (which a SwiftUI `Window` scene would do on macOS 14).
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()

    private var window: NSWindow?

    /// Show (creating on first use) the main window, bringing the app forward and
    /// revealing its Dock icon. The window is cached and reused across opens.
    func show(model: MenuModel, relays: RelayManager) {
        NSApp.setActivationPolicy(.regular)

        if window == nil {
            let root = MainWindowView()
                .environmentObject(model)
                .environmentObject(relays)
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "Edgee"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 880, height: 580))
            window.setFrameAutosaveName("EdgeeMainWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window drops us back to a menubar-only accessory (no Dock icon).
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
