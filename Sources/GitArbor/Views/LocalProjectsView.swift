import AppKit
import GitArborCore
import SwiftUI

/// Projetos no Mac: a situação de cada pasta com Git e botões para salvar, enviar e baixar.
struct LocalProjectsView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var committing: LocalRepoStatus?
    @ViewState private var publishing: URL?
    @ViewState private var detail: ProjectSheetRequest?
    @AppStorage("localProjectsLayout") private var layout: ItemLayout = .cards

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Projetos no Mac", subtitle: "As pastas com Git neste Mac e como cada uma está em relação ao GitHub.",
                             symbol: "laptopcomputer", tint: .indigo) {
                    Button { Task { await model.fetchAllLocal() } } label: {
                        if model.isScanningLocal { ProgressView().controlSize(.small) } else { Label("Conferir com o GitHub", systemImage: "arrow.triangle.2.circlepath") }
                    }
                    .buttonStyle(ActionButtonStyle(tint: .indigo, prominent: true))
                    .help("Pergunta ao GitHub se há novidades para cada projeto (não muda nenhum arquivo)")
                    .disabled(model.isScanningLocal)
                }

                SyncFlowDiagram()

                if !model.localRepos.isEmpty || !model.foldersWithoutGit.isEmpty {
                    NotPublishedSection(onPublish: { publishing = $0 })
                }
                if !model.localRepos.isEmpty {
                    ProtectionSummary()
                    AutoPushSummary()
                }

                if model.localRepos.isEmpty && model.isScanningLocal {
                    LoadingRow(text: "Procurando projetos…")
                } else if model.localRepos.isEmpty && model.foldersWithoutGit.isEmpty {
                    EmptyState(symbol: "folder.badge.questionmark", title: "Nenhum projeto com Git nas suas pastas",
                               message: "Acrescente outra pasta no menu Git Arbor › Pastas dos projetos, baixe um repositório do GitHub (clonar) ou transforme uma pasta em projeto Git.", tint: .indigo)
                } else if !model.localRepos.isEmpty {
                    HStack(alignment: .center) {
                        legend
                        Spacer(minLength: 12)
                        LayoutToggle(selection: $layout, tint: .indigo)
                    }
                    if layout == .cards {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], spacing: 16) {
                            ForEach(model.localRepos) { repo in
                                LocalRepoCard(repo: repo, onCommit: { committing = repo }, onPublish: { publishing = repo.folder },
                                              onOpen: { detail = ProjectSheetRequest(folder: repo.folder, tab: $0) })
                            }
                        }
                    } else {
                        ListPanel(items: model.localRepos, inset: 54) { repo in
                            LocalRepoCard(repo: repo, onCommit: { committing = repo }, onPublish: { publishing = repo.folder },
                                          onOpen: { detail = ProjectSheetRequest(folder: repo.folder, tab: $0) }, asRow: true)
                        }
                    }
                }

            }
            .padding(28)
        }
        .sheet(item: $committing) { repo in CommitSheetLocal(repo: repo) }
        .sheet(item: $detail) { request in ProjectSheet(request: request) }
        .onReceive(NotificationCenter.default.publisher(for: .openLocalProject)) { note in
            if let request = note.object as? ProjectSheetRequest { detail = request }
        }
        .sheet(isPresented: Binding(get: { publishing != nil }, set: { if !$0 { publishing = nil } })) {
            if let folder = publishing { PublishSheet(folder: folder) }
        }
    }

    private var legend: some View {
        FlowRow(spacing: 14) {
            ForEach([LocalRepoStatus.State.clean, .unsaved, .toSend, .toReceive, .diverged, .noRemote], id: \.self) { s in
                HStack(spacing: 6) {
                    LocalStateBadge(state: s, small: true)
                    Text(LocalStateBadge.title(s)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Escolhe pastas de projetos para acrescentar à lista (menu Git Arbor e Ajustes).
enum ProjectFolderPicker {
    static func add(to model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Acrescentar"
        panel.message = "Escolha uma ou mais pastas onde ficam seus projetos"
        panel.directoryURL = model.localFolder.deletingLastPathComponent()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { model.addLocalFolder(url) }
    }

    /// Caminho curto para mostrar (com ~ no lugar da pasta de início).
    static func display(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

/// Desenho do caminho: arquivos → salvar (commit) → enviar (push) → GitHub, e baixar (pull) de volta.
struct SyncFlowDiagram: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.showExplanations {
            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Como as mudanças viajam").font(.system(size: 13, weight: .semibold))
                        HelpTip(lessonID: "push")
                        Spacer()
                    }
                    HStack(spacing: 0) {
                        node("pencil.and.scribble", "Você edita", "os arquivos na pasta", .orange)
                        arrow("Salvar", "commit", .indigo, forward: true)
                        node("camera.fill", "Versão salva", "no histórico do Mac", .indigo)
                        arrow("Enviar", "push", .blue, forward: true)
                        node("icloud.fill", "GitHub", "cópia na nuvem", .blue)
                    }
                    HStack {
                        Spacer()
                        Label("Baixar (pull) traz para o Mac o que mudou no GitHub", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.purple)
                        Spacer()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Você edita os arquivos, salva uma versão com commit e envia ao GitHub com push. Baixar, ou pull, traz as novidades do GitHub para o Mac.")
        }
    }

    private func node(_ symbol: String, _ title: String, _ sub: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            IconTile(symbol: symbol, tint: tint, size: 40)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(sub).font(.system(size: 10.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(width: 120)
    }

    private func arrow(_ title: String, _ term: String, _ tint: Color, forward: Bool) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            HStack(spacing: 0) {
                Rectangle().fill(tint.opacity(0.5)).frame(height: 2)
                Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9)).foregroundStyle(tint.opacity(0.7))
            }
            Text(term).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 26)
    }
}

/// Selo colorido da situação de um projeto.
struct LocalStateBadge: View {
    let state: LocalRepoStatus.State
    var small = false

    static func title(_ s: LocalRepoStatus.State) -> String {
        switch s {
        case .clean: "Tudo em dia"
        case .unsaved: "Mudanças não salvas"
        case .toSend: "Falta enviar"
        case .toReceive: "Novidades para baixar"
        case .diverged: "Mudou nos dois lados"
        case .conflict: "Conflito"
        case .noRemote: "Só no Mac"
        case .noUpstream: "Ramo ainda não enviado"
        }
    }

    static func symbol(_ s: LocalRepoStatus.State) -> String {
        switch s {
        case .clean: "checkmark"
        case .unsaved: "pencil"
        case .toSend: "arrow.up"
        case .toReceive: "arrow.down"
        case .diverged: "arrow.up.arrow.down"
        case .conflict: "exclamationmark"
        case .noRemote: "laptopcomputer"
        case .noUpstream: "arrow.up.to.line"
        }
    }

    static func tint(_ s: LocalRepoStatus.State) -> Color {
        switch s {
        case .clean: Theme.open
        case .unsaved: .orange
        case .toSend: .blue
        case .toReceive: .purple
        case .diverged, .conflict: Theme.danger
        case .noRemote: .gray
        case .noUpstream: .blue
        }
    }

    /// Lição que explica a situação (o “?” ao lado do título no cartão).
    static func lessonID(_ s: LocalRepoStatus.State) -> String? {
        switch s {
        case .clean: nil
        case .unsaved: "commit"
        case .toSend, .toReceive: "push"
        case .diverged, .conflict: "conflict"
        case .noRemote: "repository"
        case .noUpstream: "branch"
        }
    }

    static func sentence(for r: LocalRepoStatus) -> String {
        switch r.state {
        case .clean: "Igual ao GitHub."
        case .unsaved: "\(Phrases.plural(r.changes.count, "arquivo mudou", "arquivos mudaram")) desde a última versão salva."
        case .toSend: "\(Phrases.plural(r.ahead, "versão salva espera", "versões salvas esperam")) para ir ao GitHub."
        case .toReceive: "O GitHub tem \(Phrases.plural(r.behind, "versão nova", "versões novas")) que este Mac não tem."
        case .diverged: "\(r.ahead) para enviar e \(r.behind) para baixar. “Baixar e juntar” une os dois lados."
        case .conflict: r.conflicts.isEmpty ? "Conflitos resolvidos: falta concluir a junção." : "\(Phrases.plural(r.conflicts.count, "arquivo mudou", "arquivos mudaram")) nos dois lados. Escolha o que fica."
        case .noRemote: "Ainda não está ligado a um repositório do GitHub."
        case .noUpstream: "O ramo “\(r.branch ?? "atual")” ainda não existe no GitHub. Enviar cria o ramo lá."
        }
    }

    var body: some View {
        let size: CGFloat = small ? 18 : 26
        Image(systemName: Self.symbol(state))
            .font(.system(size: size * 0.45, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.tint(state).gradient, in: Circle())
            .accessibilityLabel(Self.title(state))
    }
}

private struct LocalRepoCard: View {
    @Environment(AppModel.self) private var model
    let repo: LocalRepoStatus
    let onCommit: () -> Void
    let onPublish: () -> Void
    let onOpen: (ProjectSheet.Tab) -> Void
    /// Linha da lista em vez de cartão.
    var asRow = false
    @ViewState private var hovering = false

    private var busy: Bool { model.busyFolders.contains(repo.folder) }
    private var tint: Color { LocalStateBadge.tint(repo.state) }

    var body: some View {
        if asRow { row } else { card }
    }

    /// Linha da lista: situação, nome, ramo, contadores, envio automático e a última versão,
    /// com a ação principal e o menu à direita.
    private var row: some View {
        HStack(spacing: 14) {
            LocalStateBadge(state: repo.state)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(repo.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    if let b = repo.branch {
                        Button { onOpen(.branches) } label: {
                            Label(b, systemImage: "arrow.triangle.branch").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.teal)
                        }
                        .buttonStyle(.plain)
                        .help("Ver e trocar de ramo")
                    }
                    if let name = model.gitHubName(of: repo) {
                        Text(name).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    Text(LocalStateBadge.title(repo.state)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(tint)
                    Text("· " + LocalStateBadge.sentence(for: repo)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 10) {
                    if !repo.changes.isEmpty { Label("\(repo.changes.count) não salvas", systemImage: "pencil").foregroundStyle(.orange) }
                    if repo.ahead > 0 { Label("\(repo.ahead) a enviar", systemImage: "arrow.up").foregroundStyle(.blue) }
                    if repo.behind > 0 { Label("\(repo.behind) a baixar", systemImage: "arrow.down").foregroundStyle(.purple) }
                    if repo.stashCount > 0 { Label("\(repo.stashCount) guardadas", systemImage: "tray.full.fill").foregroundStyle(.indigo) }
                    if !repo.exposedFiles.isEmpty { Label("arquivo sensível exposto", systemImage: "exclamationmark.shield.fill").foregroundStyle(Theme.danger) }
                    if let target = model.renamedTarget(for: repo) {
                        Button { Task { await model.updateRemote(of: repo, to: target) } } label: {
                            Label("renomeado para \(target.name) — atualizar endereço", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                        .help("O repositório mudou de nome no GitHub. Atualizar troca o endereço antigo desta pasta pelo novo.")
                    }
                    HStack(spacing: 4) {
                        Circle().fill(AutoPushLight.color(for: repo)).frame(width: 7, height: 7)
                        Text("envio automático \(AutoPushLight.label(for: repo))")
                    }
                    .foregroundStyle(.secondary)
                    Text(repo.lastCommitMessage.map { "“\($0)” · \(Phrases.relative(repo.lastCommitDate))" } ?? "Nenhuma versão salva")
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 10.5))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            }
            Spacer(minLength: 10)
            if busy { ProgressView().controlSize(.small) }
            HStack(spacing: 8) {
                primaryAction
                Button { onOpen(.timeline) } label: { Image(systemName: "clock.arrow.circlepath").font(.system(size: 14)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.indigo)
                    .help("Linha do tempo: ver versões, desfazer e voltar no tempo")
                    .accessibilityLabel("Linha do tempo de \(repo.name)")
                moreMenu
            }
            .disabled(busy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovering ? Color.primary.opacity(0.035) : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .onHover { hovering = $0 }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                LocalStateBadge(state: repo.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        if let b = repo.branch {
                            Button { onOpen(.branches) } label: {
                                Label(b, systemImage: "arrow.triangle.branch").font(.system(size: 11, design: .monospaced)).foregroundStyle(.teal)
                            }
                            .buttonStyle(.plain)
                            .help("Ver e trocar de ramo")
                        }
                        if let name = model.gitHubName(of: repo) {
                            Text("· \(name)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(LocalStateBadge.title(repo.state)).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                    if let lesson = LocalStateBadge.lessonID(repo.state) { HelpTip(lessonID: lesson) }
                }
                Text(LocalStateBadge.sentence(for: repo)).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Três contadores: mudanças, a enviar, a baixar.
            HStack(spacing: 8) {
                counter(repo.changes.count, "não salvas", "pencil", .orange)
                counter(repo.ahead, "a enviar", "arrow.up", .blue)
                counter(repo.behind, "a baixar", "arrow.down", .purple)
            }

            AutoPushRow(repo: repo)

            if let target = model.renamedTarget(for: repo) { RenamedNotice(repo: repo, target: target) }

            if repo.stashCount > 0 {
                Button { onOpen(.stash) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full.fill").foregroundStyle(.indigo)
                        Text("\(Phrases.plural(repo.stashCount, "grupo de mudanças guardado", "grupos de mudanças guardados")) para depois")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        Text("Ver").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                    .padding(8)
                    .background(Color.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !repo.exposedFiles.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.danger)
                    Text("\(Phrases.plural(repo.exposedFiles.count, "arquivo sensível iria", "arquivos sensíveis iriam")) para o GitHub: \(repo.exposedFiles.prefix(2).joined(separator: ", "))")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.danger).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("Proteger") { Task { await model.protect(folder: repo.folder) } }
                        .buttonStyle(ActionButtonStyle(tint: Theme.danger, prominent: true))
                }
                .padding(8)
                .background(Theme.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 6) {
                Image(systemName: "camera").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(repo.lastCommitMessage.map { "Última versão: “\($0)” · \(Phrases.relative(repo.lastCommitDate))" } ?? "Nenhuma versão salva ainda")
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                primaryAction
                Spacer()
                Button { onOpen(.timeline) } label: { Image(systemName: "clock.arrow.circlepath").font(.system(size: 15)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.indigo)
                    .help("Linha do tempo: ver versões, desfazer e voltar no tempo")
                    .accessibilityLabel("Linha do tempo de \(repo.name)")
                moreMenu
            }
            .disabled(busy)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.cardCorner, bottomLeadingRadius: Theme.cardCorner, style: .continuous)
                .fill(tint).frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var moreMenu: some View {
                Menu {
                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.folder]) }
                    Button("Abrir no Terminal") {
                        NSWorkspace.shared.open([repo.folder], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init())
                    }
                    if let name = model.gitHubName(of: repo) {
                        Button("Ver no Git Arbor") { model.open(fullName: name) }
                        Button("Abrir no site do GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/\(name)")!) }
                    }
                    Divider()
                    Button("Linha do tempo…") { onOpen(.timeline) }
                    Button("Ramos…") { onOpen(.branches) }
                    Button("Guardar para depois…") { onOpen(.stash) }
                    Button("Procurar senhas no histórico…") { onOpen(.secrets) }
                    if repo.state == .conflict { Button("Resolver conflitos…") { onOpen(.conflicts) } }
                    Divider()
                    Button(repo.protected ? "Lista de arquivos sensíveis aplicada" : "Proteger arquivos sensíveis (.gitignore)") {
                        Task { await model.protect(folder: repo.folder) }
                    }
                    .disabled(repo.protected && repo.exposedFiles.isEmpty)
                    Button("Salvar versão…") { onCommit() }.disabled(repo.changes.isEmpty)
                    Button("Enviar (push)") { push() }.disabled(!repo.hasRemote)
                    Button("Baixar (pull)") { pull() }.disabled(!repo.hasRemote || repo.upstream == nil)
                    Button("Conferir com o GitHub (fetch)") {
                        Task { _ = await model.runLocal(repo.folder, success: "Situação de “\(repo.name)” atualizada") { try await LocalGit.fetch(at: repo.folder) } }
                    }
                    .disabled(!repo.hasRemote)
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Mais ações")
                .accessibilityLabel("Mais ações para \(repo.name)")
    }

    @ViewBuilder private var primaryAction: some View {
        switch repo.state {
        case .conflict:
            Button { onOpen(.conflicts) } label: { Label("Resolver conflitos", systemImage: "exclamationmark.triangle.fill") }
                .buttonStyle(ActionButtonStyle(tint: Theme.danger, prominent: true))
        case .unsaved:
            Button { onCommit() } label: { Label("Salvar versão", systemImage: "camera.fill") }
                .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
        case .toSend, .noUpstream:
            Button { push() } label: { Label("Enviar ao GitHub", systemImage: "arrow.up.circle.fill") }
                .buttonStyle(ActionButtonStyle(tint: .blue, prominent: true))
        case .toReceive:
            Button { pull() } label: { Label("Baixar novidades", systemImage: "arrow.down.circle.fill") }
                .buttonStyle(ActionButtonStyle(tint: .purple, prominent: true))
        case .diverged:
            Button { pullMerging() } label: { Label("Baixar e juntar", systemImage: "arrow.triangle.merge") }
                .buttonStyle(ActionButtonStyle(tint: .purple, prominent: true))
                .help("Traz as novidades do GitHub e junta com as versões deste Mac. Se as mesmas linhas mudaram, o app mostra os conflitos para você escolher.")
        case .noRemote:
            Button { onPublish() } label: { Label("Publicar no GitHub", systemImage: "icloud.and.arrow.up.fill") }
                .buttonStyle(ActionButtonStyle(tint: .gray, prominent: true))
        case .clean:
            Label("Nada a fazer", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.open)
        }
    }

    private func counter(_ n: Int, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(n > 0 ? tint : .secondary)
            Label(label, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func push() {
        let folder = repo.folder
        Task { _ = await model.runLocal(folder, success: "“\(repo.name)” enviado ao GitHub") { try await LocalGit.push(at: folder) } }
    }

    private func pull() {
        let folder = repo.folder
        Task { _ = await model.runLocal(folder, success: "Novidades de “\(repo.name)” baixadas") { try await LocalGit.pull(at: folder) } }
    }

    private func pullMerging() {
        let folder = repo.folder
        Task {
            let outcome = await model.runLocalOutcome(folder, success: "Novidades de “\(repo.name)” baixadas e juntadas") { try await LocalGit.pullMerging(at: folder) }
            if outcome == .conflicts { onOpen(.conflicts) }
        }
    }
}

/// Salvar uma versão (commit) com os arquivos mudados à vista e, se quiser, já enviar.
private struct CommitSheetLocal: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: LocalRepoStatus
    @ViewState private var message = ""
    @ViewState private var sendNow = true
    @ViewState private var preview: FileChange?
    @ViewState private var diff = ""
    @ViewState private var discarding: FileChange?
    @ViewState private var busy = false
    @ViewState private var stats: ChangeExplainer.Stats = [:]

    private var current: LocalRepoStatus { model.localRepos.first { $0.folder == repo.folder } ?? repo }
    private var suggestion: String { ChangeExplainer.suggestMessage(current.changes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "camera.fill", tint: .orange, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Salvar uma versão de “\(repo.name)”").font(.system(size: 18, weight: .bold))
                    Text("Um commit é uma foto dos arquivos agora, com uma frase dizendo o que mudou.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                HelpTip(lessonID: "commit")
            }
            .padding(20)
            Divider()
            HStack(spacing: 0) {
                // Lista de arquivos.
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Phrases.plural(current.changes.count, "arquivo mudado", "arquivos mudados"))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 6)
                        ForEach(current.changes) { change in
                            HStack(spacing: 8) {
                                Pill(text: change.kind.label, tint: kindTint(change.kind))
                                Text(change.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                Spacer(minLength: 0)
                                Button { discarding = change } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                                    .help("Desfazer as mudanças deste arquivo")
                                    .accessibilityLabel("Desfazer mudanças de \(change.path)")
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(preview == change ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { preview = change }
                        }
                    }
                    .padding(14)
                }
                .frame(width: 330)
                Divider()
                // O que mudou no arquivo escolhido.
                Group {
                    if preview == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            ExplainBox(lines: ChangeExplainer.summary(current.changes, stats: stats))
                            EmptyState(symbol: "hand.point.left", title: "Escolha um arquivo", message: "Clique num arquivo à esquerda para ver o que mudou nele.")
                        }
                        .padding(16)
                    } else if diff.isEmpty {
                        EmptyState(symbol: "doc", title: "Sem texto para mostrar", message: "Pode ser uma imagem ou um arquivo grande.")
                    } else {
                        ScrollView { DiffText(patch: diff) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                LabeledField(label: "O que você mudou? (frase curta)", text: $message, prompt: suggestion.isEmpty ? "ex.: Ajustei as cores da tela inicial" : suggestion)
                if !suggestion.isEmpty && message != suggestion {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                        Text("Sugestão: “\(suggestion)”").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                        Button("Usar") { message = suggestion }
                            .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                }
                HStack {
                    Toggle("Enviar ao GitHub logo depois (push)", isOn: $sendNow)
                        .toggleStyle(.checkbox)
                        .disabled(!current.hasRemote)
                    Spacer()
                    Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button { Task { await save() } } label: {
                        if busy { ProgressView().controlSize(.small) } else {
                            Label(sendNow && current.hasRemote ? "Salvar e enviar" : "Salvar versão", systemImage: "camera.fill")
                        }
                    }
                    .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || busy || current.changes.isEmpty)
                }
            }
            .padding(16)
        }
        .frame(width: 860, height: 600)
        .task(id: current.changes) {
            stats = await LocalGit.pendingLineStats(at: repo.folder, changes: current.changes)
        }
        .task(id: preview) {
            guard let preview else { return }
            diff = await LocalGit.diff(preview, at: repo.folder)
        }
        .confirmationDialog("Desfazer as mudanças de “\(discarding?.path ?? "")”?", isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })) {
            Button("Desfazer mudanças", role: .destructive) {
                guard let change = discarding else { return }
                Task {
                    _ = await model.runLocal(repo.folder, success: "Mudanças desfeitas") { try await LocalGit.discard(change, at: repo.folder) }
                    if preview == change { preview = nil }
                }
            }
        } message: {
            Text(discarding.map { $0.kind == .untracked || $0.kind == .added ? "O arquivo novo vai para o Lixo." : "O arquivo volta a ser como estava na última versão salva." } ?? "")
        }
    }

    private func kindTint(_ k: FileChange.Kind) -> Color {
        switch k {
        case .added, .untracked: Theme.open
        case .deleted: Theme.danger
        case .renamed: .blue
        case .conflict: .red
        case .modified: .orange
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        let folder = repo.folder
        let msg = message
        let push = sendNow && current.hasRemote
        let ok = await model.runLocal(folder, success: push ? "Versão salva e enviada ao GitHub" : "Versão salva no Mac") {
            try await LocalGit.commitAll(at: folder, message: msg)
            if push { try await LocalGit.push(at: folder) }
        }
        if ok { dismiss() }
    }
}

// MARK: - Ainda não publicados

/// Tudo o que ainda não está no GitHub, à vista: projetos com Git só no Mac e pastas sem Git.
/// Quando não falta nada, mostra só uma faixa verde confirmando.
private struct NotPublishedSection: View {
    @Environment(AppModel.self) private var model
    let onPublish: (URL) -> Void
    /// Recolhida por padrão; o app lembra se você deixou aberta.
    @AppStorage("notPublishedExpanded") private var expanded = false

    private var onlyOnMac: [URL] { model.localRepos.filter { !$0.hasRemote }.map(\.folder) }
    private var items: [(folder: URL, hasGit: Bool)] {
        onlyOnMac.map { ($0, true) } + model.foldersWithoutGit.map { ($0, false) }
    }

    var body: some View {
        if items.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.icloud.fill").font(.system(size: 18)).foregroundStyle(Theme.open)
                Text("Todas as pastas desta pasta de projetos já estão no GitHub.").font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(12)
            .background(Theme.open.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner))
        } else {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: "icloud.slash.fill", tint: .gray, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Ainda não estão no GitHub (\(items.count))").font(.system(size: 14, weight: .semibold))
                                Text(expanded
                                     ? "Estas pastas existem só neste Mac. Publique para ter uma cópia segura na nuvem."
                                     : items.map { $0.folder.lastPathComponent }.joined(separator: " · "))
                                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Text(expanded ? "Recolher" : "Mostrar").font(.system(size: 12, weight: .semibold))
                                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                                    .rotationEffect(.degrees(expanded ? 180 : 0))
                            }
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Theme.accentSoft))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Recolher pastas que ainda não estão no GitHub" : "Mostrar pastas que ainda não estão no GitHub")

                    if expanded {
                    ForEach(items, id: \.folder) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.hasGit ? "laptopcomputer" : "folder.fill")
                                .foregroundStyle(item.hasGit ? Color.indigo : Color.blue)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.folder.lastPathComponent).font(.system(size: 13, weight: .medium))
                                Text(item.hasGit ? "Já usa Git, mas não está ligada ao GitHub." : "Ainda não usa Git. Publicar já começa a usar.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.busyFolders.contains(item.folder) { ProgressView().controlSize(.small) }
                            if !item.hasGit {
                                Button("Só usar Git no Mac") {
                                    Task {
                                        let folder = item.folder
                                        let ok = await model.runLocal(folder, success: "“\(folder.lastPathComponent)” agora usa Git") {
                                            try await LocalGit.initialize(at: folder)
                                        }
                                        if ok { model.foldersWithoutGit.removeAll { $0 == folder } }
                                    }
                                }
                                .buttonStyle(ActionButtonStyle(tint: .secondary))
                                .help("Roda “git init” e salva a primeira versão, sem publicar")
                            }
                            Button { onPublish(item.folder) } label: { Label("Publicar no GitHub", systemImage: "icloud.and.arrow.up.fill") }
                                .buttonStyle(ActionButtonStyle(tint: .blue, prominent: true))
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    }
                }
            }
        }
    }
}

