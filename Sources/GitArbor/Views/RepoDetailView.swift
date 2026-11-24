import AppKit
import GitArborCore
import SwiftUI

/// Abas de um repositório. Cada uma mostra o nome em português e o termo do GitHub.
enum RepoTab: String, CaseIterable, Identifiable {
    case overview, files, history, branches, issues, pulls, actions, releases, security, people, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Visão geral"
        case .files: "Arquivos"
        case .history: "Histórico"
        case .branches: "Ramos"
        case .issues: "Tarefas"
        case .pulls: "Pedidos de mudança"
        case .actions: "Automações"
        case .releases: "Versões"
        case .security: "Segurança"
        case .people: "Pessoas"
        case .settings: "Ajustes"
        }
    }

    var term: String {
        switch self {
        case .overview: "README"
        case .files: "Code"
        case .history: "Commits"
        case .branches: "Branches"
        case .issues: "Issues"
        case .pulls: "Pull requests"
        case .actions: "Actions"
        case .releases: "Releases"
        case .security: "Security"
        case .people: "Collaborators"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "house.fill"
        case .files: "folder.fill"
        case .history: "clock.arrow.circlepath"
        case .branches: "arrow.triangle.branch"
        case .issues: "smallcircle.filled.circle"
        case .pulls: "arrow.triangle.pull"
        case .actions: "gearshape.2.fill"
        case .releases: "tag.fill"
        case .security: "shield.lefthalf.filled"
        case .people: "person.2.fill"
        case .settings: "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .overview: Theme.accent
        case .files: .blue
        case .history: .indigo
        case .branches: .teal
        case .issues: Theme.open
        case .pulls: Theme.closed
        case .actions: .orange
        case .releases: .pink
        case .security: .red
        case .people: .cyan
        case .settings: .gray
        }
    }
}

