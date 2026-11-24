import AppKit
import GitArborCore
import SwiftUI

// MARK: - Segurança

/// Alertas do Dependabot e segredos encontrados pelo GitHub, explicados em português.
struct SecurityTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var enabled: Bool?
    @ViewState private var alerts: [GHDependabotAlert]?
    @ViewState private var secrets: [GHSecretAlert]?
    @ViewState private var failure: String?
    @ViewState private var busy = false

    private var isOwner: Bool { repo.owner.login == model.user?.login }
    private var localCopy: LocalRepoStatus? {
        model.localCopy(of: repo)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExplainBanner(lessonID: "security")

            if let failure {
                EmptyState(symbol: "exclamationmark.shield", title: "Não consegui ler os alertas", message: failure)
            } else if let enabled {
                if !enabled {
                    Card(padding: 16) {
                        HStack(spacing: 14) {
                            IconTile(symbol: "shield.slash.fill", tint: .orange, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Os alertas de segurança estão desligados").font(.system(size: 14, weight: .semibold))
                                Text("Ligando, o GitHub avisa quando uma biblioteca usada pelo projeto tem uma falha conhecida e pode abrir sozinho um pedido de mudança com a correção.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if isOwner {
                                Button { Task { await enable() } } label: {
                                    if busy { ProgressView().controlSize(.small) } else { Label("Ligar alertas", systemImage: "shield.lefthalf.filled") }
                                }
                                .buttonStyle(ActionButtonStyle(tint: .orange, prominent: true))
                                .disabled(busy)
                            }
                        }
                    }
                } else if let alerts {
                    summary(alerts)
                    ForEach(alerts) { alertRow($0) }
                }
                if let secrets, !secrets.isEmpty {
                    Text("Segredos encontrados pelo GitHub").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
                    ForEach(secrets) { s in
                        HStack(spacing: 12) {
                            IconTile(symbol: "key.fill", tint: Theme.danger, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.secretTypeDisplayName ?? "Chave ou senha").font(.system(size: 13, weight: .semibold))
                                Text("Troque essa chave no serviço de origem: ela está no histórico do repositório. \(Phrases.relative(s.createdAt))")
                                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = s.htmlUrl {
                                Button("Ver no GitHub") { NSWorkspace.shared.open(url) }.buttonStyle(ActionButtonStyle(tint: Theme.danger))
                            }
                        }
                        .padding(10)
                        .background(Theme.danger.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                localScanHint
            } else {
                LoadingRow(text: "Conferindo a segurança…")
            }
        }
        .task(id: repo.id) { await load() }
    }

    private func summary(_ alerts: [GHDependabotAlert]) -> some View {
        let critical = alerts.filter { ["critical", "high"].contains($0.securityAdvisory?.severity ?? "") }.count
        let tint: Color = alerts.isEmpty ? Theme.open : (critical > 0 ? Theme.danger : .orange)
        return Card(padding: 16) {
            HStack(spacing: 14) {
                IconTile(symbol: alerts.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill", tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(alerts.isEmpty ? "Nenhuma falha conhecida nas dependências" : Phrases.plural(alerts.count, "alerta aberto", "alertas abertos"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(alerts.isEmpty
                         ? "Os alertas estão ligados: se aparecer algo, o GitHub avisa aqui e nas notificações."
                         : (critical > 0 ? "\(Phrases.plural(critical, "é grave", "são graves")). Atualize essas bibliotecas primeiro." : "Nenhum é grave, mas vale atualizar."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSWorkspace.shared.open(repo.htmlUrl.appendingPathComponent("security")) } label: { Label("Abrir no GitHub", systemImage: "safari") }
                    .buttonStyle(ActionButtonStyle(tint: .secondary))
            }
        }
    }

    private func alertRow(_ a: GHDependabotAlert) -> some View {
        let severity = a.securityAdvisory?.severity ?? ""
        let tint: Color = switch severity {
        case "critical": Theme.danger
        case "high": .red
        case "medium", "moderate": .orange
        default: .yellow
        }
        return HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "shippingbox.fill", tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(a.dependency?.package?.name ?? "Dependência").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Pill(text: "Gravidade: \(a.severityLabel)", tint: tint)
                    if let eco = a.dependency?.package?.ecosystem { Pill(text: eco, tint: .secondary) }
                }
                Text(a.securityAdvisory?.summary ?? "").font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                if let fixed = a.securityVulnerability?.firstPatchedVersion?.identifier {
                    Label("Como resolver: atualizar para a versão \(fixed) ou mais nova\(a.dependency?.manifestPath.map { " (em \($0))" } ?? "").", systemImage: "wrench.and.screwdriver.fill")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.open)
                } else {
                    Label("Ainda não há versão corrigida. Veja no GitHub se há outra saída.", systemImage: "hourglass")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let url = a.htmlUrl {
                Button("Detalhes") { NSWorkspace.shared.open(url) }.buttonStyle(ActionButtonStyle(tint: tint))
            }
        }
        .padding(12)
        .background(tint.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var localScanHint: some View {
        if let local = localCopy {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal.fill").foregroundStyle(.orange)
                Text("Quer conferir se alguma senha ou chave foi parar no histórico? A busca roda na cópia deste Mac.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Procurar senhas") {
                    model.section = .local
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        NotificationCenter.default.post(name: .openLocalProject, object: ProjectSheetRequest(folder: local.folder, tab: .secrets))
                    }
                }
                .buttonStyle(ActionButtonStyle(tint: .orange))
            }
            .padding(12)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.corner))
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            let on = try await client.vulnerabilityAlertsEnabled(repo.fullName)
            enabled = on
            if on { alerts = try await client.dependabotAlerts(repo.fullName) }
            failure = nil
        } catch GitHubError.forbidden {
            failure = isOwner
                ? "A chave de acesso não tem permissão para ler alertas de segurança. Rode “gh auth refresh -s security_events” no Terminal e tente de novo."
                : "Só quem administra este repositório vê os alertas de segurança."
        } catch {
            if enabled == nil { failure = error.localizedDescription }
        }
        // Varredura de segredos do GitHub: nem todo repositório tem; falha em silêncio.
        secrets = try? await client.secretScanningAlerts(repo.fullName)
    }

    private func enable() async {
        guard let client = model.client else { return }
        busy = true
        defer { busy = false }
        do {
            try await client.enableSecurityAlerts(repo.fullName)
            model.show("shield.lefthalf.filled", "Alertas de segurança ligados")
            alerts = nil
            await load()
        } catch {
            model.report(error)
        }
    }
}

