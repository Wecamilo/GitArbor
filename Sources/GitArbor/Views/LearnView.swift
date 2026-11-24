import GitArborCore
import SwiftUI

/// Aprender (menu Ajuda): janela modal com as lições ilustradas e o roteiro do dia a dia.
struct LearnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selected: Lesson?

    init(start: Lesson? = nil) {
        _selected = ViewState(initialValue: start ?? Glossary.lessons.first)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lições").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 4)
                    ForEach(Glossary.lessons) { lesson in
                        Button { withAnimation(.easeInOut(duration: 0.2)) { selected = lesson } } label: {
                            HStack(spacing: 10) {
                                IconTile(symbol: lesson.symbol, tint: .pink, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lesson.title).font(.system(size: 13, weight: .medium))
                                    Text(lesson.term).font(.system(size: 10.5)).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(selected == lesson ? Color.pink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == lesson ? .isSelected : [])
                    }
                }
                .padding(14)
            }
            .frame(width: 250)
            .background(Color.primary.opacity(0.02))

            Divider()

            VStack(spacing: 0) {
                // Cabeçalho fixo: o título e o X ficam sempre visíveis; só o conteúdo rola.
                HStack(alignment: .top) {
                    ScreenHeader(title: "Aprender", subtitle: "Os conceitos do GitHub explicados com desenhos e comparações do dia a dia.", symbol: "graduationcap.fill", tint: .pink)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Fechar (Esc)")
                    .accessibilityLabel("Fechar")
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let lesson = selected { LessonDetail(lesson: lesson).id(lesson.id).transition(.asymmetric(insertion: .opacity, removal: .identity)) }
                        DailyRoutine()
                    }
                    .padding(28)
                    .frame(maxWidth: 860, alignment: .leading)
                }
            }
        }
        .frame(width: 940, height: 680)
    }
}

private struct LessonDetail: View {
    let lesson: Lesson

    var body: some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    IconTile(symbol: lesson.symbol, tint: .pink, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lesson.title).font(.system(size: 24, weight: .bold))
                        Text("No site do GitHub aparece como: \(lesson.term)").font(.system(size: 12.5)).foregroundStyle(.secondary)
                    }
                }
                Text(lesson.summary).font(.system(size: 16, weight: .medium))
                if lesson.diagram != .none {
                    LessonDiagram(diagram: lesson.diagram)
                        .frame(height: 170)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.pink.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.corner))
                }
                Text(lesson.explanation).font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Para lembrar").font(.system(size: 12, weight: .semibold))
                        Text(lesson.analogy).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner))
            }
        }
    }
}

/// O roteiro de sempre, em quatro passos.
private struct DailyRoutine: View {
    var body: some View {
        Card(padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("O dia a dia, passo a passo").font(.system(size: 17, weight: .bold))
                step(1, "arrow.down.circle.fill", .purple, "Baixe as novidades", "Em Projetos no Mac, se aparecer “Novidades para baixar”, clique em Baixar. Assim você começa da versão mais nova.")
                step(2, "pencil.and.scribble", .orange, "Trabalhe normalmente", "Edite os arquivos do projeto como sempre (no editor, no Claude, onde for).")
                step(3, "camera.fill", .indigo, "Salve uma versão", "Clique em “Salvar versão”, escreva uma frase dizendo o que mudou. Isso é o commit.")
                step(4, "arrow.up.circle.fill", .blue, "Envie ao GitHub", "Deixe marcado “Enviar ao GitHub logo depois”. Pronto: sua cópia na nuvem está atualizada.")
            }
        }
    }

    private func step(_ n: Int, _ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                IconTile(symbol: symbol, tint: tint, size: 38)
                Text("\(n)").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 16, height: 16).background(.white, in: Circle()).offset(x: 5, y: -5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Desenhos das lições

struct LessonDiagram: View {
    let diagram: Lesson.Diagram

    var body: some View {
        switch diagram {
        case .repository: RepositoryDiagram()
        case .commits: CommitsDiagram()
        case .sync: SyncDiagram()
        case .branches: BranchDiagram(merge: false)
        case .merge: BranchDiagram(merge: true)
        case .pullRequest: PullRequestDiagram()
        case .issues: IssuesDiagram()
        case .clone: CloneDiagram()
        case .release: ReleaseDiagram()
        case .actions: ActionsDiagram()
        case .none: EmptyView()
        }
    }
}

private struct Dot: View {
    var tint: Color = .indigo
    var label: String?
    var filled = true
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(filled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                .overlay(Circle().strokeBorder(tint, lineWidth: 2.5))
                .frame(width: 22, height: 22)
            if let label { Text(label).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize() }
        }
    }
}

private struct CommitsDiagram: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(["Início", "Tela nova", "Cores", "Correção"].enumerated()), id: \.offset) { i, label in
                if i > 0 { Rectangle().fill(Color.indigo.opacity(0.4)).frame(height: 3).frame(maxWidth: 60).padding(.bottom, 16) }
                Dot(label: label, filled: i == 3)
            }
        }
        .padding(.horizontal, 20)
    }
}

