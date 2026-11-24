import AppKit
import GitArborCore
import SwiftUI

/// Preferência do ícone na barra de menus (ligado por padrão).
enum MenuBarPreference {
    static let key = "showMenuBarIcon"
}

/// Ícone da barra de menus: as três pastas do logo, em versão de modelo (o macOS pinta de
/// preto ou branco conforme a barra), com um vão entre elas para se distinguirem.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cards: [CGRect] = [
                CGRect(x: 5, y: 1.5, width: 8, height: 7),
                CGRect(x: 3.5, y: 4, width: 11, height: 7),
                CGRect(x: 2, y: 6.5, width: 14, height: 8.5)
            ]
            for (k, rect) in cards.enumerated() {
                if k > 0 {
                    // Vão transparente em volta do cartão da frente.
                    ctx.setBlendMode(.clear)
                    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -1.2, dy: -1.2), cornerWidth: 3, cornerHeight: 3, transform: nil))
                    ctx.fillPath()
                    ctx.setBlendMode(.normal)
                }
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil))
                ctx.fillPath()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Git Arbor"
        return image
    }()
}

/// Menu do ícone na barra de menus: situação, atalhos para as seções e ações rápidas.
struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var attention: [LocalRepoStatus] {
        model.localRepos.filter { [.unsaved, .toSend, .toReceive, .diverged, .conflict, .noUpstream].contains($0.state) }
    }

    var body: some View {
        if model.phase == .unlocked {
            if let user = model.user {
                Text("Conectado como @\(user.login)")
            }
            Divider()
            Button("Abrir o Git Arbor") { show(nil) }
            Divider()
            ForEach(AppSection.allCases) { section in
                Button(title(for: section)) { show(section) }
            }
            if !attention.isEmpty {
                Divider()
                Text("Pedem atenção no Mac")
                ForEach(attention.prefix(8)) { repo in
                    Button("\(repo.name) — \(LocalStateBadge.title(repo.state))") {
                        show(.local)
                    }
                }
            }
            Divider()
            Button("Atualizar tudo") {
                Task {
                    await model.refreshAll()
                    await model.scanLocal()
                }
            }
            Button("Aprender o básico do GitHub") {
                show(nil)
                model.learning = Glossary.lessons.first
            }
            SettingsLink { Text("Ajustes…") }
            Button("Bloquear agora") { model.lock() }
        } else {
            Text(model.phase == .welcome ? "Nenhuma conta conectada" : "Bloqueado")
            Button(model.phase == .welcome ? "Abrir para conectar…" : "Abrir para entrar…") { show(nil) }
        }
        Divider()
        Button("Esconder este ícone") {
            UserDefaults.standard.set(false, forKey: MenuBarPreference.key)
        }
        Button("Sair do Git Arbor") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(for section: AppSection) -> String {
        switch section {
        case .notifications where model.unreadCount > 0: "\(section.title) (\(model.unreadCount))"
        case .local where !attention.isEmpty: "\(section.title) (\(attention.count) pedem atenção)"
        case .repos where !model.repos.isEmpty: "\(section.title) (\(model.repos.count))"
        default: section.title
        }
    }

    /// Traz a janela principal para a frente (abrindo-a se estiver fechada) na seção pedida.
    private func show(_ section: AppSection?) {
        if let section {
            model.section = section
            if section == .repos { model.repoPath = [] }
        }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
