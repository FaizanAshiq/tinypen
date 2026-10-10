import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TinypenCore

/// The marks drawn on a white canvas, y counting down as on the screen layer.
struct RenderTests {
    private static let side = 200

    private func render(_ marks: [Mark]) -> CGContext {
        let context = CGContext(data: nil, width: Self.side, height: Self.side, bitsPerComponent: 8, bytesPerRow: Self.side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
        context.translateBy(x: 0, y: CGFloat(Self.side))
        context.scaleBy(x: 1, y: -1)
        marks.forEach { MarkRenderer.draw($0, in: context) }
        return context
    }

    /// Red, green and blue at a point, from the top left.
    private func pixel(_ context: CGContext, _ x: Int, _ y: Int) -> [Int] {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let at = y * context.bytesPerRow + x * 4
        return [Int(bytes[at]), Int(bytes[at + 1]), Int(bytes[at + 2])]
    }

    private let white = [255, 255, 255]

    @Test func aHighlighterNeverDarkensWhereItCrossesItself() {
        let points = [CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100), CGPoint(x: 100, y: 30), CGPoint(x: 100, y: 170)]
        let context = render([Mark(kind: .highlight(points), colorHex: "#FFCC00", width: 20)])
        let once = pixel(context, 40, 100)
        let crossing = pixel(context, 100, 100)
        #expect(once != white)
        #expect(zip(once, crossing).allSatisfy { abs($0 - $1) <= 2 })
    }

    /// A hand often starts a stroke with a little hook back. Reported: flat ends left dark wedges
    /// there, and the ends looked chopped off.
    @Test func aHighlighterCoversEverywhereThePointerWentEndsIncluded() {
        let forward: [CGPoint] = (0...12).map { CGPoint(x: 40 + CGFloat($0), y: 100) }
        let back: [CGPoint] = (1...4).map { CGPoint(x: 52 - CGFloat($0), y: 100 + CGFloat($0) / 2) }
        let on: [CGPoint] = (1...120).map { CGPoint(x: 48 + CGFloat($0), y: (102 + CGFloat($0) / 10).rounded()) }
        let points = forward + back + on
        let context = render([Mark(kind: .highlight(points), colorHex: "#34C759", width: 48)])
        let inside = pixel(context, 120, 108)
        for x in 20...70 {
            for y in 80...120 where points.contains(where: { hypot($0.x - CGFloat(x), $0.y - CGFloat(y)) < 16 }) {
                #expect(zip(pixel(context, x, y), inside).allSatisfy { abs($0 - $1) <= 2 }, "\(x), \(y)")
            }
        }
    }

    @Test func aClickWithThePenLeavesADot() {
        let context = render([Mark(kind: .stroke([CGPoint(x: 100, y: 100)]), colorHex: "#FF3B30", width: 10)])
        #expect(pixel(context, 100, 100) != white)
        #expect(pixel(context, 110, 100) == white)
    }

    @Test func anArrowHasAFilledHeadAtItsTip() {
        let context = render([Mark(kind: .arrow(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 180, y: 100)), colorHex: "#FF3B30",
                                   width: 6)])
        #expect(pixel(context, 165, 100) != white)
        #expect(pixel(context, 165, 108) != white)
        #expect(pixel(context, 30, 110) == white)
    }

    @Test func aBoxIsOutlinedNotFilled() {
        let context = render([Mark(kind: .box(CGRect(x: 50, y: 50, width: 100, height: 100)), colorHex: "#007AFF", width: 4)])
        #expect(pixel(context, 50, 100) != white)
        #expect(pixel(context, 100, 100) == white)
    }

    /// Writes every kind of mark to a PNG to look at, when TINYPEN_SAMPLE names a file.
    @Test func sample() throws {
        guard let path = ProcessInfo.processInfo.environment["TINYPEN_SAMPLE"] else { return }
        let context = render([
            Mark(kind: .stroke([CGPoint(x: 20, y: 40), CGPoint(x: 50, y: 20), CGPoint(x: 80, y: 45), CGPoint(x: 110, y: 25)]),
                 colorHex: "#FF3B30", width: 4),
            Mark(kind: .highlight([CGPoint(x: 20, y: 80), CGPoint(x: 180, y: 80), CGPoint(x: 120, y: 60), CGPoint(x: 120, y: 110)]),
                 colorHex: "#FFCC00", width: 14),
            Mark(kind: .arrow(from: CGPoint(x: 20, y: 170), to: CGPoint(x: 110, y: 120)), colorHex: "#34C759", width: 6),
            Mark(kind: .box(CGRect(x: 130, y: 130, width: 55, height: 45)), colorHex: "#007AFF", width: 4),
        ])
        let url = URL(fileURLWithPath: path) as CFURL
        let destination = try #require(CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
