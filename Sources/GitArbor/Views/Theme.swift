import AppKit
import GitArborCore
import SwiftUI

/// No SDK atual, `@State` é uma macro cujo plugin só vem com o Xcode. O alias usa
/// o property wrapper `State` diretamente e compila também com as Command Line Tools.
typealias ViewState = SwiftUI.State

/// Tokens visuais: claro, arejado, o azul da pasta da frente do ícone como cor principal.
enum Theme {
    static let accent = Color(red: 0.17, green: 0.45, blue: 0.91)
    static let accentLight = Color(red: 0.49, green: 0.77, blue: 1.0)
    static let accentSoft = Color(red: 0.17, green: 0.45, blue: 0.91).opacity(0.12)
    static let corner: CGFloat = 10
    /// Fundo da barra de ferramentas: um tom abaixo do fundo da janela (claro e escuro).
    static let toolbar = Color(nsColor: NSColor(name: nil) { appearance in
        let base = NSColor.windowBackgroundColor
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var result = base
        appearance.performAsCurrentDrawingAppearance {
            result = base.usingColorSpace(.sRGB)?.blended(withFraction: dark ? 0.18 : 0.045, of: .black) ?? base
        }
        return result
    })
    static let cardCorner: CGFloat = 14
    static let gradient = LinearGradient(colors: [accentLight, accent], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let open = Color(red: 0.16, green: 0.65, blue: 0.33)
    static let closed = Color(red: 0.51, green: 0.31, blue: 0.85)
    static let danger = Color(red: 0.86, green: 0.22, blue: 0.22)
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x8E8E93
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static func language(_ name: String?) -> Color { Color(hex: Languages.hex(name)) }

    /// Cor do texto que fica legível sobre a cor da linguagem: escuro nas cores claras
    /// (amarelo do JavaScript, verde do Shell…), branco nas demais.
    static func onLanguage(_ name: String?) -> Color {
        Self.isLight(hex: Languages.hex(name)) ? Color.black.opacity(0.78) : .white
    }

    /// Luminância relativa (WCAG) acima do ponto em que o texto branco perde contraste.
    static func isLight(hex: String) -> Bool {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x8E8E93
        func channel(_ c: UInt64) -> Double {
            let x = Double(c) / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        let l = 0.2126 * channel((v >> 16) & 0xFF) + 0.7152 * channel((v >> 8) & 0xFF) + 0.0722 * channel(v & 0xFF)
        return l > 0.4
    }
}

// MARK: - Aparência

/// Claro, escuro ou igual ao sistema (Ajustes › Preferências).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    static var current: AppAppearance {
        UserDefaults.standard.string(forKey: key).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    /// Vale para todas as janelas, os Ajustes e o menu da barra de menus.
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Logo

/// Os três cartões (pastas) do logo, de trás para a frente, em coordenadas do quadro do ícone (0…1).
/// Mesmas medidas do Scripts/make_icon.swift.
enum ArborCards {
    struct Card { let x, y, w: CGFloat; let top, bottom: Color }
    static let height: CGFloat = 0.4
    static let corner: CGFloat = 0.07
    static let all: [Card] = [
        Card(x: 0.28, y: 0.24, w: 0.44, top: Color(hex: "FFC86B"), bottom: Color(hex: "F29A26")),
        Card(x: 0.25, y: 0.33, w: 0.50, top: Color(hex: "FF8FA8"), bottom: Color(hex: "E84A73")),
        Card(x: 0.22, y: 0.42, w: 0.56, top: Color(hex: "7CC4FF"), bottom: Color(hex: "2C74E8"))
    ]
}

/// Logo do app desenhado em SwiftUI (mesma forma do ícone). Acompanha o tema claro/escuro.
struct ArborMark: View {
    var size: CGFloat = 56
    @Environment(\.colorScheme) private var scheme

    static func tileGradient(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [Color(white: 0.24), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(white: 1), Color(white: 0.94)], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(Self.tileGradient(scheme))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: size * 0.06, y: size * 0.03)
            ArborGlyph()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Só o desenho do logo (as três pastas), sem o quadro; ocupa o mesmo espaço que ocuparia no ícone.
/// `branches` (0…1) faz as pastas de trás subirem; `nodes` (0…1) traz a da frente — para a abertura.
/// Sem `style`, as pastas têm as cores do ícone; com `style`, todas usam esse estilo em camadas.
struct ArborGlyph: View {
    var branches: CGFloat = 1
    var nodes: CGFloat = 1
    var style: AnyShapeStyle?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(ArborCards.all.enumerated()), id: \.offset) { k, card in
                    cardView(card, k, width: w)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// Quanto cada pasta já apareceu (0…1). Separado do corpo para o compilador checar os tipos rápido.
    private func progress(_ k: Int) -> CGFloat {
        if k == 2 { return nodes }
        let raw: CGFloat = branches * 2 - CGFloat(k)
        return min(1, max(0, raw))
    }

    private func cardView(_ card: ArborCards.Card, _ k: Int, width w: CGFloat) -> some View {
        let p: CGFloat = progress(k)
        let corner: CGFloat = w * ArborCards.corner
        let shine = LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)], startPoint: .top, endPoint: .center)
        let lift: CGFloat = (1 - p) * w * 0.08
        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill(card, k))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(shine, lineWidth: max(0.5, w * 0.006)))
            .shadow(color: .black.opacity(0.18), radius: w * 0.03, y: w * 0.018)
            .frame(width: w * card.w, height: w * ArborCards.height)
            .offset(x: w * card.x, y: w * card.y + lift)
            .opacity(Double(p))
    }

    private func fill(_ card: ArborCards.Card, _ k: Int) -> AnyShapeStyle {
        if let style { return AnyShapeStyle(style.opacity([0.45, 0.7, 1][k])) }
        return AnyShapeStyle(LinearGradient(colors: [card.top, card.bottom], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Entrada

/// Campo de texto com rótulo, no estilo das telas de entrada.
struct LabeledField: View {
    let label: String
    @Binding var text: String
    var secure = false
    var prompt = ""
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(label, text: $text, prompt: Text(prompt))
                } else {
                    TextField(label, text: $text, prompt: Text(prompt))
                }
            }
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Color.primary.opacity(0.12)))
            if let help {
                Text(help).font(.system(size: 11)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Área de texto grande com rótulo.
struct LabeledEditor: View {
    let label: String
    @Binding var text: String
    var height: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: height)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.corner))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Color.primary.opacity(0.12)))
                .accessibilityLabel(label)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(tint.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4), in: RoundedRectangle(cornerRadius: Theme.corner))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: Theme.corner))
            .contentShape(Rectangle())
    }
}

