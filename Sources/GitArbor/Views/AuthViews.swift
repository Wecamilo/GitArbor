import AppKit
import GitArborCore
import SwiftUI

// MARK: - Primeira vez

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var method: Method = GitHubCLI.isInstalled ? .cli : .token
    @ViewState private var token = ""
    @ViewState private var useTouchID = TouchIDAuthentication.isAvailable
    @ViewState private var busy = false
    @ViewState private var error: String?

    enum Method { case cli, token }

    var body: some View {
        AuthShell(contentWidth: 440) {
            AuthSidePanel(tagline: "Sua central do GitHub, explicada em imagens.") {
                SideSteps(current: 0)
            }
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vamos começar")
                        .font(.system(size: 28, weight: .bold))
                    Text("Primeiro, ligue o app à sua conta do GitHub. Leva menos de um minuto.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    MethodCard(selected: method == .cli, symbol: "terminal.fill", tint: .indigo,
                               title: "Usar a conta do GitHub CLI",
                               detail: GitHubCLI.isInstalled
                                ? "O Terminal deste Mac já tem o GitHub conectado (o programa “gh”). O app usa a mesma conta, sem senha nova."
                                : "O programa “gh” não foi encontrado neste Mac. Use a outra opção.",
                               badge: GitHubCLI.isInstalled ? "Recomendado" : nil) { method = .cli }
                        .disabled(!GitHubCLI.isInstalled)

                    MethodCard(selected: method == .token, symbol: "key.horizontal.fill", tint: .orange,
                               title: "Colar uma chave de acesso",
                               detail: "Você cria uma chave (token) no site do GitHub e cola aqui. Ela fica guardada no app Chaves do macOS.",
                               badge: nil) { method = .token }
                }

                if method == .token { tokenSteps.transition(.opacity.combined(with: .move(edge: .top))) }

                if TouchIDAuthentication.isAvailable {
                    TouchIDOption(isOn: $useTouchID)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await connect() }
                } label: {
                    if busy { ProgressView().controlSize(.small).tint(.white) } else { Text("Conectar ao GitHub") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || (method == .token && token.trimmingCharacters(in: .whitespaces).count < 20))
                .keyboardShortcut(.defaultAction)
            }
            .animation(.smooth(duration: 0.25), value: method)
        }
    }

    private var tokenSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Como criar a chave").font(.system(size: 13, weight: .semibold))
            NumberedStep(n: 1, text: "Abra a página de chaves do GitHub.") {
                Button("Abrir no navegador") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens/new?scopes=repo,workflow,notifications,read:user,delete_repo&description=Git%20Arbor")!)
                }
                .buttonStyle(ActionButtonStyle())
            }
            NumberedStep(n: 2, text: "As permissões já vêm marcadas. Escolha a validade e clique em “Generate token”, no fim da página.") { EmptyView() }
            NumberedStep(n: 3, text: "Copie o código que começa com “ghp_” e cole abaixo.") { EmptyView() }
            LabeledField(label: "Chave de acesso", text: $token, secure: true, prompt: "ghp_…")
        }
        .padding(14)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.corner))
    }

    private func connect() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            switch method {
            case .cli: try await model.connectWithGitHubCLI(enableTouchID: useTouchID)
            case .token: try await model.connectWithToken(token, enableTouchID: useTouchID)
            }
            token = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Os três passos do começo, no painel verde (em branco).
struct SideSteps: View {
    var current: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            item(0, "link", "Conectar a conta")
            line
            item(1, "square.grid.2x2.fill", "Ver seus projetos")
            line
            item(2, "graduationcap.fill", "Aprender no caminho")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Três passos: conectar a conta, ver os projetos e aprender no caminho")
    }

    private func item(_ i: Int, _ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(i == current ? Theme.accent : .white)
                .frame(width: 32, height: 32)
                .background(i == current ? Color.white : Color.white.opacity(0.18), in: Circle())
            Text(text)
                .font(.system(size: 13, weight: i == current ? .bold : .medium))
                .foregroundStyle(.white.opacity(i == current ? 1 : 0.8))
        }
    }

    private var line: some View {
        Rectangle().fill(.white.opacity(0.35)).frame(width: 2, height: 18).padding(.leading, 15)
    }
}

private struct MethodCard: View {
    let selected: Bool
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let badge: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: symbol, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if let badge { Pill(text: badge, tint: Theme.accent) }
                    }
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .background(selected ? Theme.accentSoft : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner).strokeBorder(selected ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct NumberedStep<Accessory: View>: View {
    let n: Int
    let text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                accessory
            }
        }
    }
}

