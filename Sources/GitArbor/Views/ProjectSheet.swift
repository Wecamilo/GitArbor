import AppKit
import GitArborCore
import SwiftUI

/// Pedido para abrir a janela de um projeto do Mac numa aba.
struct ProjectSheetRequest: Identifiable, Hashable {
    let folder: URL
    var tab: ProjectSheet.Tab
    var id: URL { folder }
}

/// Janela de um projeto do Mac: linha do tempo, ramos, guardados, conflitos e segredos.
struct ProjectSheet: View {
    enum Tab: String, Hashable, CaseIterable {
        case timeline, branches, stash, conflicts, secrets

        var title: String {
            switch self {
            case .timeline: "Linha do tempo"
            case .branches: "Ramos"
            case .stash: "Guardados"
            case .conflicts: "Conflitos"
            case .secrets: "Segredos"
            }
        }

        var symbol: String {
            switch self {
            case .timeline: "clock.arrow.circlepath"
            case .branches: "arrow.triangle.branch"
            case .stash: "tray.full.fill"
            case .conflicts: "exclamationmark.triangle.fill"
            case .secrets: "key.horizontal.fill"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let folder: URL
    @ViewState var tab: Tab

    init(request: ProjectSheetRequest) {
        folder = request.folder
        _tab = ViewState(initialValue: request.tab)
    }

    private var repo: LocalRepoStatus? { model.localStatus(folder) }
    private var busy: Bool { model.busyFolders.contains(folder) }

    private var tabs: [ChipOption<Tab>] {
        Tab.allCases.compactMap { t in
            if t == .conflicts && repo?.state != .conflict && tab != .conflicts { return nil }
            let count: Int? = switch t {
            case .stash: (repo?.stashCount ?? 0) > 0 ? repo?.stashCount : nil
            case .conflicts: repo?.conflicts.count
            default: nil
            }
            return ChipOption(value: t, title: t.title, symbol: t.symbol, count: count)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: "laptopcomputer", tint: .indigo, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.lastPathComponent).font(.system(size: 18, weight: .bold))
                    HStack(spacing: 8) {
                        if let repo {
                            LocalStateBadge(state: repo.state, small: true)
                            Text(LocalStateBadge.title(repo.state)).font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(LocalStateBadge.tint(repo.state))
                            if let b = repo.branch {
                                Label(b, systemImage: "arrow.triangle.branch").font(.system(size: 11, design: .monospaced)).foregroundStyle(.teal)
                            }
                        }
                    }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            HStack {
                FilterChips(selection: $tab, options: tabs, tint: .indigo)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
            Divider()
            Group {
                switch tab {
                case .timeline: TimelinePane(folder: folder)
                case .branches: BranchesPane(folder: folder, onConflict: { tab = .conflicts })
                case .stash: StashPane(folder: folder, onConflict: { tab = .conflicts })
                case .conflicts: ConflictsPane(folder: folder, onDone: { tab = .timeline })
                case .secrets: SecretsPane(folder: folder)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 980, height: 680)
    }
}

/// Faixa curta de explicação com o “?” da lição.
private struct PaneIntro: View {
    let text: String
    let lessonID: String
    var symbol = "lightbulb.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.yellow)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            HelpTip(lessonID: lessonID, label: "Saber mais")
        }
        .padding(10)
        .background(Color.yellow.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

// MARK: - Linha do tempo

private struct TimelinePane: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    @ViewState private var mode = 0
    @ViewState private var commits: [LocalCommit]?
    @ViewState private var deleted: [DeletedFile]?
    @ViewState private var selected: LocalCommit?
    @ViewState private var files: [FileChange] = []
    @ViewState private var stats: ChangeExplainer.Stats = [:]
    @ViewState private var patch = ""
    @ViewState private var confirm: Confirm?

    enum Confirm: Identifiable {
        case undo(LocalCommit), revert(LocalCommit), restore(LocalCommit)
        var id: String {
            switch self {
            case .undo(let c): "u" + c.sha
            case .revert(let c): "r" + c.sha
            case .restore(let c): "t" + c.sha
            }
        }
    }

    private var repo: LocalRepoStatus? { model.localStatus(folder) }
    private var reloadKey: String { "\(repo?.lastCommitDate?.timeIntervalSince1970 ?? 0)-\(repo?.branch ?? "")-\(repo?.changes.count ?? 0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneIntro(text: "Cada versão salva fica guardada. Escolha uma para ver o que mudou, desfazer o que ela fez ou deixar o projeto como estava naquele momento. Nada do histórico é apagado.",
                      lessonID: "timeline")
            HStack {
                FilterChips(selection: $mode, options: [
                    ChipOption(value: 0, title: "Versões salvas", symbol: "camera.fill", count: commits?.count),
                    ChipOption(value: 1, title: "Arquivos apagados", symbol: "trash.fill", count: deleted?.count)
                ], tint: .indigo)
                Spacer()
                if let last = commits?.first, last.pushed != true, last.parents > 0 {
                    Button { confirm = .undo(last) } label: { Label("Desfazer a última versão", systemImage: "arrow.uturn.backward.circle.fill") }
                        .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
                        .help("Ela ainda não foi enviada: as mudanças voltam a ficar não salvas, para você ajustar e salvar de novo")
                }
            }
            if mode == 0 { versions } else { deletedList }
        }
        .padding(20)
        .task(id: reloadKey) { await load() }
        .task(id: selected) { await loadSelected() }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { c in
            switch c {
            case .undo:
                Button("Desfazer a última versão") { run { try await LocalGit.undoLastCommit(at: folder) } success: { "Última versão desfeita: as mudanças voltaram a ficar não salvas" } }
            case .revert(let commit):
                Button("Desfazer esta versão") { revert(commit) }
            case .restore(let commit):
                Button("Voltar o projeto para cá") { run { try await LocalGit.restoreProject(to: commit, at: folder) } success: { "O projeto voltou para “\(commit.message)”" } }
            }
        } message: { c in
            switch c {
            case .undo: Text("A versão some do histórico deste Mac, mas os arquivos continuam como estão: as mudanças dela aparecem como não salvas.")
            case .revert: Text("Cria uma versão nova que faz o contrário desta. O histórico continua inteiro, então é seguro mesmo que ela já esteja no GitHub.")
            case .restore: Text("Todos os arquivos ficam como estavam nesta versão, e isso é salvo como uma versão nova. As versões de depois continuam no histórico, então dá para voltar de novo.")
            }
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .undo: "Desfazer a última versão salva?"
        case .revert(let c): "Desfazer “\(c.message)”?"
        case .restore(let c): "Voltar o projeto para “\(c.message)”?"
        case nil: ""
        }
    }

    @ViewBuilder private var versions: some View {
        if let commits {
            if commits.isEmpty {
                EmptyState(symbol: "camera", title: "Nenhuma versão salva ainda", message: "Quando você salvar a primeira versão, ela aparece aqui.")
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                                commitRow(commit, first: index == 0, last: index == commits.count - 1)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(width: 360)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).strokeBorder(Color.primary.opacity(0.07)))
            }
        } else {
            LoadingRow(text: "Lendo o histórico…")
        }
    }

