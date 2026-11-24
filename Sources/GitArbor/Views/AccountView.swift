import AppKit
import GitArborCore
import SwiftUI

/// Conta e ajustes: perfil, segurança (Touch ID), conexão e preferências.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    var compact = false
    @ViewState private var confirmSignOut = false
    @ViewState private var touchIDError: String?
    @AppStorage(MenuBarPreference.key) private var showMenuBarIcon = true
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !compact {
                    ScreenHeader(title: "Conta e ajustes", subtitle: "Quem está conectado, como o app abre e as suas preferências.", symbol: "person.crop.circle.fill", tint: .gray)
                }

                if let user = model.user {
                    Card(padding: 20) {
                        HStack(spacing: 16) {
                            Avatar(url: user.avatarUrl, size: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name ?? user.login).font(.system(size: 20, weight: .bold))
                                Text("@\(user.login)").font(.system(size: 13)).foregroundStyle(.secondary)
                                if let bio = user.bio, !bio.isEmpty { Text(bio).font(.system(size: 12)).foregroundStyle(.secondary) }
                                HStack(spacing: 14) {
                                    Label("\((user.publicRepos ?? 0) + (user.totalPrivateRepos ?? 0)) repositórios", systemImage: "shippingbox")
                                    Label("\(user.followers ?? 0) seguidores", systemImage: "person.2")
                                    Label("no GitHub desde \(user.createdAt.map { String(Calendar.current.component(.year, from: $0)) } ?? "—")", systemImage: "calendar")
                                }
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { NSWorkspace.shared.open(user.htmlUrl ?? URL(string: "https://github.com")!) } label: { Label("Ver perfil", systemImage: "safari") }
                                .buttonStyle(ActionButtonStyle())
                        }
                    }
                }

                settingsCard(title: "Segurança", symbol: "lock.shield.fill", tint: Theme.accent) {
                    toggleRow(Binding(get: { model.requireTouchID }, set: { newValue in Task { await setTouchID(newValue) } })) {
                        row("touchid", "Pedir a digital ao abrir",
                            TouchIDAuthentication.isAvailable ? "Ninguém além de você abre o Git Arbor neste Mac." : "Este Mac não tem Touch ID: será pedida a senha do Mac.")
                    }
                    if let touchIDError { Text(touchIDError).font(.system(size: 11.5)).foregroundStyle(.red) }
                    Divider()
                    toggleRow($model.lockOnSleep) {
                        row("moon.fill", "Bloquear quando a tela apagar", "Ao voltar, o app pede a digital de novo.")
                    }
                    Divider()
                    HStack {
                        row("lock.fill", "Bloquear agora", "Atalho: ⌃⌘L")
                        Spacer()
                        Button("Bloquear") { model.lock() }.buttonStyle(ActionButtonStyle())
                    }
                }

                settingsCard(title: "Conexão com o GitHub", symbol: "link", tint: .indigo) {
                    HStack {
                        row(model.tokenSource == .githubCLI ? "terminal.fill" : "key.horizontal.fill",
                            model.tokenSource == .githubCLI ? "Pela conta do GitHub CLI (gh)" : "Por chave de acesso guardada no Chaves",
                            model.tokenSource == .githubCLI ? "O app usa a mesma conta do Terminal. Para trocar de conta, rode “gh auth login”." : "A chave fica no app Chaves do macOS, só neste Mac.")
                        Spacer()
                        Pill(text: "Conectado", symbol: "checkmark", tint: Theme.open)
                    }
                    Divider()
                    HStack {
                        row("rectangle.portrait.and.arrow.right", "Desconectar conta", "Nada é apagado no GitHub.")
                        Spacer()
                        Button("Desconectar…") { confirmSignOut = true }.buttonStyle(ActionButtonStyle(tint: Theme.danger))
                    }
                }

                settingsCard(title: "Preferências", symbol: "slider.horizontal.3", tint: .gray) {
                    HStack {
                        row("circle.lefthalf.filled", "Aparência", "Claro, escuro ou igual ao do Mac (Sistema).")
                        Spacer()
                        Picker("Aparência", selection: Binding(get: { appearance }, set: { appearance = $0; $0.apply() })) {
                            ForEach(AppAppearance.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider()
                    toggleRow($showMenuBarIcon) {
                        row("menubar.rectangle", "Mostrar ícone na barra de menus", "Acesso rápido às seções e aos projetos que pedem atenção. Também no menu Git Arbor.")
                    }
                    Divider()
                    toggleRow($model.showExplanations) {
                        row("lightbulb.fill", "Mostrar explicações para iniciantes", "As faixas amarelas e os desenhos que explicam cada tela.")
                    }
                    Divider()
                    toggleRow($model.systemNotifications) {
                        row("bell.badge.fill", "Avisos do macOS", "Avisos novos do GitHub (pedidos, tarefas, automações) e envio automático que falhou aparecem na Central de Notificações.")
                    }
                    Divider()
                    HStack {
                        row("folder.fill", "Pastas dos projetos", "Onde o app procura os projetos com Git. Também no menu Git Arbor.")
                        Spacer()
                        Button("Acrescentar…") { ProjectFolderPicker.add(to: model) }.buttonStyle(ActionButtonStyle(tint: .blue))
                    }
                    ForEach(model.localFolders, id: \.self) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 18)
                            Text(ProjectFolderPicker.display(folder))
                                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { NSWorkspace.shared.open(folder) } label: { Image(systemName: "arrow.up.forward.square") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Mostrar no Finder")
                            if model.localFolders.count > 1 {
                                Button { model.removeLocalFolder(folder) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Tirar da lista")
                            }
                        }
                        .padding(.leading, 30)
                    }
                }

                settingsCard(title: "Atalhos de teclado", symbol: "keyboard.fill", tint: .teal) {
                    shortcut("⌘1 … ⌘4", "Ir para cada seção da barra lateral")
                    shortcut("⌘N", "Novo repositório")
                    shortcut("⌘R", "Atualizar tudo")
                    shortcut("⌘[", "Voltar")
                    shortcut("⌃⌘L", "Bloquear")
                    shortcut("⌘,", "Abrir estes ajustes")
                    shortcut("⇧⌘/", "Aprender o básico do GitHub (menu Ajuda)")
                }

                Text("Git Arbor \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(compact ? 20 : 28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .confirmationDialog("Desconectar a conta do GitHub?", isPresented: $confirmSignOut) {
            Button("Desconectar", role: .destructive) { model.signOut() }
        } message: {
            Text("Nada é apagado no GitHub. Você só vai precisar conectar de novo para usar o app.")
        }
    }

    private func settingsCard<Content: View>(title: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                content()
            }
        }
    }

    /// Linha com texto à esquerda e a chave sempre alinhada à direita.
    private func toggleRow<Label: View>(_ isOn: Binding<Bool>, @ViewBuilder label: () -> Label) -> some View {
        HStack(alignment: .center, spacing: 12) {
            label()
            Spacer(minLength: 12)
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcut(_ keys: String, _ text: String) -> some View {
        HStack {
            Text(keys).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                .frame(width: 110, alignment: .leading)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }

    private func setTouchID(_ on: Bool) async {
        touchIDError = nil
        do {
            // Ligar ou desligar exige provar que é você.
            if TouchIDAuthentication.isAvailable {
                try await TouchIDAuthentication.verify(reason: on ? "ativar a digital no Git Arbor" : "desativar a digital no Git Arbor")
            } else {
                try await TouchIDAuthentication.verifyOwner(reason: on ? "proteger o Git Arbor com a senha do Mac" : "deixar de pedir a senha ao abrir o Git Arbor")
            }
            model.requireTouchID = on
        } catch {
            touchIDError = TouchIDAuthentication.message(for: error)
        }
    }
}
