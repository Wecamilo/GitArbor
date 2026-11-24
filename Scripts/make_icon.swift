// Gera Resources/AppIcon.icns: quadro claro com três pastas/cartões empilhados
// (amarelo, rosa e azul) — os seus repositórios, um atrás do outro.
// Uso: swift Scripts/make_icon.swift <pasta de saída do .iconset>
import AppKit
import CoreGraphics

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let cs = CGColorSpace(name: CGColorSpace.displayP3)!

func C(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
}
func W(_ a: CGFloat) -> CGColor { CGColor(colorSpace: cs, components: [1, 1, 1, a])! }

/// Cartões em coordenadas do quadro (0…1, y para baixo): x, y, largura, cores do degradê.
/// Mesmas medidas de ArborCards no app.
let cards: [(x: CGFloat, y: CGFloat, w: CGFloat, top: UInt32, bottom: UInt32)] = [
    (0.28, 0.24, 0.44, 0xFFC86B, 0xF29A26),
    (0.25, 0.33, 0.50, 0xFF8FA8, 0xE84A73),
    (0.22, 0.42, 0.56, 0x7CC4FF, 0x2C74E8)
]

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1) // y para baixo
    // Grade da Apple: o quadro ocupa ~80% com margem para a sombra.
    let inset = s * 0.098
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = tile.width * 0.2237
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + tile.width * x, y: tile.minY + tile.height * y) }
    func l(_ v: CGFloat) -> CGFloat { tile.width * v }
    func linear(_ path: CGPath, _ colors: [CGColor], _ a: CGPoint, _ b: CGPoint) {
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        let g = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    func rim(_ path: CGPath, _ w: CGFloat, _ top: CGFloat) {
        let edge = path.copy(strokingWithWidth: l(w), lineCap: .round, lineJoin: .round, miterLimit: 10)
        let box = path.boundingBox
        linear(edge, [W(top), W(0)], CGPoint(x: box.midX, y: box.minY), CGPoint(x: box.midX, y: box.maxY))
    }

    // Quadro.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.028, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(tilePath); ctx.setFillColor(C(0xF4F6FA)); ctx.fillPath()
    ctx.restoreGState()
    linear(tilePath, [C(0xF4F6FA), C(0xDDE3EC)], p(0.5, 0), p(0.5, 1))

    ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
    for card in cards {
        let path = CGPath(roundedRect: CGRect(x: p(card.x, card.y).x, y: p(card.x, card.y).y, width: l(card.w), height: l(0.4)),
                          cornerWidth: l(0.07), cornerHeight: l(0.07), transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -l(0.02)), blur: l(0.035), color: CGColor(gray: 0, alpha: 0.22))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        linear(path, [C(card.top), C(card.bottom)], p(0.5, card.y), p(0.5, card.y + 0.4))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        rim(path, 0.006, 0.8)
    }
    // Brilho do vidro do quadro.
    linear(tilePath, [W(0.3), W(0)], p(0.5, 0), p(0.5, 0.5))
    ctx.restoreGState()
    rim(tilePath, 0.006, 0.5)

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(output)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(output)/icon_\(base)x\(base)@2x.png"))
}
print("ok")