    private func commitRow(_ commit: LocalCommit, first: Bool, last: Bool) -> some View {
        let tint: Color = commit.pushed == false ? .orange : .indigo
        return HStack(alignment: .top, spacing: 10) {
            // Trilho da linha do tempo.
            VStack(spacing: 0) {
                Rectangle().fill(first ? .clear : Color.indigo.opacity(0.25)).frame(width: 2, height: 10)
                Circle().fill(tint.gradient).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                Rectangle().fill(last ? .clear : Color.indigo.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(commit.message).font(.system(size: 12.5, weight: .medium)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(Phrases.relative(commit.date)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Text(commit.shortSHA).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    switch commit.pushed {
                    case .some(false): Pill(text: "Só no Mac", tint: .orange)
                    case .some(true): Pill(text: "No GitHub", tint: .blue)
                    case nil: EmptyView()
                    }
                    if commit.isMerge { Pill(text: "Junção", tint: .teal) }
                }
            }
            .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .background(selected == commit ? Theme.accentSoft : .clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = commit }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var detail: some View {
        if let commit = selected {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(commit.message).font(.system(size: 15, weight: .bold)).textSelection(.enabled)
                    Text("\(commit.author) · \(Phrases.relative(commit.date)) · \(commit.shortSHA)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    ExplainBox(lines: ChangeExplainer.summary(files, stats: stats))
                    HStack(spacing: 8) {
                        Button { confirm = .revert(commit) } label: { Label("Desfazer esta versão", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(ActionButtonStyle(tint: .orange))
                            .help("Cria uma versão nova que faz o contrário desta")
                        Button { confirm = .restore(commit) } label: { Label("Voltar o projeto para cá", systemImage: "clock.arrow.circlepath") }
                            .buttonStyle(ActionButtonStyle(tint: .indigo))
                            .help("Deixa todos os arquivos como estavam nesta versão")
                            .disabled(commit == commits?.first)
                        Spacer()
                        Button { model.copy(commit.sha, label: "Código da versão copiado") } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Copiar o código (SHA) desta versão")
                    }
                    .disabled(model.busyFolders.contains(folder))
                }
                .padding(16)
                Divider()
                if patch.isEmpty {
                    EmptyState(symbol: "doc", title: "Sem texto para mostrar", message: "Esta versão não mudou arquivos de texto (ou é uma junção).")
                } else {
                    ScrollView { DiffText(patch: patch) }
                }
            }
        } else {
            EmptyState(symbol: "hand.point.left", title: "Escolha uma versão", message: "Clique numa versão à esquerda para ver o que mudou e as opções para voltar no tempo.")
        }
    }

    @ViewBuilder private var deletedList: some View {
        if let deleted {
            if deleted.isEmpty {
                EmptyState(symbol: "trash.slash", title: "Nenhum arquivo apagado para recuperar", message: "Arquivos apagados em versões salvas aparecem aqui, prontos para voltar.")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(deleted) { file in
                            HStack(spacing: 10) {
                                Image(systemName: "doc.badge.clock").foregroundStyle(.indigo).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.path).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                    Text("Apagado em “\(file.message)” · \(Phrases.relative(file.date))").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button { restore(file) } label: { Label("Trazer de volta", systemImage: "arrow.uturn.backward.circle.fill") }
                                    .buttonStyle(ActionButtonStyle(tint: .indigo, prominent: true))
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        } else {
            LoadingRow(text: "Procurando arquivos apagados…")
        }
    }

    private func load() async {
        let loaded = (try? await LocalGit.history(at: folder)) ?? []
        commits = loaded
        if let s = selected, !loaded.contains(s) { selected = nil }
        if selected == nil { selected = loaded.first }
        deleted = await LocalGit.deletedFiles(at: folder)
    }

    private func loadSelected() async {
        guard let commit = selected else { files = []; patch = ""; return }
        async let f = LocalGit.filesChanged(in: commit.sha, at: folder)
        async let s = LocalGit.lineStats(of: commit.sha, at: folder)
        async let p = LocalGit.patch(of: commit.sha, at: folder)
        (files, stats, patch) = await (f, s, p)
    }

    private func run(_ action: @escaping @Sendable () async throws -> Void, success: () -> String) {
        let message = success()
        let folder = folder
        Task {
            if await model.runLocal(folder, success: message, action) { await load() }
        }
    }

    private func revert(_ commit: LocalCommit) {
        let folder = folder
        Task {
            _ = await model.runLocalOutcome(folder, success: "Versão “\(commit.message)” desfeita") {
                try await LocalGit.revert(commit, at: folder)
            }
            await load()
        }
    }

    private func restore(_ file: DeletedFile) {
        run { try await LocalGit.restoreFile(file.path, from: file.deletedIn + "^", at: folder) } success: {
            "“\((file.path as NSString).lastPathComponent)” voltou (aparece como mudança não salva)"
        }
    }
}

/// Caixa “O que mudou, em português”.
struct ExplainBox: View {
    let lines: [String]
    var title = "O que mudou, em português"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "text.bubble.fill").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.accent)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.system(size: 12)).foregroundStyle(line.hasPrefix("Atenção") ? Theme.danger : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Ramos

private struct BranchesPane: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    let onConflict: () -> Void
    @ViewState private var branches: [LocalBranch]?
    @ViewState private var newName = ""
    @ViewState private var deleting: LocalBranch?

    private var repo: LocalRepoStatus? { model.localStatus(folder) }
    private var busy: Bool { model.busyFolders.contains(folder) }
    private var current: String? { repo?.branch }
    private var slug: String { LocalGit.branchSlug(newName) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PaneIntro(text: "Um ramo é um caminho paralelo: experimente à vontade sem mexer no principal. Quando der certo, junte de volta. Trocar de ramo troca os arquivos da pasta.",
                          lessonID: "branch")

                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Começar um ramo novo a partir de “\(current ?? "agora")”").font(.system(size: 13, weight: .semibold))
                        HStack(alignment: .bottom, spacing: 10) {
                            LabeledField(label: "Nome do ramo", text: $newName, prompt: "ex.: nova-tela-inicial",
                                         help: slug.isEmpty ? "As mudanças não salvas vão junto para o ramo novo." : "Vai ficar: \(slug). As mudanças não salvas vão junto.")
                            Button { create() } label: { Label("Criar e trocar", systemImage: "plus") }
                                .buttonStyle(ActionButtonStyle(tint: .teal, prominent: true))
                                .disabled(slug.isEmpty || busy)
                                .padding(.bottom, slug.isEmpty ? 22 : 22)
                        }
                    }
                }

                if let branches {
                    let local = branches.filter { !$0.remoteOnly }
                    let remote = branches.filter(\.remoteOnly)
                    Text("No Mac").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(local) { row($0) }
                    if !remote.isEmpty {
                        Text("Só no GitHub").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
                        ForEach(remote) { row($0) }
                    }
                } else {
                    LoadingRow(text: "Lendo os ramos…")
                }
            }
            .padding(20)
        }
        .task(id: "\(repo?.branch ?? "")-\(repo?.lastCommitDate?.timeIntervalSince1970 ?? 0)") { await load() }
        .confirmationDialog("Apagar o ramo “\(deleting?.name ?? "")” deste Mac?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { b in
            Button("Apagar ramo", role: .destructive) {
                let folder = folder
                Task { if await model.runLocal(folder, success: "Ramo “\(b.name)” apagado do Mac", { try await LocalGit.deleteBranch(b, at: folder) }) { await load() } }
            }
        } message: { _ in
            Text("O Git só apaga se tudo o que há nele já estiver juntado em outro ramo, para nada se perder. No GitHub, o ramo continua.")
        }
    }

    private func row(_ b: LocalBranch) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: b.isCurrent ? "location.fill" : (b.remoteOnly ? "icloud.fill" : "arrow.triangle.branch"),
                     tint: b.isCurrent ? .teal : (b.remoteOnly ? .blue : .gray), size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(b.name).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if b.isCurrent { Pill(text: "Você está aqui", tint: .teal) }
                    if b.gone { Pill(text: "Apagado no GitHub", tint: .gray) }
                    if b.ahead > 0 { Pill(text: "\(b.ahead) a enviar", symbol: "arrow.up", tint: .blue) }
                    if b.behind > 0 { Pill(text: "\(b.behind) a baixar", symbol: "arrow.down", tint: .purple) }
                }
                Text([b.subject.map { "“\($0)”" }, b.date.map { Phrases.relative($0) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !b.isCurrent {
                Button { switchTo(b) } label: { Label(b.remoteOnly ? "Trazer e trocar" : "Trocar para este", systemImage: "arrow.right.circle") }
                    .buttonStyle(ActionButtonStyle(tint: .teal))
                    .help(b.remoteOnly ? "Cria a cópia deste ramo no Mac, ligada ao GitHub, e passa a trabalhar nele" : "Os arquivos da pasta passam a ser os deste ramo")
                Button { merge(b) } label: { Label("Juntar em “\(current ?? "atual")”", systemImage: "arrow.triangle.merge") }
                    .buttonStyle(ActionButtonStyle(tint: .indigo))
                    .help("Traz as mudanças deste ramo para o ramo em que você está")
                    .disabled(current == nil)
                if !b.remoteOnly {
                    Button { deleting = b } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Apagar este ramo do Mac")
                }
            }
        }
        .padding(10)
        .background(b.isCurrent ? Color.teal.opacity(0.07) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .disabled(busy)
    }

    private func load() async {
        branches = (try? await LocalGit.branches(at: folder)) ?? []
    }

    private func create() {
        let name = slug, folder = folder
        Task {
            if await model.runLocal(folder, success: "Ramo “\(name)” criado — você já está nele", { try await LocalGit.createBranch(name, at: folder) }) {
                newName = ""
                await load()
            }
        }
    }

    private func switchTo(_ b: LocalBranch) {
        let folder = folder
        Task {
            if await model.runLocal(folder, success: "Agora você está no ramo “\(b.name)”", { try await LocalGit.switchBranch(b, at: folder) }) { await load() }
        }
    }

    private func merge(_ b: LocalBranch) {
        let folder = folder, target = current ?? "atual"
        Task {
            let outcome = await model.runLocalOutcome(folder, success: "“\(b.name)” juntado em “\(target)”") { try await LocalGit.merge(b, at: folder) }
            if outcome == .conflicts { onConflict() } else { await load() }
        }
    }
}

// MARK: - Guardados

private struct StashPane: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    let onConflict: () -> Void
    @ViewState private var entries: [StashEntry]?
    @ViewState private var note = ""
    @ViewState private var dropping: StashEntry?

    private var repo: LocalRepoStatus? { model.localStatus(folder) }
    private var busy: Bool { model.busyFolders.contains(folder) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PaneIntro(text: "Guardar para depois tira as mudanças não salvas da pasta e põe numa gaveta. Útil para baixar novidades ou trocar de ramo sem perder nada nem salvar uma versão pela metade.",
                          lessonID: "stash")
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        let count = repo?.changes.count ?? 0
                        Text(count == 0 ? "Não há mudanças não salvas para guardar agora."
                             : "\(Phrases.plural(count, "arquivo mudado", "arquivos mudados")) pode ir para a gaveta.")
                            .font(.system(size: 13, weight: .semibold))
                        HStack(alignment: .bottom, spacing: 10) {
                            LabeledField(label: "Lembrete (opcional)", text: $note, prompt: "ex.: tela de busca pela metade")
                            Button { save() } label: { Label("Guardar para depois", systemImage: "tray.and.arrow.down.fill") }
                                .buttonStyle(ActionButtonStyle(tint: .indigo, prominent: true))
                                .disabled(count == 0 || busy)
                        }
                    }
                }
                if let entries {
                    if entries.isEmpty {
                        EmptyState(symbol: "tray", title: "A gaveta está vazia", message: "Mudanças guardadas aparecem aqui até você trazer de volta.")
                    } else {
                        ForEach(entries) { e in
                            HStack(spacing: 12) {
                                IconTile(symbol: "tray.full.fill", tint: .indigo, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.message).font(.system(size: 13, weight: .medium))
                                    Text([e.branch.map { "do ramo “\($0)”" }, e.date.map { Phrases.relative($0) }].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { apply(e) } label: { Label("Trazer de volta", systemImage: "tray.and.arrow.up.fill") }
                                    .buttonStyle(ActionButtonStyle(tint: .indigo, prominent: true))
                                Button { dropping = e } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Jogar fora estas mudanças guardadas")
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                            .disabled(busy)
                        }
                    }
                } else {
                    LoadingRow(text: "Abrindo a gaveta…")
                }
            }
            .padding(20)
        }
        .task(id: "\(repo?.stashCount ?? -1)-\(repo?.changes.count ?? 0)") { entries = await LocalGit.stashes(at: folder) }
        .confirmationDialog("Jogar fora “\(dropping?.message ?? "")”?", isPresented: Binding(get: { dropping != nil }, set: { if !$0 { dropping = nil } }), presenting: dropping) { e in
            Button("Jogar fora", role: .destructive) {
                let folder = folder
                Task {
                    _ = await model.runLocal(folder, success: "Mudanças guardadas jogadas fora") { try await LocalGit.dropStash(e, at: folder) }
                    entries = await LocalGit.stashes(at: folder)
                }
            }
        } message: { _ in
            Text("Essas mudanças nunca foram salvas como versão: depois de jogar fora, não dá para recuperar pelo Git Arbor.")
        }
    }