/// Botão compacto com ícone e texto (ações dentro das telas).
struct ActionButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(prominent ? tint.opacity(configuration.isPressed ? 0.8 : 1) : tint.opacity(configuration.isPressed ? 0.2 : 0.12),
                        in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(prominent ? Color.white : tint)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Fundo das telas de entrada.
struct AuthBackground<Content: View>: View {
    var width: CGFloat = 400
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 560)
                .ignoresSafeArea()
            ScrollView {
                content
                    .frame(width: width)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Peças visuais

/// Quadrado colorido com um ícone (como nos Ajustes do Sistema).
struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

/// Etiqueta arredondada (público/privado, situação etc.).
struct Pill: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// Número grande com rótulo e ícone.
struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = Theme.accent
    var hint: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                IconTile(symbol: symbol, tint: tint, size: 30)
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13, weight: .semibold))
                    if let hint {
                        Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Título de tela com explicação curta logo abaixo.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    var symbol: String?
    var tint: Color = Theme.accent
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let symbol { IconTile(symbol: symbol, tint: tint, size: 44) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 26, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, symbol: String? = nil, tint: Color = Theme.accent) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// Faixa de explicação para iniciantes (some quando o usuário desliga as explicações).
struct ExplainBanner: View {
    @Environment(AppModel.self) private var model
    let lessonID: String
    var text: String?

    var body: some View {
        if model.showExplanations, let lesson = Glossary.lesson(lessonID) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(lesson.title) (\(lesson.term))").font(.system(size: 13, weight: .semibold))
                    Text(text ?? lesson.summary + " " + lesson.analogy)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HelpTip(lessonID: lessonID, label: "Saber mais")
            }
            .padding(12)
            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Color.yellow.opacity(0.25)))
        }
    }
}

