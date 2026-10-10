import AppKit

/// Screen Recording, which only the zoom lens needs.
@MainActor
enum ScreenAccess {
    /// Checked rather than requested, so nothing prompts before the zoom lens is
    /// first used. This reports the permission row, not whether a capture will succeed:
    /// macOS can list the app and still hand over nothing, which the capture itself
    /// finds out.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func request() {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