    private func save() {
        let folder = folder, text = note
        Task {
            if await model.runLocal(folder, success: "Mudanças guardadas — a pasta está como na última versão", { try await LocalGit.stash(at: folder, message: text) }) {
                note = ""
            }
            entries = await LocalGit.stashes(at: folder)
        }
    }

    private func apply(_ e: StashEntry) {
        let folder = folder
        Task {
            let outcome = await model.runLocalOutcome(folder, success: "Mudanças trazidas de volta") { try await LocalGit.applyStash(e, at: folder) }
            entries = await LocalGit.stashes(at: folder)
            if outcome == .conflicts { onConflict() }
        }
    }
}

// MARK: - Conflitos

private struct ConflictsPane: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    let onDone: () -> Void
    @ViewState private var selected: String?
    @ViewState private var confirmAbort = false

    private var repo: LocalRepoStatus? { model.localStatus(folder) }
    private var busy: Bool { model.busyFolders.contains(folder) }
    private var conflicts: [FileChange] { repo?.conflicts ?? [] }

    /// No rebase os lados se invertem: “ours” é o que veio de fora.
    private var swapped: Bool { repo?.operation == .rebase }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "exclamationmark.triangle.fill", tint: Theme.danger, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(repo?.operation?.title ?? (conflicts.isEmpty ? "Sem conflitos" : "Conflitos ao trazer mudanças guardadas"))
                            .font(.system(size: 14, weight: .bold))
                        HelpTip(lessonID: "conflict")
                    }
                    Text(conflicts.isEmpty
                         ? (repo?.operation != nil ? "Tudo resolvido. Conclua para salvar a junção como uma versão." : "Não há nada para resolver agora.")
                         : "\(Phrases.plural(conflicts.count, "arquivo mudou", "arquivos mudaram")) nos dois lados nas mesmas linhas. Para cada trecho, escolha qual versão fica. Nada se perde enquanto você decide.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if repo?.operation != nil {
                    Button { confirmAbort = true } label: { Label("Desistir e voltar como estava", systemImage: "xmark.circle") }
                        .buttonStyle(ActionButtonStyle(tint: .secondary))
                    Button { finish() } label: { Label("Concluir", systemImage: "checkmark.circle.fill") }
                        .buttonStyle(ActionButtonStyle(tint: Theme.open, prominent: true))
                        .disabled(!conflicts.isEmpty || busy)
                        .help(conflicts.isEmpty ? "Salva a junção como uma versão" : "Resolva todos os arquivos antes")
                }
            }
            .padding(14)
            .background(Theme.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardCorner))

            if conflicts.isEmpty {
                EmptyState(symbol: "checkmark.seal.fill", title: "Nenhum arquivo em conflito", message: repo?.operation != nil ? "Clique em Concluir para terminar." : "Pode voltar para a linha do tempo.", tint: Theme.open)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(conflicts) { c in
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger).font(.system(size: 11))
                                    Text(c.path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 7)
                                .background(selected == c.path ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                                .onTapGesture { selected = c.path }
                            }
                        }
                        .padding(10)
                    }
                    .frame(width: 260)
                    Divider()
                    if let path = selected, conflicts.contains(where: { $0.path == path }) {
                        ConflictEditor(folder: folder, path: path, swapped: swapped)
                            .id(path)
                    } else {
                        EmptyState(symbol: "hand.point.left", title: "Escolha um arquivo", message: "Clique num arquivo à esquerda para resolver.")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).strokeBorder(Color.primary.opacity(0.07)))
            }
        }
        .padding(20)
        .onAppear { if selected == nil { selected = conflicts.first?.path } }
        .onChange(of: conflicts.map(\.path)) { _, paths in
            if let s = selected, !paths.contains(s) { selected = paths.first }
        }
        .confirmationDialog("Desistir e voltar como estava?", isPresented: $confirmAbort) {
            Button("Desistir", role: .destructive) {
                let folder = folder
                Task { if await model.runLocal(folder, success: "Tudo voltou a ser como antes da junção", { try await LocalGit.abortOperation(at: folder) }) { onDone() } }
            }
        } message: {
            Text("A junção é cancelada e os arquivos voltam a ser como estavam antes dela. As escolhas feitas até agora se perdem.")
        }
    }

    private func finish() {
        let folder = folder
        Task { if await model.runLocal(folder, success: "Junção concluída e salva como versão", { try await LocalGit.continueOperation(at: folder) }) { onDone() } }
    }
}