/// Botão “?” que explica um conceito num balão.
struct HelpTip: View {
    let lessonID: String
    var label: String?
    @ViewState private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            if let label {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .help("O que é isso?")
        .accessibilityLabel("Explicar \(Glossary.lesson(lessonID)?.title ?? "")")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            if let lesson = Glossary.lesson(lessonID) {
                LessonPopover(lesson: lesson)
            }
        }
    }
}

struct LessonPopover: View {
    @Environment(AppModel.self) private var model
    let lesson: Lesson

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(symbol: lesson.symbol, tint: .pink, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lesson.title).font(.system(size: 16, weight: .bold))
                    Text("No GitHub: \(lesson.term)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if lesson.diagram != .none {
                LessonDiagram(diagram: lesson.diagram)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
            }
            Text(lesson.explanation).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Label(lesson.analogy, systemImage: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { model.learning = lesson } label: { Label("Ver todas as lições", systemImage: "graduationcap.fill") }
                .buttonStyle(ActionButtonStyle(tint: .pink))
        }
        .padding(18)
        .frame(width: 360)
    }
}

/// Foto do perfil vinda do GitHub.
struct Avatar: View {
    let url: URL?
    var size: CGFloat = 28

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.08))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityHidden(true)
    }
}

/// Tela vazia com ícone grande e explicação.
struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(tint.opacity(0.7))
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

/// Carregando, com frase.
struct LoadingRow: View {
    var text = "Buscando no GitHub…"
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

/// Aviso flutuante de sucesso no rodapé da janela.
struct ToastView: View {
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol).foregroundStyle(Theme.accent)
            Text(toast.text).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Bolinha colorida + nome da linguagem.
struct LanguageTag: View {
    let name: String?
    var body: some View {
        if let name {
            HStack(spacing: 5) {
                Circle().fill(Color.language(name)).frame(width: 9, height: 9)
                Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Markdown

/// Mostra um README (Markdown) de forma simples: títulos, listas, código e parágrafos.
struct MarkdownView: View {
    let text: String

    private enum Block: Hashable {
        case heading(Int, String)
        case paragraph(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
        case quote(String)
        case rule
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { result.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix(while: { $0 == "#" }).count
                result.append(.heading(level, line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush(); result.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty, line[line.index(after: dot)...].hasPrefix(" ") {
                flush(); result.append(.numbered(String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...])))
            } else if line.hasPrefix(">") {
                flush(); result.append(.quote(line.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else if line == "---" || line == "***" || line == "___" {
                flush(); result.append(.rule)
            } else if line.hasPrefix("<") && line.hasSuffix(">") {
                continue // HTML solto: ignora
            } else {
                paragraph.append(line)
            }
        }
        if let code { result.append(.code(code.joined(separator: "\n"))) }
        flush()
        return result
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let s):
                    Text(inline(s))
                        .font(.system(size: level == 1 ? 22 : level == 2 ? 18 : 15, weight: .bold))
                        .padding(.top, level <= 2 ? 8 : 4)
                case .paragraph(let s):
                    Text(inline(s)).font(.system(size: 13.5)).lineSpacing(3)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.accent)
                        Text(inline(s)).font(.system(size: 13.5))
                    }
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(Theme.accent).monospacedDigit()
                        Text(inline(s)).font(.system(size: 13.5))
                    }
                case .code(let s):
                    ScrollView(.horizontal) {
                        Text(s).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                case .quote(let s):
                    Text(inline(s)).font(.system(size: 13.5)).foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.accent.opacity(0.4)).frame(width: 3) }
                case .rule:
                    Divider()
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Abre um endereço no navegador.
    func openURL(_ url: URL?) {
        if let url { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Filtros

/// Uma opção de filtro: valor, nome, ícone e (opcional) quantos itens tem.
struct ChipOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String
    var count: Int?
    var id: Value { value }
}

/// Filtro em pílulas, no visual do Git Arbor: trilho suave, pílula escolhida em degradê
/// que desliza até a nova escolha, ícone e contagem em cada opção.
struct FilterChips<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [ChipOption<Value>]
    var tint: Color = Theme.accent
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                ChipButton(option: option, selected: option.value == selection, tint: tint, namespace: namespace) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = option.value }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.045)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .fixedSize()
    }
}

private struct ChipButton<Value: Hashable>: View {
    let option: ChipOption<Value>
    let selected: Bool
    let tint: Color
    let namespace: Namespace.ID
    let action: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: option.symbol).font(.system(size: 11, weight: .semibold))
                Text(option.title).font(.system(size: 12.5, weight: .semibold))
                if let count = option.count {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Color.primary.opacity(0.07)))
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(hovering ? 0.9 : 0.62))
            .padding(.horizontal, 12)
            .padding(.vertical, 6.5)
            .background {
                if selected {
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)))
                        .shadow(color: tint.opacity(0.35), radius: 5, y: 2)
                        .matchedGeometryEffect(id: "selecionado", in: namespace)
                } else if hovering {
                    Capsule().fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(option.count.map { "\(option.title), \($0)" } ?? option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Menu de escolha (ordem, ramo…) no mesmo estilo das pílulas.
struct ChipMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [ChipOption<Value>]
    var label: String?

    private var current: ChipOption<Value>? { options.first { $0.value == selection } }

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current?.symbol ?? "line.3.horizontal.decrease").font(.system(size: 11, weight: .semibold))
                if let label { Text(label).foregroundStyle(.secondary) }
                Text(current?.title ?? "").fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.045)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Animação

