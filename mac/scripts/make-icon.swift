import AppKit

// Draws Tinypen's icon at 1024 pixels: Tinysnap's rounded square in coral, with a white scribble
// ending in a dot. Usage: swift scripts/make-icon.swift out.png
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
context.addPath(shape)
context.setFillColor(CGColor(srgbRed: 1, green: 0.38, blue: 0.32, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [CGColor(srgbRed: 1, green: 0.47, blue: 0.40, alpha: 1),
                                   CGColor(srgbRed: 0.96, green: 0.27, blue: 0.27, alpha: 1)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
context.restoreGState()

// The scribble: a loop drawn in one stroke, rising to the right.
let line = CGMutablePath()
line.move(to: CGPoint(x: 270, y: 380))
line.addCurve(to: CGPoint(x: 470, y: 600), control1: CGPoint(x: 300, y: 560), control2: CGPoint(x: 380, y: 660))
line.addCurve(to: CGPoint(x: 480, y: 420), control1: CGPoint(x: 560, y: 540), control2: CGPoint(x: 560, y: 420))
line.addCurve(to: CGPoint(x: 700, y: 640), control1: CGPoint(x: 400, y: 420), control2: CGPoint(x: 560, y: 700))
context.addPath(line)
context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(64)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: 718, y: 662, width: 76, height: 76))

let image = context.makeImage()!
let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
