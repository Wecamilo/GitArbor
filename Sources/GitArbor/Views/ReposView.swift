import GitArborCore
import SwiftUI

/// Lista de repositórios em cartões grandes, com busca, filtros e criação.
struct ReposView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.repoPath) {
            RepoGrid()
                .navigationDestination(for: GHRepo.self) { repo in
                    RepoDetailView(repo: repo)
                        .id(repo.id)
                }
        }
    }
}

private struct RepoGrid: View {
    @Environment(AppModel.self) private var model
    @ViewState private var query = ""
    @ViewState private var filter: Filter = .all
    @ViewState private var sort: Sort = .recent
    @ViewState private var showNew = false
    @AppStorage("reposLayout") private var layout: ItemLayout = .cards

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos", mine = "Meus", privateOnly = "Privados", publicOnly = "Públicos", archived = "Arquivados"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent = "Mais recentes", name = "Nome (A–Z)", stars = "Mais estrelas"
        var id: String { rawValue }
    }

    private func repos(_ filter: Filter) -> [GHRepo] {
        switch filter {
        case .all: model.repos.filter { !$0.isArchived }
        case .mine: model.repos.filter { $0.owner.login == model.user?.login && !$0.isArchived }
        case .privateOnly: model.repos.filter { $0.isPrivate && !$0.isArchived }
        case .publicOnly: model.repos.filter { !$0.isPrivate && !$0.isArchived }
        case .archived: model.repos.filter(\.isArchived)
        }
    }

    private var filterOptions: [ChipOption<Filter>] {
        let symbols: [Filter: String] = [.all: "square.grid.2x2.fill", .mine: "person.fill", .privateOnly: "lock.fill", .publicOnly: "globe", .archived: "archivebox.fill"]
        return Filter.allCases.map { ChipOption(value: $0, title: $0.rawValue, symbol: symbols[$0]!, count: repos($0).count) }
    }

    private var sortOptions: [ChipOption<Sort>] {
        [ChipOption(value: .recent, title: Sort.recent.rawValue, symbol: "clock.fill"),
         ChipOption(value: .name, title: Sort.name.rawValue, symbol: "textformat"),
         ChipOption(value: .stars, title: Sort.stars.rawValue, symbol: "star.fill")]
    }

    /// O que dizer quando a lista fica vazia, conforme o filtro e a busca.
    private var emptyMessage: (symbol: String, title: String, message: String) {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            return ("magnifyingglass", "Nada encontrado", "Nenhum repositório com “\(query)”. Tente outra palavra ou mude o filtro.")
        }
        if model.repos.isEmpty {
            return ("shippingbox", "Nenhum repositório ainda", "Crie o primeiro com o botão “Novo repositório”.")
        }
        switch filter {
        case .publicOnly: return ("globe", "Nenhum repositório público", "Todos os seus repositórios são privados: só você vê. Para mostrar um ao mundo, abra-o e use Ajustes › Tornar público.")
        case .privateOnly: return ("lock", "Nenhum repositório privado", "Todos os seus repositórios estão visíveis para qualquer pessoa.")
        case .archived: return ("archivebox", "Nenhum repositório arquivado", "Arquivar deixa um projeto só para leitura. Faça isso em Ajustes, dentro do repositório.")
        case .mine: return ("person", "Nenhum repositório seu", "Aqui aparecem só os repositórios criados na sua conta.")
        case .all: return ("shippingbox", "Tudo arquivado", "Seus repositórios estão arquivados. Veja no filtro Arquivados.")
        }
    }

    private var filtered: [GHRepo] {
        var list = repos(filter)
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(q) || ($0.description ?? "").localizedCaseInsensitiveContains(q) }
        }
        switch sort {
        case .recent: list.sort { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .stars: list.sort { $0.stargazersCount > $1.stargazersCount }
        }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(title: "Repositórios", subtitle: "Cada cartão é um projeto guardado no GitHub. Clique para ver arquivos, histórico, tarefas e tudo mais.",
                             symbol: "shippingbox.fill", tint: .blue) {
                    Button { showNew = true } label: { Label("Novo repositório", systemImage: "plus") }
                        .buttonStyle(ActionButtonStyle(prominent: true))
                        .help("Criar um repositório no GitHub (⌘N)")
                }

                ExplainBanner(lessonID: "repository")

                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Procurar pelo nome ou descrição", text: $query)
                            .textFieldStyle(.plain)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Limpar busca")
                        }
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 14).padding(.vertical, 7.5)
                    .background(Capsule().fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    .frame(minWidth: 170, maxWidth: 300)

                    FilterChips(selection: $filter, options: filterOptions)

                    Spacer()

                    ChipMenu(selection: $sort, options: sortOptions, label: "Ordem:")
                    LayoutToggle(selection: $layout)
                }

                if model.repos.isEmpty && model.isRefreshing {
                    LoadingRow()
                } else if filtered.isEmpty {
                    EmptyState(symbol: emptyMessage.symbol, title: emptyMessage.title, message: emptyMessage.message)
                } else {
                    Text(Phrases.plural(filtered.count, "repositório", "repositórios"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if layout == .cards {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                            ForEach(filtered) { repo in
                                NavigationLink(value: repo) { RepoCard(repo: repo) }
                                    .buttonStyle(.plain)
                            }
                        }
                    } else {
                        ListPanel(items: filtered) { repo in
                            NavigationLink(value: repo) { RepoListRow(repo: repo) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showNew) { NewRepoSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .newRepository)) { _ in showNew = true }
    }
}

/// Linha da lista de repositórios: ícone, nome, descrição e os detalhes principais numa linha só.
struct RepoListRow: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var hovering = false

    private var local: LocalRepoStatus? {
        model.localCopy(of: repo)
    }

    var body: some View {
        HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(repo.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Pill(text: repo.isPrivate ? "Privado" : "Público", symbol: repo.isPrivate ? "lock.fill" : "globe",
                         tint: repo.isPrivate ? .orange : .blue)
                    if repo.isArchived { Pill(text: "Arquivado", symbol: "archivebox.fill", tint: .gray) }
                    if repo.fork { Pill(text: "Cópia", symbol: "tuningfork", tint: .purple) }
                }
                Text(repo.description?.isEmpty == false ? repo.description! : "Sem descrição")
                    .font(.system(size: 11.5))
                    .foregroundStyle(repo.description?.isEmpty == false ? .secondary : .tertiary)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    LanguageTag(name: repo.language)
                    if let branch = repo.defaultBranch {
                        Label(branch, systemImage: "arrow.triangle.branch").foregroundStyle(.teal)
                    }
                    if repo.stargazersCount > 0 { Label("\(repo.stargazersCount)", systemImage: "star.fill") }
                    if repo.forksCount > 0 { Label("\(repo.forksCount)", systemImage: "tuningfork") }
                    if repo.openIssuesCount > 0 {
                        Label("\(repo.openIssuesCount) abertas", systemImage: "smallcircle.filled.circle")
                            .help("Tarefas e pedidos abertos")
                    }
                    if let size = repo.size, size > 0 { Label(Phrases.size(kilobytes: size), systemImage: "externaldrive") }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                if let local {
                    HStack(spacing: 5) {
                        LocalStateBadge(state: local.state, small: true)
                        Text(LocalStateBadge.title(local.state)).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LocalStateBadge.tint(local.state))
                    }
                    .help("Cópia neste Mac: \(local.folder.path)")
                } else {
                    Label("Só no GitHub", systemImage: "icloud").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Text(Phrases.relative(repo.lastActivity)).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: "\(repo.fullName)|\(repo.pushedAt?.timeIntervalSince1970 ?? 0)|\(model.localFolder(for: repo)?.path ?? "")") {
            await model.loadIcon(for: repo)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre o repositório")
    }

    @ViewBuilder private var icon: some View {
        if let image = model.repoIcons.image(for: repo) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .opacity(repo.isArchived ? 0.6 : 1)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color.language(repo.language).opacity(0.85), Color.language(repo.language)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: repo.isArchived ? "archivebox.fill" : repo.fork ? "tuningfork" : "shippingbox.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.onLanguage(repo.language)))
        }
    }
}