private struct BranchDiagram: View {
    let merge: Bool

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let y1 = h * 0.68, y2 = h * 0.28
            ZStack {
                Path { p in p.move(to: CGPoint(x: w * 0.08, y: y1)); p.addLine(to: CGPoint(x: w * 0.92, y: y1)) }
                    .stroke(Color.teal.opacity(0.5), lineWidth: 3)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.25, y: y1))
                    p.addCurve(to: CGPoint(x: w * 0.42, y: y2), control1: CGPoint(x: w * 0.32, y: y1), control2: CGPoint(x: w * 0.34, y: y2))
                    p.addLine(to: CGPoint(x: w * 0.62, y: y2))
                    if merge { p.addCurve(to: CGPoint(x: w * 0.8, y: y1), control1: CGPoint(x: w * 0.72, y: y2), control2: CGPoint(x: w * 0.72, y: y1)) }
                }
                .stroke(Color.orange.opacity(0.6), lineWidth: 3)
                ForEach([0.1, 0.25, 0.55, 0.8, 0.92], id: \.self) { x in
                    Dot(tint: .teal, filled: merge && x == 0.8).position(x: w * x, y: y1)
                }
                ForEach([0.42, 0.62], id: \.self) { x in Dot(tint: .orange).position(x: w * x, y: y2) }
                Text("principal (main)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.teal).position(x: w * 0.12, y: y1 + 24)
                Text("ramo novo").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange).position(x: w * 0.52, y: y2 - 22)
                if merge { Text("juntou!").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.closed).position(x: w * 0.8, y: y1 + 24) }
            }
        }
    }
}

private struct SyncDiagram: View {
    var body: some View {
        HStack(spacing: 18) {
            box("laptopcomputer", "Seu Mac", .indigo)
            VStack(spacing: 14) {
                arrow("Enviar (push)", "arrow.right", .blue)
                arrow("Baixar (pull)", "arrow.left", .purple)
            }
            box("icloud.fill", "GitHub", .blue)
        }
    }

    private func box(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            IconTile(symbol: symbol, tint: tint, size: 54)
            Text(title).font(.system(size: 12, weight: .semibold))
        }
    }

    private func arrow(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(tint)
                .frame(width: 140)
                .background(Rectangle().fill(tint.opacity(0.25)).frame(height: 3))
        }
    }
}

private struct RepositoryDiagram: View {
    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 6) {
                IconTile(symbol: "folder.fill", tint: .blue, size: 56)
                Text("Arquivos").font(.system(size: 11, weight: .semibold))
            }
            Text("+").font(.system(size: 28, weight: .bold)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                IconTile(symbol: "clock.arrow.circlepath", tint: .indigo, size: 56)
                Text("Histórico").font(.system(size: 11, weight: .semibold))
            }
            Text("=").font(.system(size: 28, weight: .bold)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                IconTile(symbol: "shippingbox.fill", tint: Theme.accent, size: 56)
                Text("Repositório").font(.system(size: 11, weight: .semibold))
            }
        }
    }
}

private struct PullRequestDiagram: View {
    var body: some View {
        HStack(spacing: 14) {
            chip("ramo novo", .orange)
            VStack(spacing: 4) {
                IconTile(symbol: "arrow.triangle.pull", tint: Theme.closed, size: 44)
                Text("pedido + revisão").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.closed)
            chip("principal", .teal)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Label(t, systemImage: "arrow.triangle.branch")
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(c.opacity(0.14), in: Capsule()).foregroundStyle(c)
    }
}

private struct IssuesDiagram: View {
    var body: some View {
        HStack(spacing: 16) {
            column("A fazer", ["Corrigir login", "Nova tela"], Theme.open, "circle")
            column("Feito", ["Ícone novo"], Theme.closed, "checkmark.circle.fill")
        }
    }

    private func column(_ title: String, _ items: [String], _ tint: Color, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            ForEach(items, id: \.self) { i in
                Label(i, systemImage: symbol).font(.system(size: 11.5))
                    .padding(8).frame(width: 140, alignment: .leading)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 20)
    }
}

private struct CloneDiagram: View {
    var body: some View {
        HStack(spacing: 18) {
            IconTile(symbol: "icloud.fill", tint: .blue, size: 54)
            VStack(spacing: 2) {
                Text("clonar").font(.system(size: 11, weight: .semibold)).foregroundStyle(.indigo)
                Image(systemName: "arrow.right").font(.system(size: 22, weight: .bold)).foregroundStyle(.indigo)
            }
            IconTile(symbol: "laptopcomputer", tint: .indigo, size: 54)
        }
    }
}

private struct ReleaseDiagram: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<5) { i in
                if i > 0 { Rectangle().fill(Color.indigo.opacity(0.4)).frame(width: 46, height: 3) }
                ZStack {
                    Dot(filled: i == 2 || i == 4)
                    if i == 2 { Pill(text: "v1.0", symbol: "tag.fill", tint: .pink).offset(y: -30) }
                    if i == 4 { Pill(text: "v1.1", symbol: "tag.fill", tint: .pink).offset(y: -30) }
                }
            }
        }
    }
}

private struct ActionsDiagram: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) { IconTile(symbol: "arrow.up.circle.fill", tint: .blue, size: 44); Text("Você envia").font(.system(size: 10)) }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            VStack(spacing: 4) { IconTile(symbol: "gearshape.2.fill", tint: .orange, size: 44); Text("Robô testa").font(.system(size: 10)) }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Label("Deu certo", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.open)
                Label("Falhou", systemImage: "xmark.circle.fill").foregroundStyle(Theme.danger)
            }
            .font(.system(size: 11, weight: .semibold))
        }
    }
}