/// Resolve um arquivo: trecho por trecho, ou ficando com um lado inteiro.
private struct ConflictEditor: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    let path: String
    let swapped: Bool
    @ViewState private var document: ConflictDocument?
    @ViewState private var choices: [ConflictDocument.Choice] = []
    @ViewState private var loaded = false

    private var macTitle: String { "Sua versão (neste Mac)" }
    private var otherTitle: String { "A versão que chegou" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(path).font(.system(size: 12.5, weight: .semibold, design: .monospaced)).lineLimit(1).truncationMode(.head)
                Spacer()
                Button("Ficar com a minha inteira") { keepWhole(mine: true) }
                    .buttonStyle(ActionButtonStyle(tint: .blue))
                Button("Ficar com a que chegou") { keepWhole(mine: false) }
                    .buttonStyle(ActionButtonStyle(tint: .purple))
            }
            .padding(12)
            Divider()
            if let document, document.conflictCount > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(conflictSegments(document).enumerated()), id: \.offset) { index, item in
                            conflictCard(index: index, conflict: item.conflict, before: item.before)
                        }
                    }
                    .padding(14)
                }
                Divider()
                HStack {
                    Text("Escolha um lado (ou os dois) em cada trecho e salve.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                    Button { save(document) } label: { Label("Marcar como resolvido", systemImage: "checkmark.circle.fill") }
                        .buttonStyle(ActionButtonStyle(tint: Theme.open, prominent: true))
                }
                .padding(12)
            } else if loaded {
                EmptyState(symbol: "doc.questionmark", title: "Não dá para mostrar os trechos",
                           message: "Pode ser uma imagem, um arquivo grande ou um arquivo apagado de um dos lados. Use os botões acima para ficar com uma das versões inteira.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LoadingRow(text: "Abrindo o arquivo…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if let text = LocalGit.conflictText(path, at: folder) {
                let doc = ConflictDocument.parse(text)
                document = doc
                choices = Array(repeating: .both, count: doc.conflictCount)
            }
            loaded = true
        }
    }

    private func conflictSegments(_ doc: ConflictDocument) -> [(conflict: ConflictDocument.Conflict, before: String)] {
        var result: [(ConflictDocument.Conflict, String)] = []
        var previous = ""
        for segment in doc.segments {
            switch segment {
            case .common(let text): previous = text
            case .conflict(let c):
                result.append((c, previous.split(separator: "\n", omittingEmptySubsequences: false).suffix(2).joined(separator: "\n")))
                previous = ""
            }
        }
        return result
    }

    private func conflictCard(index: Int, conflict: ConflictDocument.Conflict, before: String) -> some View {
        let mine = swapped ? conflict.theirs : conflict.ours
        let other = swapped ? conflict.ours : conflict.theirs
        let choice = index < choices.count ? choices[index] : .both
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trecho \(index + 1)").font(.system(size: 12, weight: .bold))
                Spacer()
                Picker("Escolha", selection: Binding(get: { choice }, set: { if index < choices.count { choices[index] = $0 } })) {
                    Text("A minha").tag(swapped ? ConflictDocument.Choice.theirs : .ours)
                    Text("A que chegou").tag(swapped ? ConflictDocument.Choice.ours : .theirs)
                    Text("As duas").tag(ConflictDocument.Choice.both)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
            }
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(before).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2)
            }
            HStack(alignment: .top, spacing: 10) {
                side(macTitle, mine, .blue, picked: choice == (swapped ? .theirs : .ours) || choice == .both)
                side(otherTitle + (conflict.theirsLabel.isEmpty || swapped ? "" : " · \(conflict.theirsLabel)"), other, .purple,
                     picked: choice == (swapped ? .ours : .theirs) || choice == .both)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    private func side(_ title: String, _ text: String, _ tint: Color, picked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle").foregroundStyle(picked ? tint : .secondary)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
            }
            Text(text.isEmpty ? "(nada — este lado apagou o trecho)" : text)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tint.opacity(picked ? 0.1 : 0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(picked ? 0.45 : 0.1)))
        .opacity(picked ? 1 : 0.6)
    }

    private func save(_ doc: ConflictDocument) {
        let content = doc.resolved(choices), folder = folder, path = path
        Task { _ = await model.runLocal(folder, success: "“\((path as NSString).lastPathComponent)” resolvido") { try await LocalGit.resolveConflict(path, content: content, at: folder) } }
    }

    private func keepWhole(mine: Bool) {
        // No rebase, “a minha” é o lado “theirs” para o Git.
        let ours = swapped ? !mine : mine
        let folder = folder, path = path
        Task { _ = await model.runLocal(folder, success: "“\((path as NSString).lastPathComponent)” resolvido") { try await LocalGit.resolveConflict(path, keepOurs: ours, at: folder) } }
    }
}

