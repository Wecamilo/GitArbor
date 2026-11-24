import AppKit
import GitArborCore
import SwiftUI

@main
struct GitArborApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ViewState private var model = AppModel()
    @AppStorage(MenuBarPreference.key) private var showMenuBarIcon = true

    var body: some Scene {
        Window("Git Arbor", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1240, height: 820)
        .commands { ArborCommands(model: model) }

        Settings {
            AccountView(compact: true)
                .environment(model)
                .frame(width: 600, height: 680)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarMenu()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppAppearance.current.apply()
    }

    /// Com o ícone na barra de menus, fechar a janela não encerra o app (ele continua no menu).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: MenuBarPreference.key) as? Bool ?? true)
    }
}

struct ArborCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            MenuBarToggle()
            Menu("Pastas dos projetos") {
                ForEach(model.localFolders, id: \.self) { folder in
                    Menu(ProjectFolderPicker.display(folder)) {
                        Button("Mostrar no Finder") { NSWorkspace.shared.open(folder) }
                        Button("Tirar da lista") { model.removeLocalFolder(folder) }
                            .disabled(model.localFolders.count < 2)
                    }
                }
                Divider()
                Button("Acrescentar pasta…") { ProjectFolderPicker.add(to: model) }
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("Novo repositório…") {
                model.section = .repos
                model.repoPath = []
                NotificationCenter.default.post(name: .newRepository, object: nil)
            }
            .keyboardShortcut("n")
            .disabled(model.phase != .unlocked)
        }
        CommandMenu("Ir") {
            Button("Busca rápida…") { model.quickSearchOpen = true }
                .keyboardShortcut("k")
                .disabled(model.phase != .unlocked)
            Divider()
            ForEach(AppSection.allCases) { section in
                Button(section.title) {
                    model.section = section
                    if section == .repos { model.repoPath = [] }
                }
                .keyboardShortcut(section.shortcut)
                .disabled(model.phase != .unlocked)
            }
            Divider()
            Button("Atualizar tudo") {
                Task {
                    await model.refreshAll()
                    await model.scanLocal()
                }
            }
            .keyboardShortcut("r")
            .disabled(model.phase != .unlocked)
            Button("Voltar") { if !model.repoPath.isEmpty { model.repoPath.removeLast() } }
                .keyboardShortcut("[")
                .disabled(model.repoPath.isEmpty)
            Divider()
            Button("Bloquear agora") { model.lock() }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .disabled(model.phase != .unlocked)
        }
        CommandGroup(replacing: .help) {
            Button("Aprender o básico do GitHub") { model.learning = Glossary.lessons.first }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            Menu("Lições") {
                ForEach(Glossary.lessons) { lesson in
                    Button("\(lesson.title) (\(lesson.term))") { model.learning = lesson }
                }
            }
            Divider()
            Button("Abrir o GitHub no navegador") { NSWorkspace.shared.open(URL(string: "https://github.com")!) }
        }
    }
}

/// Item “Mostrar ícone na barra de menus” do menu Git Arbor (com marca de seleção).
struct MenuBarToggle: View {
    @AppStorage(MenuBarPreference.key) private var showMenuBarIcon = true

    var body: some View {
        Toggle("Mostrar ícone na barra de menus", isOn: $showMenuBarIcon)
    }
}

extension Notification.Name {
    static let newRepository = Notification.Name("GitArbor.newRepository")
    /// Abre a janela de um projeto do Mac (objeto: ProjectSheetRequest).
    static let openLocalProject = Notification.Name("GitArbor.openLocalProject")
}

/// Escolhe a tela conforme o estado da sessão.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var showSplash = true

    var body: some View {
        @Bindable var model = model
        Group {
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.35)) { showSplash = false } }
                    .transition(.opacity)
            } else {
                Group {
                    switch model.phase {
                    case .welcome: WelcomeView()
                    case .locked: LockView()
                    case .unlocked: MainView()
                    }
                }
                .transition(.opacity)
            }
        }
        // Só a tela principal tem barra de ferramentas; nas de abertura, entrada e bloqueio
        // o fundo vai até o topo, sem a faixa da barra de título.
        .toolbarBackgroundVisibility(!showSplash && model.phase == .unlocked ? .automatic : .hidden, for: .windowToolbar)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: Binding(get: { model.quickSearchOpen && model.phase == .unlocked }, set: { model.quickSearchOpen = $0 })) {
            QuickSearchView()
                .environment(model)
        }
        .sheet(item: Binding(get: { model.learning }, set: { model.learning = $0 })) { lesson in
            LearnView(start: lesson)
                .environment(model)
        }
        .alert("Algo deu errado", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
