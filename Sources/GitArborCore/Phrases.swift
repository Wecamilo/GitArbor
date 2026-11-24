import Foundation

/// Textos em português para coisas que o GitHub descreve em inglês.
public enum Phrases {
    public static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        if now.timeIntervalSince(date) < 60 { return "agora mesmo" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }

    public static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "pt_BR")))
    }

    public static func size(kilobytes: Int?) -> String {
        guard let kilobytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(kilobytes) * 1024, countStyle: .file)
    }

    public static func size(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Nome de repositório no padrão usado no GitHub: minúsculas, sem acento, palavras separadas
    /// por um hífen só. “Site - Loja Online” vira “site-loja-online”.
    public static func repoSlug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        var out = ""
        for ch in folded {
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "." { out.append(ch) }
            else if !out.hasSuffix("-") { out.append("-") }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }

    public static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }

    /// Por que o GitHub mandou a notificação.
    public static func notificationReason(_ reason: String) -> String {
        switch reason {
        case "assign": "Atribuído a você"
        case "author": "Você criou"
        case "comment": "Novo comentário"
        case "ci_activity": "Resultado de automação"
        case "invitation": "Convite"
        case "manual": "Você está acompanhando"
        case "mention": "Você foi mencionado"
        case "review_requested": "Pediram sua revisão"
        case "security_alert": "Alerta de segurança"
        case "state_change": "Mudou de situação"
        case "subscribed": "Você acompanha este repositório"
        case "team_mention": "Sua equipe foi mencionada"
        default: "Atualização"
        }
    }

    public static func notificationKind(_ type: String) -> String {
        switch type {
        case "Issue": "Tarefa (issue)"
        case "PullRequest": "Pedido de mudança (pull request)"
        case "Release": "Versão publicada"
        case "CheckSuite", "WorkflowRun": "Automação (Actions)"
        case "Commit": "Commit"
        case "Discussion": "Discussão"
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread": "Alerta de segurança"
        default: type
        }
    }

    /// Frase curta descrevendo um evento da atividade recente.
    public static func event(_ e: GHEvent) -> (symbol: String, text: String) {
        let repo = e.repo.name.split(separator: "/").last.map(String.init) ?? e.repo.name
        let p = e.payload
        switch e.type {
        case "PushEvent":
            let branch = p.ref?.replacingOccurrences(of: "refs/heads/", with: "") ?? "main"
            let n = p.size ?? p.commits?.count
            if let n, n > 0 {
                return ("arrow.up.circle.fill", "Enviou \(plural(n, "versão", "versões")) para \(repo) (\(branch))")
            }
            return ("arrow.up.circle.fill", "Enviou mudanças para \(repo) (\(branch))")
        case "CreateEvent":
            switch p.refType {
            case "repository": return ("plus.square.fill", "Criou o repositório \(repo)")
            case "branch": return ("arrow.triangle.branch", "Criou o ramo \(p.ref ?? "") em \(repo)")
            case "tag": return ("tag.fill", "Criou a etiqueta \(p.ref ?? "") em \(repo)")
            default: return ("plus.circle.fill", "Criou algo em \(repo)")
            }
        case "DeleteEvent":
            return ("trash.fill", "Apagou \(p.refType == "tag" ? "a etiqueta" : "o ramo") \(p.ref ?? "") em \(repo)")
        case "PullRequestEvent":
            let title = p.pullRequest?.title.map { "“\($0)”" } ?? "#\(p.pullRequest?.number ?? 0)"
            switch p.action {
            case "opened": return ("arrow.triangle.pull", "Abriu o pedido de mudança \(title) em \(repo)")
            case "closed": return ("arrow.triangle.merge", "Fechou o pedido de mudança \(title) em \(repo)")
            case "reopened": return ("arrow.triangle.pull", "Reabriu o pedido \(title) em \(repo)")
            default: return ("arrow.triangle.pull", "Atualizou o pedido \(title) em \(repo)")
            }
        case "IssuesEvent":
            let title = p.issue?.title.map { "“\($0)”" } ?? "#\(p.issue?.number ?? 0)"
            switch p.action {
            case "opened": return ("smallcircle.filled.circle", "Abriu a tarefa \(title) em \(repo)")
            case "closed": return ("checkmark.circle.fill", "Concluiu a tarefa \(title) em \(repo)")
            default: return ("smallcircle.filled.circle", "Atualizou a tarefa \(title) em \(repo)")
            }
        case "IssueCommentEvent":
            return ("text.bubble.fill", "Comentou em \(repo)")
        case "WatchEvent":
            return ("star.fill", "Deu estrela em \(repo)")
        case "ForkEvent":
            return ("tuningfork", "Fez uma cópia (fork) de \(repo)")
        case "ReleaseEvent":
            return ("tag.fill", "Publicou a versão \(p.release?.name ?? p.release?.tagName ?? "") de \(repo)")
        case "PublicEvent":
            return ("globe", "Tornou \(repo) público")
        case "MemberEvent":
            return ("person.badge.plus", "Adicionou alguém a \(repo)")
        default:
            return ("circle.fill", "Atividade em \(repo)")
        }
    }
}
