import AppKit
import GitArborCore
import SwiftUI

// MARK: - Arquivos

struct FilesTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var path: [String] = []
    @ViewState private var items: [GHContent]?
    @ViewState private var file: GHContent?
    @ViewState private var empty = false

    private var pathString: String { path.joined(separator: "/") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "repository", text: "Estes são os arquivos do projeto como estão no GitHub, no ramo principal (\(repo.branch)). Clique numa pasta para entrar e num arquivo para ver o conteúdo.")

            // Caminho clicável.
            HStack(spacing: 4) {
                crumb("Início", icon: "shippingbox.fill", depth: 0)
                ForEach(Array(path.enumerated()), id: \.offset) { i, part in
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                    crumb(part, icon: "folder.fill", depth: i + 1)
                }
                if let file {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                    Label(file.name, systemImage: FileIcon.symbol(file.name)).font(.system(size: 12.5, weight: .semibold))
                }
                Spacer()
            }

            if let file {
                FileViewer(repo: repo, file: file) { self.file = nil }
            } else if empty {
                EmptyState(symbol: "folder", title: "Repositório vazio", message: "Ainda não há arquivos. Envie (push) um projeto do Mac ou crie um README.")
            } else if let items {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            Button { open(item) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isDirectory ? "folder.fill" : FileIcon.symbol(item.name))
                                        .font(.system(size: 15))
                                        .foregroundStyle(item.isDirectory ? Color.blue : FileIcon.tint(item.name))
                                        .frame(width: 22)
                                    Text(item.name).font(.system(size: 13, weight: item.isDirectory ? .medium : .regular))
                                    Spacer()
                                    if !item.isDirectory {
                                        Text(Phrases.size(bytes: item.size)).font(.system(size: 11)).foregroundStyle(.tertiary)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if i < items.count - 1 { Divider().padding(.leading, 50) }
                        }
                    }
                }
            } else {
                LoadingRow(text: "Abrindo a pasta…")
            }
        }
        .task(id: pathString) { await load() }
    }

    private func crumb(_ title: String, icon: String, depth: Int) -> some View {
        Button {
            file = nil
            path = Array(path.prefix(depth))
        } label: {
            Label(title, systemImage: icon).font(.system(size: 12.5, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    private func open(_ item: GHContent) {
        if item.isDirectory { path.append(item.name) } else { file = item }
    }

    private func load() async {
        guard let client = model.client else { return }
        items = nil
        empty = false
        do {
            let list = try await client.contents(repo.fullName, path: pathString, ref: nil)
            items = list.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch GitHubError.notFound {
            empty = true
        } catch {
            model.report(error)
        }
    }
}

enum FileIcon {
    static func ext(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }

    static func symbol(_ name: String) -> String {
        switch ext(name) {
        case "swift", "js", "ts", "py", "rb", "go", "java", "kt", "c", "cpp", "h", "rs", "php", "cs", "sh", "tsx", "jsx", "vue": "chevron.left.forwardslash.chevron.right"
        case "md", "txt", "rtf": "doc.text.fill"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "icns", "ico": "photo.fill"
        case "json", "yml", "yaml", "toml", "plist", "xml": "curlybraces"
        case "html", "css", "scss": "globe"
        case "zip", "gz", "tar": "doc.zipper"
        case "pdf": "doc.richtext.fill"
        default: name.hasPrefix(".") ? "gearshape.fill" : "doc.fill"
        }
    }

    static func tint(_ name: String) -> Color {
        switch ext(name) {
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "icns", "ico": .pink
        case "md", "txt": .gray
        case "json", "yml", "yaml", "toml", "plist", "xml": .orange
        default: Theme.accent
        }
    }

    static func isImage(_ name: String) -> Bool { ["png", "jpg", "jpeg", "gif", "webp", "heic", "icns", "ico", "bmp", "tiff"].contains(ext(name)) }
}

private struct FileViewer: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    let file: GHContent
    let onClose: () -> Void
    @ViewState private var loaded: GHContent?
    @ViewState private var failed = false

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { onClose() } label: { Label("Voltar à pasta", systemImage: "chevron.left") }
                        .buttonStyle(ActionButtonStyle(tint: .secondary))
                    Spacer()
                    Text(Phrases.size(bytes: file.size)).font(.system(size: 11)).foregroundStyle(.secondary)
                    if let text = loaded?.decodedText {
                        Button { model.copy(text, label: "Conteúdo copiado") } label: { Label("Copiar", systemImage: "doc.on.doc") }
                            .buttonStyle(ActionButtonStyle(tint: .secondary))
                    }
                    if let url = file.htmlUrl {
                        Button { NSWorkspace.shared.open(url) } label: { Label("Abrir no GitHub", systemImage: "safari") }
                            .buttonStyle(ActionButtonStyle())
                    }
                }
                .padding(12)
                Divider()
                content
            }
        }
        .task(id: file.path) {
            guard let client = model.client else { return }
            loaded = nil
            failed = false
            if file.size > 1_000_000 { failed = true; return }
            do { loaded = try await client.file(repo.fullName, path: file.path, ref: nil) } catch { failed = true }
        }
    }

    @ViewBuilder private var content: some View {
        if failed {
            EmptyState(symbol: "doc.questionmark", title: "Não dá para mostrar aqui", message: "O arquivo é grande demais ou não é texto. Abra no GitHub para ver.")
        } else if let loaded {
            if FileIcon.isImage(file.name), let data = loaded.decodedData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 480).padding(20)
            } else if file.name.lowercased().hasSuffix(".md"), let text = loaded.decodedText {
                MarkdownView(text: text).padding(20)
            } else if let text = loaded.decodedText {
                CodeText(text: text)
            } else {
                EmptyState(symbol: "doc.questionmark", title: "Arquivo binário", message: "Este arquivo não é texto. Abra no GitHub ou no Mac para ver.")
            }
        } else {
            LoadingRow(text: "Abrindo o arquivo…")
        }
    }
}