// MARK: - Segredos

private struct SecretsPane: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    @ViewState private var findings: [SecretFinding]?
    @ViewState private var scanning = false

    private var repo: LocalRepoStatus? { model.localStatus(folder) }
    private var isPublic: Bool {
        guard let repo, let name = model.gitHubName(of: repo) else { return false }
        return model.repos.first { $0.fullName.caseInsensitiveCompare(name) == .orderedSame }?.isPrivate == false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PaneIntro(text: "A proteção do .gitignore evita que arquivos de senha subam daqui em diante. Esta busca olha para trás: procura chaves e senhas escritas dentro dos arquivos em todas as versões já salvas.",
                          lessonID: "security", symbol: "key.horizontal.fill")
                HStack {
                    Button { Task { await scan() } } label: {
                        if scanning { ProgressView().controlSize(.small) } else { Label(findings == nil ? "Procurar no histórico" : "Procurar de novo", systemImage: "magnifyingglass") }
                    }
                    .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
                    .disabled(scanning)
                    Text("Tudo acontece neste Mac; nada é enviado para fora.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer()
                }
                if let findings {
                    if findings.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield.fill").font(.system(size: 22)).foregroundStyle(Theme.open)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nenhuma chave ou senha encontrada").font(.system(size: 13, weight: .semibold))
                                Text("Foram conferidas as últimas 1.500 versões de todos os ramos.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.open.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner))
                    } else {
                        advice
                        ForEach(findings) { f in
                            HStack(alignment: .top, spacing: 12) {
                                IconTile(symbol: "key.fill", tint: Theme.danger, size: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(f.kind).font(.system(size: 13, weight: .semibold))
                                        Text(f.preview).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    Text(f.path).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                    Text("Entrou em “\(f.commitMessage)” · \(Phrases.relative(f.date)) · \(String(f.commit.prefix(7)))")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Theme.danger.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var advice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("O que fazer", systemImage: "list.number").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.danger)
            Text("1. Troque cada chave encontrada no site do serviço (gere uma nova e desative a antiga). \(isPublic ? "Este repositório é público: considere que as chaves já foram vistas." : "Mesmo em repositório privado, trocar é o mais seguro.")")
            Text("2. Guarde a chave nova num arquivo .env (protegido pelo .gitignore) e leia dela no código, em vez de escrever a chave no arquivo.")
            Text("3. Apagar do histórico antigo é opcional e avançado — depois de trocar, a chave antiga já não serve para nada.")
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(Theme.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private func scan() async {
        scanning = true
        defer { scanning = false }
        findings = await SecretScanner.scan(at: folder)
    }
}