// MARK: - Proteção

/// Faixa: quantos projetos têm a lista padrão de arquivos sensíveis no .gitignore, e “Proteger todos”.
/// Some quando está tudo protegido e nada sensível está exposto.
private struct ProtectionSummary: View {
    @Environment(AppModel.self) private var model

    private var mine: [LocalRepoStatus] { model.localRepos.filter { $0.hasRemote ? model.isMine($0) : true } }
    private var protected: [LocalRepoStatus] { mine.filter(\.protected) }
    private var exposed: [LocalRepoStatus] { model.localRepos.filter { !$0.exposedFiles.isEmpty } }

    var body: some View {
        if protected.count < mine.count || !exposed.isEmpty {
            Card(padding: 16) {
                HStack(spacing: 14) {
                    IconTile(symbol: "lock.shield.fill", tint: exposed.isEmpty ? Theme.open : Theme.danger, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Proteção de senhas e chaves").font(.system(size: 14, weight: .semibold))
                        Text("\(protected.count) de \(mine.count) projetos têm a lista padrão no .gitignore. Os arquivos de commits antigos continuam no histórico.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        if !exposed.isEmpty {
                            Label("Arquivos sensíveis expostos em: \(exposed.map(\.name).joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.danger)
                        }
                    }
                    Spacer()
                    Button { Task { await model.protectAll() } } label: { Label("Proteger todos", systemImage: "lock.shield.fill") }
                        .buttonStyle(ActionButtonStyle(tint: Theme.open, prominent: true))
                }
            }
        }
    }
}

// MARK: - Envio automático

/// Resumo: quantos projetos enviam sozinhos, quantos falharam no último envio, e “ligar em todos”.
private struct AutoPushSummary: View {
    @Environment(AppModel.self) private var model