/// Texto com números de linha.
struct CodeText: View {
    let text: String

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(0..<min(lines.count, 3000), id: \.self) { i in
                        Text("\(i + 1)").foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10)
                .background(Color.primary.opacity(0.03))
                Text(lines.prefix(3000).joined(separator: "\n"))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Histórico

struct HistoryTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var branches: [GHBranch] = []
    @ViewState private var branch: String = ""
    @ViewState private var commits: [GHCommit]?
    @ViewState private var page = 1
    @ViewState private var hasMore = true
    @ViewState private var selected: GHCommit?
    @ViewState private var empty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "commit")
            HStack {
                ChipMenu(selection: $branch, options: (branches.isEmpty ? [repo.branch] : branches.map(\.name)).map {
                    ChipOption(value: $0, title: $0, symbol: "arrow.triangle.branch")
                }, label: "Ramo:")
                HelpTip(lessonID: "branch")
                Spacer()
                if let commits { Text("Mostrando \(Phrases.plural(commits.count, "versão", "versões"))").font(.system(size: 12)).foregroundStyle(.secondary) }
            }

            if empty {
                EmptyState(symbol: "clock", title: "Sem histórico ainda", message: "Este repositório ainda não tem commits.")
            } else if let commits {
                Card(padding: 18) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(commits.enumerated()), id: \.element.id) { i, commit in
                            CommitRow(commit: commit, isFirst: i == 0, isLast: i == commits.count - 1 && !hasMore)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = commit }
                        }
                        if hasMore {
                            Button { Task { await load(more: true) } } label: { Label("Carregar mais antigos", systemImage: "arrow.down.circle") }
                                .buttonStyle(ActionButtonStyle(tint: .indigo))
                                .padding(.leading, 34).padding(.top, 6)
                        }
                    }
                }
            } else {
                LoadingRow(text: "Lendo o histórico…")
            }
        }
        .task {
            branch = repo.branch
            if let client = model.client { branches = (try? await client.branches(repo.fullName)) ?? [] }
        }
        .task(id: branch) { if !branch.isEmpty { await load(more: false) } }
        .sheet(item: $selected) { CommitSheet(repo: repo, commit: $0) }
    }

    private func load(more: Bool) async {
        guard let client = model.client else { return }
        if !more { commits = nil; page = 1; empty = false }
        do {
            let next = try await client.commits(repo.fullName, branch: branch, page: more ? page + 1 : 1)
            if more { page += 1; commits = (commits ?? []) + next } else { commits = next }
            hasMore = next.count == 40
        } catch GitHubError.invalid(_) {
            empty = true
        } catch GitHubError.notFound {
            empty = true
        } catch {
            model.report(error)
        }
    }
}

