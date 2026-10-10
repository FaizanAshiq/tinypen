import CoreGraphics

/// How every mark is drawn, on screen and in the tests alike.
public enum MarkRenderer {
    public static func draw(_ mark: Mark, in context: CGContext) {
        let color = Palette.color(mark.colorHex)
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineJoin(.round)
        switch mark.kind {
        case .stroke:
            context.setLineCap(.round)
            context.setLineWidth(mark.width)
            context.setStrokeColor(color)
            context.addPath(mark.path)
            context.strokePath()
        case .highlight:
            // Drawn opaque inside a layer that is faded as a whole, so the stroke never darkens
            // where it crosses itself. Round ends: flat ones looked chopped off, and left dark
            // wedges where a stroke hooked back near its start or end.
            context.setAlpha(0.4)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setLineCap(.round)
            context.setLineWidth(mark.width)
            context.setStrokeColor(color)
            context.addPath(mark.path)
            context.strokePath()
            context.endTransparencyLayer()
        case .arrow:
            context.setFillColor(color)
            context.setStrokeColor(color)
            context.setLineWidth(mark.width * 0.5)
            context.addPath(mark.path)
            context.drawPath(using: .fillStroke)
        case .box:
            context.setLineWidth(mark.width)
            context.setStrokeColor(color)
            context.addPath(mark.path)
            context.strokePath()
        }
    }
}