struct RepoDetailView: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var tab: RepoTab = .overview
    @ViewState private var cloning = false

    /// Versão mais nova do repositório (depois de editar nos Ajustes).
    private var current: GHRepo { model.repos.first { $0.id == repo.id } ?? repo }

    private var localCopy: LocalRepoStatus? {
        model.localCopy(of: current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                tabBar
                Group {
                    switch tab {
                    case .overview: RepoOverview(repo: current)
                    case .files: FilesTab(repo: current)
                    case .history: HistoryTab(repo: current)
                    case .branches: BranchesTab(repo: current)
                    case .issues: IssuesTab(repo: current)
                    case .pulls: PullsTab(repo: current)
                    case .actions: ActionsTab(repo: current)
                    case .releases: ReleasesTab(repo: current)
                    case .security: SecurityTab(repo: current)
                    case .people: PeopleTab(repo: current)
                    case .settings: RepoSettingsTab(repo: current)
                    }
                }
                .id(tab)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
            .padding(28)
        }
        .navigationTitle(current.name)
        .animation(.easeInOut(duration: 0.18), value: tab)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.language(current.language).gradient)
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: "shippingbox.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(current.name).font(.system(size: 26, weight: .bold)).textSelection(.enabled)
                        Pill(text: current.isPrivate ? "Privado" : "Público", symbol: current.isPrivate ? "lock.fill" : "globe",
                             tint: current.isPrivate ? .orange : .blue)
                        HelpTip(lessonID: "visibility")
                        if current.isArchived { Pill(text: "Arquivado", symbol: "archivebox.fill", tint: .gray) }
                        if current.fork { Pill(text: "Cópia (fork)", symbol: "tuningfork", tint: .purple) }
                    }
                    Text("de \(current.owner.login)").font(.system(size: 12)).foregroundStyle(.secondary)
                    if let d = current.description, !d.isEmpty {
                        Text(d).font(.system(size: 13.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button { NSWorkspace.shared.open(current.htmlUrl) } label: { Label("Abrir no GitHub", systemImage: "safari") }
                    .buttonStyle(ActionButtonStyle())
                Button { model.copy(current.cloneUrl ?? current.htmlUrl.absoluteString, label: "Endereço copiado") } label: {
                    Label("Copiar endereço", systemImage: "link")
                }
                .buttonStyle(ActionButtonStyle(tint: .secondary))
                .help("Copia o endereço usado para clonar")
                if let local = localCopy {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([local.folder]) } label: {
                        Label("Está no seu Mac", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(ActionButtonStyle(tint: .indigo))
                    .help("Mostrar a pasta no Finder: \(local.folder.path)")
                } else {
                    Button { clone() } label: {
                        if cloning { ProgressView().controlSize(.small) } else { Label("Baixar para o Mac (clonar)", systemImage: "square.and.arrow.down") }
                    }
                    .buttonStyle(ActionButtonStyle(tint: .indigo))
                    .disabled(cloning)
                    HelpTip(lessonID: "clone")
                }
                Spacer()
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(RepoTab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(tab == t ? .white : t.tint)
                                .frame(width: 34, height: 30)
                                .background(tab == t ? AnyShapeStyle(t.tint.gradient) : AnyShapeStyle(t.tint.opacity(0.12)), in: RoundedRectangle(cornerRadius: 8))
                            Text(t.title).font(.system(size: 11.5, weight: tab == t ? .semibold : .medium))
                                .foregroundStyle(tab == t ? .primary : .secondary)
                            Text(t.term).font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        }
                        .frame(minWidth: 84)
                        .padding(.vertical, 8)
                        .background(tab == t ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(t.title) (\(t.term))")
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                }
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func clone() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Baixar aqui"
        panel.message = "Escolha a pasta onde o projeto “\(current.name)” vai ficar"
        panel.directoryURL = model.localFolder
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let url = current.cloneUrl ?? current.htmlUrl.absoluteString + ".git"
        cloning = true
        Task {
            defer { cloning = false }
            do {
                let folder = try await LocalGit.clone(url, into: parent)
                await model.refreshLocal(folder)
                model.show("checkmark.circle.fill", "“\(current.name)” baixado para o Mac")
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                model.report(error)
            }
        }
    }
}

// MARK: - Visão geral

private struct RepoOverview: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var readme: String?
    @ViewState private var readmeMissing = false
    @ViewState private var languages: [(String, Int)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                StatTile(value: "\(repo.stargazersCount)", label: "Estrelas", symbol: "star.fill", tint: .yellow, hint: "Curtidas do projeto")
                StatTile(value: "\(repo.forksCount)", label: "Cópias (forks)", symbol: "tuningfork", tint: .purple, hint: "Pessoas que copiaram")
                StatTile(value: "\(repo.openIssuesCount)", label: "Em aberto", symbol: "smallcircle.filled.circle", tint: Theme.open, hint: "Tarefas e pedidos")
                StatTile(value: Phrases.size(kilobytes: repo.size), label: "Tamanho", symbol: "externaldrive.fill", tint: .gray, hint: "Espaço no GitHub")
                StatTile(value: repo.branch, label: "Ramo principal", symbol: "arrow.triangle.branch", tint: .teal, hint: "A versão oficial")
            }

            if !languages.isEmpty { languagesCard }

            Card(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("calendar", "Criado em", Phrases.date(repo.createdAt))
                    infoRow("arrow.up.circle", "Último envio", Phrases.relative(repo.pushedAt))
                    if let home = repo.homepage, !home.isEmpty, let url = URL(string: home) {
                        HStack(spacing: 10) {
                            Image(systemName: "globe").frame(width: 18).foregroundStyle(.secondary)
                            Text("Site").font(.system(size: 12.5)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            Link(home, destination: url).font(.system(size: 12.5))
                        }
                    }
                    if let topics = repo.topics, !topics.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "number").frame(width: 18).foregroundStyle(.secondary)
                            Text("Assuntos").font(.system(size: 12.5)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            ForEach(topics, id: \.self) { Pill(text: $0, tint: .blue) }
                        }
                    }
                }
            }

            Card(padding: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Leia-me (README)", systemImage: "doc.text.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        HelpTip(lessonID: "readme")
                    }
                    Divider()
                    if let readme {
                        MarkdownView(text: readme)
                    } else if readmeMissing {
                        EmptyState(symbol: "doc.text", title: "Este projeto não tem README",
                                   message: "O README é o arquivo de apresentação. Crie um arquivo chamado README.md na pasta do projeto, salve uma versão (commit) e envie.")
                    } else {
                        LoadingRow(text: "Lendo o README…")
                    }
                }
            }
        }
        .task {
            guard let client = model.client else { return }
            async let r = try? client.readme(repo.fullName)
            async let l = try? client.languages(repo.fullName)
            if let text = await r { readme = text } else { readmeMissing = true }
            languages = (await l ?? [:]).sorted { $0.value > $1.value }
        }
    }

    private var languagesCard: some View {
        let total = Double(languages.reduce(0) { $0 + $1.1 })
        return Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Do que o projeto é feito").font(.system(size: 13, weight: .semibold))
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(languages, id: \.0) { lang in
                            Rectangle().fill(Color.language(lang.0))
                                .frame(width: max(2, geo.size.width * Double(lang.1) / total - 2))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                FlowRow(spacing: 14) {
                    ForEach(languages.prefix(8), id: \.0) { lang in
                        HStack(spacing: 5) {
                            Circle().fill(Color.language(lang.0)).frame(width: 9, height: 9)
                            Text(lang.0).font(.system(size: 12, weight: .medium))
                            Text(String(format: "%.1f%%", Double(lang.1) / total * 100)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func infoRow(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(label).font(.system(size: 12.5)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(.system(size: 12.5, weight: .medium))
        }
    }
}

/// Linha que quebra quando não cabe (etiquetas).
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += row + 6; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + 6; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Ajustes do repositório

private struct RepoSettingsTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var name = ""
    @ViewState private var description = ""
    @ViewState private var homepage = ""
    @ViewState private var isPrivate = false
    @ViewState private var hasIssues = true
    @ViewState private var busy = false
    @ViewState private var confirmVisibility = false
    @ViewState private var confirmArchive = false
    @ViewState private var showDelete = false

    private var changed: Bool {
        name != repo.name || description != (repo.description ?? "") || homepage != (repo.homepage ?? "")
            || hasIssues != (repo.hasIssues ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Informações").font(.system(size: 15, weight: .semibold))
                    LabeledField(label: "Nome", text: $name, help: model.localCopy(of: repo) == nil
                                 ? "Mudar o nome muda o endereço. O GitHub redireciona o endereço antigo."
                                 : "Mudar o nome muda o endereço. A cópia neste Mac é atualizada junto.")
                    LabeledField(label: "Descrição", text: $description, prompt: "Para que serve este projeto")
                    LabeledField(label: "Site (opcional)", text: $homepage, prompt: "https://…")
                    Toggle(isOn: $hasIssues) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Usar Tarefas (Issues)").font(.system(size: 13, weight: .medium))
                            Text("Mostra a lista de tarefas e problemas deste repositório.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    HStack {
                        Spacer()
                        Button("Desfazer") { reset() }.buttonStyle(ActionButtonStyle(tint: .secondary)).disabled(!changed)
                        Button {
                            Task { await save(["name": name, "description": description, "homepage": homepage, "has_issues": hasIssues]) }
                        } label: { if busy { ProgressView().controlSize(.small) } else { Text("Salvar alterações") } }
                        .buttonStyle(ActionButtonStyle(prominent: true))
                        .disabled(!changed || busy || name.isEmpty)
                    }
                }
            }

            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Quem pode ver").font(.system(size: 15, weight: .semibold))
                        HelpTip(lessonID: "visibility")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                            .font(.system(size: 22)).foregroundStyle(repo.isPrivate ? .orange : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.isPrivate ? "Privado" : "Público").font(.system(size: 14, weight: .semibold))
                            Text(repo.isPrivate ? "Só você e convidados veem este repositório." : "Qualquer pessoa na internet pode ver (mas não mudar).")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(repo.isPrivate ? "Tornar público…" : "Tornar privado…") { confirmVisibility = true }
                            .buttonStyle(ActionButtonStyle(tint: .orange))
                    }
                }
            }

            Card(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Zona de cuidado", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.danger)
                    dangerRow(title: repo.isArchived ? "Desarquivar" : "Arquivar",
                              detail: repo.isArchived ? "Volta a aceitar mudanças." : "Deixa o repositório só para leitura. Dá para desfazer depois.",
                              button: repo.isArchived ? "Desarquivar…" : "Arquivar…") { confirmArchive = true }
                    Divider()
                    dangerRow(title: "Apagar repositório", detail: "Apaga do GitHub para sempre: arquivos, histórico, tarefas. Cópias no seu Mac continuam.",
                              button: "Apagar…") { showDelete = true }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).strokeBorder(Theme.danger.opacity(0.3)))
        }
        .onAppear(perform: reset)
        .confirmationDialog(repo.isPrivate ? "Tornar “\(repo.name)” público?" : "Tornar “\(repo.name)” privado?", isPresented: $confirmVisibility) {
            Button(repo.isPrivate ? "Tornar público" : "Tornar privado", role: repo.isPrivate ? .destructive : nil) {
                Task { await save(["private": !repo.isPrivate]) }
            }
        } message: {
            Text(repo.isPrivate ? "Todo o código e o histórico ficarão visíveis para qualquer pessoa. Confira se não há senhas ou dados pessoais nos arquivos." : "Só você e convidados poderão ver. Estrelas e cópias de outras pessoas podem ser perdidas.")
        }
        .confirmationDialog(repo.isArchived ? "Desarquivar “\(repo.name)”?" : "Arquivar “\(repo.name)”?", isPresented: $confirmArchive) {
            Button(repo.isArchived ? "Desarquivar" : "Arquivar") { Task { await save(["archived": !repo.isArchived]) } }
        }
        .sheet(isPresented: $showDelete) { DeleteRepoSheet(repo: repo) }
    }

    private func dangerRow(title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(button, action: action).buttonStyle(ActionButtonStyle(tint: Theme.danger))
        }
    }

    private func reset() {
        name = repo.name
        description = repo.description ?? ""
        homepage = repo.homepage ?? ""
        isPrivate = repo.isPrivate
        hasIssues = repo.hasIssues ?? true
    }

    private func save(_ fields: [String: any Sendable]) async {
        guard let client = model.client else { return }
        busy = true
        defer { busy = false }
        // A cópia no Mac, se houver, guardada antes de o nome mudar.
        let local = model.localCopy(of: repo)
        do {
            let updated = try await client.updateRepository(repo.fullName, fields: fields)
            model.replace(updated)
            model.show("checkmark.circle.fill", "Alterações salvas no GitHub")
            // Mudou o nome: a pasta do Mac passa a usar o endereço novo na hora.
            if let local, updated.fullName.caseInsensitiveCompare(repo.fullName) != .orderedSame {
                await model.updateRemote(of: local, to: updated)
            }
        } catch {
            model.report(error)
        }
    }
}