/// Cartão visual de um repositório.
struct RepoCard: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Faixa com a cor da linguagem principal.
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color.language(repo.language).opacity(0.85), Color.language(repo.language).opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack {
                    if let icon = model.repoIcons.image(for: repo) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .opacity(repo.isArchived ? 0.6 : 1)
                            .accessibilityHidden(true)
                            .transition(.opacity)
                    } else {
                        Image(systemName: repo.isArchived ? "archivebox.fill" : repo.fork ? "tuningfork" : "shippingbox.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.onLanguage(repo.language).opacity(0.95))
                    }
                    Spacer()
                    Pill(text: repo.isPrivate ? "Privado" : "Público", symbol: repo.isPrivate ? "lock.fill" : "globe", tint: Color.onLanguage(repo.language))
                        .background(.black.opacity(Color.isLight(hex: Languages.hex(repo.language)) ? 0.06 : 0.18), in: Capsule())
                }
                .padding(12)
            }
            .frame(height: 54)

            VStack(alignment: .leading, spacing: 8) {
                Text(repo.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(repo.description?.isEmpty == false ? repo.description! : "Sem descrição")
                    .font(.system(size: 12))
                    .foregroundStyle(repo.description?.isEmpty == false ? .secondary : .tertiary)
                    .lineLimit(2, reservesSpace: true)
                HStack(spacing: 12) {
                    LanguageTag(name: repo.language)
                    if repo.stargazersCount > 0 {
                        Label("\(repo.stargazersCount)", systemImage: "star.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if repo.openIssuesCount > 0 {
                        Label("\(repo.openIssuesCount)", systemImage: "smallcircle.filled.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                            .help("Tarefas e pedidos abertos")
                    }
                    Spacer()
                    Text(Phrases.relative(repo.lastActivity)).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous).strokeBorder(Color.primary.opacity(hovering ? 0.18 : 0.07)))
        .shadow(color: .black.opacity(hovering ? 0.10 : 0.04), radius: hovering ? 12 : 6, y: hovering ? 5 : 2)
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .task(id: "\(repo.fullName)|\(repo.pushedAt?.timeIntervalSince1970 ?? 0)|\(model.localFolder(for: repo)?.path ?? "")") {
            await model.loadIcon(for: repo)
        }
        .animation(.easeOut(duration: 0.2), value: model.repoIcons.image(for: repo) != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre o repositório")
    }
}

/// Criar repositório, explicando cada escolha.
struct NewRepoSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var description = ""
    @ViewState private var isPrivate = true
    @ViewState private var readme = true
    @ViewState private var busy = false

    private var cleanName: String { Phrases.repoSlug(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                IconTile(symbol: "plus.square.fill", tint: .blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Novo repositório").font(.system(size: 20, weight: .bold))
                    Text("Uma pasta nova no GitHub para um projeto.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            LabeledField(label: "Nome", text: $name, prompt: "meu-projeto",
                         help: cleanName.isEmpty ? "Sem espaços: use hífen. Ex.: site-da-loja" : "Vai ficar: github.com/\(model.user?.login ?? "")/\(cleanName)")
            LabeledField(label: "Descrição (opcional)", text: $description, prompt: "Para que serve este projeto")

            VStack(alignment: .leading, spacing: 8) {
                Text("Quem pode ver").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    choice(selected: isPrivate, symbol: "lock.fill", title: "Privado", detail: "Só você e quem você convidar.") { isPrivate = true }
                    choice(selected: !isPrivate, symbol: "globe", title: "Público", detail: "Qualquer pessoa vê; só você muda.") { isPrivate = false }
                }
            }

            Toggle(isOn: $readme) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Começar com um arquivo README").font(.system(size: 13, weight: .medium))
                    Text("Cria o arquivo de apresentação. Assim o repositório já nasce com um primeiro commit e pode ser clonado.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            HStack {
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        busy = true
                        if let repo = await model.createRepository(name: cleanName, description: description, isPrivate: isPrivate, withReadme: readme) {
                            dismiss()
                            model.open(repo)
                        }
                        busy = false
                    }
                } label: {
                    if busy { ProgressView().controlSize(.small) } else { Text("Criar repositório") }
                }
                .buttonStyle(ActionButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(cleanName.isEmpty || busy)
            }
        }
        .padding(24)
        .frame(width: 480)
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
}
