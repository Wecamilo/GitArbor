import SwiftUI

/// Moldura das telas de entrada do Git Arbor: um cartão dividido, com o painel da árvore
/// (verde-azulado) à esquerda e a ação à direita, sobre um fundo com galhos de Git.
struct AuthShell<Side: View, Content: View>: View {
    var contentWidth: CGFloat = 420
    @ViewBuilder var side: Side
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                BranchField().ignoresSafeArea()
                HStack(spacing: 0) {
                    ZStack {
                        Theme.accent
                        side.padding(30)
                    }
                    .frame(width: 300)
                    ScrollView {
                        content
                            .frame(width: contentWidth)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 40)
                            .frame(minHeight: min(geo.size.height - 60, 640))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
                .frame(height: min(geo.size.height - 60, 640))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: Theme.accent.opacity(0.18), radius: 40, y: 18)
                .padding(30)
            }
        }
    }
}

/// Painel da esquerda: árvore branca, nome e frase.
struct AuthSidePanel<Footer: View>: View {
    /// Frase abaixo do nome (a tela de bloqueio não tem).
    var tagline: String? = nil
    /// Depois de confirmar o dono, as pastas brancas ganham as cores do ícone.
    var colored = false
    @ViewBuilder var footer: Footer
    @ViewState private var grown: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                ArborGlyph(branches: grown, nodes: grown, style: AnyShapeStyle(Color.white))
                    .opacity(colored ? 0 : 1)
                ArborGlyph(branches: grown, nodes: grown)
                    .opacity(colored ? 1 : 0)
                    .scaleEffect(colored ? 1.04 : 1)
            }
            .frame(width: 140, height: 140)
            .padding(-22)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            Spacer().frame(height: 28)
            Text("Git Arbor")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if let tagline {
                Text(tagline)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            Spacer()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            withAnimation(.easeInOut(duration: 1.1)) { grown = 1 }
        }
    }
}

/// Fundo decorativo: faixas verticais de “histórico” com galhos que saem e voltam.
struct BranchField: View {
    var tint: Color = Theme.accent
    var density: Double = 1

    var body: some View {
        Canvas { ctx, size in
            let lane: CGFloat = 70 / density
            let lanes = Int(size.width / lane) + 1
            var rng = SeededRandom(seed: 7)
            for i in 0..<lanes {
                let x = CGFloat(i) * lane + lane / 2
                let opacity = 0.035 + rng.next() * 0.04
                var trunk = Path()
                trunk.move(to: CGPoint(x: x, y: 0))
                trunk.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(trunk, with: .color(tint.opacity(opacity)), lineWidth: 2)
                var y = rng.next() * 80
                while y < size.height {
                    let r: CGFloat = 4 + rng.next() * 3
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(tint.opacity(opacity * 1.8)))
                    if rng.next() > 0.72, i < lanes - 1 {
                        // Galho para a faixa vizinha, que volta mais abaixo.
                        var b = Path()
                        let span = 60 + rng.next() * 90
                        b.move(to: CGPoint(x: x, y: y))
                        b.addCurve(to: CGPoint(x: x + lane, y: y + span),
                                   control1: CGPoint(x: x, y: y + span * 0.6),
                                   control2: CGPoint(x: x + lane, y: y + span * 0.4))
                        ctx.stroke(b, with: .color(tint.opacity(opacity)), lineWidth: 2)
                    }
                    y += 50 + rng.next() * 90
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Gerador fixo para o desenho do fundo ser sempre igual.
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}

/// Anel de “commits” em volta da digital. Enquanto espera, as bolinhas seguem uma coreografia
/// que muda a cada poucos segundos: giram num sentido, voltam no outro, piscam soltas, respiram
/// juntas e se fecham e abrem pelos dois lados. Se a espera passa de ~25 s, o anel descansa
/// quase apagado por alguns segundos e depois acorda com uma volta rápida e começa de novo.
struct NodeRing: View {
    enum Mode { case waiting, paused, failed, success }
    var mode: Mode
    var count = 12
    @ViewState private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: mode != .waiting)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let glows = mode == .waiting
                ? RingChoreography.glows(at: elapsed, count: count)
                : Array(repeating: mode == .success ? 1 : 0.25, count: count)
            let ringOpacity = mode == .waiting ? 0.12 + 0.1 * RingChoreography.activity(at: elapsed) : (mode == .success ? 0.9 : 0.18)
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) / 2 - 6
                let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Circle()
                        .stroke(color.opacity(ringOpacity), lineWidth: mode == .success ? 3 : 1.5)
                        .frame(width: r * 2, height: r * 2)
                        .position(c)
                    ForEach(0..<count, id: \.self) { i in
                        let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                        let glow = glows[i]
                        Circle()
                            .fill(color.opacity(0.22 + 0.78 * glow))
                            .frame(width: 7 + 4 * glow, height: 7 + 4 * glow)
                            .shadow(color: color.opacity(mode == .waiting ? 0.6 * glow : 0), radius: 5 * glow)
                            .position(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
                    }
                }
            }
        }
        .onChange(of: mode) { _, new in
            if new == .waiting { start = Date() }
        }
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch mode {
        case .failed: .red
        case .paused: .secondary
        default: Theme.accent
        }
    }
}

/// Roteiro do anel: um giro só, sem pressa. A bolinha da frente acende devagar enquanto as de
/// trás apagam mais devagar ainda, deixando um rastro suave. Depois de ~25 s de espera o anel
/// descansa quase apagado por alguns segundos e então volta a girar.
enum RingChoreography {
    /// Segundos para uma volta inteira (no começo era menos de 1 s).
    static let lap = 7.5
    /// Quanto da volta a bolinha leva para acender antes de a “cabeça” chegar.
    static let rise = 0.09
    /// Quanto da volta o rastro leva para apagar.
    static let tail = 0.5
    static let activeLength = 25.0
    static let restLength = 5.0
    static let fade = 1.2
    static var cycle: Double { activeLength + restLength }

    /// Quanto o anel está “acordado” (0 descansando, 1 girando).
    static func activity(at t: Double) -> Double {
        let local = t.truncatingRemainder(dividingBy: cycle)
        if local < fade { return smooth(local / fade) }
        if local < activeLength - fade { return 1 }
        if local < activeLength { return smooth((activeLength - local) / fade) }
        return 0
    }

    static func glows(at t: Double, count: Int) -> [Double] {
        let local = t.truncatingRemainder(dividingBy: cycle)
        let awake = activity(at: t)
        let head = local / lap
        let h = head - floor(head)
        let resting = 0.06 + 0.04 * (0.5 + 0.5 * sin(t * 1.1))
        return (0..<count).map { i in
            let position = Double(i) / Double(count)
            var behind = h - position          // quanto a cabeça já passou desta bolinha
            behind -= floor(behind)
            let glow: Double
            if behind > 1 - rise {
                // A cabeça está chegando: acende devagar.
                glow = smooth((behind - (1 - rise)) / rise)
            } else if behind < tail {
                // Já passou: apaga mais devagar ainda.
                glow = pow(1 - behind / tail, 1.8)
            } else {
                glow = 0
            }
            return resting + (glow * 0.94 - resting) * awake
        }
    }

    static func smooth(_ x: Double) -> Double {
        let k = min(1, max(0, x))
        return k * k * (3 - 2 * k)
    }
}
