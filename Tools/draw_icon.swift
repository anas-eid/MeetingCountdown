// Renders the Harri NextUp app icon at 1024x1024 in the Harri brand palette.
// Usage: swift draw_icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, like a design tool.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [])
}

// MARK: Background tile (macOS icon grid: 824pt body, 100pt margin)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.28))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(0x0088DD))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
linear([rgb(0x0088DD), rgb(0x002137)], from: CGPoint(x: 0, y: 100), to: CGPoint(x: 0, y: 924))
ctx.restoreGState()

// MARK: Calendar page

let card = CGRect(x: 232, y: 250, width: 560, height: 540)
let cardPath = CGPath(roundedRect: card, cornerWidth: 84, cornerHeight: 84, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x00182A, 0.35))
ctx.addPath(cardPath)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Header strip, clipped to the card's rounded top.
let headerHeight: CGFloat = 150
ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
ctx.clip(to: CGRect(x: card.minX, y: card.minY, width: card.width, height: headerHeight))
linear([rgb(0xFF7B4A), rgb(0xF15B2C)], from: CGPoint(x: 0, y: card.minY),
       to: CGPoint(x: 0, y: card.minY + headerHeight))
ctx.restoreGState()

// Binder rings.
for x in [card.minX + 150, card.maxX - 150] {
    let ring = CGRect(x: x - 22, y: card.minY - 44, width: 44, height: 104)
    ctx.addPath(CGPath(roundedRect: ring, cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setFillColor(rgb(0xE7F3FF, 0.95))
    ctx.fillPath()
    let hole = CGRect(x: x - 26, y: card.minY + 44, width: 52, height: 30)
    ctx.addEllipse(in: hole)
    ctx.setFillColor(rgb(0xB83A12, 0.55))
    ctx.fillPath()
}

// MARK: Countdown ring

let bodyTop = card.minY + headerHeight
let center = CGPoint(x: card.midX, y: bodyTop + (card.maxY - bodyTop) / 2 + 4)
let radius: CGFloat = 128
let lineWidth: CGFloat = 46

ctx.setLineCap(.round)
ctx.setLineWidth(lineWidth)

ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.setStrokeColor(rgb(0xE7F3FF))
ctx.strokePath()

// About three quarters left, running clockwise from 12 o'clock. In the
// flipped context, increasing angles run clockwise on screen.
let start = -CGFloat.pi / 2
let end = start + .pi * 2 * 0.72
ctx.saveGState()
ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
ctx.replacePathWithStrokedPath()
ctx.clip()
linear([rgb(0x2CE3A0), rgb(0x0088DD)], from: CGPoint(x: center.x + radius, y: center.y - radius),
       to: CGPoint(x: center.x - radius, y: center.y + radius))
ctx.restoreGState()

// Clock hand pointing at the arc's leading edge, and a hub.
let handLength = radius - lineWidth / 2 - 30
let hand = CGPoint(x: center.x + cos(end) * handLength, y: center.y + sin(end) * handLength)
ctx.setLineWidth(22)
ctx.setStrokeColor(rgb(0x002137))
ctx.move(to: center)
ctx.addLine(to: hand)
ctx.strokePath()
ctx.addEllipse(in: CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48))
ctx.setFillColor(rgb(0x002137))
ctx.fillPath()

// MARK: Write

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
