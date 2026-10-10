import AppKit
import CoreMedia
import ScreenCaptureKit

/// The latest picture of a display, handed from the capture queue to the main thread.
struct ZoomFrame: @unchecked Sendable {
    let surface: IOSurfaceRef
}

/// A live picture of one display, Tinypen's own windows left out, for the zoom lens. It runs
/// only while zoom is on, and follows the pointer from display to display.
@MainActor
final class ZoomFeed {
    private var stream: SCStream?
    private var output: FrameOutput?
    private(set) var displayID: CGDirectDisplayID?
    private(set) var frame: IOSurfaceRef?
    /// The display could not be read, most likely as Screen Recording is not allowed.
    var onRefused: (() -> Void)?
    /// Counts every start and stop, so a capture that finishes opening after either knows it is stale.
    /// Found reading: zoom off and on again, before the first capture had opened, left both opening
    /// for the same display, and one ran on unseen, never stopped.
    private var generation = 0

    func start(on displayID: CGDirectDisplayID) {
        guard displayID != self.displayID else { return }
        stop()
        self.displayID = displayID
        let generation = generation
        Task { [weak self] in
            await self?.open(displayID, generation: generation)
        }
    }

    func stop() {
        generation += 1
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
        output = nil
        displayID = nil
        frame = nil
    }

    private func open(_ displayID: CGDirectDisplayID, generation: Int) async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            if self.generation == generation { onRefused?() }
            return
        }
        // Stopped, or started again, meanwhile.
        guard self.generation == generation else { return }
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let scale = NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 4
        configuration.colorSpaceName = CGColorSpace.sRGB

        let output = FrameOutput { [weak self] frame in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.frame = frame.surface
                }
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "Tinypen zoom"))
            try await stream.startCapture()
        } catch {
            if self.generation == generation { onRefused?() }
            return
        }
        guard self.generation == generation else {
            try? await stream.stopCapture()
            return
        }
        self.stream = stream
        self.output = output
    }
}

/// Receives the display's frames on the capture queue.
private final class FrameOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let deliver: @Sendable (ZoomFrame) -> Void

    init(deliver: @escaping @Sendable (ZoomFrame) -> Void) {
        self.deliver = deliver
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue() else { return }
        deliver(ZoomFrame(surface: surface))
    }
}