/// Um commit desenhado como ponto numa linha do tempo.
private struct CommitRow: View {
    let commit: GHCommit
    let isFirst: Bool
    let isLast: Bool
    @ViewState private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? .clear : Color.indigo.opacity(0.3)).frame(width: 2, height: 10)
                Circle()
                    .fill(isFirst ? AnyShapeStyle(Color.indigo.gradient) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                    .overlay(Circle().strokeBorder(Color.indigo, lineWidth: 2.5))
                    .frame(width: 16, height: 16)
                Rectangle().fill(isLast ? .clear : Color.indigo.opacity(0.3)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(commit.title).font(.system(size: 13.5, weight: .medium)).lineLimit(2)
                    if isFirst { Pill(text: "Mais recente", tint: .indigo) }
                }
                HStack(spacing: 8) {
                    Avatar(url: commit.author?.avatarUrl, size: 18)
                    Text(commit.authorName).font(.system(size: 11.5, weight: .medium))
                    Text("·").foregroundStyle(.tertiary)
                    Text(Phrases.relative(commit.date)).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Text(commit.shortSHA)
                        .font(.system(size: 10.5, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .help("Código único desta versão")
                }
            }
            .padding(.vertical, 8)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).padding(.top, 14)
        }
        .padding(.horizontal, 6)
        .background(hovering ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// O que mudou num commit: arquivos com barras de linhas adicionadas/removidas e o texto da diferença.
struct CommitSheet: View {
    /// Resumo em português a partir dos arquivos que o GitHub informa.
    static func explain(_ files: [GHCommit.File]) -> [String] {
        let changes = files.map { f -> FileChange in
            let kind: FileChange.Kind = switch f.status {
            case "added": .added
            case "removed": .deleted
            case "renamed": .renamed
            default: .modified
            }
            return FileChange(path: f.filename, kind: kind)
        }
        var stats: ChangeExplainer.Stats = [:]
        for f in files { stats[f.filename] = (f.additions, f.deletions) }
        return ChangeExplainer.summary(changes, stats: stats)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: GHRepo
    let commit: GHCommit
    @ViewState private var detail: GHCommit?
    @ViewState private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: "camera.fill", tint: .indigo, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(commit.title).font(.system(size: 17, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("\(commit.authorName) · \(Phrases.relative(commit.date)) · \(commit.shortSHA)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            if !commit.details.isEmpty {
                Text(commit.details).font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 12)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let detail, let stats = detail.stats, let files = detail.files {
                        HStack(spacing: 18) {
                            Label(Phrases.plural(files.count, "arquivo mudou", "arquivos mudaram"), systemImage: "doc.on.doc").font(.system(size: 13, weight: .medium))
                            Label("\(stats.additions) linhas novas", systemImage: "plus.circle.fill").foregroundStyle(Theme.open).font(.system(size: 13))
                            Label("\(stats.deletions) removidas", systemImage: "minus.circle.fill").foregroundStyle(Theme.danger).font(.system(size: 13))
                        }
                        ExplainBox(lines: Self.explain(files))
                        ForEach(files) { f in
                            VStack(alignment: .leading, spacing: 0) {
                                Button {
                                    if expanded.contains(f.filename) { expanded.remove(f.filename) } else { expanded.insert(f.filename) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: expanded.contains(f.filename) ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).frame(width: 12)
                                        Pill(text: statusName(f.status), tint: statusTint(f.status))
                                        Text(f.filename).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                        Spacer()
                                        ChangeBar(additions: f.additions, deletions: f.deletions)
                                    }
                                    .padding(10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if expanded.contains(f.filename) {
                                    if let patch = f.patch { DiffText(patch: patch) } else {
                                        Text("Sem texto para mostrar (arquivo binário ou grande).").font(.system(size: 12)).foregroundStyle(.secondary).padding(10)
                                    }
                                }
                            }
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                        }
                    } else {
                        LoadingRow(text: "Comparando com a versão anterior…")
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text("Clique num arquivo para ver as linhas: verde entrou, vermelho saiu.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                if let url = commit.htmlUrl {
                    Button { NSWorkspace.shared.open(url) } label: { Label("Abrir no GitHub", systemImage: "safari") }.buttonStyle(ActionButtonStyle())
                }
            }
            .padding(14)
        }
        .frame(width: 760, height: 620)
        .task {
            guard let client = model.client else { return }
            do { detail = try await client.commit(repo.fullName, sha: commit.sha) } catch { model.report(error) }
        }
    }

    private func statusName(_ s: String) -> String {
        switch s {
        case "added": "Novo"
        case "removed": "Apagado"
        case "renamed": "Renomeado"
        case "modified", "changed": "Alterado"
        default: s
        }
    }

    private func statusTint(_ s: String) -> Color {
        switch s {
        case "added": Theme.open
        case "removed": Theme.danger
        case "renamed": .blue
        default: .orange
        }
    }
}

/// Cinco quadradinhos verde/vermelho proporcionais às linhas mudadas.
struct ChangeBar: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        let total = max(additions + deletions, 1)
        let green = Int((Double(additions) / Double(total) * 5).rounded())
        HStack(spacing: 6) {
            Text("+\(additions)").foregroundStyle(Theme.open)
            Text("−\(deletions)").foregroundStyle(Theme.danger)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(additions + deletions == 0 ? Color.primary.opacity(0.1) : i < green ? Theme.open : Theme.danger)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        .accessibilityLabel("\(additions) linhas adicionadas, \(deletions) removidas")
    }
}

/// Texto de diferença colorido.
struct DiffText: View {
    let patch: String

    var body: some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(patch.components(separatedBy: "\n").prefix(1500).enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 11.5, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line))
                        .foregroundStyle(line.hasPrefix("@@") ? Color.blue : Color.primary)
                }
            }
            .textSelection(.enabled)
        }
        .padding(.vertical, 6)
    }

    private func background(_ line: String) -> Color {
        if line.hasPrefix("+") { return Theme.open.opacity(0.14) }
        if line.hasPrefix("-") { return Theme.danger.opacity(0.12) }
        if line.hasPrefix("@@") { return Color.blue.opacity(0.06) }
        return .clear
    }
}

// MARK: - Ramos

struct BranchesTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var branches: [GHBranch]?
    @ViewState private var showNew = false
    @ViewState private var deleting: GHBranch?
    @ViewState private var pullFrom: GHBranch?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "branch")
            HStack {
                Text("O ramo principal é o tronco. Os outros saem dele e podem voltar com um pedido de mudança.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Button { showNew = true } label: { Label("Novo ramo", systemImage: "plus") }
                    .buttonStyle(ActionButtonStyle(tint: .teal, prominent: true))
                    .disabled(branches == nil)
            }

            if let branches {
                let main = branches.first { $0.name == repo.branch }
                let others = branches.filter { $0.name != repo.branch }
                if let main {
                    Card(padding: 16) {
                        HStack(spacing: 14) {
                            IconTile(symbol: "tree.fill", tint: .teal, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(main.name).font(.system(size: 15, weight: .bold))
                                    Pill(text: "Principal (tronco)", tint: .teal)
                                    if main.protected == true { Pill(text: "Protegido", symbol: "lock.shield.fill", tint: .orange) }
                                }
                                Text("A versão oficial do projeto. É o que aparece no GitHub e o que outras pessoas baixam.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                if others.isEmpty {
                    EmptyState(symbol: "arrow.triangle.branch", title: "Só existe o tronco",
                               message: "Crie um ramo para experimentar algo novo sem mexer na versão principal.", tint: .teal)
                } else {
                    VStack(spacing: 0) {
                        ForEach(others) { b in
                            BranchRow(repo: repo, branch: b, onDelete: { deleting = b }, onPull: { pullFrom = b })
                        }
                    }
                    .padding(.leading, 26)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.teal.opacity(0.35)).frame(width: 3).padding(.leading, 6).padding(.vertical, 10)
                    }
                }
            } else {
                LoadingRow(text: "Lendo os ramos…")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showNew) {
            NewBranchSheet(repo: repo, branches: branches ?? []) { Task { await load() } }
        }
        .sheet(item: $pullFrom) { b in
            NewPullSheet(repo: repo, branches: branches ?? [], head: b.name) {}
        }
        .confirmationDialog("Apagar o ramo “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Apagar ramo", role: .destructive) {
                guard let b = deleting else { return }
                Task {
                    guard let client = model.client else { return }
                    do {
                        try await client.deleteBranch(repo.fullName, name: b.name)
                        model.show("trash.fill", "Ramo “\(b.name)” apagado")
                        await load()
                    } catch { model.report(error) }
                }
            }
        } message: {
            Text("Commits que ainda não foram juntados no principal deixam de aparecer. O ramo principal não é afetado.")
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do { branches = try await client.branches(repo.fullName) } catch { model.report(error); branches = [] }
    }
}

