import AppKit
import GitArborCore
import SwiftUI

/// Busca rápida (⌘K): acha repositórios, projetos do Mac, tarefas, pedidos, lições e ações.
struct QuickSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var text = ""
    @ViewState private var highlighted = 0
    @ViewState private var remote: [GHIssueSearchItem] = []
    @ViewState private var searchingRemote = false
    @FocusState private var focused: Bool

    struct Item: Identifiable {
        let id: String
        let group: String
        let title: String
        let detail: String
        let symbol: String
        let tint: Color
        let action: () -> Void
    }

    private var items: [Item] {
        let query = Self.fold(text.trimmingCharacters(in: .whitespaces))
        func matches(_ fields: String...) -> Bool {
            query.isEmpty || fields.contains { Self.fold($0).contains(query) }
        }
        var list: [Item] = []

        for section in AppSection.allCases where matches(section.title, section.subtitle) {
            list.append(Item(id: "s-" + section.rawValue, group: "Ir para", title: section.title, detail: section.subtitle,
                             symbol: section.symbol, tint: section.tint) {
                model.section = section
                if section == .repos { model.repoPath = [] }
            })
        }

        let repos = model.repos.filter { matches($0.name, $0.description ?? "", $0.language ?? "") }
            .sorted { ($0.pushedAt ?? .distantPast) > ($1.pushedAt ?? .distantPast) }
        for repo in repos.prefix(query.isEmpty ? 5 : 12) {
            list.append(Item(id: "r-\(repo.id)", group: "Repositórios", title: repo.name,
                             detail: repo.description?.nilIfBlank ?? (repo.isPrivate ? "Privado" : "Público"),
                             symbol: "shippingbox.fill", tint: Color.language(repo.language)) { model.open(repo) })
        }

        let locals = model.localRepos.filter { matches($0.name, $0.branch ?? "") }
            .sorted { ($0.state == .clean ? 1 : 0) < ($1.state == .clean ? 1 : 0) }
        for repo in locals.prefix(query.isEmpty ? 4 : 10) {
            list.append(Item(id: "l-\(repo.folder.path)", group: "Projetos no Mac", title: repo.name,
                             detail: LocalStateBadge.title(repo.state) + (repo.branch.map { " · \($0)" } ?? ""),
                             symbol: LocalStateBadge.symbol(repo.state), tint: LocalStateBadge.tint(repo.state)) {
                model.section = .local
                let tab: ProjectSheet.Tab = repo.state == .conflict ? .conflicts : .timeline
                // Espera a tela dos projetos aparecer para abrir a janela do projeto.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    NotificationCenter.default.post(name: .openLocalProject, object: ProjectSheetRequest(folder: repo.folder, tab: tab))
                }
            })
        }

        for issue in remote {
            list.append(Item(id: "i-\(issue.id)", group: "Tarefas e pedidos no GitHub", title: issue.title,
                             detail: "\(issue.repositoryFullName ?? "") #\(issue.number) · \(issue.state == "open" ? "aberto" : "fechado")",
                             symbol: issue.isPullRequest ? "arrow.triangle.pull" : "smallcircle.filled.circle",
                             tint: issue.state == "open" ? Theme.open : Theme.closed) {
                NSWorkspace.shared.open(issue.htmlUrl)
            })
        }

        let commands: [(String, String, String, Color, () -> Void)] = [
            ("Atualizar tudo", "Buscar as novidades do GitHub e das pastas", "arrow.clockwise", Theme.accent, {
                Task { await model.refreshAll(); await model.scanLocal() }
            }),
            ("Conferir projetos com o GitHub", "Pergunta se há novidades para cada projeto do Mac", "arrow.triangle.2.circlepath", .indigo, {
                model.section = .local
                Task { await model.fetchAllLocal() }
            }),
            ("Novo repositório", "Criar um repositório no GitHub", "plus.square.fill", .blue, {
                model.section = .repos
                model.repoPath = []
                NotificationCenter.default.post(name: .newRepository, object: nil)
            }),
            ("Acrescentar pasta de projetos", "Mais uma pasta para o app acompanhar", "folder.badge.plus", .indigo, {
                ProjectFolderPicker.add(to: model)
            }),
            ("Bloquear agora", "Fecha o app até a próxima digital", "lock.fill", .gray, { model.lock() })
        ]
        for (title, detail, symbol, tint, action) in commands where matches(title, detail) {
            list.append(Item(id: "c-" + title, group: "Ações", title: title, detail: detail, symbol: symbol, tint: tint, action: action))
        }

        if !query.isEmpty {
            for lesson in Glossary.lessons where matches(lesson.title, lesson.term, lesson.summary) {
                list.append(Item(id: "a-" + lesson.id, group: "Aprender", title: "\(lesson.title) (\(lesson.term))", detail: lesson.summary,
                                 symbol: lesson.symbol, tint: .pink) {
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        model.learning = lesson
                    }
                })
            }
        }
        return list
    }

    var body: some View {
        let list = items
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                TextField("Buscar repositórios, projetos, tarefas, lições…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { run(list) }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(list.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                if searchingRemote { ProgressView().controlSize(.small) }
                Text("esc").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(16)
            Divider()
            if list.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "Nada encontrado", message: "Tente outra palavra. Tarefas e pedidos do GitHub aparecem a partir de 3 letras.")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                                if index == 0 || list[index - 1].group != item.group {
                                    Text(item.group).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .padding(.horizontal, 12).padding(.top, index == 0 ? 4 : 10).padding(.bottom, 3)
                                }
                                row(item, selected: index == highlighted)
                                    .id(item.id)
                                    .onTapGesture { highlighted = index; run(list) }
                                    .onHover { if $0 { highlighted = index } }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: highlighted) { _, i in
                        if list.indices.contains(i) { proxy.scrollTo(list[i].id, anchor: .center) }
                    }
                }
            }
            Divider()
            HStack(spacing: 14) {
                hint("↑↓", "escolher")
                hint("↩", "abrir")
                hint("esc", "fechar")
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .frame(width: 620, height: 480)
        .onAppear { focused = true }
        .onChange(of: text) { highlighted = 0 }
        .task(id: text) {
            let query = text.trimmingCharacters(in: .whitespaces)
            guard query.count >= 3 else { remote = []; return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            searchingRemote = true
            defer { searchingRemote = false }
            let found = await model.searchIssues(query)
            if !Task.isCancelled { remote = found }
        }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: item.symbol, tint: item.tint, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(item.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "return").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }

    private func run(_ list: [Item]) {
        guard list.indices.contains(highlighted) else { return }
        let item = list[highlighted]
        dismiss()
        item.action()
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}