private struct DeleteRepoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: GHRepo
    @ViewState private var typed = ""
    @ViewState private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "trash.fill", tint: Theme.danger, size: 40)
                Text("Apagar “\(repo.name)”?").font(.system(size: 20, weight: .bold))
            }
            Text("Isto não pode ser desfeito. O repositório, o histórico, as tarefas e os pedidos serão apagados do GitHub. A pasta no seu Mac (se existir) não é afetada.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            LabeledField(label: "Para confirmar, digite o nome: \(repo.name)", text: $typed, prompt: repo.name)
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        guard let client = model.client else { return }
                        busy = true
                        defer { busy = false }
                        do {
                            try await client.deleteRepository(repo.fullName)
                            dismiss()
                            model.removeRepo(repo)
                            model.show("trash.fill", "“\(repo.name)” foi apagado")
                        } catch GitHubError.forbidden(_) {
                            model.errorMessage = "A chave de acesso não tem permissão para apagar repositórios. No Terminal, rode: gh auth refresh -s delete_repo — e tente de novo."
                        } catch {
                            model.report(error)
                        }
                    }
                } label: { if busy { ProgressView().controlSize(.small) } else { Text("Apagar para sempre") } }
                .buttonStyle(ActionButtonStyle(tint: Theme.danger, prominent: true))
                .disabled(typed != repo.name || busy)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