private struct BranchRow: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    let branch: GHBranch
    let onDelete: () -> Void
    let onPull: () -> Void
    @ViewState private var compare: GHCompare?

    var body: some View {
        HStack(spacing: 12) {
            // Galho saindo do tronco.
            Path { p in
                p.move(to: CGPoint(x: -20, y: 0))
                p.addQuadCurve(to: CGPoint(x: 6, y: 22), control: CGPoint(x: -16, y: 22))
            }
            .stroke(Color.teal.opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 6, height: 22)
            Card(padding: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(branch.name).font(.system(size: 13.5, weight: .semibold))
                        if let compare {
                            HStack(spacing: 10) {
                                aheadBehind(compare.aheadBy, "à frente", "arrow.up", Theme.open)
                                aheadBehind(compare.behindBy, "atrás", "arrow.down", .orange)
                                Text("em relação a \(repo.branch)").font(.system(size: 11)).foregroundStyle(.tertiary)
                            }
                        } else {
                            Text("Comparando…").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if (compare?.aheadBy ?? 0) > 0 {
                        Button { onPull() } label: { Label("Pedir para juntar", systemImage: "arrow.triangle.pull") }
                            .buttonStyle(ActionButtonStyle(tint: Theme.closed))
                            .help("Criar um pedido de mudança (pull request) para levar estes commits ao \(repo.branch)")
                    }
                    Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                        .buttonStyle(ActionButtonStyle(tint: Theme.danger))
                        .help("Apagar este ramo")
                        .accessibilityLabel("Apagar o ramo \(branch.name)")
                }
            }
        }
        .padding(.vertical, 5)
        .task {
            guard let client = model.client else { return }
            compare = try? await client.compare(repo.fullName, base: repo.branch, head: branch.name)
        }
    }

    private func aheadBehind(_ n: Int, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        Label("\(n) \(label)", systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(n > 0 ? tint : .secondary)
            .help(n == 1 ? "1 commit \(label)" : "\(n) commits \(label)")
    }
}

private struct NewBranchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: GHRepo
    let branches: [GHBranch]
    let onDone: () -> Void
    @ViewState private var name = ""
    @ViewState private var from = ""
    @ViewState private var busy = false

    private var clean: String { name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.triangle.branch", tint: .teal, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Novo ramo").font(.system(size: 20, weight: .bold))
                    Text("Um caminho paralelo para experimentar.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            LabeledField(label: "Nome do ramo", text: $name, prompt: "ex.: nova-tela-inicial", help: "Sem espaços. Dica: descreva o que vai fazer.")
            Picker("Começar a partir de", selection: $from) {
                ForEach(branches) { Text($0.name).tag($0.name) }
            }
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        guard let client = model.client, let sha = branches.first(where: { $0.name == from })?.commit.sha else { return }
                        busy = true
                        defer { busy = false }
                        do {
                            try await client.createBranch(repo.fullName, name: clean, fromSHA: sha)
                            model.show("arrow.triangle.branch", "Ramo “\(clean)” criado")
                            onDone()
                            dismiss()
                        } catch { model.report(error) }
                    }
                } label: { if busy { ProgressView().controlSize(.small) } else { Text("Criar ramo") } }
                .buttonStyle(ActionButtonStyle(tint: .teal, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(clean.isEmpty || from.isEmpty || busy)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { from = repo.branch }
    }
}

// MARK: - Tarefas (Issues)

struct IssuesTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var showOpen = true
    @ViewState private var issues: [GHIssue]?
    @ViewState private var selected: GHIssue?
    @ViewState private var showNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "issue")
            if repo.hasIssues == false {
                EmptyState(symbol: "smallcircle.filled.circle", title: "Tarefas desligadas",
                           message: "Este repositório não usa Issues. Ligue em Ajustes, se quiser usar.")
            } else {
                HStack {
                    FilterChips(selection: $showOpen, options: [
                        ChipOption(value: true, title: "Abertas", symbol: "circle.circle"),
                        ChipOption(value: false, title: "Concluídas", symbol: "checkmark.circle.fill")
                    ], tint: Theme.open)
                    Spacer()
                    Button { showNew = true } label: { Label("Nova tarefa", systemImage: "plus") }
                        .buttonStyle(ActionButtonStyle(tint: Theme.open, prominent: true))
                }
                if let issues {
                    if issues.isEmpty {
                        EmptyState(symbol: showOpen ? "checkmark.seal" : "tray", title: showOpen ? "Nenhuma tarefa aberta" : "Nenhuma tarefa concluída",
                                   message: showOpen ? "Tudo em dia! Crie uma tarefa para anotar um problema ou ideia." : "Quando você concluir tarefas, elas aparecem aqui.",
                                   tint: Theme.open)
                    } else {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(issues.enumerated()), id: \.element.id) { i, issue in
                                    Button { selected = issue } label: { IssueRow(issue: issue) }.buttonStyle(.plain)
                                    if i < issues.count - 1 { Divider().padding(.leading, 52) }
                                }
                            }
                        }
                    }
                } else {
                    LoadingRow(text: "Lendo as tarefas…")
                }
            }
        }
        .task(id: showOpen) { await load() }
        .sheet(item: $selected) { issue in
            ConversationSheet(repo: repo, item: .issue(issue)) { Task { await load() } }
        }
        .sheet(isPresented: $showNew) {
            NewIssueSheet(repo: repo) { Task { showOpen = true; await load() } }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        issues = nil
        do { issues = try await client.issues(repo.fullName, open: showOpen) } catch { model.report(error); issues = [] }
    }
}