// MARK: - Pessoas

/// Quem tem acesso ao repositório, convites pendentes e convidar alguém.
struct PeopleTab: View {
    @Environment(AppModel.self) private var model
    let repo: GHRepo
    @ViewState private var people: [GHCollaborator]?
    @ViewState private var invites: [GHInvitation] = []
    @ViewState private var login = ""
    @ViewState private var permission = "push"
    @ViewState private var removing: GHCollaborator?
    @ViewState private var failure: String?
    @ViewState private var busy = false

    private var isOwner: Bool { repo.owner.login == model.user?.login }

    static let permissions: [(value: String, title: String, detail: String)] = [
        ("pull", "Só ver", "Vê e baixa o projeto, abre tarefas."),
        ("triage", "Organizar", "Também organiza tarefas e pedidos."),
        ("push", "Mudar", "Também envia versões e junta pedidos."),
        ("maintain", "Manter", "Também cuida de ajustes do repositório."),
        ("admin", "Administrar", "Pode tudo, inclusive apagar.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.showExplanations {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    Text(repo.isPrivate
                         ? "Este repositório é privado: só você e as pessoas daqui veem o projeto. Convide alguém pelo nome de usuário do GitHub; a pessoa recebe um convite por e-mail."
                         : "Este repositório é público: qualquer pessoa vê, mas só quem está aqui pode mudar. Convide alguém pelo nome de usuário do GitHub.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    HelpTip(lessonID: "visibility")
                }
                .padding(12)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.corner))
            }

            if isOwner {
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Convidar alguém").font(.system(size: 13, weight: .semibold))
                        HStack(alignment: .bottom, spacing: 10) {
                            LabeledField(label: "Usuário do GitHub", text: $login, prompt: "ex.: maria-silva")
                            VStack(alignment: .leading, spacing: 6) {
                                Text("O que a pessoa pode fazer").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                Picker("Permissão", selection: $permission) {
                                    ForEach(Self.permissions, id: \.value) { Text($0.title).tag($0.value) }
                                }
                                .labelsHidden()
                                .frame(width: 160)
                            }
                            Button { Task { await invite() } } label: {
                                if busy { ProgressView().controlSize(.small) } else { Label("Convidar", systemImage: "person.badge.plus") }
                            }
                            .buttonStyle(ActionButtonStyle(tint: .blue, prominent: true))
                            .disabled(cleanLogin.isEmpty || busy)
                        }
                        Text(Self.permissions.first { $0.value == permission }?.detail ?? "")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }

            if let failure {
                EmptyState(symbol: "person.2.slash", title: "Não consegui ver as pessoas", message: failure)
            } else if let people {
                Text(Phrases.plural(people.count, "pessoa tem acesso", "pessoas têm acesso")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(people) { p in
                    HStack(spacing: 12) {
                        Avatar(url: p.avatarUrl, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.login).font(.system(size: 13, weight: .semibold))
                                if p.login == repo.owner.login { Pill(text: "Dono", tint: .blue) }
                                if p.login == model.user?.login { Pill(text: "Você", tint: .teal) }
                            }
                            Text(p.roleLabel).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isOwner && p.login != repo.owner.login {
                            Button { removing = p } label: { Image(systemName: "person.badge.minus") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Tirar o acesso de \(p.login)")
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                }
                if !invites.isEmpty {
                    Text("Convites esperando resposta").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
                    ForEach(invites) { inv in
                        HStack(spacing: 12) {
                            Avatar(url: inv.invitee?.avatarUrl, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inv.invitee?.login ?? "Convite").font(.system(size: 13, weight: .semibold))
                                Text("Convidado \(Phrases.relative(inv.createdAt))").font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isOwner {
                                Button("Cancelar convite") { Task { await cancel(inv) } }.buttonStyle(ActionButtonStyle(tint: .secondary))
                            }
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                LoadingRow(text: "Buscando quem tem acesso…")
            }
        }
        .task(id: repo.id) { await load() }
        .confirmationDialog("Tirar o acesso de \(removing?.login ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { p in
            Button("Tirar acesso", role: .destructive) { Task { await remove(p) } }
        } message: { _ in
            Text("A pessoa deixa de ver\(repo.isPrivate ? "" : " como colaboradora") e de mudar o repositório. Dá para convidar de novo depois.")
        }
    }

    private var cleanLogin: String {
        login.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            people = try await client.collaborators(repo.fullName)
            invites = isOwner ? ((try? await client.invitations(repo.fullName)) ?? []) : []
            failure = nil
        } catch GitHubError.forbidden {
            failure = "Só quem pode mudar este repositório vê a lista de pessoas."
        } catch {
            failure = error.localizedDescription
        }
    }

    private func invite() async {
        guard let client = model.client else { return }
        busy = true
        defer { busy = false }
        let name = cleanLogin
        do {
            try await client.addCollaborator(repo.fullName, login: name, permission: permission)
            model.show("person.badge.plus", "Convite enviado para \(name)")
            login = ""
            await load()
        } catch GitHubError.notFound {
            model.errorMessage = "Não achei ninguém com o usuário “\(name)” no GitHub. Confira como está escrito."
        } catch {
            model.report(error)
        }
    }

    private func remove(_ p: GHCollaborator) async {
        guard let client = model.client else { return }
        do {
            try await client.removeCollaborator(repo.fullName, login: p.login)
            model.show("person.badge.minus", "\(p.login) não tem mais acesso")
            await load()
        } catch { model.report(error) }
    }

    private func cancel(_ inv: GHInvitation) async {
        guard let client = model.client else { return }
        do {
            try await client.deleteInvitation(repo.fullName, id: inv.id)
            model.show("xmark.circle", "Convite cancelado")
            await load()
        } catch { model.report(error) }
    }
}