/// Número que conta suavemente até o valor (0 → 15 passando por 1, 2, 3…), em vez de trocar de uma vez.
struct CountingText: View, Animatable {
    var value: Double
    var prefix = ""
    var suffix = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(prefix)\(Int(value.rounded()).formatted())\(suffix)")
            .monospacedDigit()
    }
}

/// Escalas fixas para os gráficos: com o teto já decidido, as barras crescem sem a escala
/// se refazer no meio da animação (era isso que dava o “salto”).
enum ChartScale {
    /// Teto “redondo” um pouco acima do maior valor (36 → 40, 1.044.724 → 1.200.000).
    static func nice(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let exponent = pow(10, floor(log10(value)))
        let fraction = value / exponent
        let steps: [Double] = [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]
        let step = steps.first { $0 >= fraction * 1.05 } ?? 10
        return step * exponent
    }
}

/// Crescimento dos gráficos calculado quadro a quadro pelo SwiftUI (0 → 1).
/// A animação interna dos gráficos (Swift Charts) é cortada quando a tela atualiza no meio
/// do caminho — por exemplo, quando chegam os dados de linguagens —, e as barras saltavam
/// direto para o fim. Aqui o próprio valor é interpolado, então nada interrompe o crescimento.
struct Growing<Content: View>: View, Animatable {
    var progress: Double
    @ViewBuilder var content: (Double) -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(progress)
            .transaction { $0.animation = nil }
    }
}

// MARK: - Cartões ou lista

/// Como mostrar Repositórios e Projetos no Mac (o app lembra a escolha de cada tela).
enum ItemLayout: String, CaseIterable, Identifiable {
    case cards, list
    var id: String { rawValue }

    static var options: [ChipOption<ItemLayout>] {
        [ChipOption(value: .cards, title: "Cartões", symbol: "square.grid.2x2.fill"),
         ChipOption(value: .list, title: "Lista", symbol: "list.bullet")]
    }
}

/// Contêiner das listas: um cartão com as linhas separadas por divisórias finas.
struct ListPanel<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var inset: CGFloat = 64
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                if item.id != items.last?.id { Divider().padding(.leading, inset) }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

/// Seletor compacto (só ícones) entre cartões e lista, no visual das pílulas.
struct LayoutToggle: View {
    @Binding var selection: ItemLayout
    var tint: Color = Theme.accent
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ItemLayout.options) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = option.value }
                } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.6))
                        .frame(width: 30, height: 24)
                        .background {
                            if selected {
                                Capsule().fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
                                    .matchedGeometryEffect(id: "layout", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.045)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
        .fixedSize()
    }
}