private struct IssueRow: View {
    let issue: GHIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: issue.isOpen ? "circle.circle" : "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(issue.isOpen ? Theme.open : Theme.closed)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title).font(.system(size: 13.5, weight: .medium)).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text("#\(issue.number)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Text("aberta \(Phrases.relative(issue.createdAt)) por \(issue.user?.login ?? "alguém")").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(issue.labels, id: \.name) { label in
                        Pill(text: label.name, tint: Color(hex: label.color ?? "8E8E93"))
                    }
                }
            }
            Spacer()
            if issue.comments > 0 {
                Label("\(issue.comments)", systemImage: "text.bubble").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct NewIssueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: GHRepo
    let onDone: () -> Void
    @ViewState private var title = ""
    @ViewState private var body_ = ""
    @ViewState private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "smallcircle.filled.circle", tint: Theme.open, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nova tarefa").font(.system(size: 20, weight: .bold))
                    Text("Anote um problema, uma ideia ou algo a fazer.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            LabeledField(label: "Título", text: $title, prompt: "ex.: Botão de salvar não funciona")
            LabeledEditor(label: "Detalhes (opcional)", text: $body_, height: 140)
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        guard let client = model.client else { return }
                        busy = true
                        defer { busy = false }
                        do {
                            let issue = try await client.createIssue(repo.fullName, title: title, body: body_)
                            model.show("checkmark.circle.fill", "Tarefa #\(issue.number) criada")
                            onDone()
                            dismiss()
                        } catch { model.report(error) }
                    }
                } label: { if busy { ProgressView().controlSize(.small) } else { Text("Criar tarefa") } }
                .buttonStyle(ActionButtonStyle(tint: Theme.open, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

/// Conversa de uma tarefa ou de um pedido de mudança: texto, comentários e ações.
struct ConversationSheet: View {
    enum Item: Identifiable {
        case issue(GHIssue)
        case pull(GHPull)
        var id: Int { switch self { case .issue(let i): i.number; case .pull(let p): p.number } }
        var number: Int { id }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: GHRepo
    let item: Item
    let onChange: () -> Void
    @ViewState private var comments: [GHComment]?
    @ViewState private var newComment = ""
    @ViewState private var pull: GHPull?
    @ViewState private var mergeMethod = "merge"
    @ViewState private var confirmMerge = false
    @ViewState private var busy = false

    private var title: String { switch item { case .issue(let i): i.title; case .pull(let p): p.title } }
    private var body_: String? { switch item { case .issue(let i): i.body; case .pull(let p): (pull ?? p).body } }
    private var author: GHOwner? { switch item { case .issue(let i): i.user; case .pull(let p): p.user } }
    private var created: Date { switch item { case .issue(let i): i.createdAt; case .pull(let p): p.createdAt } }
    private var isOpen: Bool { switch item { case .issue(let i): i.isOpen; case .pull(let p): (pull ?? p).isOpen } }
    private var url: URL { switch item { case .issue(let i): i.htmlUrl; case .pull(let p): p.htmlUrl } }
    private var isPull: Bool { if case .pull = item { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: isPull ? "arrow.triangle.pull" : "smallcircle.filled.circle", tint: isPull ? Theme.closed : Theme.open, size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        stateBadge
                        Text("#\(item.number) · \(author?.login ?? "alguém") · \(Phrases.relative(created))").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Fechar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if case .pull(let p) = item { pullSummary(pull ?? p) }
                    bubble(author: author, date: created, text: body_?.isEmpty == false ? body_! : "_Sem descrição._")
                    if let comments {
                        ForEach(comments) { c in bubble(author: c.user, date: c.createdAt, text: c.body ?? "") }
                    } else {
                        LoadingRow(text: "Lendo os comentários…")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledEditor(label: "Escrever um comentário", text: $newComment, height: 80)
                        HStack {
                            Spacer()
                            Button { Task { await comment() } } label: { Label("Comentar", systemImage: "text.bubble.fill") }
                                .buttonStyle(ActionButtonStyle(prominent: true))
                                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack(spacing: 8) {
                Button { NSWorkspace.shared.open(url) } label: { Label("Abrir no GitHub", systemImage: "safari") }
                    .buttonStyle(ActionButtonStyle(tint: .secondary))
                Spacer()
                if !(pull?.isMerged ?? false) {
                    Button { Task { await setOpen(!isOpen) } } label: {
                        Label(isOpen ? (isPull ? "Fechar sem juntar" : "Marcar como concluída") : "Reabrir",
                              systemImage: isOpen ? "checkmark.circle" : "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(ActionButtonStyle(tint: isPull ? Theme.danger : Theme.closed))
                    .disabled(busy)
                }
                if isPull, let p = pull, p.isOpen {
                    Picker("", selection: $mergeMethod) {
                        Text("Juntar tudo (merge)").tag("merge")
                        Text("Juntar em um commit (squash)").tag("squash")
                        Text("Reaplicar (rebase)").tag("rebase")
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .help("Como os commits entram no ramo principal. Na dúvida, use “Juntar tudo”.")
                    Button { confirmMerge = true } label: { Label("Juntar no \(p.base.ref)", systemImage: "arrow.triangle.merge") }
                        .buttonStyle(ActionButtonStyle(tint: Theme.closed, prominent: true))
                        .disabled(busy || p.mergeable == false || p.draft == true)
                }
            }
            .padding(14)
        }
        .frame(width: 720, height: 640)
        .task { await load() }
        .confirmationDialog("Juntar este pedido no ramo \(pull?.base.ref ?? "")?", isPresented: $confirmMerge) {
            Button("Juntar") { Task { await merge() } }
        } message: {
            Text("As mudanças do ramo \(pull?.head.ref ?? "") vão entrar no \(pull?.base.ref ?? ""). Dá para desfazer depois, mas dá trabalho.")
        }
    }

    @ViewBuilder private var stateBadge: some View {
        if pull?.isMerged == true {
            Pill(text: "Juntado", symbol: "arrow.triangle.merge", tint: Theme.closed)
        } else if isOpen {
            Pill(text: "Aberto", symbol: "circle", tint: Theme.open)
        } else {
            Pill(text: isPull ? "Fechado" : "Concluída", symbol: "checkmark", tint: isPull ? Theme.danger : Theme.closed)
        }
    }

    private func pullSummary(_ p: GHPull) -> some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    branchChip(p.head.ref, .teal)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.closed)
                    branchChip(p.base.ref, Theme.accent)
                    HelpTip(lessonID: "pullRequest")
                    Spacer()
                }
                Text("Levar as mudanças do ramo “\(p.head.ref)” para o “\(p.base.ref)”.").font(.system(size: 12)).foregroundStyle(.secondary)
                if let files = p.changedFiles {
                    HStack(spacing: 16) {
                        Label(Phrases.plural(p.commits ?? 0, "commit", "commits"), systemImage: "camera")
                        Label(Phrases.plural(files, "arquivo", "arquivos"), systemImage: "doc.on.doc")
                        ChangeBar(additions: p.additions ?? 0, deletions: p.deletions ?? 0)
                    }
                    .font(.system(size: 12))
                    if p.isOpen {
                        if p.mergeable == false {
                            Label("Há conflitos: as mesmas linhas mudaram nos dois ramos. Resolva no site do GitHub.", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12)).foregroundStyle(.orange)
                        } else if p.mergeable == true {
                            Label("Sem conflitos — pode juntar.", systemImage: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Theme.open)
                        }
                        if p.draft == true {
                            Label("É um rascunho: marque como pronto no GitHub antes de juntar.", systemImage: "pencil.circle").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func branchChip(_ name: String, _ tint: Color) -> some View {
        Label(name, systemImage: "arrow.triangle.branch")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    private func bubble(author: GHOwner?, date: Date, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(url: author?.avatarUrl, size: 30)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(author?.login ?? "alguém").font(.system(size: 12, weight: .semibold))
                    Text(Phrases.relative(date)).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                MarkdownView(text: text)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        async let c = client.comments(repo.fullName, number: item.number)
        if isPull { pull = try? await client.pull(repo.fullName, number: item.number) }
        comments = (try? await c) ?? []
    }

    private func comment() async {
        guard let client = model.client else { return }
        busy = true
        defer { busy = false }
        do {
            let c = try await client.addComment(repo.fullName, number: item.number, body: newComment)
            comments = (comments ?? []) + [c]
            newComment = ""
        } catch { model.report(error) }
    }

    private func setOpen(_ open: Bool) async {
        guard let client = model.client else { return }
        busy = true
        defer { busy = false }
        do {
            if isPull {
                pull = try await client.setPull(repo.fullName, number: item.number, open: open)
            } else {
                _ = try await client.setIssue(repo.fullName, number: item.number, open: open)
            }
            model.show("checkmark.circle.fill", open ? "Reaberto" : (isPull ? "Pedido fechado" : "Tarefa concluída"))
            onChange()
            dismiss()
        } catch { model.report(error) }
    }

    private func merge() async {
        guard let client = model.client else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await client.mergePull(repo.fullName, number: item.number, method: mergeMethod)
            model.show("arrow.triangle.merge", "Mudanças juntadas no \(pull?.base.ref ?? "ramo principal")")
            onChange()
            dismiss()
        } catch { model.report(error) }
    }
}

// MARK: - Pedidos de mudança (Pull requests)

struct PullsTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var showOpen = true
    @ViewState private var pulls: [GHPull]?
    @ViewState private var selected: GHPull?
    @ViewState private var showNew = false
    @ViewState private var branches: [GHBranch] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "pullRequest")
            HStack {
                FilterChips(selection: $showOpen, options: [
                    ChipOption(value: true, title: "Abertos", symbol: "arrow.triangle.pull"),
                    ChipOption(value: false, title: "Fechados e juntados", symbol: "arrow.triangle.merge")
                ], tint: Theme.closed)
                Spacer()
                Button { showNew = true } label: { Label("Novo pedido", systemImage: "plus") }
                    .buttonStyle(ActionButtonStyle(tint: Theme.closed, prominent: true))
                    .disabled(branches.count < 2)
                    .help(branches.count < 2 ? "Crie um ramo primeiro: o pedido leva as mudanças de um ramo para outro." : "Criar um pedido de mudança")
            }
            if let pulls {
                if pulls.isEmpty {
                    EmptyState(symbol: "arrow.triangle.pull", title: showOpen ? "Nenhum pedido aberto" : "Nenhum pedido fechado",
                               message: "Um pedido de mudança aparece quando alguém quer juntar um ramo no principal.", tint: Theme.closed)
                } else {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(pulls.enumerated()), id: \.element.id) { i, pull in
                                Button { selected = pull } label: { PullRow(pull: pull) }.buttonStyle(.plain)
                                if i < pulls.count - 1 { Divider().padding(.leading, 52) }
                            }
                        }
                    }
                }
            } else {
                LoadingRow(text: "Lendo os pedidos…")
            }
        }
        .task(id: showOpen) { await load() }
        .task { if let client = model.client { branches = (try? await client.branches(repo.fullName)) ?? [] } }
        .sheet(item: $selected) { pull in
            ConversationSheet(repo: repo, item: .pull(pull)) { Task { await load() } }
        }
        .sheet(isPresented: $showNew) {
            NewPullSheet(repo: repo, branches: branches, head: branches.first { $0.name != repo.branch }?.name ?? "") {
                Task { showOpen = true; await load() }
            }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        pulls = nil
        do { pulls = try await client.pulls(repo.fullName, open: showOpen) } catch { model.report(error); pulls = [] }
    }
}

private struct PullRow: View {
    let pull: GHPull

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: pull.isMerged ? "arrow.triangle.merge" : "arrow.triangle.pull")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(pull.isMerged ? Theme.closed : pull.isOpen ? Theme.open : Theme.danger)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(pull.title).font(.system(size: 13.5, weight: .medium)).multilineTextAlignment(.leading)
                    if pull.draft == true { Pill(text: "Rascunho", tint: .gray) }
                }
                HStack(spacing: 6) {
                    Text("#\(pull.number)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    Text("\(pull.head.ref) → \(pull.base.ref)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.teal)
                    Text("· \(pull.user?.login ?? "") · \(Phrases.relative(pull.createdAt))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct NewPullSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: GHRepo
    let branches: [GHBranch]
    @ViewState var head: String
    let onDone: () -> Void
    @ViewState private var base = ""
    @ViewState private var title = ""
    @ViewState private var body_ = ""
    @ViewState private var busy = false

    init(repo: GHRepo, branches: [GHBranch], head: String, onDone: @escaping () -> Void) {
        self.repo = repo
        self.branches = branches
        self._head = ViewState(initialValue: head)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.triangle.pull", tint: Theme.closed, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Novo pedido de mudança").font(.system(size: 20, weight: .bold))
                    Text("Proponha levar as mudanças de um ramo para outro.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Levar de").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Picker("", selection: $head) { ForEach(branches) { Text($0.name).tag($0.name) } }.labelsHidden()
                }
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.closed).padding(.top, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Para").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Picker("", selection: $base) { ForEach(branches) { Text($0.name).tag($0.name) } }.labelsHidden()
                }
            }
            .padding(14)
            .background(Theme.closed.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.corner))
            LabeledField(label: "Título", text: $title, prompt: "O que este pedido muda")
            LabeledEditor(label: "Descrição (opcional)", text: $body_, height: 110)
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        guard let client = model.client else { return }
                        busy = true
                        defer { busy = false }
                        do {
                            let p = try await client.createPull(repo.fullName, title: title, head: head, base: base, body: body_)
                            model.show("arrow.triangle.pull", "Pedido #\(p.number) criado")
                            onDone()
                            dismiss()
                        } catch { model.report(error) }
                    }
                } label: { if busy { ProgressView().controlSize(.small) } else { Text("Criar pedido") } }
                .buttonStyle(ActionButtonStyle(tint: Theme.closed, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || head.isEmpty || base.isEmpty || head == base || busy)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            base = repo.branch
            if title.isEmpty { title = head.replacingOccurrences(of: "-", with: " ").capitalized }
        }
    }
}