    private var linked: [LocalRepoStatus] { model.localRepos.filter(model.isMine) }
    private var on: [LocalRepoStatus] { linked.filter(\.autoPush.enabled) }
    private var failed: [LocalRepoStatus] { on.filter(\.autoPushNeedsAttention) }

    /// Cor do ícone: a pior situação entre os projetos.
    private var summaryTint: Color {
        if on.count < linked.count { return AutoPushLight.off }
        if !failed.isEmpty { return AutoPushLight.failed }
        return AutoPushLight.ok
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                IconTile(symbol: "bolt.fill", tint: summaryTint, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Envio automático").font(.system(size: 14, weight: .semibold))
                        HelpTip(lessonID: "autopush")
                    }
                    Text("\(on.count) de \(linked.count) projetos seus no GitHub sobem sozinhos depois de cada versão salva.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        legend(AutoPushLight.ok, "funcionando")
                        legend(AutoPushLight.failed, "último envio falhou")
                        legend(AutoPushLight.off, "desligado")
                    }
                    .padding(.top, 2)
                    if !failed.isEmpty {
                        Label("Não conseguiu enviar sozinho: \(failed.map(\.name).joined(separator: ", ")). Clique em Enviar no cartão.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.danger)
                    }
                }
                Spacer()
                // Medidor: uma bolinha por projeto ligado ao GitHub.
                HStack(spacing: 3) {
                    ForEach(linked) { repo in
                        Circle()
                            .fill(AutoPushLight.color(for: repo))
                            .frame(width: 9, height: 9)
                            .help("\(repo.name): \(AutoPushLight.label(for: repo))")
                    }
                }
                if on.count < linked.count {
                    Button { Task { await model.enableAutoPushEverywhere() } } label: { Label("Ligar em todos", systemImage: "bolt.fill") }
                        .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
                }
            }
        }
    }
}

