import SwiftUI

/// Fountain-pen nib (unit coordinates, tip at the bottom).
struct NibShape: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 1.0))
        path.addCurve(to: p(0.06, 0.42), control1: p(0.36, 0.84), control2: p(0.06, 0.62))
        path.addLine(to: p(0.12, 0.0))
        path.addLine(to: p(0.88, 0.0))
        path.addLine(to: p(0.94, 0.42))
        path.addCurve(to: p(0.5, 1.0), control1: p(0.94, 0.62), control2: p(0.64, 0.84))
        path.closeSubpath()
        return path
    }
}

/// The nib's slit and breather hole, cut out of the nib.
struct NibSlit: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        let d = r.width * 0.16
        path.addEllipse(in: CGRect(x: p(0.5, 0.42).x - d / 2, y: p(0.5, 0.42).y - d / 2, width: d, height: d))
        path.addRect(CGRect(x: p(0.5, 0).x - r.width * 0.025, y: p(0, 0.45).y, width: r.width * 0.05, height: r.height * 0.5))
        return path
    }
}

/// The ink line: a short waveform that swells under the nib's tip.
struct InkWave: Shape {
    func path(in r: CGRect) -> Path {
        var path = Path()
        let steps = 80
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let envelope = exp(-pow((t - 0.5) * 3.2, 2))
            let y = r.midY + sin(t * .pi * 7) * envelope * r.height * 0.5
            let pt = CGPoint(x: r.minX + t * r.width, y: y)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        return path
    }
}

/// Quill's logo. `tile` draws the dark rounded background used for the app icon.
struct QuillLogo: View {
    var tile = true

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if tile {
                    RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x231C15), Color(hex: 0x0D0B09)], startPoint: .top, endPoint: .bottom))
                    RadialGradient(colors: [Theme.accent.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: s * 0.5)
                        .clipShape(RoundedRectangle(cornerRadius: s * 0.225, style: .continuous))
                    RoundedRectangle(cornerRadius: s * 0.225, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Theme.accent.opacity(0.45), Theme.accent.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                                      lineWidth: max(1, s * 0.012))
                }
                let nibW = s * 0.27, nibH = s * 0.42
                ZStack {
                    NibShape().fill(LinearGradient(colors: [Color(hex: 0xF6C46A), Theme.accent, Color(hex: 0xB8741F)], startPoint: .top, endPoint: .bottom))
                    NibSlit().fill(Color(hex: 0x120E0A)).blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(width: nibW, height: nibH)
                .shadow(color: Theme.accent.opacity(0.55), radius: s * 0.05)
                .position(x: s * 0.5, y: s * 0.38)

                InkWave()
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: max(1.2, s * 0.022), lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.accent.opacity(0.7), radius: s * 0.03)
                    .frame(width: s * 0.64, height: s * 0.14)
                    .position(x: s * 0.5, y: s * 0.67)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Renders the logo to an .iconset folder (used by scripts/make_icon.sh).
@MainActor
enum IconRenderer {
    static func render(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                // macOS icons sit inside a ~10% transparent margin.
                let view = QuillLogo().padding(CGFloat(px) * 0.09).frame(width: CGFloat(px), height: CGFloat(px))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let cg = renderer.cgImage else { continue }
                let rep = NSBitmapImageRep(cgImage: cg)
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
        }
    }
}
