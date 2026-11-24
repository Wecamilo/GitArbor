import AppKit
import GitArborCore
import SwiftUI

/// Janela principal: barra lateral com as seções e o conteúdo ao lado.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            Group {
                switch model.section {
                case .home: HomeView()
                case .panorama: PanoramaView()
                case .repos: ReposView()
                case .local: LocalProjectsView()
                case .notifications: NotificationsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            // Presa à coluna do conteúdo, a barra põe os botões no canto direito.
            .toolbar { toolbarButtons }
        }
        // Barra um tom abaixo do fundo das telas, para parecer parte da janela.
        .toolbarBackground(Theme.toolbar, for: .windowToolbar)
    }

    @ToolbarContentBuilder private var toolbarButtons: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.quickSearchOpen = true } label: {
                Label("Buscar", systemImage: "magnifyingglass")
            }
            .help("Busca rápida: repositórios, projetos, tarefas e lições (⌘K)")

            Button {
                Task {
                    await model.refreshAll()
                    await model.scanLocal()
                }
            } label: {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Atualizar", systemImage: "arrow.clockwise")
                }
            }
            .help("Buscar as novidades do GitHub (⌘R)")

            Button { NSWorkspace.shared.open(model.user?.htmlUrl ?? URL(string: "https://github.com")!) } label: {
                Label("Abrir no navegador", systemImage: "safari")
            }
            .help("Abrir o seu perfil no site do GitHub")

            Button { model.lock() } label: {
                Label("Bloquear", systemImage: "lock.fill")
            }
            .help("Bloquear o app até a próxima digital (⌃⌘L)")
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s; if s == .repos { model.repoPath = [] } } })) {
            SwiftUI.Section {
                ForEach(AppSection.allCases) { section in
                    SidebarRow(section: section, badge: badge(for: section))
                        .tag(section)
                }
            } header: {
                HStack(spacing: 8) {
                    ArborGlyph().frame(width: 24, height: 24).padding(-4)
                    Text("Git Arbor").font(.system(size: 12, weight: .bold))
                }
                .padding(.top, 14)
                .padding(.bottom, 6)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { profile }
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .notifications: model.unreadCount
        case .local: model.localRepos.filter { $0.state != .clean && $0.state != .noRemote }.count
        default: 0
        }
    }

    @ViewBuilder private var profile: some View {
        if let user = model.user {
            SettingsLink {
                HStack(spacing: 10) {
                    Avatar(url: user.avatarUrl, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.name ?? user.login).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text("@\(user.login)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Circle().fill(Theme.open).frame(width: 8, height: 8)
                        .help("Conectado ao GitHub")
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityLabel("Conectado como \(user.login). Abrir os ajustes")
            .help("Conta e ajustes (⌘,)")
        }
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let badge: Int

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: section.symbol, tint: section.tint, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(section.title).font(.system(size: 13, weight: .medium))
                Text(section.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(section.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityHint(section.subtitle)
    }
}