/// Semáforo do envio automático: verde funcionando, amarelo falhou, vermelho desligado.
enum AutoPushLight {
    static let ok = Theme.open
    static let failed = Color(red: 0.96, green: 0.70, blue: 0.0)
    static let off = Theme.danger

    static func color(for repo: LocalRepoStatus) -> Color {
        if !repo.autoPush.enabled { return off }
        return repo.autoPushNeedsAttention ? failed : ok
    }

    static func label(for repo: LocalRepoStatus) -> String {
        if !repo.autoPush.enabled { return "desligado" }
        return repo.autoPushNeedsAttention ? "último envio falhou" : "funcionando"
    }
}

/// Linha do cartão: envio automático ligado ou desligado, numa linha só.
/// Só mostra um aviso quando o envio automático falhou e ainda há versões esperando para ir ao GitHub.
private struct AutoPushRow: View {
    @Environment(AppModel.self) private var model
    let repo: LocalRepoStatus

    private var info: AutoPush { repo.autoPush }
    private var isOthers: Bool { repo.hasRemote && !model.isMine(repo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: info.enabled ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(AutoPushLight.color(for: repo).gradient, in: Circle())
                Text(isOthers ? "Envio automático (repositório de outra pessoa)" : "Envio automático")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(info.enabled ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Toggle("Envio automático", isOn: Binding(get: { info.enabled }, set: { on in
                    Task { await model.setAutoPush(on, folder: repo.folder) }
                }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(info.enabled ? "Ligado: depois de cada versão salva, sobe sozinho ao GitHub" : "Desligado: depois de salvar, é preciso clicar em Enviar")
            }
            if repo.autoPushNeedsAttention {
                Label("O envio automático não conseguiu enviar. Clique em “Enviar ao GitHub”.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AutoPushLight.failed)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AutoPushLight.color(for: repo).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.06)))
    }
}

// MARK: - Publicar

/// Publica no GitHub uma pasta que só existe no Mac: tudo já vem preenchido (nome da pasta, privado,
/// envio automático ligado); é só conferir e clicar em Publicar.
private struct PublishSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let folder: URL
    @ViewState private var name = ""
    @ViewState private var description = ""
    @ViewState private var isPrivate = true
    @ViewState private var autoPush = true
    @ViewState private var saveChangesFirst = true
    @ViewState private var commits = 0
    @ViewState private var sensitive: [String] = []
    @ViewState private var createdRepository: GHRepo?
    @ViewState private var busy = false

    private var status: LocalRepoStatus? { model.localRepos.first { $0.folder == folder } }
    /// A pasta ainda não usa Git: publicar começa pelo `git init` e a primeira versão.
    private var needsGit: Bool {
        status == nil && !FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path)
    }

    private var cleanName: String { Phrases.repoSlug(name) }

    private var nameTaken: Bool {
        model.repos.contains { $0.id != createdRepository?.id && $0.owner.login == model.user?.login
            && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "icloud.and.arrow.up.fill", tint: .blue, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Publicar no GitHub").font(.system(size: 20, weight: .bold))
                    Text("Cria um repositório na sua conta e envia o projeto “\(folder.lastPathComponent)”. Já deixei tudo preenchido — mude só o que quiser.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LabeledField(label: "Nome no GitHub", text: $name, prompt: "meu-projeto",
                                 help: cleanName.isEmpty ? "Sem espaços: use hífen." : "Vai ficar: github.com/\(model.user?.login ?? "")/\(cleanName)")
                    if nameTaken {
                        Label("Você já tem um repositório com esse nome. Escolha outro.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.danger)
                    }
                    LabeledField(label: "Descrição (opcional)", text: $description, prompt: "Para que serve este projeto")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Quem pode ver").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            HelpTip(lessonID: "visibility")
                        }
                        HStack(spacing: 10) {
                            choice(selected: isPrivate, symbol: "lock.fill", title: "Privado", detail: "Só você e quem você convidar.") { isPrivate = true }
                            choice(selected: !isPrivate, symbol: "globe", title: "Público", detail: "Qualquer pessoa vê; só você muda.") { isPrivate = false }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $autoPush) {
                            optionLabel("bolt.fill", "Ligar o envio automático", "Depois de cada versão salva, o projeto sobe sozinho para o GitHub.")
                        }
                        if let status, !status.changes.isEmpty {
                            Divider()
                            Toggle(isOn: $saveChangesFirst) {
                                optionLabel("camera.fill", "Salvar as mudanças pendentes antes",
                                            "\(Phrases.plural(status.changes.count, "arquivo mudou", "arquivos mudaram")) desde a última versão. Sem salvar, essas mudanças não vão junto.")
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(14)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.corner))

                    // O que vai ser enviado.
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.fill").foregroundStyle(.blue)
                        Text(needsGit
                             ? "A pasta ainda não usa Git: vou começar a usar, salvar a primeira versão com todos os arquivos e enviar."
                             : "Vai enviar \(Phrases.plural(commits, "versão salva", "versões salvas")) do ramo “\(status?.branch ?? "main")”.")
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let createdRepository {
                        Label("Repositório “\(createdRepository.name)” criado. Você pode tentar concluir o envio novamente nesta janela.",
                              systemImage: "info.circle")
                            .font(.system(size: 12))
                    }
                    if !sensitive.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Estes arquivos parecem senhas ou chaves", systemImage: "lock.shield.fill")
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.open)
                            ForEach(sensitive.prefix(8), id: \.self) { Text("• \($0)").font(.system(size: 11.5, design: .monospaced)) }
                            Text("O Git Arbor confere o histórico do ramo e bloqueia a publicação se encontrar esses arquivos em commits antigos.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(Theme.open.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner))
                    }
                }
                .padding(24)
                .disabled(busy || createdRepository != nil)
            }
            Divider()
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy)
                Spacer()
                Button { Task { await publish() } } label: {
                    if busy { ProgressView().controlSize(.small) } else { Label("Publicar", systemImage: "icloud.and.arrow.up.fill") }
                }
                .buttonStyle(ActionButtonStyle(tint: .blue, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(cleanName.isEmpty || nameTaken || busy)
            }
            .padding(16)
        }
        .frame(width: 540, height: 640)
        .interactiveDismissDisabled(busy)
        .onAppear { name = Phrases.repoSlug(folder.lastPathComponent) }
        .task {
            commits = await LocalGit.commitCount(at: folder)
            sensitive = await LocalGit.sensitiveFiles(at: folder)
        }
    }