/// Caixa "Entrar com Touch ID" explicando o que acontece.
struct TouchIDOption: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                Image(systemName: "touchid")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Entrar com Touch ID").font(.system(size: 14, weight: .semibold))
                    Text("Só a sua digital abre o Git Arbor neste Mac. A senha do Mac continua valendo.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(14)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Entrada

struct LockView: View {
    @Environment(AppModel.self) private var model
    @ViewState private var busy = false
    @ViewState private var error: String?
    @ViewState private var showPasswordForm = false
    @ViewState private var confirmSignOut = false

    private var usesTouchID: Bool { model.requireTouchID && TouchIDAuthentication.isAvailable }

    var body: some View {
        AuthShell(contentWidth: 360) {
            AuthSidePanel(colored: model.ownerConfirmed) {
                if let login = model.lastLogin {
                    HStack(spacing: 10) {
                        Avatar(url: model.lastAvatar, size: 32)
                            .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Conta conectada").font(.system(size: 10.5)).opacity(0.8)
                            Text("@\(login)").font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 8)
                    .background(.white.opacity(0.18), in: Capsule())
                    .frame(maxWidth: .infinity)
                }
            }
        } content: {
            VStack(spacing: 26) {
                VStack(spacing: 6) {
                    Text("Que bom te ver")
                        .font(.system(size: 26, weight: .bold))
                    Text(usesTouchID && !showPasswordForm ? "Toque no sensor para abrir sua central." : "Confirme que é você para continuar.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }

                if usesTouchID && !showPasswordForm {
                    // Digital na própria janela, sem a janela padrão do macOS por cima.
                    TouchIDPrompt { message in
                        error = message
                        withAnimation(.easeInOut(duration: 0.25)) { showPasswordForm = true }
                    }
                    .transition(.opacity)
                } else {
                    VStack(spacing: 14) {
                        IconTile(symbol: "lock.open.fill", tint: Theme.accent, size: 64)
                            .padding(.bottom, 6)
                        Button {
                            Task { await enter() }
                        } label: {
                            if busy { ProgressView().controlSize(.small).tint(.white) } else {
                                Label(model.requireTouchID ? "Entrar com a senha do Mac" : "Entrar", systemImage: "lock.open.fill")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy)

                        HStack {
                            if usesTouchID {
                                Button("Usar Touch ID") {
                                    error = nil
                                    withAnimation(.easeInOut(duration: 0.25)) { showPasswordForm = false }
                                }
                            }
                            Spacer()
                            Button("Desconectar conta…") { confirmSignOut = true }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 13))
                    }
                    .transition(.opacity)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13)).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task {
            if !model.requireTouchID { await enter() }
        }
        .confirmationDialog("Desconectar a conta do GitHub?", isPresented: $confirmSignOut) {
            Button("Desconectar", role: .destructive) { model.signOut() }
        } message: {
            Text("Nada é apagado no GitHub. Você só vai precisar conectar de novo para usar o app.")
        }
    }

    private func enter() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if model.requireTouchID {
                try await TouchIDAuthentication.verifyOwner(reason: "abrir o Git Arbor")
            }
            withAnimation(.easeInOut(duration: 0.45)) { model.ownerConfirmed = true }
            try? await Task.sleep(for: .milliseconds(500))
            try await model.unlockAfterVerification()
        } catch {
            self.error = TouchIDAuthentication.message(for: error)
        }
    }
}

// MARK: - Abertura

/// Abertura: o quadro aparece e as três pastas caem uma a uma na pilha (amarela, rosa e,
/// por último, a azul na frente), com um leve quique; o nome sobe junto. Cerca de 1,3 s.
struct SplashView: View {
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var scheme
    @ViewState private var tile = false
    @ViewState private var drops: [CGFloat] = [0, 0, 0]
    @ViewState private var title = false

    private let size: CGFloat = 132

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                        .fill(ArborMark.tileGradient(scheme))
                        .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.12), radius: 16, y: 6)
                        .scaleEffect(tile ? 1 : 0.7)
                        .opacity(tile ? 1 : 0)
                    ForEach(Array(ArborCards.all.enumerated()), id: \.offset) { k, card in
                        let p = drops[k]
                        RoundedRectangle(cornerRadius: size * ArborCards.corner, style: .continuous)
                            .fill(LinearGradient(colors: [card.top, card.bottom], startPoint: .top, endPoint: .bottom))
                            .overlay(
                                RoundedRectangle(cornerRadius: size * ArborCards.corner, style: .continuous)
                                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 0.8)
                            )
                            .shadow(color: .black.opacity(0.18 * Double(p)), radius: size * 0.03, y: size * 0.018)
                            .frame(width: size * card.w, height: size * ArborCards.height)
                            // Cai de cima: começa mais alta, um pouco menor e transparente.
                            .scaleEffect(0.92 + 0.08 * p, anchor: .bottom)
                            .offset(x: size * card.x, y: size * card.y - (1 - p) * size * 0.45)
                            .opacity(Double(min(1, p * 2.5)))
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))

                Text("Git Arbor")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .opacity(title ? 1 : 0)
                    .offset(y: title ? 0 : 8)
            }
        }
        .task {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { tile = true }
            for k in 0..<3 {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62).delay(0.14 + 0.15 * Double(k))) { drops[k] = 1 }
            }
            withAnimation(.easeOut(duration: 0.35).delay(0.5)) { title = true }
            try? await Task.sleep(for: .milliseconds(1250))
            onFinish()
        }
        .accessibilityLabel("Abrindo o Git Arbor")
    }
}