// MARK: - Automações (Actions)

struct ActionsTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var runs: [GHRun]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "actions")
            if let runs {
                if runs.isEmpty {
                    EmptyState(symbol: "gearshape.2", title: "Nenhuma automação aqui",
                               message: "Este repositório não tem Actions configuradas. Elas ficam na pasta .github/workflows do projeto.", tint: .orange)
                } else {
                    HStack(spacing: 14) {
                        summary(runs.filter { $0.outcome == .success }.count, "deram certo", "checkmark.circle.fill", Theme.open)
                        summary(runs.filter { $0.outcome == .failure }.count, "falharam", "xmark.circle.fill", Theme.danger)
                        summary(runs.filter { $0.outcome == .running }.count, "rodando", "clock.fill", .orange)
                        Spacer()
                        Button { Task { await load() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                            .buttonStyle(ActionButtonStyle(tint: .orange))
                    }
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(runs.enumerated()), id: \.element.id) { i, run in
                                RunRow(run: run) { Task { await rerun(run) } }
                                if i < runs.count - 1 { Divider().padding(.leading, 52) }
                            }
                        }
                    }
                }
            } else {
                LoadingRow(text: "Lendo as automações…")
            }
        }
        .task { await load() }
    }

    private func summary(_ n: Int, _ label: String, _ symbol: String, _ tint: Color) -> some View {
        Label("\(n) \(label)", systemImage: symbol)
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.1), in: Capsule())
            .foregroundStyle(tint)
    }

    private func load() async {
        guard let client = model.client else { return }
        do { runs = try await client.runs(repo.fullName).workflowRuns } catch { runs = [] }
    }

    private func rerun(_ run: GHRun) async {
        guard let client = model.client else { return }
        do {
            try await client.rerun(repo.fullName, runID: run.id)
            model.show("arrow.clockwise", "Automação reiniciada")
            await load()
        } catch { model.report(error) }
    }
}