    private func optionLabel(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choice(selected: Bool, symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol).foregroundStyle(selected ? Theme.accent : .secondary)
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.accent : .secondary)
                }
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accentSoft : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(selected ? Theme.accent.opacity(0.5) : Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func publish() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let folder = self.folder
        let initialize = needsGit
        let savePending = saveChangesFirst
        let name = cleanName
        let description = self.description
        let isPrivate = self.isPrivate
        let wantsAutoPush = autoPush
        let prepared = await model.runLocal(folder, success: "Projeto conferido para publicar") {
            if initialize {
                try await LocalGit.initialize(at: folder)
            } else {
                // Confere o histórico antes que a preparação possa criar um commit.
                _ = try await LocalGit.checkPublishableHistory(at: folder)
                try await LocalGit.protect(at: folder)
                let current = try await LocalGit.status(at: folder)
                if savePending && !current.changes.isEmpty {
                    try await LocalGit.commitForPublication(at: folder, message: "Versão antes de publicar no GitHub")
                }
            }
            _ = try await LocalGit.checkPublishableHistory(at: folder)
        }
        guard prepared else { return }
        model.foldersWithoutGit.removeAll { $0 == folder }
        if createdRepository == nil {
            createdRepository = await model.createRepository(name: name, description: description, isPrivate: isPrivate, withReadme: false)
        }
        guard let repo = createdRepository else { return }
        guard let remote = repo.cloneUrl else {
            model.errorMessage = "O GitHub criou o repositório, mas não informou um endereço para o envio."
            return
        }

        let published = await model.runLocal(folder, success: "“\(repo.name)” publicado no GitHub") {
            try await LocalGit.publish(at: folder, remote: remote)
        }
        guard published else { return }
        if wantsAutoPush { await model.setAutoPush(true, folder: folder) }
        dismiss()
    }
}

/// Aviso no cartão: o repositório mudou de nome no GitHub e a pasta usa o endereço antigo.
private struct RenamedNotice: View {
    @Environment(AppModel.self) private var model
    let repo: LocalRepoStatus
    let target: GHRepo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Renomeado no GitHub para “\(target.name)”").font(.system(size: 11.5, weight: .semibold))
                Text("Funciona assim mesmo, mas a pasta ainda usa o endereço antigo.").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Atualizar") { Task { await model.updateRemote(of: repo, to: target) } }
                .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
                .help("Troca o endereço da pasta pelo nome novo (git remote set-url)")
        }
        .padding(8)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}