private struct RunRow: View {
    let run: GHRun
    let onRerun: () -> Void

    private var look: (String, Color, String) {
        switch run.outcome {
        case .running: ("clock.fill", .orange, "Rodando")
        case .success: ("checkmark.circle.fill", Theme.open, "Deu certo")
        case .failure: ("xmark.circle.fill", Theme.danger, "Falhou")
        case .cancelled: ("stop.circle.fill", .gray, "Cancelada")
        case .skipped: ("forward.circle.fill", .gray, "Pulada")
        case .other: ("questionmark.circle.fill", .gray, "Terminada")
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: look.0).font(.system(size: 20)).foregroundStyle(look.1).frame(width: 24)
                .symbolEffect(.pulse, isActive: run.outcome == .running)
            VStack(alignment: .leading, spacing: 4) {
                Text(run.displayTitle ?? run.name ?? "Automação").font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Pill(text: look.2, tint: look.1)
                    Text(run.name ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                    if let b = run.headBranch { Text("· \(b)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.teal) }
                    Text("· \(Phrases.relative(run.createdAt))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if run.outcome == .failure || run.outcome == .cancelled {
                Button { onRerun() } label: { Label("Rodar de novo", systemImage: "arrow.clockwise") }
                    .buttonStyle(ActionButtonStyle(tint: .orange))
            }
            Button { NSWorkspace.shared.open(run.htmlUrl) } label: { Label("Detalhes", systemImage: "safari") }
                .buttonStyle(ActionButtonStyle(tint: .secondary))
                .help("Ver o passo a passo e os registros no GitHub")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Versões (Releases)

struct ReleasesTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var releases: [GHRelease]?
    @ViewState private var showNew = false
    @ViewState private var deleting: GHRelease?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "release")
            HStack {
                Spacer()
                Button { showNew = true } label: { Label("Publicar versão", systemImage: "plus") }
                    .buttonStyle(ActionButtonStyle(tint: .pink, prominent: true))
            }
            if let releases {
                if releases.isEmpty {
                    EmptyState(symbol: "tag", title: "Nenhuma versão publicada",
                               message: "Publique uma versão (ex.: 1.0) para marcar um momento importante do projeto.", tint: .pink)
                } else {
                    ForEach(Array(releases.enumerated()), id: \.element.id) { i, r in
                        Card(padding: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    IconTile(symbol: "tag.fill", tint: .pink, size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(r.displayName).font(.system(size: 15, weight: .bold))
                                            if i == 0 && !r.prerelease && !r.draft { Pill(text: "Mais recente", tint: Theme.open) }
                                            if r.prerelease { Pill(text: "Pré-versão", tint: .orange) }
                                            if r.draft { Pill(text: "Rascunho", tint: .gray) }
                                        }
                                        Text("\(r.tagName) · \(Phrases.date(r.publishedAt ?? r.createdAt))").font(.system(size: 11.5)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button { NSWorkspace.shared.open(r.htmlUrl) } label: { Image(systemName: "safari") }
                                        .buttonStyle(ActionButtonStyle(tint: .secondary)).help("Abrir no GitHub")
                                    Button { deleting = r } label: { Image(systemName: "trash") }
                                        .buttonStyle(ActionButtonStyle(tint: Theme.danger)).help("Apagar esta versão")
                                }
                                if let body = r.body, !body.isEmpty { MarkdownView(text: body) }
                                if !r.assets.isEmpty {
                                    ForEach(r.assets) { a in
                                        HStack {
                                            Image(systemName: "shippingbox").foregroundStyle(.secondary)
                                            Text(a.name).font(.system(size: 12, weight: .medium))
                                            Text("\(Phrases.size(bytes: a.size)) · \(Phrases.plural(a.downloadCount, "download", "downloads"))").font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                LoadingRow(text: "Lendo as versões…")
            }
        }
        .task { await load() }
        .sheet(isPresented: $showNew) { NewReleaseSheet(repo: repo) { Task { await load() } } }
        .confirmationDialog("Apagar a versão “\(deleting?.displayName ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Apagar versão", role: .destructive) {
                guard let r = deleting, let client = model.client else { return }
                Task {
                    do {
                        try await client.deleteRelease(repo.fullName, id: r.id)
                        model.show("trash.fill", "Versão apagada")
                        await load()
                    } catch { model.report(error) }
                }
            }
        } message: { Text("A etiqueta (tag) continua existindo; só a publicação é apagada.") }
    }

    private func load() async {
        guard let client = model.client else { return }
        do { releases = try await client.releases(repo.fullName) } catch { model.report(error); releases = [] }
    }
}

private struct NewReleaseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let repo: GHRepo
    let onDone: () -> Void
    @ViewState private var tag = "v1.0.0"
    @ViewState private var name = ""
    @ViewState private var notes = ""
    @ViewState private var prerelease = false
    @ViewState private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                IconTile(symbol: "tag.fill", tint: .pink, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Publicar versão").font(.system(size: 20, weight: .bold))
                    Text("Marca o estado atual do ramo \(repo.branch) com um nome.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            LabeledField(label: "Etiqueta (tag)", text: $tag, prompt: "v1.0.0", help: "Costuma ser o número da versão, como v1.0.0 ou v2.3.")
            LabeledField(label: "Nome (opcional)", text: $name, prompt: "Primeira versão")
            LabeledEditor(label: "O que mudou", text: $notes, height: 120)
            Toggle("É uma pré-versão (ainda em teste)", isOn: $prerelease).toggleStyle(.checkbox).font(.system(size: 13))
            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        guard let client = model.client else { return }
                        busy = true
                        defer { busy = false }
                        do {
                            _ = try await client.createRelease(repo.fullName, tag: tag, name: name.isEmpty ? tag : name, notes: notes, target: repo.branch, prerelease: prerelease)
                            model.show("tag.fill", "Versão \(tag) publicada")
                            onDone()
                            dismiss()
                        } catch { model.report(error) }
                    }
                } label: { if busy { ProgressView().controlSize(.small) } else { Text("Publicar") } }
                .buttonStyle(ActionButtonStyle(tint: .pink, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(tag.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
